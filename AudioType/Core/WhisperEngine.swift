import Foundation
import WhisperWrapper
import os.log

enum WhisperModel: String, CaseIterable {
  case tiny = "tiny.en"
  case base = "base.en"
  case small = "small.en"
  case medium = "medium.en"

  var displayName: String {
    switch self {
    case .tiny: return "Tiny (fastest, ~75MB)"
    case .base: return "Base (fast, ~142MB)"
    case .small: return "Small (balanced, ~466MB)"
    case .medium: return "Medium (accurate, ~1.5GB)"
    }
  }

  var fileName: String {
    return "ggml-\(rawValue).bin"
  }

  var downloadSize: String {
    switch self {
    case .tiny: return "75 MB"
    case .base: return "142 MB"
    case .small: return "466 MB"
    case .medium: return "1.5 GB"
    }
  }

  static var current: WhisperModel {
    get {
      if let saved = UserDefaults.standard.string(forKey: "whisperModel"),
        let model = WhisperModel(rawValue: saved)
      {
        return model
      }
      return .small  // Default
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "whisperModel")
    }
  }
}

enum WhisperEngineError: Error, LocalizedError {
  case modelNotFound
  case cliNotFound
  case transcriptionFailed(String)
  case downloadFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotFound:
      return "Whisper model file not found"
    case .cliNotFound:
      return "whisper-cli not found. Run Scripts/build-whisper.sh first."
    case .transcriptionFailed(let message):
      return "Transcription failed: \(message)"
    case .downloadFailed(let message):
      return "Model download failed: \(message)"
    }
  }
}

class WhisperEngine {
  private var wrapper: WhisperWrapper?
  private let logger = Logger(subsystem: "com.audiotype", category: "WhisperEngine")
  private(set) var currentModel: WhisperModel

  private init(wrapper: WhisperWrapper, model: WhisperModel) {
    self.wrapper = wrapper
    self.currentModel = model
  }

  deinit {
    wrapper = nil
  }

  static func load(model: WhisperModel? = nil) async throws -> WhisperEngine {
    let selectedModel = model ?? WhisperModel.current

    // First, build whisper-cli if needed
    try await buildWhisperCliIfNeeded()

    // Find whisper-cli
    let cliPath = findWhisperCli()
    guard FileManager.default.isExecutableFile(atPath: cliPath) else {
      throw WhisperEngineError.cliNotFound
    }

    // Ensure model exists
    let modelPath = try await ensureModelExists(model: selectedModel)

    // Create wrapper
    let wrapper = WhisperWrapper(modelPath: modelPath, whisperCliPath: cliPath)

    return WhisperEngine(wrapper: wrapper, model: selectedModel)
  }

  /// Check if a specific model is downloaded
  static func isModelDownloaded(_ model: WhisperModel) -> Bool {
    let modelsDir = getModelsDirectory()
    let modelPath = modelsDir.appendingPathComponent(model.fileName)
    return FileManager.default.fileExists(atPath: modelPath.path)
  }

  /// Download a specific model
  static func downloadModelFile(
    _ model: WhisperModel,
    progress: ((Double) -> Void)? = nil
  ) async throws {
    let modelsDir = getModelsDirectory()
    try await downloadModel(name: model.rawValue, to: modelsDir, progress: progress)
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
    let bundlePath = Bundle.main.bundlePath + "/Contents/MacOS/whisper-cli"

    let locations = [
      // App bundle (for distributed app)
      bundlePath,
      // Development paths
      projectDir + "/whisper.cpp/build/bin/whisper-cli",
      "./whisper.cpp/build/bin/whisper-cli",
      "/opt/homebrew/bin/whisper-cli",
      "/usr/local/bin/whisper-cli",
    ]

    for location in locations {
      if FileManager.default.isExecutableFile(atPath: location) {
        print("Found whisper-cli at: \(location)")
        return location
      }
    }

    print("whisper-cli not found. Checked: \(locations)")
    return bundlePath  // Default to bundle location
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

  private static func ensureModelExists(model: WhisperModel) async throws -> String {
    let modelsDir = getModelsDirectory()
    let modelPath = modelsDir.appendingPathComponent(model.fileName)

    // Check if model exists
    if FileManager.default.fileExists(atPath: modelPath.path) {
      return modelPath.path
    }

    // Download model
    try await downloadModel(name: model.rawValue, to: modelsDir, progress: nil)

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

  private static func downloadModel(
    name: String,
    to directory: URL,
    progress: ((Double) -> Void)?
  ) async throws {
    let modelURL = URL(
      string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin")!
    let destinationURL = directory.appendingPathComponent("ggml-\(name).bin")

    print("Downloading model from \(modelURL.absoluteString)...")

    // Use URLSession with delegate for progress tracking
    let (tempURL, response) = try await URLSession.shared.download(from: modelURL)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw WhisperEngineError.downloadFailed("HTTP \(statusCode)")
    }

    // Move downloaded file to destination
    try? FileManager.default.removeItem(at: destinationURL)
    try FileManager.default.moveItem(at: tempURL, to: destinationURL)

    print("Model downloaded to \(destinationURL.path)")
  }
}
