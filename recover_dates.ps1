# ============================================================
# StockHero - Generic Date Recovery & Entity Decode
# ============================================================
# Replaces fix_v8_data.ps1 with multi-platform, multi-author support.
#
# Pipeline position: save_clipboard.ps1 -> recover_dates.ps1 -> merge -> analyze
#
# Stages per raw file:
#   1. Decode HTML entities (&#xHHHH; &#NNNN; named entities)
#   2. Normalize URL (strip author from path on IG)
#   3. Recover date by cross-referencing canonical (URL shortcode -> date)
#   4. Fallback: fetch public page (embed for IG, original URL for FB/Threads)
#      and parse date from og: meta / <time datetime> / taken_at_timestamp / JSON-LD
#
# Usage:
#   .\recover_dates.ps1 -Author zhao1945                       # auto-detect platform
#   .\recover_dates.ps1 -Platform ig -Author zhao1945          # both ig_main + ig_reels
#   .\recover_dates.ps1 -Platform ig_main -Author zhao1945
#   .\recover_dates.ps1 -Platform fb -Author someuser
#   .\recover_dates.ps1 -Author zhao1945 -NoFetch              # skip fetch, map only
#   .\recover_dates.ps1 -Author zhao1945 -MaxFetch 50          # cap fetch count
# ============================================================

param(
    [ValidateSet('auto','ig','ig_main','ig_reels','fb','threads')]
    [string]$Platform = 'auto',

    [Parameter(Mandatory=$true)]
    [string]$Author,

    [string]$Domain = '',

    [switch]$NoFetch,
    [int]$MaxFetch = 200,
    [int]$MinDelayMs = 1500,
    [int]$MaxDelayMs = 3000
)

$base = $PSScriptRoot

# Auto-detect domain if not specified
if (-not $Domain) {
    $allDomains = @(Get-ChildItem "$base\domains" -Directory -ErrorAction SilentlyContinue)
    if ($allDomains.Count -eq 1) {
        $Domain = $allDomains[0].Name
        Write-Host "Auto-detected domain: $Domain" -ForegroundColor DarkCyan
    } elseif ($allDomains.Count -eq 0) {
        Write-Host "ERROR: no domains found under $base\domains\" -ForegroundColor Red; exit 1
    } else {
        Write-Host "ERROR: multiple domains exist, use -Domain to specify" -ForegroundColor Red; exit 1
    }
}
$kolDir = "$base\domains\$Domain\kols\$Author"
$rawDir = "$kolDir\raw"
$canonicalDir = "$kolDir\canonical"
# IG / FB serve the rich OG-tag version (server-rendered, no JS shell) to Facebook's
# crawler UA. Without this UA we get a 800KB React bundle with no date info.
$UA = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"

# === HTML entity decoder (generic) ===
function Decode-HtmlEntities {
    param([string]$s)
    if (-not $s) { return '' }
    # Hex numeric entities &#xHHHH;
    $s = [regex]::Replace($s, '&#x([0-9a-fA-F]+);', {
        param($m)
        try { [char]::ConvertFromUtf32([Convert]::ToInt32($m.Groups[1].Value, 16)) }
        catch { $m.Value }
    })
    # Decimal numeric entities &#NNNN;
    $s = [regex]::Replace($s, '&#(\d+);', {
        param($m)
        try { [char]::ConvertFromUtf32([int]$m.Groups[1].Value) }
        catch { $m.Value }
    })
    # Named entities
    $s = $s -replace '&nbsp;', ' '
    $s = $s -replace '&amp;', '&'
    $s = $s -replace '&quot;', '"'
    $s = $s -replace '&apos;', "'"
    $s = $s -replace '&lt;', '<'
    $s = $s -replace '&gt;', '>'
    # Strip trailing ". " from og:description templates
    $s = $s -replace '"\.\s*$', ''
    return $s
}

# === URL shortcode extraction (per platform) ===
function Get-Shortcode {
    param([string]$Url, [string]$Platform)
    if (-not $Url) { return $null }
    if ($Platform -like 'ig*' -and $Url -match '/(p|reel)/([^/?]+)') {
        return $Matches[2]
    }
    if ($Platform -eq 'fb' -and $Url -match '(?:posts|videos|reel)/([^/?]+)') {
        return $Matches[1]
    }
    if ($Platform -eq 'threads' -and $Url -match '/post/([^/?]+)') {
        return $Matches[1]
    }
    return $null
}

# === URL normalization ===
function Normalize-Url {
    param([string]$Url, [string]$Platform)
    if (-not $Url) { return $Url }
    if ($Platform -like 'ig*') {
        # /<author>/p/X/  ->  /p/X/   (IG bookmarklet sometimes emits authored URLs)
        return $Url -replace '/[\w.]+/(p|reel)/', '/$1/'
    }
    return $Url
}

# === Build URL shortcode -> date map from canonical ===
function Build-DateMap {
    param([string]$CanonicalPath, [string]$Platform)
    $map = @{}
    if (-not (Test-Path $CanonicalPath)) { return $map }
    try {
        $existing = [System.IO.File]::ReadAllText($CanonicalPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($p in $existing) {
            if ($p.url -and $p.date) {
                $sc = Get-Shortcode -Url $p.url -Platform $Platform
                if ($sc -and -not $map.ContainsKey($sc)) { $map[$sc] = $p.date }
            }
        }
    } catch {
        Write-Host "  WARN: failed to parse canonical $CanonicalPath - $_" -ForegroundColor Yellow
    }
    return $map
}

# === Date extraction from HTML (multi-strategy) ===
function Parse-DateFromHtml {
    param([string]$Html)
    if (-not $Html) { return $null }

    # 1. og:title or og:description with "on Month Day, Year"
    if ($Html -match '<meta\s+property="og:(?:title|description)"\s+content="[^"]*?\bon\s+([A-Z][a-z]+\s+\d+,\s+\d{4})\b') {
        try {
            $d = [DateTime]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
            return $d.ToString('yyyy-MM-dd')
        } catch {}
    }

    # 2. <time datetime="2024-..."> (HTML5 + IG embed pages)
    if ($Html -match '<time[^>]*datetime="(\d{4}-\d{2}-\d{2})') {
        return $Matches[1]
    }

    # 3. taken_at_timestamp (IG GraphQL-style payload)
    if ($Html -match '"taken_at_timestamp"\s*:\s*(\d+)') {
        try {
            $ts = [int64]$Matches[1]
            $d = [DateTimeOffset]::FromUnixTimeSeconds($ts).UtcDateTime
            return $d.ToString('yyyy-MM-dd')
        } catch {}
    }

    # 4. JSON-LD datePublished / uploadDate
    if ($Html -match '"datePublished"\s*:\s*"(\d{4}-\d{2}-\d{2})') {
        return $Matches[1]
    }
    if ($Html -match '"uploadDate"\s*:\s*"(\d{4}-\d{2}-\d{2})') {
        return $Matches[1]
    }

    # 5. publish_time / created_time (FB-style)
    if ($Html -match '"publish_time"\s*:\s*(\d+)') {
        try {
            $ts = [int64]$Matches[1]
            $d = [DateTimeOffset]::FromUnixTimeSeconds($ts).UtcDateTime
            return $d.ToString('yyyy-MM-dd')
        } catch {}
    }

    return $null
}

# === Fetch a single URL and parse date ===
function Get-DateFromUrl {
    param([string]$Url, [string]$Platform)
    if (-not $Url) { return $null }

    # For IG with the FB crawler UA, the main URL serves the rich OG-tag page.
    # Embed page is kept as a fallback (sometimes useful if main returns the React shell).
    $fetchUrls = @()
    if ($Platform -like 'ig*' -and $Url -match '/(p|reel)/([^/?]+)') {
        $kind = $Matches[1]
        $sc = $Matches[2]
        $fetchUrls += "https://www.instagram.com/$kind/$sc/"
        $fetchUrls += "https://www.instagram.com/$kind/$sc/embed/captioned/"
    } else {
        $fetchUrls += $Url
    }

    foreach ($fu in $fetchUrls) {
        try {
            $resp = Invoke-WebRequest -Uri $fu -UseBasicParsing -TimeoutSec 15 -UserAgent $UA -ErrorAction Stop
            $date = Parse-DateFromHtml -Html $resp.Content
            if ($date) { return $date }
        } catch {
            # silent: try next URL or give up
        }
    }
    return $null
}

# === Resolve raw + canonical file paths per platform (domain-aware) ===
function Get-PlatformFiles {
    param([string]$Platform, [string]$Author)
    switch ($Platform) {
        'ig_main'  { return @{ Raw = @("$rawDir\instagram_main.json");  Canonical = "$canonicalDir\instagram.json" } }
        'ig_reels' { return @{ Raw = @("$rawDir\instagram_reels.json"); Canonical = "$canonicalDir\instagram.json" } }
        'ig'       { return @{ Raw = @("$rawDir\instagram_main.json", "$rawDir\instagram_reels.json"); Canonical = "$canonicalDir\instagram.json" } }
        'fb'       { return @{ Raw = @("$rawDir\facebook.json");        Canonical = "$canonicalDir\facebook.json" } }
        'threads'  { return @{ Raw = @("$rawDir\threads.json");         Canonical = "$canonicalDir\threads.json" } }
    }
}

# === Process one raw file in-place ===
function Process-RawFile {
    param(
        [string]$RawPath,
        [hashtable]$DateMap,
        [string]$Platform,
        [bool]$DoFetch,
        [int]$RemainingFetchBudget
    )

    $result = @{
        Total = 0
        Decoded = 0
        RecoveredMap = 0
        RecoveredFetch = 0
        StillMissing = 0
        FetchBudgetUsed = 0
        FetchAttempts = 0
    }

    if (-not (Test-Path $RawPath)) {
        Write-Host "  Skip (not found): $([System.IO.Path]::GetFileName($RawPath))" -ForegroundColor DarkGray
        return $result
    }

    Write-Host ""
    Write-Host "Processing: $([System.IO.Path]::GetFileName($RawPath))" -ForegroundColor Cyan
    $raw = [System.IO.File]::ReadAllText($RawPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $result.Total = $raw.Count
    Write-Host "  Entries: $($raw.Count)"

    $fixed = New-Object System.Collections.ArrayList
    $fetchBudget = $RemainingFetchBudget

    $i = 0
    foreach ($entry in $raw) {
        $i++

        # 1. Decode entities
        $oldContent = "$($entry.content)"
        $cleanContent = Decode-HtmlEntities $oldContent
        if ($cleanContent -ne $oldContent) { $result.Decoded++ }

        # 2. Normalize URL
        $cleanUrl = Normalize-Url -Url $entry.url -Platform $Platform

        # 3. Try existing date, then canonical map
        $date = "$($entry.date)"
        if (-not $date) {
            $sc = Get-Shortcode -Url $cleanUrl -Platform $Platform
            if ($sc -and $DateMap.ContainsKey($sc)) {
                $date = $DateMap[$sc]
                $result.RecoveredMap++
            }
        }

        # 4. Fallback: web fetch (budget-limited)
        if (-not $date -and $DoFetch -and $fetchBudget -gt 0) {
            $fetched = Get-DateFromUrl -Url $cleanUrl -Platform $Platform
            $result.FetchAttempts++
            $fetchBudget--
            if ($fetched) {
                $date = $fetched
                $result.RecoveredFetch++
            }
            # Random pause to avoid rate limit
            $delay = Get-Random -Minimum $MinDelayMs -Maximum ($MaxDelayMs + 1)
            Start-Sleep -Milliseconds $delay
            if ($result.FetchAttempts % 5 -eq 0) {
                Write-Host ("  fetch progress: tried={0}, hit={1}, budget_left={2}" -f $result.FetchAttempts, $result.RecoveredFetch, $fetchBudget) -ForegroundColor DarkGray
            }
        }

        if (-not $date) { $result.StillMissing++ }

        # 5. Type inference for IG when missing
        $type = "$($entry.type)"
        if (-not $type -and $Platform -like 'ig*') {
            if ($cleanUrl -match '/reel/') { $type = 'reel' }
            elseif ($cleanUrl -match '/p/') { $type = 'post' }
        }

        [void]$fixed.Add([PSCustomObject]@{
            author  = $entry.author
            date    = if ($date) { $date } else { '' }
            type    = $type
            url     = $cleanUrl
            content = $cleanContent
        })
    }

    # Sort by date desc (missing dates at the bottom)
    $sorted = $fixed | Sort-Object { if ($_.date) { [DateTime]::Parse($_.date) } else { [DateTime]::MinValue } } -Descending

    # Save (UTF-8 no BOM)
    $json = $sorted | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($RawPath, $json, [System.Text.UTF8Encoding]::new($false))

    $result.FetchBudgetUsed = $RemainingFetchBudget - $fetchBudget

    Write-Host ("  Decoded: {0}  Map: {1}  Fetch: {2}/{3}  Still missing: {4}" -f `
        $result.Decoded, $result.RecoveredMap, $result.RecoveredFetch, $result.FetchAttempts, $result.StillMissing) `
        -ForegroundColor Green

    return $result
}

# ============================================================
# Main
# ============================================================

# Auto-detect platform from most recently modified raw file
if ($Platform -eq 'auto') {
    $candidates = @(
        @{ Path = "$rawDir\instagram_main.json";  Plat = 'ig_main' }
        @{ Path = "$rawDir\instagram_reels.json"; Plat = 'ig_reels' }
        @{ Path = "$rawDir\facebook.json";        Plat = 'fb' }
        @{ Path = "$rawDir\threads.json";         Plat = 'threads' }
    )
    $newest = $null
    foreach ($c in $candidates) {
        if (Test-Path $c.Path) {
            $info = Get-Item $c.Path
            if (-not $newest -or $info.LastWriteTime -gt $newest.LastWriteTime) {
                $newest = @{ LastWriteTime = $info.LastWriteTime; Plat = $c.Plat }
            }
        }
    }
    if ($newest) {
        $Platform = $newest.Plat
        Write-Host "Auto-detected platform: $Platform (most recent raw file)" -ForegroundColor Cyan
    } else {
        Write-Host "ERROR: no raw files found for author '$Author'" -ForegroundColor Red
        exit 1
    }
}

$files = Get-PlatformFiles -Platform $Platform -Author $Author
Write-Host "Author:    $Author"
Write-Host "Platform:  $Platform"
Write-Host "Canonical: $($files.Canonical)"
Write-Host "Fetch:     $(if ($NoFetch) { 'OFF (NoFetch flag)' } else { "ON (max=$MaxFetch, delay=${MinDelayMs}-${MaxDelayMs}ms)" })"

$dateMap = Build-DateMap -CanonicalPath $files.Canonical -Platform $Platform
Write-Host "Loaded $($dateMap.Count) URL->date mappings from canonical" -ForegroundColor Gray

$grand = @{
    Total = 0; Decoded = 0; RecoveredMap = 0
    RecoveredFetch = 0; StillMissing = 0
    FetchBudgetUsed = 0; FetchAttempts = 0
}
$remainingBudget = $MaxFetch
foreach ($rawPath in $files.Raw) {
    $r = Process-RawFile -RawPath $rawPath -DateMap $dateMap -Platform $Platform `
                         -DoFetch (-not $NoFetch.IsPresent) -RemainingFetchBudget $remainingBudget
    $grand.Total           += $r.Total
    $grand.Decoded         += $r.Decoded
    $grand.RecoveredMap    += $r.RecoveredMap
    $grand.RecoveredFetch  += $r.RecoveredFetch
    $grand.StillMissing    += $r.StillMissing
    $grand.FetchBudgetUsed += $r.FetchBudgetUsed
    $grand.FetchAttempts   += $r.FetchAttempts
    $remainingBudget       -= $r.FetchBudgetUsed
}

Write-Host ""
Write-Host "===== Summary =====" -ForegroundColor Cyan
Write-Host ("  Entries processed:  {0}" -f $grand.Total)
Write-Host ("  Entity-decoded:     {0}" -f $grand.Decoded)
Write-Host ("  Date from canonical:{0}" -f $grand.RecoveredMap)
Write-Host ("  Date from fetch:    {0} / {1} attempts" -f $grand.RecoveredFetch, $grand.FetchAttempts)
Write-Host ("  Still missing date: {0}" -f $grand.StillMissing)
Write-Host ("  Fetch budget used:  {0} / {1}" -f $grand.FetchBudgetUsed, $MaxFetch)
