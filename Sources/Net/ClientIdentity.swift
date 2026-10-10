import CryptoKit
import Foundation
import Security

/// The RSA key + self-signed certificate this app presents to Android TVs.
/// Generated once and kept in the keychain; the TV remembers it after pairing.
enum ClientIdentity {
    struct Material {
        let identity: SecIdentity
        let certificate: SecCertificate
    }

    enum IdentityError: LocalizedError {
        case keychain(String)
        var errorDescription: String? {
            switch self { case .keychain(let m): "Couldn't set up this device's pairing key (\(m))." }
        }
    }

    /// Overridable so dev tools keep their own key instead of sharing (and prompting for) the app's.
    /// Still named after the app's original name: changing it would orphan existing pairings.
    static var commonName = "FreeRemote"
    private static var label: String { "Free Remote Android TV client (\(commonName))" }
    private static var keyTag: Data { Data("com.natebutler.freeremote.atv-client-key.\(commonName)".utf8) }

    private static var cached: Material?

    static func loadOrCreate() throws -> Material {
        if let cached { return cached }
        if let found = find() {
            cached = found
            return found
        }
        try create()
        guard let found = find() else { throw IdentityError.keychain("identity not found after creation") }
        cached = found
        return found
    }

    /// Throws away the key so the next pairing starts fresh.
    static func reset() {
        cached = nil
        SecItemDelete(scoped([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: label]) as CFDictionary)
        SecItemDelete(scoped([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag]) as CFDictionary)
    }

    // MARK: - Keychain plumbing

    /// On macOS, prefer the modern data-protection keychain when the build is signed for it,
    /// falling back to the login keychain for unsigned/dev builds.
    static let useDataProtectionKeychain: Bool = {
        #if os(macOS)
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "freeremote.probe",
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data([1]),
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        SecItemDelete(probe as CFDictionary)
        return status == errSecSuccess || status == errSecDuplicateItem
        #else
        return false
        #endif
    }()

    /// Adds the data-protection keychain flag where it applies.
    static func scoped(_ q: [String: Any]) -> [String: Any] {
        var q = q
        #if os(macOS)
        if useDataProtectionKeychain { q[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return q
    }

    private static func find() -> Material? {
        let query = scoped([
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ])
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let identities = result as? [SecIdentity] else { return nil }
        for identity in identities {
            var cert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else { continue }
            if (SecCertificateCopySubjectSummary(cert) as String?) == commonName {
                return Material(identity: identity, certificate: cert)
            }
        }
        return nil
    }

    private static func create() throws {
        reset()
        var error: Unmanaged<CFError>?
        let attrs = scoped([
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrLabel as String: label,
            ],
        ])
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicDER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw IdentityError.keychain(error?.takeRetainedValue().localizedDescription ?? "key generation failed")
        }

        let signatureAlgorithm = DER.sequence([DER.oid("1.2.840.113549.1.1.11"), DER.null]) // sha256WithRSAEncryption
        let name = DER.sequence([DER.set([DER.sequence([DER.oid("2.5.4.3"), DER.utf8(commonName)])])])
        let now = Date()
        let validity = DER.sequence([DER.time(now.addingTimeInterval(-86_400)), DER.time(now.addingTimeInterval(20 * 365 * 86_400))])
        let spki = DER.sequence([
            DER.sequence([DER.oid("1.2.840.113549.1.1.1"), DER.null]), // rsaEncryption
            DER.bitString(Array(publicDER)),
        ])
        let basicConstraints = DER.sequence([
            DER.oid("2.5.29.19"),
            DER.octetString(DER.sequence([DER.boolean(true), DER.integer(0)])),
        ])
        let subjectAltName = DER.sequence([
            DER.oid("2.5.29.17"),
            DER.octetString(DER.sequence([DER.tlv(0x82, Array(commonName.utf8))])),
        ])
        var serial = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] &= 0x7F

        let tbs = DER.sequence([
            DER.explicit(0, DER.integer(2)), // v3
            DER.integer(serial),
            signatureAlgorithm,
            name,
            validity,
            name,
            spki,
            DER.explicit(3, DER.sequence([basicConstraints, subjectAltName])),
        ])

        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data(tbs) as CFData, &error) as Data? else {
            throw IdentityError.keychain(error?.takeRetainedValue().localizedDescription ?? "signing failed")
        }
        let certDER = DER.sequence([tbs, signatureAlgorithm, DER.bitString(Array(signature))])
        guard let certificate = SecCertificateCreateWithData(nil, Data(certDER) as CFData) else {
            throw IdentityError.keychain("certificate encoding rejected")
        }
        let status = SecItemAdd(scoped([
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label,
        ]) as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw IdentityError.keychain("OSStatus \(status)")
        }
    }

    /// RSA modulus and exponent of a certificate's public key, used in the pairing secret.
    /// First four hex digits of the certificate's SHA-256, stable for as long as the identity is.
    static func shortID(of certificate: SecCertificate) -> String {
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        return digest.prefix(2).map { String(format: "%02X", $0) }.joined()
    }

    static func rsaComponents(of certificate: SecCertificate) -> (modulus: [UInt8], exponent: [UInt8])? {
        guard let key = SecCertificateCopyKey(certificate),
              let der = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return DER.rsaPublicKeyComponents(Array(der))
    }
}
