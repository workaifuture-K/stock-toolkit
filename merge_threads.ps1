# Merge Threads raw + canonical for one author (domain-aware)
# Reads: domains/<d>/kols/<a>/raw/threads.json + canonical/threads.json (if exists)
# Writes: domains/<d>/kols/<a>/canonical/threads.json
# Dedup: URL shortcode → content hash
#
# Usage:
#   .\merge_threads.ps1 -Author zhao1945
#   .\merge_threads.ps1 -Domain tw_stock_kol -Author zhao1945

param(
    [Parameter(Mandatory=$true)]
    [string]$Author,

    [string]$Domain = '',
    [string[]]$IncludeFiles = @()
)

$base = $PSScriptRoot

if (-not $Domain) {
    $allDomains = @(Get-ChildItem "$base\domains" -Directory -ErrorAction SilentlyContinue)
    if ($allDomains.Count -eq 1) { $Domain = $allDomains[0].Name; Write-Host "Auto-detected domain: $Domain" -ForegroundColor DarkCyan }
    elseif ($allDomains.Count -eq 0) { Write-Host "ERROR: no domains found"; exit 1 }
    else { Write-Host "ERROR: multiple domains exist, use -Domain"; exit 1 }
}
$kolDir = "$base\domains\$Domain\kols\$Author"
$rawDir = "$kolDir\raw"
$canonicalDir = "$kolDir\canonical"
New-Item -ItemType Directory -Path $canonicalDir -Force | Out-Null
$canonical = "$canonicalDir\threads.json"

$autoFiles = @()
foreach ($f in @("$rawDir\threads.json", $canonical)) {
    if (Test-Path $f) { $autoFiles += $f }
}

# Add extras (legacy / explicit paths)
$allFiles = New-Object System.Collections.ArrayList
foreach ($f in $autoFiles) { [void]$allFiles.Add($f) }
foreach ($f in $IncludeFiles) {
    # Resolve relative paths against base dir
    $resolved = if ([System.IO.Path]::IsPathRooted($f)) { $f } else { Join-Path $base $f }
    if (-not ($allFiles -contains $resolved)) { [void]$allFiles.Add($resolved) }
}

if ($allFiles.Count -eq 0) {
    Write-Host "ERROR: No source files found for author '$Author'"
    Write-Host "Looked for: $base\threads_${Author}*.json"
    exit 1
}

Write-Host "===== Source files ====="
$existing = @()
foreach ($f in $allFiles) {
    if (Test-Path $f) {
        $sz = [math]::Round((Get-Item $f).Length / 1024, 1)
        Write-Host "  ✓ $($f.Substring($base.Length + 1)) ($sz KB)"
        $existing += $f
    } else {
        Write-Host "  ✗ $($f.Substring($base.Length + 1)) (missing)"
    }
}

if ($existing.Count -eq 0) { Write-Host "ERROR: All files missing"; exit 1 }

# Hash function: normalize whitespace, take first 150 chars
function ContentKey($content) {
    if (-not $content) { return '' }
    $n = $content -replace '\s+', ' '
    return $n.Substring(0, [Math]::Min(150, $n.Length))
}
# Threads post URL: https://www.threads.com/@user/post/<sc>
function Get-Shortcode($url) {
    if (-not $url) { return $null }
    if ($url -match '/post/([^/?]+)') { return "post/$($matches[1])" }
    return $null
}

$seenContent = @{}
$seenShortcode = @{}
$merged = New-Object System.Collections.ArrayList
$stats = @()

foreach ($f in $existing) {
    try {
        $raw = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
        $arr = $raw | ConvertFrom-Json
    } catch {
        Write-Host "  WARN: parse error on $f - $_"
        continue
    }

    $beforeSize = $merged.Count
    $upgraded = 0
    foreach ($p in $arr) {
        if (-not $p.content) { continue }
        $sc = Get-Shortcode $p.url

        if ($sc -and $seenShortcode.ContainsKey($sc)) {
            $idx = $seenShortcode[$sc]
            $existing = $merged[$idx]
            if (([string]$p.content).Length -gt ([string]$existing.content).Length) {
                $merged[$idx] = $p
                $seenContent[(ContentKey $p.content)] = $idx
                $upgraded++
            }
            continue
        }

        $k = ContentKey $p.content
        if (-not $seenContent.ContainsKey($k)) {
            $seenContent[$k] = $merged.Count
            if ($sc) { $seenShortcode[$sc] = $merged.Count }
            [void]$merged.Add($p)
        } else {
            $idx = $seenContent[$k]
            $existing = $merged[$idx]
            $upgrade = $false
            if (-not $existing.url  -and $p.url)  { $upgrade = $true }
            if (-not $existing.date -and $p.date) { $upgrade = $true }
            if ($upgrade) {
                $merged[$idx] = $p
                if ($sc) { $seenShortcode[$sc] = $idx }
                $upgraded++
            }
        }
    }
    $added = $merged.Count - $beforeSize
    $stats += [PSCustomObject]@{
        File = $f.Substring($base.Length + 1)
        InCount = $arr.Count
        AddedNew = $added
        Upgraded = $upgraded
    }
}

Write-Host ""
Write-Host "===== Per-file merge stats ====="
foreach ($s in $stats) {
    Write-Host ("  {0,-50}  in={1,4}  +new={2,4}  upgraded={3,4}" -f $s.File, $s.InCount, $s.AddedNew, $s.Upgraded)
}

# Sort by date desc
$sorted = $merged | Sort-Object @{Expression={
    try { [DateTime]::Parse($_.date) } catch { [DateTime]::MinValue }
}; Descending=$true}

# Save canonical
$jsonOut = $sorted | ConvertTo-Json -Depth 10 -Compress:$false
[System.IO.File]::WriteAllText($canonical, $jsonOut, [System.Text.UTF8Encoding]::new($false))

# Final stats
Write-Host ""
Write-Host "===== Result ====="
Write-Host "Total unique: $($sorted.Count)"
Write-Host "Saved to: $canonical"

$dated = $sorted | Where-Object {
    try { [DateTime]::Parse($_.date) | Out-Null; $true } catch { $false }
}
if ($dated.Count -gt 0) {
    $byDate = $dated | Sort-Object { [DateTime]::Parse($_.date) }
    $first = $byDate[0].date
    $last  = $byDate[-1].date
    $days  = ([DateTime]::Parse($last) - [DateTime]::Parse($first)).Days
    Write-Host "Date range: $first -> $last ($days days = $([math]::Round($days/30,1)) months)"
    Write-Host "Dated/total: $($dated.Count)/$($sorted.Count)"
}
