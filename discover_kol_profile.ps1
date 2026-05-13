# ============================================================
# StockHero - KOL Profile Auto-Discovery
# ============================================================
# Reads a KOL's canonical posts and proposes a content profile:
#   - Characteristic terms (TF-IDF-ish ranking of Chinese n-grams)
#   - Era / transition candidates (split by date, find keyword shifts)
#   - Existing built-in pattern hit rates (philosophy / anti-scam)
#   - Suggested domain label
#
# Output:
#   Console summary (for chat-based review)
#   kol_profile_<author>.json (consumed by analyze_platforms.ps1 -ProfilePath ...)
#
# Usage:
#   .\discover_kol_profile.ps1 -Author zhao1945
#   .\discover_kol_profile.ps1 -Author newkol -Source instagram
#
# Pipeline position:
#   scrape -> save_clipboard -> recover_dates -> merge
#       -> discover_kol_profile  <- THIS, generates draft profile
#       -> user reviews / edits kol_profile_<author>.json
#       -> analyze_platforms -ProfilePath <draft>
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Author,

    [string]$Domain = '',

    [ValidateSet('all','instagram','threads','facebook')]
    [string]$Source = 'all',

    [int]$TopKeywords = 30,
    [int]$MinDocFreq = 5,
    [int]$MaxDocFreqPct = 60,

    [switch]$Force
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
$canonicalDir = "$kolDir\canonical"

# Chinese common-particle stopwords (not domain-specific)
$Stopwords = @(
    '一個','可以','就是','然後','但是','不是','這個','那個','還是','因為','所以',
    '我們','你們','他們','真的','沒有','比較','而且','應該','已經','現在','雖然',
    '還有','一些','知道','看到','自己','大家','開始','覺得','結果','其實','可是',
    '或者','或是','只是','至少','或許','看起來','到底','時候','一直','永遠','當然',
    '當下','當作','本來','重要','繼續','需要','一定','可能','一樣','有些','某些',
    '許多','不會','不能','問題','時間','東西','地方','感覺','想法','方式','方法',
    '部分','其中','另外','例如','尤其','其他','一般','一樣','一直','一起'
)
$StopSet = @{}; foreach ($w in $Stopwords) { $StopSet[$w] = $true }

# === Load posts from canonical(s) ===
$sources = @()
if ($Source -in 'all','instagram') { $sources += "$canonicalDir\instagram.json" }
if ($Source -in 'all','threads')   { $sources += "$canonicalDir\threads.json" }
if ($Source -in 'all','facebook')  { $sources += "$canonicalDir\facebook.json" }

$allPosts = New-Object System.Collections.ArrayList
$perSource = @{}
foreach ($src in $sources) {
    if (-not (Test-Path $src)) { continue }
    $posts = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $perSource[[System.IO.Path]::GetFileNameWithoutExtension($src)] = $posts.Count
    foreach ($p in $posts) { [void]$allPosts.Add($p) }
}

if ($allPosts.Count -eq 0) {
    Write-Host "ERROR: no canonical files found for '$Author'" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "===== Source =====" -ForegroundColor Cyan
foreach ($k in $perSource.Keys) { Write-Host "  $k : $($perSource[$k]) posts" }
Write-Host "  Total: $($allPosts.Count) posts" -ForegroundColor Yellow

# === N-gram extraction (Chinese 2-4 chars only) ===
function Get-TermStats($posts, $stopSet) {
    $chineseRe = [regex]'[一-鿿]+'
    $tf = @{}; $df = @{}
    foreach ($p in $posts) {
        $content = if ($p.content) { [string]$p.content } else { '' }
        if (-not $content) { continue }
        $postTerms = @{}
        foreach ($m in $chineseRe.Matches($content)) {
            $text = $m.Value
            $L = $text.Length
            foreach ($n in 2..5) {
                if ($L -lt $n) { continue }
                $maxStart = $L - $n
                for ($i = 0; $i -le $maxStart; $i++) {
                    $ng = $text.Substring($i, $n)
                    if ($stopSet[$ng]) { continue }
                    # Skip if all chars identical (avoid "啊啊", "嗯嗯嗯")
                    $allSame = $true
                    for ($j = 1; $j -lt $n; $j++) { if ($ng[$j] -ne $ng[0]) { $allSame = $false; break } }
                    if ($allSame) { continue }
                    if (-not $tf.ContainsKey($ng)) { $tf[$ng] = 0 }
                    $tf[$ng]++
                    $postTerms[$ng] = $true
                }
            }
        }
        foreach ($t in $postTerms.Keys) {
            if (-not $df.ContainsKey($t)) { $df[$t] = 0 }
            $df[$t]++
        }
    }
    return @{ TF = $tf; DF = $df; Count = $posts.Count }
}

Write-Host ""
Write-Host "Extracting n-grams..." -ForegroundColor Gray
$stats = Get-TermStats $allPosts $StopSet
$N = $stats.Count
$maxDF = [int]($N * $MaxDocFreqPct / 100.0)
Write-Host "  Unique n-grams: $($stats.TF.Count); DF range kept: [$MinDocFreq, $maxDF]" -ForegroundColor Gray

# === Score and filter ===
# Heuristic: prefer terms with high TF, moderate DF (concentrated mentions, not stopwords).
$candidates = New-Object System.Collections.ArrayList
foreach ($t in $stats.TF.Keys) {
    $d = $stats.DF[$t]
    if ($d -lt $MinDocFreq -or $d -gt $maxDF) { continue }
    $tfv = $stats.TF[$t]
    # Score: TF * log(N/DF) — classic TF-IDF (smoothed)
    $score = $tfv * [Math]::Log(1.0 + $N / $d)
    # Penalty for short n-grams (2-chars often noisy)
    if ($t.Length -eq 2) { $score *= 0.7 }
    [void]$candidates.Add([PSCustomObject]@{
        term=$t; tf=$tfv; df=$d; score=$score; n=$t.Length
    })
}

# Remove n-grams that are substrings of higher-ranked n-grams.
# (e.g., if "台積電" is top, drop "台積" and "積電")
$sortedAll = @($candidates | Sort-Object score -Descending)
$kept = New-Object System.Collections.ArrayList
$keptSet = @{}
foreach ($c in $sortedAll) {
    $shadowed = $false
    foreach ($winnerTerm in $keptSet.Keys) {
        if ($winnerTerm.Length -gt $c.term.Length -and $winnerTerm.Contains($c.term)) {
            # Only shadow if score is dominated (winner term has at least 70% of c.tf)
            if ($keptSet[$winnerTerm] -ge $c.tf * 0.7) { $shadowed = $true; break }
        }
    }
    if (-not $shadowed) {
        [void]$kept.Add($c)
        $keptSet[$c.term] = $c.tf
    }
    if ($kept.Count -ge ($TopKeywords * 3)) { break }
}

$topByScore = $kept | Select-Object -First $TopKeywords

Write-Host ""
Write-Host "===== Top $TopKeywords characteristic terms =====" -ForegroundColor Cyan
$topByScore | Format-Table @{n='term';e={$_.term}}, @{n='tf';e={$_.tf}}, @{n='df';e={$_.df}}, @{n='score';e={[math]::Round($_.score,1)}}

# === Era detection (split by date) ===
# Accept only ISO-style yyyy-MM-dd dates; skip relative/garbled strings
$isoDateRe = [regex]'^\d{4}-\d{2}-\d{2}$'
$datedPosts = @($allPosts | Where-Object { $_.date -and $isoDateRe.IsMatch($_.date) } | Sort-Object { [DateTime]::Parse($_.date) })
$transitionTerms = @{}
$earlyTopTerms = @()
$lateTopTerms = @()
if ($datedPosts.Count -ge 50) {
    $half = [int]($datedPosts.Count / 2)
    $early = $datedPosts[0..($half-1)]
    $late = $datedPosts[$half..($datedPosts.Count-1)]
    $earlyStats = Get-TermStats $early $StopSet
    $lateStats = Get-TermStats $late $StopSet

    $earlyMid = $early[0].date
    $earlyEnd = $early[-1].date
    $lateStart = $late[0].date
    $lateEnd = $late[-1].date

    Write-Host ""
    Write-Host "===== Era split =====" -ForegroundColor Cyan
    Write-Host "  Early half: $($early.Count) posts, $earlyMid ~ $earlyEnd"
    Write-Host "  Late  half: $($late.Count)  posts, $lateStart ~ $lateEnd"

    $allTerms = @{}
    foreach ($t in $earlyStats.TF.Keys) { $allTerms[$t] = $true }
    foreach ($t in $lateStats.TF.Keys)  { $allTerms[$t] = $true }

    $shifts = New-Object System.Collections.ArrayList
    foreach ($t in $allTerms.Keys) {
        if ($t.Length -eq 2) { continue }  # skip 2-grams here, too noisy
        $eDF = if ($earlyStats.DF[$t]) { $earlyStats.DF[$t] } else { 0 }
        $lDF = if ($lateStats.DF[$t])  { $lateStats.DF[$t]  } else { 0 }
        if (($eDF + $lDF) -lt 5) { continue }
        $eRate = $eDF / $earlyStats.Count
        $lRate = $lDF / $lateStats.Count
        $diff = $lRate - $eRate
        [void]$shifts.Add([PSCustomObject]@{
            term=$t; early_df=$eDF; late_df=$lDF; diff=$diff
        })
    }
    $emerging = @($shifts | Sort-Object diff -Descending | Select-Object -First 12)
    $declining = @($shifts | Sort-Object diff | Select-Object -First 12)

    Write-Host ""
    Write-Host "  Emerging (more common in late):" -ForegroundColor Green
    $emerging | Format-Table term, early_df, late_df, @{n='diff';e={[math]::Round($_.diff,3)}}
    Write-Host "  Declining (more common in early):" -ForegroundColor Yellow
    $declining | Format-Table term, early_df, late_df, @{n='diff';e={[math]::Round($_.diff,3)}}

    $earlyTopTerms = @($declining | Select-Object -First 8 | ForEach-Object { $_.term })
    $lateTopTerms = @($emerging | Select-Object -First 8 | ForEach-Object { $_.term })
} else {
    Write-Host ""
    Write-Host "Skipping era split (too few dated posts: $($datedPosts.Count) < 50)" -ForegroundColor Yellow
}

# === Existing built-in pattern hit-rate ===
$builtinPhilKws = @('震盪','邏輯','紀律','情緒','人性','貪婪','恐懼','紅燈不過','止損')
$builtinAntiScam = @('冒','不主動私訊','詐騙')
$philHits = 0; $antiHits = 0
foreach ($p in $allPosts) {
    $c = if ($p.content) { [string]$p.content } else { '' }
    foreach ($k in $builtinPhilKws) { if ($c -like "*$k*") { $philHits++; break } }
    foreach ($k in $builtinAntiScam) { if ($c -like "*$k*") { $antiHits++; break } }
}
$philRate = if ($N -gt 0) { [math]::Round(100 * $philHits / $N, 1) } else { 0 }
$antiRate = if ($N -gt 0) { [math]::Round(100 * $antiHits / $N, 1) } else { 0 }

Write-Host ""
Write-Host "===== Built-in pattern fit =====" -ForegroundColor Cyan
Write-Host "  Philosophy keywords:    $philHits / $N ($philRate%)"
Write-Host "  Anti-scam patterns:     $antiHits / $N ($antiRate%)"

# Domain hint
$financialHits = 0
$financialMarkers = @('股','台積','聯準','降息','升息','加權','美股','台股','投資','大盤','財報','法說','EPS')
foreach ($p in $allPosts) {
    $c = if ($p.content) { [string]$p.content } else { '' }
    foreach ($k in $financialMarkers) { if ($c -like "*$k*") { $financialHits++; break } }
}
$financialRate = if ($N -gt 0) { [math]::Round(100 * $financialHits / $N, 1) } else { 0 }

$domainGuess = if ($financialRate -ge 40) { 'financial_kol' } else { 'general' }
Write-Host "  Financial markers:      $financialHits / $N ($financialRate%) -> domain: $domainGuess" -ForegroundColor Yellow

# === Build draft profile ===
# Note: use $kolProfile (not $profile) — $profile is a PowerShell automatic variable.
$kolProfile = [ordered]@{
    author          = $Author
    generated_at    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    persona         = $Author   # USER: edit this if KOL has a public persona name
    domain          = $domainGuess
    total_posts     = $allPosts.Count
    discovered_terms = @($topByScore | ForEach-Object { $_.term })
    eras            = if ($earlyTopTerms.Count -gt 0 -and $lateTopTerms.Count -gt 0) {
        [ordered]@{
            '前期' = $earlyTopTerms
            '後期' = $lateTopTerms
        }
    } else { $null }
    philosophy_keywords = if ($philRate -ge 5) { $builtinPhilKws } else { @() }
    anti_scam_patterns  = if ($antiRate -ge 1) { $builtinAntiScam } else { @() }
    builtin_fit = [ordered]@{
        philosophy_hit_pct = $philRate
        anti_scam_hit_pct  = $antiRate
        financial_marker_pct = $financialRate
    }
    review_notes = @(
        "請檢視 'discovered_terms' 中是否有破詞或無意義片段，刪除無用項",
        "請檢視 'eras' 兩個列表是否符合此 KOL 真實轉型軌跡，可改名 / 增減 keywords",
        "若此 KOL 非財經類，請清空 'philosophy_keywords' 和 'anti_scam_patterns'",
        "'persona' 預設為 author name，可改成公開暱稱（如 '股市兆英雄'）"
    )
}

$activePath = "$kolDir\kol_profile.json"
$draftPath  = "$kolDir\kol_profile_draft.json"

# Save-target decision:
#   - active does not exist        -> save as active (first time onboarding)
#   - active exists and -Force     -> overwrite active (user explicitly opted in)
#   - active exists, no -Force     -> save as _draft.json (safety: never clobber edits)
$activeExists = Test-Path $activePath
if ($activeExists -and -not $Force) {
    $profilePath = $draftPath
    $savedAs = 'draft'
} else {
    $profilePath = $activePath
    $savedAs = if ($activeExists) { 'active (overwritten via -Force)' } else { 'active (first run)' }
}

$json = $kolProfile | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($profilePath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "===== Draft profile saved =====" -ForegroundColor Green
Write-Host "  -> $profilePath" -ForegroundColor Cyan
Write-Host "  mode: $savedAs"

if ($savedAs -eq 'draft') {
    Write-Host ""
    Write-Host "WARN: active profile already exists, wrote draft instead." -ForegroundColor Yellow
    Write-Host "      Existing active : $activePath"
    Write-Host "      New draft       : $draftPath"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1) Diff/merge the new draft into your active profile manually, OR"
    Write-Host "  2) Re-run with -Force to overwrite active (loses prior edits!)"
} else {
    Write-Host ""
    Write-Host "NEXT STEP:" -ForegroundColor Yellow
    Write-Host "  1) Review the file, edit persona / eras / keywords if needed"
    Write-Host "  2) Run: .\analyze_platforms.ps1 -Author $Author"
}
