//
//  AIAssistantOverlayView.swift
//  Smart Glasses
//
//  Overlay UI for AI Assistant mode - Meta Ray-Bans style
//  Speak or type to interact, automatic vision with photos sent every 5 seconds
//

import SwiftUI
import MWDATCamera

// MARK: - Main Overlay View

struct AIAssistantOverlayView: View {
    @ObservedObject var voiceAssistant: OpenAIVoiceAssistant
    @ObservedObject var wearablesManager: WearablesManager

    // Text input state (lifted up so text field can be at top)
    @State private var showTextInput = false
    @State private var textInput = ""
    @FocusState private var isTextFieldFocused: Bool

    init(voiceAssistant: OpenAIVoiceAssistant, wearablesManager: WearablesManager) {
        self.voiceAssistant = voiceAssistant
        self.wearablesManager = wearablesManager
    }

    var body: some View {
        VStack {
            // Top status area
            HStack(spacing: 12) {
                AssistantStatusBadge(voiceAssistant: voiceAssistant)

                Spacer()

                // Auto vision indicator (when session is active)
                if voiceAssistant.state == .recording ||
                   voiceAssistant.state == .processing ||
                   voiceAssistant.state == .speaking {
                    AutoVisionBadge()
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 16)

            // Text input field at top (when typing)
            if showTextInput {
                TopTextInputView(
                    text: $textInput,
                    isFocused: $isTextFieldFocused,
                    onSubmit: {
                        if !textInput.isEmpty {
                            voiceAssistant.sendTextMessage(textInput)
                            textInput = ""
                            showTextInput = false
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            // Response text (when available and not speaking)
            if !voiceAssistant.lastResponse.isEmpty && voiceAssistant.state == .idle && !showTextInput {
                LastResponseView(response: voiceAssistant.lastResponse)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }

            // Main controls
            VoiceAssistantControls(
                voiceAssistant: voiceAssistant,
                showTextInput: $showTextInput,
                onToggleTextInput: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTextInput.toggle()
                        if showTextInput {
                            isTextFieldFocused = true
                        } else {
                            textInput = ""
                        }
                    }
                }
            )
            .padding(.bottom, 120)  // Space for mode picker
        }
        .animation(.easeInOut(duration: 0.3), value: voiceAssistant.state)
        .animation(.easeInOut(duration: 0.2), value: showTextInput)
    }
}

// MARK: - Top Text Input View

struct TopTextInputView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Text field styled like LastResponseView
            TextField("Type your message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1...4)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(onSubmit)
                .padding()
                .frame(minHeight: 50)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Send button
            if !text.isEmpty {
                Button(action: onSubmit) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Send")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .clipShape(Capsule())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
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

// MARK: - Voice Assistant Components

struct AssistantStatusBadge: View {
    @ObservedObject var voiceAssistant: OpenAIVoiceAssistant

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

struct AutoVisionBadge: View {
    @State private var dotOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .opacity(dotOpacity)
                .animation(
                    .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                    value: dotOpacity
                )
                .onAppear { dotOpacity = 0.3 }

            Image(systemName: "eye.fill")
                .font(.caption)
            Text("Auto Vision")
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
    @ObservedObject var voiceAssistant: OpenAIVoiceAssistant
    @Binding var showTextInput: Bool
    var onToggleTextInput: () -> Void

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
                .alert("OpenAI API Key", isPresented: $showAPIKeyAlert) {
                    TextField("Enter API Key", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Cancel", role: .cancel) { apiKeyInput = "" }
                    Button("Save") {
                        if OpenAIAPIKeyManager.shared.setAPIKey(apiKeyInput) {
                            apiKeyInput = ""
                        }
                    }
                } message: {
                    Text("Enter your OpenAI API key from platform.openai.com")
                }
            } else {
                // Main control buttons
                HStack(spacing: 30) {
                    // Auto vision indicator
                    AutoVisionIndicator(voiceAssistant: voiceAssistant)

                    // Main speak button
                    MainSpeakButton(voiceAssistant: voiceAssistant)

                    // Text input toggle button
                    TextInputButton(
                        isActive: showTextInput,
                        isEnabled: voiceAssistant.state == .idle || voiceAssistant.state.isError,
                        action: onToggleTextInput
                    )
                }
            }
        }
    }
}

// MARK: - Text Input Button

struct TextInputButton: View {
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)

                    Image(systemName: isActive ? "keyboard.fill" : "keyboard")
                        .font(.system(size: 22))
                        .foregroundColor(isActive ? .white : .white.opacity(0.8))
                }

                Text(isActive ? "Typing" : "Type")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Auto Vision Indicator

struct AutoVisionIndicator: View {
    @ObservedObject var voiceAssistant: OpenAIVoiceAssistant

    @State private var isPulsing = false

    private var isActive: Bool {
        voiceAssistant.state == .recording ||
        voiceAssistant.state == .processing ||
        voiceAssistant.state == .speaking
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Pulsing ring when active
                if isActive {
                    Circle()
                        .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                        .opacity(isPulsing ? 0 : 1)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                }

                Circle()
                    .fill(isActive ? Color.blue : Color.white.opacity(0.2))
                    .frame(width: 56, height: 56)

                Image(systemName: isActive ? "eye.fill" : "eye")
                    .font(.system(size: 24))
                    .foregroundColor(isActive ? .white : .white.opacity(0.8))
            }

            Text(isActive ? "Auto Vision" : "Vision Off")
                .font(.caption)
                .foregroundColor(.white)
        }
        .onChange(of: isActive) { _, active in
            isPulsing = active
        }
        .onAppear {
            if isActive {
                isPulsing = true
            }
        }
    }
}

// MARK: - Main Speak Button

struct MainSpeakButton: View {
    @ObservedObject var voiceAssistant: OpenAIVoiceAssistant

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
        case .recording: return "mic.fill"
        case .processing: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var buttonText: String {
        switch voiceAssistant.state {
        case .idle: return "Tap to Speak"
        case .recording: return "Listening..."
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
            voiceAssistant: OpenAIVoiceAssistant.shared,
            wearablesManager: WearablesManager.shared
        )
    }
    .ignoresSafeArea()
}
