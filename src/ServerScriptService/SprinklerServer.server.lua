--[[
	SprinklerServer  (Script)  -- ServerScriptService

	Stardust Sprinklers from the gear shop:
	  * equip one and click a garden bed in YOUR base to place it (SprinklerClient sends the click)
	  * while it runs, every planet in its range grows faster (GrowBoost in GearCatalog)
	  * stardust floats around those planets; BLACK HOLES suck it in, and every 10 seconds each one
	    has a chance (StardustChance) to get the Stardust mutation
	  * placed sprinklers are saved and keep counting down while you're offline
	  * sprinklers belong to your BASE: they only show while you own one, move with you to a new
	    base (like your planets) and disappear when you leave or lose the base

	Needs: GameData, BaseService, GameServer (GearBridge), PlantingServer (GardenAPI), GearCatalog.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local GameData = require(script.Parent:WaitForChild("GameData"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
local SprinklerModel = require(ReplicatedStorage:WaitForChild("SprinklerModel"))
local gearBridge = ServerStorage:WaitForChild("GearBridge")
local gardenApi = ServerStorage:WaitForChild("GardenAPI")

local PAD_TAG = "GardenPad"
local MAX_PLACE_DISTANCE = 45 -- how far from your character you can place one
local MUTATION_EVERY = 10      -- seconds between Stardust rolls for black holes
local MIN_GAP = 4              -- sprinklers can't be placed closer than this to each other

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local function getRemote(name)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end
local placeRemote = getRemote("PlaceGear") -- client -> server: (gearId, position, pad)
local noticeRemote = getRemote("Notice")

local function notice(player, text, kind)
	noticeRemote:FireClient(player, text, kind or "ok")
end

local folder = workspace:FindFirstChild("Sprinklers")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Sprinklers"
	folder.Parent = workspace
end

local active = {} -- { Model, Owner, Gear, Entry, Label }

---------------------------------------------------------------------
-- The sprinkler model
---------------------------------------------------------------------
local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function buildModel(gear, position, ownerId, untilTime)
	local model = SprinklerModel.Build(gear, CFrame.new(position))
	model:SetAttribute("Owner", ownerId)
	model:SetAttribute("GearId", gear.Id)
	model:SetAttribute("Radius", gear.Radius)
	model:SetAttribute("Until", untilTime)
	model:SetAttribute("DustColor", gear.DustColor)
	-- name + timer floating above the design. Hung on the upright "Origin" point at the bottom:
	-- the Base part is a cylinder turned on its side, and a label's offset turns with its part
	local anchor = model:FindFirstChild("Origin") or model.PrimaryPart

	local gui = Instance.new("BillboardGui")
	gui.Name = "Timer"
	gui.Size = UDim2.fromOffset(170, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, model:GetAttribute("CoreY") + 3.4, 0) -- above the top of the design
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 17
	text.TextColor3 = gear.DustColor
	text.TextStrokeTransparency = 0
	text.RichText = true
	text.Text = gear.Name
	text.Parent = gui

	model.Parent = folder
	return model, text
end

---------------------------------------------------------------------
-- Placing
---------------------------------------------------------------------
local function countFor(player)
	local n = 0
	for _, s in ipairs(active) do
		if s.Owner == player then
			n += 1
		end
	end
	return n
end

-- the base a saved sprinkler was placed on (older saves didn't record it: work it out from the spot)
local function savedBaseSpot(entry)
	if entry.BX then
		return Vector3.new(entry.BX, entry.BY, entry.BZ)
	end
	local old = BaseService.BaseAtPosition(Vector3.new(entry.X, entry.Y, entry.Z))
	return old and Vector3.new(old.Center.X, old.Top, old.Center.Z) or nil
end

-- shows a saved sprinkler on the player's CURRENT base (slid over if it was saved on another base)
local function spawnSprinkler(player, entry, base)
	local gear = GearCatalog.Get(entry.Id)
	if not gear or not base then
		return nil
	end
	local from = savedBaseSpot(entry)
	local to = Vector3.new(base.Center.X, base.Top, base.Center.Z)
	if from and (from - to).Magnitude > 1 then
		entry.X += to.X - from.X
		entry.Y += to.Y - from.Y
		entry.Z += to.Z - from.Z
	end
	entry.BX, entry.BY, entry.BZ = to.X, to.Y, to.Z
	local model, label = buildModel(gear, Vector3.new(entry.X, entry.Y, entry.Z), player.UserId, entry.Until)
	local s = { Model = model, Owner = player, Gear = gear, Entry = entry, Label = label }
	table.insert(active, s)
	return s
end

-- takes a player's sprinklers out of the world (they stay saved and keep counting down)
local function despawnFor(player)
	for i = #active, 1, -1 do
		if active[i].Owner == player then
			active[i].Model:Destroy()
			table.remove(active, i)
		end
	end
end

local lastPlace = {}
placeRemote.OnServerEvent:Connect(function(player, gearId, position, pad)
	if typeof(gearId) ~= "string" or typeof(position) ~= "Vector3" or typeof(pad) ~= "Instance" then
		return
	end
	local now = os.clock()
	if lastPlace[player] and now - lastPlace[player] < 0.5 then
		return
	end
	lastPlace[player] = now

	local gear = GearCatalog.Get(gearId)
	local data = GameData.Get(player)
	if not gear or not data then
		return
	end

	-- must be one of YOUR garden beds
	if not pad:IsA("BasePart") or not CollectionService:HasTag(pad, PAD_TAG) then
		notice(player, "Place sprinklers on a garden bed.", "error")
		return
	end
	local myBase = BaseService.BaseOf(player)
	if not myBase then
		notice(player, "Claim a base first (plant a seed on it).", "error")
		return
	end
	if BaseService.BaseForPad(pad) ~= myBase then
		notice(player, "You can only place sprinklers in your own base.", "error")
		return
	end

	-- snap onto the top of the bed, inside its edges
	local localPos = pad.CFrame:PointToObjectSpace(position)
	local half = pad.Size / 2
	localPos = Vector3.new(
		math.clamp(localPos.X, -half.X + 1.2, half.X - 1.2),
		half.Y,
		math.clamp(localPos.Z, -half.Z + 1.2, half.Z - 1.2)
	)
	local spot = pad.CFrame:PointToWorldSpace(localPos)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - spot).Magnitude > MAX_PLACE_DISTANCE then
		notice(player, "Walk closer to place it.", "error")
		return
	end
	if countFor(player) >= GearCatalog.MaxPlaced then
		notice(player, "You already have " .. GearCatalog.MaxPlaced .. " sprinklers running.", "error")
		return
	end
	for _, s in ipairs(active) do
		if s.Model.PrimaryPart and (s.Model.PrimaryPart.Position - spot).Magnitude < MIN_GAP then
			notice(player, "Too close to another sprinkler.", "error")
			return
		end
	end

	if not gearBridge:Invoke("use", player, gear.Id) then
		notice(player, "You don't have a " .. gear.Name .. ".", "error")
		return
	end

	data.Sprinklers = data.Sprinklers or {}
	local entry = {
		Id = gear.Id, X = spot.X, Y = spot.Y, Z = spot.Z, Until = os.time() + gear.Duration,
		BX = myBase.Center.X, BY = myBase.Top, BZ = myBase.Center.Z, -- which base it's on
	}
	table.insert(data.Sprinklers, entry)
	spawnSprinkler(player, entry, myBase)
	notice(player, gear.Name .. " placed! It runs for " .. math.floor(gear.Duration / 60) .. " minutes.", "ok")
end)

---------------------------------------------------------------------
-- Join / leave
---------------------------------------------------------------------
-- Sprinklers follow your base: nothing shows until you own one (like your planets), they slide
-- over if you claim a different base, and they vanish if the base is released. Checked every second.
local shownOn = {} -- player -> the base their sprinklers are showing on

local function syncPlayer(player)
	local data = GameData.Get(player)
	if not data then
		return
	end
	data.Sprinklers = data.Sprinklers or {}
	local base = BaseService.BaseOf(player)
	if base == shownOn[player] then
		return
	end
	despawnFor(player)
	shownOn[player] = base
	if not base then
		return
	end
	local now = os.time()
	for i = #data.Sprinklers, 1, -1 do
		local entry = data.Sprinklers[i]
		if type(entry) ~= "table" or type(entry.Until) ~= "number" or entry.Until <= now or not GearCatalog.Get(entry.Id) then
			table.remove(data.Sprinklers, i) -- ran out while you were away
		else
			spawnSprinkler(player, entry, base)
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	despawnFor(player)
	shownOn[player] = nil
	lastPlace[player] = nil
end)

---------------------------------------------------------------------
-- Admin panel API (a BindableFunction: only server scripts can call it; AdminServer checks permissions)
--   "list", player            their placed sprinklers
--   "remove", player, key     one of them, or "all" (also removed from their save)
--   "spawn", player, gearId, count   placed on free spots of their base, running for the full time
---------------------------------------------------------------------
do
	local api = Instance.new("BindableFunction")
	api.Name = "SprinklerAPI"
	api.Parent = ServerStorage
	local keys = 0

	api.OnInvoke = function(action, player, a, b)
		if action == "list" then
			local list = {}
			for _, s in ipairs(active) do
				if s.Owner == player then
					if not s.Key then
						keys += 1
						s.Key = keys
					end
					table.insert(list, { Key = s.Key, Id = s.Gear.Id, Name = s.Gear.Name, Rarity = s.Gear.Rarity, Left = s.Entry.Until - os.time() })
				end
			end
			return list

		elseif action == "remove" then
			local data = GameData.Get(player)
			local removed = 0
			for i = #active, 1, -1 do
				local s = active[i]
				if s.Owner == player and (a == "all" or s.Key == a) then
					s.Model:Destroy()
					table.remove(active, i)
					if data and data.Sprinklers then
						local index = table.find(data.Sprinklers, s.Entry)
						if index then
							table.remove(data.Sprinklers, index)
						end
					end
					removed += 1
				end
			end
			return removed

		elseif action == "spawn" then
			local gear = GearCatalog.Get(a)
			local data = GameData.Get(player)
			local base = BaseService.BaseOf(player)
			if not gear or not data then
				return 0, "Unknown sprinkler"
			end
			if not base or not base.Pads or #base.Pads == 0 then
				return 0, player.DisplayName .. " doesn't have a base yet"
			end
			data.Sprinklers = data.Sprinklers or {}
			local made = 0
			for _ = 1, math.clamp(tonumber(b) or 1, 1, GearCatalog.MaxPlaced) do
				local spot
				for _ = 1, 60 do
					local pad = base.Pads[math.random(1, #base.Pads)]
					if pad and pad.Parent then
						local half = pad.Size / 2
						local p = pad.CFrame:PointToWorldSpace(Vector3.new(
							(math.random() * 2 - 1) * (half.X - 1.2), half.Y, (math.random() * 2 - 1) * (half.Z - 1.2)))
						local clear = true
						for _, other in ipairs(active) do
							if other.Model.PrimaryPart and (other.Model.PrimaryPart.Position - p).Magnitude < MIN_GAP then
								clear = false
								break
							end
						end
						if clear then
							spot = p
							break
						end
					end
				end
				if not spot then
					break
				end
				local entry = {
					Id = gear.Id, X = spot.X, Y = spot.Y, Z = spot.Z, Until = os.time() + gear.Duration,
					BX = base.Center.X, BY = base.Top, BZ = base.Center.Z,
				}
				table.insert(data.Sprinklers, entry)
				spawnSprinkler(player, entry, base)
				made += 1
			end
			return made, made == 0 and "No free space in their base" or nil
		end
		return nil
	end
end

---------------------------------------------------------------------
-- Every second: count down, speed up planets, stardust, and Stardust mutation rolls
---------------------------------------------------------------------
local rng = Random.new()
local sinceRoll = 0

local function flatDistance(a, b)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

task.spawn(function()
	while true do
		local dt = task.wait(1)
		local now = os.time()
		sinceRoll += dt
		local rollNow = sinceRoll >= MUTATION_EVERY
		if rollNow then
			sinceRoll = 0
		end

		-- show / move / hide sprinklers to match each player's base
		for _, player in ipairs(Players:GetPlayers()) do
			syncPlayer(player)
		end

		-- remove sprinklers that ran out
		for i = #active, 1, -1 do
			local s = active[i]
			if s.Entry.Until <= now or not s.Owner.Parent then
				s.Model:Destroy()
				table.remove(active, i)
				local data = GameData.Get(s.Owner)
				if data and data.Sprinklers then
					local index = table.find(data.Sprinklers, s.Entry)
					if index then
						table.remove(data.Sprinklers, index)
					end
				end
				if s.Owner.Parent then
					notice(s.Owner, "Your " .. s.Gear.Name .. " ran out.", "ok")
				end
			else
				s.Label.Text = string.format('%s\n<font color="#ffffff">%s</font>', s.Gear.Name, formatTime(s.Entry.Until - now))
			end
		end

		-- each owner's planets, once per tick
		local byOwner = {}
		for _, s in ipairs(active) do
			byOwner[s.Owner] = byOwner[s.Owner] or {}
			table.insert(byOwner[s.Owner], s)
		end
		for owner, list in pairs(byOwner) do
			local ok, plants = pcall(function()
				return gardenApi:Invoke("plants", owner)
			end)
			if ok and type(plants) == "table" then
				for _, p in ipairs(plants) do
					local pivot = p.Model:GetPivot().Position
					local best, bestGear = nil, nil
					for _, s in ipairs(list) do
						local center = s.Model.PrimaryPart and s.Model.PrimaryPart.Position
						if center and flatDistance(center, pivot) <= s.Gear.Radius then
							if not best or s.Gear.GrowBoost > best.GrowBoost then
								best, bestGear = s.Gear, s.Gear
							end
						end
					end
					if best then
						-- the client shows stardust around planets with this (and sucks it into black holes)
						p.Model:SetAttribute("StardustUntil", now + 2)
						p.Model:SetAttribute("StardustColor", bestGear.DustColor)
						p.Model:SetAttribute("StardustStyle", bestGear.Id) -- which sprinkler's stardust floats around it
						p.Model:SetAttribute("Group", p.Group) -- the client sucks the dust into black holes
						if not p.Ready then
							gardenApi:Invoke("boost", p.Model, (best.GrowBoost - 1) * dt)
						end
						if rollNow and p.Group == "BlackHole" and not p.HasStardust and rng:NextNumber() < best.StardustChance then
							gardenApi:Invoke("mutate", p.Model, "stardust")
						end
					end
					-- bonus mutations: every sprinkler covering this planet rolls its own (they stack)
					if rollNow then
						local has = p.Mutations or {}
						for _, s in ipairs(list) do
							local gear = s.Gear
							local center = s.Model.PrimaryPart and s.Model.PrimaryPart.Position
							if gear.BonusMutation and center and flatDistance(center, pivot) <= gear.Radius
								and not table.find(has, gear.BonusMutation) and rng:NextNumber() < (gear.BonusChance or 0) then
								if gardenApi:Invoke("mutate", p.Model, gear.BonusMutation) then
									table.insert(has, gear.BonusMutation)
								end
							end
						end
					end
				end
			end
		end
	end
end)

print("[SprinklerServer] Ready")
