--!strict
-- Tiny UI toolkit: an Instance factory plus editors for every field/prop type
-- used by blocks (Schema/Blocks) and VFX layers (Vfx/VfxSchema).
--
-- Every editor has the signature  editor(def, value, onChange) -> GuiObject
-- and calls onChange(newValue) with an already-clamped value.

local Theme = {
	Background = Color3.fromRGB(16, 14, 24),
	Panel = Color3.fromRGB(26, 23, 38),
	PanelLight = Color3.fromRGB(38, 34, 54),
	Accent = Color3.fromRGB(140, 90, 255),
	Danger = Color3.fromRGB(220, 70, 80),
	Good = Color3.fromRGB(80, 200, 120),
	Warn = Color3.fromRGB(240, 180, 60),
	Text = Color3.fromRGB(235, 232, 245),
	SubText = Color3.fromRGB(160, 155, 180),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	RowHeight = 28,
}

local C = { Theme = Theme }

function C.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function C.corner(radius: number?): UICorner
	return C.new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function C.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return C.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function C.list(padding: number?, horizontal: boolean?): UIListLayout
	return C.new("UIListLayout", {
		Padding = UDim.new(0, padding or 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
	})
end

function C.label(text: string, props: { [string]: any }?): TextLabel
	local l = C.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Theme.Text,
		Font = Theme.Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

function C.button(text: string, color: Color3?, onClick: () -> (), props: { [string]: any }?): TextButton
	local b = C.new("TextButton", {
		Text = text,
		BackgroundColor3 = color or Theme.PanelLight,
		TextColor3 = Theme.Text,
		Font = Theme.FontBold,
		TextSize = 14,
		AutoButtonColor = true,
		Size = UDim2.new(0, 90, 0, Theme.RowHeight),
	}, { C.corner(5) })
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	b.Activated:Connect(onClick)
	return b
end

function C.textBox(text: string, onCommit: (string) -> (), props: { [string]: any }?): TextBox
	local box = C.new("TextBox", {
		Text = text,
		BackgroundColor3 = Theme.Background,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		Font = Theme.Font,
		TextSize = 14,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, { C.corner(4), C.padding(4) })
	if props then
		for k, v in props do
			(box :: any)[k] = v
		end
	end
	box.FocusLost:Connect(function()
		onCommit(box.Text)
	end)
	return box
end

function C.scroll(props: { [string]: any }?): ScrollingFrame
	local s = C.new("ScrollingFrame", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, { C.corner(6), C.padding(6), C.list(4) })
	if props then
		for k, v in props do
			(s :: any)[k] = v
		end
	end
	return s
end

function C.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A labelled row: [label | editor area]
function C.row(labelText: string, height: number?): (Frame, Frame)
	local h = height or Theme.RowHeight
	local area = C.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.4, 0, 0, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
	})
	local row = C.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, h),
	}, {
		C.label(labelText, { Size = UDim2.new(0.4, -4, 0, Theme.RowHeight), TextColor3 = Theme.SubText, TextSize = 13 }),
		area,
	})
	return row, area
end

local function clamp(n: number, def: any): number
	if def.min then
		n = math.max(def.min, n)
	end
	if def.max then
		n = math.min(def.max, n)
	end
	if def.type == "int" then
		n = math.floor(n + 0.5)
	end
	return n
end

local function fmt(n: number): string
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "") :: string
end
C.fmt = fmt

-- number / int ------------------------------------------------------------------
function C.numberEditor(def: any, value: number, onChange: (number) -> ()): GuiObject
	local row, area = C.row(def.label or def.key)
	local box: TextBox
	local function set(n: number)
		n = clamp(n, def)
		box.Text = fmt(n)
		onChange(n)
	end
	local step = def.step or (if def.type == "int" then 1 else 0.1)
	box = C.textBox(fmt(value), function(text)
		set(tonumber(text) or value)
		value = tonumber(box.Text) or value
	end, { Size = UDim2.new(1, -56, 1, 0), Position = UDim2.new(0, 28, 0, 0), TextXAlignment = Enum.TextXAlignment.Center })
	box.Parent = area
	C.button("-", nil, function()
		value = clamp((tonumber(box.Text) or value) - step, def)
		set(value)
	end, { Size = UDim2.new(0, 24, 1, 0), Parent = area })
	C.button("+", nil, function()
		value = clamp((tonumber(box.Text) or value) + step, def)
		set(value)
	end, { Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(1, -24, 0, 0), Parent = area })
	return row
end

-- bool ----------------------------------------------------------------------------
function C.boolEditor(def: any, value: boolean, onChange: (boolean) -> ()): GuiObject
	local row, area = C.row(def.label or def.key)
	local b: TextButton
	b = C.button(if value then "ON" else "OFF", if value then Theme.Good else Theme.PanelLight, function()
		value = not value
		b.Text = if value then "ON" else "OFF"
		b.BackgroundColor3 = if value then Theme.Good else Theme.PanelLight
		onChange(value)
	end, { Size = UDim2.new(1, 0, 1, 0), Parent = area })
	return row
end

-- enum: < value > ----------------------------------------------------------------
function C.enumEditor(def: any, value: string, onChange: (string) -> ()): GuiObject
	local row, area = C.row(def.label or def.key)
	local options: { string } = def.options
	local index = table.find(options, value) or 1
	local mid = C.label(options[index], {
		Size = UDim2.new(1, -56, 1, 0),
		Position = UDim2.new(0, 28, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = area,
	})
	local function step(d: number)
		index = (index - 1 + d) % #options + 1
		mid.Text = options[index]
		onChange(options[index])
	end
	C.button("<", nil, function()
		step(-1)
	end, { Size = UDim2.new(0, 24, 1, 0), Parent = area })
	C.button(">", nil, function()
		step(1)
	end, { Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(1, -24, 0, 0), Parent = area })
	return row
end

-- vector (2 or 3 numbers) -------------------------------------------------------
function C.vectorEditor(def: any, value: { number }, onChange: ({ number }) -> (), count: number?): GuiObject
	local n = count or 3
	local row, area = C.row(def.label or def.key)
	local current = table.clone(value)
	for i = 1, n do
		C.textBox(fmt(current[i]), function(text)
			local num = tonumber(text)
			if num then
				current[i] = clamp(num, { min = def.min, max = def.max })
			end
			onChange(table.clone(current))
		end, {
			Size = UDim2.new(1 / n, -3, 1, 0),
			Position = UDim2.new((i - 1) / n, 0, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = area,
		})
	end
	return row
end

-- range {min,max} ------------------------------------------------------------------
function C.rangeEditor(def: any, value: { number }, onChange: ({ number }) -> ()): GuiObject
	return C.vectorEditor(def, value, function(v)
		if v[1] > v[2] then
			v[2] = v[1]
		end
		onChange(v)
	end, 2)
end

-- color {r,g,b} --------------------------------------------------------------------
function C.colorEditor(def: any, value: { number }, onChange: ({ number }) -> ()): GuiObject
	local row, area = C.row(def.label or def.key)
	local current = table.clone(value)
	local swatch = C.new("Frame", {
		Size = UDim2.new(0, 24, 1, 0),
		BackgroundColor3 = Color3.fromRGB(current[1], current[2], current[3]),
		Parent = area,
	}, { C.corner(4) })
	for i = 1, 3 do
		C.textBox(tostring(current[i]), function(text)
			local num = tonumber(text)
			if num then
				current[i] = math.clamp(math.floor(num), 0, 255)
			end
			swatch.BackgroundColor3 = Color3.fromRGB(current[1], current[2], current[3])
			onChange(table.clone(current))
		end, {
			-- three boxes share the space to the right of the 28px swatch
			Size = UDim2.new(1 / 3, -28 / 3 - 3, 1, 0),
			Position = UDim2.new((i - 1) / 3, 28 - (i - 1) * 28 / 3, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			PlaceholderText = ({ "R", "G", "B" })[i],
			Parent = area,
		})
	end
	return row
end

-- sequences: one text row per keypoint ------------------------------------------------
-- colorSeq rows:  "t r g b"      numSeq rows:  "t value envelope"
function C.sequenceEditor(def: any, value: { { number } }, onChange: ({ { number } }) -> ()): GuiObject
	local isColor = def.type == "colorSeq"
	local text = {}
	for _, kp in value do
		local parts = {}
		for _, n in kp do
			table.insert(parts, fmt(n))
		end
		table.insert(text, table.concat(parts, " "))
	end
	local lines = math.max(#value, 2)
	local frame = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22 + lines * 18 + 10) })
	C.label((def.label or def.key) .. (if isColor then "  (time  R G B)" else "  (time  value  random±)"), {
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.SubText,
		TextSize = 13,
		Parent = frame,
	})
	C.textBox(table.concat(text, "\n"), function(input)
		local seq = {}
		for line in string.gmatch(input, "[^\n]+") do
			local nums = {}
			for token in string.gmatch(line, "[%-%d%.]+") do
				table.insert(nums, tonumber(token) or 0)
			end
			if #nums >= 2 then
				table.insert(seq, nums)
			end
		end
		if #seq >= 2 then
			onChange(seq) -- validated/fixed up by VfxValidator before use
		end
	end, {
		MultiLine = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, lines * 18 + 10),
		Parent = frame,
	})
	return frame
end

-- asset id -----------------------------------------------------------------------
function C.assetEditor(def: any, value: string, onChange: (string) -> ()): GuiObject
	local row, area = C.row(def.label or def.key)
	C.textBox(value, function(text)
		local digits = string.match(text, "(%d+)") or ""
		onChange(digits)
	end, { PlaceholderText = "rbxassetid / number", Size = UDim2.new(1, 0, 1, 0), Parent = area })
	return row
end

-- Dispatch by type. `extra.vfxOptions` = { {id, name} } for "vfx" fields.
function C.editor(def: any, value: any, onChange: (any) -> (), extra: any?): GuiObject
	local t = def.type
	if t == "number" or t == "int" then
		return C.numberEditor(def, value, onChange)
	elseif t == "bool" then
		return C.boolEditor(def, value, onChange)
	elseif t == "enum" then
		return C.enumEditor(def, value, onChange)
	elseif t == "vector3" then
		return C.vectorEditor(def, value, onChange, 3)
	elseif t == "vector2" then
		return C.vectorEditor(def, value, onChange, 2)
	elseif t == "range" then
		return C.rangeEditor(def, value, onChange)
	elseif t == "color" then
		return C.colorEditor(def, value, onChange)
	elseif t == "colorSeq" or t == "numSeq" then
		return C.sequenceEditor(def, value, onChange)
	elseif t == "asset" then
		return C.assetEditor(def, value, onChange)
	elseif t == "vfx" then
		local options = { "" }
		local names = { "(none)" }
		for _, o in (extra and extra.vfxOptions) or {} do
			table.insert(options, o.id)
			table.insert(names, o.name)
		end
		local index = table.find(options, value) or 1
		local row, area = C.row(def.label or def.key)
		local mid = C.label(names[index], {
			Size = UDim2.new(1, -56, 1, 0),
			Position = UDim2.new(0, 28, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = area,
		})
		local function step(d: number)
			index = (index - 1 + d) % #options + 1
			mid.Text = names[index]
			onChange(options[index])
		end
		C.button("<", nil, function()
			step(-1)
		end, { Size = UDim2.new(0, 24, 1, 0), Parent = area })
		C.button(">", nil, function()
			step(1)
		end, { Size = UDim2.new(0, 24, 1, 0), Position = UDim2.new(1, -24, 0, 0), Parent = area })
		return row
	end
	return C.label("?? " .. tostring(t))
end

-- Modal message / confirm ---------------------------------------------------------
function C.toast(screen: Instance, text: string, color: Color3?)
	local t = C.new("TextLabel", {
		Text = text,
		BackgroundColor3 = color or Theme.PanelLight,
		TextColor3 = Theme.Text,
		Font = Theme.FontBold,
		TextSize = 15,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(0, 420, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 50,
		Parent = screen,
	}, { C.corner(6), C.padding(8) })
	task.delay(3.5, function()
		t:Destroy()
	end)
end

return C
