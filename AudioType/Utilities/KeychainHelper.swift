import Foundation
import Security
import os.log

/// Stores secrets (e.g. API keys) in the macOS Keychain using the Security framework.
///
/// Each value is stored as a `kSecClassGenericPassword` item keyed by account name,
/// with a service identifier of `com.audiotype.app`.
enum KeychainHelper {
  private static let service = "com.audiotype.app"
  private static let logger = Logger(
    subsystem: "com.audiotype", category: "KeychainHelper"
  )

  // MARK: - Public API

  /// Save a value to the Keychain. Overwrites any existing value for the key.
  static func save(key: String, value: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KeychainError.encodingFailed
    }

    // Delete any existing item first (SecItemAdd fails on duplicates)
    delete(key: key)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      logger.error("Failed to save key \(key), status: \(status)")
      throw KeychainError.saveFailed(status)
    }
    logger.info("Saved value for key: \(key)")
  }

  /// Retrieve a value from the Keychain.
  static func get(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      return nil
    }

    return value
  }

  /// Delete a value from the Keychain.
  @discardableResult
  static func delete(key: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]

    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      return true
    }
    logger.error("Failed to delete key \(key), status: \(status)")
    return false
  }

  // MARK: - Migration from file-based storage

  /// Migrate secrets from the old file-based `.secrets` store to the Keychain.
  /// Call once at app launch. After successful migration the old file is removed.
  static func migrateFromFileStoreIfNeeded() {
    let migrationKey = "keychainMigrationDone"
    guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

    let oldStore = loadLegacyFileStore()
    guard !oldStore.isEmpty else {
      UserDefaults.standard.set(true, forKey: migrationKey)
      return
    }

    logger.info("Migrating \(oldStore.count) secret(s) from file store to Keychain")
    for (key, value) in oldStore {
      do {
        try save(key: key, value: value)
        logger.info("Migrated key: \(key)")
      } catch {
        logger.error("Failed to migrate key \(key): \(error.localizedDescription)")
      }
    }

    // Remove old file
    let url = legacyStorageURL
    try? FileManager.default.removeItem(at: url)
    logger.info("Removed legacy .secrets file")

    UserDefaults.standard.set(true, forKey: migrationKey)
  }

  // MARK: - Legacy file helpers

  private static var legacyStorageURL: URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let dir = appSupport.appendingPathComponent("AudioType")
    return dir.appendingPathComponent(".secrets")
  }

  private static func loadLegacyFileStore() -> [String: String] {
    let url = legacyStorageURL
    guard FileManager.default.fileExists(atPath: url.path),
      let data = try? Data(contentsOf: url),
      let dict = try? JSONDecoder().decode(
        [String: String].self, from: data
      )
    else {
      return [:]
    }
    return dict
  }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
  case encodingFailed
  case saveFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .encodingFailed:
      return "Failed to encode value for Keychain storage."
    case .saveFailed(let status):
      return "Keychain save failed with status: \(status)"
    }
  }
}
