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

	Suite_CrossCheck()
		var/R = 3000000

		// arm A: this framework's own timer
		var/t0 = world.timeofday
		for(var/i = 1 to R)
			XV_Cheap()
		var/a_cheap = (world.timeofday - t0) * 100000 / R
		var/t1 = world.timeofday
		for(var/i = 1 to R)
			XV_Medium()
		var/a_med = (world.timeofday - t1) * 100000 / R
		var/t2 = world.timeofday
		for(var/i = 1 to R)
			XV_Heavy()
		var/a_heavy = (world.timeofday - t2) * 100000 / R

		// arm B: world.Profile()
		world.Profile(PROFILE_RESTART)
		for(var/i = 1 to R)
			XV_Cheap()
		for(var/i = 1 to R)
			XV_Medium()
		for(var/i = 1 to R)
			XV_Heavy()
		var/list/prof = world.Profile(PROFILE_REFRESH)
		world.Profile(PROFILE_STOP | PROFILE_CLEAR)

		var/p_cheap = ProfSelf(prof, "XV_Cheap")
		var/p_med = ProfSelf(prof, "XV_Medium")
		var/p_heavy = ProfSelf(prof, "XV_Heavy")

		Value("xcheck.timer_cheap", "xcheck", "XV_Cheap by this framework", round(a_cheap, 0.001), "us", null)
		Value("xcheck.timer_medium", "xcheck", "XV_Medium by this framework", round(a_med, 0.001), "us", null)
		Value("xcheck.timer_heavy", "xcheck", "XV_Heavy by this framework", round(a_heavy, 0.001), "us", null)
		Value("xcheck.profiler_cheap", "xcheck", "XV_Cheap self time by world.Profile", p_cheap, "s-total", null)
		Value("xcheck.profiler_medium", "xcheck", "XV_Medium self time by world.Profile", p_med, "s-total", null)
		Value("xcheck.profiler_heavy", "xcheck", "XV_Heavy self time by world.Profile", p_heavy, "s-total", null)

		Assert("xcheck.profiler_found_our_procs", "xcheck",
			"world.Profile reported the procs we called",
			(p_cheap >= 0 && p_med >= 0 && p_heavy >= 0) ? 1 : 0, 1,
			"cheap=[p_cheap] medium=[p_med] heavy=[p_heavy]")

		// Absolute values cannot match: the profiler inflates calls ~3.5x.
		// Ratios between procs should agree if both instruments are sound.
		if(p_cheap > 0 && a_cheap > 0)
			var/ratio_timer = a_heavy / a_cheap
			var/ratio_prof = p_heavy / p_cheap
			Value("xcheck.ratio_timer", "xcheck", "heavy/cheap by this framework", round(ratio_timer, 0.01), "x", null)
			Value("xcheck.ratio_profiler", "xcheck", "heavy/cheap by world.Profile", round(ratio_prof, 0.01), "x", null)
			Assert("xcheck.instruments_agree_on_ratio", "xcheck",
				"both instruments agree on the ratio between procs",
				(abs(ratio_timer - ratio_prof) < ratio_timer * 0.5) ? 1 : 0, 1,
				"framework [round(ratio_timer,0.01)]x, profiler [round(ratio_prof,0.01)]x")

	Suite_CallsDeep()
		var/R = 15000000

		// --- user-defined procs, by argument count ---
		var/t0 = world.timeofday
		for(var/i = 1 to R)
			UserNoop0()
		var/u0 = Measure("calls.user_0args", "calls", "user proc, 0 args", world.timeofday - t0, R, 1, null)

		var/t1 = world.timeofday
		for(var/i = 1 to R)
			UserNoop1(1)
		var/u1 = Measure("calls.user_1arg", "calls", "user proc, 1 arg", world.timeofday - t1, R, 1, null)

		var/t2 = world.timeofday
		for(var/i = 1 to R)
			UserNoop4(1, 2, 3, 4)
		var/u4 = Measure("calls.user_4args", "calls", "user proc, 4 args", world.timeofday - t2, R, 1, null)

		var/t3 = world.timeofday
		for(var/i = 1 to R)
			UserNoop8(1, 2, 3, 4, 5, 6, 7, 8)
		var/u8 = Measure("calls.user_8args", "calls", "user proc, 8 args", world.timeofday - t3, R, 1, null)

		Assert("calls.args_are_copied", "calls",
			"call cost rises with argument count",
			(u8 > u0 * 1.15) ? 1 : 0, 1,
			"0 args [round(u0,0.001)] us, 8 args [round(u8,0.001)] us")

		// --- hard-called builtins ---
		DACC = 0
		var/t4 = world.timeofday
		for(var/i = 1 to R)
			DACC += abs(-5)
		var/h1 = Measure("calls.builtin_abs", "calls", "abs(x), hard builtin", world.timeofday - t4, R, 1, null)

		DACC = 0
		var/t5 = world.timeofday
		for(var/i = 1 to R)
			DACC += max(3, 7)
		var/h2 = Measure("calls.builtin_max", "calls", "max(a,b), hard builtin", world.timeofday - t5, R, 1, null)

		Assert("calls.hard_builtin_cheaper_than_user", "calls",
			"a hard-called builtin costs less than a user-defined proc",
			(h1 < u1) ? 1 : 0, 1,
			"abs() [round(h1,0.001)] us vs 1-arg user proc [round(u1,0.001)] us")

		// --- soft-called builtin: vector.Dot() ---
		var/vector/va = vector(3, 4)
		var/vector/vb = vector(1, 2)
		DACC = 0
		var/t6 = world.timeofday
		for(var/i = 1 to R)
			DACC += va.Dot(vb)
		var/sd = Measure("calls.builtin_vector_dot", "calls", "vector.Dot(), soft-called builtin", world.timeofday - t6, R, 1, null)

		Assert("calls.soft_builtin_above_hard", "calls",
			"a soft-called builtin costs more than a hard-called one",
			(sd > h1) ? 1 : 0, 1,
			"Dot() [round(sd,0.001)] us vs abs() [round(h1,0.001)] us, user proc [round(u1,0.001)] us")

		Value("calls.hard_vs_user_ratio", "calls", "user proc cost divided by hard builtin cost",
			round(u1 / max(h1, 0.001), 0.01), "x", null)

	// ---- is world.Profile() safe to leave on? ----

	Suite_Profiler()
		var/R = 10000000

		DACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to R)
			UserNoop1(i)
		var/off = (world.timeofday - t0) * 100000 / R

		world.Profile(PROFILE_RESTART)
		var/t1 = world.timeofday
		for(var/i = 1 to R)
			UserNoop1(i)
		var/on = (world.timeofday - t1) * 100000 / R
		world.Profile(PROFILE_STOP)

		var/t2 = world.timeofday
		for(var/i = 1 to R)
			UserNoop1(i)
		var/after = (world.timeofday - t2) * 100000 / R

		Value("profiler.call_cost_off", "profiler", "user proc call, profiler off", round(off, 0.001), "us", null)
		Value("profiler.call_cost_on", "profiler", "user proc call, profiler on", round(on, 0.001), "us", null)
		Value("profiler.call_cost_after", "profiler", "user proc call, profiler stopped again", round(after, 0.001), "us", null)
		Value("profiler.overhead_multiple", "profiler", "profiled cost divided by unprofiled",
			round(on / max(off, 0.001), 0.01), "x", null)

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
