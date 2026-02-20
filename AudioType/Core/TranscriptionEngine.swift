import Foundation

// MARK: - Engine Type

/// User-facing choice for which transcription backend to use.
enum TranscriptionEngineType: String, CaseIterable, Identifiable {
  case auto
  case groq
  case openAI
  case appleSpeech

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .auto: return "Auto (recommended)"
    case .groq: return "Groq Whisper (cloud)"
    case .openAI: return "OpenAI Whisper (cloud)"
    case .appleSpeech: return "Apple Speech (on-device)"
    }
  }

  static var current: TranscriptionEngineType {
    get {
      if let saved = UserDefaults.standard.string(
        forKey: "transcriptionEngine"),
        let engine = TranscriptionEngineType(rawValue: saved) {
        return engine
      }
      return .auto
    }
    set {
      UserDefaults.standard.set(
        newValue.rawValue, forKey: "transcriptionEngine"
      )
    }
  }
}

// MARK: - Transcription Engine Protocol

/// Common interface for all speech-to-text backends.
protocol TranscriptionEngine {
  /// Human-readable name shown in logs and UI.
  var displayName: String { get }

  /// Whether this engine is ready to accept transcription requests right now.
  var isAvailable: Bool { get }

  /// Transcribe 16 kHz mono Float32 PCM samples into text.
  func transcribe(samples: [Float]) async throws -> String
}

// MARK: - Engine Resolver

/// Decides which concrete engine to use based on user preference and availability.
enum EngineResolver {
  /// Returns the engine to use for the current transcription request.
  static func resolve() -> TranscriptionEngine {
    let preference = TranscriptionEngineType.current

    switch preference {
    case .groq:
      return GroqEngine()
    case .openAI:
      return OpenAIEngine()
    case .appleSpeech:
      return AppleSpeechEngine()
    case .auto:
      // Prefer Groq, then OpenAI, then Apple Speech.
      if GroqEngine.isConfigured {
        return GroqEngine()
      }
      if OpenAIEngine.isConfigured {
        return OpenAIEngine()
      }
      return AppleSpeechEngine()
    }
  }

  /// `true` when at least one engine is usable.
  static var anyEngineAvailable: Bool {
    GroqEngine.isConfigured
      || OpenAIEngine.isConfigured
      || AppleSpeechEngine.isSupported
  }
}
