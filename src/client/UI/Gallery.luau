--!strict
-- Public technique gallery: browse recent / top techniques, like, report,
-- import with one click, and publish your own.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)

local C = require(script.Parent.Components)
local Store = require(script.Parent.Parent.Store)

local T = C.Theme

local Gallery = {}

function Gallery.new(parent: GuiObject, app: any)
	local self = { sort = "recent", page = 1, loading = false }

	local bar = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = parent }, { C.list(6, true) })
	local publishPanel = C.scroll({ Position = UDim2.new(0.7, 6, 0, T.RowHeight + 8), Size = UDim2.new(0.3, -6, 1, -(T.RowHeight + 8)), Parent = parent })
	local list = C.scroll({ Position = UDim2.new(0, 0, 0, T.RowHeight + 8), Size = UDim2.new(0.7, 0, 1, -(T.RowHeight + 8)), Parent = parent })

	local refresh: () -> ()

	local function card(e: any)
		local frame = C.new("Frame", {
			BackgroundColor3 = T.PanelLight,
			Size = UDim2.new(1, 0, 0, 92),
			Parent = list,
		}, { C.corner(6), C.padding(8) })
		C.label(e.name, { Font = T.FontBold, TextSize = 16, Size = UDim2.new(1, -230, 0, 20), Parent = frame })
		C.label(`by {e.authorName} · ♥ {e.likes}`, {
			TextColor3 = T.SubText,
			TextSize = 12,
			Position = UDim2.new(0, 0, 0, 20),
			Size = UDim2.new(1, -230, 0, 16),
			Parent = frame,
		})
		C.label(table.concat(e.moves, " · "), {
			TextColor3 = T.Accent,
			TextSize = 12,
			Position = UDim2.new(0, 0, 0, 38),
			Size = UDim2.new(1, -230, 0, 16),
			Parent = frame,
		})
		C.label(e.description, {
			TextColor3 = T.SubText,
			TextSize = 12,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 0, 0, 56),
			Size = UDim2.new(1, -230, 0, 22),
			Parent = frame,
		})
		local buttons = C.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 220, 1, 0),
			Parent = frame,
		}, {
			C.new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 34), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		C.button("Import", T.Good, function()
			local result = Remotes.func("GalleryImport"):InvokeServer(e.id)
			if not result or not result.ok then
				app.toast("Import failed: " .. tostring(result and result.error), T.Danger)
				return
			end
			Store.refresh()
			app.toast(`Imported "{result.value.name}"! Find it in Techniques.`, T.Good)
			if result.errors and #result.errors > 0 then
				app.toast("It's over budget here: " .. result.errors[1], T.Warn)
			end
		end, { LayoutOrder = 1, Parent = buttons })
		if e.mine then
			C.button("Unpublish", T.Danger, function()
				app.confirm(`Remove "{e.name}" from the gallery?`, function()
					if Remotes.func("GalleryUnpublish"):InvokeServer(e.id) then
						app.toast("Unpublished.", T.Good)
						refresh()
					end
				end)
			end, { LayoutOrder = 2, Parent = buttons })
		else
			local like: TextButton
			like = C.button(if e.liked then "♥ Liked" else "♡ Like", if e.liked then T.Accent else nil, function()
				local ok, likes = Remotes.func("GalleryLike"):InvokeServer(e.id)
				if ok then
					like.Text = "♥ Liked"
					like.BackgroundColor3 = T.Accent
					e.likes = likes
				end
			end, { LayoutOrder = 2, Parent = buttons })
			C.button("Report", nil, function()
				app.confirm(`Report "{e.name}" as inappropriate?`, function()
					Remotes.func("GalleryReport"):InvokeServer(e.id)
					app.toast("Thanks, it's been reported.", nil)
				end)
			end, { LayoutOrder = 3, TextColor3 = T.SubText, Parent = buttons })
		end
	end

	refresh = function()
		if self.loading then
			return
		end
		self.loading = true
		C.clear(list)
		C.label("Loading...", { TextColor3 = T.SubText, Parent = list })
		local result
		if self.sort == "mine" then
			result = Remotes.func("GalleryMine"):InvokeServer()
		else
			result = Remotes.func("GalleryList"):InvokeServer(self.sort, self.page)
		end
		self.loading = false
		C.clear(list)
		if not result then
			return
		end
		if result.error then
			C.label(result.error, { TextColor3 = T.Warn, Parent = list })
		end
		if #result.entries == 0 then
			C.label(if self.sort == "mine" then "You haven't published anything yet." else "Nothing here yet. Be the first to publish!", {
				TextColor3 = T.SubText,
				Parent = list,
			})
		end
		for _, e in result.entries do
			card(e)
		end
		if self.sort ~= "mine" then
			local nav = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = list }, { C.list(6, true) })
			if self.page > 1 then
				C.button("< Prev", nil, function()
					self.page -= 1
					refresh()
				end, { LayoutOrder = 1, Parent = nav })
			end
			C.label(`Page {self.page}`, { LayoutOrder = 2, Size = UDim2.new(0, 70, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, Parent = nav })
			if result.hasMore then
				C.button("Next >", nil, function()
					self.page += 1
					refresh()
				end, { LayoutOrder = 3, Parent = nav })
			end
		end
	end

	-- Sort bar ----------------------------------------------------------------------------
	local sortButtons = {}
	local function setSort(sort: string)
		self.sort = sort
		self.page = 1
		for key, b in sortButtons do
			b.BackgroundColor3 = if key == sort then T.Accent else T.PanelLight
		end
		refresh()
	end
	for i, entry in { { "recent", "Recent" }, { "top", "Most liked" }, { "mine", "My published" } } do
		sortButtons[entry[1]] = C.button(entry[2], nil, function()
			setSort(entry[1])
		end, { LayoutOrder = i, Size = UDim2.new(0, 120, 1, 0), Parent = bar })
	end
	C.button("Refresh", nil, refresh, { LayoutOrder = 10, Parent = bar })

	-- Publish panel ------------------------------------------------------------------------
	local function renderPublish()
		C.clear(publishPanel)
		C.label("PUBLISH A TECHNIQUE", { Font = T.FontBold, TextColor3 = T.SubText, Parent = publishPanel })
		local profile = Store.profile
		if not profile or #profile.slots == 0 then
			C.label("Save a technique first.", { TextColor3 = T.SubText, Parent = publishPanel })
			return
		end
		local names = {}
		for _, m in profile.slots do
			table.insert(names, m.name)
		end
		local chosen = 1
		C.enumEditor({ label = "Technique", options = names }, names[1], function(v)
			chosen = table.find(names, v) or 1
		end).Parent = publishPanel
		C.label("Description", { TextColor3 = T.SubText, Parent = publishPanel })
		local desc = C.textBox(profile.slots[1].description or "", function() end, {
			Size = UDim2.new(1, 0, 0, 70),
			MultiLine = true,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			PlaceholderText = "What does it do? How do you combo it?",
			Parent = publishPanel,
		})
		C.button("Publish", T.Good, function()
			local ok, err = Remotes.func("GalleryPublish"):InvokeServer(chosen, string.sub(desc.Text, 1, Config.Gallery.MaxDescriptionLength))
			if ok then
				app.toast("Published! Everyone can find it in the gallery.", T.Good)
				setSort("recent")
			else
				app.toast(tostring(err), T.Danger)
			end
		end, { Size = UDim2.new(1, 0, 0, T.RowHeight), Parent = publishPanel })
		C.label(
			`Only techniques within budget can be published. Max {Config.Gallery.MaxPublishedPerPlayer} per player. Names are filtered and the gallery shows your username.`,
			{ TextWrapped = true, TextColor3 = T.SubText, TextSize = 11, Size = UDim2.new(1, 0, 0, 52), Parent = publishPanel }
		)
	end

	function self.open()
		renderPublish()
		setSort(self.sort)
	end

	Store.Changed:Connect(function()
		if parent.Visible then
			renderPublish()
		end
	end)

	return self
end

return Gallery
