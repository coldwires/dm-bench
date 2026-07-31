// Perception costs.
//
// The headline claim, that a typed for-loop over view() is an order of
// magnitude cheaper than materialising the list, is backed by an ASSERT that
// both forms produce identical output. Without that assertion the comparison
// is meaningless, because they would be doing different work.

var/global/VACC = 0
var/global/mob/vw_probe

mob/vw_mob
	icon_state = "m"

obj/vw_obj
	icon_state = "o"

obj/vw_blocker
	opacity = 1

proc
	VW_Setup(mobs, objs)
		if(!vw_probe)
			vw_probe = new /mob/vw_mob
			vw_probe.loc = locate(50, 50, 1)
		for(var/i = 1 to mobs)
			var/mob/vw_mob/m = new
			m.loc = locate(50 + rand(-5,5), 50 + rand(-5,5), 1)
		for(var/i = 1 to objs)
			var/obj/vw_obj/o = new
			o.loc = locate(50 + rand(-7,7), 50 + rand(-7,7), 1)

	VW_Build(reps)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			var/list/V = view(7, vw_probe)
			VACC += V.len
		return world.timeofday - t0

	VW_BuildFilter(reps)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			var/list/V = view(7, vw_probe)
			for(var/mob/M in V)
				VACC++
		return world.timeofday - t0

	VW_Inline(reps, r)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			for(var/mob/M in view(r, vw_probe))
				VACC++
		return world.timeofday - t0

	VW_Untyped(reps)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			for(var/atom/A in view(7, vw_probe))
				VACC++
		return world.timeofday - t0

	VW_TwoCached(reps)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			var/list/V = view(7, vw_probe)
			for(var/mob/M in V)
				VACC++
			for(var/obj/O in V)
				VACC++
		return world.timeofday - t0

	VW_TwoInline(reps)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			for(var/mob/M in view(7, vw_probe))
				VACC++
			for(var/obj/O in view(7, vw_probe))
				VACC++
		return world.timeofday - t0

	VW_Range(reps)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			for(var/mob/M in range(7, vw_probe))
				VACC++
		return world.timeofday - t0

	VW_Oview(reps)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			for(var/mob/M in oview(7, vw_probe))
				VACC++
		return world.timeofday - t0

	VW_Viewers(reps)
		VACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			for(var/mob/M in viewers(7, vw_probe))
				VACC++
		return world.timeofday - t0

	Suite_View()
		VW_Setup(40, 400)

		// --- same output, three ways ---
		var/d_build = VW_Build(8000)
		var/atoms = VACC / 8000
		var/d_bf = VW_BuildFilter(8000)
		var/n_bf = VACC / 8000
		var/d_in = VW_Inline(110000, 7)
		var/n_in = VACC / 110000
		var/d_un = VW_Untyped(6000)

		Assert("view.filter_equivalence", "view",
			"cached-then-filtered and inline-typed return identical counts",
			(n_bf == n_in) ? 1 : 0, 1,
			"[n_bf] vs [n_in] mobs; without this the timing comparison is void")

		Measure("view.build_only", "view", "var/list/V = view(7,c)", d_build, 8000, 0, "[atoms] atoms")
		Measure("view.build_then_filter", "view", "cache list, then for(mob in V)", d_bf, 8000, 0, "[n_bf] mobs")
		Measure("view.inline_typed", "view", "for(mob in view(7,c))", d_in, 110000, 0, "[n_in] mobs")
		Measure("view.inline_untyped", "view", "for(atom in view(7,c))", d_un, 6000, 0, "[atoms] atoms")

		// --- two passes ---
		var/d_tc = VW_TwoCached(6000)
		var/n_tc = VACC / 6000
		var/d_ti = VW_TwoInline(14000)
		var/n_ti = VACC / 14000
		Assert("view.twopass_equivalence", "view",
			"cached and re-queried two-pass return identical counts",
			(n_tc == n_ti) ? 1 : 0, 1, "[n_tc] vs [n_ti]")
		Measure("view.twopass_cached", "view", "cache list, two typed loops", d_tc, 6000, 0, null)
		Measure("view.twopass_requery", "view", "call view() twice inline", d_ti, 14000, 0, null)

		// --- family ---
		Measure("view.family_view", "view", "for(mob in view(7,c))", VW_Inline(110000, 7), 60000, 0, null)
		Measure("view.family_oview", "view", "for(mob in oview(7,c))", VW_Oview(110000), 110000, 0, null)
		Measure("view.family_viewers", "view", "for(mob in viewers(7,c))", VW_Viewers(120000), 120000, 0, null)
		Measure("view.family_range", "view", "for(mob in range(7,c))", VW_Range(270000), 270000, 0, null)

		// --- radius ---
		Measure("view.radius_1", "view", "for(mob in view(1,c))", VW_Inline(1600000, 1), 1600000, 0, null)
		Measure("view.radius_3", "view", "for(mob in view(3,c))", VW_Inline(340000, 3), 340000, 0, null)
		Measure("view.radius_5", "view", "for(mob in view(5,c))", VW_Inline(160000, 5), 160000, 0, null)
		Measure("view.radius_7", "view", "for(mob in view(7,c))", VW_Inline(110000, 7), 60000, 0, null)
		Measure("view.radius_10", "view", "for(mob in view(10,c))", VW_Inline(70000, 10), 70000, 0, null)

		// --- does the typed loop actually skip building? ---
		// Add atoms that cannot match. If the list is never materialised, the
		// typed loop should barely move while raw view() climbs steeply.
		var/list/clutter = list()
		var/base_raw = 0
		var/base_typed = 0
		for(var/added in list(0, 1200))
			while(clutter.len < added)
				var/obj/vw_obj/o = new
				o.loc = locate(50 + rand(-7,7), 50 + rand(-7,7), 1)
				clutter += o
			var/dr = VW_Build(10000)
			var/at = VACC / 10000
			var/dtp = VW_Inline(110000, 7)
			var/mo = VACC / 100000
			var/raw_us = dr * 100000 / 10000
			var/typed_us = dtp * 100000 / 110000
			if(added == 0)
				base_raw = raw_us
				base_typed = typed_us
			else
				Assert("view.typed_loop_skips_build", "view",
					"typed loop grows far less than raw view() as clutter rises",
					(raw_us / max(base_raw, 0.01) > 3 * (typed_us / max(base_typed, 0.01))) ? 1 : 0, 1,
					"raw x[round(raw_us/max(base_raw,0.01),0.1)], typed x[round(typed_us/max(base_typed,0.01),0.1)] at [at] atoms, [mo] mobs")
			Measure("view.clutter_[added]_raw", "view", "view(7) build with [added] extra objs", dr, 10000, 0, "[at] atoms")
			Measure("view.clutter_[added]_typed", "view", "typed loop with [added] extra objs", dtp, 110000, 0, "[mo] mobs")
		for(var/obj/vw_obj/o in clutter)
			o.loc = null
		clutter.Cut()

		// --- is view() cost driven by opaque atoms? ---
		var/list/blocks = list()
		var/v_clear = VW_Inline(110000, 7)
		var/seen_clear = VACC / 110000
		while(blocks.len < 200)
			var/obj/vw_blocker/b = new
			b.loc = locate(50 + rand(-7,7), 50 + rand(-7,7), 1)
			blocks += b
		var/v_blocked = VW_Inline(110000, 7)
		var/seen_blocked = VACC / 110000
		var/us_clear = v_clear * 100000 / 60000
		var/us_blocked = v_blocked * 100000 / 60000
		Assert("view.los_cost_is_unconditional", "view",
			"view() cost does not rise with opaque atom count",
			(us_blocked < us_clear * 1.6) ? 1 : 0, 1,
			"[round(us_clear,1)] us clear vs [round(us_blocked,1)] us with 200 opaque")
		Assert("view.occlusion_works", "view",
			"opaque atoms actually occlude", (seen_blocked < seen_clear) ? 1 : 0, 1,
			"[seen_clear] mobs visible, [seen_blocked] with 200 opaque")
		for(var/obj/vw_blocker/b in blocks)
			b.loc = null
		blocks.Cut()
