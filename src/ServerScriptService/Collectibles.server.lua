--[[
	Collectibles  (Script, NOT a LocalScript)
	Put in: ServerScriptService

	Lets players collect the moons and rocks orbiting a planted black hole (TON 618).
	  * Plant it, let it grow until it says READY!, then run into the glowing pieces as they orbit.
	  * Each piece pays coins and the coins fly to your coin bar (SeedShopUI does the flying).
	  * A collected piece disappears and comes back after 2 minutes.

	How much each piece pays, and the 2 minutes, are set in PlanetCatalog on the planet's
	"Collect" line (MoonValue, DebrisValue, Regrow).

	The server works out where each piece is from the shared server clock, the same math
	PlanetSpinner uses on your screen, so nobody can collect from far away.

	Needs: GameData (same folder), PlantingServer (it creates the PlantedPlanets folder).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(script.Parent:WaitForChild("GameData"))
local LiveOps = require(script.Parent:WaitForChild("LiveOps"))

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local FOLDER_NAME = "PlantedPlanets"
local COLLECT_RADIUS = 6      -- studs: how close you have to get to a piece to grab it
local CHECK_INTERVAL = 0.1
local OWNER_ONLY = true       -- only the player who planted it can collect from it
local TAU = math.pi * 2

---------------------------------------------------------------------
-- Remote (tells the client to fly the coins)
---------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("PlanetRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "PlanetRemotes"
	remotes.Parent = ReplicatedStorage
end

local rewardRemote = remotes:FindFirstChild("CoinReward")
if not rewardRemote then
	rewardRemote = Instance.new("RemoteEvent")
	rewardRemote.Name = "CoinReward" -- server -> client: (amount, worldPosition)
	rewardRemote.Parent = remotes
end

---------------------------------------------------------------------
-- Find the planted planets that have collectible pieces
---------------------------------------------------------------------
local plantsFolder = workspace:WaitForChild(FOLDER_NAME, 60)
if not plantsFolder then
	warn("[Collectibles] Couldn't find workspace." .. FOLDER_NAME .. ". Is PlantingServer in ServerScriptService?")
	return
end

local tracked = {} -- model -> { Body, Tilt, Regrow, Pieces }

local function register(model)
	if tracked[model] or not model:IsA("Model") then
		return
	end
	local body = model:FindFirstChild("Body")
	if not body then
		return
	end

	local pieces = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local value = descendant:GetAttribute("CoinValue")
			if value then
				table.insert(pieces, {
					Part = descendant,
					Value = value,
					Speed = descendant:GetAttribute("SpinSpeed") or 0,
					Collected = false,
					BaseTransparency = descendant.Transparency,
				})
			end
		end
	end

	if #pieces > 0 then
		tracked[model] = {
			Body = body,
			Model = model,
			Tilt = CFrame.Angles(0, 0, math.rad(model:GetAttribute("Tilt") or 0)),
			Regrow = model:GetAttribute("CollectRegrow") or 120,
			Pieces = pieces,
		}
	end
end

for _, model in ipairs(plantsFolder:GetChildren()) do
	register(model)
end
plantsFolder.ChildAdded:Connect(register)
plantsFolder.ChildRemoved:Connect(function(model)
	tracked[model] = nil
end)

---------------------------------------------------------------------
-- Collecting
---------------------------------------------------------------------
local function pieceWorldPosition(info, piece, serverTime)
	local base = info.Body.CFrame * info.Tilt
	local relative = base:ToObjectSpace(piece.Part.CFrame)
	return (base * CFrame.Angles(0, (piece.Speed * serverTime) % TAU, 0) * relative).Position
end

local function collect(player, info, piece, position)
	if not GameData.Get(player) then
		return
	end

	piece.Collected = true
	piece.Part.Transparency = 1 -- it vanishes for everyone

	-- mutated planets (Meteor Shower, Nebula...) pay more
	local mult = info.Model and info.Model:GetAttribute("MutationMult") or 1
	local value = math.max(1, math.floor(piece.Value * mult * LiveOps.Get("Coins") + 0.5))
	if GameData.AddCoins(player, value) then
		rewardRemote:FireClient(player, value, position)
	end

	task.delay(info.Regrow, function()
		if piece.Part.Parent then
			piece.Part.Transparency = piece.BaseTransparency
			piece.Collected = false
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		local serverTime = workspace:GetServerTimeNow()

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")

			if root and humanoid and humanoid.Health > 0 then
				for model, info in pairs(tracked) do
					if not model.Parent then
						tracked[model] = nil
					else
						local mine = (not OWNER_ONLY) or model:GetAttribute("Owner") == player.UserId
						-- the planet's Harvest prompt is only switched on once it is fully grown
						local prompt = info.Body:FindFirstChildOfClass("ProximityPrompt")

						if mine and prompt and prompt.Enabled then
							for _, piece in ipairs(info.Pieces) do
								if not piece.Collected and piece.Part.Parent then
									local position = pieceWorldPosition(info, piece, serverTime)
									if (position - root.Position).Magnitude <= COLLECT_RADIUS then
										collect(player, info, piece, position)
									end
								end
							end
						end
					end
				end
			end
		end
	end
end)

print("[Collectibles] Ready")
