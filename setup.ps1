# MoonBit Hex Editor — Windows 一键搭建脚本 (PowerShell)
# 以管理员或普通用户运行: .\setup.ps1

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " MoonBit Hex Editor — Setup Script" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check C compiler (gcc from MinGW)
Write-Host "[1/5] Checking C compiler..." -ForegroundColor Yellow
$gcc = Get-Command gcc -ErrorAction SilentlyContinue
if ($gcc) {
    $ver = & gcc --version 2>&1 | Select-Object -First 1
    Write-Host "  √ $ver" -ForegroundColor Green
} else {
    Write-Host "  × gcc not found." -ForegroundColor Red
    Write-Host "  Please install MinGW-w64: https://github.com/niXman/mingw-builds-binaries/releases" -ForegroundColor Yellow
    Write-Host "  Or install via scoop: scoop install mingw" -ForegroundColor Yellow
    Write-Host ""
    $continue = Read-Host "Continue without gcc? (y/n)"
    if ($continue -ne 'y') { exit 1 }
}

# 2. Check/Install MoonBit
Write-Host ""
Write-Host "[2/5] Checking MoonBit toolchain..." -ForegroundColor Yellow
$moon = Get-Command moon -ErrorAction SilentlyContinue
if ($moon) {
    $ver = & moon version 2>&1 | Select-Object -First 1
    Write-Host "  √ $ver" -ForegroundColor Green
} else {
    Write-Host "  Installing MoonBit..."
    try {
        Invoke-RestMethod https://cli.moonbitlang.com/install/powershell.ps1 | Invoke-Expression
        # Refresh PATH
        $env:PATH = "$env:USERPROFILE\.moon\bin;$env:PATH"
        $ver = & moon version 2>&1 | Select-Object -First 1
        Write-Host "  √ MoonBit installed: $ver" -ForegroundColor Green
    } catch {
        Write-Host "  × MoonBit installation failed." -ForegroundColor Red
        Write-Host "  Please install manually: https://www.moonbitlang.com/download/" -ForegroundColor Yellow
        exit 1
    }
}

# 3. Install dependencies
Write-Host ""
Write-Host "[3/5] Installing dependencies..." -ForegroundColor Yellow
& moon update 2>$null


# 4. Build
Write-Host ""
Write-Host "[4/5] Building..." -ForegroundColor Yellow
& moon build --target native
Write-Host "  √ Native build OK" -ForegroundColor Green
& moon build --target wasm-gc cmd/wasm
Write-Host "  √ Wasm-GC build OK" -ForegroundColor Green

# 5. Test
Write-Host ""
Write-Host "[5/5] Running tests..." -ForegroundColor Yellow
$result = & moon test --target native 2>&1 | Select-Object -Last 1
Write-Host "  $result" -ForegroundColor Green

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Setup Complete!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Usage:" -ForegroundColor White
Write-Host "   # TUI mode" -ForegroundColor Gray
Write-Host "   moon run --target native cmd/main -- <file>" -ForegroundColor White
Write-Host ""
Write-Host "   # CLI commands" -ForegroundColor Gray
Write-Host "   moon run --target native cmd/main -- view <file>" -ForegroundColor White
Write-Host "   moon run --target native cmd/main -- struct <file>" -ForegroundColor White
Write-Host "   moon run --target native cmd/main -- scan <file>" -ForegroundColor White
Write-Host "   moon run --target native cmd/main -- help" -ForegroundColor White
Write-Host ""
Write-Host "   # Wasm-GC CLI" -ForegroundColor Gray
Write-Host "   moon run --target wasm-gc cmd/wasm -- struct <file>" -ForegroundColor White
Write-Host ""
