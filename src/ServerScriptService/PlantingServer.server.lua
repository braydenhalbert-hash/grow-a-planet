--[[
	PlantingServer  (Script, NOT a LocalScript)  -- REPLACES the earlier PlantingServer
	Put in: ServerScriptService

	Planting, growing and harvesting:
	  * you plant a seed on any part tagged "GardenPad" (your PlantingSpots script tags the
	    parts named "GROWING BEDS", so KEEP that script)
	  * the planet grows for its GrowTime (from PlanetCatalog), showing a countdown
	  * when it says READY!, hold E on it to harvest: it goes in your hotbar with a random weight
	  * keep holding E and the harvest STREAK takes over: it harvests every ready planet near you,
	    one after another, faster and faster (the HarvestStreak LocalScript sends the requests)
	  * plants are saved, so they keep growing while you're offline
	  * every seed has a small chance to grow BIGGER (see TIERS below): HUGE, INSANE or CRAZY.
	    Bigger ones weigh more, so they sell for more.

	Needs: GameData (same folder), PlanetCatalog + PlanetBuilder (ReplicatedStorage),
	       and the client scripts PlantingClient and HarvestStreak.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local GameData = require(script.Parent:WaitForChild("GameData"))
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PlanetBuilder = require(ReplicatedStorage:WaitForChild("PlanetBuilder"))
local MutationCatalog do
	-- if the MutationCatalog ModuleScript is missing, the game still works (just without mutations)
	local module = ReplicatedStorage:WaitForChild("MutationCatalog", 5)
	if module then
		MutationCatalog = require(module)
	else
		warn("[PlantingServer] ReplicatedStorage.MutationCatalog is missing, so there are no mutations. Create it (ModuleScript).")
		MutationCatalog = {
			Get = function() return nil end,
			Parse = function() return {} end,
			Join = function() return "" end,
			Names = function() return "" end,
			RollAll = function() return {} end,
			CoinMult = function() return 1 end,
			SellMult = function() return 1 end,
		}
	end
end

-- Garden bases (the BaseService ModuleScript). If it isn't there, everyone can plant anywhere, like before.
local baseModule = script.Parent:WaitForChild("BaseService", 10)
local BaseService = baseModule and require(baseModule) or {
	HasBases = function()
		return false
	end,
}

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local PAD_TAG = "GardenPad"
local DISPLAY_SCALE = 0.2          -- planets in the garden are this fraction of their catalog size
local HOVER = 1.0                  -- studs a planet floats above the bed
local MAX_PLANT_DISTANCE = 40      -- how far from the bed you can plant
local MAX_PLANTS_PER_PLAYER = 100
local EDGE_MARGIN = 1              -- keep plants this far from the edge of a bed
local SPACING_PADDING = 0.5
local PLANT_COOLDOWN = 0.2
local MUTATION_EARLIEST = 0.25  -- a mutation lands somewhere between these two points of the growing time
local MUTATION_LATEST = 0.85

local STREAK_RANGE = 6            -- how close a ready planet has to be for the harvest streak to take it
local STREAK_MIN_GAP = 0.1        -- the server never harvests faster than this (seconds)

-- Chance for each planted seed to grow bigger.
--   Chance  chance of that tier on its own (0.05 = 5%, 0.001 = 0.1%)
--   Size    how many times bigger        Weight  how many times heavier (so it sells for more)
-- If there's no room for the big one where you plant, it grows the next size down instead.
local TIERS = {
	huge   = { Name = "HUGE",   Label = "Huge",   Chance = 0.05,  Size = 2, Weight = 2,  Color = Color3.fromRGB(255, 215, 90),
		Cheer = "WOW! It's a HUGE" },
	insane = { Name = "INSANE", Label = "Insane", Chance = 0.01,  Size = 4, Weight = 5,  Color = Color3.fromRGB(255, 130, 60),
		Cheer = "INCREDIBLE! It's an INSANELY BIG" },
	crazy  = { Name = "CRAZY",  Label = "Crazy",  Chance = 0.001, Size = 8, Weight = 15, Color = Color3.fromRGB(255, 80, 200),
		Cheer = "UNBELIEVABLE!!! It's an ABSOLUTELY CRAZY HUGE" },
}
local TIER_ORDER = { "crazy", "insane", "huge" } -- rarest first

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("PlanetRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "PlanetRemotes"
	remotes.Parent = ReplicatedStorage
end

-- the client reads these so its preview matches the server
remotes:SetAttribute("GardenScale", DISPLAY_SCALE)
remotes:SetAttribute("PlantHover", HOVER)
remotes:SetAttribute("PlantDistance", MAX_PLANT_DISTANCE)
remotes:SetAttribute("StreakRange", STREAK_RANGE)

local function getRemote(name)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end

local plantRemote = getRemote("PlantSeed")
local noticeRemote = getRemote("Notice")
local harvestNextRemote = getRemote("HarvestNext")       -- client -> server: harvest the nearest ready planet
local audioCueRemote = getRemote("AudioCue")           -- server -> client: small sound cues (AudioManager plays them)
local mutationRemote = getRemote("MutationGained")       -- server -> everyone: (planetModel, mutationId) so the effects play
local harvestedRemote = getRemote("PlantHarvested")      -- server -> client: (planetName, weight, tierName)

local function notice(player, text, kind)
	noticeRemote:FireClient(player, text, kind or "ok")
end

-- save right away after planting / harvesting, so stopping the game never loses your planets
local lastSave = {}
local function saveSoon(player)
	if lastSave[player] then
		return -- a save is already waiting
	end
	lastSave[player] = true
	task.delay(2, function()
		lastSave[player] = nil
		if player.Parent then
			local ok = GameData.Save(player)
			print(string.format("[PlantingServer] saved %s's garden (%s)", player.Name, ok and "ok" or "FAILED - is Studio API access on?"))
		end
	end)
end

---------------------------------------------------------------------
-- Size tiers
---------------------------------------------------------------------
local function rollTier()
	local roll = math.random()
	local total = 0
	for _, key in ipairs(TIER_ORDER) do
		total += TIERS[key].Chance
		if roll < total then
			return key
		end
	end
	return nil
end

local function lowerTier(key)
	local index = table.find(TIER_ORDER, key)
	return index and TIER_ORDER[index + 1] or nil -- nil after "huge" = normal size
end

-- reads a saved plant (older saves used Huge = true)
local function entryTier(entry)
	if entry.Tier and TIERS[entry.Tier] then
		return entry.Tier
	end
	if entry.Huge then
		return "huge"
	end
	return nil
end

---------------------------------------------------------------------
-- Planet sizes
---------------------------------------------------------------------
-- how wide a planet is in the garden (includes rings and moons), used for spacing
local function footprintRadius(planet, sizeMultiplier)
	local look = planet.Look
	local extent = 1
	for _, ring in ipairs(look.Rings or {}) do
		extent = math.max(extent, ring.Scale)
	end
	for _, moon in ipairs(look.Moons or {}) do
		extent = math.max(extent, moon.Distance * 2)
	end
	return look.Size * extent * DISPLAY_SCALE * (sizeMultiplier or 1) / 2
end

-- how far (at full catalog size) any part reaches above/below the planet's center
local function halfHeight(planet)
	local look = planet.Look
	local tilt = math.abs(math.sin(math.rad(look.Tilt or 0)))
	local h = look.Size / 2
	for _, ring in ipairs(look.Rings or {}) do
		h = math.max(h, ring.Scale * look.Size / 2 * tilt)
	end
	for _, moon in ipairs(look.Moons or {}) do
		h = math.max(h, moon.Distance * look.Size * tilt + moon.Size * look.Size / 2)
	end
	if look.Glow then
		h = math.max(h, look.Glow.Size * look.Size / 2)
	end
	return h
end

---------------------------------------------------------------------
-- Tools (what the hotbar shows)
---------------------------------------------------------------------
local function seedToolName(planet)
	return planet.Name .. " Seed"
end

local function findTool(player, name)
	local containers = {}
	if player:FindFirstChild("Backpack") then
		table.insert(containers, player.Backpack)
	end
	if player.Character then
		table.insert(containers, player.Character)
	end
	for _, container in ipairs(containers) do
		local tool = container:FindFirstChild(name)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end
	return nil
end

-- update the seed tool to match the saved count (removes it at 0)
local function refreshSeed(player, planetId)
	local data = GameData.Get(player)
	local planet = PlanetCatalog.Get(planetId)
	if not data or not planet then
		return
	end

	local count = data.Seeds[planetId] or 0
	local tool = findTool(player, seedToolName(planet))

	if count <= 0 then
		data.Seeds[planetId] = nil
		if tool then
			tool:Destroy()
		end
	elseif tool then
		tool:SetAttribute("Count", count)
	end
end

local function makePlanetTool(planet, weight, tierKey, mutId)
	local tier = tierKey and TIERS[tierKey]
	local displayName = tier and (tier.Label .. " " .. planet.Name) or planet.Name
	local mutationIds = MutationCatalog.Parse(mutId)
	if #mutationIds > 0 then
		displayName = MutationCatalog.Names(mutationIds) .. " " .. displayName
	end
	local tool = Instance.new("Tool")
	tool.Name = displayName
	tool.ToolTip = string.format("%s (%.2f kg)", displayName, weight)
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("Kind", "Planet")
	tool:SetAttribute("PlanetId", planet.Id)
	tool:SetAttribute("Rarity", planet.Rarity)
	tool:SetAttribute("Weight", weight)
	if tier then
		tool:SetAttribute("SizeTier", tierKey)
	end
	if #mutationIds > 0 then
		tool:SetAttribute("Mutations", MutationCatalog.Join(mutationIds))
	end
	return tool
end

---------------------------------------------------------------------
-- Plants in the world
---------------------------------------------------------------------
local plantsFolder = Instance.new("Folder")
plantsFolder.Name = "PlantedPlanets"
plantsFolder.Parent = workspace

local plants = {}      -- every plant currently in the world
local spawnedFor = {}  -- player -> true once their saved plants are spawned

local claimBaseForPlayer -- defined further down

local function formatTime(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function isReady(plant)
	return os.time() - plant.Entry.T >= plant.Planet.GrowTime
end

local function placeModel(plant, progress)
	local scale = DISPLAY_SCALE * plant.SizeMultiplier * (0.3 + 0.7 * progress)
	pcall(function()
		plant.Model:ScaleTo(scale)
	end)
	local half = plant.HalfHeight * scale
	plant.Model:PivotTo(CFrame.new(plant.Ground + Vector3.new(0, HOVER + half, 0)))
	plant.Gui.StudsOffsetWorldSpace = Vector3.new(0, half + 2, 0)
	if plant.TitleGui then
		plant.TitleGui.StudsOffsetWorldSpace = Vector3.new(0, half + 2, 0)
	end
end

-- (re)builds the stack of glowing titles above a plant, one line per mutation
local function buildTitle(plant)
	local body = plant.Model.PrimaryPart
	if plant.TitleGui then
		plant.TitleGui:Destroy()
		plant.TitleGui = nil
	end
	if #plant.Mutations == 0 then
		return
	end

	local lineHeight = 36
	local extra = #plant.Mutations > 1 and 26 or 0 -- the "TOTAL x4" line
	local title = Instance.new("BillboardGui")
	title.Name = "MutationTitle"
	title.Size = UDim2.fromOffset(320, 26 + #plant.Mutations * lineHeight + extra)
	title.SizeOffset = Vector2.new(0, 0.5) -- grows UP from just above the name
	title.AlwaysOnTop = false
	title.MaxDistance = 120 + plant.BodyRadius * 2
	title.LightInfluence = 0
	title.Adornee = body
	title.Parent = body

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 1, -26) -- leaves room for the name underneath
	holder.Parent = title
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = holder

	-- newest on top
	for index = #plant.Mutations, 1, -1 do
		local mutation = MutationCatalog.Get(plant.Mutations[index])
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.LayoutOrder = #plant.Mutations - index
		label.Size = UDim2.new(1, 0, 0, lineHeight)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = string.upper(mutation.Name) .. "!"
		label.Parent = holder

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(20, 8, 30)
		stroke.Parent = label

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, mutation.Color),
			ColorSequenceKeypoint.new(0.5, mutation.Color2),
			ColorSequenceKeypoint.new(1, mutation.Color),
		})
		gradient.Parent = label
	end

	if #plant.Mutations > 1 then
		local totalLabel = Instance.new("TextLabel")
		totalLabel.BackgroundTransparency = 1
		totalLabel.LayoutOrder = 100
		totalLabel.Size = UDim2.new(1, 0, 0, extra)
		totalLabel.Font = Enum.Font.FredokaOne
		totalLabel.TextScaled = true
		totalLabel.TextColor3 = Color3.fromRGB(255, 235, 120)
		totalLabel.Text = string.format("x%s COINS", tostring(MutationCatalog.CoinMult(plant.Mutations)))
		totalLabel.Parent = holder
		local totalStroke = Instance.new("UIStroke")
		totalStroke.Thickness = 2
		totalStroke.Color = Color3.fromRGB(20, 8, 30)
		totalStroke.Parent = totalLabel
	end

	plant.TitleGui = title
end

-- adds one mutation to a plant (they STACK): a glowing title line, a bigger boost to its coins, and effects for everyone
local function applyMutation(plant, mutId, silent)
	local mutation = MutationCatalog.Get(mutId)
	if not mutation or table.find(plant.Mutations, mutId) then
		return
	end
	table.insert(plant.Mutations, mutId)
	plant.MutationKey = MutationCatalog.Join(plant.Mutations)
	plant.DisplayName = MutationCatalog.Names(plant.Mutations) .. " " .. plant.BaseName
	plant.Prompt.ObjectText = plant.DisplayName

	local model = plant.Model
	local coinMult = MutationCatalog.CoinMult(plant.Mutations)
	model:SetAttribute("Mutations", plant.MutationKey)
	model:SetAttribute("MutationMult", coinMult)

	buildTitle(plant)
	plant.Stage = -1 -- put the title in the right place on the next update

	if not silent then
		mutationRemote:FireAllClients(model, mutId)
		notice(plant.Owner, string.format("%s! Your %s now makes x%s coins and sells for x%s!",
			mutation.Name, plant.Planet.Name, tostring(coinMult), tostring(MutationCatalog.SellMult(plant.Mutations))), "ok")
	end
end

local function updatePlant(plant)
	local planet = plant.Planet
	local elapsed = os.time() - plant.Entry.T
	local progress = math.clamp(elapsed / planet.GrowTime, 0, 1)

	local entry = plant.Entry
	if entry.Muts then
		for _, m in ipairs(entry.Muts) do
			if elapsed >= (m.At or 0) and not table.find(plant.Mutations, m.Id) then
				-- if it should have happened a while ago (you were away) skip the show
				applyMutation(plant, m.Id, elapsed - (m.At or 0) > 10)
			end
		end
	end

	local stage = math.floor(progress * 50)
	if stage ~= plant.Stage then
		plant.Stage = stage
		placeModel(plant, progress)
	end

	local ready = progress >= 1
	if ready and not plant.ReadyCued then
		plant.ReadyCued = true
		-- only chime if it finished while you were here (not planets that finished while you were away)
		if elapsed - planet.GrowTime < 6 then
			audioCueRemote:FireClient(plant.Owner, "grow_ready")
		end
	end
	if ready then
		plant.Text.Text = plant.DisplayName .. '\n<font color="#78ff96">READY!</font>'
	else
		plant.Text.Text = string.format(
			'%s\n<font color="#ffe16e">%s</font>',
			plant.DisplayName,
			formatTime(math.ceil(planet.GrowTime - elapsed))
		)
	end
	plant.Prompt.Enabled = ready
end

local function removePlant(plant)
	local index = table.find(plants, plant)
	if index then
		table.remove(plants, index)
	end
	if plant.Model then
		plant.Model:Destroy()
	end
end

-- quiet = true during a harvest streak (no pop-up message for every single planet)
local function harvest(plant, player, quiet)
	if plant.Harvested then
		return
	end
	if player ~= plant.Owner then
		notice(player, "That's not your planet!", "error")
		return
	end
	local data = GameData.Get(player)
	if not data then
		return
	end
	local planet = plant.Planet
	if not isReady(plant) then
		return
	end

	plant.Harvested = true

	local tierKey = entryTier(plant.Entry)
	local tier = tierKey and TIERS[tierKey]
	local weight = PlanetCatalog.RollWeight(planet)
	if tier then
		weight = math.floor(weight * tier.Weight * 100 + 0.5) / 100
	end

	local savedIndex = table.find(data.Plants, plant.Entry)
	if savedIndex then
		table.remove(data.Plants, savedIndex)
	end
	table.insert(data.Planets, { Id = planet.Id, Weight = weight, Tier = tierKey, Mut = plant.MutationKey })
	removePlant(plant)
	saveSoon(player)

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		makePlanetTool(planet, weight, tierKey, plant.MutationKey).Parent = backpack
	end

	harvestedRemote:FireClient(player, planet.Name, weight, tier and tier.Name or "")
	if not quiet then
		notice(player, string.format("Harvested a %s%.2f kg %s!", tier and (tier.Name .. " ") or "", weight, planet.Name), "ok")
	end
end

local function spawnPlant(player, entry)
	local planet = PlanetCatalog.Get(entry.Id)
	if not planet or type(entry.T) ~= "number" then
		return nil
	end

	-- older saves had a single Mut / MutAt: turn them into the new stackable list
	if entry.Mut and not entry.Muts then
		entry.Muts = { { Id = entry.Mut, At = entry.MutAt or 0 } }
	end
	entry.Mut, entry.MutAt = nil, nil

	local tierKey = entryTier(entry)
	local tier = tierKey and TIERS[tierKey]
	local sizeMultiplier = tier and tier.Size or 1
	local displayName = tier and (tier.Name .. " " .. planet.Name) or planet.Name
	local bodyRadius = (planet.Look.Size / 2) * DISPLAY_SCALE * sizeMultiplier

	local model = PlanetBuilder.Build(planet, plantsFolder)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Footprint", footprintRadius(planet, sizeMultiplier))
	model:SetAttribute("BodyRadius", bodyRadius)
	model:SetAttribute("SizeTier", tierKey)
	local body = model.PrimaryPart

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 46)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80 + bodyRadius * 2
	gui.LightInfluence = 0
	gui.Adornee = body
	gui.Parent = body

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 18
	text.TextColor3 = tier and tier.Color or Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	text.RichText = true
	text.Text = displayName
	text.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Harvest"
	prompt.ObjectText = displayName
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 8 + bodyRadius -- big planets can be harvested from a bit farther away
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = body

	local plant = {
		Owner = player,
		Entry = entry,
		Planet = planet,
		Model = model,
		Ground = Vector3.new(entry.X, entry.Y, entry.Z),
		HalfHeight = halfHeight(planet),
		Footprint = footprintRadius(planet, sizeMultiplier),
		BodyRadius = bodyRadius,
		SizeMultiplier = sizeMultiplier,
		DisplayName = displayName,
		BaseName = displayName,
		Mutations = {},
		Gui = gui,
		Text = text,
		Prompt = prompt,
		Stage = -1,
	}

	prompt.Triggered:Connect(function(who)
		harvest(plant, who, false)
	end)

	table.insert(plants, plant)
	updatePlant(plant)
	return plant
end

-- grow every plant (once a second)
task.spawn(function()
	while true do
		task.wait(1)
		for _, plant in ipairs(plants) do
			updatePlant(plant)
		end
	end
end)

---------------------------------------------------------------------
-- Harvest streak: the client asks, the server picks the nearest ready planet
---------------------------------------------------------------------
local lastStreak = {}

harvestNextRemote.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastStreak[player] and now - lastStreak[player] < STREAK_MIN_GAP then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local best, bestDistance = nil, math.huge
	for _, plant in ipairs(plants) do
		if plant.Owner == player and not plant.Harvested and isReady(plant) then
			local body = plant.Model.PrimaryPart
			if body then
				-- distance to the planet's surface, not its center, so big ones are easy to reach
				local distance = (body.Position - root.Position).Magnitude - plant.BodyRadius
				if distance <= STREAK_RANGE and distance < bestDistance then
					best, bestDistance = plant, distance
				end
			end
		end
	end

	if best then
		lastStreak[player] = now
		harvest(best, player, true)
	end
end)

---------------------------------------------------------------------
-- Planting
---------------------------------------------------------------------
-- returns the point on top of the bed under `position`, or nil if it isn't on a bed
local function findGround(position)
	for _, pad in ipairs(CollectionService:GetTagged(PAD_TAG)) do
		if pad:IsA("BasePart") then
			local localPos = pad.CFrame:PointToObjectSpace(position)
			local half = pad.Size / 2
			if math.abs(localPos.X) <= half.X - EDGE_MARGIN
				and math.abs(localPos.Z) <= half.Z - EDGE_MARGIN
				and math.abs(localPos.Y - half.Y) <= 4
			then
				return pad.CFrame:PointToWorldSpace(Vector3.new(localPos.X, half.Y, localPos.Z)), pad
			end
		end
	end
	return nil
end

-- does a planet with this footprint fit at `ground` without touching another planet?
local function fits(ground, radius)
	for _, plant in ipairs(plants) do
		local dx = plant.Ground.X - ground.X
		local dz = plant.Ground.Z - ground.Z
		if math.sqrt(dx * dx + dz * dz) < radius + plant.Footprint + SPACING_PADDING then
			return false
		end
	end
	return true
end

local lastPlant = {}

-- gives a player an empty base and brings their saved planets onto it (used by planting and by walking up to a base)
function claimBaseForPlayer(player, data, base)
	local previous = data.Base -- where this player's base was last time (saved)
	if not BaseService.Claim(player, base) then
		return false
	end
	-- if your saved planets were on another base, slide them over to this one
	if previous and #data.Plants > 0 then
		local dx = base.Center.X - previous.X
		local dz = base.Center.Z - previous.Z
		local dy = base.Top - (previous.Y or base.Top)
		if math.abs(dx) > 1 or math.abs(dz) > 1 then
			for _, saved in ipairs(data.Plants) do
				saved.X += dx
				saved.Z += dz
				saved.Y += dy
			end
		end
	end
	-- saved planets that were waiting for a base appear now
	for _, saved in ipairs(data.Plants) do
		spawnPlant(player, saved)
	end
	notice(player, "You claimed this base!", "ok")
	audioCueRemote:FireClient(player, "claim")
	return true
end

-- walking up to an empty base claims it too, if you have saved planets waiting
BaseService.WalkClaim = function(player, base)
	local data = GameData.Get(player)
	if not data or #data.Plants == 0 or not spawnedFor[player] then
		return false
	end
	return claimBaseForPlayer(player, data, base)
end

plantRemote.OnServerEvent:Connect(function(player, planetId, position)
	if typeof(planetId) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end
	if position ~= position then -- NaN
		return
	end
	local planet = PlanetCatalog.Get(planetId)
	if not planet then
		return
	end

	local now = os.clock()
	if lastPlant[player] and now - lastPlant[player] < PLANT_COOLDOWN then
		return
	end
	lastPlant[player] = now

	local data = GameData.Get(player)
	if not data then
		return
	end

	if (data.Seeds[planetId] or 0) <= 0 then
		notice(player, "You don't have a " .. planet.Name .. " Seed.", "error")
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - position).Magnitude > MAX_PLANT_DISTANCE then
		notice(player, "Too far away to plant there.", "error")
		return
	end

	local ground, pad = findGround(position)
	if not ground then
		notice(player, "You can only plant in the garden beds.", "error")
		return
	end

	-- bases: you can only plant on your own base, and planting on an empty base claims it
	local baseToClaim = nil
	if BaseService.HasBases() then
		local base = BaseService.BaseForPad(pad)
		if base then
			if base.Owner and base.Owner ~= player then
				notice(player, base.Owner.DisplayName .. " owns this base. Plant on your own base.", "error")
				return
			end
			if not base.Owner then
				if BaseService.BaseOf(player) then
					notice(player, "You already have a base. Plant on your own base.", "error")
					return
				end
				baseToClaim = base
			end
		end
	end

	local owned = 0
	for _, plant in ipairs(plants) do
		if plant.Owner == player then
			owned += 1
		end
	end
	if owned >= MAX_PLANTS_PER_PLAYER then
		notice(player, "You can only have " .. MAX_PLANTS_PER_PLAYER .. " planets growing at once.", "error")
		return
	end

	if not fits(ground, footprintRadius(planet)) then
		notice(player, "Too close to another planet.", "error")
		return
	end

	-- small chance to grow bigger; if the big one doesn't fit here, try the next size down
	local tierKey = rollTier()
	while tierKey and not fits(ground, footprintRadius(planet, TIERS[tierKey].Size)) do
		tierKey = lowerTier(tierKey)
	end

	-- planting on an empty base claims it
	if baseToClaim then
		claimBaseForPlayer(player, data, baseToClaim)
	end

	-- plant it
	data.Seeds[planetId] -= 1
	refreshSeed(player, planetId)

	local entry = { Id = planetId, X = ground.X, Y = ground.Y, Z = ground.Z, T = os.time(), Tier = tierKey }
	-- every mutation rolls on its own (a planet can get several and they stack). Each one is decided now and
	-- lands part of the way through growing, so you can watch it happen.
	local rolled = MutationCatalog.RollAll()
	if #rolled > 0 then
		entry.Muts = {}
		for _, id in ipairs(rolled) do
			table.insert(entry.Muts, {
				Id = id,
				At = math.floor(planet.GrowTime * (MUTATION_EARLIEST + math.random() * (MUTATION_LATEST - MUTATION_EARLIEST))),
			})
		end
	end
	table.insert(data.Plants, entry)
	spawnPlant(player, entry)
	audioCueRemote:FireClient(player, "plant", tierKey)
	saveSoon(player)

	local tier = tierKey and TIERS[tierKey]
	if tier then
		notice(player, tier.Cheer .. " " .. planet.Name .. "! Ready in " .. formatTime(planet.GrowTime) .. ".", "ok")
	else
		notice(player, "Planted a " .. planet.Name .. "! Ready in " .. formatTime(planet.GrowTime) .. ".", "ok")
	end
end)

---------------------------------------------------------------------
-- Players joining / leaving
---------------------------------------------------------------------
local function loadPlants(player)
	local data = GameData.WaitFor(player)
	if not data or spawnedFor[player] then
		return
	end
	spawnedFor[player] = true

	if BaseService.HasBases() then
		-- your planets only appear on your own base. If you don't have one yet, they wait (saved)
		-- and appear when you claim a base by planting.
		BaseService.WaitForSetup(player)
		local base = BaseService.BaseOf(player)
		print(string.format("[PlantingServer] %s joined with %d saved planets, base: %s",
			player.Name, #data.Plants, base and "got it back" or "none (plant on a base to claim it)"))
		if not base then
			return
		end
		for _, entry in ipairs(data.Plants) do
			if BaseService.BaseAtPosition(Vector3.new(entry.X, entry.Y, entry.Z)) == base then
				spawnPlant(player, entry)
			end
		end
	else
		for _, entry in ipairs(data.Plants) do
			spawnPlant(player, entry)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPlants, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadPlants, player)
end

-- when you leave, your planets leave the world (they stay in your save and keep growing)
Players.PlayerRemoving:Connect(function(player)
	for i = #plants, 1, -1 do
		local plant = plants[i]
		if plant.Owner == player then
			plant.Model:Destroy()
			table.remove(plants, i)
		end
	end
	spawnedFor[player] = nil
	lastPlant[player] = nil
	lastStreak[player] = nil
	lastSave[player] = nil
end)

-- admin panel: AdminServer asks us to grow / harvest / mutate the admin's own planets
do
	local ServerStorage = game:GetService("ServerStorage")
	local adminBridge = Instance.new("BindableEvent")
	adminBridge.Name = "AdminBridge_Garden"
	adminBridge.Parent = ServerStorage

	local function mine(player)
		local list = {}
		for _, plant in ipairs(plants) do
			if plant.Owner == player and not plant.Harvested then
				table.insert(list, plant)
			end
		end
		return list
	end

	adminBridge.Event:Connect(function(player, action, mutId)
		local list = mine(player)
		if #list == 0 then
			notice(player, "You have no planets growing.", "error")
			return
		end

		if action == "grow" or action == "harvest" then
			for _, plant in ipairs(list) do
				plant.Entry.T = os.time() - plant.Planet.GrowTime - 1
				updatePlant(plant)
			end
			if action == "harvest" then
				for _, plant in ipairs(list) do
					harvest(plant, player, true)
				end
				notice(player, "Harvested " .. #list .. " planets!", "ok")
			else
				notice(player, #list .. " planets fully grown!", "ok")
			end

		elseif action == "mutate" then
			for _, plant in ipairs(list) do
				local entry = plant.Entry
				removePlant(plant)
				if mutId then
					entry.Muts = entry.Muts or {}
					local has = false
					for _, m in ipairs(entry.Muts) do
						if m.Id == mutId then
							has = true
						end
					end
					if not has then
						table.insert(entry.Muts, { Id = mutId, At = 0 })
					end
				else
					entry.Muts = nil
				end
				spawnPlant(player, entry)
			end
			local mutation = MutationCatalog.Get(mutId)
			notice(player, mutation and (mutation.Name .. " added to " .. #list .. " planets (they stack)!") or "Mutations removed.", "ok")
		end
	end)
end

-- sprinklers (SprinklerServer) ask us about a player's planets, make them grow faster and give Stardust
do
	local ServerStorage = game:GetService("ServerStorage")
	local gardenApi = Instance.new("BindableFunction")
	gardenApi.Name = "GardenAPI"
	gardenApi.Parent = ServerStorage

	local function plantFor(model)
		for _, plant in ipairs(plants) do
			if plant.Model == model and not plant.Harvested then
				return plant
			end
		end
		return nil
	end

	gardenApi.OnInvoke = function(action, a, b)
		if action == "plants" then
			-- a = player: every planet they have growing
			local list = {}
			for _, plant in ipairs(plants) do
				if plant.Owner == a and not plant.Harvested and plant.Model and plant.Model.Parent then
					table.insert(list, {
						Model = plant.Model,
						Group = plant.Planet.Group,
						Ready = isReady(plant),
						HasStardust = table.find(plant.Mutations, "stardust") ~= nil,
					})
				end
			end
			return list

		elseif action == "boost" then
			-- a = planet model, b = extra seconds of growing
			local plant = plantFor(a)
			if plant and not isReady(plant) and type(b) == "number" and b > 0 then
				plant.Entry.T -= b
				updatePlant(plant)
				return true
			end
			return false

		elseif action == "mutate" then
			-- a = planet model, b = mutation id: saved, so it stays after harvesting / rejoining
			local plant = plantFor(a)
			if not plant or not MutationCatalog.Get(b) or table.find(plant.Mutations, b) then
				return false
			end
			plant.Entry.Muts = plant.Entry.Muts or {}
			table.insert(plant.Entry.Muts, { Id = b, At = math.max(0, os.time() - plant.Entry.T) })
			applyMutation(plant, b, false)
			saveSoon(plant.Owner)
			return true
		end
		return nil
	end
end

print("[PlantingServer] Ready")
