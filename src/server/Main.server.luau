--!strict
-- Server entry point: wires services together and handles combat input.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local Executor = require(script.Parent.Runtime.Executor)
local MovesetService = require(script.Parent.MovesetService)
local RateLimiter = require(script.Parent.RateLimiter)
local Dummies = require(script.Parent.Dummies)
require(script.Parent.GalleryService)

local notify = Remotes.event("Notify")

local function onCharacter(player: Player, character: Model)
	CombatService.register(character)
	local profile = DataService.get(player)
	if profile then
		MovesetService.equipFor(player, profile)
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		Executor.unequip(character)
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Remotes.event("UseMove").OnServerEvent:Connect(function(player, slot: any, aim: any, phase: any)
	if not RateLimiter.check(player, "UseMove", Config.RateLimit.UseMove) then
		return
	end
	local character = player.Character
	if not character or type(slot) ~= "number" or slot ~= slot then
		return
	end
	slot = math.floor(slot)
	if slot < 1 or slot > Config.Moveset.MaxMoves then
		return
	end
	-- Aim must be a finite unit-ish vector; otherwise use facing direction.
	local aimDir: Vector3? = nil
	if typeof(aim) == "Vector3" and aim.Magnitude > 0.1 and aim.Magnitude < 10 and aim.X == aim.X then
		aimDir = aim.Unit
	end
	Executor.use(character, slot, aimDir, if phase == "up" then "up" else "down")
end)

Remotes.event("M1").OnServerEvent:Connect(function(player)
	if not RateLimiter.check(player, "M1", 8) then
		return
	end
	local character = player.Character
	if character and not Executor.isBusy(character) then
		CombatService.m1(character)
	end
end)

Remotes.event("Block").OnServerEvent:Connect(function(player, holding: any)
	if not RateLimiter.check(player, "Block", 10) then
		return
	end
	local character = player.Character
	if character and type(holding) == "boolean" then
		CombatService.setBlocking(character, holding)
	end
end)

Dummies.start()
notify:FireAllClients("Server ready.", "info")
