$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$source = Join-Path $scriptDir "AGENTS_template.md"
$userHome = $env:USERPROFILE
$claudeDir = Join-Path $userHome ".claude"
$codexDir = Join-Path $userHome ".codex"
$envDir = "C:\env"

$targets = @(
    @{ Path = $claudeDir; FileName = "CLAUDE.md" },
    @{ Path = $codexDir; FileName = "AGENTS.md" }
)

function Ensure-Directory($dir) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created directory: $dir" -ForegroundColor Yellow
    }
}

function Sync-File($src, $dest) {
    Copy-Item -Path $src -Destination $dest -Force
    Write-Host "Synced -> $dest" -ForegroundColor Green
}

if (-not (Test-Path $source)) {
    Write-Host "Source not found: $source" -ForegroundColor Red
    exit 1
}

Write-Host "=== Sync AGENTS_template.md ===" -ForegroundColor Cyan
Write-Host "Source: $source"

foreach ($target in $targets) {
    Ensure-Directory $target.Path
    $destination = Join-Path $target.Path $target.FileName
    Sync-File $source $destination
}

Write-Host ""
Write-Host "=== Sync env binaries to $envDir ===" -ForegroundColor Cyan
Ensure-Directory $envDir

$envFiles = @("clauded.bat", "codexd.bat")
foreach ($file in $envFiles) {
    $src = Join-Path $scriptDir $file
    $dest = Join-Path $envDir $file
    if (-not (Test-Path $src)) {
        Write-Host "Skip (source missing): $src" -ForegroundColor Yellow
        continue
    }
    Sync-File $src $dest
}

Write-Host ""
Write-Host "=== Setup Claude statusline ===" -ForegroundColor Cyan
$statuslineSrc = Join-Path $scriptDir "statusline.sh"
$statuslineDest = Join-Path $claudeDir "statusline.sh"
$settingsFile = Join-Path $claudeDir "settings.json"

if (-not (Test-Path $statuslineSrc)) {
    Write-Host "Skip (statusline.sh missing): $statuslineSrc" -ForegroundColor Yellow
} else {
    Ensure-Directory $claudeDir

    Sync-File $statuslineSrc $statuslineDest

    if (-not (Test-Path $settingsFile)) {
        '{}' | Out-File -FilePath $settingsFile -Encoding utf8
        Write-Host "Created settings.json" -ForegroundColor Yellow
    }

    $json = Get-Content $settingsFile -Raw | ConvertFrom-Json
    $needWrite = $false

    if (-not $json.PSObject.Properties.Match('statusLine').Count) {
        $statusLineObj = [PSCustomObject]@{
            type    = "command"
            command = "bash ~/.claude/statusline.sh"
        }
        $json | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLineObj
        $needWrite = $true
        Write-Host "Added statusLine config" -ForegroundColor Green
    } else {
        Write-Host "statusLine already configured, skip" -ForegroundColor DarkGray
    }

    if (-not $json.PSObject.Properties.Match('env').Count) {
        $envObj = [PSCustomObject]@{
            ANTHROPIC_AUTH_TOKEN          = "hocai-api-cua-ban"
            ANTHROPIC_BASE_URL            = "https://danglamgiau.com"
            ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-haiku-4-5"
            ANTHROPIC_DEFAULT_OPUS_MODEL  = "claude-opus-4-6"
            ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-4-6"
            ANTHROPIC_MODEL               = "claude-opus-4-6"
        }
        $json | Add-Member -NotePropertyName env -NotePropertyValue $envObj
        $needWrite = $true
        Write-Host "Added env block" -ForegroundColor Green
    } else {
        Write-Host "env already configured, skip" -ForegroundColor DarkGray
    }

    if (-not $json.PSObject.Properties.Match('model').Count) {
        $json | Add-Member -NotePropertyName model -NotePropertyValue "opus"
        $needWrite = $true
        Write-Host "Added model = opus" -ForegroundColor Green
    } else {
        Write-Host "model already configured, skip" -ForegroundColor DarkGray
    }

    if ($needWrite) {
        $json | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsFile -Encoding utf8
        Write-Host "Wrote settings.json" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
