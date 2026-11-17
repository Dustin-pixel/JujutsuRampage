--!strict
-- Builds and plays a validated VFX effect definition. Client-side only: the
-- server never creates particles, it tells clients what to play (VfxService).
--
--   local handle = VfxBuilder.play(effect, { cframe = cf })            -- world position
--   local handle = VfxBuilder.play(effect, { part = hrp, offset = cf }) -- follows a part
--   handle.destroy()
--
-- Every layer gets its own invisible carrier part welded to a root part, so
-- emitter shapes (Box/Sphere/...) use EmitterSize and meshes can spin.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(script.Parent.Parent.Config)
local VfxSchema = require(script.Parent.VfxSchema)
local S = require(script.Parent.VfxSerialize)

local VfxBuilder = {}

export type PlayOptions = {
	cframe: CFrame?,
	part: BasePart?, -- follow this part
	offset: CFrame?,
	lifetime: number?, -- override; clamped to Config.Vfx.MaxDuration
	parent: Instance?, -- default workspace (the preview uses a WorldModel)
	loop: boolean?, -- editor preview: replay continuously until destroyed
}

export type Handle = {
	root: BasePart,
	destroy: () -> (),
	replay: () -> (),
}

local EMITTER_DIRECT = {
	"Texture", "Color", "Size", "Transparency", "Squash", "Lifetime", "Speed", "Rotation", "RotSpeed",
	"SpreadAngle", "Acceleration", "Drag", "Rate", "LightEmission", "LightInfluence", "Brightness",
	"ZOffset", "LockedToPart", "FlipbookFramerate",
}

local EMITTER_ENUMS: { [string]: any } = {
	Orientation = Enum.ParticleOrientation,
	Shape = Enum.ParticleEmitterShape,
	ShapeStyle = Enum.ParticleEmitterShapeStyle,
	ShapeInOut = Enum.ParticleEmitterShapeInOut,
	FlipbookLayout = Enum.ParticleFlipbookLayout,
	FlipbookMode = Enum.ParticleFlipbookMode,
}

-- Enum lookups by name throw on unknown names; values are validated, but be safe.
local function enumItem(enumType: any, name: any, fallback: EnumItem?): EnumItem?
	local ok, item = pcall(function()
		return enumType[name]
	end)
	if ok and item then
		return item
	end
	return fallback
end

local function carrier(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	return p
end

local function weldTo(part: BasePart, root: BasePart, c0: CFrame): Weld
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = part
	w.C0 = c0
	w.Parent = part
	return w
end

local function rad3(v: { number }): CFrame
	return CFrame.fromOrientation(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
end

local function setProp(inst: Instance, kind: string, key: string, value: any)
	local def = VfxSchema.PropsByKind[kind][key]
	if def.type == "asset" and (value == nil or value == "") then
		return -- keep Roblox's default texture
	end
	local ok, err = pcall(function()
		(inst :: any)[key] = S.decodeProp(def.type, value)
	end)
	if not ok then
		warn(`[VFX] could not set {key}: {err}`)
	end
end

-- Builds a layer onto `root`. Returns a function that plays it once and the
-- time it needs to finish.
local function buildLayer(layer: any, root: BasePart, connections: { RBXScriptConnection }): ((() -> ()), number)
	local props = layer.props
	local offset = CFrame.new(layer.offset[1], layer.offset[2], layer.offset[3])
	local delay = props.Delay or 0

	if layer.kind == "Emitter" then
		local part = carrier(layer.name, S.toVector3(props.EmitterSize))
		weldTo(part, root, offset)
		part.Parent = root
		local pe = Instance.new("ParticleEmitter")
		pe.Name = layer.name
		for _, key in EMITTER_DIRECT do
			setProp(pe, "Emitter", key, props[key])
		end
		for key, enumType in EMITTER_ENUMS do
			local item = enumItem(enumType, props[key])
			if item then
				(pe :: any)[key] = item
			end
		end
		pe.Enabled = false
		pe.Parent = part
		local rate = props.Rate
		local maxLife = props.Lifetime[2]
		return function()
			task.delay(delay, function()
				if not pe.Parent then
					return
				end
				if props.EmitCount > 0 then
					pe:Emit(props.EmitCount)
				end
				if rate > 0 then
					pe.Enabled = true
				end
			end)
		end, delay + maxLife
	elseif layer.kind == "Mesh" then
		local part = carrier(layer.name, Vector3.one)
		part.Material = enumItem(Enum.Material, props.Material, Enum.Material.Neon) :: any
		part.Color = S.toColor3(props.Color)
		local weld = weldTo(part, root, offset * rad3(props.Rotation))
		local mesh = Instance.new("SpecialMesh")
		if props.Shape == "FileMesh" and props.MeshId ~= "" then
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = S.assetUrl(props.MeshId)
		else
			mesh.MeshType = enumItem(Enum.MeshType, props.Shape, Enum.MeshType.Sphere) :: any
			if mesh.MeshType == Enum.MeshType.FileMesh then
				mesh.MeshType = Enum.MeshType.Sphere -- FileMesh without an id
			end
		end
		mesh.TextureId = S.assetUrl(props.TextureId)
		mesh.VertexColor = Vector3.new(part.Color.R, part.Color.G, part.Color.B)
		mesh.Scale = S.toVector3(props.StartScale)
		mesh.Parent = part
		part.Parent = root
		local duration = props.Duration
		local style = enumItem(Enum.EasingStyle, props.Easing, Enum.EasingStyle.Quad) :: any
		local spin = S.toVector3(props.Spin)
		local baseC0 = weld.C0
		return function()
			mesh.Scale = S.toVector3(props.StartScale)
			part.Transparency = 1
			weld.C0 = baseC0
			task.delay(delay, function()
				if not part.Parent then
					return
				end
				part.Transparency = props.StartTransparency
				local info = TweenInfo.new(duration, style, Enum.EasingDirection.Out)
				TweenService:Create(mesh, info, { Scale = S.toVector3(props.EndScale) }):Play()
				TweenService:Create(part, info, { Transparency = props.EndTransparency }):Play()
				if spin.Magnitude > 0 then
					local elapsed = 0
					local conn: RBXScriptConnection
					conn = RunService.Heartbeat:Connect(function(dt)
						elapsed += dt
						if elapsed > duration or not weld.Parent then
							conn:Disconnect()
							return
						end
						weld.C0 = baseC0 * rad3({ spin.X * elapsed, spin.Y * elapsed, spin.Z * elapsed })
					end)
					table.insert(connections, conn)
				end
			end)
		end, delay + duration
	elseif layer.kind == "Beam" then
		local part = carrier(layer.name, Vector3.one * 0.2)
		weldTo(part, root, offset)
		local a0 = Instance.new("Attachment")
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 0, -props.Length)
		a1.Parent = part
		local beam = Instance.new("Beam")
		beam.Name = layer.name
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		for _, key in { "Texture", "Color", "Transparency", "Width0", "Width1", "CurveSize0", "CurveSize1", "TextureSpeed", "TextureLength", "LightEmission", "Segments" } do
			setProp(beam, "Beam", key, props[key])
		end
		beam.FaceCamera = true
		beam.Enabled = false
		beam.Parent = part
		part.Parent = root
		return function()
			beam.Enabled = false
			task.delay(delay, function()
				if beam.Parent then
					beam.Enabled = true
					task.delay(props.Duration, function()
						if beam.Parent then
							beam.Enabled = false
						end
					end)
				end
			end)
		end, delay + props.Duration
	elseif layer.kind == "Light" then
		local part = carrier(layer.name, Vector3.one * 0.2)
		weldTo(part, root, offset)
		local light = Instance.new("PointLight")
		light.Color = S.toColor3(props.Color)
		light.Range = props.Range
		light.Brightness = 0
		light.Parent = part
		part.Parent = root
		return function()
			light.Brightness = 0
			task.delay(delay, function()
				if not light.Parent then
					return
				end
				light.Brightness = props.Brightness
				TweenService:Create(light, TweenInfo.new(props.Duration), { Brightness = 0 }):Play()
			end)
		end, delay + props.Duration
	end
	return function() end, 0
end

function VfxBuilder.play(effect: any, options: PlayOptions): Handle
	local root = carrier("Vfx_" .. tostring(effect.name), Vector3.one * 0.2)
	local connections: { RBXScriptConnection } = {}
	local players: { () -> () } = {}
	local longest = 0
	for _, layer in effect.layers do
		local playFn, length = buildLayer(layer, root, connections)
		table.insert(players, playFn)
		longest = math.max(longest, length)
	end

	if options.part then
		root.CFrame = options.part.CFrame * (options.offset or CFrame.identity)
		weldTo(root, options.part, options.offset or CFrame.identity)
	else
		root.Anchored = true
		root.CFrame = (options.cframe or CFrame.identity) * (options.offset or CFrame.identity)
	end
	root.Parent = options.parent or workspace

	local destroyed = false
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		for _, c in connections do
			c:Disconnect()
		end
		root:Destroy()
	end

	local function replay()
		for _, fn in players do
			fn()
		end
	end
	replay()

	local maxDuration = Config.Vfx.MaxDuration
	if options.loop then
		task.spawn(function()
			while not destroyed do
				task.wait(math.clamp(longest, 0.5, maxDuration) + 0.25)
				if not destroyed then
					-- stop continuous emitters before replaying
					for _, d in root:GetDescendants() do
						if d:IsA("ParticleEmitter") then
							d.Enabled = false
							d:Clear()
						end
					end
					replay()
				end
			end
		end)
	else
		local lifetime = math.clamp(options.lifetime or longest, 0.1, maxDuration)
		-- stop emitting at `lifetime`, let particles fade, then clean up
		task.delay(lifetime, function()
			if destroyed then
				return
			end
			for _, d in root:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d.Enabled = false
				end
			end
		end)
		task.delay(lifetime + Config.Vfx.MaxLifetime, destroy)
		Debris:AddItem(root, lifetime + Config.Vfx.MaxLifetime + 1)
	end

	return { root = root, destroy = destroy, replay = replay }
end

return VfxBuilder
