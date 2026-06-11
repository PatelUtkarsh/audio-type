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
  // Key-presence cache. resolve() and anyEngineAvailable run on every hotkey
  // press; without the cache each press paid up to four Keychain XPC
  // round-trips. Every key write goes through the engines' setApiKey /
  // clearApiKey, which call invalidateCache(). Accessed from the main thread
  // only (TranscriptionManager, AppDelegate, Settings/Onboarding UI).
  private static var cachedGroqConfigured: Bool?
  private static var cachedOpenAIConfigured: Bool?

  /// Platform capability; cannot change while the process runs.
  private static let appleSpeechSupported = AppleSpeechEngine.isSupported

  /// Drop cached key-presence. Called whenever an API key is saved or
  /// cleared, and from TranscriptionManager.onEngineConfigChanged().
  static func invalidateCache() {
    cachedGroqConfigured = nil
    cachedOpenAIConfigured = nil
  }

  private static var groqConfigured: Bool {
    if let cached = cachedGroqConfigured { return cached }
    let configured = GroqEngine.isConfigured
    cachedGroqConfigured = configured
    return configured
  }

  private static var openAIConfigured: Bool {
    if let cached = cachedOpenAIConfigured { return cached }
    let configured = OpenAIEngine.isConfigured
    cachedOpenAIConfigured = configured
    return configured
  }

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
      if groqConfigured {
        return GroqEngine()
      }
      if openAIConfigured {
        return OpenAIEngine()
      }
      return AppleSpeechEngine()
    }
  }

  /// `true` when at least one engine is usable.
  static var anyEngineAvailable: Bool {
    groqConfigured
      || openAIConfigured
      || appleSpeechSupported
  }
}
