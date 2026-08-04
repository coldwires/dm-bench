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
used. Extract a release into a new folder and the runner finds it. The
binaries are Byond Software's and are not redistributed here.

`.\tools\fetch-byond.ps1 -Version 516.1685` will download and lay one out for
you. **Exercised end to end on 2026-08-03**: it fetched 516.1679 in about 50
seconds, extracted it, verified that the binaries report the version the
folder claims, and `run.ps1 -List` then discovered it. If packaging ever
changes, pass `-Url` with the real one; extracting a release by hand into
`byond-standalones/<version>/` is equivalent and always works.

Two things worth knowing before scripting it. byond.com rate-limits: three
requests in quick succession returned 429 on the third. And the script
replaces the target directory, so `-Force` on a build you already have will
delete it before the download starts.

`tools/fetch-byond.sh` is the Linux counterpart. Its URL shape is checked but
the script itself has not been run end to end, unlike the PowerShell one.

```powershell
.\tools\run.ps1 -List                                  # discovered builds
.\tools\run.ps1 -Suite suite_del -Version 516.1685
.\tools\run.ps1 -Suite suite -Version all
```

Runs execute DreamDaemon at High process priority by default, which halves the
between-run spread of long rows (see Precision); pass `-Priority Normal` to
override. The runner stamps `# runner_priority` into each result file, and
`merge-runs.ps1` refuses to merge runs taken at different priorities, because
priority changes measured spread. Baselines dated before 2026-07-31 predate the
stamp and were taken at normal priority.

Manually:

```
byond-standalones\516.1666\bin\dm.exe suite\suite.dme
byond-standalones\516.1666\bin\dd.exe suite\suite.dmb 47899 -trusted -invisible
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
.\tools\merge-runs.ps1 -Runs build\run1,build\run2,build\run3 -Out results\516.1666-windows-merged.tsv
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
suite/suite.dme            manifest, non-contaminating tests
suite/suite_del.dme        del() tests, separate process by necessity
suite/src/framework.dm     emission, assertions, clock calibration, guards
suite/src/assert_*.dm      known-answer behaviour tests
suite/src/perf_*.dm        cost measurements

tools/run.ps1              build discovery and runner
tools/merge-runs.ps1       merge N runs into one baseline, median and spread
tools/check-docs.ps1       documentation consistency check
tools/fetch-byond.ps1      download a BYOND release into byond-standalones/

results/                   baselines, one per build and system
site/gen-site.ps1          renders results/ into site/index.html
docs/BYOND-PERF-SPEC.md    measured results
docs/METHOD.md             how these tests were run, and how a machine qualifies
net/                       two-machine client probe, not part of either suite
extras/                    unported harnesses and standalone demonstrations
LICENSE                    MIT, harness and documents only, not BYOND itself
```

Everything under `suite/` is the thing being published: DM source and nothing
else. Everything under `tools/` runs it. `results/` is the data those tools
produced, and `site/` renders that data into a page. Three directories the
repository does not carry are created locally by use: `byond-standalones/`
holds one full BYOND per build, `build/` is per-run scratch, and a private
`working/` holds the maintainers' operating notes.

`extras/load.dme` and `extras/respawn.dme` are earlier harnesses, not yet
ported to the framework. `extras/noeffect.dme` is a standalone demonstration
of the discarded-expression compiler behaviour the measurement form depends
on.

### The harness and the suite are separable

`suite/src/framework.dm` is the library: output format, assertions, clock
calibration, the resolution guards and the emission helpers. It knows nothing
about what is being measured. The `assert_*` and `perf_*` files are one suite
written with it, and the two `.dme` manifests are what bind a set of them into
a runnable world.

To measure something else with the same guarantees, include `framework.dm` in
your own manifest, call `Header()`, `CalibrateClock()` and
`CalibrateBaseline()` once, and route every timing through `Measure`,
`MeasureU`, `MeasureTU` or `MeasureDelta`. `Value()` exists for counts and
labels and applies no resolution check, which is why `check-docs.ps1` rejects
a `Value()` call carrying a time unit.

Two rules travel with the library. Name a measurement's iteration count once
and use it both to drive the loop and to divide the result, because passing
them separately is how two rows here published 1.83x high. And keep anything
that grows the live object population out of the same process as a `del()`
measurement.

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

**Figures come from a dedicated headless Linux machine**, which runs nothing
else and has its CPU frequency clamped to base. A Windows desktop runs the
same suite as a cross-check. The two agree on every assertion and on every
cost outside the io layer, and where they disagree the results page says so
rather than averaging them. The desktop is not the source of published figures
because it is in daily use: its runs agree with each other to about 9%,
against about 2% on the measuring machine.

All baselines were regenerated on 2026-08-03, three runs per build of each
suite on each machine, after every measured row outside the scheduler moved to
`world.tick_usage`.

`suite_del.dme` passes 10 of 10 on 516.1666 and 516.1685 on both machines,
with the population sweep reaching 300,000 live objects. Its population
figures publish as median plus range, because the del() scan is a memory walk:
the shape (superlinear growth, flat null cost, permanent residual) holds
everywhere and `del.population_sweep_monotonic` asserts it, but the slope
belongs to the machine. Going from 50,000 to 300,000 live objects costs 12.7x
the time on one machine here and 40x on the other. Carry the shape, not the
coefficient.

`suite.dme`, three runs merged per build on each machine: 59 assertions, 118
measurements, 0 unstable anywhere.

**58 of the 59 carry the same verdict on both builds and both operating
systems.** The one that does not is `lists.find_costs_about_the_same_as_in`,
which passes on 516.1666 and fails on 516.1685, and it is doing exactly what it
was added for. A FAIL in this table is not a defect in the suite; it is the
engine having changed, and this one is a 4x slowdown in `L.Find()` introduced
in 516.1674. If a later build repairs it, the row flips back to PASS on the day
it happens.

Every other verdict agreeing across two builds and two operating systems is the
other half of the result, and it is what makes the disagreement legible.

Two rows in 118 exceed 25% spread on the measuring machine. On the desktop 19
and 27 do, which is that machine rather than the suite.

**The measurement half earned its keep in the same cycle.** `L.Find()` is about
**4x slower from 516.1674 onward**, per element rather than per call,
reproduced on both machines with every control flat, including `L.Copy()`. The
boundary was bisected across six builds: clean at 516.1673, regressed at
516.1674, still regressed at 516.1685. Details in
`docs/BYOND-PERF-SPEC.md` §3. No mechanism is offered, because this repository
does not hold BYOND's release notes.

The lookup, call and allocation rows use the discarded-unroll instrument,
which cut the subtracted-baseline share of those rows from up to 40% to a few
percent and reduced the `BASELINE_HEAVY` count to the four variable reads.
Those keep an accumulator because the compiler eliminates a discarded pure
read outright, so a converted row would time an empty loop and publish a
plausible near-zero with nothing flagged.

Two rows in the del suite are withheld on the measuring machine rather than
published: the zero-reference case, which is below the resolution floor on
every machine tried, and the 256-reference case, whose figure is a difference
between two timed blocks that this machine deletes too quickly to separate
from its own error. Both say so where they would otherwise appear.

**Six of the assertions encode invariants rather than behaviour**: that the
view() radius sweep rises at every step, that three rows timing the same
operation agree, that linear search scales with list size while associative
lookup does not, that a longer write is not cheaper than a shorter one, and
that del() cost rises with population. They exist because a wrong divisor
published two rows 1.83x high through every repeatability check the suite had.
Each has been observed failing, via a compiled-out `BREAKCHECK` block that
reintroduces the defect it guards against.

### Precision

**The error bar belongs to the machine, not to the project**, and the two
machines here differ by about 4x. Median run-to-run spread by measurement size,
three runs of one build on each:

| value band | linux, dedicated | windows, in daily use |
|---|---|---|
| under 0.2 us | 0% | 12% |
| 0.2 to 1 us | 3% | 9% |
| 1 to 10 us | 3% | 8% |
| over 10 us | 2% | 5% |

Overall, one row in 92 exceeds 25% spread on the measuring machine against 24
on the desktop. **That gap is what "qualify the machine before publishing its
numbers" is for**, and it is why the two are separate columns rather than an
average.

Two cautions, both learned by getting them wrong here first.

**A spread column is only evidence down to the resolution of what produced
it.** These figures come from `world.tick_usage`. The same suite timed with the
0.1s wall clock reported the desktop at 9% overall and the Linux box at 0% on
long rows, because three runs landing in one clock quantum cannot disagree.
Neither number was precision; both were the instrument. The 0% in the top row
above is the surviving edge of the same effect, since values are emitted at two
decimals and a 0.08 us row cannot express a finer disagreement than that.

**So do not read a sub-microsecond figure to two decimal places**, whatever the
spread column says: those rows also subtract a calibrated baseline, which is a
large share of what they measure. Ratios between rows measured close together
are sounder than absolutes, because the two share machine conditions and drift
partly cancels. A ratio transfers between machines only when both of its arms
are bounded by the same resource; computation against computation travels,
buffered logging against an unbuffered file write does not.

Process priority is a per-machine answer, not a rule: elevating it halved
long-row spread on the desktop and does nothing on the dedicated box, where no
other process competes. The clock is not the limit either way.
`world.tick_usage` measures linear to within 2.4% across a 500x range of
workload.

How a measuring machine qualifies before its numbers are published, and the
full answer to "how were these tests run", is in `METHOD.md`.

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
