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

/// User preference for live typing: transcribe and type chunks at natural
/// pauses while the hotkey is still held, instead of waiting for release.
/// Off by default; opt in via Settings → General.
enum LiveTypingSetting {
  private static let key = "liveTypingEnabled"

  static var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: key) }
    set { UserDefaults.standard.set(newValue, forKey: key) }
  }
}

@MainActor
class TranscriptionManager: ObservableObject {
  static let shared = TranscriptionManager()

  @Published private(set) var state: TranscriptionState = .idle
  @Published private(set) var isInitialized = false
  @Published private(set) var activeEngineName: String = ""

  private var audioRecorder: AudioRecorder?
  private var hotKeyManager: HotKeyManager?
  private var textInserter: TextInserter?

  /// The current session's chunk tasks, in spoken order. Each one waits for
  /// the one before it, so a chunk is sent with the text before it as its
  /// prompt and its text is typed in spoken order. Cancelled when a new
  /// recording starts so stale text never lands in a new context.
  private var chunkTasks: [Task<Void, Never>] = []

  /// Increases at each recording start. Chunk work from an older session
  /// checks it and does nothing.
  private var sessionID = 0

  /// Chunk-boundary policy for live typing. Fed level updates on the main
  /// queue while recording.
  private var pauseDetector = SpeechPauseDetector()

  /// Snapshot of LiveTypingSetting at session start so toggling Settings
  /// mid-recording doesn't change behavior halfway through.
  private var liveTypingActive = false

  /// Joins the session's chunks: holds back the period that a pause cut
  /// adds and supplies the prompt for the next chunk.
  private var chunkJoiner = LiveChunkJoiner()

  /// Whether the last character AudioType typed was whitespace. When it
  /// wasn't, the next chunk gets one separator space typed up front as its
  /// own keystroke - editors with smart paste can strip whitespace at the
  /// edges of pasted payloads, so the separator never rides along inside a
  /// pasted chunk. Persists across sessions so back-to-back dictations stay
  /// separated even when a session ended abnormally.
  private var lastInsertEndedWithWhitespace = true

  /// Chunks sent so far in the current session (live cuts + final tail).
  private var sessionChunkCount = 0

  /// When the processing state began (hotkey release), for the minimum
  /// indicator display time.
  private var processingStart: TimeInterval = 0

  private let logger = Logger(subsystem: "com.audiotype", category: "TranscriptionManager")

  private init() {}

  func initialize() async {
    logger.info("Initializing TranscriptionManager...")

    // Initialize components
    audioRecorder = AudioRecorder()
    // Write the level straight into the UI observable. The previous chain
    // (Task -> @Published nobody read -> NotificationCenter + userInfo dict
    // -> observer -> second main-queue hop) allocated on every update,
    // ~12x/sec while recording.
    audioRecorder?.onLevelUpdate = { [weak self] level in
      DispatchQueue.main.async {
        AudioLevelMonitor.shared.level = level
        self?.handleLevel(level)
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
    EngineResolver.invalidateCache()
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

    // Cancel any still-pending chunk work from a previous recording so we
    // don't insert stale text into the user's new context.
    cancelChunkTasks()
    sessionID += 1
    chunkJoiner = LiveChunkJoiner()

    // Resolve the engine once, up front. The whole session reuses it.
    let engine = EngineResolver.resolve()
    activeEngine = engine
    activeEngineName = engine.displayName

    liveTypingActive = LiveTypingSetting.isEnabled
    sessionChunkCount = 0
    if liveTypingActive {
      pauseDetector.begin(at: ProcessInfo.processInfo.systemUptime)
    }

    do {
      try audioRecorder?.startRecording()
      setState(.recording)
      logger.info(
        "Recording started with engine: \(engine.displayName) (live typing \(self.liveTypingActive ? "on" : "off"))"
      )
    } catch {
      logger.error("Failed to start recording: \(error.localizedDescription)")
      setState(.error("Failed to start recording"))
    }
  }

  /// Level updates arrive on the main queue ~12x/sec while recording. Feed
  /// the pause detector and cut a live chunk when it says so.
  private func handleLevel(_ level: Float) {
    guard state == .recording, liveTypingActive else { return }
    if pauseDetector.update(level: level, at: ProcessInfo.processInfo.systemUptime) == .cut {
      emitLiveChunk()
    }
  }

  private func emitLiveChunk() {
    guard let engine = activeEngine,
      let samples = audioRecorder?.drainChunk(),
      !samples.isEmpty
    else { return }
    logger.info("Live chunk cut: \(samples.count) samples")
    enqueueChunk(samples: samples, engine: engine, isFinal: false)
  }

  private func stopRecordingAndTranscribe() {
    guard state == .recording else {
      logger.warning("Cannot stop recording: not recording")
      return
    }

    let finalSamples = audioRecorder?.stopRecording()

    // Take the engine resolved at startRecording. Falls back to a fresh
    // resolution defensively if somehow nil.
    let engine = activeEngine ?? EngineResolver.resolve()
    activeEngine = nil

    // The detector knows whether the tail since the last live cut carried
    // any speech. Skip a silence-only tail, but only when earlier chunks
    // exist: for a single-chunk session always send, so very quiet speech
    // never gets eaten by the threshold heuristic.
    let tailWorthSending =
      !liveTypingActive || sessionChunkCount == 0 || pauseDetector.chunkHasSpeech
    pauseDetector.end()

    // Nothing captured and nothing in flight: bail like before.
    let tail = finalSamples ?? []
    if tail.isEmpty && chunkTasks.isEmpty {
      logger.error("No audio samples captured")
      setState(.idle)
      return
    }

    logger.info(
      "Recording stopped, final tail \(tail.count) samples after \(self.sessionChunkCount) live chunk(s)"
    )
    setState(.processing)
    processingStart = ProcessInfo.processInfo.systemUptime

    if !tail.isEmpty && tailWorthSending {
      enqueueChunk(samples: tail, engine: engine, isFinal: true)
    }

    finishSession()
  }

  /// Transcribe one chunk and type its text. Chunks run one after another:
  /// each request waits for the chunk before it, so it can send the text so
  /// far as its prompt (the model then continues the sentence instead of
  /// starting a new one), and text always lands in spoken order. A cut
  /// needs at least 3s of audio, so the previous request has usually
  /// finished by then and the wait costs little.
  private func enqueueChunk(samples: [Float], engine: TranscriptionEngine, isFinal: Bool) {
    sessionChunkCount += 1
    let chunkIndex = sessionChunkCount
    let isPartial = !isFinal || chunkIndex > 1
    let session = sessionID
    let logger = self.logger
    let previous = chunkTasks.last

    let task = Task { [weak self] in
      await previous?.value
      guard !Task.isCancelled, let self = self, self.sessionID == session else { return }
      let context = TranscriptionContext(
        precedingText: self.chunkJoiner.prompt(), isPartial: isPartial)
      let startTime = ProcessInfo.processInfo.systemUptime
      do {
        let text = try await engine.transcribe(samples: samples, context: context)
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        logger.info(
          "[\(engine.displayName)] Chunk \(chunkIndex) transcribed in \(elapsed, format: .fixed(precision: 2))s: \(text)"
        )
        guard !Task.isCancelled, self.sessionID == session else { return }
        self.insertChunk(text, isFinal: isFinal)
      } catch {
        logger.error(
          "[\(engine.displayName)] Chunk \(chunkIndex) failed: \(error.localizedDescription)"
        )
        guard !Task.isCancelled, isFinal, self.sessionID == session else { return }
        // Non-final chunk failures drop that fragment and the session keeps
        // going; a final failure surfaces like the old single-shot path.
        guard case .processing = self.state else { return }
        self.setState(.error("Transcription failed"))
        Task {
          try? await Task.sleep(for: .seconds(2))
          if case .error = self.state {
            self.setState(.idle)
          }
        }
      }
    }
    chunkTasks.append(task)
  }

  private func cancelChunkTasks() {
    chunkTasks.forEach { $0.cancel() }
    chunkTasks = []
  }

  /// Post-process and type one chunk's text. Runs on the main actor, in
  /// chunk order.
  private func insertChunk(_ text: String, isFinal: Bool) {
    guard let insertion = chunkJoiner.append(text, isFinal: isFinal) else { return }
    let processed = TextPostProcessor.shared.process(
      insertion.text, capitalizeFirst: insertion.startsSentence
    )

    // The previous chunk's held-back period (when this chunk starts a new
    // sentence) and the separator space go first, as one short keystroke
    // insert that never takes the clipboard path: editors with smart paste
    // can strip whitespace at the edges of pasted payloads. After a line
    // break, no period and no space are needed.
    if !lastInsertEndedWithWhitespace {
      textInserter?.insertText(insertion.terminator + " ")
    }
    textInserter?.insertText(processed)
    lastInsertEndedWithWhitespace = processed.last?.isWhitespace ?? false
  }

  /// Wait for the chunk tasks to drain, keep the processing indicator up
  /// for at least 0.5s so it doesn't flash, then return to idle.
  private func finishSession() {
    let pipeline = chunkTasks.last
    let start = processingStart
    let session = sessionID
    Task { [weak self] in
      await pipeline?.value
      let elapsed = ProcessInfo.processInfo.systemUptime - start
      let remaining = 0.5 - elapsed
      if remaining > 0 {
        try? await Task.sleep(for: .seconds(remaining))
      }
      guard let self = self, self.sessionID == session else { return }
      // Only the processing state transitions to idle here; an error set by
      // the final chunk is left alone.
      if case .processing = self.state {
        self.closeDictation()
        self.setState(.idle)
      }
    }
  }

  /// Type the period that is still held back, if any, and one trailing
  /// space so the next session (or the user's own typing) doesn't run into
  /// this text. Skipped when nothing was inserted or the output already
  /// ends in whitespace.
  private func closeDictation() {
    let terminator = chunkJoiner.finish()
    guard !lastInsertEndedWithWhitespace else { return }
    textInserter?.insertText(terminator + " ")
    lastInsertEndedWithWhitespace = true
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
