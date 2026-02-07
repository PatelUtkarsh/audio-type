import Foundation
import os.log

enum TranscriptionState: Equatable {
  case idle
  case recording
  case processing
  case error(String)

  static func == (lhs: TranscriptionState, rhs: TranscriptionState) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle), (.recording, .recording), (.processing, .processing):
      return true
    case let (.error(a), .error(b)):
      return a == b
    default:
      return false
    }
  }
}

@MainActor
class TranscriptionManager: ObservableObject {
  static let shared = TranscriptionManager()

  @Published private(set) var state: TranscriptionState = .idle
  @Published private(set) var isInitialized = false

  private var groqEngine: GroqEngine?
  private var audioRecorder: AudioRecorder?
  private var hotKeyManager: HotKeyManager?
  private var textInserter: TextInserter?

  private let logger = Logger(subsystem: "com.audiotype", category: "TranscriptionManager")

  private init() {}

  func initialize() async {
    logger.info("Initializing TranscriptionManager...")

    // Initialize components
    audioRecorder = AudioRecorder()
    textInserter = TextInserter()

    // Initialize Groq engine (lightweight — no model download needed)
    groqEngine = GroqEngine()

    if !GroqEngine.isConfigured {
      logger.warning("Groq API key not configured")
      setState(.error("API key required — open Settings"))
    } else {
      logger.info("Groq engine ready")
    }

    // Start hotkey listener
    hotKeyManager = HotKeyManager { [weak self] event in
      Task { @MainActor in
        self?.handleHotKeyEvent(event)
      }
    }
    hotKeyManager?.startListening()

    isInitialized = true
    if GroqEngine.isConfigured {
      setState(.idle)
    }
    logger.info("TranscriptionManager initialized successfully")
  }

  func cleanup() {
    hotKeyManager?.stopListening()
    groqEngine = nil
    audioRecorder = nil
  }

  /// Called when the user saves an API key — re-validate and clear error state.
  func onApiKeyChanged() {
    if GroqEngine.isConfigured {
      setState(.idle)
      logger.info("API key configured, engine ready")
    } else {
      setState(.error("API key required — open Settings"))
    }
  }

  private func handleHotKeyEvent(_ event: HotKeyEvent) {
    switch event {
    case .keyDown:
      startRecording()
    case .keyUp:
      stopRecordingAndTranscribe()
    }
  }

  private func startRecording() {
    guard state == .idle else {
      logger.warning("Cannot start recording: not in idle state")
      return
    }

    guard GroqEngine.isConfigured else {
      setState(.error("API key required — open Settings"))
      return
    }

    do {
      try audioRecorder?.startRecording()
      setState(.recording)
      logger.info("Recording started")
    } catch {
      logger.error("Failed to start recording: \(error.localizedDescription)")
      setState(.error("Failed to start recording"))
    }
  }

  private func stopRecordingAndTranscribe() {
    guard state == .recording else {
      logger.warning("Cannot stop recording: not recording")
      return
    }

    guard let samples = audioRecorder?.stopRecording() else {
      logger.error("No audio samples captured")
      setState(.idle)
      return
    }

    logger.info("Recording stopped, captured \(samples.count) samples")
    setState(.processing)

    // Transcribe in background
    Task.detached { [weak self] in
      await self?.transcribeAndInsert(samples: samples)
    }
  }

  private func transcribeAndInsert(samples: [Float]) async {
    guard let groqEngine = groqEngine else {
      await MainActor.run {
        self.setState(.error("Groq engine not initialized"))
      }
      return
    }

    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let text = try await groqEngine.transcribe(samples: samples)
      let elapsed = CFAbsoluteTimeGetCurrent() - startTime
      logger.info("Transcription completed in \(elapsed, format: .fixed(precision: 2))s: \(text)")

      // Post-process and insert text with trailing space
      await MainActor.run {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
          let processedText = TextPostProcessor.shared.process(trimmedText)
          self.textInserter?.insertText(processedText + " ")
        }
        self.setState(.idle)
      }
    } catch {
      logger.error("Transcription failed: \(error.localizedDescription)")
      await MainActor.run {
        self.setState(.error("Transcription failed"))
        // Auto-reset to idle after 2 seconds
        Task {
          try? await Task.sleep(for: .seconds(2))
          if case .error = self.state {
            self.setState(.idle)
          }
        }
      }
    }
  }

  private func setState(_ newState: TranscriptionState) {
    state = newState
    NotificationCenter.default.post(
      name: .transcriptionStateChanged,
      object: nil,
      userInfo: ["state": newState]
    )
  }
}
