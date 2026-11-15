--[[
	CoinFix  (Script, NOT a LocalScript)
	Put in: ServerScriptService

	Takes away coins that are way too high. Whenever a player joins, once their saved data
	has loaded, if they have MORE than MAX_ALLOWED coins, their coins are set to RESET_TO.
	The fixed number saves itself like normal.

	Players who are not in the game right now get fixed the next time they join.
	When everyone has been fixed, you can delete this script.
]]

local Players = game:GetService("Players")

local GameData = require(script.Parent:WaitForChild("GameData"))

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local MAX_ALLOWED = 1000000   -- anyone with MORE than this gets reset
local RESET_TO = 20000-- what they get instead
local SKIP_GAME_OWNER = true  -- don't touch YOUR coins (works when the game is on your own account)

local function fix(player)
	if SKIP_GAME_OWNER and game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return
	end

	-- wait for their saved data to load (up to 30 seconds)
	local data
	for _ = 1, 60 do
		local ok, result = pcall(GameData.Get, player)
		if ok and result then
			data = result
			break
		end
		task.wait(0.5)
	end
	if not data then
		warn("[CoinFix] data never loaded for " .. player.Name)
		return
	end

	local coins = data.Coins
	if type(coins) == "number" and coins > MAX_ALLOWED then
		data.Coins = RESET_TO
		player:SetAttribute("Coins", RESET_TO) -- updates the coin counter on their screen
		print(string.format("[CoinFix] %s had %s coins, set to %d", player.Name, tostring(coins), RESET_TO))
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(fix, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(fix, player)
end

