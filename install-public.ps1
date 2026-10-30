$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($env:OS -ne 'Windows_NT') {
    throw 'Bộ cài HEMTScout hiện chỉ hỗ trợ Windows 10/11.'
}

$stage = Join-Path $env:TEMP ('HEMTScout-bootstrap-' + [Guid]::NewGuid().ToString('N'))
$archive = Join-Path $stage 'hemtscout-main.zip'
$archiveUrl = 'https://github.com/caos2010/hemtscout/archive/refs/heads/main.zip'

try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Write-Host 'Đang tải mã nguồn HEMTScout công khai từ GitHub...'
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archive -UseBasicParsing

    Write-Host 'Đang giải nén bộ cài tạm...'
    Expand-Archive -LiteralPath $archive -DestinationPath $stage -Force
    $setupScripts = @(Get-ChildItem -LiteralPath $stage -Filter 'setup-windows.ps1' -File -Recurse)
    if ($setupScripts.Count -ne 1) {
        throw 'Không tìm thấy duy nhất một setup-windows.ps1 trong gói tải về.'
    }

    Write-Host 'Bắt đầu cài Hermes, Ollama, model và HEMTScout...'
    & $setupScripts[0].FullName
} finally {
    if (Test-Path -LiteralPath $stage) {
        $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
        $stagePath = [IO.Path]::GetFullPath($stage)
        $isSafeStage = $stagePath.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($stagePath) -match '^HEMTScout-bootstrap-[0-9a-f]{32}$'
        if ($isSafeStage) {
            Remove-Item -LiteralPath $stagePath -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Warning 'Không xóa thư mục tạm vì đường dẫn không khớp vùng dọn dẹp an toàn.'
        }
    }
}
