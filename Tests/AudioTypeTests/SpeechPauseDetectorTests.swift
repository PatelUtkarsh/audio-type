import XCTest

@testable import AudioType

final class SpeechPauseDetectorTests: XCTestCase {

  /// Feed a constant level over a time range at a fixed step, returning the
  /// first time `update` says cut, or nil.
  private func feed(
    _ detector: inout SpeechPauseDetector,
    level: Float,
    from start: TimeInterval,
    to end: TimeInterval,
    step: TimeInterval = 0.05
  ) -> TimeInterval? {
    var time = start
    while time <= end {
      if detector.update(level: level, at: time) == .cut {
        return time
      }
      time += step
    }
    return nil
  }

  private func makeDetector() -> SpeechPauseDetector {
    var detector = SpeechPauseDetector()
    detector.begin(at: 0)
    return detector
  }

  func testSilenceOnlyNeverCuts() {
    var detector = makeDetector()
    let cutAt = feed(&detector, level: 0.01, from: 0, to: 60)
    XCTAssertNil(cutAt)
    XCTAssertFalse(detector.chunkHasSpeech)
  }

  func testCutsAfterSpeechThenPause() throws {
    var detector = makeDetector()
    // 3.5s of speech, then sustained pause.
    XCTAssertNil(feed(&detector, level: 0.5, from: 0, to: 3.5))
    let cutAt = try XCTUnwrap(feed(&detector, level: 0.02, from: 3.55, to: 6))
    // Pause begins at ~3.55; a normal chunk needs >= 1.0s of it.
    XCTAssertGreaterThanOrEqual(cutAt, 4.55 - 0.06)
    XCTAssertLessThan(cutAt, 4.7)
  }

  func testShortPauseDoesNotCut() {
    var detector = makeDetector()
    XCTAssertNil(feed(&detector, level: 0.5, from: 0, to: 2))
    // 0.4s pause - well under the requirement.
    XCTAssertNil(feed(&detector, level: 0.02, from: 2.05, to: 2.45))
    // Speech resumes; still no cut.
    XCTAssertNil(feed(&detector, level: 0.5, from: 2.5, to: 4))
  }

  func testPauseInsideShortPhraseDoesNotCut() {
    var detector = makeDetector()
    // A 0.8s breath or hesitation inside a sentence is not a chunk boundary.
    XCTAssertNil(feed(&detector, level: 0.5, from: 0, to: 2))
    XCTAssertNil(feed(&detector, level: 0.02, from: 2.05, to: 2.85))
    XCTAssertNil(feed(&detector, level: 0.5, from: 2.9, to: 4))
  }

  func testShorterPauseCutsLongChunk() throws {
    var detector = makeDetector()
    // Past 6s a 0.7s pause is enough, so long monologues still stream.
    XCTAssertNil(feed(&detector, level: 0.5, from: 0, to: 7))
    let cutAt = try XCTUnwrap(feed(&detector, level: 0.02, from: 7.05, to: 9))
    XCTAssertGreaterThanOrEqual(cutAt, 7.75 - 0.06)
    XCTAssertLessThan(cutAt, 7.9)
  }

  func testMinDurationDelaysCutUntilChunkLongEnough() throws {
    var detector = makeDetector()
    // 0.5s of speech, then silence. The pause condition is met at ~1.55s
    // but the chunk is shorter than minChunkDuration (3s); the cut lands
    // once the chunk duration crosses it.
    XCTAssertNil(feed(&detector, level: 0.5, from: 0, to: 0.5))
    let cutAt = try XCTUnwrap(feed(&detector, level: 0.02, from: 0.55, to: 5))
    XCTAssertGreaterThanOrEqual(cutAt, 3 - 0.06)
    XCTAssertLessThan(cutAt, 3.1)
  }

  func testShortDipCutsPastMaxDuration() throws {
    var detector = makeDetector()
    // Continuous speech past maxChunkDuration (15s) does not cut at once;
    // the cut waits for a short dip between words.
    XCTAssertNil(feed(&detector, level: 0.8, from: 0, to: 16))
    let cutAt = try XCTUnwrap(feed(&detector, level: 0.02, from: 16.05, to: 17))
    XCTAssertGreaterThanOrEqual(cutAt, 16.3 - 0.06)
    XCTAssertLessThan(cutAt, 16.45)
  }

  func testForcedCutOnContinuousSpeech() throws {
    var detector = makeDetector()
    let cutAt = try XCTUnwrap(feed(&detector, level: 0.8, from: 0, to: 60))
    // No dip at all: hardMaxChunkDuration (17s) forces the cut.
    XCTAssertGreaterThanOrEqual(cutAt, 17 - 0.06)
    XCTAssertLessThan(cutAt, 17.2)
  }

  func testLeadingSilenceDoesNotCountTowardDuration() throws {
    var detector = makeDetector()
    // 20s of leading silence (user holds key, thinks).
    XCTAssertNil(feed(&detector, level: 0.01, from: 0, to: 20))
    // Continuous speech afterwards: forced cut ~17s after speech starts,
    // not instantly (which would happen if leading silence counted).
    let cutAt = try XCTUnwrap(feed(&detector, level: 0.8, from: 20.05, to: 60))
    XCTAssertGreaterThanOrEqual(cutAt, 37 - 0.2)
  }

  func testChunkHasSpeechResetsAfterCut() throws {
    var detector = makeDetector()
    _ = feed(&detector, level: 0.5, from: 0, to: 3.5)
    let cutAt = try XCTUnwrap(feed(&detector, level: 0.02, from: 3.55, to: 6))
    // Tail after the cut is silence only.
    XCTAssertNil(feed(&detector, level: 0.02, from: cutAt + 0.05, to: cutAt + 5))
    XCTAssertFalse(detector.chunkHasSpeech)
  }

  func testNoCutsAfterEnd() {
    var detector = makeDetector()
    _ = feed(&detector, level: 0.5, from: 0, to: 2)
    detector.end()
    XCTAssertNil(feed(&detector, level: 0.02, from: 2.05, to: 10))
  }
}
