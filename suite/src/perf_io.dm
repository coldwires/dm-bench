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
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			IOACC += i % 7
		return world.timeofday - t0

	// Median of three passes, in us per iteration. A single pass of this
	// reference is not stable enough to compare against.
	IO_RefMedian(reps)
		var/a = IO_Reference(reps)
		var/b = IO_Reference(reps)
		var/c = IO_Reference(reps)
		return Median3(a, b, c) * 100000 / reps

	// One timed pass of `reps` writes of `line` to `f`, in deciseconds.
	IO_WritePass(f, line, reps)
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			f << line
		return world.timeofday - t0

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
		var/short_us = Measure("io.file_write_short", "io", "file << 10-char line",
			sdt, 10000, 1, "median of 3 passes")

		var/long_line = IO_LongLine()
		var/ldt = Median3(IO_WritePass(probe, long_line, 10000), \
			IO_WritePass(probe, long_line, 10000), \
			IO_WritePass(probe, long_line, 10000))
		var/long_us = Measure("io.file_write_long", "io", "file << 1000-char line",
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

		var/t2 = world.timeofday
		for(var/i = 1 to 400000)
			world.log << "short line"
		var/log_us = Measure("io.world_log_short", "io", "world.log << 10-char line",
			world.timeofday - t2, 400000, 1, null)

		Assert("io.world_log_far_cheaper_than_file", "io",
			"world.log is dramatically cheaper than a direct file write",
			(log_us < short_us / 10) ? 1 : 0, 1,
			"world.log [round(log_us,2)] us vs file [round(short_us,2)] us")

		// --- interpolation is separate from the write ---
		// 15000, raised from 8000 on 2026-08-01. This row is the cheapest of the
		// three file-write arms, about 175 us against 210 for the short line, so
		// 8000 writes put it at 14 to 18 deciseconds against a 15 floor. It drew
		// LOW_RESOLUTION in one run of a triple, which withholds it from the spec
		// sheet and the site, and it is the last row in this suite sitting on the
		// guard. 15000 puts it near 26.
		var/interp_writes = 15000
		var/t3 = world.timeofday
		for(var/i = 1 to interp_writes)
			probe << "iteration [i] of the run"
		Measure("io.file_write_interpolated", "io", "file << line with one embedded value",
			world.timeofday - t3, interp_writes, 1, "includes string building")

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
