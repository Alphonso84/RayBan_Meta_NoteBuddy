//
//  GeminiLiveService.swift
//  Smart Glasses
//
//  WebSocket-based Gemini Live API service for real-time voice assistant
//  Push-to-talk audio with on-demand video context from ring buffer
//

import Foundation
import AVFoundation
import Combine

// MARK: - Service State

enum GeminiLiveServiceState: Equatable {
    case disconnected
    case connecting
    case connected           // WebSocket open, awaiting setup complete
    case ready               // Setup complete, ready for input
    case recording           // User is recording voice
    case processing          // Sent input, waiting for response
    case responding          // Receiving streamed audio
    case error(GeminiLiveServiceError)

    var isActive: Bool {
        switch self {
        case .ready, .recording, .processing, .responding:
            return true
        default:
            return false
        }
    }

    var canRecord: Bool {
        self == .ready || self == .responding
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

enum GeminiLiveServiceError: Error, Equatable {
    case connectionFailed(String)
    case sessionExpired
    case invalidAPIKey
    case audioError(String)
    case networkError(String)
    case setupFailed(String)
}

// MARK: - Available Voices

enum GeminiLiveVoice: String, CaseIterable {
    case puck = "Puck"
    case charon = "Charon"
    case kore = "Kore"
    case fenrir = "Fenrir"
    case aoede = "Aoede"
    case leda = "Leda"
    case orus = "Orus"
    case zephyr = "Zephyr"
}

// MARK: - GeminiLiveService

@MainActor
class GeminiLiveService: ObservableObject {

    // MARK: - Singleton

    static let shared = GeminiLiveService()

    // MARK: - Published State

    @Published var state: GeminiLiveServiceState = .disconnected
    @Published var isRecording: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var lastTranscript: String = ""
    @Published var lastResponse: String = ""
    @Published var errorMessage: String?

    /// Selected voice for Gemini responses
    @Published var selectedVoice: GeminiLiveVoice = .puck

    // MARK: - Configuration

    // Gemini Live API model - gemini-2.0-flash-exp supports bidiGenerateContent
    private let model = "models/gemini-2.0-flash-exp"
    private let sessionTimeout: TimeInterval = 14 * 60  // Refresh before 15-minute limit

    private let systemPrompt = """
    You are a helpful AI assistant integrated into smart glasses. You can see what the user sees \
    through their camera and hear what they say. Be conversational but concise since your responses \
    are spoken aloud. Help with everyday tasks like reading text, identifying objects, answering \
    questions about the environment, or general knowledge questions. When you receive images, \
    describe what's relevant to the user's question. If no question was asked with images, briefly \
    note anything interesting or useful you see.
    """

    // MARK: - Components

    private let webSocketClient = GeminiWebSocketClient()
    private let microphoneCapture = GeminiMicrophoneCapture()
    private let audioPlayer = GeminiAudioPlayer()
    private let frameEncoder = GeminiFrameEncoder(preset: .balanced)
    private let apiKeyManager = GeminiAPIKeyManager.shared

    // MARK: - Session Management

    private var sessionStartTime: Date?
    private var sessionTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Audio Accumulator

    private var recordedAudioChunks: [Data] = []
    private let audioLock = NSLock()

    // MARK: - Silence Detection

    /// Threshold for detecting speech (0.0 - 1.0)
    private let speechThreshold: Float = 0.02

    /// Duration of silence before auto-sending (seconds)
    private let silenceDuration: TimeInterval = 1.5

    /// Time when silence was first detected
    private var silenceStartTime: Date?

    /// Whether we've detected speech in this recording session
    private var hasDetectedSpeech: Bool = false

    /// Timer for checking silence
    private var silenceCheckTimer: Timer?

    /// Published audio level for UI visualization
    @Published var currentAudioLevel: Float = 0

    // MARK: - Initialization

    private init() {
        setupDelegates()
        configureFrameEncoder()
    }

    private func setupDelegates() {
        webSocketClient.delegate = self
        microphoneCapture.delegate = self
    }

    private func configureFrameEncoder() {
        // Configure for ring buffer mode (keep last 6 frames for context)
        frameEncoder.ringBufferCapacity = 6
    }

    // MARK: - Public API

    /// Check if API key is configured
    var hasAPIKey: Bool {
        apiKeyManager.hasAPIKey
    }

    /// Start a new Live API session
    func startSession() {
        guard state == .disconnected || state.isError else {
            print("[GeminiLiveService] Cannot start - already in state: \(state)")
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
        frameEncoder.clearRingBuffer()

        webSocketClient.connect(apiKey: apiKey)
        print("[GeminiLiveService] Starting session...")
    }

    /// End the current session
    func endSession() {
        print("[GeminiLiveService] Ending session...")

        reconnectTask?.cancel()
        reconnectTask = nil
        stopSessionTimer()
        stopSilenceDetection()

        // Stop audio components
        stopRecordingInternal()
        audioPlayer.stop()

        // Clear frame buffer
        frameEncoder.clearRingBuffer()

        // Clear audio buffer
        audioLock.lock()
        recordedAudioChunks.removeAll()
        audioLock.unlock()

        // Disconnect WebSocket
        webSocketClient.disconnect()

        // Reset state
        state = .disconnected
        isRecording = false
        isSpeaking = false
        currentAudioLevel = 0
        errorMessage = nil
    }

    /// Reset service (e.g., when leaving AI assistant mode)
    func reset() {
        endSession()
        lastTranscript = ""
        lastResponse = ""
    }

    // MARK: - Video Frame Buffering

    /// Buffer a video frame for context (called by WearablesManager)
    func bufferVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard state.isActive else { return }
        frameEncoder.addToRingBuffer(sampleBuffer)
    }

    // MARK: - Recording with Auto-Send on Silence

    /// Start recording voice (auto-sends when silence detected)
    func startRecording() {
        guard state.canRecord else {
            print("[GeminiLiveService] Cannot start recording - not ready (state: \(state))")
            return
        }

        // Interrupt any current response (barge-in)
        if isSpeaking {
            interruptResponse()
        }

        // Reset recording state
        audioLock.lock()
        recordedAudioChunks.removeAll()
        audioLock.unlock()

        silenceStartTime = nil
        hasDetectedSpeech = false
        currentAudioLevel = 0

        isRecording = true
        state = .recording

        // Start microphone
        do {
            try configureAudioSession()
            try microphoneCapture.startCapturing()
            startSilenceDetection()
            print("[GeminiLiveService] Recording started (auto-send on silence)")
        } catch {
            print("[GeminiLiveService] Failed to start recording: \(error)")
            isRecording = false
            state = .ready
            errorMessage = "Failed to start microphone: \(error.localizedDescription)"
        }
    }

    /// Stop recording and send audio + video context to Gemini
    func stopRecordingAndSend() {
        guard isRecording else { return }

        stopSilenceDetection()
        stopRecordingInternal()

        // Get accumulated audio
        audioLock.lock()
        let audioChunks = recordedAudioChunks
        recordedAudioChunks.removeAll()
        audioLock.unlock()

        guard !audioChunks.isEmpty else {
            print("[GeminiLiveService] No audio recorded")
            state = .ready
            return
        }

        // Combine audio data
        var combinedAudio = Data()
        for chunk in audioChunks {
            combinedAudio.append(chunk)
        }

        // Get buffered video frames
        let videoFrames = frameEncoder.getRingBufferFrames()

        print("[GeminiLiveService] Sending \(combinedAudio.count) bytes audio + \(videoFrames.count) video frames")

        // Ensure audio player is ready for response playback
        prepareForPlayback()

        // Send to Gemini
        sendInputToGemini(audioData: combinedAudio, videoFrames: videoFrames)

        state = .processing
    }

    /// Cancel recording without sending
    func cancelRecording() {
        guard isRecording else { return }

        stopSilenceDetection()
        stopRecordingInternal()

        audioLock.lock()
        recordedAudioChunks.removeAll()
        audioLock.unlock()

        state = .ready
        print("[GeminiLiveService] Recording cancelled")
    }

    /// Toggle recording (for button press) - now just starts, auto-sends on silence
    func toggleRecording() {
        if isRecording {
            // Manual send if user taps again
            stopRecordingAndSend()
        } else {
            startRecording()
        }
    }

    // MARK: - Silence Detection

    private func startSilenceDetection() {
        silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSilence()
            }
        }
    }

    private func stopSilenceDetection() {
        silenceCheckTimer?.invalidate()
        silenceCheckTimer = nil
    }

    private func checkForSilence() {
        guard isRecording, hasDetectedSpeech else { return }

        if currentAudioLevel < speechThreshold {
            // Silence detected
            if silenceStartTime == nil {
                silenceStartTime = Date()
            } else if let start = silenceStartTime,
                      Date().timeIntervalSince(start) >= silenceDuration {
                // Silence duration exceeded - auto-send
                print("[GeminiLiveService] Silence detected for \(silenceDuration)s - auto-sending")
                stopRecordingAndSend()
            }
        } else {
            // Speech detected - reset silence timer
            silenceStartTime = nil
        }
    }

    /// Process audio level for silence detection
    private func updateAudioLevel(from audioData: Data) {
        // Calculate RMS level from PCM data
        let level = calculateAudioLevel(from: audioData)
        currentAudioLevel = level

        // Mark that we've detected speech
        if level > speechThreshold {
            hasDetectedSpeech = true
            silenceStartTime = nil
        }
    }

    private func calculateAudioLevel(from data: Data) -> Float {
        guard data.count >= 2 else { return 0 }

        var sum: Float = 0
        let samples = data.withUnsafeBytes { buffer -> [Int16] in
            let pointer = buffer.bindMemory(to: Int16.self)
            return Array(pointer)
        }

        for sample in samples {
            let normalized = Float(sample) / Float(Int16.max)
            sum += normalized * normalized
        }

        let rms = sqrt(sum / Float(samples.count))
        return rms
    }

    /// Interrupt Gemini's response (barge-in)
    func interruptResponse() {
        audioPlayer.interrupt()
        isSpeaking = false
        if state == .responding {
            state = .ready
        }
        print("[GeminiLiveService] Response interrupted")
    }

    // MARK: - Private Methods

    private func stopRecordingInternal() {
        isRecording = false
        microphoneCapture.stopCapturing()
    }

    private func configureAudioSession() throws {
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
    }

    private func sendSetupMessage() {
        let voiceConfig = GeminiVoiceConfig(
            prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig(voiceName: selectedVoice.rawValue)
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
            systemInstruction: systemInstruction,
            outputAudioTranscription: GeminiTranscriptionConfig()
        )

        let message = GeminiSetupMessage(setup: setup)

        // Log setup details
        print("[GeminiLiveService] === SETUP CONFIG ===")
        print("[GeminiLiveService] Model: \(model)")
        print("[GeminiLiveService] Voice: \(selectedVoice.rawValue)")
        print("[GeminiLiveService] responseModalities: [\"AUDIO\"]")
        print("[GeminiLiveService] ===================")

        webSocketClient.send(setup: message)
    }

    /// Send audio and video to Gemini (video frames first for context, then audio)
    private func sendInputToGemini(audioData: Data, videoFrames: [String]) {
        // Send video frames first to provide visual context
        for (index, frameData) in videoFrames.enumerated() {
            let videoInput = GeminiRealtimeInput.video(data: frameData)
            let videoMessage = GeminiRealtimeInputMessage(realtimeInput: videoInput)
            webSocketClient.send(realtimeInput: videoMessage)

            if index == 0 {
                print("[GeminiLiveService] Sent video frame \(index + 1)/\(videoFrames.count)")
            }
        }

        // Then send audio
        let audioBase64 = audioData.base64EncodedString()
        let audioInput = GeminiRealtimeInput.audio(data: audioBase64)
        let audioMessage = GeminiRealtimeInputMessage(realtimeInput: audioInput)
        webSocketClient.send(realtimeInput: audioMessage)

        print("[GeminiLiveService] Sent audio (\(audioData.count) bytes)")
    }

    private func startAudioPlayer() {
        do {
            try configureAudioSessionForPlayback()
            try audioPlayer.start()
            print("[GeminiLiveService] Audio player started")
        } catch {
            print("[GeminiLiveService] Audio player failed: \(error)")
        }
    }

    /// Prepare audio system for playback after recording
    private func prepareForPlayback() {
        do {
            try configureAudioSessionForPlayback()

            // Restart audio player if needed
            if !audioPlayer.isPlaying {
                try audioPlayer.start()
                print("[GeminiLiveService] Audio player restarted for playback")
            }
        } catch {
            print("[GeminiLiveService] Failed to prepare for playback: \(error)")
        }
    }

    /// Configure audio session specifically for playback
    private func configureAudioSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()

        // Ensure we're in playAndRecord mode with speaker output
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )

        // Make sure audio session is active
        try session.setActive(true)

        print("[GeminiLiveService] Audio session configured for playback: \(session.currentRoute.outputs.map { $0.portName })")
    }

    // MARK: - Session Timer

    private func startSessionTimer() {
        sessionStartTime = Date()

        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleSessionTimeout()
            }
        }

        print("[GeminiLiveService] Session timer started (\(Int(sessionTimeout/60)) minutes)")
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    private func handleSessionTimeout() {
        print("[GeminiLiveService] Session timeout - refreshing connection")

        // Save current state
        let wasRecording = isRecording

        // Stop current session
        stopRecordingInternal()
        webSocketClient.disconnect()

        // Brief delay then reconnect
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s

            if let apiKey = apiKeyManager.apiKey {
                state = .connecting
                webSocketClient.connect(apiKey: apiKey)
            }
        }
    }

    // MARK: - Reconnection

    private func handleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            state = .error(.connectionFailed("Max reconnection attempts reached"))
            errorMessage = "Connection failed after \(maxReconnectAttempts) attempts"
            return
        }

        reconnectAttempts += 1
        print("[GeminiLiveService] Reconnecting (attempt \(reconnectAttempts)/\(maxReconnectAttempts))...")

        reconnectTask = Task {
            // Exponential backoff: 2, 4, 8 seconds
            let delay = UInt64(pow(2.0, Double(reconnectAttempts))) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delay)

            if !Task.isCancelled {
                if let apiKey = self.apiKeyManager.apiKey {
                    self.state = .connecting
                    self.webSocketClient.connect(apiKey: apiKey)
                }
            }
        }
    }
}

// MARK: - WebSocket Delegate

extension GeminiLiveService: GeminiWebSocketDelegate {

    nonisolated func webSocketDidConnect() {
        Task { @MainActor in
            self.state = .connected
            self.sendSetupMessage()
        }
    }

    nonisolated func webSocketDidDisconnect(error: Error?) {
        Task { @MainActor in
            let wasActive = self.state.isActive

            self.isRecording = false
            self.isSpeaking = false
            self.stopSessionTimer()

            if wasActive && self.state != .disconnected {
                print("[GeminiLiveService] Unexpected disconnect, attempting reconnect...")
                self.handleReconnect()
            } else {
                self.state = .disconnected
            }
        }
    }

    nonisolated func webSocketDidReceive(message: GeminiServerMessage) {
        Task { @MainActor in
            // Handle setup complete
            if message.setupComplete != nil {
                self.state = .ready
                self.reconnectAttempts = 0
                self.startSessionTimer()
                self.startAudioPlayer()
                print("[GeminiLiveService] Setup complete, ready for input")
            }

            // Handle model turn (Gemini is speaking)
            if let modelTurn = message.serverContent?.modelTurn {
                if let parts = modelTurn.parts, !parts.isEmpty {
                    self.isSpeaking = true
                    if self.state == .processing {
                        self.state = .responding
                    }

                    // Extract text response if present
                    for part in parts {
                        if let text = part.text, !text.isEmpty {
                            self.lastResponse = text
                        }
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
                self.state = .ready
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
            print("[GeminiLiveService] Received audio data: \(audioData.count) bytes, player isPlaying: \(self.audioPlayer.isPlaying)")

            if !self.audioPlayer.isPlaying {
                print("[GeminiLiveService] Audio player not playing, attempting restart...")
                self.prepareForPlayback()
            }

            self.audioPlayer.enqueue(audioData: audioData)
        }
    }
}

// MARK: - Microphone Delegate

extension GeminiLiveService: GeminiMicrophoneCaptureDelegate {

    nonisolated func microphoneDidCapture(audioData: Data) {
        Task { @MainActor in
            // Only accumulate if recording
            guard self.isRecording else { return }

            // Update audio level for silence detection
            self.updateAudioLevel(from: audioData)

            self.audioLock.lock()
            self.recordedAudioChunks.append(audioData)
            self.audioLock.unlock()
        }
    }

    nonisolated func microphoneDidFail(error: Error) {
        Task { @MainActor in
            self.errorMessage = "Microphone error: \(error.localizedDescription)"
            self.isRecording = false
            self.stopSilenceDetection()
            self.state = .ready
            print("[GeminiLiveService] Microphone error: \(error)")
        }
    }
}

// MARK: - Status Helpers

extension GeminiLiveService {

    var statusDescription: String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Setting up..."
        case .ready: return "Ready"
        case .recording: return "Listening..."
        case .processing: return "Thinking..."
        case .responding: return "Speaking..."
        case .error(let error): return "Error"
        }
    }

    var statusColor: String {
        switch state {
        case .disconnected: return "gray"
        case .connecting: return "yellow"
        case .connected: return "yellow"
        case .ready: return "green"
        case .recording: return "red"
        case .processing: return "yellow"
        case .responding: return "purple"
        case .error: return "red"
        }
    }
}
