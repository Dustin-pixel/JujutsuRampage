--!strict
-- The technique builder.
--
--  ┌ Techniques ┐┌ Moves 1..6 / trigger / block list ┐┌ Palette    ┐
--  │ slots      ││ Hitbox                            ││ Flow ...   │
--  │ name/desc  ││   ↳ onHit [+]                     ││ Combat ... │
--  │ save/equip ││     Damage 8                      │├ Inspector  ┤
--  │ export     ││ budget report                     ││ fields     │
--  └────────────┘└───────────────────────────────────┘└────────────┘
--
-- Edits happen on a local copy; "Save" sends it to the server, which
-- validates it and returns the cleaned version.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Blocks = require(Shared.Schema.Blocks)
local Triggers = require(Shared.Schema.Triggers)
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local MovesetValidator = require(Shared.Validate.MovesetValidator)

local C = require(script.Parent.Components)
local Store = require(script.Parent.Parent.Store)

local T = C.Theme

local SkillBuilder = {}

type Insert = { list: { any }, label: string }

function SkillBuilder.new(parent: GuiObject, app: any)
	local self = {
		slotIndex = 1,
		working = nil :: any,
		moveIndex = 1,
		selected = nil :: { list: { any }, index: number }?,
		insert = nil :: Insert?,
	}

	-- Columns ----------------------------------------------------------------
	local left = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.2, -6, 1, 0), Parent = parent })
	local mid = C.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.2, 0, 0, 0), Size = UDim2.new(0.45, -6, 1, 0), Parent = parent })
	local right = C.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.65, 0, 0, 0), Size = UDim2.new(0.35, 0, 1, 0), Parent = parent })

	local slotList = C.scroll({ Size = UDim2.new(1, 0, 0.45, -4), Parent = left })
	local techPanel = C.scroll({ Position = UDim2.new(0, 0, 0.45, 4), Size = UDim2.new(1, 0, 0.55, -4), Parent = left })

	local moveTabs = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = mid }, { C.list(4, true) })
	local moveHeader = C.scroll({ Position = UDim2.new(0, 0, 0, T.RowHeight + 6), Size = UDim2.new(1, 0, 0, 130), Parent = mid })
	local tree = C.scroll({ Position = UDim2.new(0, 0, 0, T.RowHeight + 142), Size = UDim2.new(1, 0, 1, -(T.RowHeight + 142) - 116), Parent = mid })
	local report = C.scroll({ Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1), Size = UDim2.new(1, 0, 0, 110), Parent = mid })

	local palette = C.scroll({ Size = UDim2.new(1, 0, 0.5, -4), Parent = right })
	local inspector = C.scroll({ Position = UDim2.new(0, 0, 0.5, 4), Size = UDim2.new(1, 0, 0.5, -4), Parent = right })

	local render: () -> ()

	local function currentMove(): any?
		return self.working and self.working.moves[self.moveIndex]
	end

	local function vfxOptions(): { any }
		local seen = {}
		local out = {}
		local profile = Store.profile
		for id, effect in (profile and profile.vfx) or {} do
			seen[id] = true
			table.insert(out, { id = id, name = effect.name })
		end
		for id, effect in (self.working and self.working.vfx) or {} do
			if not seen[id] then
				table.insert(out, { id = id, name = effect.name .. " (embedded)" })
			end
		end
		table.sort(out, function(a, b)
			return a.name < b.name
		end)
		return out
	end

	-- Opening a technique -------------------------------------------------------
	function self.open(slot: number)
		local profile = Store.profile
		self.slotIndex = slot
		local existing = profile and profile.slots[slot]
		if existing then
			self.working = Util.deepCopy(existing)
		else
			self.working = {
				name = "New Technique",
				description = "",
				color = { 140, 90, 255 },
				moves = { { name = "Move 1", cooldown = 3, trigger = { type = "Press", fields = {} }, blocks = {} } },
				vfx = {},
			}
		end
		self.moveIndex = 1
		self.selected = nil
		self.insert = nil
		render()
	end

	-- Left column ------------------------------------------------------------------
	local function renderSlots()
		C.clear(slotList)
		C.label("TECHNIQUES", { Font = T.FontBold, TextColor3 = T.SubText, Parent = slotList })
		local profile = Store.profile
		if not profile then
			return
		end
		for i, moveset in profile.slots do
			local label = (if profile.equipped == i then "★ " else "") .. moveset.name
			C.button(label, if i == self.slotIndex then T.Accent else T.PanelLight, function()
				self.open(i)
			end, { Size = UDim2.new(1, 0, 0, T.RowHeight), TextXAlignment = Enum.TextXAlignment.Left, Parent = slotList })
		end
		if #profile.slots < Config.Moveset.MaxSlotsSaved then
			C.button("+ New technique", T.PanelLight, function()
				self.open(#profile.slots + 1)
			end, { Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = slotList })
		end
	end

	local function renderTechPanel()
		C.clear(techPanel)
		local w = self.working
		if not w then
			return
		end
		C.label("Name", { TextColor3 = T.SubText, Parent = techPanel })
		C.textBox(w.name, function(text)
			w.name = text
		end, { Parent = techPanel })
		C.label("Description", { TextColor3 = T.SubText, Parent = techPanel })
		C.textBox(w.description, function(text)
			w.description = text
		end, { Size = UDim2.new(1, 0, 0, 56), MultiLine = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = techPanel })

		local full = UDim2.new(1, 0, 0, T.RowHeight)
		C.button("Save", T.Good, function()
			local result = Store.saveMoveset(self.slotIndex, w)
			if not result then
				return
			end
			if result.value then
				-- the server returns the cleaned copy; old list references are now stale
				self.working = Util.deepCopy(result.value)
				w = self.working
				self.selected = nil
				self.insert = nil
				self.moveIndex = math.max(1, math.min(self.moveIndex, #self.working.moves))
			end
			if result.ok then
				app.toast("Saved!", T.Good)
			else
				app.toast("Saved, but it can't be equipped yet:\n" .. table.concat(result.errors or {}, "\n"), T.Warn)
			end
			for _, warning in result.warnings or {} do
				app.toast(warning, T.Warn)
			end
			render()
		end, { Size = full, Parent = techPanel })
		C.button("Equip", T.Accent, function()
			if not Store.profile.slots[self.slotIndex] then
				app.toast("Save it first.", T.Warn)
				return
			end
			local ok, err = Store.equip(self.slotIndex)
			app.toast(if ok then "Equipped!" else tostring(err), if ok then T.Good else T.Danger)
		end, { Size = full, Parent = techPanel })
		C.button("Export code", nil, function()
			if not Store.profile.slots[self.slotIndex] then
				app.toast("Save it first.", T.Warn)
				return
			end
			local code, err = Store.export("moveset", self.slotIndex)
			if code then
				app.showCode("Technique code", code)
			else
				app.toast(tostring(err), T.Danger)
			end
		end, { Size = full, Parent = techPanel })
		C.button("Import code", nil, function()
			app.showImport()
		end, { Size = full, Parent = techPanel })
		C.button("Delete", T.Danger, function()
			if Store.profile.slots[self.slotIndex] then
				app.confirm(`Delete "{w.name}"?`, function()
					Store.deleteMoveset(self.slotIndex)
					self.open(math.max(1, self.slotIndex - 1))
				end)
			end
		end, { Size = full, Parent = techPanel })
	end

	-- Moves: tabs + header -------------------------------------------------------------
	local function renderMoveTabs()
		C.clear(moveTabs)
		local w = self.working
		if not w then
			return
		end
		for i in w.moves do
			C.button(`{i}`, if i == self.moveIndex then T.Accent else T.PanelLight, function()
				self.moveIndex = i
				self.selected = nil
				self.insert = nil
				render()
			end, { Size = UDim2.new(0, 34, 1, 0), LayoutOrder = i, Parent = moveTabs })
		end
		if #w.moves < Config.Moveset.MaxMoves then
			C.button("+ Move", nil, function()
				table.insert(w.moves, { name = `Move {#w.moves + 1}`, cooldown = 3, trigger = { type = "Press", fields = {} }, blocks = {} })
				self.moveIndex = #w.moves
				self.selected = nil
				self.insert = nil
				render()
			end, { Size = UDim2.new(0, 70, 1, 0), LayoutOrder = 100, Parent = moveTabs })
		end
		if #w.moves > 1 then
			C.button("Delete move", T.Danger, function()
				app.confirm(`Delete move "{w.moves[self.moveIndex].name}"?`, function()
					table.remove(w.moves, self.moveIndex)
					self.moveIndex = math.max(1, self.moveIndex - 1)
					self.selected = nil
					self.insert = nil
					render()
				end)
			end, { Size = UDim2.new(0, 100, 1, 0), LayoutOrder = 101, Parent = moveTabs })
		end
	end

	local function renderMoveHeader()
		C.clear(moveHeader)
		local move = currentMove()
		if not move then
			return
		end
		local row, area = C.row("Move name")
		C.textBox(move.name, function(text)
			move.name = text
		end, { Size = UDim2.new(1, 0, 1, 0), Parent = area })
		row.Parent = moveHeader
		C.numberEditor({ label = "Cooldown (s)", type = "number", min = 0, max = 120, step = 0.5 }, move.cooldown, function(v)
			move.cooldown = v
			render()
		end).Parent = moveHeader

		local triggerIds = {}
		for _, t in Triggers.List do
			table.insert(triggerIds, t.id)
		end
		move.trigger = move.trigger or { type = "Press", fields = {} }
		move.trigger.fields = move.trigger.fields or {}
		C.enumEditor({ label = "Trigger", options = triggerIds }, move.trigger.type, function(v)
			move.trigger = { type = v, fields = {} }
			for _, field in Triggers.ById[v].fields do
				move.trigger.fields[field.key] = field.default
			end
			render()
		end).Parent = moveHeader
		local tdef = Triggers.ById[move.trigger.type]
		if tdef then
			C.label(tdef.description, { TextWrapped = true, TextColor3 = T.SubText, TextSize = 12, Size = UDim2.new(1, 0, 0, 30), Parent = moveHeader })
			for _, field in tdef.fields do
				C.editor(field, move.trigger.fields[field.key] or field.default, function(v)
					move.trigger.fields[field.key] = v
				end).Parent = moveHeader
			end
		end
	end

	-- Block tree -------------------------------------------------------------------------
	local function summary(block: any): string
		local def = Blocks.ById[block.type]
		if not def then
			return block.type
		end
		local parts = {}
		for i, field in def.fields do
			if i > 3 then
				break
			end
			local v = block.fields[field.key]
			if type(v) == "number" then
				table.insert(parts, C.fmt(v))
			elseif type(v) == "table" then
				local nums = {}
				for _, n in v do
					table.insert(nums, C.fmt(n))
				end
				table.insert(parts, table.concat(nums, "×"))
			elseif type(v) == "boolean" then
				if v then
					table.insert(parts, field.label)
				end
			elseif type(v) == "string" and v ~= "" then
				if field.type == "vfx" then
					local effect = (Store.profile.vfx[v] or (self.working.vfx or {})[v])
					table.insert(parts, if effect then effect.name else "missing effect")
				else
					table.insert(parts, v)
				end
			end
		end
		return def.label .. "  " .. table.concat(parts, " · ")
	end

	local function insertButton(list: { any }, label: string, depth: number, layoutOrder: number)
		local active = self.insert and self.insert.list == list
		C.button(if active then `▶ adding to {label}` else `+ add to {label}`, if active then T.Accent else T.Panel, function()
			self.insert = { list = list, label = label }
			render()
		end, {
			Size = UDim2.new(1, -depth * 18, 0, 22),
			Position = UDim2.new(0, depth * 18, 0, 0),
			TextSize = 12,
			TextColor3 = if active then T.Text else T.SubText,
			Parent = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = layoutOrder, Parent = tree }),
		})
	end

	local order = 0
	local function renderList(list: { any }, depth: number, label: string)
		for i, block in list do
			order += 1
			local def = Blocks.ById[block.type]
			local isSelected = self.selected ~= nil and self.selected.list == list and self.selected.index == i
			local row = C.new("Frame", {
				BackgroundColor3 = if isSelected then T.PanelLight else T.Background,
				Size = UDim2.new(1, -depth * 18, 0, T.RowHeight),
				Position = UDim2.new(0, depth * 18, 0, 0),
			}, { C.corner(4) })
			C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, T.RowHeight), LayoutOrder = order, Parent = tree }, { row })
			C.new("Frame", { BackgroundColor3 = def and def.color or T.Danger, Size = UDim2.new(0, 4, 1, 0), Parent = row })
			C.button(summary(block), Color3.new(), function()
				self.selected = { list = list, index = i }
				render()
			end, {
				BackgroundTransparency = 1,
				Font = T.Font,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -96, 1, 0),
				Parent = row,
			})
			local function small(text: string, x: number, fn: () -> (), color: Color3?)
				C.button(text, color, fn, { Size = UDim2.new(0, 24, 0, 22), Position = UDim2.new(1, x, 0, 3), Parent = row })
			end
			small("↑", -82, function()
				if i > 1 then
					list[i], list[i - 1] = list[i - 1], list[i]
					self.selected = { list = list, index = i - 1 }
					render()
				end
			end)
			small("↓", -55, function()
				if i < #list then
					list[i], list[i + 1] = list[i + 1], list[i]
					self.selected = { list = list, index = i + 1 }
					render()
				end
			end)
			small("✕", -28, function()
				table.remove(list, i)
				self.selected = nil
				-- if we were inserting into a slot that just got deleted, fall back to root
				self.insert = nil
				render()
			end, T.Danger)

			if def and def.slots then
				block.children = block.children or {}
				for _, slot in def.slots do
					block.children[slot] = block.children[slot] or {}
					order += 1
					C.label(`↳ {slot}`, {
						Size = UDim2.new(1, -(depth + 1) * 18, 0, 18),
						Position = UDim2.new(0, (depth + 1) * 18, 0, 0),
						TextColor3 = def.color,
						TextSize = 12,
						Parent = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order, Parent = tree }),
					})
					renderList(block.children[slot], depth + 1, `{def.label} › {slot}`)
				end
			end
		end
		order += 1
		insertButton(list, label, depth, order)
	end

	local function renderTree()
		C.clear(tree)
		order = 0
		local move = currentMove()
		if not move then
			return
		end
		if not self.insert then
			self.insert = { list = move.blocks, label = "move" }
		end
		renderList(move.blocks, 0, "move")
	end

	-- Palette + inspector ---------------------------------------------------------------
	local function renderPalette()
		C.clear(palette)
		C.label("BLOCKS  (adds to: " .. (if self.insert then self.insert.label else "move") .. ")", {
			Font = T.FontBold,
			TextColor3 = T.SubText,
			Parent = palette,
		})
		for _, category in Blocks.Categories do
			C.label(category, { TextColor3 = Blocks.CategoryColors[category], Font = T.FontBold, Size = UDim2.new(1, 0, 0, 20), Parent = palette })
			local grid = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = palette }, {
				C.new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 26), CellPadding = UDim2.new(0, 4, 0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for _, def in Blocks.List do
				if def.category == category then
					local b = C.button(def.label, T.PanelLight, function()
						local move = currentMove()
						if not move then
							return
						end
						local target = if self.insert then self.insert.list else move.blocks
						table.insert(target, Blocks.create(def.id))
						self.selected = { list = target, index = #target }
						render()
					end, { TextSize = 12, Parent = grid })
					C.new("Frame", { BackgroundColor3 = def.color, Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0, Parent = b })
				end
			end
		end
	end

	local function renderInspector()
		C.clear(inspector)
		local sel = self.selected
		local block = sel and sel.list[sel.index]
		if not block then
			C.label("Select a block to edit it.", { TextColor3 = T.SubText, Parent = inspector })
			return
		end
		local def = Blocks.ById[block.type]
		if not def then
			return
		end
		C.label(def.label, { Font = T.FontBold, TextColor3 = def.color, Parent = inspector })
		C.label(def.description, { TextWrapped = true, TextColor3 = T.SubText, TextSize = 12, Size = UDim2.new(1, 0, 0, 34), Parent = inspector })
		local options = { vfxOptions = vfxOptions() }
		for _, field in def.fields do
			C.editor(field, block.fields[field.key], function(v)
				block.fields[field.key] = v
				renderTree()
				-- budget may have changed
				task.defer(function()
					self.renderReport()
				end)
			end, options).Parent = inspector
			if field.hint then
				C.label(field.hint, { TextWrapped = true, TextColor3 = T.SubText, TextSize = 11, Size = UDim2.new(1, 0, 0, 26), Parent = inspector })
			end
		end
	end

	-- Budget report -------------------------------------------------------------------------
	function self.renderReport()
		C.clear(report)
		local move = currentMove()
		if not move then
			return
		end
		local _, r = MovesetValidator.move(Util.deepCopy(move), self.moveIndex, {})
		local t = r.totals
		local B = Config.Budget
		local grid = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = report }, {
			C.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 16), CellPadding = UDim2.new(0, 4, 0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local function line(text: string, color: Color3)
			C.label(text, { TextColor3 = color, TextSize = 12, Parent = grid })
		end
		local function stat(name: string, v: number, max: number)
			line(`{name}: {C.fmt(math.floor(v * 10 + 0.5) / 10)} / {max}`, if v > max then T.Danger else T.SubText)
		end
		stat("Damage / target", t.damage, B.MaxDamage)
		stat("Duration (s)", t.duration, B.MaxDuration)
		stat("Hitboxes", t.hitboxes, B.MaxHitboxes)
		stat("Projectiles", t.projectiles, B.MaxProjectiles)
		stat("Healing", t.heal, B.MaxHeal)
		line(`Min cooldown: {C.fmt(math.ceil(r.minCooldown * 10) / 10)}s`, if move.cooldown < r.minCooldown then T.Warn else T.SubText)
		for _, e in r.errors do
			C.label("✕ " .. e, { TextColor3 = T.Danger, TextWrapped = true, TextSize = 12, Size = UDim2.new(1, 0, 0, 30), Parent = report })
		end
	end

	render = function()
		renderSlots()
		renderTechPanel()
		renderMoveTabs()
		renderMoveHeader()
		renderTree()
		renderPalette()
		renderInspector()
		self.renderReport()
	end

	Store.Changed:Connect(function()
		if parent.Visible then
			renderSlots()
		end
	end)

	return self
end

return SkillBuilder
