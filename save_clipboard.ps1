# ============================================================
# StockHero - Save Clipboard JSON to Domain Raw Folder
# ============================================================
# Domain-aware. Writes bookmarklet output to:
#   domains/<domain>/kols/<author>/raw/<platform>.json
#
# Auto-detects:
#   - Domain (if only one domain exists)
#   - Platform (from URL pattern in first entry)
#
# Usage:
#   .\save_clipboard.ps1                                          # auto domain + platform
#   .\save_clipboard.ps1 -Author zhao1945
#   .\save_clipboard.ps1 -Domain tw_stock_kol -Author zhao1945
#   .\save_clipboard.ps1 -Platform ig_main                        # force platform
# ============================================================

param(
    [ValidateSet('auto','fb','ig_main','ig_reels','threads')]
    [string]$Platform = 'auto',

    [string]$Author = 'zhao1945',

    [string]$Domain = ''
)

Add-Type -AssemblyName System.Windows.Forms
$base = $PSScriptRoot

# === Auto-detect domain ===
if (-not $Domain) {
    $allDomains = @(Get-ChildItem "$base\domains" -Directory -ErrorAction SilentlyContinue)
    if ($allDomains.Count -eq 1) {
        $Domain = $allDomains[0].Name
        Write-Host "Auto-detected domain: $Domain" -ForegroundColor DarkCyan
    } elseif ($allDomains.Count -eq 0) {
        Write-Host "ERROR: no domains found under $base\domains\" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "ERROR: multiple domains exist, use -Domain to specify" -ForegroundColor Red
        Write-Host "Available: $(($allDomains | ForEach-Object Name) -join ', ')"
        exit 1
    }
}

$kolDir = "$base\domains\$Domain\kols\$Author"
$rawDir = "$kolDir\raw"
if (-not (Test-Path "$base\domains\$Domain")) {
    Write-Host "ERROR: domain folder not found: $base\domains\$Domain" -ForegroundColor Red
    exit 1
}
New-Item -ItemType Directory -Path $rawDir -Force | Out-Null

# === Read clipboard ===
$data = [System.Windows.Forms.Clipboard]::GetText()
Write-Host "Clipboard length: $($data.Length)"
if ($data.Length -lt 200) {
    Write-Host "ERROR: clipboard too short - did you click Copy?" -ForegroundColor Red
    if ($data.Length -gt 0) { Write-Host "Content: $data" }
    exit 1
}
Write-Host "First 200 chars: $($data.Substring(0, [Math]::Min(200, $data.Length)))"

# === Parse JSON ===
try {
    $arr = $data | ConvertFrom-Json
} catch {
    Write-Host "ERROR: clipboard is not valid JSON - $_" -ForegroundColor Red
    exit 1
}
Write-Host "Post count: $($arr.Count)"

# === Auto-detect platform ===
if ($Platform -eq 'auto' -and $arr.Count -gt 0) {
    $firstUrl = $arr[0].url
    $firstType = $arr[0].type
    if ($firstUrl -match 'facebook\.com')           { $Platform = 'fb' }
    elseif ($firstUrl -match 'instagram\.com/reel') { $Platform = 'ig_reels' }
    elseif ($firstUrl -match 'instagram\.com')      { $Platform = 'ig_main' }
    elseif ($firstUrl -match 'threads\.(net|com)')  { $Platform = 'threads' }
    elseif ($firstType -eq 'reel')                  { $Platform = 'ig_reels' }
    else {
        Write-Host "WARNING: cannot auto-detect platform; use -Platform" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Auto-detected platform: $Platform" -ForegroundColor DarkCyan
}

# === Resolve output path ===
$pathMap = @{
    'fb'       = "$rawDir\facebook.json"
    'ig_main'  = "$rawDir\instagram_main.json"
    'ig_reels' = "$rawDir\instagram_reels.json"
    'threads'  = "$rawDir\threads.json"
}
$outPath = $pathMap[$Platform]

[System.IO.File]::WriteAllText($outPath, $data, [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "===== Saved =====" -ForegroundColor Green
Write-Host "  Domain  : $Domain"
Write-Host "  Author  : $Author"
Write-Host "  Platform: $Platform"
Write-Host "  Output  : $outPath"
Write-Host "  Posts   : $($arr.Count)"

# === Optional: date range summary ===
$datedPosts = $arr | Where-Object { $_.date }
if ($datedPosts.Count -gt 0) {
    try {
        $sorted = $datedPosts | Sort-Object { [DateTime]::Parse($_.date) }
        $first = $sorted[0].date; $last = $sorted[-1].date
        $days = ([DateTime]::Parse($last) - [DateTime]::Parse($first)).Days
        Write-Host "  Date range: $first → $last ($days days)" -ForegroundColor Gray
    } catch {}
}
