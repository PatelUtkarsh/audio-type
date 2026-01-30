import Foundation
import WhisperWrapper
import os.log

enum WhisperEngineError: Error, LocalizedError {
  case modelNotFound
  case cliNotFound
  case transcriptionFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotFound:
      return "Whisper model file not found"
    case .cliNotFound:
      return "whisper-cli not found. Run Scripts/build-whisper.sh first."
    case .transcriptionFailed(let message):
      return "Transcription failed: \(message)"
    }
  }
}

class WhisperEngine {
  private var wrapper: WhisperWrapper?
  private let logger = Logger(subsystem: "com.audiotype", category: "WhisperEngine")

  private init(wrapper: WhisperWrapper) {
    self.wrapper = wrapper
  }

  deinit {
    wrapper = nil
  }

  static func load() async throws -> WhisperEngine {
    // First, build whisper-cli if needed
    try await buildWhisperCliIfNeeded()

    // Find whisper-cli
    let cliPath = findWhisperCli()
    guard FileManager.default.isExecutableFile(atPath: cliPath) else {
      throw WhisperEngineError.cliNotFound
    }

    // Ensure model exists
    let modelPath = try await ensureModelExists()

    // Create wrapper
    let wrapper = WhisperWrapper(modelPath: modelPath, whisperCliPath: cliPath)

    return WhisperEngine(wrapper: wrapper)
  }

  func transcribe(samples: [Float]) throws -> String {
    guard let wrapper = wrapper else {
      throw WhisperEngineError.cliNotFound
    }

    do {
      return try wrapper.transcribe(samples: samples, sampleRate: 16000)
    } catch {
      throw WhisperEngineError.transcriptionFailed(error.localizedDescription)
    }
  }

  // MARK: - Private

  private static func findWhisperCli() -> String {
    let projectDir = getProjectDirectory()
    let locations = [
      projectDir + "/whisper.cpp/build/bin/whisper-cli",
      "./whisper.cpp/build/bin/whisper-cli",
      "/opt/homebrew/bin/whisper-cli",
      "/usr/local/bin/whisper-cli",
    ]

    for location in locations {
      if FileManager.default.isExecutableFile(atPath: location) {
        return location
      }
    }

    return locations[0]  // Default to first option
  }

  private static func getProjectDirectory() -> String {
    // Try to find project root
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    // Check if we're in the project directory
    let whisperPath = url.appendingPathComponent("whisper.cpp").path
    if FileManager.default.fileExists(atPath: whisperPath) {
      return url.path
    }

    // Check parent directories
    for _ in 0..<5 {
      url = url.deletingLastPathComponent()
      let whisperPath = url.appendingPathComponent("whisper.cpp").path
      if FileManager.default.fileExists(atPath: whisperPath) {
        return url.path
      }
    }

    return FileManager.default.currentDirectoryPath
  }

  private static func buildWhisperCliIfNeeded() async throws {
    let cliPath = findWhisperCli()

    if FileManager.default.isExecutableFile(atPath: cliPath) {
      return  // Already built
    }

    // The CLI needs to be built - this is done via the build script
    // For now, just check if it exists
    print("Note: whisper-cli not found. Run ./Scripts/build-whisper.sh to build it.")
  }

  private static func ensureModelExists() async throws -> String {
    let modelName = "ggml-base.en.bin"
    let modelsDir = getModelsDirectory()
    let modelPath = modelsDir.appendingPathComponent(modelName)

    // Check if model exists
    if FileManager.default.fileExists(atPath: modelPath.path) {
      return modelPath.path
    }

    // Download model
    try await downloadModel(name: "base.en", to: modelsDir)

    guard FileManager.default.fileExists(atPath: modelPath.path) else {
      throw WhisperEngineError.modelNotFound
    }

    return modelPath.path
  }

  private static func getModelsDirectory() -> URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let modelsDir = appSupport.appendingPathComponent("AudioType/models")

    try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

    return modelsDir
  }

  private static func downloadModel(name: String, to directory: URL) async throws {
    let modelURL = URL(
      string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin")!
    let destinationURL = directory.appendingPathComponent("ggml-\(name).bin")

    print("Downloading model from \(modelURL.absoluteString)...")

    let (tempURL, response) = try await URLSession.shared.download(from: modelURL)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      throw WhisperEngineError.modelNotFound
    }

    // Move downloaded file to destination
    try? FileManager.default.removeItem(at: destinationURL)
    try FileManager.default.moveItem(at: tempURL, to: destinationURL)

    print("Model downloaded to \(destinationURL.path)")
  }
}
