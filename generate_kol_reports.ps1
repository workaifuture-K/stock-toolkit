# ============================================================
# StockHero - Per-KOL Reports Generator
# ============================================================
# Reads per-KOL database, produces:
#   - 3 platform reports (8 sections, deep conclusions)
#   - KOL index page (links to 3 reports)
#   - Domain index page (lists all KOLs in domain) — regenerated each run
#
# Each KOL has its own Database + own Reports. No cross-KOL aggregation.
#
# Usage:
#   .\generate_kol_reports.ps1 -Domain tw_stock_kol -Author zhao1945
# ============================================================

param(
    [Parameter(Mandatory=$true)] [string]$Domain,
    [Parameter(Mandatory=$true)] [string]$Author
)

$base = $PSScriptRoot
$domainDir = "$base\domains\$Domain"
$kolDir    = "$domainDir\kols\$Author"
$dbDir     = "$kolDir\database"
$reportDir = "$kolDir\reports"
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$domainCfg = [System.IO.File]::ReadAllText("$domainDir\domain.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$kolCfg    = [System.IO.File]::ReadAllText("$kolDir\kol_profile.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$kolDb     = [System.IO.File]::ReadAllText("$dbDir\kol_db.json", [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$persona = if ($kolCfg.persona) { $kolCfg.persona } else { $Author }
$displayName = if ($persona -and $persona -ne $Author) { "@$Author（$persona）" } else { "@$Author" }

# ────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────
function HtmlEscape($s) {
    if ($null -eq $s) { return '' }
    return ([string]$s).Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}
function Pct($v) { return "$([math]::Round($v * 100, 1))%" }

function Bar-Html($items, $maxN = 12, $hideZero = $true) {
    if (-not $items) { return '<p class="muted">（無資料）</p>' }
    $entries = @()
    foreach ($prop in $items.PSObject.Properties) {
        $v = [int]$prop.Value
        if ($hideZero -and $v -le 0) { continue }
        $entries += [PSCustomObject]@{ key=$prop.Name; value=$v }
    }
    $entries = @($entries | Sort-Object value -Descending | Select-Object -First $maxN)
    if ($entries.Count -eq 0) { return '<p class="muted">（無資料）</p>' }
    $maxVal = ($entries | Measure-Object value -Maximum).Maximum
    if ($maxVal -le 0) { $maxVal = 1 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<table class="bar-table">')
    foreach ($e in $entries) {
        $pctOfMax = [math]::Round(100 * $e.value / $maxVal, 1)
        [void]$sb.Append("<tr><td class='bar-label'>$(HtmlEscape $e.key)</td><td class='bar-track'><div class='bar-fill' style='width:$pctOfMax%'></div></td><td class='bar-value'>$($e.value)</td></tr>")
    }
    [void]$sb.Append('</table>')
    return $sb.ToString()
}

# Display percentage-based bar (for category_post_share)
function Bar-Pct-Html($items, $maxN = 8) {
    if (-not $items) { return '<p class="muted">（無資料）</p>' }
    $entries = @()
    foreach ($prop in $items.PSObject.Properties) {
        $v = [double]$prop.Value
        $entries += [PSCustomObject]@{ key=$prop.Name; value=$v }
    }
    $entries = @($entries | Sort-Object value -Descending | Select-Object -First $maxN)
    if ($entries.Count -eq 0) { return '<p class="muted">（無資料）</p>' }
    $maxVal = ($entries | Measure-Object value -Maximum).Maximum
    if ($maxVal -le 0) { $maxVal = 1 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<table class="bar-table">')
    foreach ($e in $entries) {
        $pctOfMax = [math]::Round(100 * $e.value / $maxVal, 1)
        $pctDisplay = "$([math]::Round($e.value * 100, 1))%"
        [void]$sb.Append("<tr><td class='bar-label'>$(HtmlEscape $e.key)</td><td class='bar-track'><div class='bar-fill' style='width:$pctOfMax%'></div></td><td class='bar-value'>$pctDisplay</td></tr>")
    }
    [void]$sb.Append('</table>')
    return $sb.ToString()
}

# Display top items from an array of {keyField, valueField} PSObjects
function Bar-Items-Html($items, $keyField, $valueField, $maxN = 15) {
    if (-not $items) { return '<p class="muted">（無資料）</p>' }
    $list = @($items)
    if ($list.Count -eq 0) { return '<p class="muted">（無資料）</p>' }
    $list = @($list | Select-Object -First $maxN)
    $maxVal = ($list | ForEach-Object { [int]$_.$valueField } | Measure-Object -Maximum).Maximum
    if ($maxVal -le 0) { $maxVal = 1 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<table class="bar-table">')
    foreach ($e in $list) {
        $v = [int]$e.$valueField
        $k = [string]$e.$keyField
        $pctOfMax = [math]::Round(100 * $v / $maxVal, 1)
        [void]$sb.Append("<tr><td class='bar-label'>$(HtmlEscape $k)</td><td class='bar-track'><div class='bar-fill' style='width:$pctOfMax%'></div></td><td class='bar-value'>$v</td></tr>")
    }
    [void]$sb.Append('</table>')
    return $sb.ToString()
}

function Sparkline-Html($monthDist) {
    if (-not $monthDist) { return '' }
    $entries = @()
    foreach ($prop in $monthDist.PSObject.Properties) {
        $entries += [PSCustomObject]@{ month=$prop.Name; count=[int]$prop.Value }
    }
    if ($entries.Count -eq 0) { return '<p class="muted">（無時序資料）</p>' }
    $entries = @($entries | Sort-Object month)
    $maxVal = ($entries | Measure-Object count -Maximum).Maximum
    if ($maxVal -le 0) { $maxVal = 1 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<div class="sparkline">')
    foreach ($e in $entries) {
        $h = [math]::Max(2, [math]::Round(70 * $e.count / $maxVal, 0))
        [void]$sb.Append("<div class='spark-bar' style='height:${h}px' title='$($e.month): $($e.count) 篇'></div>")
    }
    [void]$sb.Append('</div>')
    [void]$sb.Append("<div class='sparkline-axis'><span>$($entries[0].month)</span><span>峰值 $($entries[($entries.Count - 1)].month) → $($maxVal) 篇</span><span>$($entries[-1].month)</span></div>")
    return $sb.ToString()
}

# ────────────────────────────────────────────────────────────
# Deep conclusion builders (each returns multi-sentence paragraph)
# ────────────────────────────────────────────────────────────
function Concl-Overview($m, $platformLabel) {
    $t = $m.totals; $tem = $m.temporal; $pr = $m.profile_summary
    $sent1 = "$displayName 在 $platformLabel 累積 <b>$($t.posts)</b> 篇貼文（共 $($t.chars) 字），活躍 <b>$($tem.months_span)</b> 個月，平均每篇 <b>$($t.avg_chars)</b> 字。"
    $sent2 = "依量級分類，屬 <b>$($pr.activity_label)</b> 發文者；依資歷分類，屬 <b>$($pr.tenure_label)</b>；依篇幅分類，屬 <b>$($pr.intensity_label)</b>。"
    $sent3 = "此三個標籤組合勾勒出該 KOL 在 $platformLabel 的基本面貌 — 量、年資、深度。"
    return "$sent1 $sent2 $sent3"
}

function Concl-Cadence($m) {
    $tem = $m.temporal
    $sent1 = "活躍月份占可能月份比 <b>$(Pct $tem.active_month_ratio)</b>（$($tem.active_months_count) / $([math]::Ceiling($tem.months_span)) 月），最長中斷期 <b>$($tem.max_dormant_gap_months)</b> 個月。"
    $sent2 = "發文節奏屬 <b>$($tem.cadence_label)</b>，峰值月份為 $($tem.peak_month)（$($tem.peak_count) 篇）。"
    $cadenceInsight = switch ($tem.cadence_label) {
        '穩定型' { "代表內容產出可預測，適合穩定追蹤；訂閱者體驗一致性高。" }
        '中斷後復活型' { "代表曾經沉寂後重新活躍，內容方向可能在中斷前後有顯著轉變，值得拆解前後期差異。" }
        '爆發集中型' { "代表內容產出高度集中在特定時段，可能對應市場事件或個人轉折；非常時期之外活躍度有限。" }
        '間歇型' { "代表發文以季節性或機會性為主，非每日例行；適合「事件驅動」型受眾。" }
        '稀疏型' { "代表整體投入度有限，內容增量緩慢；不適合作為高頻資訊源使用。" }
        default { "" }
    }
    return "$sent1 $sent2 $cadenceInsight"
}

function Concl-Lens($m) {
    $lens = $m.investment_lens
    if (-not $lens -or $lens.total_indicator_mentions -eq 0) {
        return "本平台貼文中未偵測到明顯的投資分析語彙 — 內容可能偏向心情記錄、生活分享或非投資題材。"
    }

    # Top 2 lens categories (with share %)
    $lensEntries = @()
    foreach ($prop in $lens.category_post_share.PSObject.Properties) {
        $lensEntries += [PSCustomObject]@{ name=$prop.Name; share=[double]$prop.Value }
    }
    $lensSorted = @($lensEntries | Sort-Object share -Descending | Where-Object { $_.share -gt 0 })
    $top2Str = @()
    foreach ($e in ($lensSorted | Select-Object -First 2)) {
        $top2Str += "<b>$($e.name)</b>（$(Pct $e.share) 貼文觸及）"
    }

    # Top 3 indicators (concrete vocab)
    $topInd = @($lens.top_indicators | Select-Object -First 3)
    $indStr = ($topInd | ForEach-Object { "<b>$(HtmlEscape $_.indicator)</b>（$($_.count)）" }) -join '、'

    # Top 3 stocks
    $topStk = @($lens.top_stocks | Select-Object -First 3)
    $stkStr = if ($topStk.Count -gt 0) { ($topStk | ForEach-Object { "<b>$(HtmlEscape $_.stock)</b>（$($_.count)）" }) -join '、' } else { '無顯著個股提及' }

    $sent1 = "本平台分析面向以 $($top2Str -join '、') 為主，整體判定為 <b>$($lens.lens_label)</b>。"
    $sent2 = "最常出現的具體語彙：$indStr；提及最多的個股／ETF：$stkStr。"

    # Count categories with ≥30% share — if 3+ are high, KOL is "comprehensive coverage"
    $highCats = @($lensSorted | Where-Object { $_.share -ge 0.3 })
    $isComprehensive = $highCats.Count -ge 3

    if ($isComprehensive) {
        $catNames = ($highCats | ForEach-Object { $_.name }) -join '、'
        $insight = "這位 KOL 在本平台採 <b>全面覆蓋型</b> 操作 — $catNames 等多個面向都有顯著占比，單篇內容常同時談財務、資金、心法。受眾若同時關心多個層面，這位 KOL 可作為一站式內容源。"
    } else {
        $insight = switch ($lens.dominant_lens) {
            '基本面' { "這位 KOL 看一檔股票好壞，主要從「公司賺不賺錢」切入 — 看的是營收、毛利率、EPS、法說會等財報數字。內容適合長線投資者參考。" }
            '籌碼面' { "這位 KOL 看一檔股票好壞，主要從「誰在買、誰在賣」切入 — 看的是外資、投信、融資融券、大戶動向等資金流向。內容適合追隨法人腳步的中短線操作者。" }
            '技術面' { "這位 KOL 看一檔股票好壞，主要從「線型走勢」切入 — 看的是均線、K 線、MACD、KD、支撐壓力等技術指標。內容適合波段／當沖型操作者。" }
            '消息面' { "這位 KOL 看一檔股票好壞，主要從「總體環境與事件」切入 — 看的是 Fed 升降息、CPI、地緣政治、油價匯率等宏觀變數。內容適合關注大環境輪動者。" }
            '心理面' { "這位 KOL 內容以「投資心法 + 紀律」為主軸 — 較少談特定股票數據，較多談部位控管、停損停利、情緒管理。內容適合建立投資觀念者。" }
            default { "" }
        }
    }

    return "$sent1 $sent2 $insight"
}

function Concl-Themes($m) {
    $th = $m.themes
    $top3 = @()
    $i = 0
    foreach ($prop in $th.distribution.PSObject.Properties) {
        if ($prop.Value -le 0) { break }
        $top3 += "<b>$($prop.Name)</b>（$($prop.Value) 篇）"
        $i++; if ($i -ge 3) { break }
    }
    if ($top3.Count -eq 0) {
        return "本平台貼文未命中任何領域主題定義，可能為非該領域內容或樣本太少。"
    }
    $sent1 = "次級主題前三：$($top3 -join '、')，合計占題材命中總數 <b>$(Pct $th.top3_concentration)</b>（$($th.concentration_label)）。"
    $sent2 = "在領域定義的 12 個主題中，命中 <b>$($th.non_zero_count)</b> 個（廣度：$($th.breadth_label)）。"
    return "$sent1 $sent2"
}

function Concl-Temporal($m) {
    $tem = $m.temporal
    if (-not $tem.trend) {
        return "時序資料長度不足以計算近期 vs 歷史比較（需至少 6 個月）。"
    }
    $tr = $tem.trend
    $sign = if ($tr.delta_pct -ge 0) { '+' } else { '' }
    $color = if ($tr.delta_pct -ge 10) { 'color:#22c55e' } elseif ($tr.delta_pct -le -10) { 'color:#ef4444' } else { 'color:#facc15' }
    $sent1 = "近 3 個月平均 <b>$($tr.recent_3mo_avg)</b> 篇/月，歷史平均 <b>$($tr.history_avg)</b> 篇/月。"
    $sent2 = "變動 <b style='$color'>$sign$($tr.delta_pct)%</b> — 屬 <b style='$color'>$($tr.direction)</b>。"
    $insight = switch ($tr.direction) {
        '明顯加溫' { "投入度近期顯著上升，可能對應市場熱度、平台演算法配合、或 KOL 主動調整重心；建議優先觀察。" }
        '溫和成長' { "穩定向上的軌跡，反映 KOL 對此平台的投入持續增加，但非爆發式。" }
        '明顯降溫' { "近期投入大幅減少，可能轉向其他平台、或內容重心調整；需追蹤是否為暫時性。" }
        '溫和衰退' { "投入度溫和下降，可能是市場降溫、KOL 重心移轉，或屬季節性回落。" }
        '持平' { "節奏穩定、近期與歷史一致，內容供給可預測。" }
        default { "" }
    }
    return "$sent1 $sent2 $insight"
}

function Concl-Length($m) {
    $L = $m.length
    $sent1 = "短文（<100 字）占 <b>$(Pct $L.short_share)</b>、中文（100-300）占 <b>$(Pct $L.medium_share)</b>、長文（≥300 字）占 <b>$(Pct $L.long_share)</b>。"
    $sent2 = "整體歸類為 <b>$($L.predominant_label)</b>（平均 $($m.totals.avg_chars) 字/篇）。"
    $insight = ''
    if ($L.short_share -ge 0.5) {
        $insight = "短文密集型 KOL 在此平台主要做「即時反應 / 情緒同步」，內容適合做訊號片段而非深度引用。"
    } elseif ($L.long_share -ge 0.4) {
        $insight = "長文密集型 KOL 在此平台做深度分析 / 結構化論述，內容適合作為知識素材或概念詞典來源。"
    } elseif ($L.predominant_label -like '*兼具長短*') {
        $insight = "兼具長短代表 KOL 在此平台同時做即時觀點 + 深度長文，內容多樣性高、用法彈性大。"
    } else {
        $insight = "篇幅集中在中間區間，屬於「能講清楚但不冗長」型內容；通常為標準觀察記錄。"
    }
    return "$sent1 $sent2 $insight"
}

function Concl-PlatformSpecific($m, $platform) {
    $ps = $m.platform_specific
    if ($platform -eq 'instagram') {
        $sent1 = "Post 篇數 <b>$($ps.posts_count)</b>（占 $(Pct $ps.posts_share)、平均 $($ps.post_avg_chars) 字）；Reel 篇數 <b>$($ps.reels_count)</b>（占 $(Pct $ps.reels_share)、平均 $($ps.reel_avg_chars) 字）。"
        $sent2 = "主要使用 <b>$($ps.dominant_format)</b>，雙軌結構屬 <b>$($ps.format_balance_label)</b>。"
        $insight = if ($ps.format_balance_label -eq '雙軌平衡') {
            "Post + Reel 並重的 KOL 把 IG 當「圖文 + 短影音」綜合載體用，可同時鎖定不同消費形態的受眾。"
        } elseif ($ps.posts_share -gt 0.7) {
            "明顯偏 Post 導向，IG 對該 KOL 來說近似「結構化貼文記錄板」；Reel 不是主要產出形式。"
        } elseif ($ps.reels_share -gt 0.7) {
            "明顯偏 Reel 導向，IG 對該 KOL 來說是「短影音通路」；圖文價值密度較低。"
        } else { "格式偏好溫和，沒有單一格式壓倒性主導。" }
        return "$sent1 $sent2 $insight"
    }
    if ($platform -eq 'facebook') {
        $sent1 = "含影片連結（YouTube / FB Video / Reel）<b>$($ps.video_refs_count)</b> 篇、純圖文 <b>$($ps.text_only_count)</b> 篇。"
        $sent2 = "影音占比 <b>$(Pct $ps.video_share)</b> — 歸類為 <b>$($ps.video_label)</b>；重度 hashtag 貼文（≥5 個）共 $($ps.heavy_hashtag_posts) 篇（$(Pct $ps.heavy_hashtag_share)）。"
        $insight = if ($ps.video_share -ge 0.5) {
            "影音為主代表 KOL 把 FB 當作 YouTube / 短影音導流站，FB 圖文內容多為影片預告或轉貼。深度文字內容請優先看其他平台。"
        } elseif ($ps.video_share -le 0.15) {
            "純圖文導向代表 KOL 把 FB 當作獨立文字載體；FB 內容自成一格，不依賴影音輔助。"
        } else { "影音輔助代表 FB 內容同時有圖文觀點與影片連結，混合型操作。" }
        return "$sent1 $sent2 $insight"
    }
    if ($platform -eq 'threads') {
        $sent1 = "短文（<100 字）<b>$($ps.short_posts)</b> 篇（占 $(Pct $ps.short_share)），長文（≥300 字）<b>$($ps.long_posts)</b> 篇（占 $(Pct $ps.long_share)）。"
        $sent2 = "整體結構歸類為 <b>$($ps.type_label)</b>。"
        $insight = switch -Wildcard ($ps.type_label) {
            '深度長文導向' { "Threads 對該 KOL 是論述場域，每篇都有完整鋪陳；不適合做「碎片化引用」式素材抽取。" }
            '即時短評導向' { "Threads 對該 KOL 是情緒同步通道，內容偏即時反應；單篇深度有限但量大、即時性高。" }
            '混合型' { "Threads 同時用於短評與長文，操作彈性最高；可同時提取金句與深度論述。" }
            default { "" }
        }
        return "$sent1 $sent2 $insight"
    }
    return ''
}

function Concl-Hashtag($m) {
    $h = $m.hashtag
    $sent1 = "平均每篇 <b>$($h.avg_per_post)</b> 個 hashtag、$(Pct $h.coverage) 貼文至少含 1 個 — 整體使用強度屬 <b>$($h.intensity_label)</b>。"
    $sent2 = "個人品牌標籤（含 KOL 名稱或暱稱）占 hashtag 總出現次數 <b>$(Pct $h.personal_brand_share)</b>，歸類為 <b>$($h.personal_brand_label)</b>。"
    $insight = ''
    if ($h.personal_brand_share -ge 0.2) {
        $insight = "強個人品牌標籤策略代表 KOL 主動經營「可搜尋的個人關鍵字」 — 對既有粉絲找回 KOL 過往內容、跨平台識別有強化效果。"
    } elseif ($h.avg_per_post -ge 5) {
        $insight = "高 hashtag 密度但個人品牌占比低，反映 KOL 用 hashtag 做主題曝光與演算法觸及，不強調自我識別。"
    } elseif ($h.avg_per_post -le 1) {
        $insight = "幾乎不用 hashtag 代表內容仰賴 followers / 演算法分發，而非主題標籤觸及；可能反映平台與內容性質（如純觀點論述）。"
    } else {
        $insight = "中度 hashtag 使用、低個人品牌占比，屬於「適度搜尋友善」型策略。"
    }
    return "$sent1 $sent2 $insight"
}

# ────────────────────────────────────────────────────────────
# Generate per-platform report
# ────────────────────────────────────────────────────────────
function Generate-PlatformReport($platform, $platformLabel, $accent) {
    $metricsPath = "$dbDir\${platform}_metrics.json"
    if (-not (Test-Path $metricsPath)) { return $null }
    $m = [System.IO.File]::ReadAllText($metricsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $today = (Get-Date).ToString('yyyy-MM-dd')

    if ($m.totals.posts -eq 0) {
        $html = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>$displayName — $platformLabel</title></head><body style='font-family:sans-serif;padding:30px;'>" +
                "<h1>$displayName · $platformLabel 平台報告</h1><p>該 KOL 在此平台目前尚無資料。</p></body></html>"
        $outPath = "$reportDir\${platform}_report.html"
        [System.IO.File]::WriteAllText($outPath, $html, [System.Text.UTF8Encoding]::new($false))
        return $outPath
    }

    $hero = "$displayName 在 <b>$platformLabel</b> 上累積 <b>$($m.totals.posts)</b> 篇內容，活躍期 <b>$($m.temporal.first_date) ~ $($m.temporal.last_date)</b>（$($m.temporal.months_span) 個月）。本平台主軸主題：<b>$($m.themes.top_theme)</b>。"

    $cOverview = Concl-Overview $m $platformLabel
    $cCadence  = Concl-Cadence  $m
    $cLens     = Concl-Lens     $m
    $cThemes   = Concl-Themes   $m
    $cTemporal = Concl-Temporal $m
    $cLength   = Concl-Length   $m
    $cPlatSpec = Concl-PlatformSpecific $m $platform
    $cHashtag  = Concl-Hashtag  $m

    $themeBar = Bar-Html $m.themes.distribution 12
    $spark = Sparkline-Html $m.temporal.monthly_distribution

    # Investment lens bars
    if ($m.investment_lens) {
        $lensBar      = Bar-Pct-Html  $m.investment_lens.category_post_share 5
        $indicatorBar = Bar-Items-Html $m.investment_lens.top_indicators 'indicator' 'count' 15
        $stockBar     = Bar-Items-Html $m.investment_lens.top_stocks 'stock' 'count' 20
        $lensLabel    = [string]$m.investment_lens.lens_label
        $lensSummary  = "整體判定：<b>$(HtmlEscape $lensLabel)</b> · 共出現 <b>$($m.investment_lens.total_indicator_mentions)</b> 次具體語彙、<b>$($m.investment_lens.unique_indicators)</b> 種不同指標、提及 <b>$($m.investment_lens.unique_stocks)</b> 支不同個股／ETF。"
    } else {
        $lensBar = '<p class="muted">（無資料）</p>'
        $indicatorBar = '<p class="muted">（無資料）</p>'
        $stockBar = '<p class="muted">（無資料）</p>'
        $lensLabel = ''
        $lensSummary = ''
    }

    # Hashtag chips
    $tagChips = ''
    foreach ($t in ($m.hashtag.top_tags | Select-Object -First 12)) {
        $isPersonal = $false
        if ($t.is_personal -is [array]) { $isPersonal = $t.is_personal -contains $true }
        else { $isPersonal = [bool]$t.is_personal }
        $extra = if ($isPersonal) { ' personal' } else { '' }
        $tagChips += "<span class='hashtag-chip$extra'>$(HtmlEscape $t.tag)<span class='chip-count'>$($t.count)</span></span>"
    }

    # Platform-specific section content
    $platSpecHtml = ''
    if ($platform -eq 'instagram') {
        $ps = $m.platform_specific
        $platSpecHtml = "<table class='kv-table'><tr><td>Post 篇數</td><td><b>$($ps.posts_count)</b>（$(Pct $ps.posts_share)）</td></tr><tr><td>Reel 篇數</td><td><b>$($ps.reels_count)</b>（$(Pct $ps.reels_share)）</td></tr><tr><td>Post 平均字數</td><td>$($ps.post_avg_chars)</td></tr><tr><td>Reel 平均字數</td><td>$($ps.reel_avg_chars)</td></tr><tr><td>主要格式</td><td><b>$($ps.dominant_format)</b></td></tr><tr><td>格式平衡</td><td><b>$($ps.format_balance_label)</b></td></tr></table>"
    } elseif ($platform -eq 'facebook') {
        $ps = $m.platform_specific
        $platSpecHtml = "<table class='kv-table'><tr><td>含影片連結</td><td><b>$($ps.video_refs_count)</b>（$(Pct $ps.video_share)）</td></tr><tr><td>純圖文</td><td>$($ps.text_only_count)</td></tr><tr><td>影音定位</td><td><b>$($ps.video_label)</b></td></tr><tr><td>平均 hashtag/篇</td><td>$($ps.avg_hashtags_per_post)</td></tr><tr><td>重度 hashtag 貼文（≥5）</td><td>$($ps.heavy_hashtag_posts)（$(Pct $ps.heavy_hashtag_share)）</td></tr></table>"
    } elseif ($platform -eq 'threads') {
        $ps = $m.platform_specific
        $platSpecHtml = "<table class='kv-table'><tr><td>短文（&lt;100）</td><td><b>$($ps.short_posts)</b>（$(Pct $ps.short_share)）</td></tr><tr><td>中文（100-300）</td><td>$($ps.medium_posts)</td></tr><tr><td>長文（≥300）</td><td><b>$($ps.long_posts)</b>（$(Pct $ps.long_share)）</td></tr><tr><td>結構定位</td><td><b>$($ps.type_label)</b></td></tr></table>"
    }


    $html = @"
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<title>$(HtmlEscape $displayName) — $platformLabel 分析報告</title>
<style>
:root { --bg:#0f1419; --card:#1a1f2e; --border:#2a3142; --text:#e8eaed; --muted:#8b95a8; --accent:$accent; }
* { box-sizing: border-box; }
body { font-family: -apple-system, "Segoe UI", "Microsoft JhengHei", "PingFang TC", sans-serif; background: var(--bg); color: var(--text); margin: 0; padding: 32px 24px; line-height: 1.7; }
.wrap { max-width: 980px; margin: 0 auto; }
.report-header { border-bottom: 3px solid var(--accent); padding-bottom: 18px; margin-bottom: 24px; }
.report-header .domain-badge { display: inline-block; background: var(--accent); color: white; padding: 3px 10px; border-radius: 4px; font-size: 11px; font-weight: 700; margin-bottom: 8px; }
.report-header h1 { margin: 0; font-size: 28px; }
.report-header .meta { color: var(--muted); font-size: 13px; margin-top: 6px; }
.nav-back { float: right; }
.nav-back a, .nav-back button { background: rgba(255,255,255,0.06); color: var(--text); border: none; padding: 7px 12px; border-radius: 6px; cursor: pointer; font-size: 12px; text-decoration: none; margin-left: 6px; }
.nav-back button { background: var(--accent); color: white; }
.hero { background: linear-gradient(135deg, rgba(255,87,87,0.08), rgba(59,130,246,0.04)); border-left: 4px solid var(--accent); padding: 18px 22px; margin: 20px 0 28px; border-radius: 6px; font-size: 15px; }
.hero b { color: var(--accent); }
section { margin: 28px 0; padding: 22px 24px; background: var(--card); border-radius: 10px; border: 1px solid var(--border); }
section h2 { margin: 0 0 14px; font-size: 18px; color: #fff; }
section h2 .num { color: var(--accent); margin-right: 8px; }
section h3 { margin: 18px 0 6px; font-size: 15px; color: #facc15; font-weight: 700; border-left: 3px solid #facc15; padding-left: 10px; }
.conclusion { background: rgba(255,87,87,0.06); border-left: 3px solid var(--accent); padding: 14px 16px; margin-top: 16px; font-size: 14px; color: var(--text); border-radius: 4px; line-height: 1.8; }
.conclusion::before { content: "結論："; font-weight: 700; color: var(--accent); margin-right: 6px; display: block; margin-bottom: 4px; }
.muted { color: var(--muted); font-size: 13px; }
.kv-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 14px; margin: 10px 0; }
.kv-card { background: rgba(255,255,255,0.03); padding: 12px 14px; border-radius: 6px; }
.kv-label { color: var(--muted); font-size: 12px; margin-bottom: 4px; }
.kv-value { font-size: 20px; font-weight: 700; }
.kv-value.small { font-size: 14px; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
table.kv-table td, table.kv-table th { padding: 7px 10px; border-bottom: 1px solid var(--border); text-align: left; }
table.kv-table td:first-child, table.kv-table th:first-child { color: var(--muted); width: 40%; }
table.bar-table td { padding: 4px 6px; border: none; }
.bar-label { width: 28%; color: var(--text); white-space: nowrap; }
.bar-track { width: 60%; background: rgba(255,255,255,0.06); border-radius: 3px; height: 18px; position: relative; }
.bar-fill { background: var(--accent); height: 18px; border-radius: 3px; }
.bar-value { width: 12%; text-align: right; color: var(--text); font-weight: 600; }
.sparkline { display: flex; gap: 2px; align-items: flex-end; height: 80px; margin: 12px 0 6px; padding: 6px 4px; background: rgba(255,255,255,0.03); border-radius: 4px; }
.spark-bar { flex: 1; min-width: 4px; background: var(--accent); border-radius: 2px 2px 0 0; opacity: 0.85; }
.sparkline-axis { display: flex; justify-content: space-between; color: var(--muted); font-size: 11px; }
.hashtag-chip { display: inline-block; background: rgba(255,255,255,0.05); padding: 5px 10px; border-radius: 14px; margin: 3px; font-size: 12px; }
.hashtag-chip.personal { background: rgba(255,87,87,0.15); border: 1px solid var(--accent); }
.chip-count { background: var(--accent); color: white; padding: 1px 6px; margin-left: 6px; border-radius: 8px; font-size: 11px; font-weight: 700; }
.footnote { color: var(--muted); font-size: 11px; margin-top: 30px; padding-top: 14px; border-top: 1px solid var(--border); }
@media print { body { background: white; color: black; } section { background: white; border: 1px solid #ddd; } .nav-back, .print-bar { display: none; } }
</style>
</head>
<body>
<div class="wrap">

<div class="nav-back">
  <a href="index.html">← 返回 KOL 索引</a>
  <button onclick="window.print()">📄 列印 / 存 PDF</button>
</div>

<div class="report-header">
  <span class="domain-badge">$(HtmlEscape $domainCfg.domain_name) · $platformLabel</span>
  <h1>$(HtmlEscape $displayName) — $platformLabel 內容分析</h1>
  <div class="meta">領域：$(HtmlEscape $domainCfg.domain_id) · 報告日 $today · 資料量：$($m.totals.posts) 篇 · $($m.totals.chars) 字</div>
</div>

<div class="hero">$hero</div>

<section>
<h2><span class="num">一、</span>關鍵指標一覽 + KOL 畫像速覽</h2>
<div class="kv-grid">
  <div class="kv-card"><div class="kv-label">貼文數</div><div class="kv-value">$($m.totals.posts)</div></div>
  <div class="kv-card"><div class="kv-label">總字數</div><div class="kv-value">$($m.totals.chars)</div></div>
  <div class="kv-card"><div class="kv-label">平均字/篇</div><div class="kv-value">$($m.totals.avg_chars)</div></div>
  <div class="kv-card"><div class="kv-label">時間跨度</div><div class="kv-value">$($m.temporal.months_span) <span style="font-size:13px">月</span></div></div>
  <div class="kv-card"><div class="kv-label">活躍標籤</div><div class="kv-value small">$($m.profile_summary.activity_label)</div></div>
  <div class="kv-card"><div class="kv-label">資歷標籤</div><div class="kv-value small">$($m.profile_summary.tenure_label)</div></div>
  <div class="kv-card"><div class="kv-label">篇幅型態</div><div class="kv-value small">$($m.profile_summary.intensity_label)</div></div>
  <div class="kv-card"><div class="kv-label">主軸主題</div><div class="kv-value small">$(HtmlEscape $m.themes.top_theme)</div></div>
</div>
<div class="conclusion">$cOverview</div>
</section>

<section>
<h2><span class="num">二、</span>活躍與發文節奏</h2>
<table class="kv-table">
  <tr><td>活躍時間範圍</td><td>$($m.temporal.first_date) ~ $($m.temporal.last_date)</td></tr>
  <tr><td>活躍月份數 / 跨度</td><td>$($m.temporal.active_months_count) 個月 / $($m.temporal.months_span) 月跨度</td></tr>
  <tr><td>活躍月份占比</td><td><b>$(Pct $m.temporal.active_month_ratio)</b></td></tr>
  <tr><td>最長中斷期</td><td>$($m.temporal.max_dormant_gap_months) 個月</td></tr>
  <tr><td>峰值月份</td><td>$($m.temporal.peak_month)（$($m.temporal.peak_count) 篇）</td></tr>
  <tr><td>平均每活躍月發文</td><td>$($m.temporal.avg_posts_per_active_month) 篇</td></tr>
  <tr><td>節奏定位</td><td><b>$($m.temporal.cadence_label)</b></td></tr>
</table>
<div class="conclusion">$cCadence</div>
</section>

<section>
<h2><span class="num">三、</span>投資視角分析（這位 KOL 看什麼決定股票好壞）</h2>
<p class="muted" style="margin-top:-8px;">$lensSummary</p>

<h3 style="margin-top:18px;">3-1　五大分析面向分佈</h3>
<p class="muted" style="margin-top:-4px;">每篇貼文若提及任一面向關鍵字即計入。同一篇可被多個面向計入（一篇文章可能同時談基本面 + 籌碼面）。</p>
$lensBar

<h3 style="margin-top:18px;">3-2　常用具體指標 Top 15</h3>
<p class="muted" style="margin-top:-4px;">直接顯示原文用詞 — KOL 實際用哪些字眼判斷股票。</p>
$indicatorBar

<h3 style="margin-top:18px;">3-3　重點個股 ／ ETF 提及 Top 20</h3>
<p class="muted" style="margin-top:-4px;">該 KOL 在此平台最常提及的個股／ETF（含台股、美股、ETF、中文+代碼+英文別名比對）。</p>
$stockBar

<h3 style="margin-top:18px;">3-4　內容主題分佈（次級觀察）</h3>
<p class="muted" style="margin-top:-4px;">領域 12 大主題的命中分佈 — 觀察題材廣度的補充視角。</p>
$themeBar
<div class="conclusion" style="margin-top:8px;">$cThemes</div>

<div class="conclusion" style="margin-top:14px;">$cLens</div>
</section>

<section>
<h2><span class="num">四、</span>時序動能（月份分佈）</h2>
$spark
<div class="conclusion">$cTemporal</div>
</section>

<section>
<h2><span class="num">五、</span>貼文長度與深度</h2>
<div class="kv-grid">
  <div class="kv-card"><div class="kv-label">短文 &lt;100</div><div class="kv-value">$($m.length.short_lt100)<span style='font-size:12px;color:var(--muted)'> · $(Pct $m.length.short_share)</span></div></div>
  <div class="kv-card"><div class="kv-label">中文 100-300</div><div class="kv-value">$($m.length.medium_100_300)<span style='font-size:12px;color:var(--muted)'> · $(Pct $m.length.medium_share)</span></div></div>
  <div class="kv-card"><div class="kv-label">長文 ≥300</div><div class="kv-value">$($m.length.long_gte300)<span style='font-size:12px;color:var(--muted)'> · $(Pct $m.length.long_share)</span></div></div>
  <div class="kv-card"><div class="kv-label">平均字/篇</div><div class="kv-value">$($m.totals.avg_chars)</div></div>
</div>
<div class="conclusion">$cLength</div>
</section>

<section>
<h2><span class="num">六、</span>$platformLabel 平台特徵</h2>
$platSpecHtml
<div class="conclusion">$cPlatSpec</div>
</section>

<section>
<h2><span class="num">七、</span>Hashtag 使用與個人品牌</h2>
<div class="kv-grid">
  <div class="kv-card"><div class="kv-label">平均 hashtag/篇</div><div class="kv-value">$($m.hashtag.avg_per_post)</div></div>
  <div class="kv-card"><div class="kv-label">含 hashtag 貼文比</div><div class="kv-value">$(Pct $m.hashtag.coverage)</div></div>
  <div class="kv-card"><div class="kv-label">使用強度</div><div class="kv-value small">$($m.hashtag.intensity_label)</div></div>
  <div class="kv-card"><div class="kv-label">個人品牌占 hashtag</div><div class="kv-value">$(Pct $m.hashtag.personal_brand_share)</div></div>
</div>
<div style="margin-top:14px;">$tagChips</div>
<p class="muted" style="margin-top:8px;">紅色標籤 = 個人品牌標籤（含 KOL 名稱或暱稱）</p>
<div class="conclusion">$cHashtag</div>
</section>

<div class="footnote">
  方法論：本報告為 StockHero 自動產出之 KOL 個別分析。資料來源 = $Author 的 $platformLabel 公開貼文（書籤擷取，含解碼與日期回補）。<br>
  <b>投資視角分析（第三章）</b>：根據貼文內容直接比對五大派系（基本面／籌碼面／技術面／消息面／心理面）的關鍵字字典，每篇若提及任一字眼即計入對應面向；同一篇可被多個面向計入。「常用指標」為原始用詞排序、「個股提及」依中文名稱、4位代碼、英文別名同時比對。<br>
  <b>其他章節</b>：主題分類依領域共用 themes 定義匹配；長度分箱以字元數計；個人品牌標籤判斷依 hashtag 是否含 KOL 帳號或暱稱字串。每段結論為數值門檻判斷產出，非人工撰寫。
</div>

</div>
</body>
</html>
"@

    $outPath = "$reportDir\${platform}_report.html"
    [System.IO.File]::WriteAllText($outPath, $html, [System.Text.UTF8Encoding]::new($false))
    return $outPath
}

# ────────────────────────────────────────────────────────────
# KOL Index (links to 3 reports)
# ────────────────────────────────────────────────────────────
function Generate-KolIndex {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $cards = ''
    foreach ($cfg in @(
        @{ key='threads';   label='Threads';   color='#10b981' }
        @{ key='instagram'; label='Instagram'; color='#ec4899' }
        @{ key='facebook';  label='Facebook';  color='#3b82f6' }
    )) {
        $m = $kolDb.platforms.($cfg.key)
        $posts = if ($m) { $m.posts } else { 0 }
        $months = if ($m) { $m.months_span } else { 0 }
        $top = if ($m -and $m.top_theme) { $m.top_theme } else { '—' }
        $activity = if ($m) { $m.activity } else { '—' }
        $cards += @"
<a class="card" href="$($cfg.key)_report.html" style="--c:$($cfg.color)">
  <span class="badge" style="background:$($cfg.color)">$($cfg.label)</span>
  <h3>$($cfg.label) 內容分析</h3>
  <div class="stat"><b>$posts</b> 篇 · $months 個月跨度</div>
  <div class="stat muted">主軸：$(HtmlEscape $top) · $(HtmlEscape $activity)</div>
  <div class="open">→ 開啟報告</div>
</a>
"@
    }
    $html = @"
<!DOCTYPE html><html lang="zh-Hant"><head><meta charset="UTF-8"><title>$(HtmlEscape $displayName) — 平台分析索引</title>
<style>
body { font-family: -apple-system, "Microsoft JhengHei", sans-serif; background: #0f1419; color: #e8eaed; margin: 0; padding: 40px 30px; }
.wrap { max-width: 900px; margin: 0 auto; }
h1 { font-size: 30px; margin-bottom: 6px; }
.sub { color: #8b95a8; margin-bottom: 28px; font-size: 14px; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 18px; }
.card { background: #1a1f2e; border: 1px solid #2a3142; border-radius: 10px; padding: 22px; text-decoration: none; color: inherit; display: block; border-left: 4px solid var(--c); }
.card:hover { transform: translateY(-2px); }
.badge { display: inline-block; padding: 3px 10px; border-radius: 4px; color: white; font-weight: 700; font-size: 11px; margin-bottom: 12px; }
.card h3 { margin: 0 0 10px; font-size: 18px; }
.stat { color: var(--c); font-size: 13px; margin-bottom: 4px; }
.stat.muted { color: #8b95a8; }
.stat b { color: #fff; font-size: 16px; }
.open { color: #ff5757; font-size: 12px; font-weight: 700; margin-top: 12px; }
.back { display: inline-block; margin-bottom: 16px; color: #8b95a8; text-decoration: none; font-size: 13px; }
</style></head><body>
<div class="wrap">
<a class="back" href="../../../index.html">← 返回 $(HtmlEscape $domainCfg.domain_name) 領域</a>
<h1>$(HtmlEscape $displayName)</h1>
<p class="sub">領域：$(HtmlEscape $domainCfg.domain_name)（$(HtmlEscape $domainCfg.domain_id)） · 報告日 $today · 三平台 $($kolDb.totals_all_platforms.posts) 篇合計</p>
<div class="cards">$cards</div>
</div></body></html>
"@
    $outPath = "$reportDir\index.html"
    [System.IO.File]::WriteAllText($outPath, $html, [System.Text.UTF8Encoding]::new($false))
    return $outPath
}

# ────────────────────────────────────────────────────────────
# Domain Index (lists all KOLs in this domain) — regenerated each run
# ────────────────────────────────────────────────────────────
function Generate-DomainIndex {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $kolCards = ''
    foreach ($k in $domainCfg.kols) {
        $kolFolder = "$domainDir\kols\$($k.id)"
        $kolDbFile = "$kolFolder\database\kol_db.json"
        if (-not (Test-Path $kolDbFile)) {
            $kolCards += "<div class='card'><h3>$(HtmlEscape $k.persona)</h3><div class='stat muted'>@$(HtmlEscape $k.id)</div><div class='stat muted'>（尚未產出 database — 跑 build_kol_db.ps1）</div></div>"
            continue
        }
        $kdb = [System.IO.File]::ReadAllText($kolDbFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $totalPosts = $kdb.totals_all_platforms.posts
        $platsActive = $kdb.totals_all_platforms.platforms_with_data
        $kolCards += @"
<a class="card" href="kols/$($k.id)/reports/index.html">
  <h3>$(HtmlEscape $k.persona)</h3>
  <div class="stat muted">@$(HtmlEscape $k.id)</div>
  <div class="stat-row">
    <span><b>$totalPosts</b> 篇</span>
    <span>$platsActive / 3 平台</span>
  </div>
  <div class="open">→ 看 KOL 報告</div>
</a>
"@
    }
    $html = @"
<!DOCTYPE html><html lang="zh-Hant"><head><meta charset="UTF-8"><title>$(HtmlEscape $domainCfg.domain_name) — KOL 名單</title>
<style>
body { font-family: -apple-system, "Microsoft JhengHei", sans-serif; background: #0f1419; color: #e8eaed; margin: 0; padding: 40px 30px; }
.wrap { max-width: 1000px; margin: 0 auto; }
h1 { font-size: 32px; margin-bottom: 4px; }
.sub { color: #8b95a8; margin-bottom: 30px; font-size: 14px; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 18px; }
.card { background: #1a1f2e; border: 1px solid #2a3142; border-radius: 10px; padding: 22px; text-decoration: none; color: inherit; display: block; }
.card:hover { transform: translateY(-2px); border-color: #ff5757; }
.card h3 { margin: 0 0 6px; font-size: 20px; }
.stat { color: #8b95a8; font-size: 13px; margin-bottom: 4px; }
.stat-row { display: flex; gap: 14px; color: #e8eaed; font-size: 13px; margin: 12px 0 8px; }
.stat-row b { color: #ff5757; font-size: 18px; }
.open { color: #ff5757; font-size: 12px; font-weight: 700; margin-top: 8px; }
.intro { background: #1a1f2e; padding: 18px 22px; border-radius: 8px; margin-bottom: 28px; border-left: 4px solid #ff5757; font-size: 13px; line-height: 1.7; }
</style></head><body>
<div class="wrap">
<h1>$(HtmlEscape $domainCfg.domain_name)</h1>
<p class="sub">領域 ID：$(HtmlEscape $domainCfg.domain_id) · 更新日 $today · $($domainCfg.kols.Count) 位 KOL</p>
<div class="intro">$(HtmlEscape $domainCfg.description)</div>
<div class="cards">$kolCards</div>
</div></body></html>
"@
    $outPath = "$domainDir\index.html"
    [System.IO.File]::WriteAllText($outPath, $html, [System.Text.UTF8Encoding]::new($false))
    return $outPath
}

# ────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "===== Generating KOL Reports =====" -ForegroundColor Cyan
Write-Host "Domain : $($domainCfg.domain_id)"
Write-Host "Author : $Author ($persona)"

$r1 = Generate-PlatformReport 'threads'   'Threads'   '#10b981'
$r2 = Generate-PlatformReport 'instagram' 'Instagram' '#ec4899'
$r3 = Generate-PlatformReport 'facebook'  'Facebook'  '#3b82f6'
$kolIdx = Generate-KolIndex
$domIdx = Generate-DomainIndex

Write-Host ""
Write-Host "===== Reports generated =====" -ForegroundColor Green
if ($r1) { Write-Host "  $r1" }
if ($r2) { Write-Host "  $r2" }
if ($r3) { Write-Host "  $r3" }
Write-Host "  $kolIdx"
Write-Host "  $domIdx"
