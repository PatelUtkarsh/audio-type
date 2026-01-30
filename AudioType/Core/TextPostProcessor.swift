import Foundation

/// Post-processes transcribed text to fix common errors and improve accuracy
class TextPostProcessor {
  static let shared = TextPostProcessor()

  // Common misheard words/phrases and their corrections
  // These are case-insensitive replacements
  private var wordReplacements: [String: String] = [
    // Tech terms often misheard
    "bit of action": "GitHub",
    "git hub": "GitHub",
    "get hub": "GitHub",
    "gith hub": "GitHub",
    "big hub": "GitHub",
    "kick hub": "GitHub",
    "good hub": "GitHub",
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
    "my sequel": "MySQL",
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
    "graphical": "GraphQL",
    "c i c d": "CI/CD",
    "c i d d": "CI/CD",

    // Programming terms
    "jason": "JSON",
    "j son": "JSON",
    "html": "HTML",
    "h t m l": "HTML",
    "css": "CSS",
    "c s s": "CSS",
    "sql": "SQL",
    "s q l": "SQL",
    "sequel": "SQL",
    "no sequel": "NoSQL",
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

    // Commands
    "new line": "\n",
    "newline": "\n",
    "new paragraph": "\n\n",
    "period": ".",
    "comma": ",",
    "question mark": "?",
    "exclamation mark": "!",
    "exclamation point": "!",
    "colon": ":",
    "semicolon": ";",
    "open parenthesis": "(",
    "close parenthesis": ")",
    "open bracket": "[",
    "close bracket": "]",
    "open brace": "{",
    "close brace": "}",
  ]

  // User-defined custom replacements
  private var customReplacements: [String: String] = [:]

  private init() {
    loadCustomReplacements()
  }

  /// Process transcribed text with corrections
  func process(_ text: String) -> String {
    var result = text

    // Apply word replacements (case-insensitive)
    let allReplacements = wordReplacements.merging(customReplacements) { _, custom in custom }

    for (pattern, replacement) in allReplacements {
      result = result.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: .caseInsensitive
      )
    }

    // Capitalize first letter of sentences
    result = capitalizeSentences(result)

    return result
  }

  /// Add a custom word replacement
  func addCustomReplacement(from: String, to: String) {
    customReplacements[from.lowercased()] = to
    saveCustomReplacements()
  }

  /// Remove a custom replacement
  func removeCustomReplacement(from: String) {
    customReplacements.removeValue(forKey: from.lowercased())
    saveCustomReplacements()
  }

  /// Get all custom replacements
  func getCustomReplacements() -> [String: String] {
    return customReplacements
  }

  // MARK: - Private

  private func capitalizeSentences(_ text: String) -> String {
    var result = ""
    var capitalizeNext = true

    for char in text {
      if capitalizeNext && char.isLetter {
        result.append(char.uppercased())
        capitalizeNext = false
      } else {
        result.append(char)
      }

      if char == "." || char == "!" || char == "?" || char == "\n" {
        capitalizeNext = true
      }
    }

    return result
  }

  private func loadCustomReplacements() {
    if let data = UserDefaults.standard.data(forKey: "customWordReplacements"),
      let replacements = try? JSONDecoder().decode([String: String].self, from: data)
    {
      customReplacements = replacements
    }
  }

  private func saveCustomReplacements() {
    if let data = try? JSONEncoder().encode(customReplacements) {
      UserDefaults.standard.set(data, forKey: "customWordReplacements")
    }
  }
}
