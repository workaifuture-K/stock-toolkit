# Merge IG raw + canonical for one author (domain-aware)
# Reads: domains/<d>/kols/<a>/raw/instagram_main.json, raw/instagram_reels.json,
#        domains/<d>/kols/<a>/canonical/instagram.json (if exists)
# Writes: domains/<d>/kols/<a>/canonical/instagram.json
# Dedup: URL shortcode (longest content wins) → content hash (fill-in fields)
#
# Usage:
#   .\merge_ig.ps1 -Author zhao1945
#   .\merge_ig.ps1 -Domain tw_stock_kol -Author zhao1945
#   .\merge_ig.ps1 -Author zhao1945 -IncludeFiles "C:\path\legacy.json"

param(
    [Parameter(Mandatory=$true)]
    [string]$Author,

    [string]$Domain = '',
    [string[]]$IncludeFiles = @()
)

$base = $PSScriptRoot

# Auto-detect domain
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
$canonical = "$canonicalDir\instagram.json"

# Sources: raw IG files + existing canonical (if any) + extras
$autoFiles = @()
foreach ($f in @("$rawDir\instagram_main.json", "$rawDir\instagram_reels.json", $canonical)) {
    if (Test-Path $f) { $autoFiles += $f }
}

$allFiles = New-Object System.Collections.ArrayList
foreach ($f in $autoFiles) { [void]$allFiles.Add($f) }
foreach ($f in $IncludeFiles) {
    $resolved = if ([System.IO.Path]::IsPathRooted($f)) { $f } else { Join-Path $base $f }
    if (-not ($allFiles -contains $resolved)) { [void]$allFiles.Add($resolved) }
}

if ($allFiles.Count -eq 0) {
    Write-Host "ERROR: No source files for '$Author'"
    Write-Host "Looked for: $base\instagram_${Author}*.json"
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
if ($existing.Count -eq 0) { Write-Host "ERROR: all missing"; exit 1 }

function ContentKey($c) {
    if (-not $c) { return '' }
    $n = $c -replace '\s+', ' '
    return $n.Substring(0, [Math]::Min(150, $n.Length))
}
# Extract IG post shortcode for URL-aware dedup.
# Returns canonical key "p/<sc>" or "reel/<sc>", or $null if URL absent / unparseable.
function Get-Shortcode($url) {
    if (-not $url) { return $null }
    if ($url -match '/(p|reel)/([^/?]+)') { return "$($matches[1])/$($matches[2])" }
    return $null
}

$seenContent = @{}        # content_key -> merged index
$seenShortcode = @{}      # shortcode   -> merged index
$merged = New-Object System.Collections.ArrayList
$stats = @()

foreach ($f in $existing) {
    try {
        $arr = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch { Write-Host "  WARN: parse error $f"; continue }

    # Skip placeholder files (< 100 bytes typically just contain ph data)
    if ($arr.Count -eq 0) { continue }

    $before = $merged.Count
    $upgraded = 0
    foreach ($p in $arr) {
        if (-not $p.content) { continue }
        $sc = Get-Shortcode $p.url

        # Priority 1: URL shortcode collision (same post, possibly comment vs caption)
        if ($sc -and $seenShortcode.ContainsKey($sc)) {
            $idx = $seenShortcode[$sc]
            $existing = $merged[$idx]
            # Keep the entry with longer content (caption > comment)
            if (([string]$p.content).Length -gt ([string]$existing.content).Length) {
                $merged[$idx] = $p
                # Rebind content key to the longer entry
                $newK = ContentKey $p.content
                $seenContent[$newK] = $idx
                $upgraded++
            }
            continue
        }

        # Priority 2: content hash collision (same content, different URL state)
        $k = ContentKey $p.content
        if (-not $seenContent.ContainsKey($k)) {
            # First time seeing this content
            $seenContent[$k] = $merged.Count
            if ($sc) { $seenShortcode[$sc] = $merged.Count }
            [void]$merged.Add($p)
        } else {
            $idx = $seenContent[$k]
            $existing = $merged[$idx]
            # Upgrade if new entry has data existing lacks (URL, date, type)
            $upgrade = $false
            if (-not $existing.url  -and $p.url)  { $upgrade = $true }
            if (-not $existing.date -and $p.date) { $upgrade = $true }
            if (-not $existing.type -and $p.type) { $upgrade = $true }
            if ($upgrade) {
                $merged[$idx] = $p
                if ($sc) { $seenShortcode[$sc] = $idx }
                $upgraded++
            }
        }
    }
    $stats += [PSCustomObject]@{ File = $f.Substring($base.Length+1); InCount = $arr.Count; AddedNew = $merged.Count - $before; Upgraded = $upgraded }
}

Write-Host ""
Write-Host "===== Per-file ====="
foreach ($s in $stats) {
    Write-Host ("  {0,-50}  in={1,4}  +new={2,4}  upgraded={3,4}" -f $s.File, $s.InCount, $s.AddedNew, $s.Upgraded)
}

$sorted = $merged | Sort-Object @{Expression={ try { [DateTime]::Parse($_.date) } catch { [DateTime]::MinValue } }; Descending=$true}
$jsonOut = $sorted | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($canonical, $jsonOut, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "===== Result ====="
Write-Host "Total unique: $($sorted.Count)"
Write-Host "Saved to: $canonical"

$dated = $sorted | Where-Object { try { [DateTime]::Parse($_.date) | Out-Null; $true } catch { $false } }
if ($dated.Count -gt 0) {
    $byDate = $dated | Sort-Object { [DateTime]::Parse($_.date) }
    $f = $byDate[0].date; $l = $byDate[-1].date
    $d = ([DateTime]::Parse($l) - [DateTime]::Parse($f)).Days
    Write-Host "Date range: $f -> $l ($d days = $([math]::Round($d/30,1)) months)"
}

# Type breakdown (post vs reel)
$byType = $sorted | Group-Object type
if ($byType.Count -gt 0) {
    Write-Host ""
    Write-Host "By type:"
    foreach ($g in $byType) { Write-Host "  $($g.Name): $($g.Count)" }
}
