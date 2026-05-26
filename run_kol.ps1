# ============================================================
# StockHero - End-to-End Pipeline Wrapper
# ============================================================
# Runs the post-scrape pipeline for one KOL.
# Assumes you have already run save_clipboard.ps1 for each platform.
#
# Daily refresh (existing KOL):
#   .\run_kol.ps1 -Author zhao1945
#
# First-time onboard (new KOL, generates profile):
#   .\run_kol.ps1 -Author newkol -Discover
#   # ↑ pauses after discover so you can edit kol_profile_newkol.json
#
# Re-discover (rebuild profile, careful — wipes manual edits if -Force):
#   .\run_kol.ps1 -Author zhao1945 -Discover -Force
#
# CI / automation (no human prompt):
#   .\run_kol.ps1 -Author zhao1945 -Discover -NoPause
#
# Include monetization analysis (Taiwan finance KOL flavor):
#   .\run_kol.ps1 -Author zhao1945 -Monetization
#   # ↑ Section 5 (競品/護城河/變現建議) 含 placeholder 待人工填寫
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Author,

    [string]$Domain = '',

    # Run discover_kol_profile after merge.
    # Default OFF (daily refresh assumes profile already exists).
    [switch]$Discover,

    # When -Discover is set, pass -Force to discover_kol_profile
    # (overwrite active profile instead of writing _draft.json).
    [switch]$Force,

    # recover_dates fetch budget per run
    [int]$MaxFetch = 200,

    # Skip the human review pause after discover (for automation)
    [switch]$NoPause,

    # Also run analyze_monetization.ps1 to produce monetization_report.html.
    # Default OFF — the script's Section 5 (competitor positioning) is
    # Taiwan-finance-KOL flavored and requires manual customization for other domains.
    [switch]$Monetization
)

$base = $PSScriptRoot
$ErrorActionPreference = 'Stop'

# Auto-detect domain
if (-not $Domain) {
    $allDomains = @(Get-ChildItem "$base\domains" -Directory -ErrorAction SilentlyContinue)
    if ($allDomains.Count -eq 1) { $Domain = $allDomains[0].Name; Write-Host "Auto-detected domain: $Domain" -ForegroundColor DarkCyan }
    elseif ($allDomains.Count -eq 0) { Write-Host "ERROR: no domains found"; exit 1 }
    else { Write-Host "ERROR: multiple domains exist, use -Domain"; exit 1 }
}

function Step($n, $total, $name) {
    Write-Host ""
    Write-Host "[$n/$total] $name" -ForegroundColor Cyan
    Write-Host ("─" * 60) -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "===== StockHero Pipeline =====" -ForegroundColor Cyan
Write-Host "Author : $Author"
Write-Host "Mode   : $(if ($Discover) { 'onboard / re-discover' } else { 'daily refresh' })"
Write-Host ""

# === Sanity: any data for this author in the domain folder? ===
$kolDir = "$base\domains\$Domain\kols\$Author"
if (-not (Test-Path $kolDir)) {
    Write-Host "ERROR: KOL folder not found: $kolDir" -ForegroundColor Red
    Write-Host "Add the KOL to domain.json and run save_clipboard.ps1 first."
    exit 1
}
$candidates = @(
    "raw\instagram_main.json", "raw\instagram_reels.json", "raw\threads.json", "raw\facebook.json", "raw\facebook_videos.json",
    "canonical\instagram.json", "canonical\threads.json", "canonical\facebook.json"
)
$found = @($candidates | Where-Object { Test-Path "$kolDir\$_" })
if ($found.Count -eq 0) {
    Write-Host "ERROR: no data files in $kolDir. Run save_clipboard.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "Existing data files:"
foreach ($f in $found) {
    $sz = [math]::Round((Get-Item "$kolDir\$f").Length / 1024, 1)
    Write-Host "  $f ($sz KB)"
}

$totalSteps = if ($Discover) { 4 } else { 3 }
$step = 0

# === Step: recover_dates ===
$step++
Step $step $totalSteps "recover_dates  (decode entities + fill dates)"
& "$base\recover_dates.ps1" -Domain $Domain -Author $Author -MaxFetch $MaxFetch
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Host "recover_dates failed (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1
}

# === Step: merge canonical ===
$step++
Step $step $totalSteps "merge_ig  (content-hash dedup + date upgrade)"
& "$base\merge_ig.ps1" -Domain $Domain -Author $Author
& "$base\merge_threads.ps1" -Domain $Domain -Author $Author -ErrorAction SilentlyContinue
& "$base\merge_fb.ps1" -Domain $Domain -Author $Author -ErrorAction SilentlyContinue
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Host "merge_ig failed (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1
}

# === Step: discover (optional) ===
if ($Discover) {
    $step++
    Step $step $totalSteps "discover_kol_profile  (TF-IDF + era split)"
    if ($Force) {
        & "$base\discover_kol_profile.ps1" -Domain $Domain -Author $Author -Force
    } else {
        & "$base\discover_kol_profile.ps1" -Domain $Domain -Author $Author
    }

    $activeProfile = "$base\domains\$Domain\kols\$Author\kol_profile.json"
    $draftProfile  = "$base\domains\$Domain\kols\$Author\kol_profile_draft.json"
    $editTarget = if (Test-Path $draftProfile) { $draftProfile } else { $activeProfile }

    Write-Host ""
    Write-Host ">>> REVIEW CHECKPOINT <<<" -ForegroundColor Magenta
    Write-Host "Edit: $editTarget" -ForegroundColor Yellow
    Write-Host "  1) Confirm 'persona' (公開暱稱)"
    Write-Host "  2) Rename 'eras' labels (前期/後期 → 真實階段名)"
    Write-Host "  3) Remove boilerplate from 'discovered_terms'"
    Write-Host "  4) Non-financial KOL: set philosophy_keywords / anti_scam_patterns / type_rules / themes = []"
    if ($editTarget -eq $draftProfile) {
        Write-Host ""
        Write-Host "NOTE: a draft was created (active profile already exists)." -ForegroundColor Yellow
        Write-Host "      Diff/merge draft into active manually, then re-run without -Discover."
        Write-Host "      (Pipeline will stop here; rerun later: .\run_kol.ps1 -Author $Author)"
        exit 0
    }

    if (-not $NoPause) {
        Write-Host ""
        Read-Host "Press Enter when profile is ready to analyze"
    } else {
        Write-Host "(-NoPause set, proceeding to analyze immediately)"
    }
}

# === Step: build DB + generate reports ===
$step++
Step $step $totalSteps "build_kol_db + generate_kol_reports"
& "$base\build_kol_db.ps1" -Domain $Domain -Author $Author
& "$base\generate_kol_reports.ps1" -Domain $Domain -Author $Author
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Host "report generation failed (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1
}

# === Step (optional): monetization analysis ===
if ($Monetization) {
    Step ($step + 1) ($totalSteps + 1) "analyze_monetization (Taiwan-finance template)"
    & "$base\analyze_monetization.ps1" -Domain $Domain -Author $Author
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "monetization analysis failed (exit $LASTEXITCODE)" -ForegroundColor Yellow
        Write-Host "(pipeline still considered complete — monetization is supplementary)"
    }
}

Write-Host ""
Write-Host "===== Pipeline complete =====" -ForegroundColor Green
Write-Host "Database: domains\$Domain\kols\$Author\database\"
Write-Host "Reports : domains\$Domain\kols\$Author\reports\"
if ($Monetization) {
    Write-Host "        + monetization_report.html (Section 5 待人工填寫 placeholder)"
}
Write-Host "Domain  : domains\$Domain\index.html"
