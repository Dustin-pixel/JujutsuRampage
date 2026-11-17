--!strict
-- The VFX editor. An effect is a stack of layers (ParticleEmitter, Mesh, Beam,
-- Light). The preview plays in front of your character, locally, because
-- particles don't render inside ViewportFrames.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local VfxSchema = require(Shared.Vfx.VfxSchema)
local VfxBuilder = require(Shared.Vfx.VfxBuilder)
local VfxValidator = require(Shared.Validate.VfxValidator)

local C = require(script.Parent.Components)
local Store = require(script.Parent.Parent.Store)

local T = C.Theme

local VfxEditor = {}

local KIND_COLORS = {
	Emitter = Color3.fromRGB(240, 120, 200),
	Mesh = Color3.fromRGB(90, 200, 240),
	Beam = Color3.fromRGB(240, 200, 90),
	Light = Color3.fromRGB(250, 250, 160),
}

function VfxEditor.new(parent: GuiObject, app: any)
	local self = {
		effectId = nil :: string?,
		working = nil :: any,
		layerIndex = 1,
		preview = nil :: VfxBuilder.Handle?,
		previewOn = true,
	}

	local left = C.scroll({ Size = UDim2.new(0.22, -6, 1, 0), Parent = parent })
	local mid = C.scroll({ Position = UDim2.new(0.22, 0, 0, 0), Size = UDim2.new(0.3, -6, 1, 0), Parent = parent })
	local right = C.scroll({ Position = UDim2.new(0.52, 0, 0, 0), Size = UDim2.new(0.48, 0, 1, 0), Parent = parent })

	local render: () -> ()

	-- Preview ------------------------------------------------------------------------
	local previewToken = 0
	local function stopPreview()
		if self.preview then
			self.preview.destroy()
			self.preview = nil
		end
	end

	local function refreshPreview()
		previewToken += 1
		local token = previewToken
		task.delay(0.25, function() -- debounce rapid edits
			if token ~= previewToken then
				return
			end
			stopPreview()
			if not self.previewOn or not self.working or not parent.Visible then
				return
			end
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return
			end
			local clean = VfxValidator.effect(Util.deepCopy(self.working))
			if clean then
				self.preview = VfxBuilder.play(clean, {
					cframe = root.CFrame * CFrame.new(0, 0, -8) * CFrame.Angles(0, math.pi, 0),
					loop = true,
				})
			end
		end)
	end
	self.stopPreview = stopPreview
	self.refreshPreview = refreshPreview

	-- Opening ----------------------------------------------------------------------------
	function self.open(id: string?)
		local profile = Store.profile
		self.effectId = id
		if id and profile.vfx[id] then
			self.working = Util.deepCopy(profile.vfx[id])
		else
			self.working = VfxSchema.newEffect("New Effect")
		end
		self.layerIndex = 1
		render()
		refreshPreview()
	end

	-- Library ------------------------------------------------------------------------------
	local function renderLibrary()
		C.clear(left)
		C.label("VFX LIBRARY", { Font = T.FontBold, TextColor3 = T.SubText, Parent = left })
		local profile = Store.profile
		if not profile then
			return
		end
		local ids = {}
		for id in profile.vfx do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			return profile.vfx[a].name < profile.vfx[b].name
		end)
		for _, id in ids do
			C.button(profile.vfx[id].name, if id == self.effectId then T.Accent else T.PanelLight, function()
				self.open(id)
			end, { Size = UDim2.new(1, 0, 0, T.RowHeight), TextXAlignment = Enum.TextXAlignment.Left, Parent = left })
		end
		C.label(`{#ids} / {Config.Vfx.MaxLibrarySize}`, { TextColor3 = T.SubText, TextSize = 12, Parent = left })
		C.button("+ New effect", nil, function()
			self.open(nil)
		end, { Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = left })
		C.button("Import code", nil, function()
			app.showImport()
		end, { Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = left })
		C.label("Tip: design in Studio, then use the VFX Exporter plugin to get a code.", {
			TextWrapped = true,
			TextColor3 = T.SubText,
			TextSize = 11,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = left,
		})
	end

	-- Layers ---------------------------------------------------------------------------------
	local function renderLayers()
		C.clear(mid)
		local w = self.working
		if not w then
			return
		end
		C.label("Effect name", { TextColor3 = T.SubText, Parent = mid })
		C.textBox(w.name, function(text)
			w.name = text
		end, { Parent = mid })

		C.label("LAYERS", { Font = T.FontBold, TextColor3 = T.SubText, Parent = mid })
		for i, layer in w.layers do
			local row = C.new("Frame", {
				BackgroundColor3 = if i == self.layerIndex then T.PanelLight else T.Background,
				Size = UDim2.new(1, 0, 0, T.RowHeight),
				Parent = mid,
			}, { C.corner(4) })
			C.new("Frame", { BackgroundColor3 = KIND_COLORS[layer.kind], Size = UDim2.new(0, 4, 1, 0), Parent = row })
			C.button(`{layer.name}  ({layer.kind})`, Color3.new(), function()
				self.layerIndex = i
				render()
			end, {
				BackgroundTransparency = 1,
				Font = T.Font,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -96, 1, 0),
				Parent = row,
			})
			local function small(text: string, x: number, fn: () -> (), color: Color3?)
				C.button(text, color, fn, { Size = UDim2.new(0, 24, 0, 22), Position = UDim2.new(1, x, 0, 3), Parent = row })
			end
			small("↑", -82, function()
				if i > 1 then
					w.layers[i], w.layers[i - 1] = w.layers[i - 1], w.layers[i]
					self.layerIndex = i - 1
					render()
					refreshPreview()
				end
			end)
			small("↓", -55, function()
				if i < #w.layers then
					w.layers[i], w.layers[i + 1] = w.layers[i + 1], w.layers[i]
					self.layerIndex = i + 1
					render()
					refreshPreview()
				end
			end)
			small("✕", -28, function()
				table.remove(w.layers, i)
				self.layerIndex = math.clamp(self.layerIndex, 1, math.max(1, #w.layers))
				render()
				refreshPreview()
			end, T.Danger)
		end

		if #w.layers < Config.Vfx.MaxLayers then
			local addRow = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = mid }, {
				C.new("UIGridLayout", { CellSize = UDim2.new(0.25, -3, 1, 0), CellPadding = UDim2.new(0, 4, 0, 0) }),
			})
			for _, kind in VfxSchema.KindOrder do
				C.button("+" .. kind, KIND_COLORS[kind]:Lerp(T.PanelLight, 0.6), function()
					table.insert(w.layers, VfxSchema.newLayer(kind))
					self.layerIndex = #w.layers
					render()
					refreshPreview()
				end, { TextSize = 12, Parent = addRow })
			end
		end

		local full = UDim2.new(1, 0, 0, T.RowHeight)
		C.label("", { Size = UDim2.new(1, 0, 0, 6), Parent = mid })
		C.button(if self.previewOn then "Preview: ON" else "Preview: OFF", nil, function()
			self.previewOn = not self.previewOn
			render()
			refreshPreview()
		end, { Size = full, Parent = mid })
		C.button("Save effect", T.Good, function()
			local id, result = Store.saveVfx(self.effectId, w)
			if id then
				self.effectId = id
				self.working = Util.deepCopy(result)
				app.toast("Effect saved! Pick it in a Play VFX or Projectile block.", T.Good)
				render()
			else
				app.toast(tostring(result), T.Danger)
			end
		end, { Size = full, Parent = mid })
		C.button("Export code", nil, function()
			if not self.effectId then
				app.toast("Save it first.", T.Warn)
				return
			end
			local code, err = Store.export("vfx", self.effectId)
			if code then
				app.showCode("VFX code", code)
			else
				app.toast(tostring(err), T.Danger)
			end
		end, { Size = full, Parent = mid })
		C.button("Delete effect", T.Danger, function()
			local id = self.effectId
			if id then
				app.confirm(`Delete effect "{w.name}"? Techniques that use it will lose it next time you save them.`, function()
					Store.deleteVfx(id)
					self.open(nil)
				end)
			end
		end, { Size = full, Parent = mid })
	end

	-- Layer inspector -------------------------------------------------------------------------
	local function renderInspector()
		C.clear(right)
		local w = self.working
		local layer = w and w.layers[self.layerIndex]
		if not layer then
			C.label("Add a layer to start.", { TextColor3 = T.SubText, Parent = right })
			return
		end
		C.label(`{layer.kind} layer`, { Font = T.FontBold, TextColor3 = KIND_COLORS[layer.kind], Parent = right })
		local row, area = C.row("Layer name")
		C.textBox(layer.name, function(text)
			layer.name = text
			renderLayers()
		end, { Size = UDim2.new(1, 0, 1, 0), Parent = area })
		row.Parent = right
		C.vectorEditor({ label = "Offset", min = -20, max = 20 }, layer.offset, function(v)
			layer.offset = v
			refreshPreview()
		end).Parent = right

		local defs = table.clone(VfxSchema.Common)
		for _, def in VfxSchema.Kinds[layer.kind] do
			table.insert(defs, def)
		end
		for _, def in defs do
			local value = layer.props[def.key]
			if value == nil then
				value = Util.deepCopy(def.default)
				layer.props[def.key] = value
			end
			C.editor(def, value, function(v)
				layer.props[def.key] = v
				refreshPreview()
			end).Parent = right
		end
	end

	render = function()
		renderLibrary()
		renderLayers()
		renderInspector()
	end

	parent:GetPropertyChangedSignal("Visible"):Connect(function()
		if parent.Visible then
			refreshPreview()
		else
			stopPreview()
		end
	end)
	Store.Changed:Connect(function()
		if parent.Visible then
			renderLibrary()
		end
	end)

	return self
end

return VfxEditor
