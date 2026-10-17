import XCTest

@testable import AudioType

/// Serves canned HTTP responses to URLSession.shared and counts requests.
private final class StubURLProtocol: URLProtocol {
  struct Reply {
    let status: Int
    let headers: [String: String]
    let body: String
  }

  private static let lock = NSLock()
  private static var replies: [Reply] = []
  private static var requests = 0

  static func reset(replies: [Reply]) {
    lock.lock()
    defer { lock.unlock() }
    self.replies = replies
    requests = 0
  }

  static var requestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return requests
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "stub.audiotype.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.requests += 1
    let reply = Self.replies.isEmpty ? Reply(status: 500, headers: [:], body: "") : Self.replies.removeFirst()
    Self.lock.unlock()

    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class StubEngine: WhisperAPIEngine {
  override var config: WhisperAPIConfig {
    WhisperAPIConfig(baseURL: "https://stub.audiotype.test/v1", keychainKey: "unused", providerName: "Stub")
  }
  override var currentModel: String { "stub-model" }
  override var apiKey: String? { "test-key" }
}

final class WhisperAPIEngineTests: XCTestCase {

  private let context = TranscriptionContext(precedingText: nil, isPartial: false)
  private let samples = [Float](repeating: 0, count: 1_600)

  override func setUp() {
    super.setUp()
    URLProtocol.registerClass(StubURLProtocol.self)
  }

  override func tearDown() {
    URLProtocol.unregisterClass(StubURLProtocol.self)
    super.tearDown()
  }

  // MARK: - Prompt field

  private func bodyText(prompt: String?) throws -> String {
    let url = try XCTUnwrap(URL(string: "https://stub.audiotype.test/v1/audio/transcriptions"))
    let (_, body) = WAVEncoder.buildRequest(
      url: url, apiKey: "k", wavData: Data(), model: "m", languageCode: nil, prompt: prompt)
    return String(decoding: body, as: UTF8.self)
  }

  func testRequestSendsThePromptField() throws {
    let body = try bodyText(prompt: "I want to")
    XCTAssertTrue(body.contains("name=\"prompt\"\r\n\r\nI want to\r\n"))
  }

  func testRequestOmitsAnEmptyPrompt() throws {
    XCTAssertFalse(try bodyText(prompt: "").contains("name=\"prompt\""))
    XCTAssertFalse(try bodyText(prompt: nil).contains("name=\"prompt\""))
  }

  // MARK: - API key input

  func testPastedApiKeyIsTrimmed() throws {
    XCTAssertEqual(try WhisperAPIEngine.normalizedApiKey("  gsk_abc123\n"), "gsk_abc123")
  }

  func testBlankApiKeyIsRejected() {
    XCTAssertThrowsError(try WhisperAPIEngine.normalizedApiKey(" \n\t"))
  }

  // MARK: - Rate limit retry

  func testShortRateLimitIsRetriedOnce() async throws {
    StubURLProtocol.reset(replies: [
      .init(status: 429, headers: ["Retry-After": "0"], body: "{}"),
      .init(status: 200, headers: [:], body: "{\"text\":\"hello\"}")
    ])

    let text = try await StubEngine().transcribe(samples: samples, context: context)

    XCTAssertEqual(text, "hello")
    XCTAssertEqual(StubURLProtocol.requestCount, 2)
  }

  func testLongRetryAfterFailsWithoutRetry() async {
    StubURLProtocol.reset(replies: [
      .init(status: 429, headers: ["Retry-After": "30"], body: "{}")
    ])

    do {
      _ = try await StubEngine().transcribe(samples: samples, context: context)
      XCTFail("Expected a rate-limit error")
    } catch {
      XCTAssertEqual(error.localizedDescription, WhisperAPIError.rateLimited.localizedDescription)
    }
    XCTAssertEqual(StubURLProtocol.requestCount, 1)
  }

  func testSecondRateLimitFails() async {
    StubURLProtocol.reset(replies: [
      .init(status: 429, headers: ["Retry-After": "0"], body: "{}"),
      .init(status: 429, headers: ["Retry-After": "0"], body: "{}")
    ])

    do {
      _ = try await StubEngine().transcribe(samples: samples, context: context)
      XCTFail("Expected a rate-limit error")
    } catch {
      XCTAssertEqual(error.localizedDescription, WhisperAPIError.rateLimited.localizedDescription)
    }
    XCTAssertEqual(StubURLProtocol.requestCount, 2)
  }
}
