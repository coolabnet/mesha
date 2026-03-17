# =============================================================================
# scripts/bootstrap.ps1
# Mesha Community Infrastructure Operator — Windows Bootstrap
#
# This script helps Windows users get set up using WSL2 (Windows Subsystem
# for Linux 2), which is the standard path for running Mesha on Windows.
#
# Why WSL2?
#   - Mesha uses SSH, Node.js, Git, Docker, and shell scripts that work best
#     in a Linux environment.
#   - WSL2 gives you a real Linux shell inside Windows.
#   - One set of scripts works on Linux, macOS, and Windows via WSL2.
#
# Usage:
#   Right-click this file and choose "Run with PowerShell"
#   — or —
#   In an elevated PowerShell window:
#     powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1
#
# Risk class: Class B (see TOOLS.md). Run on a trusted host only.
# =============================================================================

# Require PowerShell 5+
#Requires -Version 5.0

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "── $Text ──" -ForegroundColor Cyan -NoNewline
    Write-Host ""
}

function Write-Pass {
    param([string]$Text)
    Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
    Write-Host $Text
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Text
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
    Write-Host $Text
}

function Write-Info {
    param([string]$Text)
    Write-Host "  [INFO] " -ForegroundColor DarkCyan -NoNewline
    Write-Host $Text
}

function Write-Step {
    param([string]$Number, [string]$Text)
    Write-Host "  $Number. " -ForegroundColor White -NoNewline
    Write-Host $Text
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Mesha Community Infrastructure Operator" -ForegroundColor Cyan
Write-Host "  Windows Bootstrap — WSL2 Setup Guide" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  The standard way to run Mesha on Windows is through WSL2." -ForegroundColor White
Write-Host "  This script checks if WSL2 is ready and tells you what to do next." -ForegroundColor White
Write-Host ""

# ---------------------------------------------------------------------------
# Check 1: Is WSL available at all?
# ---------------------------------------------------------------------------

Write-Header "Checking for WSL2"

$wslPath = "$env:SystemRoot\System32\wsl.exe"
$wslAvailable = Test-Path $wslPath

if (-not $wslAvailable) {
    Write-Fail "wsl.exe not found. WSL is not installed."
    Write-Host ""
    Write-Host "  To install WSL2, follow these steps:" -ForegroundColor Yellow
    Write-Host ""
    Write-Step "1" "Open PowerShell as Administrator."
    Write-Step "2" "Run this command:"
    Write-Host ""
    Write-Host "      wsl --install" -ForegroundColor Green
    Write-Host ""
    Write-Step "3" "Restart your computer when prompted."
    Write-Step "4" "After restart, Ubuntu will open automatically and ask you to"
    Write-Host "     create a username and password. Do that."
    Write-Step "5" "Then come back and run this script again."
    Write-Host ""
    Write-Host "  More information:" -ForegroundColor DarkCyan
    Write-Host "  https://learn.microsoft.com/en-us/windows/wsl/install" -ForegroundColor DarkCyan
    Write-Host ""
    exit 1
}

# WSL is installed — check version and distros
Write-Pass "wsl.exe is present."

# ---------------------------------------------------------------------------
# Check 2: WSL version
# ---------------------------------------------------------------------------

Write-Header "Checking WSL version"

try {
    $wslStatus = & wsl --status 2>&1 | Out-String
    if ($wslStatus -match "2") {
        Write-Pass "WSL2 appears to be the default version."
    } else {
        Write-Warn "Could not confirm WSL2 is the default."
        Write-Info "To set WSL2 as default, run in PowerShell as Administrator:"
        Write-Host ""
        Write-Host "      wsl --set-default-version 2" -ForegroundColor Green
        Write-Host ""
    }
} catch {
    Write-Warn "Could not check WSL version. Continuing anyway."
}

# ---------------------------------------------------------------------------
# Check 3: Is Ubuntu available?
# ---------------------------------------------------------------------------

Write-Header "Checking for Ubuntu in WSL2"

$distros = ""
try {
    $distros = & wsl --list --quiet 2>&1 | Out-String
} catch {
    Write-Warn "Could not list WSL distros."
}

$ubuntuFound = $distros -match "Ubuntu"

if ($ubuntuFound) {
    Write-Pass "Ubuntu is installed in WSL2."
} else {
    Write-Warn "Ubuntu does not appear to be installed."
    Write-Host ""
    Write-Host "  To install Ubuntu in WSL2, run in PowerShell as Administrator:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "      wsl --install -d Ubuntu" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Then restart your computer and open Ubuntu from the Start menu." -ForegroundColor Yellow
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Next steps: run bootstrap.sh inside WSL2
# ---------------------------------------------------------------------------

Write-Header "What to do next"

if ($ubuntuFound) {
    Write-Host ""
    Write-Host "  WSL2 with Ubuntu is ready. Now run the Linux bootstrap inside WSL2." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Open Ubuntu (from Start menu or run 'wsl' in PowerShell) and type:" -ForegroundColor White
    Write-Host ""
    Write-Host "      bash scripts/bootstrap.sh" -ForegroundColor Green
    Write-Host ""
    Write-Host "  If you have not cloned the Mesha repo yet, do this first inside WSL2:" -ForegroundColor White
    Write-Host ""
    Write-Host "      sudo apt update && sudo apt install -y git" -ForegroundColor Green
    Write-Host "      mkdir -p ~/community-ops" -ForegroundColor Green
    Write-Host "      cd ~/community-ops" -ForegroundColor Green
    Write-Host "      git clone <your-repo-url> mesha" -ForegroundColor Green
    Write-Host "      cd mesha" -ForegroundColor Green
    Write-Host "      bash scripts/bootstrap.sh" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Store the repo inside your WSL2 home folder (~/) — not under" -ForegroundColor DarkCyan
    Write-Host "  /mnt/c/ — for best performance." -ForegroundColor DarkCyan
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "  Install Ubuntu in WSL2 first (see instructions above)," -ForegroundColor Yellow
    Write-Host "  then run this script again to get the next steps." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  For full deployment instructions, see: docs/deployment.md" -ForegroundColor DarkCyan
Write-Host ""
