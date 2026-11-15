--[[
	TutorialServer  (Script)  -- ServerScriptService

	Remembers each player's tutorial progress in their saved data (GameData, field "Tutorial"):
	  Done        which steps / discoveries they've finished
	  Skipped     they pressed SKIP (no more guided steps until they press ? to restart)
	  Experienced they already had progress when the tutorial was added, so the basics are skipped

	TutorialClient asks for it when you join and tells the server when a step is finished.
	Only step ids from TutorialSteps are accepted. Nothing here changes coins or items.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(script.Parent:WaitForChild("GameData"))
local TutorialSteps = require(ReplicatedStorage:WaitForChild("TutorialSteps"))

local VERSION = 1
local MAX_DONE = 400
local START_COINS = 50

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local function getRemote(name, class)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(class)
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end
local stateRemote = getRemote("TutorialState", "RemoteFunction")
local eventRemote = getRemote("TutorialEvent", "RemoteEvent")

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n += 1
	end
	return n
end

local function tutorialOf(player)
	local data = GameData.Get(player)
	if not data then
		return nil
	end
	local t = data.Tutorial
	if type(t) ~= "table" then
		t = {}
		data.Tutorial = t
	end
	if t.Version == nil then
		-- first time this player meets the tutorial: did they already play?
		local played = (#(data.Plants or {}) > 0) or (#(data.Planets or {}) > 0) or (#(data.Sprinklers or {}) > 0)
			or next(data.Seeds or {}) ~= nil or next(data.Packs or {}) ~= nil or next(data.Gear or {}) ~= nil
			or (data.Coins or 0) > START_COINS
		t.Version = VERSION
		t.Done = {}
		if played then
			t.Experienced = true
			for _, step in ipairs(TutorialSteps.Core) do
				t.Done[step.Id] = true
			end
		end
	end
	t.Done = type(t.Done) == "table" and t.Done or {}
	return t
end

stateRemote.OnServerInvoke = function(player)
	local deadline = os.clock() + 20
	while not GameData.Get(player) and os.clock() < deadline and player.Parent do
		task.wait(0.25)
	end
	local t = tutorialOf(player)
	if not t then
		return nil
	end
	return { Done = t.Done, Skipped = t.Skipped == true, Experienced = t.Experienced == true }
end

local recent = {}
eventRemote.OnServerEvent:Connect(function(player, action, id)
	local now = os.clock()
	local list = recent[player] or {}
	recent[player] = list
	while list[1] and now - list[1] > 5 do
		table.remove(list, 1)
	end
	if #list > 20 then
		return
	end
	table.insert(list, now)

	local t = tutorialOf(player)
	if not t then
		return
	end
	if action == "done" and TutorialSteps.IsValidId(id) then
		if count(t.Done) < MAX_DONE then
			t.Done[id] = true
		end
	elseif action == "skip" then
		t.Skipped = true
	elseif action == "restart" then
		t.Skipped = false
		t.Experienced = false
		-- keep discoveries, replay the lessons
		for _, list2 in ipairs({ TutorialSteps.Core, TutorialSteps.Side }) do
			for _, step in ipairs(list2) do
				t.Done[step.Id] = nil
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	recent[player] = nil
end)

print("[TutorialServer] ready")
