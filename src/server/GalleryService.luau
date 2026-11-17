--!strict
-- Public technique gallery: publish, browse (recent / top), like, report and
-- one-click import.
--
-- Storage (DataStore "Gallery_v1"):
--   "index"              -> { entries = { meta... } }  (up to MAX_INDEX entries, no codes)
--   "code_<id>"          -> share code string           (written once on publish)
--   "vote_<id>_<userId>" -> "like" | "report"           (one vote of each kind per player)
--
-- A single DataStore key can only be written about every 6 seconds, so this
-- server batches index changes (new entries, like/report deltas, removals) and
-- merges them into the index with one UpdateAsync every FLUSH_INTERVAL.
-- Reads are cached for Config.Gallery.CacheSeconds.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sanitize = require(Shared.Validate.Sanitize)
local ExportCode = require(Shared.Codec.ExportCode)
local MovesetValidator = require(Shared.Validate.MovesetValidator)

local DataService = require(script.Parent.DataService)
local MovesetService = require(script.Parent.MovesetService)
local RateLimiter = require(script.Parent.RateLimiter)

local G = Config.Gallery
local MAX_INDEX = 500
local KEEP_TOP = 60 -- most-liked entries are never pushed out by new ones
local FLUSH_INTERVAL = 20

local GalleryService = {}

export type Meta = {
	id: string,
	name: string,
	description: string,
	author: number,
	authorName: string,
	moves: { string },
	likes: number,
	reports: number,
	time: number,
}

-- Storage backend (DataStore, or memory when unavailable) -----------------------

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("Gallery_v1")
end)
local memory: { [string]: any } = {}
local useMemory = store == nil

local function dsGet(key: string): any
	if useMemory then
		return memory[key]
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(key)
	end)
	if not ok then
		warn("[Gallery] GetAsync failed, switching to memory: " .. tostring(result))
		useMemory = true
		return memory[key]
	end
	return result
end

local function dsUpdate(key: string, fn: (any) -> any): (boolean, any)
	if useMemory then
		local result = fn(memory[key])
		if result ~= nil then
			memory[key] = result
		end
		return true, result
	end
	return pcall(function()
		return (store :: DataStore):UpdateAsync(key, fn)
	end)
end

-- Index cache + pending changes ------------------------------------------------------

local cachedIndex: { Meta } = {}
local cachedAt = -math.huge

local pending = {
	adds = {} :: { Meta },
	removes = {} :: { [string]: boolean },
	likes = {} :: { [string]: number },
	reports = {} :: { [string]: number },
}

local function cleanMeta(raw: any): Meta?
	if type(raw) ~= "table" or Sanitize.id(raw.id) == "" then
		return nil
	end
	local moves = {}
	if type(raw.moves) == "table" then
		for i = 1, Config.Moveset.MaxMoves do
			if type(raw.moves[i]) == "string" then
				table.insert(moves, Sanitize.text(raw.moves[i], Config.Moveset.MaxNameLength))
			end
		end
	end
	return {
		id = raw.id,
		name = Sanitize.text(raw.name, Config.Moveset.MaxNameLength, "Technique"),
		description = Sanitize.text(raw.description, G.MaxDescriptionLength, ""),
		author = Sanitize.int(raw.author, 0, 0),
		authorName = Sanitize.text(raw.authorName, 40, "?"),
		moves = moves,
		likes = Sanitize.int(raw.likes, 0, 0),
		reports = Sanitize.int(raw.reports, 0, 0),
		time = Sanitize.number(raw.time, 0, 0),
	}
end

local function applyPending(entries: { Meta }): { Meta }
	local out = {}
	local seen = {}
	for _, add in pending.adds do
		if not pending.removes[add.id] then
			table.insert(out, table.clone(add))
			seen[add.id] = true
		end
	end
	for _, e in entries do
		if not pending.removes[e.id] and not seen[e.id] then
			local copy = table.clone(e)
			copy.likes += pending.likes[e.id] or 0
			copy.reports += pending.reports[e.id] or 0
			table.insert(out, copy)
			seen[e.id] = true
		end
	end
	return out
end

local function trim(entries: { Meta }): { Meta }
	if #entries <= MAX_INDEX then
		return entries
	end
	local byLikes = table.clone(entries)
	table.sort(byLikes, function(a, b)
		return a.likes > b.likes
	end)
	local keep = {}
	for i = 1, math.min(KEEP_TOP, #byLikes) do
		keep[byLikes[i].id] = true
	end
	table.sort(entries, function(a, b)
		return a.time > b.time
	end)
	local out = {}
	for _, e in entries do
		if #out < MAX_INDEX and (keep[e.id] or #out < MAX_INDEX - KEEP_TOP) then
			table.insert(out, e)
		end
	end
	return out
end

local function readIndex(): { Meta }
	if os.clock() - cachedAt < G.CacheSeconds then
		return cachedIndex
	end
	local raw = dsGet("index")
	local entries = {}
	if type(raw) == "table" and type(raw.entries) == "table" then
		for _, e in raw.entries do
			local m = cleanMeta(e)
			if m then
				table.insert(entries, m)
			end
		end
	end
	cachedIndex = entries
	cachedAt = os.clock()
	return entries
end

local function flush()
	local hasWork = #pending.adds > 0 or next(pending.removes) ~= nil or next(pending.likes) ~= nil or next(pending.reports) ~= nil
	if not hasWork then
		return
	end
	-- snapshot and clear so new changes during the yield aren't lost
	local snapshot = pending
	pending = { adds = {}, removes = {}, likes = {}, reports = {} }
	local ok, result = dsUpdate("index", function(old)
		local entries = {}
		if type(old) == "table" and type(old.entries) == "table" then
			for _, e in old.entries do
				local m = cleanMeta(e)
				if m then
					table.insert(entries, m)
				end
			end
		end
		local byId = {}
		for _, e in entries do
			byId[e.id] = e
		end
		for id, d in snapshot.likes do
			if byId[id] then
				byId[id].likes = math.max(0, byId[id].likes + d)
			end
		end
		for id, d in snapshot.reports do
			if byId[id] then
				byId[id].reports += d
			end
		end
		for _, add in snapshot.adds do
			if not byId[add.id] then
				table.insert(entries, add)
				byId[add.id] = add
			end
		end
		local out = {}
		for _, e in entries do
			if not snapshot.removes[e.id] then
				table.insert(out, e)
			end
		end
		return { entries = trim(out) }
	end)
	if ok then
		cachedAt = -math.huge -- re-read next time
	else
		warn("[Gallery] flush failed, will retry: " .. tostring(result))
		-- put the changes back
		for _, add in snapshot.adds do
			table.insert(pending.adds, add)
		end
		for id in snapshot.removes do
			pending.removes[id] = true
		end
		for id, d in snapshot.likes do
			pending.likes[id] = (pending.likes[id] or 0) + d
		end
		for id, d in snapshot.reports do
			pending.reports[id] = (pending.reports[id] or 0) + d
		end
	end
end

task.spawn(function()
	while true do
		task.wait(FLUSH_INTERVAL)
		flush()
	end
end)
game:BindToClose(flush)

-- Helpers -------------------------------------------------------------------------------

local lastPublish: { [Player]: number } = {}
local sessionVotes: { [string]: boolean } = {} -- "<kind>_<id>_<userId>" seen this server
Players.PlayerRemoving:Connect(function(player)
	lastPublish[player] = nil
end)

local function visible(entries: { Meta }): { Meta }
	local out = {}
	for _, e in entries do
		if e.reports < G.HideAtReports then
			table.insert(out, e)
		end
	end
	return out
end

local function findEntry(id: string): Meta?
	for _, e in applyPending(readIndex()) do
		if e.id == id then
			return e
		end
	end
	return nil
end

local function toClient(e: Meta, player: Player): any
	return {
		id = e.id,
		name = e.name,
		description = e.description,
		authorName = e.authorName,
		moves = e.moves,
		likes = e.likes,
		time = e.time,
		mine = e.author == player.UserId,
		liked = sessionVotes[`like_{e.id}_{player.UserId}`] == true,
	}
end

-- Records one vote per (kind, entry, player) across servers. Returns true if new.
local function vote(kind: string, id: string, userId: number): boolean
	local sessionKey = `{kind}_{id}_{userId}`
	if sessionVotes[sessionKey] then
		return false
	end
	local isNew = false
	local ok = dsUpdate(`{kind}_{id}_{userId}`, function(old)
		if old ~= nil then
			isNew = false
			return nil -- already voted; cancel
		end
		isNew = true
		return true
	end)
	if ok then
		sessionVotes[sessionKey] = true
	end
	return ok and isNew
end

-- Remotes ----------------------------------------------------------------------------------

Remotes.func("GalleryList").OnServerInvoke = function(player, sort: any, page: any)
	if not RateLimiter.check(player, "Gallery", Config.RateLimit.Gallery) then
		return { entries = {}, hasMore = false, error = "Slow down a little." }
	end
	local entries = visible(applyPending(readIndex()))
	if sort == "top" then
		table.sort(entries, function(a, b)
			if a.likes == b.likes then
				return a.time > b.time
			end
			return a.likes > b.likes
		end)
	else
		table.sort(entries, function(a, b)
			return a.time > b.time
		end)
	end
	local p = math.max(1, math.floor(tonumber(page) or 1))
	local out = {}
	for i = (p - 1) * G.PageSize + 1, math.min(#entries, p * G.PageSize) do
		table.insert(out, toClient(entries[i], player))
	end
	return { entries = out, hasMore = #entries > p * G.PageSize, page = p }
end

Remotes.func("GalleryMine").OnServerInvoke = function(player)
	local out = {}
	for _, e in applyPending(readIndex()) do
		if e.author == player.UserId then
			table.insert(out, toClient(e, player))
		end
	end
	return { entries = out }
end

Remotes.func("GalleryPublish").OnServerInvoke = function(player, slotIndex: any, description: any)
	local profile = DataService.get(player)
	if not profile then
		return false, "Profile not loaded yet."
	end
	if type(slotIndex) ~= "number" or not profile.slots[slotIndex] then
		return false, "Pick a saved technique to publish."
	end
	local now = os.clock()
	if lastPublish[player] and now - lastPublish[player] < G.PublishCooldown then
		return false, `Wait {math.ceil(G.PublishCooldown - (now - lastPublish[player]))}s before publishing again.`
	end
	if #profile.published >= G.MaxPublishedPerPlayer then
		return false, `You can have {G.MaxPublishedPerPlayer} techniques published. Unpublish one first.`
	end
	local moveset = profile.slots[slotIndex]
	local result = MovesetValidator.moveset(moveset)
	if not result.ok then
		return false, "Only techniques you can equip (within budget) can be published."
	end
	lastPublish[player] = now

	local id = string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 12)
	local code = ExportCode.encode("moveset", result.value)
	local ok, err = dsUpdate("code_" .. id, function()
		return code
	end)
	if not ok then
		return false, "Couldn't publish right now: " .. tostring(err)
	end
	local moves = {}
	for _, m in result.value.moves do
		table.insert(moves, m.name)
	end
	local meta: Meta = {
		id = id,
		name = result.value.name, -- already filtered on save
		description = MovesetService.filter(Sanitize.text(description, G.MaxDescriptionLength, ""), player.UserId),
		author = player.UserId,
		authorName = player.Name,
		moves = moves,
		likes = 0,
		reports = 0,
		time = os.time(),
	}
	table.insert(pending.adds, meta)
	table.insert(profile.published, id)
	return true, id
end

Remotes.func("GalleryUnpublish").OnServerInvoke = function(player, id: any)
	local profile = DataService.get(player)
	if not profile or type(id) ~= "string" then
		return false
	end
	local i = table.find(profile.published, id)
	local entry = findEntry(id)
	if not i and not (entry and entry.author == player.UserId) then
		return false
	end
	if i then
		table.remove(profile.published, i)
	end
	pending.removes[id] = true
	return true
end

Remotes.func("GalleryLike").OnServerInvoke = function(player, id: any)
	if not RateLimiter.check(player, "Gallery", Config.RateLimit.Gallery) or type(id) ~= "string" then
		return false
	end
	local entry = findEntry(id)
	if not entry or entry.author == player.UserId then
		return false
	end
	if vote("like", id, player.UserId) then
		pending.likes[id] = (pending.likes[id] or 0) + 1
		return true, entry.likes + 1
	end
	return false, entry.likes
end

Remotes.func("GalleryReport").OnServerInvoke = function(player, id: any)
	if not RateLimiter.check(player, "Gallery", Config.RateLimit.Gallery) or type(id) ~= "string" then
		return false
	end
	local entry = findEntry(id)
	if not entry or entry.author == player.UserId then
		return false
	end
	if vote("report", id, player.UserId) then
		pending.reports[id] = (pending.reports[id] or 0) + 1
	end
	return true
end

Remotes.func("GalleryImport").OnServerInvoke = function(player, id: any)
	if not RateLimiter.check(player, "Import", Config.RateLimit.Import) then
		return { ok = false, error = "You're importing too fast." }
	end
	if type(id) ~= "string" or Sanitize.id(id) == "" then
		return { ok = false, error = "Unknown entry." }
	end
	local entry = findEntry(id)
	if not entry or entry.reports >= G.HideAtReports then
		return { ok = false, error = "That technique is no longer available." }
	end
	local code = dsGet("code_" .. id)
	if type(code) ~= "string" then
		return { ok = false, error = "Couldn't load that technique." }
	end
	-- Same path as a pasted code: decoded as data, validated, filtered.
	return MovesetService.importCode(player, code)
end

return GalleryService
