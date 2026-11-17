--!strict
-- Remote handlers for the builder: save / delete / equip movesets, manage the
-- VFX library, and import / export share codes.
--
-- Every argument from the client is untrusted: it is type-checked, rate
-- limited, run through the validators, and player-written text is filtered.

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)
local ExportCode = require(Shared.Codec.ExportCode)
local MovesetValidator = require(Shared.Validate.MovesetValidator)
local VfxValidator = require(Shared.Validate.VfxValidator)

local DataService = require(script.Parent.DataService)
local Executor = require(script.Parent.Runtime.Executor)
local RateLimiter = require(script.Parent.RateLimiter)

local MovesetService = {}

local notify = Remotes.event("Notify")
local cooldownEvent = Remotes.event("Cooldown")

-- Text filtering ------------------------------------------------------------

local function filter(text: string, fromUserId: number): string
	if text == "" then
		return ""
	end
	local ok, result = pcall(function()
		local r = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	return string.rep("#", math.min(#text, 12))
end

local function filterMoveset(moveset: any, userId: number)
	moveset.name = filter(moveset.name, userId)
	moveset.description = filter(moveset.description, userId)
	for _, move in moveset.moves do
		move.name = filter(move.name, userId)
	end
	for _, effect in moveset.vfx do
		effect.name = filter(effect.name, userId)
	end
end

MovesetService.filter = filter

-- Helpers ---------------------------------------------------------------------

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Embeds every library effect the moveset references so the saved moveset (and
-- its share code) is self-contained.
local function embedVfx(raw: any, library: { [string]: any })
	local embedded = if type(raw.vfx) == "table" then raw.vfx else {}
	local merged = {}
	for id, effect in embedded do
		merged[id] = effect
	end
	for id, effect in library do
		merged[id] = effect
	end
	raw.vfx = merged
end

local function equipFor(player: Player, profile: any)
	local character = player.Character
	if not character then
		return
	end
	local moveset = profile.slots[profile.equipped]
	if not moveset then
		Executor.unequip(character)
		return
	end
	local result = MovesetValidator.moveset(moveset)
	if not result.ok then
		Executor.unequip(character)
		notify:FireClient(player, "Your equipped technique is over budget. Fix it in the builder.", "warn")
		return
	end
	Executor.equip(character, result.value, function(slot, seconds)
		cooldownEvent:FireClient(player, slot, seconds)
	end)
end
MovesetService.equipFor = equipFor

-- Remote handlers -------------------------------------------------------------

local function profileFor(player: Player): any?
	return DataService.get(player)
end

Remotes.func("GetProfile").OnServerInvoke = function(player)
	local profile = DataService.wait(player)
	if not profile then
		return nil
	end
	return {
		slots = profile.slots,
		equipped = profile.equipped,
		vfx = profile.vfx,
		limits = { slots = Config.Moveset.MaxSlotsSaved, vfx = Config.Vfx.MaxLibrarySize },
	}
end

Remotes.func("SaveMoveset").OnServerInvoke = function(player, slotIndex: any, raw: any)
	local profile = profileFor(player)
	if not profile then
		return { ok = false, errors = { "Profile not loaded yet." } }
	end
	if not RateLimiter.check(player, "Save", Config.RateLimit.Save) then
		return { ok = false, errors = { "You're saving too fast." } }
	end
	if type(slotIndex) ~= "number" or slotIndex ~= slotIndex then
		return { ok = false, errors = { "Bad slot." } }
	end
	slotIndex = math.floor(slotIndex)
	local nextFree = #profile.slots + 1
	if slotIndex < 1 or slotIndex > math.min(nextFree, Config.Moveset.MaxSlotsSaved) then
		return { ok = false, errors = { "No free technique slot." } }
	end
	if type(raw) ~= "table" then
		return { ok = false, errors = { "Bad data." } }
	end
	embedVfx(raw, profile.vfx)
	local result = MovesetValidator.moveset(raw)
	local value = result.value
	if not value then
		return { ok = false, errors = result.errors }
	end
	filterMoveset(value, player.UserId)
	-- Over-budget movesets are still saved (so work isn't lost) but can't be equipped.
	profile.slots[slotIndex] = value
	if profile.equipped == slotIndex then
		equipFor(player, profile)
	end
	return { ok = result.ok, value = value, errors = result.errors, warnings = result.warnings }
end

Remotes.func("DeleteMoveset").OnServerInvoke = function(player, slotIndex: any)
	local profile = profileFor(player)
	if not profile or type(slotIndex) ~= "number" or not profile.slots[slotIndex] then
		return false
	end
	table.remove(profile.slots, slotIndex) -- keep the array dense for DataStores
	if profile.equipped == slotIndex then
		profile.equipped = 0
	elseif profile.equipped > slotIndex then
		profile.equipped -= 1
	end
	equipFor(player, profile)
	return true
end

Remotes.func("EquipMoveset").OnServerInvoke = function(player, slotIndex: any)
	local profile = profileFor(player)
	if not profile or type(slotIndex) ~= "number" or not profile.slots[slotIndex] then
		return false, "No technique in that slot."
	end
	local result = MovesetValidator.moveset(profile.slots[slotIndex])
	if not result.ok then
		return false, result.errors[1]
	end
	profile.equipped = slotIndex
	equipFor(player, profile)
	return true
end

Remotes.func("SaveVfx").OnServerInvoke = function(player, effectId: any, raw: any)
	local profile = profileFor(player)
	if not profile then
		return nil, "Profile not loaded yet."
	end
	if not RateLimiter.check(player, "Save", Config.RateLimit.Save) then
		return nil, "You're saving too fast."
	end
	local effect, err = VfxValidator.effect(raw)
	if not effect then
		return nil, err
	end
	effect.name = filter(effect.name, player.UserId)
	local id = if type(effectId) == "string" and profile.vfx[effectId] then effectId else nil
	if not id then
		if count(profile.vfx) >= Config.Vfx.MaxLibrarySize then
			return nil, "Your VFX library is full."
		end
		repeat
			id = Util.newId()
		until not profile.vfx[id]
	end
	profile.vfx[id :: string] = effect
	return id, effect
end

Remotes.func("DeleteVfx").OnServerInvoke = function(player, effectId: any)
	local profile = profileFor(player)
	if profile and type(effectId) == "string" and profile.vfx[effectId] then
		profile.vfx[effectId] = nil
		return true
	end
	return false
end

Remotes.func("ExportCode").OnServerInvoke = function(player, kind: any, which: any)
	local profile = profileFor(player)
	if not profile then
		return nil, "Profile not loaded yet."
	end
	if kind == "moveset" and type(which) == "number" and profile.slots[which] then
		return ExportCode.encode("moveset", profile.slots[which])
	elseif kind == "vfx" and type(which) == "string" and profile.vfx[which] then
		return ExportCode.encode("vfx", profile.vfx[which])
	end
	return nil, "Nothing to export."
end

-- Decodes and validates a pasted code, then stores the result:
--   moveset -> next free technique slot (its effects are also added to the VFX library)
--   vfx     -> the VFX library
-- Shared by pasted codes and the public gallery. Not rate limited here.
function MovesetService.importCode(player: Player, code: any): any
	local profile = profileFor(player)
	if not profile then
		return { ok = false, error = "Profile not loaded yet." }
	end
	if type(code) ~= "string" then
		return { ok = false, error = "Code must be text." }
	end
	local kind, data = ExportCode.decode(code)
	if not kind then
		return { ok = false, error = data }
	end

	if kind == "vfx" then
		local effect, err = VfxValidator.effect(data)
		if not effect then
			return { ok = false, error = err }
		end
		if count(profile.vfx) >= Config.Vfx.MaxLibrarySize then
			return { ok = false, error = "Your VFX library is full." }
		end
		effect.name = filter(effect.name, player.UserId)
		local id
		repeat
			id = Util.newId()
		until not profile.vfx[id]
		profile.vfx[id] = effect
		return { ok = true, kind = "vfx", id = id, value = effect }
	end

	-- moveset
	local result = MovesetValidator.moveset(data)
	local value = result.value
	if not value then
		return { ok = false, error = result.errors[1] or "Invalid technique." }
	end
	if #profile.slots >= Config.Moveset.MaxSlotsSaved then
		return { ok = false, error = "All technique slots are full. Delete one first." }
	end
	filterMoveset(value, player.UserId)

	-- Give imported effects fresh ids in the library and remap references, so
	-- they never overwrite the player's own effects.
	local remap: { [string]: string } = {}
	for oldId, effect in value.vfx do
		if count(profile.vfx) >= Config.Vfx.MaxLibrarySize then
			break
		end
		local newId
		repeat
			newId = Util.newId()
		until not profile.vfx[newId]
		profile.vfx[newId] = Util.deepCopy(effect)
		remap[oldId] = newId
	end
	local function remapBlocks(blocks: { any })
		for _, b in blocks do
			for k, v in b.fields do
				if (k == "vfx") and type(v) == "string" and remap[v] then
					b.fields[k] = remap[v]
				end
			end
			if b.children then
				for _, list in b.children do
					remapBlocks(list)
				end
			end
		end
	end
	for _, move in value.moves do
		remapBlocks(move.blocks)
	end
	local newVfx = {}
	for oldId, effect in value.vfx do
		newVfx[remap[oldId] or oldId] = effect
	end
	value.vfx = newVfx

	table.insert(profile.slots, value)
	return {
		ok = true,
		kind = "moveset",
		slot = #profile.slots,
		value = value,
		warnings = result.warnings,
		errors = result.errors, -- non-empty = over budget: saved but not equippable until fixed
	}
end

Remotes.func("ImportCode").OnServerInvoke = function(player, code: any)
	if not RateLimiter.check(player, "Import", Config.RateLimit.Import) then
		return { ok = false, error = "You're importing too fast." }
	end
	return MovesetService.importCode(player, code)
end

-- Equip on spawn ------------------------------------------------------------------

DataService.ProfileLoaded:Connect(function(player: Player, profile: any)
	if player.Character then
		equipFor(player, profile)
	end
end)

return MovesetService
