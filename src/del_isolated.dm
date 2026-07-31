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

		Assert("del.zero_refs_is_free", "del",
			"del() is free when only a local points at the victim",
			(zero < 2) ? 1 : 0, 1, "[round(zero, 0.01)] us")
		Assert("del.one_ref_costs", "del",
			"a single heap reference makes del() cost real time",
			(one > 3) ? 1 : 0, 1, "[round(one, 0.01)] us")
		Assert("del.refcount_does_not_scale", "del",
			"256 references cost no more than 1",
			(many <= one * 1.5) ? 1 : 0, 1,
			"1 ref [round(one,0.01)] us, 256 refs [round(many,0.01)] us")

		MeasureDelta("del.refs_0", "del", "del cost, 0 heap refs", z[2], z[3], 60000, null)
		MeasureDelta("del.refs_1", "del", "del cost, 1 heap ref", o[2], o[3], 60000, null)
		MeasureDelta("del.refs_256", "del", "del cost, 256 heap refs", m[2], m[3], 20000, null)

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
		for(var/target in list(50000, 100000, 200000))
			while(DEL_BALLAST.len < target)
				Grow(10000)
			var/reps = (target >= 200000) ? 1500 : 6000
			var/list/lv = DelNet(reps, 1)
			var/cost = lv[1]
			MeasureDelta("del.live_[target]", "del", "del cost at [target] live objs", lv[2], lv[3], reps, null)
			if(target == 200000)
				Assert("del.live_count_drives_cost", "del",
					"del() cost rises sharply with live object count",
					(cost > cold * 20) ? 1 : 0, 1,
					"[round(cold,0.01)] us cold vs [round(cost,0.01)] us at 200k live")

		// --- peak population leaves a permanent residual ---
		DEL_BALLAST.Cut()
		sleep(10)
		var/list/af = DelNet(20000, 1)
		var/after_free = af[1]
		Assert("del.peak_leaves_residual", "del",
			"freeing the population does not restore the cold cost",
			(after_free > cold * 3) ? 1 : 0, 1,
			"[round(cold,0.01)] us cold, [round(after_free,0.01)] us after 200k existed and were freed")
		MeasureDelta("del.residual_after_peak", "del", "del cost after peak population freed", af[2], af[3], 20000, null)
