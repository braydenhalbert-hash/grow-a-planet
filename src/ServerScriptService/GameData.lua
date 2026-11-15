--[[
	GameData  (ModuleScript)
	Put in: ServerScriptService   (name it exactly: GameData)

	Holds every player's coins, seeds, harvested planets and planted plants, and saves
	them with DataStore. Other server scripts use it like this:

	  local GameData = require(script.Parent:WaitForChild("GameData"))
	  local data = GameData.Get(player)         -- nil until the player's data has loaded
	  local data = GameData.WaitFor(player)     -- waits until it has loaded
	  GameData.AddCoins(player, -50)            -- returns false if they can't afford it

	Coins are also copied to player:GetAttribute("Coins") so the UI can show them.

	To test saving in Studio: Game Settings > Security > turn on
	"Enable Studio Access to API Services". Without it the game still works, it just
	won't save (you'll see a warning in Output).
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local GameData = {}

local STORE_NAME = "PlanetGame_v1"
local START_COINS = 50
local AUTOSAVE_SECONDS = 60
local LOAD_ATTEMPTS = 3

local store = DataStoreService:GetDataStore(STORE_NAME)
local sessions = {} -- player -> { Data = table, CanSave = boolean }

local loadedEvent = Instance.new("BindableEvent")
GameData.PlayerLoaded = loadedEvent.Event

local function newData()
	return {
		Coins = START_COINS,
		Seeds = {},   -- [planetId] = count
		Packs = {},   -- [packId] = count of unopened Black Hole Packs
		Planets = {}, -- harvested planets: { Id = planetId, Weight = kg }
		Plants = {},  -- planted in beds (used in phase 2)
		Gear = {},    -- [gearId] = count of unplaced gear (sprinklers) from the gear shop
		Sprinklers = {}, -- placed sprinklers: { Id = gearId, X, Y, Z, Until = os.time() it runs out }
	}
end

-- fill in anything an older save is missing
local function reconcile(data)
	for key, value in pairs(newData()) do
		if data[key] == nil then
			data[key] = value
		end
	end
	return data
end

local function keyFor(player)
	return "u" .. player.UserId
end

local function loadPlayer(player)
	local data
	local canSave = false

	for attempt = 1, LOAD_ATTEMPTS do
		local ok, result = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			data = result
			canSave = true
			break
		end
		warn(string.format("[GameData] load failed for %s (try %d): %s", player.Name, attempt, tostring(result)))
		if attempt < LOAD_ATTEMPTS then
			task.wait(1.5)
		end
	end

	if not player.Parent then
		return
	end

	if type(data) ~= "table" then
		data = newData() -- brand new player (or the load failed)
	end
	reconcile(data)

	if not canSave then
		warn("[GameData] Couldn't reach DataStore, so " .. player.Name .. "'s progress will NOT be saved this session. "
			.. "In Studio, turn on Game Settings > Security > Enable Studio Access to API Services.")
	end

	sessions[player] = { Data = data, CanSave = canSave }
	player:SetAttribute("Coins", data.Coins)
	loadedEvent:Fire(player)
end

function GameData.Get(player)
	local session = sessions[player]
	return session and session.Data
end

function GameData.WaitFor(player)
	while player.Parent and not sessions[player] do
		task.wait(0.1)
	end
	return GameData.Get(player)
end

function GameData.GetCoins(player)
	local data = GameData.Get(player)
	return data and data.Coins or 0
end

function GameData.AddCoins(player, amount)
	local data = GameData.Get(player)
	if not data then
		return false
	end
	if data.Coins + amount < 0 then
		return false
	end
	data.Coins += amount
	player:SetAttribute("Coins", data.Coins)
	return true
end

-- admin panel: wipe a player's progress (a fresh start, saved when they leave)
function GameData.Reset(player)
	local session = sessions[player]
	if not session then
		return false
	end
	session.Data = newData()
	player:SetAttribute("Coins", session.Data.Coins)
	return true
end

function GameData.Save(player)
	local session = sessions[player]
	if not session or not session.CanSave then
		return false
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:SetAsync(keyFor(player), session.Data)
		end)
		if ok then
			return true
		end
		warn(string.format("[GameData] save failed for %s (try %d): %s", player.Name, attempt, tostring(err)))
		task.wait(1.5)
	end
	return false
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPlayer, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	GameData.Save(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		GameData.Save(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			GameData.Save(player)
		end
	end
end)

return GameData
