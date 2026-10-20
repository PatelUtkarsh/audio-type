import XCTest

@testable import AudioType

final class LiveChunkJoinerTests: XCTestCase {

  // MARK: - Held-back period at a pause cut

  func testMidSentenceCutDropsTheChunkPeriod() throws {
    var joiner = LiveChunkJoiner()
    let first = try XCTUnwrap(joiner.append("I want to.", isFinal: false))
    XCTAssertEqual(first, .init(terminator: "", text: "I want to", startsSentence: true))

    let second = try XCTUnwrap(joiner.append("go to the store.", isFinal: true))
    XCTAssertEqual(second, .init(terminator: "", text: "go to the store.", startsSentence: false))
  }

  func testNewSentenceTypesTheHeldPeriodFirst() throws {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("I went home.", isFinal: false)

    let next = try XCTUnwrap(joiner.append("Then I slept.", isFinal: true))
    XCTAssertEqual(next, .init(terminator: ".", text: "Then I slept.", startsSentence: true))
  }

  func testFinishTypesTheHeldPeriodOnce() {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("We are done.", isFinal: false)
    XCTAssertEqual(joiner.finish(), ".")
    XCTAssertEqual(joiner.finish(), "")
  }

  func testEllipsisAtACutIsHeldBack() throws {
    var joiner = LiveChunkJoiner()
    let first = try XCTUnwrap(joiner.append("I was going to...", isFinal: false))
    XCTAssertEqual(first.text, "I was going to")

    let next = try XCTUnwrap(joiner.append("go home.", isFinal: true))
    XCTAssertEqual(next.terminator, "")
  }

  func testQuestionMarkIsNotHeldBack() throws {
    var joiner = LiveChunkJoiner()
    let first = try XCTUnwrap(joiner.append("Are you there?", isFinal: false))
    XCTAssertEqual(first.text, "Are you there?")

    let next = try XCTUnwrap(joiner.append("Yes.", isFinal: true))
    XCTAssertEqual(next.terminator, "")
  }

  func testFinalChunkKeepsItsPeriod() throws {
    var joiner = LiveChunkJoiner()
    let only = try XCTUnwrap(joiner.append("Done.", isFinal: true))
    XCTAssertEqual(only.text, "Done.")
    XCTAssertEqual(joiner.finish(), "")
  }

  func testDigitStartContinuesTheSentence() throws {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("The meeting is at.", isFinal: false)

    let next = try XCTUnwrap(joiner.append("3 pm today.", isFinal: true))
    XCTAssertEqual(next, .init(terminator: "", text: "3 pm today.", startsSentence: false))
  }

  func testAbbreviationAtTheEndIsNotHeldBack() throws {
    var joiner = LiveChunkJoiner()
    let first = try XCTUnwrap(joiner.append("We moved to the U.S.", isFinal: false))
    XCTAssertEqual(first.text, "We moved to the U.S.")
  }

  func testDottedNameAtTheEndIsHeldBack() throws {
    var joiner = LiveChunkJoiner()
    let first = try XCTUnwrap(joiner.append("We use Node.js.", isFinal: false))
    XCTAssertEqual(first.text, "We use Node.js")

    let next = try XCTUnwrap(joiner.append("for the backend.", isFinal: true))
    XCTAssertEqual(next.terminator, "")
  }

  func testDecimalAtTheEndIsHeldBack() throws {
    var joiner = LiveChunkJoiner()
    let first = try XCTUnwrap(joiner.append("Pi is about 3.14.", isFinal: false))
    XCTAssertEqual(first.text, "Pi is about 3.14")
  }

  func testCapitalStartAfterAJoiningWordContinuesTheSentence() throws {
    var joiner = LiveChunkJoiner()
    // "and" cannot end a sentence, so the period is wrong even though the
    // next chunk starts with "I".
    _ = joiner.append("I came home and.", isFinal: false)

    let next = try XCTUnwrap(joiner.append("I went to bed.", isFinal: true))
    XCTAssertEqual(next, .init(terminator: "", text: "I went to bed.", startsSentence: false))
  }

  func testPunctuationOnlyChunkIsIgnored() {
    var joiner = LiveChunkJoiner()
    XCTAssertNil(joiner.append("...", isFinal: false))
    XCTAssertNil(joiner.append("   ", isFinal: true))
    XCTAssertFalse(joiner.hasText)
  }

  // MARK: - Recorded whisper-large-v3 output (Groq, synthetic speech)

  func testRecordedPauseAfterToBecomesOneSentence() throws {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("Yesterday after work, I really wanted to.", isFinal: false)

    // Sent with the prompt "Yesterday after work, I really wanted to".
    let next = try XCTUnwrap(
      joiner.append("go to the store and buy some milk.", isFinal: true, sentWithPrompt: true))
    XCTAssertEqual(next.terminator, "")
    XCTAssertEqual(joiner.finish(), "")
  }

  func testRecordedSentenceEndKeepsBothPeriods() throws {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("Yesterday, I finished the report and sent it to the team.", isFinal: false)

    // With a prompt that has no final period, the model left out its own.
    let next = try XCTUnwrap(
      joiner.append("Then I went home and slept", isFinal: true, sentWithPrompt: true))
    XCTAssertEqual(next.terminator, ".")
    XCTAssertEqual(joiner.finish(), ".")
  }

  // MARK: - Missing period after a prompt

  func testUnpunctuatedChunkSentWithPromptLetsTheNextChunkDecide() throws {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("We need to review.", isFinal: false)
    _ = joiner.append("the quarterly numbers", isFinal: false, sentWithPrompt: true)

    let last = try XCTUnwrap(joiner.append("with the team", isFinal: true, sentWithPrompt: true))
    XCTAssertEqual(last.terminator, "")
    XCTAssertEqual(joiner.finish(), ".")
  }

  func testUnpunctuatedChunksWithoutPromptGetNoPeriods() throws {
    var joiner = LiveChunkJoiner()
    // Apple Speech: no prompt and no punctuation in Live Typing chunks.
    _ = joiner.append("I want to", isFinal: false)

    let next = try XCTUnwrap(joiner.append("Go to the store", isFinal: true))
    XCTAssertEqual(next.terminator, "")
    XCTAssertEqual(joiner.finish(), "")
  }

  // MARK: - Prompt context for the next request

  func testPromptIsNilBeforeAnyText() {
    let joiner = LiveChunkJoiner()
    XCTAssertNil(joiner.prompt())
  }

  func testPromptLeavesOutTheHeldPeriod() {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("I want to.", isFinal: false)
    XCTAssertEqual(joiner.prompt(), "I want to")
  }

  func testPromptIncludesATypedPeriod() {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("I went home.", isFinal: false)
    _ = joiner.append("Then I slept", isFinal: false)
    XCTAssertEqual(joiner.prompt(), "I went home. Then I slept")
  }

  func testPromptKeepsTheEndWithinTheByteLimitAtAWordStart() {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("alpha bravo charlie delta echo foxtrot", isFinal: false)
    XCTAssertEqual(joiner.prompt(maxUTF8Bytes: 20), "delta echo foxtrot")
  }

  func testPromptCountsMultiByteCharacters() {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("今日はいい天気です", isFinal: false)
    XCTAssertEqual(joiner.prompt(maxUTF8Bytes: 12), "天気です")
  }

  // MARK: - Prompt echo

  func testEchoOfThePromptIsDropped() {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("We should ship the release on Friday.", isFinal: false)
    XCTAssertNil(joiner.append("Ship the release on Friday.", isFinal: true))
  }

  func testShortRepeatIsNotAnEcho() {
    var joiner = LiveChunkJoiner()
    _ = joiner.append("Say no.", isFinal: false)
    XCTAssertNotNil(joiner.append("No.", isFinal: true))
  }
}
