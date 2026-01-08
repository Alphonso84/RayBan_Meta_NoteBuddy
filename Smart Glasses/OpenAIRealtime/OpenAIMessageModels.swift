//
//  OpenAIMessageModels.swift
//  Smart Glasses
//
//  Codable message structures for OpenAI Realtime API WebSocket communication
//

import Foundation

// MARK: - Voice Options

/// Available voices for OpenAI Realtime API
enum OpenAIVoice: String, CaseIterable, Identifiable {
    case alloy = "alloy"
    case ash = "ash"
    case ballad = "ballad"
    case coral = "coral"
    case echo = "echo"
    case sage = "sage"
    case shimmer = "shimmer"
    case verse = "verse"

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Client Events (Sent to Server)

/// Session configuration update
struct SessionUpdateEvent: Encodable {
    let type = "session.update"
    let session: SessionConfig
}

struct SessionConfig: Encodable {
    let modalities: [String]
    let instructions: String?
    let voice: String?
    let inputAudioFormat: String?
    let outputAudioFormat: String?
    let inputAudioTranscription: InputAudioTranscription?
    /// Set to nil for push-to-talk (manual mode), or provide TurnDetection for VAD
    let turnDetection: TurnDetection?

    enum CodingKeys: String, CodingKey {
        case modalities, instructions, voice
        case inputAudioFormat = "input_audio_format"
        case outputAudioFormat = "output_audio_format"
        case inputAudioTranscription = "input_audio_transcription"
        case turnDetection = "turn_detection"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modalities, forKey: .modalities)
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encodeIfPresent(voice, forKey: .voice)
        try container.encodeIfPresent(inputAudioFormat, forKey: .inputAudioFormat)
        try container.encodeIfPresent(outputAudioFormat, forKey: .outputAudioFormat)
        try container.encodeIfPresent(inputAudioTranscription, forKey: .inputAudioTranscription)
        // For push-to-talk, encode null explicitly to disable VAD
        if turnDetection == nil {
            try container.encodeNil(forKey: .turnDetection)
        } else {
            try container.encode(turnDetection, forKey: .turnDetection)
        }
    }
}

struct InputAudioTranscription: Encodable {
    let model: String
}

struct TurnDetection: Encodable {
    let type: String  // "server_vad" or "semantic_vad"
}

/// Append audio data to input buffer
struct InputAudioBufferAppendEvent: Encodable {
    let type = "input_audio_buffer.append"
    let audio: String  // base64-encoded PCM audio
}

/// Commit the audio buffer (signal end of user speech)
struct InputAudioBufferCommitEvent: Encodable {
    let type = "input_audio_buffer.commit"
}

/// Clear the audio buffer
struct InputAudioBufferClearEvent: Encodable {
    let type = "input_audio_buffer.clear"
}

/// Create a conversation item (text, audio, or image)
struct ConversationItemCreateEvent: Encodable {
    let type = "conversation.item.create"
    let item: ConversationItem
}

struct ConversationItem: Encodable {
    let type: String  // "message"
    let role: String  // "user" or "assistant"
    let content: [ContentPart]
}

struct ContentPart: Encodable {
    let type: String  // "input_text", "input_audio", "input_image"
    let text: String?
    let audio: String?  // base64
    let imageUrl: String?  // data URL for images (data:image/jpeg;base64,...)

    enum CodingKeys: String, CodingKey {
        case type, text, audio
        case imageUrl = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let text = text {
            try container.encode(text, forKey: .text)
        }
        if let audio = audio {
            try container.encode(audio, forKey: .audio)
        }
        if let imageUrl = imageUrl {
            try container.encode(imageUrl, forKey: .imageUrl)
        }
    }

    /// Create a text content part
    static func text(_ text: String) -> ContentPart {
        ContentPart(type: "input_text", text: text, audio: nil, imageUrl: nil)
    }

    /// Create an audio content part
    static func audio(_ base64Audio: String) -> ContentPart {
        ContentPart(type: "input_audio", text: nil, audio: base64Audio, imageUrl: nil)
    }

    /// Create an image content part with base64 data
    static func image(_ base64Image: String) -> ContentPart {
        // Format as data URL for OpenAI
        let dataUrl = "data:image/jpeg;base64,\(base64Image)"
        return ContentPart(type: "input_image", text: nil, audio: nil, imageUrl: dataUrl)
    }
}

/// Trigger response generation
struct ResponseCreateEvent: Encodable {
    let type = "response.create"
    let response: ResponseConfig?
}

struct ResponseConfig: Encodable {
    let modalities: [String]?
    let instructions: String?
}

/// Cancel an in-progress response
struct ResponseCancelEvent: Encodable {
    let type = "response.cancel"
}

// MARK: - Server Events (Received from Server)

/// Generic server event for initial parsing
struct ServerEventType: Decodable {
    let type: String
}

/// Session created event
struct SessionCreatedEvent: Decodable {
    let type: String
    let eventId: String?
    let session: SessionInfo?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case session
    }
}

struct SessionInfo: Decodable {
    let id: String?
    let voice: String?
    let modalities: [String]?
}

/// Session updated event
struct SessionUpdatedEvent: Decodable {
    let type: String
    let eventId: String?
    let session: SessionInfo?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case session
    }
}

/// Response audio delta event
struct ResponseAudioDeltaEvent: Decodable {
    let type: String
    let eventId: String?
    let responseId: String?
    let itemId: String?
    let outputIndex: Int?
    let contentIndex: Int?
    let delta: String?  // base64-encoded audio

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
    }
}

/// Response audio transcript delta event
struct ResponseAudioTranscriptDeltaEvent: Decodable {
    let type: String
    let eventId: String?
    let responseId: String?
    let itemId: String?
    let outputIndex: Int?
    let contentIndex: Int?
    let delta: String?  // transcript text

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
    }
}

/// Response done event
struct ResponseDoneEvent: Decodable {
    let type: String
    let eventId: String?
    let response: ResponseDoneInfo?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case response
    }
}

struct ResponseDoneInfo: Decodable {
    let id: String?
    let status: String?  // "completed", "cancelled", "failed", "incomplete"
    let statusDetails: StatusDetails?

    enum CodingKeys: String, CodingKey {
        case id, status
        case statusDetails = "status_details"
    }
}

struct StatusDetails: Decodable {
    let type: String?
    let reason: String?
    let error: ErrorInfo?
}

/// Error event
struct ErrorEvent: Decodable {
    let type: String
    let eventId: String?
    let error: ErrorInfo?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case error
    }
}

struct ErrorInfo: Decodable {
    let type: String?
    let code: String?
    let message: String?
    let param: String?
}

/// Input audio buffer speech started (for VAD mode)
struct InputAudioBufferSpeechStartedEvent: Decodable {
    let type: String
    let eventId: String?
    let audioStartMs: Int?
    let itemId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case audioStartMs = "audio_start_ms"
        case itemId = "item_id"
    }
}

/// Input audio buffer speech stopped (for VAD mode)
struct InputAudioBufferSpeechStoppedEvent: Decodable {
    let type: String
    let eventId: String?
    let audioEndMs: Int?
    let itemId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case audioEndMs = "audio_end_ms"
        case itemId = "item_id"
    }
}

/// Input audio buffer committed event
struct InputAudioBufferCommittedEvent: Decodable {
    let type: String
    let eventId: String?
    let previousItemId: String?
    let itemId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case previousItemId = "previous_item_id"
        case itemId = "item_id"
    }
}

/// Conversation item created event
struct ConversationItemCreatedEvent: Decodable {
    let type: String
    let eventId: String?
    let previousItemId: String?
    let item: ConversationItemInfo?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case previousItemId = "previous_item_id"
        case item
    }
}

struct ConversationItemInfo: Decodable {
    let id: String?
    let type: String?
    let role: String?
    let status: String?
}

/// Rate limit info
struct RateLimitsUpdatedEvent: Decodable {
    let type: String
    let eventId: String?
    let rateLimits: [RateLimit]?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case rateLimits = "rate_limits"
    }
}

struct RateLimit: Decodable {
    let name: String?
    let limit: Int?
    let remaining: Int?
    let resetSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case name, limit, remaining
        case resetSeconds = "reset_seconds"
    }
}

// MARK: - Response audio done event

struct ResponseAudioDoneEvent: Decodable {
    let type: String
    let eventId: String?
    let responseId: String?
    let itemId: String?
    let outputIndex: Int?
    let contentIndex: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
    }
}
