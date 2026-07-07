# MoonBit Hex Editor — Demo Script (Windows PowerShell)
# Run after setup: .\demo.ps1

$ErrorActionPreference = "Continue"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " MoonBit Hex Editor — Demo" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Ensure built
$built = Test-Path "_build/native/debug/test/hex_editor.internal_test.exe"
if (-not $built) {
    Write-Host "Building first..." -ForegroundColor Yellow
    moon build
}

Write-Host "--- 1. File Structure Analysis ---" -ForegroundColor Yellow
Write-Host "`$ moon run cmd/main -- struct testfile/test.png" -ForegroundColor Gray
moon run cmd/main -- struct testfile/test.png 2>&1 | Select-Object -First 20
Write-Host ""

Write-Host "--- 2. Signature Scan (Steganography Detection) ---" -ForegroundColor Yellow
Write-Host "`$ moon run cmd/main -- scan testfile/hidden.jpg" -ForegroundColor Gray
moon run cmd/main -- scan testfile/hidden.jpg 2>&1
Write-Host ""

Write-Host "--- 3. Hex Dump ---" -ForegroundColor Yellow
Write-Host "`$ moon run cmd/main -- view testfile/test.txt" -ForegroundColor Gray
moon run cmd/main -- view testfile/test.txt 2>&1
Write-Host ""

Write-Host "--- 4. Entropy Analysis ---" -ForegroundColor Yellow
Write-Host "`$ moon run cmd/main -- entropy testfile/test.zip" -ForegroundColor Gray
moon run cmd/main -- entropy testfile/test.zip 2>&1
Write-Host ""

Write-Host "--- 5. Base64 Encoding ---" -ForegroundColor Yellow
Write-Host "`$ moon run cmd/main -- encode base64 Hello" -ForegroundColor Gray
moon run cmd/main -- encode base64 "Hello" 2>&1
Write-Host ""

Write-Host "--- 6. String Extraction ---" -ForegroundColor Yellow
Write-Host "`$ moon run cmd/main -- strings testfile/test.txt" -ForegroundColor Gray
moon run cmd/main -- strings testfile/test.txt 2>&1
Write-Host ""

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Demo Complete!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "For full TUI: moon run cmd/main -- testfile/test.png" -ForegroundColor White
