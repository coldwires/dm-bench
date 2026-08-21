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
# Not a pass and not a failure: a check that could not run, said out loud. A
# skipped check that prints nothing is indistinguishable from a passing one.
function Note([string]$m) { if (-not $Quiet) { Write-Host "note  $m" } }

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
#
# Split by whether the document ships, because the answer to "is it missing"
# differs. A public document absent from the doc path is always a failure. The
# operating notes are gitignored, so they are simply not there in a fresh
# clone, and demanding them made this script fail in exactly the environment a
# contributor or CI would run it in. They are still required whenever they
# exist locally: a working tree that has them must not quietly stop checking
# them, which was the original point.
$publicDocs  = @('README.md', 'CONTRIBUTING.md', 'BYOND-PERF-SPEC.md', 'METHOD.md')
$privateDocs = @('NOTES.md', 'VERIFICATION.md', 'INSTRUMENTS.md')
# Held separately and by name, because $publicDocs is REASSIGNED further down to
# a list of FileInfo objects for the git check. The checks that distinguish the
# published record from the audit trail run before that point and would keep
# working, right up until someone reorders two blocks, at which point
# "-contains $d.Name" would match nothing and both checks would silently verify
# zero documents while still printing ok. That is this project's oldest failure
# shape and it does not get to live in the checker itself.
$publishedDocNames = $publicDocs.Clone()
$missingDocs = @($publicDocs | Where-Object { $docs.Name -notcontains $_ })
if ($missingDocs.Count -gt 0) { Bad "published document(s) not found on the doc path: $($missingDocs -join ', ')" }
else { Good "$($docs.Count) documents discovered, all $($publicDocs.Count) published ones present" }

$absentNotes = @($privateDocs | Where-Object { $docs.Name -notcontains $_ })
if ($absentNotes.Count -eq $privateDocs.Count) {
    Note "operating notes absent, so this is a published-record check only. That is expected in a clone; the notes do not ship."
} elseif ($absentNotes.Count -gt 0) {
    Bad "operating note(s) missing from a tree that has the others: $($absentNotes -join ', '). Either all of them are absent, which is a clone, or one has been lost."
}

# ---------------------------------------------------------------- 1. row counts
# Caught nothing for weeks, then caught "15 measurements" where the file said 13.
$baselines = @{}
# Row-level facts, for the checks after this one. $rowFlags records whether each
# MEASURE row cleared its guards in each baseline, which is what decides whether
# the published record is allowed to call it withheld.
$rowIds   = New-Object System.Collections.Generic.HashSet[string]
$families = New-Object System.Collections.Generic.HashSet[string]
$rowFlags = @{}
foreach ($f in Get-ChildItem (Join-Path $Root "results") -Filter *.tsv -File -ErrorAction SilentlyContinue) {
    $lines = Get-Content $f.FullName
    $baselines[$f.Name] = [pscustomobject]@{
        Assert  = @($lines | Where-Object { $_ -like "ASSERT`t*" }).Count
        Measure = @($lines | Where-Object { $_ -like "MEASURE`t*" }).Count
    }
}

# Which baselines the published record is answerable to. results/ keeps
# superseded files on purpose (-run1..3, -v2, -v3, the pre-merge singles), and
# counting those made the row checks below useless in both directions: a
# renamed row still resolved because an old file still carried it, and one
# stale file flagging a row was enough to make its flag state look
# machine-dependent and skip the check. So: one baseline per suite, build and
# system, and where several exist the one with the most measured rows wins,
# which is always the newest since rows are added and not removed. Deterministic
# and self-maintaining, so a new baseline needs no edit here.
$canonical = @{}
foreach ($f in Get-ChildItem (Join-Path $Root "results") -Filter *.tsv -File -ErrorAction SilentlyContinue) {
    $lines = Get-Content $f.FullName
    $meta = @{}
    foreach ($line in $lines) { if ($line -match '^#\s*(\S+)\s+(.*)$') { $meta[$Matches[1]] = $Matches[2].Trim() } }
    $key = "$($meta['suite'])|$($meta['byond_build'])|$($meta['system'])"
    $n = $baselines[$f.Name].Measure
    if (-not $canonical.ContainsKey($key) -or $n -gt $canonical[$key].N) {
        $canonical[$key] = [pscustomobject]@{ Name = $f.Name; N = $n; Lines = $lines }
    }
}
foreach ($c in $canonical.Values) {
    foreach ($line in $c.Lines) {
        if (-not ($line -like "ASSERT`t*" -or $line -like "MEASURE`t*")) { continue }
        $p = $line -split "`t"
        if ($p.Count -lt 8) { continue }
        $id = $p[1]
        [void]$rowIds.Add($id)
        [void]$families.Add(($id -split '\.')[0])
        if ($p[0] -eq 'MEASURE') {
            if (-not $rowFlags.ContainsKey($id)) { $rowFlags[$id] = New-Object System.Collections.Generic.List[bool] }
            $rowFlags[$id].Add([bool]($p.Count -ge 10 -and $p[9] -match 'LOW_RESOLUTION|SUBTRACTION_NOISE'))
        }
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
#
# Three phrasings, because matching only one is how this check spent its whole
# life validating README.md and never once looking at BYOND-PERF-SPEC.md, which
# writes the counts before the filename and joins them with "and". That page
# carried "52 assertions and 92 measurements" against a real 59 and 118 while
# this script printed "docs consistent" (VERIFICATION 40).
$claimPatterns = @(
    '(?<suite>suite\w*)\.dme`?(?<between>[^`]{0,120}?)(?<a>\d+) assertions?, (?<m>\d+) measurements?'
    '(?<a>\d+) assertions? and (?<m>\d+) measurements? for `?(?<suite>suite\w*)\.dme'
    '(?<a>\d+) and (?<m>\d+) for `?(?<suite>suite\w*)\.dme'
)
$claims = 0
foreach ($d in $docs) {
    $flat = ((Get-Content $d.FullName -Raw) -replace '\s+', ' ')
    # Where a full claim was parsed, so the coverage check below can tell a
    # verified number from one nobody looked at.
    $covered = New-Object System.Collections.Generic.List[object]
    foreach ($pat in $claimPatterns) {
        foreach ($mm in [regex]::Matches($flat, $pat)) {
            if ($mm.Groups['between'].Success -and $mm.Groups['between'].Value -match '\.dme') { continue }
            $a = [int]$mm.Groups['a'].Value
            $m = [int]$mm.Groups['m'].Value
            $suite = $mm.Groups['suite'].Value
            $claims++
            $covered.Add(@($mm.Index, $mm.Index + $mm.Length))
            $hit = $baselines.GetEnumerator() | Where-Object { $_.Value.Assert -eq $a -and $_.Value.Measure -eq $m }
            if ($hit) {
                Good "$($d.Name): $suite.dme $a/$m matches $($hit[0].Key)"
            } else {
                $seen = ($baselines.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value.Assert)/$($_.Value.Measure)" }) -join ", "
                Bad "$($d.Name): claims $suite.dme $a assertions, $m measurements. No baseline matches. Have: $seen"
            }
        }
    }

    # Coverage. A count that no pattern above consumed is a number nobody
    # checked, and silence there is indistinguishable from a pass, which is the
    # exact failure this whole check keeps repeating. So a bare count must match
    # some baseline on its own.
    #
    # Public documents only. The operating notes record superseded counts on
    # purpose, as the audit trail of what the suite emitted at the time, and
    # rewriting those to satisfy a checker would destroy the record.
    if ($publishedDocNames -contains $d.Name) {
        foreach ($bare in [regex]::Matches($flat, '(?<n>\d+) (?<kind>assertions?|measurements?)')) {
            $inside = $false
            foreach ($c in $covered) { if ($bare.Index -ge $c[0] -and $bare.Index -lt $c[1]) { $inside = $true; break } }
            if ($inside) { continue }
            $n = [int]$bare.Groups['n'].Value
            $isAssert = $bare.Groups['kind'].Value -like 'assertion*'
            $ok = $baselines.GetEnumerator() | Where-Object { if ($isAssert) { $_.Value.Assert -eq $n } else { $_.Value.Measure -eq $n } }
            if ($ok) {
                $claims++
                Good "$($d.Name): $n $($bare.Groups['kind'].Value) matches $($ok[0].Key)"
            } else {
                Bad "$($d.Name): says ``$n $($bare.Groups['kind'].Value)`` and no baseline has that count. Either the figure is stale or the phrasing needs adding to the claim patterns."
            }
        }
    }
}
# A check that verifies nothing must say so rather than pass quietly. That was
# this check's own failure mode.
if ($claims -eq 0) { Bad "no count claim matched anywhere in the documents; the claim pattern has gone stale" }
else { Good "$claims count claim(s) checked against the baselines" }

# ------------------------------------------------ 1b. row ids and withheld rows
# BYOND-PERF-SPEC.md withheld `del.refs_256` as SUBTRACTION_NOISE and rested a
# published claim on the other machine instead. The row was unflagged in every
# tracked baseline: the withholding had been true of the merge the section was
# written from, and stayed in the prose after the data moved. Nothing could see
# it, because no check ever compared a document against a row (VERIFICATION 40).
#
# Families come from the baselines themselves, so `world.tick_usage` and
# `client.byond_build` are not mistaken for row ids, and a new family needs no
# edit here.
#
# Published documents only, for the same reason the count coverage above is:
# the operating notes name rows that were renamed or deleted, on purpose, as
# the record of what happened at the time. VERIFICATION 27 says so in as many
# words about `io.world_log_far_cheaper_than_file`. Holding the audit trail to
# the current baselines would force it to be rewritten, which is the one thing
# an audit trail must never be.
$idsChecked = 0; $idProblems = 0
foreach ($d in $docs) {
    if ($publishedDocNames -notcontains $d.Name) { continue }
    $raw = Get-Content $d.FullName -Raw
    $flat = ($raw -replace '\s+', ' ')
    foreach ($mm in [regex]::Matches($flat, '`(?<id>[a-z][a-z0-9_]*\.[a-z0-9_]+)`')) {
        $id = $mm.Groups['id'].Value
        if (-not $families.Contains(($id -split '\.')[0])) { continue }
        # `framework.dm` is a file, and `framework` is also a row family, so a
        # filename matches the id shape exactly. Extensions are never row ids.
        if ($id -match '\.(dm|dme|ps1|sh|md|tsv|py|html|txt|zip|log|yml)$') { continue }
        $idsChecked++

        if (-not $rowIds.Contains($id)) {
            Bad "$($d.Name): names row ``$id``, which is in none of the $($canonical.Count) current baselines. A renamed or deleted row leaves the prose describing something that no longer runs."
            $idProblems++
            continue
        }
        if (-not $rowFlags.ContainsKey($id)) { continue }

        $flags = $rowFlags[$id]
        $start = [math]::Max(0, $mm.Index - 220)
        $window = $flat.Substring($start, [math]::Min(440, $flat.Length - $start))
        $saysWithheld = $window -match 'withheld|withhold'

        if ($saysWithheld -and ($flags -notcontains $true)) {
            Bad "$($d.Name): calls ``$id`` withheld, but it clears its guards in all $($flags.Count) baseline(s) that carry it. A row is withheld when its own data says so; publish it or say why not."
            $idProblems++
        } elseif (-not $saysWithheld -and ($flags -notcontains $false) -and $window -match '\d\s*(?:us|µs)') {
            Bad "$($d.Name): quotes a figure beside ``$id``, which is flagged in every baseline that carries it. A flagged row is not evidence."
            $idProblems++
        }
    }
}
if ($idsChecked -eq 0) { Bad "no row id was checked against a baseline; the id pattern has gone stale" }
elseif ($idProblems -eq 0) { Good "$idsChecked row id mention(s) agree with the $($canonical.Count) current baselines" }

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
$operatingNotes = @('VERIFICATION.md', 'INSTRUMENTS.md', 'NOTES.md')

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
# output. That rule was written into NOTES.md on 2026-07-30 after the del suite
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

# ------------------------------------------------------- 5. provenance leaks
#
# The rule: the public record is hypothesis, test, empirical data. Not who said
# it, not where the claim was found, not which channel or which person. That
# belongs in the operating notes.
#
# It was a written rule for weeks and it was broken anyway, in source comments
# rather than in documents, which is where nobody was looking: a harness added
# on 2026-08-03 credited a reporter and the engine author five times, and two
# older files had been carrying attributions since before the rule existed. A
# rule with an exit code beats a rule written down, which this project has now
# learned four times.
#
# The term list lives in working/, untracked, because writing the handles into
# a tracked file to prove they are absent from tracked files would publish the
# very thing being stripped. So this check is armed locally, where the
# pre-commit run happens, and unarmed in a clone. It says which it is rather
# than passing silently.
$denyPath = Join-Path $Root "working\provenance-denylist.txt"
if (-not (Test-Path $denyPath)) {
    Note "provenance check unarmed: no working/provenance-denylist.txt. Expected in a clone; the list does not ship."
} else {
    $terms = @(Get-Content $denyPath | ForEach-Object { $_.Trim() } |
               Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($terms.Count -eq 0) {
        Note "provenance check unarmed: the denylist is empty"
    } else {
        # Everything git tracks, which is exactly the definition of public.
        # Baselines are excluded: they are engine output, and a term appearing
        # there would be a row id rather than an attribution.
        # Leading word boundary only. Both ends would miss a handle carrying a
        # suffix, which is how the engine author's name is usually written, and
        # no boundary at all would flag "authors" for containing a short handle.
        # Verified against both cases rather than reasoned about: the pattern
        # was wrong in each direction once before it was right.
        $termPatterns = @($terms | ForEach-Object { '\b' + [regex]::Escape($_) })
        Push-Location $Root
        $tracked = @(& git ls-files 2>$null | Where-Object { $_ -and $_ -notlike 'results/*' })
        Pop-Location
        $leaks = 0
        foreach ($rel in $tracked) {
            $full = Join-Path $Root $rel
            if (-not (Test-Path $full -PathType Leaf)) { continue }
            # Word boundaries, not substrings. A short handle is a substring of
            # ordinary words, and "authors" contains one of these, so a
            # substring match would fail the check on innocent prose and get
            # itself disabled, which is how a check dies.
            $hits = @(Select-String -Path $full -Pattern $termPatterns -AllMatches -ErrorAction SilentlyContinue)
            foreach ($h in $hits) {
                Bad "$rel line $($h.LineNumber): names a person or a channel in a tracked file. Provenance belongs in the notes."
                $leaks++
            }
        }
        if ($leaks -eq 0) { Good "no provenance in tracked files ($($terms.Count) terms checked)" }
    }
}

# ------------------------------------------------------------------ verdict
Write-Host ""
if ($Fails -eq 0) { Write-Host "docs consistent"; exit 0 }
Write-Host "$Fails inconsistency(ies). These are defects, not warnings."
exit 1
