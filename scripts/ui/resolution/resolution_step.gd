class_name ResolutionStep
extends RefCounted
## One step of the resolution replay: a roll (or a prompt) and what came of it. Made by
## `ResolutionSteps.build`; plain data, view only.

var kind: String = ""
var phase: int = 0
var ship_id: String = ""
var target_id: String = ""
## The events folded into the step: the lead event first.
var events: Array[PhaseEvents.PhaseEvent] = []
## Indices into the event list given to `ResolutionSteps.build` (first = the lead's).
var first_index: int = 0
var last_index: int = 0
## One entry per die rolled: {"sides": 6|10, "values": Array[int]}. A 2d6 roll is one entry holding
## the total, with "count": 2.
var dice: Array = []
var title: String = ""
## {"label": String, "value": int}, in the order the event gives them.
var modifiers: Array = []
var final_text: String = ""
var outcome_lines: PackedStringArray = PackedStringArray()
## The request for the player's input when the step is a prompt; empty otherwise.
var prompt: Dictionary = {}
