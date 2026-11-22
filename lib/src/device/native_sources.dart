// Native sources are embedded in the CLI artifact, never read from the cwd.
// These helpers use only hardware providers and never export private keys.
// Source is embedded so source, pub-global and AOT installations use exactly
// the same reviewed version, without looking in the working directory.
const secureEnclaveSource = r'''
import Foundation
import CryptoKit
import Security

do {
    guard SecureEnclave.isAvailable else {
        throw NSError(domain: "OnePub: Secure Enclave unavailable", code: 1)
    }
    let args = CommandLine.arguments
    let operation = args[1]
    let keyURL = URL(fileURLWithPath: args[2])
    let key: SecureEnclave.P256.Signing.PrivateKey
    if operation == "create" {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error) else {
            throw error!.takeRetainedValue()
        }
        key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        // CryptoKit exports only an encrypted, device-bound key reference.
        // This does not contain a transferable plaintext private scalar.
        try key.dataRepresentation.write(to: keyURL, options: .atomic)
    } else {
        key = try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: Data(contentsOf: keyURL))
    }
    if operation == "sign" {
        let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        print(try key.signature(for: data).rawRepresentation.base64EncodedString())
    } else {
        print(key.publicKey.x963Representation.base64EncodedString())
    }
} catch {
    FileHandle.standardError.write(Data("Secure Enclave operation failed: \(error)\n".utf8))
    exit(1)
}
''';

const platformCryptoSource = r'''
param([string]$Operation, [string]$KeyName, [string]$InputPath)
$ErrorActionPreference = 'Stop'
try {
    $provider = [System.Security.Cryptography.CngProvider]::new('Microsoft Platform Crypto Provider')
    if ($Operation -eq 'create') {
        $parameters = [System.Security.Cryptography.CngKeyCreationParameters]::new()
        $parameters.Provider = $provider
        $parameters.KeyUsage = [System.Security.Cryptography.CngKeyUsages]::Signing
        $parameters.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::None
        $key = [System.Security.Cryptography.CngKey]::Create(
            [System.Security.Cryptography.CngAlgorithm]::ECDsaP256, $KeyName, $parameters)
    } else {
        $key = [System.Security.Cryptography.CngKey]::Open($KeyName, $provider)
    }
    try {
        if ($Operation -eq 'delete') {
            $key.Delete()
        } elseif ($Operation -eq 'sign') {
            $signer = [System.Security.Cryptography.ECDsaCng]::new($key)
            try {
                $signature = $signer.SignData([System.IO.File]::ReadAllBytes($InputPath),
                    [System.Security.Cryptography.HashAlgorithmName]::SHA256)
                [Console]::WriteLine([Convert]::ToBase64String($signature))
            } finally { $signer.Dispose() }
        } else {
            # BCRYPT_ECCPUBLIC_BLOB: magic, coordinate size, X, Y.
            $blob = $key.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
            if ($blob.Length -ne 72 -or [BitConverter]::ToUInt32($blob, 0) -ne 0x31534345 -or
                [BitConverter]::ToUInt32($blob, 4) -ne 32) { throw 'Unexpected P-256 public key' }
            [byte[]]$point = @(4) + $blob[8..71]
            [Console]::WriteLine([Convert]::ToBase64String($point))
        }
    } finally { $key.Dispose() }
} catch {
    [Console]::Error.WriteLine('Platform Crypto Provider operation failed: ' + $_.Exception.Message)
    exit 1
}
''';
