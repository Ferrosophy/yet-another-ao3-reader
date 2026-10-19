import Foundation
import Security

/// API Key 只保存在本機鑰匙圈：
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`：不隨備份遷移到其他裝置
/// - `kSecAttrSynchronizable = false`：不經 iCloud 鑰匙圈同步
/// 應用本身沒有帳戶系統，金鑰不會上傳或綁定到任何服務，只在呼叫對應翻譯 API 時作為請求標頭送出。
enum KeychainStore {
    private static let service = "AO3Reader.APIKeys"
    /// 同步服務（WebDAV）的密碼另外存放，「刪除所有 API Key」不會清除
    static let syncService = "AO3Reader.Sync"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    private static func baseQuery(_ account: String, service: String = service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func save(_ value: String, account: String, service: String = service) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery(account, service: service) as CFDictionary)
        guard !trimmed.isEmpty else { return }

        var query = baseQuery(account, service: service)
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func read(account: String, service: String = service) -> String? {
        var query = baseQuery(account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    static func deleteAll() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }
}
