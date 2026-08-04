<#
.SYNOPSIS
Compile and run a bench suite against one or more standalone BYOND builds.

.DESCRIPTION
Standalone builds live in byond-standalones\<label>\bin\. Nothing is installed
and the system BYOND is never used, so the build under test is always explicit.

The folder label is treated as a hint, not as truth. Every build is queried for
the version its binaries actually report, and a mismatch is a hard error. The
suite then names its own output file after the engine that produced it, so a
result cannot be filed under the wrong build by hand.

.EXAMPLE
.\run.ps1 -List
.\run.ps1 -Suite suite_del
.\run.ps1 -Suite suite -Version 516.1685
.\run.ps1 -Suite suite_del -Version all
#>
[CmdletBinding()]
param(
    [string]$Suite   = "suite",
    [string]$Version = "all",
    [int]$Port       = 47899,
    [int]$TimeoutSec = 900,
    # High is the baseline standard since 2026-07-31: it halved the median
    # spread of rows over 10 us (18.3% to 9.9%). Pass Normal to override.
    [ValidateSet('Normal', 'AboveNormal', 'High')]
    [string]$Priority = 'High',
    [switch]$List
)

$ErrorActionPreference = "Stop"
# This script lives in tools/; every path below is relative to the repository
# root, one level up.
$Root      = Split-Path $PSScriptRoot -Parent
$Standalone = Join-Path $Root "byond-standalones"
$ResultsDir = Join-Path $Root "results"

# Which source produced this result. Twelve Linux runs were discarded on
# 2026-08-02 for having been built from a checkout two commits behind, and
# nothing in the output said so: all twelve read 52 assertions and 0 failed. A
# green summary cannot see a stale checkout, so the runner records the commit
# and merge-runs.ps1 refuses to blend two of them, the way it already refuses
# to blend builds and priorities. A tree with edits under suite/ or tools/ is
# stamped dirty, because "which commit" stops being an answer once the source
# has been edited; doc edits do not count, since they cannot change what ran.
$SourceCommit = 'unknown'
try {
    $sha = & git -C $Root rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $sha) {
        $SourceCommit = $sha.Trim()
        $dirty = & git -C $Root status --porcelain -- suite tools 2>$null
        if ($dirty) { $SourceCommit = "$SourceCommit+dirty" }
    }
} catch { $SourceCommit = 'unknown' }

function Get-Builds {
    if (-not (Test-Path $Standalone)) { throw "no byond-standalones directory at $Standalone" }
    $found = @()
    foreach ($d in Get-ChildItem $Standalone -Directory | Sort-Object Name) {
        $dm = Join-Path $d.FullName "bin\dm.exe"
        $dd = Join-Path $d.FullName "bin\dd.exe"
        if (-not (Test-Path $dm)) { continue }
        if (-not (Test-Path $dd)) { continue }

        # ProductVersion looks like "5.0.516.1666 (5.0 Public)". Take the 516.1666.
        $raw = (Get-Item $dm).VersionInfo.ProductVersion
        $reported = $null
        if ($raw -match '(\d+)\.(\d+)\.(\d+)\.(\d+)') { $reported = "$($Matches[3]).$($Matches[4])" }

        $found += [pscustomobject]@{
            Label    = $d.Name
            Reported = $reported
            Dm       = $dm
            Dd       = $dd
            Match    = ($reported -eq $d.Name)
        }
    }
    return $found
}

$builds = Get-Builds
if ($builds.Count -eq 0) { throw "no usable builds under $Standalone (need <label>\bin\dm.exe and dd.exe)" }

if ($List) {
    "Discovered builds:"
    $builds | ForEach-Object {
        "{0,-12} binaries report {1,-12} {2}" -f $_.Label, $_.Reported, $(if ($_.Match) { "ok" } else { "MISLABELLED" })
    }
    return
}

# A folder called 516.1685 holding 1666 binaries would silently produce a
# baseline attributed to the wrong engine. Refuse rather than guess.
$bad = $builds | Where-Object { -not $_.Match }
if ($bad) {
    $bad | ForEach-Object { Write-Error "folder '$($_.Label)' holds binaries reporting '$($_.Reported)'" -ErrorAction Continue }
    throw "mislabelled build directory; fix the folder name before running"
}

$targets = if ($Version -eq "all") { $builds } else { $builds | Where-Object { $_.Label -eq $Version } }
if (-not $targets) { throw "no build matching '$Version'. Try -List." }

$dme = Join-Path $Root "suite\$Suite.dme"
if (-not (Test-Path $dme)) { throw "no such suite: $dme" }
if (-not (Test-Path $ResultsDir)) { New-Item -ItemType Directory -Path $ResultsDir | Out-Null }

$port = $Port
foreach ($b in $targets) {
    "=== $Suite on $($b.Label) ==="

    # Each build gets its own working directory. The .dmb is version-specific and
    # the suite writes its output beside it, so sharing one directory would race.
    $wd = Join-Path $Root "build\$($b.Label)"
    New-Item -ItemType Directory -Path $wd -Force | Out-Null

    $compile = & $b.Dm $dme 2>&1 | Out-String
    $summary = ($compile -split "`n" | Where-Object { $_ -match 'errors,' }) -join ''
    "  compile: $($summary.Trim())"
    if ($compile -match '\b([1-9]\d*) error') { Write-Error "compile failed on $($b.Label)"; continue }

    # dm.exe writes the .dmb beside the .dme, which is suite/ now.
    $dmb = Join-Path $Root "suite\$Suite.dmb"
    Copy-Item $dmb $wd -Force
    Get-ChildItem (Join-Path $Root "suite") -Filter "$Suite.rsc" -ErrorAction SilentlyContinue | Copy-Item -Destination $wd -Force

    $before = Get-ChildItem $wd -Filter "results-*.tsv" | Select-Object -ExpandProperty Name

    $started = Get-Date
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $b.Dd -ArgumentList "$Suite.dmb $port -trusted -invisible" -WorkingDirectory $wd -PassThru -NoNewWindow
    if ($Priority -ne 'Normal') {
        $p.PriorityClass = $Priority
        "  priority: $($p.PriorityClass)"
    }
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Write-Error "timed out after ${TimeoutSec}s on $($b.Label)"
        continue
    }
    $sw.Stop()
    "  ran in $([int]$sw.Elapsed.TotalSeconds)s"

    # A run that produces nothing must fail loudly. dd.exe prints
    # "FAILED to open port" and then exits 0, so exit code proves nothing, and
    # a suite run that takes seconds instead of minutes has not run.
    if ($sw.Elapsed.TotalSeconds -lt 30) {
        Write-Error ("$Suite on $($b.Label) exited after $([int]$sw.Elapsed.TotalSeconds)s. A port collision looks exactly like this: dd.exe fails to open port $port, prints it, and exits 0. Try another port.")
        continue
    }

    # A pre-existing file counts only if this run rewrote it. Compare against the
    # run's start time; comparing against $sw.Elapsed (a TimeSpan) throws.
    $produced = Get-ChildItem $wd -Filter "results-*.tsv" | Where-Object { $before -notcontains $_.Name -or $_.LastWriteTime -gt $started }
    # NO fallback to "the newest file lying around". Until 2026-08-01 this
    # reached for the most recent results-*.tsv when the run produced nothing,
    # which filed the PREVIOUS run's data under this run's name. Six such
    # copies were taken as a fresh triple before the assertion count gave it
    # away. Absence must be an error, never a guess.
    if (-not $produced) { Write-Error "no results file produced on $($b.Label); the run wrote nothing this session"; continue }

    foreach ($f in $produced) {
        # Trust the file's own header over anything this script believes.
        $stamped = (Select-String -Path $f.FullName -Pattern '^# byond_build\s+(\S+)' | Select-Object -First 1).Matches.Groups[1].Value
        $ver     = (Select-String -Path $f.FullName -Pattern '^# byond_version\s+(\S+)' | Select-Object -First 1).Matches.Groups[1].Value
        if ("$ver.$stamped" -ne $b.Reported) {
            Write-Error "result header says $ver.$stamped but binaries report $($b.Reported)"
            continue
        }
        # The suite cannot see its own process priority, so the runner stamps
        # it. merge-runs.ps1 refuses to merge runs of mixed priority.
        # run_started is what lets merge-runs.ps1 refuse a triple stitched
        # together across hours. Twice on 2026-08-03 a batch was interrupted,
        # resumed, and silently produced a merge containing one run taken 2.5
        # hours before the others; the first such merge had 76 of 118 rows over
        # 25% spread. Every other condition was identical, so no existing
        # refusal could see it. File timestamps cannot serve: copying a result
        # off another machine rewrites them.
        $started = $started.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        [System.IO.File]::AppendAllText($f.FullName, "# runner_priority`t$Priority`r`n# source_commit`t$SourceCommit`r`n# run_started`t$started`r`n", (New-Object System.Text.UTF8Encoding($false)))
        Copy-Item $f.FullName (Join-Path $ResultsDir $f.Name) -Force
        $res = (Select-String -Path $f.FullName -Pattern '^# (passed|failed|measured|low_resolution|result)\s+(\S+)') |
               ForEach-Object { "{0}={1}" -f $_.Matches.Groups[1].Value, $_.Matches.Groups[2].Value }
        "  $($f.Name)"
        "  $($res -join '  ')"
    }
    $port++
}
"done. baselines in $ResultsDir"
