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

	Suite_IO()
		var/probe = file("io_probe.tmp")

		probe = file("io_probe.tmp")

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

		var/lt0 = world.time
		for(var/i = 1 to 20000)
			world.log << "suite io probe [i]"
		var/lt1 = world.time
		Assert("io.world_log_does_not_yield", "io",
			"world.log write does not yield to the scheduler",
			(lt1 == lt0) ? 1 : 0, 1,
			"world.time [lt0] before, [lt1] after 4000 writes")

		// --- cost per write ---
		var/t0 = world.timeofday
		for(var/i = 1 to 8000)
			probe << "short line"
		var/short_us = Measure("io.file_write_short", "io", "file << 10-char line",
			world.timeofday - t0, 8000, 1, null)

		var/long_line = IO_LongLine()
		var/t1 = world.timeofday
		for(var/i = 1 to 8000)
			probe << long_line
		var/long_us = Measure("io.file_write_long", "io", "file << 1000-char line",
			world.timeofday - t1, 8000, 1, null)

		// Measured: 1000 chars costs ~7% more than 10 chars. The syscall
		// dominates, not the payload. Batching lines into one write is
		// therefore close to free per extra line.
		Assert("io.write_cost_is_per_call_not_per_byte", "io",
			"write cost is dominated by the call, not the payload",
			(long_us < short_us * 1.5) ? 1 : 0, 1,
			"[round(short_us,2)] us at 10 chars, [round(long_us,2)] us at 1000 chars, 100x the data")

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
		var/t3 = world.timeofday
		for(var/i = 1 to 8000)
			probe << "iteration [i] of the run"
		Measure("io.file_write_interpolated", "io", "file << line with one embedded value",
			world.timeofday - t3, 8000, 1, "includes string building")

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
