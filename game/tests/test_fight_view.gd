## The client side of "an enemy stopped playing": a visual sequence that never ends blocks the events
## after it (ClientSession._pump waits for sequence_done). SequenceGuard / FightView.watchdog give up.
extends TestCase


func test_a_sequence_guard_counts_and_gives_up() -> void:
	var g := SequenceGuard.new()
	var t := g.begin(1000)
	eq(g.running, 1)
	check(not g.expired(1000 + SequenceGuard.TIMEOUT_MS - 1), "not yet")
	check(g.finish(t), "ends normally")
	eq(g.running, 0)
	check(not g.expired(1000 + SequenceGuard.TIMEOUT_MS * 5), "nothing running, nothing to give up")
	var stuck := g.begin(5000)
	check(g.expired(5000 + SequenceGuard.TIMEOUT_MS), "too long: given up")
	eq(g.running, 0)
	check(not g.expired(5000 + SequenceGuard.TIMEOUT_MS * 2), "only once")
	var next := g.begin(60000)
	check(not g.finish(stuck), "the abandoned sequence waking up late is ignored")
	eq(g.running, 1, "and does not end the next one")
	check(g.finish(next))


func test_the_fight_view_unblocks_the_queue() -> void:
	var view := FightView.new()
	var done := [0]
	view.sequence_done.connect(func() -> void: done[0] += 1)
	var token := view._begin_sequence()
	check(not view.watchdog(Time.get_ticks_msec() + 1000), "a normal sequence is left alone")
	check(view.watchdog(Time.get_ticks_msec() + SequenceGuard.TIMEOUT_MS + 1000), "a stuck one is forced done")
	eq(done[0], 1, "sequence_done emitted: the client queue goes on")
	view._end_sequence(token) # the coroutine finally ends
	eq(done[0], 1, "not signalled twice")
	var t2 := view._begin_sequence()
	view._end_sequence(t2)
	eq(done[0], 2)
	view.free()
