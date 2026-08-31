<#
.SYNOPSIS
    Signs MagicSoftSQL Windows binaries (runner executable and Inno Setup installer).

.DESCRIPTION
    Uses Microsoft SignTool (signtool.exe) to sign the application executable and the
    installer with Authenticode SHA-256 signatures and RFC 3161 timestamps.
    Supports existing PFX certificates, certificates from the Windows Certificate Store,
    or generating a self-signed certificate for local testing.

.PARAMETER CertPath
    Path to the .pfx certificate file.

.PARAMETER CertPassword
    Password for the .pfx certificate file (if password protected).

.PARAMETER CertThumbprint
    SHA1 thumbprint of a certificate installed in the Windows Certificate Store (CurrentUser\My).

.PARAMETER TimestampServer
    RFC 3161 timestamp authority URL. Default is http://timestamp.digicert.com.

.PARAMETER TargetPath
    Path or array of paths to .exe or .msix files to sign. If omitted, signs default release artifacts:
    - build/windows/x64/runner/Release/flutter_sql_converter.exe
    - build/windows/x64/installer/*.exe

.PARAMETER CreateSelfSigned
    Generates a new self-signed code-signing certificate for local testing and exports it to a .pfx file.

.EXAMPLE
    .\scripts\sign_windows.ps1 -CertPath "C:\certs\mycert.pfx" -CertPassword "secret"

.EXAMPLE
    .\scripts\sign_windows.ps1 -CreateSelfSigned -CertPassword "test1234"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$CertPath,

    [Parameter(Mandatory = $false)]
    [string]$CertPassword,

    [Parameter(Mandatory = $false)]
    [string]$CertThumbprint,

    [Parameter(Mandatory = $false)]
    [string]$TimestampServer = "http://timestamp.digicert.com",

    [Parameter(Mandatory = $false)]
    [string[]]$TargetPath,

    [Parameter(Mandatory = $false)]
    [switch]$CreateSelfSigned,

    [Parameter(Mandatory = $false)]
    [string]$Publisher = "CN=Genexis, O=Genexis"
)

$ErrorActionPreference = "Stop"

# Navigate to project root
$rootDir = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $rootDir

# Function: Locate signtool.exe
function Find-SignTool {
    # Check if signtool is in PATH
    $signtoolCmd = Get-Command "signtool.exe" -ErrorAction SilentlyContinue
    if ($signtoolCmd) {
        return $signtoolCmd.Source
    }

    # Search standard Windows Kits directories
    $searchPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe",
        "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe",
        "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\*\bin\NETFX *\signtool.exe"
    )

    $found = Get-ChildItem -Path $searchPaths -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if ($found) {
        return $found.FullName
    }

    throw "signtool.exe not found. Please install the Windows 10/11 SDK or run from the Visual Studio Developer Command Prompt."
}

# Function: Generate self-signed certificate for local testing
if ($CreateSelfSigned) {
    Write-Host "Creating self-signed code signing certificate for '$Publisher'..." -ForegroundColor Cyan

    $plainPassword = if ($CertPassword) { $CertPassword } else { "Password123!" }
    $secPassword = ConvertTo-SecureString -String $plainPassword -AsPlainText -Force
    $outCertPath = Join-Path $rootDir "dev_codesign.pfx"

    $cert = New-SelfSignedCertificate `
        -Type Custom `
        -Subject $Publisher `
        -KeyUsage DigitalSignature `
        -FriendlyName "MagicSoftSQL Dev Code Signing" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3") `
        -NotAfter (Get-Date).AddYears(3)

    Export-PfxCertificate -Cert $cert -FilePath $outCertPath -Password $secPassword | Out-Null
    Write-Host "Exported self-signed certificate to: $outCertPath" -ForegroundColor Green
    Write-Host "Certificate Thumbprint: $($cert.Thumbprint)" -ForegroundColor Yellow
    Write-Host "To trust this certificate for local testing, import it into 'Trusted Root Certification Authorities'." -ForegroundColor Yellow

    if (-not $CertPath) {
        $CertPath = $outCertPath
        if (-not $CertPassword) {
            $CertPassword = "Password123!"
        }
    }
}

# Locate signtool
$signtool = Find-SignTool
Write-Host "Using SignTool: $signtool" -ForegroundColor Gray

# If a certificate path is provided, import it into the Windows Certificate Store
# so SignTool can resolve it reliably via CryptoAPI / SHA1 thumbprint across all PFX formats.
$resolvedCertPath = $null
if ($CertPath) {
    if (-not (Test-Path $CertPath)) {
        throw "Certificate file not found: $CertPath"
    }
    $resolvedCertPath = (Resolve-Path $CertPath).Path

    $importedCerts = $null
    $passwordsToTry = @()
    if (-not [string]::IsNullOrEmpty($CertPassword)) {
        $passwordsToTry += $CertPassword
        $unquoted = $CertPassword.Trim('"').Trim("'")
        if ($unquoted -ne $CertPassword) { $passwordsToTry += $unquoted }
    }
    $passwordsToTry += ""

    foreach ($attemptPass in $passwordsToTry) {
        try {
            $secPass = ConvertTo-SecureString -String $attemptPass -AsPlainText -Force
            $importParams = @{
                FilePath = $resolvedCertPath
                CertStoreLocation = "Cert:\CurrentUser\My"
                Exportable = $true
                Password = $secPass
            }
            $importedCerts = @(Import-PfxCertificate @importParams)
            if ($importedCerts.Count -gt 0) {
                Write-Host "Successfully imported certificate into CurrentUser\My" -ForegroundColor Green
                break
            }
        } catch {
            # Continue trying alternate passwords/formats
        }
    }

    # If direct import failed, attempt OpenSSL legacy / PEM conversion if openssl is available
    if (-not $importedCerts -or $importedCerts.Count -eq 0) {
        $opensslCmd = Get-Command "openssl" -ErrorAction SilentlyContinue
        if (-not $opensslCmd) {
            $gitOpenssl = "${env:ProgramFiles}\Git\usr\bin\openssl.exe"
            if (Test-Path $gitOpenssl) {
                $opensslCmd = @{ Source = $gitOpenssl }
            }
        }
        if ($opensslCmd) {
            try {
                $tempId = [Guid]::NewGuid().ToString('N')
                $tempPem = Join-Path $env:TEMP "cert_$tempId.pem"
                $tempLegacyPfx = Join-Path $env:TEMP "cert_$tempId.pfx"
                $passArg = if (-not [string]::IsNullOrEmpty($CertPassword)) { $CertPassword } else { "" }

                & $opensslCmd.Source pkcs12 -in $resolvedCertPath -passin "pass:$passArg" -nodes -out $tempPem 2>$null
                if (Test-Path $tempPem) {
                    & $opensslCmd.Source pkcs12 -export -in $tempPem -passout "pass:$passArg" -out $tempLegacyPfx -legacy 2>$null
                    Remove-Item -Force $tempPem -ErrorAction SilentlyContinue
                    if (Test-Path $tempLegacyPfx) {
                        $secPass = ConvertTo-SecureString -String $passArg -AsPlainText -Force
                        $importedCerts = @(Import-PfxCertificate -FilePath $tempLegacyPfx -CertStoreLocation "Cert:\CurrentUser\My" -Password $secPass -Exportable)
                        Remove-Item -Force $tempLegacyPfx -ErrorAction SilentlyContinue
                        if ($importedCerts.Count -gt 0) {
                            Write-Host "Successfully converted and imported certificate via OpenSSL legacy mode" -ForegroundColor Green
                        }
                    }
                }
            } catch {
                Write-Warning "OpenSSL legacy conversion attempt failed: $($_.Exception.Message)"
            }
        }
    }

    if ($importedCerts -and $importedCerts.Count -gt 0) {
        $codeCert = $importedCerts | Where-Object { $_.HasPrivateKey } | Select-Object -First 1
        if (-not $codeCert) {
            $codeCert = $importedCerts[0]
            Write-Warning "Imported certificate does NOT contain a private key. Code signing may fail if this is a public-only certificate (.cer/.crt)."
        }
        $CertThumbprint = $codeCert.Thumbprint
        Write-Host "Using Certificate Thumbprint: $CertThumbprint (Subject: $($codeCert.Subject))" -ForegroundColor Green
    } else {
        Write-Warning "Could not import PFX to certificate store. Attempting direct file signing with signtool."
    }
}

# Determine files to sign
$filesToSign = @()

if ($TargetPath -and $TargetPath.Count -gt 0) {
    foreach ($path in $TargetPath) {
        $resolved = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        if ($resolved) {
            $filesToSign += $resolved.FullName
        } else {
            Write-Warning "Target path not found: $path"
        }
    }
} else {
    # Default release binaries
    $runnerExe = Join-Path $rootDir "build\windows\x64\runner\Release\flutter_sql_converter.exe"
    if (Test-Path $runnerExe) {
        $filesToSign += $runnerExe
    }

    $installerExes = Get-ChildItem -Path (Join-Path $rootDir "build\windows\x64\installer\*.exe") -ErrorAction SilentlyContinue
    if ($installerExes) {
        $filesToSign += $installerExes.FullName
    }

    $msixFiles = Get-ChildItem -Path (Join-Path $rootDir "build\windows\*.msix"), (Join-Path $rootDir "build\windows\x64\runner\Release\*.msix") -ErrorAction SilentlyContinue
    if ($msixFiles) {
        $filesToSign += $msixFiles.FullName
    }
}

if ($filesToSign.Count -eq 0) {
    Write-Warning "No target binaries found to sign. Build the project first:"
    Write-Warning "  flutter build windows --release"
    Write-Warning "  dart run inno_bundle:build --release --no-app"
    exit 0
}

# Sign each file
foreach ($file in $filesToSign) {
    Write-Host "`nSigning: $file" -ForegroundColor Cyan

    $signArgs = @("sign", "/fd", "sha256")

    if ($TimestampServer) {
        $signArgs += @("/tr", $TimestampServer, "/td", "sha256")
    }

    if ($CertThumbprint) {
        $signArgs += @("/sha1", $CertThumbprint, "/s", "My")
    } elseif ($resolvedCertPath) {
        $signArgs += @("/f", $resolvedCertPath)
        if (-not [string]::IsNullOrEmpty($CertPassword)) {
            $signArgs += @("/p", $CertPassword)
        }
    } else {
        # Try automatic store selection
        $signArgs += @("/a")
    }

    $signArgs += $file

    & $signtool $signArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to sign $file (exit code: $LASTEXITCODE)"
    }

    Write-Host "Verifying signature..." -ForegroundColor Gray
    & $signtool verify /pa /v $file
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Authenticode policy verification (/pa) returned code $LASTEXITCODE. Retrying basic signature verification without root policy check..."
        & $signtool verify /v $file
        if ($LASTEXITCODE -ne 0) {
            throw "Signature verification failed for $file (exit code: $LASTEXITCODE)"
        }
    }
    Write-Host "Successfully signed and verified: $file" -ForegroundColor Green
}

Write-Host "`nAll target files successfully signed." -ForegroundColor Green
