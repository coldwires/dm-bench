// Log and file I/O cost.
//
// This matters for two reasons beyond curiosity.
//
// 1. If a file write yields to the scheduler, then any "this proc must never
//    sleep" rule is violated by logging inside it, and a command queue that
//    logs per command has a reentrancy hole.
// 2. This framework writes a TSV row after every measurement. If writing
//    yields, the suite perturbs the thing it is measuring.

var/global/IOACC = 0

proc
	IO_LongLine()
		var/s = ""
		for(var/i = 1 to 100)
			s += "0123456789"
		return s          // 1000 chars

	// A stable reference workload, used to detect whether logging perturbs
	// whatever is measured next.
	IO_Reference(reps)
		IOACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			IOACC += i % 7
		return world.tick_usage - tu0

	// Median of three passes, in us per iteration. A single pass of this
	// reference is not stable enough to compare against.
	IO_RefMedian(reps)
		var/a = IO_Reference(reps)
		var/b = IO_Reference(reps)
		var/c = IO_Reference(reps)
		return Median3(a, b, c) * US_PER_PCT / reps

	// One timed pass of `reps` writes of `line` to `f`, in percent of a tick.
	//
	// world.tick_usage, not world.timeofday, since 2026-08-02. A file write
	// costs about 190 us on the Windows machine and about 10 on the Linux one,
	// so 10,000 writes fill 19 deciseconds there and 1 here: the same rep count
	// cannot clear a 0.1 second quantum on both machines, and no single
	// constant can be chosen that does. Raising reps 30x to suit the faster
	// machine would put one row into the minutes on the slower one. tick_usage
	// carries four to six significant figures and has no quantum to clear, so
	// the row resolves on both without either machine dictating the other's
	// rep count. Safe here because these loops never yield, which
	// io.file_write_does_not_yield asserts directly.
	IO_WritePass(f, line, reps)
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			f << line
		return world.tick_usage - tu0

	Suite_IO()
		var/probe = file("io_probe.tmp")

		// --- does writing yield to the scheduler? ---
		// world.time only advances when the scheduler runs. A proc that never
		// yields holds the tick, so an unchanged world.time means no yield.
		var/wt0 = world.time
		for(var/i = 1 to 4000)
			probe << "line [i]"
		var/wt1 = world.time
		Assert("io.file_write_does_not_yield", "io",
			"file write does not yield to the scheduler",
			(wt1 == wt0) ? 1 : 0, 1,
			"world.time [wt0] before, [wt1] after 4000 writes")

		var/log_writes = 20000
		var/lt0 = world.time
		for(var/i = 1 to log_writes)
			world.log << "suite io probe [i]"
		var/lt1 = world.time
		Assert("io.world_log_does_not_yield", "io",
			"world.log write does not yield to the scheduler",
			(lt1 == lt0) ? 1 : 0, 1,
			"world.time [lt0] before, [lt1] after [log_writes] writes")

		// --- cost per write ---
		// VERIFICATION 8.11: as single 8000-write passes these arms are 15 to
		// 22 timeofday quanta wide, and the ratio between two such readings
		// ranged 0.90 to 1.53 on identical code, flipping the old 1.5x
		// assertion in 2 of 9 runs. Median of three passes per arm, and the
		// threshold carries headroom: 2x still separates per-call dominance
		// decisively, since per-byte cost would put 100x the payload near
		// 100x the price.
		// 10000 writes per pass, raised from 8000: the median pass read 13
		// to 14 ds under fast ambient conditions and drew LOW_RESOLUTION in
		// 2 of 6 runs. 10000 puts the short arm near 26 ds.
		var/sdt = Median3(IO_WritePass(probe, "short line", 10000), \
			IO_WritePass(probe, "short line", 10000), \
			IO_WritePass(probe, "short line", 10000))
		var/short_us = MeasureTU("io.file_write_short", "io", "file << 10-char line",
			sdt, 10000, 1, "median of 3 passes")

		var/long_line = IO_LongLine()
		var/ldt = Median3(IO_WritePass(probe, long_line, 10000), \
			IO_WritePass(probe, long_line, 10000), \
			IO_WritePass(probe, long_line, 10000))
		var/long_us = MeasureTU("io.file_write_long", "io", "file << 1000-char line",
			ldt, 10000, 1, "median of 3 passes")

		// The syscall dominates, not the payload. Batching lines into one
		// write is therefore close to free per extra line.
		Assert("io.write_cost_is_per_call_not_per_byte", "io",
			"write cost is dominated by the call, not the payload",
			(long_us < short_us * 2) ? 1 : 0, 1,
			"[round(short_us,2)] us at 10 chars, [round(long_us,2)] us at 1000 chars, 100x the data, medians of 3")

#ifdef BREAKCHECK
		long_us = short_us * 0.5       // long write cheaper than short
#endif
		// The invariant under the claim above: 100x the payload may cost
		// almost nothing extra, but it cannot cost less. A run reading the
		// long write cheaper than the short one is measuring noise, which is
		// what happened in 2 of 9 runs before 8.11 raised the reps and took
		// medians per arm. 0.9, against a measured 1.10 to 1.13 across six
		// runs on two builds; both arms are timed adjacently, so the ratio
		// cancels the drift that moves each of them.
		Assert("io.long_write_not_cheaper_than_short", "io",
			"a 1000-char write does not cost less than a 10-char one",
			(long_us > short_us * 0.9) ? 1 : 0, 1,
			"short [round(short_us,2)] us, long [round(long_us,2)] us, ratio [round(short_us > 0 ? long_us/short_us : 0, 0.01)]x")

		var/tu2 = world.tick_usage
		for(var/i = 1 to 400000)
			world.log << "short line"
		var/log_us = MeasureTU("io.world_log_short", "io", "world.log << 10-char line",
			world.tick_usage - tu2, 400000, 1, null)

		// 2x, lowered from 10x on 2026-08-02. The claim under test is that
		// stdout logging is materially cheaper than an unbuffered file write,
		// and it holds on both machines: 43x on Windows, 5x on Linux, where a
		// file write is about 19x cheaper to begin with. A 10x threshold
		// encoded one machine's margin as the claim and failed 6 of 6 runs on
		// the other for a reason that has nothing to do with the engine.
		//
		// This ratio moves with how DreamDaemon's stdout is bound, since
		// world.log goes to stdout and the file arm does not: bound to a file
		// it is fully buffered on Linux and slower on Windows. The binding is
		// stamped into every result as stdout_binding rather than assumed, and
		// the measured multiple is published per machine instead of asserted
		// as one number.
		Assert("io.world_log_cheaper_than_file", "io",
			"world.log is materially cheaper than a direct file write",
			(log_us < short_us / 2) ? 1 : 0, 1,
			"world.log [round(log_us,2)] us vs file [round(short_us,2)] us, [round(log_us > 0 ? short_us/log_us : 0, 0.1)]x")

		// --- interpolation is separate from the write ---
		// Rep history, which is the argument for the clock change: 8000 put
		// this row at 14 to 18 deciseconds against a 15 floor and it drew
		// LOW_RESOLUTION in one Windows run; 15000 fixed that here and still
		// read 2 deciseconds on Linux, where the write is 19x cheaper. Chasing
		// a rep count that suits both machines is unwinnable, so the row is
		// timed with tick_usage and the count stays where Windows put it.
		var/interp_writes = 15000
		var/tu3 = world.tick_usage
		for(var/i = 1 to interp_writes)
			probe << "iteration [i] of the run"
		MeasureTU("io.file_write_interpolated", "io", "file << line with one embedded value",
			world.tick_usage - tu3, interp_writes, 1, "includes string building")

		// --- does the framework's own logging perturb the next measurement? ---
		// This is the question that decides whether results.tsv should move to
		// world.log. If a burst of writes shifts a stable reference workload,
		// every row after a row is suspect.
		// Each reference is a median of three; with single readings this flipped
		// because the reference drifted 0.11 to 0.19 us while the post-write
		// arms held. Medianing stabilised the reference at 0.14 to 0.15 across
		// six runs, and the assertion then flipped again anyway: the arms read
		// monotonically lower in measurement order, and that drift alone spent
		// the whole 25% tolerance (VERIFICATION 8.10). So the tolerance now
		// carries a measured drift allowance: a warm-up arm is discarded, two
		// back-to-back reference arms with nothing between them measure what
		// the machine drifts on its own, and the perturbed arms are compared
		// against the adjacent control rather than the section's first reading.
		var/R = 10000000
		IO_RefMedian(R)                  // warm-up, discarded: the first arm reads high
		var/ref_a = IO_RefMedian(R)
		var/ref_ctl = IO_RefMedian(R)    // nothing between these two: pure drift
		var/drift = abs(ref_ctl - ref_a)
		for(var/i = 1 to 500)
			probe << "perturbation probe line [i]"
		var/ref_b = IO_RefMedian(R)
		for(var/i = 1 to 500)
			world.log << "perturbation probe line [i]"
		var/ref_c = IO_RefMedian(R)

		var/tol = ref_ctl * 0.25 + drift
		Assert("io.logging_does_not_perturb", "io",
			"a burst of writes does not shift a following measurement",
			(abs(ref_b - ref_ctl) < tol && abs(ref_c - ref_ctl) < tol) ? 1 : 0, 1,
			"control [round(ref_ctl, 0.001)] us, own drift [round(drift, 0.001)], after 500 file writes [round(ref_b, 0.001)], after 500 world.log [round(ref_c, 0.001)]")

		fdel("io_probe.tmp")
