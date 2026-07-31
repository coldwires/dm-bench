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

var/global/OUTFILE
var/global/OUTPATH
// Set by the manifest before the first Row(), e.g. "del". Keeps suites from
// writing over each other when several run against the same build.
var/global/SUITE_TAG = ""
var/global/BASE_US = 0
var/global/PASSED = 0
var/global/FAILED = 0
var/global/MEASURED = 0
var/global/LOWRES = 0

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
	// sub_baseline strips the empty-loop cost, which matters below ~1 us.
	Measure(id, category, name, dt, reps, sub_baseline, notes)
		var/raw = dt * 100000 / reps
		var/val = sub_baseline ? (raw - BASE_US) : raw
		if(val < 0) val = 0
		MEASURED++
		var/flag = ""
		if(dt < MIN_DS)
			LOWRES++
			flag = "LOW_RESOLUTION"
		var/n = notes ? notes : ""
		if(flag) n = n ? "[flag]; [n]" : flag
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
	CalibrateBaseline()
		var/acc = 0
		var/outer = 5
		var/inner = 10000000
		var/reps = outer * inner
		var/t0 = world.timeofday
		for(var/o = 1 to outer)
			for(var/i = 1 to inner)
				acc++
		var/dt = world.timeofday - t0
		if(acc < 0) Row("# unreachable")
		BASE_US = dt * 100000 / reps
		Measure("framework.empty_loop", "framework", "empty loop iteration", dt, reps, 0, "baseline, subtracted from sub-microsecond rows")
		Row("# baseline_us\t[round(BASE_US, 0.01)]")

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
		Row("# result\t[FAILED ? "FAIL" : "PASS"]")
