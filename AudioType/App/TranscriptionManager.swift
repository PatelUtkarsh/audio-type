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

  /// Reason of the session's first failed chunk, shown when it ends.
  private var sessionFailure: String?

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
    // Onboarding can finish twice (button and auto-complete). A second run
    // would start a second HotKeyManager while the first, which retains
    // itself for its event tap, keeps listening.
    guard !isInitialized else {
      logger.info("TranscriptionManager already initialized")
      return
    }
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
    logger.info("Engine config changed, active engine: \(engine.displayName)")

    // A session in progress keeps the engine it started with. Forcing .idle
    // here left the recorder running, and the next session sent the old
    // audio too.
    switch state {
    case .recording, .processing:
      return
    case .idle, .error:
      if EngineResolver.anyEngineAvailable {
        setState(.idle)
      } else {
        setState(.error("No engine available - add a cloud API key or enable Apple Speech"))
      }
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
    case .keyUp(let otherKeyPressed):
      stopRecordingAndTranscribe(otherKeyPressed: otherKeyPressed)
    case .cancel:
      cancelRecording(reason: "the hotkey binding changed")
    }
  }

  /// A release this soon after the press, with no Live Typing chunk sent,
  /// is a tap of the hotkey, not a dictation.
  private static let minimumHoldDuration: TimeInterval = 0.3

  /// When the current recording started, for `minimumHoldDuration`.
  private var recordingStartTime: TimeInterval = 0

  /// A shortcut hold (another key pressed with the hotkey) is kept as a
  /// dictation when it has at least this much audio above the pause level,
  /// so a stray key does not lose speech. Key clicks alone stay under it.
  private static let minimumVoicedDuration: TimeInterval = 1.0

  /// Time with a level above the pause threshold in the current recording.
  private var voicedDuration: TimeInterval = 0
  private var lastLevelTime: TimeInterval?

  /// Engine resolved at recording start and reused for the matching
  /// transcription. Keeps Keychain / availability checks out of the
  /// post-stop hot path and ensures the engine identity doesn't change
  /// mid-recording if the user edits settings.
  private var activeEngine: TranscriptionEngine?

  private func startRecording() {
    // An error state never blocks a new recording: it only reports the last
    // failure. Before, a failed microphone start left the app in .error
    // with every later hotkey press ignored until a relaunch.
    switch state {
    case .idle, .error:
      break
    case .recording, .processing:
      logger.warning("Cannot start recording: a session is still active")
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
    sessionFailure = nil

    // Resolve the engine once, up front. The whole session reuses it.
    let engine = EngineResolver.resolve()
    activeEngine = engine
    activeEngineName = engine.displayName

    liveTypingActive = LiveTypingSetting.isEnabled
    sessionChunkCount = 0
    finishedChunkCount = 0
    voicedDuration = 0
    lastLevelTime = nil
    if liveTypingActive {
      pauseDetector.begin(at: ProcessInfo.processInfo.systemUptime)
    }

    do {
      try audioRecorder?.startRecording()
      recordingStartTime = ProcessInfo.processInfo.systemUptime
      setState(.recording)
      logger.info(
        "Recording started with engine: \(engine.displayName) (live typing \(self.liveTypingActive ? "on" : "off"))"
      )
    } catch {
      logger.error("Failed to start recording: \(error.localizedDescription)")
      activeEngine = nil
      pauseDetector.end()
      showError("Could not start the microphone")
    }
  }

  /// Level updates arrive on the main queue ~12x/sec while recording. Count
  /// voiced time, feed the pause detector and cut a live chunk when it says
  /// so.
  private func handleLevel(_ level: Float) {
    guard state == .recording else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if level >= pauseDetector.silenceThreshold, let last = lastLevelTime {
      // One update covers one tap buffer (~0.1s); cap a gap from a stall.
      voicedDuration += min(now - last, 0.25)
    }
    lastLevelTime = now

    guard liveTypingActive else { return }
    if pauseDetector.update(level: level, at: now) == .cut {
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

  private func stopRecordingAndTranscribe(otherKeyPressed: Bool) {
    guard state == .recording else {
      logger.warning("Cannot stop recording: not recording")
      return
    }

    // A shortcut such as fn+Delete or fn+arrow, or a short tap of the
    // hotkey, is not a dictation: models can return text such as "Thank
    // you." for near-silent audio, and it would be typed. Discard it,
    // unless Live Typing already sent part of the session or the hold has
    // real speech in it.
    let heldFor = ProcessInfo.processInfo.systemUptime - recordingStartTime
    let isShortcut = otherKeyPressed && voicedDuration < Self.minimumVoicedDuration
    if sessionChunkCount == 0 && (isShortcut || heldFor < Self.minimumHoldDuration) {
      cancelRecording(
        reason: isShortcut ? "another key was pressed with the hotkey" : "the hotkey was only tapped")
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

  /// How long a chunk waits for the chunk before it, so that chunk's text
  /// can go into the prompt. A cut needs at least 3s of audio, so the
  /// previous request has usually finished long before. The wait is
  /// bounded so that one slow request (bad network) does not hold up every
  /// later one.
  private static let promptWait: Duration = .milliseconds(1_500)

  /// Chunks of the current session that are typed (or failed), in order.
  private var finishedChunkCount = 0

  /// Transcribe one chunk and type its text. The request waits (briefly)
  /// for the chunk before it and sends the text so far as its prompt, so
  /// the model continues the sentence instead of starting a new one. Text
  /// is always typed in spoken order.
  private func enqueueChunk(samples: [Float], engine: TranscriptionEngine, isFinal: Bool) {
    sessionChunkCount += 1
    let chunkIndex = sessionChunkCount
    let isPartial = !isFinal || chunkIndex > 1
    let session = sessionID
    let logger = self.logger
    let previous = chunkTasks.last

    let task = Task { [weak self] in
      guard let self = self else { return }
      await self.waitForChunk(chunkIndex - 1, of: session, upTo: Self.promptWait)
      guard !Task.isCancelled, self.sessionID == session else { return }
      let context = TranscriptionContext(
        precedingText: self.chunkJoiner.prompt(), isPartial: isPartial)
      let startTime = ProcessInfo.processInfo.systemUptime
      let result: Result<String, Error>
      do {
        let text = try await engine.transcribe(samples: samples, context: context)
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        logger.info(
          "[\(engine.displayName)] Chunk \(chunkIndex) transcribed in \(elapsed, format: .fixed(precision: 2))s: \(text)"
        )
        result = .success(text)
      } catch {
        logger.error(
          "[\(engine.displayName)] Chunk \(chunkIndex) failed: \(error.localizedDescription)"
        )
        result = .failure(error)
      }

      // Type in spoken order.
      await previous?.value
      guard !Task.isCancelled, self.sessionID == session else { return }
      switch result {
      case .success(let text):
        let sentWithPrompt = engine.supportsPrompt && context.precedingText != nil
        await self.insertChunk(text, isFinal: isFinal, sentWithPrompt: sentWithPrompt)
      case .failure(let error):
        // The session keeps going; finishSession reports the failure.
        self.recordChunkFailure(error)
      }
      if self.sessionID == session {
        self.finishedChunkCount = chunkIndex
      }
    }
    chunkTasks.append(task)
  }

  /// Returns when chunk `index` of `session` is typed (or failed), when the
  /// session ends, or after `limit`.
  private func waitForChunk(_ index: Int, of session: Int, upTo limit: Duration) async {
    let deadline = ContinuousClock.now + limit
    while finishedChunkCount < index, sessionID == session, !Task.isCancelled,
      ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  private func recordChunkFailure(_ error: Error) {
    // An empty Apple Speech result is not a failure: the Whisper engines
    // return "" for the same audio.
    if case .noResult? = error as? AppleSpeechError { return }
    if sessionFailure == nil {
      sessionFailure = Self.userMessage(for: error)
    }
  }

  /// A short reason for the menu bar. The full error is in the log.
  private static func userMessage(for error: Error) -> String {
    // The HTTP error body can be long JSON; the status code is enough here.
    if case .httpError(let code, _)? = error as? WhisperAPIError {
      return "API error (HTTP \(code))"
    }
    return (error as? LocalizedError)?.errorDescription ?? "Transcription failed"
  }

  private func cancelChunkTasks() {
    chunkTasks.forEach { $0.cancel() }
    chunkTasks = []
  }

  /// End the recording without transcribing it.
  private func cancelRecording(reason: String) {
    guard state == .recording else { return }
    _ = audioRecorder?.stopRecording()
    pauseDetector.end()
    activeEngine = nil
    cancelChunkTasks()
    sessionID += 1
    logger.info("Recording discarded: \(reason, privacy: .public)")
    setState(.idle)
  }

  /// Post-process and type one chunk's text. Runs on the main actor, in
  /// chunk order.
  private func insertChunk(_ text: String, isFinal: Bool, sentWithPrompt: Bool) async {
    guard
      let insertion = chunkJoiner.append(text, isFinal: isFinal, sentWithPrompt: sentWithPrompt)
    else { return }
    let processed = TextPostProcessor.shared.process(
      insertion.text, capitalizeFirst: insertion.startsSentence
    )

    // The previous chunk's held-back period (when this chunk starts a new
    // sentence) and the separator space go first, as one short keystroke
    // insert that never takes the clipboard path: editors with smart paste
    // can strip whitespace at the edges of pasted payloads. After a line
    // break, no period and no space are needed.
    if !lastInsertEndedWithWhitespace {
      await textInserter?.insertText(insertion.terminator + " ")
    }
    await textInserter?.insertText(processed)
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
      guard let self = self, self.sessionID == session, case .processing = self.state else {
        return
      }
      await self.closeDictation()
      if let failure = self.sessionFailure {
        // Say so when other chunks were typed: the text has a gap.
        self.showError(
          self.chunkJoiner.hasText ? "Some speech was not typed: \(failure)" : failure)
      } else {
        self.setState(.idle)
      }
    }
  }

  /// Type the period that is still held back, if any, and one trailing
  /// space so the next session (or the user's own typing) doesn't run into
  /// this text. Skipped when nothing was inserted or the output already
  /// ends in whitespace.
  private func closeDictation() async {
    let terminator = chunkJoiner.finish()
    guard !lastInsertEndedWithWhitespace else { return }
    await textInserter?.insertText(terminator + " ")
    lastInsertEndedWithWhitespace = true
  }

  /// How long an error stays in the menu bar before the state returns to
  /// idle: long enough to open the menu and read it. A new recording does
  /// not wait for this.
  private static let errorDisplayDuration: Duration = .seconds(5)

  private func showError(_ message: String) {
    setState(.error(message))
    Task { [weak self] in
      try? await Task.sleep(for: Self.errorDisplayDuration)
      guard let self = self, self.state == .error(message) else { return }
      self.setState(.idle)
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
