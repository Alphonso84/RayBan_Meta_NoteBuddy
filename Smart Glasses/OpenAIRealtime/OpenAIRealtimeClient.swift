//
//  OpenAIRealtimeClient.swift
//  Smart Glasses
//
//  WebSocket client for OpenAI Realtime API communication
//

import Foundation

// MARK: - Delegate Protocol

protocol OpenAIRealtimeClientDelegate: AnyObject {
    func clientDidConnect()
    func clientDidDisconnect(error: Error?)
    func clientDidReceiveSessionCreated()
    func clientDidReceiveSessionUpdated()
    func clientDidReceiveSpeechStarted()
    func clientDidReceiveSpeechStopped()
    func clientDidReceiveAudioDelta(_ base64Audio: String)
    func clientDidReceiveTranscript(_ text: String)
    func clientDidReceiveResponseDone()
    func clientDidReceiveError(_ error: ErrorInfo)
}

// MARK: - WebSocket Client

class OpenAIRealtimeClient: NSObject {

    // MARK: - Properties

    weak var delegate: OpenAIRealtimeClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?

    private let endpoint = "wss://api.openai.com/v1/realtime"
    private let model = "gpt-4o-realtime-preview-2024-12-17"

    private(set) var isConnected = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600  // 10 minutes max session
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Connection Management

    func connect(apiKey: String) {
        guard !isConnected else {
            print("[OpenAIRealtime] Already connected")
            return
        }

        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "model", value: model)]

        guard let url = urlComponents.url else {
            let error = NSError(domain: "OpenAIRealtime", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            delegate?.clientDidDisconnect(error: error)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        startReceiving()
        startPingTimer()

        print("[OpenAIRealtime] Connecting to OpenAI Realtime API...")
    }

    func disconnect() {
        stopPingTimer()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("[OpenAIRealtime] Disconnected")
    }

    // MARK: - Sending Events

    /// Configure the session with voice and modalities
    func sendSessionUpdate(instructions: String?, voice: OpenAIVoice) {
        let config = SessionConfig(
            modalities: ["text", "audio"],
            instructions: instructions,
            voice: voice.rawValue,
            inputAudioFormat: "pcm16",
            outputAudioFormat: "pcm16",
            inputAudioTranscription: InputAudioTranscription(model: "whisper-1"),
            turnDetection: TurnDetection(type: "server_vad")  // Auto-detect when user stops talking
        )
        let event = SessionUpdateEvent(session: config)
        sendEncodable(event)
    }

    /// Append audio data to the input buffer
    func appendAudioBuffer(_ base64Audio: String) {
        let event = InputAudioBufferAppendEvent(audio: base64Audio)
        sendEncodable(event)
    }

    /// Commit the audio buffer (signal end of user speech)
    func commitAudioBuffer() {
        let event = InputAudioBufferCommitEvent()
        sendEncodable(event)
        print("[OpenAIRealtime] Audio buffer committed")
    }

    /// Clear the audio buffer
    func clearAudioBuffer() {
        let event = InputAudioBufferClearEvent()
        sendEncodable(event)
        print("[OpenAIRealtime] Audio buffer cleared")
    }

    /// Create a conversation item with an image
    func createImageItem(base64Image: String) {
        let content = [ContentPart.image(base64Image)]
        let item = ConversationItem(type: "message", role: "user", content: content)
        let event = ConversationItemCreateEvent(item: item)
        sendEncodable(event)
        print("[OpenAIRealtime] Image item created")
    }

    /// Create a conversation item with text
    func createTextItem(_ text: String) {
        let content = [ContentPart.text(text)]
        let item = ConversationItem(type: "message", role: "user", content: content)
        let event = ConversationItemCreateEvent(item: item)
        sendEncodable(event)
        print("[OpenAIRealtime] Text item created")
    }

    /// Trigger response generation
    func createResponse() {
        let event = ResponseCreateEvent(response: nil)
        sendEncodable(event)
        print("[OpenAIRealtime] Response requested")
    }

    /// Cancel an in-progress response
    func cancelResponse() {
        let event = ResponseCancelEvent()
        sendEncodable(event)
        print("[OpenAIRealtime] Response cancelled")
    }

    private func sendEncodable<T: Encodable>(_ message: T) {
        guard isConnected else {
            print("[OpenAIRealtime] Cannot send - not connected")
            return
        }

        do {
            let data = try encoder.encode(message)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                print("[OpenAIRealtime] Failed to convert message to string")
                return
            }

            // Log message for debugging (truncate audio data)
            if jsonString.contains("input_audio_buffer.append") {
                print("[OpenAIRealtime] Sending audio chunk...")
            } else if jsonString.count < 500 {
                print("[OpenAIRealtime] Sending: \(jsonString)")
            } else {
                print("[OpenAIRealtime] Sending message: \(jsonString.prefix(200))... (\(jsonString.count) chars)")
            }

            webSocketTask?.send(.string(jsonString)) { [weak self] error in
                if let error = error {
                    print("[OpenAIRealtime] Send error: \(error.localizedDescription)")
                    self?.handleSendError(error)
                }
            }
        } catch {
            print("[OpenAIRealtime] Encoding error: \(error.localizedDescription)")
        }
    }

    private func handleSendError(_ error: Error) {
        if (error as NSError).code == 57 {  // Socket not connected
            DispatchQueue.main.async {
                self.delegate?.clientDidDisconnect(error: error)
            }
        }
    }

    // MARK: - Receiving Messages

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.startReceiving()

            case .failure(let error):
                print("[OpenAIRealtime] Receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.delegate?.clientDidDisconnect(error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTextMessage(text)

        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseTextMessage(text)
            }

        @unknown default:
            print("[OpenAIRealtime] Unknown message type received")
        }
    }

    private func parseTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            print("[OpenAIRealtime] Failed to convert message to data")
            return
        }

        // First, determine the event type
        guard let eventType = try? decoder.decode(ServerEventType.self, from: data) else {
            print("[OpenAIRealtime] Failed to decode event type")
            return
        }

        do {
            switch eventType.type {
            case "session.created":
                let event = try decoder.decode(SessionCreatedEvent.self, from: data)
                print("[OpenAIRealtime] Session created: \(event.session?.id ?? "unknown")")
                DispatchQueue.main.async {
                    self.delegate?.clientDidReceiveSessionCreated()
                }

            case "session.updated":
                let event = try decoder.decode(SessionUpdatedEvent.self, from: data)
                print("[OpenAIRealtime] Session updated: voice=\(event.session?.voice ?? "unknown")")
                DispatchQueue.main.async {
                    self.delegate?.clientDidReceiveSessionUpdated()
                }

            case "response.audio.delta":
                let event = try decoder.decode(ResponseAudioDeltaEvent.self, from: data)
                if let audio = event.delta {
                    DispatchQueue.main.async {
                        self.delegate?.clientDidReceiveAudioDelta(audio)
                    }
                }

            case "response.audio_transcript.delta":
                let event = try decoder.decode(ResponseAudioTranscriptDeltaEvent.self, from: data)
                if let transcript = event.delta {
                    DispatchQueue.main.async {
                        self.delegate?.clientDidReceiveTranscript(transcript)
                    }
                }

            case "response.audio.done":
                print("[OpenAIRealtime] Audio response complete")

            case "response.done":
                let event = try decoder.decode(ResponseDoneEvent.self, from: data)
                print("[OpenAIRealtime] Response done: status=\(event.response?.status ?? "unknown")")
                DispatchQueue.main.async {
                    self.delegate?.clientDidReceiveResponseDone()
                }

            case "error":
                let event = try decoder.decode(ErrorEvent.self, from: data)
                print("[OpenAIRealtime] Error: \(event.error?.message ?? "unknown")")
                if let error = event.error {
                    DispatchQueue.main.async {
                        self.delegate?.clientDidReceiveError(error)
                    }
                }

            case "input_audio_buffer.committed":
                print("[OpenAIRealtime] Audio buffer committed by server")

            case "input_audio_buffer.speech_started":
                print("[OpenAIRealtime] Speech detected (VAD)")
                DispatchQueue.main.async {
                    self.delegate?.clientDidReceiveSpeechStarted()
                }

            case "input_audio_buffer.speech_stopped":
                print("[OpenAIRealtime] Speech stopped (VAD)")
                DispatchQueue.main.async {
                    self.delegate?.clientDidReceiveSpeechStopped()
                }

            case "conversation.item.created":
                let event = try decoder.decode(ConversationItemCreatedEvent.self, from: data)
                print("[OpenAIRealtime] Conversation item created: \(event.item?.type ?? "unknown")")

            case "rate_limits.updated":
                let event = try decoder.decode(RateLimitsUpdatedEvent.self, from: data)
                if let limits = event.rateLimits {
                    for limit in limits {
                        print("[OpenAIRealtime] Rate limit: \(limit.name ?? "unknown") - \(limit.remaining ?? 0)/\(limit.limit ?? 0)")
                    }
                }

            case "response.created", "response.output_item.added", "response.content_part.added",
                 "response.output_item.done", "response.content_part.done", "response.text.delta",
                 "response.text.done", "response.audio_transcript.done":
                // Known events that we don't need to process
                break

            default:
                print("[OpenAIRealtime] Unhandled event type: \(eventType.type)")
                if text.count < 500 {
                    print("[OpenAIRealtime] Raw: \(text)")
                }
            }
        } catch {
            print("[OpenAIRealtime] Failed to decode event '\(eventType.type)': \(error.localizedDescription)")
            if text.count < 500 {
                print("[OpenAIRealtime] Raw: \(text)")
            }
        }
    }

    // MARK: - Keep-Alive

    private func startPingTimer() {
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }

    private func stopPingTimer() {
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = nil
        }
    }

    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("[OpenAIRealtime] Ping failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.delegate?.clientDidDisconnect(error: error)
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension OpenAIRealtimeClient: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("[OpenAIRealtime] Connected successfully")
        DispatchQueue.main.async {
            self.delegate?.clientDidConnect()
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        isConnected = false
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        print("[OpenAIRealtime] Connection closed: \(closeCode) - \(reasonString)")
        DispatchQueue.main.async {
            self.delegate?.clientDidDisconnect(error: nil)
        }
    }
}
