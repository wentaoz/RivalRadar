import Foundation
import SQLite3
import CommonCrypto
import CryptoKit
import Security

struct ChromeProfile: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
}

enum ChromeSessionError: LocalizedError {
    case cookiesDatabaseMissing
    case openFailed

    var errorDescription: String? {
        switch self {
        case .cookiesDatabaseMissing:
            return "未找到 Chrome Cookies 数据库"
        case .openFailed:
            return "无法读取 Chrome Cookies 数据库"
        }
    }
}

final class ChromeSessionReader {
    func availableProfiles() -> [ChromeProfile] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        return entries.compactMap { url in
            let cookies = url.appendingPathComponent("Cookies")
            let networkCookies = url.appendingPathComponent("Network/Cookies")
            guard FileManager.default.fileExists(atPath: cookies.path) || FileManager.default.fileExists(atPath: networkCookies.path) else {
                return nil
            }
            return ChromeProfile(name: url.lastPathComponent, path: url.path)
        }
        .sorted { $0.name < $1.name }
    }

    func cookieHeader(for url: URL, profilePath: String) throws -> String? {
        let profileURL = URL(fileURLWithPath: profilePath, isDirectory: true)
        let cookiesURL = existingCookiesURL(in: profileURL)
        guard let cookiesURL else { throw ChromeSessionError.cookiesDatabaseMissing }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RivalRadar-\(UUID().uuidString)-Cookies.sqlite")
        try? FileManager.default.removeItem(at: tempURL)
        try FileManager.default.copyItem(at: cookiesURL, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ChromeSessionError.openFailed
        }
        defer { sqlite3_close(db) }

        let host = url.host?.lowercased() ?? ""
        let secureOnly = url.scheme?.lowercased() == "https"
        let query = """
        SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure
        FROM cookies
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var cookies: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let hostKey = columnString(statement, 0).lowercased()
            let name = columnString(statement, 1)
            let storedValue = columnString(statement, 2)
            let encryptedValue = columnData(statement, 3)
            let isSecure = sqlite3_column_int(statement, 6) == 1

            let value = cookieValue(hostKey: hostKey, storedValue: storedValue, encryptedValue: encryptedValue)
            guard !name.isEmpty, let value, !value.isEmpty else { continue }
            guard hostMatches(cookieHost: hostKey, requestHost: host) else { continue }
            guard secureOnly || !isSecure else { continue }
            cookies.append("\(name)=\(value)")
        }

        return cookies.isEmpty ? nil : cookies.joined(separator: "; ")
    }

    private func existingCookiesURL(in profileURL: URL) -> URL? {
        let candidates = [
            profileURL.appendingPathComponent("Cookies"),
            profileURL.appendingPathComponent("Network/Cookies")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func hostMatches(cookieHost: String, requestHost: String) -> Bool {
        let normalizedCookieHost = cookieHost.hasPrefix(".") ? String(cookieHost.dropFirst()) : cookieHost
        return requestHost == normalizedCookieHost || requestHost.hasSuffix("." + normalizedCookieHost)
    }

    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private func columnData(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func cookieValue(hostKey: String, storedValue: String, encryptedValue: Data?) -> String? {
        if !storedValue.isEmpty {
            return storedValue
        }
        guard let encryptedValue else { return nil }
        return decryptChromeCookie(hostKey: hostKey, encryptedValue: encryptedValue)
    }

    private func decryptChromeCookie(hostKey: String, encryptedValue: Data) -> String? {
        guard encryptedValue.starts(with: Data("v10".utf8)),
              let password = chromeSafeStoragePassword(),
              let key = deriveChromeKey(password: password) else {
            return nil
        }

        let cipherText = encryptedValue.dropFirst(3)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        let outputCapacity = cipherText.count + kCCBlockSizeAES128
        var output = Data(repeating: 0, count: outputCapacity)
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            cipherText.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            cipherText.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)

        let hostDigest = Data(SHA256.hash(data: Data(hostKey.utf8)))
        if output.count > hostDigest.count, output.prefix(hostDigest.count) == hostDigest {
            output.removeFirst(hostDigest.count)
        }

        return String(data: output, encoding: .utf8)
    }

    private func chromeSafeStoragePassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Chrome Safe Storage",
            kSecAttrAccount as String: "Chrome",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    private func deriveChromeKey(password: String) -> Data? {
        let salt = Data("saltysalt".utf8)
        let keyLength = 16
        var key = Data(repeating: 0, count: keyLength)
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    password.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyLength
                )
            }
        }
        return status == kCCSuccess ? key : nil
    }
}
