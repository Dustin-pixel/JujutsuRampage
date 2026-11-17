--!strict
-- Domain Expansions: the barrier, who is inside, trapping, and clashes.
--
-- Clash rule: when a new domain overlaps an active domain of another fighter,
-- the higher refinement wins and the other collapses immediately. Equal
-- refinement collapses both. The barrier is a server-side sphere so every
-- client sees it; extra visuals come from the move's own VFX.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local CombatService = require(script.Parent.CombatService)

local DomainService = {}

export type Domain = {
	caster: Model,
	center: Vector3,
	radius: number,
	refinement: number,
	trap: boolean,
	sureHit: boolean,
	closed: boolean,
	barrier: BasePart,
	trapped: { [Model]: boolean },
	close: (reason: string?) -> (),
	inside: () -> { Model },
}

local active: { Domain } = {}
local domainEvent = Remotes.event("Domain")

local function notifyNearby(center: Vector3, radius: number, phase: string, info: any)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and CombatService.root(character)
		if root and (root.Position - center).Magnitude <= radius + 40 then
			domainEvent:FireClient(player, phase, info)
		end
	end
end

local function makeBarrier(center: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = "DomainBarrier"
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.ForceField
	p.Color = color
	p.Transparency = 0.15
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.one
	p.CFrame = CFrame.new(center)
	p.Parent = workspace
	return p
end

function DomainService.activeFor(caster: Model): Domain?
	for _, d in active do
		if d.caster == caster and not d.closed then
			return d
		end
	end
	return nil
end

function DomainService.isInside(model: Model, domain: Domain): boolean
	local r = CombatService.root(model)
	return r ~= nil and (r.Position - domain.center).Magnitude <= domain.radius
end

-- Opens a domain. Returns the domain, or nil + "clash_lost" if an existing
-- domain overpowered it.
function DomainService.open(caster: Model, radius: number, refinement: number, trap: boolean, color: Color3): (Domain?, string?)
	local root = CombatService.root(caster)
	if not root then
		return nil, "no_root"
	end
	local center = root.Position

	-- Clash with overlapping domains of other fighters.
	local lost = false
	for _, other in table.clone(active) do
		if not other.closed and other.caster ~= caster and (other.center - center).Magnitude < other.radius + radius then
			notifyNearby(center, radius, "clash", { winner = if other.refinement > refinement then "existing" elseif other.refinement < refinement then "new" else "none" })
			if other.refinement >= refinement then
				lost = true
			end
			if other.refinement <= refinement then
				other.close("clash")
			end
		end
	end
	if lost then
		return nil, "clash_lost"
	end

	local barrier = makeBarrier(center, color)
	TweenService:Create(barrier, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
	}):Play()

	local domain: Domain
	local conn: RBXScriptConnection
	domain = {
		caster = caster,
		center = center,
		radius = radius,
		refinement = refinement,
		trap = trap,
		sureHit = false, -- set by the Domain block
		closed = false,
		barrier = barrier,
		trapped = {},
		close = function(reason: string?)
			if domain.closed then
				return
			end
			domain.closed = true
			conn:Disconnect()
			local i = table.find(active, domain)
			if i then
				table.remove(active, i)
			end
			notifyNearby(center, radius, "close", { reason = reason })
			local t = TweenService:Create(barrier, TweenInfo.new(0.4), { Size = Vector3.one, Transparency = 1 })
			t:Play()
			t.Completed:Once(function()
				barrier:Destroy()
			end)
		end,
		inside = function(): { Model }
			local out = {}
			for _, model in CombatService.query(caster, CFrame.new(center), Vector3.one * radius * 2, "Sphere") do
				table.insert(out, model)
			end
			return out
		end,
	}

	-- Everyone inside when it opens is trapped (pushed back if they reach the edge).
	if trap then
		for _, model in domain.inside() do
			domain.trapped[model] = true
		end
	end
	conn = RunService.Heartbeat:Connect(function()
		if not CombatService.isAlive(caster) then
			domain.close("caster_down")
			return
		end
		if not domain.trap then
			return
		end
		for model in domain.trapped do
			local r = CombatService.root(model)
			if not r or not CombatService.isAlive(model) then
				domain.trapped[model] = nil
				continue
			end
			local offset = r.Position - center
			if offset.Magnitude > radius - 2 then
				local inward = -offset.Unit
				r.CFrame = CFrame.new(center + offset.Unit * (radius - 3)) * r.CFrame.Rotation
				r.AssemblyLinearVelocity = inward * 20
			end
		end
	end)

	table.insert(active, domain)
	notifyNearby(center, radius, "open", { color = color, radius = radius, center = center })
	return domain, nil
end

return DomainService
