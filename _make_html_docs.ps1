# Convert .md docs to .html for reliable local browser viewing
# (BOM alone doesn't always work — explicit <meta charset="UTF-8"> in HTML always does)
param([switch]$Verbose)

$base = $PSScriptRoot

function Convert-MdToHtml {
    param([string]$mdPath, [string]$htmlPath, [string]$title)

    $md = [System.IO.File]::ReadAllText($mdPath, [System.Text.Encoding]::UTF8)

    # Normalize line endings
    $md = $md -replace "`r`n", "`n"

    $html = New-Object System.Text.StringBuilder
    $lines = $md -split "`n"
    $i = 0
    $inCode = $false
    $inList = $false
    $inTable = $false
    $tableHeaderDone = $false

    while ($i -lt $lines.Count) {
        $line = $lines[$i]

        # Code block ```lang ... ```
        if ($line -match '^```') {
            if ($inCode) {
                [void]$html.AppendLine('</code></pre>')
                $inCode = $false
            } else {
                $lang = ($line -replace '^```', '').Trim()
                [void]$html.AppendLine("<pre><code class=`"lang-$lang`">")
                $inCode = $true
            }
            $i++; continue
        }
        if ($inCode) {
            [void]$html.AppendLine([System.Web.HttpUtility]::HtmlEncode($line))
            $i++; continue
        }

        # Close list if we leave it
        if ($inList -and $line -notmatch '^\s*[-*]\s' -and $line -notmatch '^\s*\d+\.\s' -and $line.Trim() -ne '') {
            [void]$html.AppendLine('</ul>')
            $inList = $false
        }

        # Close table if we leave it
        if ($inTable -and $line -notmatch '^\|') {
            [void]$html.AppendLine('</tbody></table>')
            $inTable = $false
            $tableHeaderDone = $false
        }

        # Headings
        if ($line -match '^# (.*)') {
            [void]$html.AppendLine("<h1>$(InlineFormat $matches[1])</h1>")
        } elseif ($line -match '^## (.*)') {
            [void]$html.AppendLine("<h2>$(InlineFormat $matches[1])</h2>")
        } elseif ($line -match '^### (.*)') {
            [void]$html.AppendLine("<h3>$(InlineFormat $matches[1])</h3>")
        } elseif ($line -match '^#### (.*)') {
            [void]$html.AppendLine("<h4>$(InlineFormat $matches[1])</h4>")
        }
        # Horizontal rule
        elseif ($line -match '^---+$') {
            [void]$html.AppendLine('<hr>')
        }
        # Table
        elseif ($line -match '^\|') {
            if (-not $inTable) {
                [void]$html.AppendLine('<table>')
                $inTable = $true
                $tableHeaderDone = $false
            }
            # Skip separator rows like |---|---|
            if ($line -match '^\|[\s\-:|]+\|?\s*$') {
                if (-not $tableHeaderDone) {
                    [void]$html.AppendLine('</thead><tbody>')
                    $tableHeaderDone = $true
                }
            } else {
                $cells = ($line.Trim().TrimStart('|').TrimEnd('|') -split '\|') | ForEach-Object { $_.Trim() }
                if (-not $tableHeaderDone) {
                    [void]$html.AppendLine('<thead><tr>')
                    foreach ($c in $cells) { [void]$html.AppendLine("<th>$(InlineFormat $c)</th>") }
                    [void]$html.AppendLine('</tr>')
                } else {
                    [void]$html.AppendLine('<tr>')
                    foreach ($c in $cells) { [void]$html.AppendLine("<td>$(InlineFormat $c)</td>") }
                    [void]$html.AppendLine('</tr>')
                }
            }
        }
        # Unordered list
        elseif ($line -match '^\s*[-*]\s+(.+)') {
            if (-not $inList) {
                [void]$html.AppendLine('<ul>')
                $inList = $true
            }
            [void]$html.AppendLine("<li>$(InlineFormat $matches[1])</li>")
        }
        # Ordered list
        elseif ($line -match '^\s*(\d+)\.\s+(.+)') {
            if (-not $inList) {
                [void]$html.AppendLine('<ol>')
                $inList = $true
            }
            [void]$html.AppendLine("<li>$(InlineFormat $matches[2])</li>")
        }
        # Empty line
        elseif ($line.Trim() -eq '') {
            [void]$html.AppendLine('')
        }
        # Normal paragraph
        else {
            [void]$html.AppendLine("<p>$(InlineFormat $line)</p>")
        }
        $i++
    }

    # Close any open blocks
    if ($inCode) { [void]$html.AppendLine('</code></pre>') }
    if ($inList) { [void]$html.AppendLine('</ul>') }
    if ($inTable) { [void]$html.AppendLine('</tbody></table>') }

    $body = $html.ToString()

    $template = @"
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title — StockHero Toolkit</title>
<style>
* { box-sizing: border-box; }
body { font-family: -apple-system, "Segoe UI", "Microsoft JhengHei", "PingFang TC", sans-serif; background: #0f1419; color: #e8eaed; margin: 0; padding: 40px 20px; line-height: 1.7; }
.wrap { max-width: 820px; margin: 0 auto; }
h1 { font-size: 32px; border-bottom: 3px solid #ff5757; padding-bottom: 12px; color: #fff; }
h2 { font-size: 22px; color: #fff; border-left: 4px solid #ff5757; padding-left: 12px; margin-top: 36px; }
h3 { font-size: 17px; color: #ffd24d; margin-top: 24px; }
h4 { font-size: 15px; color: #ffd24d; margin-top: 16px; }
p { color: #d1d5db; margin: 8px 0; }
ul, ol { color: #d1d5db; padding-left: 24px; }
li { margin: 4px 0; }
code { background: rgba(255,255,255,0.08); padding: 2px 6px; border-radius: 3px; font-size: 13px; color: #facc15; font-family: Consolas, Monaco, monospace; }
pre { background: #1a1f2e; border: 1px solid #2a3142; padding: 14px 18px; border-radius: 6px; overflow-x: auto; font-size: 13px; }
pre code { background: transparent; padding: 0; color: #e8eaed; }
table { width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 13px; }
th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #2a3142; }
th { color: #ffd24d; font-weight: 600; background: rgba(255,255,255,0.03); }
td { color: #c8cdd6; }
hr { border: none; border-top: 1px solid #2a3142; margin: 32px 0; }
a { color: #ff7070; text-decoration: none; }
a:hover { text-decoration: underline; }
strong, b { color: #fff; }
blockquote { border-left: 3px solid #ffd24d; padding-left: 14px; color: #c8cdd6; margin: 12px 0; }
.back { display: inline-block; margin-bottom: 20px; color: #8b95a8; }
</style>
</head>
<body>
<div class="wrap">
<a class="back" href="index.html">← 回首頁</a>
$body
</div>
</body>
</html>
"@
    [System.IO.File]::WriteAllText($htmlPath, $template, [System.Text.UTF8Encoding]::new($true))
}

function InlineFormat([string]$s) {
    if ($null -eq $s) { return '' }
    # Process in order: code first (to protect from other rules), then bold/italic, then links
    $s = [regex]::Replace($s, '`([^`]+)`', { param($m) "<code>$([System.Web.HttpUtility]::HtmlEncode($m.Groups[1].Value))</code>" })
    $s = [regex]::Replace($s, '\*\*([^*]+)\*\*', '<b>$1</b>')
    $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
    return $s
}

# Need System.Web for HtmlEncode
Add-Type -AssemblyName System.Web

Convert-MdToHtml -mdPath "$base\QUICKSTART.md" -htmlPath "$base\QUICKSTART.html" -title "5 分鐘上手指南"
"Generated: QUICKSTART.html"

Convert-MdToHtml -mdPath "$base\README.md" -htmlPath "$base\README.html" -title "README"
"Generated: README.html"
