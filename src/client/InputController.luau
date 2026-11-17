--!strict
-- Keyboard / gamepad / touch input for combat.
--   1-6 : moves        LMB / ButtonR2 : M1        F / ButtonL2 : block (hold)
-- Input is ignored while a TextBox is focused or the builder is open.

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local InputController = {}
InputController.enabled = true

local useMove = Remotes.event("UseMove")
local m1 = Remotes.event("M1")
local blockEvent = Remotes.event("Block")

local KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonB] = 3,
	[Enum.KeyCode.DPadUp] = 4,
	[Enum.KeyCode.DPadRight] = 5,
	[Enum.KeyCode.DPadDown] = 6,
}

local function aim(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.LookVector
end

-- phase "down" on press, "up" on release (Charge moves fire on release).
local held: { [number]: boolean } = {}
function InputController.useMove(slot: number, phase: string?)
	local p = phase or "down"
	if p == "down" then
		if not InputController.enabled then
			return
		end
		held[slot] = true
	else
		if not held[slot] then
			return
		end
		held[slot] = nil
	end
	useMove:FireServer(slot, aim(), p)
end

function InputController.m1()
	if InputController.enabled then
		m1:FireServer()
	end
end

function InputController.setBlocking(holding: boolean)
	blockEvent:FireServer(holding and InputController.enabled)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	local slot = KEYS[input.KeyCode]
	if slot then
		InputController.useMove(slot)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		InputController.m1()
	elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL2 then
		InputController.setBlocking(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local slot = KEYS[input.KeyCode]
	if slot then
		InputController.useMove(slot, "up")
	elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL2 then
		InputController.setBlocking(false)
	end
end)

return InputController
