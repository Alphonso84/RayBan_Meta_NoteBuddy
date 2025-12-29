//
//  GeminiLiveManager.swift
//  Smart Glasses
//
//  Main coordinator for Gemini Live API integration
//  Manages WebSocket connection, audio I/O, and video frame streaming
//

import Foundation
import AVFoundation
import Combine

@MainActor
class GeminiLiveManager: ObservableObject {

    // MARK: - Singleton

    static let shared = GeminiLiveManager()

    // MARK: - Published Properties

    @Published var state: GeminiSessionState = .disconnected
    @Published var isListening: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var conversationActive: Bool = false
    @Published var errorMessage: String?
    @Published var lastTranscript: String = ""

    /// Whether the user is currently recording voice (push-to-talk mode)
    @Published var isRecordingVoice: Bool = false

    /// Accumulated audio data during push-to-talk recording
    private var recordedAudioData: [Data] = []
    private let audioDataLock = NSLock()

    // MARK: - Configuration

    // Native audio model from docs: supports audio output via Live API
    private let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"
    private let voiceName = "Puck"  // Available: Puck, Charon, Kore, Fenrir, Aoede

    private let systemPrompt = """
    You are an AI assistant integrated into smart glasses. You receive video updates every \
    5 seconds showing what the user sees through their glasses camera, and you can hear \
    what they say in real-time. When you receive new video frames, briefly describe any \
    significant changes or interesting things you notice. Be conversational but brief since \
    your responses are spoken aloud. Focus on being useful for everyday tasks like reading \
    text, identifying objects, navigating, or answering questions about the environment. \
    When the user first connects, greet them briefly and let them know you'll be watching \
    and can answer questions about what they're seeing.
    """

    // MARK: - Components

    private let webSocketClient = GeminiWebSocketClient()
    private let frameEncoder = GeminiFrameEncoder(preset: .balanced)
    private let microphoneCapture = GeminiMicrophoneCapture()
    private let audioPlayer = GeminiAudioPlayer()
    private let apiKeyManager = GeminiAPIKeyManager.shared

    // MARK: - Private Properties

    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var reconnectTask: Task<Void, Never>?

    private var isStreamingFrames = false
    private var pendingVideoFrame: String?

    // MARK: - Initialization

    private init() {
        setupDelegates()
        setupFrameBufferCallback()
    }

    private func setupDelegates() {
        webSocketClient.delegate = self
        microphoneCapture.delegate = self
    }

    /// Setup callback for when buffered frames are ready to send
    private func setupFrameBufferCallback() {
        frameEncoder.onBufferReady = { [weak self] frames in
            Task { @MainActor in
                self?.sendBufferedFrames(frames)
            }
        }
    }

    /// Send accumulated video frames as a chunk to Gemini
    private func sendBufferedFrames(_ frames: [String]) {
        guard state == .ready || state == .streaming || state == .responding else { return }
        guard !frames.isEmpty else { return }

        print("[GeminiLive] Sending \(frames.count) buffered frames to Gemini")

        // Send frames as a batch - we'll send the most recent frames
        // For Gemini, sending multiple frames gives temporal context
        for (index, frame) in frames.enumerated() {
            // Add small delay between frames to avoid overwhelming the connection
            // But for batch analysis, we send them all quickly
            let input = GeminiRealtimeInput.video(data: frame)
            let message = GeminiRealtimeInputMessage(realtimeInput: input)
            webSocketClient.send(realtimeInput: message)

            // Log first and last frame of batch
            if index == 0 {
                print("[GeminiLive] Sent first frame of batch")
            } else if index == frames.count - 1 {
                print("[GeminiLive] Sent last frame of batch (\(frames.count) total)")
            }
        }

        if state == .ready {
            state = .streaming
        }
    }

    // MARK: - Public API

    /// Check if API key is configured
    var hasAPIKey: Bool {
        apiKeyManager.hasAPIKey
    }

    /// Start a new Gemini Live session
    func startSession() {
        guard state == .disconnected || state.isError else {
            print("[GeminiLive] Cannot start - already in state: \(state)")
            return
        }

        guard let apiKey = apiKeyManager.apiKey, !apiKey.isEmpty else {
            state = .error(.invalidAPIKey)
            errorMessage = "Gemini API key not configured. Please add your API key in settings."
            return
        }

        state = .connecting
        errorMessage = nil
        reconnectAttempts = 0
        frameEncoder.reset()

        webSocketClient.connect(apiKey: apiKey)
        print("[GeminiLive] Starting session...")
    }

    /// End the current session
    func endSession() {
        print("[GeminiLive] Ending session...")

        reconnectTask?.cancel()
        reconnectTask = nil

        // Ensure buffer timer is stopped
        frameEncoder.stopBufferTimer()
        frameEncoder.clearBuffer()

        stopStreaming()
        webSocketClient.disconnect()

        state = .disconnected
        conversationActive = false
        isListening = false
        isSpeaking = false
        errorMessage = nil
    }

    /// Process a video frame from the glasses
    /// In buffered mode, frames are accumulated and sent every 5 seconds
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isStreamingFrames else { return }
        guard state == .ready || state == .streaming || state == .responding else { return }

        if frameEncoder.isBufferedMode {
            // Buffered mode: accumulate frames and send every 5 seconds
            frameEncoder.bufferFrame(sampleBuffer)
        } else {
            // Real-time mode: send immediately (legacy behavior)
            guard let base64Frame = frameEncoder.encode(sampleBuffer) else {
                return  // Frame skipped due to rate limiting
            }

            let input = GeminiRealtimeInput.video(data: base64Frame)
            let message = GeminiRealtimeInputMessage(realtimeInput: input)
            webSocketClient.send(realtimeInput: message)

            if state == .ready {
                state = .streaming
            }
        }
    }

    /// Start streaming video (audio is push-to-talk only)
    func startStreaming() {
        guard state == .ready || state == .streaming else {
            print("[GeminiLive] Cannot start streaming - not ready (state: \(state))")
            return
        }

        do {
            // Configure audio session for both recording and playback
            let session = AVAudioSession.sharedInstance()

            // Only reconfigure if not already in playAndRecord mode
            if session.category != .playAndRecord {
                // Deactivate first to avoid conflicts
                try? session.setActive(false, options: .notifyOthersOnDeactivation)

                try session.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
                )
            }

            try session.setActive(true)

            print("[GeminiLive] Audio session configured: \(session.category.rawValue)")
            print("[GeminiLive] Audio route: \(session.currentRoute.outputs.map { $0.portName })")

            // NOTE: Microphone is NOT started here - it's push-to-talk only
            // User must press the speak button to record voice

            // Start audio player for Gemini's responses
            do {
                try audioPlayer.start()
                print("[GeminiLive] Audio player started")
            } catch {
                print("[GeminiLive] Audio player failed (will retry): \(error)")
                // Don't fail completely - we can still send video
            }

            isStreamingFrames = true
            isListening = false  // Not listening until user presses speak button
            conversationActive = true
            frameEncoder.reset()

            // Start buffer timer for 5-second video chunks
            if frameEncoder.isBufferedMode {
                frameEncoder.startBufferTimer()
                print("[GeminiLive] Streaming started with 5-second video chunks (push-to-talk audio)")
            } else {
                print("[GeminiLive] Streaming started in real-time mode (push-to-talk audio)")
            }
        } catch {
            print("[GeminiLive] Failed to start streaming: \(error)")
            errorMessage = "Failed to start audio: \(error.localizedDescription)"
            state = .error(.microphoneError(error.localizedDescription))
        }
    }

    /// Stop streaming (pause, not disconnect)
    func stopStreaming() {
        // Stop any ongoing voice recording
        if isRecordingVoice {
            isRecordingVoice = false
            audioDataLock.lock()
            recordedAudioData.removeAll()
            audioDataLock.unlock()
        }

        microphoneCapture.stopCapturing()
        audioPlayer.stop()

        // Stop buffer timer and clear any pending frames
        frameEncoder.stopBufferTimer()
        frameEncoder.clearBuffer()

        isStreamingFrames = false
        isListening = false

        if state == .streaming || state == .responding {
            state = .ready
        }

        print("[GeminiLive] Streaming stopped")
    }

    /// Interrupt Gemini's response (barge-in when user speaks)
    func interruptResponse() {
        audioPlayer.interrupt()
        isSpeaking = false
    }

    // MARK: - Push-to-Talk Methods

    /// Start recording voice (push-to-talk)
    func startVoiceRecording() {
        guard state == .ready || state == .streaming || state == .responding else {
            print("[GeminiLive] Cannot start voice recording - not ready (state: \(state))")
            return
        }

        // Interrupt any current Gemini response
        if isSpeaking {
            interruptResponse()
        }

        // Clear previous recording
        audioDataLock.lock()
        recordedAudioData.removeAll()
        audioDataLock.unlock()

        isRecordingVoice = true
        isListening = true

        // Start microphone if not already running
        do {
            if !microphoneCapture.isCapturing {
                // Configure audio session
                let session = AVAudioSession.sharedInstance()
                if session.category != .playAndRecord {
                    try? session.setActive(false, options: .notifyOthersOnDeactivation)
                    try session.setCategory(
                        .playAndRecord,
                        mode: .voiceChat,
                        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
                    )
                }
                try session.setActive(true)
                try microphoneCapture.startCapturing()
            }
            print("[GeminiLive] Voice recording started")
        } catch {
            print("[GeminiLive] Failed to start voice recording: \(error)")
            isRecordingVoice = false
            isListening = false
        }
    }

    /// Stop recording voice and send to Gemini
    func stopVoiceRecording() {
        guard isRecordingVoice else { return }

        isRecordingVoice = false
        isListening = false

        // Stop microphone
        microphoneCapture.stopCapturing()

        // Send accumulated audio
        audioDataLock.lock()
        let allAudioData = recordedAudioData
        recordedAudioData.removeAll()
        audioDataLock.unlock()

        if !allAudioData.isEmpty {
            // Combine all audio chunks
            var combinedData = Data()
            for chunk in allAudioData {
                combinedData.append(chunk)
            }

            print("[GeminiLive] Sending \(combinedData.count) bytes of recorded audio")

            // Send the audio to Gemini
            let base64Audio = combinedData.base64EncodedString()
            let input = GeminiRealtimeInput.audio(data: base64Audio)
            let message = GeminiRealtimeInputMessage(realtimeInput: input)
            webSocketClient.send(realtimeInput: message)
        } else {
            print("[GeminiLive] No audio recorded")
        }
    }

    /// Toggle voice recording (for button press)
    func toggleVoiceRecording() {
        if isRecordingVoice {
            stopVoiceRecording()
        } else {
            startVoiceRecording()
        }
    }

    // MARK: - Private Methods

    private func sendSetupMessage() {
        let voiceConfig = GeminiVoiceConfig(
            prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig(voiceName: voiceName)
        )
        let speechConfig = GeminiSpeechConfig(voiceConfig: voiceConfig)
        let generationConfig = GeminiGenerationConfig(
            responseModalities: ["AUDIO"],
            speechConfig: speechConfig
        )
        let systemInstruction = GeminiSystemInstruction(
            parts: [GeminiTextPart(text: systemPrompt)]
        )

        let setup = GeminiSetupContent(
            model: model,
            generationConfig: generationConfig,
            systemInstruction: systemInstruction
        )

        let message = GeminiSetupMessage(setup: setup)
        webSocketClient.send(setup: message)

        state = .configuring
        print("[GeminiLive] Setup message sent")
    }

    private func handleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            state = .error(.connectionFailed("Max reconnection attempts reached"))
            errorMessage = "Connection failed after \(maxReconnectAttempts) attempts"
            return
        }

        reconnectAttempts += 1
        state = .reconnecting(attempt: reconnectAttempts)
        print("[GeminiLive] Reconnecting (attempt \(reconnectAttempts)/\(maxReconnectAttempts))...")

        reconnectTask = Task {
            // Exponential backoff: 2, 4, 6 seconds
            let delay = UInt64(2 * reconnectAttempts) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delay)

            if !Task.isCancelled {
                if let apiKey = self.apiKeyManager.apiKey {
                    self.webSocketClient.connect(apiKey: apiKey)
                }
            }
        }
    }
}

// MARK: - WebSocket Delegate

extension GeminiLiveManager: GeminiWebSocketDelegate {

    nonisolated func webSocketDidConnect() {
        Task { @MainActor in
            self.state = .connected
            self.sendSetupMessage()
        }
    }

    nonisolated func webSocketDidDisconnect(error: Error?) {
        Task { @MainActor in
            let wasActive = self.conversationActive

            self.isListening = false
            self.isSpeaking = false

            if wasActive && self.state != .disconnected {
                // Unexpected disconnect - try to reconnect
                print("[GeminiLive] Unexpected disconnect, attempting reconnect...")
                self.handleReconnect()
            } else {
                self.state = .disconnected
                self.conversationActive = false
            }
        }
    }

    nonisolated func webSocketDidReceive(message: GeminiServerMessage) {
        Task { @MainActor in
            // Handle setup complete
            if message.setupComplete != nil {
                self.state = .ready
                self.reconnectAttempts = 0
                print("[GeminiLive] Setup complete, ready for streaming")

                // Auto-start streaming
                self.startStreaming()
            }

            // Handle model turn (Gemini is speaking)
            if let modelTurn = message.serverContent?.modelTurn {
                if !(modelTurn.parts?.isEmpty ?? true) {
                    self.isSpeaking = true
                    if self.state == .streaming {
                        self.state = .responding
                    }
                }
            }

            // Handle transcription
            if let inputTranscript = message.serverContent?.inputTranscription?.text {
                self.lastTranscript = inputTranscript
            }

            // Handle turn complete
            if message.serverContent?.turnComplete == true {
                self.isSpeaking = false
                if self.isStreamingFrames {
                    self.state = .streaming
                }
            }

            // Handle generation complete
            if message.serverContent?.generationComplete == true {
                self.isSpeaking = false
            }

            // Handle interruption
            if message.serverContent?.interrupted == true {
                self.isSpeaking = false
                self.audioPlayer.interrupt()
            }
        }
    }

    nonisolated func webSocketDidReceive(audioData: Data) {
        Task { @MainActor in
            print("[GeminiLive] Received audio data: \(audioData.count) bytes, player isPlaying: \(self.audioPlayer.isPlaying)")
            self.audioPlayer.enqueue(audioData: audioData)
        }
    }
}

// MARK: - Microphone Delegate

extension GeminiLiveManager: GeminiMicrophoneCaptureDelegate {

    nonisolated func microphoneDidCapture(audioData: Data) {
        Task { @MainActor in
            // In push-to-talk mode, accumulate audio instead of sending immediately
            if self.isRecordingVoice {
                self.audioDataLock.lock()
                self.recordedAudioData.append(audioData)
                self.audioDataLock.unlock()
                return
            }

            // Legacy continuous mode (not used in push-to-talk)
            guard self.state == .streaming || self.state == .responding else { return }

            // Check audio level for barge-in (only interrupt on loud speech)
            let audioLevel = self.calculateAudioLevel(audioData)

            // Interrupt if Gemini is speaking AND user is speaking loudly (barge-in)
            if self.isSpeaking && audioLevel > 0.05 {  // Threshold to detect actual speech
                print("[GeminiLive] Barge-in detected (level: \(audioLevel))")
                self.interruptResponse()
            }

            // Send audio to Gemini (only in continuous mode, not push-to-talk)
            let base64Audio = audioData.base64EncodedString()
            let input = GeminiRealtimeInput.audio(data: base64Audio)
            let message = GeminiRealtimeInputMessage(realtimeInput: input)

            self.webSocketClient.send(realtimeInput: message)
        }
    }

    nonisolated func microphoneDidFail(error: Error) {
        Task { @MainActor in
            self.errorMessage = "Microphone error: \(error.localizedDescription)"
            self.isRecordingVoice = false
            self.isListening = false
            print("[GeminiLive] Microphone error: \(error)")
        }
    }

    /// Calculate RMS audio level from PCM data (0.0 to 1.0)
    private func calculateAudioLevel(_ data: Data) -> Float {
        guard data.count >= 2 else { return 0 }

        var sum: Float = 0
        let sampleCount = data.count / 2  // 16-bit samples

        data.withUnsafeBytes { rawBytes in
            let samples = rawBytes.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Float(samples[i]) / Float(Int16.max)
                sum += sample * sample
            }
        }

        let rms = sqrt(sum / Float(sampleCount))
        return rms
    }
}

// MARK: - Debug Helpers

extension GeminiLiveManager {

    var statusDescription: String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .configuring: return "Setting up..."
        case .ready: return "Ready"
        case .streaming: return "AI Active"
        case .responding: return "Responding"
        case .error(let error): return "Error: \(error)"
        case .reconnecting(let attempt): return "Reconnecting (\(attempt)/\(maxReconnectAttempts))"
        }
    }

    var encodingStatistics: String {
        let stats = frameEncoder.statistics
        return "Frames: \(stats.encoded) sent, \(stats.skipped) skipped (\(Int(stats.ratio * 100))%)"
    }
}
