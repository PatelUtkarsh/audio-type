import Foundation

/// Post-processes transcribed text to fix common errors and improve accuracy
class TextPostProcessor {
  static let shared = TextPostProcessor()

  // Common misheard words/phrases and their corrections.
  // Case-insensitive, whole-word replacements. Keys that are also normal
  // English words or phrases ("jason", "sequel", "big hub", "period") are
  // left out on purpose: they changed ordinary sentences.
  private var wordReplacements: [String: String] = [
    // Tech terms often misheard
    "git hub": "GitHub",
    "get hub": "GitHub",
    "gith hub": "GitHub",
    "kick hub": "GitHub",
    "j query": "jQuery",
    "jake weary": "jQuery",
    "java script": "JavaScript",
    "type script": "TypeScript",
    "node js": "Node.js",
    "node jazz": "Node.js",
    "react js": "React.js",
    "next js": "Next.js",
    "view js": "Vue.js",
    "mongo db": "MongoDB",
    "post gress": "Postgres",
    "post grass": "Postgres",
    "postgres q l": "PostgreSQL",
    "redis": "Redis",
    "docker": "Docker",
    "cooper net ease": "Kubernetes",
    "cooper nettys": "Kubernetes",
    "cube control": "kubectl",
    "aws": "AWS",
    "a w s": "AWS",
    "gcp": "GCP",
    "azure": "Azure",
    "api": "API",
    "a p i": "API",
    "rest api": "REST API",
    "graph q l": "GraphQL",
    "c i c d": "CI/CD",
    "c i d d": "CI/CD",

    // Programming terms
    "j son": "JSON",
    "html": "HTML",
    "h t m l": "HTML",
    "css": "CSS",
    "c s s": "CSS",
    "sql": "SQL",
    "s q l": "SQL",
    "http": "HTTP",
    "h t t p": "HTTP",
    "https": "HTTPS",
    "url": "URL",
    "u r l": "URL",
    "ssh": "SSH",
    "s s h": "SSH",
    "ssl": "SSL",
    "tls": "TLS",
    "oauth": "OAuth",
    "o auth": "OAuth",
    "jwt": "JWT",
    "j w t": "JWT",

    // Common corrections
    "i'm": "I'm",
    "i'll": "I'll",
    "i've": "I've",
    "i'd": "I'd",
    "can't": "can't",
    "won't": "won't",
    "don't": "don't",
    "doesn't": "doesn't",
    "wouldn't": "wouldn't",
    "couldn't": "couldn't",
    "shouldn't": "shouldn't",

    // Commands. Only phrases that are rare in normal speech; the cloud
    // models already add punctuation.
    "new line": "\n",
    "newline": "\n",
    "new paragraph": "\n\n",
    "question mark": "?",
    "exclamation mark": "!",
    "exclamation point": "!",
    "semicolon": ";",
    "open parenthesis": "(",
    "close parenthesis": ")",
    "open bracket": "[",
    "close bracket": "]",
    "open brace": "{",
    "close brace": "}"
  ]

  // User-defined custom replacements
  private var customReplacements: [String: String] = [:]

  // Cached compiled regex + lookup table. Rebuilt only when the catalog
  // changes (custom replacements added/removed). The previous code rebuilt
  // a merged dictionary and ran ~85 case-insensitive String scans on every
  // single transcription.
  private var cachedRegex: NSRegularExpression?
  private var cachedLookup: [String: String] = [:]
  private let regexLock = NSLock()

  private init() {
    loadCustomReplacements()
    rebuildRegex()
  }

  /// Process transcribed text with corrections.
  ///
  /// `capitalizeFirst` controls whether the first letter gets uppercased.
  /// Live typing passes false when the previous chunk didn't end a sentence,
  /// so a chunk continuing mid-sentence isn't wrongly capitalized.
  func process(_ text: String, capitalizeFirst: Bool = true) -> String {
    let result = applyReplacements(text)
    return capitalizeSentences(result, capitalizeFirst: capitalizeFirst)
  }

  /// Add a custom word replacement
  func addCustomReplacement(from: String, to: String) {
    customReplacements[from.lowercased()] = to
    saveCustomReplacements()
    rebuildRegex()
  }

  /// Remove a custom replacement
  func removeCustomReplacement(from: String) {
    customReplacements.removeValue(forKey: from.lowercased())
    saveCustomReplacements()
    rebuildRegex()
  }

  /// Get all custom replacements
  func getCustomReplacements() -> [String: String] {
    return customReplacements
  }

  // MARK: - Private

  /// Rebuild the compiled regex from the current built-in + custom catalogs.
  /// Custom replacements override built-ins on key collision.
  private func rebuildRegex() {
    regexLock.lock()
    defer { regexLock.unlock() }

    let merged = wordReplacements.merging(customReplacements) { _, custom in custom }
    cachedLookup = [:]
    cachedLookup.reserveCapacity(merged.count)
    for (key, value) in merged {
      cachedLookup[key.lowercased()] = value
    }

    // Sort keys longest-first so e.g. "rest api" wins over "api". This also
    // gives us a deterministic order independent of dictionary hashing,
    // which the old implementation lacked. Word boundaries stop a key from
    // matching inside a longer word ("api" in "rapid", "aws" in "laws").
    let keys = merged.keys.sorted { $0.count > $1.count }
    let alternatives = keys.map { NSRegularExpression.escapedPattern(for: $0) }
      .joined(separator: "|")
    let pattern = "\\b(?:\(alternatives))\\b"

    cachedRegex = try? NSRegularExpression(
      pattern: pattern,
      options: [.caseInsensitive]
    )
  }

  /// Apply replacements in a single regex pass.
  private func applyReplacements(_ text: String) -> String {
    regexLock.lock()
    let regex = cachedRegex
    let lookup = cachedLookup
    regexLock.unlock()

    guard let regex = regex, !text.isEmpty else { return text }

    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    let matches = regex.matches(in: text, options: [], range: range)
    if matches.isEmpty { return text }

    // Reassemble in one pass, alternating original spans and replacements.
    var result = ""
    result.reserveCapacity(text.count)
    var cursor = 0
    for match in matches {
      let r = match.range
      if r.location > cursor {
        result.append(
          nsText.substring(with: NSRange(location: cursor, length: r.location - cursor))
        )
      }
      let matched = nsText.substring(with: r).lowercased()
      if let replacement = lookup[matched] {
        result.append(replacement)
      } else {
        result.append(nsText.substring(with: r))
      }
      cursor = r.location + r.length
    }
    if cursor < nsText.length {
      result.append(
        nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
      )
    }
    return result
  }

  /// Characters that can come before the first letter of a sentence.
  private static let sentenceOpeners: Set<Character> = ["\"", "'", "“", "‘", "(", "[", "«", "¿", "¡"]

  /// Uppercases the first letter of each sentence; never lowercases. A
  /// sentence starts at a newline, or after ".", "!" or "?" that a space
  /// follows. A dot inside a token ("Node.js", "3.5", "example.com"), an
  /// ellipsis, or an abbreviation with an inner dot ("e.g.") does not end
  /// a sentence.
  private func capitalizeSentences(_ text: String, capitalizeFirst: Bool) -> String {
    let chars = Array(text)
    var result = ""
    result.reserveCapacity(text.count)
    var capitalizeNext = capitalizeFirst

    for (index, char) in chars.enumerated() {
      if capitalizeNext && char.isLetter {
        result.append(contentsOf: char.uppercased())
        capitalizeNext = false
        continue
      }
      result.append(char)

      if char == "\n" || Self.endsSentence(chars, at: index) {
        capitalizeNext = true
      } else if capitalizeNext && !char.isWhitespace && !Self.sentenceOpeners.contains(char) {
        // The sentence starts with a digit or symbol; leave the next word alone.
        capitalizeNext = false
      }
    }

    return result
  }

  private static func endsSentence(_ chars: [Character], at index: Int) -> Bool {
    let char = chars[index]
    guard char == "." || char == "!" || char == "?" else { return false }
    guard index + 1 < chars.count, chars[index + 1].isWhitespace else { return false }
    guard char == "." else { return true }

    // Walk back over the token that ends with this dot. Another dot in it
    // means an ellipsis ("...") or an abbreviation ("e.g.", "U.S.").
    var cursor = index - 1
    while cursor >= 0 && !chars[cursor].isWhitespace {
      if chars[cursor] == "." { return false }
      cursor -= 1
    }
    return true
  }

  private func loadCustomReplacements() {
    if let data = UserDefaults.standard.data(forKey: "customWordReplacements"),
      let replacements = try? JSONDecoder().decode([String: String].self, from: data) {
      customReplacements = replacements
    }
  }

  private func saveCustomReplacements() {
    if let data = try? JSONEncoder().encode(customReplacements) {
      UserDefaults.standard.set(data, forKey: "customWordReplacements")
    }
  }
}
