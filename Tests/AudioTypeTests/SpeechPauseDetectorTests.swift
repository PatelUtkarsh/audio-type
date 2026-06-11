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

  func testCutsAfterSpeechThenPause() {
    var detector = makeDetector()
    // 2s of speech, then sustained pause.
    XCTAssertNil(feed(&detector, level: 0.5, from: 0, to: 2))
    let cutAt = feed(&detector, level: 0.02, from: 2.05, to: 5)
    XCTAssertNotNil(cutAt)
    // Pause begins at ~2.05; cut requires >= 0.7s of it.
    XCTAssertGreaterThanOrEqual(cutAt!, 2.75 - 0.06)
    XCTAssertLessThan(cutAt!, 3.2)
  }

  func testShortPauseDoesNotCut() {
    var detector = makeDetector()
    XCTAssertNil(feed(&detector, level: 0.5, from: 0, to: 2))
    // 0.4s pause - under the 0.7s requirement.
    XCTAssertNil(feed(&detector, level: 0.02, from: 2.05, to: 2.45))
    // Speech resumes; still no cut.
    XCTAssertNil(feed(&detector, level: 0.5, from: 2.5, to: 4))
  }

  func testMinDurationDelaysCutUntilChunkLongEnough() {
    var detector = makeDetector()
    // 0.5s of speech, then silence. Pause condition is met at ~1.2s but the
    // chunk is shorter than minChunkDuration (1.5s); the cut lands once the
    // chunk duration crosses it.
    XCTAssertNil(feed(&detector, level: 0.5, from: 0, to: 0.5))
    let cutAt = feed(&detector, level: 0.02, from: 0.55, to: 4)
    XCTAssertNotNil(cutAt)
    XCTAssertGreaterThanOrEqual(cutAt!, 1.5 - 0.06)
  }

  func testForcedCutOnContinuousSpeech() {
    var detector = makeDetector()
    let cutAt = feed(&detector, level: 0.8, from: 0, to: 60)
    XCTAssertNotNil(cutAt)
    // maxChunkDuration is 15s.
    XCTAssertGreaterThanOrEqual(cutAt!, 15 - 0.06)
    XCTAssertLessThan(cutAt!, 15.5)
  }

  func testLeadingSilenceDoesNotCountTowardDuration() {
    var detector = makeDetector()
    // 20s of leading silence (user holds key, thinks).
    XCTAssertNil(feed(&detector, level: 0.01, from: 0, to: 20))
    // Continuous speech afterwards: forced cut ~15s after speech starts,
    // not instantly (which would happen if leading silence counted).
    let cutAt = feed(&detector, level: 0.8, from: 20.05, to: 60)
    XCTAssertNotNil(cutAt)
    XCTAssertGreaterThanOrEqual(cutAt!, 35 - 0.2)
  }

  func testChunkHasSpeechResetsAfterCut() {
    var detector = makeDetector()
    _ = feed(&detector, level: 0.5, from: 0, to: 2)
    let cutAt = feed(&detector, level: 0.02, from: 2.05, to: 5)
    XCTAssertNotNil(cutAt)
    // Tail after the cut is silence only.
    XCTAssertNil(feed(&detector, level: 0.02, from: cutAt! + 0.05, to: cutAt! + 5))
    XCTAssertFalse(detector.chunkHasSpeech)
  }

  func testNoCutsAfterEnd() {
    var detector = makeDetector()
    _ = feed(&detector, level: 0.5, from: 0, to: 2)
    detector.end()
    XCTAssertNil(feed(&detector, level: 0.02, from: 2.05, to: 10))
  }
}
