# Minimalist Dark Islands Bootstrap Installer for Windows
# One-liner:
#   irm https://raw.githubusercontent.com/tfdmendes/minimalist-dark-islands/main/bootstrap.ps1 | iex

param()

$ErrorActionPreference = "Stop"

$RepoUrl = if ($env:MINIMALIST_DARK_ISLANDS_REPO) {
    $env:MINIMALIST_DARK_ISLANDS_REPO
} else {
    "https://github.com/tfdmendes/minimalist-dark-islands.git"
}
$Branch = if ($env:MINIMALIST_DARK_ISLANDS_BRANCH) {
    $env:MINIMALIST_DARK_ISLANDS_BRANCH
} else {
    "main"
}
$InstallDir = Join-Path $env:TEMP "minimalist-dark-islands-temp"

Write-Host "Minimalist Dark Islands Bootstrap Installer"
Write-Host "==========================================="
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is required to download the installer: https://git-scm.com/download/win"
    exit 1
}

Write-Host "Step 1: Downloading Minimalist Dark Islands..."
Write-Host "Repository: $RepoUrl"

if (Test-Path $InstallDir) {
    Remove-Item -Recurse -Force $InstallDir
}

try {
    git clone $RepoUrl $InstallDir --quiet --branch $Branch
} catch {
    Write-Error "Failed to download Minimalist Dark Islands. $($_.Exception.Message)"
    exit 1
}

Write-Host "Downloaded successfully."
Write-Host ""

Write-Host "Step 2: Running installer..."
Write-Host ""

Set-Location $InstallDir
try {
    .\install.ps1
} catch {
    Write-Error "Installation failed. $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "Step 3: Cleaning up..."
$RemoveTemp = Read-Host "Remove temporary files? [y/N]"
if ($RemoveTemp -eq "y" -or $RemoveTemp -eq "Y" -or $RemoveTemp -eq "yes" -or $RemoveTemp -eq "YES") {
    Remove-Item -Recurse -Force $InstallDir
    Write-Host "Temporary files removed."
} else {
    Write-Host "Files kept at: $InstallDir"
}

Write-Host ""
Write-Host "Done. Enjoy Minimalist Dark Islands."
