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
		for(var/n in list(10, 100, 1000, 5000))
			var/list/flat = list()
			var/list/amap = list()
			for(var/i = 1 to n)
				flat += "k[i]"
				amap["k[i]"] = 1
			var/needle = "k[n]"
			// scan cost is O(n), so hold total work roughly constant
			var/reps = (n >= 1000) ? (3000000 / (n / 1000)) : 15000000

			CACC = 0
			var/t0 = world.timeofday
			for(var/i = 1 to reps)
				if(needle in flat) CACC++
			Measure("lists.in_n[n]", "lists", "needle in L, n=[n], worst case",
				world.timeofday - t0, reps, 1, null)

			CACC = 0
			var/t1 = world.timeofday
			for(var/i = 1 to 15000000)
				if(amap[needle]) CACC++
			Measure("lists.assoc_n[n]", "lists", "A\[needle\], n=[n]",
				world.timeofday - t1, 15000000, 1, null)

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

		var/R = 15000000

		CACC = 0
		var/t0 = world.timeofday
		for(var/i = 1 to R)
			if(istype(W, /obj/pc_thing)) CACC++
		Measure("dispatch.istype", "dispatch", "istype(O, /obj/thing)", world.timeofday - t0, R, 1, null)

		CACC = 0
		var/t1 = world.timeofday
		for(var/i = 1 to R)
			if(W.type == /obj/pc_thing) CACC++
		Measure("dispatch.type_eq", "dispatch", "O.type == /obj/thing", world.timeofday - t1, R, 1, null)

		CACC = 0
		var/t2 = world.timeofday
		for(var/i = 1 to R)
			if(W.flags & FLAG_A) CACC++
		Measure("dispatch.bitfield", "dispatch", "O.flags & FLAG_A", world.timeofday - t2, R, 1, null)

		CACC = 0
		var/t3 = world.timeofday
		for(var/i = 1 to R)
			if(W.cats["weapon"]) CACC++
		Measure("dispatch.assoc_category", "dispatch", "O.cats assoc lookup", world.timeofday - t3, R, 1, null)

		CACC = 0
		var/t4 = world.timeofday
		for(var/i = 1 to R)
			if(locate(/obj/pc_thing) in W) CACC++
		Measure("dispatch.locate_in_contents", "dispatch", "locate(type) in O, 1 item", world.timeofday - t4, R, 1, null)

		inner.loc = null

	// ---------------- calls and variable access ----------------

	Suite_Calls()
		var/datum/pc_holder/H = new
		var/R = 15000000

		var/t0 = world.timeofday
		for(var/i = 1 to R)
			PC_GlobalNoop()
		Measure("calls.global_proc", "calls", "GlobalProc(), empty", world.timeofday - t0, R, 1, null)

		var/t1 = world.timeofday
		for(var/i = 1 to R)
			H.Noop()
		Measure("calls.datum_method", "calls", "D.Method(), empty", world.timeofday - t1, R, 1, null)

		var/t2 = world.timeofday
		for(var/i = 1 to R)
			H.NoopDot()
		Measure("calls.datum_method_dot", "calls", "D.Method(), sets . = 1", world.timeofday - t2, R, 1, null)

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
		var/t0 = world.timeofday
		for(var/i = 1 to reps)
			var/x = new T
			x = null
		Measure(id, "alloc", "new [T]", world.timeofday - t0, reps, 1, null)

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
