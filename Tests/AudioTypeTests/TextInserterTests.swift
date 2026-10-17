import AppKit
import XCTest

@testable import AudioType

/// Clipboard-path tests. They use a private named pasteboard and replace the
/// Cmd+V keystroke with a closure, so no key events are posted.
final class TextInserterTests: XCTestCase {

  private final class Reads {
    var values: [String] = []
  }

  private let longA = String(repeating: "a", count: 40)
  private let longB = String(repeating: "b", count: 40)

  private func makePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("com.audiotype.tests.\(UUID().uuidString)"))
  }

  @MainActor
  func testBackToBackPastesEachDeliverTheirOwnText() async throws {
    let board = makePasteboard()
    defer { board.releaseGlobally() }
    let reads = Reads()
    let inserter = TextInserter(pasteboard: board, pasteSettleDelay: .milliseconds(300)) {
      // A target app that reads the pasteboard 50 ms after Cmd+V.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        reads.values.append(board.string(forType: .string) ?? "")
      }
    }

    await inserter.insertText(longA)
    await inserter.insertText(longB)
    try await Task.sleep(for: .milliseconds(900))

    XCTAssertEqual(reads.values, [longA, longB])
  }

  @MainActor
  func testUserClipboardIsRestoredAfterTheLastPaste() async throws {
    let board = makePasteboard()
    defer { board.releaseGlobally() }
    board.clearContents()
    board.setString("user clip", forType: .string)
    let inserter = TextInserter(pasteboard: board, pasteSettleDelay: .milliseconds(100)) {}

    await inserter.insertText(longA)
    await inserter.insertText(longB)
    try await Task.sleep(for: .milliseconds(450))

    XCTAssertEqual(board.string(forType: .string), "user clip")
  }

  @MainActor
  func testNonTextClipboardIsRestored() async throws {
    let board = makePasteboard()
    defer { board.releaseGlobally() }
    let imageType = NSPasteboard.PasteboardType("com.audiotype.tests.image")
    board.clearContents()
    board.setData(Data([1, 2, 3]), forType: imageType)
    let inserter = TextInserter(pasteboard: board, pasteSettleDelay: .milliseconds(100)) {}

    await inserter.insertText(longA)
    try await Task.sleep(for: .milliseconds(450))

    XCTAssertEqual(board.data(forType: imageType), Data([1, 2, 3]))
  }

  @MainActor
  func testCopyBetweenBackToBackPastesIsKept() async throws {
    let board = makePasteboard()
    defer { board.releaseGlobally() }
    board.clearContents()
    board.setString("old clip", forType: .string)
    let inserter = TextInserter(pasteboard: board, pasteSettleDelay: .milliseconds(100)) {}

    await inserter.insertText(longA)
    // The user or a password manager copies while the restore is pending.
    board.clearContents()
    board.setString("new copy", forType: .string)
    await inserter.insertText(longB)
    try await Task.sleep(for: .milliseconds(450))

    XCTAssertEqual(board.string(forType: .string), "new copy")
  }

  @MainActor
  func testPastedTextIsMarkedTransient() async {
    let board = makePasteboard()
    defer { board.releaseGlobally() }
    var typesAtPaste: [NSPasteboard.PasteboardType] = []
    let inserter = TextInserter(pasteboard: board, pasteSettleDelay: .milliseconds(50)) {
      typesAtPaste = board.types ?? []
    }

    await inserter.insertText(longA)

    // Clipboard managers skip items with this type (nspasteboard.org).
    XCTAssertTrue(typesAtPaste.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")))
    XCTAssertTrue(typesAtPaste.contains(.string))
  }

  @MainActor
  func testNewUserCopyIsNotOverwritten() async throws {
    let board = makePasteboard()
    defer { board.releaseGlobally() }
    board.clearContents()
    board.setString("old clip", forType: .string)
    let inserter = TextInserter(pasteboard: board, pasteSettleDelay: .milliseconds(100)) {}

    await inserter.insertText(longA)
    board.clearContents()
    board.setString("new copy", forType: .string)
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(board.string(forType: .string), "new copy")
  }
}
