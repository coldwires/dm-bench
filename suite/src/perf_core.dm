// Lists, dispatch, calls, strings, allocation, movement.
//
// All sub-microsecond rows have the empty-loop baseline subtracted. Reps are
// sized so each cell clears MIN_DS; anything that does not gets flagged
// LOW_RESOLUTION in the notes column rather than silently reported.

#define FLAG_A (1<<0)

var/global/CACC = 0
var/global/CGLOBAL = 5
var/global/MV_ENTER = 0
var/global/MV_EXIT = 0
var/global/MV_ENTERED = 0
var/global/MV_EXITED = 0

datum/pc_holder
	var/x = 5
	proc
		Noop()
			return
		NoopDot()
			. = 1

obj/pc_thing
	var
		flags = 0
		list/cats

// Depth-8 chains for the istype scaling rows (VERIFICATION 6.1). The obj
// chain carries the istype forms; the mob chain exists for the typesof
// control, which the source claim specifically names as still O(depth).
obj/pc_d1/d2/d3/d4/d5/d6/d7/d8
mob/pc_m1/m2/m3/m4/m5/m6/m7/m8

turf/pc_turf
	Enter(atom/movable/A)
		MV_ENTER++
		return ..()
	Exit(atom/movable/A)
		MV_EXIT++
		return ..()
	Entered(atom/movable/A)
		MV_ENTERED++
		return ..()
	Exited(atom/movable/A)
		MV_EXITED++
		return ..()

proc/PC_GlobalNoop()
	return

proc
	// ---------------- lists ----------------

	Suite_Lists()
		// Kept per size so the sweep's ordering can be asserted after it runs.
		var/list/in_us = list()
		var/list/assoc_us = list()
		for(var/n in list(10, 100, 1000, 5000))
			var/list/flat = list()
			var/list/amap = list()
			for(var/i = 1 to n)
				flat += "k[i]"
				amap["k[i]"] = 1
			var/needle = "k[n]"
			// scan cost is O(n), so hold total work roughly constant. The
			// small-n reps rose 15M to 20M with the discarded-unroll
			// conversion: dropping the accumulator made the blocks faster and
			// 15M would sit at the MIN_DS edge.
			var/reps = (n >= 1000) ? (3000000 / (n / 1000)) : 20000000

			// Discarded-unroll, endorsed by differential compilation: a
			// discarded `in` and a discarded assoc index are both emitted, 16
			// bytes per copy (INSTRUMENTS.md). Unlike a field read, indexing
			// is an operation, not a pure read.
			#pragma push
			#pragma ignore no_effect
			var/t0 = world.timeofday
			for(var/i = 1 to reps / UNROLL)
				X10(needle in flat)
			in_us["[n]"] = MeasureU("lists.in_n[n]", "lists", "needle in L, n=[n], worst case",
				world.timeofday - t0, reps, UNROLL, null)

			var/t1 = world.timeofday
			for(var/i = 1 to 20000000 / UNROLL)
				X10(amap[needle])
			assoc_us["[n]"] = MeasureU("lists.assoc_n[n]", "lists", "A\[needle\], n=[n]",
				world.timeofday - t1, 20000000, UNROLL, null)
			#pragma pop

#ifdef BREAKCHECK
		in_us["5000"] = in_us["10"] / 2       // scan cost falling with size
		assoc_us["5000"] = assoc_us["10"] * 5 // assoc lookup scaling
#endif
		// The sweep's shape is the published claim, so it is asserted, not left
		// to a reader comparing four rows by eye. A linear scan must cost more
		// on a longer list at every step; measured steps are 3x or wider.
		Assert("lists.in_scales_with_size", "lists",
			"linear search cost rises at every list size",
			(in_us["10"] < in_us["100"] && in_us["100"] < in_us["1000"] && in_us["1000"] < in_us["5000"]) ? 1 : 0, 1,
			"10:[round(in_us["10"],0.01)] 100:[round(in_us["100"],0.01)] 1000:[round(in_us["1000"],0.01)] 5000:[round(in_us["5000"],0.01)] us")

		// The other half of the same claim, and the one the design advice rests
		// on. 3x, against a measured 1.5 to 1.6x across six runs: the assoc
		// column drifts upward slightly at the instrument's floor, which the
		// spec sheet reads as flat within its error bar. O(n) would be 500x.
		Assert("lists.assoc_stays_flat", "lists",
			"associative lookup does not scale with list size",
			(assoc_us["10"] > 0 && assoc_us["5000"] < assoc_us["10"] * 3) ? 1 : 0, 1,
			"10:[round(assoc_us["10"],0.01)] 5000:[round(assoc_us["5000"],0.01)] us, against in at 5000 of [round(in_us["5000"],0.01)]")

		// building, 100 elements
		var/t2 = world.timeofday
		for(var/i = 1 to 150000)
			var/list/L = list()
			for(var/j = 1 to 100)
				L += j
		Measure("lists.build_plus", "lists", "L = list(); L += j  x100", world.timeofday - t2, 150000, 0, "per 100-element list")

		var/t3 = world.timeofday
		for(var/i = 1 to 150000)
			var/list/L = list()
			for(var/j = 1 to 100)
				L.Add(j)
		Measure("lists.build_add", "lists", "L = list(); L.Add(j)  x100", world.timeofday - t3, 150000, 0, "per 100-element list")

		var/t4 = world.timeofday
		for(var/i = 1 to 150000)
			var/list/L = new(100)
			for(var/j = 1 to 100)
				L[j] = j
		Measure("lists.build_prealloc", "lists", "L = new(100); indexed assign x100", world.timeofday - t4, 150000, 0, "per 100-element list")

		var/list/L100 = list()
		for(var/i = 1 to 100) L100 += "k[i]"
		CACC = 0
		var/t5 = world.timeofday
		for(var/i = 1 to 1500000)
			var/list/C = L100.Copy()
			CACC += C.len
		Measure("lists.copy_100", "lists", "L.Copy(), 100 elements", world.timeofday - t5, 1500000, 0, null)

	// ---------------- dispatch ----------------

	Suite_Dispatch()
		var/obj/pc_thing/W = new
		W.flags = FLAG_A
		W.cats = list("weapon" = 1)
		var/obj/pc_thing/inner = new
		inner.loc = W

		// 25M, not 15M. Dropping the accumulator made each block finish faster,
		// and three of these rows fell under MIN_DS at the old count. The
		// resolution guard caught it rather than the numbers quietly getting
		// worse. Loop runs R/UNROLL = 2.5M times, well inside the 2^24 bound.
		var/R = 25000000

		// Unrolled UNROLL times with the result discarded, and reported through
		// MeasureU, which subtracts BASE_LOOP_US/UNROLL rather than BASE_US.
		//
		// The old form was `for(i = 1 to R) if(op) CACC++`, subtracting a
		// baseline that included both the loop and an accumulator. On istype
		// that baseline was 40.7% of the reading, so the published figure moved
		// with baseline calibration as much as with the engine. Discarding the
		// result and unrolling takes it to 3.4%. Neither lever alone is worth
		// much: unrolling reaches 34%, discarding 26%.
		//
		// This depends on DM executing an expression whose value is unused.
		// `framework.discarded_work_still_costs` asserts that it does, so a
		// future build that optimises it away fails loudly instead of silently
		// reporting every row as near zero.

		// Unrolling a discarded expression is exactly what no_effect is designed
		// to catch, so each X10 emits ten identical warnings at one line number.
		// Scoped suppression, not a global one: outside this block the warning is
		// wanted, because there it means someone wrote a statement by mistake.
		#pragma push
		#pragma ignore no_effect

		var/t0 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(istype(W, /obj/pc_thing))
		MeasureU("dispatch.istype", "dispatch", "istype(O, /obj/thing)", world.timeofday - t0, R, UNROLL, null)

		var/t1 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(W.type == /obj/pc_thing)
		MeasureU("dispatch.type_eq", "dispatch", "O.type == /obj/thing", world.timeofday - t1, R, UNROLL, null)

		var/t2 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(W.flags & FLAG_A)
		MeasureU("dispatch.bitfield", "dispatch", "O.flags & FLAG_A", world.timeofday - t2, R, UNROLL, null)

		var/t3 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(W.cats["weapon"])
		MeasureU("dispatch.assoc_category", "dispatch", "O.cats assoc lookup", world.timeofday - t3, R, UNROLL, null)

		var/t4 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(locate(/obj/pc_thing) in W)
		MeasureU("dispatch.locate_in_contents", "dispatch", "locate(type) in O, 1 item", world.timeofday - t4, R, UNROLL, null)

		// ---- istype scaling, VERIFICATION 6.1 ----
		// The claim (O(1) since 514.1579) is about DEPTH and RELATEDNESS, and
		// dispatch.istype above varies neither: one type, depth 1, tested
		// against the variable's own declared type. These rows vary both, in
		// UNTYPED vars so no declared-type best case applies. The discarded
		// unrolled form does identical work for hits and misses, so no
		// branch-taken confound applies (the accumulator form charges hits an
		// extra 0.027 us for the taken branch, see INSTRUMENTS.md).
		var/UD = new/obj/pc_d1/d2/d3/d4/d5/d6/d7/d8
		var/US = new/obj/pc_d1

		var/t5 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(istype(US, /obj/pc_d1))
		var/it_d1 = MeasureU("dispatch.istype_d1", "dispatch", "istype, depth-1 hit, untyped var", world.timeofday - t5, R, UNROLL, null)

		var/t6 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(istype(UD, /obj/pc_d1/d2/d3/d4/d5/d6/d7/d8))
		var/it_d8 = MeasureU("dispatch.istype_d8", "dispatch", "istype, depth-8 exact hit", world.timeofday - t6, R, UNROLL, null)

		var/t7 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(istype(UD, /obj/pc_d1))
		var/it_anc = MeasureU("dispatch.istype_ancestor", "dispatch", "istype, depth-8 instance vs depth-1 ancestor", world.timeofday - t7, R, UNROLL, null)

		var/t8 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(istype(US, /mob/pc_m1))
		var/it_miss = MeasureU("dispatch.istype_unrelated", "dispatch", "istype, unrelated-branch miss", world.timeofday - t8, R, UNROLL, null)

		#pragma pop

		// The control the source claim names: typesof() on mob types should
		// still scale, d1 returning 9 types against d8's 1. If istype comes
		// out flat AND this pair comes out flat, the harness is measuring
		// nothing and the ordering assertion below fails loudly.
		// TSGUARD's branch is never taken, identically in both arms, so the
		// list stays live without an accumulator saturating (8M x 9 would
		// pass 2^24; see assert_numeric).
		var/Rt = 8000000
		var/TSGUARD = 0

		var/t9 = world.timeofday
		for(var/i = 1 to Rt)
			var/list/L = typesof(/mob/pc_m1)
			if(L.len < 0) TSGUARD++
		var/ts_d1 = Measure("dispatch.typesof_d1", "dispatch", "typesof, depth-1 mob type, 9 subtypes", world.timeofday - t9, Rt, 1, null)

		var/t10 = world.timeofday
		for(var/i = 1 to Rt)
			var/list/L = typesof(/mob/pc_m1/m2/m3/m4/m5/m6/m7/m8)
			if(L.len < 0) TSGUARD++
		var/ts_d8 = Measure("dispatch.typesof_d8", "dispatch", "typesof, depth-8 mob type, 1 subtype", world.timeofday - t10, Rt, 1, null)

		if(TSGUARD) Row("# unreachable")

		// O(depth) would put depth 8 near 8x depth 1; flat-within-noise is
		// about 1x with a spread ceiling near 25%. 3x separates the two
		// decisively without a noise-anchored tolerance. The 0.02 floor stops
		// a BELOW_BASELINE zero in the anchor from failing the row spuriously.
		Assert("dispatch.istype_flat", "dispatch",
			"istype cost is flat across depth and relatedness",
			(it_d8 < max(it_d1, 0.02) * 3 && it_anc < max(it_d1, 0.02) * 3 && it_miss < max(it_d1, 0.02) * 3) ? 1 : 0, 1,
			"d1 [round(it_d1,0.001)] d8 [round(it_d8,0.001)] ancestor [round(it_anc,0.001)] unrelated [round(it_miss,0.001)] us/op")

		// Ordering, no tolerance, per the xcheck lesson: an instrument that has
		// gone wrong misranks these; one that is merely noisy does not.
		Assert("dispatch.typesof_control_scales", "dispatch",
			"typesof on a 9-subtype mob type outranks a 1-subtype one",
			(ts_d1 > ts_d8) ? 1 : 0, 1,
			"d1 [round(ts_d1,0.001)] us/op vs d8 [round(ts_d8,0.001)] us/op")

		inner.loc = null

	// ---------------- calls and variable access ----------------

	Suite_Calls()
		var/datum/pc_holder/H = new
		var/R = 15000000

		// Unrolled, results discarded. A discarded call is emitted (it may
		// have side effects), so no pragma is needed here; only pure
		// expressions draw no_effect.
		var/t0 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(PC_GlobalNoop())
		MeasureU("calls.global_proc", "calls", "GlobalProc(), empty", world.timeofday - t0, R, UNROLL, null)

		var/t1 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(H.Noop())
		MeasureU("calls.datum_method", "calls", "D.Method(), empty", world.timeofday - t1, R, UNROLL, null)

		var/t2 = world.timeofday
		for(var/i = 1 to R / UNROLL)
			X10(H.NoopDot())
		MeasureU("calls.datum_method_dot", "calls", "D.Method(), sets . = 1", world.timeofday - t2, R, UNROLL, null)

		// The vars rows below stay in accumulator form PERMANENTLY. A
		// discarded pure read (local, global, world.time, field) is
		// eliminated by the compiler, verified by differential compilation
		// on both builds (INSTRUMENTS.md), so a discarded-unroll conversion
		// would time an empty loop and publish near zero with nothing
		// flagged. Their BASELINE_HEAVY flag is the honest cost of
		// measuring a read.
		var/lv = 5
		CACC = 0
		var/t3 = world.timeofday
		for(var/o = 1 to 3)
			for(var/i = 1 to 10000000)
				CACC += lv
		Measure("vars.local", "calls", "acc += local_var", world.timeofday - t3, 30000000, 1, null)

		CACC = 0
		var/t4 = world.timeofday
		for(var/o = 1 to 3)
			for(var/i = 1 to 10000000)
				CACC += CGLOBAL
		Measure("vars.global", "calls", "acc += global_var", world.timeofday - t4, 30000000, 1, null)

		CACC = 0
		var/t5 = world.timeofday
		for(var/o = 1 to 3)
			for(var/i = 1 to 10000000)
				CACC += world.time
		Measure("vars.world_time", "calls", "acc += world.time", world.timeofday - t5, 30000000, 1, null)

		CACC = 0
		var/t6 = world.timeofday
		for(var/o = 1 to 3)
			for(var/i = 1 to 10000000)
				CACC += H.x
		Measure("vars.datum", "calls", "acc += D.x", world.timeofday - t6, 30000000, 1, null)

	// ---------------- strings ----------------

	Suite_Strings()
		var/a = "foo"
		var/b = "bar"
		var/R = 5000000

		CACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to R)
			var/s = "[a][b]"
			CACC += length(s)
		Measure("strings.embed", "strings", "s = embedded expression", world.timeofday - t0, R, 1, null)

		CACC = 0
		var/t1 = world.timeofday
		for(var/i = 1 to R)
			var/s = a + b
			CACC += length(s)
		Measure("strings.concat", "strings", "s = a + b", world.timeofday - t1, R, 1, null)

		CACC = 0
		var/t2 = world.timeofday
		for(var/i = 1 to 2000000)
			CACC += length(num2text(i))
		Measure("strings.num2text", "strings", "num2text(i)", world.timeofday - t2, 2000000, 1, null)

		var/hay = "the quick brown fox jumps over the lazy dog"
		CACC = 0
		var/t3 = world.timeofday
		for(var/i = 1 to 1000000)
			CACC += findtext(hay, "lazy")
		Measure("strings.findtext", "strings", "findtext, 43-char haystack", world.timeofday - t3, 1000000, 1, null)

	// ---------------- allocation ----------------

	Suite_Alloc()
		AllocOne("alloc.datum", /datum, 10000000)
		AllocOne("alloc.datum_holder", /datum/pc_holder, 10000000)
		AllocOne("alloc.obj", /obj, 4000000)
		AllocOne("alloc.mob", /mob, 4000000)

	AllocOne(id, T, reps)
		// Discarded-unroll: `new T` with the result dropped allocates an
		// object that is freed on the spot (zero references), the same
		// churn as the old assign-then-overwrite form without the var
		// machinery. Live population stays at one either way, so this does
		// not contaminate anything (and del() rows live in another process
		// regardless).
		var/t0 = world.timeofday
		for(var/i = 1 to reps / UNROLL)
			X10(new T)
		MeasureU(id, "alloc", "new [T]", world.timeofday - t0, reps, UNROLL, null)

	// ---------------- movement ----------------

	Suite_Movement()
		// Timing runs on PLAIN turfs. Using the counted turf here measures the
		// four callback overrides as part of Move() and inflates it ~70%.
		var/turf/P1 = locate(30, 30, 1)
		var/turf/P2 = locate(31, 30, 1)
		var/mob/M = new
		M.loc = P1

		var/t0 = world.timeofday
		for(var/i = 1 to 6000000)
			M.loc = (i % 2) ? P1 : P2
		Measure("movement.loc_assign", "movement", "M.loc = T", world.timeofday - t0, 6000000, 1, "plain turf, no callbacks")

		var/t1 = world.timeofday
		for(var/i = 1 to 2000000)
			M.Move((i % 2) ? P1 : P2)
		Measure("movement.move_proc", "movement", "M.Move(T)", world.timeofday - t1, 2000000, 1, "plain turf, engine callbacks only")

		// Overridden callbacks are a separate, more expensive case.
		var/turf/pc_turf/A = new(locate(20, 20, 1))
		var/turf/pc_turf/B = new(locate(21, 20, 1))
		M.loc = A
		var/t2 = world.timeofday
		for(var/i = 1 to 2000000)
			M.Move((i % 2) ? A : B)
		Measure("movement.move_proc_overridden", "movement", "M.Move(T) with 4 overridden callbacks", world.timeofday - t2, 2000000, 1, "cost of user hooks on top of Move()")

		// callbacks actually fire
		MV_ENTER = 0; MV_EXIT = 0; MV_ENTERED = 0; MV_EXITED = 0
		for(var/i = 1 to 1000)
			M.Move((i % 2) ? A : B)
		Assert("movement.move_fires_callbacks", "movement",
			"Move() fires Enter, Exit, Entered and Exited",
			(MV_ENTER >= 999 && MV_EXIT >= 999 && MV_ENTERED >= 999 && MV_EXITED >= 999) ? 1 : 0, 1,
			"Enter=[MV_ENTER] Exit=[MV_EXIT] Entered=[MV_ENTERED] Exited=[MV_EXITED] over 1000 moves")

		MV_ENTER = 0; MV_EXIT = 0; MV_ENTERED = 0; MV_EXITED = 0
		for(var/i = 1 to 1000)
			M.loc = (i % 2) ? A : B
		Assert("movement.loc_assign_skips_callbacks", "movement",
			"assigning loc fires none of them",
			(MV_ENTER + MV_EXIT + MV_ENTERED + MV_EXITED), 0, null)
