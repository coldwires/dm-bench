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
# This script lives in tools/; everything it checks is relative to the
# repository root, one level up.
$Root = Split-Path $PSScriptRoot -Parent
$Fails = 0

function Bad([string]$m) { Write-Host "FAIL  $m"; $script:Fails++ }
function Good([string]$m) { if (-not $Quiet) { Write-Host "ok    $m" } }

# Documents live in three places: README at the root, the published record in
# docs/, the operating notes in working/. This was a single non-recursive glob
# of the root, so moving a document into a folder would have removed it from
# every check below while this script went on printing "docs consistent". The
# expected set is therefore named, and a document missing from the doc path is
# a failure rather than a smaller job. A check that shrinks quietly is the
# failure shape this project keeps rediscovering.
$docDirs = @($Root, (Join-Path $Root "docs"), (Join-Path $Root "working"))
$docs = @()
foreach ($dd in $docDirs) {
    if (Test-Path $dd) { $docs += Get-ChildItem $dd -Filter *.md -File }
}
$expectedDocs = @('README.md', 'BYOND-PERF-SPEC.md', 'METHOD.md', 'CLAUDE.md', 'VERIFICATION.md', 'INSTRUMENTS.md')
$missingDocs = @($expectedDocs | Where-Object { $docs.Name -notcontains $_ })
if ($missingDocs.Count -gt 0) { Bad "expected document(s) not found on the doc path: $($missingDocs -join ', ')" }
else { Good "$($docs.Count) documents discovered, all $($expectedDocs.Count) expected ones present" }

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

# The counts rarely sit flush against the filename, and prose wraps. README
# writes "`suite.dme`, three High-priority runs merged per build: 47
# assertions, 92 measurements" with a line break inside the claim. The original
# pattern required the count flush against the filename on one line, so it
# matched exactly one claim in the whole document set and reported "docs
# consistent" whether or not the rest were true. Match against whitespace-
# collapsed text so a wrapped claim still counts, cap the gap so a claim cannot
# pair with a filename from another paragraph, and skip a gap containing a
# second .dme, which would validate one suite's counts against another's name.
$claimRe = '(?<suite>suite\w*)\.dme`?(?<between>[^`]{0,120}?)(?<a>\d+) assertions?, (?<m>\d+) measurements?'
$claims = 0
foreach ($d in $docs) {
    $flat = ((Get-Content $d.FullName -Raw) -replace '\s+', ' ')
    foreach ($mm in [regex]::Matches($flat, $claimRe)) {
        if ($mm.Groups['between'].Value -match '\.dme') { continue }
        $a = [int]$mm.Groups['a'].Value
        $m = [int]$mm.Groups['m'].Value
        $suite = $mm.Groups['suite'].Value
        $claims++
        $hit = $baselines.GetEnumerator() | Where-Object { $_.Value.Assert -eq $a -and $_.Value.Measure -eq $m }
        if ($hit) {
            Good "$($d.Name): $suite.dme $a/$m matches $($hit[0].Key)"
        } else {
            $seen = ($baselines.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.Assert)/$($_.Value.Measure)" }) -join ", "
            Bad "$($d.Name): claims $suite.dme $a assertions, $m measurements. No baseline matches. Have: $seen"
        }
    }
}
# A check that verifies nothing must say so rather than pass quietly. That was
# this check's own failure mode.
if ($claims -eq 0) { Bad "no count claim matched anywhere in the documents; the claim pattern has gone stale" }
else { Good "$claims count claim(s) checked against the baselines" }

# ------------------------------------------------------- 2. VERIFICATION refs
# A renumber of VERIFICATION.md silently invalidated citations in a sibling
# project. Item numbers are load-bearing across a project boundary: append only.
$vpath = Join-Path $Root "working\VERIFICATION.md"
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
#
# What each one still holds up, checked 2026-08-01: spec_sheet.dme and
# hypotheses.dme back sections 11 and 12, which cannot regenerate here at all
# (one needs an absent 200-player harness, the other a remote server and a
# second machine). numlimits.dme backs two side observations in section 14, the
# rest of which now cites src/assert_numeric.dm. delscale2.dme and delcause.dme
# back nothing since section 2 was rederived (VERIFICATION 13) and appear only
# in the audit trail. respawn.dme and load.dme were dropped from this table on
# 2026-08-01: both are in the tree, merely unported, which the path check
# already resolves.
$KnownAbsent = @{
    'spec_sheet.dme' = 'VERIFICATION 4.7'
    'hypotheses.dme' = 'VERIFICATION 4.7'
    'delscale2.dme'  = 'VERIFICATION 4.7'
    'delcause.dme'   = 'VERIFICATION 4.7'
    'numlimits.dme'  = 'VERIFICATION 4.7'
}

# Roots inside this project only. Paths into ../discord-mine are deliberately NOT
# resolved: it is a separate deliverable that restructures on its own schedule,
# and twice in two days a path written here went stale because of it. Reaching
# into it to validate would make this checker fail on their changes, which is
# exactly the coupling being removed. Such paths are reported as external and
# left unchecked, so a stale one is visible without being a build break here.
$parent = Split-Path $Root -Parent
# Prose says `suite.dme`, `run.ps1` and `framework.dm` by bare name, and those
# resolve because the directory holding each is a search root. That is what
# kept the 2026-08-02 reorganisation from rewriting forty references.
$searchRoots = @(
    $Root
    (Join-Path $Root "suite")
    (Join-Path $Root "suite\src")
    (Join-Path $Root "tools")
    (Join-Path $Root "docs")
    (Join-Path $Root "working")
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
$historical = New-Object System.Collections.Generic.HashSet[string]
$external = New-Object System.Collections.Generic.HashSet[string]

# The debt block says it counts "figures nobody can reproduce", so only the
# public record can put a name on it. The operating notes name absent harnesses
# constantly, as the audit trail of what was once imported and has since been
# withdrawn: delscale2.dme and delcause.dme stopped backing any published figure
# on 2026-08-01 (VERIFICATION 13) and still appeared in the ledger the next day,
# purely because that entry describes them. A ledger that counts its own history
# overstates the debt, which is the same failure as understating it.
$operatingNotes = @('VERIFICATION.md', 'INSTRUMENTS.md', 'CLAUDE.md')

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
        if ($KnownAbsent.ContainsKey($leaf)) {
            if ($operatingNotes -contains $d.Name) { [void]$historical.Add("$leaf (named in $($d.Name))") }
            else { [void]$debt.Add("$leaf ($($KnownAbsent[$leaf]), cited in $($d.Name))") }
            continue
        }

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
    Write-Host "debt  $($debt.Count) source(s) cited by the PUBLIC record but absent from the tree:"
    foreach ($x in ($debt | Sort-Object)) { Write-Host "debt    $x" }
    Write-Host "debt  Published figures resting on these are not reproducible here."
    Write-Host ""
}
# A name that the public record already carries is debt, not audit trail, so it
# is reported once rather than in both blocks.
$debtLeaves = @($debt | ForEach-Object { ($_ -split ' ')[0] })
$historyOnly = @($historical | Where-Object { $debtLeaves -notcontains ($_ -split ' ')[0] })
if ($historyOnly.Count -gt 0 -and -not $Quiet) {
    Write-Host "hist  $($historyOnly.Count) absent harness(es) named only in the operating notes, as audit trail:"
    foreach ($x in ($historyOnly | Sort-Object)) { Write-Host "hist    $x" }
    Write-Host "hist  These back no published figure. Not debt."
    Write-Host ""
}

# ------------------------- 3d. public documents cite only published files
# A reference in the published record to a file that does not ship is a
# dangling link for everyone who clones. On 2026-08-02 METHOD.md cited
# VERIFICATION.md and BYOND-PERF-SPEC.md cited INSTRUMENTS.md; both files exist
# on this disk and neither is tracked, so the path check above waved them
# through. Existence and publication are different questions, and only git can
# answer the second.
# "Public" is decided by what git ships, not by which folder a file sits in.
# Defining it by directory made this check pass vacuously the first time it
# ran, because it was written against a layout that did not exist yet and
# inspected one document instead of three.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "skip  git is not on PATH; cannot verify that public documents cite only published files"
} else {
    $publicDocs = @($docs | Where-Object {
        git check-ignore --quiet -- $_.FullName
        $LASTEXITCODE -ne 0
    })
    $privateHits = 0
    foreach ($d in $publicDocs) {
        $text = Get-Content $d.FullName -Raw
        foreach ($mm in [regex]::Matches($text, '`(?<p>[A-Za-z0-9_./\\-]+\.(?:md|dme|dm|ps1|tsv))`')) {
            $p = $mm.Groups['p'].Value
            if ($skip -contains $p) { continue }
            if ($p -match '\*') { continue }
            $resolved = $null
            foreach ($r in $searchRoots) {
                $cand = Join-Path $r $p
                if (Test-Path $cand) { $resolved = $cand; break }
            }
            # A path that resolves nowhere is section 3's business, not this one.
            if (-not $resolved) { continue }
            git check-ignore --quiet -- $resolved
            if ($LASTEXITCODE -eq 0) {
                Bad "$($d.Name): cites ``$p``, which is gitignored and does not ship. Copy the fact across instead of citing the file."
                $privateHits++
            }
        }
    }
    if ($privateHits -eq 0) { Good "$($publicDocs.Count) public document(s) cite only files that ship" }
}

# ------------------------------------------------------- 3b. source rules
# The framework has guards; they only apply if the code routes through them.
# Value() performs NO resolution check, so a timing sent through it bypasses
# MIN_DS, BASELINE_HEAVY and BELOW_BASELINE and the row looks identical in the
# output. That rule was written into CLAUDE.md on 2026-07-30 after the del suite
# was fixed, and perf_calls_deep.dm violated it in 13 places for a further day,
# because nothing checked. This is that check.
$timeUnits = @('us', 'ms', 'ds', 's', 's-total', 'x')
$srcDir = Join-Path $Root "suite\src"
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

# ------------------------------------------------- 3c. document corruption
# Patching these files through a shell heredoc has three times mangled
# backslashes: a path separator became a literal carriage return, another
# collapsed into one garbage glyph, and once the corruption landed in the
# command block telling the next session what to run. Nothing caught it but
# reading. Hence this check. Prefer the Edit tool over shell heredocs here.
foreach ($d in $docs) {
    $ln = 0
    foreach ($line in [System.IO.File]::ReadAllLines($d.FullName)) {
        $ln++
        foreach ($ch in $line.ToCharArray()) {
            if ([int]$ch -lt 32 -and $ch -ne "`t") {
                $hex = "{0:X2}" -f [int]$ch
                Bad "$($d.Name):$ln contains a control character (0x$hex). A shell patch probably ate a backslash."
                break
            }
        }
    }
    # An odd number of fences means a code block was clobbered mid-edit.
    $fences = @(Select-String -Path $d.FullName -Pattern '^```').Count
    if ($fences % 2 -ne 0) { Bad "$($d.Name): $fences code fences, an odd number. A block is unterminated." }
}
Good "no document corruption"

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
