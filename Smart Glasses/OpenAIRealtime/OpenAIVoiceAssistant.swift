//
//  OpenAIVoiceAssistant.swift
//  Smart Glasses
//
//  Voice assistant using OpenAI Realtime API (WebSocket)
//  Speak or type to interact, with VAD for natural conversation
//  Automatic photo capture every 5 seconds for continuous vision context
//

import Foundation
import AVFoundation
import UIKit
import Combine

// MARK: - Assistant State

enum VoiceAssistantState: Equatable {
    case idle
    case recording
    case processing
    case speaking
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Voice Assistant Manager

@MainActor
class OpenAIVoiceAssistant: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = OpenAIVoiceAssistant()

    // MARK: - Published Properties

    @Published var state: VoiceAssistantState = .idle
    @Published var isRecording: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var lastResponse: String = ""
    @Published var errorMessage: String?

    /// Whether to include a photo with the next request
    @Published var includePhoto: Bool = false

    /// The captured photo for vision requests
    @Published var capturedPhoto: UIImage?

    /// Selected voice for TTS
    @Published var selectedVoice: OpenAIVoice = .alloy

    // MARK: - Configuration

    private let systemPrompt = """
    You are a helpful AI assistant integrated into smart glasses. You receive periodic visual context \
    descriptions from the user's glasses camera (marked with [Visual context from glasses camera: ...]). \
    These descriptions tell you what the user is currently looking at. You can also hear their voice. \
    Be conversational, helpful, and concise. Keep responses brief and natural, like a conversation with a friend. \
    Use the visual context to answer questions about what the user sees, point out interesting things, \
    potential hazards, or useful information. When referencing visual context, speak naturally as if you can see it.
    """

    // MARK: - Components

    private let realtimeClient = OpenAIRealtimeClient()
    private let visionClient = OpenAIVisionClient()
    private let apiKeyManager = OpenAIAPIKeyManager.shared

    // Audio recording (24kHz for OpenAI)
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioConverter: AVAudioConverter?
    private var audioBuffer: Data = Data()
    private let targetSampleRate: Double = 24000
    private let chunkInterval: TimeInterval = 0.1  // Send audio every 100ms

    // Audio playback - accumulate chunks for smooth playback
    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var accumulatedAudioData: Data = Data()
    private var isPlaybackEngineRunning: Bool = false
    private var pendingBufferCount: Int = 0
    private let playbackLock = NSLock()

    // Response transcript accumulator
    private var responseTranscript: String = ""

    // Pending text message (for when we need to connect first)
    private var pendingTextMessage: String?

    // Automatic photo capture timer
    private var photoTimer: Timer?
    private let photoCaptureInterval: TimeInterval = 5.0  // Send photo every 5 seconds

    // Fallback iOS TTS
    private let speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - Initialization

    private override init() {
        super.init()
        speechSynthesizer.delegate = self
        realtimeClient.delegate = self
        // Don't setup playback engine here - do it lazily when needed
    }

    /// Setup playback engine lazily when first needed
    private func ensurePlaybackEngineSetup() {
        guard playbackEngine == nil else { return }

        playbackEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = playbackEngine, let player = playerNode else { return }

        engine.attach(player)
        print("[VoiceAssistant] Playback engine created")
    }

    // MARK: - Public API

    /// Check if API key is configured
    var hasAPIKey: Bool {
        apiKeyManager.hasAPIKey
    }

    /// Start recording voice
    func startRecording() {
        guard state == .idle || state.isError else {
            print("[VoiceAssistant] Cannot start recording - state: \(state)")
            return
        }

        guard hasAPIKey else {
            state = .error("API key not configured")
            errorMessage = "Please add your OpenAI API key"
            return
        }

        // Stop any ongoing speech
        if isSpeaking {
            stopSpeaking()
        }

        // Reset state
        errorMessage = nil
        responseTranscript = ""

        // Connect to OpenAI if not connected
        if !realtimeClient.isConnected {
            connectAndStartSession()
        } else {
            beginAudioCapture()
        }
    }

    /// Stop recording and send to OpenAI (manual stop - VAD will handle this automatically)
    func stopRecordingAndSend() {
        guard state == .recording else {
            return
        }

        stopAudioCapture()
        state = .processing

        print("[VoiceAssistant] Recording stopped manually, processing...")

        // If photo is queued, send it first
        if includePhoto, let photo = capturedPhoto {
            sendPhotoToConversation(photo)
            clearPhoto()
        }

        // With VAD enabled, the server will auto-commit when speech stops
        // But we can also manually commit if user taps stop
        realtimeClient.commitAudioBuffer()
        realtimeClient.createResponse()
    }

    /// Called when VAD detects speech has stopped - server will auto-respond
    private func onSpeechStopped() {
        guard state == .recording else { return }

        // Send photo if queued (before server generates response)
        if includePhoto, let photo = capturedPhoto {
            sendPhotoToConversation(photo)
            clearPhoto()
        }

        state = .processing
        print("[VoiceAssistant] Speech stopped (VAD), waiting for response...")
        // Server will automatically commit and generate response
    }

    /// Toggle recording state
    func toggleRecording() {
        if isRecording {
            stopRecordingAndSend()
        } else {
            startRecording()
        }
    }

    /// Send a text message instead of voice
    func sendTextMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard hasAPIKey else {
            state = .error("API key not configured")
            errorMessage = "Please add your OpenAI API key"
            return
        }

        // Stop any ongoing speech or recording
        if isSpeaking {
            stopSpeaking()
        }
        if isRecording {
            stopAudioCapture()
        }

        // Reset state
        errorMessage = nil
        responseTranscript = ""
        state = .processing

        // If not connected, queue the message and connect
        if !realtimeClient.isConnected {
            pendingTextMessage = text
            connectForTextMessage()
        } else {
            // Already connected, send immediately
            sendTextAndRequestResponse(text)
        }
    }

    /// Connect specifically for sending a text message
    private func connectForTextMessage() {
        guard let apiKey = apiKeyManager.apiKey else {
            state = .error("API key not configured")
            errorMessage = "Please add your OpenAI API key"
            return
        }

        print("[VoiceAssistant] Connecting for text message...")
        realtimeClient.connect(apiKey: apiKey)
    }

    /// Send text to the conversation and request a response
    private func sendTextAndRequestResponse(_ text: String) {
        print("[VoiceAssistant] Sending text message: \(text.prefix(50))...")

        // Send the text as a conversation item
        realtimeClient.createTextItem(text)

        // Request a response
        realtimeClient.createResponse()
    }

    /// Capture photo for vision request
    func capturePhotoForVision(_ image: UIImage) {
        capturedPhoto = image
        includePhoto = true
        print("[VoiceAssistant] Photo captured for vision request")
    }

    /// Clear captured photo
    func clearPhoto() {
        capturedPhoto = nil
        includePhoto = false
    }

    /// Stop speaking
    func stopSpeaking() {
        // Stop audio player
        playerNode?.stop()
        playbackLock.lock()
        accumulatedAudioData = Data()
        pendingBufferCount = 0
        playbackLock.unlock()

        // Stop fallback iOS TTS
        speechSynthesizer.stopSpeaking(at: .immediate)

        // Cancel ongoing response
        if realtimeClient.isConnected && state == .speaking {
            realtimeClient.cancelResponse()
        }

        isSpeaking = false
        if state == .speaking {
            state = .idle
        }
    }

    /// Reset assistant state
    func reset() {
        stopSpeaking()
        stopPhotoTimer()  // Stop automatic photo capture
        if isRecording {
            stopAudioCapture()
        }

        // Disconnect WebSocket
        realtimeClient.disconnect()

        // Stop engines
        audioEngine?.stop()
        playbackEngine?.stop()
        isPlaybackEngineRunning = false

        state = .idle
        lastResponse = ""
        errorMessage = nil
        responseTranscript = ""
        pendingTextMessage = nil
        clearPhoto()
    }

    // MARK: - Private Methods - Connection

    private func connectAndStartSession() {
        guard let apiKey = apiKeyManager.apiKey else {
            state = .error("API key not configured")
            errorMessage = "Please add your OpenAI API key"
            return
        }

        state = .processing
        print("[VoiceAssistant] Connecting to OpenAI Realtime API...")
        realtimeClient.connect(apiKey: apiKey)
    }

    // MARK: - Private Methods - Audio Recording

    private func beginAudioCapture() {
        audioBuffer = Data()

        do {
            // Configure audio session - use options that don't interfere with video
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)

            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }

            inputNode = engine.inputNode
            guard let inputNode = inputNode else { return }

            // Get the input format
            let inputFormat = inputNode.outputFormat(forBus: 0)
            print("[VoiceAssistant] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

            // Create target format (24kHz, mono, Int16)
            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: true) else {
                throw NSError(domain: "VoiceAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create target format"])
            }

            // Create converter if sample rates differ
            if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
                // Need intermediate float format for conversion
                guard let floatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: true) else {
                    throw NSError(domain: "VoiceAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create float format"])
                }
                audioConverter = AVAudioConverter(from: inputFormat, to: floatFormat)
            }

            // Install tap on input node
            let bufferSize: AVAudioFrameCount = 4096
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, inputFormat: inputFormat)
            }

            try engine.start()

            state = .recording
            isRecording = true
            print("[VoiceAssistant] Recording started at \(inputFormat.sampleRate)Hz")

        } catch {
            print("[VoiceAssistant] Failed to start recording: \(error)")
            state = .error("Failed to start recording")
            errorMessage = error.localizedDescription
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        // Convert to 24kHz mono Int16
        let pcmData = convertToTargetFormat(buffer, inputFormat: inputFormat)

        // Append to buffer
        audioBuffer.append(pcmData)

        // Send chunks every ~100ms (2400 samples at 24kHz = 4800 bytes)
        let chunkSize = Int(targetSampleRate * chunkInterval) * 2  // 2 bytes per Int16
        if audioBuffer.count >= chunkSize {
            let chunk = audioBuffer.prefix(chunkSize)
            let base64Audio = chunk.base64EncodedString()

            Task { @MainActor in
                self.realtimeClient.appendAudioBuffer(base64Audio)
            }

            audioBuffer.removeFirst(chunkSize)
        }
    }

    private func convertToTargetFormat(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> Data {
        let frameCount = buffer.frameLength

        // If input is already at target format, just extract the data
        if inputFormat.sampleRate == targetSampleRate && inputFormat.channelCount == 1 {
            if let floatData = buffer.floatChannelData {
                // Convert float to Int16
                var int16Data = Data(count: Int(frameCount) * 2)
                int16Data.withUnsafeMutableBytes { rawBuffer in
                    let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                    for i in 0..<Int(frameCount) {
                        let sample = max(-1.0, min(1.0, floatData[0][i]))
                        int16Buffer[i] = Int16(sample * 32767.0)
                    }
                }
                return int16Data
            }
        }

        // Need to resample - use simple downsampling
        let ratio = inputFormat.sampleRate / targetSampleRate
        let outputFrameCount = Int(Double(frameCount) / ratio)

        var int16Data = Data(count: outputFrameCount * 2)

        if let floatData = buffer.floatChannelData {
            int16Data.withUnsafeMutableBytes { rawBuffer in
                let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                for i in 0..<outputFrameCount {
                    let sourceIndex = Int(Double(i) * ratio)
                    if sourceIndex < frameCount {
                        // Average channels if stereo
                        var sample: Float = 0
                        for ch in 0..<Int(inputFormat.channelCount) {
                            sample += floatData[ch][sourceIndex]
                        }
                        sample /= Float(inputFormat.channelCount)
                        sample = max(-1.0, min(1.0, sample))
                        int16Buffer[i] = Int16(sample * 32767.0)
                    }
                }
            }
        } else if let int16Data = buffer.int16ChannelData {
            // Input is already Int16
            var outputData = Data(count: outputFrameCount * 2)
            outputData.withUnsafeMutableBytes { rawBuffer in
                let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                for i in 0..<outputFrameCount {
                    let sourceIndex = Int(Double(i) * ratio)
                    if sourceIndex < frameCount {
                        int16Buffer[i] = int16Data[0][sourceIndex]
                    }
                }
            }
            return outputData
        }

        return int16Data
    }

    private func stopAudioCapture() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        isRecording = false

        // Send any remaining audio
        if !audioBuffer.isEmpty {
            let base64Audio = audioBuffer.base64EncodedString()
            realtimeClient.appendAudioBuffer(base64Audio)
            audioBuffer = Data()
        }

        print("[VoiceAssistant] Recording stopped")
    }

    // MARK: - Private Methods - Photo

    /// Analyze image with Vision API and send description to Realtime conversation
    /// Note: Realtime API doesn't support images directly, so we use GPT-4o Vision
    private func sendPhotoToConversation(_ image: UIImage) {
        Task {
            do {
                print("[VoiceAssistant] Analyzing image with Vision API...")
                let description = try await visionClient.analyzeImage(image)
                print("[VoiceAssistant] Vision analysis complete: \(description.prefix(100))...")

                // Send the description as a system context message
                let contextMessage = "[Visual context from glasses camera: \(description)]"
                realtimeClient.createTextItem(contextMessage)
            } catch {
                print("[VoiceAssistant] Vision analysis failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Automatic Photo Capture

    /// Start automatic photo capture timer
    private func startPhotoTimer() {
        stopPhotoTimer()  // Clear any existing timer

        // Send initial photo immediately
        captureAndSendCurrentFrame()

        // Schedule recurring captures
        photoTimer = Timer.scheduledTimer(withTimeInterval: photoCaptureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureAndSendCurrentFrame()
            }
        }
        print("[VoiceAssistant] Photo timer started (every \(Int(photoCaptureInterval))s)")
    }

    /// Stop automatic photo capture timer
    private func stopPhotoTimer() {
        photoTimer?.invalidate()
        photoTimer = nil
    }

    /// Capture the current frame from WearablesManager and send it
    private func captureAndSendCurrentFrame() {
        // Access the shared WearablesManager to get the latest frame
        // Note: We import this lazily to avoid circular dependency issues
        guard realtimeClient.isConnected else { return }

        // Get the latest frame from the camera stream
        let frame = WearablesManager.shared.latestFrameImage
        guard let image = frame else {
            print("[VoiceAssistant] No frame available for auto-capture")
            return
        }

        // Resize image to reduce bandwidth (max 512px on longest side)
        let resizedImage = resizeImageForAPI(image, maxDimension: 512)
        sendPhotoToConversation(resizedImage)
    }

    /// Resize image to reduce API bandwidth
    private func resizeImageForAPI(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)

        // Don't upscale
        if ratio >= 1.0 { return image }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Private Methods - Audio Playback

    private func playAudioChunk(_ base64Audio: String) {
        guard let audioData = Data(base64Encoded: base64Audio) else {
            print("[VoiceAssistant] Failed to decode audio chunk")
            return
        }

        // Accumulate audio data
        playbackLock.lock()
        accumulatedAudioData.append(audioData)
        let currentDataSize = accumulatedAudioData.count
        playbackLock.unlock()

        // Start playback engine if not running
        if !isPlaybackEngineRunning {
            startPlaybackEngine()
        }

        // Schedule audio when we have enough data (at least 100ms = 4800 bytes at 24kHz)
        // Or schedule smaller chunks if engine is already running
        let minBufferSize = isPlaybackEngineRunning ? 2400 : 4800  // 50ms or 100ms
        if currentDataSize >= minBufferSize {
            scheduleAccumulatedAudio()
        }
    }

    private func startPlaybackEngine() {
        // Ensure engine is created
        ensurePlaybackEngineSetup()

        guard let engine = playbackEngine, let player = playerNode else {
            print("[VoiceAssistant] Playback engine not available")
            return
        }

        do {
            // Configure audio session - use options that don't interfere with video
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)

            // Create format and connect
            guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true) else {
                return
            }

            if !engine.isRunning {
                engine.connect(player, to: engine.mainMixerNode, format: format)
                try engine.start()
                player.play()
                isPlaybackEngineRunning = true
                print("[VoiceAssistant] Playback engine started")
            }

        } catch {
            print("[VoiceAssistant] Failed to start playback engine: \(error)")
        }
    }

    private func scheduleAccumulatedAudio() {
        playbackLock.lock()
        guard !accumulatedAudioData.isEmpty else {
            playbackLock.unlock()
            return
        }
        let dataToPlay = accumulatedAudioData
        accumulatedAudioData = Data()
        pendingBufferCount += 1
        playbackLock.unlock()

        guard let player = playerNode else { return }

        // Create format
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true) else {
            return
        }

        // Calculate frame count
        let frameCount = UInt32(dataToPlay.count) / 2

        // Create audio buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        // Copy data to buffer
        dataToPlay.withUnsafeBytes { rawBytes in
            let samples = rawBytes.bindMemory(to: Int16.self)
            if let channelData = buffer.int16ChannelData {
                for i in 0..<Int(frameCount) {
                    channelData[0][i] = samples[i]
                }
            }
        }

        // Schedule buffer - use completion to track when buffers finish
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                self?.onBufferCompleted()
            }
        }
    }

    private func onBufferCompleted() {
        playbackLock.lock()
        pendingBufferCount -= 1
        let remaining = pendingBufferCount
        let hasMoreData = !accumulatedAudioData.isEmpty
        playbackLock.unlock()

        // If there's more accumulated data, schedule it
        if hasMoreData {
            scheduleAccumulatedAudio()
        }

        // If no more buffers pending and no more data, we're done
        if remaining <= 0 && !hasMoreData && state == .speaking {
            // Small delay to ensure we're really done
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                self.playbackLock.lock()
                let stillEmpty = self.pendingBufferCount <= 0 && self.accumulatedAudioData.isEmpty
                self.playbackLock.unlock()

                if stillEmpty && self.state == .speaking {
                    self.isSpeaking = false
                    self.state = .idle
                    print("[VoiceAssistant] Playback complete")
                }
            }
        }
    }

    /// Called when response.done is received - flush any remaining audio
    private func flushRemainingAudio() {
        playbackLock.lock()
        let hasData = !accumulatedAudioData.isEmpty
        playbackLock.unlock()

        if hasData {
            scheduleAccumulatedAudio()
        }
    }

    /// Fallback to iOS TTS if needed
    private func speakWithFallback(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        speechSynthesizer.speak(utterance)
    }
}

// MARK: - OpenAI Realtime Client Delegate

extension OpenAIVoiceAssistant: OpenAIRealtimeClientDelegate {

    nonisolated func clientDidConnect() {
        Task { @MainActor in
            print("[VoiceAssistant] Connected to OpenAI")
            // Session configuration will be sent after session.created
        }
    }

    nonisolated func clientDidDisconnect(error: Error?) {
        Task { @MainActor in
            self.stopPhotoTimer()  // Stop automatic photo capture
            if let error = error {
                print("[VoiceAssistant] Disconnected with error: \(error)")
                self.state = .error("Connection lost")
                self.errorMessage = error.localizedDescription
            } else {
                print("[VoiceAssistant] Disconnected normally")
                if self.state != .idle {
                    self.state = .idle
                }
            }
            self.isRecording = false
            self.isSpeaking = false
        }
    }

    nonisolated func clientDidReceiveSessionCreated() {
        Task { @MainActor in
            print("[VoiceAssistant] Session created, configuring...")
            self.realtimeClient.sendSessionUpdate(
                instructions: self.systemPrompt,
                voice: self.selectedVoice
            )
        }
    }

    nonisolated func clientDidReceiveSessionUpdated() {
        Task { @MainActor in
            print("[VoiceAssistant] Session configured...")
            self.startPhotoTimer()  // Start automatic photo capture

            // Check if there's a pending text message to send
            if let pendingText = self.pendingTextMessage {
                self.pendingTextMessage = nil
                self.sendTextAndRequestResponse(pendingText)
            } else {
                // Normal voice flow - start recording
                self.beginAudioCapture()
            }
        }
    }

    nonisolated func clientDidReceiveSpeechStarted() {
        Task { @MainActor in
            print("[VoiceAssistant] Speech detected by VAD")
            // Could add visual feedback here if desired
        }
    }

    nonisolated func clientDidReceiveSpeechStopped() {
        Task { @MainActor in
            print("[VoiceAssistant] Speech stopped by VAD, processing...")
            self.onSpeechStopped()
        }
    }

    nonisolated func clientDidReceiveAudioDelta(_ base64Audio: String) {
        Task { @MainActor in
            if self.state != .speaking {
                self.state = .speaking
                self.isSpeaking = true
            }
            self.playAudioChunk(base64Audio)
        }
    }

    nonisolated func clientDidReceiveTranscript(_ text: String) {
        Task { @MainActor in
            self.responseTranscript += text
            self.lastResponse = self.responseTranscript
        }
    }

    nonisolated func clientDidReceiveResponseDone() {
        Task { @MainActor in
            print("[VoiceAssistant] Response complete, flushing remaining audio")
            // Flush any remaining accumulated audio
            self.flushRemainingAudio()
            // State transition will happen in onBufferCompleted when all audio finishes
        }
    }

    nonisolated func clientDidReceiveError(_ error: ErrorInfo) {
        Task { @MainActor in
            let message = error.message ?? "Unknown error"
            print("[VoiceAssistant] Error: \(message)")
            self.state = .error(message)
            self.errorMessage = message
            self.isRecording = false
            self.isSpeaking = false
        }
    }
}

// MARK: - Speech Synthesizer Delegate

extension OpenAIVoiceAssistant: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.state = .idle
            print("[VoiceAssistant] Finished speaking (fallback TTS)")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            if self.state == .speaking {
                self.state = .idle
            }
        }
    }
}

// MARK: - Status Description

extension OpenAIVoiceAssistant {

    var statusDescription: String {
        switch state {
        case .idle:
            return "Ready"
        case .recording:
            return "Listening..."
        case .processing:
            return "Thinking..."
        case .speaking:
            return "Speaking..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var statusColor: String {
        switch state {
        case .idle: return "gray"
        case .recording: return "red"
        case .processing: return "yellow"
        case .speaking: return "purple"
        case .error: return "red"
        }
    }
}
