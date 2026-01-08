# Smart Glasses - Claude Context File

## Project Type
iOS Swift app for Meta Ray-Ban smart glasses using Meta Wearables SDK (MWDATCore, MWDATCamera)

## Core Architecture

```
App Entry: Smart_GlassesApp.swift → ContentView.swift → FullScreenStreamView.swift
                                                              ↓
                                          ┌─────────────────────────────────────┐
                                          │  WearablesManager (singleton)       │
                                          │  - Manages device connection        │
                                          │  - Handles video frames             │
                                          │  - Routes to processors by mode     │
                                          └─────────────────────────────────────┘
                                                              ↓
                    ┌─────────────────────┬─────────────────────┬─────────────────────┐
                    ↓                     ↓                     ↓                     ↓
              Live View             Object Tracking        Text Reader          AI Assistant
              (passthrough)         (saliency-based)       (not impl)          (OpenAI Realtime)
```

## Key Managers & Singletons

| Class | File | Purpose |
|-------|------|---------|
| `WearablesManager.shared` | WearablesManager.swift | Central hub: device connection, stream control, mode switching, frame routing |
| `OpenAIVoiceAssistant.shared` | OpenAIRealtime/OpenAIVoiceAssistant.swift | AI Assistant: push-to-talk, WebSocket streaming, real-time audio |
| `OpenAIRealtimeClient` | OpenAIRealtime/OpenAIRealtimeClient.swift | WebSocket client for OpenAI Realtime API |
| `OpenAIAPIKeyManager.shared` | OpenAIRealtime/OpenAIAPIKeyManager.swift | Keychain storage for OpenAI API key |
| `ObjectDetectionProcessor` | ObjectDetection/ObjectDetectionProcessor.swift | Vision framework saliency detection |
| `VoiceFeedbackManager.shared` | Audio/VoiceFeedbackManager.swift | iOS TTS for detection announcements |

## Streaming Modes (WearablesManager.currentMode)

```swift
enum StreamingMode {
    case liveView        // Raw video only
    case objectDetection // Saliency tracking with bounding boxes
    case textReader      // OCR (not implemented)
    case aiAssistant     // OpenAI Realtime voice assistant
}
```

## AI Assistant Flow (OpenAI Realtime API)

```
User taps mic → startRecording() → connects WebSocket if needed
                        ↓
        OpenAIRealtimeClient.connect()
        wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview
                        ↓
        session.created → session.update (configure voice, modalities)
                        ↓
        AVAudioEngine captures 24kHz PCM → stream via input_audio_buffer.append
                        ↓
User taps again → stopRecordingAndSend()
                        ↓
        [Optional: conversation.item.create with image if photo captured]
                        ↓
        input_audio_buffer.commit → response.create
                        ↓
        response.audio.delta (streaming audio chunks) → AVAudioEngine playback
                        ↓
        response.done → return to idle
```

## Object Tracking Flow

```
VideoFrame → ObjectDetectionProcessor.processFrame()
                    ↓
    VNGenerateAttentionBasedSaliencyImageRequest
                    ↓
    extractSalientRegions() → TrackedObject[]
                    ↓
    DetectionResult(trackedObjects:) → DetectionOverlayView
                    ↓
    TrackingBoxView (colored bounding boxes, no labels)
```

## Key Data Models

```swift
// Object Tracking
struct TrackedObject { boundingBox: CGRect, saliency: Float, trackingLabel: String, colorIndex: Int }
struct DetectionResult { objects: [DetectedObject], trackedObjects: [TrackedObject], isTrackingMode: Bool }

// Voice Assistant States
enum VoiceAssistantState { idle, recording, processing, speaking, error(String) }

// OpenAI Voices
enum OpenAIVoice { alloy, ash, ballad, coral, echo, sage, shimmer, verse }
```

## File Structure

```
Smart Glasses/
├── Smart_GlassesApp.swift          # App entry, URL handling
├── ContentView.swift               # Main settings/controls
├── FullScreenStreamView.swift      # Video display + overlays
├── WearablesManager.swift          # Central manager, StreamingMode enum
├── WearablesConfig.swift           # SDK initialization
│
├── ObjectDetection/
│   ├── ObjectDetectionProcessor.swift  # VNGenerateAttentionBasedSaliencyImageRequest
│   ├── DetectionResult.swift           # TrackedObject, DetectedObject, DetectionResult
│   └── DetectionConfiguration.swift    # FocusArea (legacy), config options
│
├── OpenAIRealtime/
│   ├── OpenAIVoiceAssistant.swift      # Main assistant: WebSocket, record, stream, playback
│   ├── OpenAIRealtimeClient.swift      # WebSocket client for Realtime API
│   ├── OpenAIAPIKeyManager.swift       # Keychain storage for API key
│   └── OpenAIMessageModels.swift       # Codable event types for API
│
├── Views/
│   ├── AIAssistantOverlayView.swift    # Speak button, camera button, status
│   ├── DetectionOverlayView.swift      # TrackingBoxView, TrackingBadge
│   └── ...
│
└── Audio/
    └── VoiceFeedbackManager.swift      # AVSpeechSynthesizer for detection
```

## OpenAI Realtime API

```
# WebSocket Connection
wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17
Headers: Authorization: Bearer <API_KEY>, OpenAI-Beta: realtime=v1

# Key Client Events
- session.update: Configure voice, modalities, turn_detection
- input_audio_buffer.append: Stream audio chunks (base64 PCM)
- input_audio_buffer.commit: Signal end of user speech
- conversation.item.create: Add text/image to conversation
- response.create: Trigger AI response

# Key Server Events
- session.created/updated: Session configuration confirmed
- response.audio.delta: Streaming audio response (base64 PCM)
- response.audio_transcript.delta: Real-time transcription
- response.done: Response complete
- error: Error information
```

## Audio Formats

| Context | Format |
|---------|--------|
| Recording (mic input) | PCM 24kHz 16-bit mono |
| OpenAI audio output | PCM 24kHz 16-bit mono |
| Playback | AVAudioEngine with AVAudioPlayerNode |

## UI Components (AIAssistantOverlayView.swift)

```
┌─────────────────────────────────────────┐
│ [AssistantStatusBadge]  [PhotoQueuedBadge] │  ← Top
│                                         │
│         [LastResponseView]              │  ← Shows last AI response
│                                         │
│    [VisionCaptureButton] [MainSpeakButton] │  ← Bottom controls
└─────────────────────────────────────────┘

MainSpeakButton states:
- idle (green): "Tap to Speak"
- recording (red): "Tap to Send"
- processing (yellow): spinner
- speaking (purple): "Speaking..."
```

## Key Patterns

1. **Singletons**: WearablesManager.shared, OpenAIVoiceAssistant.shared, OpenAIAPIKeyManager.shared
2. **@MainActor**: All managers are MainActor for UI updates
3. **Combine**: @Published properties, sink subscriptions for state changes
4. **async/await**: Audio processing, state management
5. **WebSocket**: Real-time bidirectional audio streaming
6. **Vision framework**: VNImageRequestHandler, VNGenerateAttentionBasedSaliencyImageRequest

## Dependencies

- MWDATCore, MWDATCamera (Meta Wearables SDK)
- AVFoundation (audio record/playback)
- Vision (object tracking)
- Security (Keychain for API key)

## Architecture Decisions

1. **OpenAI Realtime API** → WebSocket for real-time bidirectional audio
2. **No continuous video streaming** → Photo capture on-demand
3. **Push-to-talk audio** → turn_detection: "none" (not continuous listening)
4. **Saliency-based tracking** → Not classification (no labels, just bounding boxes)
5. **Streaming audio playback** → Play audio chunks as they arrive
6. **Fallback TTS** → iOS AVSpeechSynthesizer if OpenAI fails

## Common Tasks

| Task | Location |
|------|----------|
| Add new streaming mode | WearablesManager.StreamingMode enum |
| Modify AI prompt | OpenAIVoiceAssistant.systemPrompt |
| Change TTS voice | OpenAIVoiceAssistant.selectedVoice |
| Adjust tracking sensitivity | ObjectDetectionProcessor.saliencyThreshold (default 0.3) |
| Handle new WebSocket events | OpenAIRealtimeClient.parseTextMessage() |
