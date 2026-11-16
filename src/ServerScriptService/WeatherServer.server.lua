--[[
	WeatherServer  (Script)  -- ServerScriptService

	Runs the space weather and the live events for the whole server (server-authoritative):
	  * WEATHER   picks a weather from WeatherConfig every few minutes and runs it through LiveOps
	              (so the admin panel's weather buttons keep working). While it runs, every planet in every
	              garden rolls for that weather's mutations every WeatherConfig.RollEvery seconds.
	  * EVENTS    every 15-25 minutes a live event from EventConfig: a 60 second countdown everyone sees,
	              then the event itself (boosts, mutation rolls, meteor shards, alien beams), then coins for
	              everyone in the server.
	  * DISCOVERY when one of your planets gets ANY mutation you get a popup; the first time ever you get
	              a mutation it's a NEW DISCOVERY (saved in your data).

	Everything clients need is published as attributes on ReplicatedStorage.LiveOps:
	  Weather, WeatherUntil, WeatherStarted (LiveOps)   WeatherNext, WeatherNextAt
	  LiveEvent, LiveEventPhase ("countdown"/"active"), LiveEventStart, LiveEventUntil, Gravity
	Remotes in ReplicatedStorage.WeatherRemotes:
	  MutationDiscovered (to the owner): mutationId, planetModel, planetName, isNew
	  EventFx (to everyone or one player): kind, ...

	Commands for the owner (type in chat):  /weather <id or clear> [seconds]   /event <id> [countdown seconds]
	Needs: LiveOps, GameData (ServerScriptService), WeatherConfig, EventConfig, MutationCatalog (ReplicatedStorage),
	       PlantingServer (makes ServerStorage.GardenAPI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local LiveOps = require(script.Parent:WaitForChild("LiveOps"))
local GameData = require(script.Parent:WaitForChild("GameData"))
local WeatherConfig = require(ReplicatedStorage:WaitForChild("WeatherConfig"))
local EventConfig = require(ReplicatedStorage:WaitForChild("EventConfig"))
local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))

local state = ReplicatedStorage:WaitForChild("LiveOps")
local rng = Random.new()

local function now()
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("WeatherRemotes") or Instance.new("Folder")
remotes.Name = "WeatherRemotes"
remotes.Parent = ReplicatedStorage
local function remote(name)
	local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local discoveredRemote = remote("MutationDiscovered")
local fxRemote = remote("EventFx")

state:SetAttribute("WeatherNext", "")
state:SetAttribute("WeatherNextAt", 0)
state:SetAttribute("LiveEvent", "")
state:SetAttribute("LiveEventPhase", "")
state:SetAttribute("LiveEventStart", 0)
state:SetAttribute("LiveEventUntil", 0)
state:SetAttribute("Gravity", 1)

local gardenApi = ServerStorage:WaitForChild("GardenAPI", 60)

local function allPlants()
	local list = {}
	if not gardenApi then
		return list
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, plants = pcall(function()
			return gardenApi:Invoke("plants", player)
		end)
		if ok and type(plants) == "table" then
			for _, p in ipairs(plants) do
				p.Owner = player
				table.insert(list, p)
			end
		end
	end
	return list
end

local function mutate(model, mutId)
	local ok, result = pcall(function()
		return gardenApi:Invoke("mutate", model, mutId)
	end)
	return ok and result
end

-- every planet rolls once for a list of { Id, Chance }: at most ONE new mutation per planet per roll
local function rollMutations(list)
	if not list or #list == 0 then
		return 0
	end
	local luck = LiveOps.Get("Luck")
	local given = 0
	for _, plant in ipairs(allPlants()) do
		for _, m in ipairs(list) do
			if MutationCatalog.Get(m.Id) and not table.find(plant.Mutations, m.Id) then
				if rng:NextNumber() < math.min(m.Chance * luck, 0.9) then
					if mutate(plant.Model, m.Id) then
						given += 1
						break
					end
				end
			end
		end
	end
	return given
end

---------------------------------------------------------------------
-- Gravity (weather and events can lower it; clients apply it to their own character)
---------------------------------------------------------------------
local eventGravity = 1
local function updateGravity()
	local w = WeatherConfig.Get(state:GetAttribute("Weather") or "clear")
	local g = math.min(w and w.Gravity or 1, eventGravity)
	state:SetAttribute("Gravity", g)
end

---------------------------------------------------------------------
-- WEATHER
---------------------------------------------------------------------
local lastWeather = nil
local function planNextWeather(delay)
	local nextWeather = WeatherConfig.Pick(rng, lastWeather)
	state:SetAttribute("WeatherNext", nextWeather.Id)
	state:SetAttribute("WeatherNextAt", now() + delay)
end

local function startWeather(id, seconds)
	local w = WeatherConfig.Get(id)
	if not w then
		return false
	end
	if id == "clear" then
		LiveOps.SetWeather("clear", 0)
		return true
	end
	seconds = seconds or rng:NextInteger(w.Duration[1], w.Duration[2])
	lastWeather = id
	LiveOps.SetWeather(id, seconds)
	print(string.format("[WeatherServer] weather: %s for %ds", w.Name, seconds))
	return true
end

state:GetAttributeChangedSignal("Weather"):Connect(function()
	local id = state:GetAttribute("Weather")
	if id == "clear" then
		planNextWeather(rng:NextInteger(WeatherConfig.GapMin, WeatherConfig.GapMax))
	else
		lastWeather = id
		state:SetAttribute("WeatherNext", "")
		state:SetAttribute("WeatherNextAt", 0)
	end
	updateGravity()
end)
planNextWeather(WeatherConfig.FirstDelay)

local nextWeatherRoll = 0
task.spawn(function()
	while true do
		task.wait(1)
		local t = now()
		local id = state:GetAttribute("Weather") or "clear"
		if id == "clear" then
			local at = state:GetAttribute("WeatherNextAt") or 0
			local nextId = state:GetAttribute("WeatherNext") or ""
			if at > 0 and t >= at and nextId ~= "" then
				startWeather(nextId)
				nextWeatherRoll = t + WeatherConfig.RollEvery
			end
		else
			local w = WeatherConfig.Get(id)
			if w and t >= nextWeatherRoll then
				nextWeatherRoll = t + WeatherConfig.RollEvery
				local given = rollMutations(w.Mutations)
				if given > 0 then
					print(string.format("[WeatherServer] %s mutated %d planets", w.Name, given))
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- LIVE EVENTS
---------------------------------------------------------------------
local currentEvent = nil
local eventToken = 0
local lastEvent = nil
local shardsModel = nil

local function crashGround()
	local site = EventConfig.CrashSite
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, name in ipairs({ "PlantedPlanets", "MutationFX", "LiveEventFX" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(site.X, 1400, site.Z), Vector3.new(0, -1600, 0), params)
	return hit and hit.Position or Vector3.new(site.X, 901, site.Z)
end

local function rewardFor(player, reward)
	local coins = GameData.GetCoins(player)
	local amount = math.clamp(math.floor(coins * (reward.CoinPercent or 0)), reward.CoinMin or 0, reward.CoinMax or math.huge)
	return amount
end

local function giveShard(player, shard, event)
	if shard:GetAttribute("C" .. player.UserId) then
		return
	end
	shard:SetAttribute("C" .. player.UserId, true)
	local amount = math.clamp(math.floor(GameData.GetCoins(player) * event.ShardCoinPercent), event.ShardCoinMin or 0, 1e15)
	GameData.AddCoins(player, amount)
	local mutatedName = nil
	if event.ShardMutation and rng:NextNumber() < event.ShardMutationChance and gardenApi then
		local ok, plants = pcall(function()
			return gardenApi:Invoke("plants", player)
		end)
		if ok and type(plants) == "table" then
			local options = {}
			for _, p in ipairs(plants) do
				if not table.find(p.Mutations, event.ShardMutation) then
					table.insert(options, p)
				end
			end
			if #options > 0 then
				local pick = options[rng:NextInteger(1, #options)]
				if mutate(pick.Model, event.ShardMutation) then
					mutatedName = pick.Model.Name
				end
			end
		end
	end
	fxRemote:FireClient(player, "shard", amount, mutatedName and event.ShardMutation or nil, mutatedName)
end

-- the meteor's crater and glowing shards (the falling meteor + explosion are drawn by LiveEventClient)
local function buildCrater(event)
	local ground = crashGround()
	local model = Instance.new("Model")
	model.Name = "MeteorCrater"

	local function part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = props.CanCollide ~= false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do
			if k ~= "CanCollide" then
				p[k] = v
			end
		end
		p.Parent = model
		return p
	end

	-- scorched ground + a ring of broken rock
	part({ Name = "Scorch", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 46, 46), CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(35, 22, 20), Material = Enum.Material.Basalt, CanCollide = false })
	part({ Name = "Glow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 30, 30), CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 90, 20), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false })
	for i = 1, 14 do
		local a = (i / 14) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local d = rng:NextNumber(17, 22)
		local s = rng:NextNumber(3, 6)
		part({ Name = "Rock", Size = Vector3.new(s, s * rng:NextNumber(0.6, 1.2), s * rng:NextNumber(0.8, 1.4)),
			CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * d, s * 0.25, math.sin(a) * d)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), a, rng:NextNumber(-0.5, 0.5)),
			Color = Color3.fromRGB(60, 45, 42), Material = Enum.Material.Basalt })
	end
	-- the meteor itself, half buried and still glowing
	local rock = part({ Name = "Meteor", Shape = Enum.PartType.Ball, Size = Vector3.new(14, 14, 14), CFrame = CFrame.new(ground + Vector3.new(0, 3, 0)),
		Color = Color3.fromRGB(55, 40, 38), Material = Enum.Material.CrackedLava })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Range = 40
	light.Brightness = 3
	light.Parent = rock
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 60, 20))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new(5, 0)
	fire.Lifetime = NumberRange.new(1, 2)
	fire.Speed = NumberRange.new(4, 9)
	fire.Rate = 25
	fire.SpreadAngle = Vector2.new(40, 40)
	fire.Parent = rock
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 55, 50))
	smoke.Size = NumberSequence.new(6, 16)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Speed = NumberRange.new(5, 9)
	smoke.Rate = 6
	smoke.Parent = rock

	-- shards to grab
	for i = 1, event.Shards or 8 do
		local a = (i / (event.Shards or 8)) * math.pi * 2 + 0.3
		local d = rng:NextNumber(9, 15)
		local shard = part({ Name = "Shard", Size = Vector3.new(1.4, 3.6, 1.4),
			CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * d, 2, math.sin(a) * d)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), a, rng:NextNumber(-0.4, 0.4)),
			Color = Color3.fromRGB(255, 190, 70), Material = Enum.Material.Neon, CanCollide = false })
		shard:SetAttribute("MeteorShard", true)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Grab Shard"
		prompt.ObjectText = "Meteor Shard"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = shard
		prompt.Triggered:Connect(function(player)
			giveShard(player, shard, event)
		end)
	end

	local folder = workspace:FindFirstChild("LiveEventFX") or Instance.new("Folder")
	folder.Name = "LiveEventFX"
	folder.Parent = workspace
	model.Parent = folder
	return model
end

local function endEvent(token)
	if token ~= eventToken or not currentEvent then
		return
	end
	local event = currentEvent
	currentEvent = nil
	for id in pairs(event.Boosts or {}) do
		LiveOps.SetExtra(id, 1)
	end
	eventGravity = 1
	updateGravity()
	-- rewards for everyone who was here
	for _, player in ipairs(Players:GetPlayers()) do
		if GameData.Get(player) then
			local amount = rewardFor(player, event.Reward or {})
			if amount > 0 then
				GameData.AddCoins(player, amount)
			end
			fxRemote:FireClient(player, "reward", event.Id, amount)
		end
	end
	state:SetAttribute("LiveEventPhase", "ended")
	task.delay(8, function()
		if token == eventToken then
			state:SetAttribute("LiveEvent", "")
			state:SetAttribute("LiveEventPhase", "")
			state:SetAttribute("LiveEventStart", 0)
			state:SetAttribute("LiveEventUntil", 0)
		end
		if shardsModel then
			shardsModel:Destroy()
			shardsModel = nil
		end
	end)
	print("[WeatherServer] event ended: " .. event.Name)
end

local nextEventAt = now() + EventConfig.FirstDelay

local function startEvent(id, countdown)
	local event = EventConfig.Get(id)
	if not event then
		return false
	end
	if currentEvent then
		endEvent(eventToken)
	end
	eventToken += 1
	local token = eventToken
	lastEvent = id
	countdown = countdown or EventConfig.Countdown
	local startAt = now() + countdown
	state:SetAttribute("LiveEvent", id)
	state:SetAttribute("LiveEventPhase", "countdown")
	state:SetAttribute("LiveEventStart", startAt)
	state:SetAttribute("LiveEventUntil", startAt + event.Duration)
	print(string.format("[WeatherServer] event %s in %ds", event.Name, countdown))

	task.delay(countdown, function()
		if token ~= eventToken then
			return
		end
		currentEvent = event
		state:SetAttribute("LiveEventPhase", "active")
		for boostId, value in pairs(event.Boosts or {}) do
			LiveOps.SetExtra(boostId, value)
		end
		eventGravity = event.Gravity or 1
		updateGravity()

		if event.Shards then
			task.delay(4.6, function() -- matches the meteor's fall in LiveEventClient
				if token == eventToken then
					if shardsModel then
						shardsModel:Destroy()
					end
					shardsModel = buildCrater(event)
				end
			end)
		end

		local untilTime = now() + event.Duration
		local nextRoll = now() + 5
		local nextBeam = now() + 6
		while token == eventToken and currentEvent == event and now() < untilTime do
			task.wait(0.5)
			local t = now()
			if t >= nextRoll then
				nextRoll = t + EventConfig.RollEvery
				rollMutations(event.Mutations)
			end
			if event.Abductions and t >= nextBeam then
				nextBeam = t + (event.BeamEvery or 4)
				local plants = allPlants()
				if #plants > 0 then
					local pick = plants[rng:NextInteger(1, #plants)]
					fxRemote:FireAllClients("beam", pick.Model)
					if event.BeamMutation and not table.find(pick.Mutations, event.BeamMutation) and rng:NextNumber() < (event.BeamChance or 0) * LiveOps.Get("Luck") then
						task.delay(1.6, function()
							mutate(pick.Model, event.BeamMutation)
						end)
					end
				end
			end
		end
		endEvent(token)
		nextEventAt = now() + rng:NextInteger(EventConfig.GapMin, EventConfig.GapMax)
	end)
	return true
end

task.spawn(function()
	while true do
		task.wait(1)
		if not currentEvent and (state:GetAttribute("LiveEventPhase") or "") == "" and now() >= nextEventAt then
			nextEventAt = now() + EventConfig.GapMax -- (set properly when it ends)
			startEvent(EventConfig.Pick(rng, lastEvent).Id)
		end
	end
end)

---------------------------------------------------------------------
-- MUTATION DISCOVERY (any mutation, from weather, events, sprinklers or planting)
---------------------------------------------------------------------
local QUIET_AFTER_PLANT = 4 -- seconds: mutations put back on a planet when you join aren't "new"

local function discovered(player)
	local data = GameData.Get(player)
	if not data then
		return nil
	end
	data.Discovered = data.Discovered or {}
	return data.Discovered
end

local function countDiscovered(player)
	local list = discovered(player)
	local n = 0
	for _ in pairs(list or {}) do
		n += 1
	end
	player:SetAttribute("MutationsFound", n)
end

local function watchPlanet(model)
	if not model:IsA("Model") then
		return
	end
	local addedAt = os.clock()
	local known = {}
	for _, id in ipairs(MutationCatalog.Parse(model:GetAttribute("Mutations") or "")) do
		known[id] = true
	end
	local function check()
		local owner = Players:GetPlayerByUserId(model:GetAttribute("Owner") or 0)
		for _, id in ipairs(MutationCatalog.Parse(model:GetAttribute("Mutations") or "")) do
			if not known[id] then
				known[id] = true
				if owner then
					local list = discovered(owner)
					local isNew = list ~= nil and not list[id]
					if list then
						list[id] = true
						countDiscovered(owner)
					end
					if os.clock() - addedAt > QUIET_AFTER_PLANT then
						discoveredRemote:FireClient(owner, id, model, model.Name, isNew)
					end
				end
			end
		end
	end
	model:GetAttributeChangedSignal("Mutations"):Connect(check)
	check()
end

task.spawn(function()
	local plantsFolder = workspace:WaitForChild("PlantedPlanets", 60)
	if not plantsFolder then
		return
	end
	for _, model in ipairs(plantsFolder:GetChildren()) do
		watchPlanet(model)
	end
	plantsFolder.ChildAdded:Connect(function(model)
		task.defer(watchPlanet, model)
	end)
end)

GameData.PlayerLoaded:Connect(countDiscovered)
for _, player in ipairs(Players:GetPlayers()) do
	if GameData.Get(player) then
		countDiscovered(player)
	end
end

---------------------------------------------------------------------
-- Owner commands + an API for other scripts
---------------------------------------------------------------------
local function isOwner(player)
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function command(alias, fn)
	local c = Instance.new("TextChatCommand")
	c.Name = "WeatherCmd_" .. alias
	c.PrimaryAlias = "/" .. alias
	c.Parent = TextChatService
	c.Triggered:Connect(function(source, text)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player and isOwner(player) then
			local args = string.split(text, " ")
			fn(args[2], tonumber(args[3]))
		end
	end)
end
command("weather", function(id, seconds)
	startWeather(id or "clear", seconds)
end)
command("event", function(id, countdown)
	startEvent(id or EventConfig.Pick(rng).Id, countdown or 10)
end)

local api = Instance.new("BindableFunction")
api.Name = "WeatherAPI"
api.OnInvoke = function(action, a, b)
	if action == "weather" then
		return startWeather(a, b)
	elseif action == "event" then
		return startEvent(a, b)
	elseif action == "stopEvent" then
		if currentEvent then
			endEvent(eventToken)
		end
		return true
	end
	return nil
end
api.Parent = ServerStorage

print("[WeatherServer] ready: " .. #WeatherConfig.List .. " weathers, " .. #EventConfig.List .. " live events")
