--[[
	Leaderboard  (Script)  -- ServerScriptService

	Shows everyone's money on the Roblox player list (the leaderboard you open with Tab).
	It reads each player's "Coins" attribute (kept up to date by GameData) and shows it short,
	the same way the coin bar does: 36.9B¢, 971.7T¢ ...
]]

local Players = game:GetService("Players")

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function short(n)
	n = math.floor(tonumber(n) or 0)
	if n < 1000 then
		return tostring(n) .. "¢"
	end
	local index = math.min(math.floor(math.log10(n) / 3), #SUFFIXES)
	local value = n / 10 ^ (index * 3)
	local text = string.format("%.1f", math.floor(value * 10) / 10):gsub("%.0$", "")
	return text .. SUFFIXES[index] .. "¢"
end

local function setup(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
	end
	local money = stats:FindFirstChild("Money") or Instance.new("StringValue")
	money.Name = "Money"
	money.Parent = stats
	stats.Parent = player

	local function update()
		money.Value = short(player:GetAttribute("Coins") or 0)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(update)
	update()
end

Players.PlayerAdded:Connect(setup)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setup, player)
end
