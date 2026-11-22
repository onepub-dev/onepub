// Native sources are embedded in the CLI artifact, never read from the cwd.
// These helpers use only hardware providers and never export private keys.
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
