// Scheduler semantics and tick ordering.
//
// Documented engine model: waking procs, then world.Tick(), then incoming
// verbs, then maptick. The first two are testable headless. Verbs and maptick
// need a connected client and live in net/.

var/global/TICK_FIRED = 0
var/global/SEQ = 0
var/global/WAKE_SEQ = -1
var/global/TICK_SEQ = -1
var/global/CAPTURE_ORDER = 0
var/global/SPAWN0_TIME = -1
var/global/SCHED_RUNNING = 1

world/Tick()
	TICK_FIRED++
	if(CAPTURE_ORDER && TICK_SEQ < 0 && WAKE_SEQ > 0)
		TICK_SEQ = ++SEQ

proc
	OrderWaker()
		sleep(world.tick_lag)
		if(CAPTURE_ORDER && WAKE_SEQ < 0)
			WAKE_SEQ = ++SEQ

	Parked()
		sleep(36000)

	Ticker()
		while(SCHED_RUNNING)
			sleep(world.tick_lag)

	Settle(ticks)
		for(var/i = 1 to ticks)
			sleep(world.tick_lag)

	TickCost(n)
		var/t0 = world.timeofday
		for(var/i = 1 to n)
			sleep(world.tick_lag)
		return world.timeofday - t0

	// A spawned block gets a COPY of the caller's locals and cannot write back.
	SpawnWritesLocal()
		var/local_val = -1
		spawn(0)
			local_val = 99
		sleep(world.tick_lag)
		return local_val

	Suite_Scheduler()
		// --- world/Tick() is a real engine hook ---
		TICK_FIRED = 0
		Settle(10)
		Assert("scheduler.world_tick_is_hook", "scheduler",
			"world/Tick() fires once per tick", (TICK_FIRED >= 8 && TICK_FIRED <= 13) ? 1 : 0, 1,
			"fired [TICK_FIRED] times over ~10 ticks")

		// --- waking procs run before world.Tick() ---
		SEQ = 0; WAKE_SEQ = -1; TICK_SEQ = -1
		CAPTURE_ORDER = 1
		spawn(0) OrderWaker()
		Settle(6)
		CAPTURE_ORDER = 0
		Assert("scheduler.wake_before_world_tick", "scheduler",
			"waking procs run before world.Tick()",
			(WAKE_SEQ > 0 && TICK_SEQ > WAKE_SEQ) ? 1 : 0, 1,
			"wake seq [WAKE_SEQ], Tick seq [TICK_SEQ]")

		// --- spawn(0) runs in the same tick ---
		SPAWN0_TIME = -1
		var/before = world.time
		spawn(0)
			SPAWN0_TIME = world.time
		sleep(world.tick_lag)
		Assert("scheduler.spawn0_same_tick", "scheduler",
			"spawn(0) runs in the same tick", (SPAWN0_TIME == before) ? 1 : 0, 1,
			"before [before], inside [SPAWN0_TIME]")

		// --- a spawned context is a copy of the caller's locals ---
		Assert("scheduler.spawn_context_is_copy", "scheduler",
			"spawned block cannot write to the caller's locals",
			SpawnWritesLocal(), -1,
			"99 would mean the context is shared, not copied")

		// --- parked procs are free ---
		// Measure only after the spawns have finished starting. Sampling during
		// the backlog reports large fake overhead.
		var/ideal = 100 * world.tick_lag
		var/parked = 0
		for(var/target in list(0, 10000, 100000))
			while(parked < target)
				spawn(0) Parked()
				parked++
			Settle(40)
			var/dt = TickCost(100)
			Measure("scheduler.parked_[target]", "scheduler",
				"100 ticks with [target] parked procs", dt, 100, 0,
				"ideal [ideal] ds, overhead [round(dt - ideal, 0.1)] ds")

		// --- procs waking every tick are free ---
		var/tickers = 0
		for(var/target in list(1000, 5000))
			while(tickers < target)
				spawn(0) Ticker()
				tickers++
			Settle(40)
			var/dt = TickCost(100)
			Measure("scheduler.waking_[target]", "scheduler",
				"100 ticks with [target] procs waking each tick", dt, 100, 0,
				"ideal [ideal] ds, overhead [round(dt - ideal, 0.1)] ds")
		SCHED_RUNNING = 0
		Settle(10)
