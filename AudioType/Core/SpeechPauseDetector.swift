import Foundation

/// Decides where to cut chunk boundaries during a hold-to-record session so
/// audio can be transcribed and typed while the user keeps speaking.
///
/// Fed normalized mic levels (0-1, as produced by AudioRecorder) with
/// monotonic timestamps. Pure state machine - no clocks, no audio - so the
/// cut policy is unit-testable. The caller drains the recorder's buffer
/// whenever `update` returns `.cut`.
///
/// Policy: cut after a natural pause (level below `silenceThreshold` for at
/// least `pauseDuration`) once the chunk carries speech and is at least
/// `minChunkDuration` long. Force a cut at `maxChunkDuration` so an unbroken
/// monologue still streams. Chunks with no speech at all never cut; leading
/// silence (key held, user thinking) just accrues until speech starts.
struct SpeechPauseDetector {

  /// Normalized level below which audio counts as a pause. Speech sits at
  /// roughly 0.25-1.0 after AudioRecorder's aggressive scaling; quiet-room
  /// noise stays well under this.
  var silenceThreshold: Float = 0.12

  /// How long the level must stay below the threshold to count as a pause.
  var pauseDuration: TimeInterval = 0.7

  /// Minimum chunk length before a pause may cut, so we don't spray tiny
  /// fragments at the API.
  var minChunkDuration: TimeInterval = 1.5

  /// Hard cut past this length even without a pause. Cutting mid-speech can
  /// split a word, so this is deliberately generous.
  var maxChunkDuration: TimeInterval = 15

  /// Whether the current (uncut) chunk has carried any speech. The session
  /// owner uses this to skip transcribing a silence-only final tail.
  private(set) var chunkHasSpeech = false

  private var chunkStart: TimeInterval?
  private var silenceStart: TimeInterval?

  enum Decision {
    case keep
    case cut
  }

  /// Start a session (hotkey down).
  mutating func begin(at time: TimeInterval) {
    chunkStart = time
    silenceStart = nil
    chunkHasSpeech = false
  }

  /// End the session (hotkey up).
  mutating func end() {
    chunkStart = nil
    silenceStart = nil
    chunkHasSpeech = false
  }

  /// Feed one level sample. Returns `.cut` when the audio accumulated since
  /// the last cut (or session start) should be sent for transcription.
  mutating func update(level: Float, at time: TimeInterval) -> Decision {
    guard let start = chunkStart else { return .keep }

    if level >= silenceThreshold {
      chunkHasSpeech = true
      silenceStart = nil
    } else if silenceStart == nil {
      silenceStart = time
    }

    // Nothing worth transcribing yet. Slide the chunk start forward through
    // leading silence so "held the key, thought for ten seconds, then spoke"
    // doesn't immediately trip the max-duration cut.
    guard chunkHasSpeech else {
      chunkStart = time
      return .keep
    }

    let chunkDuration = time - start

    if chunkDuration >= maxChunkDuration {
      resetChunk(at: time)
      return .cut
    }

    if let pauseBegan = silenceStart,
      time - pauseBegan >= pauseDuration,
      chunkDuration >= minChunkDuration {
      resetChunk(at: time)
      return .cut
    }

    return .keep
  }

  private mutating func resetChunk(at time: TimeInterval) {
    chunkStart = time
    silenceStart = nil
    chunkHasSpeech = false
  }
}
