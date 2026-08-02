// Object lifetime and garbage collection semantics.
//
// Every assertion here encodes behaviour observed on 516.1666. A FAIL on a
// later version means the engine changed, which is the point of the suite.
// It does not necessarily mean the engine got worse: if the loc/contents
// cycle ever becomes collectable, that assertion SHOULD fail and the whole
// mandatory-teardown discipline can be relaxed.

var/global/LIFE_MADE = 0
var/global/LIFE_GONE = 0
var/global/PIN_MADE = 0
var/global/PIN_GONE = 0
var/global/SLEEPER_SAW = "unset"
var/global/PROC_CONTINUED = 0

lt_obj
	parent_type = /obj

	New()
		..()
		LIFE_MADE++

	Del()
		LIFE_GONE++
		..()

	proc
		SuicideGuarded()
			if(!src)
				del(src)
			PROC_CONTINUED = 1

		SuicidePlain()
			del(src)
			PROC_CONTINUED = 1     // must NOT run: del(src) aborts the proc

// Dedicated type for the spawn-pin assertion. A shared census picks up
// deferred collections from earlier subtests and reports a false negative.
lt_pin
	parent_type = /obj

	New()
		..()
		PIN_MADE++

	Del()
		PIN_GONE++
		..()

	proc
		Snooze()
			spawn(20)
				SLEEPER_SAW = src ? "ALIVE" : "NULL"

lt_host
	parent_type = /mob

proc
	LifeLive()
		return LIFE_MADE - LIFE_GONE

	PinLive()
		return PIN_MADE - PIN_GONE

	StartSleeper()
		var/lt_pin/d = new
		d.Snooze()
		d = null

	Suite_Lifetime()
		// --- refcount collection of an unreferenced object ---
		LIFE_MADE = 0; LIFE_GONE = 0
		var/lt_obj/a = new
		a = null
		Assert("lifetime.refcount_collects", "lifetime",
			"unreferenced object is collected", LifeLive(), 0,
			"created 1, dropped the only ref")

		// --- loc/contents cycle ---
		LIFE_MADE = 0; LIFE_GONE = 0
		for(var/i = 1 to 500)
			var/lt_host/h = new
			var/lt_obj/e = new
			e.loc = h
			e = null
			h = null
		Assert("lifetime.cycle_not_collected", "lifetime",
			"loc/contents cycle is never collected", LIFE_GONE, 0,
			"500 host+child pairs, all refs dropped, none freed")

		// --- same, contents cleared first ---
		LIFE_MADE = 0; LIFE_GONE = 0
		for(var/i = 1 to 500)
			var/lt_host/h = new
			var/lt_obj/e = new
			e.loc = h
			e.loc = null
			e = null
			h = null
		Assert("lifetime.cycle_broken_collects", "lifetime",
			"clearing contents first allows collection", (LIFE_GONE >= 499) ? 1 : 0, 1,
			"500 pairs, freed [LIFE_GONE]; the last iteration's local may still be scoped")

		// --- del(src) aborts the proc ---
		PROC_CONTINUED = 0
		var/lt_obj/b = new
		b.SuicidePlain()
		Assert("lifetime.del_src_aborts_proc", "lifetime",
			"del(src) aborts the calling proc", PROC_CONTINUED, 0,
			"the line after del(src) must not execute")

		Assert("lifetime.del_nulls_caller_ref", "lifetime",
			"del(src) nulls the caller's local", b ? "ALIVE" : "NULL", "NULL", null)

		// --- if(!src) is unreachable in a live proc ---
		PROC_CONTINUED = 0
		var/lt_obj/c = new
		c.SuicideGuarded()
		Assert("lifetime.src_never_null_in_proc", "lifetime",
			"if(!src) never passes inside a live proc", PROC_CONTINUED, 1,
			"guarded del must not fire; proc runs to completion")
		c = null

		// --- a pending spawn() pins its object ---
		// Own type and own counters. A shared census is contaminated by
		// deferred collections from the cycle tests above, which produced a
		// false FAIL on the first version of this suite.
		PIN_MADE = 0; PIN_GONE = 0
		SLEEPER_SAW = "unset"
		// Created and released inside a helper that RETURNS, so no frame of
		// the still-running suite proc can hold a residual reference.
		StartSleeper()
		Assert("lifetime.spawn_pins_object", "lifetime",
			"object survives while a spawn is pending", PinLive(), 1,
			"only ref dropped, spawn still queued")

		sleep(30)
		Assert("lifetime.spawn_sees_live_src", "lifetime",
			"pending spawn wakes with src alive", SLEEPER_SAW, "ALIVE", null)

		// Collection after the spawn resolves is eventual, not immediate.
		// Asserting on the instant the spawn fires produces a false FAIL.
		var/waited = 0
		while(PinLive() > 0 && waited < 200)
			sleep(1)
			waited++
		Assert("lifetime.collected_after_spawn", "lifetime",
			"object is collected once the spawn resolves", PinLive(), 0,
			"collected [waited] ticks after the spawn fired")
