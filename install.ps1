param()

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallScript = Join-Path $ScriptDir "install-minimalist.sh"

if (-not (Test-Path $InstallScript)) {
    Write-Error "install-minimalist.sh was not found in $ScriptDir"
    exit 1
}

$Bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $Bash) {
    Write-Error "This installer uses install-minimalist.sh. Install Git for Windows or WSL so PowerShell can run bash, then try again."
    exit 1
}

& $Bash.Source $InstallScript
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
