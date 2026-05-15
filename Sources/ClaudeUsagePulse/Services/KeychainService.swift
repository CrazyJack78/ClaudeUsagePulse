import Foundation
import Security

enum KeychainService {
    private static let service = "dev.jack.claudeusagepulse"
    private static let cookiesKey = "claude_cookies"
    private static let orgIdKey = "org_id"

    static func saveCookies(_ cookies: [HTTPCookie]) {
        let dicts = cookies.map { c -> [String: String] in
            [
                "name":   c.name,
                "value":  c.value,
                "domain": c.domain,
                "path":   c.path
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dicts) else { return }
        store(key: cookiesKey, data: data)
    }

    static func loadCookies() -> [HTTPCookie] {
        guard let data = fetch(key: cookiesKey),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }

        return array.compactMap { d -> HTTPCookie? in
            guard let name   = d["name"],
                  let value  = d["value"],
                  let domain = d["domain"],
                  let path   = d["path"] else { return nil }
            return HTTPCookie(properties: [
                .name:   name,
                .value:  value,
                .domain: domain,
                .path:   path,
                .secure: "TRUE"
            ])
        }
    }

    static func saveOrgId(_ orgId: String) {
        guard let data = orgId.data(using: .utf8) else { return }
        store(key: orgIdKey, data: data)
    }

    static func loadOrgId() -> String? {
        guard let data = fetch(key: orgIdKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasCookies() -> Bool {
        fetch(key: cookiesKey) != nil
    }

    static func clearAll() {
        remove(key: cookiesKey)
        remove(key: orgIdKey)
    }

    // MARK: - Private

    private static func store(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func fetch(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func remove(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
