--!strict
-- The starter technique every new player gets, plus a few starter effects.
-- Uses only built-in textures/shapes so it works without uploading assets.
-- (Written as raw data on purpose: it goes through the validator like any import.)

local Presets = {}

local function block(type: string, fields: { [string]: any }?, children: { [string]: { any } }?)
	return { type = type, fields = fields or {}, children = children }
end

Presets.StarterVfx = {
	spark = {
		name = "Cursed Spark",
		layers = {
			{
				kind = "Emitter",
				name = "Sparks",
				offset = { 0, 0, -1 },
				props = {
					Color = { { 0, 140, 90, 255 }, { 1, 40, 10, 120 } },
					Size = { { 0, 0.8, 0 }, { 1, 0, 0 } },
					Transparency = { { 0, 0, 0 }, { 1, 1, 0 } },
					Lifetime = { 0.2, 0.4 },
					Speed = { 20, 35 },
					SpreadAngle = { 180, 180 },
					EmitCount = 30,
					LightEmission = 1,
					Brightness = 3,
				},
			},
			{ kind = "Light", name = "Glow", props = { Color = { 140, 90, 255 }, Brightness = 4, Range = 14, Duration = 0.3 } },
		},
	},
	impact = {
		name = "Impact",
		layers = {
			{
				kind = "Emitter",
				name = "Burst",
				props = {
					Color = { { 0, 255, 255, 255 }, { 1, 120, 60, 255 } },
					Size = { { 0, 1.5, 0.3 }, { 1, 0, 0 } },
					Lifetime = { 0.15, 0.35 },
					Speed = { 25, 45 },
					SpreadAngle = { 180, 180 },
					Drag = 6,
					EmitCount = 40,
				},
			},
			{
				kind = "Mesh",
				name = "Shockwave",
				props = {
					Shape = "Cylinder",
					Color = { 170, 130, 255 },
					StartScale = { 0.2, 1, 1 },
					EndScale = { 0.2, 12, 12 },
					Rotation = { 0, 0, 90 },
					StartTransparency = 0.2,
					EndTransparency = 1,
					Duration = 0.35,
				},
			},
		},
	},
	orb = {
		name = "Cursed Orb",
		layers = {
			{
				kind = "Mesh",
				name = "Core",
				props = {
					Shape = "Sphere",
					Color = { 90, 40, 220 },
					StartScale = { 2.5, 2.5, 2.5 },
					EndScale = { 3, 3, 3 },
					StartTransparency = 0.1,
					EndTransparency = 0.3,
					Duration = 1.5,
					Easing = "Linear",
				},
			},
			{
				kind = "Emitter",
				name = "Trail",
				props = {
					Color = { { 0, 160, 110, 255 }, { 1, 30, 0, 80 } },
					Size = { { 0, 1.2, 0 }, { 1, 0, 0 } },
					Lifetime = { 0.3, 0.5 },
					Speed = { 1, 3 },
					Rate = 80,
					EmitCount = 0,
				},
			},
		},
	},
	heal = {
		name = "Reverse Flow",
		layers = {
			{
				kind = "Emitter",
				name = "Rising",
				offset = { 0, -2, 0 },
				props = {
					Color = { { 0, 120, 255, 170 }, { 1, 255, 255, 255 } },
					Size = { { 0, 0.4, 0 }, { 1, 0, 0 } },
					Lifetime = { 0.6, 1 },
					Speed = { 4, 8 },
					SpreadAngle = { 15, 15 },
					Acceleration = { 0, 6, 0 },
					Rate = 60,
					EmitCount = 0,
					Shape = "Cylinder",
					EmitterSize = { 3, 0.5, 3 },
				},
			},
		},
	},
}

Presets.StarterMoveset = {
	name = "Cursed Strikes",
	description = "A basic sorcerer kit. Edit it, or start from scratch!",
	color = { 140, 90, 255 },
	moves = {
		{
			name = "Divergent Fist",
			cooldown = 5,
			trigger = { type = "Press" },
			blocks = {
				block("CostEnergy", { amount = 10 }),
				block("PlayVfx", { vfx = "spark", at = "Self", seconds = 0.4 }),
				block("Dash", { direction = "Forward", distance = 10, seconds = 0.15 }),
				block("Hitbox", { shape = "Box", size = { 5, 5, 6 }, offset = { 0, 0, -3 }, maxTargets = 2 }, {
					onHit = {
						block("Damage", { amount = 7 }),
						block("Stun", { seconds = 0.7 }),
						block("PlayVfx", { vfx = "impact", at = "Target", seconds = 0.4 }),
						block("Wait", { seconds = 0.3 }),
						block("Damage", { amount = 6 }),
						block("Knockback", { direction = "Away", force = 55 }),
					},
				}),
			},
		},
		{
			name = "Cursed Blast",
			cooldown = 7,
			trigger = { type = "Charge", fields = { maxCharge = 1.2 } },
			blocks = {
				block("CostEnergy", { amount = 20 }),
				block("FaceTarget", { range = 60 }),
				block("Projectile", { speed = 90, range = 100, radius = 2, vfx = "orb" }, {
					onHit = {
						block("Damage", { amount = 14, scaleWithCharge = true }),
						block("Knockback", { direction = "Away", force = 70, scaleWithCharge = true }),
						block("PlayVfx", { vfx = "impact", at = "Target", seconds = 0.4 }),
						block("CameraShake", { intensity = 0.6, seconds = 0.25 }),
					},
				}),
			},
		},
		{
			name = "Flash Step",
			cooldown = 4,
			trigger = { type = "Press" },
			blocks = {
				block("CostEnergy", { amount = 10 }),
				block("Armor", { seconds = 0.2 }),
				block("Dash", { direction = "Forward", distance = 25, seconds = 0.15 }),
			},
		},
		{
			name = "Reverse Cursed Technique",
			cooldown = 20,
			trigger = { type = "Press" },
			blocks = {
				block("CostEnergy", { amount = 40 }),
				block("PlayVfx", { vfx = "heal", at = "Self", seconds = 1.5 }),
				block("Heal", { amount = 20 }),
			},
		},
		{
			name = "Counter Seal",
			cooldown = 10,
			trigger = { type = "Counter", fields = { window = 0.6 } },
			blocks = {
				block("Teleport", { mode = "BehindTarget" }),
				block("PlayVfx", { vfx = "impact", at = "Target", seconds = 0.4 }),
				block("Damage", { amount = 10 }),
				block("Stun", { seconds = 1 }),
				block("Knockback", { direction = "Up", force = 50 }),
			},
		},
		{
			name = "Domain: Cursed Void",
			cooldown = 90,
			trigger = { type = "Press" },
			blocks = {
				block("CostEnergy", { amount = 60 }),
				block("Armor", { seconds = 0.6 }),
				block("Domain", {
					radius = 30,
					seconds = 6,
					tick = 1,
					refinement = 5,
					sureHit = true,
					trap = true,
					burnout = 10,
					color = { 25, 0, 45 },
					vfx = "spark",
				}, {
					onTick = {
						block("Damage", { amount = 5 }),
						block("PlayVfx", { vfx = "impact", at = "Target", seconds = 0.4 }),
					},
				}),
			},
		},
	},
	vfx = Presets.StarterVfx,
}

return Presets
