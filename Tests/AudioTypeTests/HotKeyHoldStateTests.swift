import XCTest

@testable import AudioType

final class HotKeyHoldStateTests: XCTestCase {

  func testPressAndReleaseSendKeyDownAndKeyUp() {
    var hold = HotKeyHoldState()
    XCTAssertEqual(hold.bindingFlagChanged(isDown: true, at: 0), .keyDown)
    XCTAssertEqual(hold.bindingFlagChanged(isDown: false, at: 2), .keyUp(otherKeyPressed: false))
  }

  func testRepeatedDownFlagIsIgnored() {
    var hold = HotKeyHoldState()
    _ = hold.bindingFlagChanged(isDown: true, at: 0)
    XCTAssertNil(hold.bindingFlagChanged(isDown: true, at: 0.1))
  }

  func testOtherKeySoonAfterPressMarksAShortcut() {
    var hold = HotKeyHoldState()
    _ = hold.bindingFlagChanged(isDown: true, at: 0)
    hold.otherKeyDown(at: 0.2)  // fn+Delete, fn+arrow
    XCTAssertEqual(hold.bindingFlagChanged(isDown: false, at: 0.5), .keyUp(otherKeyPressed: true))
  }

  func testOtherKeyLateInALongHoldIsNotAShortcut() {
    var hold = HotKeyHoldState()
    _ = hold.bindingFlagChanged(isDown: true, at: 0)
    hold.otherKeyDown(at: 3)
    XCTAssertEqual(hold.bindingFlagChanged(isDown: false, at: 5), .keyUp(otherKeyPressed: false))
  }

  func testAutorepeatOfAKeyHeldBeforeThePressIsNotAShortcut() {
    var hold = HotKeyHoldState()
    // Delete was already held down; its autorepeat continues after fn.
    _ = hold.bindingFlagChanged(isDown: true, at: 0)
    hold.otherKeyDown(at: 0.1, isAutorepeat: true)
    XCTAssertEqual(hold.bindingFlagChanged(isDown: false, at: 3), .keyUp(otherKeyPressed: false))
  }

  func testOtherKeyWithoutAHoldIsIgnored() {
    var hold = HotKeyHoldState()
    hold.otherKeyDown(at: 0)
    _ = hold.bindingFlagChanged(isDown: true, at: 0.1)
    XCTAssertEqual(hold.bindingFlagChanged(isDown: false, at: 2), .keyUp(otherKeyPressed: false))
  }

  func testNewHoldClearsTheShortcutMark() {
    var hold = HotKeyHoldState()
    _ = hold.bindingFlagChanged(isDown: true, at: 0)
    hold.otherKeyDown(at: 0.1)
    _ = hold.bindingFlagChanged(isDown: false, at: 0.3)

    _ = hold.bindingFlagChanged(isDown: true, at: 5)
    XCTAssertEqual(hold.bindingFlagChanged(isDown: false, at: 8), .keyUp(otherKeyPressed: false))
  }

  func testBindingChangeDuringAHoldCancelsIt() {
    var hold = HotKeyHoldState()
    _ = hold.bindingFlagChanged(isDown: true, at: 0)
    XCTAssertEqual(hold.reset(), .cancel)
    // The old key's release is no longer a keyUp, and the next press works.
    XCTAssertNil(hold.bindingFlagChanged(isDown: false, at: 1))
    XCTAssertEqual(hold.bindingFlagChanged(isDown: true, at: 2), .keyDown)
  }

  func testBindingChangeWithoutAHoldSendsNothing() {
    var hold = HotKeyHoldState()
    XCTAssertNil(hold.reset())
  }
}
