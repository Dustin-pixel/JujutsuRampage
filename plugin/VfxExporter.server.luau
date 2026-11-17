--!strict
-- JujutsuRampage VFX Exporter (Studio plugin)
--
-- Design an effect in Studio with real ParticleEmitters, Beams, PointLights,
-- MeshParts or Parts with a SpecialMesh. Select the root Part/Model/Attachment
-- and click "Export VFX". You get a code to paste into the in-game VFX tab.
--
-- The place must contain the synced game code (ReplicatedStorage.Shared),
-- because the exporter reuses the game's own schema, validator and codec.
-- Anything the game doesn't support is dropped, and values get clamped exactly
-- like an in-game import, so what you export is what players see.
--
-- Optional attributes for timing (put them on the emitter / beam / light / mesh part):
--   Delay (number)          seconds before the layer starts
--   EmitCount (number)      particles emitted in one burst when the effect plays
--   Duration (number)       beam / light / mesh animation length
--   EndScale (Vector3)      mesh: scale multiplier at the end (default 2,2,2)
--   EndTransparency (number) mesh: transparency at the end (default 1)
--   Spin (Vector3)          mesh: degrees per second
--   Easing (string)         mesh: Linear, Quad, Cubic, Quart, Exponential, Back, Sine

local Selection = game:GetService("Selection")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local toolbar = plugin:CreateToolbar("JujutsuRampage")
local button = toolbar:CreateButton("Export VFX", "Turn the selected effect into a JujutsuRampage VFX code", "rbxassetid://4458901886")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"JJRVfxExporter",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 420, 300, 300, 200)
)
widget.Title = "JJR VFX Exporter"

local output = Instance.new("TextBox")
output.Size = UDim2.fromScale(1, 1)
output.MultiLine = true
output.TextWrapped = true
output.ClearTextOnFocus = false
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.Font = Enum.Font.Code
output.TextSize = 12
output.Text = "Select an effect and click Export VFX."
output.Parent = widget

local function round(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end

local function attr(inst: Instance, name: string, default: any): any
	local v = inst:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

local function v3(v: Vector3): { number }
	return { round(v.X), round(v.Y), round(v.Z) }
end

local function worldCFrame(inst: Instance): CFrame?
	if inst:IsA("BasePart") then
		return inst.CFrame
	elseif inst:IsA("Attachment") then
		return inst.WorldCFrame
	elseif inst:IsA("Model") then
		return inst:GetPivot()
	end
	return nil
end

-- Position of whatever holds the effect, relative to the selected root.
local function offsetOf(holder: Instance, rootCf: CFrame): { number }
	local cf = worldCFrame(holder)
	if not cf then
		return { 0, 0, 0 }
	end
	return v3(rootCf:PointToObjectSpace(cf.Position))
end

-- Returns the code (only the code, so it can be copied as-is) or nil + error.
-- Notes about dropped / adjusted layers go to the Output window.
local function export(root: Instance): (string?, string?)
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if not Shared then
		return nil, "ReplicatedStorage.Shared not found. Open the place that has the synced game code (rojo serve)."
	end
	local VfxSchema = require(Shared.Vfx.VfxSchema) :: any
	local VfxSerialize = require(Shared.Vfx.VfxSerialize) :: any
	local VfxValidator = require(Shared.Validate.VfxValidator) :: any
	local ExportCode = require(Shared.Codec.ExportCode) :: any

	local rootCf = worldCFrame(root) or CFrame.identity
	local layers = {}
	local notes = {}

	local function readProps(inst: Instance, kind: string): { [string]: any }
		local props = {}
		for _, def in VfxSchema.Kinds[kind] do
			local ok, value = pcall(function()
				return (inst :: any)[def.key]
			end)
			if ok and value ~= nil then
				props[def.key] = VfxSerialize.encodeProp(def.type, value)
			end
		end
		props.Delay = attr(inst, "Delay", 0)
		return props
	end

	local items = { root }
	for _, d in root:GetDescendants() do
		table.insert(items, d)
	end

	for _, inst in items do
		if inst:IsA("ParticleEmitter") then
			local props = readProps(inst, "Emitter")
			props.EmitCount = attr(inst, "EmitCount", if inst.Rate == 0 then 20 else 0)
			local parent = inst.Parent
			if parent and parent:IsA("BasePart") then
				props.EmitterSize = v3(parent.Size)
			else
				props.EmitterSize = { 0.1, 0.1, 0.1 }
			end
			table.insert(layers, { kind = "Emitter", name = inst.Name, offset = offsetOf(parent :: Instance, rootCf), props = props })
		elseif inst:IsA("Beam") then
			local props = readProps(inst, "Beam")
			local a0, a1 = inst.Attachment0, inst.Attachment1
			props.Length = if a0 and a1 then round((a1.WorldPosition - a0.WorldPosition).Magnitude) else 10
			props.Duration = attr(inst, "Duration", 0.5)
			table.insert(layers, { kind = "Beam", name = inst.Name, offset = if a0 then offsetOf(a0, rootCf) else { 0, 0, 0 }, props = props })
			if a0 and a1 then
				table.insert(notes, `Beam "{inst.Name}" is exported pointing forward (-Z) with length {props.Length}.`)
			end
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") then
			table.insert(layers, {
				kind = "Light",
				name = inst.Name,
				offset = offsetOf(inst.Parent :: Instance, rootCf),
				props = {
					Color = VfxSerialize.fromColor3(inst.Color),
					Brightness = inst.Brightness,
					Range = inst.Range,
					Duration = attr(inst, "Duration", 0.3),
					Delay = attr(inst, "Delay", 0),
				},
			})
		elseif inst:IsA("MeshPart") or (inst:IsA("BasePart") and inst:FindFirstChildOfClass("SpecialMesh")) then
			local part = inst :: BasePart
			local props: { [string]: any } = {
				Color = VfxSerialize.fromColor3(part.Color),
				Material = part.Material.Name,
				StartTransparency = part.Transparency,
				EndTransparency = attr(part, "EndTransparency", 1),
				Duration = attr(part, "Duration", 0.5),
				Easing = attr(part, "Easing", "Quad"),
				Delay = attr(part, "Delay", 0),
			}
			local scale: Vector3
			if part:IsA("MeshPart") then
				props.Shape = "FileMesh"
				props.MeshId = VfxSerialize.assetIdFromUrl(part.MeshId)
				props.TextureId = VfxSerialize.assetIdFromUrl(part.TextureID)
				local ok, meshSize = pcall(function()
					return (part :: any).MeshSize
				end)
				scale = if ok and meshSize and meshSize.Magnitude > 0 then part.Size / meshSize else Vector3.one
			else
				local mesh = part:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh
				if mesh.MeshType == Enum.MeshType.FileMesh then
					props.Shape = "FileMesh"
					props.MeshId = VfxSerialize.assetIdFromUrl(mesh.MeshId)
					props.TextureId = VfxSerialize.assetIdFromUrl(mesh.TextureId)
					scale = mesh.Scale
				else
					props.Shape = mesh.MeshType.Name
					scale = mesh.Scale * part.Size -- the game's carrier part is 1x1x1
				end
			end
			local endMult = attr(part, "EndScale", Vector3.new(2, 2, 2))
			props.StartScale = v3(scale)
			props.EndScale = v3(scale * endMult)
			local rx, ry, rz = rootCf:ToObjectSpace(part.CFrame):ToOrientation()
			props.Rotation = { round(math.deg(rx)), round(math.deg(ry)), round(math.deg(rz)) }
			local spin = attr(part, "Spin", Vector3.zero)
			props.Spin = v3(spin)
			table.insert(layers, { kind = "Mesh", name = part.Name, offset = offsetOf(part, rootCf), props = props })
		end
	end

	if #layers == 0 then
		return nil, "No ParticleEmitters, Beams, Lights or meshes found in the selection."
	end

	local effect, err = VfxValidator.effect({ name = root.Name, layers = layers })
	if not effect then
		return nil, err
	end
	local dropped = #layers - #effect.layers
	if dropped > 0 then
		table.insert(notes, `{dropped} layer(s) dropped (max {#effect.layers}).`)
	end
	local code = ExportCode.encode("vfx", effect)
	print(`[JJR VFX Exporter] "{effect.name}": {#effect.layers} layer(s), code length {#code}.`)
	for _, note in notes do
		print("[JJR VFX Exporter] " .. note)
	end
	return code, nil
end

button.Click:Connect(function()
	widget.Enabled = true
	local selected = Selection:Get()[1]
	if not selected then
		output.Text = "Select the Part, Model or Attachment that holds your effect first."
		return
	end
	local ok, code, err = pcall(export, selected)
	if not ok then
		output.Text = "Export failed: " .. tostring(code)
	elseif not code then
		output.Text = "Export failed: " .. tostring(err)
	else
		output.Text = code
	end
end)
