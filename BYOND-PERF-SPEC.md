# BYOND 516 Performance Spec Sheet

Measured cost of common BYOND operations.

## Test conditions

- DreamDaemon 516.1666, Windows 11. Single machine, machine drift possible. Ratios hold.
- Baselines dated 2026-07-31 or later run DreamDaemon at High process priority; earlier figures were normal priority.
- Sections 1 to 11 and 13 to 14: single machine, no clients connected.
- Section 12: server on a remote Linux box, clients on a separate machine over the public internet.
- Sections other than 2 ran at least 1.5s against `world.timeofday` (0.1s resolution). Quantization error under 7% **for a single timed block**. That guard does not cover a difference between two blocks, which is what section 2 is made of; see the note there.
- Section 2 uses `world.tick_usage`, calibrated per run at 500 to 507 µs per percent of a tick, with median-of-three.
- Empty loop baseline: 0.05 to 0.06 µs. Removed from all figures below 1 µs.
- Where two snippets are claimed equivalent, the harness asserts matching output counts and prints the result.
- Harnesses: `suite.dme` and `suite_del.dme`. **Not every figure on this page regenerates from them.** Five harnesses are cited across the page and none is in the tree: `spec_sheet.dme`, `hypotheses.dme`, `delscale2.dme`, `delcause.dme`, `respawn.dme`. Sections carrying imported figures are flagged in place.

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
var/list/V = view(7, c)                                    // 210 µs   667 atoms
var/list/V = view(7, c); for(var/mob/M in V) ...           // 240 µs    41 mobs
for(var/mob/M in view(7, c)) ...                           //  23 µs    41 mobs
for(var/atom/A in view(7, c)) ...                          // 333 µs   667 atoms
```

Middle two verified identical at 41 mobs, in all three runs. Ratio 10.0 to 11.9x.

A typed `for(... in view(...))` passes the filter to the engine and skips building the list. Building the list accounts for the cost. The DM-side filter loop adds only 30 µs on top of the 210 µs build.

The 10x figure is specific to 667 atoms in view. Tested against rising clutter with the mob count held at 21:

| Atoms in view | `var/list/V = view(7,c)` | `for(var/mob/M in view(7,c))` |
|---|---|---|
| 247 | 25 µs | 15 µs |
| 547 | 175 µs | 20 µs |
| 847 | 350 µs | 25 µs |
| 1,447 | 975 µs | 25 µs |
| 2,647 | 3,075 µs | 40 µs |

Materialising the list is superlinear: 10.7x the atoms costs 123x the time. The typed loop grows 2.7x over the same range, which confirms it never builds the discarded entries. The advantage is 1.7x on a bare turf and 77x in a crowded room.

### Two passes over one view

```dm
var/list/V = view(7, c)
for(var/mob/M in V) ...
for(var/obj/O in V) ...                                    // 317 µs

for(var/mob/M in view(7, c)) ...
for(var/obj/O in view(7, c)) ...                           // 150 µs
```

Verified identical output in all three runs. Ratio 2.0 to 2.1x. Caching a view for reuse is slower than running the query twice.

### Family

```dm
for(var/mob/M in view(7, c)) ...                           // 23 µs
for(var/mob/M in oview(7, c)) ...                          // 23 µs
for(var/mob/M in viewers(7, c)) ...                        // 18 µs
for(var/mob/M in range(7, c)) ...                          // 8.5 µs
for(var/mob/M in maintained_list) ...   // 40 entries      // 3.75 µs
```

`view()` computes line of sight, `range()` does not. The cost is unconditional, not proportional to how many opaque atoms exist:

| Opaque atoms in range | `view(7)` | mobs seen | `range(7)` | mobs seen |
|---|---|---|---|---|
| 0 | 15 µs | 21 | 5 µs | 21 |
| 200 | 15 µs | 6 | 10 µs | 21 |

`view()` costs 3x `range()` with zero opaque atoms present, and adding 200 of them does not change its cost. Occlusion works (21 mobs drop to 6). `range()` gets slower only because 200 more atoms exist to walk.

A maintained list is not a drop-in substitute. It returns all entries regardless of distance, so it only replaces a spatial query if the list is scoped per area.

### Radius

```dm
view(1)    1.5 µs
view(3)    5.5 µs
view(5)     14 µs
view(7)     21 µs
view(10)    36 µs
```

---

## 2. del()

> **Re-measured 2026-07-30 on 516.1666 and 516.1685**, using `world.tick_usage`
> with median-of-three. The old figures were differences between two
> `world.timeofday` blocks, only one to four clock quanta wide, so a result could
> only land on a multiple of 100000/reps.
>
> **Only the reference-count table below was re-measured.** Everything after it
> comes from `delscale2.dme`, `delcause.dme` and `hypotheses.dme`, **none of which
> are in this tree**, and it uses a population series (to 300,000) that
> `suite_del.dme` does not run (it stops at 200,000). Those tables are unverified
> and are flagged individually.
>
> What the 1666-versus-1685 comparison establishes is that **`suite_del.dme`'s own
> figures are unchanged across the GC fixes**. It does not validate the tables
> below, and it does not reproduce the 3,300x headline, which rests on a
> 300,000-object measurement no harness in this tree performs.

### Cost by reference count

Clean world, 400 turfs, live object count held at zero in both arms. Median of
three, three runs per build.

| Heap refs on victim | 516.1666 | 516.1685 |
|---|---|---|
| 0 | not resolvable | not resolvable |
| 1 | 9.4 to 10.7 µs | 9.4 to 10.4 µs |
| 256 | 11.4 to 13.7 µs | 10.7 to 14.2 µs |

One heap reference costs about 10 µs. **256 references cost roughly 1.3x that,
not the same.** The direction held in every run on both builds.

That is still very nearly flat: 256x the references buys 1.3x the cost, so
reference count barely matters and the design guidance is unchanged. But the
earlier claim that cost is *flat* in reference count, and the supporting series
"8.3, 10.3, 8.3, 10.3, 8.3 µs, no drift", were reading quantization rather than
the engine. Both are withdrawn.

The zero-reference case is **not measurable by this harness**. Its signal is 3 to
8 percent of a tick against a 20 percent floor, so it is flagged
`LOW_RESOLUTION` and withheld. The earlier "0 µs, zero heap references is free"
was that same artifact reported as a finding.

### Cost by live object count

Clean world, population grown monotonically. Victim holds one heap reference.

**Unverified, from harnesses not in this tree.** `delscale2.dme` and
`delcause.dme` are cited as the source and neither exists here. Where the series
overlaps what `suite_del.dme` does measure, the two disagree well outside the 15%
band this page claims for itself:

| Live objs | published | `suite_del.dme`, 516.1666 | `suite_del.dme`, 516.1685 |
|---|---|---|---|
| 0 | 10 µs | 9.6 to 9.7 µs | 9.4 to 11.4 µs |
| 10,000 | 20 µs | not measured | not measured |
| 25,000 | 50 µs | not measured | not measured |
| 50,000 | 75 µs | 81 to 132 µs | 76 to 87 µs |
| 100,000 | 210 µs | 169 to 207 µs | 178 to 210 µs |
| 200,000 | 1,860 µs | **2,398 to 2,605 µs** | **2,437 to 2,590 µs** |
| 300,000 | 3,345 µs | not measured | not measured |

The 200,000 row is 29 to 40% above the published value on both builds, and the
old `world.timeofday` baseline read 2,333 there, so this is not the clock change.
The published series should be treated as indicative until a harness in this tree
reproduces it.

Growth is superlinear above 50,000. That much is reproduced by `suite_del.dme` on
both builds and is not in doubt.

At 300,000 live objs and `tick_lag 0.5`, 15 deletions consume the tick. **Rests on
the unverified 300,000 figure.**

### Turfs are not counted

Map resized with no objects present:

| Map | Turfs | del cost |
|---|---|---|
| 20x20 | 400 | 17 µs |
| 60x60 | 3,600 | 17 µs |
| 100x100 | 10,000 | 17 µs |
| 160x160 | 25,600 | 17 µs |
| 220x220 | 48,400 | 17 µs |

Completely flat. Only objs and mobs contribute.

### Cumulative allocation does not matter

Objects allocated then immediately freed, so live count stays at zero:

| Cumulative allocations | Live objs | del cost |
|---|---|---|
| 20,000 | 0 | 10 µs |
| 140,000 | 0 | 10 µs |
| 380,000 | 0 | 10 µs |
| 620,000 | 0 | 10 µs |

Flat. How many objects a server has created over its lifetime is irrelevant.

### Peak concurrent population leaves a permanent residual

| State | Live objs | del cost |
|---|---|---|
| cold start | 0 | 10 µs |
| grown to 300,000 | 300,000 | 3,345 µs |
| all 300,000 freed | 0 | **180 µs** |

Freeing the population does not restore the cold cost. Whatever structure the scan walks grows with peak concurrent live count and never shrinks. A one-off population spike raises `del()` cost 18x for the remaining life of the process.

### Alternative

```dm
del(thing)          // 3,345 µs at 300k live objs
thing = null        // 1 µs, flat at any population
```

### Not a defect: confirmed across the GC fixes

516.1676, 1678 and 1679 fixed garbage collection bugs that 516.1676 describes as
longstanding, which placed them inside 516.1666 and put every figure in this
section in doubt. Tested directly, three runs on each build:

| id | 516.1666 | 516.1685 |
|---|---|---|
| `del.live_0` | 9.60 9.63 9.73 | 11.4 10.6 9.42 |
| `del.live_200000` | 2398 2475 2605 | 2468 2590 2437 |
| `del.residual_after_peak` | 151 131 143 | 150 142 145 |

Unchanged. The superlinear growth and the permanent residual are engine
characteristics, not defects.

**Two caveats that must travel with this result.**

516.1676's pathology requires `del()` *and* a large number of sleeping or spawned
procs in the scheduler simultaneously. This suite is deliberately isolated and
carries no scheduler load, so the comparison never exercised the fixed path. What
is shown is that the isolated case is unaffected.

The comparison covers `suite_del.dme`'s own rows, which stop at 200,000 live
objects. **The 3,300x headline is not among them.** It derives from a
300,000-object measurement made by a harness absent from this tree, and no run on
either build reproduced it.

### Measurement note

An earlier version of this page reported a 155 to 200 µs floor at zero live objects. That was an artifact of harness ordering: the section ran a 300,000-object test before the sweep, which set the residual described above. The clean baseline is 10 µs. Isolate `del()` measurements in a fresh process.

---

## 3. List lookup

Worst case for `in`: needle is the last element. Baseline removed.

| Entries | `needle in L` | `A[needle]` |
|---|---|---|
| 10 | 0.09 µs | 0.09 µs |
| 50 | 0.18 µs | 0.10 µs |
| 100 | 0.28 µs | 0.09 µs |
| 500 | 1.07 µs | 0.12 µs |
| 1,000 | 2.04 µs | 0.13 µs |
| 5,000 | 10.0 µs | 0.14 µs |

Associative lookup is flat. `in` is linear at roughly 2 ns per element.

Crossover is 10 to 20 entries. Below that the two are equivalent.

```dm
L.Find(needle)      // n=100, hit    0.37 µs
needle in L         // n=100, miss   0.24 µs
```

---

## 4. List building

100 elements per iteration.

```dm
L = list(); L += j                                         // 10 µs
L = new(100); L[j] = j                                     // 12 µs
L = list(); L.Add(j)                                       // 15 µs
L.Copy()                                                   // 1.53 µs
```

Preallocation is slower than `+=`. List growth is already amortised. `.Add()` costs 50% more than `+=`.

---

## 5. Type tests

Baseline removed.

```dm
istype(O, /obj/thing)                                      // 0.09 µs
O.type == /obj/thing                                       // 0.10 µs
O.flags & FLAG_A                                           // 0.11 µs
O.categories["weapon"]                                     // 0.14 µs
locate(/obj/thing) in O          // 1 item in contents     // 0.13 µs
```

Spread is 0.05 µs across all five. Dispatch strategy is a design decision, not a performance one.

---

## 6. Calls and variable access

Baseline removed.

```dm
GlobalProc()                     // empty proc             // 0.12 µs
D.Method()                       // empty datum method     // 0.18 µs
D.Method()                       // sets . = 1             // 0.17 µs
acc += local_var                                           // 0.02 µs
acc += global_var                                          // 0.02 µs
acc += world.time                                          // 0.04 µs
acc += D.x                       // datum var              // 0.09 µs
```

A proc call is 0.12 to 0.18 µs. Datum variable access is 4x a local and still under 0.1 µs. Globals cost the same as locals.

At `tick_lag 0.5` this allows roughly 300,000 proc calls per tick.

---

## 7. Strings

Baseline removed.

```dm
s = "[a][b]"                     // embed                  // 0.30 µs
s = a + b                        // concat                 // 0.32 µs
num2text(i)                                                // 0.89 µs
findtext(hay, "lazy")            // 43-char haystack       // 2.04 µs
```

`findtext` is the most expensive routine operation listed here.

---

## 8. Allocation

Baseline removed. Three High-priority runs merged, 2026-07-31.

```dm
new /datum                                                 // 0.20 µs
new /datum/holder                // 1 var, 2 procs         // 0.22 µs
new /obj                                                   // 0.46 µs
new /mob                                                   // 0.53 µs
```

An earlier version claimed a blank `/mob` costs the same as a blank `/obj` and
that var count, not type, drives allocation cost. The data supports neither.
The mob reads 10 to 22% above the obj across merges, same direction in every
run. The large step is datum to obj, 0.20 to 0.46, which is a type
distinction with no vars added; one var on a datum adds nothing measurable.
The two datum rows are BASELINE_HEAVY, meaning a quarter or more of the raw
reading is the subtracted empty-loop term.

A mob with 30 vars and 3 lists measured 2.6 µs by the unported respawn
harness; indicative only, per the harness note at the top of this page.

---

## 9. Movement

Baseline removed. Three High-priority runs merged, 2026-07-31.

```dm
M.loc = T                        // direct                 // 0.24 to 0.33 µs
M.Move(T)                        // Enter/Exit chain       // 2.54 µs
M.Move(T)                        // all 4 callbacks overridden // 3.94 µs
```

`loc` assignment is the one wide row here, so its ratio to `Move()` is 8 to
11x rather than a point value. Overriding the callbacks, which is what real
codebases do, costs 55% over the plain path.

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

```dm
file << "short line"            // 313 us
file << "1000-char line"        // 351 us
file << "line with [value]"     // 330 us   includes string building
world.log << "short line"       // 5.9 us
```

**A direct file write costs about 313 us.** That is roughly 1,500 proc calls, and at
`tick_lag 0.5` a mere 160 of them consume the entire tick. Writing to a file per
game event is not viable.

**`world.log` is ~53x cheaper** at 5.9 us, because it goes to buffered stdout rather
than an unbuffered flush.

**Cost is per call, not per byte.** 1000 characters costs 12% more than 10, despite
100x the data. Batching many lines into a single write is therefore nearly free per
additional line, and is the correct fix if you need volume.

Neither form yields to the scheduler. `world.time` was unchanged across 20,000
writes of each kind, so logging does not break a no-sleep guarantee. It just costs.

---

## 12. Network cost with real clients

Measured with the server on a remote Linux box (Vultr, 1 vCPU, Ubuntu 24.04) and clients on a separate Windows machine over the public internet, so client rendering cannot contend with server CPU. Server-side instruments: `world.cpu` and NIC byte counters from `/proc/net/dev`.

`world.map_cpu` does not exist in 516. `world.tick_usage` sampled at the top of a tick stays at 0 regardless of client load, so it does not capture map send cost. `world.cpu` does.

Scene: 120x120 map, 1500 objs and 300 NPCs inside a 21x21 zone. In `moving` modes every NPC takes a `step()` each tick at `tick_lag 0.5`.

### The cost is change, not content

Three clients (`Suicide Shifter`, `Guest-1217841536`, `Penk`):

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

DM numbers are 32-bit floats. Integers are exact to 2^24 = 16,777,216. Tested directly in `numlimits.dme`.

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

| Rule | Ratio |
|---|---|
| `for(var/mob/M in view())` instead of assigning `view()` to a var | 1.7x empty, 10x typical, 77x crowded |
| Re-query `view()` instead of caching for two passes | 2.0 to 2.1x |
| `range()` instead of `view()` when line of sight is not needed | 2.3 to 3x |
| Push from the event instead of polling from observers | 9.2 to 9.6x |
| `thing = null` instead of `del(thing)` | ~2,400x at 200k live objs (measured); 3,300x at 300k is unverified, see 2 |
| `loc =` instead of `Move()` when callbacks are not needed | 8 to 11x |
| Associative list above 20 entries | up to 70x |
| `+=` instead of `.Add()` for list building | 1.4x |

Type test strategy has no measurable performance impact.

Clear `contents` before nullspacing, or the object leaks permanently.
