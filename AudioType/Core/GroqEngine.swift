import Foundation
import os.log

// MARK: - Groq Model

enum GroqModel: String, CaseIterable {
  case whisperLargeV3Turbo = "whisper-large-v3-turbo"
  case whisperLargeV3 = "whisper-large-v3"

  var displayName: String {
    switch self {
    case .whisperLargeV3Turbo: return "Whisper Large V3 Turbo (faster)"
    case .whisperLargeV3: return "Whisper Large V3 (most accurate)"
    }
  }

  static var current: GroqModel {
    get {
      if let saved = UserDefaults.standard.string(forKey: "groqModel"),
        let model = GroqModel(rawValue: saved) {
        return model
      }
      return .whisperLargeV3Turbo
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
      if let saved = UserDefaults.standard.string(forKey: "transcriptionLanguage"),
        let lang = TranscriptionLanguage(rawValue: saved) {
        return lang
      }
      return .auto
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "transcriptionLanguage")
    }
  }
}

// MARK: - Errors

enum GroqEngineError: Error, LocalizedError {
  case apiKeyNotConfigured
  case wavEncodingFailed
  case networkError(String)
  case httpError(Int, String)
  case invalidResponse
  case rateLimited
  case unauthorized

  var errorDescription: String? {
    switch self {
    case .apiKeyNotConfigured:
      return "Groq API key not configured. Open Settings to add your key."
    case .wavEncodingFailed:
      return "Failed to encode audio to WAV format."
    case let .networkError(message):
      return "Network error: \(message)"
    case let .httpError(code, message):
      return "Groq API error (HTTP \(code)): \(message)"
    case .invalidResponse:
      return "Invalid response from Groq API."
    case .rateLimited:
      return "Rate limited. Please wait a moment and try again."
    case .unauthorized:
      return "Invalid Groq API key. Check your key in Settings."
    }
  }
}

// MARK: - Groq Engine

class GroqEngine {
  private static let apiURL = URL(
    string: "https://api.groq.com/openai/v1/audio/transcriptions")!
  private static let keychainKey = "groqApiKey"

  private let logger = Logger(subsystem: "com.audiotype", category: "GroqEngine")

  init() {}

  // MARK: - API Key Management

  static var apiKey: String? {
    KeychainHelper.get(key: keychainKey)
  }

  static var isConfigured: Bool {
    guard let key = apiKey else { return false }
    return !key.isEmpty
  }

  static func setApiKey(_ key: String) throws {
    try KeychainHelper.save(key: keychainKey, value: key)
  }

  static func clearApiKey() {
    KeychainHelper.delete(key: keychainKey)
  }

  // MARK: - Transcription

  func transcribe(samples: [Float]) async throws -> String {
    guard let apiKey = Self.apiKey, !apiKey.isEmpty else {
      throw GroqEngineError.apiKeyNotConfigured
    }

    // Convert PCM samples to WAV data
    let wavData = try encodeWAV(samples: samples, sampleRate: 16000)
    logger.info("Encoded WAV: \(wavData.count) bytes from \(samples.count) samples")

    // Build multipart request
    let boundary = UUID().uuidString
    var request = URLRequest(url: Self.apiURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30

    let model = GroqModel.current
    var body = Data()

    // file field
    body.appendMultipart(
      boundary: boundary, name: "file", filename: "audio.wav",
      contentType: "audio/wav", data: wavData)
    // model field
    body.appendMultipart(boundary: boundary, name: "model", value: model.rawValue)
    // language field (omit for auto-detect — Whisper infers the language)
    if let langCode = TranscriptionLanguage.current.isoCode {
      body.appendMultipart(boundary: boundary, name: "language", value: langCode)
    }
    // response_format field
    body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
    // temperature
    body.appendMultipart(boundary: boundary, name: "temperature", value: "0")
    // close boundary
    body.append(Data("--\(boundary)--\r\n".utf8))

    request.httpBody = body

    // Send request
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw GroqEngineError.networkError(error.localizedDescription)
    }

    // Parse response
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GroqEngineError.invalidResponse
    }

    logger.info("Groq API response: HTTP \(httpResponse.statusCode)")

    switch httpResponse.statusCode {
    case 200:
      break
    case 401:
      throw GroqEngineError.unauthorized
    case 429:
      throw GroqEngineError.rateLimited
    default:
      let body = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw GroqEngineError.httpError(httpResponse.statusCode, body)
    }

    // Decode JSON
    struct TranscriptionResponse: Decodable {
      let text: String
    }

    do {
      let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
      return result.text
    } catch {
      let raw = String(data: data, encoding: .utf8) ?? "<binary>"
      logger.error("Failed to decode Groq response: \(raw)")
      throw GroqEngineError.invalidResponse
    }
  }

  // MARK: - WAV Encoding

  /// Encode Float32 PCM samples into a WAV file in memory (16-bit PCM, mono).
  private func encodeWAV(samples: [Float], sampleRate: Int) throws -> Data {
    var data = Data()

    let int16Samples = samples.map { sample -> Int16 in
      let clamped = max(-1.0, min(1.0, sample))
      return Int16(clamped * Float(Int16.max))
    }

    let numChannels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
    let blockAlign = numChannels * (bitsPerSample / 8)
    let dataSize = UInt32(int16Samples.count * 2)
    let fileSize = 36 + dataSize

    // RIFF header
    data.append(contentsOf: "RIFF".utf8)
    data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
    data.append(contentsOf: "WAVE".utf8)

    // fmt chunk
    data.append(contentsOf: "fmt ".utf8)
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
    data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

    // data chunk
    data.append(contentsOf: "data".utf8)
    data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

    for sample in int16Samples {
      data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
    }

    return data
  }
}

// MARK: - Data Helpers

extension Data {
  mutating func appendMultipart(
    boundary: String, name: String, filename: String, contentType: String, data: Data
  ) {
    append(Data("--\(boundary)\r\n".utf8))
    append(Data(
      "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
    append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
    append(data)
    append(Data("\r\n".utf8))
  }

  mutating func appendMultipart(boundary: String, name: String, value: String) {
    append(Data("--\(boundary)\r\n".utf8))
    append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
    append(Data("\(value)\r\n".utf8))
  }
}
