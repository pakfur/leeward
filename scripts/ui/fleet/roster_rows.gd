class_name RosterRows
extends RefCounted
## The player roster of the side panel: one row per player, human or AI, with what that player
## is doing now. Pure statics over read-only game state; no server call, no state written.
## A player's replay is known only to the local client, so only the local player is ever
## "resolving" (networking will report the others later).

const PLANNING := "planning"
const DECLARING := "declaring"
const READY := "ready"
const RESOLVING := "resolving"
const REVIEWING := "reviewing"
const ENDED_TURN := "ended_turn"
const WAITING := "waiting"
const NO_SHIPS := "no_ships"

const LABELS := {
	PLANNING: "planning",
	DECLARING: "declaring",
	READY: "ready",
	RESOLVING: "resolving",
	REVIEWING: "reviewing",
	ENDED_TURN: "ended turn",
	WAITING: "waiting",
	NO_SHIPS: "no ships",
}


## Rows in player-id order: {id, name, side, is_ai, is_local, state, ships} (ships = in play).
static func rows(game_state, local_player_id: int, local_resolving: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in game_state.player_ids():
		var player: PlayerState = game_state.players.get(id)
		var is_local: bool = id == local_player_id
		var is_ai: bool = player != null and player.is_ai
		var player_name: String = "Player %d" % id
		if player != null and player.name != "":
			player_name = player.name
		if is_local:
			player_name = "You"
		var ships: int = game_state.in_play_ships_of_player(id).size()
		out.append({
			"id": id,
			"name": player_name,
			"side": player.side if player != null else id,
			"is_ai": is_ai,
			"is_local": is_local,
			"state": _state(game_state, id, is_ai, is_local and local_resolving, ships),
			"ships": ships,
		})
	return out


static func state_label(state: String) -> String:
	return String(LABELS.get(state, state))


static func _state(game_state, id: int, is_ai: bool, resolving: bool, ships: int) -> String:
	if ships == 0:
		return NO_SHIPS
	if resolving:
		return RESOLVING
	var pc = game_state.phase_controller
	match pc.current_phase:
		TurnPhaseController.GamePhase.PLANNING:
			return READY if pc.is_player_ready(id) else PLANNING
		TurnPhaseController.GamePhase.COMBAT_RESOLUTION:
			if pc.combat_step == TurnPhaseController.CombatStep.DECLARE:
				# The server's per-player "orders in" record, read only (no accessor exists).
				var in_orders: bool = bool(pc._fire_ready.get(id, false))
				return READY if (is_ai or in_orders) else DECLARING
			return WAITING
		TurnPhaseController.GamePhase.POST_COMBAT:
			# AI players are not waited on: they count as done.
			return ENDED_TURN if (is_ai or bool(pc.ended_turn.get(id, false))) else REVIEWING
		_:
			return WAITING
