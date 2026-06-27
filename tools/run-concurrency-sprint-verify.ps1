# Contract-driven concurrency sprint verification. Exits non-zero on failure; writes scratch evidence on pass.
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ScratchDir = $env:CONCURRENCY_SPRINT_SCRATCH,
    [string]$FixtureDir = '',
    [switch]$SkipUnittest,
    [switch]$SkipDryRun
)

$ErrorActionPreference = 'Stop'
if (-not $ScratchDir) {
    $ScratchDir = Join-Path $env:TEMP 'grok-goal-8c69e504b531\implementer'
}
New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null

$contractPath = Join-Path $PSScriptRoot 'concurrency-sprint-contract.json'
if (-not (Test-Path $contractPath)) {
    Write-Error "Missing contract: $contractPath"
    exit 2
}
$contract = Get-Content $contractPath -Raw | ConvertFrom-Json

function Fail([string]$msg) {
    Write-Host "CONTRACT FAIL: $msg" -ForegroundColor Red
    @(
        'CONCURRENCY SPRINT VERIFICATION FAILED',
        "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Contract: $contractPath",
        "Reason: $msg"
    ) | Set-Content (Join-Path $ScratchDir 'concurrency-sprint-verify-fail.txt') -Encoding UTF8
    exit 1
}

function Get-GateValue([string]$Text, [string]$Key) {
    if ($Text -match "(?m)^${Key}=([^\s]+)") { return $Matches[1] }
    return $null
}

$evidenceRoot = if ($FixtureDir) { $FixtureDir } else { $ScratchDir }
$gateParse = New-Object System.Text.StringBuilder
[void]$gateParse.AppendLine('GATE PARSE')
[void]$gateParse.AppendLine("EvidenceRoot: $evidenceRoot")
[void]$gateParse.AppendLine("FixtureMode: $([bool]$FixtureDir)")
[void]$gateParse.AppendLine('')

foreach ($slot in $contract.gate_evidence_files.PSObject.Properties) {
    $rel = $slot.Value
    $full = Join-Path $evidenceRoot $rel
    if (-not (Test-Path $full)) {
        Fail "Missing gate evidence: $rel (expected under $evidenceRoot)"
    }
    [void]$gateParse.AppendLine("OK present: $rel")
}
$gateParse.ToString() | Set-Content (Join-Path $ScratchDir 'gate-parse.txt') -Encoding UTF8

$stardustTxt = Get-Content (Join-Path $evidenceRoot $contract.gate_evidence_files.h1_stardust) -Raw
$laptopTxt = Get-Content (Join-Path $evidenceRoot $contract.gate_evidence_files.h1_laptop) -Raw
$h3Txt = Get-Content (Join-Path $evidenceRoot $contract.gate_evidence_files.h3_signal) -Raw
$intTxt = Get-Content (Join-Path $evidenceRoot $contract.gate_evidence_files.integration) -Raw

$h1sCv = [double](Get-GateValue $stardustTxt 'H1_CV')
$h1sPass = Get-GateValue $stardustTxt 'H1_PASS'
$h1lCv = [double](Get-GateValue $laptopTxt 'H1_CV')
$h1lPass = Get-GateValue $laptopTxt 'H1_PASS'
$h2Delta = [double](Get-GateValue $stardustTxt 'H2_DELTA_PCT')
$h2Pass = Get-GateValue $stardustTxt 'H2_PASS'
$h3Delta = [double](Get-GateValue $h3Txt 'H3_DELTA_PCT')
$h3Pass = Get-GateValue $h3Txt 'H3_PASS'

if ($h1sPass -ne 'yes' -or $h1lPass -ne 'yes') { Fail "H1_PASS not yes on both machines (stardust=$h1sPass laptop=$h1lPass)" }
if ($h1sCv -gt $contract.gates.h1_cv_max -or $h1lCv -gt $contract.gates.h1_cv_max) {
    Fail "H1 CV exceeds max $($contract.gates.h1_cv_max) (stardust=$h1sCv laptop=$h1lCv)"
}
if ($h2Pass -ne 'yes' -or $h2Delta -gt $contract.gates.h2_delta_pct_max) {
    Fail "H2 failed (pass=$h2Pass delta=$h2Delta max=$($contract.gates.h2_delta_pct_max))"
}
$expectH3Pass = [bool]$contract.gates.h3_must_pass
$actualH3Pass = ($h3Pass -eq 'yes')
if ($expectH3Pass -ne $actualH3Pass) {
    Fail "H3 pass mismatch expected=$expectH3Pass actual=$actualH3Pass (delta=$h3Delta)"
}
if ($actualH3Pass -and $h3Delta -lt $contract.gates.h3_delta_pct_min) {
    Fail "H3 marked pass but delta $h3Delta < min $($contract.gates.h3_delta_pct_min)"
}
if ($intTxt -notmatch 'weight 0') { Fail 'integration-decision.txt must document weight 0' }

foreach ($rel in $contract.required_present_cursiveos) {
    if (-not (Test-Path (Join-Path $RepoRoot $rel))) { Fail "Required present missing: $rel" }
}

$harness = Get-Content (Join-Path $RepoRoot 'cursiveos-full-test-v1.4.sh') -Raw
if ($harness -notmatch 'observe-only' -or $harness -notmatch '"weight": 0') {
    Fail 'cursiveos-full-test-v1.4.sh missing observe-only weight 0 concurrency hook'
}

$researchRoot = Resolve-Path (Join-Path $RepoRoot $contract.cursiveresearch_repo)
$planPath = Join-Path $researchRoot 'experiments/concurrency-inference-sensor-noise-floor-plan.md'
if (-not (Test-Path $planPath)) { Fail "Missing experiment plan: $planPath" }
$planTxt = Get-Content $planPath -Raw
if ($planTxt -notmatch [regex]::Escape($contract.gates.experiment_status_contains)) {
    Fail "Experiment plan missing status $($contract.gates.experiment_status_contains)"
}

if (-not $SkipDryRun) {
    Push-Location $RepoRoot
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $dryLines = & bash benchmarks/benchmark-inference-concurrency-v0.1.sh --dry-run 4 mistral 2>&1
    $ErrorActionPreference = $prevEap
    Pop-Location
    $dryText = ($dryLines | Out-String).Trim()
    $dryText | Set-Content (Join-Path $ScratchDir 'dry-run-verify.txt') -Encoding UTF8
    if ($dryText -notmatch 'model=mistral') { Fail '--dry-run 4 mistral must show model=mistral' }
}

if (-not $SkipUnittest) {
    Push-Location $RepoRoot
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $utLines = & python -m unittest tests.test_benchmark_concurrency 2>&1
    $utExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    Pop-Location
    $utText = ($utLines | Out-String).Trim()
    $utText | Set-Content (Join-Path $ScratchDir 'unittest-verify.txt') -Encoding UTF8
    if ($utText -match '(?m)^FAILED \(') { Fail "unittest failed: $utText" }
    if ($utText -notmatch '(?m)^OK\s*$') { Fail "unittest summary missing OK: $utText" }
}

function Get-DiffNames([string]$Root, [string]$Baseline) {
    Push-Location $Root
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $names = @(git diff --name-only "${Baseline}..HEAD" 2>$null)
    $ErrorActionPreference = $prev
    Pop-Location
    return $names
}

$osDiff = Get-DiffNames $RepoRoot $contract.cursiveos_baseline
$rsDiff = Get-DiffNames $researchRoot $contract.cursiveresearch_baseline

foreach ($req in $contract.required_modified_cursiveos) {
    if ($osDiff -notcontains $req) { Fail "CursiveOS diff missing required path: $req" }
}
foreach ($req in $contract.required_modified_research) {
    if ($rsDiff -notcontains $req) { Fail "CursiveResearch diff missing required path: $req" }
}
foreach ($ban in $contract.must_not_modify) {
    if ($osDiff -contains $ban) { Fail "Must not modify: $ban" }
}

$scriptPath = $PSCommandPath
$scriptHash = (Get-FileHash $scriptPath -Algorithm SHA256).Hash
$contractHash = (Get-FileHash $contractPath -Algorithm SHA256).Hash

Push-Location $RepoRoot
$osHead = git rev-parse HEAD
Pop-Location
Push-Location $researchRoot
$rsHead = git rev-parse HEAD
Pop-Location

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('CHANGED_FILES EVIDENCE - concurrency sprint')
[void]$sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('INPUT RECORDS (verification harness):')
[void]$sb.AppendLine("  ScriptPath: $scriptPath")
[void]$sb.AppendLine("  ScriptSHA256: $scriptHash")
[void]$sb.AppendLine("  ContractPath: $contractPath")
[void]$sb.AppendLine("  ContractSHA256: $contractHash")
[void]$sb.AppendLine("  CursiveOS_HEAD: $osHead")
[void]$sb.AppendLine("  CursiveResearch_HEAD: $rsHead")
[void]$sb.AppendLine("  ScratchDir: $ScratchDir")
[void]$sb.AppendLine("  EvidenceRoot: $evidenceRoot")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('GATE SUMMARY:')
[void]$sb.AppendLine("  H1 Stardust CV=$h1sCv PASS=$h1sPass")
[void]$sb.AppendLine("  H1 Laptop CV=$h1lCv PASS=$h1lPass")
[void]$sb.AppendLine("  H2 delta_pct=$h2Delta PASS=$h2Pass")
[void]$sb.AppendLine("  H3 delta_pct=$h3Delta PASS=$h3Pass (must_pass=$expectH3Pass)")
[void]$sb.AppendLine("  Integration: weight $($contract.gates.fitness_weight)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("MODIFIED FILES (git diff --name-status $($contract.cursiveos_baseline)..HEAD) CursiveOS:")
Push-Location $RepoRoot
git diff --name-status "$($contract.cursiveos_baseline)..HEAD" | ForEach-Object { [void]$sb.AppendLine("  $_") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine("MODIFIED FILES (git diff --name-status $($contract.cursiveresearch_baseline)..HEAD) CursiveResearch:")
Pop-Location
Push-Location $researchRoot
git diff --name-status "$($contract.cursiveresearch_baseline)..HEAD" | ForEach-Object { [void]$sb.AppendLine("  $_") }
Pop-Location
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Uncommitted CursiveOS:')
Push-Location $RepoRoot
$u = git status --porcelain 2>$null
if ($u) { $u | ForEach-Object { [void]$sb.AppendLine("  $_") } } else { [void]$sb.AppendLine('  (clean)') }
Pop-Location

$sb.ToString() | Set-Content (Join-Path $ScratchDir 'changed-files-evidence.txt') -Encoding UTF8

@(
    'CONCURRENCY SPRINT VERIFICATION PASSED',
    "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "H1 stardust_cv=$h1sCv laptop_cv=$h1lCv",
    "H2 delta_pct=$h2Delta",
    "H3 delta_pct=$h3Delta pass=$h3Pass",
    "CursiveOS_HEAD=$osHead",
    "CursiveResearch_HEAD=$rsHead"
) | Set-Content (Join-Path $ScratchDir 'concurrency-sprint-verify-pass.txt') -Encoding UTF8

Write-Host 'CONCURRENCY SPRINT VERIFICATION PASSED' -ForegroundColor Green
exit 0