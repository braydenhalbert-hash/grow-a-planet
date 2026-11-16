--[[
	FriendBoost  (Script)  -- ServerScriptService

	Grow a Garden style Friend Boost: +10% sell money for every Roblox friend in the same
	server as you (up to +50%). Each player gets an attribute "FriendBoost" (the percent),
	which the coin bar shows ("Friend Boost: +10%") and SellServer adds to every sale.
]]

local Players = game:GetService("Players")

local PERCENT_PER_FRIEND = 10
local MAX_PERCENT = 50

local friendCache = {} -- [userIdA .. ":" .. userIdB] = true/false

local function areFriends(a, b)
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = low .. ":" .. high
	if friendCache[key] == nil then
		local ok, result = pcall(function()
			return a:IsFriendsWith(b.UserId)
		end)
		if not ok then
			return false -- try again next time
		end
		friendCache[key] = result
	end
	return friendCache[key]
end

local function update()
	local players = Players:GetPlayers()
	for _, player in ipairs(players) do
		local friends = 0
		for _, other in ipairs(players) do
			if other ~= player and areFriends(player, other) then
				friends += 1
			end
		end
		player:SetAttribute("FriendBoost", math.min(friends * PERCENT_PER_FRIEND, MAX_PERCENT))
	end
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("FriendBoost", 0)
	task.defer(update)
end)
Players.PlayerRemoving:Connect(function()
	task.defer(update)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player:SetAttribute("FriendBoost", 0)
end
task.spawn(update)

-- friendships can change while playing (someone accepts a friend request): re-check now and then
task.spawn(function()
	while true do
		task.wait(60)
		table.clear(friendCache)
		update()
	end
end)

print("[FriendBoost] ready")
