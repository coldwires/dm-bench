<#
.SYNOPSIS
Merge N runs of one suite on one build into a single baseline. Exits non-zero if
any assertion is unstable across the runs.

.DESCRIPTION
A baseline built from one run cannot show whether the suite is stable. This is
the tool behind the rule "run three times before trusting a baseline".

MEASURE rows become the median of the runs, with the observed spread recorded in
the notes column. Median rather than mean, so one slow run cannot drag a figure.

ASSERT rows become PASS only if every run passed, FAIL only if every run failed,
and UNSTABLE if the runs disagree. An unstable assertion is a defect in the
suite, not a property of the engine, and it is reported rather than averaged
away. Averaging a verdict would hide exactly what this is built to find.

Merging across processes rather than within one is deliberate: it samples
thermal state, background load and process startup, which a within-run repeat
cannot see.

.EXAMPLE
.\merge-runs.ps1 -Runs build\fix1,build\fix2,build\fix3
.\merge-runs.ps1 -Runs build\fix1,build\fix2,build\fix3 -Out results\516.1666-windows-merged.tsv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$Runs,
    [string]$Out,
    [double]$SpreadWarnPct = 25
)

$ErrorActionPreference = "Stop"

function Read-Run([string]$path) {
    if (Test-Path $path -PathType Container) {
        $f = Get-ChildItem $path -Filter "results-*.tsv" -File | Select-Object -First 1
        if (-not $f) { throw "no results-*.tsv in $path" }
        $path = $f.FullName
    }
    if (-not (Test-Path $path)) { throw "no such file: $path" }
    $rows = [ordered]@{}
    $meta = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content $path)) {
        if ($line -match '^#\s*(\S+)\s+(.*)$') { $meta[$Matches[1]] = $Matches[2].Trim(); continue }
        if ($line -like 'kind`t*') { continue }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $p = $line -split "`t"
        if ($p.Count -lt 8) { continue }
        if ($p[0] -ne 'ASSERT' -and $p[0] -ne 'MEASURE') { continue }
        $id = $p[1]
        if (-not $rows.Contains($id)) { $order.Add($id) }
        $rows[$id] = $p
    }
    return [pscustomobject]@{ Path = $path; Rows = $rows; Meta = $meta; Order = $order }
}

$parsed = @($Runs | ForEach-Object { Read-Run $_ })
if ($parsed.Count -lt 2) { throw "merging needs at least two runs; got $($parsed.Count)" }

# A merged baseline that mixes builds would be meaningless and undetectable later.
$builds = @($parsed | ForEach-Object { "$($_.Meta['byond_version']).$($_.Meta['byond_build'])" } | Sort-Object -Unique)
$systems = @($parsed | ForEach-Object { $_.Meta['system'] } | Sort-Object -Unique)
if ($builds.Count -ne 1) { throw "runs are from different builds: $($builds -join ', ')" }
if ($systems.Count -ne 1) { throw "runs are from different systems: $($systems -join ', ')" }

$suites = @($parsed | ForEach-Object { $_.Meta['suite'] } | Sort-Object -Unique)
if ($suites.Count -ne 1) { throw "runs are from different suites: $($suites -join ', ')" }

# Process priority changes measured spread (INSTRUMENTS.md), so a merge across
# priorities would blend two measurement conditions. Runs predating the stamp
# count as Normal, which is what they were.
$prios = @($parsed | ForEach-Object { if ($_.Meta['runner_priority']) { $_.Meta['runner_priority'] } else { 'Normal' } } | Sort-Object -Unique)
if ($prios.Count -ne 1) { throw "runs are from mixed priorities: $($prios -join ', ')" }

# Two more measurement conditions that must not blend, added 2026-08-03.
#
# clock: converting a row from world.timeofday to world.tick_usage changes what
# its resolution column means and moved two values about 15%, so a merge across
# the conversion would average two instruments. This is also what makes a
# cross-OS comparison safe downstream: gen-site.ps1 refuses to compare two
# baselines whose clocks disagree, and it can only ask because the merge
# records the answer.
#
# stdout_binding: how DreamDaemon's stdout is bound changes measured world.log
# cost by about 20x (INSTRUMENTS.md). Runs predating the stamp record nothing
# rather than guessing, and unstamped runs merge with each other as before.
$conditions = @{}
#
# source_commit: twelve Linux runs were binned on 2026-08-02 for having been
# built from a checkout two commits behind, and every one of them reported 52
# assertions and 0 failed. Runs from different source cannot be one baseline.
foreach ($key in @('clock', 'stdout_binding', 'source_commit')) {
    $vals = @($parsed | ForEach-Object { $_.Meta[$key] } | Where-Object { $_ } | Sort-Object -Unique)
    $stamped = @($parsed | Where-Object { $_.Meta[$key] }).Count
    if ($vals.Count -gt 1) { throw "runs disagree on ${key}: $($vals -join ', ')" }
    if ($vals.Count -eq 1 -and $stamped -ne $parsed.Count) {
        throw "${key} is stamped in $stamped of $($parsed.Count) runs; an unstamped run cannot be assumed to match '$($vals[0])'"
    }
    if ($vals.Count -eq 1) { $conditions[$key] = $vals[0] }
}

# A run that died early would otherwise contribute its prefix and look merged.
$counts = @($parsed | ForEach-Object { $_.Rows.Count } | Sort-Object -Unique)
if ($counts.Count -ne 1) {
    $detail = ($parsed | ForEach-Object { "$(Split-Path $_.Path -Leaf)=$($_.Rows.Count)" }) -join ", "
    throw "runs have different row counts, one is incomplete: $detail"
}

function Median([double[]]$v) {
    $s = @($v | Sort-Object)
    $n = $s.Count
    if ($n % 2 -eq 1) { return $s[[math]::Floor($n / 2)] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

$build = $builds[0]; $system = $systems[0]
# This script lives in tools/; results/ is at the repository root, one level up.
if (-not $Out) { $Out = Join-Path (Split-Path $PSScriptRoot -Parent) ("results\{0}-{1}-merged.tsv" -f $build, $system) }
$outDir = Split-Path $Out -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# suite`t$($suites[0])")
$lines.Add("# byond_version`t$($parsed[0].Meta['byond_version'])")
$lines.Add("# byond_build`t$($parsed[0].Meta['byond_build'])")
$lines.Add("# system`t$system")
$lines.Add("# runner_priority`t$($prios[0])")
foreach ($key in @('clock', 'stdout_binding', 'source_commit')) {
    if ($conditions.ContainsKey($key)) { $lines.Add("# $key`t$($conditions[$key])") }
}
$lines.Add("# merged_runs`t$($parsed.Count)")
# Each run writes the same filename inside its own directory, so the leaf alone
# does not identify which run contributed what. Keep the parent.
$lines.Add("# merged_from`t$(($parsed | ForEach-Object { Join-Path (Split-Path (Split-Path $_.Path -Parent) -Leaf) (Split-Path $_.Path -Leaf) }) -join ' ')")
$lines.Add("kind`tid`tcategory`tname`tvalue`tunit`texpected`tstatus`tres`tnotes")

$passed = 0; $failed = 0; $unstable = 0; $measured = 0; $wide = 0
$unstableIds = New-Object System.Collections.Generic.List[string]
$wideIds = New-Object System.Collections.Generic.List[string]

foreach ($id in $parsed[0].Order) {
    # Unary comma: ForEach-Object unrolls arrays, which would flatten three rows
    # into one list of fields and make every row look like it disagreed with
    # itself. This produced "129 unstable" on first run.
    $all = @($parsed | ForEach-Object { ,$_.Rows[$id] })
    if ($all.Count -ne $parsed.Count) { continue }
    $kind = $all[0][0]

    if ($kind -eq 'ASSERT') {
        $verdicts = @($all | ForEach-Object { $_[7] } | Sort-Object -Unique)
        if ($verdicts.Count -gt 1) {
            $status = 'UNSTABLE'; $unstable++; $unstableIds.Add($id)
        } else {
            $status = $verdicts[0]
            if ($status -eq 'PASS') { $passed++ } else { $failed++ }
        }
        $seen = ($all | ForEach-Object { $_[7] }) -join '/'
        $note = "n=$($all.Count) $seen"
        if ($all[0].Count -ge 10 -and $all[0][9]) { $note = "$note; $($all[0][9])" }
        $lines.Add(($kind, $id, $all[0][2], $all[0][3], $all[0][4], '', $all[0][6], $status, '', $note) -join "`t")
        continue
    }

    $measured++
    $nums = @()
    $numeric = $true
    foreach ($r in $all) {
        $d = 0.0
        if ([double]::TryParse($r[4], [ref]$d)) { $nums += $d } else { $numeric = $false; break }
    }
    if (-not $numeric) {
        $vals = @($all | ForEach-Object { $_[4] } | Sort-Object -Unique)
        $status = ''
        if ($vals.Count -gt 1) { $status = 'UNSTABLE'; $unstable++; $unstableIds.Add($id) }
        $lines.Add(($kind, $id, $all[0][2], $all[0][3], $all[0][4], $all[0][5], '', $status, '', "n=$($all.Count)") -join "`t")
        continue
    }

    $med = Median $nums
    $lo = ($nums | Measure-Object -Minimum).Minimum
    $hi = ($nums | Measure-Object -Maximum).Maximum
    $spread = 0.0
    if ($med -ne 0) { $spread = (($hi - $lo) / [math]::Abs($med)) * 100 }
    $shown = if ([math]::Abs($med) -ge 10) { [math]::Round($med, 1) } else { [math]::Round($med, 2) }

    # Flags from the runs survive the merge. A row flagged in any run is not
    # evidence, and the merge must not launder that away.
    $flags = @($all | ForEach-Object { if ($_.Count -ge 10) { $_[9] } } |
              Where-Object { $_ -match 'LOW_RESOLUTION|SUBTRACTION_NOISE|BELOW_BASELINE|BASELINE_HEAVY' } |
              ForEach-Object { ($_ -split ';')[0].Trim() } | Sort-Object -Unique)
    $note = "n=$($all.Count) min=$([math]::Round($lo,2)) max=$([math]::Round($hi,2)) spread=$([math]::Round($spread,0))%"
    if ($spread -gt $SpreadWarnPct) { $note = "WIDE_SPREAD; $note"; $wide++; $wideIds.Add($id) }
    if ($flags) { $note = "$(($flags -join '; ')); $note" }

    $lines.Add(($kind, $id, $all[0][2], $all[0][3], $shown, $all[0][5], '', '', '', $note) -join "`t")
}

$lines.Add("")
$lines.Add("# passed`t$passed")
$lines.Add("# failed`t$failed")
$lines.Add("# unstable`t$unstable")
$lines.Add("# measured`t$measured")
$lines.Add("# wide_spread`t$wide")
$lines.Add("# result`t$(if ($failed -or $unstable) { 'FAIL' } else { 'PASS' })")

# PS 5.1's -Encoding utf8 writes a BOM, which lands in the first cell of the
# first row and breaks anything matching on '^#'. Write UTF-8 without one.
$absOut = Join-Path (Resolve-Path -LiteralPath (Split-Path $Out -Parent)).Path (Split-Path $Out -Leaf)
[System.IO.File]::WriteAllLines($absOut, $lines, (New-Object System.Text.UTF8Encoding($false)))
"merged $($parsed.Count) runs of $build/$system -> $Out"
"  passed $passed   failed $failed   unstable $unstable"
"  measured $measured   wide spread (>$SpreadWarnPct%) $wide"
if ($unstableIds.Count) {
    ""
    "unstable assertions. These are suite defects, not engine results:"
    foreach ($i in $unstableIds) { "  $i" }
}
if ($wideIds.Count) {
    ""
    "rows varying more than $SpreadWarnPct% across runs:"
    foreach ($i in ($wideIds | Select-Object -First 30)) { "  $i" }
    if ($wideIds.Count -gt 30) { "  ... and $($wideIds.Count - 30) more" }
}
if ($failed -or $unstable) { exit 1 }
exit 0
