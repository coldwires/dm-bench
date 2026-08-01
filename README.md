# dm-bench

Measures the cost and behaviour of BYOND engine operations, against a named
build, reproducibly.

Most published BYOND performance advice is untested. Some of it is wrong, some
was true and stopped being true, and some describes a cost that no longer exists.
This suite replaces assertion with measurement.

## Method

Every entry follows the same cycle.

**Hypothesis.** A specific, falsifiable statement about the engine. "Assigning
`loc` is cheaper than calling `Move()`." "Reference count does not affect
`del()` cost."

**Test.** A harness that measures it, with a control that would behave
differently if the hypothesis were false. A measurement without a control is not
a test. Where two snippets are claimed to be alternatives, the harness asserts
they produce identical output before comparing timings.

**Empirical data.** A number, the build it came from, and enough repeats to know
whether it is stable. Results are TSV with stable ids, so runs from different
builds diff cleanly.

**Repeat.** On a new build, or when a number looks wrong.

A hypothesis that survives is recorded with its data. One that fails is recorded
as failed, with the data that killed it. Both are results.

### Two kinds of row

**ASSERT** has a known-correct answer and reports PASS or FAIL. A FAIL is not
automatically bad. If `lifetime.cycle_not_collected` ever fails, the engine
started collecting `loc`/`contents` reference cycles, and a class of mandatory
teardown code can be deleted. That is the suite working.

**MEASURE** has no correct answer. Absolute times do not travel between
machines; ratios do. Compare a build against itself on the same hardware.

### Rules the harness enforces

- **Every measurement clears a resolution guard.** `MIN_DS` (15 deciseconds) for
  `world.timeofday` rows, `MIN_PCT` (20 percent of a tick) for
  `world.tick_usage` rows. Short rows are flagged `LOW_RESOLUTION`.
- **A difference gets a second guard.** The error of `a - b` is the sum of both
  arms' errors, so a small delta between two large arms is noise even when each
  arm is individually well resolved. Flagged `SUBTRACTION_NOISE`.
- **A flagged row is not evidence.** Do not publish one.
- **Run three times before trusting a baseline.** A single run compared against a
  stored baseline cannot detect an unstable suite.
- **Record the build with every result.** The suite names its own output file
  from `world.byond_version` and `world.byond_build`, so a result cannot be filed
  under the wrong engine by hand.

## Running

Builds live in `byond-standalones/<version>/bin/`, one complete BYOND each.
Nothing is installed, no registry key is written, and the system BYOND is not
used. Extract a release into a new folder and the runner finds it.

```powershell
.\run.ps1 -List                                  # discovered builds
.\run.ps1 -Suite suite_del -Version 516.1685
.\run.ps1 -Suite suite -Version all
```

Runs execute DreamDaemon at High process priority by default, which halves the
between-run spread of long rows (see Precision); pass `-Priority Normal` to
override. The runner stamps `# runner_priority` into each result file, and
`merge-runs.ps1` refuses to merge runs taken at different priorities, because
priority changes measured spread. Baselines dated before 2026-07-31 predate the
stamp and were taken at normal priority.

Manually:

```
byond-standalones\516.1666\bin\dm.exe suite.dme
byond-standalones\516.1666\bin\dd.exe suite.dmb 47899 -trusted -invisible
```

On Linux, set `LD_LIBRARY_PATH` to the BYOND `bin` directory first.

`suite_del.dme` **must run in its own process.** `del()` cost is driven by live
object count, and peak concurrent population leaves a permanent residual, so any
test that grows the population corrupts every later `del()` reading in that
process.

Comparing builds:

```
diff <(cut -f1-8 results/516.1666-windows-del-v2.tsv) \
     <(cut -f1-8 results/516.1685-windows-del-v2.tsv)
```

Column 9 is the resolution figure behind the row, deciseconds or percent of a
tick depending on the clock. It is excluded from diffs as timing noise and kept
so an under-resolved row stays auditable.

Building a baseline from several runs:

```powershell
.\merge-runs.ps1 -Runs build\run1,build\run2,build\run3 -Out results\516.1666-windows-merged.tsv
```

A baseline from a single run cannot show whether the suite is stable, so the
baseline is a merge. MEASURE rows become the median across runs, with the
observed min, max and spread recorded per row, and rows varying more than 25%
are marked `WIDE_SPREAD`. ASSERT rows become PASS only if every run passed and
`UNSTABLE` if the runs disagree, because an unstable assertion is a defect in
the suite rather than a property of the engine, and averaging a verdict would
hide the thing worth finding. The merge refuses runs from different builds, and
refuses a run that ended early. It exits non-zero if anything is unstable.

`check-docs.ps1` verifies that counts quoted in the documentation match the
baselines, that cross-references resolve, and that every file path named in a
document exists. It exits non-zero on failure.

## Layout

```
run.ps1              build discovery and runner
merge-runs.ps1       merge N runs into one baseline, median and spread
check-docs.ps1       documentation consistency check
suite.dme            manifest, non-contaminating tests
suite_del.dme        del() tests, separate process by necessity
src/framework.dm     emission, assertions, clock calibration, resolution guards
src/assert_*.dm      known-answer behaviour tests
src/perf_*.dm        cost measurements
results/             baselines, one per build and system
net/                 two-machine client probe, not part of either suite
BYOND-PERF-SPEC.md   measured results
```

`load.dme` and `respawn.dme` are earlier harnesses, not yet ported to the
framework.

| Module | Covers |
|---|---|
| `assert_lifetime` | refcounting, reference cycles, `del(src)` semantics, spawn pinning |
| `assert_numeric` | the 2^24 bound, loop non-termination, accumulator saturation, bit shifts |
| `assert_scheduler` | tick hook, wake ordering, `spawn(0)`, context copying, scheduler load |
| `perf_view` | the view family, typed-loop filtering, radius, clutter, line of sight |
| `perf_core` | lists, dispatch, calls, variable access, strings, allocation, movement |
| `perf_io` | file and `world.log` cost, yielding, perturbation self-check |
| `perf_calls_deep` | hard against soft calls, argument copying, profiler overhead |
| `del_isolated` | `del()` by reference count, population, turfs, churn, residual |

## State of the results

`suite_del.dme` passes 7 of 7 on 516.1666 and 516.1685, three runs each. Its
figures were re-derived after the original timing method proved too coarse to
distinguish them, and are stable.

`suite.dme`, three High-priority runs merged per build: 47 assertions, 92
measurements, 47 passed, 0 failed, 0 unstable on both 516.1666 and 516.1685,
with every assertion verdict identical across the two builds. 8 of 92 rows on
1666 and 7 of 92 on 1685 vary more than 25% across their triples, and those
that do are the rows pinned at the instrument's floor (the vars reads) or
derived ratios. The lookup, call and allocation rows use the discarded-unroll
instrument as of 2026-07-31, which cut the subtracted-baseline share of those
rows from up to 40% to a few percent and reduced the BASELINE_HEAVY count
from 13 rows to the four vars reads, which keep an accumulator because the
compiler eliminates a discarded pure read outright. A normal-priority triple
is kept alongside as `516.1666-windows-normal-priority.tsv` as the priority
experiment's record; the count of wide rows tracks ambient machine load and
ranged 11 to 30 across same-day triples.

### Precision

**Absolute figures carry an error bar of at least 15%.** That is measured, not
estimated. Spread by measurement size, three runs on one build:

| value band | rows | median spread |
|---|---|---|
| under 0.2 us | 25 | 21% |
| 0.2 to 1 us | 15 | 13% |
| 1 to 10 us | 15 | 14% |
| over 10 us | 29 | 15% |

If timing resolution were the limit, small measurements would be far worse than
large ones. Rows over 10 us run for seconds, have negligible quantization and
subtract no baseline, and still scatter 15%. That floor is machine variance:
scheduling, thermal behaviour, cache state. It survived sleeps between
measurements, order rotation, a discarded warm-up round and eight samples.

About half of the long-row floor is OS scheduling, measured directly: running
DreamDaemon at High priority took rows over 10 us from 18.3% to 9.9% median
spread, three interleaved runs per condition. High priority has been the
runner default since 2026-07-31. The remainder is thermal and cache state and
does not yield to priority or to any choice of clock.

The clock is not the limit. `world.tick_usage` measures linear to within 2.4%
across a 500x range of workload.

**So do not read a sub-microsecond figure to two decimal places.** 0.09 and 0.11
do not differ at this precision. Ratios between rows measured close together are
sounder than absolutes, because the two share machine conditions and drift
partly cancels.

Parts of `BYOND-PERF-SPEC.md` predate the current framework, come from harnesses
not in this repository, and still print more precision than the data supports.
Those sections are marked in place.

## Client testing needs two machines

One machine hosts one real key plus one guest, two clients maximum, because BYOND
identifies clients by ckey and a second connection presenting an existing key
evicts the first. More clients need more accounts or more machines. The probe
under `net/` is therefore not part of either suite.

Server and client builds are independently selectable: launch `dd.exe` from one
version directory and `dreamseeker.exe` from another, and `client.byond_build`
reports the client that connected.

## Style

DM tree syntax, tabs, no leading slash on the root token. Code lives in `.dm`
files; a `.dme` is a manifest, though the suites deliberately keep a little world
setup in theirs.
