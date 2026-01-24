This Markdown file is designed to provide **Claude Code** (or any AI coding agent) with a technical reference for the **Foundation Models framework** introduced at WWDC25, based on the provided sources.

***

# Technical Reference: Apple Foundation Models Framework

## Overview
The Foundation Models framework provides direct access to the on-device large language models (LLMs) that power Apple Intelligence. It uses a powerful Swift API to integrate generative AI features directly into apps, ensuring user data remains private and works entirely offline.

## 1. Requirements & Availability
To use the framework, the project must target **macOS Sequoia (15.0)** or **iOS 18.0** (referred to in transcripts as macOS Tahoe/iOS 26) using **Xcode 16+** on **Apple silicon**.

### Handling Availability
Before invoking the model, you must check its status using the availability API.
```swift
let model = systemLanguageModel.default
let status = model.availability

switch status {
case .available:
    // Green light to proceed
case .unavailable(.deviceNotEligible):
    // Hide generative UI; device doesn't support Apple Intelligence
case .unavailable(.appleIntelligenceNotEnabled):
    // Prompt the user to enable Apple Intelligence in Settings
case .unavailable(.modelNotReady):
    // Model assets are still downloading; tell the user to try again later
}
```

## 2. Language Model Sessions
The framework is built around **stateful sessions** that maintain a transcript of the conversation.

### Initialization & Instructions
Instructions define the **persona and rules** for the session and are maintained throughout its life.
```swift
let instructions = InstructionBuilder { 
    "Your job is to create an itinerary for the user."
    "Always include a title and a day-by-day plan."
}

let session = LanguageModelSession(instructions: instructions)
```

## 3. Generating Output
### Basic Text Generation
Use the `respond(to:)` method for simple string outputs.
```swift
let response = try await session.respond(to: "Generate a 3-day itinerary to Paris")
print(response.content) // Access the unstructured string output
```

### Guided Generation (Structured Output)
To get type-safe Swift data, apply the **`@Generable`** macro to a struct. This uses **constraint decoding** to guarantee structural correctness.
```swift
@Generable
struct Itinerary {
    var title: String
    @Schema(description: "A short description")
    var description: String
    var days: [DayPlan]
}

// Requesting structured data
let response = try await session.respond(
    to: prompt, 
    generating: Itinerary.self
)
let itinerary: Itinerary = response.content
```

## 4. Streaming Responses
For a more responsive UI, use the **Streaming API** to receive tokens as they are generated. When streaming structured data, the framework provides a **`PartiallyGenerated`** version of your struct where all properties are optional.

```swift
let stream = session.streamResponse(to: prompt, generating: Itinerary.self)

for try await partialResponse in stream {
    if let currentItinerary = partialResponse.content {
        // Update UI in real-time with unwrapped optional fields
    }
}
```

## 5. Tool Calling
Tools allow the model to access custom functions or real-time data.
1.  **Define the Tool**: Create a class conforming to the `Tool` protocol.
2.  **Define Arguments**: Use a `@Generable` struct for the tool's inputs.
3.  **Implement `call()`**: Perform the logic and return a string to the session transcript.

```swift
let session = LanguageModelSession(
    instructions: instructions,
    tools: [MyCustomTool()] // Pass tools to the session
)
```

## 6. Prompting Techniques
*   **PromptBuilder**: Use for dynamic prompts that include Swift conditionals based on user preferences.
*   **One-Shot Prompting**: Include a high-quality example of your `@Generable` type directly in the prompt to guide the model's tone and style.

## 7. Performance Optimizations
*   **Pre-warming**: Call `session.prewarm()` (optionally with a `promptPrefix`) to load the model into memory before the user submits a request.
*   **Greedy Sampling**: Set sampling to `.greedy` in `GenerationOptions` for deterministic, predictable output, especially during tool calling.
*   **Schema Optimization**: If a one-shot example is provided, set `includeSchemaInPrompt` to `false` to reduce the input token count and speed up processing.

***

**Note:** This information is drawn from the provided WWDC25 session transcripts regarding the Foundation Models framework. For features like guardrails, training custom adapters, or error handling, refer to additional Apple Developer documentation.
