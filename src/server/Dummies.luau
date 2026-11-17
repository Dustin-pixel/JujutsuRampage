--!strict
-- Training dummies so players can test their techniques alone.
-- Place Models named "Dummy" (with a Humanoid + HumanoidRootPart) inside a
-- Folder named "Dummies" in Workspace. If there is none, one is generated.
-- Dummies respawn a few seconds after dying.

local Players = game:GetService("Players")

local CombatService = require(script.Parent.CombatService)

local Dummies = {}

local function makeRig(): Model
	-- R15 rig generated from a default HumanoidDescription.
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		model.Name = "Dummy"
		return model
	end
	-- Fallback: a single block with a humanoid.
	local m = Instance.new("Model")
	m.Name = "Dummy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 5, 1)
	root.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.CFrame = root.CFrame * CFrame.new(0, 3, 0)
	head.Parent = m
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root
	Instance.new("Humanoid").Parent = m
	m.PrimaryPart = root
	return m
end

local function track(template: Model, folder: Instance, cf: CFrame)
	local function spawnOne()
		local dummy = template:Clone()
		dummy:PivotTo(cf)
		dummy.Parent = folder
		local humanoid = dummy:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		humanoid.BreakJointsOnDeath = false
		CombatService.register(dummy)
		humanoid.Died:Connect(function()
			task.wait(4)
			dummy:Destroy()
			spawnOne()
		end)
	end
	spawnOne()
end

function Dummies.start()
	local folder = workspace:FindFirstChild("Dummies")
	local templates: { { model: Model, cf: CFrame } } = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
				table.insert(templates, { model = child, cf = child:GetPivot() })
			end
		end
	else
		folder = Instance.new("Folder")
		folder.Name = "Dummies"
		folder.Parent = workspace
		local rig = makeRig()
		for i = 0, 2 do
			table.insert(templates, { model = rig, cf = CFrame.new(i * 8 - 8, 5, -20) * CFrame.Angles(0, math.pi, 0) })
		end
	end
	for _, t in templates do
		local template = t.model:Clone()
		if t.model.Parent == folder then
			t.model:Destroy()
		end
		track(template, folder :: Instance, t.cf)
	end
end

return Dummies
