// Numeric precision limits.
//
// DM numbers are 32-bit floats. Integers are exact to 2^24 = 16,777,216.
// Everything here is a consequence of that. If a future BYOND widens the
// numeric type, these assertions fail and a lot of defensive code can go.

var/global/LOOP_ESCAPED = 0

proc
	Suite_Numeric()
		// --- the bound itself ---
		Assert("numeric.eq_at_2p24", "numeric",
			"16777216 == 16777217", (16777216 == 16777217) ? 1 : 0, 1,
			"16777217 is not representable and rounds down")

		Assert("numeric.increment_stalls", "numeric",
			"n+1 == n first holds at 2^24", FindStallPoint(), 16777216, null)

		// --- for-loops past the bound never terminate ---
		var/guard = 0
		var/last = 0
		for(var/i = 16777210 to 16777230)
			guard++
			last = i
			if(guard > 50)
				break
		Assert("numeric.loop_nonterminating", "numeric",
			"for-loop past 2^24 does not terminate", (guard > 50) ? 1 : 0, 1,
			"bailed via guard at i=[last]")

		// control: identical loop shape below the bound
		var/g2 = 0
		for(var/i = 16777100 to 16777120)
			g2++
			if(g2 > 50) break
		Assert("numeric.loop_control_terminates", "numeric",
			"same loop below 2^24 terminates normally", g2, 21,
			"control for the above")

		// --- accumulators saturate silently ---
		var/acc = 16000000
		for(var/i = 1 to 2000000)
			acc += 1
		Assert("numeric.accumulator_saturates", "numeric",
			"accumulator saturates at 2^24", acc, 16777216,
			"expected 18000000, lost [18000000 - acc], no error raised")

		// --- num2text switches to scientific notation above the bound ---
		//
		// The consequence is not arithmetic, it is text: a number that is still
		// exactly representable stops rendering as digits, so anything writing
		// an id, a savefile key or a log line through string interpolation
		// silently changes format partway up the range.
		//
		// Ported 2026-08-03. This was published for months as an observation
		// from a harness that is not in this tree, then withdrawn when the page
		// was audited for figures nobody could reproduce. It is four lines, so
		// withdrawing it was the wrong trade: it is asserted here instead.
		//
		// The control is the point. 16777216 is at the bound and must still
		// render as digits, so a build that changed formatting wholesale would
		// fail that one rather than quietly passing this pair.
		var/at_bound = "[16777216]"
		var/above_bound = "[16777218]"
		Assert("numeric.num2text_plain_at_bound", "numeric",
			"a value at 2^24 still renders as digits",
			findtext(at_bound, "e+") ? 0 : 1, 1,
			"\"[at_bound]\"")
		Assert("numeric.num2text_scientific_above_bound", "numeric",
			"a value above 2^24 renders in scientific notation",
			findtext(above_bound, "e+") ? 1 : 0, 1,
			"16777218 renders as \"[above_bound]\", not as digits")

		// --- bit shifts ---
		Assert("numeric.shift_23_ok", "numeric", "1 << 23", 1 << 23, 8388608, "highest usable bit")
		Assert("numeric.shift_24_zero", "numeric", "1 << 24", 1 << 24, 0, "mask becomes zero, not a large number")
		Assert("numeric.shift_30_zero", "numeric", "1 << 30", 1 << 30, 0, null)
		Assert("numeric.shift_32_wraps", "numeric", "1 << 32", 1 << 32, 1, "shift count wraps")

		// --- bitfield round-trip ---
		Assert("numeric.bitfield_23_survives", "numeric",
			"flag at bit 23 round-trips", BitRoundTrip(23), 1, null)
		Assert("numeric.bitfield_24_lost", "numeric",
			"flag at bit 24 is silently lost", BitRoundTrip(24), 0,
			"zero mask: setting stores nothing, testing reads false")

	FindStallPoint()
		var/n = 16777200
		for(var/steps = 1 to 200)
			if((n + 1) == n)
				return n
			n = n + 1
		return -1

	BitRoundTrip(b)
		var/mask = 1 << b
		var/flags = 0
		flags |= mask
		return (flags & mask) ? 1 : 0
