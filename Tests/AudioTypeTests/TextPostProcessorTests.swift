import XCTest

@testable import AudioType

final class TextPostProcessorTests: XCTestCase {

  private func process(_ text: String, capitalizeFirst: Bool = true) -> String {
    TextPostProcessor.shared.process(text, capitalizeFirst: capitalizeFirst)
  }

  // MARK: - Replacements match whole words only

  func testKeyInsideLongerWordIsNotReplaced() {
    XCTAssertEqual(process("Run the command in the terminal."), "Run the command in the terminal.")
  }

  func testAcronymKeysInsideWordsAreNotReplaced() {
    XCTAssertEqual(process("The new laws are rapid."), "The new laws are rapid.")
  }

  func testPunctuationWordsInsideLongerWordsAreNotReplaced() {
    XCTAssertEqual(process("We check it periodically."), "We check it periodically.")
  }

  func testWholeWordTechTermsAreStillReplaced() {
    XCTAssertEqual(process("push it to git hub and call the rest api"), "Push it to GitHub and call the REST API")
  }

  // MARK: - Normal words keep their meaning

  func testPeriodAsAWordIsKept() {
    XCTAssertEqual(process("Over a period of three months."), "Over a period of three months.")
  }

  func testCommaAndColonAsWordsAreKept() {
    XCTAssertEqual(process("A comma and a colon."), "A comma and a colon.")
  }

  func testNamesAndCommonWordsAreNotReplaced() {
    XCTAssertEqual(process("I met Jason at the colony."), "I met Jason at the colony.")
  }

  func testCommonPhrasesAreNotReplaced() {
    XCTAssertEqual(
      process("A bit of action in a big hub, a graphical sequel."),
      "A bit of action in a big hub, a graphical sequel."
    )
  }

  func testNewLineCommandStillInsertsALineBreak() {
    XCTAssertTrue(process("first line new line second line").contains("\n"))
  }

  // MARK: - Capitalization only after a real sentence end

  func testNoCapitalAfterDotInsideWord() {
    XCTAssertEqual(process("We use node js and next js."), "We use Node.js and Next.js.")
  }

  func testNoCapitalAfterDecimalPoint() {
    XCTAssertEqual(process("Version 3.5 is out."), "Version 3.5 is out.")
  }

  func testNoCapitalAfterDotInDomainName() {
    XCTAssertEqual(process("Open example.com now."), "Open example.com now.")
  }

  func testNoCapitalAfterEllipsis() {
    XCTAssertEqual(process("I was thinking... maybe later."), "I was thinking... maybe later.")
  }

  func testNoCapitalAfterAbbreviationWithInnerDot() {
    XCTAssertEqual(process("Use tabs, e.g. spaces are worse."), "Use tabs, e.g. spaces are worse.")
  }

  func testCapitalAfterSentenceEndAndSpace() {
    XCTAssertEqual(process("hello. world? yes! ok"), "Hello. World? Yes! Ok")
  }

  func testCapitalizeFirstFalseKeepsLowercaseStart() {
    XCTAssertEqual(process("and then we left.", capitalizeFirst: false), "and then we left.")
  }
}
