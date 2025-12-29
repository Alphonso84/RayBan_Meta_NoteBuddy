//
//  AIAssistantOverlayView.swift
//  Smart Glasses
//
//  Overlay UI for AI Assistant mode - Meta Ray-Bans style
//  Tap to speak, optional photo for vision questions
//

import SwiftUI
import MWDATCamera

// MARK: - Main Overlay View

struct AIAssistantOverlayView: View {
    @ObservedObject var voiceAssistant: GeminiVoiceAssistant
    @ObservedObject var wearablesManager: WearablesManager

    // Legacy initializer for compatibility
    init(geminiManager: GeminiLiveManager, wearablesManager: WearablesManager) {
        self.voiceAssistant = GeminiVoiceAssistant.shared
        self.wearablesManager = wearablesManager
    }

    init(voiceAssistant: GeminiVoiceAssistant, wearablesManager: WearablesManager) {
        self.voiceAssistant = voiceAssistant
        self.wearablesManager = wearablesManager
    }

    var body: some View {
        VStack {
            // Top status area
            HStack(spacing: 12) {
                AssistantStatusBadge(voiceAssistant: voiceAssistant)

                Spacer()

                // Photo indicator (when photo is queued)
                if voiceAssistant.includePhoto {
                    PhotoQueuedBadge()
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 16)

            Spacer()

            // Response text (when available and not speaking)
            if !voiceAssistant.lastResponse.isEmpty && voiceAssistant.state == .idle {
                LastResponseView(response: voiceAssistant.lastResponse)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }

            // Main controls
            VoiceAssistantControls(
                voiceAssistant: voiceAssistant,
                wearablesManager: wearablesManager
            )
            .padding(.bottom, 120)  // Space for mode picker
        }
        .animation(.easeInOut(duration: 0.3), value: voiceAssistant.state)
        .animation(.easeInOut(duration: 0.2), value: voiceAssistant.includePhoto)
    }
}

// MARK: - Status Badge

struct StatusBadgeView: View {
    @ObservedObject var geminiManager: GeminiLiveManager

    var body: some View {
        HStack(spacing: 8) {
            // Connection status dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.5), radius: 4)

            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch geminiManager.state {
        case .disconnected:
            return .gray
        case .connecting, .configuring:
            return .yellow
        case .connected, .ready:
            return .blue
        case .streaming, .responding:
            return .green
        case .error:
            return .red
        case .reconnecting:
            return .orange
        }
    }

    private var statusText: String {
        switch geminiManager.state {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .configuring:
            return "Setting up..."
        case .ready:
            return "Ready"
        case .streaming:
            return "AI Active"
        case .responding:
            return "Responding"
        case .error:
            return "Error"
        case .reconnecting(let attempt):
            return "Reconnecting (\(attempt))"
        }
    }
}

// MARK: - Compact Conversation Indicator (for top bar)

struct CompactConversationIndicator: View {
    @ObservedObject var geminiManager: GeminiLiveManager

    var body: some View {
        HStack(spacing: 8) {
            if geminiManager.isSpeaking {
                // Compact speaking animation
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        CompactSpeakingBar(delay: Double(index) * 0.1)
                    }
                }
                .frame(width: 20, height: 16)

                Text("AI Speaking")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            } else if geminiManager.isRecordingVoice {
                // Recording indicator
                Image(systemName: "mic.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .symbolEffect(.pulse)

                Text("Recording...")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            geminiManager.isSpeaking ? Color.purple.opacity(0.8) :
            geminiManager.isRecordingVoice ? Color.red.opacity(0.8) :
            Color.green.opacity(0.8)
        )
        .clipShape(Capsule())
    }
}

struct CompactSpeakingBar: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white)
            .frame(width: 3, height: isAnimating ? 14 : 4)
            .animation(
                .easeInOut(duration: 0.3)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Conversation Indicator (legacy, kept for reference)

struct ConversationIndicatorView: View {
    @ObservedObject var geminiManager: GeminiLiveManager

    var body: some View {
        VStack(spacing: 16) {
            if geminiManager.isSpeaking {
                // Speaking animation
                SpeakingAnimationView()

                Text("Gemini is speaking...")
                    .font(.caption)
                    .foregroundColor(.white)
            } else if geminiManager.isListening {
                // Listening indicator
                ListeningIndicatorView()

                Text("Listening...")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Speaking Animation

struct SpeakingAnimationView: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                SpeakingBar(delay: Double(index) * 0.1)
            }
        }
        .frame(height: 40)
    }
}

struct SpeakingBar: View {
    let delay: Double

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(
                colors: [.blue, .purple],
                startPoint: .bottom,
                endPoint: .top
            ))
            .frame(width: 6, height: isAnimating ? 35 : 8)
            .animation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Listening Indicator

struct ListeningIndicatorView: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse
            Circle()
                .stroke(Color.green.opacity(0.3), lineWidth: 2)
                .frame(width: 60, height: 60)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 1)

            // Inner circle
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 50, height: 50)

            // Mic icon
            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundColor(.green)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Controls View

struct AIAssistantControlsView: View {
    @ObservedObject var geminiManager: GeminiLiveManager
    let isStreaming: Bool

    @State private var showAPIKeyAlert = false
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(spacing: 16) {
            // Error message if any
            if let error = geminiManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // API Key prompt if not configured
            if !geminiManager.hasAPIKey {
                Button {
                    showAPIKeyAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                        Text("Add API Key to Start")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
                }
                .alert("Gemini API Key", isPresented: $showAPIKeyAlert) {
                    TextField("Enter API Key", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Cancel", role: .cancel) {
                        apiKeyInput = ""
                    }
                    Button("Save") {
                        if GeminiAPIKeyManager.shared.setAPIKey(apiKeyInput) {
                            apiKeyInput = ""
                            // Auto-start after saving key
                            if isStreaming {
                                geminiManager.startSession()
                            }
                        }
                    }
                } message: {
                    Text("Enter your Gemini API key from Google AI Studio")
                }
            } else if geminiManager.conversationActive {
                // Push-to-Talk Speak Button
                PushToTalkButton(geminiManager: geminiManager)
            }
        }
    }
}

// MARK: - Push-to-Talk Button

struct PushToTalkButton: View {
    @ObservedObject var geminiManager: GeminiLiveManager
    @State private var isPressing = false

    private var isEnabled: Bool {
        geminiManager.state == .ready ||
        geminiManager.state == .streaming ||
        geminiManager.state == .responding
    }

    private var buttonColor: Color {
        if geminiManager.isRecordingVoice {
            return .red
        } else if geminiManager.isSpeaking {
            return .purple.opacity(0.6)
        } else {
            return .green
        }
    }

    private var buttonIcon: String {
        if geminiManager.isRecordingVoice {
            return "mic.fill"
        } else if geminiManager.isSpeaking {
            return "speaker.wave.2.fill"
        } else {
            return "mic"
        }
    }

    private var buttonText: String {
        if geminiManager.isRecordingVoice {
            return "Tap to Send"
        } else if geminiManager.isSpeaking {
            return "AI Speaking..."
        } else {
            return "Tap to Speak"
        }
    }

    var body: some View {
        Button {
            geminiManager.toggleVoiceRecording()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    // Outer ring (animated when recording)
                    Circle()
                        .stroke(buttonColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 90, height: 90)
                        .scaleEffect(geminiManager.isRecordingVoice ? 1.2 : 1.0)
                        .opacity(geminiManager.isRecordingVoice ? 0.5 : 1.0)
                        .animation(
                            geminiManager.isRecordingVoice ?
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                                .default,
                            value: geminiManager.isRecordingVoice
                        )

                    // Main button circle
                    Circle()
                        .fill(buttonColor)
                        .frame(width: 76, height: 76)
                        .shadow(color: buttonColor.opacity(0.5), radius: 8, y: 4)

                    // Icon
                    Image(systemName: buttonIcon)
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .symbolEffect(.pulse, isActive: geminiManager.isRecordingVoice)
                }

                // Label
                Text(buttonText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: geminiManager.isRecordingVoice)
        .animation(.easeInOut(duration: 0.2), value: geminiManager.isSpeaking)
    }
}

// MARK: - New Voice Assistant Components

struct AssistantStatusBadge: View {
    @ObservedObject var voiceAssistant: GeminiVoiceAssistant

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.5), radius: 4)

            Text(voiceAssistant.statusDescription)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch voiceAssistant.state {
        case .idle: return .gray
        case .recording: return .red
        case .processing: return .yellow
        case .speaking: return .purple
        case .error: return .red
        }
    }
}

struct PhotoQueuedBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.fill")
                .font(.caption)
            Text("Photo Ready")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.8))
        .clipShape(Capsule())
    }
}

struct LastResponseView: View {
    let response: String

    var body: some View {
        Text(response)
            .font(.subheadline)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .padding()
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct VoiceAssistantControls: View {
    @ObservedObject var voiceAssistant: GeminiVoiceAssistant
    @ObservedObject var wearablesManager: WearablesManager

    @State private var showAPIKeyAlert = false
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(spacing: 20) {
            // Error message
            if let error = voiceAssistant.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // API Key prompt or main controls
            if !voiceAssistant.hasAPIKey {
                Button {
                    showAPIKeyAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                        Text("Add API Key")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
                }
                .alert("Gemini API Key", isPresented: $showAPIKeyAlert) {
                    TextField("Enter API Key", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Cancel", role: .cancel) { apiKeyInput = "" }
                    Button("Save") {
                        if GeminiAPIKeyManager.shared.setAPIKey(apiKeyInput) {
                            apiKeyInput = ""
                        }
                    }
                } message: {
                    Text("Enter your Gemini API key from Google AI Studio")
                }
            } else {
                // Main control buttons
                HStack(spacing: 40) {
                    // Camera button - capture photo for vision
                    VisionCaptureButton(
                        voiceAssistant: voiceAssistant,
                        wearablesManager: wearablesManager
                    )

                    // Main speak button
                    MainSpeakButton(voiceAssistant: voiceAssistant)
                }
            }
        }
    }
}

// MARK: - Vision Capture Button

struct VisionCaptureButton: View {
    @ObservedObject var voiceAssistant: GeminiVoiceAssistant
    @ObservedObject var wearablesManager: WearablesManager

    private var isEnabled: Bool {
        voiceAssistant.state == .idle && wearablesManager.latestFrameImage != nil
    }

    var body: some View {
        Button {
            // Capture current frame for vision
            if let frame = wearablesManager.latestFrameImage {
                voiceAssistant.capturePhotoForVision(frame)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(voiceAssistant.includePhoto ? Color.blue : Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)

                    Image(systemName: voiceAssistant.includePhoto ? "camera.fill" : "camera")
                        .font(.system(size: 24))
                        .foregroundColor(voiceAssistant.includePhoto ? .white : .white.opacity(0.8))
                }

                Text(voiceAssistant.includePhoto ? "Photo Added" : "Add Photo")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Main Speak Button

struct MainSpeakButton: View {
    @ObservedObject var voiceAssistant: GeminiVoiceAssistant

    private var isEnabled: Bool {
        voiceAssistant.state == .idle || voiceAssistant.state == .recording
    }

    private var buttonColor: Color {
        switch voiceAssistant.state {
        case .idle: return .green
        case .recording: return .red
        case .processing: return .yellow
        case .speaking: return .purple
        case .error: return .gray
        }
    }

    private var buttonIcon: String {
        switch voiceAssistant.state {
        case .idle: return "mic"
        case .recording: return "stop.fill"
        case .processing: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var buttonText: String {
        switch voiceAssistant.state {
        case .idle: return "Tap to Speak"
        case .recording: return "Tap to Send"
        case .processing: return "Processing..."
        case .speaking: return "Speaking..."
        case .error: return "Try Again"
        }
    }

    var body: some View {
        Button {
            if voiceAssistant.state == .speaking {
                voiceAssistant.stopSpeaking()
            } else if voiceAssistant.state.isError {
                voiceAssistant.reset()
            } else {
                voiceAssistant.toggleRecording()
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    // Outer ring (animated when recording)
                    Circle()
                        .stroke(buttonColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 90, height: 90)
                        .scaleEffect(voiceAssistant.isRecording ? 1.2 : 1.0)
                        .opacity(voiceAssistant.isRecording ? 0.5 : 1.0)
                        .animation(
                            voiceAssistant.isRecording ?
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                                .default,
                            value: voiceAssistant.isRecording
                        )

                    // Main button circle
                    Circle()
                        .fill(buttonColor)
                        .frame(width: 76, height: 76)
                        .shadow(color: buttonColor.opacity(0.5), radius: 8, y: 4)

                    // Icon
                    if voiceAssistant.state == .processing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, isActive: voiceAssistant.isRecording)
                    }
                }

                // Label
                Text(buttonText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
        }
        .disabled(!isEnabled && voiceAssistant.state != .speaking && !voiceAssistant.state.isError)
        .animation(.easeInOut(duration: 0.2), value: voiceAssistant.state)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        AIAssistantOverlayView(
            voiceAssistant: GeminiVoiceAssistant.shared,
            wearablesManager: WearablesManager.shared
        )
    }
    .ignoresSafeArea()
}
