# Ray-Ban Meta - NoteBuddy

A powerful iOS application for Ray-Ban Meta smart glasses that transforms physical documents into AI-summarized study cards. Scan documents hands-free through your smart glasses, extract text with OCR, generate intelligent summaries using Apple's Foundation Models on-device Apple Intelligence, and organize content into study decks. Because the app utilizes Apple's Foundation Models On Device LLM; this app does not require a internet connection.

## Features

### Document Scanning
- **Hands-Free Scanning**: Use Meta Ray-Ban smart glasses camera for document capture
- **Auto-Capture Mode**: Automatically detects document boundaries and captures when stable
- **Multi-Page Support**: Scan multiple pages and combine them into a single summary
- **Real-Time Boundary Detection**: Visual overlay shows detected document edges
- **Distance Mode**: Enhanced OCR processing for normal reading distance scanning
- **Perspective Correction**: Automatic skew correction for angled documents

### AI-Powered Summarization
- **On-Device Processing**: Uses Apple Foundation Models for privacy-preserving summarization
- **Streaming Output**: Watch summaries generate in real-time, token by token
- **Smart Extraction**: Automatically generates titles, summaries, and key points
- **Document Classification**: Identifies document type (article, letter, receipt, etc.)
- **Fallback Support**: Graceful degradation on devices without Foundation Models

### Study Organization
- **Deck Management**: Organize cards into color-coded study decks
- **Quick Capture**: Save cards without assigning to a deck for later organization
- **Card Carousel**: Swipe through cards in a deck with playback controls
- **Text-to-Speech**: Listen to summaries through glasses speakers via Bluetooth
- **Search & Filter**: Find cards across all decks

### Audio Feedback
- **Haptic & Audio Cues**: Feedback for capture success, stability progress, and errors
- **Bluetooth A2DP**: Audio plays through smart glasses speakers when connected
- **Voice Announcements**: Status updates and card content read aloud

---

## Requirements

- **-> iOS 26+ for Foundation Models AI summarization)
- **Meta Ray-Ban Smart Glasses** (required for scanning)
- **Download Meta AI App (required to allow NoteBuddy to access the glasses)
- **Xcode 15+** for building

### Dependencies
| Dependency | Purpose |
|------------|---------|
| `MWDATCore` / `MWDATCamera` | Meta Wearables SDK |
| `SwiftUI` / `SwiftData` | UI and persistence |
| `Vision` | Document detection and OCR |
| `CoreImage` | Image processing |
| `FoundationModels` | On-device AI (iOS 26+) |
| `AVFoundation` | Audio/Speech synthesis |

---

## Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/smart-glasses.git
cd smart-glasses
```

### 2. Put Meta AI App into Developer Mode
-On your iOS or Android device, select Settings > App Info, and then tap the App version number five times to display the toggle for developer mode.
-Select the toggle to enable Developer Mode.
-Click Enable to confirm.

### 3. Open in Xcode
```bash
open "Smart Glasses.xcodeproj"
```

### 4. Configure Signing
- Select the project in Xcode
- Navigate to Signing & Capabilities
- Select your development team

### 5. Build and Run
- Connect your iOS device
- Select your device as the build target
- Press `Cmd + R` to build and run

---

## How to Use

### Initial Setup

1. **Launch the App** - Open Smart Glasses on your iPhone
2. **Connect Glasses** - Navigate to the Settings tab and tap "Connect Glasses"
3. **Complete Registration** - Follow the prompts on your Meta Ray-Ban glasses
4. **Grant Permissions** - Allow camera access when prompted

### Scanning Documents

1. **Open Scanner** - Tap the Scan tab (viewfinder icon)
2. **Point at Document** - Hold a document in view of your glasses
3. **Wait for Detection** - A cyan boundary appears around detected documents
4. **Hold Steady** - The progress ring fills as you hold still
5. **Auto-Capture** - Document captures automatically when stable (or tap Manual Capture)

### Multi-Page Scanning

1. **Scan First Page** - Follow standard scanning process
2. **Add Page** - Tap "Add Page" to include and continue
3. **Scan Additional Pages** - Repeat for all pages
4. **Finish** - Tap "Done" to combine and summarize all pages
5. **Skip** - Tap "Skip" to discard current page without adding

### Saving Cards

1. **Review Summary** - Check the generated title, summary, and key points
2. **Save Card** - Tap "Save Card" to open deck selector
3. **Choose Deck** - Select an existing deck or create new
4. **Confirm** - Tap "Save" to persist the card

### Managing Decks

1. **View Library** - Tap the Library tab (books icon)
2. **Browse Decks** - Scroll through your deck grid
3. **Open Deck** - Tap a deck to view its cards
4. **Navigate Cards** - Swipe or use arrow buttons to browse
5. **Listen** - Tap play button to hear card content

---

## Settings

### Ray-Ban Meta Glasses
| Setting | Description |
|---------|-------------|
| Status | Connection status indicator (green/yellow/red) |
| Registration | Registration state with glasses |
| Stream | Video streaming status |
| Connect/Disconnect | Manage glasses pairing |
| Start/Stop Stream | Control video feed |

### Scanning Options
| Setting | Default | Description |
|---------|---------|-------------|
| Distance Mode | ON | Enhanced processing for normal reading distance |
| Auto-Summarize | ON | Automatically generate AI summary after capture |
| Speak Summaries | OFF | Read summaries aloud via TTS |

---

## Architecture

### High-Level Overview

```
+------------------------------------------------------------------+
|                      Smart Glasses App                            |
+------------------------------------------------------------------+
|                                                                   |
|   +---------------+   +---------------+   +---------------+       |
|   |    Library    |   |     Scan      |   |   Settings    |       |
|   |      Tab      |   |      Tab      |   |      Tab      |       |
|   +-------+-------+   +-------+-------+   +-------+-------+       |
|           |                   |                   |               |
|   +-------v-------+   +-------v-------+   +-------v-------+       |
|   |  DeckLibrary  |   |LibraryScanner |   | SettingsView  |       |
|   |     View      |   |     View      |   |               |       |
|   +-------+-------+   +-------+-------+   +---------------+       |
|           |                   |                                   |
|   +-------v-------+   +-------v-------+                           |
|   |  DeckDetail   |   |   Document    |                           |
|   |     View      |   |   Boundary    |                           |
|   |               |   |   Overlay     |                           |
|   +---------------+   +---------------+                           |
|                                                                   |
+------------------------------------------------------------------+
|                          SERVICES                                 |
|   +---------------+   +---------------+   +---------------+       |
|   |  Wearables    |   |   Document    |   |  Streaming    |       |
|   |   Manager     |<--|    Reader     |-->|  Summarizer   |       |
|   |  (glasses)    |   |   Processor   |   |     (AI)      |       |
|   +-------+-------+   +-------+-------+   +-------+-------+       |
|           |                   |                   |               |
|   +-------v-------+   +-------v-------+   +-------v-------+       |
|   |   Meta SDK    |   |    Vision     |   |  Foundation   |       |
|   |  MWDATCamera  |   |   Framework   |   |    Models     |       |
|   +---------------+   +---------------+   +---------------+       |
|                                                                   |
+------------------------------------------------------------------+
|                        DATA LAYER                                 |
|   +-----------------------------------------------------+         |
|   |                     SwiftData                        |         |
|   |   +--------------+           +--------------+        |         |
|   |   | SummaryDeck  |<--------->| SummaryCard  |        |         |
|   |   +--------------+           +--------------+        |         |
|   +-----------------------------------------------------+         |
+------------------------------------------------------------------+
```

### Core Components

#### Entry Point
- **`Smart_GlassesApp.swift`** - App initialization, SwiftData container, URL handling

#### Views
| View | Purpose |
|------|---------|
| `MainTabView.swift` | Three-tab navigation (Library, Scan, Settings) |
| `DeckLibraryView.swift` | Deck grid with stats and quick capture section |
| `DeckDetailView.swift` | Card carousel with playback controls |
| `LibraryScannerView.swift` | Full scanner interface with auto-capture |
| `SettingsView.swift` | Glasses connection and app preferences |
| `DocumentBoundaryOverlay.swift` | Real-time boundary visualization |
| `CardPreviewSheet.swift` | Deck selector and card preview |

#### Services
| Service | Purpose |
|---------|---------|
| `WearablesManager.swift` | Meta glasses connection hub (singleton) |
| `DocumentReaderProcessor.swift` | Document detection and OCR engine |
| `StreamingSummarizer.swift` | AI summarization with Foundation Models |
| `VoiceFeedbackManager.swift` | Audio/haptic feedback system (singleton) |

#### Models
| Model | Purpose |
|-------|---------|
| `SummaryCard.swift` | Study card with summary, key points, source text |
| `SummaryDeck.swift` | Collection of cards with color theming |
| `DocumentReadingResult.swift` | OCR result structures |

---

## Document Processing Pipeline

```
Video Frame (from Smart Glasses)
         |
         v
+-------------------------+
|  Document Detection     |  VNDetectDocumentSegmentationRequest
|  (boundary detection)   |
+-----------+-------------+
            |
            v
+-------------------------+
|  Perspective Correction |  CIPerspectiveCorrection filter
|  (skew removal)         |
+-----------+-------------+
            |
            v
+-------------------------+
|  Image Enhancement      |  CISharpenLuminance
|  (Distance Mode only)   |  CIColorControls (contrast)
|                         |  CIUnsharpMask
+-----------+-------------+
            |
            v
+-------------------------+
|  Text Recognition       |  VNRecognizeTextRequest
|  (OCR)                  |  .accurate recognition level
+-----------+-------------+
            |
            v
+-------------------------+
|  AI Summarization       |  LanguageModelSession (Foundation Models)
|  (on-device)            |  or fallback heuristic parsing
+-----------+-------------+
            |
            v
     SummaryCard (saved to SwiftData)
```

---

## Data Models

### SummaryCard
```swift
@Model
final class SummaryCard {
    var id: UUID
    var title: String              // AI-generated or user title
    var summary: String            // 1-3 sentence summary
    var keyPoints: [String]        // 3-5 extracted key points
    var sourceText: String         // Original OCR text
    var pageNumber: Int?           // For multi-page documents
    var thumbnailData: Data?       // JPEG thumbnail
    var createdAt: Date
    var deck: SummaryDeck?         // Optional deck relationship
}
```

### SummaryDeck
```swift
@Model
final class SummaryDeck {
    var id: UUID
    var title: String
    var deckDescription: String?
    var colorHex: String           // UI color theme
    var cards: [SummaryCard]       // @Relationship(deleteRule: .cascade)
    var createdAt: Date
    var lastAccessedAt: Date
    var isQuickCapture: Bool
}
```

---

## File Structure

```
Smart Glasses/
|-- Smart_GlassesApp.swift              # App entry point
|-- WearablesConfig.swift               # Meta SDK configuration
|-- WearablesManager.swift              # Glasses connection manager
|-- Smart-Glasses-Info.plist            # App configuration
|
|-- Models/
|   |-- SummaryCard.swift               # Card data model
|   +-- SummaryDeck.swift               # Deck data model
|
|-- Views/
|   |-- MainTabView.swift               # Tab navigation
|   |-- SettingsView.swift              # Settings screen
|   |-- DocumentBoundaryOverlay.swift   # Scanning overlay
|   |
|   |-- DeckLibrary/
|   |   |-- DeckLibraryView.swift       # Library grid
|   |   |-- DeckDetailView.swift        # Card carousel
|   |   +-- LibraryScannerView.swift    # Scanner interface
|   |
|   +-- DocumentScanner/
|       +-- CardPreviewSheet.swift      # Save card sheet
|
|-- DocumentReader/
|   |-- DocumentReaderProcessor.swift   # OCR engine
|   +-- DocumentReadingResult.swift     # Result models
|
|-- Services/
|   +-- StreamingSummarizer.swift       # AI summarization
|
|-- Audio/
|   +-- VoiceFeedbackManager.swift      # TTS & feedback
|
+-- Assets.xcassets/                    # App resources
```

---

## Configuration

### Distance Mode Settings
| Parameter | Distance Mode | Close-up Mode |
|-----------|---------------|---------------|
| `maxProcessingDimension` | 3500px | 2000px |
| `sharpeningIntensity` | 0.5 | 0.0 |
| `contrastMultiplier` | 1.15 | 1.0 |
| `textConfidenceThreshold` | 0.2 | 0.3 |
| `minimumTextLines` | 2 | 3 |
| `minimumCharacters` | 30 | 50 |

### Auto-Capture Settings
| Parameter | Value | Description |
|-----------|-------|-------------|
| `stableFramesRequired` | 8 | Consecutive stable frames needed |
| `stabilityThreshold` | 0.03 | Max movement allowed (fraction) |
| `detectionFrameSkip` | 3 | Process every Nth frame |
| `documentConfidenceThreshold` | 0.5 | Minimum detection confidence |

---

## Permissions

The app requires the following permissions configured in `Info.plist`:

| Permission | Usage |
|------------|-------|
| Bluetooth | Connect to Meta smart glasses |
| Camera | Document detection and scanning |
| Microphone | Voice commands (optional) |
| Photo Library | Save captured images |
| Siri | Voice shortcuts integration |

### Background Modes
- `audio` - Bluetooth A2DP audio
- `bluetooth-peripheral` - Wearable connection
- `external-accessory` - Meta glasses communication

---

## Troubleshooting

### Glasses Won't Connect
1. Ensure glasses are powered on and in range
2. Check Bluetooth is enabled on iPhone
3. Try "Disconnect Glasses" then "Connect Glasses"
4. Restart the Meta View app if installed

### Poor OCR Results
1. Enable Distance Mode in Settings
2. Ensure adequate lighting
3. Hold document steady until green indicator
4. Try moving slightly closer to the document

### AI Summarization Not Working
- Foundation Models require iOS 26+ and Apple Intelligence enabled
- Check Settings > Apple Intelligence & Siri > Apple Intelligence
- The app falls back to basic summarization on unsupported devices

### No Audio Through Glasses
1. Verify glasses are connected via Bluetooth A2DP
2. Check iPhone audio output is set to glasses
3. Ensure "Speak Summaries" is enabled in Settings

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Meta Wearables SDK team for glasses integration
- Apple Vision framework for OCR capabilities
- Apple Foundation Models for on-device AI
- SwiftUI and SwiftData teams for modern iOS development tools

---

## Version History

- **1.0.0** - Initial release
  - Document scanning with Meta smart glasses
  - AI-powered summarization with Foundation Models
  - Study deck organization with SwiftData
  - Multi-page scanning support
  - Distance mode for optimal OCR
  - Audio feedback through glasses speakers
