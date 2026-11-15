local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local GameData = require(script.Parent:WaitForChild("GameData"))

local function isOwner(player)
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local command = Instance.new("TextChatCommand")
command.Name = "CoinsCommand"
command.PrimaryAlias = "/coins"
command.Parent = TextChatService

command.Triggered:Connect(function(source, text)
	local player = Players:GetPlayerByUserId(source.UserId)
	if not player or not isOwner(player) then
		return
	end
	local amount = tonumber(text:match("/coins%s+(%-?%d+)"))
	if amount then
		GameData.AddCoins(player, amount)
	end
end)