--[[
	Sprint  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	Hold Shift to sprint. Let go and you go back to normal speed.
	Change SPRINT_SPEED to make it faster or slower (Roblox's normal walk speed is 16).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local WALK_SPEED = 16
local SPRINT_SPEED = 30

local SPRINT_KEYS = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
}

local sprinting = false

local function apply()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = sprinting and SPRINT_SPEED or WALK_SPEED
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not SPRINT_KEYS[input.KeyCode] then
		return
	end
	sprinting = true
	apply()
end)

UserInputService.InputEnded:Connect(function(input)
	if SPRINT_KEYS[input.KeyCode] then
		sprinting = false
		apply()
	end
end)

-- if you click out of the game while holding Shift, stop sprinting
UserInputService.WindowFocusReleased:Connect(function()
	sprinting = false
	apply()
end)

-- a new character (after you respawn) starts at normal speed
player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Humanoid")
	apply()
end)

apply()
