# ============================================================
# StockHero - Per-KOL Database Builder
# ============================================================
# Reads one KOL's canonical files, computes deep analytics,
# writes structured Database (per-KOL, completely independent).
#
# Input:
#   domains/<domain>/domain.json                              — shared themes
#   domains/<domain>/kols/<author>/kol_profile.json
#   domains/<domain>/kols/<author>/canonical/{ig,threads,fb}.json
#
# Output:
#   domains/<domain>/kols/<author>/database/kol_db.json       — top-level summary
#   domains/<domain>/kols/<author>/database/threads_metrics.json
#   domains/<domain>/kols/<author>/database/instagram_metrics.json
#   domains/<domain>/kols/<author>/database/facebook_metrics.json
#
# Usage:
#   .\build_kol_db.ps1 -Domain tw_stock_kol -Author zhao1945
# ============================================================

param(
    [Parameter(Mandatory=$true)] [string]$Domain,
    [Parameter(Mandatory=$true)] [string]$Author
)

$base = $PSScriptRoot
$domainDir = "$base\domains\$Domain"
$kolDir    = "$domainDir\kols\$Author"
$dbDir     = "$kolDir\database"
$ErrorActionPreference = 'Stop'

if (-not (Test-Path "$domainDir\domain.json")) { Write-Host "ERROR: domain.json not found" -ForegroundColor Red; exit 1 }
if (-not (Test-Path "$kolDir\kol_profile.json")) { Write-Host "ERROR: kol_profile.json not found for $Author" -ForegroundColor Red; exit 1 }
New-Item -ItemType Directory -Path $dbDir -Force | Out-Null

$domainCfg = [System.IO.File]::ReadAllText("$domainDir\domain.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$kolCfg    = [System.IO.File]::ReadAllText("$kolDir\kol_profile.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$themes = $domainCfg.domain_themes
$themeKeys = @($themes.PSObject.Properties.Name)

Write-Host ""
Write-Host "===== Building KOL Database =====" -ForegroundColor Cyan
Write-Host "Domain : $($domainCfg.domain_id)"
Write-Host "Author : $Author ($($kolCfg.persona))"

# ────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────
function Resolve-Date($s) {
    if (-not $s) { return $null }
    # Accept yyyy-M-d / yyyy-MM-dd / yyyy-MM-d / yyyy-M-dd
    if ($s -match '^(\d{4})-(\d{1,2})-(\d{1,2})') {
        $y = $matches[1]; $mo = $matches[2].PadLeft(2,'0'); $da = $matches[3].PadLeft(2,'0')
        try { return [DateTime]::ParseExact("$y-$mo-$da", 'yyyy-MM-dd', $null) } catch { return $null }
    }
    return $null
}

function Get-Label($value, $thresholds, $labels) {
    for ($i = 0; $i -lt $thresholds.Count; $i++) {
        if ($value -lt $thresholds[$i]) { return $labels[$i] }
    }
    return $labels[$labels.Count - 1]
}

# ────────────────────────────────────────────────────────────
# Investment-lens analysis: 五大分析面向 + 常用指標 + 個股提及
# ────────────────────────────────────────────────────────────
$script:InvestmentLens = [ordered]@{
    '基本面' = @('營收','毛利','毛利率','淨利','淨利率','EPS','每股盈餘','本益比','PE','PER','ROE','ROA','PB','殖利率','配息','股息','法說會','法說','財報','季報','月營收','自結','訂單','接單','出貨','庫存','產能','擴產','資本支出','財測','展望','上修','下修','獲利','虧損','轉盈','轉虧')
    '籌碼面' = @('外資','投信','自營商','三大法人','法人','買超','賣超','連買','連賣','大買','大賣','融資','融券','融資維持率','券資比','融資餘額','融券餘額','大戶','大股東','千張','庫藏股','庫藏','回購','集保','籌碼集中','籌碼凌亂','籌碼面','主力','散戶','分點','實戶')
    '技術面' = @('K線','均線','5日線','10日線','20日線','月線','季線','半年線','年線','MACD','KD','RSI','布林','葛蘭碧','BBI','OBV','支撐','壓力','突破','跌破','站上','摜破','量價','成交量','量縮','量增','爆量','價量','黃金交叉','死亡交叉','多頭排列','空頭排列','W底','M頭','頭肩','三角整理','旗形','背離','缺口')
    '消息面' = @('Fed','FOMC','聯準會','鮑威爾','鮑爾','升息','降息','利率','寬鬆','緊縮','QE','縮表','CPI','PCE','通膨','通縮','GDP','非農','失業率','ISM','中東','戰爭','衝突','川普','川習會','拜登','關稅','貿易戰','兩岸','台海','油價','原油','黃金','金價','銅價','大宗物資','美元','美元指數','DXY','台幣','匯率','日圓','人民幣','地緣政治','制裁')
    '心理面' = @('紀律','心法','邏輯','情緒','貪婪','恐懼','人性','FOMO','止損','停損','停利','加碼','減碼','攤平','攤低','套牢','不追高','不殺低','追高殺低','風險','部位','控管','資金管理','資金水位','持股比例','心態','冷靜','耐心','等待','觀望','逢低','逢高','分批')
}

$script:StockMentions = @(
    # ── Taiwan Large Cap ──
    @{ name='台積電'; aliases=@('台積電','TSMC','2330','台積','TSM') }
    @{ name='聯發科'; aliases=@('聯發科','MediaTek','2454') }
    @{ name='鴻海';   aliases=@('鴻海','2317','Foxconn') }
    @{ name='聯電';   aliases=@('聯電','2303','UMC') }
    @{ name='台達電'; aliases=@('台達電','2308') }
    @{ name='大立光'; aliases=@('大立光','3008') }
    @{ name='南亞科'; aliases=@('南亞科','2408') }
    @{ name='華邦電'; aliases=@('華邦電','2344') }
    @{ name='群創';   aliases=@('群創','3481') }
    @{ name='友達';   aliases=@('友達','2409') }
    @{ name='廣達';   aliases=@('廣達','2382') }
    @{ name='緯創';   aliases=@('緯創','3231') }
    @{ name='仁寶';   aliases=@('仁寶','2324') }
    @{ name='富邦金'; aliases=@('富邦金','2881') }
    @{ name='國泰金'; aliases=@('國泰金','2882') }
    @{ name='中華電'; aliases=@('中華電','2412') }
    @{ name='台塑';   aliases=@('台塑','1301') }
    @{ name='中鋼';   aliases=@('中鋼','2002') }
    @{ name='統一';   aliases=@('統一企業','1216') }
    @{ name='欣興';   aliases=@('欣興','3037') }
    @{ name='金像電'; aliases=@('金像電','2368') }
    @{ name='奇鋐';   aliases=@('奇鋐','3017') }
    @{ name='健策';   aliases=@('健策','3653') }
    @{ name='雙鴻';   aliases=@('雙鴻','3324') }
    @{ name='華城';   aliases=@('華城','1519') }
    @{ name='中興電'; aliases=@('中興電','1513') }
    @{ name='智邦';   aliases=@('智邦','2345') }
    @{ name='川湖';   aliases=@('川湖','2059') }
    @{ name='世芯';   aliases=@('世芯','3661') }
    @{ name='創意';   aliases=@('創意電子','3443') }
    # ── US Tech ──
    @{ name='NVIDIA'; aliases=@('NVIDIA','NVDA','輝達','英偉達') }
    @{ name='AMD';    aliases=@('AMD','超微') }
    @{ name='Intel';  aliases=@('Intel','INTC','英特爾') }
    @{ name='Apple';  aliases=@('Apple','AAPL','蘋果') }
    @{ name='Microsoft'; aliases=@('Microsoft','MSFT','微軟') }
    @{ name='Google'; aliases=@('Google','GOOGL','GOOG','Alphabet') }
    @{ name='Tesla';  aliases=@('Tesla','TSLA','特斯拉') }
    @{ name='Meta';   aliases=@('Meta','META','臉書','Facebook股價') }
    @{ name='Amazon'; aliases=@('Amazon','AMZN','亞馬遜') }
    @{ name='Broadcom'; aliases=@('Broadcom','AVGO','博通') }
    @{ name='Qualcomm'; aliases=@('Qualcomm','QCOM','高通') }
    @{ name='Micron'; aliases=@('Micron','MU','美光') }
    @{ name='ASML';   aliases=@('ASML','艾斯摩爾') }
    @{ name='ARM';    aliases=@('ARM Holdings','安謀') }
    @{ name='Netflix';aliases=@('Netflix','NFLX') }
    @{ name='Palantir';aliases=@('Palantir','PLTR') }
    # ── ETFs (Taiwan) ──
    @{ name='0050';   aliases=@('0050','元大台灣50') }
    @{ name='0056';   aliases=@('0056','元大高股息') }
    @{ name='00878';  aliases=@('00878','國泰永續高股息') }
    @{ name='00900';  aliases=@('00900','富邦特選高股息30') }
    @{ name='00919';  aliases=@('00919','群益台灣精選高息') }
    @{ name='00936';  aliases=@('00936','台新永續高息中小') }
    @{ name='00929';  aliases=@('00929','復華台灣科技優息') }
    @{ name='00940';  aliases=@('00940','元大臺灣價值高息') }
    # ── ETFs (US) ──
    @{ name='QQQ';    aliases=@('QQQ','那斯達克100','Nasdaq 100') }
    @{ name='SPY';    aliases=@('SPY','S&P 500 ETF') }
    @{ name='VOO';    aliases=@('VOO') }
    @{ name='VTI';    aliases=@('VTI') }
    @{ name='DIA';    aliases=@('DIA','道瓊ETF') }
    @{ name='IWM';    aliases=@('IWM','羅素2000') }
    @{ name='ARKK';   aliases=@('ARKK','方舟') }
    @{ name='SMH';    aliases=@('SMH','半導體ETF') }
    @{ name='SOXL';   aliases=@('SOXL','三倍半導體') }
    @{ name='TQQQ';   aliases=@('TQQQ','三倍那斯達克') }
)

function Test-AliasMatch($content, $alias) {
    # Word-boundary regex for short pure-ASCII aliases (≤ 5 chars) to avoid
    # false positives like "PE" hitting "Apple" or "DIA" hitting "NVIDIA".
    # Longer aliases and any string with non-ASCII (Chinese) use literal -like.
    $isShortAscii = ($alias.Length -le 5) -and ($alias -match '^[A-Za-z0-9&]+$')
    if ($isShortAscii) {
        $pattern = '(?<![A-Za-z0-9])' + [regex]::Escape($alias) + '(?![A-Za-z0-9])'
        return [regex]::IsMatch($content, $pattern, 'IgnoreCase')
    }
    return ($content -like "*$alias*")
}

function Compute-InvestmentLens($posts, $lensCategories, $stockList) {
    $catPostCount = [ordered]@{}
    foreach ($cat in $lensCategories.Keys) { $catPostCount[$cat] = 0 }
    $indicatorCounts = @{}
    $stockCounts = @{}
    $totalPosts = $posts.Count

    foreach ($p in $posts) {
        $c = if ($p.content) { [string]$p.content } else { '' }
        if (-not $c) { continue }

        # Per-category: count posts that contain ANY keyword in that category
        foreach ($cat in $lensCategories.Keys) {
            $hit = $false
            foreach ($kw in $lensCategories[$cat]) {
                if (Test-AliasMatch $c $kw) {
                    $hit = $true
                    if (-not $indicatorCounts.ContainsKey($kw)) { $indicatorCounts[$kw] = 0 }
                    $indicatorCounts[$kw]++
                }
            }
            if ($hit) { $catPostCount[$cat]++ }
        }

        # Per-stock: count posts mentioning each stock (any alias)
        foreach ($s in $stockList) {
            foreach ($alias in $s.aliases) {
                if (Test-AliasMatch $c $alias) {
                    if (-not $stockCounts.ContainsKey($s.name)) { $stockCounts[$s.name] = 0 }
                    $stockCounts[$s.name]++
                    break
                }
            }
        }
    }

    # Category shares (posts that mention each category / total posts)
    $catShares = [ordered]@{}
    foreach ($cat in $catPostCount.Keys) {
        $catShares[$cat] = if ($totalPosts -gt 0) { [math]::Round($catPostCount[$cat] / $totalPosts, 3) } else { 0 }
    }

    # Top indicators (across all 5 categories)
    $topInd = @($indicatorCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object {
        [PSCustomObject]@{ indicator = $_.Key; count = $_.Value }
    })

    # Top stocks
    $topStocks = @($stockCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 | ForEach-Object {
        [PSCustomObject]@{ stock = $_.Key; count = $_.Value }
    })

    # Dominant lens label
    $catSorted = @($catPostCount.GetEnumerator() | Sort-Object Value -Descending)
    $dominant = if ($catSorted.Count -gt 0) { $catSorted[0].Name } else { $null }
    $secondary = if ($catSorted.Count -gt 1) { $catSorted[1].Name } else { $null }
    $top1Count = if ($catSorted.Count -gt 0) { $catSorted[0].Value } else { 0 }
    $top2Count = if ($catSorted.Count -gt 1) { $catSorted[1].Value } else { 0 }

    $lensLabel = if ($top1Count -eq 0) { '無顯著傾向' }
                 elseif ($top2Count / [math]::Max(1, $top1Count) -lt 0.5) { "$dominant 型" }
                 elseif ($top2Count / [math]::Max(1, $top1Count) -lt 0.8) { "$dominant 主、$secondary 輔" }
                 else { "$dominant + $secondary 混合型" }

    return [ordered]@{
        category_post_count = $catPostCount
        category_post_share = $catShares
        top_indicators = $topInd
        top_stocks = $topStocks
        dominant_lens = $dominant
        secondary_lens = $secondary
        lens_label = $lensLabel
        total_indicator_mentions = ($indicatorCounts.Values | Measure-Object -Sum).Sum
        unique_indicators = $indicatorCounts.Count
        unique_stocks = $stockCounts.Count
    }
}

# ────────────────────────────────────────────────────────────
# Per-platform deep aggregation
# ────────────────────────────────────────────────────────────
function Build-Metrics($platform, $posts, $kolCfg, $themesObj, $themeKeys, $domainCfg) {
    $persona = if ($kolCfg.persona) { $kolCfg.persona } else { $kolCfg.author }
    $allPosts = New-Object System.Collections.ArrayList
    foreach ($p in $posts) {
        $c = if ($p.content) { [string]$p.content } else { '' }
        $d = Resolve-Date $p.date
        [void]$allPosts.Add([PSCustomObject]@{ content=$c; date=$d; date_raw=$p.date; type=$p.type; url=$p.url })
    }

    $total = $allPosts.Count
    if ($total -eq 0) {
        return [ordered]@{ platform=$platform; posts_total=0; note='no_data' }
    }

    $totalChars = ($allPosts | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum
    $avgChars = [int]($totalChars / $total)
    $datedPosts = @($allPosts | Where-Object { $_.date })
    $firstDate = if ($datedPosts.Count) { ($datedPosts | Sort-Object date | Select-Object -First 1).date } else { $null }
    $lastDate  = if ($datedPosts.Count) { ($datedPosts | Sort-Object date -Descending | Select-Object -First 1).date } else { $null }
    $monthsSpan = if ($firstDate -and $lastDate) { [math]::Round(($lastDate - $firstDate).Days / 30.0, 1) } else { 0 }

    # ── Monthly distribution ──
    $monthDist = [ordered]@{}
    foreach ($p in $datedPosts) {
        $k = $p.date.ToString('yyyy-MM')
        if (-not $monthDist.Contains($k)) { $monthDist[$k] = 0 }
        $monthDist[$k]++
    }
    $monthKeys = @($monthDist.Keys | Sort-Object)
    $sortedMonths = [ordered]@{}
    foreach ($k in $monthKeys) { $sortedMonths[$k] = $monthDist[$k] }

    $activeMonths = $monthKeys.Count
    $expectedMonths = [math]::Max(1, [int][math]::Ceiling($monthsSpan))
    $activeMonthRatio = if ($expectedMonths -gt 0) { [math]::Round($activeMonths / $expectedMonths, 3) } else { 0 }

    # Max dormant gap (months without posts between first and last)
    $maxDormantGap = 0
    if ($monthKeys.Count -gt 1) {
        for ($i = 1; $i -lt $monthKeys.Count; $i++) {
            $a = [DateTime]::ParseExact($monthKeys[$i-1], 'yyyy-MM', $null)
            $b = [DateTime]::ParseExact($monthKeys[$i], 'yyyy-MM', $null)
            $gap = (($b.Year - $a.Year) * 12) + ($b.Month - $a.Month) - 1
            if ($gap -gt $maxDormantGap) { $maxDormantGap = $gap }
        }
    }

    $peakMonth = $monthKeys | ForEach-Object { [PSCustomObject]@{m=$_; n=$monthDist[$_]} } | Sort-Object n -Descending | Select-Object -First 1
    $avgPostsPerMonth = if ($activeMonths -gt 0) { [math]::Round($total / $activeMonths, 1) } else { 0 }

    # ── Recent vs history trend ──
    $trend = $null
    if ($monthKeys.Count -ge 6) {
        $recent = $monthKeys[-3..-1] | ForEach-Object { $monthDist[$_] }
        $rest   = $monthKeys[0..($monthKeys.Count - 4)] | ForEach-Object { $monthDist[$_] }
        $recentAvg = ($recent | Measure-Object -Average).Average
        $restAvg = ($rest | Measure-Object -Average).Average
        if ($restAvg -gt 0) {
            $deltaPct = [math]::Round(($recentAvg - $restAvg) / $restAvg * 100, 1)
            $trend = @{
                recent_3mo_avg = [math]::Round($recentAvg, 1)
                history_avg = [math]::Round($restAvg, 1)
                delta_pct = $deltaPct
                direction = if ($deltaPct -ge 30) { '明顯加溫' } elseif ($deltaPct -ge 10) { '溫和成長' } elseif ($deltaPct -le -30) { '明顯降溫' } elseif ($deltaPct -le -10) { '溫和衰退' } else { '持平' }
            }
        }
    }

    # ── Posting cadence label ──
    $cadenceLabel = if ($activeMonthRatio -ge 0.85 -and $maxDormantGap -le 1) { '穩定型' }
                    elseif ($maxDormantGap -ge 6) { '中斷後復活型' }
                    elseif ($peakMonth.n -gt ($avgPostsPerMonth * 2.5)) { '爆發集中型' }
                    elseif ($activeMonthRatio -ge 0.5) { '間歇型' }
                    else { '稀疏型' }

    # ── Investment lens analysis (五大派系 + 指標 + 個股) ──
    $investmentLens = Compute-InvestmentLens $allPosts $script:InvestmentLens $script:StockMentions

    # ── Theme analysis ──
    $themeCounts = [ordered]@{}
    foreach ($k in $themeKeys) { $themeCounts[$k] = 0 }
    foreach ($p in $allPosts) {
        foreach ($k in $themeKeys) {
            foreach ($kw in $themesObj.$k) {
                if ($p.content -like "*$kw*") { $themeCounts[$k]++; break }
            }
        }
    }
    $themeSorted = [ordered]@{}
    foreach ($entry in ($themeCounts.GetEnumerator() | Sort-Object Value -Descending)) {
        $themeSorted[$entry.Key] = $entry.Value
    }
    $themeNonZero = ($themeSorted.Values | Where-Object { $_ -gt 0 }).Count
    $allThemeSum = ($themeSorted.Values | Measure-Object -Sum).Sum
    $top3Sum = 0; $i = 0
    foreach ($v in $themeSorted.Values) { if ($i -ge 3) { break }; $top3Sum += $v; $i++ }
    $top3Share = if ($allThemeSum -gt 0) { [math]::Round($top3Sum / $allThemeSum, 3) } else { 0 }
    $topThemeName = ($themeSorted.Keys | Select-Object -First 1)
    $topThemeCount = if ($topThemeName) { $themeSorted[$topThemeName] } else { 0 }
    $topThemeShare = if ($total -gt 0) { [math]::Round($topThemeCount / $total, 3) } else { 0 }
    $concLabel = Get-Label $top3Share @(0.4, 0.6, 0.8) @('分散涵蓋', '中度集中', '高度集中', '極度集中')
    $breadthLabel = Get-Label $themeNonZero @(3, 6, 9) @('窄頻', '中等廣度', '廣泛涵蓋', '全方位')

    # ── Length analysis ──
    $shortN = 0; $medN = 0; $longN = 0
    foreach ($p in $allPosts) {
        $L = $p.content.Length
        if ($L -lt 100) { $shortN++ } elseif ($L -lt 300) { $medN++ } else { $longN++ }
    }
    $shortR = [math]::Round($shortN / $total, 3)
    $medR = [math]::Round($medN / $total, 3)
    $longR = [math]::Round($longN / $total, 3)
    $predominant = if ($shortN -ge $medN -and $shortN -ge $longN) { '短文型' }
                   elseif ($longN -ge $medN) { '長文型' }
                   else { '中文型' }
    $lengthSpread = $longN -gt 0 -and $shortN -gt 0 -and ($shortR -ge 0.25 -and $longR -ge 0.25)
    if ($lengthSpread) { $predominant = "$predominant（兼具長短）" }

    # ── Hashtag analysis ──
    $hashtagRe = [regex]'#[\w一-鿿]+'
    $totalHashtags = 0; $postsWithTag = 0
    $hashtagFreq = @{}
    foreach ($p in $allPosts) {
        $tags = $hashtagRe.Matches($p.content)
        if ($tags.Count -gt 0) {
            $postsWithTag++
            $totalHashtags += $tags.Count
            foreach ($t in $tags) {
                $tag = $t.Value
                if (-not $hashtagFreq[$tag]) { $hashtagFreq[$tag] = 0 }
                $hashtagFreq[$tag]++
            }
        }
    }
    $avgTagsPerPost = if ($total -gt 0) { [math]::Round($totalHashtags / $total, 2) } else { 0 }
    $tagCoverage = if ($total -gt 0) { [math]::Round($postsWithTag / $total, 3) } else { 0 }
    $tagIntensityLabel = Get-Label $avgTagsPerPost @(1, 3, 6) @('幾乎不用', '輕度使用', '中度使用', '重度使用')

    # Personal-brand hashtags (containing persona or author)
    $brandTokens = @($persona, $Author) | Where-Object { $_ }
    $personalTagOccurrences = 0
    foreach ($tag in $hashtagFreq.Keys) {
        foreach ($tok in $brandTokens) {
            if ($tag -like "*$tok*") { $personalTagOccurrences += $hashtagFreq[$tag]; break }
        }
    }
    $personalBrandShare = if ($totalHashtags -gt 0) { [math]::Round($personalTagOccurrences / $totalHashtags, 3) } else { 0 }
    $brandLabel = Get-Label $personalBrandShare @(0.05, 0.15, 0.3) @('無個人品牌標籤', '輕度個人品牌', '中度個人品牌', '強個人品牌')

    $topHashtags = $hashtagFreq.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object {
        [PSCustomObject]@{ tag=$_.Key; count=$_.Value; is_personal = $(foreach ($tok in $brandTokens) { if ($_.Key -like "*$tok*") { $true; break } else { $false } }) }
    }

    # ── Disclaimer analysis ──
    $discKws = @('不構成投資建議','僅供參考','個人觀點','僅為個人','以上為個人','請自負盈虧','投資風險','非投資建議')
    $discCount = 0
    $discByYear = @{}
    $allByYear = @{}
    foreach ($p in $allPosts) {
        $hit = $false
        foreach ($k in $discKws) { if ($p.content -like "*$k*") { $hit = $true; break } }
        if ($hit) { $discCount++ }
        if ($p.date) {
            $y = $p.date.Year.ToString()
            if (-not $allByYear[$y]) { $allByYear[$y] = 0 }
            if (-not $discByYear[$y]) { $discByYear[$y] = 0 }
            $allByYear[$y]++
            if ($hit) { $discByYear[$y]++ }
        }
    }
    $discCoverage = if ($total -gt 0) { [math]::Round($discCount / $total, 3) } else { 0 }
    $discLabel = Get-Label $discCoverage @(0.1, 0.3, 0.6, 0.85) @('幾乎不附', '部分附上', '多數附上', '幾乎全附', '一律附上')
    $discYearTrend = [ordered]@{}
    foreach ($y in ($allByYear.Keys | Sort-Object)) {
        $rate = if ($allByYear[$y] -gt 0) { [math]::Round($discByYear[$y] / $allByYear[$y], 3) } else { 0 }
        $discYearTrend[$y] = $rate
    }

    # ── Platform-specific ──
    $platSpec = [ordered]@{}
    if ($platform -eq 'instagram') {
        $postType = @($allPosts | Where-Object { $_.type -eq 'post' })
        $reels    = @($allPosts | Where-Object { $_.type -eq 'reel' })
        $postAvg = if ($postType.Count) { [int](($postType | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum / $postType.Count) } else { 0 }
        $reelAvg = if ($reels.Count) { [int](($reels | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum / $reels.Count) } else { 0 }
        $platSpec = [ordered]@{
            posts_count = $postType.Count
            reels_count = $reels.Count
            posts_share = if ($total) { [math]::Round($postType.Count / $total, 3) } else { 0 }
            reels_share = if ($total) { [math]::Round($reels.Count / $total, 3) } else { 0 }
            post_avg_chars = $postAvg
            reel_avg_chars = $reelAvg
            dominant_format = if ($postType.Count -gt $reels.Count) { 'Post（圖文）' } else { 'Reel（短影音）' }
            format_balance_label = $(if ($postType.Count -eq 0 -or $reels.Count -eq 0) { '單一格式' } elseif ([math]::Abs($postType.Count - $reels.Count) / [math]::Max(1, $total) -lt 0.2) { '雙軌平衡' } else { '主格式偏好' })
        }
    }
    elseif ($platform -eq 'facebook') {
        $videoRe = [regex]'(youtu\.be|youtube\.com|/videos/|/reel/)'
        $videoCnt = ($allPosts | Where-Object { $videoRe.IsMatch($_.content) -or $videoRe.IsMatch([string]$_.url) }).Count
        $textOnly = $total - $videoCnt
        $vShare = if ($total) { [math]::Round($videoCnt / $total, 3) } else { 0 }
        $vLabel = Get-Label $vShare @(0.2, 0.4, 0.6) @('純圖文導向', '影音輔助', '影音為主', '影音壓倒性')
        $heavyTag = ($allPosts | Where-Object { $hashtagRe.Matches($_.content).Count -ge 5 }).Count
        $platSpec = [ordered]@{
            video_refs_count = $videoCnt
            text_only_count = $textOnly
            video_share = $vShare
            video_label = $vLabel
            avg_hashtags_per_post = $avgTagsPerPost
            heavy_hashtag_posts = $heavyTag
            heavy_hashtag_share = if ($total) { [math]::Round($heavyTag / $total, 3) } else { 0 }
        }
    }
    elseif ($platform -eq 'threads') {
        $type = if ($longR -gt 0.3) { '深度長文導向' }
                elseif ($shortR -gt 0.5) { '即時短評導向' }
                else { '混合型' }
        $platSpec = [ordered]@{
            short_posts = $shortN
            medium_posts = $medN
            long_posts = $longN
            short_share = $shortR
            long_share = $longR
            type_label = $type
        }
    }

    # ── Activity / tenure / intensity profile ──
    $activityLabel = Get-Label $avgPostsPerMonth @(3, 8, 20) @('低頻', '中頻', '高頻', '極高頻')
    $tenureLabel = Get-Label $monthsSpan @(6, 24, 60) @('新進', '中期', '老牌', '資深')
    $intensityLabel = Get-Label $avgChars @(80, 250, 600) @('短文型', '中等型', '長文型', '深度長文型')

    return [ordered]@{
        platform = $platform
        persona = $persona
        kol_id = $Author
        generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

        totals = [ordered]@{
            posts = $total
            chars = $totalChars
            avg_chars = $avgChars
        }

        temporal = [ordered]@{
            first_date = if ($firstDate) { $firstDate.ToString('yyyy-MM-dd') } else { $null }
            last_date  = if ($lastDate)  { $lastDate.ToString('yyyy-MM-dd') }  else { $null }
            months_span = $monthsSpan
            active_months_count = $activeMonths
            active_month_ratio = $activeMonthRatio
            max_dormant_gap_months = $maxDormantGap
            peak_month = if ($peakMonth) { $peakMonth.m } else { $null }
            peak_count = if ($peakMonth) { $peakMonth.n } else { 0 }
            avg_posts_per_active_month = $avgPostsPerMonth
            monthly_distribution = $sortedMonths
            trend = $trend
            cadence_label = $cadenceLabel
        }

        investment_lens = $investmentLens

        themes = [ordered]@{
            distribution = $themeSorted
            top_theme = $topThemeName
            top_theme_share = $topThemeShare
            top3_concentration = $top3Share
            non_zero_count = $themeNonZero
            concentration_label = $concLabel
            breadth_label = $breadthLabel
        }

        length = [ordered]@{
            short_lt100 = $shortN
            medium_100_300 = $medN
            long_gte300 = $longN
            short_share = $shortR
            medium_share = $medR
            long_share = $longR
            predominant_label = $predominant
        }

        hashtag = [ordered]@{
            posts_with_hashtag = $postsWithTag
            coverage = $tagCoverage
            avg_per_post = $avgTagsPerPost
            intensity_label = $tagIntensityLabel
            personal_brand_share = $personalBrandShare
            personal_brand_label = $brandLabel
            top_tags = @($topHashtags)
        }

        disclaimer = [ordered]@{
            coverage = $discCoverage
            coverage_label = $discLabel
            by_year = $discYearTrend
        }

        platform_specific = $platSpec

        profile_summary = [ordered]@{
            activity_label = $activityLabel
            tenure_label = $tenureLabel
            intensity_label = $intensityLabel
        }
    }
}

# ────────────────────────────────────────────────────────────
# Build per-platform metrics
# ────────────────────────────────────────────────────────────
function Load-Canonical($platform) {
    $f = "$kolDir\canonical\$platform.json"
    if (-not (Test-Path $f)) { return @() }
    return [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}

Write-Host ""
Write-Host "Computing metrics..." -ForegroundColor Gray

$threads_posts = Load-Canonical 'threads'
$ig_posts      = Load-Canonical 'instagram'
$fb_posts      = Load-Canonical 'facebook'

$threadsM = Build-Metrics 'threads'   $threads_posts $kolCfg $themes $themeKeys $domainCfg
$igM      = Build-Metrics 'instagram' $ig_posts      $kolCfg $themes $themeKeys $domainCfg
$fbM      = Build-Metrics 'facebook'  $fb_posts      $kolCfg $themes $themeKeys $domainCfg

# ────────────────────────────────────────────────────────────
# Top-level kol_db.json (App reads this for navigation)
# ────────────────────────────────────────────────────────────
$kolDb = [ordered]@{
    kol_id = $Author
    persona = $kolCfg.persona
    domain_id = $domainCfg.domain_id
    domain_name = $domainCfg.domain_name
    generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    totals_all_platforms = [ordered]@{
        posts = $threadsM.totals.posts + $igM.totals.posts + $fbM.totals.posts
        chars = $threadsM.totals.chars + $igM.totals.chars + $fbM.totals.chars
        platforms_with_data = (@($threadsM, $igM, $fbM) | Where-Object { $_.totals.posts -gt 0 }).Count
    }

    platforms = [ordered]@{
        threads = [ordered]@{
            posts = $threadsM.totals.posts
            first_date = $threadsM.temporal.first_date
            last_date  = $threadsM.temporal.last_date
            months_span = $threadsM.temporal.months_span
            cadence = $threadsM.temporal.cadence_label
            top_theme = $threadsM.themes.top_theme
            activity = $threadsM.profile_summary.activity_label
        }
        instagram = [ordered]@{
            posts = $igM.totals.posts
            first_date = $igM.temporal.first_date
            last_date  = $igM.temporal.last_date
            months_span = $igM.temporal.months_span
            cadence = $igM.temporal.cadence_label
            top_theme = $igM.themes.top_theme
            activity = $igM.profile_summary.activity_label
        }
        facebook = [ordered]@{
            posts = $fbM.totals.posts
            first_date = $fbM.temporal.first_date
            last_date  = $fbM.temporal.last_date
            months_span = $fbM.temporal.months_span
            cadence = $fbM.temporal.cadence_label
            top_theme = $fbM.themes.top_theme
            activity = $fbM.profile_summary.activity_label
        }
    }

    profile = [ordered]@{
        persona = $kolCfg.persona
        domain = $kolCfg.domain
        joined_at = (Get-Date).ToString('yyyy-MM-dd')
    }
}

# ────────────────────────────────────────────────────────────
# Save outputs
# ────────────────────────────────────────────────────────────
function Save-Json($obj, $path) {
    $json = $obj | ConvertTo-Json -Depth 14
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

Save-Json $kolDb     "$dbDir\kol_db.json"
Save-Json $threadsM  "$dbDir\threads_metrics.json"
Save-Json $igM       "$dbDir\instagram_metrics.json"
Save-Json $fbM       "$dbDir\facebook_metrics.json"

Write-Host ""
Write-Host "===== KOL Database built =====" -ForegroundColor Green
Write-Host "  $dbDir\kol_db.json"
Write-Host "  $dbDir\threads_metrics.json    ($($threadsM.totals.posts) posts)"
Write-Host "  $dbDir\instagram_metrics.json  ($($igM.totals.posts) posts)"
Write-Host "  $dbDir\facebook_metrics.json   ($($fbM.totals.posts) posts)"
