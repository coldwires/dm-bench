// Call overhead by kind, and whether world.Profile() can be trusted.
//
// Claim under test, from Lummox JR (BYOND author):
//   "default hard procs have a smidge less overhead than regular procs because
//    they're not running user code, so they don't spin up Proc and ProcData
//    structs. They do however copy args."
//
// Two testable predictions:
//   1. A hard-called builtin costs less per call than a user-defined proc.
//   2. Cost rises with argument count, for both kinds, because args are copied.
//
// Also tested: vector.Dot() is built in but described as "still a soft call",
// so it should land nearer the user-proc cost than the hard-builtin cost.

var/global/DACC = 0

proc
	UserNoop0()
		return
	UserNoop1(a)
		return
	UserNoop4(a, b, c, d)
		return
	UserNoop8(a, b, c, d, e, f, g, h)
		return

	// deliberately different costs, for cross-instrument comparison
	XV_Cheap()
		return
	XV_Medium()
		DACC += 7 % 3
		return
	XV_Heavy()
		DACC += length(num2text(12345))
		return

	// profiler rows are 6 columns each, after 6 header names
	ProfSelf(list/prof, pname)
		if(!islist(prof)) return -1
		for(var/i = 7 to prof.len step 6)
			if(findtext("[prof[i]]", pname))
				return prof[i+1]
		return -1

	// Cross-validates this framework's timer against world.Profile().
	//
	// Rewritten 2026-07-31. The previous version failed all three runs of one
	// build and had been passing by luck before that. Three separate defects:
	//
	// 1. R was 3,000,000 for every proc, so XV_Cheap measured 5 to 7 quanta.
	//    Across nine runs it took exactly three values: 0.167, 0.200, 0.233,
	//    each one quantum apart. Rep counts are now sized per proc.
	//
	// 2. The rows went through Value(), which applies no resolution guard, so
	//    none of that was flagged. They now go through Measure().
	//
	// 3. The two instruments were being asked to agree on quantities that are
	//    not the same. Our timer measures loop + call + work. Profiler self time
	//    measures only inside the proc. That shared loop overhead sits in both
	//    numerator and denominator and COMPRESSES our ratio toward 1, which is
	//    exactly what was seen: 5.5x against the profiler's 9x. Subtracting an
	//    empty-call baseline puts both on "work beyond call overhead".
	//
	// The tolerance was also anchored to the smaller value, so the test grew
	// stricter as noise pushed that value down. It is now relative to the larger.
	Suite_CrossCheck()
		// sized so each block clears MIN_DS at its own per-call cost
		var/R_cheap = 10000000
		var/R_med = 9000000
		var/R_heavy = 2000000

		// XV_Cheap is an empty proc, so it IS each instrument's zero point:
		// loop plus call for our timer, profiler overhead for world.Profile.
		// Subtracting it from the other two puts both instruments on "work
		// beyond an empty call", which is the only basis on which their ratios
		// can be expected to agree.
		var/t0 = world.timeofday
		for(var/i = 1 to R_cheap)
			XV_Cheap()
		var/a_cheap = Measure("xcheck.timer_cheap", "xcheck", "XV_Cheap, an empty proc", world.timeofday - t0, R_cheap, 0, "the timer's zero point")

		var/t1 = world.timeofday
		for(var/i = 1 to R_med)
			XV_Medium()
		var/a_med = Measure("xcheck.timer_medium", "xcheck", "XV_Medium by this framework", world.timeofday - t1, R_med, 0, null)

		var/t2 = world.timeofday
		for(var/i = 1 to R_heavy)
			XV_Heavy()
		var/a_heavy = Measure("xcheck.timer_heavy", "xcheck", "XV_Heavy by this framework", world.timeofday - t2, R_heavy, 0, null)

		// arm B: world.Profile(). Self time is a total, so normalise by the call
		// count, which differs per proc now.
		world.Profile(PROFILE_RESTART)
		for(var/i = 1 to R_cheap)
			XV_Cheap()
		for(var/i = 1 to R_med)
			XV_Medium()
		for(var/i = 1 to R_heavy)
			XV_Heavy()
		var/list/prof = world.Profile(PROFILE_REFRESH)
		world.Profile(PROFILE_STOP | PROFILE_CLEAR)

		var/p_cheap = ProfSelf(prof, "XV_Cheap")
		var/p_med = ProfSelf(prof, "XV_Medium")
		var/p_heavy = ProfSelf(prof, "XV_Heavy")

		Extern("xcheck.profiler_cheap", "xcheck", "XV_Cheap self time", p_cheap, "s-total", "world.Profile()", "call count [R_cheap]")
		Extern("xcheck.profiler_medium", "xcheck", "XV_Medium self time", p_med, "s-total", "world.Profile()", "call count [R_med]")
		Extern("xcheck.profiler_heavy", "xcheck", "XV_Heavy self time", p_heavy, "s-total", "world.Profile()", "call count [R_heavy]")

		Assert("xcheck.profiler_found_our_procs", "xcheck",
			"world.Profile reported the procs we called",
			(p_cheap >= 0 && p_med >= 0 && p_heavy >= 0) ? 1 : 0, 1,
			"cheap=[p_cheap] medium=[p_med] heavy=[p_heavy]")

		// Ordering is the robust cross-check. It needs no matching zero point and
		// no tolerance, and it is what actually catches an instrument that has
		// gone wrong.
		var/pc = (p_cheap > 0) ? (p_cheap / R_cheap) : 0
		var/pm = (p_med > 0) ? (p_med / R_med) : 0
		var/ph = (p_heavy > 0) ? (p_heavy / R_heavy) : 0
		Assert("xcheck.instruments_agree_on_order", "xcheck",
			"both instruments rank the three procs the same way",
			((a_cheap < a_med && a_med < a_heavy) && (pc < pm && pm < ph)) ? 1 : 0, 1,
			"timer [round(a_cheap,0.001)]/[round(a_med,0.001)]/[round(a_heavy,0.001)] us, profiler per call [round(pc,0.000001)]/[round(pm,0.000001)]/[round(ph,0.000001)]")

		// Ratio agreement, on work beyond an empty call so both instruments share
		// a zero point. heavy/medium, not heavy/cheap: cheap is the zero point
		// itself, so heavy/cheap would divide by each instrument's own overhead
		// and the two could never agree. That was the old assertion's third
		// defect, and it is why our ratio read 5.5x against the profiler's 9x.
		var/net_med = a_med - a_cheap
		var/net_heavy = a_heavy - a_cheap
		var/pnet_med = pm - pc
		var/pnet_heavy = ph - pc
		if(net_med > 0 && pnet_med > 0)
			var/ratio_timer = net_heavy / net_med
			var/ratio_prof = pnet_heavy / pnet_med
			Derived("xcheck.ratio_timer", "xcheck", "heavy/medium work by this framework", round(ratio_timer, 0.01), "x",
				"(timer_heavy - timer_cheap) / (timer_medium - timer_cheap)")
			Derived("xcheck.ratio_profiler", "xcheck", "heavy/medium work by world.Profile", round(ratio_prof, 0.01), "x",
				"profiler self times per call, cheap subtracted")
			// NO assertion on these two. Reported for inspection only.
			//
			// This assertion has now failed in three different forms and it was
			// never sound in any of them:
			//
			//   heavy/cheap, tolerance on the smaller value  -> passed by luck,
			//     then failed 3/3 once the values drifted down
			//   heavy/cheap, tolerance on the larger value   -> still comparing
			//     quantities with different zero points
			//   heavy/medium with cheap subtracted           -> denominator is
			//     0.22 minus 0.16, a tiny difference of two noisy numbers.
			//     Spreads went to 66% and 63%, worse than either predecessor.
			//
			// The last attempt reintroduced the subtraction problem this whole
			// framework exists to avoid, in the denominator of a ratio. The
			// procs are too close in cost for their difference to be measurable.
			//
			// Ordering is the cross-check that works. It needs no tolerance, no
			// shared zero point and no subtraction, and it is what actually
			// catches an instrument that has gone wrong. Restoring a ratio
			// assertion requires XV_Medium and XV_Heavy to be far enough apart
			// that their difference is not itself a noise measurement.

	Suite_CallsDeep()
		// 20M rather than 15M: the discarded-unroll conversion dropped the
		// accumulator, and the cheapest blocks (abs, max) would sit at the
		// MIN_DS edge at 15M. Loop runs R/UNROLL = 2M times, inside 2^24.
		var/R = 20000000

		// --- user-defined procs, by argument count ---
		// Unrolled, results discarded. Calls are emitted when discarded, so
		// no pragma; the pure builtins below need one.
		var/t0 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(UserNoop0())
		var/u0 = MeasureU("calls.user_0args", "calls", "user proc, 0 args", world.timeofday - t0, R, UNROLL, null)

		var/t1 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(UserNoop1(1))
		var/u1 = MeasureU("calls.user_1arg", "calls", "user proc, 1 arg", world.timeofday - t1, R, UNROLL, null)

		var/t2 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(UserNoop4(1, 2, 3, 4))
		var/u4 = MeasureU("calls.user_4args", "calls", "user proc, 4 args", world.timeofday - t2, R, UNROLL, null)

		var/t3 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(UserNoop8(1, 2, 3, 4, 5, 6, 7, 8))
		var/u8 = MeasureU("calls.user_8args", "calls", "user proc, 8 args", world.timeofday - t3, R, UNROLL, null)

		Assert("calls.args_are_copied", "calls",
			"call cost rises with argument count",
			(u8 > u0 * 1.15) ? 1 : 0, 1,
			"0 args [round(u0,0.001)] us, 8 args [round(u8,0.001)] us")

		// --- hard-called builtins ---
		// Discarded pure builtins draw no_effect and are emitted anyway,
		// abs at ~6 bytes per copy and max at ~14, verified by differential
		// compilation (INSTRUMENTS.md).
		//
		// Their own reps counts, sized by the resolution guard across two
		// rounds: 20M read LOW_RESOLUTION for both in 6/6 runs, and 40M
		// still did for abs, which measures about 0.02 us discarded. The
		// old accumulator-form figure near 0.1 us was mostly harness; the
		// operation itself is nearly free, so it needs 120M operations
		// (12M loops, inside 2^24) to fill 15 deciseconds.
		var/RB = 40000000
		var/RA = 120000000
		#pragma push
		#pragma ignore no_effect
		var/t4 = world.timeofday
		for(var/i = 1 to RA / UNROLL)
			X10(abs(-5))
		var/h1 = MeasureU("calls.builtin_abs", "calls", "abs(x), hard builtin", world.timeofday - t4, RA, UNROLL, null)

		var/t5 = world.timeofday
		for(var/i = 1 to RB / UNROLL)
			X10(max(3, 7))
		var/h2 = MeasureU("calls.builtin_max", "calls", "max(a,b), hard builtin", world.timeofday - t5, RB, UNROLL, null)
		#pragma pop

		Assert("calls.hard_builtin_cheaper_than_user", "calls",
			"a hard-called builtin costs less than a user-defined proc",
			(h1 < u1) ? 1 : 0, 1,
			"abs() [round(h1,0.001)] us vs 1-arg user proc [round(u1,0.001)] us")

		// --- soft-called builtin: vector.Dot() ---
		var/vector/va = vector(3, 4)
		var/vector/vb = vector(1, 2)
		var/t6 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(va.Dot(vb))
		var/sd = MeasureU("calls.builtin_vector_dot", "calls", "vector.Dot(), soft-called builtin", world.timeofday - t6, R, UNROLL, null)

		Assert("calls.soft_builtin_above_hard", "calls",
			"a soft-called builtin costs more than a hard-called one",
			(sd > h1) ? 1 : 0, 1,
			"Dot() [round(sd,0.001)] us vs abs() [round(h1,0.001)] us, user proc [round(u1,0.001)] us")

		Derived("calls.hard_vs_user_ratio", "calls", "user proc cost divided by hard builtin cost",
			round(u1 / max(h1, 0.001), 0.01), "x", "calls.user_1arg / calls.builtin_abs")

	// ---- is world.Profile() safe to leave on? ----

	Suite_Profiler()
		var/R = 10000000

		DACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to R)
			UserNoop1(i)
		var/dt_off = world.timeofday - t0
		var/off = dt_off * 100000 / R

		world.Profile(PROFILE_RESTART)
		var/t1 = world.timeofday
		for(var/i = 1 to R)
			UserNoop1(i)
		var/dt_on = world.timeofday - t1
		var/on = dt_on * 100000 / R
		world.Profile(PROFILE_STOP)

		var/t2 = world.timeofday
		for(var/i = 1 to R)
			UserNoop1(i)
		var/dt_after = world.timeofday - t2
		var/after = dt_after * 100000 / R

		// These are our own timings and must carry the resolution guards. They
		// were on Value() and therefore unguarded, like the xcheck rows.
		Measure("profiler.call_cost_off", "profiler", "user proc call, profiler off", dt_off, R, 0, null)
		Measure("profiler.call_cost_on", "profiler", "user proc call, profiler on", dt_on, R, 0, null)
		Measure("profiler.call_cost_after", "profiler", "user proc call, profiler stopped again", dt_after, R, 0, null)
		Derived("profiler.overhead_multiple", "profiler", "profiled cost divided by unprofiled",
			round(on / max(off, 0.001), 0.01), "x", "profiler.call_cost_on / profiler.call_cost_off")

		Assert("profiler.perturbs_measurements", "profiler",
			"enabling the profiler measurably changes call cost",
			(on > off * 1.2) ? 1 : 0, 1,
			"off [round(off,0.001)] us, on [round(on,0.001)] us, off again [round(after,0.001)] us")

		Assert("profiler.overhead_is_reversible", "profiler",
			"stopping the profiler restores the original cost",
			(abs(after - off) < off * 0.3) ? 1 : 0, 1,
			"[round(off,0.001)] us before, [round(after,0.001)] us after stopping")

		// does it actually return data, and in what shape?
		world.Profile(PROFILE_RESTART)
		for(var/i = 1 to 200000)
			UserNoop1(i)
		var/list/prof = world.Profile(PROFILE_REFRESH)
		world.Profile(PROFILE_STOP | PROFILE_CLEAR)

		Assert("profiler.returns_data", "profiler",
			"Profile() returns a populated list",
			(islist(prof) && prof.len > 6) ? 1 : 0, 1,
			"[islist(prof) ? "[prof.len] entries" : "not a list"]")
		if(islist(prof) && prof.len >= 6)
			Value("profiler.columns", "profiler", "column names",
				"[prof[1]]/[prof[2]]/[prof[3]]/[prof[4]]/[prof[5]]/[prof[6]]", "names", null)
