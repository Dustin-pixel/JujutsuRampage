--!strict
-- Player profiles in a DataStore, with a simple session lock so two servers
-- can't overwrite each other's data. Falls back to in-memory profiles when
-- DataStores are unavailable (e.g. Studio without "Enable Studio Access to
-- API Services"), so the game is still testable.
--
-- Profile shape:
--   { version = 1, slots = { [1..5] = moveset }, equipped = 0, vfx = { [id] = effect }, published = { entryId } }
--
-- Everything loaded is re-validated, so a bad save can't crash the game.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MovesetValidator = require(Shared.Validate.MovesetValidator)
local VfxValidator = require(Shared.Validate.VfxValidator)
local Presets = require(Shared.Presets)

local DataService = {}

local STORE_NAME = "Profiles_v1"
local LOCK_EXPIRY = 30 * 60 -- a lock older than this is considered abandoned
local AUTOSAVE_INTERVAL = 120

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStores unavailable, using in-memory profiles: " .. tostring(result))
	end
end

local profiles: { [Player]: any } = {}
local loaded = Instance.new("BindableEvent")
DataService.ProfileLoaded = loaded.Event -- (player, profile)

local function newProfile(): any
	local starter = MovesetValidator.moveset(Presets.StarterMoveset).value
	return {
		version = 1,
		slots = { starter },
		equipped = 1,
		vfx = VfxValidator.library(Presets.StarterVfx),
		published = {}, -- gallery entry ids
	}
end

local function cleanProfile(raw: any): any
	if type(raw) ~= "table" then
		return newProfile()
	end
	local profile = { version = 1, slots = {}, equipped = 0, vfx = VfxValidator.library(raw.vfx) }
	if type(raw.slots) == "table" then
		for i = 1, Config.Moveset.MaxSlotsSaved do
			local m = raw.slots[i]
			if type(m) == "table" then
				local result = MovesetValidator.moveset(m)
				-- keep over-budget saves so the owner can fix them, but they can't be equipped
				profile.slots[i] = result.value
			end
		end
	end
	profile.published = {}
	if type(raw.published) == "table" then
		for i = 1, Config.Gallery.MaxPublishedPerPlayer do
			local id = raw.published[i]
			if type(id) == "string" and #id <= 16 then
				table.insert(profile.published, id)
			end
		end
	end
	local eq = tonumber(raw.equipped) or 0
	if profile.slots[eq] then
		profile.equipped = eq
	end
	return profile
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function retry<T>(fn: () -> T, attempts: number): (boolean, T | string)
	local lastErr: any
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if i < attempts then
			task.wait(2 ^ i)
		end
	end
	return false, tostring(lastErr)
end

local function load(player: Player)
	if not store then
		profiles[player] = newProfile()
		loaded:Fire(player, profiles[player])
		return
	end
	local ds = store :: DataStore
	local jobId = if RunService:IsStudio() then "studio" else game.JobId
	for attempt = 1, 6 do
		local lockedElsewhere = false
		local ok, result = retry(function()
			return ds:UpdateAsync(key(player), function(old)
				lockedElsewhere = false -- the transform can run more than once
				old = old or {}
				local lock = old.lock
				if lock and lock.job ~= jobId and os.time() - (lock.time or 0) < LOCK_EXPIRY and attempt < 6 then
					lockedElsewhere = true
					return nil -- cancel the write
				end
				old.lock = { job = jobId, time = os.time() }
				return old
			end)
		end, if RunService:IsStudio() then 1 else 3)
		if not player.Parent then
			return
		end
		if ok and not lockedElsewhere then
			local profile = cleanProfile(if type(result) == "table" and result.slots then result else nil)
			profiles[player] = profile
			loaded:Fire(player, profile)
			return
		end
		if not ok then
			warn(`[DataService] load failed for {player.UserId}: {result}`)
			if RunService:IsStudio() then
				-- Studio without API access: play with a temporary profile that is never saved.
				warn("[DataService] Using a temporary profile. Enable 'Studio Access to API Services' to test saving.")
				local profile = newProfile()
				profile.temporary = true
				profiles[player] = profile
				loaded:Fire(player, profile)
				return
			end
			break
		end
		task.wait(5) -- another server still holds the session; wait for it to release
	end
	player:Kick("Couldn't load your data. Please rejoin in a moment.")
end

local function save(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not store or profile.temporary then
		return
	end
	local ds = store :: DataStore
	local jobId = if RunService:IsStudio() then "studio" else game.JobId
	local ok, err = retry(function()
		return ds:UpdateAsync(key(player), function(old)
			old = old or {}
			if old.lock and old.lock.job ~= jobId then
				return nil -- someone else owns this session now; don't clobber
			end
			local data = table.clone(profile)
			data.lock = if release then nil else { job = jobId, time = os.time() }
			return data
		end)
	end, 3)
	if not ok then
		warn(`[DataService] save failed for {player.UserId}: {err}`)
	end
end

function DataService.get(player: Player): any?
	return profiles[player]
end

-- Waits for the profile (max ~30s).
function DataService.wait(player: Player): any?
	local t = 0
	while not profiles[player] and player.Parent and t < 30 do
		t += task.wait(0.1)
	end
	return profiles[player]
end

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end

Players.PlayerRemoving:Connect(function(player)
	save(player, true)
	profiles[player] = nil
end)

game:BindToClose(function()
	for player in profiles do
		task.spawn(save, player, true)
	end
	task.wait(3)
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player in profiles do
			task.spawn(save, player, false)
		end
	end
end)

return DataService
