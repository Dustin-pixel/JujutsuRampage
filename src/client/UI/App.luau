--!strict
-- Top-level UI: HUD (cursed energy, hotbar with cooldowns), the Builder window
-- (Techniques + VFX tabs), and shared dialogs (export code, import code, confirm).
-- Press B (or the "Builder" button) to toggle the builder.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)

local C = require(script.Parent.Components)
local SkillBuilder = require(script.Parent.SkillBuilder)
local VfxEditor = require(script.Parent.VfxEditor)
local Gallery = require(script.Parent.Gallery)
local Store = require(script.Parent.Parent.Store)
local InputController = require(script.Parent.Parent.InputController)

local T = C.Theme

local App = {}

function App.start()
	local player = Players.LocalPlayer
	local screen = C.new("ScreenGui", {
		Name = "JujutsuRampage",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	local app: any = {}

	function app.toast(text: string, color: Color3?)
		C.toast(screen, text, color)
	end

	-- Dialogs ---------------------------------------------------------------------------
	local function modal(title: string, height: number): (Frame, () -> ())
		local shade = C.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 40,
			Parent = screen,
		})
		local box = C.new("Frame", {
			BackgroundColor3 = T.Panel,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 480, 0, height),
			ZIndex = 41,
			Parent = shade,
		}, { C.corner(8), C.padding(12) })
		C.label(title, { Font = T.FontBold, TextSize = 16, ZIndex = 42, Parent = box })
		local function close()
			shade:Destroy()
		end
		return box, close
	end

	function app.showCode(title: string, code: string)
		local box, close = modal(title, 300)
		C.label("Click the box, press Ctrl+A then Ctrl+C to copy. Anyone can import this code.", {
			Position = UDim2.new(0, 0, 0, 28),
			TextWrapped = true,
			TextColor3 = T.SubText,
			TextSize = 12,
			Size = UDim2.new(1, 0, 0, 30),
			ZIndex = 42,
			Parent = box,
		})
		local text = C.textBox(code, function() end, {
			Position = UDim2.new(0, 0, 0, 62),
			Size = UDim2.new(1, 0, 1, -100),
			MultiLine = true,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextSize = 11,
			ZIndex = 42,
			Parent = box,
		})
		-- keep the text intact if the user types into it
		text:GetPropertyChangedSignal("Text"):Connect(function()
			if text.Text ~= code then
				text.Text = code
			end
		end)
		C.button("Close", nil, close, { Position = UDim2.new(1, -90, 1, -28), ZIndex = 42, Parent = box })
	end

	function app.showImport()
		local box, close = modal("Import a code", 300)
		C.label("Paste a technique or VFX code:", { Position = UDim2.new(0, 0, 0, 28), TextColor3 = T.SubText, ZIndex = 42, Parent = box })
		local input = C.textBox("", function() end, {
			Position = UDim2.new(0, 0, 0, 58),
			Size = UDim2.new(1, 0, 1, -96),
			MultiLine = true,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextSize = 11,
			PlaceholderText = "JJR1.M....",
			ZIndex = 42,
			Parent = box,
		})
		C.button("Import", T.Good, function()
			if #input.Text > Config.MaxCodeLength + 1000 then
				app.toast("That code is too long.", T.Danger)
				return
			end
			local result = Store.import(input.Text)
			if not result or not result.ok then
				app.toast("Import failed: " .. tostring(result and result.error), T.Danger)
				return
			end
			close()
			if result.kind == "moveset" then
				app.toast(`Imported technique "{result.value.name}"!`, T.Good)
				if result.errors and #result.errors > 0 then
					app.toast("It's over budget here, so fix it before equipping:\n" .. result.errors[1], T.Warn)
				end
				app.builder.open(result.slot)
				app.setTab("Techniques")
			else
				app.toast(`Imported effect "{result.value.name}"!`, T.Good)
				app.vfx.open(result.id)
				app.setTab("VFX")
			end
		end, { Position = UDim2.new(1, -184, 1, -28), ZIndex = 42, Parent = box })
		C.button("Cancel", nil, close, { Position = UDim2.new(1, -90, 1, -28), ZIndex = 42, Parent = box })
	end

	function app.confirm(text: string, onYes: () -> ())
		local box, close = modal("Are you sure?", 150)
		C.label(text, { Position = UDim2.new(0, 0, 0, 28), TextWrapped = true, Size = UDim2.new(1, 0, 0, 50), ZIndex = 42, Parent = box })
		C.button("Yes", T.Danger, function()
			close()
			onYes()
		end, { Position = UDim2.new(1, -184, 1, -28), ZIndex = 42, Parent = box })
		C.button("No", nil, close, { Position = UDim2.new(1, -90, 1, -28), ZIndex = 42, Parent = box })
	end

	-- HUD --------------------------------------------------------------------------------
	local hud = C.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, 520, 0, 86),
		Parent = screen,
	})
	local energyBack = C.new("Frame", { BackgroundColor3 = T.Background, Size = UDim2.new(1, 0, 0, 12), Parent = hud }, { C.corner(6) })
	local energyFill = C.new("Frame", { BackgroundColor3 = T.Accent, Size = UDim2.fromScale(1, 1), Parent = energyBack }, { C.corner(6) })
	local energyText = C.label("CE 100", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 10, Parent = energyBack })

	local hotbar = C.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 20), Size = UDim2.new(1, 0, 0, 64), Parent = hud }, {
		C.new("UIGridLayout", { CellSize = UDim2.new(1 / 6, -6, 1, 0), CellPadding = UDim2.new(0, 6, 0, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local slots = {}
	local cooldownEnds: { [number]: number } = {}
	local cooldownLengths: { [number]: number } = {}
	for i = 1, Config.Moveset.MaxMoves do
		local b = C.button("", T.Panel, function() end, { LayoutOrder = i, TextWrapped = true, TextSize = 11, Parent = hotbar })
		-- press/release so "Hold to Charge" moves work on touch and mouse too
		b.MouseButton1Down:Connect(function()
			InputController.useMove(i, "down")
		end)
		b.MouseButton1Up:Connect(function()
			InputController.useMove(i, "up")
		end)
		b.MouseLeave:Connect(function()
			InputController.useMove(i, "up")
		end)
		C.label(tostring(i), { Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 4, 0, 2), TextSize = 11, TextColor3 = T.SubText, Parent = b })
		local cover = C.new("Frame", {
			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = 0.45,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			Parent = b,
		}, { C.corner(5) })
		slots[i] = { button = b, cover = cover }
	end

	-- mobile: M1 + block buttons
	if UserInputService.TouchEnabled then
		C.button("M1", T.Accent, function()
			InputController.m1()
		end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -120), Size = UDim2.new(0, 70, 0, 70), Parent = screen })
		local blockBtn = C.button("Block", nil, function() end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -100, 1, -120), Size = UDim2.new(0, 60, 0, 60), Parent = screen })
		blockBtn.MouseButton1Down:Connect(function()
			InputController.setBlocking(true)
		end)
		blockBtn.MouseButton1Up:Connect(function()
			InputController.setBlocking(false)
		end)
	end

	local function refreshHotbar()
		local profile = Store.profile
		local moveset = profile and profile.slots[profile.equipped]
		for i, slot in slots do
			local move = moveset and moveset.moves[i]
			if move then
				local trig = move.trigger.type
				local suffix = if trig == "Press"
					then ""
					elseif trig == "Charge" then "\n(hold)"
					elseif trig == "Counter" then "\n(counter)"
					elseif trig == "Passive" then "\n(passive)"
					else "\n(finisher)"
				slot.button.Text = move.name .. suffix
			else
				slot.button.Text = ""
			end
		end
	end
	Store.Changed:Connect(refreshHotbar)

	Remotes.event("Cooldown").OnClientEvent:Connect(function(slot: number, seconds: number)
		cooldownEnds[slot] = os.clock() + seconds
		cooldownLengths[slot] = seconds
	end)
	Remotes.event("CombatState").OnClientEvent:Connect(function(state: any)
		energyFill.Size = UDim2.fromScale(math.clamp(state.energy / state.maxEnergy, 0, 1), 1)
		energyText.Text = `CE {state.energy}` .. (if state.stunned then "  · STUNNED" elseif state.blocking then "  · BLOCKING" else "")
	end)
	Remotes.event("Notify").OnClientEvent:Connect(function(text: string, kind: string)
		app.toast(text, if kind == "warn" then T.Warn else nil)
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for i, slot in slots do
			local left = (cooldownEnds[i] or 0) - t
			local length = cooldownLengths[i] or 1
			slot.cover.Size = UDim2.fromScale(1, if left > 0 then left / length else 0)
		end
	end)

	-- Builder window ---------------------------------------------------------------------------
	local window = C.new("Frame", {
		Visible = false,
		BackgroundColor3 = T.Background,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.86, 0),
		Parent = screen,
	}, { C.corner(10), C.padding(10), C.new("UISizeConstraint", { MaxSize = Vector2.new(1500, 900) }) })

	local tabs = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = window }, { C.list(6, true) })
	local pages = {
		Techniques = C.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, T.RowHeight + 8), Size = UDim2.new(1, 0, 1, -(T.RowHeight + 8)), Parent = window }),
		VFX = C.new("Frame", { Visible = false, BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, T.RowHeight + 8), Size = UDim2.new(1, 0, 1, -(T.RowHeight + 8)), Parent = window }),
		Gallery = C.new("Frame", { Visible = false, BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, T.RowHeight + 8), Size = UDim2.new(1, 0, 1, -(T.RowHeight + 8)), Parent = window }),
	}
	local tabButtons = {}
	function app.setTab(name: string)
		for n, page in pages do
			page.Visible = n == name and window.Visible
			tabButtons[n].BackgroundColor3 = if n == name then T.Accent else T.PanelLight
		end
		local changed = app.currentTab ~= name
		app.currentTab = name
		if name == "Gallery" and window.Visible and (changed or not app.galleryOpened) then
			app.galleryOpened = true
			app.gallery.open()
		end
	end
	for i, name in { "Techniques", "VFX", "Gallery" } do
		tabButtons[name] = C.button(name, nil, function()
			app.setTab(name)
		end, { LayoutOrder = i, Size = UDim2.new(0, 120, 1, 0), Parent = tabs })
	end
	C.label("JUJUTSU RAMPAGE · BUILDER", { LayoutOrder = 4, Size = UDim2.new(0, 260, 1, 0), Font = T.FontBold, TextColor3 = T.SubText, Parent = tabs })
	C.button("Close (B)", T.Danger, function()
		app.toggle(false)
	end, { LayoutOrder = 5, Size = UDim2.new(0, 100, 1, 0), Parent = tabs })

	app.builder = SkillBuilder.new(pages.Techniques, app)
	app.vfx = VfxEditor.new(pages.VFX, app)
	app.gallery = Gallery.new(pages.Gallery, app)
	app.currentTab = "Techniques"

	local openedOnce = false
	function app.toggle(open: boolean?)
		local show = if open == nil then not window.Visible else open
		if show and not Store.profile then
			Store.refresh()
		end
		window.Visible = show
		hud.Visible = not show
		InputController.enabled = not show
		if show and not openedOnce and Store.profile then
			openedOnce = true
			app.builder.open(if Store.profile.equipped > 0 then Store.profile.equipped else 1)
			app.vfx.open((next(Store.profile.vfx)))
		end
		app.setTab(app.currentTab)
	end

	C.button("Builder (B)", T.Accent, function()
		app.toggle()
	end, { AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 16, 0, 60), Size = UDim2.new(0, 110, 0, 32), Parent = screen })

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			app.toggle()
		end
	end)

	task.spawn(function()
		Store.refresh()
		refreshHotbar()
	end)

	return app
end

return App
