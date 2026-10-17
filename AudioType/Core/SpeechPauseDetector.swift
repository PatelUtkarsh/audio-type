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
/// `minChunkDuration` long. Shorter pauses are often inside a sentence (a
/// breath, a hesitation), so a normal chunk needs a long pause; a chunk past
/// `longChunkDuration` cuts at a shorter one so a monologue still streams.
/// Past `maxChunkDuration` a short dip between words is enough, and
/// `hardMaxChunkDuration` forces the cut. Chunks with no speech at all never
/// cut; leading silence (key held, user thinking) just accrues until speech
/// starts.
struct SpeechPauseDetector {

  /// Normalized level below which audio counts as a pause. Speech sits at
  /// roughly 0.25-1.0 after AudioRecorder's aggressive scaling; quiet-room
  /// noise stays well under this.
  var silenceThreshold: Float = 0.12

  /// How long the level must stay below the threshold to cut a chunk of
  /// normal length.
  var pauseDuration: TimeInterval = 1.0

  /// Past this chunk length, `longChunkPauseDuration` is enough to cut.
  var longChunkDuration: TimeInterval = 6
  var longChunkPauseDuration: TimeInterval = 0.7

  /// Minimum chunk length before a pause may cut. Short chunks give the
  /// model little context and cost a full request each (Groq bills at
  /// least 10s per request).
  var minChunkDuration: TimeInterval = 3

  /// Past this length, cut at the first dip of `shortDipDuration`.
  var maxChunkDuration: TimeInterval = 15
  var shortDipDuration: TimeInterval = 0.25

  /// Cut here even without a dip. This can split a word.
  var hardMaxChunkDuration: TimeInterval = 17

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
    let pause = silenceStart.map { time - $0 } ?? 0
    let requiredPause =
      chunkDuration >= longChunkDuration ? longChunkPauseDuration : pauseDuration

    let shouldCut =
      chunkDuration >= hardMaxChunkDuration
      || (chunkDuration >= maxChunkDuration && pause >= shortDipDuration)
      || (chunkDuration >= minChunkDuration && pause >= requiredPause)
    guard shouldCut else { return .keep }

    resetChunk(at: time)
    return .cut
  }

  private mutating func resetChunk(at time: TimeInterval) {
    chunkStart = time
    silenceStart = nil
    chunkHasSpeech = false
  }
}
