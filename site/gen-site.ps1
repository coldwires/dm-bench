<#
.SYNOPSIS
Generate site/index.html from the checked-in TSV baselines. Every number on
the page comes from a results file; nothing is hand-transcribed.

.EXAMPLE
.\site\gen-site.ps1
#>
[CmdletBinding()]
param(
    [string]$Out = (Join-Path $PSScriptRoot "index.html")
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Results = Join-Path $Root "results"

function Parse-Tsv([string]$path) {
    $rows = [ordered]@{}
    $meta = @{}
    foreach ($line in (Get-Content $path)) {
        if ($line -match '^#\s*(\S+)\s+(.*)$') { $meta[$Matches[1]] = $Matches[2].Trim(); continue }
        $p = $line -split "`t"
        if ($p.Count -lt 8) { continue }
        if ($p[0] -ne 'ASSERT' -and $p[0] -ne 'MEASURE') { continue }
        $notes = if ($p.Count -ge 10) { $p[9] } else { '' }
        $spread = $null
        if ($notes -match 'spread=(\d+)%') { $spread = [int]$Matches[1] }
        $rows[$p[1]] = [pscustomobject]@{
            Kind = $p[0]; Id = $p[1]; Cat = $p[2]; Name = $p[3]
            Val = $p[4]; Unit = $p[5]; Status = $p[7]; Notes = $notes
            Spread = $spread
            Withheld = ($notes -match 'LOW_RESOLUTION|BELOW_BASELINE')
            Heavy = ($notes -match 'BASELINE_HEAVY')
        }
    }
    [pscustomobject]@{ Rows = $rows; Meta = $meta }
}

$s66 = Parse-Tsv (Join-Path $Results "516.1666-windows-merged.tsv")
$s85 = Parse-Tsv (Join-Path $Results "516.1685-windows-merged.tsv")
$d66 = Parse-Tsv (Join-Path $Results "516.1666-windows-del-v3.tsv")
$d85 = Parse-Tsv (Join-Path $Results "516.1685-windows-del-v3.tsv")

function Esc([string]$s) {
    $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
}

function UnitHtml([string]$u) {
    if ($u -eq 'us') { return '&micro;s' }
    return (Esc $u)
}

# ---- reproduction snippets, extracted from the suite source ----
#
# Each row's dropdown shows the DM code that produced it, captured from the
# emitting call site in src/ at generation time so it cannot drift from what
# actually ran. An id like lists.in_n10 matches a source literal like
# "lists.in_n[n]" by treating embedded [expr] as a wildcard.

$SrcFiles = Get-ChildItem (Join-Path $Root "suite\src") -Filter "*.dm" | Sort-Object Name
$EmitIndex = New-Object System.Collections.Generic.List[object]
foreach ($sf in $SrcFiles) {
    $lines = Get-Content $sf.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?:Measure|MeasureU|MeasureTU|MeasureDelta|Assert|Value|Derived|Extern)\("([^"]+)"') {
            $lit = $Matches[1]
            $rx = '^' + ((([regex]::Escape($lit)) -replace '\\\[[^\]]*\]', '.+')) + '$'
            $EmitIndex.Add([pscustomobject]@{ File = $sf.Name; Lines = $lines; At = $i; Pattern = $rx })
        }
    }
}

function Get-Snippet([string]$id) {
    foreach ($e in $EmitIndex) {
        if ($id -notmatch $e.Pattern) { continue }
        $lines = $e.Lines
        # forward: include continuation lines of the emit call until parens balance
        $endAt = $e.At
        $bal = 0
        for ($j = $e.At; $j -lt [math]::Min($e.At + 6, $lines.Count); $j++) {
            $bal += ([regex]::Matches($lines[$j], '\(')).Count - ([regex]::Matches($lines[$j], '\)')).Count
            $endAt = $j
            if ($bal -le 0) { break }
        }
        # backward: capture the timed block. Stop at a blank line once a clock
        # read is in hand, at a previous emit call, or at a 30-line cap.
        $clockSeen = $false
        $startAt = $e.At
        for ($j = $e.At - 1; $j -ge [math]::Max(0, $e.At - 30); $j--) {
            $l = $lines[$j]
            if ($l -match '(?:Measure|MeasureU|MeasureTU|MeasureDelta|Assert|Value|Derived|Extern)\("') { break }
            if ([string]::IsNullOrWhiteSpace($l) -and $clockSeen) { break }
            if ([string]::IsNullOrWhiteSpace($l) -and $j -eq $e.At - 1) { continue }
            $startAt = $j
            if ($l -match 'world\.timeofday|world\.tick_usage|IO_RefMedian|EmptyLoopPass|BareLoopPass|DelNet') { $clockSeen = $true }
        }
        $snip = @($lines[$startAt..$endAt] | Where-Object { $_ -ne $null })
        # A previous emit call can span lines; its dangling continuation has
        # more closing parens than opening. Drop such fragments off the top,
        # plus any blank line they leave behind.
        while ($snip.Count -gt 1) {
            $open = ([regex]::Matches($snip[0], '\(')).Count
            $close = ([regex]::Matches($snip[0], '\)')).Count
            if ($close -gt $open -or [string]::IsNullOrWhiteSpace($snip[0]) -or $snip[0] -match '^\s*"') { $snip = $snip[1..($snip.Count - 1)] } else { break }
        }
        # If nothing above the emit was a timed block (suites like view time
        # inside helper procs and pass the result in), chase the helper: find
        # the proc that produced dt, directly in the emit args or via a
        # variable assigned above, and splice its body in.
        if ((($snip -join ' ') -replace '"[^"]*"', '') -notmatch 'world\.timeofday|world\.tick_usage|for\s*\(') {
            $emitLine = $lines[$e.At]
            $ctxLine = $null
            $helper = $null
            $skipNames = @('Measure','MeasureU','MeasureTU','MeasureDelta','Assert','Value','Derived','Extern','Median3','round','max','min','abs','list','locate','length','file','fdel')
            $noStr = $emitLine -replace '"[^"]*"', '""'
            foreach ($hm in [regex]::Matches($noStr, '\b([A-Za-z]\w*)\(')) {
                if ($hm.Groups[1].Value -in $skipNames) { continue }
                $helper = $hm.Groups[1].Value; break
            }
            if (-not $helper -and $noStr -match '""\s*,\s*([a-z]\w+)\s*,') {
                $dtVar = $Matches[1]
                for ($j = $e.At - 1; $j -ge [math]::Max(0, $e.At - 40); $j--) {
                    if ($lines[$j] -match ('(?:var/)?' + [regex]::Escape($dtVar) + '\s*=')) {
                        $ctxLine = $lines[$j]
                        foreach ($hm in [regex]::Matches($ctxLine, '\b([A-Za-z]\w*)\(')) {
                            if ($hm.Groups[1].Value -in $skipNames) { continue }
                            $helper = $hm.Groups[1].Value; break
                        }
                        break
                    }
                }
            }
            if ($helper) {
                $defAt = -1
                for ($j = 0; $j -lt $lines.Count; $j++) {
                    if ($lines[$j] -match ('^\s*' + [regex]::Escape($helper) + '\([a-z][\w\s,/=]*\)\s*$') -and $lines[$j] -notmatch '\d\)') { $defAt = $j; break }
                }
                if ($defAt -ge 0) {
                    $defEnd = $defAt
                    for ($j = $defAt + 1; $j -lt [math]::Min($defAt + 22, $lines.Count); $j++) {
                        $defEnd = $j
                        if ($lines[$j] -match '^\s*return\b') { break }
                    }
                    # An emit call passes its iteration count by name, so that
                    # the loop and the divisor cannot drift apart (VERIFICATION
                    # 14). Splice in the line that defines it, or the snippet
                    # reads "VW_Inline(r_view, 7)" and the reader cannot see
                    # how many iterations produced the figure.
                    $consts = New-Object System.Collections.Generic.List[string]
                    $seenNames = @()
                    foreach ($im in [regex]::Matches(($emitLine -replace '"[^"]*"', '""'), '\b([a-z]\w*)\b')) {
                        $n2 = $im.Groups[1].Value
                        if ($n2 -in $skipNames -or $seenNames -contains $n2) { continue }
                        $seenNames += $n2
                        for ($j = $e.At - 1; $j -ge [math]::Max(0, $e.At - 40); $j--) {
                            if ($lines[$j] -match ('^\s*var/' + [regex]::Escape($n2) + '\s*=\s*\d+\s*$')) {
                                $consts.Add($lines[$j].Trim()); break
                            }
                        }
                    }
                    $rebuilt = New-Object System.Collections.Generic.List[string]
                    if ($ctxLine) { $rebuilt.Add($ctxLine); $rebuilt.Add('') }
                    foreach ($dl in $lines[$defAt..$defEnd]) { $rebuilt.Add($dl) }
                    $rebuilt.Add('')
                    foreach ($cl in $consts) { $rebuilt.Add($cl) }
                    $rebuilt.Add($emitLine)
                    $snip = @($rebuilt)
                }
            }
        }
        # dedent: strip the common leading tab depth
        $minTabs = ($snip | Where-Object { $_ -notmatch '^\s*$' } | ForEach-Object { ([regex]::Match($_, '^\t*')).Length } | Measure-Object -Minimum).Minimum
        if ($minTabs -gt 0) { $snip = $snip | ForEach-Object { if ($_.Length -ge $minTabs) { $_.Substring($minTabs) } else { $_ } } }
        return (Render-Snippet $snip $e.File)
    }
    # Rows emitted through a generic helper carry no literal id at the emit
    # site. Show the call site plus the helper body instead.
    foreach ($sf in $SrcFiles) {
        $lines = Get-Content $sf.FullName
        $callAt = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ('\w+\("' + [regex]::Escape($id) + '"')) { $callAt = $i; break }
        }
        if ($callAt -lt 0) { continue }
        if ($lines[$callAt] -notmatch '^\s*(\w+)\(') { continue }
        $helper = $Matches[1]
        $bodyAt = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($i -ne $callAt -and $lines[$i] -match ('^\s*' + [regex]::Escape($helper) + '\(\w')) { $bodyAt = $i; break }
        }
        if ($bodyAt -lt 0) { continue }
        $bodyEnd = $bodyAt
        for ($i = $bodyAt + 1; $i -lt [math]::Min($bodyAt + 20, $lines.Count); $i++) {
            if ($lines[$i] -match '(?:Measure|MeasureU|MeasureTU)\(') { $bodyEnd = $i; break }
            if ($lines[$i] -match '^\t\w' -and $i -gt $bodyAt + 1) { break }
            $bodyEnd = $i
        }
        $snip = @($lines[$callAt]) + @('') + @($lines[$bodyAt..$bodyEnd])
        $minTabs = ($snip | Where-Object { $_ -notmatch '^\s*$' } | ForEach-Object { ([regex]::Match($_, '^\t*')).Length } | Measure-Object -Minimum).Minimum
        if ($minTabs -gt 0) { $snip = $snip | ForEach-Object { if ($_.Length -ge $minTabs) { $_.Substring($minTabs) } else { $_ } } }
        return (Render-Snippet $snip $sf.Name)
    }
    return $null
}

# The plain-DM view, derived mechanically from the harness code so the two
# cannot disagree: unwrap X10(expr) to expr, restore R / UNROLL to R, drop
# clock reads, counter resets, pragmas, comments and the emit call. What
# remains is the code a developer would write to reproduce the measurement.
function Make-Payload([string[]]$lines) {
    $out = New-Object System.Collections.Generic.List[string]
    $transformed = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*(var/\w+ = )?(Measure|MeasureU|MeasureTU|MeasureDelta|Assert|Value|Derived|Extern)\(') {
            # An assertion's payload IS its logic; a plain view that drops the
            # check would misrepresent it. Assertions render verbatim only.
            if ($Matches[2] -eq 'Assert') { return $null }
            $transformed = $true; break
        }
        if ($l -match '^\s*#pragma') { $transformed = $true; continue }
        if ($l -match '^\s*//') { continue }
        if ($l -match '^\s*(var/)?t\d+ = world\.(timeofday|tick_usage)') { $transformed = $true; continue }
        if ($l -match '^\s*return world\.(timeofday|tick_usage)') { $transformed = $true; continue }
        if ($l -match '^\s*(CACC|DACC|TSGUARD|VACC|IOACC) = 0\s*$') { continue }
        $p = $l
        if ($p -match 'X10\(') { $p = $p -replace 'X10\((.*)\)\s*$', '$1'; $transformed = $true }
        if ($p -match '/ UNROLL') { $p = $p -replace '(\w+)\s*/\s*UNROLL', '$1'; $transformed = $true }
        $out.Add($p)
    }
    while ($out.Count -gt 0 -and [string]::IsNullOrWhiteSpace($out[0])) { $out.RemoveAt(0) }
    while ($out.Count -gt 0 -and [string]::IsNullOrWhiteSpace($out[$out.Count - 1])) { $out.RemoveAt($out.Count - 1) }
    if (-not $transformed -or $out.Count -eq 0) { return $null }
    if (($out -join ' ') -notmatch 'for\s*\(') { return $null }
    return @($out)
}

function Render-Snippet([string[]]$snip, [string]$file) {
    $code = Esc ($snip -join "`n")
    $note = ''
    if ($code -match 'X10\(' -or $code -match 'UNROLL') { $note = '<p class="srcnote">X10(s) repeats the statement ten times per loop pass; UNROLL = 10. Defined in src/framework.dm.</p>' }
    $payload = Make-Payload $snip
    if ($payload) {
        $pcode = Esc ($payload -join "`n")
        $inner = "<pre class=`"code`">$pcode</pre><details class=`"inner`"><summary class=`"srcnote`">as measured, verbatim harness code (src/$file)</summary><pre class=`"code`">$code</pre>$note</details>"
    } else {
        $inner = "<pre class=`"code`">$code</pre><p class=`"srcnote`">src/$file</p>$note"
    }
    return "<details><summary><span class=`"id`">{ID}</span><span class=`"desc`">{DESC}</span></summary>$inner</details>"
}

function LabelCell($r) {
    $tpl = Get-Snippet $r.Id
    if ($tpl) {
        return '<td>' + ($tpl -replace '\{ID\}', (Esc $r.Id) -replace '\{DESC\}', (Esc $r.Name)) + '</td>'
    }
    return "<td><span class=`"id`">$(Esc $r.Id)</span><span class=`"desc`">$(Esc $r.Name)</span></td>"
}

function MeasureCell($r) {
    if (-not $r) { return '<td class="num"><span class="st st-notrun">not run</span></td>' }
    if ($r.Withheld) {
        $flag = if ($r.Notes -match '(LOW_RESOLUTION|BELOW_BASELINE)') { $Matches[1] } else { 'flagged' }
        return "<td class=`"num`"><span class=`"withheld`">withheld</span> <span class=`"flag`">$flag</span></td>"
    }
    $sp = ''
    if ($null -ne $r.Spread) {
        $w = [math]::Min([math]::Round($r.Spread * 4), 100)
        $sp = "<span class=`"spread`"><span class=`"bar`"><i style=`"width:$w%`"></i></span>$($r.Spread)%</span>"
    }
    $hv = if ($r.Heavy) { ' <span class="flag">BASELINE_HEAVY</span>' } else { '' }
    return "<td class=`"num`"><span class=`"val`">$(Esc $r.Val) $(UnitHtml $r.Unit)</span> $sp$hv</td>"
}

function AssertCell($r) {
    if (-not $r) { return '<td><span class="st st-notrun">not run</span></td>' }
    switch ($r.Status) {
        'PASS'     { return '<td><span class="st st-pass">PASS</span></td>' }
        'FAIL'     { return '<td><span class="st st-fail">FAIL</span></td>' }
        'UNSTABLE' { return '<td><span class="st st-unstable">UNSTABLE</span></td>' }
        default    { return "<td><span class=`"st`">$(Esc $r.Status)</span></td>" }
    }
}

# ---- counts, computed not asserted ----
$a66 = @($s66.Rows.Values | Where-Object { $_.Kind -eq 'ASSERT' })
$m66 = @($s66.Rows.Values | Where-Object { $_.Kind -eq 'MEASURE' })
$aDel = @($d66.Rows.Values | Where-Object { $_.Kind -eq 'ASSERT' })
$mDel = @($d66.Rows.Values | Where-Object { $_.Kind -eq 'MEASURE' })
$identical = 0
foreach ($a in $a66) { $o = $s85.Rows[$a.Id]; if ($o -and $o.Status -eq $a.Status) { $identical++ } }

$css = @'
  :root { --bg:#fcfcfd; --ink:#1c2127; --muted:#616a73; --faint:#8b949e; --hair:#dde1e6; --soft:#f3f5f7; --accent:#3565b0; --pass:#1a7f37; --warn:#9a6700; --fail:#b42318; --fail-bg:#fbeeec; --warn-bg:#faf3e1; }
  @media (prefers-color-scheme: dark) { :root { --bg:#15181c; --ink:#e4e8ec; --muted:#99a3ad; --faint:#6e7982; --hair:#2b3138; --soft:#1c2127; --accent:#7aa5e0; --pass:#57ab5a; --warn:#c99728; --fail:#f47067; --fail-bg:#35201e; --warn-bg:#2e2717; } }
  :root[data-theme="light"] { --bg:#fcfcfd; --ink:#1c2127; --muted:#616a73; --faint:#8b949e; --hair:#dde1e6; --soft:#f3f5f7; --accent:#3565b0; --pass:#1a7f37; --warn:#9a6700; --fail:#b42318; --fail-bg:#fbeeec; --warn-bg:#faf3e1; }
  :root[data-theme="dark"] { --bg:#15181c; --ink:#e4e8ec; --muted:#99a3ad; --faint:#6e7982; --hair:#2b3138; --soft:#1c2127; --accent:#7aa5e0; --pass:#57ab5a; --warn:#c99728; --fail:#f47067; --fail-bg:#35201e; --warn-bg:#2e2717; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }
  code,.mono,td.num,.id,.val { font-family:ui-monospace,"Cascadia Mono",Consolas,Menlo,monospace; font-variant-numeric:tabular-nums; }
  main { max-width:75vw; margin:0 auto; padding:0 24px 64px; }
  @media (max-width:1000px) { main { max-width:100%; } }
  a { color:var(--accent); text-decoration:none; } a:hover,a:focus-visible { text-decoration:underline; }
  section { border-top:1px solid var(--hair); padding:32px 0 8px; }
  h2 { margin:0 0 4px; font-size:12px; font-weight:600; letter-spacing:0.09em; text-transform:uppercase; color:var(--muted); }
  .sub { margin:0 0 20px; color:var(--muted); font-size:14px; max-width:64ch; }
  header { display:flex; align-items:baseline; gap:16px; flex-wrap:wrap; padding:40px 0 12px; }
  .wordmark { font-size:22px; font-weight:700; letter-spacing:-0.01em; }
  nav { margin-left:auto; display:flex; gap:18px; font-size:14px; }
  .tagline { margin:0 0 24px; color:var(--muted); font-size:15px; max-width:58ch; }
  .buildmeta { margin:0 0 6px; font-size:13px; color:var(--muted); }
  .scroll { overflow-x:auto; margin:0 0 12px; }
  table { border-collapse:collapse; width:100%; font-size:13.5px; }
  th { text-align:left; font-weight:600; font-size:12px; color:var(--muted); padding:6px 12px 6px 0; border-bottom:1px solid var(--hair); white-space:nowrap; }
  td { padding:7px 12px 7px 0; border-bottom:1px solid var(--hair); vertical-align:top; }
  tbody tr:hover { background:var(--soft); }
  td.num,th.num { white-space:nowrap; }
  .id { font-size:12.5px; white-space:nowrap; }
  .desc { display:block; color:var(--muted); font-size:12px; font-family:system-ui,sans-serif; white-space:normal; max-width:40ch; }
  .grouphead td { padding-top:16px; font-size:11px; font-weight:600; letter-spacing:0.08em; text-transform:uppercase; color:var(--faint); border-bottom:1px solid var(--hair); }
  .grouphead:hover { background:transparent; }
  .st { font-family:ui-monospace,Consolas,monospace; font-size:12px; font-weight:600; letter-spacing:0.04em; white-space:nowrap; }
  .st-pass { color:var(--pass); }
  .st-fail { color:var(--fail); background:var(--fail-bg); padding:1px 6px; border-radius:3px; }
  .st-unstable { color:var(--warn); background:var(--warn-bg); padding:1px 6px; border-radius:3px; }
  .st-notrun { color:var(--faint); font-weight:400; }
  .legend { font-size:13px; color:var(--muted); margin:4px 0 20px; line-height:2; }
  .spread { display:inline-flex; align-items:center; gap:6px; white-space:nowrap; font-size:12px; color:var(--muted); }
  .bar { width:48px; height:4px; background:var(--soft); border-radius:2px; overflow:hidden; flex:none; }
  .bar i { display:block; height:100%; background:var(--accent); border-radius:2px; }
  .withheld { color:var(--muted); background:var(--soft); border:1px solid var(--hair); border-radius:3px; padding:1px 7px; font-size:12px; white-space:nowrap; }
  .flag { color:var(--faint); font-size:11px; font-family:ui-monospace,Consolas,monospace; }
  footer { border-top:1px solid var(--hair); padding:24px 0 0; font-size:13px; color:var(--muted); max-width:66ch; }
  footer p { margin:0 0 10px; }
  caption { text-align:left; caption-side:bottom; font-size:13px; color:var(--muted); padding:8px 0 0; }
  details summary { cursor:pointer; list-style:none; }
  details summary::-webkit-details-marker { display:none; }
  details summary .id::after { content:" \25B8"; color:var(--faint); font-size:10px; }
  details[open] summary .id::after { content:" \25BE"; }
  details summary:hover .id { color:var(--accent); }
  pre.code { margin:8px 0 4px; padding:10px 12px; background:var(--soft); border:1px solid var(--hair); border-radius:4px; overflow-x:auto; font-size:12px; line-height:1.5; tab-size:4; font-family:ui-monospace,"Cascadia Mono",Consolas,Menlo,monospace; white-space:pre; }
  .srcnote { margin:0 0 8px; font-size:11.5px; color:var(--faint); font-family:ui-monospace,Consolas,monospace; }
  .trust { display:grid; grid-template-columns:repeat(auto-fit, minmax(320px, 1fr)); gap:10px 32px; margin:0 0 16px; }
  .trustitem { margin:0; font-size:14px; color:var(--muted); line-height:1.55; }
  .trustitem strong { color:var(--ink); font-weight:600; display:block; }
  details.inner { margin:2px 0 8px; }
  details.inner summary { display:inline-block; }
  details.inner summary:hover { color:var(--accent); }
  details.inner summary::before { content:"\25B8 "; font-size:10px; }
  details.inner[open] summary::before { content:"\25BE "; }
'@

$L = New-Object System.Collections.Generic.List[string]
$L.Add('<!DOCTYPE html>')
$L.Add('<html lang="en">')
$L.Add('<head>')
$L.Add('<meta charset="utf-8">')
$L.Add('<meta name="viewport" content="width=device-width, initial-scale=1">')
$L.Add('<title>dm-bench, BYOND engine benchmarks</title>')
$L.Add("<style>$css</style>")
$L.Add('</head>')
$L.Add('<body>')
$L.Add('<main>')

$L.Add('<header><span class="wordmark">dm-bench</span><nav aria-label="site"><a href="#trust">Trust</a><a href="#behaviour">Behaviour</a><a href="#costs">Costs</a><a href="#rules">Rules</a><a href="#method">Method</a></nav></header>')
$L.Add('<p class="tagline">The measured behaviour and cost of BYOND engine operations, per build, reproducibly. Most published BYOND performance advice is untested; this replaces assertion with measurement. The repository is the database: every figure below regenerates from a version-stamped TSV baseline.</p>')
$L.Add("<p class=`"buildmeta mono`">516.1666 and 516.1685 &middot; windows &middot; main suite $($a66.Count) assertions / $($m66.Count) measurements per build &middot; del suite $($aDel.Count) / $($mDel.Count) &middot; $identical of $($a66.Count) assertion verdicts identical across builds</p>")

# ---- why trust this ----
$L.Add('<section id="trust">')
$L.Add('<h2>Why trust these numbers</h2>')
$L.Add('<p class="sub">Most BYOND performance advice has been repeated for years without anyone timing it. This page exists so you can check instead of trust. Here is what stands behind the numbers.</p>')
$L.Add('<div class="trust">')
$trust = @(
    @('This page is generated from data files.', 'Every figure comes from a results file in the repository, including the ratios in the rules table at the bottom, which are computed when the page is built. Nothing here is typed in by hand, so nothing can quietly drift away from the data. Until 2026-08-01 that was true of the tables but not of the rules, two of which quoted a harness that is not in the repository; they were removed rather than restated.'),
    @('A result cannot be filed under the wrong engine.', 'The suite names its own output file from the engine version it detects at runtime, the runner refuses build folders whose binaries report a different version, and the merge tool rejects runs from different builds, different priorities, or runs that died early.'),
    @('Every figure shows its spread.', 'Each number is the median of three separate runs, and the variation between those runs is printed right next to it. A number that jumped around between runs says so.'),
    @('The harness measures itself before it measures the engine.', 'At startup the suite times an empty loop, and that cost gets subtracted from the small measurements so the loop machinery is never billed to the operation. Where the subtracted part is still a large share of a reading, the row carries a flag saying so.'),
    @('Warm-up passes are thrown away.', 'The first pass of a workload reads about 3% high on this machine, measured directly. Form comparisons discard a warm-up round, rotate which form goes first, and rest a tick between arms, so no result benefits from its position in line.'),
    @('Unreliable readings say so.', 'When a measurement is too small for the clock to resolve, the row prints "withheld". A real-looking number in that spot would be worse than an empty one.'),
    @('Click any row to see the code.', 'The DM code behind each figure is pulled from the test source when this page is built. The code you read is the code that ran.'),
    @('Comparisons prove they are fair first.', 'When two ways of doing the same thing are compared, a check first confirms they produce identical results. Timing two snippets that do different work would prove nothing, and one published 19x claim died exactly that way.'),
    @('Some tests exist to catch the harness lying.', 'The istype scaling test ships with a companion that is expected to scale (typesof), so if both come out flat, the harness is measuring nothing and fails loudly. Another assertion confirms discarded test code still executes, so a future compiler that optimizes it away breaks the suite instead of quietly zeroing every figure.'),
    @('An unstable test is its own alarm.', 'A pass only counts if all three runs passed. When runs disagree, the merge marks the row UNSTABLE and treats it as a defect in the suite to be diagnosed, never as engine news, and verdicts are never averaged into a majority.'),
    @('The classic measurement traps have each been tested directly.', 'Compiled binaries were diffed to confirm the engine really executes discarded test code, and to find the one case where it does not. del() runs in its own process because its cost depends on everything the process did before. Every timing passes a clock-resolution check or gets flagged.'),
    @('Results are cross-checked on other machines and builds.', 'Key findings were reproduced on separate hardware and a second engine version. The ratios agreed, which is what should transfer. The raw times differed, which is what should differ.'),
    @('The whole pipeline is open.', 'The harness, the runner, the results files, and the generator that built this page live in one repository. Clone it, drop a BYOND release into a folder, and rerun everything. Your absolute times will differ; your ratios should not.'),
    @('What could not be tested is not on the page.', 'Plenty of circulating BYOND claims have no harness here yet. Those are left out entirely, so every figure and every rule shown has a measurement behind it. The docs are also machine-checked: a script verifies that every count quoted in prose matches the data files and fails otherwise.'),
    @('Mistakes stay on the record.', 'When a published figure turns out to be wrong, it gets corrected in place with the old value still shown. The repository history contains every wrong number this project has published and the check that caught it.'),
    @('Even the machine had to qualify.', 'Before this machine could publish, its noise floor was measured at about 15% on long-running rows. A scheduling experiment then showed half of that came from the OS and cut it to 10% by raising process priority. Its sensitivity to background load was mapped across a day, and its clock was calibrated against a wall-clock reference and checked for linearity across a 500x workload range. Any machine that joins, including yours if you run the suite, goes through the same steps before its column counts.')
)
foreach ($t in $trust) {
    $L.Add("<p class=`"trustitem`"><strong>$($t[0])</strong> $($t[1])</p>")
}
$L.Add('</div>')
$L.Add('<p class="sub">One limit to know about: absolute times come from one machine and carry an error bar of at least 15%. The ratios between rows are the numbers meant to travel to your hardware.</p>')
$L.Add('</section>')

# ---- behaviour matrix ----
$L.Add('<section id="behaviour">')
$L.Add('<h2>Behaviour</h2>')
$L.Add('<p class="sub">Every assertion encodes engine behaviour with a known answer. A FAIL here usually means the engine changed, and catching that is this table''s entire job: a future build that starts collecting reference cycles, or stops emitting discarded expressions, or fixes the 2^24 loop trap, flips a cell here before its release notes say so.</p>')
$L.Add('<div class="scroll"><table>')
$L.Add('<thead><tr><th>assertion</th><th>516.1666</th><th>516.1685</th></tr></thead><tbody>')
$cat = ''
foreach ($r in $a66) {
    if ($r.Cat -ne $cat) {
        $cat = $r.Cat
        $L.Add("<tr class=`"grouphead`"><td colspan=`"3`">$(Esc $cat)</td></tr>")
    }
    $L.Add("<tr>$(LabelCell $r)$(AssertCell $r)$(AssertCell $s85.Rows[$r.Id])</tr>")
}
$L.Add('<tr class="grouphead"><td colspan="3">del &middot; own process, suite_del.dme</td></tr>')
foreach ($r in $aDel) {
    $L.Add("<tr>$(LabelCell $r)$(AssertCell $r)$(AssertCell $d85.Rows[$r.Id])</tr>")
}
$L.Add('</tbody></table></div>')
$L.Add('<p class="legend"><span class="st st-pass">PASS</span> behaviour matches the recorded answer &nbsp;&middot;&nbsp; <span class="st st-fail">FAIL</span> behaviour changed in this build &nbsp;&middot;&nbsp; <span class="st st-unstable">UNSTABLE</span> verdict varied between runs, a suite defect, not an engine result</p>')
$L.Add('</section>')

# ---- measurements ----
$L.Add('<section id="costs">')
$L.Add('<h2>Measured costs</h2>')
$L.Add('<p class="sub">Median of three runs per build at High process priority, spread beside every figure (the bar fills at 25%). Rows that failed a resolution check print as withheld, because below a certain size the clock produces noise shaped like data. Absolute times belong to this machine; the ratios between rows are what carry over to yours. The two builds were measured in separate sittings, so compare ratios within a build rather than absolutes across builds. <strong>Click any row to see the DM code that produced it</strong>, extracted from the suite source when this page was generated, so it cannot drift from what ran.</p>')
$L.Add('<div class="scroll"><table>')
$L.Add('<thead><tr><th>measurement</th><th class="num">516.1666</th><th class="num">516.1685</th></tr></thead><tbody>')
$cat = ''
foreach ($r in $m66) {
    if ($r.Cat -ne $cat) {
        $cat = $r.Cat
        $label = $cat
        if ($cat -eq 'framework') { $label = 'framework &middot; harness self-measurement' }
        if ($cat -eq 'xcheck')    { $label = 'xcheck &middot; instrument cross-checks' }
        $L.Add("<tr class=`"grouphead`"><td colspan=`"3`">$label</td></tr>")
    }
    $L.Add("<tr>$(LabelCell $r)$(MeasureCell $r)$(MeasureCell $s85.Rows[$r.Id])</tr>")
}
$L.Add('<tr class="grouphead"><td colspan="3">del &middot; own process, three runs merged per build</td></tr>')
foreach ($r in $mDel) {
    $L.Add("<tr>$(LabelCell $r)$(MeasureCell $r)$(MeasureCell $d85.Rows[$r.Id])</tr>")
}
$L.Add('</tbody></table></div>')
$L.Add('</section>')

# ---- design rules ----
$L.Add('<section id="rules">')
$L.Add('<h2>What to do about it</h2>')
$L.Add('<p class="sub">The ratios that survive measurement, stated as rules. Ratios hold across machines; the absolute times above do not. Every figure in this column is computed from the same baselines as the tables above, at generation time. A rule whose rows are missing or withheld in a baseline does not appear at all, which is why some advice you may have seen on this page before is gone: it rested on a harness that is not in the repository.</p>')
$L.Add('<div class="scroll"><table>')
$L.Add('<thead><tr><th>rule</th><th class="num">measured advantage</th></tr></thead><tbody>')

# Ratios computed from the merges, never typed in. Until 2026-08-01 this table
# was a hardcoded list, two of whose figures ("77x crowded", "9.2 to 9.6x")
# came from harnesses absent from the tree, on a page whose own trust section
# says nothing here is typed by hand. Those two rules are gone rather than
# restated: the page's rule is that what could not be measured here is absent.
function RowVal($set, [string]$id) {
    $r = $set.Rows[$id]
    if (-not $r) { return $null }
    if ($r.Withheld) { return $null }
    $d = 0.0
    if (-not [double]::TryParse($r.Val, [ref]$d)) { return $null }
    if ($d -eq 0) { return $null }
    return $d
}
# One ratio per build, so a build-dependent advantage shows as one.
function RatioTxt($setA, $setB, [string]$hi, [string]$lo, [string]$labA, [string]$labB) {
    $out = @()
    foreach ($pair in @(@($setA, $labA), @($setB, $labB))) {
        $h = RowVal $pair[0] $hi
        $l = RowVal $pair[0] $lo
        if ($null -eq $h -or $null -eq $l) { continue }
        $out += "{0}x on {1}" -f ([math]::Round($h / $l, 1)), $pair[1]
    }
    if ($out.Count -eq 0) { return $null }
    return ($out -join ', ')
}

$rules = New-Object System.Collections.Generic.List[object]
# clutter_0, not build_only/inline_typed. Both pairs time the same comparison,
# but the clutter pair measures its two arms adjacently in one block, so drift
# cancels; the other pair is separated by the whole two-pass section and read
# 8.2x where the adjacent pair read 9.5x. The spec sheet quotes the adjacent
# pair, and two published figures for one claim must not disagree.
$typicalTyped = RatioTxt $s66 $s85 'view.clutter_0_raw' 'view.clutter_0_typed' '1666' '1685'
$crowdedTyped = RatioTxt $s66 $s85 'view.clutter_1200_raw' 'view.clutter_1200_typed' '1666' '1685'
if ($typicalTyped -and $crowdedTyped) {
    $rules.Add(@('Iterate <code>for(var/mob/M in view())</code> instead of assigning view() to a list', "$typicalTyped at 667 atoms; $crowdedTyped with 1,200 more in view"))
}
$twoPass = RatioTxt $s66 $s85 'view.twopass_cached' 'view.twopass_requery' '1666' '1685'
if ($twoPass) { $rules.Add(@('Re-query view() for a second pass instead of caching it', $twoPass)) }
$rangeVsView = RatioTxt $s66 $s85 'view.family_view' 'view.family_range' '1666' '1685'
if ($rangeVsView) { $rules.Add(@('Use range() when line of sight is not needed', $rangeVsView)) }
$locVsMove = RatioTxt $s66 $s85 'movement.move_proc' 'movement.loc_assign' '1666' '1685'
if ($locVsMove) { $rules.Add(@('Assign <code>loc</code> directly when Enter/Exit callbacks are not needed', $locVsMove)) }
$assoc = RatioTxt $s66 $s85 'lists.in_n5000' 'lists.assoc_n5000' '1666' '1685'
if ($assoc) { $rules.Add(@('Use an associative list for lookups instead of <code>in</code>, at 5,000 entries', $assoc)) }
$addVsPlus = RatioTxt $s66 $s85 'lists.build_add' 'lists.build_plus' '1666' '1685'
if ($addVsPlus) { $rules.Add(@('Build lists with <code>+=</code> rather than .Add()', $addVsPlus)) }
# del() is stated as a cost, not as a ratio: this tree measures del() at
# population, but has no published row for the null-assignment arm, so a
# multiple would have an unmeasured denominator.
$del300 = RowVal $d66 'del.live_300000'
$del300b = RowVal $d85 'del.live_300000'
if ($del300 -and $del300b) {
    $rules.Add(@('Drop the last reference and let refcounting collect, instead of calling del()', ("del() costs {0:N0} &micro;s on 1666 and {1:N0} &micro;s on 1685 at 300,000 live objects" -f [math]::Round($del300), [math]::Round($del300b))))
}
$rules.Add(@('Clear <code>contents</code> before nullspacing an atom', 'prevents a permanent leak'))
$rules.Add(@('Never define a flag above bit 23', 'masks past 2^24 are silently zero'))
$rules.Add(@('Keep every loop under 16,777,216 iterations', 'loops past 2^24 never terminate'))
foreach ($rule in $rules) {
    $L.Add("<tr><td>$($rule[0])</td><td class=`"num`">$($rule[1])</td></tr>")
}
$L.Add('</tbody></table>')
$L.Add('<caption>Ratios computed from the merged baselines when this page was generated. The last three rules carry no figure because they are behaviour, asserted in the table above rather than timed.</caption></div>')
$L.Add('<p class="sub">Type-test strategy (istype, type ==, bitfield, associative category) has no measurable performance impact; istype is flat across tree depth and relatedness. Dispatch is a design decision, not a performance one.</p>')
$L.Add('</section>')

# ---- method ----
$L.Add('<section id="method">')
$L.Add('<h2>Method</h2>')
$L.Add('<p class="sub">Hypothesis, test with a control, empirical data, repeat. Every entry is a falsifiable statement about the engine with a harness behind it.</p>')
$L.Add('<footer>')
$L.Add('<p>Every baseline is three runs merged: medians per row, observed spread published, assertions PASS only if every run passed. Runs execute DreamDaemon at High process priority, which halves long-row spread; the residual spread floor is thermal and cache state, measured at about 10 to 15%, so absolute figures carry at least that error bar and sub-microsecond values are one significant figure. Timing rows pass resolution guards (a 0.1s wall clock quantum, a tick-usage floor, a subtraction-noise check) or are withheld.</p>')
$L.Add('<p>del() measurements run in their own process because peak concurrent population permanently raises later del() cost in the same process, a property this suite measured and every earlier published del() figure silently suffered from.</p>')
$L.Add('<p>Measured on DreamDaemon 516.1666 and 516.1685, Windows 11, single machine. Engine behaviour claims are tested, not cited; where a claim could not be tested, it is absent rather than repeated.</p>')
$L.Add("<p class=`"mono`">Generated $(Get-Date -Format 'yyyy-MM-dd') from results/516.1666-windows-merged.tsv, results/516.1685-windows-merged.tsv, results/516.1666-windows-del-v3.tsv, results/516.1685-windows-del-v3.tsv</p>")
$L.Add('</footer>')
$L.Add('</section>')

$L.Add('</main>')
$L.Add('</body>')
$L.Add('</html>')

[System.IO.File]::WriteAllLines($Out, $L, (New-Object System.Text.UTF8Encoding($false)))
"wrote $Out ($((Get-Item $Out).Length) bytes, $($L.Count) lines)"
"assertions: $($a66.Count) suite + $($aDel.Count) del; measurements: $($m66.Count) suite + $($mDel.Count) del; verdicts identical: $identical/$($a66.Count)"
