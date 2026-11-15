--[[
	SprinklerServer  (Script)  -- ServerScriptService

	Stardust Sprinklers from the gear shop:
	  * equip one and click a garden bed in YOUR base to place it (SprinklerClient sends the click)
	  * while it runs, every planet in its range grows faster (GrowBoost in GearCatalog)
	  * stardust floats around those planets; BLACK HOLES suck it in, and every 10 seconds each one
	    has a chance (StardustChance) to get the Stardust mutation
	  * placed sprinklers are saved and keep counting down while you're offline

	Needs: GameData, GameServer (GearBridge), PlantingServer (GardenAPI), GearCatalog.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local GameData = require(script.Parent:WaitForChild("GameData"))
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
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
local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function cylinderUp(position)
	-- Roblox cylinders lie on their side; turn them upright
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function buildModel(gear, position, ownerId, untilTime)
	local model = Instance.new("Model")
	model.Name = gear.Name
	model:SetAttribute("Owner", ownerId)
	model:SetAttribute("GearId", gear.Id)
	model:SetAttribute("Radius", gear.Radius)
	model:SetAttribute("Until", untilTime)
	model:SetAttribute("DustColor", gear.DustColor)

	local metal = Color3.fromRGB(120, 126, 134)
	local base = part({
		Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 2.2, 2.2),
		CFrame = cylinderUp(position + Vector3.new(0, 0.175, 0)), Color = Color3.fromRGB(60, 64, 70),
		Material = Enum.Material.DiamondPlate,
	}, model)
	part({
		Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 2.35, 2.35),
		CFrame = cylinderUp(position + Vector3.new(0, 0.38, 0)), Color = gear.Color, Material = Enum.Material.Neon,
		Transparency = 0.2,
	}, model)
	part({
		Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.1, 0.42, 0.42),
		CFrame = cylinderUp(position + Vector3.new(0, 1.4, 0)), Color = metal, Material = Enum.Material.Metal,
	}, model)
	part({
		Name = "Valve", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 0.75, 0.75),
		CFrame = CFrame.new(position + Vector3.new(0, 1.0, 0.3)), Color = Color3.fromRGB(200, 60, 50), Material = Enum.Material.Metal,
	}, model)
	local head = part({
		Name = "Head", Size = Vector3.new(1.1, 0.35, 1.1),
		CFrame = CFrame.new(position + Vector3.new(0, 2.6, 0)), Color = gear.Color, Material = Enum.Material.Neon,
	}, model)
	local cap = Instance.new("SpecialMesh")
	cap.MeshType = Enum.MeshType.Sphere
	cap.Scale = Vector3.new(1, 0.8, 1)
	cap.Parent = head
	-- three nozzles around the head (the client sprays stardust out of them and spins the head)
	for i = 1, 3 do
		local angle = (i - 1) * (math.pi * 2 / 3)
		local nozzle = Instance.new("Attachment")
		nozzle.Name = "Nozzle" .. i
		-- points outward and 45 degrees up
		nozzle.CFrame = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.5) * CFrame.Angles(math.rad(45), 0, 0)
		nozzle.Parent = head
	end
	model.PrimaryPart = base

	local gui = Instance.new("BillboardGui")
	gui.Name = "Timer"
	gui.Size = UDim2.fromOffset(170, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = base
	gui.Parent = base
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

local function spawnSprinkler(player, entry)
	local gear = GearCatalog.Get(entry.Id)
	if not gear then
		return nil
	end
	local model, label = buildModel(gear, Vector3.new(entry.X, entry.Y, entry.Z), player.UserId, entry.Until)
	local s = { Model = model, Owner = player, Gear = gear, Entry = entry, Label = label }
	table.insert(active, s)
	return s
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
	local owner = pad:GetAttribute("BaseOwner")
	if owner ~= nil and owner ~= player.UserId then
		notice(player, owner == 0 and "Claim this base first (plant a seed on it)." or "That's not your garden!", "error")
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
	local entry = { Id = gear.Id, X = spot.X, Y = spot.Y, Z = spot.Z, Until = os.time() + gear.Duration }
	table.insert(data.Sprinklers, entry)
	spawnSprinkler(player, entry)
	notice(player, gear.Name .. " placed! It runs for " .. math.floor(gear.Duration / 60) .. " minutes.", "ok")
end)

---------------------------------------------------------------------
-- Join / leave
---------------------------------------------------------------------
local function onJoin(player)
	local data = GameData.WaitFor(player)
	if not data or not player.Parent then
		return
	end
	data.Sprinklers = data.Sprinklers or {}
	local now = os.time()
	for i = #data.Sprinklers, 1, -1 do
		local entry = data.Sprinklers[i]
		if type(entry) ~= "table" or type(entry.Until) ~= "number" or entry.Until <= now or not GearCatalog.Get(entry.Id) then
			table.remove(data.Sprinklers, i) -- ran out while you were away
		else
			spawnSprinkler(player, entry)
		end
	end
end

Players.PlayerAdded:Connect(onJoin)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, player)
end

Players.PlayerRemoving:Connect(function(player)
	for i = #active, 1, -1 do
		if active[i].Owner == player then
			active[i].Model:Destroy()
			table.remove(active, i)
		end
	end
	lastPlace[player] = nil
end)

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
						p.Model:SetAttribute("Group", p.Group) -- the client sucks the dust into black holes
						if not p.Ready then
							gardenApi:Invoke("boost", p.Model, (best.GrowBoost - 1) * dt)
						end
						if rollNow and p.Group == "BlackHole" and not p.HasStardust and rng:NextNumber() < best.StardustChance then
							gardenApi:Invoke("mutate", p.Model, "stardust")
						end
					end
				end
			end
		end
	end
end)

print("[SprinklerServer] Ready")
