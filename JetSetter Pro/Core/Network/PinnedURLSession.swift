// File: Core/Network/PinnedURLSession.swift
//
// Certificate public-key (SPKI) pinning for the Supabase backend host.
//
// Pinning is INERT by default: with an empty `pinnedSPKIHashes` set the delegate
// performs standard system trust evaluation, so the app behaves exactly as it did
// before pinning was introduced. This lets us ship the machinery without risking
// a bricked app on certificate rotation — it activates only once real pins are
// configured below.
//
// To enable:
//   1. Fetch the server's public-key hash(es):
//        openssl s_client -connect <project>.supabase.co:443 -servername <project>.supabase.co \
//          < /dev/null 2>/dev/null | openssl x509 -pubkey -noout \
//          | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
//   2. Add BOTH the current leaf hash AND a backup (the intermediate CA, or a
//      pre-provisioned next leaf) to `pinnedSPKIHashes`, so a routine certificate
//      renewal doesn't lock users out.
//   3. Ship. Rotate the pin set ahead of any planned cert change.

import Foundation
import CryptoKit

enum CertificatePinning {

    /// base64( SHA-256( DER SubjectPublicKeyInfo ) ) values that are allowed for
    /// the Supabase host. An empty set disables pinning (system trust only).
    static let pinnedSPKIHashes: Set<String> = [
        // "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", // current leaf
        // "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=", // backup (intermediate)
    ]

    /// True once at least one pin is configured.
    static var isEnabled: Bool { !pinnedSPKIHashes.isEmpty }
}

/// URLSession delegate that enforces `CertificatePinning`. Always requires the
/// chain to validate against the system trust store first; when pinning is
/// enabled it additionally requires one certificate in the chain to match a pin.
final class PinningURLSessionDelegate: NSObject, URLSessionDelegate {

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 1. System trust evaluation (CA chain, hostname, expiry). Always required.
        guard SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 2. Pinning disabled → accept the system-validated chain unchanged.
        guard CertificatePinning.isEnabled else {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // 3. Accept if any certificate's SPKI hash matches a configured pin.
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        for certificate in chain {
            if let hash = Self.spkiSHA256Base64(certificate),
               CertificatePinning.pinnedSPKIHashes.contains(hash) {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    /// base64( SHA-256( DER SubjectPublicKeyInfo ) ) for a certificate's public key.
    private static func spkiSHA256Base64(_ certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let header = asn1Header(for: publicKey) else { return nil }
        // SecKeyCopyExternalRepresentation returns the bare key bits, not the full
        // SubjectPublicKeyInfo, so we prepend the algorithm-specific ASN.1 header
        // to reconstruct the SPKI that browsers/tools hash.
        var spki = Data(header)
        spki.append(keyData)
        return Data(SHA256.hash(data: spki)).base64EncodedString()
    }

    /// ASN.1 SubjectPublicKeyInfo header for the given key type/size (RFC 5280).
    private static func asn1Header(for key: SecKey) -> [UInt8]? {
        guard let attrs = SecKeyCopyAttributes(key) as? [CFString: Any],
              let type = attrs[kSecAttrKeyType] as? String,
              let bits = attrs[kSecAttrKeySizeInBits] as? Int else { return nil }
        // Bind the CFString constants to Swift Strings so the switch below uses
        // value (==) patterns rather than type-cast patterns.
        let rsa = kSecAttrKeyTypeRSA as String
        let ec  = kSecAttrKeyTypeECSECPrimeRandom as String
        switch (type, bits) {
        case (rsa, 2048): return rsa2048Header
        case (rsa, 4096): return rsa4096Header
        case (ec, 256):   return ecP256Header
        case (ec, 384):   return ecP384Header
        default:          return nil
        }
    }

    private static let rsa2048Header: [UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
        0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    ]
    private static let rsa4096Header: [UInt8] = [
        0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
        0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
    ]
    private static let ecP256Header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
        0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00
    ]
    private static let ecP384Header: [UInt8] = [
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
        0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
    ]
}
