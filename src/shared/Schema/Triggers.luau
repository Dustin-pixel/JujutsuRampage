--!strict
-- How a move starts. Each move has exactly one trigger.

export type TriggerDef = {
	id: string,
	label: string,
	description: string,
	fields: { any },
}

local list: { TriggerDef } = {
	{
		id = "Press",
		label = "On Press",
		description = "Runs when you press the move's key.",
		fields = {},
	},
	{
		id = "Charge",
		label = "Hold to Charge",
		description = "Hold the key to charge, release to fire. Charge (0-100%) can scale Damage / Knockback and be checked with If › ChargeAbove. You move slower while charging.",
		fields = {
			{ key = "maxCharge", label = "Full charge (s)", type = "number", default = 1.5, min = 0.3, max = 3, step = 0.1 },
		},
	},
	{
		id = "Counter",
		label = "Counter",
		description = "Pressing the key opens a counter window. If you're attacked during it, the hit is cancelled and the move runs with the attacker as its target.",
		fields = {
			{ key = "window", label = "Window (s)", type = "number", default = 0.6, min = 0.2, max = 1.5, step = 0.05 },
		},
	},
	{
		id = "ComboFinisher",
		label = "Combo Finisher",
		description = "Runs automatically (with the target) when your last M1 of a combo lands. Still has a cooldown.",
		fields = {},
	},
	{
		id = "Passive",
		label = "Passive",
		description = "Runs on its own every few seconds while the moveset is equipped.",
		fields = {
			{ key = "interval", label = "Every (s)", type = "number", default = 10, min = 3, max = 60, step = 1 },
		},
	},
}

local Triggers = { List = list, ById = {} :: { [string]: TriggerDef } }
for _, def in list do
	Triggers.ById[def.id] = def
end

return Triggers
