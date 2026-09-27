import Security

/// Delete the obsolete credential without reading its contents. Retried on each launch.
enum LegacyCredentialCleanup {
    static func run() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.xnu.BabelTable",
            kSecAttrAccount as String: "openai_api_key"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
