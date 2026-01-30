import Foundation

/// A Swift wrapper that calls the whisper-cli binary for transcription
/// This approach avoids complex C interop and is more reliable
public class WhisperWrapper {
  private let modelPath: String
  private let whisperCliPath: String

  public init(modelPath: String, whisperCliPath: String? = nil) {
    self.modelPath = modelPath
    // Look for whisper-cli in the build directory or use provided path
    self.whisperCliPath = whisperCliPath ?? Self.findWhisperCli()
  }

  /// Transcribe audio samples by writing to a temp WAV file and calling whisper-cli
  public func transcribe(samples: [Float], sampleRate: Int = 16000) throws -> String {
    // Write samples to temporary WAV file
    let tempDir = FileManager.default.temporaryDirectory
    let wavPath = tempDir.appendingPathComponent("audiotype_\(UUID().uuidString).wav")

    try writeWAV(samples: samples, sampleRate: sampleRate, to: wavPath)
    defer { try? FileManager.default.removeItem(at: wavPath) }

    // Call whisper-cli
    let result = try runWhisperCli(wavPath: wavPath.path)

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func runWhisperCli(wavPath: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: whisperCliPath)
    process.arguments = [
      "-m", modelPath,
      "-f", wavPath,
      "-l", "en",  // English language
      "-nt",  // No timestamps
      "--no-prints",  // Suppress progress output
    ]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
      throw WhisperError.cliError("whisper-cli failed: \(errorOutput)")
    }

    return output
  }

  /// Write Float samples to a WAV file (16-bit PCM, mono)
  private func writeWAV(samples: [Float], sampleRate: Int, to url: URL) throws {
    var data = Data()

    // Convert Float samples to Int16
    let int16Samples = samples.map { sample -> Int16 in
      let clamped = max(-1.0, min(1.0, sample))
      return Int16(clamped * Float(Int16.max))
    }

    // WAV header
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
    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // audio format (PCM)
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

    try data.write(to: url)
  }

  /// Find whisper-cli in common locations
  private static func findWhisperCli() -> String {
    let locations = [
      // Built from source
      "./whisper.cpp/build/bin/whisper-cli",
      "../whisper.cpp/build/bin/whisper-cli",
      // In app bundle
      Bundle.main.bundlePath + "/Contents/MacOS/whisper-cli",
      // Homebrew
      "/opt/homebrew/bin/whisper-cli",
      "/usr/local/bin/whisper-cli",
    ]

    for location in locations {
      if FileManager.default.fileExists(atPath: location) {
        return location
      }
    }

    // Default to bundled location
    return Bundle.main.bundlePath + "/Contents/MacOS/whisper-cli"
  }

  /// Check if whisper-cli is available
  public static func isAvailable() -> Bool {
    let path = findWhisperCli()
    return FileManager.default.isExecutableFile(atPath: path)
  }
}

public enum WhisperError: Error, LocalizedError {
  case cliNotFound
  case cliError(String)
  case modelNotFound

  public var errorDescription: String? {
    switch self {
    case .cliNotFound:
      return "whisper-cli not found"
    case .cliError(let message):
      return message
    case .modelNotFound:
      return "Whisper model not found"
    }
  }
}
