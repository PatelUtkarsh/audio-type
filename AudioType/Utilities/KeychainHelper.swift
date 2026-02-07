import Foundation

/// Stores secrets (e.g. API keys) in a file within Application Support
/// with restricted file permissions (owner-only read/write).
///
/// We avoid the macOS Keychain because unsigned/ad-hoc signed apps get
/// repeated Keychain permission prompts on every rebuild or code-sign change.
enum KeychainHelper {
  private static var storageURL: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let dir = appSupport.appendingPathComponent("AudioType")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(".secrets")
  }

  /// Save a value.
  static func save(key: String, value: String) throws {
    var store = loadStore()
    store[key] = value
    try writeStore(store)
  }

  /// Retrieve a value.
  static func get(key: String) -> String? {
    let store = loadStore()
    return store[key]
  }

  /// Delete a value.
  @discardableResult
  static func delete(key: String) -> Bool {
    var store = loadStore()
    guard store.removeValue(forKey: key) != nil else { return false }
    do {
      try writeStore(store)
      return true
    } catch {
      return false
    }
  }

  // MARK: - Private

  private static func loadStore() -> [String: String] {
    let url = storageURL
    guard FileManager.default.fileExists(atPath: url.path),
      let data = try? Data(contentsOf: url),
      let dict = try? JSONDecoder().decode([String: String].self, from: data)
    else {
      return [:]
    }
    return dict
  }

  private static func writeStore(_ store: [String: String]) throws {
    let url = storageURL
    let data = try JSONEncoder().encode(store)
    try data.write(to: url, options: .atomic)

    // Restrict file permissions to owner-only (0600)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

enum KeychainError: Error, LocalizedError {
  case encodingFailed
  case saveFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .encodingFailed:
      return "Failed to encode value"
    case .saveFailed(let status):
      return "Save failed with status: \(status)"
    }
  }
}
