$ErrorActionPreference = 'Stop'
$skillSource = Join-Path $PSScriptRoot 'hermes\skills\hemt-paper-research-fast\SKILL.md'
$hermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:USERPROFILE 'AppData\Local\hermes' }
$skillTarget = Join-Path $hermesHome 'skills\research\hemt-paper-research-fast'
New-Item -ItemType Directory -Force -Path $skillTarget | Out-Null
Copy-Item -LiteralPath $skillSource -Destination (Join-Path $skillTarget 'SKILL.md') -Force
Write-Host "Hermes skill installed to $(Join-Path $skillTarget 'SKILL.md')"
Write-Host 'Install HEMTScout with: .\.venv\Scripts\python.exe -m pip install -e .'
