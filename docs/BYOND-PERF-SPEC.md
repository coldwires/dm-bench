# BYOND 516 Performance Spec Sheet

Measured cost of common BYOND operations.

## Test conditions

- **Figures come from DreamDaemon 516.1666 on the measuring machine**, a dedicated headless Linux box that runs nothing else, with its CPU frequency clamped to base so thermal state cannot become timing noise. 516.1685 is quoted wherever the two builds differ.
- **A Windows desktop runs the same suite as a cross-check.** It agrees on every assertion and on every cost outside the io layer, and it appears in this page wherever the two genuinely disagree. It is not the source of the figures, because it is in daily use and cannot be quiesced: its runs agree with each other to about 9%, against about 2% on the measuring machine.
- Each machine runs in the condition its own qualification measured as best, which is not the same answer on both: raising process priority halves long-row spread on the desktop and does nothing on the dedicated box, where nothing competes for the CPU.
- Every measured row outside the scheduler is timed with `world.tick_usage`, calibrated per run against a long wall-clock reference at 490 to 520 µs per percent of a tick, after establishing that it is linear to within 2.4% across a 500x range of workload.
- Empty loop baseline: 0.08 µs with an accumulator, 0.03 without. The first is removed from accumulator-form rows, the second from the unrolled discarded-result rows.
- Sections 1 to 11 and 13 to 14: no clients connected. Section 12: server on a remote Linux box, clients on a separate machine over the public internet.
- **Every figure regenerates from three runs per build merged**, medians per row with the observed spread recorded: 59 assertions and 118 measurements for `suite.dme`, 10 and 17 for `suite_del.dme`, and 0 unstable anywhere. **Every assertion carries the same verdict on both operating systems.** One differs across builds: `lists.find_costs_about_the_same_as_in` passes on 516.1666 and fails on 516.1685, on both machines, which is the `Find()` regression in §3 and is the suite working rather than a defect.
- **A row that fails a resolution guard is withheld rather than printed.** One row in section 2 is withheld on the measuring machine for exactly this reason and says so in place. A second, the 256-reference arm, was withheld in earlier printings and is restored, because it clears its guard in the baselines this page is now derived from.
- **Figures are printed at the precision the harness emits, which is finer than the measurement supports.** Repeatability is about 2% on the measuring machine, but that is not the same as accuracy: sub-microsecond rows subtract a calibrated baseline, and values are emitted at two decimals, so a row reading 0.12 cannot express a difference finer than about 8% whatever the machine does. **Do not read 0.12 against 0.13 as a difference.** Ratios between rows measured close together are sounder than absolutes, since the arms share machine conditions.
- **A ratio only travels when both of its arms are bounded by the same resource.** Computation against computation transfers between machines; buffered logging against an unbuffered file write does not, and section 11b is what that looks like when measured on two operating systems.
- Where two snippets are claimed equivalent, the harness asserts matching output counts and prints the result.
- Harnesses: `suite.dme` and `suite_del.dme`. **Every figure on this page regenerates from them**, with one stated exception: section 12 needs a remote server and a second machine driving real clients, so no automated run here can produce it, and it says so at its head. Everything else that could not be reproduced was withdrawn on 2026-08-03 rather than carried behind a banner, including section 11 entire, whose heading is kept so the removal is visible.
- **What the suite does not cover is stated too**, in "What this does not measure" near the end. Silence there is not evidence that a thing is cheap.

**Regenerated 2026-08-03, and the figures moved.** Sections 1 through 11b now
come from the measuring machine rather than the desktop, and every measured row
outside the scheduler moved from `world.timeofday` to `world.tick_usage` the day
before. Absolute times therefore differ from any earlier copy of this page,
mostly downward, since the two machines are not equally fast at everything.
Ratios moved less: the typed view loop reads 7.8x where it read 9.5x, `loc`
against `Move()` is unchanged at about 8x, and the associative lookup at 5,000
entries is 50x where it read 81x. Where a multiple genuinely depends on which
machine measured it, both are now printed, and sections 2, 7 and 11b are where
that happens.

**Repeatability and precision, and the error bar is per machine.** Every
baseline is three runs merged, median and spread per row. On the measuring
machine the median row disagrees with itself by about **1%** between runs, two
rows in 118 exceed 25%, and rows over 10 µs sit near 2%. On the desktop the same
suite gives about 10%, with 20 rows over 25% and its long rows the widest band
rather than the tightest, at 16%. Those are the 516.1666 triples; the 516.1685
pair is tighter on both machines, at 0 and 4 rows over 25%, which is the
sitting rather than the build. **Neither figure is an accuracy
claim**: it is how well a machine repeats itself, which is the most a
repeatability measurement can tell you, and small rows remain limited by
baseline subtraction and by two-decimal output whatever the machine does.

**Spread figures are not comparable across conditions**, and there are now
three of those: process priority, sitting, and clock. The last one was learned
the hard way. A 0.1s wall clock cannot express a disagreement smaller than its
own quantum, so before the conversion to `world.tick_usage` some rows printed a
tight spread that meant only "three runs landed in the same quantum". On the
desktop that made the same suite look four times tighter than it is; on the
measuring machine it produced long rows reading exactly 0%. A spread column is
only evidence down to the resolution of what produced it.

**Section 2 carries its own history**: three of its seven assertions once
flipped at random across four runs, because each figure was a difference
between two `world.timeofday` blocks one to four clock quanta wide. It was
re-derived with `world.tick_usage` and median-of-three, and two of its rows are
withheld today because that same subtraction guard now judges them too noisy on
a machine fast enough to shrink the difference it was measuring.

**Controls.** Where this page claims a mechanism rather than a cost, an assertion tests it in the suite and is named in place: that a typed view loop never builds the discarded entries, that occlusion actually occludes, that `istype` does not scale with tree depth while `typesof` does, that `Move()` fires four callbacks where `loc` fires none, that write cost is per call rather than per byte. The `del()` figures were re-derived in an isolated harness after the main run proved to contaminate itself; see §2.

Reference: at `tick_lag 0.5` a tick is 50,000 µs.

---

## 1. view()

Test set: 41 mobs and 400 objs inside `view(7)`. 667 atoms total.

### Same output, three ways

```dm
var/list/V = view(7, c)                                    // 215 µs   667 atoms
var/list/V = view(7, c); for(var/mob/M in V) ...           // 248 µs    41 mobs
for(var/mob/M in view(7, c)) ...                           //  27 µs    41 mobs
for(var/atom/A in view(7, c)) ...                          // 352 µs   667 atoms
```

Middle two verified identical at 41 mobs, in all three runs. Ratio **7.8x**.

A typed `for(... in view(...))` passes the filter to the engine and skips building the list. Building the list accounts for the cost. The DM-side filter loop adds only about 33 µs on top of the 215 µs build.

The 7.8x figure is specific to 667 atoms in view. Tested against rising clutter with the mob count held at 41:

| Atoms in view | `var/list/V = view(7,c)` | `for(var/mob/M in view(7,c))` | advantage |
|---|---|---|---|
| 667 | 214 µs | 27.2 µs | 7.9x |
| 967 | 433 µs | 30.1 µs | 14.2x |
| 1,867 | 1,560 µs | 41.8 µs | 36.1x |
| 2,667 | 3,217 µs | 54.5 µs | 62x |

516.1685 tracks it within a few percent at every level. `view.clutter_advantage_rises` asserts that the advantage widens at every step, which two points could never have shown: two points establish that a gap exists, four establish that it grows with clutter, and growing with clutter is the actual claim.

Materialising the list is superlinear: 4x the atoms costs 15x the time, while the typed loop grows 2x, which confirms it never builds the discarded entries. `view.typed_loop_skips_build` asserts that pair of multiples, so the mechanism is checked rather than inferred from the timings.

An earlier printing of this table gave "1.7x empty, 10x typical, 77x crowded" from a harness that is not in this repository, and it was cut to two points during an audit. The sweep was rebuilt on 2026-08-03 and reaches 62x at 2,667 atoms on the measuring machine and 77.8x on the desktop, so the withdrawn figure was sound; what it lacked was somewhere to come from.

An earlier version of this table ran five clutter levels to 2,647 atoms and reported the advantage as "1.7x empty, 10x typical, 77x crowded". That harness is not in this repository and the finer sweep is not reproducible here, so the table now shows only the two points this suite measures. The shape is unchanged; the endpoints are gone rather than repeated on trust.

### Two passes over one view

```dm
var/list/V = view(7, c)
for(var/mob/M in V) ...
for(var/obj/O in V) ...                                    // 372 µs

for(var/mob/M in view(7, c)) ...
for(var/obj/O in view(7, c)) ...                           // 228 µs
```

Verified identical output, 441 atoms against 441, in all three runs.
**Caching a view for reuse is slower than running the query twice, on every
build, on both machines, and in every run measured.** Medians per build:

| build | cached | re-queried | ratio |
|---|---|---|---|
| 516.1666 | 371.6 µs | 228.2 µs | 1.63x |
| 516.1685 | 368.7 µs | 220.9 µs | 1.67x |

**A build-dependence claim here was withdrawn rather than restated.** An early
sitting reported 2.05x against 1.84x with six of six samples separated, and
this page once stated the ratio per build on that basis. Later triples
overlapped, and on the current machine the two builds sit within 0.04 of each
other, which is well inside the run-to-run noise of either. There is no
measured build difference here. What is established, now across two machines,
two builds and many samples, is the design rule: **re-querying beats caching
every time, and by at least 1.6x everywhere it has been measured.**

### Family

```dm
for(var/mob/M in view(7, c)) ...                           // 27.4 µs
for(var/mob/M in oview(7, c)) ...                          // 27.1 µs
for(var/mob/M in viewers(7, c)) ...                        // 23.6 µs
for(var/mob/M in range(7, c)) ...                          // 14.7 µs
```

This suite times the `view()` row three times in three places, and
`view.same_operation_rows_agree` asserts the three agree: they land at 27.37,
27.40 and 27.35 µs, a ratio of 1.00x. That assertion exists because a divisor
defect once put those same three rows 1.83x apart.

### Keeping your own list instead of asking the engine

Rebuilt 2026-08-03, having been withdrawn in an earlier audit. Both arms
iterate the identical set, which `view.maintained_equivalence` confirms at 41
mobs against 41 before either timing is allowed to mean anything.

```dm
for(var/mob/M in view(7, c)) ...        // 27.2 µs   the query
for(var/mob/M in my_list) ...           //  5.8 µs   your own list
my_list -= M; my_list += M              //  0.25 µs  recording one move
```

**Reading your own list is about 4.7x cheaper than querying.** That is the
number usually quoted, and on its own it is misleading, because a maintained
list is not free: something has to keep it correct.

**The break-even is about 85 moves per read.** An atom may move roughly 85
times between two reads before querying becomes the cheaper option. Most
designs read far more often than that, which is why the advice holds, but it
holds for a reason with a number behind it rather than because lists are
"faster than view".

This is the same discipline §2 needed: publishing the read without the update
would be quoting a numerator with no denominator.

`view()` computes line of sight and `range()` does not, which costs **1.9x**
here on both builds. **This is one of the few ratios that does not travel
cleanly between machines**: the Windows desktop reads 2.6x for the same pair,
because `range()` is measurably cheaper there while `view()` is not. Both
machines agree on the direction and on the advice; treat the multiple as "in
the 2x region" rather than as a constant.

The line-of-sight cost is unconditional rather than proportional to how many
opaque atoms exist:

| Opaque atoms in range | `view(7)` | mobs seen |
|---|---|---|
| 0 | 27 µs | 41 |
| 200 | 16 µs | 6 |

Adding 200 opaque atoms does not raise the cost; it lowers the count seen, so
occlusion works (41 mobs down to 6). Both figures come from
`view.los_cost_is_unconditional` and `view.occlusion_works`, which assert the
cost does not rise and that occlusion has an effect.

An earlier version of this table carried a `range()` column alongside, showing
that a call which computes no line of sight is unaffected by opaque atoms in
either direction. It was withdrawn in an earlier audit because its harness is
not in this repository, and it has not been rebuilt.

### Radius

```dm
view(1)     1.7 µs
view(3)     7.4 µs
view(5)     18.3 µs
view(7)     27.3 µs
view(10)    39.4 µs
```

`view.radius_sweep_monotonic` asserts this ordering, which is why the row that
once published view(7) above view(10) cannot recur silently.

---

## 2. del()

> **Every figure in this section regenerates from `suite_del.dme`** as of
> 2026-08-01: three runs merged per build, `world.tick_usage` with
> median-of-three inside each run, and the population sweep now reaches
> 300,000. Earlier versions of this section imported tables from harnesses
> that were not in the tree; those harnesses are no longer cited, and where
> the inherited figures could be checked they fell inside the re-measured
> ranges.
>
> **The shape of this section travels between machines. The coefficients do
> not, and the gap is larger here than anywhere else on the page.** The del()
> scan is a memory walk, so its slope is a property of a machine's memory
> subsystem rather than of the engine. Every figure below is from the
> measuring machine; where the second machine changes a multiple rather than
> just a magnitude, it is stated.

### Cost by reference count

Clean world, 400 turfs, live object count held at zero in both arms. Median of
three runs per build.

| Heap refs on victim | 516.1666 | 516.1685 |
|---|---|---|
| 0 | withheld, below the resolution floor | withheld |
| 1 | 3.68 (3.68 to 3.70) µs | 4.00 (3.94 to 4.01) µs |
| 256 | 5.71 (5.40 to 5.75) µs | 5.91 (5.90 to 5.92) µs |

One heap reference costs about 3.7 µs here and 256 of them about 5.8, so
**a 256x change in reference count costs about 1.5x, not 256x.** Reference
count is not what drives `del()`; live population is, as the next table shows.
The desktop agrees on the direction and reads 1.2x on 516.1666 and 1.4x on
516.1685, at spreads of 55 and 26 percent against 6 and 0 percent here, which
is why the figures above come from the measuring machine.

**An earlier printing withheld the 256-reference row as `SUBTRACTION_NOISE`
and rested the claim on the desktop instead.** That was true of the merge it
was written from and is not true of the baselines in `results/` today, where
the row clears its guard on both builds. It is restored rather than left
withheld, on the standing rule that a withheld row measures nothing.

The zero-reference case is not measurable by either machine; its signal is a
few percent of a tick against a 20 percent floor, so it is flagged
`LOW_RESOLUTION` and withheld.

### The scan runs only for references del cannot see

`del(H[1])`, where the indexed list slot is the victim's only heap reference,
costs 0.27 µs (0.25 to 0.38), the same as the zero-reference case, while
`del(e)` through a local with the same single reference held elsewhere costs
the full 3.7 µs. The expensive part of del() is the hunt for references it cannot
account for from the deletion site. Asserted as
`del.accounted_ref_is_free`, passing on both builds, so an engine that
changes this behaviour flips a cell in the matrix.

### Cost by live object count

Clean world, population grown monotonically. Victim holds one heap reference.
Median of three runs, with the observed range.

| Live objs | 516.1666 | 516.1685 |
|---|---|---|
| 0 | 3.71 (3.71 to 3.74) µs | 4.02 (3.94 to 4.03) µs |
| 50,000 | 87.1 (86.2 to 87.1) µs | 89.4 (89.2 to 90.0) µs |
| 100,000 | 190 (171 to 198) µs | 178 (173 to 189) µs |
| 200,000 | 610 (600 to 620) µs | 670 (667 to 671) µs |
| 300,000 | 1,104 (1,102 to 1,161) µs | 1,154 (1,151 to 1,158) µs |

Growth is superlinear above 50,000 on both builds and on both machines, and
`del.population_sweep_monotonic` asserts that ordering rather than leaving it
to a reader comparing five rows.

**How superlinear is a property of the machine and the moment, not of the
engine, and this is the sharpest example on the page.** Going from 50,000 to
300,000 live objects, a 6x increase in population, costs **12.7x** the time
here and **53x** on the Windows desktop, whose absolute figure at 300,000 is
3,856 µs against this machine's 1,104.

**That desktop coefficient is not stable across sittings, and there are now
three of them on record.** The same measurement on the same machine, same
build, same clock, has given 27x, 40x and 53x on three different evenings.
Nothing changed but the hour. The scan is a memory walk, so its slope belongs
to the cache hierarchy, the memory bandwidth and whatever else that machine was
doing. **Carry the shape, which is that deletion cost climbs faster than
population. Do not carry any coefficient on this page onto your own hardware,
including the one measured here.**

At 300,000 live objs and `tick_lag 0.5`, roughly 45 deletions consume the tick
here and roughly 13 on the desktop. Both numbers say the same thing about
design.

### Turfs are not counted

Map resized with no objects present, one heap ref on the victim:

| Turfs | 516.1666 | 516.1685 |
|---|---|---|
| 10,000 | 3.68 µs | 4.00 µs |
| 48,400 | 3.72 µs | 4.02 µs |

Flat, and at 1 to 2% spread this is now a tight result rather than a plausible
one. Turfs do not feed the scan.

### Cumulative allocation does not matter

500,000 objects allocated and immediately freed between two measurements,
live count held at zero:

| | 516.1666 | 516.1685 |
|---|---|---|
| before the churn | 3.75 µs | 4.04 µs |
| after 500k allocated and freed | 3.69 µs | 3.99 µs |

Flat. How many objects a server has created over its lifetime is irrelevant;
only concurrent population counts.

### Peak concurrent population leaves a permanent residual

| State | 516.1666 | 516.1685 |
|---|---|---|
| cold start, 0 live | 3.71 µs | 4.02 µs |
| grown to 300,000 | 1,104 µs | 1,154 µs |
| all 300,000 freed | **200.7 (200.3 to 200.9) µs** | **198.7 µs** |

Freeing the population does not restore the cold cost. Whatever structure the
scan walks grows with peak concurrent live count and never shrinks. **A
one-off population spike raises `del()` cost about 54x here for the remaining
life of the process, and about 24x on the desktop.** The two machines differ on
the multiple for the same reason they differ on everything else in this
section: their cold costs are 3.7 µs and 9.6 µs, so the same residual structure
prices differently against each. Note that the residual itself is the one row
in this section that barely moves between machines, 201 µs here against 231 on
the desktop, while the scan that produces it is 3.5x apart.

### Alternative

```dm
del(thing)          // ~1,104 µs at 300k live objs here, ~3,856 on the desktop
thing = null        // no scan, no population sensitivity
```

**The denominator exists as of 2026-08-03.** Every del figure on this page is a
difference between two timed loops, one calling `del()` and one dropping the
reference, and the second was being measured all along without ever being
printed. It is now published as `del.drop_control_1ref`:

| | 516.1666 | 516.1685 |
|---|---|---|
| allocate, build 1 heap ref, drop both, **no** `del()` | 1.04 µs | 1.04 µs |
| the same with `del()`, net of that control | 3.68 µs | 4.00 µs |

Note what the control includes, because the name matters: allocation is
unavoidable, since there is nothing to drop without first making it. So this is
not the cost of `thing = null` in isolation, it is the cost of the whole
control arm, and quoting it as anything else would repeat the mistake being
corrected.

With both halves measured, the comparison can finally be stated honestly.
Against that 1.04 µs control, `del()` costs about **3.5x** at zero population
and, at 300,000 live objects where it reads 1,104 µs, about **1,060x**. Earlier
versions of this page said "up to 3,300x" and then "about 3,000x" against a
denominator that had never been measured here at all.

What is measured is the numerator: **deletion at 300,000 live objects costs
about 1,100 µs on the measuring machine and about 3,900 on the desktop, and
dropping the last reference does not scale with population at all**, holding at
1.04 µs in both builds. The design advice is unchanged and now rests only on
figures this repository can reproduce.

### Not a defect: confirmed across the GC fixes

516.1676, 1678 and 1679 fixed garbage collection bugs that 516.1676 describes as
longstanding, which placed them inside 516.1666 and put every figure in this
section in doubt. Tested directly, three runs on each build:

| id | 516.1666 | 516.1685 |
|---|---|---|
| `del.live_0` | 3.71 (3.71 to 3.74) | 4.02 (3.94 to 4.03) |
| `del.live_200000` | 610 (600 to 620) | 670 (667 to 671) |
| `del.live_300000` | 1,104 (1,102 to 1,161) | 1,154 (1,151 to 1,158) |
| `del.residual_after_peak` | 200.7 | 198.7 |

The two builds separate by 4 to 10% on three of these four rows, with 1685 the
dearer. **It is recorded as an observation and not promoted to a claim**, for
four reasons now: it is one machine, the same rows overlapped completely on the
desktop, this project's own rule is that a cross-build comparison must
interleave its runs within one sitting and the run order behind these triples
does not record it, and **the 300,000 ranges do overlap** (1,102 to 1,161
against 1,151 to 1,158), so only the two smaller rows separate cleanly at all.
An earlier printing of this table said the ranges did not overlap; that was
true of the merge it was written from and is not true of the baselines in
`results/` today. A separation this size is exactly what non-interleaved
sittings have faked here before. The residual row, which does not separate and
in fact runs marginally cheaper on 1685, is the useful control sitting right
next to it. The superlinear growth and the
permanent residual are engine characteristics, not defects. Earlier printings
of this table gave three raw values per cell from a 2026-07-30 pair of
triples; medians with ranges say the same thing and are comparable with the
rest of the page.

**Two caveats that must travel with this result.**

516.1676's pathology requires `del()` *and* a large number of sleeping or spawned
procs in the scheduler simultaneously. This suite is deliberately isolated and
carries no scheduler load, so the comparison never exercised the fixed path. What
is shown is that the isolated case is unaffected.

That comparison was made when the sweep stopped at 200,000. The sweep has
since been extended to 300,000 (2026-08-01) and the 300k figures above come
from this tree on both builds, so the headline ratio no longer rests on an
absent harness. The values the older harness published fell inside the
re-measured ranges.

### Measurement note

An earlier version of this page reported a 155 to 200 µs floor at zero live objects. That was an artifact of harness ordering: the section ran a 300,000-object test before the sweep, which set the residual described above. The clean baseline is 10 µs. Isolate `del()` measurements in a fresh process.

---

## 3. List lookup

Worst case for `in`: needle is the last element. Baseline removed.

| Entries | `needle in L` | `A[needle]` |
|---|---|---|
| 10 | 0.12 µs | 0.15 µs |
| 100 | 0.33 µs | 0.18 µs |
| 1,000 | 2.38 µs | 0.20 µs |
| 5,000 | 11.5 µs | 0.23 µs |

The 50-entry and 500-entry rows in earlier printings came from a harness not
in this tree and have been dropped rather than carried forward. Both columns
are asserted: `lists.in_scales_with_size` requires the left column to rise at
every step, `lists.assoc_stays_flat` requires the right to stay within 3x of
its smallest value across a 500x change in list size.

Associative lookup is flat. The right-hand column moves 0.15 to 0.23 across a
500x change in list size, a factor of 1.5 where the left column moves 96x.
**Read the right column as one value, not as a slow climb**, and note that the
assertion behind it allows 3x precisely so that a genuine O(n) regression would
break it while this drift does not.

Crossover is around 10 entries: at 10 the linear search is already the cheaper
of the two here, and by 100 it has lost. Below the crossover the two are
equivalent in any way that matters.

### `L.Find()` got about 4x slower between 516.1666 and 516.1685

The one place on this page where the two builds genuinely differ, and the
reason this suite exists.

| n | `Find()` on 1666 | `Find()` on 1685 |
|---|---|---|
| 10 | 0.17 µs | 0.26 µs |
| 100 | 0.46 µs | 1.48 µs |
| 1,000 | 3.33 µs | 13.4 µs |
| 5,000 | 16.1 µs | 66.5 µs |

**Per element the scan goes from 3.19 ns to 13.27 ns.** It is not call
overhead: at n=10 the gap is 0.09 µs and at n=5,000 it is 50 µs, which is a
slope change rather than a constant. Measured on two machines and two operating
systems, three runs per build, at 0 to 1% spread.

**Every control is flat across the same two builds, in the same runs**: `in`
with the needle in the last slot, `in` with the needle absent, associative
lookup, list building with `+=`, and `L.Copy()`. That last one is the important
one, because it is also a list method call, so this is not a change in how
methods dispatch. Whatever moved is inside the scan.

**It was introduced in 516.1674.** Bisected across six builds, with the
boundary pair repeated three times each and no overlap between them:

| build | `Find()` cost, percent of a tick, 1,000-element list |
|---|---|
| 516.1666 | 1,410 |
| 516.1672 | 1,422 |
| **516.1673** | **1,383, 1,412, 1,435** |
| **516.1674** | **6,252, 6,264, 6,306** |
| 516.1676 | 6,286 |
| 516.1679 | 6,410 |
| 516.1685 | 6,312 |

A 4.5x step between two consecutive builds, holding for the eleven that follow,
while `in` over the same list stays flat throughout as the control.

**No mechanism is offered.** This repository does not hold BYOND's release
notes, so what changed in that build is outside what it can answer. What it can
say is where: clean at 516.1673, regressed at 516.1674, still regressed at
516.1685.

**Practical consequence, on 516.1685:** `Find()` costs about 5.8x what `in`
costs for the same scan, against 1.4x on 516.1666. If you want a position, it
is still the only way to get one; if you want a yes or no, `in` is now
dramatically cheaper, and an associative list is cheaper than either.

`in` with the needle absent costs the same as `in` with the needle in the last
slot on both builds, which is expected: both walk the entire list.

---

## 4. List building

100 elements per iteration.

```dm
L = list(); L += j                                         // 13.0 µs
L = new(100); L[j] = j                                     // 17.3 µs
L = list(); L.Add(j)                                       // 19.5 µs
L.Copy()                                                   // 3.20 µs
```

Preallocation is slower than `+=`. List growth is already amortised. `.Add()`
costs 50% more than `+=` here, and 48% on 516.1685.

---

## 5. Type tests

Baseline removed.

```dm
istype(O, /obj/thing)                                      // 0.12 µs
O.type == /obj/thing                                       // 0.12 µs
O.flags & FLAG_A                                           // 0.11 µs
O.categories["weapon"]                                     // 0.17 µs
locate(/obj/thing) in O          // 1 item in contents     // 0.18 µs
```

istype is also flat across tree depth and relatedness, which is the claim
`dispatch.istype_flat` tests: 0.124 µs at depth 1, 0.124 at depth 8, 0.136 at
depth 8 against a depth-1 ancestor and 0.126 for an unrelated-branch miss. Its
control, `typesof()` on mob types, does not stay flat (0.464 against 0.267 µs),
so the harness is not simply reporting everything as flat.

Spread is 0.07 µs across all five. **Treat the first three as one value**, and
note that the two lookup forms at the bottom sit slightly above them here on
both builds and on the second machine, which is a consistent direction rather
than noise, but amounts to about 60 nanoseconds. No design decision should turn
on that. Dispatch strategy is a design decision, not a performance one.

---

## 6. Calls and variable access

Call rows use the discarded-unroll instrument; three High-priority runs
merged, 2026-07-31. The vars rows keep an accumulator, because a discarded
pure read is eliminated by the compiler, and they sit at the instrument's
floor: one significant figure at best.

```dm
GlobalProc()                     // empty proc             // 0.18 µs
D.Method()                       // empty datum method     // 0.22 µs
D.Method()                       // sets . = 1             // 0.27 µs
UserProc(a)                      // 1 arg                  // 0.21 µs
UserProc(a, ..., h)              // 8 args                 // 0.39 µs
abs(x)                           // hard builtin           // 0.03 µs
max(a, b)                        // hard builtin           // 0.09 µs
V.Dot(W)                         // soft-called builtin    // 0.12 µs
acc += local_var                 // BASELINE_HEAVY         // 0.02 µs
acc += global_var                // BASELINE_HEAVY         // 0.02 µs
acc += world.time                // BASELINE_HEAVY         // 0.07 µs
acc += D.x                       // BASELINE_HEAVY         // 0.13 µs
```

**The four variable-read rows are at the instrument's floor and are flagged
for it.** They keep an accumulator, because the compiler eliminates a
discarded pure read outright, so what is subtracted from them is a large share
of what they measure. Read them as "too small for this instrument to separate,
and under 0.15 µs", not as four distinct values. On the second machine two of
them fall to or below the empty-loop cost and are withheld entirely.

A proc call is **0.18 to 0.27 µs**, and each argument adds about 0.026. **A
hard-called builtin is nearly free**: `abs()` at 0.026 µs is about an eighth
of a one-argument user proc, a measured ratio of 8.0x, with a soft-called
builtin between them at 0.12. An earlier figure near 0.1 µs for `abs` was
mostly harness, the accumulator and its branch; the discarded-unroll
conversion removed both.

The four plain call rows at 0.18 to 0.27 are close enough to treat as one
value; the 8-argument row at 0.39 and the two hard builtins are genuinely
apart from it. Datum variable access is above a local, 0.13 against 0.02, but
both are inside the flagged band described above, so treat that as a direction
rather than as a measured multiple.

At `tick_lag 0.5` this allows roughly 250,000 proc calls per tick.

---

## 7. Strings

Baseline removed.

```dm
s = "[a][b]"                     // embed                  // 0.31 µs
s = a + b                        // concat                 // 0.28 µs
findtext(hay, "lazy")            // 43-char haystack       // 0.38 µs
num2text(i)                                                // 0.59 µs
```

Embed, concat and `findtext` are one value at this scale; `num2text` is
roughly twice any of them.

**`findtext` is where the two machines disagree most outside the io layer, and
the ordering flips.** It costs 1.76 µs on the Windows desktop, where it is the
most expensive routine string operation by a wide margin and dearer than
`num2text`, against 0.38 µs here, where it is the cheapest of the four. A
4.6x gap on a row that is pure computation, reproduced on a third environment,
points at the platform's string search rather than at either machine. If your
code leans on `findtext` in a hot path, measure it on the operating system you
deploy on; this is not a figure to carry across.

---

## 8. Allocation

Discarded-unroll instrument, three High-priority runs merged, 2026-07-31.

```dm
new /datum                                                 // 0.25 µs
new /datum/holder                // 1 var, 2 procs         // 0.26 µs
new /obj                                                   // 0.46 µs
new /mob                                                   // 0.48 µs
```

**A blank `/mob` and a blank `/obj` are indistinguishable**: 0.46 and 0.48 µs,
and 0.46 and 0.47 on 516.1685. This conclusion moved twice in one day and the
history matters. The original equivalence claim was withdrawn once because the
accumulator-form instrument read the mob 10 to 22% above the obj, in the same
direction in every run. The discarded-unroll conversion removed the
accumulator and the difference went with it: it belonged to the harness, not
to the type. Two machines and two builds now agree.

The step that is real is datum to obj, 0.25 to 0.46, a type distinction with
no vars added. That gap is 1.8x and survives on both machines. One var on a
datum adds nothing measurable, 0.25 against 0.26.

### Declaring vars is free. Initialising them is not

A figure for "a mob with 30 vars and 3 lists" was published here for months
from a harness that is not in this repository. It could never have settled the
question it was quoted for, because carrying both at once cannot separate
declaring a var from running an initialiser. Split on 2026-08-03:

```dm
new /datum                                                 // 0.25 µs
new /datum   + 30 declared vars, none initialised          // 0.25 µs
new /datum   + 3 vars initialised to list()                // 1.14 µs
```

**Thirty bare vars cost nothing measurable.** Three list initialisers cost
**4.6x a plain datum**, and that cost is paid per instance, forever.
`alloc.initialisers_cost_more_than_bare_vars` asserts the ordering so it cannot
quietly reverse.

The practical form: a type carrying many declared vars is cheap to instantiate,
and one carrying a handful of `= list()` initialisers is not. If instances are
created in bulk, initialise lazily rather than in the declaration.

---

## 9. Movement

Baseline removed. Three High-priority runs merged, 2026-07-31.

```dm
M.loc = T                        // direct                 // 0.28 µs
M.Move(T)                        // Enter/Exit chain       // 2.17 µs
M.Move(T)                        // all 4 callbacks overridden // 3.42 µs
```

`loc` assignment is about **8x** cheaper than `Move()`: 7.7x on 516.1666 and
8.6x on 516.1685 here, 9.6x and 8.2x on the second machine. Overriding the
callbacks, which is what real codebases do, costs a further 58% over the plain
path.

Callback counts verified by overriding all four on a turf type:

| 1,000 iterations | Enter | Exit | Entered | Exited |
|---|---|---|---|---|
| `M.Move(T)` | 1000 | 1000 | 1000 | 1000 |
| `M.loc = T` | 0 | 0 | 0 | 0 |

An earlier version of this table read 999 with a rationale about the first
move targeting the occupied turf; the recorded count is 1000 in every run and
the rationale did not survive checking. Assigning `loc` fires nothing.

---

## 10. Object lifetime

| Behaviour | Result |
|---|---|
| `loc` and `contents` reference cycle | Never collected. 2,000 objects created, 0 freed. |
| Same, `contents` cleared first | 2,000 created, 1,998 freed. The 2 are test locals. |
| `del(src)` | Fires immediately and aborts the proc. Code after it does not run. |
| Pending `spawn()` | Holds its object alive until it resolves. |
| `if(!src)` | Creates no reference. `src` is never null inside a live proc. |

A mob sent to nullspace with anything in `contents` leaks permanently, along with its contents. Inventory counts.

Leak detection:

```dm
#ifdef LEAKCHECK
#define CENSUS_IN   census["[type]"] = (census["[type]"] || 0) + 1
#define CENSUS_OUT  census["[type]"] = (census["[type]"] || 0) - 1
#endif
```

Increment in `New()`, decrement in `Del()`, dump per-type counts from an admin verb. A counter that only climbs is a leak.

---

## 11. Tick budget, 200 players. Withdrawn

This section published a 200-player perception-load simulation: polling
`view(7)` from every player against pushing events outward, with the polling
cost given as 9.2 to 9.6x the event-driven form and peaking near half a tick
when players clustered.

**It has been removed rather than restated.** Its harness is not in this
repository, so nothing here could reproduce it, and it was two runs with no
spread published and no resolution guard applied, which is below the standard
every other section is now held to. The design advice it carried, that pushing
from an event beats polling from every observer, may well be right, and §1
independently establishes that `view()` is expensive enough for the shape to be
plausible. Neither of those is a measurement.

Rebuilding it is a real piece of work rather than a port: it needs a load
harness with 200 mobs and its own manifest. `extras/load.dme` is an earlier,
unported harness of the same shape and is the obvious starting point.

---

## 11b. Logging and file I/O

**This section regenerates from `suite.dme` as of 2026-08-01.** Earlier
printings (313, 351, 330 and 5.9 µs) came from a harness not in this tree.

```dm
file << "short line"            // 8.5 us    median of 3 passes
file << "1000-char line"        // 10.0 us   median of 3 passes
file << "line with [value]"     // 9.3 us    includes string building
world.log << "short line"       // 1.9 us
```

**This is the one section where the platform decides the design advice, not
just the number.** A direct file write costs about **8.5 us on Linux and 190
us on Windows**, and the two lead to different conclusions from the same
engine. At `tick_lag 0.5`, roughly 5,900 short file writes fill a tick on
Linux against about 260 on Windows. Logging every game event to a file is
merely expensive on one platform and completely unaffordable on the other.

**`world.log` is cheaper than a direct write everywhere**, because it goes to
buffered stdout rather than an unbuffered flush: 1.9 us here, 4.2 us on
Windows. But the advantage it buys is **4.4x on Linux and 45.9x on Windows**,
because the arm it is being compared against is what moves.

Measured on both machines, same suite, same clock, three runs each:

| | linux | windows |
|---|---|---|
| `file << "short line"` | 8.51 µs | 190.5 µs |
| `world.log << "short line"` | 1.92 µs | 4.15 µs |
| advantage of `world.log` | **4.4x** | **45.9x** |

The direction survives on both, which is what the advice rests on. The
magnitude does not travel, and neither would any ratio whose two arms are
bounded by different resources: buffered stdout against an unbuffered syscall
is exactly such a pair. Everything else on this page is computation against
computation, which is why this is the only section carrying a platform column.

**The binding matters as much as the platform.** `world.log` goes to stdout,
so what stdout *is* decides its cost. Bound to a file handle rather than
inherited from a console or pipe, `world.log` measured 85 µs on Windows, a
fifth of a direct file write instead of a fortieth. Anyone running
DreamDaemon under `> server.log` loses most of the benefit. That figure is one
run each way against eight of the inherited case, so treat the 20x as the
shape rather than the coefficient. The Linux figures above were taken with
stdout bound to a file, which is recorded in that baseline rather than
assumed.

**Cost is per call, not per byte.** 1000 characters costs 17% more than 10,
despite 100x the data, and the same holds on the second machine. Batching many lines into a single write is therefore
nearly free per additional line, and is the correct fix if you need volume.
Two assertions hold this down: `io.write_cost_is_per_call_not_per_byte`
requires the long write to stay under 2x the short one, and
`io.long_write_not_cheaper_than_short` requires it not to come out cheaper,
which single-shot noise produced twice before the arms were medianed.

Neither form yields to the scheduler. `world.time` was unchanged across 20,000
writes of each kind, so logging does not break a no-sleep guarantee. It just costs.

---

## 12. Network cost with real clients

> **This section does not regenerate from this repository either.** It needs a
> remote server and a second machine driving real clients, which no automated
> run here can assemble, and it predates the current framework: single runs, no
> spread, no resolution guards. `net/probe.dme` is the world it was measured
> against and is in the tree; the driver and the byte-counter sampling were not
> part of a suite. The transferable quantity is the per-moved-atom byte figure
> and the linearity in client count, not the absolute KB/s of this scene.

Measured with the server on a remote Linux box (Vultr, 1 vCPU, Ubuntu 24.04) and clients on a separate Windows machine over the public internet, so client rendering cannot contend with server CPU. Server-side instruments: `world.cpu` and NIC byte counters from `/proc/net/dev`.

`world.map_cpu` does not exist in 516. `world.tick_usage` sampled at the top of a tick stays at 0 regardless of client load, so it does not capture map send cost. `world.cpu` does.

Scene: 120x120 map, 1500 objs and 300 NPCs inside a 21x21 zone. In `moving` modes every NPC takes a `step()` each tick at `tick_lag 0.5`.

### The cost is change, not content

Three clients, two keyed accounts and one guest:

| Mode | Clients see | CPU | tx total | tx per client |
|---|---|---|---|---|
| `empty_moving` | bare turf, NPCs moving elsewhere | 5.60% | 0.2 KB/s | 0.1 KB/s |
| `dense_static` | 1800 atoms, nothing moving | 1.93% | 0.2 KB/s | 0.1 KB/s |
| `dense_moving` | 1800 atoms, ~300 moving | 10.2 to 11.5% | 222 to 226 KB/s | 74 to 75 KB/s |

A connected client seeing nothing costs 0.1 KB/s, so per-connection overhead is negligible. A client staring at 1800 static atoms costs 0.2 KB/s, so **scene density is free to maintain**. Only movement costs anything.

BYOND sends deltas. Bandwidth is driven by atoms that changed in view per tick, not by atoms in view.

### Per-client bandwidth is linear

All repeats, `dense_moving`:

| Clients | tx total | tx per client |
|---|---|---|
| 1 | 71.9, 74.5 KB/s | 71.9, 74.5 |
| 2 | 137.4, 150.2, 150.8, 151.7 KB/s | 68.7, 75.1, 75.4, 75.8 |
| 3 | 221.8, 225.9 KB/s | 73.9, 75.3 |

Per-client is flat at about 74 KB/s regardless of client count. Totals track `74 * N` almost exactly: predicted 74 / 148 / 222 against measured 72-75 / 137-152 / 222-226.

**No cross-client deduplication.** Clients watching the identical scene each receive their own full stream. Extrapolation is straightforward and unkind.

The controls hold at N=3 too: per-connection overhead stays at 0.1 KB/s per client rather than growing, so the linear term is entirely map content.

### Derived rate

At 20 ticks/sec, 74 KB/s is about 3.7 KB per tick per client. With roughly 150 of the 300 NPCs inside a client's view at any moment, that works out to **about 25 bytes per moved atom per tick per observing client**.

Which makes the crowd case quadratic. For N players in one room all moving, each seeing the other N:

```
bytes/sec ~= N clients * N moving * 25 bytes * 20 ticks = 500 * N^2
```

| Players in one room | Sustained upload |
|---|---|
| 50 | 1.25 MB/s (10 Mbps) |
| 100 | 5 MB/s (40 Mbps) |
| 200 | 20 MB/s (160 Mbps) |

Halving the tick rate halves all of it, since deltas are sent per tick. So `tick_lag 1` costs half the bandwidth of `tick_lag 0.5`.

### Server CPU per client

About 2 to 2.7% per client on a 1 vCPU instance in the dense moving scene, against a 5.6% baseline for the NPC movement itself. That figure is specific to this hardware and does not transfer. The bandwidth figures do.

### Caveat

The scene is deliberately pathological: 300 NPCs moving every single tick. Treat 74 KB/s as an upper bound for a very busy room, not a typical one. The 25 bytes per moved atom per tick figure is the transferable number.

### Client count limit

One machine can host **one real key plus one guest, two clients maximum**. BYOND identifies clients by ckey, and a second connection presenting an existing key evicts the first. Additional clients require additional BYOND accounts or additional machines. This is the one test category that cannot be run single-machine.

---

## 13. Scheduler and tick order

### Order within a tick

`world/Tick()` is a real engine hook and fires once per tick. Waking procs run before it, first-in-first-out by spawn order:

```
world.Tick()   time=6     seq=1
waker1 wakes   time=6.5   seq=2
waker2 wakes   time=6.5   seq=3
world.Tick()   time=6.5   seq=4
waker1 wakes   time=7     seq=5
waker2 wakes   time=7     seq=6
world.Tick()   time=7     seq=7
```

Full order per the engine model: waking procs, then `world.Tick()`, then incoming verbs, then maptick (the phase that sends each client its viewport). The verb and maptick positions were not verified here, since both need a connected client.

Consequence for command-queue designs: a queue drained from a slept proc or from `world.Tick()` runs *before* verbs arrive, so input from tick N is processed in tick N+1. That is one tick of structural latency, 50 ms at `tick_lag 0.5`.

### A spawned context is a copy

```dm
var/t = -1
spawn(0)
    t = world.time     // writes to a COPY
sleep(world.tick_lag)
// t is still -1
```

`spawn` copies the caller's local execution context into the scheduler. The spawned block cannot write back to the caller's locals. Use a global or a datum field to get a value out.

`spawn(0)` runs in the same tick, verified with a global.

### Pending sleeps are free

100 ticks measured after the scheduler settles, ideal 50 ds:

| Parked procs (never wake) | 100 ticks |
|---|---|
| 0 | 50 ds |
| 10,000 | 50 ds |
| 50,000 | 50 ds |
| 100,000 | 50 ds |
| 200,000 | 50 ds |

| Procs waking every tick | 100 ticks | total wakes |
|---|---|---|
| 0 | 50 ds | 0 |
| 500 | 50 ds | 50,000 |
| 1,000 | 50 ds | 100,000 |
| 2,500 | 50 ds | 250,000 |
| 5,000 | 50 ds | 500,000 |

Zero measurable overhead in both cases. 5,000 procs waking every tick, half a million wakes over the run, costs nothing detectable. One loop doing the same work inline also measures zero.

**The scheduler is not a bottleneck at any realistic scale.** Arguments against `spawn()` have to rest on correctness (reentrancy, object pinning, context copying), not throughput.

Note: measuring this before the spawns finish starting shows large fake overhead. 200,000 parked procs appeared to cost 114 ds until a settle period was added, after which the cost is zero. That was the backlog of spawns still reaching their first `sleep()`.

---

## 14. Numeric limits

DM numbers are 32-bit floats. Integers are exact to 2^24 = 16,777,216.

**Most of this section regenerates from `suite/src/assert_numeric.dm`**, as
assertions rather than figures, so a build that widens the numeric type flips
them to FAIL: `numeric.eq_at_2p24`, `numeric.increment_stalls`,
`numeric.loop_nonterminating` with its below-the-bound control,
`numeric.accumulator_saturates`, the `numeric.shift_*` family and
`numeric.bitfield_23_survives` against `numeric.bitfield_24_lost`. All pass on
516.1666 and 516.1685.

**Two observations were withdrawn from this section on 2026-08-03**: the
`num2text` switch to scientific notation above the bound, and the fact that
`as` cannot be used as a variable name. Both came from a harness that is not
in this repository, so neither could be reproduced here, and this page does not
carry figures nobody can check. The first is a runtime behaviour and is a
straightforward assertion for whoever adds it. The second is compile-time and
this suite has no way to assert on it at runtime at all.

The bit round-trip table below lists bits the suite does not individually
assert; 23 and 24 are the boundary and are the two that are tested.

### Integers stop advancing at exactly 2^24

```dm
16777216 == 16777217            // TRUE
```

`n + 1 == n` first holds at n = 16,777,216. 16,777,217 is not representable and rounds down.

Above the bound, string interpolation switches to scientific notation:

```dm
"[16777216]"                    // "16777216"
"[16777218]"                    // "1.67772e+07"
```

Asserted since 2026-08-03 as `numeric.num2text_scientific_above_bound`, with
`numeric.num2text_plain_at_bound` as its control, because a build that changed
number formatting wholesale would otherwise pass both. The consequence is not
arithmetic, it is text: a value that is still exactly representable stops
rendering as digits, so anything writing an id, a savefile key or a log line
through interpolation changes format partway up the range.

### Loops past the bound do not terminate

```dm
for(var/i = 16777210 to 16777230)   // never exits, i sticks at 16777216
for(var/i = 16777100 to 16777120)   // control: exits after 21 iterations
```

Verified with an escape counter. The first loop ran 51 guard iterations with `i` frozen at 16,777,216. The control loop below the bound completed normally.

### Accumulators saturate silently

```dm
var/acc = 16000000
for(var/i = 1 to 2000000)
    acc += 1
// expected 18000000, actual 16777216, lost 1222784
```

No error, no warning. The counter simply stops counting.

### Bitfields: bits 0 to 23 only

```dm
1 << 22    // 4194304
1 << 23    // 8388608     highest usable
1 << 24    // 0
1 << 25    // 0
1 << 30    // 0
1 << 32    // 1           shift count wraps
```

Shifting past bit 23 produces a mask of **zero**, not a large number. A flag defined as `1 << 24` has a zero mask, so setting it stores nothing and every test of it reads false. The failure is silent in both directions.

| Bit | Mask | Round-trip |
|---|---|---|
| 0 | 1 | OK |
| 15 | 32768 | OK |
| 22 | 4194304 | OK |
| 23 | 8388608 | OK |
| 24 | 0 | LOST |
| 25 | 0 | LOST |
| 30 | 0 | LOST |

24 flags per field maximum, indices 0 through 23. Use a second var beyond that.

### Reserved words

`as` cannot be used as a variable name. `var/list/as = list()` fails to compile
with "missing left-hand argument to =".

This is compile-time behaviour, so no runtime assertion in this suite can reach
it. It is backed instead by `extras/compile-probes/reserved-as.dme`, a file
that **must fail to compile**, carrying an ordinary variable name beside the
reserved one as its control so that a failure proves something about `as`
rather than about the probe. Verified on 516.1666 and 516.1685. A build on
which that file compiles cleanly has un-reserved the word, and success there is
the finding.

---

## What this does not measure

Stated so it is a declared scope rather than something a reader discovers by
looking for a number that is not here. The suite covers eleven families well.
It is silent on a great deal, and silence here is not evidence that a thing is
cheap.

**Not covered at all.** `animate()` and the appearance system, icons and icon
generation, maptext, matrices, sound, savefiles, regular expressions and the
rest of string manipulation beyond the four operations in §7, `..()` parent
calls, `pick()`, `Cut()` against reassignment, and luminosity.

**Covered in one direction only.** §2 measures `del()` in isolation, and
deliberately: it is the only way to keep the population residual from
corrupting everything else in the process. The case that matters most in
practice, deletion while a large number of procs sleep in the scheduler, needs
a third manifest and has never been measured here. That gap has been open since
2026-07-30 and it is the one this project most wants closed.

**Cannot be measured here at all.** Anything needing a connected client:
maptext round-trips, `GetMapIcons` scaling, icon frame count against client
load, client-side dir changes. One machine hosts one real key plus one guest,
because BYOND identifies clients by ckey and a second connection presenting an
existing key evicts the first. §12 is what a two-machine measurement looks
like, and why it does not regenerate from this repository.

**Memory is not measured.** Nothing in DM exposes allocation size, so claims
about storage layout, turf memory or the first-var hashtable cannot be tested
by any timing harness. Answering them needs an external sampler reading the
process's private bytes, written once per operating system, and that does not
exist here.

Two builds are covered, 516.1666 and 516.1685. A claim that something changed
in a particular build needs the builds either side of it, which is a matter of
fetching them rather than of writing tests.

---

## Summary

Every ratio here is computed from the merged baselines in `results/`, on both
builds, and each names the section it comes from.

| Rule | Ratio | From |
|---|---|---|
| `for(var/mob/M in view())` instead of assigning `view()` to a var | 7.8x at 667 atoms, 38x at 1,867 | §1 |
| Re-query `view()` instead of caching for two passes | 1.6x on 1666, 1.7x on 1685, and every sample on both machines favours re-querying | §1 |
| `range()` instead of `view()` when line of sight is not needed | 1.9x here, 2.6x on the desktop | §1 |
| `loc =` instead of `Move()` when callbacks are not needed | about 8x, 7.7 to 9.6x across two builds and two machines | §9 |
| Associative list instead of `in` at 5,000 entries | 50x here, 74x on the desktop | §3 |
| `+=` instead of `.Add()` for list building | 1.5x | §4 |
| `world.log` instead of a direct file write | 4.4x here, 45.9x on Windows; platform-conditional, and only when stdout is not a file | §11b |
| Dropping the last reference instead of `del()` at 300k live objects | `del()` alone costs 1,104 µs here and 3,856 on the desktop, against a 1.04 µs control that does not scale with population | §2 |

Two rules were dropped from this table on 2026-08-01 rather than restated:
"push from the event instead of polling", whose 9.2 to 9.6x comes from the
absent section 11 harness, and the "up to 3,300x" del multiple, whose
denominator was never measured here. Both claims may well be right; neither is
reproducible from this repository, which is the standard this page now holds
itself to.

Type test strategy has no measurable performance impact, and istype is flat
across tree depth and relatedness.

Clear `contents` before nullspacing, or the object leaks permanently.
