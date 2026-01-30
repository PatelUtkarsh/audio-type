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
    case (.error(let a), .error(let b)):
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

  private var whisperEngine: WhisperEngine?
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

    // Load whisper model
    do {
      whisperEngine = try await WhisperEngine.load()
      logger.info("Whisper model loaded successfully")
    } catch {
      logger.error("Failed to load whisper model: \(error.localizedDescription)")
      setState(.error("Failed to load model: \(error.localizedDescription)"))
      return
    }

    // Start hotkey listener
    hotKeyManager = HotKeyManager { [weak self] event in
      Task { @MainActor in
        self?.handleHotKeyEvent(event)
      }
    }
    hotKeyManager?.startListening()

    isInitialized = true
    setState(.idle)
    logger.info("TranscriptionManager initialized successfully")
  }

  func cleanup() {
    hotKeyManager?.stopListening()
    whisperEngine = nil
    audioRecorder = nil
  }

  var currentHotkey: HotKeyTrigger {
    hotKeyManager?.currentTrigger ?? .fnKey
  }

  func setHotkey(_ trigger: HotKeyTrigger) {
    hotKeyManager?.currentTrigger = trigger
    logger.info("Hotkey changed to: \(trigger.displayName)")
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
    guard let whisperEngine = whisperEngine else {
      await MainActor.run {
        self.setState(.error("Whisper engine not initialized"))
      }
      return
    }

    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let text = try whisperEngine.transcribe(samples: samples)
      let elapsed = CFAbsoluteTimeGetCurrent() - startTime
      logger.info("Transcription completed in \(elapsed, format: .fixed(precision: 2))s: \(text)")

      // Insert text with trailing space
      await MainActor.run {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
          self.textInserter?.insertText(trimmedText + " ")
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
