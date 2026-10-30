[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'HEMTScout')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Get-ProjectFiles {
    return @(
        'README.md',
        '.gitignore',
        'pyproject.toml',
        'evaluate_hemt_lora.py',
        'merge_hemt_pilot.py',
        'train_hemt_lora.py',
        'Modelfile.hermes-qwen3-instruct-64k',
        'Modelfile.hermes-qwen3.5-fast-64k',
        'Modelfile.qwen3-0.6b-64k',
        'install-hermes-skill.ps1',
        'setup-windows.ps1',
        'start-hemtscout.ps1',
        'data/eval/hemt_eval.csv',
        'data/finetune/README.md',
        'src',
        'hermes'
    )
}

function Copy-ProjectToInstallRoot([string]$SourceRoot, [string]$DestinationRoot) {
    $sourcePath = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $destinationPath = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
    if ($sourcePath.Equals($destinationPath, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    foreach ($relativePath in Get-ProjectFiles) {
        $from = Join-Path $sourcePath $relativePath
        if (-not (Test-Path -LiteralPath $from)) {
            throw "Thiếu tệp cần cài: $from"
        }
        $to = Join-Path $destinationPath $relativePath
        if ((Get-Item -LiteralPath $from).PSIsContainer) {
            New-Item -ItemType Directory -Path $to -Force | Out-Null
            Get-ChildItem -LiteralPath $from -Force | Copy-Item -Destination $to -Recurse -Force
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
    }
}

function Get-PythonCommand {
    $py = Get-Command 'py.exe' -ErrorAction SilentlyContinue
    if ($py) {
        & $py.Source -3.12 --version *> $null
        if ($LASTEXITCODE -eq 0) { return @{ Path = $py.Source; Prefix = @('-3.12') } }
    }

    $python = Get-Command 'python.exe' -ErrorAction SilentlyContinue
    if ($python) {
        & $python.Source --version *> $null
        if ($LASTEXITCODE -eq 0) {
            $versionText = (& $python.Source --version 2>&1 | Out-String).Trim()
            if ($versionText -match 'Python\s+3\.(1[0-9]|[2-9][0-9])') {
                return @{ Path = $python.Source; Prefix = @() }
            }
        }
    }
    return $null
}

function Ensure-Python {
    $python = Get-PythonCommand
    if ($python) { return $python }

    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'Chưa có Python 3.12 và winget. Cài Python 3.12 từ https://www.python.org/downloads/windows/, mở PowerShell mới rồi chạy lại setup-windows.ps1.'
    }

    Write-Step 'Cài Python 3.12 (chỉ cho tài khoản Windows hiện tại)'
    & $winget.Source install --id Python.Python.3.12 --exact --scope user --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget không cài được Python (mã $LASTEXITCODE). Cài Python 3.12 từ https://www.python.org/downloads/windows/ rồi chạy lại script."
    }

    $env:Path = "$env:LOCALAPPDATA\Programs\Python\Python312;$env:LOCALAPPDATA\Programs\Python\Python312\Scripts;$env:Path"
    $python = Get-PythonCommand
    if (-not $python) {
        throw 'Python đã được cài nhưng chưa xuất hiện trong phiên PowerShell này. Mở PowerShell mới tại thư mục dự án và chạy lại setup-windows.ps1.'
    }
    return $python
}

function Get-OllamaCommand {
    $command = Get-Command 'ollama.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        (Join-Path $env:ProgramFiles 'Ollama\ollama.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    if ($candidates) { return $candidates[0] }
    return $null
}

function Ensure-Ollama {
    $ollama = Get-OllamaCommand
    if (-not $ollama) {
        Write-Step 'Cài Ollama từ máy chủ cài đặt chính thức'
        $installerText = (Invoke-WebRequest -Uri 'https://ollama.com/install.ps1' -UseBasicParsing).Content
        if (-not $installerText) { throw 'Không tải được trình cài Ollama chính thức.' }
        & ([scriptblock]::Create($installerText))
        $ollama = Get-OllamaCommand
        if (-not $ollama) { throw 'Cài Ollama xong nhưng không tìm thấy ollama.exe. Mở PowerShell mới rồi chạy lại script.' }
    }

    $ollamaDirectory = Split-Path -Parent $ollama
    if (($env:Path -split ';') -notcontains $ollamaDirectory) {
        $env:Path = "$ollamaDirectory;$env:Path"
    }
    return $ollama
}

function Test-OllamaApi {
    try {
        $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3
        return $true
    } catch { return $false }
}

function Wait-OllamaApi([string]$OllamaPath) {
    if (-not (Test-OllamaApi)) {
        Write-Host 'Đang khởi động Ollama...'
        Start-Process -FilePath $OllamaPath -ArgumentList 'serve' -WindowStyle Hidden
    }
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if (Test-OllamaApi) { return }
        Start-Sleep -Seconds 2
    }
    throw 'Ollama chưa mở API tại 127.0.0.1:11434. Khởi động ứng dụng Ollama rồi chạy lại script.'
}

function Ensure-Hermes {
    $hermes = Get-Command 'hermes.exe' -ErrorAction SilentlyContinue
    if (-not $hermes) {
        Write-Step 'Cài Hermes Agent chính thức (bỏ qua trình duyệt và computer-use không cần thiết)'
        $installerText = (Invoke-WebRequest -Uri 'https://hermes-agent.nousresearch.com/install.ps1' -UseBasicParsing).Content
        if (-not $installerText) { throw 'Không tải được trình cài Hermes chính thức.' }
        & ([scriptblock]::Create($installerText)) -NonInteractive -SkipBrowser -SkipComputerUse
    }

    $hermesBin = Join-Path $env:LOCALAPPDATA 'hermes\bin'
    if (Test-Path -LiteralPath $hermesBin) { $env:Path = "$hermesBin;$env:Path" }
    $hermes = Get-Command 'hermes.exe' -ErrorAction SilentlyContinue
    if (-not $hermes) { throw 'Không tìm thấy Hermes sau khi cài. Mở PowerShell mới rồi chạy lại setup-windows.ps1.' }
    return $hermes.Source
}

function Set-HermesValue([string]$HermesPath, [string]$Key, [string]$Value) {
    & $HermesPath config set $Key $Value
    if ($LASTEXITCODE -ne 0) { throw "Hermes không ghi được cấu hình '$Key'. Mở PowerShell mới và chạy lại setup-windows.ps1." }
}

function Install-ManagedSoul([string]$SourceSoul, [string]$TargetSoul) {
    $begin = '<!-- HEMTScout managed instructions: begin -->'
    $end = '<!-- HEMTScout managed instructions: end -->'
    $managed = Get-Content -LiteralPath $SourceSoul -Raw -Encoding UTF8
    $managed = $managed.Trim()
    $existing = if (Test-Path -LiteralPath $TargetSoul) { Get-Content -LiteralPath $TargetSoul -Raw -Encoding UTF8 } else { '' }
    $pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
    $block = "$begin`r`n$managed`r`n$end"
    $match = [regex]::Match($existing, $pattern)
    if ($match.Success) {
        $existing = $existing.Substring(0, $match.Index) + $block + $existing.Substring($match.Index + $match.Length)
    } else {
        $existing = $existing.TrimEnd()
        if ($existing) { $existing += "`r`n`r`n" }
        $existing += $block + "`r`n"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $TargetSoul) -Force | Out-Null
    Set-Content -LiteralPath $TargetSoul -Value $existing -Encoding UTF8
}

function Add-StartMenuShortcut([string]$LauncherPath, [string]$ProjectRoot) {
    try {
        $menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        New-Item -ItemType Directory -Path $menu -Force | Out-Null
        $shortcutPath = Join-Path $menu 'HEMTScout.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$LauncherPath`""
        $shortcut.WorkingDirectory = $ProjectRoot
        $shortcut.Description = 'Mở chatbot HEMTScout bằng tiếng Việt'
        $shortcut.Save()
        Write-Host "Đã tạo lối tắt trong Start Menu: $shortcutPath"
    } catch {
        Write-Warning "Không tạo được lối tắt Start Menu; vẫn có thể chạy .\start-hemtscout.ps1. Chi tiết: $($_.Exception.Message)"
    }
}

if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
    throw 'Bộ cài này chỉ dành cho Windows 10/11.'
}

$sourceRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
Write-Step "Chuẩn bị thư mục HEMTScout tại $InstallRoot"
Copy-ProjectToInstallRoot -SourceRoot $sourceRoot -DestinationRoot $InstallRoot
$projectRoot = $InstallRoot
$hermesHome = Join-Path $env:LOCALAPPDATA 'HEMTScout\hermes'
$modelName = 'hemt-qwen3-instruct:64k'

# Keep the HEMTScout profile separate so an existing Hermes configuration is not replaced.
$env:HERMES_HOME = $hermesHome
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'data\papers') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'data\eval') -Force | Out-Null

$memory = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
if ($memory -and $memory.TotalPhysicalMemory -lt 16GB) {
    Write-Warning 'Máy có dưới 16 GB RAM. Bộ cài vẫn tiếp tục, nhưng model 4B với cửa sổ 64K có thể chạy chậm hoặc thiếu bộ nhớ.'
}

Write-Step 'Kiểm tra và cài Python'
$python = Ensure-Python
$venvPython = Join-Path $projectRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    & $python.Path @($python.Prefix) -m venv (Join-Path $projectRoot '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Không tạo được môi trường Python ảo.' }
}
Write-Host 'Cài HEMTScout và thư viện đọc PDF...'
& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw 'Không nâng cấp được pip.' }
& $venvPython -m pip install -e $projectRoot
if ($LASTEXITCODE -ne 0) { throw 'Không cài được HEMTScout hoặc PyMuPDF.' }

Write-Step 'Cài và khởi động Ollama'
$ollamaPath = Ensure-Ollama
Wait-OllamaApi -OllamaPath $ollamaPath

Write-Step 'Tải model Qwen3 4B và tạo cấu hình 64K'
& $ollamaPath pull 'qwen3:4b-instruct'
if ($LASTEXITCODE -ne 0) { throw 'Tải model thất bại. Kiểm tra kết nối Internet/dung lượng đĩa rồi chạy lại script.' }
& $ollamaPath create $modelName -f (Join-Path $projectRoot 'Modelfile.hermes-qwen3-instruct-64k')
if ($LASTEXITCODE -ne 0) { throw 'Không tạo được model HEMTScout trong Ollama.' }

Write-Step 'Cài Hermes Agent và cấu hình chatbot riêng'
$hermesPath = Ensure-Hermes
Set-HermesValue $hermesPath 'model.default' $modelName
Set-HermesValue $hermesPath 'model.provider' 'custom'
Set-HermesValue $hermesPath 'model.base_url' 'http://127.0.0.1:11434/v1'
Set-HermesValue $hermesPath 'model.api_key' 'ollama'
Set-HermesValue $hermesPath 'model.context_length' '65536'
Set-HermesValue $hermesPath 'agent.reasoning_effort' 'none'
Set-HermesValue $hermesPath 'mcp_servers.hemtscout.command' $venvPython
Set-HermesValue $hermesPath 'mcp_servers.hemtscout.args' '["-m","hemtscout.mcp_server"]'
Set-HermesValue $hermesPath 'mcp_servers.hemtscout.timeout' '120'
Set-HermesValue $hermesPath 'mcp_servers.hemtscout.tools.include' '["hemtscout_paper","hemtscout_search","hemtscout_papers"]'

Write-Step 'Cài skill đọc paper và thiết lập trả lời bằng tiếng Việt'
& (Join-Path $projectRoot 'install-hermes-skill.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Không cài được skill HEMTScout.' }
Install-ManagedSoul -SourceSoul (Join-Path $projectRoot 'hermes\SOUL.md') -TargetSoul (Join-Path $hermesHome 'SOUL.md')
Add-StartMenuShortcut -LauncherPath (Join-Path $projectRoot 'start-hemtscout.ps1') -ProjectRoot $projectRoot

Write-Host "`nCài đặt hoàn tất." -ForegroundColor Green
Write-Host "Thư viện PDF riêng của máy này: $(Join-Path $projectRoot 'data\papers')"
Write-Host 'Chép PDF vào thư mục trên, sau đó mở HEMTScout từ Start Menu hoặc chạy .\start-hemtscout.ps1.'
Write-Host 'Lần cài đầu đã tải model vài GB; hiệu năng phụ thuộc RAM, GPU và driver của máy.'
