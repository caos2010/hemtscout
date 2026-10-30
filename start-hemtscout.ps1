$ErrorActionPreference = 'Stop'
$env:HERMES_HOME = Join-Path $env:LOCALAPPDATA 'HEMTScout\hermes'
$projectRoot = $PSScriptRoot
$hermes = Get-Command 'hermes.exe' -ErrorAction SilentlyContinue
if (-not $hermes) {
    $candidate = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
    if (Test-Path -LiteralPath $candidate) { $hermesPath = $candidate }
    else { throw 'Không tìm thấy Hermes. Chạy setup-windows.ps1 trước.' }
} else {
    $hermesPath = $hermes.Source
}
Set-Location -LiteralPath $projectRoot
& $hermesPath chat
