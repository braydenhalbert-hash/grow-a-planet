--[[
	TestTon  (Script, NOT a LocalScript)
	Put in: ServerScriptService

	TEMPORARY, for testing only. It only runs inside Roblox Studio (never in your published game).
	When you press Play it puts a fully grown TON 618 on the ground in front of you, already
	"ready", so you can test collecting the glowing pieces and the flying coins without
	planting and waiting an hour.

	It doesn't use the garden beds or save anything. Delete this script when you're done.

	Needs: PlanetCatalog + PlanetBuilder (ReplicatedStorage), PlantingServer (makes the
	PlantedPlanets folder) and Collectibles (ServerScriptService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PlanetBuilder = require(ReplicatedStorage:WaitForChild("PlanetBuilder"))

local PLANET_ID = "bh_ton618"
local DISTANCE = 40   -- studs in front of you
local HOVER = 1       -- same float height the garden uses

local planet = PlanetCatalog.Get(PLANET_ID)
local folder = workspace:WaitForChild("PlantedPlanets", 30)
if not planet or not folder then
	warn("[TestTon] Couldn't find the planet or workspace.PlantedPlanets. Is PlantingServer in ServerScriptService?")
	return
end

local remotes = ReplicatedStorage:FindFirstChild("PlanetRemotes")
local scale = remotes and remotes:GetAttribute("GardenScale") or 0.3

local function spawnFor(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end

	local old = folder:FindFirstChild("TestTON618_" .. player.UserId)
	if old then
		old:Destroy()
	end

	-- find the ground in front of the player
	local ahead = (root.CFrame * CFrame.new(0, 0, -DISTANCE)).Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder }
	local hit = workspace:Raycast(ahead + Vector3.new(0, 100, 0), Vector3.new(0, -300, 0), params)
	local groundY = hit and hit.Position.Y or (root.Position.Y - 3)

	local half = (planet.Look.Size / 2) * scale
	local center = Vector3.new(ahead.X, groundY + HOVER + half, ahead.Z)

	local model = PlanetBuilder.Build(planet, folder, CFrame.new(center), scale)
	model.Name = "TestTON618_" .. player.UserId
	model:SetAttribute("Owner", player.UserId)

	-- Collectibles only lets you collect from a planet whose Harvest prompt is switched on (fully grown).
	-- This one does nothing, and it's hidden because its distance is 0.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Test planet"
	prompt.MaxActivationDistance = 0
	prompt.Enabled = true
	prompt.Parent = model.PrimaryPart

	print("[TestTon] Fully grown TON 618 placed 40 studs in front of " .. player.Name)
end

local function setup(player)
	local spawned = false
	local function onCharacter(character)
		if spawned then
			return
		end
		spawned = true
		spawnFor(player, character)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(setup)
for _, player in ipairs(Players:GetPlayers()) do
	setup(player)
end

