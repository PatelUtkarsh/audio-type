import Foundation
import os.log

// MARK: - Whisper API Configuration

/// Configuration for an OpenAI-compatible Whisper transcription provider.
struct WhisperAPIConfig {
  /// Base URL (e.g. `https://api.groq.com/openai/v1`).
  let baseURL: String

  /// Keychain key for storing the API key.
  let keychainKey: String

  /// Human-readable provider name for logs and UI.
  let providerName: String
}

// MARK: - Whisper API Engine (shared base)

/// Base class for any cloud engine that speaks the OpenAI-compatible
/// `POST /v1/audio/transcriptions` multipart protocol.
///
/// Subclasses override `config` and `currentModel` to supply their
/// provider-specific values. WAV encoding, multipart building, HTTP,
/// and response parsing are all handled here.
class WhisperAPIEngine: TranscriptionEngine {

  /// Provider configuration — subclasses must override.
  var config: WhisperAPIConfig {
    fatalError("Subclasses must override config")
  }

  /// The model identifier to send in the `model` form field.
  /// Subclasses must override.
  var currentModel: String {
    fatalError("Subclasses must override currentModel")
  }

  var displayName: String { config.providerName }

  var isAvailable: Bool { apiKey != nil && !apiKey!.isEmpty }

  private var logger: Logger {
    Logger(
      subsystem: "com.audiotype",
      category: config.providerName
        .replacingOccurrences(of: " ", with: "")
    )
  }

  // MARK: - API Key Management

  var apiKey: String? {
    KeychainHelper.get(key: config.keychainKey)
  }

  var isConfigured: Bool {
    guard let key = apiKey else { return false }
    return !key.isEmpty
  }

  func setApiKey(_ key: String) throws {
    try KeychainHelper.save(key: config.keychainKey, value: key)
  }

  func clearApiKey() {
    KeychainHelper.delete(key: config.keychainKey)
  }

  // MARK: - TranscriptionEngine

  func transcribe(samples: [Float]) async throws -> String {
    guard let apiKey = apiKey, !apiKey.isEmpty else {
      throw WhisperAPIError.apiKeyNotConfigured(config.providerName)
    }

    let wavData = WAVEncoder.encode(
      samples: samples, sampleRate: 16000
    )
    logger.info(
      "Encoded WAV: \(wavData.count) bytes from \(samples.count) samples"
    )

    guard
      let url = URL(string: "\(config.baseURL)/audio/transcriptions")
    else {
      throw WhisperAPIError.invalidURL
    }

    let request = WAVEncoder.buildRequest(
      url: url,
      apiKey: apiKey,
      wavData: wavData,
      model: currentModel,
      languageCode: TranscriptionLanguage.current.isoCode
    )

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw WhisperAPIError.networkError(error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw WhisperAPIError.invalidResponse
    }

    logger.info(
      "\(self.config.providerName) HTTP \(httpResponse.statusCode)"
    )

    switch httpResponse.statusCode {
    case 200:
      break
    case 401:
      throw WhisperAPIError.unauthorized(config.providerName)
    case 429:
      throw WhisperAPIError.rateLimited
    default:
      let body = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw WhisperAPIError.httpError(httpResponse.statusCode, body)
    }

    do {
      let result = try JSONDecoder().decode(
        WhisperTranscriptionResponse.self, from: data
      )
      return result.text
    } catch {
      let raw = String(data: data, encoding: .utf8) ?? "<binary>"
      logger.error("Failed to decode response: \(raw)")
      throw WhisperAPIError.invalidResponse
    }
  }
}

// MARK: - Response

private struct WhisperTranscriptionResponse: Decodable {
  let text: String
}

// MARK: - Shared Errors

enum WhisperAPIError: Error, LocalizedError {
  case apiKeyNotConfigured(String)
  case invalidURL
  case networkError(String)
  case httpError(Int, String)
  case invalidResponse
  case rateLimited
  case unauthorized(String)

  var errorDescription: String? {
    switch self {
    case .apiKeyNotConfigured(let name):
      return "\(name) API key not configured. Open Settings to add your key."
    case .invalidURL:
      return "Invalid API endpoint URL."
    case .networkError(let message):
      return "Network error: \(message)"
    case .httpError(let code, let message):
      return "API error (HTTP \(code)): \(message)"
    case .invalidResponse:
      return "Invalid response from API."
    case .rateLimited:
      return "Rate limited. Please wait a moment and try again."
    case .unauthorized(let name):
      return "Invalid \(name) API key. Check your key in Settings."
    }
  }
}

// MARK: - WAV Encoder

/// Encodes Float32 PCM samples into WAV data and builds multipart requests.
enum WAVEncoder {

  /// Encode Float32 PCM samples into WAV in memory (16-bit PCM, mono).
  static func encode(samples: [Float], sampleRate: Int) -> Data {
    var data = Data()

    let int16Samples = samples.map { sample -> Int16 in
      let clamped = max(-1.0, min(1.0, sample))
      return Int16(clamped * Float(Int16.max))
    }

    let numChannels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = UInt32(sampleRate)
      * UInt32(numChannels) * UInt32(bitsPerSample / 8)
    let blockAlign = numChannels * (bitsPerSample / 8)
    let dataSize = UInt32(int16Samples.count * 2)
    let fileSize = 36 + dataSize

    // RIFF header
    data.append(contentsOf: "RIFF".utf8)
    data.appendLittleEndian(fileSize)
    data.append(contentsOf: "WAVE".utf8)

    // fmt chunk
    data.append(contentsOf: "fmt ".utf8)
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))  // PCM
    data.appendLittleEndian(numChannels)
    data.appendLittleEndian(UInt32(sampleRate))
    data.appendLittleEndian(byteRate)
    data.appendLittleEndian(blockAlign)
    data.appendLittleEndian(bitsPerSample)

    // data chunk
    data.append(contentsOf: "data".utf8)
    data.appendLittleEndian(dataSize)

    for sample in int16Samples {
      data.appendLittleEndian(sample)
    }

    return data
  }

  /// Build a multipart/form-data request for an OpenAI-compatible
  /// `/v1/audio/transcriptions` endpoint.
  static func buildRequest(
    url: URL,
    apiKey: String,
    wavData: Data,
    model: String,
    languageCode: String?,
    timeoutInterval: TimeInterval = 30
  ) -> URLRequest {
    let boundary = UUID().uuidString

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(
      "Bearer \(apiKey)",
      forHTTPHeaderField: "Authorization"
    )
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    request.timeoutInterval = timeoutInterval

    var body = Data()
    body.appendFileField(
      boundary: boundary, name: "file",
      filename: "audio.wav",
      contentType: "audio/wav", fileData: wavData
    )
    body.appendFormField(
      boundary: boundary, name: "model", value: model
    )
    if let langCode = languageCode {
      body.appendFormField(
        boundary: boundary, name: "language", value: langCode
      )
    }
    body.appendFormField(
      boundary: boundary, name: "response_format", value: "json"
    )
    body.appendFormField(
      boundary: boundary, name: "temperature", value: "0"
    )
    body.append(Data("--\(boundary)--\r\n".utf8))

    request.httpBody = body
    return request
  }
}

// MARK: - Data Helpers

extension Data {
  /// Append a multipart file field.
  mutating func appendFileField(
    boundary: String, name: String,
    filename: String, contentType: String, fileData: Data
  ) {
    append(Data("--\(boundary)\r\n".utf8))
    let header =
      "Content-Disposition: form-data; "
      + "name=\"\(name)\"; filename=\"\(filename)\"\r\n"
    append(Data(header.utf8))
    append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
    append(fileData)
    append(Data("\r\n".utf8))
  }

  /// Append a multipart text field.
  mutating func appendFormField(
    boundary: String, name: String, value: String
  ) {
    append(Data("--\(boundary)\r\n".utf8))
    let header =
      "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
    append(Data(header.utf8))
    append(Data("\(value)\r\n".utf8))
  }

  /// Append a fixed-width integer in little-endian byte order.
  mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var le = value.littleEndian
    Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
  }
}
