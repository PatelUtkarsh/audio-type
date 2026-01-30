import Foundation
import os.log

enum WhisperEngineError: Error, LocalizedError {
    case modelNotFound
    case initializationFailed
    case transcriptionFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Whisper model file not found"
        case .initializationFailed:
            return "Failed to initialize Whisper engine"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}

class WhisperEngine {
    private var context: WhisperContextRef?
    private let logger = Logger(subsystem: "com.audiotype", category: "WhisperEngine")
    
    private init(context: WhisperContextRef) {
        self.context = context
    }
    
    deinit {
        if let ctx = context {
            whisper_kit_free(ctx)
        }
    }
    
    static func load() async throws -> WhisperEngine {
        let modelPath = try await ensureModelExists()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let ctx = whisper_kit_init(modelPath) else {
                    continuation.resume(throwing: WhisperEngineError.initializationFailed)
                    return
                }
                
                let engine = WhisperEngine(context: ctx)
                continuation.resume(returning: engine)
            }
        }
    }
    
    func transcribe(samples: [Float]) throws -> String {
        guard let ctx = context else {
            throw WhisperEngineError.initializationFailed
        }
        
        let result = samples.withUnsafeBufferPointer { buffer -> String? in
            guard let ptr = buffer.baseAddress else { return nil }
            
            if let resultPtr = whisper_kit_transcribe(ctx, ptr, Int32(samples.count)) {
                let text = String(cString: resultPtr)
                whisper_kit_free_string(resultPtr)
                return text
            }
            return nil
        }
        
        guard let text = result else {
            throw WhisperEngineError.transcriptionFailed
        }
        
        return text
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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("AudioType/models")
        
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        
        return modelsDir
    }
    
    private static func downloadModel(name: String, to directory: URL) async throws {
        let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin")!
        let destinationURL = directory.appendingPathComponent("ggml-\(name).bin")
        
        let logger = Logger(subsystem: "com.audiotype", category: "ModelDownload")
        logger.info("Downloading model from \(modelURL.absoluteString)")
        
        let (tempURL, response) = try await URLSession.shared.download(from: modelURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WhisperEngineError.modelNotFound
        }
        
        // Move downloaded file to destination
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        logger.info("Model downloaded successfully to \(destinationURL.path)")
    }
}
