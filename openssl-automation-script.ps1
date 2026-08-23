# ============================================================
# OpenSSL Self-Signed SSL Certificate Generator
# ============================================================

Clear-Host

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " OpenSSL Self-Signed SSL Certificate Tool" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Check whether OpenSSL is installed
# ------------------------------------------------------------

$opensslCommand = Get-Command openssl -ErrorAction SilentlyContinue

if (-not $opensslCommand) {
    Write-Host "ERROR: OpenSSL was not found on this system." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install OpenSSL and make sure it is added to the" -ForegroundColor Yellow
    Write-Host "system PATH, then open a new PowerShell window and run" -ForegroundColor Yellow
    Write-Host "this script again." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "OpenSSL found: $($opensslCommand.Source)" -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# Ask for output directory
# ------------------------------------------------------------

$outputPath = Read-Host "Enter the path where you want to save the certificate files"

if ([string]::IsNullOrWhiteSpace($outputPath)) {
    Write-Host "ERROR: Output path cannot be empty." -ForegroundColor Red
    exit 1
}

# Expand environment variables if used
$outputPath = [Environment]::ExpandEnvironmentVariables($outputPath)

# Create directory if it does not exist
if (-not (Test-Path -LiteralPath $outputPath)) {
    try {
        New-Item -ItemType Directory -Path $outputPath -Force -ErrorAction Stop | Out-Null
        Write-Host "Output directory created: $outputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Unable to create the output directory." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""

# ------------------------------------------------------------
# Ask for primary domain / hostname
# ------------------------------------------------------------

$commonName = Read-Host "Enter the primary domain/hostname (e.g. server.example.com)"

if ([string]::IsNullOrWhiteSpace($commonName)) {
    Write-Host "ERROR: Domain/hostname cannot be empty." -ForegroundColor Red
    exit 1
}

$commonName = $commonName.Trim()

# ------------------------------------------------------------
# Ask for additional SAN entries
# ------------------------------------------------------------

$sanInput = Read-Host "Enter additional SAN DNS names separated by commas (e.g. www.example.com,api.example.com)"

# Start SAN list with the primary hostname
$sanNames = @($commonName)

if (-not [string]::IsNullOrWhiteSpace($sanInput)) {

    $additionalSANs = $sanInput.Split(',') |
        ForEach-Object {
            $_.Trim()
        } |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }

    $sanNames += $additionalSANs
}

# Remove duplicate SAN entries
$sanNames = $sanNames | Select-Object -Unique

Write-Host ""
Write-Host "SAN entries:" -ForegroundColor Cyan

foreach ($san in $sanNames) {
    Write-Host "  - $san"
}

Write-Host ""

# ------------------------------------------------------------
# Ask for certificate file base name
# ------------------------------------------------------------

$baseName = Read-Host "Enter the base name for the certificate files (e.g. myserver)"

if ([string]::IsNullOrWhiteSpace($baseName)) {
    Write-Host "ERROR: Certificate file name cannot be empty." -ForegroundColor Red
    exit 1
}

$baseName = $baseName.Trim()

# Check invalid Windows filename characters
$invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

if ($baseName.IndexOfAny($invalidChars) -ge 0) {
    Write-Host "ERROR: The file name contains invalid characters." -ForegroundColor Red
    Write-Host "Use only letters, numbers, hyphens, or underscores." -ForegroundColor Yellow
    exit 1
}

# ------------------------------------------------------------
# Define output files
# ------------------------------------------------------------

$configFile = Join-Path $outputPath "$baseName-openssl.cnf"
$keyFile    = Join-Path $outputPath "$baseName.key"
$certFile   = Join-Path $outputPath "$baseName.crt"
$pfxFile    = Join-Path $outputPath "$baseName.pfx"

# ------------------------------------------------------------
# Check whether files already exist
# ------------------------------------------------------------

$existingFiles = @(
    $configFile
    $keyFile
    $certFile
    $pfxFile
) | Where-Object {
    Test-Path -LiteralPath $_
}

if ($existingFiles.Count -gt 0) {

    Write-Host "WARNING: The following files already exist:" -ForegroundColor Yellow

    foreach ($file in $existingFiles) {
        Write-Host "  $file" -ForegroundColor Yellow
    }

    Write-Host ""

    $overwrite = Read-Host "Do you want to overwrite these files? (Y/N)"

    if ($overwrite -notmatch "^[Yy]$") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ------------------------------------------------------------
# Create SAN configuration entries
# ------------------------------------------------------------

$sanEntries = for ($i = 0; $i -lt $sanNames.Count; $i++) {
    "DNS.$($i + 1) = $($sanNames[$i])"
}

# ------------------------------------------------------------
# Create OpenSSL configuration
# ------------------------------------------------------------

$opensslConfig = @"
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $commonName

[v3_req]
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
$($sanEntries -join "`r`n")
"@

try {

    $opensslConfig |
        Set-Content `
            -Path $configFile `
            -Encoding ASCII `
            -ErrorAction Stop

    Write-Host "OpenSSL configuration created successfully." -ForegroundColor Green
}
catch {

    Write-Host "ERROR: Unable to create the OpenSSL configuration file." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# ------------------------------------------------------------
# Generate private key
# ------------------------------------------------------------

Write-Host "Generating private key..." -ForegroundColor Cyan

& openssl genrsa -out $keyFile 2048

if ($LASTEXITCODE -ne 0) {

    Write-Host "ERROR: Failed to generate the private key." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $keyFile)) {

    Write-Host "ERROR: Private key file was not created." -ForegroundColor Red
    exit 1
}

Write-Host "Private key created successfully." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# Generate self-signed certificate
# ------------------------------------------------------------

Write-Host "Generating self-signed SSL certificate..." -ForegroundColor Cyan

& openssl req `
    -x509 `
    -new `
    -nodes `
    -key $keyFile `
    -sha256 `
    -days 365 `
    -out $certFile `
    -config $configFile `
    -extensions v3_req

if ($LASTEXITCODE -ne 0) {

    Write-Host "ERROR: Failed to generate the SSL certificate." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $certFile)) {

    Write-Host "ERROR: SSL certificate file was not created." -ForegroundColor Red
    exit 1
}

Write-Host "Self-signed SSL certificate created successfully." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# Export certificate and private key to PFX
# ------------------------------------------------------------

Write-Host "Exporting certificate and private key to PFX..." -ForegroundColor Cyan
Write-Host "You will be asked to enter a password for the PFX file." -ForegroundColor Yellow
Write-Host ""

& openssl pkcs12 `
    -export `
    -out $pfxFile `
    -inkey $keyFile `
    -in $certFile `
    -name $commonName

if ($LASTEXITCODE -ne 0) {

    Write-Host "ERROR: Failed to export the PFX file." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $pfxFile)) {

    Write-Host "ERROR: PFX file was not created." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "PFX file created successfully." -ForegroundColor Green

# ------------------------------------------------------------
# Display certificate information
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Certificate Generation Completed" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Output directory:" -ForegroundColor Cyan
Write-Host "$outputPath"
Write-Host ""

Write-Host "Generated files:" -ForegroundColor Cyan
Write-Host "OpenSSL Config : $configFile"
Write-Host "Private Key    : $keyFile"
Write-Host "Certificate    : $certFile"
Write-Host "PFX Certificate: $pfxFile"
Write-Host ""

Write-Host "SAN entries:" -ForegroundColor Cyan

foreach ($san in $sanNames) {
    Write-Host "  - $san"
}

Write-Host ""
Write-Host "IMPORTANT: Keep the .key and .pfx files secure." -ForegroundColor Yellow
Write-Host "The PFX file contains the private key." -ForegroundColor Yellow
Write-Host ""