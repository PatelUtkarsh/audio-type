import Foundation

/// Joins the separately transcribed chunks of one Live Typing session into
/// the text to type, and removes the sentence ends that pause cuts add.
///
/// A model that gets one chunk alone treats it as a full sentence and ends
/// it with "." even when the speaker only paused. The joiner holds back the
/// final "." or "..." of a non-final chunk. The next chunk is transcribed
/// with the session text as its prompt, so its first letter shows whether it
/// continues the sentence: lowercase (or a digit) drops the held period;
/// anything else types the period first. `finish()` returns a period that
/// is still held when the session ends.
///
/// Pure state machine with no I/O, like `SpeechPauseDetector`, so the
/// policy is unit-testable.
struct LiveChunkJoiner {

  /// What to type for one chunk, in this order.
  struct Insertion: Equatable {
    /// Sentence end held back from the previous chunk ("" when none).
    let terminator: String
    /// The chunk text, trimmed, without a held-back final period.
    let text: String
    /// Whether `text` starts a new sentence (capitalize its first letter).
    let startsSentence: Bool
  }

  /// A chunk must have at least this many letters and digits before it can
  /// count as an echo of the prompt, so short real repeats ("no") survive.
  private static let minimumEchoLength = 12

  /// Session text as the model wrote it, without the held-back period.
  private var transcript = ""
  private var heldTerminator: String?

  /// Whether any chunk of this session produced text.
  var hasText: Bool { !transcript.isEmpty }

  /// Accepts the model output for the next chunk. Returns nil when the
  /// chunk adds nothing: no letters or digits, or only an echo of the
  /// prompt (models can repeat the prompt for near-silent audio).
  mutating func append(_ rawText: String, isFinal: Bool) -> Insertion? {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.contains(where: { $0.isLetter || $0.isNumber }), !isEcho(text) else {
      return nil
    }

    let continuesSentence =
      hasText && (Self.startsMidSentence(text) || Self.endsWithJoiningWord(transcript))
    let terminator = continuesSentence ? "" : (heldTerminator ?? "")
    heldTerminator = nil

    var body = text
    if !isFinal, let period = Self.heldPeriod(at: text) {
      body = String(text.dropLast(period.count)).trimmingCharacters(in: .whitespaces)
      heldTerminator = period
    }

    if hasText {
      transcript += terminator + " "
    }
    transcript += body
    if transcript.count > 2_000 {
      transcript = String(transcript.suffix(1_000))
    }

    return Insertion(terminator: terminator, text: body, startsSentence: !continuesSentence)
  }

  /// Ends the session. Returns the held-back sentence end ("" when none).
  mutating func finish() -> String {
    defer { heldTerminator = nil }
    return heldTerminator ?? ""
  }

  /// Context for the next request: the end of the session text, without the
  /// held-back period. At most `maxUTF8Bytes` long, which keeps it under the
  /// 224-token prompt limit of Whisper on Groq (a token covers at least one
  /// byte). Starts at a word when the text has spaces. Nil before any text.
  func prompt(maxUTF8Bytes: Int = 220) -> String? {
    var bytes = 0
    var start = transcript.endIndex
    for index in transcript.indices.reversed() {
      let size = transcript[index].utf8.count
      if bytes + size > maxUTF8Bytes { break }
      bytes += size
      start = index
    }

    var tail = transcript[start...]
    if start > transcript.startIndex,
      !transcript[transcript.index(before: start)].isWhitespace,
      let space = tail.firstIndex(where: \.isWhitespace) {
      tail = tail[tail.index(after: space)...]
    }
    let result = tail.trimmingCharacters(in: .whitespaces)
    return result.isEmpty ? nil : result
  }

  // MARK: - Private

  private func isEcho(_ text: String) -> Bool {
    let chunk = Self.lettersAndDigits(text)
    guard chunk.count >= Self.minimumEchoLength else { return false }
    return Self.lettersAndDigits(transcript).hasSuffix(chunk)
  }

  private static func lettersAndDigits(_ text: String) -> String {
    String(text.lowercased().filter { $0.isLetter || $0.isNumber })
  }

  /// A chunk transcribed with context continues the sentence when its first
  /// letter is lowercase or it starts with a digit. A capital ("I", a name)
  /// gives no signal.
  private static func startsMidSentence(_ text: String) -> Bool {
    guard let first = text.first(where: { $0.isLetter || $0.isNumber }) else { return false }
    return first.isNumber || first.isLowercase
  }

  /// English words that do not end a sentence. After one of them, a held
  /// period is wrong even when the next chunk starts with a capital
  /// ("and [pause] I went"). Words that can end a sentence ("to", "in",
  /// "can", "it") are left out on purpose.
  private static let joiningWords: Set<String> = [
    "a", "an", "the", "and", "or", "but", "nor", "because", "if", "although",
    "though", "unless", "whether", "than", "when", "while", "of", "with",
    "from", "into", "onto", "between", "during", "without", "my", "your",
    "our", "their", "its", "these", "those", "every", "each", "um", "uh"
  ]

  private static func endsWithJoiningWord(_ text: String) -> Bool {
    guard let lastWord = text.split(whereSeparator: \.isWhitespace).last else { return false }
    let word = lastWord.lowercased().trimmingCharacters(in: .punctuationCharacters)
    return joiningWords.contains(word)
  }

  /// The final "...", "…" or "." to hold back. Never "?" or "!", and not
  /// the dot of a letter abbreviation ("U.S.", "e.g.", "a.m."), which must
  /// stay. A dotted name or number ("Node.js.", "3.14.") is held back.
  private static func heldPeriod(at text: String) -> String? {
    if text.hasSuffix("...") { return "..." }
    if text.hasSuffix("…") { return "…" }
    guard text.hasSuffix(".") else { return nil }
    let lastWord = String(text.split(whereSeparator: \.isWhitespace).last ?? "")
    let isAbbreviation =
      lastWord.range(of: "^(\\p{L}{1,3}\\.){2,}$", options: .regularExpression) != nil
    return isAbbreviation ? nil : "."
  }
}
