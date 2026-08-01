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
`byond-standalones/<version>/`, and run `.\run.ps1 -Suite suite`. The suite
is self-contained and writes its own results file. Absolute times are
machine-specific and will differ; ratios should hold.

**The strongest claim last.** The repository history includes the wrong
numbers this project published and the control that caught each one. Anyone
asking how the tests were run is really asking whether the author would
notice being fooled. The honest answer is: not always, and here is the paper
trail of the machinery that noticed each time instead.

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
can deliver. A new machine publishes nothing until it has been through this;
a planned bare-metal Linux box will be the second, and the same protocol
applies to anyone running the suite on their own hardware.
