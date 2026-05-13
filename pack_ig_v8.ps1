# Build v8 bookmarklet URL + update install page
$base = $PSScriptRoot
$src  = [System.IO.File]::ReadAllText("$base\instagram-bookmarklet-v8.js", [System.Text.Encoding]::UTF8)

# Strip block comments
$srcMin = [regex]::Replace($src, '(?s)/\*.*?\*/', '')
# Strip single-line // comments at start of line
$srcMin = [regex]::Replace($srcMin, '(?m)^\s*//.*$', '')
# Collapse blank lines
$srcMin = [regex]::Replace($srcMin, '(?m)^\s*\r?\n', '')

$encoded = [uri]::EscapeDataString($srcMin)
$bookmarklet = "javascript:$encoded"

Write-Host "Source bytes:    $($src.Length)"
Write-Host "Minified bytes:  $($srcMin.Length)"
Write-Host "Encoded bytes:   $($encoded.Length)"
Write-Host "Bookmarklet URL: $($bookmarklet.Substring(0, [Math]::Min(150, $bookmarklet.Length)))..."

[System.IO.File]::WriteAllText("$base\instagram-bookmarklet-v8.url.txt", $bookmarklet, [System.Text.UTF8Encoding]::new($false))

# Update install page: replace the IG bookmark href + label
$installPath = "$base\install-bookmarklets.html"
$html = [System.IO.File]::ReadAllText($installPath, [System.Text.Encoding]::UTF8)

$marker = '<a class="bm ig" href="'
$idx = $html.IndexOf($marker)
if ($idx -lt 0) { Write-Host "ERROR: anchor not found" -ForegroundColor Red; exit 1 }
$startHref = $idx + $marker.Length
$endHref = $html.IndexOf('"', $startHref)
$oldHref = $html.Substring($startHref, $endHref - $startHref)
Write-Host "Old IG bookmark href len: $($oldHref.Length)"

$bookmarkletForHtml = $bookmarklet.Replace('&', '&amp;')
$newHtml = $html.Substring(0, $startHref) + $bookmarkletForHtml + $html.Substring($endHref)

# Update label
$labelStart = $newHtml.IndexOf('>', $startHref + $bookmarkletForHtml.Length) + 1
$labelEnd = $newHtml.IndexOf('</a>', $labelStart)
if ($labelEnd -gt $labelStart) {
    $newHtml = $newHtml.Substring(0, $labelStart) + '📸 IG 擷取 v8.1' + $newHtml.Substring($labelEnd)
}

[System.IO.File]::WriteAllText($installPath, $newHtml, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated: $installPath"
