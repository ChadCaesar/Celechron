//
//  WatchECardCredentialStore.swift
//  CelechronWatch
//
//  Stores the campus-card credential as one atomic, device-only Keychain item.
//

import Foundation
import Security

struct WatchECardCredential: Codable, Equatable {
    var auth: String
    var account: String?
    var revision: Int64
    var needsRefresh: Bool

    init(auth: String, account: String?, revision: Int64, needsRefresh: Bool = false) {
        self.auth = auth
        self.account = account
        self.revision = revision
        self.needsRefresh = needsRefresh
    }
}

enum WatchECardCredentialStoreError: Error, Equatable {
    case passcodeRequired
    case encodingFailed
    case keychain(OSStatus)
}

final class WatchECardCredentialStore {
    static let shared = WatchECardCredentialStore()

    private let service = "top.celechron.celechron.watch.ecard"
    private let account = "ecardCredential"
    private let lock = NSLock()

    private init() {}

    func load() -> WatchECardCredential? {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return try? JSONDecoder().decode(WatchECardCredential.self, from: data)
    }

    @discardableResult
    func save(_ credential: WatchECardCredential) -> Result<Void, WatchECardCredentialStoreError> {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(credential) else {
            return .failure(.encodingFailed)
        }

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return .success(())
        }
        guard updateStatus == errSecItemNotFound else {
            return .failure(mapStatus(updateStatus))
        }

        var insert = baseQuery
        attributes.forEach { insert[$0.key] = $0.value }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        return addStatus == errSecSuccess ? .success(()) : .failure(mapStatus(addStatus))
    }

    func markNeedsRefresh() {
        guard var credential = load() else { return }
        credential.needsRefresh = true
        _ = save(credential)
    }

    func delete() {
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
    }

    private func mapStatus(_ status: OSStatus) -> WatchECardCredentialStoreError {
        // Security.framework doesn't expose errSecPasscodeRequired on watchOS.
        // Adding a WhenPasscodeSetThisDeviceOnly item without an enabled device
        // passcode is reported as an authentication failure.
        status == errSecAuthFailed ? .passcodeRequired : .keychain(status)
    }
}

enum WatchECardCredentialMessage {
    static let provisionAction = "provisionPayCredential"
    static let revokeAction = "revokePayCredential"

    static func credential(from message: [String: Any]) -> WatchECardCredential? {
        guard let payload = message["credential"] as? [String: Any],
              let auth = payload["auth"] as? String,
              !auth.isEmpty
        else {
            return nil
        }
        let account = payload["account"] as? String
        let revision: Int64
        if let value = payload["revision"] as? Int64 {
            revision = value
        } else if let value = payload["revision"] as? NSNumber {
            revision = value.int64Value
        } else {
            return nil
        }
        return WatchECardCredential(auth: auth, account: account, revision: revision)
    }

    static func accept(_ credential: WatchECardCredential) -> Result<Void, WatchECardCredentialStoreError> {
        let store = WatchECardCredentialStore.shared
        if let existing = store.load(), existing.revision > credential.revision {
            // A delayed reply must never overwrite a newer credential.
            return .success(())
        }
        return store.save(credential)
    }
}
