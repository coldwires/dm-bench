// del() cost.
//
// THIS MUST RUN IN ITS OWN PROCESS. del() cost is driven by live object count,
// and peak concurrent population leaves a permanent residual that never decays.
// Running any large-population test before this one inflates every reading here
// by an order of magnitude. That mistake produced a published 155 us floor where
// the true clean baseline is 10 us.
//
// Ordering within this file also matters: the clean-world measurements run
// before anything grows the population.

var/global/list/DEL_BALLAST = list()

obj/del_obj

proc
	// build nrefs heap references, then delete the victim.
	//
	// Timed with world.tick_usage, not world.timeofday. Every figure in this
	// file is a DIFFERENCE between two arms, and at 0.1s resolution that
	// difference was 1 to 4 quanta wide, so the reported values could only ever
	// land on multiples of 100000/reps. Three assertions here flipped at random
	// across four runs of 516.1666 on one machine because of it.
	DelArm(reps, nrefs)
		var/tu0 = world.tick_usage
		for(var/r = 1 to reps)
			var/obj/del_obj/e = new
			var/list/H = new(nrefs)
			for(var/i = 1 to nrefs) H[i] = e
			del(e)
		return world.tick_usage - tu0

	// identical build, dropped instead of deleted. live count stays at zero,
	// so this is a control rather than a population-growing baseline.
	//
	// THE CONTRACT, for any reviewer of this pair: both arms must end each
	// iteration with the victim destroyed and every reference gone, because
	// the published figure compares two COMPLETE ways of achieving deletion.
	// H = null is not optional: without it the list would keep the victim
	// alive past e = null (deletion never happens) and 20k survivors per
	// call would grow the live population mid-suite. One asymmetry is
	// intended and stays: this arm frees H while its slots are live (paying
	// a refcount decrement per slot), the del arm frees H after del()
	// already nulled the slots. Each path pays its own true bookkeeping;
	// that is the design-alternative comparison the spec publishes. An
	// asymmetry OTHER than that one is a bug.
	DropArm(reps, nrefs)
		var/tu0 = world.tick_usage
		for(var/r = 1 to reps)
			var/obj/del_obj/e = new
			var/list/H = new(nrefs)
			for(var/i = 1 to nrefs) H[i] = e
			H = null
			e = null
		return world.tick_usage - tu0

	// Returns list(net_us, hi_pct, lo_pct). The arms travel with the result so
	// the emitter can judge whether the difference was resolvable at all.
	DelOnce(reps, nrefs)
		var/hi = DelArm(reps, nrefs)
		var/lo = DropArm(reps, nrefs)
		return list((hi - lo) * US_PER_PCT / reps, hi, lo)

	// Median of three. Once the clock stopped being the limit, the remaining
	// spread was genuine variance in del() itself: at 256 refs the delete arm
	// ranged 1962 to 2450 pct across runs while its control held at 1425 to
	// 1508. A single reading of that case swung 2x, which is enough to flip an
	// assertion. Median, not mean, so one slow run cannot drag the figure.
	//
	// Safe to repeat: both arms return live count to zero, and the residual is
	// driven by PEAK concurrent population, which repetition does not change.
	DelNet(reps, nrefs)
		var/list/a = DelOnce(reps, nrefs)
		var/list/b = DelOnce(reps, nrefs)
		var/list/c = DelOnce(reps, nrefs)
		if((a[1] <= b[1] && b[1] <= c[1]) || (c[1] <= b[1] && b[1] <= a[1])) return b
		if((b[1] <= a[1] && a[1] <= c[1]) || (c[1] <= a[1] && a[1] <= b[1])) return a
		return c

	// The victim's ONLY heap reference is the list slot the del expression
	// indexes through. VERIFICATION 12: this reads like the zero-ref case at
	// any population, because the scan runs only for references del cannot
	// account for from the deletion site.
	DelIndexArm(reps)
		var/tu0 = world.tick_usage
		for(var/r = 1 to reps)
			var/list/H = new(1)
			H[1] = new /obj/del_obj
			del(H[1])
		return world.tick_usage - tu0

	DelIndexDrop(reps)
		var/tu0 = world.tick_usage
		for(var/r = 1 to reps)
			var/list/H = new(1)
			H[1] = new /obj/del_obj
			H = null
		return world.tick_usage - tu0

	Churn(n)
		for(var/i = 1 to n)
			var/obj/del_obj/e = new
			e = null

	Grow(n)
		for(var/i = 1 to n)
			DEL_BALLAST += new /obj/del_obj

	Suite_Del()
		// --- clean world, cost by reference count ---
		var/list/z = DelNet(60000, 0)
		var/list/o = DelNet(60000, 1)
		var/list/m = DelNet(20000, 256)
		var/zero = z[1]
		var/one = o[1]
		var/many = m[1]

		// The denominator, published for the first time on 2026-08-03.
		//
		// Every del figure on the page is a difference, DelArm minus DropArm,
		// and the drop side was measured all along without ever being printed.
		// That left the most quoted claim this project ever made, del() against
		// dropping the last reference, with a numerator and no denominator, so
		// the ratio could not honestly be stated at all.
		//
		// NEITHER ARM IS TOUCHED. DelOnce already returns both, and this reads
		// the value it returns. That matters because the DelArm/DropArm pair is
		// the one artifact here that has passed external cold review, and the
		// contract above DropArm says changing either arm re-opens it. Reading
		// a number that was already being computed does not.
		//
		// Name it for what the arm actually does, which is NOT "thing = null"
		// on its own: the loop allocates an object, builds a list of nrefs
		// references to it, then drops both. Allocation is unavoidable, since
		// there is nothing to drop without it. Published as the whole control,
		// so the ratio it anchors is a ratio between two things that were both
		// measured rather than between one measurement and a remembered figure.
		MeasureTU("del.drop_control_1ref", "del",
			"allocate, build 1 heap ref, drop both, no del()",
			o[3], 60000, 0, "the control arm every del row subtracts")

		Assert("del.zero_refs_is_free", "del",
			"del() is free when only a local points at the victim",
			(zero < 2) ? 1 : 0, 1, "[round(zero, 0.01)] us")
		Assert("del.one_ref_costs", "del",
			"a single heap reference makes del() cost real time",
			(one > 3) ? 1 : 0, 1, "[round(one, 0.01)] us")
		// 3x, not 1.5x. The 256-ref delete arm is the highest-variance
		// quantity in this file (documented in INSTRUMENTS.md; net values
		// ranged 9.6 to 18.2 us across six runs on 2026-08-01), and per-run
		// ratios reached 1.66 from noise alone, flipping the old 1.5x
		// threshold once. The claim being tested is flat-versus-scaling:
		// O(refs) would read near 256x, flat reads near 1.3x, so 3x
		// separates them with headroom instead of sitting in the noise tail.
		Assert("del.refcount_does_not_scale", "del",
			"256 references cost far less than 256x one",
			(many <= one * 3) ? 1 : 0, 1,
			"1 ref [round(one,0.01)] us, 256 refs [round(many,0.01)] us")

		MeasureDelta("del.refs_0", "del", "del cost, 0 heap refs", z[2], z[3], 60000, null)
		MeasureDelta("del.refs_1", "del", "del cost, 1 heap ref", o[2], o[3], 60000, null)
		MeasureDelta("del.refs_256", "del", "del cost, 256 heap refs", m[2], m[3], 20000, null)

		// --- a reference del can account for from the deletion site ---
		// del(H[1]) where the indexed slot is the victim's only heap ref.
		// Reads like refs_0, not refs_1: the expensive scan is the hunt for
		// UNACCOUNTED references, and this one is in del's hand already. Its
		// delta is small by design, so the row carries the same resolution
		// flags refs_0 does; the assertion is what matters. A build that
		// starts scanning here anyway flips this to FAIL.
		var/ihi = DelIndexArm(60000)
		var/ilo = DelIndexDrop(60000)
		var/via_index = (ihi - ilo) * US_PER_PCT / 60000
		Assert("del.accounted_ref_is_free", "del",
			"del through the ref's own list slot skips the scan",
			(via_index < 2) ? 1 : 0, 1,
			"[round(via_index, 0.01)] us via del(H\[1\]) vs [round(one, 0.01)] us with an unaccounted ref")
		MeasureDelta("del.ref_via_index", "del", "del cost, sole ref indexed by the del expression", ihi, ilo, 60000, null)

		// --- turfs are not counted ---
		var/list/sm = DelNet(40000, 1)
		var/small = sm[1]
		world.maxx = 220
		world.maxy = 220
		sleep(2)
		var/list/bg = DelNet(40000, 1)
		var/big = bg[1]
		MeasureDelta("del.turfs_10k", "del", "del cost at 10k turfs", sm[2], sm[3], 40000, null)
		MeasureDelta("del.turfs_48k", "del", "del cost at 48k turfs", bg[2], bg[3], 40000, null)
		Assert("del.turfs_not_counted", "del",
			"map size does not affect del() cost",
			(big < small * 1.6) ? 1 : 0, 1,
			"[round(small,0.01)] us at 10k turfs, [round(big,0.01)] us at 48k turfs")
		world.maxx = 100
		world.maxy = 100
		sleep(2)

		// --- cumulative allocation does not matter ---
		var/list/bc = DelNet(40000, 1)
		var/before_churn = bc[1]
		Churn(500000)
		var/list/ac = DelNet(40000, 1)
		var/after_churn = ac[1]
		MeasureDelta("del.before_churn", "del", "del cost before 500k churn", bc[2], bc[3], 40000, null)
		MeasureDelta("del.after_churn", "del", "del cost after 500k churn", ac[2], ac[3], 40000, null)
		Assert("del.cumulative_alloc_irrelevant", "del",
			"allocating and freeing 500k objects does not change del() cost",
			(after_churn < before_churn * 1.6) ? 1 : 0, 1,
			"[round(before_churn,0.01)] us before, [round(after_churn,0.01)] us after")

		// --- live population is what drives it ---
		var/list/cd = DelNet(40000, 1)
		var/cold = cd[1]
		MeasureDelta("del.live_0", "del", "del cost at 0 live objs", cd[2], cd[3], 40000, null)
		// 300k added 2026-08-01: the published population table and the 3,300x
		// headline rest on a 300k figure from a harness that is not in this
		// tree. This sweep now reaches it, so the table regenerates from here.
		// Kept per population so the sweep's ordering can be asserted. These
		// rows are the most ambient-sensitive in the project, 30 to 65% spread
		// across same-morning triples (item 13), which is exactly why the
		// invariant is asserted as an ordering rather than as coefficients.
		var/list/live_us = list()
		for(var/target in list(50000, 100000, 200000, 300000))
			while(DEL_BALLAST.len < target)
				Grow(10000)
			var/reps = (target >= 300000) ? 1000 : ((target >= 200000) ? 1500 : 6000)
			var/list/lv = DelNet(reps, 1)
			var/cost = lv[1]
			live_us["[target]"] = cost
			MeasureDelta("del.live_[target]", "del", "del cost at [target] live objs", lv[2], lv[3], reps, null)
			if(target == 200000)
				Assert("del.live_count_drives_cost", "del",
					"del() cost rises sharply with live object count",
					(cost > cold * 20) ? 1 : 0, 1,
					"[round(cold,0.01)] us cold vs [round(cost,0.01)] us at 200k live")

#ifdef BREAKCHECK
		live_us["300000"] = live_us["200000"] / 2   // cost falling with population
#endif
		Assert("del.population_sweep_monotonic", "del",
			"del() cost rises at every step of the population sweep",
			(cold < live_us["50000"] && live_us["50000"] < live_us["100000"] \
				&& live_us["100000"] < live_us["200000"] \
				&& live_us["200000"] < live_us["300000"]) ? 1 : 0, 1,
			"0:[round(cold,0.01)] 50k:[round(live_us["50000"],0.01)] 100k:[round(live_us["100000"],0.01)] 200k:[round(live_us["200000"],0.01)] 300k:[round(live_us["300000"],0.01)] us")

		// --- peak population leaves a permanent residual ---
		DEL_BALLAST.Cut()
		sleep(10)
		var/list/af = DelNet(20000, 1)
		var/after_free = af[1]
		Assert("del.peak_leaves_residual", "del",
			"freeing the population does not restore the cold cost",
			(after_free > cold * 3) ? 1 : 0, 1,
			"[round(cold,0.01)] us cold, [round(after_free,0.01)] us after 300k existed and were freed")
		MeasureDelta("del.residual_after_peak", "del", "del cost after peak population freed", af[2], af[3], 20000, null)
