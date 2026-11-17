--!strict
-- Client-side copy of the player's profile (techniques + VFX library) with a
-- change signal for the UI. The server is authoritative; after each change we
-- apply what the server returned.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Store = {}

Store.profile = nil :: any
local changed = Instance.new("BindableEvent")
Store.Changed = changed.Event

function Store.refresh()
	local profile = Remotes.func("GetProfile"):InvokeServer()
	if profile then
		Store.profile = profile
		changed:Fire()
	end
	return profile
end

function Store.saveMoveset(slot: number, moveset: any): any
	local result = Remotes.func("SaveMoveset"):InvokeServer(slot, moveset)
	if result and result.value then
		Store.profile.slots[slot] = result.value
		changed:Fire()
	end
	return result
end

function Store.deleteMoveset(slot: number)
	if Remotes.func("DeleteMoveset"):InvokeServer(slot) then
		Store.refresh()
	end
end

function Store.equip(slot: number): (boolean, string?)
	local ok, err = Remotes.func("EquipMoveset"):InvokeServer(slot)
	if ok then
		Store.profile.equipped = slot
		changed:Fire()
	end
	return ok, err
end

function Store.saveVfx(id: string?, effect: any): (string?, any)
	local newId, result = Remotes.func("SaveVfx"):InvokeServer(id, effect)
	if newId then
		Store.profile.vfx[newId] = result
		changed:Fire()
	end
	return newId, result
end

function Store.deleteVfx(id: string)
	if Remotes.func("DeleteVfx"):InvokeServer(id) then
		Store.profile.vfx[id] = nil
		changed:Fire()
	end
end

function Store.export(kind: string, which: any): (string?, string?)
	return Remotes.func("ExportCode"):InvokeServer(kind, which)
end

function Store.import(code: string): any
	local result = Remotes.func("ImportCode"):InvokeServer(code)
	if result and result.ok then
		Store.refresh()
	end
	return result
end

return Store
