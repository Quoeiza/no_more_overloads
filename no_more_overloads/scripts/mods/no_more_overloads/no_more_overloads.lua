local mod = get_mod("no_more_overloads")

local BuffSettings = require("scripts/settings/buff/buff_settings")
-- Overload immunity keyword.
local PSYCHIC_FORTRESS = BuffSettings.keywords.psychic_fortress
-- Empowered Psionics: blitzes cost no Peril.
local EMPOWERED_GRENADE = BuffSettings.keywords.psyker_empowered_grenade
-- Scrier's Gaze is active.
local SCRIERS_STANCE = BuffSettings.keywords.psyker_overcharge
-- Stance Peril per frame = PASSIVE x (1 + secs/RAMP)^2 x stat buffs. BUFFER = margin below 100%.
local SCRIERS_PASSIVE = 0.00075
local SCRIERS_RAMP = 18
local SCRIERS_BUFFER = 0.01
local SCRIERS_MAX_STACKS = 30
local SCRIERS_BUFF = "psyker_overcharge_stance"
-- Vent delay estimates (seconds): wind-up to heavy, a swing's vent chain, an untimed stream.
local WINDUP_RESOLVE = 0.25
local SWING_VENT_CHAIN = 0.6
local STREAM_WAIT = 1.15
-- Smoothing time for the measured Peril climb.
local CLIMB_TAU = 0.5
-- Kinds whose chain_time is multiplied by time_scale when it is below 1, else divided.
local INVERTED_KINDS = {
	overload_charge = true, overload_charge_position_finder = true, overload_charge_target_finder = true,
	overload_charge_weapon_special = true, overload_target_finder = true,
}
local WarpCharge = require("scripts/utilities/warp_charge")

-- An action overloads only when it pays at 100%. Brain Rupture blocks only its lock, at the
-- game's extreme threshold.
local PERIL_CAP = 0.999
local BRAIN_RUPTURE_EXTREME = 0.97
-- Headroom below that threshold: one fixed frame of climb.
local BRAIN_RUPTURE_HEADROOM = 0.003

-- Auto Fire fires this far below the block threshold.
local AUTO_FIRE_MARGIN = 0.03
-- Charge time before the fire can start (the fire's chain_time).
local AUTO_FIRE_CHAIN_TIME = 0.5
-- Charge actions (staffs, Smite's heavy, the plasma brace) and their fire-transition keys.
local STAFF_CHARGE_ACTIONS = { action_charge = true, action_charge_flame = true }
local STAFF_FIRE_INPUTS = { "trigger_charge_flame", "trigger_explosion", "shoot_charged", "shoot_heavy_hold", "shoot_braced" }
-- Categories whose charged fire can be queued and land later.
local FIRE_GUARD = { staff = true, blitz = true, plasma = true }
local OVERHEAT_CATEGORIES = { plasma = true }
local BLITZ_VARIANT = { psyker_smite = "brain_rupture", psyker_throwing_knives = "assail" }
-- Seconds (plus ping) for a server-only Peril payment or a spent Empowered Psionics stack to
-- reach this client.
local SYNC_MARGIN = 0.15
local EMPOWERED_SETTLE = 0.35
local EMPOWERED_BUFFS = {
	"psyker_empowered_grenades_passive_visual_buff", "psyker_empowered_grenades_passive_visual_buff_increased",
}
-- A stun on the first frame of a plasma hip charge fires it: block the press this close to the cap.
local PLASMA_HIP_MARGIN = 0.004

-- Immunity counts as ended this long (plus ping) early, covering the longest cast.
local IMMUNITY_LEAD = 1.25
local MAX_PING_LEAD = 0.5

-- Margin (plus ping) to force a held cast to conclude before immunity ends.
local CONCLUDE_MARGIN = 0.15

-- Clears the auto-use latch if the press never lands.
local FIRE_LATCH_TIMEOUT = 0.5

-- After a weapon swap, reload stays false this long so the vent input cannot stick.
local WIELD_VENT_GUARD = 0.3

local IDLE_GAME_MODES = { hub = true, prologue_hub = true }

local RECOVERY_ABILITIES = {
	psyker_overcharge_stance = true,          -- Scrier's Gaze
	psyker_discharge_shout = true,            -- Psykinetic's Wrath
	psyker_discharge_shout_improved = true,   -- Venting Shriek
}
local AUTO_USE_SETTING = {
	psyker_overcharge_stance = "auto_use_scriers",         -- Scrier's Gaze
	psyker_discharge_shout = "auto_use_wrath",             -- Psykinetic's Wrath
	psyker_discharge_shout_improved = "auto_use_shriek",   -- Venting Shriek
}

-- Raw inputs blocked at the cap. Held ones are skipped mid-charge: a forced release fires it.
local CATEGORY_INPUTS = {
	staff       = { pressed = { "action_one_pressed" }, held = { "action_one_hold" } },
	-- Aiming and charging (action_two) never overload; only the fire does.
	blitz       = { pressed = { "action_one_pressed" }, held = { "action_one_hold" } },
	-- Only charging the sword pays Peril; swings, charged or not, are free.
	force_sword = { pressed = { "weapon_extra_pressed" }, held = { "weapon_extra_hold" } },
	gun         = { pressed = { "weapon_extra_pressed" }, held = { "weapon_extra_hold" } },
	-- The parry special builds Peril.
	duelling_sword = { pressed = { "weapon_extra_pressed" }, held = { "weapon_extra_hold" } },
	-- Only a braced shot at full heat detonates; the charged-fire guard blocks it.
	plasma = { pressed = {}, held = {} },
}
-- Force-sword holds blocked during a push: adds the fling follow-up.
local FS_HELD_PUSH = { "weapon_extra_hold", "action_one_hold" }
-- Brain Rupture: only action_one_hold starts a locked cast.
local BR_HELD = { "action_one_hold" }

local CAST_HOLDS = { "action_one_hold", "action_two_hold", "weapon_extra_hold" }

-- Quell interrupt categories. Offensive = attacks and anything building Peril.
-- Other = block, sprint and pushes (see push_info).
local OFFENSIVE_PRESSES = { "action_one_pressed", "weapon_extra_pressed", "grenade_ability_pressed" }
local OFFENSIVE_HOLDS = {
	staff = CAST_HOLDS,
	blitz = CAST_HOLDS,
	force_sword = { "action_one_hold", "weapon_extra_hold" }, -- action_two is block
}
local OTHER_HOLDS = { force_sword = { "action_two_hold" } }
-- Presses a running vent swallows; re-sent once it stops.
local REPLAY_PRESSES = { action_one_pressed = true, weapon_extra_pressed = true, sprint = true }
local REPLAY_WINDOW = 0.5
-- Forward input needed for a sprint to start (Sprint.check).
local SPRINT_FORWARD = 0.7
-- Charge and aim kinds: a quell releases them instead of letting them conclude.
local CHARGE_KINDS = {
	overload_charge = true, overload_charge_position_finder = true,
	overload_charge_target_finder = true, smite_targeting = true,
}

-- Categories that quell on reload.
local VENTABLE = { staff = true, force_sword = true, blitz = true }

-- Staff holds released to conclude a cast before immunity ends.
local STAFF_RELEASE = { "action_one_hold", "action_two_hold" }

local InputHandlerSettings = require("scripts/managers/player/player_game_states/input_handler_settings")
local BuffTemplates = require("scripts/settings/buff/buff_templates")
local Sprint = require("scripts/extension_systems/character_state_machine/character_states/utilities/sprint")

-- Plasma vent interrupts: every press action except movement and the vent key itself.
local PLASMA_VENT_KEEP = {
	jump = true, crouch = true, sprint = true, weapon_extra_pressed = true,
}
local PLASMA_VENT_INTERRUPTS = {}
do
	local ephemeral = InputHandlerSettings.ephemeral_actions
	for i = 1, #ephemeral do
		local name = ephemeral[i]
		if not PLASMA_VENT_KEEP[name] and not string.find(name, "_release", 1, true) then
			PLASMA_VENT_INTERRUPTS[#PLASMA_VENT_INTERRUPTS + 1] = name
		end
	end
end

local EMPTY = {}

-- Settings
local cfg = {}

-- Presets are saved as English values; the HUD shows their localized labels.
local WORD_KEYS = {
	BLOCKED = "opt_word_blocked", DANGER = "opt_word_danger", STOP = "opt_word_stop",
	WAIT = "opt_word_wait", HOLD = "opt_word_hold", ["DON'T CAST"] = "opt_word_dontcast",
	GO = "opt_word_go", OK = "opt_word_ok", CLEAR = "opt_word_clear", READY = "opt_word_ready",
	CAST = "opt_word_cast",
}

-- "default" uses the localized SAFE / UNSAFE word.
local function indicator_word(value, default_key)
	if not value or value == "default" then
		return mod:localize(default_key)
	end
	local key = WORD_KEYS[value]
	return key and mod:localize(key) or value
end

local function refresh_settings()
	-- Anything but "strict" is Relaxed.
	cfg.blocking_strict    = mod:get("blocking_type") == "strict"
	cfg.block_staffs       = mod:get("block_staffs")
	cfg.block_blitzes      = mod:get("block_blitzes")
	cfg.block_force_swords = mod:get("block_force_swords")
	cfg.block_force_greatswords = mod:get("block_force_greatswords")
	cfg.block_guns         = mod:get("block_guns")
	cfg.block_crystalline  = mod:get("block_crystalline")
	cfg.block_duelling_swords = mod:get("block_duelling_swords")
	cfg.block_plasma       = mod:get("block_plasma")

	cfg.auto_quell           = mod:get("auto_quell")
	cfg.auto_quell_scriers   = mod:get("auto_quell_scriers")
	cfg.auto_quell_scriers_stacks = mod:get("auto_quell_scriers_stacks")
	cfg.auto_quell_trigger   = mod:get("auto_quell_trigger") or 100
	cfg.quell_interrupt_offensive = mod:get("auto_quell_interrupt_offensive")
	cfg.quell_interrupt_other     = mod:get("auto_quell_interrupt_other")
	cfg.auto_quell_hold      = mod:get("auto_quell_hold")
	cfg.auto_plasma_vent           = mod:get("auto_plasma_vent")
	cfg.auto_plasma_vent_interrupt = mod:get("auto_plasma_vent_interrupt")
	cfg.auto_plasma_vent_hold      = mod:get("auto_plasma_vent_hold")
	cfg.auto_ability         = mod:get("auto_ability")
	cfg.auto_use_scriers     = mod:get("auto_use_scriers")
	cfg.auto_use_shriek      = mod:get("auto_use_shriek")
	cfg.auto_use_wrath       = mod:get("auto_use_wrath")
	cfg.when_to_use          = mod:get("when_to_use")
	cfg.min_peril            = mod:get("min_peril")
	cfg.recover_window       = mod:get("recover_window")
	cfg.auto_fire_before_unsafe = mod:get("auto_fire_before_unsafe")

	cfg.show_unsafe        = mod:get("show_unsafe")
	cfg.show_safe          = mod:get("show_safe")
	cfg.unsafe_color       = { 255, mod:get("unsafe_r"), mod:get("unsafe_g"), mod:get("unsafe_b") }
	cfg.safe_color         = { 255, mod:get("safe_r"), mod:get("safe_g"), mod:get("safe_b") }
	cfg.font_size          = mod:get("font_size")
	cfg.pos_x              = mod:get("pos_x")
	cfg.pos_y              = mod:get("pos_y")

	cfg.word_unsafe = indicator_word(mod:get("unsafe_word"), "txt_unsafe")
	cfg.word_safe = indicator_word(mod:get("safe_word"), "txt_safe")
end

-- One-time settings migration: both quell interrupts on; greatswords inherit the force-sword block.
if (mod:get("settings_version") or 0) < 1 then
	mod:set("auto_quell_interrupt_offensive", true)
	mod:set("auto_quell_interrupt_other", true)
	if mod:get("block_force_swords") == false then
		mod:set("block_force_greatswords", false)
	end
	mod:set("settings_version", 1)
end

mod.on_all_mods_loaded = refresh_settings
mod.on_setting_changed = refresh_settings
refresh_settings()

-- State the HUD element reads.
mod._sc_visible = false
mod._sc_text = nil
mod._sc_color = nil
mod._sc_font_size = cfg.font_size
mod._sc_offset_x = cfg.pos_x
mod._sc_offset_y = cfg.pos_y
-- State the input hooks read. Boundary = Peril at which the block engages; huge = disarmed.
mod._sc_block_boundary = math.huge
mod._sc_block_category = nil
mod._sc_block_overheat = false
mod._sc_pressed = EMPTY
mod._sc_held = EMPTY
mod._sc_release = EMPTY
mod._sc_fire_request = false
mod._sc_quell = false
mod._sc_cast_held = false
mod._sc_offense_held = false
mod._sc_scriers_guard = false
mod._sc_quell_cut = false
mod._sc_quell_interrupted = false
mod._sc_plasma_vent = false
mod._sc_plasma_vent_interrupted = false
mod._sc_wield_guard = 0
mod._sc_last_slot = false
-- Brain Rupture lock boundary; huge = disarmed.
mod._sc_br_boundary = math.huge
mod._sc_autofire_armed = false

mod:register_hud_element({
	class_name = "HudElementNoMoreOverloads",
	filename = "no_more_overloads/scripts/mods/no_more_overloads/HudElementNoMoreOverloads",
	use_hud_scale = true,
	visibility_groups = { "alive" },
})

-- Latest ping in seconds.
local last_ping = 0
mod:hook_safe("PingReporter", "_take_measure", function (self)
	local measures = self._measures
	local latest = measures and measures[#measures]
	if latest then
		last_ping = latest / 1000
	end
end)

-- Fixed-frame time for the input hook. One frame stale, so its gates open late, never early.
local last_fixed_t = 0
mod:hook_safe("HumanInputHandler", "fixed_update", function (self, dt, t)
	last_fixed_t = t
end)

-- Read helpers
local function local_player()
	local pm = Managers.player
	if not pm or not pm.local_player_safe then
		return nil
	end
	-- Returns nil before the connection is up.
	return pm:local_player_safe(1)
end

local function in_active_session()
	local state = Managers.state
	local game_mode = state and state.game_mode
	if not game_mode or not game_mode.game_mode_name then
		return false
	end
	local name = game_mode:game_mode_name()
	return name ~= nil and not IDLE_GAME_MODES[name]
end

local function get_local_unit()
	local player = local_player()
	if not player then
		return nil
	end
	local unit = player.player_unit
	if not unit or not ALIVE[unit] then
		return nil
	end
	local archetype = player.archetype_name and player:archetype_name() or nil
	return unit, archetype
end

-- Wielded weapon's category and variant ("brain_rupture", "assail", "greatsword" or nil).
-- nil if not overload-relevant.
local function classify(unit)
	local weapon_ext = ScriptUnit.has_extension(unit, "weapon_system")
	local template = weapon_ext and weapon_ext:weapon_template()
	local kws = template and template.keywords
	if not kws then
		return nil
	end
	local combat_sword, p3
	for i = 1, #kws do
		local k = kws[i]
		if k == "force_staff" then return "staff" end
		if k == "force_sword" then
			return "force_sword", string.find(template.name or "", "forcesword_2h", 1, true) and "greatsword" or nil
		end
		if k == "laspistol" then return "gun" end
		if k == "plasma_rifle" then return "plasma" end
		if k == "combat_sword" then combat_sword = true end
		if k == "p3" then p3 = true end
	end
	-- combat_sword + p3 is the Duelling Sword, the only one with a Peril parry.
	if combat_sword and p3 then
		return "duelling_sword"
	end
	-- Template psyker_smite is Brain Rupture.
	if #kws == 1 and kws[1] == "psyker" then
		return "blitz", BLITZ_VARIANT[template.name]
	end
	return nil
end

local function block_toggle_for(category, greatsword)
	if category == "staff" then return cfg.block_staffs end
	if category == "blitz" then return cfg.block_blitzes end
	if category == "force_sword" then
		if greatsword then return cfg.block_force_greatswords end
		return cfg.block_force_swords
	end
	if category == "gun" then return cfg.block_guns end
	if category == "duelling_sword" then return cfg.block_duelling_swords end
	if category == "plasma" then return cfg.block_plasma end
	return false
end

-- Seconds until the recovery ability is ready: huge if none, 0 while its regen is paused.
local function recovery_cooldown(unit)
	local ability_ext = ScriptUnit.has_extension(unit, "ability_system")
	if not ability_ext or not ability_ext:ability_is_equipped("combat_ability") then
		return math.huge
	end
	if not RECOVERY_ABILITIES[ability_ext:ability_name("combat_ability")] then
		return math.huge
	end
	if not ability_ext:ability_enabled("combat_ability") then
		return math.huge
	end
	if ability_ext:is_ability_resource_regen_paused("combat_ability") then
		return 0
	end
	return ability_ext:missing_ability_resource_until_next_charge("combat_ability") or math.huge
end

local function auto_use_enabled(unit)
	if not cfg.auto_ability then
		return false
	end
	local ability_ext = ScriptUnit.has_extension(unit, "ability_system")
	if not ability_ext or not ability_ext:ability_is_equipped("combat_ability") then
		return false
	end
	local setting = AUTO_USE_SETTING[ability_ext:ability_name("combat_ability")]
	return (setting and cfg[setting]) or false
end

-- Crystalline Will makes overload non-lethal.
local function has_crystalline_will(unit)
	local talent_ext = ScriptUnit.has_extension(unit, "talent_system")
	if not talent_ext then
		return false
	end
	return talent_ext:has_special_rule("psyker_no_knock_down_overload") and true or false
end

-- Seconds of overload immunity left; huge if indefinite.
local function immunity_remaining(buff_ext)
	local buffs = (buff_ext.buffs and buff_ext:buffs()) or buff_ext._buffs_by_index
	if not buffs then
		return math.huge
	end
	local max_remaining = 0
	for _, buff in pairs(buffs) do
		local template = buff.template and buff:template()
		local keywords = template and template.keywords
		if keywords then
			local fortress = false
			for i = 1, #keywords do
				if keywords[i] == PSYCHIC_FORTRESS then
					fortress = true
					break
				end
			end
			if fortress then
				local duration = buff.duration and buff:duration()
				local progress = buff.duration_progress and buff:duration_progress()
				if duration and progress and duration > 0 then
					local remaining = duration * progress
					if remaining > max_remaining then
						max_remaining = remaining
					end
				else
					return math.huge
				end
			end
		end
	end
	return max_remaining
end

-- Auto Ability Use: one latched ability press. Reactive fires on overload, Proactive once ready.
local fire_latched = false
local latch_timer = 0
local latch_saw_unusable = false
-- Auto Fire latch: one press per charge.
local autofire_latched = false
-- Quell pause held by an offensive interrupt, and the press awaiting re-send.
local quell_offense_pause = false
local quell_replay = nil
local quell_replay_until = 0
-- Weapon the press was made on; a swap drops it.
local quell_replay_template = nil
-- Last fixed frame's meter while a charge-and-fire weapon is wielded, and the fastest one-frame
-- climb of the running charge (its start time identifies it).
local fire_prev = false
local fire_climb_t = false
local fire_climb = 0
-- Peril the running action still owes: its instance, the meter at its start, its cost, and when
-- the meter must show it by.
local pending = { start_t = false, base = 0, cost = 0, until_t = 0 }
local pending_now = 0
-- Start times of the last blitz casts that spend an Empowered Psionics stack.
local blitz_fire_ts = {}

-- Whether an Empowered Psionics stack is certainly unspent: stacks seen here, less the recent
-- casts whose spent stack may not have reached this client yet.
local function empowered_free(buff_ext)
	if not (EMPOWERED_GRENADE and buff_ext:has_keyword(EMPOWERED_GRENADE)) then
		return false
	end
	local settle = EMPOWERED_SETTLE + math.min(last_ping, 1)
	local recent = 0
	for i = 1, #blitz_fire_ts do
		local since = last_fixed_t - blitz_fire_ts[i]
		if since >= 0 and since <= settle then
			recent = recent + 1
		end
	end
	local stacks = 1
	if buff_ext.current_stacks then
		for i = 1, #EMPOWERED_BUFFS do
			-- The buff briefly holds one stack over its cap (max_stacks - 1) when a gain overflows.
			local buff_template = rawget(BuffTemplates, EMPOWERED_BUFFS[i])
			local cap = buff_template and buff_template.max_stacks and buff_template.max_stacks - 1 or 1
			stacks = math.max(stacks, math.min(buff_ext:current_stacks(EMPOWERED_BUFFS[i]) or 0, cap))
		end
	end
	return stacks - recent >= 1
end

local function update_auto_ability(unit, overloading, peril, dt)
	if not auto_use_enabled(unit) then
		fire_latched = false
		return
	end
	local ability_ext = ScriptUnit.has_extension(unit, "ability_system")
	local can_use = ability_ext:can_use_ability("combat_ability")

	if fire_latched then
		latch_timer = latch_timer + dt
		if not can_use then
			latch_saw_unusable = true
		end
		if (latch_saw_unusable and can_use) or latch_timer > FIRE_LATCH_TIMEOUT then
			fire_latched = false
		end
	end

	-- Proactive also fires when no cast is held and Peril is over the minimum.
	local trigger = overloading
	if cfg.when_to_use == "proactive" then
		trigger = trigger or (not mod._sc_cast_held and peril >= cfg.min_peril / 100)
	end

	if trigger and can_use and not fire_latched then
		mod._sc_fire_request = true
		fire_latched = true
		latch_timer = 0
		latch_saw_unusable = false
	end
end

-- Whether to vent this frame: while needed or in the band, then for hold_amount after.
-- Shared by quelling and plasma venting.
local function update_vent(state, venting_needed, band_needed, allowed, minimum, hold_amount, interrupted, dt)
	if not allowed then
		state.hold_timer = 0
		return false
	end
	if venting_needed then
		-- Keep the follow-through full, or empty while an interrupting key is held.
		state.hold_timer = minimum and 0 or hold_amount
		return true
	end
	if interrupted then
		state.hold_timer = 0
	end
	if band_needed then
		return true
	end
	if state.hold_timer > 0 then
		state.hold_timer = state.hold_timer - dt
		return true
	end
	return false
end

local quell_state = { hold_timer = 0 }
local plasma_vent_state = { hold_timer = 0 }

-- Holds a running attack still needs to conclude (attack_keep), cached per action.
local WINDUP_KEEP = { action_one_hold = true, action_two_hold = true, weapon_extra_hold = true }
local attack_keep_cache = setmetatable({}, { __mode = "k" })

-- Raw keys whose release stops the action, as a set, or false.
local function stop_keys(template, action)
	local stop = action.stop_input
	local stop_config = stop and template.action_inputs and template.action_inputs[stop]
	local sequence = stop_config and stop_config.input_sequence
	local element = type(sequence) == "table" and sequence[1]
	local list = element and (element.inputs or { element }) or EMPTY
	local keys = false
	for i = 1, #list do
		if list[i].value == false and list[i].input then
			keys = keys or {}
			keys[list[i].input] = true
		end
	end
	return keys
end

local function node_lists_vent(template, start_input)
	local hierarchy = template.action_input_hierarchy or EMPTY
	for i = 1, #hierarchy do
		local entry = hierarchy[i]
		if entry.input == start_input and type(entry.transition) == "table" then
			for j = 1, #entry.transition do
				if entry.transition[j].input == "vent" then
					return true
				end
			end
		end
	end
	return false
end

local function attack_keep(template, action_name, category)
	local actions = template and template.actions
	local action = action_name and actions and actions[action_name]
	if not action then
		return nil
	end
	local cached = attack_keep_cache[action]
	if cached ~= nil then
		return cached or nil
	end
	local keep = false
	local kind = action.kind
	-- A locked Brain Rupture cast counts as an attack; target_finder is an aim only on blitzes.
	local locked = action_name == "action_charge_target_sticky" or action_name == "action_charge_target_lock_on"
	if kind == "windup" then
		keep = WINDUP_KEEP
	elseif locked or not (CHARGE_KINDS[kind] or (kind == "target_finder" and category == "blitz")) then
		keep = stop_keys(template, action)
	else
		local vent = action.allowed_chain_actions and action.allowed_chain_actions.vent
		if vent and (vent.chain_time or 0) <= (action.minimum_hold_time or 0)
			and node_lists_vent(template, action.start_input) then
			keep = stop_keys(template, action)
		end
	end
	attack_keep_cache[action] = keep
	return keep or nil
end

-- Seconds the running action delays a vent. `cut` treats release-stoppable attacks as released.
local function vent_wait(template, weapon_action, t, category, cut)
	local name = weapon_action and weapon_action.current_action_name
	local actions = template and template.actions
	local action = name and name ~= "none" and actions and actions[name]
	if not action or action.kind == "vent_warp_charge" then
		return 0
	end
	local kind = action.kind
	local elapsed = math.max(0, t - (weapon_action.start_t or t))
	if kind == "windup" then
		return math.max(0, WINDUP_RESOLVE - elapsed) + SWING_VENT_CHAIN
	end
	local charge = CHARGE_KINDS[kind] or (kind == "target_finder" and category == "blitz")
	local releasable = kind == "block" or (charge and not attack_keep(template, name, category))
		or (cut and not charge and stop_keys(template, action))
	if releasable then
		return math.max(0, (action.minimum_hold_time or 0) - elapsed)
	end
	local chain = action.allowed_chain_actions and action.allowed_chain_actions.vent
	if chain then
		local ts = weapon_action.time_scale or 1
		local chain_time = chain.chain_time or 0
		local gate = (ts < 1 and INVERTED_KINDS[kind]) and chain_time * ts or chain_time / ts
		return math.max(0, gate - elapsed)
	end
	if not weapon_action.is_infinite_duration and weapon_action.end_t then
		return math.max(0, weapon_action.end_t - t)
	end
	local stop = action.stop_time
	stop = type(stop) == "table" and math.max(stop[1] or 0, stop[2] or 0) or stop or STREAM_WAIT
	return math.max(0, stop - elapsed)
end

-- Scrier's model: lead to a vent's first drop, passive climb before the ramp, Peril stat-buff scale.
local scriers_model = { base_lead = 0, per_second = 0, scale = 1, secs = 0 }

local function update_scriers_model(unit, buff_ext, stance_secs, dt)
	local player = local_player()
	local game_session = Managers.state.game_session
	local fixed_dt = game_session and game_session.fixed_time_step or (1 / 52)
	local archetype_template = player and WarpCharge.archetype_warp_charge_template(player)
	local weapon_template = WarpCharge.weapon_warp_charge_template(unit)
	local first_drop = (archetype_template and archetype_template.vent_interval or 0.25)
		* (weapon_template and weapon_template.vent_interval_modifier or 1)
	local stat_buffs = buff_ext:stat_buffs()
	local scale = (stat_buffs and stat_buffs.warp_charge_amount or 1)
		* (stat_buffs and stat_buffs.warp_charge_immediate_amount or 1)
	scriers_model.base_lead = dt + 2 * fixed_dt + first_drop
	scriers_model.per_second = SCRIERS_PASSIVE * scale / fixed_dt
	scriers_model.scale = scale
	scriers_model.secs = stance_secs
end

-- Stance's passive climb (Peril/s) `ahead` seconds from now.
local function scriers_passive(ahead)
	local ramp = 1 + (scriers_model.secs + ahead) / SCRIERS_RAMP
	return scriers_model.per_second * ramp * ramp
end

-- Peril at which quelling must start for the vent's first drop to land before 100%.
local function scriers_quell_point(unit_data, template, category, climb)
	local weapon_action = unit_data:read_component("weapon_action")
	local wait = vent_wait(template, weapon_action, last_fixed_t, category, true)
	local lead = scriers_model.base_lead + wait
	local attack = math.max(0, climb - scriers_passive(0))
	return 1 - SCRIERS_BUFFER - scriers_passive(lead) * lead - attack * wait
end

-- Precognition stacks: the buff's count, at least the time-based one.
local function scriers_stacks(buff_ext, stance_secs)
	local count = math.min(SCRIERS_MAX_STACKS, math.ceil(stance_secs))
	local buffs = buff_ext.buffs and buff_ext:buffs()
	if buffs then
		for _, buff in pairs(buffs) do
			if buff.template_name and buff:template_name() == SCRIERS_BUFF and buff.visual_stack_count then
				count = math.max(count, buff:visual_stack_count() or 0)
			end
		end
	end
	return count
end

local scriers_secs = 0
local scriers_prev_peril = false
local scriers_climb = 0

-- Per-frame update
local function clear_state()
	mod._sc_visible = false
	mod._sc_block_boundary = math.huge
	mod._sc_block_category = nil
	mod._sc_block_overheat = false
	mod._sc_pressed = EMPTY
	mod._sc_held = EMPTY
	mod._sc_release = EMPTY
	mod._sc_fire_request = false
	mod._sc_quell = false
	mod._sc_cast_held = false
	mod._sc_offense_held = false
	mod._sc_scriers_guard = false
	mod._sc_quell_cut = false
	mod._sc_quell_interrupted = false
	mod._sc_plasma_vent = false
	mod._sc_plasma_vent_interrupted = false
	mod._sc_autofire_armed = false
	fire_latched = false
	autofire_latched = false
	quell_offense_pause = false
	quell_replay = nil
	fire_prev, fire_climb_t, fire_climb = false, false, 0
	pending.start_t, pending.until_t, pending_now = false, 0, 0
	blitz_fire_ts[1], blitz_fire_ts[2], blitz_fire_ts[3] = nil, nil, nil
	quell_state.hold_timer = 0
	plasma_vent_state.hold_timer = 0
	scriers_secs, scriers_prev_peril, scriers_climb = 0, false, 0
	mod._sc_wield_guard = 0
	mod._sc_last_slot = false
	mod._sc_br_boundary = math.huge
end

mod.update = function (dt)
	if not mod:is_enabled() or not in_active_session() then
		clear_state()
		return
	end

	local unit, archetype = get_local_unit()
	if not unit then
		clear_state()
		return
	end

	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
	if not unit_data or not buff_ext then
		clear_state()
		return
	end

	-- A weapon swap opens the reload-false window.
	local wield_inv = unit_data:read_component("inventory")
	local wielded_slot = wield_inv and wield_inv.wielded_slot
	if wielded_slot ~= mod._sc_last_slot then
		mod._sc_last_slot = wielded_slot
		mod._sc_wield_guard = WIELD_VENT_GUARD
	elseif mod._sc_wield_guard > 0 then
		mod._sc_wield_guard = math.max(0, mod._sc_wield_guard - dt)
	end

	local category, variant = classify(unit)
	local is_brain_rupture = variant == "brain_rupture"
	local is_overheat = category and OVERHEAT_CATEGORIES[category] or false

	-- Plasma runs for any class if either plasma feature is on; Peril weapons are Psyker-only.
	if is_overheat then
		if not cfg.block_plasma and not cfg.auto_plasma_vent then
			clear_state()
			return
		end
	elseif archetype ~= "psyker" then
		clear_state()
		return
	end

	local peril, charging, overloading
	local immune, effectively_immune, force_conclude, crystalline, cd
	local in_stance = false
	if is_overheat then
		-- Overheat is on the wielded slot's component.
		local inv = unit_data:read_component("inventory")
		local slot_name = inv and inv.wielded_slot
		local slot = slot_name and slot_name ~= "none" and unit_data:read_component(slot_name)
		peril = slot and slot.overheat_current_percentage or 0
		charging = slot and slot.overheat_state == "increasing" or false
		overloading = slot and slot.overheat_state == "exploding" or false
		immune, effectively_immune, force_conclude, crystalline, cd = false, false, false, false, math.huge
	else
		local warp_charge = unit_data:read_component("warp_charge")
		peril = warp_charge.current_percentage or 0
		charging = warp_charge.state == "increasing"
		overloading = warp_charge.state == "exploding"
		immune = buff_ext:has_keyword(PSYCHIC_FORTRESS)
		in_stance = SCRIERS_STANCE ~= nil and buff_ext:has_keyword(SCRIERS_STANCE) or false
		-- Strict never trusts the recovery ability.
		cd = cfg.blocking_strict and math.huge or recovery_cooldown(unit)
		crystalline = has_crystalline_will(unit)
		-- Immunity counts as gone `lead` seconds early.
		local ping_lead = math.min(last_ping, MAX_PING_LEAD)
		local imm_remaining = immune and immunity_remaining(buff_ext) or math.huge
		local lead = IMMUNITY_LEAD + ping_lead
		effectively_immune = immune and imm_remaining >= lead
		-- Immunity about to end: force a held staff cast to conclude now.
		force_conclude = immune and imm_remaining < ping_lead + CONCLUDE_MARGIN
	end

	-- Empowered Psionics makes a Brain Rupture or Assail cast free.
	local empowered = (is_brain_rupture or variant == "assail") and empowered_free(buff_ext)
	local threshold = PERIL_CAP
	-- Assail keeps its block armed: block_engaged_now lifts it live while a stack is left.
	local block_threshold = PERIL_CAP
	if empowered then
		threshold = math.huge
		block_threshold = is_brain_rupture and math.huge or PERIL_CAP
	elseif is_brain_rupture then
		-- Safe when locked below 1 - (1 - extreme) x warp_charge_amount.
		local stat_buffs = buff_ext:stat_buffs()
		local warp_charge_amount = (stat_buffs and stat_buffs.warp_charge_amount) or 1
		threshold = 1 - (1 - BRAIN_RUPTURE_EXTREME) * warp_charge_amount - BRAIN_RUPTURE_HEADROOM
		block_threshold = threshold
	end

	local at_cap = category ~= nil and not effectively_immune and peril >= threshold
	-- UNSAFE: at the cap with no recovery in time, or already overloading.
	local unsafe = (at_cap and cd > cfg.recover_window) or overloading

	-- Block armed. The Peril comparison itself runs live on the fixed frame (block_engaged_now).
	local block_armed = category ~= nil and not effectively_immune and not overloading
		and cd > cfg.recover_window and block_toggle_for(category, variant == "greatsword")
		and not (crystalline and not cfg.block_crystalline)
	mod._sc_block_boundary = block_armed and block_threshold or math.huge
	mod._sc_block_category = category
	mod._sc_block_overheat = is_overheat
	-- Brain Rupture's lock gets its own live check, which skips a running locked cast.
	local br_armed = is_brain_rupture and block_armed
	mod._sc_br_boundary = br_armed and threshold or math.huge
	local sets = category and CATEGORY_INPUTS[category]
	mod._sc_pressed = (block_armed and sets) and sets.pressed or EMPTY
	local held = (block_armed and not charging and sets) and sets.held or EMPTY
	if is_brain_rupture then
		-- Block only the lock key, and never inside a running locked cast.
		local weapon_action = unit_data:read_component("weapon_action")
		local action_name = weapon_action and weapon_action.current_action_name
		local in_locked_cast = action_name == "action_charge_target_sticky"
			or action_name == "action_charge_target_lock_on"
		held = (block_armed and not in_locked_cast) and BR_HELD or EMPTY
	elseif held ~= EMPTY and category == "force_sword" then
		-- Also block the fling follow-up during a push.
		local weapon_action = unit_data:read_component("weapon_action")
		if weapon_action and weapon_action.current_action_name == "action_push" then
			held = FS_HELD_PUSH
		end
	end
	mod._sc_held = held
	-- Releases that conclude a staff cast as immunity ends; not queue-gated.
	mod._sc_release = (block_armed and force_conclude and category == "staff") and STAFF_RELEASE or EMPTY

	-- Track the stance. Quell only below the configured Precognition stacks.
	if in_stance then
		scriers_secs = scriers_secs + dt
		if scriers_prev_peril and dt > 0 then
			local climb_now = math.max(0, peril - scriers_prev_peril) / dt
			scriers_climb = scriers_climb + (climb_now - scriers_climb) * math.min(1, dt / CLIMB_TAU)
		end
		scriers_prev_peril = peril
	else
		scriers_secs, scriers_prev_peril, scriers_climb = 0, false, 0
	end
	local stance_secs = scriers_secs + math.min(last_ping, MAX_PING_LEAD)
	local scriers = cfg.auto_quell_scriers and in_stance
		and scriers_stacks(buff_ext, stance_secs) < (cfg.auto_quell_scriers_stacks or SCRIERS_MAX_STACKS) or false

	-- Skipped under immunity and Crystalline Will, except for the Scrier's quell.
	local quell_allowed = cfg.auto_quell and not overloading and VENTABLE[category]
		and (scriers or (not immune and not (crystalline and not cfg.block_crystalline))) or false
	-- Scrier's limit: the latest safe start point, or the start value if lower.
	local scriers_limit = false
	if scriers then
		update_scriers_model(unit, buff_ext, stance_secs, dt)
		local weapon_ext = ScriptUnit.has_extension(unit, "weapon_system")
		local point = scriers_quell_point(unit_data, weapon_ext and weapon_ext:weapon_template(), category, scriers_climb)
		scriers_limit = peril >= math.min(cfg.auto_quell_trigger * 0.01, point)
	end
	-- The guard swallows stance-ending staff shots; the cut ends an attack a release can stop.
	mod._sc_scriers_guard = scriers and not cfg.quell_interrupt_offensive or false
	mod._sc_quell_cut = scriers_limit
	-- Custom start value, capped at the category threshold. Yields to a held offensive interrupt.
	local quell_threshold = math.min(cfg.auto_quell_trigger * 0.01, threshold)
	local quell_band = category ~= nil and not effectively_immune and peril >= quell_threshold
		and cd > cfg.recover_window and not overloading
		and not (cfg.quell_interrupt_offensive and mod._sc_offense_held) or false
	local quell_interrupted = mod._sc_quell_interrupted
	mod._sc_quell_interrupted = false
	mod._sc_quell = update_vent(quell_state, unsafe or scriers_limit, quell_band, quell_allowed,
		cfg.quell_interrupt_offensive and mod._sc_offense_held, cfg.auto_quell_hold, quell_interrupted, dt)

	-- Plasma venting: hold the weapon special while UNSAFE.
	local plasma_vent_allowed = cfg.auto_plasma_vent and is_overheat and not overloading or false
	local plasma_vent_interrupted = mod._sc_plasma_vent_interrupted
	mod._sc_plasma_vent_interrupted = false
	-- No held-key minimum: the plasma vent overrides a held brace.
	mod._sc_plasma_vent = update_vent(plasma_vent_state, unsafe, false, plasma_vent_allowed,
		false, cfg.auto_plasma_vent_hold, plasma_vent_interrupted, dt)

	-- The Psyker ability does nothing for overheat.
	if not is_overheat then
		update_auto_ability(unit, overloading, peril, dt)
	end

	-- Auto Fire is armed here; the input hook gates the press live.
	mod._sc_autofire_armed = cfg.auto_fire_before_unsafe and category == "staff"
		and not overloading and block_toggle_for(category) and not effectively_immune
		and cd > cfg.recover_window and not (crystalline and not cfg.block_crystalline)
		and peril >= threshold - AUTO_FIRE_MARGIN * 2

	-- The indicator shows real recoverability, even under Strict.
	local shown_unsafe = overloading or (at_cap and (is_overheat or recovery_cooldown(unit) > cfg.recover_window))
	if shown_unsafe and cfg.show_unsafe then
		mod._sc_visible = true
		mod._sc_text = cfg.word_unsafe
		mod._sc_color = cfg.unsafe_color
	elseif not shown_unsafe and cfg.show_safe then
		mod._sc_visible = true
		mod._sc_text = cfg.word_safe
		mod._sc_color = cfg.safe_color
	else
		mod._sc_visible = false
	end
	mod._sc_font_size = cfg.font_size
	mod._sc_offset_x = cfg.pos_x
	mod._sc_offset_y = cfg.pos_y
end

-- Input hooks. The local input cache is predicted and sent, so edits are desync-safe.
local function set_input(cache, lookup, name, index, value)
	local idx = lookup[name]
	local slot = idx and cache[idx]
	if slot then
		slot[index] = value
	end
end

local function get_input(cache, lookup, name, index)
	local idx = lookup[name]
	local slot = idx and cache[idx]
	return slot and slot[index]
end

-- Live Peril, or heat for an overheat weapon.
local function meter(unit_data, overheat)
	if overheat then
		local inv = unit_data:read_component("inventory")
		local slot_name = inv and inv.wielded_slot
		local slot = slot_name and slot_name ~= "none" and unit_data:read_component(slot_name)
		return slot and slot.overheat_current_percentage or 0
	end
	local warp_charge = unit_data:read_component("warp_charge")
	return warp_charge and warp_charge.current_percentage or 0
end

-- Peril one immediate payment adds, as WarpCharge.increase_immediate computes it.
local function immediate_cost(charge_template, buff_ext, charge_level)
	local percent = charge_template.warp_charge_percent
	if type(percent) == "table" then
		percent = math.max(percent.lerp_basic or 0, percent.lerp_perfect or 0)
	end
	if type(percent) ~= "number" then
		return 0
	end
	local stat_buffs = buff_ext:stat_buffs() or EMPTY
	local scale = (stat_buffs.warp_charge_amount or 1) * (stat_buffs.warp_charge_immediate_amount or 1)
	if charge_template.psyker_smite then
		scale = scale * (stat_buffs.psyker_smite_cost_multiplier or 1) * (stat_buffs.warp_charge_amount_smite or 1)
	end
	return percent * (charge_template.use_charge and charge_level or 1) * scale
end

-- Meter per second a charge action adds at its fastest; huge if it cannot be read.
local function charge_rate(weapon_ext, buff_ext, action, overheat)
	local charge_template = action and action.charge_template and weapon_ext._weapon_tweak_template
		and weapon_ext:_weapon_tweak_template("charge", action.charge_template)
	if not charge_template then
		return math.huge
	end
	local percent = overheat and charge_template.overheat_percent or charge_template.warp_charge_percent
	local duration = charge_template.charge_duration
	if type(percent) == "table" then
		percent = math.max(percent.lerp_basic or 0, percent.lerp_perfect or 0)
	end
	if type(duration) == "table" then
		duration = math.min(duration.lerp_basic or math.huge, duration.lerp_perfect or math.huge)
	end
	if type(percent) ~= "number" or type(duration) ~= "number" or duration <= 0 or duration == math.huge then
		return math.huge
	end
	local stat_buffs = buff_ext:stat_buffs() or EMPTY
	if overheat then
		return percent / duration * (stat_buffs.overheat_amount or 1) * (stat_buffs.overheat_over_time_amount or 1)
	end
	local scale = (stat_buffs.warp_charge_amount or 1) * (stat_buffs.warp_charge_over_time_amount or 1)
	if charge_template.psyker_smite then
		scale = scale * (stat_buffs.psyker_smite_cost_multiplier or 1)
	end
	return percent / duration * scale
end

-- Per fixed frame: Peril the running action still owes (pending_now). A projectile pays at its
-- fire time; a force-sword fling and a blocked parry pay on the server only, so the meter lags
-- by ping. Also records blitz casts for empowered_free.
local function track_running_action()
	pending_now = 0
	local category = mod._sc_block_category
	if not category or mod._sc_block_overheat then
		return
	end
	local player = local_player()
	local unit = player and player.player_unit
	local unit_data = unit and ALIVE[unit] and ScriptUnit.has_extension(unit, "unit_data_system")
	local weapon_ext = unit_data and ScriptUnit.has_extension(unit, "weapon_system")
	local buff_ext = weapon_ext and ScriptUnit.has_extension(unit, "buff_system")
	if not buff_ext then
		return
	end
	local t = last_fixed_t
	local weapon_action = unit_data:read_component("weapon_action")
	local template = weapon_ext:weapon_template()
	local name = weapon_action and weapon_action.current_action_name
	local action = name and template and template.actions and template.actions[name]
	local kind = action and action.charge_template and action.kind
	local live = meter(unit_data, false)
	local sync = math.min(last_ping, 1) + SYNC_MARGIN
	if kind == "spawn_projectile" or kind == "damage_target" or kind == "block" then
		local start_t = weapon_action.start_t or t
		local charge_template = weapon_ext:charge_template()
		if pending.start_t ~= start_t then
			pending.start_t, pending.base, pending.cost, pending.until_t = start_t, live, 0, 0
			if kind ~= "block" and category == "blitz" then
				blitz_fire_ts[3], blitz_fire_ts[2], blitz_fire_ts[1] = blitz_fire_ts[2], blitz_fire_ts[1], start_t
			end
			if charge_template and kind == "spawn_projectile" then
				local charge = action.use_charge and unit_data:read_component("action_module_charge")
				local game_session = Managers.state.game_session
				local fixed_dt = game_session and game_session.fixed_time_step or (1 / 52)
				pending.cost = immediate_cost(charge_template, buff_ext, charge and charge.charge_level or 1)
				pending.until_t = start_t + (action.fire_time or 0.1) / (weapon_action.time_scale or 1) + 2 * fixed_dt
			elseif charge_template and kind == "damage_target" and category == "force_sword" then
				-- A fling with no target pays nothing.
				local target = unit_data:read_component("action_module_target_finder")
				if target and target.target_unit_1 then
					pending.cost = immediate_cost(charge_template, buff_ext, 1)
					pending.until_t = start_t + (action.pay_warp_charge_time or 0.5) + sync
				end
			end
		end
		if kind == "block" and charge_template then
			local block = unit_data:read_component("block")
			if block and block.has_blocked then
				pending.cost = immediate_cost(charge_template, buff_ext, 1)
				pending.until_t = t + sync
			end
		end
	end
	if t <= pending.until_t then
		pending_now = math.max(0, pending.base + pending.cost - live)
	end
end

-- Live cap test on the fixed frame, reading the Peril the cast start will snapshot plus what the
-- running action still owes.
local function block_engaged_now()
	if mod._sc_block_boundary >= math.huge then
		return false
	end
	local player = local_player()
	local unit = player and player.player_unit
	if not unit or not ALIVE[unit] then
		return false
	end
	-- A mid-hitch swap must not block the new weapon.
	local category, variant = classify(unit)
	if category ~= mod._sc_block_category then
		return false
	end
	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data then
		return false
	end
	-- An Empowered Psionics Assail throw is free.
	if variant == "assail" then
		local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
		if buff_ext and empowered_free(buff_ext) then
			return false
		end
	end
	return meter(unit_data, mod._sc_block_overheat) + pending_now >= mod._sc_block_boundary
end

-- Whether any of `interrupts` is pressed this frame.
local function player_taking_action(cache, lookup, index, interrupts)
	for i = 1, #interrupts do
		if get_input(cache, lookup, interrupts[i], index) then
			return true
		end
	end
	return false
end

-- Whether a raw input is cap-blocked. Release inputs are excluded so their conclude action survives.
local function raw_is_blocked(raw)
	local pressed = mod._sc_pressed
	for i = 1, #pressed do
		if pressed[i] == raw then return true end
	end
	local held = mod._sc_held
	for i = 1, #held do
		if held[i] == raw then return true end
	end
	return false
end

-- First of `names` set this frame, or nil.
local function first_input(cache, lookup, index, names)
	for i = 1, #names do
		if get_input(cache, lookup, names[i], index) then
			return names[i]
		end
	end
	return nil
end

local function axis(cache, lookup, name, index)
	local value = get_input(cache, lookup, name, index)
	return type(value) == "number" and value or 0
end

-- The sprint input that would start a sprint this frame, or nil.
local function sprint_input(cache, lookup, index)
	if axis(cache, lookup, "move_forward", index) - axis(cache, lookup, "move_backward", index) < SPRINT_FORWARD then
		return nil
	end
	if get_input(cache, lookup, "hold_to_sprint", index) then
		return get_input(cache, lookup, "sprinting", index) and "sprinting" or nil
	end
	return get_input(cache, lookup, "sprint", index) and "sprint" or nil
end

-- Staff's primary fire action name, cached.
local primary_fire_cache = setmetatable({}, { __mode = "k" })

local function primary_fire(actions)
	local cached = primary_fire_cache[actions]
	if cached == nil then
		cached = false
		for name, action in pairs(actions) do
			if action.start_input == "shoot_pressed" then
				cached = name
				break
			end
		end
		primary_fire_cache[actions] = cached
	end
	return cached or nil
end

-- Whether sprinting keeps the charge's fire from starting (Surge).
local function sprint_blocks_fire(unit, unit_data, action_name)
	local sprint = unit_data:read_component("sprint_character_state")
	if not (sprint and Sprint.is_sprinting(sprint)) then
		return false
	end
	local weapon_ext = ScriptUnit.has_extension(unit, "weapon_system")
	local template = weapon_ext and weapon_ext:weapon_template()
	local actions = template and template.actions
	local chains = actions and actions[action_name] and actions[action_name].allowed_chain_actions
	if chains then
		for i = 1, #STAFF_FIRE_INPUTS do
			local fire = chains[STAFF_FIRE_INPUTS[i]]
			if fire then
				local settings = fire.action_name and actions[fire.action_name]
				return settings ~= nil and not settings.allowed_during_sprint and not settings.buff_keywords
			end
		end
	end
	return false
end

-- Last fixed frame's Peril for the Scrier's guard; false when untracked.
local scriers_guard_prev = false
local guard_weapon_action = {}

-- Whether a staff fire press now would end Scrier's Gaze: Peril + climb until the fire gate
-- + shot cost + stance climb until a vent bites.
local function scriers_shot_ends_stance(unit, unit_data, live, climb)
	local weapon_ext = ScriptUnit.has_extension(unit, "weapon_system")
	local template = weapon_ext and weapon_ext:weapon_template()
	local actions = template and template.actions
	local weapon_action = unit_data:read_component("weapon_action")
	if not actions or not weapon_action then
		return false
	end
	local current = weapon_action.current_action_name
	local fire_name, gate = nil, 0
	if STAFF_CHARGE_ACTIONS[current] and actions[current] then
		local chains = actions[current].allowed_chain_actions
		for i = 1, #STAFF_FIRE_INPUTS do
			local fire = chains and chains[STAFF_FIRE_INPUTS[i]]
			if fire then
				fire_name = fire.action_name
				local ts = weapon_action.time_scale or 1
				local chain_time = fire.chain_time or 0
				local open = (ts < 1) and (chain_time * ts) or (chain_time / ts)
				gate = math.max(0, open - (last_fixed_t - (weapon_action.start_t or last_fixed_t)))
				break
			end
		end
	else
		fire_name = primary_fire(actions)
	end
	local fire = fire_name and actions[fire_name]
	if not fire then
		return false
	end
	local cost = 0
	local charge_template = fire.charge_template and weapon_ext._weapon_tweak_template
		and weapon_ext:_weapon_tweak_template("charge", fire.charge_template)
	local percent = charge_template and charge_template.warp_charge_percent
	if type(percent) == "table" then
		percent = math.max(percent.lerp_basic or 0, percent.lerp_perfect or 0)
	end
	if type(percent) == "number" then
		local level = 1
		if charge_template.use_charge and gate <= 0 then
			local charge = unit_data:read_component("action_module_charge")
			level = charge and charge.charge_level or 1
		end
		cost = percent * level * scriers_model.scale
	end
	local now = last_fixed_t
	local total = fire.total_time
	guard_weapon_action.current_action_name = fire_name
	guard_weapon_action.start_t = now
	guard_weapon_action.time_scale = 1
	guard_weapon_action.is_infinite_duration = type(total) ~= "number" or total == math.huge
	guard_weapon_action.end_t = type(total) == "number" and now + total or nil
	local after = vent_wait(template, guard_weapon_action, now, "staff", true) + scriers_model.base_lead
	local game_session = Managers.state.game_session
	local fixed_dt = game_session and game_session.fixed_time_step or (1 / 52)
	local predicted = live + climb * (gate / fixed_dt + 2) + cost + scriers_passive(gate + after) * after
	return predicted >= 1 - SCRIERS_BUFFER
end

-- Push info from the weapon template, cached: press and hold inputs, raw keys, and action
-- names (push, follow-up, the attack it ends in). nil if the weapon has no push.
local push_info_cache = setmetatable({}, { __mode = "k" })

local function push_info(template)
	if not template then
		return nil
	end
	local info = push_info_cache[template]
	if info == nil then
		info = false
		local inputs, actions = template.action_inputs, template.actions
		local push = inputs and inputs.push
		local step = push and push.input_sequence and push.input_sequence[1]
		if step and step.input and actions then
			info = { press = step.input, hold = step.hold_input, keys = { [step.input] = true }, actions = {} }
			local follow = inputs.push_follow_up
			local follow_step = follow and follow.input_sequence and follow.input_sequence[1]
			if follow_step and follow_step.input then
				info.keys[follow_step.input] = true
			end
			for name, action in pairs(actions) do
				if action.kind == "push" then
					info.actions[name] = true
					local chain = action.allowed_chain_actions and action.allowed_chain_actions.push_follow_up
					local follow_name = chain and chain.action_name
					local follow_action = follow_name and actions[follow_name]
					if follow_action then
						info.actions[follow_name] = true
						for _, next_chain in pairs(follow_action.allowed_chain_actions or EMPTY) do
							local next_name = type(next_chain) == "table" and next_chain.action_name
							if next_name and actions[next_name] and actions[next_name].kind == "damage_target" then
								info.actions[next_name] = true
							end
						end
					end
				end
			end
		end
		push_info_cache[template] = info
	end
	return info or nil
end

-- Last queued weapon action input: the parser listens for that input's children.
local function last_queued_input(unit)
	local input_ext = ScriptUnit.has_extension(unit, "action_input_system")
	local parsers = input_ext and input_ext._action_input_parsers
	local parser = parsers and parsers.weapon_action
	local queue = parser and parser._action_input_queue and parser._action_input_queue[parser._ring_buffer_index]
	local inputs = queue and queue[1]
	if not inputs then
		return (input_ext and input_ext:peek_next_input("weapon_action")) or nil
	end
	local last = nil
	for i = 1, parser._MAX_ACTION_INPUT_QUEUE or 0 do
		local input = inputs[i]
		if input == nil or input == parser._NO_ACTION_INPUT then
			break
		end
		last = input
	end
	return last
end

-- Charged fire: the game queues the input and snapshots the meter when the fire can start (its
-- chain gate, or the ready-up after a sprint). Swallows it if the meter is predicted at the cap
-- by then.
local function guard_charged_fire(input_cache, lookup, index)
	local fire_category = mod._sc_block_category
	local player = FIRE_GUARD[fire_category] and local_player()
	local unit = player and player.player_unit
	local unit_data = unit and ALIVE[unit] and classify(unit) == fire_category
		and ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data then
		-- A tracking gap invalidates the sample.
		fire_prev = false
		return
	end
	local overheat = mod._sc_block_overheat
	local live = meter(unit_data, overheat)
	local climb = fire_prev and math.max(0, live - fire_prev) or 0
	fire_prev = live
	local boundary = mod._sc_block_boundary
	local wa = unit_data:read_component("weapon_action")
	local action_name = wa and wa.current_action_name
	local charging = action_name ~= nil and STAFF_CHARGE_ACTIONS[action_name] or false
	if charging then
		if fire_climb_t ~= wa.start_t then
			fire_climb_t, fire_climb = wa.start_t, 0
		end
		fire_climb = math.max(fire_climb, climb)
	else
		fire_climb_t = false
	end
	local weapon_ext = boundary < math.huge and ScriptUnit.has_extension(unit, "weapon_system")
	local buff_ext = weapon_ext and ScriptUnit.has_extension(unit, "buff_system")
	local template = buff_ext and weapon_ext:weapon_template()
	local actions = template and template.actions
	if not actions then
		return
	end
	-- The charge that is running, or queued last (the parser already listens for its fire).
	local charge_name = charging and action_name or nil
	if not charge_name then
		local last = last_queued_input(unit)
		local last_config = last and template.action_inputs and template.action_inputs[last]
		-- A zero-buffer input that does not start on its own frame expires.
		if last_config and (last_config.buffer_time or 0) > 0 then
			for name in pairs(STAFF_CHARGE_ACTIONS) do
				if actions[name] and actions[name].start_input == last then
					charge_name = name
				end
			end
		end
	end
	local charge = charge_name and actions[charge_name]
	local chains = charge and charge.allowed_chain_actions
	local fire, fire_input
	if chains then
		for i = 1, #STAFF_FIRE_INPUTS do
			fire_input = STAFF_FIRE_INPUTS[i]
			fire = chains[fire_input]
			if fire then
				break
			end
		end
	end
	-- The fire input's raw keys (a press, and for Smite's heavy a hold that completes it), and
	-- whether the key it must be pressed with is held.
	local input_config = fire and template.action_inputs and template.action_inputs[fire_input]
	local sequence = input_config and input_config.input_sequence
	local triggered, held = false, true
	if type(sequence) == "table" then
		for i = 1, #sequence do
			local raw, hold = sequence[i].input, sequence[i].hold_input
			if raw and get_input(input_cache, lookup, raw, index) then
				triggered = true
			end
			if type(hold) == "string" and not get_input(input_cache, lookup, hold, index) then
				held = false
			end
		end
	end
	if not triggered then
		-- Hip fire at full heat only forces a vent, but a stun would fire it.
		if fire_category == "plasma" and not charge_name and live >= boundary - PLASMA_HIP_MARGIN then
			set_input(input_cache, lookup, "action_one_pressed", index, false)
		end
		return
	end
	local fire_settings = fire.action_name and actions[fire.action_name]
	local game_session = Managers.state.game_session
	local fixed_dt = game_session and game_session.fixed_time_step or (1 / 52)
	-- last_fixed_t is the previous frame's time.
	local now = last_fixed_t + fixed_dt
	local chain_time = fire.chain_time or 0
	local ready_up = fire_settings and fire_settings.sprint_ready_up_time or 0
	local sprint = unit_data:read_component("sprint_character_state")
	local sprinting = sprint ~= nil and Sprint.is_sprinting(sprint)
	local sprint_blocked = sprinting and fire_settings ~= nil
		and not fire_settings.allowed_during_sprint and not fire_settings.buff_keywords
	-- Seconds a sprint that just ended still holds the fire back.
	local recent = not sprinting and sprint and type(sprint.last_sprint_time) == "number"
		and math.max(0, sprint.last_sprint_time + ready_up - now) or 0
	local owed = live + pending_now
	local swallow = false
	if not charging then
		-- Without its hold key the press cannot fire the queued charge.
		if held and sprint_blocked then
			-- The sprint may become a jump before the charge starts: unknowable.
			swallow = true
		elseif held then
			-- The climb cannot be measured yet: assume the charge's rate until the gate, or until
			-- the queued fire's buffer runs out.
			local span = math.min(chain_time, input_config.buffer_time or 0)
			-- A sprint or its cooldown keeps the queued fire alive until the gate.
			if sprinting or recent > 0 or (sprint and type(sprint.cooldown) == "number" and now < sprint.cooldown) then
				span = math.max(chain_time, ready_up + fixed_dt, recent)
			end
			swallow = owed + charge_rate(weapon_ext, buff_ext, charge, overheat) * (span + 2 * fixed_dt) >= boundary
		end
	else
		local elapsed = now - (wa.start_t or now)
		local wait
		local sprint_drop = 0
		if not held then
			-- The press cannot fire the charge, which climbs until its release is taken.
			wait = (charge.minimum_hold_time or 0) - elapsed
		else
			local ts = wa.time_scale or 1
			local gate = (ts < 1) and (chain_time * ts) or (chain_time / ts)
			wait = gate - elapsed
			if sprint_blocked then
				local inair = unit_data:read_component("inair_state")
				if sprint.is_sprinting and not get_input(input_cache, lookup, "jump", index)
					and (not inair or inair.on_ground) then
					-- The queued input ends the sprint; the fire starts after its ready-up.
					wait = math.max(wait, ready_up)
					sprint_drop = 1
				else
					-- A sprint-jump holds the input until landing: unknowable.
					swallow = true
				end
			elseif recent > 0 then
				wait = math.max(wait, recent)
			end
		end
		if not swallow then
			-- Frames until the charge stops climbing; a float tie can open the gate a frame late.
			local frames = math.max(0, math.ceil(wait / fixed_dt - 0.001))
			if wait > -fixed_dt then
				frames = math.max(frames, 1)
			end
			-- Each further sequence element takes a frame.
			frames = math.max(frames, #sequence - 1) + sprint_drop
			if frames == 0 then
				swallow = owed >= boundary
			else
				-- An unmeasured climb (the charge's first frame) falls back to its rate. One
				-- frame of margin on a prediction.
				local per_frame = fire_climb > 0 and fire_climb
					or charge_rate(weapon_ext, buff_ext, charge, overheat) * fixed_dt
				swallow = owed + per_frame * (frames + 1) >= boundary
			end
		end
	end
	if swallow then
		for i = 1, #sequence do
			local raw = sequence[i].input
			if raw then
				set_input(input_cache, lookup, raw, index, false)
			end
		end
	end
end

local quell_ctx = {}

local function read_quell_ctx()
	quell_ctx.category, quell_ctx.template, quell_ctx.action, quell_ctx.kind = nil, nil, nil, nil
	quell_ctx.venting, quell_ctx.sprinting = false, false
	local player = local_player()
	local unit = player and player.player_unit
	local unit_data = unit and ALIVE[unit] and ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data then
		return
	end
	local weapon_ext = ScriptUnit.has_extension(unit, "weapon_system")
	local template = weapon_ext and weapon_ext:weapon_template()
	local weapon_action = unit_data:read_component("weapon_action")
	local action_name = weapon_action and weapon_action.current_action_name
	local actions = template and template.actions
	local action = action_name and actions and actions[action_name]
	quell_ctx.category = classify(unit)
	quell_ctx.template = template
	quell_ctx.action = action_name
	quell_ctx.kind = action and action.kind
	quell_ctx.venting = action ~= nil and action.kind == "vent_warp_charge"
	local sprint = unit_data:read_component("sprint_character_state")
	quell_ctx.sprinting = sprint ~= nil and Sprint.is_sprinting(sprint)
end

mod:hook_safe("HumanInputHandler", "_parse_input", function (self, input_cache, input_service, index)
	local lookup = self._action_lookup
	if not lookup then
		return
	end
	-- Read before the block zeroes keys: a press interrupts the plasma vent.
	local plasma_vent_interrupt_now = mod._sc_plasma_vent and cfg.auto_plasma_vent_interrupt
		and player_taking_action(input_cache, lookup, index, PLASMA_VENT_INTERRUPTS)
	if plasma_vent_interrupt_now then
		mod._sc_plasma_vent_interrupted = true
	end
	mod._sc_cast_held = first_input(input_cache, lookup, index, CAST_HOLDS) ~= nil
	track_running_action()
	local block_now = block_engaged_now()
	if block_now then
		local pressed = mod._sc_pressed
		for i = 1, #pressed do
			set_input(input_cache, lookup, pressed[i], index, false)
		end
		local held = mod._sc_held
		for i = 1, #held do
			set_input(input_cache, lookup, held[i], index, false)
		end
		-- Conclude a cast before immunity ends.
		local release = mod._sc_release
		for i = 1, #release do
			set_input(input_cache, lookup, release[i], index, false)
		end
	end
	guard_charged_fire(input_cache, lookup, index)
	-- Scrier's guard: swallow a staff shot that would end the stance.
	local guard_tracked = false
	if mod._sc_scriers_guard then
		local g_player = local_player()
		local g_unit = g_player and g_player.player_unit
		local g_ud = g_unit and ALIVE[g_unit] and classify(g_unit) == "staff"
			and ScriptUnit.has_extension(g_unit, "unit_data_system")
		if g_ud then
			local warp = g_ud:read_component("warp_charge")
			local live = (warp and warp.current_percentage) or 0
			local climb = scriers_guard_prev and math.max(0, live - scriers_guard_prev) or 0
			scriers_guard_prev = live
			guard_tracked = true
			if get_input(input_cache, lookup, "action_one_pressed", index)
				and scriers_shot_ends_stance(g_unit, g_ud, live, climb) then
				set_input(input_cache, lookup, "action_one_pressed", index, false)
			end
		end
	end
	if not guard_tracked then
		scriers_guard_prev = false
	end
	-- Brain Rupture: block the lock against live Peril, unless a locked cast is running.
	if mod._sc_br_boundary < math.huge then
		local br_player = local_player()
		local br_unit = br_player and br_player.player_unit
		if br_unit and ALIVE[br_unit] and select(2, classify(br_unit)) == "brain_rupture" then
			local br_ud = ScriptUnit.has_extension(br_unit, "unit_data_system")
			if br_ud then
				local weapon_action = br_ud:read_component("weapon_action")
				local action_name = weapon_action and weapon_action.current_action_name
				if action_name ~= "action_charge_target_sticky" and action_name ~= "action_charge_target_lock_on" then
					local warp_charge = br_ud:read_component("warp_charge")
					if warp_charge and (warp_charge.current_percentage or 0) >= mod._sc_br_boundary then
						set_input(input_cache, lookup, "action_one_hold", index, false)
					end
				end
			end
		end
	end
	-- Quelling: hold reload unless a player action pauses it.
	-- Reads the cache after the blocks, so swallowed keys never pause.
	local offense_holds = OFFENSIVE_HOLDS[mod._sc_block_category] or EMPTY
	mod._sc_offense_held = first_input(input_cache, lookup, index, offense_holds) ~= nil
	if not mod._sc_quell then
		quell_offense_pause = false
	end
	if mod._sc_quell or quell_replay then
		read_quell_ctx()
	end
	-- A mid-hitch swap must not force reload onto a non-venting weapon.
	if mod._sc_quell and VENTABLE[quell_ctx.category] then
		local category = quell_ctx.category
		local offense_on = cfg.quell_interrupt_offensive
		local other_on = cfg.quell_interrupt_other
		-- A push under way or pressed now.
		local push = push_info(quell_ctx.template)
		local pushing = false
		if push then
			pushing = push.actions[quell_ctx.action]
				or (get_input(input_cache, lookup, push.press, index)
					and (not push.hold or get_input(input_cache, lookup, push.hold, index)))
				or false
		end
		local offense_input, other_input
		if offense_on then
			offense_input = first_input(input_cache, lookup, index, OFFENSIVE_PRESSES)
				or first_input(input_cache, lookup, index, OFFENSIVE_HOLDS[category] or EMPTY)
			-- Push keys are not offensive.
			if pushing and push.keys[offense_input] then
				offense_input = nil
			end
		end
		if other_on then
			other_input = first_input(input_cache, lookup, index, OTHER_HOLDS[category] or EMPTY)
				or sprint_input(input_cache, lookup, index)
		end
		-- An offensive interrupt holds the pause while its action runs.
		local attacking = quell_ctx.action ~= nil and quell_ctx.action ~= "none" and not quell_ctx.venting
		if offense_input then
			quell_offense_pause = true
		elseif quell_offense_pause and not attacking and not quell_replay then
			quell_offense_pause = false
		end
		-- Queue a press the running vent swallows for re-send; a replayable press outranks a held key.
		local press = offense_input
		if not (press and REPLAY_PRESSES[press]) then
			press = other_input
		end
		if press and REPLAY_PRESSES[press] and quell_ctx.venting then
			quell_replay = press
			quell_replay_until = last_fixed_t + REPLAY_WINDOW
			quell_replay_template = quell_ctx.template
		end
		local paused = quell_offense_pause or other_input ~= nil or quell_replay ~= nil
			or (other_on and (quell_ctx.sprinting or pushing))
		if paused then
			-- Cancels the follow-through.
			mod._sc_quell_interrupted = true
		else
			-- Reload stays false just after a swap so the vent cannot stick.
			set_input(input_cache, lookup, "weapon_reload_hold", index, mod._sc_wield_guard <= 0)
		end
		-- Offensive interrupts off: swallow new presses and release holds a running attack does not need.
		if not offense_on then
			-- Push keys pass while its hold key is held and other interrupts are on.
			local push_keys = other_on and pushing
				and (not push.hold or get_input(input_cache, lookup, push.hold, index))
				and push.keys or EMPTY
			-- The follow-up's attack needs no key.
			local push_running = push_keys ~= EMPTY and push.actions[quell_ctx.action]
				and quell_ctx.kind ~= "damage_target"
			for i = 1, #OFFENSIVE_PRESSES do
				local press = OFFENSIVE_PRESSES[i]
				if not push_keys[press] then
					set_input(input_cache, lookup, press, index, false)
				end
			end
			local keep = attack_keep(quell_ctx.template, quell_ctx.action, category)
			-- Scrier's cut: the attack does not conclude.
			if keep and mod._sc_quell_cut and not CHARGE_KINDS[quell_ctx.kind] and not push_running then
				keep = nil
			end
			local holds = OFFENSIVE_HOLDS[category] or EMPTY
			for i = 1, #holds do
				local hold = holds[i]
				if not (keep and keep[hold]) and not (push_running and push_keys[hold]) then
					set_input(input_cache, lookup, hold, index, false)
				end
			end
		end
		-- Other interrupts off: release block.
		if not other_on then
			local holds = OTHER_HOLDS[category] or EMPTY
			for i = 1, #holds do
				set_input(input_cache, lookup, holds[i], index, false)
			end
		end
	end
	-- Re-send the swallowed press once the vent stops, unless the cap blocks it.
	if quell_replay then
		if last_fixed_t > quell_replay_until or quell_ctx.template ~= quell_replay_template then
			quell_replay = nil
		elseif not quell_ctx.venting then
			if not (block_now and raw_is_blocked(quell_replay)) then
				set_input(input_cache, lookup, quell_replay, index, true)
				-- A force-sword swing starts on the attack hold, so a tap needs it for one frame.
				-- Not while blocking: there the tap is a push, which this hold would turn into a swing.
				if quell_replay == "action_one_pressed" and quell_ctx.category == "force_sword"
					and not get_input(input_cache, lookup, "action_two_hold", index)
					and not (block_now and raw_is_blocked("action_one_hold")) then
					set_input(input_cache, lookup, "action_one_hold", index, true)
				end
				guard_charged_fire(input_cache, lookup, index)
			end
			quell_replay = nil
		end
	end
	-- Plasma vent: only while a plasma gun is still wielded.
	if mod._sc_plasma_vent and not plasma_vent_interrupt_now then
		local vent_player = local_player()
		local vent_unit = vent_player and vent_player.player_unit
		if vent_unit and ALIVE[vent_unit] and classify(vent_unit) == "plasma" then
			-- Release a held brace (hold-to-ADS only) so the vent can start.
			if not get_input(input_cache, lookup, "toggle_ads", index) then
				set_input(input_cache, lookup, "action_two_hold", index, false)
			end
			set_input(input_cache, lookup, "weapon_extra_hold", index, true)
		end
	end
	if mod._sc_fire_request then
		set_input(input_cache, lookup, "combat_ability_pressed", index, true)
		mod._sc_fire_request = false
	end
	-- Auto Fire: one press per charge, only when it starts now (gate open, Peril just under the cap).
	local in_fire_window = false
	-- A quell blocking offensive actions blocks this too.
	if mod._sc_autofire_armed and not (mod._sc_quell and not cfg.quell_interrupt_offensive) then
		local af_player = local_player()
		local af_unit = af_player and af_player.player_unit
		local af_ud = af_unit and ALIVE[af_unit] and classify(af_unit) == "staff"
			and ScriptUnit.has_extension(af_unit, "unit_data_system")
		local wa = af_ud and af_ud:read_component("weapon_action")
		local action_name = wa and wa.current_action_name
		if action_name and STAFF_CHARGE_ACTIONS[action_name] then
			local warp = af_ud:read_component("warp_charge")
			local live_peril = (warp and warp.current_percentage) or 0
			-- Time until the fire can chain.
			local ts = wa.time_scale or 1
			local gate = (ts < 1) and (AUTO_FIRE_CHAIN_TIME * ts) or (AUTO_FIRE_CHAIN_TIME / ts)
			if live_peril < PERIL_CAP and live_peril >= PERIL_CAP - AUTO_FIRE_MARGIN
				and (last_fixed_t - (wa.start_t or last_fixed_t)) >= gate
				and not sprint_blocks_fire(af_unit, af_ud, action_name) then
				in_fire_window = true
				if not autofire_latched then
					set_input(input_cache, lookup, "action_one_pressed", index, true)
					autofire_latched = true
				end
			end
		end
	end
	if not in_fire_window then
		autofire_latched = false
	end
end)

-- Queue gate: drop cap-blocked inputs already queued. Only works where the client is the authority.
mod:hook_safe("ActionInputParser", "fixed_update", function (self, unit, dt, t, fixed_frame)
	if mod._sc_block_boundary >= math.huge or self._action_component_name ~= "weapon_action" then
		return
	end
	if self._player ~= local_player() then
		return
	end
	-- Re-tested here: this hook runs after Peril decay.
	if not block_engaged_now() then
		return
	end
	-- Queue arrays: [1] action inputs, [2] raw inputs.
	local queue = self._action_input_queue and self._action_input_queue[self._ring_buffer_index]
	local actions = queue and queue[1]
	local raws = queue and queue[2]
	if not actions or not raws then
		return
	end
	-- Entries chain, so clearing a blocked one clears those after it.
	local no_action = self._NO_ACTION_INPUT
	for i = 1, self._MAX_ACTION_INPUT_QUEUE do
		local action_input = actions[i]
		if action_input == nil or action_input == no_action then
			break
		end
		local raw = raws[i]
		if raw and raw_is_blocked(raw) then
			self:_clear_action_input_queue(queue, i)
			break
		end
	end
end)
