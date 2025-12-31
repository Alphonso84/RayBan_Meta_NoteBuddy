//
//  GeminiWebSocketClient.swift
//  Smart Glasses
//
//  WebSocket client for Gemini Live API communication
//

import Foundation

// MARK: - Delegate Protocol

protocol GeminiWebSocketDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceive(message: GeminiServerMessage)
    func webSocketDidReceive(audioData: Data)
}

// MARK: - WebSocket Client

class GeminiWebSocketClient: NSObject {

    // MARK: - Properties

    weak var delegate: GeminiWebSocketDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?

    private let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

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

        // Gemini API uses camelCase for JSON keys
        // Do NOT use snake_case conversion - it breaks mimeType, realtimeInput, etc.
    }

    // MARK: - Connection Management

    func connect(apiKey: String) {
        guard !isConnected else {
            print("[GeminiWS] Already connected")
            return
        }

        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = urlComponents.url else {
            delegate?.webSocketDidDisconnect(error: GeminiError.connectionFailed("Invalid URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        startReceiving()
        startPingTimer()

        print("[GeminiWS] Connecting to Gemini Live API...")
    }

    func disconnect() {
        stopPingTimer()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("[GeminiWS] Disconnected")
    }

    // MARK: - Sending Messages

    func send(setup: GeminiSetupMessage) {
        sendEncodable(setup)
    }

    func send(realtimeInput: GeminiRealtimeInputMessage) {
        sendEncodable(realtimeInput)
    }

    private func sendEncodable<T: Encodable>(_ message: T) {
        guard isConnected else {
            print("[GeminiWS] Cannot send - not connected")
            return
        }

        do {
            let data = try encoder.encode(message)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                print("[GeminiWS] Failed to convert message to string")
                return
            }

            // Log all messages for debugging
            if jsonString.contains("setup") {
                print("[GeminiWS] === SENDING SETUP ===")
                print("[GeminiWS] \(jsonString)")
                print("[GeminiWS] === END SETUP ===")
            } else if jsonString.count < 200 {
                print("[GeminiWS] Sending: \(jsonString)")
            } else {
                print("[GeminiWS] Sending message: \(jsonString.prefix(100))... (\(jsonString.count) chars)")
            }

            webSocketTask?.send(.string(jsonString)) { [weak self] error in
                if let error = error {
                    print("[GeminiWS] Send error: \(error.localizedDescription)")
                    self?.handleSendError(error)
                } else {
                    print("[GeminiWS] Message sent successfully")
                }
            }
        } catch {
            print("[GeminiWS] Encoding error: \(error.localizedDescription)")
        }
    }

    private func handleSendError(_ error: Error) {
        // If send fails due to connection issue, trigger disconnect
        if (error as NSError).code == 57 {  // Socket not connected
            DispatchQueue.main.async {
                self.delegate?.webSocketDidDisconnect(error: error)
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
                // Continue receiving
                self.startReceiving()

            case .failure(let error):
                print("[GeminiWS] Receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.delegate?.webSocketDidDisconnect(error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTextMessage(text)

        case .data(let data):
            // Binary messages - less common for Gemini
            parseDataMessage(data)

        @unknown default:
            print("[GeminiWS] Unknown message type received")
        }
    }

    private func parseTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            print("[GeminiWS] Failed to convert message to data")
            return
        }

        do {
            let serverMessage = try decoder.decode(GeminiServerMessage.self, from: data)

            // Log message type for debugging
            if serverMessage.setupComplete != nil {
                print("[GeminiWS] ✓ Received: setupComplete")
            }
            if serverMessage.serverContent != nil {
                if serverMessage.serverContent?.turnComplete == true {
                    print("[GeminiWS] ✓ Received: turnComplete")
                }
                if serverMessage.serverContent?.interrupted == true {
                    print("[GeminiWS] ✓ Received: interrupted")
                }
                if serverMessage.serverContent?.generationComplete == true {
                    print("[GeminiWS] ✓ Received: generationComplete")
                }
            }

            // Log transcription if present
            if let inputTranscript = serverMessage.serverContent?.inputTranscription?.text {
                print("[GeminiWS] 🎤 Input transcription: \(inputTranscript)")
            }
            if let outputTranscript = serverMessage.serverContent?.outputTranscription?.text {
                print("[GeminiWS] 🔊 Output transcription: \(outputTranscript)")
            }

            // Extract audio data if present and notify delegate
            if let parts = serverMessage.serverContent?.modelTurn?.parts {
                print("[GeminiWS] 📦 Processing modelTurn with \(parts.count) parts")

                var audioPartsCount = 0
                var textPartsCount = 0

                for (index, part) in parts.enumerated() {
                    // Check for text response
                    if let textContent = part.text {
                        textPartsCount += 1
                        print("[GeminiWS] Part \(index): TEXT = \"\(textContent.prefix(100))\"")
                    }

                    // Check for audio response
                    if let inlineData = part.inlineData {
                        print("[GeminiWS] Part \(index): INLINE_DATA mimeType=\"\(inlineData.mimeType)\" base64Length=\(inlineData.data.count)")

                        // Accept various audio formats from Gemini
                        if inlineData.mimeType.starts(with: "audio/") || inlineData.mimeType.contains("pcm") || inlineData.mimeType.contains("wav") {
                            audioPartsCount += 1
                            if let audioData = Data(base64Encoded: inlineData.data) {
                                print("[GeminiWS] ✓ Part \(index): Decoded AUDIO \(audioData.count) bytes - sending to delegate")
                                DispatchQueue.main.async {
                                    self.delegate?.webSocketDidReceive(audioData: audioData)
                                }
                            } else {
                                print("[GeminiWS] ✗ Part \(index): ERROR - Failed to decode base64 audio data")
                            }
                        } else {
                            print("[GeminiWS] Part \(index): Non-audio inlineData (mimeType=\(inlineData.mimeType)), skipping")
                        }
                    }

                    // Check if part has neither text nor inlineData
                    if part.text == nil && part.inlineData == nil {
                        print("[GeminiWS] Part \(index): Empty part (no text or inlineData)")
                    }
                }

                // Summary log
                print("[GeminiWS] 📊 ModelTurn summary: \(textPartsCount) text parts, \(audioPartsCount) audio parts")
                if audioPartsCount == 0 && textPartsCount > 0 {
                    print("[GeminiWS] ⚠️ WARNING: Response contains text but NO audio - check model and responseModalities config")
                }
            }

            // Notify delegate of the full message
            DispatchQueue.main.async {
                self.delegate?.webSocketDidReceive(message: serverMessage)
            }

        } catch {
            print("[GeminiWS] Failed to decode message: \(error.localizedDescription)")
            // Print raw message for debugging
            if text.count < 500 {
                print("[GeminiWS] Raw message: \(text)")
            } else {
                print("[GeminiWS] Raw message (truncated): \(text.prefix(500))...")
            }
        }
    }

    private func parseDataMessage(_ data: Data) {
        // Attempt to decode as server message
        do {
            let serverMessage = try decoder.decode(GeminiServerMessage.self, from: data)
            DispatchQueue.main.async {
                self.delegate?.webSocketDidReceive(message: serverMessage)
            }
        } catch {
            print("[GeminiWS] Failed to decode binary message: \(error.localizedDescription)")
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
                print("[GeminiWS] Ping failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.delegate?.webSocketDidDisconnect(error: error)
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiWebSocketClient: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("[GeminiWS] Connected successfully")
        DispatchQueue.main.async {
            self.delegate?.webSocketDidConnect()
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        isConnected = false
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        print("[GeminiWS] Connection closed: \(closeCode) - \(reasonString)")
        DispatchQueue.main.async {
            self.delegate?.webSocketDidDisconnect(error: nil)
        }
    }
}
