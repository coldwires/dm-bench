# Contributing

Three kinds of contribution, in increasing order of what they cost you.

## 1. Run the assertion suite on a build nobody has tested

**This needs no qualified hardware and it is the most useful thing most people
can do.** Assertion verdicts are machine independent: the engine either
collects a reference cycle or it does not, and that answer does not depend on
your CPU. A laptop, a VM, or a shared VPS is fine for this.

```
tools/run.ps1 -Suite suite -Version <build>     # Windows
tools/run.sh --suite suite --version <build>    # Linux
```

Open an issue with the result file, or a pull request adding it under
`results/`. What matters is the assertion block, not the timings.

**A verdict that disagrees with the published matrix is a finding, not a
mistake.** Do not assume your machine is wrong. Either the behaviour is
environment dependent, which is worth its own investigation, or something in
the run is broken, which the header will usually show. Say what you saw.

## 2. Publish measurements from your own machine

Timings need a qualified machine, and qualifying one is deliberately a
protocol rather than a vibe. It is written out in `docs/METHOD.md` under
**How a machine qualifies**: measure your own spread by band, run the
scheduling experiment interleaved, check ambient sensitivity across a day, and
let the clock calibrate itself. It takes about ten runs and no more.

Until that is done, your machine's numbers stay yours. After it, they get
their own column with their own error bars.

**Absolute times never merge across machines.** An average of twenty machines'
microseconds describes no machine that exists. Ratios pool as a median with
the cross-machine range beside them, and only where both arms of the ratio are
bounded by the same resource. The rules are in `docs/METHOD.md` under **Many
machines, one record**.

## 3. Add a test

The bar is not "it measures something". It is:

- **A falsifiable statement about the engine.** "Assigning `loc` is cheaper
  than calling `Move()`" is testable. "Lists are slow" is not.
- **A control that behaves differently if the claim is false.** The `istype`
  scaling test ships with a `typesof` companion that is expected to scale, so
  a harness that measures nothing fails loudly instead of reporting everything
  as flat. A measurement without a control is not a test.
- **An equivalence assertion, if you are comparing two ways of doing one
  thing.** Assert the two produce identical output before comparing their
  timings. A published 19x claim here turned out to be comparing different
  work.
- **An ordering assertion, if you are sweeping an axis.** Radius, list size,
  population: if the ordering is known in advance, encode it. Ordering needs
  no tolerance and cannot flip on noise. A wrong divisor once published two
  rows 1.83x high through every repeatability check this project had, and only
  an impossible ordering in the data gave it away.
- **A version boundary, if the claim is about a change.** A claim plus a build
  either side of it is a regression test. A claim without one is folklore.

Route every timing through `Measure`, `MeasureTU`, `MeasureUTU` or
`MeasureDelta`. `Value()` applies no resolution check at all, which is exactly
how a whole section of this suite once published quantization as data.

Anything that grows the live object population, or grows engine state without
bound, needs its own manifest. `suite_del.dme` and `suite_animate.dme` are
separate processes for that reason, not by preference.

## What a pull request has to pass

```
tools/check-docs.ps1        # counts in prose match the data, references resolve
site/gen-site.ps1           # regenerate the page if you changed results/
```

CI runs both, and it fails if `site/index.html` disagrees with what the
generator produces from the checked-in baselines. Never hand-edit the HTML.

Do not commit a baseline from a single run. A baseline is three runs merged by
`tools/merge-runs.ps1`, which refuses to blend builds, systems, priorities,
clocks, stdout bindings or source commits, and exits non-zero if any assertion
was unstable across the runs.

## What this project will not publish

- A figure from a flagged row. `LOW_RESOLUTION` and `SUBTRACTION_NOISE` mean
  the number is not evidence, and a withheld row is more honest than a
  plausible one.
- A figure whose harness is not in the tree. Two sections here carry that
  banner and one was withdrawn entirely rather than restated.
- Provenance in the published record. Who said a thing, or where a claim was
  found, belongs in the working notes. The public record is hypothesis, test,
  data.
