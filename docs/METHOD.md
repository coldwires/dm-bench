# How these tests were run

The answer at three depths, shortest first.

## The one-liner

Headless DreamDaemon, standalone builds, three runs per build merged as
medians with the spread published, every number regenerates from a TSV in the
repository. Click any row on the results page and it shows the DM that
produced it.

## The paragraph

Each BYOND build lives in its own folder under `byond-standalones/`, nothing
installed, so the build under test is always explicit, and the runner checks
the binaries' reported version against the folder label before every run. A
PowerShell runner compiles the suite with that build's `dm.exe` and runs it
under `dd.exe` headless, at High process priority. The suite itself is DM
code: it calibrates its clock at startup, times each operation over millions
of iterations, and writes a TSV named after the engine version it detected at
runtime, so a result cannot be filed under the wrong build. Every baseline is
three runs merged: measurements become the median with min, max and spread
recorded per row; assertions count as PASS only if every run passed. A row
that fails a resolution check is marked withheld instead of printed. The
`del()` tests run in a separate process, because deletion cost depends on the
process's peak historical object count and would contaminate everything that
runs after them.

## The receipts

Each clause above has a specific answer behind it, and most of them exist
because the naive version was tried first and produced a wrong number that is
still on the record.

**Why three runs?** One run cannot detect an unstable measurement. An
assertion in this suite once passed three consecutive runs and failed on the
fourth observation. The merge tool refuses runs from different builds,
different process priorities, or runs that ended early.

**Why High process priority?** Measured, not assumed: elevating priority
halved the between-run spread of long rows, 18.3% to 9.9% median, which
established that about half the noise floor was OS scheduling. The remainder
is thermal and cache state and does not yield to priority or to any choice of
clock, which is why every absolute figure carries an error bar of at least
15% and sub-microsecond values are one significant figure.

**How do you know the loop is not measuring the harness?** Because twice it
was, and both corrections are published with the old numbers beside the new.
`abs()` was published near five times its real cost until the accumulator
keeping its result alive was removed; the empty-loop baseline was 40% of some
readings until the measured expressions were unrolled. The current forms were
validated below the timing layer: compiling variants with 0, 1, 10 and 20
copies of a discarded expression and diffing the binaries confirms the
compiler emits discarded operations (16 bytes per istype, exactly linear) and
eliminates discarded reads entirely, which is why the four variable-read rows
still use an accumulator and carry a flag saying so.

**What clock?** `world.tick_usage`, calibrated per run against a long
`world.timeofday` reference, after establishing it is linear to within 2.4%
across a 500x workload range. `world.timeofday` alone has 0.1s resolution and
produced provably quantized results in the earliest `del()` figures: every
published value was an exact integer multiple of the clock quantum, and three
of seven assertions flipped at random between identical runs while the suite
reported zero failures. That incident is why resolution guards exist and why
a difference between two timed blocks carries its own separate guard.

**Comparisons are controlled.** Where two code forms are claimed equivalent,
an assertion checks they produce identical output before their timings are
compared; a published comparison once turned out to be comparing different
work. Claimed scaling is tested by varying the axis the claim is about, with
a control that is expected NOT to be flat, so a harness that measures nothing
fails loudly. Cross-build comparisons interleave their runs within one
sitting; a same-day pair of non-interleaved triples once produced a coherent
33% "improvement" across a whole row family that interleaving showed was
ambient machine drift, not the engine.

**Can I reproduce it?** Clone the repository, extract a BYOND release into
`byond-standalones/<version>/`, and run `.\tools\run.ps1 -Suite suite`. The suite
is self-contained and writes its own results file. Absolute times are
machine-specific and will differ; ratios should hold.

**The strongest claim last.** The repository history includes the wrong
numbers this project published and the control that caught each one. Anyone
asking how the tests were run is really asking whether the author would
notice being fooled. The honest answer is: not always, and here is the paper
trail of the machinery that noticed each time instead.

## Qualification in plain words

Everything in the next section reduces to one idea: **before you trust a
scale, you weigh the same object on it a few times and see how much the
readings disagree.** Qualification is not about BYOND at all. It is about
the machine, so that when the machine later measures BYOND, we know how much
to trust each number it produces.

The vocabulary, since it is smaller than it looks:

- A **run** is one execution of the suite. A **triple** is three runs
  back to back. A **sitting** is a triple done at one time of day.
- **Spread** is how much the three copies of a number disagree, as a
  percent. It is the machine's natural wobble. **By band** just means
  grouped by size, because tiny numbers wobble for different reasons than
  big ones.
- **Priority** (Windows) and **nice** (Linux) are the knob that tells the
  operating system "this program matters, interrupt it less".
- **Interleaved** means alternating two kinds of run (normal, elevated,
  normal, elevated) instead of doing all of one kind then all of the other.
  If the room warms up over the hour, alternation makes the warmth hit both
  kinds equally instead of faking a difference between them.

The order of operations for a new machine:

0. **Make it boring.** Nothing else running, automatic updates off, clocks
   locked to one speed. An instrument should be the same machine every day.
1. **Run a triple.** The disagreement between the three copies of each
   number is the machine's wobble, and that wobble is its error bar from
   now on.
2. **Run the priority experiment**, interleaved. If elevation shrinks the
   wobble, it becomes the machine's permanent setting; if it does nothing,
   the machine runs plain. Both answers are fine; the point is to know.
3. **Run one more triple at a different time of day.** If the wobble grows
   when the surroundings are busy, runs get scheduled for quiet hours.
4. **Clock check: automatic.** Every run calibrates its own stopwatch
   against a second one. Nothing to do.

Then the machine is qualified, which only means: its wobble is known and
written down. And the first triple from step 1 is not thrown away. Its three
copies of each number get merged (take the middle value) and that file
becomes the machine's baseline, the official reference numbers. The
measuring and the qualifying are the same runs, examined from different
angles, which is why a new machine needs about ten runs total and no more.

## How a machine qualifies

A machine's numbers are published only after the machine itself has been
measured. Every box that contributes results goes through the same
qualification the original Windows machine went through:

1. **Spread by band.** Run the suite at least three times and measure the
   run-to-run spread of small, medium and long rows separately. Long rows
   carry no quantization and subtract no baseline, so their spread is the
   machine's own noise floor. On the first machine that floor was about 15%.

2. **The scheduling experiment.** Re-run at elevated process priority,
   interleaved with normal-priority runs so ambient drift cannot pose as a
   priority effect. Whatever elevation buys becomes that machine's standard
   running condition. On the first machine it halved long-row spread, 18.3%
   to 9.9%, which also established that half the noise was the OS scheduler
   and the rest thermal and cache state.

3. **Ambient sensitivity.** Same suite, same settings, different times of
   day. On the first machine the count of high-spread rows ranged from 11 to
   30 within one day, so that count is treated as a property of conditions
   at run time, never as a property of the suite or the engine.

4. **Clock calibration.** The conversion from the engine's tick-usage clock
   to microseconds is measured per run against a long wall-clock reference,
   never assumed, after first establishing the clock is linear across a
   500x range of workload.

The point of all four: each machine's column carries its own error bars, and
no number is quoted at more precision than its machine has demonstrated it
can deliver. A new machine publishes nothing until it has been through this,
and the same protocol applies to anyone running the suite on their own
hardware.

Two machines have been through it. The first is a Windows desktop in daily
use, which is why its error bars are the wider pair. The second is a
bare-metal Linux box, headless, clock-clamped and otherwise idle, qualified
2026-08-02: its median run-to-run spread is about 2%, against about 9% on the
first machine measured the same way. **That gap is the machine and its
conditions, not the operating system**, and it is the clearest available
demonstration of why absolute times are published per machine and never
blended.

## Setting up a bench machine

The steps a new machine goes through before its first qualification run.
Everything here exists because it measurably changed a number on the first
machine; nothing is cargo cult.

### Hardware

Any x86-64 CPU. BYOND is 32-bit x86, so ARM cannot run it at all. Single-core
speed and thermal stability are what matter; core count and RAM beyond 8 GB
are irrelevant to this suite. Small machines with small coolers can heat-soak
during a six-minute 100% single-core run, which shows up as drift no software
setting removes.

**Consider disabling turbo or boost in the firmware.** Boost clocks depend on
temperature, so they convert thermal state into timing noise. Disabling
trades peak speed for flat speed, which is the correct trade for a bench
machine: absolute figures drop, spreads tighten, ratios hold. Either choice
is fine; what is not fine is changing it between runs that will be compared.
Record the state either way.

Shared or virtual hardware cannot produce publishable measurements. A VPS
adds hypervisor steal time that no priority setting can remove, and a VM
shares its host's thermal and cache state. Such machines can still run the
assertion half of the suite, which is machine-independent.

### Windows

1. Plugged in, High Performance power plan, lid open if a laptop.
2. Close what can be closed. Background load is the single largest source of
   run-to-run spread measured on the first machine: the count of high-spread
   rows tripled between a quiet morning and a busy afternoon of the same day.
3. **Run nothing that watches the run.** A log tail or monitor observing
   DreamDaemon's output measurably changed CPU-bound sections by 20 to 25% on
   the first machine. Runs write to files; read the files afterwards.
4. Check reserved port ranges before choosing ports:
   `netsh interface ipv4 show excludedportrange protocol=tcp`. A port inside
   a reserved range fails silently and instantly. The runner defaults to a
   range that was clear on the first machine, not necessarily on yours.
5. Process priority is handled by the runner. High is the default and is
   stamped into every result file; the merge tool refuses to mix priorities.

### Getting builds

One folder per build under `byond-standalones/`, each holding a complete
extracted BYOND release, nothing installed, no registry writes. The folder
name must be the version, `516.1666` style, and the runner hard-errors if the
binaries inside report a different version than the folder claims. Use the
fetch script or extract a zip from byond.com by hand; never copy binaries
between folders.

### Producing a baseline

```powershell
.\tools\run.ps1 -List                        # confirm the build is discovered
.\tools\run.ps1 -Suite suite -Version <v>    # once per run, three runs minimum
.\tools\merge-runs.ps1 -Runs <dir1>,<dir2>,<dir3> -Out results\<v>-<system>-merged.tsv
.\tools\run.ps1 -Suite suite_del -Version <v>   # separate process, same drill
```

Move each run's TSV into its own directory before the next run. One run is
not a baseline: the merge exists to show whether the machine can repeat
itself, and it exits non-zero if any assertion was unstable across the
triple. Then run the qualification protocol above before treating any
measurement from the machine as publishable.

### Linux

Written against Ubuntu Server 24.04; any Debian-class distribution works the
same way. A server (no desktop) install is the right choice for a bench box:
fewer background services is measurably less noise. DreamDaemon ships 32-bit
x86.

1. **Base tools, then go headless.**
   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo apt install -y openssh-server git unzip
   ```
   Administer over SSH from then on. Nothing may watch a run (step 6).

2. **The 32-bit layer.**
   ```bash
   sudo dpkg --add-architecture i386
   sudo apt update
   sudo apt install -y libc6:i386 libstdc++6:i386 zlib1g:i386 libcurl4t64:i386
   ```
   The curl dependency hides inside libbyond.so, so `ldd DreamDaemon` does
   not reveal it; DreamMaker simply refuses to start without it. Found on
   the first real Linux setup, 2026-08-02.

3. **Builds, one folder per version.** URL shape verified 2026-08-01:
   ```bash
   mkdir -p ~/byond-standalones/516.1666 && cd ~/byond-standalones/516.1666
   wget https://www.byond.com/download/build/516/516.1666_byond_linux.zip
   unzip 516.1666_byond_linux.zip
   ldd byond/bin/DreamDaemon | grep "not found"    # empty output = satisfied
   ```
   Anything "not found" is one more `:i386` package.

4. **Flat clocks.** Disabling boost in the firmware is the durable form and
   applies to every OS on the machine. The per-boot software equivalent:
   ```bash
   echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   ```
   The boost knob's location depends on the kernel's frequency driver
   (`/sys/devices/system/cpu/cpufreq/boost` under acpi-cpufreq, per-policy
   under amd_pstate). **If the firmware exposes no boost switch at all**,
   common on laptop-derived boards, clamp the frequency ceiling to the base
   clock instead; a chip that cannot clock past base is boost-disabled by
   construction, and this works under any driver:
   ```bash
   sudo cpupower frequency-set -g performance -u <base>MHz
   ```
   On Windows the equivalent is the hidden power-plan setting: unhide with
   `powercfg -attributes SUB_PROCESSOR PERFBOOSTMODE -ATTRIB_HIDE`, set
   `PERFBOOSTMODE` to 0 on the active scheme. Software settings are per-boot
   and per-OS where firmware is global: record them per OS, and verify by
   watching the clock under load stay at base. Whichever boost state is
   chosen, record it and never change it between runs that will be
   compared.

5. **Compile and run.** Manual until a shell twin of the runner exists:
   ```bash
   export LD_LIBRARY_PATH=~/byond-standalones/516.1666/byond/bin
   ~/byond-standalones/516.1666/byond/bin/DreamMaker suite.dme
   ~/byond-standalones/516.1666/byond/bin/DreamDaemon suite.dmb 47899 -trusted -invisible
   ```
   The suite names its own result `-unix`. Three runs into separate
   directories, then merge, exactly as on Windows. Priority discipline is
   `nice` or `chrt` in place of a priority class; adopt whatever level the
   qualification experiment measures a benefit from, then never vary it.

6. **Decide how DreamDaemon's stdout is bound, and never change it between
   compared runs.** Binding stdout straight to a file changed the measured
   cost of a `world.log` write by roughly 20x on the first machine and
   flipped an io assertion. It is an environmental sensitivity, not a
   defect; the binding is part of a run's recorded conditions.

7. **Qualification**, per the protocol above, before anything publishes.

### After qualification

The machine's standard running condition (priority, boost state, stdout
binding) is recorded alongside its qualification numbers, and its results
get their own column with their own error bars, per the federation rules
below.

**The first cross-OS assertion matrix now exists, and it is clean.** All 59
assertions carry the same verdict on Windows and Linux, on both 516.1666 and
516.1685, compared by id and verdict rather than by counting passes. That was
an open question with no data behind it until 2026-08-03. It is the weaker of
the two possible answers, since a disagreement would have been a finding about
the engine, but it is the one that makes the assertion half of this suite
portable in fact rather than in principle.

**It also does work the build matrix could not do alone.** One assertion
differs between builds, `lists.find_costs_about_the_same_as_in`, and it flips
in the same direction on both operating systems. A verdict that moved on one OS
and not the other would have been a platform property; one that moves on both
is the engine. The clean cross-OS column is what licenses calling the `Find()`
regression an engine change rather than a Windows one.

Cost is a different story in one place. Engine compute measures the same on
both machines; the io layer does not, and a direct file write is roughly 20x
cheaper on the Linux box than on the Windows one. Design advice that rests on
io therefore carries its platform with it. The results page states the
divergent rows and links both baselines; the tables are deliberately not split
by operating system, because a handful of rows do not justify a dimension
through every figure.

## Many machines, one record

Whether twenty people can run this and produce one coherent record depends on
which of the three result kinds is being combined. The rule set:

**Assertion verdicts merge globally.** PASS or FAIL is machine-independent:
the engine either collects a reference cycle or it does not, on any hardware.
Twenty machines running the assertion suite against every build and OS is
pure coverage, and it is the intended crowd-scale contribution. A verdict
that DIFFERS across machines is not noise to vote away, it is a discovery:
either the behaviour is environment-dependent, which earns its own numbered
audit entry, or one machine's run is broken, which its qualification record
will show.

**Ratios pool as distributions, never as a single number.** Ratios mostly
travel between machines because both arms share conditions. A design rule
holds when its direction holds on every qualified machine; the published form
is the median ratio with the cross-machine range beside it. "Typed view loop,
8 to 14x across N machines" is stronger evidence than any single machine can
produce. A machine where the direction reverses is, again, a finding.

**Absolute times never merge across machines.** An average of twenty
machines' microseconds describes no machine that exists. Each qualified
machine is its own column with its own error bars from its own qualification,
exactly as `merge-runs.ps1` already refuses to blend builds, systems or
priorities within one machine. Machine drift does not make the model
unfeasible; it makes blending unfeasible, and blending was never the product.

The precedent is SPEC rather than a leaderboard: standardized run rules, a
disclosure record per machine, results keyed by system. What the crowd
contributes is the assertion matrix and ratio consensus; what stays
per-machine is everything with units on it.
