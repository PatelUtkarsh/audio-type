import Foundation

// MARK: - Groq Model

enum GroqModel: String, CaseIterable {
  case whisperLargeV3Turbo = "whisper-large-v3-turbo"
  case whisperLargeV3 = "whisper-large-v3"

  var displayName: String {
    switch self {
    case .whisperLargeV3Turbo: return "Whisper Large V3 Turbo (faster)"
    case .whisperLargeV3: return "Whisper Large V3 (best, default)"
    }
  }

  static var current: GroqModel {
    get {
      if let saved = UserDefaults.standard.string(forKey: "groqModel"),
        let model = GroqModel(rawValue: saved)
      {
        return model
      }
      return .whisperLargeV3
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "groqModel")
    }
  }
}

// MARK: - Transcription Language

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
  case auto = "auto"
  case english = "en"
  case spanish = "es"
  case french = "fr"
  case german = "de"
  case italian = "it"
  case portuguese = "pt"
  case dutch = "nl"
  case russian = "ru"
  case chinese = "zh"
  case japanese = "ja"
  case korean = "ko"
  case arabic = "ar"
  case hindi = "hi"
  case turkish = "tr"
  case polish = "pl"
  case swedish = "sv"
  case danish = "da"
  case norwegian = "no"
  case finnish = "fi"
  case czech = "cs"
  case ukrainian = "uk"
  case indonesian = "id"
  case malay = "ms"
  case thai = "th"
  case vietnamese = "vi"
  case gujarati = "gu"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .auto: return "Auto-detect"
    case .english: return "English"
    case .spanish: return "Spanish"
    case .french: return "French"
    case .german: return "German"
    case .italian: return "Italian"
    case .portuguese: return "Portuguese"
    case .dutch: return "Dutch"
    case .russian: return "Russian"
    case .chinese: return "Chinese"
    case .japanese: return "Japanese"
    case .korean: return "Korean"
    case .arabic: return "Arabic"
    case .hindi: return "Hindi"
    case .turkish: return "Turkish"
    case .polish: return "Polish"
    case .swedish: return "Swedish"
    case .danish: return "Danish"
    case .norwegian: return "Norwegian"
    case .finnish: return "Finnish"
    case .czech: return "Czech"
    case .ukrainian: return "Ukrainian"
    case .indonesian: return "Indonesian"
    case .malay: return "Malay"
    case .thai: return "Thai"
    case .vietnamese: return "Vietnamese"
    case .gujarati: return "Gujarati"
    }
  }

  /// ISO-639-1 code sent to the API, or `nil` for auto-detect.
  var isoCode: String? {
    self == .auto ? nil : rawValue
  }

  static var current: TranscriptionLanguage {
    get {
      if let saved = UserDefaults.standard.string(
        forKey: "transcriptionLanguage"),
        let lang = TranscriptionLanguage(rawValue: saved)
      {
        return lang
      }
      return .auto
    }
    set {
      UserDefaults.standard.set(
        newValue.rawValue, forKey: "transcriptionLanguage"
      )
    }
  }
}

// MARK: - Groq Engine

/// Groq Whisper cloud transcription engine.
/// All HTTP, WAV encoding, and error handling live in `WhisperAPIEngine`.
class GroqEngine: WhisperAPIEngine {

  private static let groqConfig = WhisperAPIConfig(
    baseURL: "https://api.groq.com/openai/v1",
    keychainKey: "groqApiKey",
    providerName: "Groq Whisper"
  )

  override var config: WhisperAPIConfig { Self.groqConfig }

  override var currentModel: String { GroqModel.current.rawValue }

  // MARK: - Static convenience (used by Settings / Onboarding)

  static var apiKey: String? {
    KeychainHelper.get(key: groqConfig.keychainKey)
  }

  static var isConfigured: Bool {
    guard let key = apiKey else { return false }
    return !key.isEmpty
  }

  static func setApiKey(_ key: String) throws {
    try KeychainHelper.save(key: groqConfig.keychainKey, value: key)
  }

  static func clearApiKey() {
    KeychainHelper.delete(key: groqConfig.keychainKey)
  }
}
