import Accelerate
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

  /// Provider configuration - subclasses must override.
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
    case let .httpError(code, message):
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
  ///
  /// The previous implementation allocated an intermediate `[Int16]`
  /// (~960 KB for a 30 s clip), let `Data` realloc as it grew, and
  /// did 480 000 individual `appendLittleEndian` calls. This version:
  ///
  /// - Allocates the final `Data` once at exact size (44-byte header + 2N).
  /// - Writes the header in place.
  /// - Uses Accelerate to clip Float → Int16 directly into the data
  ///   region in a single pass.
  static func encode(samples: [Float], sampleRate: Int) -> Data {
    let numChannels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = UInt32(sampleRate)
      * UInt32(numChannels) * UInt32(bitsPerSample / 8)
    let blockAlign = numChannels * (bitsPerSample / 8)
    let dataSize = UInt32(samples.count * 2)
    let fileSize: UInt32 = 36 + dataSize
    let totalSize = 44 + samples.count * 2

    var data = Data(count: totalSize)
    data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Void in
      guard let base = raw.baseAddress else { return }

      // --- Header ---------------------------------------------------------
      func writeASCII(_ string: String, at offset: Int) {
        for (i, byte) in string.utf8.enumerated() {
          base.storeBytes(of: byte, toByteOffset: offset + i, as: UInt8.self)
        }
      }
      func writeLE<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        base.storeBytes(of: value.littleEndian, toByteOffset: offset, as: T.self)
      }

      writeASCII("RIFF", at: 0)
      writeLE(fileSize, at: 4)
      writeASCII("WAVE", at: 8)

      writeASCII("fmt ", at: 12)
      writeLE(UInt32(16), at: 16)
      writeLE(UInt16(1), at: 20)  // PCM
      writeLE(numChannels, at: 22)
      writeLE(UInt32(sampleRate), at: 24)
      writeLE(byteRate, at: 28)
      writeLE(blockAlign, at: 32)
      writeLE(bitsPerSample, at: 34)

      writeASCII("data", at: 36)
      writeLE(dataSize, at: 40)

      // --- PCM data -------------------------------------------------------
      // Clip to [-1, 1], scale by Int16.max, convert to Int16 — all via
      // Accelerate, all into the destination region in one pass.
      guard !samples.isEmpty else { return }

      let dst = base.advanced(by: 44).assumingMemoryBound(to: Int16.self)
      let n = vDSP_Length(samples.count)

      samples.withUnsafeBufferPointer { src in
        guard let srcBase = src.baseAddress else { return }

        // Scratch buffer for clip+scale; reuse src memory would mutate the
        // caller's input, so allocate a transient float buffer.
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
        defer { scratch.deallocate() }

        // Clip into scratch.
        var lo: Float = -1.0
        var hi: Float = 1.0
        vDSP_vclip(srcBase, 1, &lo, &hi, scratch, 1, n)

        // Scale by Int16.max in place.
        var scale = Float(Int16.max)
        vDSP_vsmul(scratch, 1, &scale, scratch, 1, n)

        // Convert Float → Int16 with rounding directly into dst.
        vDSP_vfix16(scratch, 1, dst, 1, n)

        // WAV is little-endian. On Apple silicon and Intel, host order is
        // already LE so no byte-swap needed. Guard with a static assert
        // for any future big-endian Apple platform (none exist today).
        assert(1.littleEndian == 1, "WAVEncoder assumes little-endian host")
      }
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
