<#
.SYNOPSIS
Mechanical consistency check on this project's documents. Exits non-zero on failure.

.DESCRIPTION
Every check here exists because the same error was made in prose and caught by a
human rather than by a machine. The rule this enforces is the project's oldest
one: ask for the number, not the assurance.

  1. Row counts claimed in prose match the baselines they describe.
  2. Every `VERIFICATION.md <n>` citation resolves to a real section.
  3. Every file path named in a document exists.
  4. No em dashes or en dashes.

Run before claiming the docs are current. It is the answer to "did you check",
because "I read it carefully" is worth nothing next to a command and its output.

.EXAMPLE
.\check-docs.ps1
.\check-docs.ps1 -Quiet
#>
[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Fails = 0

function Bad([string]$m) { Write-Host "FAIL  $m"; $script:Fails++ }
function Good([string]$m) { if (-not $Quiet) { Write-Host "ok    $m" } }

$docs = Get-ChildItem $Root -Filter *.md -File

# ---------------------------------------------------------------- 1. row counts
# Caught nothing for weeks, then caught "15 measurements" where the file said 13.
$baselines = @{}
foreach ($f in Get-ChildItem (Join-Path $Root "results") -Filter *.tsv -File -ErrorAction SilentlyContinue) {
    $lines = Get-Content $f.FullName
    $baselines[$f.Name] = [pscustomobject]@{
        Assert  = @($lines | Where-Object { $_ -like "ASSERT`t*" }).Count
        Measure = @($lines | Where-Object { $_ -like "MEASURE`t*" }).Count
    }
}
if ($baselines.Count -eq 0) { Bad "no baselines under results/, cannot verify any claimed count" }

$claimRe = '(?<suite>suite\w*)\.dme\s+(?<a>\d+)\s+assertions?,\s*(?<m>\d+)\s+measurements?'
foreach ($d in $docs) {
    foreach ($line in (Get-Content $d.FullName)) {
        $mm = [regex]::Match($line, $claimRe)
        if (-not $mm.Success) { continue }
        $a = [int]$mm.Groups['a'].Value
        $m = [int]$mm.Groups['m'].Value
        $suite = $mm.Groups['suite'].Value
        $hit = $baselines.GetEnumerator() | Where-Object { $_.Value.Assert -eq $a -and $_.Value.Measure -eq $m }
        if ($hit) {
            Good "$($d.Name): $suite.dme $a/$m matches $($hit[0].Key)"
        } else {
            $seen = ($baselines.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.Assert)/$($_.Value.Measure)" }) -join ", "
            Bad "$($d.Name): claims $suite.dme $a assertions, $m measurements. No baseline matches. Have: $seen"
        }
    }
}

# ------------------------------------------------------- 2. VERIFICATION refs
# A renumber of VERIFICATION.md silently invalidated citations in a sibling
# project. Item numbers are load-bearing across a project boundary: append only.
$vpath = Join-Path $Root "VERIFICATION.md"
if (Test-Path $vpath) {
    $v = Get-Content $vpath
    $sections = New-Object System.Collections.Generic.HashSet[string]
    foreach ($line in $v) {
        $s = [regex]::Match($line, '^#{2,3}\s+(?<n>\d+(\.\d+)?)[\.\s]')
        if ($s.Success) { [void]$sections.Add($s.Groups['n'].Value) }
    }
    # gaps in top-level numbering read as a deleted section; they are a smell
    $tops = @($sections | Where-Object { $_ -notmatch '\.' } | ForEach-Object { [int]$_ } | Sort-Object)
    if ($tops.Count -gt 0) {
        $expected = 1..($tops[-1])
        $missing = @($expected | Where-Object { $tops -notcontains $_ })
        if ($missing.Count -gt 0) { Bad "VERIFICATION.md top-level sections not contiguous, missing: $($missing -join ', ')" }
        else { Good "VERIFICATION.md sections contiguous 1..$($tops[-1])" }
    }

    # Scans THIS directory only. An earlier version also scanned ../discord-mine,
    # which made this check fail whenever that project restructured. It is a
    # separate deliverable and its files are not this project's to validate.
    $searchDirs = @($Root)
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in Get-ChildItem $dir -Filter *.md -File -Recurse) {
            foreach ($line in (Get-Content $f.FullName)) {
                foreach ($c in [regex]::Matches($line, 'VERIFICATION\.md`?\s+(?:item\s+)?(?<n>\d+(\.\d+)?)')) {
                    $n = $c.Groups['n'].Value
                    if (-not $sections.Contains($n)) {
                        Bad "$($f.FullName.Substring($Root.Length + 1)): cites VERIFICATION.md $n which does not exist"
                    }
                }
            }
        }
    }
    Good "VERIFICATION.md citations resolved"
}

# ------------------------------------------------------------ 3. file paths
# "respawn.dme", "delscale2.dme", "hypotheses.dme", "spec_sheet.dme" were cited
# as sources for published figures. None were in the tree. Nobody noticed for
# months, and section 2 of the spec sheet still rests on three of them.
#
# KnownAbsent is the debt ledger, not an excuse list. Each entry is a published
# figure with no reproducible source. Removing an entry means the harness was
# ported or the figure was withdrawn. ADDING one requires a VERIFICATION item.
$KnownAbsent = @{
    'spec_sheet.dme' = 'VERIFICATION 4.7'
    'hypotheses.dme' = 'VERIFICATION 4.7'
    'delscale2.dme'  = 'VERIFICATION 4.7'
    'delcause.dme'   = 'VERIFICATION 4.7'
    'numlimits.dme'  = 'VERIFICATION 4.7'
    'respawn.dme'    = 'VERIFICATION 4.2'
    'load.dme'       = 'unported, README'
}

# Roots inside this project only. Paths into ../discord-mine are deliberately NOT
# resolved: it is a separate deliverable that restructures on its own schedule,
# and twice in two days a path written here went stale because of it. Reaching
# into it to validate would make this checker fail on their changes, which is
# exactly the coupling being removed. Such paths are reported as external and
# left unchecked, so a stale one is visible without being a build break here.
$parent = Split-Path $Root -Parent
$searchRoots = @(
    $Root
    (Join-Path $Root "src")
    (Join-Path $Root "results")
    (Join-Path $Root "byond-standalones")
)
$externalPrefixes = @('../discord-mine', '..\discord-mine', '../../byond-dwo', '..\..\byond-dwo', 'notes/', 'guide/')

# Files owned by another project that this one names by bare leaf. Listed
# explicitly rather than pattern-matched, so adding one is a deliberate act of
# coupling that a reader can see and question.
$externalLeaves = @('BENCHMARK-IMPLICATIONS.md')

$skip = @('.dm', '.dme', '.tsv', '.md', '.ps1')   # bare extensions, not paths
$reported = New-Object System.Collections.Generic.HashSet[string]
$debt = New-Object System.Collections.Generic.HashSet[string]
$external = New-Object System.Collections.Generic.HashSet[string]

foreach ($d in $docs) {
    $text = Get-Content $d.FullName -Raw
    foreach ($mm in [regex]::Matches($text, '`(?<p>[A-Za-z0-9_./\\-]+\.(?:md|dme|dm|ps1|py|tsv))`')) {
        $p = $mm.Groups['p'].Value
        if ($skip -contains $p) { continue }
        if ($p -match '\*') { continue }

        $isExternal = $false
        foreach ($pre in $externalPrefixes) { if ($p.StartsWith($pre)) { $isExternal = $true; break } }
        if ($externalLeaves -contains (Split-Path $p -Leaf)) { $isExternal = $true }
        if ($isExternal) { [void]$external.Add($p); continue }

        $found = $false
        foreach ($r in $searchRoots) {
            if (Test-Path (Join-Path $r $p)) { $found = $true; break }
        }
        if ($found) { continue }

        $leaf = Split-Path $p -Leaf
        if ($KnownAbsent.ContainsKey($leaf)) { [void]$debt.Add("$leaf ($($KnownAbsent[$leaf]))"); continue }

        $key = "$($d.Name)|$p"
        if ($reported.Add($key)) { Bad "$($d.Name): names ``$p`` which does not exist anywhere on the search path" }
    }
}

# Placeholder paths like `notes/implications/<subject>.md` slipped through the
# check above because <subject> is not a path character, and one went stale for a
# day when discord-mine restructured. Validate as far as the directory.
foreach ($d in $docs) {
    $text = Get-Content $d.FullName -Raw
    foreach ($mm in [regex]::Matches($text, '`(?<dir>[A-Za-z0-9_./\\-]+)/<[A-Za-z]+>\.[a-z]+`')) {
        $dir = $mm.Groups['dir'].Value
        $isExt = $false
        foreach ($pre in $externalPrefixes) { if ($dir.StartsWith($pre)) { $isExt = $true; break } }
        if ($isExt) { [void]$external.Add("$dir/"); continue }
        $found = $false
        foreach ($r in $searchRoots) {
            if (Test-Path (Join-Path $r $dir) -PathType Container) { $found = $true; break } }
        if (-not $found) {
            $key = "$($d.Name)|dir|$dir"
            if ($reported.Add($key)) { Bad "$($d.Name): placeholder path under ``$dir/`` but that directory does not exist" }
        }
    }
}
Good "placeholder paths checked"

if ($external.Count -gt 0 -and -not $Quiet) {
    Write-Host ""
    Write-Host "ext   $($external.Count) path(s) point outside this project and are NOT verified here:"
    foreach ($x in ($external | Sort-Object)) { Write-Host "ext     $x" }
    Write-Host "ext   Those projects restructure on their own schedule. Confirm by hand before relying on one."
}

if ($debt.Count -gt 0) {
    Write-Host ""
    Write-Host "debt  $($debt.Count) cited source(s) absent from the tree, each tracked:"
    foreach ($x in ($debt | Sort-Object)) { Write-Host "debt    $x" }
    Write-Host "debt  Published figures resting on these are not reproducible here."
    Write-Host ""
}

# ------------------------------------------------------- 3b. source rules
# The framework has guards; they only apply if the code routes through them.
# Value() performs NO resolution check, so a timing sent through it bypasses
# MIN_DS, BASELINE_HEAVY and BELOW_BASELINE and the row looks identical in the
# output. That rule was written into CLAUDE.md on 2026-07-30 after the del suite
# was fixed, and perf_calls_deep.dm violated it in 13 places for a further day,
# because nothing checked. This is that check.
$timeUnits = @('us', 'ms', 'ds', 's', 's-total', 'x')
$srcDir = Join-Path $Root "src"
if (Test-Path $srcDir) {
    $violations = 0
    foreach ($f in Get-ChildItem $srcDir -Filter *.dm -File) {
        $text = Get-Content $f.FullName -Raw
        foreach ($mm in [regex]::Matches($text, 'Value\(')) {
            # take the call and a generous tail, since calls wrap across lines
            $tail = $text.Substring($mm.Index, [math]::Min(400, $text.Length - $mm.Index))
            $cut = $tail.IndexOf("`n`n")
            if ($cut -gt 0) { $tail = $tail.Substring(0, $cut) }
            foreach ($u in $timeUnits) {
                if ($tail -match [regex]::Escape('"' + $u + '"')) {
                    $line = ($text.Substring(0, $mm.Index) -split "`n").Count
                    Bad "$($f.Name):$line  Value() carrying a time unit `"$u`". Timings must use Measure, MeasureTU or MeasureDelta; computed values must use Derived."
                    $violations++
                    break
                }
            }
        }
    }
    if ($violations -eq 0) { Good "no timing bypasses Value()" }
}

# -------------------------------------------------------------- 4. dashes
foreach ($d in $docs) {
    $hits = @(Select-String -Path $d.FullName -Pattern '[—–]' -AllMatches)
    if ($hits.Count -gt 0) { Bad "$($d.Name): contains em or en dashes on line(s) $(($hits | ForEach-Object { $_.LineNumber }) -join ', ')" }
}
Good "dash style checked"

# ------------------------------------------------------------------ verdict
Write-Host ""
if ($Fails -eq 0) { Write-Host "docs consistent"; exit 0 }
Write-Host "$Fails inconsistency(ies). These are defects, not warnings."
exit 1
