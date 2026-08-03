# BYOND 516 Performance Spec Sheet

Measured cost of common BYOND operations.

## Test conditions

- DreamDaemon 516.1666, Windows 11. Single machine, machine drift possible. Ratios hold.
- Baselines dated 2026-07-31 or later run DreamDaemon at High process priority; earlier figures were normal priority.
- Sections 1 to 11 and 13 to 14: single machine, no clients connected.
- Section 12: server on a remote Linux box, clients on a separate machine over the public internet.
- Sections other than 2 ran at least 1.5s against `world.timeofday` (0.1s resolution). Quantization error under 7% **for a single timed block**. That guard does not cover a difference between two blocks, which is what section 2 is made of; see the note there.
- Section 2 uses `world.tick_usage`, calibrated per run at 500 to 507 µs per percent of a tick, with median-of-three.
- Empty loop baseline: 0.07 to 0.08 µs with an accumulator, 0.03 without. The first is removed from accumulator-form rows, the second from the unrolled discarded-result rows.
- **Every figure on this page was regenerated on 2026-08-01** from three interleaved runs per build of each suite: 52 assertions and 92 measurements for `suite.dme`, 10 and 16 for `suite_del.dme`, 0 failed and 0 unstable everywhere, and every assertion verdict identical across the two builds.
- **Figures are printed at the precision the harness emits, which is finer than the measurement supports. Read every absolute figure as plus or minus 15% at least.** Two figures whose intervals overlap are one figure: 0.09 and 0.11 do not differ, and a table that lists them in ascending order is not showing a trend. Sections 3 and 5 through 8 carry a reminder in place, because their values are small enough that the printed decimals are the whole of the apparent difference. Ratios between rows measured close together are sounder, since the arms share machine conditions.
- Where two snippets are claimed equivalent, the harness asserts matching output counts and prints the result.
- Harnesses: `suite.dme` and `suite_del.dme`. Sections 1 through 10, 11b, 13 and 14 regenerate from them. Figures imported from harnesses absent from this tree are flagged in place and are now confined to: the `extras/respawn.dme` line in section 8, two side observations in section 14, and sections 11 and 12 entire, whose harnesses (`spec_sheet.dme`, `hypotheses.dme`) predate this suite. Several tables lost rows on 2026-08-01 because those rows came from absent harnesses and could not be reproduced; each loss is noted where it happened rather than quietly carried.

**Regenerated 2026-08-03, and two things changed that a reader should know
before comparing this page to an older copy.** The Windows baselines were
retaken as three runs per build after every measured row outside the scheduler
moved from `world.timeofday` to `world.tick_usage`. First, the ratios in the
summary table at the bottom are recomputed from those runs, and four moved
inside the error bar this page already declares: the typed view loop 9.5x to
8.5x, `range()` against `view()` 2.3x to 2.6x, `loc` against `Move()` 8x to
about 9x, and the associative lookup at 5,000 entries 81x to 74x. The
section-by-section tables below still quote the 2026-08-01 figures except in
§11b, and re-deriving them is outstanding work.

Second, **the spread column roughly doubled, from a median of 9% to 18%, and
that is mostly the instrument getting more honest rather than the engine or
the suite getting worse.** A 0.1s wall clock cannot express a disagreement
smaller than its own quantum, so run-to-run variation below that was invisible
and printed as a tight spread; `world.tick_usage` resolves it. The same effect
was measured in the other direction on the Linux machine, whose long rows read
exactly 0% spread until the same conversion. Part of the increase is also that
the Windows machine is in daily use and cannot be quiesced. Which is why
**precision figures now come from a dedicated Linux machine**, whose merged
baselines carry one wide row in 92 against this machine's 22.

**Repeatability and precision.** Every baseline is three runs merged, median
and spread per row. **Absolute figures carry an error bar of at least 15%,
measured rather than estimated**: rows over 10 µs, where quantization is
negligible and no baseline is subtracted, still scatter about 15% between
runs, and the number of rows varying over 25% tracked ambient machine load
from 11 to 30 of 86 across triples taken the same day. A sub-microsecond
figure printed to two decimals is formatting, not precision; 0.09 and 0.11 do
not differ at this scale. Ratios between rows measured close together are
sounder than absolutes, because the arms share machine conditions. Since
2026-07-31 baselines run DreamDaemon at High process priority, which halves
the between-run spread of long rows (18.3% to 9.9% median); spread figures
are not comparable across priorities. **Section 2 carries its own history**:
three of its seven assertions once flipped at random across four runs,
because each figure was a difference between two `world.timeofday` blocks
one to four clock quanta wide. It was re-derived with `world.tick_usage` and
median-of-three.

**Controls.** Mechanism claims on this page are tested rather than asserted, in `hypotheses.dme`, **which is not in the tree**. The `del()` figures were re-derived in isolated harnesses after the main run proved to contaminate itself; see §2.

Reference: at `tick_lag 0.5` a tick is 50,000 µs.

---

## 1. view()

Test set: 41 mobs and 400 objs inside `view(7)`. 667 atoms total.

### Same output, three ways

```dm
var/list/V = view(7, c)                                    // 238 µs   667 atoms
var/list/V = view(7, c); for(var/mob/M in V) ...           // 275 µs    41 mobs
for(var/mob/M in view(7, c)) ...                           //  29 µs    41 mobs
for(var/atom/A in view(7, c)) ...                          // 417 µs   667 atoms
```

Middle two verified identical at 41 mobs, in all three runs. Ratio **9.5x**.

A typed `for(... in view(...))` passes the filter to the engine and skips building the list. Building the list accounts for the cost. The DM-side filter loop adds only about 37 µs on top of the 238 µs build.

The 9.5x figure is specific to 667 atoms in view. Tested against rising clutter with the mob count held at 41:

| Atoms in view | `var/list/V = view(7,c)` | `for(var/mob/M in view(7,c))` | advantage |
|---|---|---|---|
| 667 | 250 µs | 26.4 µs | 9.5x |
| 1,867 | 1,740 µs | 40 µs | 43.5x |

516.1685 gives 8.8x and 40.4x on the same two points. Materialising the list is superlinear: 2.8x the atoms costs 7.0x the time, while the typed loop grows 1.5x, which confirms it never builds the discarded entries.

An earlier version of this table ran five clutter levels to 2,647 atoms and reported the advantage as "1.7x empty, 10x typical, 77x crowded". That harness is not in this repository and the finer sweep is not reproducible here, so the table now shows only the two points this suite measures. The shape is unchanged; the endpoints are gone rather than repeated on trust.

### Two passes over one view

```dm
var/list/V = view(7, c)
for(var/mob/M in V) ...
for(var/obj/O in V) ...                                    // 383 µs

for(var/mob/M in view(7, c)) ...
for(var/obj/O in view(7, c)) ...                           // 207 µs
```

Verified identical output in all three runs. **Caching a view for reuse is
slower than running the query twice, on every build and in every run
measured.** Within-run ratios, three runs per build, both arms timed under
identical conditions:

| build | per-run ratios | median |
|---|---|---|
| 516.1666 | 1.99, 1.85, 1.81 | 1.85x |
| 516.1685 | 1.84, 1.64, 1.61 | 1.64x |

**A build-dependence claim here has been weakened by better data.** An earlier
sitting reported 2.05x against 1.84x with six of six samples separated, and
this page stated the ratio per build on that basis. In the current triples the
distributions overlap: 1666's slowest sample reads 1.81 and 1685's fastest
reads 1.84. The direction of the medians is the same, so the difference may
well be real, but it is no longer separated and this page no longer claims it
as established. What is established, on twelve samples across two sittings, is
the design rule: re-querying beats caching every time, by 1.6x at worst.

### Family

```dm
for(var/mob/M in view(7, c)) ...                           // 26 to 29 µs
for(var/mob/M in oview(7, c)) ...                          // 27 µs
for(var/mob/M in viewers(7, c)) ...                        // 22 µs
for(var/mob/M in range(7, c)) ...                          // 12 µs
```

`view()` is given as a range because this suite times it three times in three
places, and `view.same_operation_rows_agree` asserts the three agree; they
land at 26.4, 27.3 and 29.1 µs. The maintained-list comparison that used to
close this block came from a harness not in this tree and has been withdrawn
rather than repeated.

`view()` computes line of sight, `range()` does not, and it costs **2.3x** more
on 516.1666 (26.4 against 11.5 µs) and 2.6x on 516.1685. The line-of-sight cost is unconditional
rather than proportional to how many opaque atoms exist:

| Opaque atoms in range | `view(7)` | mobs seen |
|---|---|---|
| 0 | 30 µs | 41 |
| 200 | 22 µs | 9 |

Adding 200 opaque atoms does not raise the cost; it lowers the count seen, so
occlusion works (41 mobs down to 9). Both figures come from
`view.los_cost_is_unconditional` and `view.occlusion_works`, which assert the
cost does not rise and that occlusion has an effect. The `range()` half of the
old version of this table used a harness not in this tree and has been
withdrawn.

### Radius

```dm
view(1)     1.8 µs
view(3)     7.1 µs
view(5)      19 µs
view(7)      30 µs
view(10)     47 µs
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
> **The population rows are ambient-sensitive and are published as median
> plus range.** The del() scan is memory-bound, so its per-object cost moves
> with cache and memory conditions: across three same-morning triples the
> population rows spread 30 to 65%, with both builds moving together. The
> shape (superlinear growth, flat null, permanent residual) is stable; the
> coefficients belong partly to the machine and the moment.

### Cost by reference count

Clean world, 400 turfs, live object count held at zero in both arms. Median of
three, three runs per build, 2026-08-01.

| Heap refs on victim | 516.1666 | 516.1685 |
|---|---|---|
| 0 | not resolvable | not resolvable |
| 1 | 10.9 (10.7 to 11.2) µs | 10.4 (10.1 to 10.6) µs |
| 256 | 13.4 (10.8 to 17.7) µs | 12.3 (10.5 to 16.7) µs |

One heap reference costs about 10 µs. 256 references cost somewhere between
the same and 1.5x, with the 256-ref arm being the highest-variance quantity
in this suite. Nearly flat against a 256x change in reference count either
way; the design guidance is unchanged.

The zero-reference case is **not measurable by this harness**. Its signal is 3
to 8 percent of a tick against a 20 percent floor, so it is flagged
`LOW_RESOLUTION` and withheld.

### The scan runs only for references del cannot see

`del(H[1])`, where the indexed list slot is the victim's only heap reference,
costs 0.22 to 0.23 µs, the same as the zero-reference case, while `del(e)`
through a local with the same single reference held elsewhere costs the full
10 µs. The expensive part of del() is the hunt for references it cannot
account for from the deletion site. Asserted as
`del.accounted_ref_is_free`, passing on both builds, so an engine that
changes this behaviour flips a cell in the matrix.

### Cost by live object count

Clean world, population grown monotonically. Victim holds one heap reference.
Median of three runs, with the observed range, 2026-08-01.

| Live objs | 516.1666 | 516.1685 |
|---|---|---|
| 0 | 10.9 (10.1 to 11.2) µs | 11.0 (9.8 to 11.9) µs |
| 50,000 | 94.8 (90 to 107) µs | 115 (112 to 121) µs |
| 100,000 | 244 (186 to 286) µs | 237 (208 to 291) µs |
| 200,000 | 1,992 (1,957 to 2,281) µs | 2,162 (2,142 to 2,474) µs |
| 300,000 | 3,830 (3,628 to 3,887) µs | 3,763 (3,492 to 3,914) µs |

Growth is superlinear above 50,000 on both builds: 6x the population from 50k
to 300k costs about 40x the time. The ranges are wide because the scan is
memory-bound and tracks ambient machine conditions; the shape held in every
run, and `del.population_sweep_monotonic` now asserts that ordering rather
than leaving it to a reader comparing five rows.

At 300,000 live objs and `tick_lag 0.5`, roughly 13 deletions consume the
tick.

### Turfs are not counted

Map resized with no objects present, one heap ref on the victim:

| Turfs | 516.1666 | 516.1685 |
|---|---|---|
| 10,000 | 11.0 µs | 11.7 µs |
| 48,400 | 10.7 µs | 10.3 µs |

Flat within the ranges above. Turfs do not feed the scan.

### Cumulative allocation does not matter

500,000 objects allocated and immediately freed between two measurements,
live count held at zero:

| | 516.1666 | 516.1685 |
|---|---|---|
| before the churn | 10.7 µs | 10.5 µs |
| after 500k allocated and freed | 11.0 µs | 11.3 µs |

Flat. How many objects a server has created over its lifetime is irrelevant;
only concurrent population counts.

### Peak concurrent population leaves a permanent residual

| State | 516.1666 | 516.1685 |
|---|---|---|
| cold start, 0 live | 10.9 µs | 11.0 µs |
| grown to 300,000 | 3,830 µs | 3,763 µs |
| all 300,000 freed | **203 (191 to 232) µs** | **229 (206 to 230) µs** |

Freeing the population does not restore the cold cost. Whatever structure the
scan walks grows with peak concurrent live count and never shrinks. A one-off
population spike raises `del()` cost roughly 19 to 21x for the remaining life
of the process.

### Alternative

```dm
del(thing)          // ~3,800 µs at 300k live objs (3,500 to 3,900 observed)
thing = null        // no scan, no population sensitivity
```

**The multiple is not quoted, and that is deliberate.** Earlier versions of
this page put the ratio at "up to 3,300x" and then "about 3,000x", against a
`thing = null` arm of "about 1 µs" that came from a harness not in this tree.
This suite measures the `del()` side, at any population, and uses dropping the
reference as the control arm inside each measurement, but it publishes no
standalone row for the control, so the denominator of that ratio has never
been measured here. What is measured is the numerator: **deletion at 300,000
live objects costs about 3,800 µs and dropping the last reference does not
scale with population at all.** The design advice is unchanged and now rests
only on figures this repository can reproduce.

### Not a defect: confirmed across the GC fixes

516.1676, 1678 and 1679 fixed garbage collection bugs that 516.1676 describes as
longstanding, which placed them inside 516.1666 and put every figure in this
section in doubt. Tested directly, three runs on each build:

| id | 516.1666 | 516.1685 |
|---|---|---|
| `del.live_0` | 10.9 (10.1 to 11.2) | 11.0 (9.8 to 11.9) |
| `del.live_200000` | 1,992 (1,957 to 2,281) | 2,162 (2,142 to 2,474) |
| `del.live_300000` | 3,830 (3,628 to 3,887) | 3,763 (3,492 to 3,914) |
| `del.residual_after_peak` | 203 (191 to 232) | 229 (206 to 230) |

Unchanged: every row overlaps between builds. The superlinear growth and the
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
| 10 | 0.11 µs | 0.11 µs |
| 100 | 0.34 µs | 0.13 µs |
| 1,000 | 2.60 µs | 0.15 µs |
| 5,000 | 13.7 µs | 0.17 µs |

The 50-entry and 500-entry rows in earlier printings came from a harness not
in this tree and have been dropped rather than carried forward. Both columns
are asserted: `lists.in_scales_with_size` requires the left column to rise at
every step, `lists.assoc_stays_flat` requires the right to stay within 3x of
its smallest value across a 500x change in list size.

Associative lookup is flat. The right-hand column moves 0.09 to 0.14 across a
500x change in list size, which is inside the plus or minus 15% error bar on
figures this small: **read that column as one value, not as a slow climb.**
`in` is linear at roughly 2 ns per element, and its column spans 100x, far
outside any error bar.

Crossover is 10 to 20 entries. Below that the two are equivalent.

`L.Find()` and the miss case were measured by a harness that is not in this
tree, so the figures once printed here (0.37 and 0.24 µs at n=100) have been
withdrawn. This suite times the worst case for `in`, which is the needle in
the last slot.

---

## 4. List building

100 elements per iteration.

```dm
L = list(); L += j                                         // 12.7 µs
L = new(100); L[j] = j                                     // 16.0 µs
L = list(); L.Add(j)                                       // 17.3 µs
L.Copy()                                                   // 1.80 µs
```

Preallocation is slower than `+=`. List growth is already amortised. `.Add()`
costs 36% more than `+=` here, and 39% on 516.1685.

---

## 5. Type tests

Baseline removed.

```dm
istype(O, /obj/thing)                                      // 0.10 µs
O.type == /obj/thing                                       // 0.10 µs
O.flags & FLAG_A                                           // 0.08 µs
O.categories["weapon"]                                     // 0.12 µs
locate(/obj/thing) in O          // 1 item in contents     // 0.16 µs
```

istype is also flat across tree depth and relatedness, which is the claim
`dispatch.istype_flat` tests: 0.11 µs at depth 1, depth 8, depth 8 against a
depth-1 ancestor, and an unrelated-branch miss, all four identical. Its
control, `typesof()` on mob types, does still scale (0.41 against 0.29 µs),
so the harness is not simply reporting everything as flat.

Spread is 0.05 µs across all five, against a per-figure error of at least 15%,
which at this scale is roughly 0.02 µs. **The five are one value.** The order
they are printed in is not a ranking, and no reading of this table supports
preferring one form over another. Dispatch strategy is a design decision, not a
performance one.

---

## 6. Calls and variable access

Call rows use the discarded-unroll instrument; three High-priority runs
merged, 2026-07-31. The vars rows keep an accumulator, because a discarded
pure read is eliminated by the compiler, and they sit at the instrument's
floor: one significant figure at best.

```dm
GlobalProc()                     // empty proc             // 0.18 µs
D.Method()                       // empty datum method     // 0.20 µs
D.Method()                       // sets . = 1             // 0.24 µs
UserProc(a)                      // 1 arg                  // 0.19 µs
UserProc(a, ..., h)              // 8 args                 // 0.32 µs
abs(x)                           // hard builtin           // 0.02 µs
max(a, b)                        // hard builtin           // 0.06 µs
V.Dot(W)                         // soft-called builtin    // 0.10 µs
acc += local_var                 // BASELINE_HEAVY         // 0.02 µs
acc += global_var                // BASELINE_HEAVY         // 0.04 µs
acc += world.time                // BASELINE_HEAVY         // 0.05 µs
acc += D.x                       // BASELINE_HEAVY         // 0.11 µs
```

**The four variable-read rows are at the instrument's floor and are flagged
for it.** They keep an accumulator, because the compiler eliminates a
discarded pure read outright, so what is subtracted from them is a large share
of what they measure. On 516.1685 `vars.local` and `vars.global` came out at
or below the empty-loop cost entirely and are withheld there rather than
printed as a number. Read them as "too small for this instrument to separate,
and under 0.1 µs", not as four distinct values.

**Read this block at plus or minus 15%**, which is 0.03 µs on most of these
rows. The four call rows at 0.18 to 0.24 are one value; the 8-argument row at
0.32 and the builtins at 0.02 and 0.06 are genuinely apart from it.

A proc call is 0.18 to 0.24 µs, and each argument adds about 0.019. **A
hard-called builtin is nearly free**: `abs()` at 0.02 µs is about a tenth of
a user proc (measured ratio 9.5x), with a soft-called builtin between them
at 0.10. An earlier figure near 0.1 µs for `abs` was mostly harness, the
accumulator and its branch; the discarded-unroll conversion removed both and
the figure moved on 2026-07-31.

Datum variable access is above a local, 0.11 against 0.02, but both are inside
the flagged band described above, so treat that as a direction rather than a
measured multiple.

At `tick_lag 0.5` this allows roughly 250,000 proc calls per tick.

---

## 7. Strings

Baseline removed.

```dm
s = "[a][b]"                     // embed                  // 0.35 µs
s = a + b                        // concat                 // 0.35 µs
num2text(i)                                                // 1.05 µs
findtext(hay, "lazy")            // 43-char haystack       // 2.35 µs
```

`findtext` is the most expensive routine operation listed here. At plus or
minus 15%, embed and concat are one value; `num2text` and `findtext` are
separated from them by more than the error bar and from each other.

---

## 8. Allocation

Discarded-unroll instrument, three High-priority runs merged, 2026-07-31.

```dm
new /datum                                                 // 0.21 µs
new /datum/holder                // 1 var, 2 procs         // 0.25 µs
new /obj                                                   // 0.57 µs
new /mob                                                   // 0.57 µs
```

**A blank `/mob` and a blank `/obj` are indistinguishable**: 0.57 µs each,
spreads 5 and 9%. This conclusion moved twice in one day and the history
matters. The original equivalence claim was withdrawn in the morning because
the accumulator-form instrument read the mob 10 to 22% above the obj, same
direction in every run. The discarded-unroll conversion then removed the
accumulator, and the difference went with it: it belonged to the harness,
not the type. 516.1685 gives the same verdict, 0.49 and 0.55 with
overlapping ranges.

The step that is real is datum to obj, 0.21 to 0.57, a type distinction with
no vars added. That gap is 2.7x and survives the error bar comfortably. One
var on a datum adds nothing meaningful, 0.21 against 0.25, and at plus or
minus 15% nothing under about 0.04 µs here could be called a difference.

A mob with 30 vars and 3 lists measured 2.6 µs by the unported respawn
harness; indicative only, per the harness note at the top of this page.

---

## 9. Movement

Baseline removed. Three High-priority runs merged, 2026-07-31.

```dm
M.loc = T                        // direct                 // 0.33 µs
M.Move(T)                        // Enter/Exit chain       // 2.70 µs
M.Move(T)                        // all 4 callbacks overridden // 3.98 µs
```

`loc` assignment is about **8x** cheaper than `Move()`, identical on both
builds. Overriding the callbacks, which is what real codebases do, costs 47%
over the plain path.

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

## 11. Tick budget, 200 players

> **This section does not regenerate from this repository.** It was measured by
> a 200-player simulation harness that is not in the tree, in two runs rather
> than the three this project now requires, with no spread published per row
> and no resolution guard applied. `extras/load.dme` here is an earlier, unported
> harness of the same shape. Treat the figures as indicative, and the 9.2 to
> 9.6x polling ratio as the one quantity worth carrying, since a ratio between
> two arms of one run survives conditions that its absolute percentages do
> not. Nothing else on this page depends on it.

200 mobs, 100 ticks, `tick_lag 0.5`, sampling `world.tick_usage`. Perception work only.

Two runs.

| Workload | Spread over 200x200 | All 200 in an 11x11 |
|---|---|---|
| idle | 0% | 0% |
| every player polls `view(7)` | 7.4 to 8.2% | 32.5 to 37.6%, peak 43 to 51% |
| 20 movers query | 0.9 to 1.0% | 3.5 to 4.1% |
| 20 events push outward | 0.8 to 0.9% | 3.4 to 4.1% |

Polling costs 9.2 to 9.6x event-driven notification and peaks near half the tick when players cluster.

---

## 11b. Logging and file I/O

**This section regenerates from `suite.dme` as of 2026-08-01.** Earlier
printings (313, 351, 330 and 5.9 µs) came from a harness not in this tree.

```dm
file << "short line"            // 190 us   median of 3 passes
file << "1000-char line"        // 210 us   median of 3 passes
file << "line with [value]"     // 207 us   includes string building
world.log << "short line"       // 4.5 us
```

**A direct file write costs about 190 us on Windows.** That is roughly 1,000
proc calls, and at `tick_lag 0.5` about 260 of them consume the entire tick.
Writing to a file per game event is not viable there.

**`world.log` is ~46x cheaper on Windows** at 4.2 us, because it goes to
buffered stdout rather than an unbuffered flush.

**That multiple is not a property of the engine, and this is the one place on
this page where the operating system changes the advice.** Measured on both
machines, same suite, same clock, three runs each:

| | windows | linux |
|---|---|---|
| `file << "short line"` | 190.5 µs | 8.51 µs |
| `world.log << "short line"` | 4.15 µs | 1.92 µs |
| advantage of `world.log` | **45.9x** | **4.4x** |

A direct file write is about 22x cheaper on Linux, so the gap it opens over
`world.log` mostly closes. The direction survives on both, which is what the
advice rests on; the magnitude does not travel, and neither would any ratio
whose two arms are bounded by different resources. Buffered stdout against an
unbuffered syscall is exactly such a pair.

**The binding matters as much as the platform.** `world.log` goes to stdout,
so what stdout *is* decides its cost. Bound to a file handle rather than
inherited from a console or pipe, `world.log` measured 85 µs on Windows, a
fifth of a direct file write instead of a fortieth. Anyone running
DreamDaemon under `> server.log` loses most of the benefit. That figure is one
run each way against eight of the inherited case, so treat the 20x as the
shape rather than the coefficient. The Linux figures above were taken with
stdout bound to a file, which is recorded in that baseline rather than
assumed.

**Cost is per call, not per byte.** 1000 characters costs 11% more than 10,
despite 100x the data. Batching many lines into a single write is therefore
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

Two observations below are **not** covered by any assertion here and come from
`numlimits.dme`, which is not in the tree: the `num2text` switch to scientific
notation, and the `as` reserved word, which is a compile-time behaviour this
suite has no way to assert on at runtime. The bit round-trip table lists bits
the suite does not individually assert; 23 and 24 are the boundary and are the
two that are tested.

### Integers stop advancing at exactly 2^24

```dm
16777216 == 16777217            // TRUE
```

`n + 1 == n` first holds at n = 16,777,216. 16,777,217 is not representable and rounds down.

Above the bound, `num2text` switches to scientific notation:

```dm
"[16777216]"                    // "16777216"
"[16777218]"                    // "1.67772e+07"
```

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

`as` cannot be used as a variable name. `var/list/as = list()` fails to compile with "missing left-hand argument to =".

---

## Summary

Every ratio here is computed from the merged baselines in `results/`, on both
builds, and each names the section it comes from.

| Rule | Ratio | From |
|---|---|---|
| `for(var/mob/M in view())` instead of assigning `view()` to a var | 8.5x at 667 atoms, 41.3x at 1,867 | §1 |
| Re-query `view()` instead of caching for two passes | 1.85x on 1666, 1.70x on 1685, and every sample so far favours re-querying | §1 |
| `range()` instead of `view()` when line of sight is not needed | 2.6x | §1 |
| `loc =` instead of `Move()` when callbacks are not needed | about 9x, 8.2 to 9.6x across the two builds | §9 |
| Associative list instead of `in` at 5,000 entries | 74x | §3 |
| `+=` instead of `.Add()` for list building | 1.4x | §4 |
| `world.log` instead of a direct file write | 45.9x on Windows, 4.4x on Linux; platform-conditional, and only when stdout is not a file | §11b |
| Dropping the last reference instead of `del()` at 300k live objects | `del()` alone costs 3,800 µs; the ratio is not quoted, see §2 | §2 |

Two rules were dropped from this table on 2026-08-01 rather than restated:
"push from the event instead of polling", whose 9.2 to 9.6x comes from the
absent section 11 harness, and the "up to 3,300x" del multiple, whose
denominator was never measured here. Both claims may well be right; neither is
reproducible from this repository, which is the standard this page now holds
itself to.

Type test strategy has no measurable performance impact, and istype is flat
across tree depth and relatedness.

Clear `contents` before nullspacing, or the object leaks permanently.
