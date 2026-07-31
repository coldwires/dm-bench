// Canonical BYOND test suite: framework.
//
// Two kinds of result:
//
//   ASSERT   engine behaviour with a known-correct answer. PASS/FAIL.
//            These catch regressions. If a future BYOND changes GC semantics,
//            an assertion FAILS and that is the headline, not a footnote.
//
//   MEASURE  a cost with no correct answer. Compare across versions and
//            machines. Absolute numbers do not travel; ratios do.
//
// Output is TSV to results.tsv next to the .dmb, with stable test IDs so runs
// from different BYOND versions diff cleanly.

obj/fw_probe

var/global/OUTFILE
var/global/OUTPATH
// Set by the manifest before the first Row(), e.g. "del". Keeps suites from
// writing over each other when several run against the same build.
var/global/SUITE_TAG = ""
var/global/BASE_US = 0
// Cost of one bare loop iteration with NO accumulator. Rows measured the
// unrolled, result-discarded way subtract BASE_LOOP_US/unroll instead of
// BASE_US. Measured 516.1666: bare loop 0.034 us, accumulator a further 0.040.
// The accumulator is the larger term, which is why dropping it matters more
// than unrolling. See INSTRUMENTS.md.
var/global/BASE_LOOP_US = 0
var/global/PASSED = 0
var/global/FAILED = 0
var/global/MEASURED = 0
var/global/LOWRES = 0
var/global/HEAVY = 0

// Every measurement should run this long. Below it, world.timeofday's 0.1s
// resolution dominates and the number is noise. Rows under this are flagged.
#define MIN_DS 15

// ---- clocks ----
//
// world.timeofday has 0.1s resolution. That is adequate for one long block and
// useless for the DIFFERENCE between two of them, which is what every del() row
// is. The del rows were reported through Value(), which performs no resolution
// check at all, so three of the seven del assertions flipped at random across
// four runs of one build on one machine while the suite reported 0 failed.
//
// world.tick_usage is the fix. Measured on 516.1666: linear to within 2.4%
// across a 500x range of workload (2k to 1M iterations), and it agrees with
// timeofday on a long run. A tight loop is never preempted and world.time does
// not advance during one, so tick_usage accumulates monotonically past 100% for
// the whole block and a plain before/after delta works with no per-tick
// accumulation.
//
// Costs about 0.10 us per read, so read it either side of a timed block, never
// inside an inner loop.
//
// US_PER_PCT is CALIBRATED at startup, not assumed from tick_lag * 1000. The
// predicted and measured values differed by 6% on first test, within the
// reference clock's own error, which is precisely why it is measured.
var/global/US_PER_PCT = 0

// A tick_usage delta below this is under-resolved. At 5% the observed spread
// was 8%, at 23% it was 5.7%. Rows under MIN_PCT are flagged.
#define MIN_PCT 20

// A difference carries the error of BOTH arms, so a small delta between two
// large arms is noise even when each arm is individually well resolved. That is
// exactly how the del() rows looked fine while flipping. Flag when the delta is
// a smaller fraction of the larger arm than this.
#define MIN_DELTA_FRAC 0.1

// A sub_baseline row where the subtracted term is more than this fraction of the
// raw reading is dominated by baseline calibration rather than by the operation.
// Advisory, not disqualifying: it does not mean the figure is wrong, it means
// the figure will not repeat to the precision it is printed at.
#define BASELINE_HEAVY_FRAC 0.25

// Unroll helpers. Repeat the measured expression inside one loop iteration so
// loop machinery is amortised across U operations. Verified on 516.1666: the
// body executes exactly U times, and a statement following an if() is NOT
// swallowed into the if body.
//
// Pair with discarding the result rather than accumulating it. Together these
// take the subtracted baseline on istype from 40.7% of the reading to 3.4%.
// Either alone is worth little: unrolling gets to 34%, discarding to 26%.
#define X2(s)  s; s
#define X5(s)  s; s; s; s; s
#define X10(s) s; s; s; s; s; s; s; s; s; s
#define UNROLL 10

proc
	// The run names its own output after the engine that produced it, so a
	// result can never be filed under the wrong build by hand. Nothing outside
	// this proc decides the filename.
	ResultPath()
		return "results-[world.byond_version].[world.byond_build]-[SystemName()][SUITE_TAG ? "-[SUITE_TAG]" : ""].tsv"

	Row(text)
		if(!OUTFILE)
			OUTPATH = ResultPath()
			// file() << APPENDS. Verified: two runs against one path produce a
			// doubled file with no warning. Truncate, or a re-run silently
			// corrupts the baseline it is supposed to replace.
			if(fexists(OUTPATH)) fdel(OUTPATH)
			OUTFILE = file(OUTPATH)
		OUTFILE << text

	SystemName()
		return (world.system_type == MS_WINDOWS) ? "windows" : "unix"

	Header()
		Row("# suite\tbyond-canonical[SUITE_TAG ? "-[SUITE_TAG]" : ""]")
		Row("# byond_version\t[world.byond_version]")
		Row("# byond_build\t[world.byond_build]")
		Row("# result_file\t[OUTPATH]")
		Row("# system\t[SystemName()]")
		Row("# tick_lag\t[world.tick_lag]")
		Row("# min_ds\t[MIN_DS]")
		Row("# min_pct\t[MIN_PCT]")
		// Column 9 is the resolution figure behind the row: deciseconds for a
		// timeofday row, tick-percent for a tick_usage one. Excluded from diffs,
		// present so an under-resolved row stays auditable.
		Row("kind\tid\tcategory\tname\tvalue\tunit\texpected\tstatus\tres\tnotes")

	// ---- assertions ----

	Assert(id, category, name, actual, expected, notes)
		var/ok = ("[actual]" == "[expected]")
		if(ok) PASSED++
		else FAILED++
		Row("ASSERT\t[id]\t[category]\t[name]\t[actual]\t\t[expected]\t[ok ? "PASS" : "FAIL"]\t\t[notes ? notes : ""]")
		return ok

	// ---- measurements ----

	// dt is deciseconds from world.timeofday. reps is the iteration count.
	//
	// sub_baseline strips the empty-loop cost. That subtraction is not free: it
	// makes the row a DIFFERENCE, with all the error behaviour of one. Measured
	// 2026-07-31 across three runs of 516.1666, BASE_US itself moved 0.06 to
	// 0.08, and on 25 rows it is a quarter or more of the raw figure. Its error
	// is systematic across every such row, not random, because it is calibrated
	// once per run. The flags below make that visible instead of silent.
	Measure(id, category, name, dt, reps, sub_baseline, notes)
		var/raw = dt * 100000 / reps
		var/val = raw
		var/flag = ""
		if(sub_baseline)
			val = raw - BASE_US
			if(val <= 0)
				// The operation is indistinguishable from an empty loop. This is
				// the ABSENCE of a measurement. It used to be clamped to 0 and
				// published as "0.00 us", which reads as a very fast operation.
				val = 0
				flag = "BELOW_BASELINE"
			else if(raw > 0 && (BASE_US / raw) > BASELINE_HEAVY_FRAC)
				// Most of this figure is the subtracted term. Not noise exactly,
				// but the row moves with baseline calibration rather than with
				// the operation, so it will not repeat across runs.
				flag = "BASELINE_HEAVY"
		MEASURED++
		if(dt < MIN_DS)
			flag = "LOW_RESOLUTION"
		if(flag == "LOW_RESOLUTION" || flag == "BELOW_BASELINE") LOWRES++
		else if(flag == "BASELINE_HEAVY") HEAVY++
		var/n = notes ? notes : ""
		if(flag) n = n ? "[flag]; [n]" : flag
		Row("MEASURE\t[id]\t[category]\t[name]\t[val >= 10 ? round(val,0.1) : round(val,0.01)]\tus\t\t\t[dt]\t[n]")
		return val

	// A row measured the unrolled, result-discarded way. `unroll` is the factor
	// the loop body was repeated by, and `reps` is still the total operation
	// count, not the loop count.
	//
	// Subtracts BASE_LOOP_US/unroll, not BASE_US. The measured loop carries no
	// accumulator, so subtracting an accumulator-inclusive baseline would
	// over-subtract by about 0.040 us and drive small rows negative.
	MeasureU(id, category, name, dt, reps, unroll, notes)
		var/raw = dt * 100000 / reps
		var/base = BASE_LOOP_US / max(unroll, 1)
		var/val = raw - base
		var/flag = ""
		if(val <= 0)
			val = 0
			flag = "BELOW_BASELINE"
		else if(raw > 0 && (base / raw) > BASELINE_HEAVY_FRAC)
			flag = "BASELINE_HEAVY"
		MEASURED++
		if(dt < MIN_DS)
			flag = "LOW_RESOLUTION"
		if(flag == "LOW_RESOLUTION" || flag == "BELOW_BASELINE") LOWRES++
		else if(flag == "BASELINE_HEAVY") HEAVY++
		var/n = notes ? notes : ""
		n = n ? "u=[unroll]; [n]" : "u=[unroll]"
		if(flag) n = "[flag]; [n]"
		Row("MEASURE\t[id]\t[category]\t[name]\t[val >= 10 ? round(val,0.1) : round(val,0.01)]\tus\t\t\t[dt]\t[n]")
		return val

	// ---- tick_usage measurements ----

	// pct is the world.tick_usage delta across the timed block.
	MeasureTU(id, category, name, pct, reps, sub_baseline, notes)
		var/raw = pct * US_PER_PCT / reps
		var/val = sub_baseline ? (raw - BASE_US) : raw
		if(val < 0) val = 0
		MEASURED++
		var/flag = ""
		if(pct < MIN_PCT)
			LOWRES++
			flag = "LOW_RESOLUTION"
		var/n = notes ? notes : ""
		if(flag) n = n ? "[flag]; [n]" : flag
		Row("MEASURE\t[id]\t[category]\t[name]\t[val >= 10 ? round(val,0.1) : round(val,0.01)]\tus\t\t\t[round(pct,0.01)]\t[n]")
		return val

	// A measured arm minus its control arm. Both guards apply: the delta must be
	// resolvable in absolute terms AND must not be a sliver of two large arms.
	MeasureDelta(id, category, name, hi_pct, lo_pct, reps, notes)
		var/pct = hi_pct - lo_pct
		var/val = pct * US_PER_PCT / reps
		MEASURED++
		var/flag = ""
		if(pct < MIN_PCT)
			flag = "LOW_RESOLUTION"
		else if(hi_pct > 0 && (pct / hi_pct) < MIN_DELTA_FRAC)
			flag = "SUBTRACTION_NOISE"
		if(flag) LOWRES++
		var/n = "arms [round(hi_pct,0.01)]/[round(lo_pct,0.01)] pct"
		if(notes) n = "[n]; [notes]"
		if(flag) n = "[flag]; [n]"
		Row("MEASURE\t[id]\t[category]\t[name]\t[val >= 10 ? round(val,0.1) : round(val,0.01)]\tus\t\t\t[round(pct,0.01)]\t[n]")
		return val

	// convenience for raw values that are not per-operation times.
	// NOTE: performs no resolution check. Do not use it for a timing.
	Value(id, category, name, val, unit, notes)
		MEASURED++
		Row("MEASURE\t[id]\t[category]\t[name]\t[val]\t[unit]\t\t\t\t[notes ? notes : ""]")

	Median3(a, b, c)
		if((a <= b && b <= c) || (c <= b && b <= a)) return b
		if((b <= a && a <= c) || (c <= a && a <= b)) return a
		return c

	// ---- clock calibration ----

	// Derives us-per-tick-usage-percent against a timeofday run long enough that
	// its own 0.1s quantization is about 1%, so the factor is trustworthy to
	// roughly that. Must run before any MeasureTU or MeasureDelta row.
	//
	// Ratios do not depend on this factor at all, it cancels. It only matters
	// for absolute microsecond figures.
	CalibrateClock()
		var/acc = 0
		var/outer = 8
		var/inner = 10000000
		var/tod0 = world.timeofday
		var/tu0 = world.tick_usage
		for(var/o = 1 to outer)
			for(var/i = 1 to inner)
				acc++
		var/tud = world.tick_usage - tu0
		var/todd = world.timeofday - tod0
		if(acc < 0) Row("# unreachable")
		var/predicted = world.tick_lag * 1000
		US_PER_PCT = (tud > 0) ? (todd * 100000 / tud) : predicted
		Row("# clock\ttick_usage")
		Row("# us_per_pct_measured\t[round(US_PER_PCT, 0.01)]")
		Row("# us_per_pct_predicted\t[predicted]")
		Row("# clock_calibration_ds\t[todd]")
		Row("# clock_calibration_pct\t[round(tud, 0.01)]")

	// ---- baseline ----

	// A single for-loop cannot exceed 2^24 iterations (see assert_numeric),
	// and 16.7M at ~0.06us only reaches 10 ds. Nest to get enough runtime.
	// One pass of a loop with NO body. Measures loop machinery alone, with no
	// accumulator, which is what an unrolled result-discarded row needs to
	// subtract.
	// A bodyless for() is legal, but only when the next statement sits at the
	// SAME indent. Dedenting straight to `return` is "invalid expression".
	// Hence `guard`, which runs `outer` times, not `outer * inner`.
	BareLoopPass(outer, inner)
		var/guard = 0
		var/t0 = world.timeofday
		for(var/o = 1 to outer)
			for(var/i = 1 to inner)
			guard++
		var/dt = world.timeofday - t0
		if(guard < 0) Row("# unreachable")
		return dt

	// One pass of the empty loop. A single for() cannot exceed 2^24 iterations,
	// so this nests.
	EmptyLoopPass(outer, inner)
		var/acc = 0
		var/t0 = world.timeofday
		for(var/o = 1 to outer)
			for(var/i = 1 to inner)
				acc++
		var/dt = world.timeofday - t0
		if(acc < 0) Row("# unreachable")
		return dt

	// Median of three, not one.
	//
	// BASE_US is subtracted from every sub-microsecond row, so its error is
	// SYSTEMATIC across all of them rather than random: a baseline 0.01 high
	// pushes forty figures 0.01 low, in the same direction, and no amount of
	// repeating the suite on one build would reveal it. Measured across three
	// runs of 516.1666 on 2026-07-31, a single-reading baseline moved 0.06 to
	// 0.08, a 29% swing on the term being subtracted.
	CalibrateBaseline()
		var/outer = 5
		var/inner = 10000000
		var/reps = outer * inner
		var/a = EmptyLoopPass(outer, inner)
		var/b = EmptyLoopPass(outer, inner)
		var/c = EmptyLoopPass(outer, inner)
		var/dt = Median3(a, b, c)
		BASE_US = dt * 100000 / reps
		Measure("framework.empty_loop", "framework", "empty loop iteration", dt, reps, 0, "baseline, median of 3, subtracted from sub-microsecond rows")
		Row("# baseline_us\t[round(BASE_US, 0.01)]")
		Row("# baseline_passes_ds\t[a] [b] [c]")

		// A bare loop is roughly half the cost of one with an accumulator, so it
		// needs more iterations to clear MIN_DS. At outer=5 it measured 13 ds and
		// was correctly flagged LOW_RESOLUTION. Every converted row subtracts
		// this figure, so an under-resolved calibration would propagate.
		var/bouter = 12
		var/breps = bouter * inner
		var/ba = BareLoopPass(bouter, inner)
		var/bb = BareLoopPass(bouter, inner)
		var/bc = BareLoopPass(bouter, inner)
		var/bdt = Median3(ba, bb, bc)
		BASE_LOOP_US = bdt * 100000 / breps
		Measure("framework.bare_loop", "framework", "loop iteration, no accumulator", bdt, breps, 0, "median of 3, subtracted from unrolled rows")
		Row("# baseline_loop_us\t[round(BASE_LOOP_US, 0.01)]")

	// Rows measured by discarding the operation's result depend on DM emitting
	// an expression whose value is unused. It does on 516.1666, and the compiler
	// warns `statement has no effect` while emitting it anyway.
	//
	// That is a compiler behaviour, not a language guarantee. If a later build
	// eliminates dead expressions, every such row silently collapses to the
	// empty-loop cost and reports near zero with nothing flagged. This assertion
	// makes that fail loudly on the build that introduces it.
	AssertDiscardedWorkStillCosts()
		var/R = 4000000
		var/obj/fw_probe/P = new
		var/t0 = world.timeofday
		for(var/i = 1 to R)
		var/bare = world.timeofday - t0
		var/t1 = world.timeofday
		for(var/i = 1 to R)
			istype(P, /obj/fw_probe)
		var/discarded = world.timeofday - t1
		Assert("framework.discarded_work_still_costs", "framework",
			"an expression whose result is unused is still executed",
			(discarded > bare * 1.3) ? 1 : 0, 1,
			"bare loop [bare] ds, discarded istype [discarded] ds over [R]")

	// Wraps a suite call and records how long that section took, so the slow
	// parts are identified by measurement rather than by guessing.
	Section(name, dt_ds)
		Row("SECTION	[name]			[round(dt_ds/10, 0.1)]	s				")

	Summary()
		Row("")
		Row("# passed\t[PASSED]")
		Row("# failed\t[FAILED]")
		Row("# measured\t[MEASURED]")
		Row("# low_resolution\t[LOWRES]")
		Row("# baseline_heavy\t[HEAVY]")
		Row("# result\t[FAILED ? "FAIL" : "PASS"]")
