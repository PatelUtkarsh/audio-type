import Foundation

// MARK: - OpenAI Model

enum OpenAIModel: String, CaseIterable {
  case whisper1 = "whisper-1"
  case gpt4oTranscribe = "gpt-4o-transcribe"
  case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"

  var displayName: String {
    switch self {
    case .whisper1: return "Whisper V2 (cheapest)"
    case .gpt4oTranscribe: return "GPT-4o Transcribe (best)"
    case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe (balanced)"
    }
  }

  static var current: OpenAIModel {
    get {
      if let saved = UserDefaults.standard.string(
        forKey: "openaiModel"),
        let model = OpenAIModel(rawValue: saved) {
        return model
      }
      return .gpt4oMiniTranscribe
    }
    set {
      UserDefaults.standard.set(
        newValue.rawValue, forKey: "openaiModel"
      )
    }
  }
}

// MARK: - OpenAI Engine

/// OpenAI Whisper cloud transcription engine.
/// All HTTP, WAV encoding, and error handling live in `WhisperAPIEngine`.
class OpenAIEngine: WhisperAPIEngine {

  private static let openAIConfig = WhisperAPIConfig(
    baseURL: "https://api.openai.com/v1",
    keychainKey: "openaiApiKey",
    providerName: "OpenAI"
  )

  override var config: WhisperAPIConfig { Self.openAIConfig }

  override var currentModel: String { OpenAIModel.current.rawValue }

  // MARK: - Static convenience (used by Settings / Onboarding)

  static var apiKey: String? {
    KeychainHelper.get(key: openAIConfig.keychainKey)
  }

  static var isConfigured: Bool {
    guard let key = apiKey else { return false }
    return !key.isEmpty
  }

  static func setApiKey(_ key: String) throws {
    try KeychainHelper.save(key: openAIConfig.keychainKey, value: key)
  }

  static func clearApiKey() {
    KeychainHelper.delete(key: openAIConfig.keychainKey)
  }
}
