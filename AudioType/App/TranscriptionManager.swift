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
  @Published private(set) var audioLevel: Float = 0.0
  @Published private(set) var activeEngineName: String = ""

  private var audioRecorder: AudioRecorder?
  private var hotKeyManager: HotKeyManager?
  private var textInserter: TextInserter?

  /// Active transcription task. Held so a new recording can cancel any
  /// in-flight transcription from a previous one (e.g. user re-triggers
  /// the hotkey while the network call is still pending).
  private var transcriptionTask: Task<Void, Never>?

  private let logger = Logger(subsystem: "com.audiotype", category: "TranscriptionManager")

  private init() {}

  func initialize() async {
    logger.info("Initializing TranscriptionManager...")

    // Initialize components
    audioRecorder = AudioRecorder()
    audioRecorder?.onLevelUpdate = { [weak self] level in
      Task { @MainActor in
        self?.audioLevel = level
        NotificationCenter.default.post(
          name: .audioLevelChanged,
          object: nil,
          userInfo: ["level": level]
        )
      }
    }
    textInserter = TextInserter()

    // Resolve which engine we will use and log it
    let engine = EngineResolver.resolve()
    activeEngineName = engine.displayName
    logger.info("Active transcription engine: \(engine.displayName)")

    if !EngineResolver.anyEngineAvailable {
      logger.warning("No transcription engine available")
      setState(.error("No engine available - add a cloud API key or enable Apple Speech"))
    } else {
      logger.info("Transcription engine ready: \(engine.displayName)")
    }

    // Start hotkey listener
    hotKeyManager = HotKeyManager { [weak self] event in
      Task { @MainActor in
        self?.handleHotKeyEvent(event)
      }
    }
    hotKeyManager?.startListening()

    isInitialized = true
    if EngineResolver.anyEngineAvailable {
      setState(.idle)
    }
    logger.info("TranscriptionManager initialized successfully")
  }

  func cleanup() {
    hotKeyManager?.stopListening()
    audioRecorder = nil
  }

  /// Called when the user saves an API key or changes engine preference - re-evaluate.
  func onEngineConfigChanged() {
    let engine = EngineResolver.resolve()
    activeEngineName = engine.displayName
    if EngineResolver.anyEngineAvailable {
      setState(.idle)
      logger.info("Engine config changed, active engine: \(engine.displayName)")
    } else {
      setState(.error("No engine available - add a cloud API key or enable Apple Speech"))
    }
  }

  /// Backwards-compatible alias used by SettingsView.
  func onApiKeyChanged() {
    onEngineConfigChanged()
  }

  private func handleHotKeyEvent(_ event: HotKeyEvent) {
    switch event {
    case .keyDown:
      startRecording()
    case .keyUp:
      stopRecordingAndTranscribe()
    }
  }

  /// Engine resolved at recording start and reused for the matching
  /// transcription. Keeps Keychain / availability checks out of the
  /// post-stop hot path and ensures the engine identity doesn't change
  /// mid-recording if the user edits settings.
  private var activeEngine: TranscriptionEngine?

  private func startRecording() {
    guard state == .idle else {
      logger.warning("Cannot start recording: not in idle state")
      return
    }

    guard EngineResolver.anyEngineAvailable else {
      setState(.error("No engine available - add a cloud API key or enable Apple Speech"))
      return
    }

    // Cancel any still-pending transcription from a previous recording so
    // we don't insert stale text into the user's new context.
    transcriptionTask?.cancel()
    transcriptionTask = nil

    // Resolve the engine once, up front. transcribeAndInsert will reuse it.
    let engine = EngineResolver.resolve()
    activeEngine = engine
    activeEngineName = engine.displayName

    do {
      try audioRecorder?.startRecording()
      setState(.recording)
      logger.info("Recording started with engine: \(engine.displayName)")
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

    // Take the engine resolved at startRecording. Falls back to a fresh
    // resolution defensively if somehow nil.
    let engine = activeEngine ?? EngineResolver.resolve()
    activeEngine = nil

    logger.info("Recording stopped, captured \(samples.count) samples")
    setState(.processing)

    // Transcribe in background. Hold the task so the next recording can
    // cancel it if it's still pending.
    transcriptionTask = Task.detached { [weak self] in
      await self?.transcribeAndInsert(samples: samples, engine: engine)
    }
  }

  private func transcribeAndInsert(samples: [Float], engine: TranscriptionEngine) async {

    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let text = try await engine.transcribe(samples: samples)
      let elapsed = CFAbsoluteTimeGetCurrent() - startTime
      logger.info(
        "[\(engine.displayName)] Transcription completed in \(elapsed, format: .fixed(precision: 2))s: \(text)"
      )

      // Ensure processing indicator is visible for at least 0.5s
      let minDisplayTime = 0.5
      let remaining = minDisplayTime - elapsed
      if remaining > 0 {
        try? await Task.sleep(for: .seconds(remaining))
      }

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
      logger.error("[\(engine.displayName)] Transcription failed: \(error.localizedDescription)")
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
