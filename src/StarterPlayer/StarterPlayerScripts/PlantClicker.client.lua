-- PlantClicker: left-click a growing bed to plant a planet exactly where you clicked
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = remotes:WaitForChild("PlantAtPad", 30)
if not remote then
	warn("[PlantClicker] PlantAtPad remote not found - click planting disabled")
	return
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local target = mouse.Target
	if not target or not CollectionService:HasTag(target, "GardenPad") then
		return
	end
	remote:FireServer(target, mouse.Hit.Position)
end)

print("[PlantClicker] Ready - click a growing bed to plant")
