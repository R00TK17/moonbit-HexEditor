# MoonBit Hex Editor — Windows 一键搭建脚本 (PowerShell)
# Run: .\setup.ps1

$ErrorActionPreference = "Stop"

# Fix Unicode rendering on Windows terminals
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host ""
    Write-Host "[$Step/5] $Message" -ForegroundColor Yellow
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " MoonBit Hex Editor  Setup Script" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# 1. Check C compiler (gcc from MinGW)
Write-Step "1" "Checking C compiler..."
$gcc = Get-Command gcc -ErrorAction SilentlyContinue
if ($gcc) {
    $ver = & gcc --version 2>&1 | Select-Object -First 1
    Write-Host "  [OK] $ver" -ForegroundColor Green
} else {
    Write-Host "  [X] gcc not found. Attempting automatic install..." -ForegroundColor Red
    $installed = $false

    # Try winget first
    if (-not $installed -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "  Trying winget..."
        try {
            winget install -e --id Ninja.Build.GCC --accept-source-agreements --silent 2>$null
            if ($LASTEXITCODE -eq 0) { $installed = $true }
        } catch {}
    }

    # Try scoop
    if (-not $installed -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Host "  Trying scoop..."
        try {
            scoop install mingw 2>$null
            if ($LASTEXITCODE -eq 0) { $installed = $true }
        } catch {}
    }

    # Try chocolatey
    if (-not $installed -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "  Trying chocolatey..."
        try {
            choco install mingw -y 2>$null
            if ($LASTEXITCODE -eq 0) { $installed = $true }
        } catch {}
    }

    if ($installed) {
        # Refresh PATH so gcc is available in this session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    # Verify again after install
    $gcc = Get-Command gcc -ErrorAction SilentlyContinue
    if ($gcc) {
        Write-Host "  [OK] gcc installed and available" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  gcc still not found on PATH. Install MinGW-w64 manually:" -ForegroundColor Yellow
        Write-Host "    https://github.com/niXman/mingw-builds-binaries/releases" -ForegroundColor White
        Write-Host "  After install, add MinGW\\bin to your system PATH." -ForegroundColor Yellow
        Write-Host ""
        $continue = Read-Host "Continue without gcc? (y/n)"
        if ($continue -ne 'y') { exit 1 }
    }
}

# 2. Check/Install MoonBit
Write-Step "2" "Checking MoonBit toolchain..."
$moon = Get-Command moon -ErrorAction SilentlyContinue
if ($moon) {
    $ver = & moon version 2>&1 | Select-Object -First 1
    Write-Host "  [OK] $ver" -ForegroundColor Green
} else {
    Write-Host "  Installing MoonBit..."
    if (-not (Get-Command curl -ErrorAction SilentlyContinue)) {
        Write-Host "  [X] curl is required. Install curl and retry." -ForegroundColor Red
        exit 1
    }
    try {
        Invoke-RestMethod https://cli.moonbitlang.com/install/powershell.ps1 | Invoke-Expression
        # Refresh PATH
        $env:PATH = "$env:USERPROFILE\.moon\bin;$env:PATH"
    } catch {
        Write-Host "  [X] MoonBit installation failed." -ForegroundColor Red
        Write-Host "  Please install manually: https://www.moonbitlang.com/download/" -ForegroundColor Yellow
        exit 1
    }

    # Verify the installation
    $moonCheck = Get-Command moon -ErrorAction SilentlyContinue
    if ($moonCheck) {
        $ver = & moon version 2>&1 | Select-Object -First 1
        Write-Host "  [OK] MoonBit installed: $ver" -ForegroundColor Green
    } else {
        Write-Host "  [X] MoonBit installation failed. Please install manually:" -ForegroundColor Red
        Write-Host "    https://www.moonbitlang.com/download/" -ForegroundColor Yellow
        exit 1
    }
}

# 3. Install dependencies
Write-Step "3" "Installing dependencies..."
try { & moon update 2>$null } catch {}

# 4. Build
Write-Step "4" "Building..."
& moon build
Write-Host "  [OK] Native build OK" -ForegroundColor Green
& moon build --target wasm-gc cmd/wasm
Write-Host "  [OK] Wasm-GC build OK" -ForegroundColor Green

# 5. Test
Write-Step "5" "Running tests..."
$result = & moon test 2>&1 | Select-Object -Last 1
Write-Host "  $result" -ForegroundColor Green

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Setup Complete!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Note: if 'moon' is not recognized after opening a new terminal," -ForegroundColor Yellow
Write-Host "   run this to add MoonBit to your user PATH permanently:" -ForegroundColor Yellow
Write-Host '   [Environment]::SetEnvironmentVariable("Path", "$env:USERPROFILE\.moon\bin;" + [Environment]::GetEnvironmentVariable("Path", "User"), "User")' -ForegroundColor White
Write-Host ""
Write-Host " Usage:" -ForegroundColor White
Write-Host "   # TUI mode" -ForegroundColor Gray
Write-Host "   moon run cmd/main -- <file>" -ForegroundColor White
Write-Host ""
Write-Host "   # CLI commands" -ForegroundColor Gray
Write-Host "   moon run cmd/main -- view <file>" -ForegroundColor White
Write-Host "   moon run cmd/main -- struct <file>" -ForegroundColor White
Write-Host "   moon run cmd/main -- scan <file>" -ForegroundColor White
Write-Host "   moon run cmd/main -- help" -ForegroundColor White
Write-Host ""
Write-Host "   # Wasm-GC CLI" -ForegroundColor Gray
Write-Host "   moon run --target wasm-gc cmd/wasm -- struct <file>" -ForegroundColor White
Write-Host ""
