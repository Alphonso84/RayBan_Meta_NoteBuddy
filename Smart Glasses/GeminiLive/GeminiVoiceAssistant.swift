//
//  GeminiVoiceAssistant.swift
//  Smart Glasses
//
//  Simple voice assistant using Gemini REST API
//  Tap to record → Send audio (+ optional photo) → Get spoken response
//  Uses Gemini TTS for high-quality voice output
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
class GeminiVoiceAssistant: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = GeminiVoiceAssistant()

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
    @Published var selectedVoice: GeminiVoice = .zephyr

    // MARK: - Configuration

    private let systemPrompt = """
    You are a helpful AI assistant integrated into smart glasses. You can see what the user \
    sees when they share a photo, and you can hear their voice. Be conversational, helpful, \
    and extremely detailed. \
    If the user asks about what they're looking at but \
    no image is provided, politely ask them to tap the camera button first. \
    Look for things in pictures that humans may not immediately notice and offer suggestions or point out things to be aware of.
    """

    // MARK: - Components

    private let apiClient = GeminiAPIClient.shared
    private let apiKeyManager = GeminiAPIKeyManager.shared

    // Audio recording
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    // Audio playback (for Gemini TTS)
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // Fallback iOS TTS (if Gemini TTS fails)
    private let speechSynthesizer = AVSpeechSynthesizer()

    // MARK: - Initialization

    private override init() {
        super.init()
        speechSynthesizer.delegate = self
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else { return }

        engine.attach(player)

        // Gemini TTS outputs 24kHz, 16-bit, mono PCM
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
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
            errorMessage = "Please add your Gemini API key"
            return
        }

        // Stop any ongoing speech
        if isSpeaking {
            stopSpeaking()
        }

        do {
            // Configure audio session
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            // Create recording URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            recordingURL = documentsPath.appendingPathComponent("voice_recording.wav")

            // Recording settings for WAV format
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.record()

            state = .recording
            isRecording = true
            errorMessage = nil

            print("[VoiceAssistant] Recording started")

        } catch {
            print("[VoiceAssistant] Failed to start recording: \(error)")
            state = .error("Failed to start recording")
            errorMessage = error.localizedDescription
        }
    }

    /// Stop recording and send to Gemini
    func stopRecordingAndSend() {
        guard state == .recording, let recorder = audioRecorder else {
            return
        }

        recorder.stop()
        isRecording = false
        state = .processing

        print("[VoiceAssistant] Recording stopped, processing...")

        // Get the recorded audio data
        guard let recordingURL = recordingURL,
              let audioData = try? Data(contentsOf: recordingURL) else {
            state = .error("Failed to read recording")
            errorMessage = "Could not read audio recording"
            return
        }

        print("[VoiceAssistant] Audio size: \(ByteCountFormatter.string(fromByteCount: Int64(audioData.count), countStyle: .file))")

        // Send to Gemini
        Task {
            await sendToGemini(audioData: audioData)
        }
    }

    /// Toggle recording state
    func toggleRecording() {
        if isRecording {
            stopRecordingAndSend()
        } else {
            startRecording()
        }
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
        // Stop Gemini TTS audio player
        playerNode?.stop()

        // Stop fallback iOS TTS
        speechSynthesizer.stopSpeaking(at: .immediate)

        isSpeaking = false
        if state == .speaking {
            state = .idle
        }
    }

    /// Reset assistant state
    func reset() {
        stopSpeaking()
        if isRecording {
            audioRecorder?.stop()
            isRecording = false
        }

        // Stop audio engine
        audioEngine?.stop()

        state = .idle
        lastResponse = ""
        errorMessage = nil
        clearPhoto()
    }

    // MARK: - Private Methods

    private func sendToGemini(audioData: Data) async {
        do {
            let response: String

            if includePhoto, let photo = capturedPhoto {
                // Vision + Audio request
                print("[VoiceAssistant] Sending vision + audio request")
                response = try await apiClient.sendMultimodalMessage(
                    text: "The user is asking about what they see. Listen to their audio question and look at the image to provide a helpful response.",
                    image: photo,
                    audioData: audioData,
                    systemPrompt: systemPrompt
                )
                clearPhoto()
            } else {
                // Audio-only request
                print("[VoiceAssistant] Sending audio-only request")
                response = try await apiClient.sendAudioMessage(
                    "Listen to the user's question and provide a helpful response.",
                    audioData: audioData,
                    systemPrompt: systemPrompt
                )
            }

            print("[VoiceAssistant] Received response: \(response.prefix(100))...")
            lastResponse = response

            // Speak the response
            await speakResponse(response)

        } catch {
            print("[VoiceAssistant] API error: \(error)")
            state = .error("Failed to get response")
            errorMessage = error.localizedDescription
        }
    }

    private func speakResponse(_ text: String) async {
        state = .speaking
        isSpeaking = true

        do {
            // Use Gemini TTS for high-quality voice
            print("[VoiceAssistant] Requesting Gemini TTS...")
            let audioData = try await apiClient.textToSpeech(text, voice: selectedVoice)
            await playPCMAudio(audioData)
        } catch {
            // Fallback to iOS TTS if Gemini TTS fails
            print("[VoiceAssistant] Gemini TTS failed, using fallback: \(error)")
            speakWithFallback(text)
        }
    }

    /// Play PCM audio data from Gemini TTS (24kHz, 16-bit, mono)
    private func playPCMAudio(_ data: Data) async {
        guard let engine = audioEngine, let player = playerNode else {
            print("[VoiceAssistant] Audio engine not available")
            isSpeaking = false
            state = .idle
            return
        }

        // Create audio format for Gemini TTS output
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true) else {
            print("[VoiceAssistant] Failed to create audio format")
            isSpeaking = false
            state = .idle
            return
        }

        // Calculate frame count
        let frameCount = UInt32(data.count) / 2  // 2 bytes per Int16 sample

        // Create audio buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("[VoiceAssistant] Failed to create audio buffer")
            isSpeaking = false
            state = .idle
            return
        }

        buffer.frameLength = frameCount

        // Copy data to buffer
        data.withUnsafeBytes { rawBytes in
            let samples = rawBytes.bindMemory(to: Int16.self)
            if let channelData = buffer.int16ChannelData {
                for i in 0..<Int(frameCount) {
                    channelData[0][i] = samples[i]
                }
            }
        }

        do {
            // Configure audio session for playback
            // Use .playAndRecord to allow .defaultToSpeaker option (routes audio to speaker)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            // Start engine if needed
            if !engine.isRunning {
                // Reconnect player with correct format before starting
                let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
                engine.connect(player, to: engine.mainMixerNode, format: format)
                try engine.start()
            }

            let durationSeconds = Double(frameCount) / 24000.0
            print("[VoiceAssistant] Playing TTS audio (\(frameCount) frames, \(data.count) bytes, \(String(format: "%.1f", durationSeconds))s)...")

            // Schedule buffer with .dataPlayedBack to ensure completion fires AFTER audio finishes
            // (default completion fires when buffer is scheduled, not when playback ends)
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    self?.isSpeaking = false
                    self?.state = .idle
                    print("[VoiceAssistant] Finished playing TTS audio")
                }
            }

            player.play()

        } catch {
            print("[VoiceAssistant] Failed to play audio: \(error)")
            isSpeaking = false
            state = .idle
        }
    }

    /// Fallback to iOS TTS if Gemini TTS fails
    private func speakWithFallback(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        speechSynthesizer.speak(utterance)
    }

    // MARK: - Cleanup

    private func cleanupRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioRecorder = nil
        recordingURL = nil
    }
}

// MARK: - Speech Synthesizer Delegate

extension GeminiVoiceAssistant: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.state = .idle
            print("[VoiceAssistant] Finished speaking")
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

extension GeminiVoiceAssistant {

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
