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
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			var/list/V = view(7, vw_probe)
			VACC += V.len
		return world.tick_usage - tu0

	VW_BuildFilter(reps)
		VACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			var/list/V = view(7, vw_probe)
			for(var/mob/M in V)
				VACC++
		return world.tick_usage - tu0

	VW_Inline(reps, r)
		VACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			for(var/mob/M in view(r, vw_probe))
				VACC++
		return world.tick_usage - tu0

	VW_Untyped(reps)
		VACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			for(var/atom/A in view(7, vw_probe))
				VACC++
		return world.tick_usage - tu0

	VW_TwoCached(reps)
		VACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			var/list/V = view(7, vw_probe)
			for(var/mob/M in V)
				VACC++
			for(var/obj/O in V)
				VACC++
		return world.tick_usage - tu0

	VW_TwoInline(reps)
		VACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			for(var/mob/M in view(7, vw_probe))
				VACC++
			for(var/obj/O in view(7, vw_probe))
				VACC++
		return world.tick_usage - tu0

	VW_Range(reps)
		VACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			for(var/mob/M in range(7, vw_probe))
				VACC++
		return world.tick_usage - tu0

	VW_Oview(reps)
		VACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			for(var/mob/M in oview(7, vw_probe))
				VACC++
		return world.tick_usage - tu0

	VW_Viewers(reps)
		VACC = 0
		var/tu0 = world.tick_usage
		for(var/i = 1 to reps)
			for(var/mob/M in viewers(7, vw_probe))
				VACC++
		return world.tick_usage - tu0

	Suite_View()
		VW_Setup(40, 400)

		// --- same output, three ways ---
		// Every count in this proc is named once and used everywhere it is
		// needed: to drive the loop, to divide the elapsed time, and to
		// normalise the atom counts in the evidence. Passing the loop count and
		// the divisor independently is what put view.family_view and
		// view.radius_7 1.83x high in two merged baselines and on the generated
		// site until 2026-08-01, and it also mis-scaled two evidence strings.
		// VERIFICATION 14.
		var/r_build = 8000
		var/r_bf = 8000
		var/r_inline = 110000
		var/r_untyped = 6000
		var/d_build = VW_Build(r_build)
		var/atoms = VACC / r_build
		var/d_bf = VW_BuildFilter(r_bf)
		var/n_bf = VACC / r_bf
		var/d_in = VW_Inline(r_inline, 7)
		var/n_in = VACC / r_inline
		var/d_un = VW_Untyped(r_untyped)

		Assert("view.filter_equivalence", "view",
			"cached-then-filtered and inline-typed return identical counts",
			(n_bf == n_in) ? 1 : 0, 1,
			"[n_bf] vs [n_in] mobs; without this the timing comparison is void")

		MeasureTU("view.build_only", "view", "var/list/V = view(7,c)", d_build, r_build, 0, "[atoms] atoms")
		MeasureTU("view.build_then_filter", "view", "cache list, then for(mob in V)", d_bf, r_bf, 0, "[n_bf] mobs")
		var/m_inline = MeasureTU("view.inline_typed", "view", "for(mob in view(7,c))", d_in, r_inline, 0, "[n_in] mobs")
		MeasureTU("view.inline_untyped", "view", "for(atom in view(7,c))", d_un, r_untyped, 0, "[atoms] atoms")

		// --- two passes ---
		var/r_tc = 6000
		var/r_ti = 14000
		var/d_tc = VW_TwoCached(r_tc)
		var/n_tc = VACC / r_tc
		var/d_ti = VW_TwoInline(r_ti)
		var/n_ti = VACC / r_ti
		Assert("view.twopass_equivalence", "view",
			"cached and re-queried two-pass return identical counts",
			(n_tc == n_ti) ? 1 : 0, 1, "[n_tc] vs [n_ti]")
		MeasureTU("view.twopass_cached", "view", "cache list, two typed loops", d_tc, r_tc, 0, null)
		MeasureTU("view.twopass_requery", "view", "call view() twice inline", d_ti, r_ti, 0, null)

		// --- family ---
		// The iteration count is named once and used twice, to run the loop and
		// to divide the result. Passing the two independently is how
		// view.family_view and view.radius_7 came to run 110,000 iterations and
		// divide by 60,000, publishing both 1.83x high in two merged baselines
		// and on the generated site until 2026-08-01. VERIFICATION 14.
		var/r_view = 110000
		var/r_oview = 110000
		var/r_viewers = 120000
		var/r_range = 270000
		var/m_family = MeasureTU("view.family_view", "view", "for(mob in view(7,c))", VW_Inline(r_view, 7), r_view, 0, null)
		MeasureTU("view.family_oview", "view", "for(mob in oview(7,c))", VW_Oview(r_oview), r_oview, 0, null)
		MeasureTU("view.family_viewers", "view", "for(mob in viewers(7,c))", VW_Viewers(r_viewers), r_viewers, 0, null)
		MeasureTU("view.family_range", "view", "for(mob in range(7,c))", VW_Range(r_range), r_range, 0, null)

		// --- radius ---
		var/r_r1 = 1600000
		var/r_r3 = 340000
		var/r_r5 = 160000
		var/r_r7 = 110000
		var/r_r10 = 70000
		var/v_r1 = MeasureTU("view.radius_1", "view", "for(mob in view(1,c))", VW_Inline(r_r1, 1), r_r1, 0, null)
		var/v_r3 = MeasureTU("view.radius_3", "view", "for(mob in view(3,c))", VW_Inline(r_r3, 3), r_r3, 0, null)
		var/v_r5 = MeasureTU("view.radius_5", "view", "for(mob in view(5,c))", VW_Inline(r_r5, 5), r_r5, 0, null)
		var/v_r7 = MeasureTU("view.radius_7", "view", "for(mob in view(7,c))", VW_Inline(r_r7, 7), r_r7, 0, null)
		var/v_r10 = MeasureTU("view.radius_10", "view", "for(mob in view(10,c))", VW_Inline(r_r10, 10), r_r10, 0, null)

#ifdef BREAKCHECK
		v_r7 = v_r7 * 1.83             // radius_7 above radius_10, as published
#endif
		// A sweep's ordering is known before it runs, so it is asserted rather
		// than hoped for. A wider view cannot cost less than a narrower one, and
		// this is the check that was missing when view.radius_7 published above
		// view.radius_10 for days: the number was impossible and nothing owned
		// the question. Ordering needs no tolerance and does not flip on noise
		// (xcheck lesson); measured steps are 1.5x or wider at every point.
		Assert("view.radius_sweep_monotonic", "view",
			"view() cost rises with radius at every step",
			(v_r1 < v_r3 && v_r3 < v_r5 && v_r5 < v_r7 && v_r7 < v_r10) ? 1 : 0, 1,
			"1:[round(v_r1,0.01)] 3:[round(v_r3,0.01)] 5:[round(v_r5,0.01)] 7:[round(v_r7,0.01)] 10:[round(v_r10,0.01)] us")

		// --- does the typed loop actually skip building? ---
		// Add atoms that cannot match. If the list is never materialised, the
		// typed loop should barely move while raw view() climbs steeply.
		var/list/clutter = list()
		var/base_raw = 0
		var/base_typed = 0
		var/m_clutter0 = 0
		for(var/added in list(0, 1200))
			while(clutter.len < added)
				var/obj/vw_obj/o = new
				o.loc = locate(50 + rand(-7,7), 50 + rand(-7,7), 1)
				clutter += o
			// mo read VACC / 100000 against a 110,000-iteration run until
			// 2026-08-01, so the mob count in this row's evidence was 10% high.
			var/r_craw = 10000
			var/r_ctyped = 110000
			var/dr = VW_Build(r_craw)
			var/at = VACC / r_craw
			var/dtp = VW_Inline(r_ctyped, 7)
			var/mo = VACC / r_ctyped
			var/raw_us = dr * US_PER_PCT / r_craw
			var/typed_us = dtp * US_PER_PCT / r_ctyped
			if(added == 0)
				base_raw = raw_us
				base_typed = typed_us
			else
				Assert("view.typed_loop_skips_build", "view",
					"typed loop grows far less than raw view() as clutter rises",
					(raw_us / max(base_raw, 0.01) > 3 * (typed_us / max(base_typed, 0.01))) ? 1 : 0, 1,
					"raw x[round(raw_us/max(base_raw,0.01),0.1)], typed x[round(typed_us/max(base_typed,0.01),0.1)] at [at] atoms, [mo] mobs")
			MeasureTU("view.clutter_[added]_raw", "view", "view(7) build with [added] extra objs", dr, r_craw, 0, "[at] atoms")
			var/mc = MeasureTU("view.clutter_[added]_typed", "view", "typed loop with [added] extra objs", dtp, r_ctyped, 0, "[mo] mobs")
			if(added == 0) m_clutter0 = mc
		for(var/obj/vw_obj/o in clutter)
			o.loc = null
		clutter.Cut()

		// Three rows time the same operation, `for(var/mob/M in view(7,c))`,
		// from three places in this section. They must agree, and when
		// view.family_view divided 110,000 iterations by 60,000 they did not:
		// it read 1.83x its siblings in two published baselines while every
		// per-row spread stayed under 10%, because a constant wrong divisor
		// repeats perfectly. Repeatability cannot catch that; cross-row
		// agreement can.
		//
		// 1.5x, sized from six runs on two builds where the three agreed to
		// within 1.00 to 1.19x. The worst case was the slowest run of a triple,
		// where the rows drift apart because they sit at different depths in
		// the section. The defect this exists to catch is 1.83x.
		// BREAKCHECK reintroduces the exact defect each new invariant exists to
		// catch, so the assertion can be seen going red rather than trusted for
		// being green. Compiled out of every normal build; define it in the
		// manifest to run a break check. A green that has never been red is a
		// decoration.
#ifdef BREAKCHECK
		m_family = m_family * 1.83     // the 110000/60000 divisor error
#endif
		var/same_hi = max(m_inline, max(m_family, m_clutter0))
		var/same_lo = min(m_inline, min(m_family, m_clutter0))
		Assert("view.same_operation_rows_agree", "view",
			"three rows timing the same typed view loop report the same cost",
			(same_lo > 0 && same_hi < same_lo * 1.5) ? 1 : 0, 1,
			"inline [round(m_inline,0.01)], family [round(m_family,0.01)], clutter_0 [round(m_clutter0,0.01)] us, ratio [round(same_lo > 0 ? same_hi/same_lo : 0, 0.01)]x")

		// --- is view() cost driven by opaque atoms? ---
		var/list/blocks = list()
		// Same named-count rule as the rows above. Both arms divided by 60,000
		// after running 110,000, which left the assertion sound (a ratio, so the
		// error cancelled) and its printed evidence 1.83x high.
		var/r_los = 110000
		var/v_clear = VW_Inline(r_los, 7)
		var/seen_clear = VACC / r_los
		while(blocks.len < 200)
			var/obj/vw_blocker/b = new
			b.loc = locate(50 + rand(-7,7), 50 + rand(-7,7), 1)
			blocks += b
		var/v_blocked = VW_Inline(r_los, 7)
		var/seen_blocked = VACC / r_los
		var/us_clear = v_clear * US_PER_PCT / r_los
		var/us_blocked = v_blocked * US_PER_PCT / r_los
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
