// animate() supersession: does the superseded-sequence queue still grow?
//
// The claim under test: calling animate() on an atom that is still
// mid-animation does not replace the old sequence, it chains from wherever the
// old one had reached. Animating every tick with a duration longer than a tick
// therefore builds ((A->B, 0.5) -> C, 0.5) -> D and so on without bound, and
// both server and client pay for the growing list.
//
// 516.1656 records that superseded animation sequences behaved erratically and
// were fixed. A release note can say the visible symptom was fixed; it cannot
// say the accumulation was, and the published analysis separates the two,
// describing a bypass that would hide this specific test case without
// addressing the mechanism. So the question this harness answers is not "is it
// fixed" but "did the fix fix it".
//
// The measurement is an ordering claim over time, which needs no tolerance on
// any absolute: the workload in every window is identical, 1,000 animate()
// calls per tick, so a healthy engine costs the same in the last window as in
// the first. Growth across windows is the accumulation alive.
//
// Two controls, both escape hatches the published analysis named as avoiding
// the problem: ANIMATION_END_NOW and ANIMATION_PARALLEL. If the plain arm grows while the
// controls stay flat, the mechanism is confirmed. If everything grows, this
// harness is measuring something else and NO conclusion is allowed from it.
//
// END_NOW is deliberately used untagged. Named sequences had their own END_NOW
// defect until 516.1657, and a control must not sit inside its own bug window.
//
// SCOPE, and it is half the story: this is the server side only. The dramatic
// symptoms in the original report, client CPU and a network read error, need a
// connected DreamSeeker and the two-machine leg. A flat result here reads
// "server-side accumulation not detected", never "fixed".
//
// This runs in its own manifest because it grows engine state without bound and
// the historic endpoint was an overflow. It must not share a process with rows
// anybody trusts.

var/global/AN_COUNT = 0

obj/an_thing
	icon_state = "x"

var/global/list/AN_OBJS = list()

proc
	// One arm. `mode` is 0 plain, 1 END_NOW, 2 PARALLEL.
	//
	// Returns a list of the three window costs in percent of a tick. Each
	// window runs AN_WINDOW ticks of identical work, so the three are directly
	// comparable and no baseline is subtracted from any of them.
	AN_Arm(mode, objs, window, gap)
		AN_COUNT = 0
		var/w1 = 0
		var/w2 = 0
		var/w3 = 0
		var/total = window * 3 + gap * 2
		var/w2_start = window + gap
		var/w3_start = window * 2 + gap * 2

		for(var/t = 1 to total)
			// Ping-pong between two DIFFERENT states. Animating A to A would
			// let a do-nothing shortcut mask the mechanism. The published
			// analysis describes counting an exhausted sequence as free to
			// supersede, which would fix a test case without fixing the
			// underlying issue.
			var/target = (t % 2) ? 16 : 0
			var/tu0 = world.tick_usage
			switch(mode)
				if(1)
					for(var/obj/an_thing/A in AN_OBJS)
						animate(A, pixel_x = target, time = 2, flags = ANIMATION_END_NOW)
						AN_COUNT++
				if(2)
					for(var/obj/an_thing/A in AN_OBJS)
						animate(A, pixel_x = target, time = 2, flags = ANIMATION_PARALLEL)
						AN_COUNT++
				else
					for(var/obj/an_thing/A in AN_OBJS)
						animate(A, pixel_x = target, time = 2)
						AN_COUNT++
			var/used = world.tick_usage - tu0

			if(t <= window)
				w1 += used
			else if(t > w2_start && t <= w2_start + window)
				w2 += used
			else if(t > w3_start && t <= w3_start + window)
				w3 += used

			sleep(world.tick_lag)

		return list(w1, w2, w3)

	Suite_Animate()
		var/objs = 1000
		var/window = 300
		var/gap = 1200

		// The population is built once and shared by all three arms, so the
		// arms differ only in the flag passed to animate(). Rebuilding between
		// arms would put a different set of appearances behind each one.
		for(var/i = 1 to objs)
			var/obj/an_thing/A = new(locate((i % 90) + 5, (i / 90) + 5, 1))
			AN_OBJS += A

		var/reps = objs * window

		// --- the arm under test ---
		var/list/plain = AN_Arm(0, objs, window, gap)
		var/p1 = MeasureTU("animate.plain_early", "animate", "animate() per call, ticks 1 to 300",
			plain[1], reps, 0, "1000 objs, time=2, superseding every tick")
		var/p2 = MeasureTU("animate.plain_mid", "animate", "animate() per call, ticks 1501 to 1800",
			plain[2], reps, 0, null)
		var/p3 = MeasureTU("animate.plain_late", "animate", "animate() per call, ticks 3001 to 3300",
			plain[3], reps, 0, null)

		// A liveness check that cannot saturate: 900,000 calls is well under
		// 2^24, but the count is asserted rather than assumed because a proc
		// that runtimes mid-loop would otherwise report a small, plausible cost.
		Assert("animate.arm_ran_every_call", "animate",
			"the plain arm issued every animate() call it was asked to",
			AN_COUNT, objs * (window * 3 + gap * 2),
			"[AN_COUNT] calls over [window * 3 + gap * 2] ticks")

		// --- controls ---
		var/list/endnow = AN_Arm(1, objs, window, gap)
		var/e1 = MeasureTU("animate.end_now_early", "animate", "ANIMATION_END_NOW per call, ticks 1 to 300",
			endnow[1], reps, 0, "control: supersession cannot chain")
		MeasureTU("animate.end_now_mid", "animate", "ANIMATION_END_NOW per call, ticks 1501 to 1800",
			endnow[2], reps, 0, null)
		var/e3 = MeasureTU("animate.end_now_late", "animate", "ANIMATION_END_NOW per call, ticks 3001 to 3300",
			endnow[3], reps, 0, null)

		var/list/par = AN_Arm(2, objs, window, gap)
		var/r1 = MeasureTU("animate.parallel_early", "animate", "ANIMATION_PARALLEL per call, ticks 1 to 300",
			par[1], reps, 0, "control: parallel sequences do not supersede")
		MeasureTU("animate.parallel_mid", "animate", "ANIMATION_PARALLEL per call, ticks 1501 to 1800",
			par[2], reps, 0, null)
		var/r3 = MeasureTU("animate.parallel_late", "animate", "ANIMATION_PARALLEL per call, ticks 3001 to 3300",
			par[3], reps, 0, null)

		// The claim, stated as the healthy answer so that a FAIL is the finding.
		// Identical work in every window means identical cost; 1.5x is far
		// outside anything the windows have varied by and far inside what
		// unbounded accumulation would produce.
		Assert("animate.cost_flat_over_time", "animate",
			"repeated supersession does not get more expensive over time",
			(p1 > 0 && p3 < p1 * 1.5) ? 1 : 0, 1,
			"early [round(p1,0.001)] mid [round(p2,0.001)] late [round(p3,0.001)] us/call, late/early [round(p1 > 0 ? p3/p1 : 0, 0.01)]x")

		// Without these, a growing plain arm proves nothing: it could be the
		// harness, the map, or the appearance count rather than supersession.
		Assert("animate.end_now_control_flat", "animate",
			"the END_NOW control does not grow",
			(e1 > 0 && e3 < e1 * 1.5) ? 1 : 0, 1,
			"early [round(e1,0.001)] late [round(e3,0.001)] us/call, [round(e1 > 0 ? e3/e1 : 0, 0.01)]x")

		Assert("animate.parallel_control_flat", "animate",
			"the PARALLEL control does not grow",
			(r1 > 0 && r3 < r1 * 1.5) ? 1 : 0, 1,
			"early [round(r1,0.001)] late [round(r3,0.001)] us/call, [round(r1 > 0 ? r3/r1 : 0, 0.01)]x")
