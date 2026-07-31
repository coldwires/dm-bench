# BYOND benchmark suite

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

`check-docs.ps1` verifies that counts quoted in the documentation match the
baselines, that cross-references resolve, and that every file path named in a
document exists. It exits non-zero on failure.

## Layout

```
run.ps1              build discovery and runner
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

`suite.dme` passes 44 of 44 on two runs of 516.1666 and 43 of 44 on a third. One
assertion is unstable, and 26 of its 77 measured rows vary by more than 25%
between runs on the same build. The cause is understood: sub-microsecond rows
subtract an empty-loop baseline comparable in size to the operation itself, and
that baseline is calibrated once per run. A fix is in progress.

**Do not quote a sub-microsecond figure from `suite.dme` to two decimal places.**
Ratios at the 10x scale the suite was built for are sound.

Parts of `BYOND-PERF-SPEC.md` predate the current framework and come from
harnesses not in this repository. Those sections are marked in place.

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
