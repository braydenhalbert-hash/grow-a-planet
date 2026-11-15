local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local coinsChanged = remotes:WaitForChild("CoinsChanged")
local inventoryChanged = remotes:WaitForChild("InventoryChanged")
local PlanetConfig = require(ReplicatedStorage:WaitForChild("PlanetConfig"))

local PlayerData = {}

local sessions = {} -- [player] = { Coins, Seeds = {id:count}, Planets = {id:count} }

local function snapshot(session)
	local seeds, planets = {}, {}
	for id, count in pairs(session.Seeds) do
		seeds[id] = count
	end
	for id, count in pairs(session.Planets) do
		planets[id] = count
	end
	return seeds, planets
end

local function push(player)
	local session = sessions[player]
	if not session then
		return
	end
	coinsChanged:FireClient(player, session.Coins)
	local seeds, planets = snapshot(session)
	inventoryChanged:FireClient(player, seeds, planets)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Coins.Value = session.Coins
	end
end

function PlayerData.Get(player)
	local session = sessions[player]
	if not session then
		session = {
			Coins = PlanetConfig.StartCoins,
			Seeds = {},
			Planets = {},
		}
		sessions[player] = session
	end
	return session
end

function PlayerData.AddCoins(player, delta)
	local session = PlayerData.Get(player)
	session.Coins = math.max(0, session.Coins + delta)
	push(player)
end

function PlayerData.GetCoins(player)
	return PlayerData.Get(player).Coins
end

function PlayerData.AddSeed(player, planetId, count)
	local session = PlayerData.Get(player)
	session.Seeds[planetId] = (session.Seeds[planetId] or 0) + (count or 1)
	push(player)
end

function PlayerData.RemoveSeed(player, planetId)
	local session = PlayerData.Get(player)
	if (session.Seeds[planetId] or 0) <= 0 then
		return false
	end
	session.Seeds[planetId] -= 1
	if session.Seeds[planetId] <= 0 then
		session.Seeds[planetId] = nil
	end
	push(player)
	return true
end

function PlayerData.AddPlanet(player, planetId, count)
	local session = PlayerData.Get(player)
	session.Planets[planetId] = (session.Planets[planetId] or 0) + (count or 1)
	push(player)
end

function PlayerData.RemovePlanet(player, planetId)
	local session = PlayerData.Get(player)
	if (session.Planets[planetId] or 0) <= 0 then
		return false
	end
	session.Planets[planetId] -= 1
	if session.Planets[planetId] <= 0 then
		session.Planets[planetId] = nil
	end
	push(player)
	return true
end

function PlayerData.GetSeedCounts(player)
	local session = PlayerData.Get(player)
	local seeds, _ = snapshot(session)
	return seeds
end

function PlayerData.GetPlanetCounts(player)
	local session = PlayerData.Get(player)
	local _, planets = snapshot(session)
	return planets
end

Players.PlayerAdded:Connect(function(player)
	local session = PlayerData.Get(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = session.Coins
	coins.Parent = leaderstats
	leaderstats.Parent = player
	push(player)
end)

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
end)

return PlayerData