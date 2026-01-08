//
//  OpenAIVisionClient.swift
//  Smart Glasses
//
//  REST API client for GPT-4o Vision (image analysis)
//  Used as a workaround since Realtime API doesn't support images yet
//

import Foundation
import UIKit

/// Client for OpenAI Vision API (REST) to analyze images
class OpenAIVisionClient {

    private let apiKeyManager = OpenAIAPIKeyManager.shared
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o"

    /// Analyze an image and return a description
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - prompt: Optional prompt to guide the analysis
    /// - Returns: Description of the image
    func analyzeImage(_ image: UIImage, prompt: String? = nil) async throws -> String {
        guard let apiKey = apiKeyManager.apiKey else {
            throw VisionError.noAPIKey
        }

        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw VisionError.imageEncodingFailed
        }

        let base64Image = imageData.base64EncodedString()
        let dataUrl = "data:image/jpeg;base64,\(base64Image)"

        let systemPrompt = """
        You are a vision assistant for smart glasses. Describe what you see concisely but thoroughly. \
        Focus on: people, objects, text, signs, potential hazards, and anything notable. \
        Be specific about positions (left, right, center, near, far). \
        Keep descriptions under 100 words unless there's a lot of important detail.
        """

        let userPrompt = prompt ?? "What do you see in this image?"

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPrompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": dataUrl,
                                "detail": "low"  // Use low detail for faster response
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 300
        ]

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw VisionError.apiError(message)
            }
            throw VisionError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw VisionError.invalidResponse
        }

        return content
    }
}

// MARK: - Errors

enum VisionError: LocalizedError {
    case noAPIKey
    case imageEncodingFailed
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .imageEncodingFailed:
            return "Failed to encode image"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let message):
            return message
        }
    }
}
