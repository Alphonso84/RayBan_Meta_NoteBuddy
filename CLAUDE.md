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
              (passthrough)         (saliency-based)       (not impl)          (Gemini REST)
```

## Key Managers & Singletons

| Class | File | Purpose |
|-------|------|---------|
| `WearablesManager.shared` | WearablesManager.swift | Central hub: device connection, stream control, mode switching, frame routing |
| `GeminiVoiceAssistant.shared` | GeminiLive/GeminiVoiceAssistant.swift | AI Assistant: push-to-talk, record→send→TTS response |
| `GeminiAPIClient.shared` | GeminiLive/GeminiAPIClient.swift | REST API: text/image/audio→Gemini, TTS |
| `ObjectDetectionProcessor` | ObjectDetection/ObjectDetectionProcessor.swift | Vision framework saliency detection |
| `VoiceFeedbackManager.shared` | Audio/VoiceFeedbackManager.swift | iOS TTS for detection announcements |

## Streaming Modes (WearablesManager.currentMode)

```swift
enum StreamingMode {
    case liveView        // Raw video only
    case objectDetection // Saliency tracking with bounding boxes
    case textReader      // OCR (not implemented)
    case aiAssistant     // Gemini voice assistant
}
```

## AI Assistant Flow (Meta Ray-Bans style)

```
User taps mic → startRecording() → records WAV 16kHz mono
User taps again → stopRecordingAndSend()
                        ↓
        [Optional: capturedPhoto if user tapped camera]
                        ↓
        GeminiAPIClient.sendMultimodalMessage() or sendAudioMessage()
        POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent
                        ↓
        Text response → GeminiAPIClient.textToSpeech()
        POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent
                        ↓
        24kHz PCM audio → AVAudioEngine playback
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

// Gemini Voices
enum GeminiVoice { puck, charon, kore, fenrir, aoede, leda, orus, zephyr }
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
├── GeminiLive/
│   ├── GeminiVoiceAssistant.swift      # Main assistant: record, send, play TTS
│   ├── GeminiAPIClient.swift           # REST API: generateContent, TTS
│   ├── GeminiAPIKeyManager.swift       # Keychain storage for API key
│   ├── GeminiLiveManager.swift         # LEGACY WebSocket (not used)
│   ├── GeminiWebSocketClient.swift     # LEGACY
│   ├── GeminiFrameEncoder.swift        # LEGACY
│   ├── GeminiMicrophoneCapture.swift   # LEGACY
│   ├── GeminiAudioPlayer.swift         # LEGACY
│   └── GeminiMessageModels.swift       # LEGACY
│
├── Views/
│   ├── AIAssistantOverlayView.swift    # Speak button, camera button, status
│   ├── DetectionOverlayView.swift      # TrackingBoxView, TrackingBadge
│   └── ...
│
└── Audio/
    └── VoiceFeedbackManager.swift      # AVSpeechSynthesizer for detection
```

## API Endpoints

```
# Gemini 2.5 Flash (multimodal understanding)
POST /v1beta/models/gemini-2.5-flash:generateContent
- Input: { contents: [{ parts: [{ text }, { inlineData: { mimeType, data:base64 } }] }] }
- Output: { candidates: [{ content: { parts: [{ text }] } }] }

# Gemini TTS
POST /v1beta/models/gemini-2.5-flash-preview-tts:generateContent
- Input: { contents, generationConfig: { responseModalities: ["AUDIO"], speechConfig: { voiceConfig } } }
- Output: { candidates: [{ content: { parts: [{ inlineData: { data: base64_pcm } }] } }] }

# Auth: ?key=API_KEY or x-goog-api-key header
```

## Audio Formats

| Context | Format |
|---------|--------|
| Recording (mic input) | WAV 16kHz 16-bit mono |
| Gemini TTS output | PCM 24kHz 16-bit mono |
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

1. **Singletons**: WearablesManager.shared, GeminiVoiceAssistant.shared, GeminiAPIClient.shared
2. **@MainActor**: All managers are MainActor for UI updates
3. **Combine**: @Published properties, sink subscriptions for state changes
4. **async/await**: API calls, audio processing
5. **Vision framework**: VNImageRequestHandler, VNGenerateAttentionBasedSaliencyImageRequest

## Dependencies

- MWDATCore, MWDATCamera (Meta Wearables SDK)
- AVFoundation (audio record/playback)
- Vision (object tracking)
- Security (Keychain for API key)

## Recent Architecture Decisions

1. **Abandoned WebSocket Live API** → REST API for simplicity (Meta Ray-Bans style)
2. **No continuous video streaming** → Photo capture on-demand
3. **Push-to-talk audio** → Not continuous listening
4. **Saliency-based tracking** → Not classification (no labels, just bounding boxes)
5. **Gemini TTS** → High-quality voice (fallback to iOS AVSpeechSynthesizer)

## Common Tasks

| Task | Location |
|------|----------|
| Add new streaming mode | WearablesManager.StreamingMode enum |
| Modify AI prompt | GeminiVoiceAssistant.systemPrompt |
| Change TTS voice | GeminiVoiceAssistant.selectedVoice or GeminiAPIClient.selectedVoice |
| Adjust tracking sensitivity | ObjectDetectionProcessor.saliencyThreshold (default 0.3) |
| Add new Gemini API call | GeminiAPIClient methods |
