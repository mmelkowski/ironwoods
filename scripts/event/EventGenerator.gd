class_name EventGenerator
extends RefCounted
## Chooses the event of an EVENT node. Like EncounterGenerator, the draw is seeded with the
## run and the node: the same node gives the same event during one run (reloading a save
## cannot reroll it) and runs differ.


## The fixed `event` of the node, otherwise a weighted draw among the events that fit the
## expedition's tags (minus the unique ones already seen). Null if nothing can be drawn:
## the caller shows a plain message and validation already warned about it.
static func pick(expedition: ExpeditionData, node: ExpeditionNode, run: RunState) -> EventData:
	if node.event != null:
		return node.event

	var pool: Array[EventData] = []
	for event in expedition.get_event_pool():
		if event.unique_per_run and run.has_seen_event(event.id):
			continue
		pool.append(event)
	if pool.is_empty():
		return null

	var rng := make_rng(run, node, "event")
	var total := 0.0
	for event in pool:
		total += event.weight
	var roll := rng.randf() * total
	for event in pool:
		roll -= event.weight
		if roll < 0.0:
			return event
	return pool.back()


## A random number generator for this node. `salt` separates the uses ("event" for the draw,
## "outcome" for the random results of the chosen option).
static func make_rng(run: RunState, node: ExpeditionNode, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:%s" % [run.rng_seed, node.id, salt])
	return rng
