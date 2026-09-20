$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $env:LOCALAPPDATA) {
    throw "LOCALAPPDATA is not set. Unable to locate Neovim's Windows config directory."
}

$TargetDir = Join-Path $env:LOCALAPPDATA "nvim"
$RequiredPaths = @("init.lua", "lua", "nvim-pack-lock.json")

foreach ($Path in $RequiredPaths) {
    $SourcePath = Join-Path $SourceDir $Path
    if (-not (Test-Path $SourcePath)) {
        throw "Missing required source: $SourcePath"
    }
}

$StagingDir = Join-Path $env:LOCALAPPDATA (".nvim-install-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $StagingDir | Out-Null

try {
    Copy-Item (Join-Path $SourceDir "init.lua") $StagingDir
    Copy-Item (Join-Path $SourceDir "nvim-pack-lock.json") $StagingDir
    Copy-Item (Join-Path $SourceDir "lua") $StagingDir -Recurse

    if (Test-Path $TargetDir) {
        $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $BackupDir = "$TargetDir.backup-$Timestamp"
        Move-Item $TargetDir $BackupDir
        Write-Host "Existing config backed up to $BackupDir"
    }

    Move-Item $StagingDir $TargetDir
}
catch {
    if (Test-Path $StagingDir) {
        Remove-Item $StagingDir -Recurse -Force
    }
    throw
}

Write-Host "Installed Neovim config to $TargetDir"
Write-Host "Included: init.lua, lua/, nvim-pack-lock.json"
Write-Host "Excluded: examples/, README.md, installer scripts, and Git metadata"
