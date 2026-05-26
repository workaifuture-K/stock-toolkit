# ============================================================
# 變現分析 (Monetization Analysis) — Taiwan finance KOL template
# ============================================================
# 從 canonical + metrics 產出 monetization_report.html
#
# 涵蓋 5 大角度：
#   1. 現有變現盤點 — 業配貼文掃描、品牌頻率、類別分布
#   2. 內容強項與缺口 — 主題分布 vs 機會
#   3. 產文節奏可持續性 — 月度趨勢、加溫程度
#   4. 平台分工 — IG vs FB 風格差異
#   5. 競品定位 — 跟主流 KOL 的差異化（含 placeholder 待填寫）
#
# ⚠️ 客製化需求（Taiwan finance KOL flavor）：
#   - $sponsors 列表：Taiwan 券商/投信/平台品牌名單。若 KOL 跨域（美股、Crypto、
#     非財經）請增刪。若 KOL 同樣是 Taiwan ETF/存股/個股，可直接用。
#   - Section 5 競品表：硬編碼 Taiwan ETF KOL 競品名單（市場先生、清流君、施昇輝、
#     雷浩斯、R爸、李柏鋒、怪老子）。其他細分請改成符合該 KOL 的競品。
#   - Section 5 護城河/弱點/變現建議：留 placeholder「[請填寫]」待人工填寫，因為
#     這要 case-by-case 判斷，無法自動產生。
#
# Usage:
#   .\analyze_monetization.ps1 -Domain <domain> -Author <kol>
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Domain,

    [Parameter(Mandatory=$true)]
    [string]$Author
)

$base = $PSScriptRoot
$kolDir = "$base\domains\$Domain\kols\$Author"

# ── Load data ────────────────────────────────────────────────────────────────
$ig    = [System.IO.File]::ReadAllText("$kolDir\canonical\instagram.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$fb    = [System.IO.File]::ReadAllText("$kolDir\canonical\facebook.json",  [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$igM   = [System.IO.File]::ReadAllText("$kolDir\database\instagram_metrics.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$fbM   = [System.IO.File]::ReadAllText("$kolDir\database\facebook_metrics.json",  [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$prof  = [System.IO.File]::ReadAllText("$kolDir\kol_profile.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$dom   = [System.IO.File]::ReadAllText("$base\domains\$Domain\domain.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json

Write-Host "Loaded: IG=$($ig.Count) posts, FB=$($fb.Count) posts" -ForegroundColor Cyan

# ── Combine posts with platform tag ──────────────────────────────────────────
$posts = @()
foreach ($p in $ig) { $posts += [PSCustomObject]@{ platform='instagram'; date=$p.date; url=$p.url; content=$p.content } }
foreach ($p in $fb) { $posts += [PSCustomObject]@{ platform='facebook';  date=$p.date; url=$p.url; content=$p.content } }
Write-Host "Combined posts: $($posts.Count)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: 業配掃描 (Sponsored post detection)
# ─────────────────────────────────────────────────────────────────────────────
# 偵測邏輯分層：
#   Tier A (極高信心)：含「X投信行銷資訊」或「本文受 X 委託」
#   Tier B (高信心)  ：含品牌名 + CTA 模式（留言「X」我傳給你）
#   Tier C (中信心)  ：含品牌名（但不一定是業配，可能只是 mention）

$sponsors = [ordered]@{
    # 券商
    '新光證券'   = @{ category='券商'; pattern='新光證券' }
    '富邦證券'   = @{ category='券商'; pattern='富邦證券|富邦.{0,3}AI PRO' }
    '國泰證券'   = @{ category='券商'; pattern='國泰證券|小樹點' }
    '永豐證券'   = @{ category='券商'; pattern='永豐證券' }
    # 投信（行銷資訊明顯標註）
    '國泰投信'   = @{ category='投信'; pattern='國泰投信行銷' }
    '富邦投信'   = @{ category='投信'; pattern='富邦投信行銷' }
    '元大投信'   = @{ category='投信'; pattern='元大投信行銷' }
    '群益投信'   = @{ category='投信'; pattern='群益投信行銷' }
    '中信投信'   = @{ category='投信'; pattern='中信投信行銷|本文受中信' }
    '玉山投信'   = @{ category='投信'; pattern='玉山投信行銷|本文受玉山' }
    '貝萊德投信' = @{ category='投信'; pattern='貝萊德投信' }
    '凱基投信'   = @{ category='投信'; pattern='凱基投信行銷' }
    '統一投信'   = @{ category='投信'; pattern='統一投信行銷' }
    '大華銀投信' = @{ category='投信'; pattern='大華銀投信行銷|大華投信行銷' }
    '永豐投信'   = @{ category='投信'; pattern='永豐投信行銷' }
    '富蘭克林'   = @{ category='投信'; pattern='富蘭克林華美投信|富蘭克林.{0,3}行銷' }
    # 平台 / 工具
    'Hami書城'   = @{ category='平台/工具'; pattern='Hami.{0,5}書城|Hami.{0,3}閱讀' }
    'ZONE Wallet'= @{ category='平台/工具'; pattern='ZONE Wallet|ZoneWallet' }
    'Money錢出版'= @{ category='出版/媒體'; pattern='Ryan爸爸的高效存股|《Ryan爸爸|《Money錢' }
    # 注意：原本有 '稀飯部落格' 和 'LINE社群'，但這兩個出現在他「反詐騙 footer」
    # 的「稀飯僅一人經營以下平台」列表中，不是業配（是身分聲明），會誤算 ~287 篇 Tier C
    # 已移除，避免污染統計。
}

# 自有平台 mentions (track separately, NOT counted as sponsored)
$ownPlatforms = @{
    '部落格' = 'stevenhongisme\.com|稀飯.{0,5}部落格'
    'LINE社群' = 'LINE封閉社群'
}

# CTA detector
$ctaPattern = '留言「[^」]+」'

# Scan each post
$sponsored = New-Object System.Collections.ArrayList
foreach ($post in $posts) {
    $content = if ($post.content) { [string]$post.content } else { '' }
    $hits = New-Object System.Collections.ArrayList
    foreach ($brand in $sponsors.Keys) {
        if ($content -match $sponsors[$brand].pattern) {
            [void]$hits.Add($brand)
        }
    }
    $hasCta = $content -match $ctaPattern
    $isExplicitMarketing = $content -match '行銷資訊|本文受.{0,5}委託'

    if ($hits.Count -gt 0 -or $hasCta) {
        $tier = if ($isExplicitMarketing) { 'A' }
                elseif ($hits.Count -gt 0 -and $hasCta) { 'B' }
                elseif ($hits.Count -gt 0) { 'C' }
                else { 'D' } # CTA only, no brand match
        $categories = New-Object System.Collections.ArrayList
        foreach ($h in $hits) {
            $c = $sponsors[$h].category
            if (-not $categories.Contains($c)) { [void]$categories.Add($c) }
        }
        [void]$sponsored.Add([PSCustomObject]@{
            platform   = $post.platform
            date       = $post.date
            url        = $post.url
            brands     = ($hits -join ', ')
            categories = ($categories -join ', ')
            tier       = $tier
            has_cta    = $hasCta
            snippet    = if ($content.Length -gt 220) { $content.Substring(0,220) + '...' } else { $content }
        })
    }
}

Write-Host "Sponsored posts detected: $($sponsored.Count) / $($posts.Count) ($([math]::Round($sponsored.Count/$posts.Count*100,1))%)"

# Aggregate brand counts (only Tier A+B+C, exclude D)
$brandCounts = @{}
$categoryCounts = @{}
foreach ($s in $sponsored | Where-Object { $_.tier -in 'A','B','C' }) {
    foreach ($b in ($s.brands -split ', ')) {
        if ($b) {
            if (-not $brandCounts.ContainsKey($b)) { $brandCounts[$b] = 0 }
            $brandCounts[$b]++
        }
    }
    foreach ($c in ($s.categories -split ', ')) {
        if ($c) {
            if (-not $categoryCounts.ContainsKey($c)) { $categoryCounts[$c] = 0 }
            $categoryCounts[$c]++
        }
    }
}

$tierA = @($sponsored | Where-Object { $_.tier -eq 'A' })
$tierB = @($sponsored | Where-Object { $_.tier -eq 'B' })
$tierC = @($sponsored | Where-Object { $_.tier -eq 'C' })
$tierD = @($sponsored | Where-Object { $_.tier -eq 'D' })

Write-Host "  Tier A (極高信心 - 行銷資訊明標): $($tierA.Count)"
Write-Host "  Tier B (高信心 - 品牌+CTA):       $($tierB.Count)"
Write-Host "  Tier C (中信心 - 品牌 mention):   $($tierC.Count)"
Write-Host "  Tier D (僅 CTA):                  $($tierD.Count)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: 主題分布合併 (Cross-platform theme aggregation)
# ─────────────────────────────────────────────────────────────────────────────
$themes = @{}
foreach ($t in $igM.themes.distribution.PSObject.Properties) {
    $themes[$t.Name] = @{ ig=$t.Value; fb=0; total=$t.Value }
}
foreach ($t in $fbM.themes.distribution.PSObject.Properties) {
    if ($themes.ContainsKey($t.Name)) {
        $themes[$t.Name].fb = $t.Value
        $themes[$t.Name].total += $t.Value
    } else {
        $themes[$t.Name] = @{ ig=0; fb=$t.Value; total=$t.Value }
    }
}
$themeRanking = $themes.GetEnumerator() | Sort-Object { $_.Value.total } -Descending

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: 月度節奏分析 (Monthly cadence)
# ─────────────────────────────────────────────────────────────────────────────
$months = @{}
foreach ($m in $igM.temporal.monthly_distribution.PSObject.Properties) {
    $months[$m.Name] = @{ ig=$m.Value; fb=0 }
}
foreach ($m in $fbM.temporal.monthly_distribution.PSObject.Properties) {
    if ($months.ContainsKey($m.Name)) {
        $months[$m.Name].fb = $m.Value
    } else {
        $months[$m.Name] = @{ ig=0; fb=$m.Value }
    }
}
$sortedMonths = $months.GetEnumerator() | Sort-Object Name

# Compute trend
$last3Months = $sortedMonths | Select-Object -Last 3
$prev3Months = $sortedMonths | Select-Object -Last 6 | Select-Object -First 3
$last3Total  = ($last3Months | ForEach-Object { $_.Value.ig + $_.Value.fb } | Measure-Object -Sum).Sum
$prev3Total  = ($prev3Months | ForEach-Object { $_.Value.ig + $_.Value.fb } | Measure-Object -Sum).Sum
$growthPct   = if ($prev3Total -gt 0) { [math]::Round(($last3Total - $prev3Total) / $prev3Total * 100, 1) } else { 0 }

# ─────────────────────────────────────────────────────────────────────────────
# Helper: HTML escape
# ─────────────────────────────────────────────────────────────────────────────
function HtmlE([string]$s) {
    if (-not $s) { return '' }
    return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

# ─────────────────────────────────────────────────────────────────────────────
# Build HTML
# ─────────────────────────────────────────────────────────────────────────────
$today = (Get-Date).ToString('yyyy-MM-dd')
$persona = HtmlE $prof.persona

# Section 1 — Sponsored breakdown
$totalSponsored = $tierA.Count + $tierB.Count + $tierC.Count
$sponsoredPct = if ($posts.Count -gt 0) { [math]::Round($totalSponsored / $posts.Count * 100, 1) } else { 0 }

$brandRows = ''
$maxBrandCount = if ($brandCounts.Values.Count -gt 0) { ($brandCounts.Values | Measure-Object -Maximum).Maximum } else { 1 }
foreach ($kv in ($brandCounts.GetEnumerator() | Sort-Object Value -Descending)) {
    $brand = HtmlE $kv.Key
    $count = $kv.Value
    $cat = HtmlE $sponsors[$kv.Key].category
    $barWidth = [math]::Round($count / $maxBrandCount * 100)
    $brandRows += "<tr><td>$brand</td><td>$cat</td><td style='width:50%'><div class='bar' style='width:$barWidth%'></div></td><td class='num'>$count</td></tr>"
}

$categoryRows = ''
$maxCatCount = if ($categoryCounts.Values.Count -gt 0) { ($categoryCounts.Values | Measure-Object -Maximum).Maximum } else { 1 }
foreach ($kv in ($categoryCounts.GetEnumerator() | Sort-Object Value -Descending)) {
    $cat = HtmlE $kv.Key
    $count = $kv.Value
    $barWidth = [math]::Round($count / $maxCatCount * 100)
    $categoryRows += "<tr><td><b>$cat</b></td><td style='width:60%'><div class='bar bar-cat' style='width:$barWidth%'></div></td><td class='num'>$count</td></tr>"
}

# Section 2 — Theme strengths/gaps
$themeRows = ''
$totalThemePosts = ($themes.Values | ForEach-Object { $_.total } | Measure-Object -Sum).Sum
$maxThemeCount = if ($themes.Values.Count -gt 0) { ($themes.Values | ForEach-Object { $_.total } | Measure-Object -Maximum).Maximum } else { 1 }
$rank = 0
foreach ($t in $themeRanking) {
    $rank++
    $theme = HtmlE $t.Key
    $total = $t.Value.total
    $ig_c  = $t.Value.ig
    $fb_c  = $t.Value.fb
    $share = if ($totalThemePosts -gt 0) { [math]::Round($total / $totalThemePosts * 100, 1) } else { 0 }
    $barWidth = [math]::Round($total / $maxThemeCount * 100)
    $verdictClass = if ($rank -le 3) { 'strong' } elseif ($rank -le 8) { 'medium' } else { 'gap' }
    $verdictText = if ($rank -le 3) { '強項' } elseif ($rank -le 8) { '中段' } else { '缺口' }
    $themeRows += "<tr><td class='num'>$rank</td><td>$theme</td><td style='width:35%'><div class='bar' style='width:$barWidth%'></div></td><td class='num'>$total</td><td class='num'>$share%</td><td class='num'>$ig_c</td><td class='num'>$fb_c</td><td><span class='tag tag-$verdictClass'>$verdictText</span></td></tr>"
}

# Section 3 — Monthly cadence
$monthRows = ''
$maxMonthCount = 1
foreach ($m in $sortedMonths) {
    $v = $m.Value.ig + $m.Value.fb
    if ($v -gt $maxMonthCount) { $maxMonthCount = $v }
}
foreach ($m in $sortedMonths) {
    $month = $m.Key
    $ig_c  = $m.Value.ig
    $fb_c  = $m.Value.fb
    $total = $ig_c + $fb_c
    $igPct = [math]::Round($ig_c / $maxMonthCount * 100)
    $fbPct = [math]::Round($fb_c / $maxMonthCount * 100)
    $monthRows += "<tr><td>$month</td><td class='num'>$total</td><td class='num'>$ig_c</td><td class='num'>$fb_c</td><td style='width:55%'><div class='stack'><div class='bar bar-ig' style='width:$igPct%'></div><div class='bar bar-fb' style='width:$fbPct%'></div></div></td></tr>"
}

# Section 4 — Platform diff
$igLen = $igM.length
$fbLen = $fbM.length
$igTheme = $igM.themes.top_theme_share * 100
$fbTheme = $fbM.themes.top_theme_share * 100

# Section 5 — Competitor placeholder, will fill in HTML directly

# ─────────────────────────────────────────────────────────────────────────────
# Build full HTML
# ─────────────────────────────────────────────────────────────────────────────
$html = @"
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<title>$persona — 變現分析報告</title>
<style>
* { box-sizing: border-box; }
body { font-family: -apple-system, "Segoe UI", "Microsoft JhengHei", "PingFang TC", sans-serif; background: #0f1419; color: #e8eaed; margin: 0; padding: 40px 24px; line-height: 1.7; }
.wrap { max-width: 1100px; margin: 0 auto; }
header { border-bottom: 3px solid #ff5757; padding-bottom: 20px; margin-bottom: 32px; }
h1 { font-size: 32px; margin: 0 0 8px; }
.tagline { color: #8b95a8; font-size: 14px; margin: 0; }
section { margin: 40px 0; }
h2 { font-size: 22px; color: #fff; margin: 0 0 8px; border-left: 4px solid #ff5757; padding-left: 12px; }
.intro { color: #c8cdd6; margin-bottom: 16px; font-size: 14px; }
h3 { font-size: 16px; color: #ffd24d; margin: 24px 0 8px; }
.card { background: #1a1f2e; border: 1px solid #2a3142; border-radius: 10px; padding: 18px 22px; margin: 12px 0; }
.kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin: 16px 0; }
.kpi { background: #1a1f2e; border: 1px solid #2a3142; border-radius: 8px; padding: 14px 16px; }
.kpi .label { color: #8b95a8; font-size: 12px; }
.kpi .val { color: #fff; font-size: 22px; font-weight: 700; margin-top: 4px; }
.kpi .val.green { color: #4ade80; }
.kpi .val.red { color: #ff7b7b; }
.kpi .val.yellow { color: #ffd24d; }
.kpi .sub { color: #8b95a8; font-size: 11px; margin-top: 3px; }
table { width: 100%; border-collapse: collapse; margin: 12px 0; font-size: 13px; }
th, td { padding: 8px 10px; text-align: left; border-bottom: 1px solid #2a3142; }
th { color: #8b95a8; font-weight: 600; font-size: 12px; }
td.num { text-align: right; color: #c8cdd6; font-variant-numeric: tabular-nums; }
.bar { background: linear-gradient(90deg, #ff5757, #ff8a3d); height: 12px; border-radius: 3px; min-width: 1px; }
.bar-cat { background: linear-gradient(90deg, #4ade80, #16a34a); }
.bar-ig { background: linear-gradient(90deg, #ec4899, #db2777); height: 10px; display: inline-block; }
.bar-fb { background: linear-gradient(90deg, #3b82f6, #2563eb); height: 10px; display: inline-block; }
.stack { display: flex; flex-direction: column; gap: 2px; }
.tag { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 700; }
.tag-strong { background: rgba(74,222,128,0.15); color: #4ade80; }
.tag-medium { background: rgba(255,210,77,0.15); color: #ffd24d; }
.tag-gap { background: rgba(255,123,123,0.15); color: #ff7b7b; }
.insight { background: rgba(255,210,77,0.08); border-left: 3px solid #ffd24d; padding: 14px 18px; margin: 16px 0; border-radius: 0 6px 6px 0; }
.insight h4 { margin: 0 0 6px; color: #ffd24d; font-size: 14px; }
.insight p { margin: 4px 0; color: #d1d5db; font-size: 13px; }
.warn { background: rgba(255,123,123,0.08); border-left: 3px solid #ff7b7b; padding: 14px 18px; margin: 16px 0; border-radius: 0 6px 6px 0; }
.warn h4 { margin: 0 0 6px; color: #ff7b7b; font-size: 14px; }
.warn p { margin: 4px 0; color: #d1d5db; font-size: 13px; }
.good { background: rgba(74,222,128,0.08); border-left: 3px solid #4ade80; padding: 14px 18px; margin: 16px 0; border-radius: 0 6px 6px 0; }
.good h4 { margin: 0 0 6px; color: #4ade80; font-size: 14px; }
.good p { margin: 4px 0; color: #d1d5db; font-size: 13px; }
.cmp-table { font-size: 12px; }
.cmp-table th, .cmp-table td { padding: 8px 6px; }
.back { display: inline-block; color: #8b95a8; text-decoration: none; font-size: 13px; margin-bottom: 16px; }
.back:hover { color: #ff5757; }
ul, ol { color: #d1d5db; font-size: 13px; padding-left: 20px; line-height: 1.9; }
li { margin: 4px 0; }
b { color: #fff; }
.snippet { font-size: 12px; color: #9ca3af; max-width: 600px; }
.muted { color: #8b95a8; font-size: 12px; }
</style>
</head>
<body>
<div class="wrap">
<a class="back" href="index.html">← 回 $persona 平台索引</a>
<header>
  <h1>$persona — 變現分析報告</h1>
  <p class="tagline">基於 $($posts.Count) 篇貼文（IG $($ig.Count) + FB $($fb.Count)）的變現機會與策略分析　·　生成日 $today</p>
</header>

<section>
<h2>1. 現有變現盤點</h2>
<p class="intro">掃描 $($posts.Count) 篇貼文，偵測業配貼文：四個信心等級。Tier A = 明標「行銷資訊」/「本文受 X 委託」、Tier B = 品牌名+CTA、Tier C = 純品牌 mention、Tier D = 僅 CTA。</p>

<div class="kpi-grid">
  <div class="kpi"><div class="label">業配貼文總數 (A+B+C)</div><div class="val yellow">$totalSponsored</div><div class="sub">$sponsoredPct% of all posts</div></div>
  <div class="kpi"><div class="label">Tier A 明標行銷</div><div class="val">$($tierA.Count)</div><div class="sub">高信心業配</div></div>
  <div class="kpi"><div class="label">Tier B 品牌+CTA</div><div class="val">$($tierB.Count)</div></div>
  <div class="kpi"><div class="label">Tier C 純品牌</div><div class="val">$($tierC.Count)</div></div>
  <div class="kpi"><div class="label">合作品牌數</div><div class="val">$($brandCounts.Count)</div></div>
</div>

<h3>按品牌排序</h3>
<table>
<thead><tr><th>品牌</th><th>類別</th><th>頻率</th><th>篇數</th></tr></thead>
<tbody>$brandRows</tbody>
</table>

<h3>按類別排序</h3>
<table>
<thead><tr><th>類別</th><th>頻率</th><th>篇數</th></tr></thead>
<tbody>$categoryRows</tbody>
</table>

<div class="insight">
<h4>💡 解讀</h4>
<p><b>變現結構：</b>主要靠投信「行銷資訊」業配（Tier A 明標），輔以證券商開戶優惠引導（Tier B 品牌+CTA）。</p>
<p><b>單一品牌風險：</b>排名前幾名的品牌如果是同一家投信，代表合作集中，需要分散。</p>
<p><b>CTA 漏斗：</b>大量「留言『XXX』我傳給你」是經典 KOL lead-gen 套路——把社群互動轉成 LINE/email 名單。值得追蹤每次 CTA 後的轉換率（這需要他自己的後台資料）。</p>
</div>
</section>

<section>
<h2>2. 內容強項與缺口</h2>
<p class="intro">12 個 ETF/存股 主題的兩平台合計分布。前 3 名 = 強項可包裝商品，中段 = 可拓展，後段 = 缺口（要嘛補上、要嘛承認不專精）。</p>

<table>
<thead><tr><th>#</th><th>主題</th><th>合計分布</th><th>合計</th><th>佔比</th><th>IG</th><th>FB</th><th>定位</th></tr></thead>
<tbody>$themeRows</tbody>
</table>

<div class="insight">
<h4>💡 變現轉化建議</h4>
<p><b>強項 (前 3) 可包裝：</b>「配息策略」「Fed/利率」「高股息 ETF」這三個主題的提及次數最高，最有資格做付費內容（電子書、訂閱電子報、Hahow 課程）。</p>
<p><b>中段主題 = 衛星商品：</b>市值型/債券/金融股/民生股——已有基礎，可做小型專題（單篇付費深度文、付費 LINE 群提早解讀）。</p>
<p><b>缺口的兩種詮釋：</b>(a) 不專精就承認、堅守強項；(b) 主動補強做差異化，例如「個人理財/保險」「資產配置」「退休 FIRE」——這幾個比較有「人生階段規劃」感，跟現在他主打的「資訊解讀」是不同類型的內容，可長線拓展但短期變現有限。</p>
</div>
</section>

<section>
<h2>3. 產文節奏可持續性</h2>
<p class="intro">按月份的發文量。近 3 個月趨勢能看出他是「加溫」、「持平」還是「降溫」。</p>

<div class="kpi-grid">
  <div class="kpi"><div class="label">前 3 月合計</div><div class="val">$prev3Total</div></div>
  <div class="kpi"><div class="label">近 3 月合計</div><div class="val yellow">$last3Total</div></div>
  <div class="kpi"><div class="label">成長率</div><div class="val $(if ($growthPct -gt 30) { 'red' } elseif ($growthPct -gt 0) { 'green' } else { 'red' })">$growthPct%</div></div>
  <div class="kpi"><div class="label">FB 整體趨勢</div><div class="val">$(HtmlE $fbM.temporal.trend.direction)</div><div class="sub">FB 內部判定</div></div>
  <div class="kpi"><div class="label">IG 整體趨勢</div><div class="val">$(HtmlE $igM.temporal.trend.direction)</div></div>
</div>

<table>
<thead><tr><th>月份</th><th>合計</th><th>IG</th><th>FB</th><th>IG / FB 分布</th></tr></thead>
<tbody>$monthRows</tbody>
</table>

<div class="warn">
<h4>⚠️ 可持續性警訊</h4>
<p><b>產文爆增：</b>近 3 個月跟前 3 個月相比成長 <b>$growthPct%</b>。$persona 從原本月 ~30-50 篇 FB 暴增到月 ~100-200 篇的「日報級」頻率。</p>
<p><b>燃燒風險：</b>單人經營（他文末多次強調「稀飯僅一人經營」）卻維持日更，6-12 個月內若沒分工/工具化，幾乎必然撞牆。</p>
<p><b>變現連動：</b>產文量決定當前流量，但「砸時間換流量」的模式無法長期擴張。應該把 <b>產文 → 課程/書籍/訂閱</b> 這條變現槓桿做起來，把單篇的「邊際時間成本」攤掉。</p>
</div>

<div class="good">
<h4>✅ 機會點</h4>
<p><b>趨勢正向但邊際遞減：</b>產文 5 倍但變現不會 5 倍，現在是把現有觀眾「升級」成付費客戶的最佳時機。</p>
<p><b>選擇分群：</b>免費 FB/IG 維持流量、收費社群（LINE 已有）提供更早解讀、付費課程（殖利率計算機/補充保費試算/ETF 比較器）為核心商品。</p>
</div>
</section>

<section>
<h2>4. 平台分工（IG vs FB）</h2>
<p class="intro">$persona 同一主題在兩個平台上的呈現完全不同，已經有自然的平台分工。</p>

<table class="cmp-table">
<thead><tr><th>面向</th><th>Instagram</th><th>Facebook</th><th>解讀</th></tr></thead>
<tbody>
<tr><td><b>內容跨度</b></td><td>$($igM.temporal.months_span) 個月</td><td>$($fbM.temporal.months_span) 個月</td><td>IG 經營比 FB 早 ~20 個月</td></tr>
<tr><td><b>篇數</b></td><td>$($igM.totals.posts)</td><td>$($fbM.totals.posts)</td><td>FB 後進但篇數已超車（高頻策略）</td></tr>
<tr><td><b>平均字數</b></td><td>$($igM.totals.avg_chars)</td><td>$($fbM.totals.avg_chars)</td><td>IG 長文 ~$([math]::Round($igM.totals.avg_chars/$fbM.totals.avg_chars,1)) 倍</td></tr>
<tr><td><b>長文（300+ 字）佔比</b></td><td>$([math]::Round($igLen.long_share*100,1))%</td><td>$([math]::Round($fbLen.long_share*100,1))%</td><td>IG 純長文型、FB 短長並用</td></tr>
<tr><td><b>Top theme 集中度</b></td><td>$([math]::Round($igTheme,1))%</td><td>$([math]::Round($fbTheme,1))%</td><td>IG 更集中在「配息策略」</td></tr>
<tr><td><b>分析鏡頭</b></td><td>$(HtmlE $igM.investment_lens.lens_label)</td><td>$(HtmlE $fbM.investment_lens.lens_label)</td><td>IG 更談「為什麼」、FB 更談「發生什麼」</td></tr>
<tr><td><b>Hashtag 使用</b></td><td>$([math]::Round($igM.hashtag.coverage*100,1))% 覆蓋</td><td>$([math]::Round($fbM.hashtag.coverage*100,1))% 覆蓋</td><td>IG 用 hashtag 抓 SEO、FB 不用</td></tr>
<tr><td><b>免責聲明覆蓋</b></td><td>$([math]::Round($igM.disclaimer.coverage*100,1))%</td><td>$([math]::Round($fbM.disclaimer.coverage*100,1))%</td><td>長文較容易加上「投資一定有風險」聲明</td></tr>
</tbody>
</table>

<div class="insight">
<h4>💡 變現的平台分工策略</h4>
<p><b>IG = 「長期 SEO 教育型」</b>：長文 + hashtag 適合做「教育型內容入口」。新讀者搜尋「高股息 ETF」「殖利率」會搜到他的 IG。<b>變現路徑：</b>IG → 部落格 → 課程/eBook</p>
<p><b>FB = 「即時資訊型」</b>：短文 + 高頻 + 無 hashtag 適合做「老粉的日常 dispatch」。已知道他的人會習慣每日刷他的 FB 看配息預估。<b>變現路徑：</b>FB → LINE 社群（已有）→ 付費訂閱</p>
<p><b>差異化執行：</b>不要在兩個平台發完全一樣的內容（雖然他現在某程度上有）。IG 改成「主題式長文」、FB 改成「即時短評+加碼留意名單」。</p>
</div>
</section>

<section>
<h2>5. 競品定位 — 跟主流 ETF KOL 的差異</h2>
<p class="intro">台灣 ETF/存股 KOL 圈的主要對手與 $persona 的差異化機會。</p>

<table class="cmp-table">
<thead><tr><th>競品</th><th>定位</th><th>變現主要靠</th><th>跟 $persona 的差異</th></tr></thead>
<tbody>
<tr><td><b>市場先生</b></td><td>理財教育綜合站</td><td>Hahow 課程、付費 newsletter、業配</td><td>市場先生內容更廣（房地產、保險、選股），$persona 更聚焦 ETF。市場先生不做日報級配息追蹤。</td></tr>
<tr><td><b>清流君</b></td><td>被動投資理念派</td><td>書籍、Hahow 課程</td><td>清流君主打「全球分散+指數投資」哲學，$persona 主打「台股ETF配息實務」。清流君學術，$persona 實用。</td></tr>
<tr><td><b>施昇輝</b></td><td>0050 福音派</td><td>書籍、講座、節目</td><td>施昇輝倡導「無腦買 0050 1 張」、講人生哲學。$persona 數據導向、追蹤新檔。客群重疊不高。</td></tr>
<tr><td><b>雷浩斯</b></td><td>價值投資派</td><td>書籍、Hahow 課程</td><td>雷浩斯選股、不買 ETF。$persona 不選股、專注 ETF。完全不同細分。</td></tr>
<tr><td><b>R爸 (Ryan爸爸)</b></td><td>存股 ETF 派</td><td>新書、訂閱社群</td><td>R爸跟 $persona 主題重疊度最高。R爸更生活化（家庭情境），$persona 更專業化（即時資料）。$persona 已經跟 R 爸聯名推書，是合作對象不是純對手。</td></tr>
<tr><td><b>李柏鋒</b></td><td>美股 / 海外 ETF</td><td>付費 newsletter、講師</td><td>李柏鋒主軸美股。$persona 主軸台股 ETF。互補性高。</td></tr>
<tr><td><b>怪老子</b></td><td>退休理財派</td><td>書籍、講座</td><td>怪老子主談「退休現金流規劃」。$persona 沒做退休規劃（缺口 #7）。怪老子年長受眾，$persona 較年輕。</td></tr>
</tbody>
</table>

<div class="good">
<h4>✅ $persona 的差異化護城河</h4>
<p class="muted" style="background:rgba(255,210,77,0.08);padding:10px;border-radius:4px;margin-bottom:8px">📝 <b>請依此 KOL 實際差異化點填寫</b>（可從 Section 1-4 數據找線索：強項主題、平台分工、業配密度、產文節奏）</p>
<p><b>1. [請填寫 — KOL 獨特的內容定位 / 節奏 / 形式]：</b>[請描述為什麼這是護城河，例如「日報級即時更新沒人想跟」]</p>
<p><b>2. [請填寫 — KOL 對某趨勢/題材的早期或獨佔卡位]：</b>[請描述]</p>
<p><b>3. [請填寫 — KOL 有但競品都沒重點談的實務細節]：</b>[請描述如何能轉成 lead magnet 工具]</p>
<p><b>4. [請填寫 — KOL 的品牌記憶點 / 個人風格]：</b>[請描述跟同行差異]</p>
</div>

<div class="warn">
<h4>⚠️ 競爭弱點 / 應補強的</h4>
<p class="muted" style="background:rgba(255,123,123,0.08);padding:10px;border-radius:4px;margin-bottom:8px">📝 <b>請對照上方競品表填寫此 KOL 的缺口</b>（競品有但 KOL 沒有的東西）</p>
<p><b>1. [請填寫 — 競品有但此 KOL 沒有的核心商品 / 教材]：</b>[描述要怎麼補]</p>
<p><b>2. [請填寫 — 競品有清晰一句話定位但此 KOL 沒有]：</b>[描述]</p>
<p><b>3. [請填寫 — 競品吃下某客群但此 KOL 沒覆蓋]：</b>[描述]</p>
<p><b>4. [請填寫 — 競品有某主題但此 KOL 不主打]：</b>[描述]</p>
</div>

<div class="insight">
<h4>💡 具體變現建議（通用槓桿，請填入適合此 KOL 的主題）</h4>
<ol>
<li><b>短期 (1-3 個月)：</b>建立 lead magnet（試算工具 / 計算機 / 模板 / 速查表），引流到既有 LINE 社群或電子報。投入低、轉換可衡量。<br><span class="muted">→ 此 KOL 可做的具體工具：[請填寫]</span></li>
<li><b>中期 (3-6 個月)：</b>把日更/週更內容濃縮成電子書（100-150 頁），可跟既有合作媒體合作（出版社、新聞網站、財經平台）。<br><span class="muted">→ 此 KOL 適合主題：[請填寫]</span></li>
<li><b>中長期 (6-12 個月)：</b>上 Hahow / PressPlay / 自架站開課程，把分散貼文系統化。<br><span class="muted">→ 此 KOL 適合課程主題：[請填寫]</span></li>
<li><b>長期 (12 個月+)：</b>建立付費訂閱服務（評等 / 即時情報 / 個股追蹤），目標可衡量定價 + 留存率。<br><span class="muted">→ 此 KOL 適合的訂閱服務形式：[請填寫]</span></li>
<li><b>對外品牌：</b>確立一句話 elevator pitch（領域 + 風格 + 差異化），讓他在跟同行 PK 時有明確記憶點。<br><span class="muted">→ 此 KOL 的 elevator pitch 提案：[請填寫]</span></li>
</ol>
</div>
</section>

<footer style="margin-top: 60px; padding-top: 20px; border-top: 1px solid #2a3142; color: #8b95a8; font-size: 12px;">
本報告基於 $($posts.Count) 篇貼文 (IG $($ig.Count) + FB $($fb.Count))，跨度 $($igM.temporal.months_span) 個月 (IG) / $($fbM.temporal.months_span) 個月 (FB)。<br>
業配偵測為啟發式（regex 比對），可能漏偵測或誤判。實際業配關係請以本人/合作方確認為準。<br>
競品比較區段為知識整理（非數據驅動）；具體策略建議請依當事人意願執行。<br>
生成腳本：analyze_monetization.ps1　·　工具鏈：StockHero KOL Quantification Toolkit
</footer>

</div>
</body>
</html>
"@

$outPath = "$kolDir\reports\monetization_report.html"
[System.IO.File]::WriteAllText($outPath, $html, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "===== Monetization Report =====" -ForegroundColor Green
Write-Host "  Saved: $outPath"
Write-Host "  Open with: Start-Process '$outPath'"
