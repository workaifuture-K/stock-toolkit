# ============================================================
# StockHero - Canonical Cleanup (dedupe + comment-pollution)
# ============================================================
# Fixes two systemic data quality issues in canonical files:
#
#   1) Same URL, different content (early bookmark versions sometimes
#      captured COMMENTS as if they were the post caption).
#      Fix: group by URL shortcode, keep the entry with longest content
#      (caption is always longer than a comment).
#
#   2) No-URL entries that duplicate a with-URL entry (early bookmarks
#      didn't capture URL field; same caption later got scraped with URL).
#      Fix: compare no-URL content's first 60 chars to all with-URL
#      content prefixes; drop matches; keep truly independent ones.
#
#   3) No-URL vs no-URL duplicates: dedupe among themselves by content prefix.
#
# Original canonical is backed up to <plat>.json.dirty.bak before overwrite.
#
# Usage:
#   .\cleanup_canonical.ps1 -Domain tw_stock_kol -Author zhao1945
#   .\cleanup_canonical.ps1 -Domain X -Author Y -Platform instagram
#   .\cleanup_canonical.ps1 -Domain X -Author Y -DryRun
# ============================================================

param(
    [Parameter(Mandatory=$true)] [string]$Domain,
    [Parameter(Mandatory=$true)] [string]$Author,

    [ValidateSet('all','instagram','threads','facebook')]
    [string]$Platform = 'all',

    [switch]$DryRun
)

$base = $PSScriptRoot
$canonicalDir = "$base\domains\$Domain\kols\$Author\canonical"
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $canonicalDir)) {
    Write-Host "ERROR: canonical dir not found: $canonicalDir" -ForegroundColor Red
    exit 1
}

$urlPatterns = @{
    'instagram' = '/(p|reel)/([^/?]+)'
    'threads'   = '/post/([^/?]+)'
    'facebook'  = '(?:posts|videos|reel)/([^/?]+)'
}

function Cleanup-Platform($plat) {
    $f = "$canonicalDir\$plat.json"
    if (-not (Test-Path $f)) { Write-Host "[$plat] file not found, skip"; return }

    $data = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $total = @($data).Count
    $pattern = $urlPatterns[$plat]

    # Step 1: dedupe by URL shortcode — keep longest content
    $byShortcode = @{}
    $noUrl = New-Object System.Collections.ArrayList
    foreach ($p in $data) {
        if ($p.url -and $p.url -match $pattern) {
            $key = $matches[0]
            if (-not $byShortcode.ContainsKey($key)) {
                $byShortcode[$key] = $p
            } elseif (([string]$p.content).Length -gt ([string]$byShortcode[$key].content).Length) {
                $byShortcode[$key] = $p
            }
        } else {
            [void]$noUrl.Add($p)
        }
    }

    $s1Withurl = $byShortcode.Count
    $s1Excess = $total - $s1Withurl - $noUrl.Count

    # Step 2: drop no-URL entries that match a with-URL entry by content prefix
    function Prefix-Key($s) {
        if (-not $s) { return '' }
        $n = ([string]$s) -replace '\s+', ' '
        return $n.Substring(0, [Math]::Min(60, $n.Length))
    }
    $withUrlPrefixSet = @{}
    foreach ($p in $byShortcode.Values) {
        $key = Prefix-Key $p.content
        if ($key) { $withUrlPrefixSet[$key] = $true }
    }
    $noUrlSurvivors = New-Object System.Collections.ArrayList
    $s2DroppedAsDupe = 0
    foreach ($p in $noUrl) {
        $key = Prefix-Key $p.content
        if (-not $key) { $s2DroppedAsDupe++; continue }
        if ($withUrlPrefixSet.ContainsKey($key)) { $s2DroppedAsDupe++; continue }
        [void]$noUrlSurvivors.Add($p)
    }

    # Step 3: dedupe no-URL survivors among themselves by content prefix (keep first)
    $seenNoUrl = @{}
    $finalNoUrl = New-Object System.Collections.ArrayList
    $s3InternalDupes = 0
    foreach ($p in $noUrlSurvivors) {
        $key = Prefix-Key $p.content
        if ($seenNoUrl.ContainsKey($key)) { $s3InternalDupes++; continue }
        $seenNoUrl[$key] = $true
        [void]$finalNoUrl.Add($p)
    }

    # Combine + sort by date desc
    $combined = @($byShortcode.Values) + @($finalNoUrl)
    $sorted = $combined | Sort-Object {
        if ($_.date -and $_.date -match '^\d{4}-\d{1,2}-\d{1,2}') {
            try { [DateTime]::Parse($_.date) } catch { [DateTime]::MinValue }
        } else { [DateTime]::MinValue }
    } -Descending

    $finalCount = $sorted.Count
    $removed = $total - $finalCount

    Write-Host ""
    Write-Host "[$plat]" -ForegroundColor Cyan
    Write-Host ("  Before:                {0}" -f $total)
    Write-Host ("  Step 1 (shortcode):    {0} unique URLs ({1} dupe entries removed)" -f $s1Withurl, $s1Excess)
    Write-Host ("  Step 2 (no-URL match): {0} no-URL dropped as duplicate of with-URL" -f $s2DroppedAsDupe)
    Write-Host ("  Step 3 (no-URL intra): {0} dropped as no-URL internal dupes" -f $s3InternalDupes)
    Write-Host ("  After:                 {0}  (removed {1})" -f $finalCount, $removed) -ForegroundColor Green

    if (-not $DryRun) {
        Copy-Item $f "$f.dirty.bak" -Force
        $json = $sorted | ConvertTo-Json -Depth 14
        [System.IO.File]::WriteAllText($f, $json, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  Saved (backup -> $plat.json.dirty.bak)"
    } else {
        Write-Host "  (DryRun — no files written)" -ForegroundColor Yellow
    }
}

Write-Host "===== Canonical Cleanup =====" -ForegroundColor Cyan
Write-Host "Domain : $Domain"
Write-Host "Author : $Author"
Write-Host "Mode   : $(if ($DryRun) { 'DRY RUN' } else { 'WRITE' })"

if ($Platform -eq 'all') {
    foreach ($plat in 'instagram','threads','facebook') { Cleanup-Platform $plat }
} else {
    Cleanup-Platform $Platform
}
