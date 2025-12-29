//
//  GeminiAPIClient.swift
//  Smart Glasses
//
//  REST API client for Gemini 2.5 Flash
//  Handles multimodal requests (text, image, audio)
//

import Foundation
import UIKit
import Combine

// MARK: - API Response Models

struct GeminiAPIResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let error: GeminiAPIError?
}

struct GeminiCandidate: Decodable {
    let content: GeminiContent?
    let finishReason: String?
}

struct GeminiContent: Decodable {
    let parts: [GeminiPart]?
    let role: String?
}

struct GeminiPart: Decodable {
    let text: String?
    let inlineData: GeminiInlineData?
}

struct GeminiAPIError: Decodable {
    let code: Int?
    let message: String?
    let status: String?
}

// MARK: - Gemini Voice Options

enum GeminiVoice: String, CaseIterable {
    case puck = "Puck"          // Upbeat
    case charon = "Charon"      // Informative
    case kore = "Kore"          // Firm
    case fenrir = "Fenrir"      // Deep
    case aoede = "Aoede"        // Warm
    case leda = "Leda"          // Youthful
    case orus = "Orus"          // Firm
    case zephyr = "Zephyr"      // Bright

    var description: String {
        switch self {
        case .puck: return "Upbeat"
        case .charon: return "Informative"
        case .kore: return "Firm"
        case .fenrir: return "Deep"
        case .aoede: return "Warm"
        case .leda: return "Youthful"
        case .orus: return "Firm"
        case .zephyr: return "Bright"
        }
    }
}

// MARK: - API Request Models

struct GeminiAPIRequest: Encodable {
    let contents: [GeminiRequestContent]
    let generationConfig: GeminiRequestGenerationConfig?
    let systemInstruction: GeminiRequestSystemInstruction?
}

struct GeminiRequestContent: Encodable {
    let parts: [GeminiRequestPart]
    let role: String?
}

struct GeminiRequestPart: Encodable {
    let text: String?
    let inlineData: GeminiRequestInlineData?

    init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    init(mimeType: String, data: String) {
        self.text = nil
        self.inlineData = GeminiRequestInlineData(mimeType: mimeType, data: data)
    }
}

struct GeminiRequestInlineData: Encodable {
    let mimeType: String
    let data: String  // base64 encoded
}

struct GeminiRequestGenerationConfig: Encodable {
    let temperature: Double?
    let maxOutputTokens: Int?
    let topP: Double?
    let topK: Int?
    let responseModalities: [String]?
    let speechConfig: GeminiTTSSpeechConfig?

    init(
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        responseModalities: [String]? = nil,
        speechConfig: GeminiTTSSpeechConfig? = nil
    ) {
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.topP = topP
        self.topK = topK
        self.responseModalities = responseModalities
        self.speechConfig = speechConfig
    }
}

// TTS Speech Config structures
struct GeminiTTSSpeechConfig: Encodable {
    let voiceConfig: GeminiTTSVoiceConfig
}

struct GeminiTTSVoiceConfig: Encodable {
    let prebuiltVoiceConfig: GeminiTTSPrebuiltVoiceConfig
}

struct GeminiTTSPrebuiltVoiceConfig: Encodable {
    let voiceName: String
}

struct GeminiRequestSystemInstruction: Encodable {
    let parts: [GeminiRequestPart]
}

// MARK: - API Client

class GeminiAPIClient {

    // MARK: - Properties

    static let shared = GeminiAPIClient()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let model = "gemini-2.5-flash"
    private let ttsModel = "gemini-2.5-flash-preview-tts"

    private let session: URLSession
    private let apiKeyManager = GeminiAPIKeyManager.shared

    /// Selected voice for TTS
    var selectedVoice: GeminiVoice = .puck

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Send a text-only message to Gemini
    /// - Parameters:
    ///   - text: The user's message
    ///   - systemPrompt: Optional system instruction
    /// - Returns: Gemini's text response
    func sendTextMessage(_ text: String, systemPrompt: String? = nil) async throws -> String {
        let parts = [GeminiRequestPart(text: text)]
        return try await sendRequest(parts: parts, systemPrompt: systemPrompt)
    }

    /// Send a message with an image to Gemini
    /// - Parameters:
    ///   - text: The user's question about the image
    ///   - image: The image to analyze
    ///   - systemPrompt: Optional system instruction
    /// - Returns: Gemini's text response
    func sendImageMessage(_ text: String, image: UIImage, systemPrompt: String? = nil) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw GeminiClientError.imageEncodingFailed
        }

        let base64Image = imageData.base64EncodedString()

        let parts: [GeminiRequestPart] = [
            GeminiRequestPart(mimeType: "image/jpeg", data: base64Image),
            GeminiRequestPart(text: text)
        ]

        return try await sendRequest(parts: parts, systemPrompt: systemPrompt)
    }

    /// Send a message with audio to Gemini
    /// - Parameters:
    ///   - text: Optional text prompt
    ///   - audioData: The audio data (WAV format recommended)
    ///   - mimeType: Audio MIME type (e.g., "audio/wav", "audio/mp3")
    ///   - systemPrompt: Optional system instruction
    /// - Returns: Gemini's text response
    func sendAudioMessage(_ text: String?, audioData: Data, mimeType: String = "audio/wav", systemPrompt: String? = nil) async throws -> String {
        let base64Audio = audioData.base64EncodedString()

        var parts: [GeminiRequestPart] = [
            GeminiRequestPart(mimeType: mimeType, data: base64Audio)
        ]

        if let text = text, !text.isEmpty {
            parts.append(GeminiRequestPart(text: text))
        }

        return try await sendRequest(parts: parts, systemPrompt: systemPrompt)
    }

    /// Send a multimodal message with both image and audio
    /// - Parameters:
    ///   - text: Optional text prompt
    ///   - image: The image to analyze
    ///   - audioData: The audio data
    ///   - audioMimeType: Audio MIME type
    ///   - systemPrompt: Optional system instruction
    /// - Returns: Gemini's text response
    func sendMultimodalMessage(
        text: String?,
        image: UIImage?,
        audioData: Data?,
        audioMimeType: String = "audio/wav",
        systemPrompt: String? = nil
    ) async throws -> String {
        var parts: [GeminiRequestPart] = []

        // Add image first if present
        if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
            let base64Image = imageData.base64EncodedString()
            parts.append(GeminiRequestPart(mimeType: "image/jpeg", data: base64Image))
        }

        // Add audio if present
        if let audioData = audioData {
            let base64Audio = audioData.base64EncodedString()
            parts.append(GeminiRequestPart(mimeType: audioMimeType, data: base64Audio))
        }

        // Add text last
        if let text = text, !text.isEmpty {
            parts.append(GeminiRequestPart(text: text))
        }

        guard !parts.isEmpty else {
            throw GeminiClientError.noContent
        }

        return try await sendRequest(parts: parts, systemPrompt: systemPrompt)
    }

    // MARK: - Text-to-Speech

    /// Convert text to speech using Gemini TTS
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use (default: selectedVoice)
    /// - Returns: PCM audio data (24kHz, 16-bit, mono)
    func textToSpeech(_ text: String, voice: GeminiVoice? = nil) async throws -> Data {
        guard let apiKey = apiKeyManager.apiKey, !apiKey.isEmpty else {
            throw GeminiClientError.missingAPIKey
        }

        let voiceToUse = voice ?? selectedVoice
        let url = URL(string: "\(baseURL)/\(ttsModel):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build TTS request
        let content = GeminiRequestContent(
            parts: [GeminiRequestPart(text: text)],
            role: "user"
        )

        // Build speech config with the selected voice
        // IMPORTANT: speechConfig must be INSIDE generationConfig per Gemini API docs
        let speechConfig = GeminiTTSSpeechConfig(
            voiceConfig: GeminiTTSVoiceConfig(
                prebuiltVoiceConfig: GeminiTTSPrebuiltVoiceConfig(voiceName: voiceToUse.rawValue)
            )
        )

        // generationConfig with speechConfig nested inside (correct structure per docs)
        let generationConfig = GeminiRequestGenerationConfig(
            responseModalities: ["AUDIO"],
            speechConfig: speechConfig
        )

        let apiRequest = GeminiAPIRequest(
            contents: [content],
            generationConfig: generationConfig,
            systemInstruction: nil
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(apiRequest)

        // Debug: print the request body to verify structure
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print("[GeminiAPI] TTS request body: \(bodyString.prefix(500))...")
        }

        print("[GeminiAPI] TTS request for \(text.prefix(50))... using voice: \(voiceToUse.rawValue)")

        // Send request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiClientError.invalidResponse
        }

        print("[GeminiAPI] TTS response status: \(httpResponse.statusCode)")

        // Debug: print response if error
        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                print("[GeminiAPI] TTS error response: \(responseString)")
            }
        }

        // Parse response
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(GeminiAPIResponse.self, from: data)

        // Check for API error
        if let error = apiResponse.error {
            throw GeminiClientError.apiError(
                code: error.code ?? -1,
                message: error.message ?? "Unknown error"
            )
        }

        // Extract audio data
        guard let candidate = apiResponse.candidates?.first,
              let content = candidate.content,
              let parts = content.parts,
              let audioPart = parts.first(where: { $0.inlineData?.data != nil }),
              let base64Audio = audioPart.inlineData?.data,
              let audioData = Data(base64Encoded: base64Audio) else {
            throw GeminiClientError.noAudioResponse
        }

        print("[GeminiAPI] TTS audio received: \(ByteCountFormatter.string(fromByteCount: Int64(audioData.count), countStyle: .file))")

        return audioData
    }

    // MARK: - Private Methods

    private func sendRequest(parts: [GeminiRequestPart], systemPrompt: String?) async throws -> String {
        guard let apiKey = apiKeyManager.apiKey, !apiKey.isEmpty else {
            throw GeminiClientError.missingAPIKey
        }

        let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        let content = GeminiRequestContent(parts: parts, role: "user")

        var systemInstruction: GeminiRequestSystemInstruction? = nil
        if let systemPrompt = systemPrompt {
            systemInstruction = GeminiRequestSystemInstruction(
                parts: [GeminiRequestPart(text: systemPrompt)]
            )
        }

        let generationConfig = GeminiRequestGenerationConfig(
            temperature: 0.7,
            maxOutputTokens: 1024,
            topP: 0.95,
            topK: 40
        )

        let apiRequest = GeminiAPIRequest(
            contents: [content],
            generationConfig: generationConfig,
            systemInstruction: systemInstruction
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(apiRequest)

        // Log request size for debugging
        if let bodySize = request.httpBody?.count {
            print("[GeminiAPI] Request size: \(ByteCountFormatter.string(fromByteCount: Int64(bodySize), countStyle: .file))")
        }

        // Send request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiClientError.invalidResponse
        }

        // Log response status
        print("[GeminiAPI] Response status: \(httpResponse.statusCode)")

        // Parse response
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(GeminiAPIResponse.self, from: data)

        // Check for API error
        if let error = apiResponse.error {
            throw GeminiClientError.apiError(
                code: error.code ?? -1,
                message: error.message ?? "Unknown error"
            )
        }

        // Extract text response
        guard let candidate = apiResponse.candidates?.first,
              let content = candidate.content,
              let parts = content.parts,
              let textPart = parts.first(where: { $0.text != nil }),
              let text = textPart.text else {
            throw GeminiClientError.noTextResponse
        }

        return text
    }
}

// MARK: - Error Types

enum GeminiClientError: Error, LocalizedError {
    case missingAPIKey
    case imageEncodingFailed
    case audioEncodingFailed
    case noContent
    case invalidResponse
    case noTextResponse
    case noAudioResponse
    case apiError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key not configured"
        case .imageEncodingFailed:
            return "Failed to encode image"
        case .audioEncodingFailed:
            return "Failed to encode audio"
        case .noContent:
            return "No content provided"
        case .invalidResponse:
            return "Invalid response from server"
        case .noTextResponse:
            return "No text in response"
        case .noAudioResponse:
            return "No audio in response"
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        }
    }
}
