local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Blocks = require(Shared.Schema.Blocks)
local Presets = require(Shared.Presets)
local MovesetValidator = require(Shared.Validate.MovesetValidator)
local VfxValidator = require(Shared.Validate.VfxValidator)

local function moveset(blocks: { any }, extra: { [string]: any }?): any
	local move = { name = "Test", cooldown = 5, trigger = { type = "Press" }, blocks = blocks }
	for k, v in extra or {} do
		move[k] = v
	end
	return { name = "T", moves = { move } }
end

local function hitbox(onHit: { any }, maxTargets: number?): any
	local b = Blocks.create("Hitbox")
	b.fields.maxTargets = maxTargets or 1
	b.children.onHit = onHit
	return b
end

local function damage(n: number): any
	local b = Blocks.create("Damage")
	b.fields.amount = n
	return b
end

return {
	["starter moveset is valid"] = function(t)
		local r = MovesetValidator.moveset(Presets.StarterMoveset)
		t.ok(r.ok, table.concat(r.errors, "; "))
		t.eq(#r.value.moves, #Presets.StarterMoveset.moves)
		t.ok(r.value.vfx.spark ~= nil, "referenced effects are embedded")
	end,
	["unknown blocks are removed"] = function(t)
		local r = MovesetValidator.moveset(moveset({ { type = "RunLuaCode", fields = { code = "print(1)" } } }))
		t.eq(#r.value.moves[1].blocks, 0)
		t.ok(#r.warnings > 0)
	end,
	["numbers are clamped and NaN / inf replaced"] = function(t)
		local r = MovesetValidator.moveset(moveset({ hitbox({ damage(1e9) }) }))
		t.eq(r.value.moves[1].blocks[1].children.onHit[1].fields.amount, 30, "Damage max is 30")
		local r2 = MovesetValidator.moveset(moveset({ hitbox({ damage(0 / 0) }) }))
		t.eq(r2.value.moves[1].blocks[1].children.onHit[1].fields.amount, Blocks.ById.Damage.fields[1].default)
		local r3 = MovesetValidator.moveset(moveset({ { type = "Wait", fields = { seconds = math.huge } } }))
		t.eq(r3.value.moves[1].blocks[1].fields.seconds, 0.2)
	end,
	["damage needs a target"] = function(t)
		local r = MovesetValidator.moveset(moveset({ damage(5) }))
		t.ok(not r.ok, "Damage at the root of a Press move is an error")
		local counter = MovesetValidator.moveset(moveset({ damage(5) }, { trigger = { type = "Counter" } }))
		t.ok(counter.ok, "Counter moves have a target at the root")
	end,
	["repeat multiplies damage into the budget"] = function(t)
		local rep = Blocks.create("Repeat")
		rep.fields.count = 10
		rep.children.body = { hitbox({ damage(10) }) }
		local r = MovesetValidator.moveset(moveset({ rep }))
		t.ok(not r.ok, "10 x 10 damage is over budget")
		t.eq(r.reports[1].totals.damage, 100)
	end,
	["block count and nesting are limited"] = function(t)
		local many = {}
		for i = 1, 100 do
			many[i] = { type = "Wait", fields = { seconds = 0 } }
		end
		local r = MovesetValidator.moveset(moveset(many))
		t.eq(#r.value.moves[1].blocks, Config.Moveset.MaxBlocksPerMove)

		-- 6 levels of nested Repeat
		local inner: any = { type = "Wait", fields = { seconds = 0 } }
		for _ = 1, 6 do
			inner = { type = "Repeat", fields = { count = 1 }, children = { body = { inner } } }
		end
		local r2 = MovesetValidator.moveset(moveset({ inner }))
		local depth = 0
		local node = r2.value.moves[1].blocks[1]
		while node do
			depth += 1
			node = node.children and node.children.body and node.children.body[1]
		end
		t.ok(depth <= Config.Moveset.MaxNestingDepth, "depth " .. depth)
	end,
	["cooldown is raised to match power"] = function(t)
		local r = MovesetValidator.moveset(moveset({ hitbox({ damage(30), damage(30) }) }, { cooldown = 0 }))
		t.ok(r.value.moves[1].cooldown >= 60 / Config.Budget.DamagePerCooldownSecond)
	end,
	["move count is capped"] = function(t)
		local moves = {}
		for i = 1, 20 do
			moves[i] = { name = "m" .. i, blocks = {} }
		end
		local r = MovesetValidator.moveset({ moves = moves })
		t.eq(#r.value.moves, Config.Moveset.MaxMoves)
	end,
	["text is sanitized"] = function(t)
		local r = MovesetValidator.moveset({ name = "<font color='red'>Hi</font>\0" .. string.rep("x", 100), moves = {} })
		t.ok(not string.find(r.value.name, "[<>%c]"), "markup/control chars removed")
		t.ok(#r.value.name <= Config.Moveset.MaxNameLength)
	end,
	["vfx: unknown layers and props are dropped, values clamped"] = function(t)
		local effect = VfxValidator.effect({
			name = "x",
			layers = {
				{ kind = "Explosion", props = {} },
				{ kind = "Emitter", props = { Rate = 1e6, Texture = "rbxassetid://123", Parent = "workspace", Size = { { 0.5, 99999, 0 } } } },
			},
		})
		t.ok(effect ~= nil)
		t.eq(#effect.layers, 1)
		local props = effect.layers[1].props
		t.eq(props.Rate, Config.Vfx.MaxRatePerEmitter)
		t.eq(props.Texture, "123")
		t.eq(props.Parent, nil)
		t.eq(#props.Size, 2, "sequence with < 2 keypoints falls back to default")
	end,
	["vfx: sequences are sorted and pinned to 0..1"] = function(t)
		local effect = VfxValidator.effect({
			layers = { { kind = "Emitter", props = { Transparency = { { 0.8, 1, 0 }, { 0.2, 0, 0 }, { 0.5, 0.5, 0 } } } } },
		})
		local seq = effect.layers[1].props.Transparency
		t.eq(seq[1][1], 0)
		t.eq(seq[#seq][1], 1)
		for i = 2, #seq do
			t.ok(seq[i][1] > seq[i - 1][1], "strictly increasing times")
		end
	end,
	["vfx: bad asset ids are rejected"] = function(t)
		local effect = VfxValidator.effect({ layers = { { kind = "Mesh", props = { MeshId = "http://evil.example/x.mesh" } } } })
		t.eq(effect.layers[1].props.MeshId, "")
	end,
}
