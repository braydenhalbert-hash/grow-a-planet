-- GardenServer: planting, growing, and harvesting planets on the garden pads
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local PlanetConfig = require(ReplicatedStorage:WaitForChild("PlanetConfig"))
local PlanetVisuals = require(ReplicatedStorage:WaitForChild("PlanetVisuals"))
local PlanetVfx = require(script.Parent:WaitForChild("PlanetVfx"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

PlanetVfx.Init()

local GROWN_HOVER = 4.5
local GROW_STEPS = 20

local padStates = {} -- [pad] = array of plant states (a pad can grow many planets at once)
local growingPlanets = {} -- [state] = { model, ball, ring, planet, startClock, baseCF, spin }
local grownPlanets = {} -- [model] = { state, angle }
local MAX_PLANTS_PER_PAD = 200
local setupPad -- forward declaration (plantSeed can register a pad lazily)

local function makeBillboard(ball)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PadStatus"
	billboard.Size = UDim2.fromOffset(200, 50)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = billboard
	billboard.Parent = ball
	return billboard, label
end

local function fxSparkles(position, color, count, speed)
	local holder = Instance.new("Part")
	holder.Name = "FxSparkles"
	holder.Anchored = true
	holder.CanCollide = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.5, 0.5, 0.5)
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Parent = holder
	emitter:Emit(count)
	holder.Parent = workspace
	Debris:AddItem(holder, 2)
end

local function playFx(position, soundId, volume, speed)
	local holder = Instance.new("Part")
	holder.Name = "FxSound"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.5, 0.5, 0.5)
	holder.CFrame = CFrame.new(position)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMaxDistance = 140
	sound.Parent = holder
	holder.Parent = workspace
	sound:Play()
	Debris:AddItem(holder, 4)
end

local function fxRingFlash(position, color, maxRadius)
	local flash = Instance.new("Part")
	flash.Name = "FxRingFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Transparency = 0.3
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Size = Vector3.new(1, 1, 1)
	flash.CFrame = CFrame.new(position)
	flash.Parent = workspace
	task.spawn(function()
		local t0 = os.clock()
		while flash.Parent do
			local a = (os.clock() - t0) / 0.45
			if a >= 1 then
				break
			end
			local eased = 1 - (1 - a) * (1 - a)
			local s = 1 + eased * (maxRadius or 8)
			flash.Size = Vector3.new(s, s, s)
			flash.Transparency = 0.3 + eased * 0.7
			task.wait()
		end
		flash:Destroy()
	end)
end

-- bigger planets sound deeper
local function planetPitch(planet)
	return math.clamp(1.35 - planet.Diameter * 0.06, 0.6, 1.2)
end

local POP_DURATION = 0.9

local function popOff(model, color, tilt, pitch)
	if not model or not model.Parent then
		return
	end
	grownPlanets[model] = nil

	task.spawn(function()
		local ball = model:FindFirstChild("Ball")
		if not ball then
			model:Destroy()
			return
		end
		local ring = model:FindFirstChild("Ring")

		local baseTransparency = { [ball] = ball.Transparency }
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				baseTransparency[part] = part.Transparency
			end
		end

		local start = ball.CFrame
		local spin = math.random() * math.pi * 2
		local t0 = os.clock()
		local last = t0
		fxSparkles(start.Position, color, 30, 14)
		fxRingFlash(start.Position, color, 6)
		PlanetVfx.HarvestBurst(start.Position, ball.Size.X)
		playFx(start.Position, "rbxasset://sounds/bass.mp3", 0.6, (pitch or 1) * 0.7)

		while ball.Parent do
			local now = os.clock()
			local alpha = (now - t0) / POP_DURATION
			if alpha >= 1 then
				break
			end
			spin += (now - last) * (8 + alpha * 24)
			last = now
			ball.CFrame = start * CFrame.new(0, alpha * alpha * 13, 0) * CFrame.Angles(0, spin, 0)
			if ring then
				ring.CFrame = ball.CFrame * (tilt or CFrame.Angles(0, 0, math.rad(20)))
			end
			local fade = math.clamp((alpha - 0.55) / 0.45, 0, 1)
			if fade > 0 then
				for part, baseT in pairs(baseTransparency) do
					part.Transparency = math.min(baseT + fade, 1)
				end
			end
			task.wait()
		end
		model:Destroy()
	end)
end

local function removePlant(state)
	local states = state.pad and padStates[state.pad]
	if states then
		local idx = table.find(states, state)
		if idx then
			table.remove(states, idx)
		end
	end
	growingPlanets[state] = nil
	if state.visuals then
		grownPlanets[state.visuals] = nil
		state.visuals:Destroy()
		state.visuals = nil
	end
end

local function buildPlanetModel(pad, planet)
	local rarity = PlanetConfig.GetRarity(planet)
	local model = Instance.new("Model")
	model.Name = planet.Id .. "Planet"

	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.5, 0.5, 0.5)
	ball.Color = Color3.fromRGB(planet.Color[1], planet.Color[2], planet.Color[3])
	ball.Anchored = true
	ball.CanCollide = false
	ball.Parent = model

	if planet.Id == "Saturn" or planet.Id == "Uranus" then
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.4, planet.Diameter * 1.9, planet.Diameter * 1.9)
		ring.Color = planet.Id == "Saturn" and Color3.fromRGB(216, 190, 130) or Color3.fromRGB(190, 245, 250)
		ring.Material = Enum.Material.SmoothPlastic
		ring.Transparency = 0.35
		ring.Anchored = true
		ring.CanCollide = false
		ring.Parent = model
	end

	PlanetVisuals.StyleGrowing(ball, model:FindFirstChild("Ring"), planet, rarity)
	PlanetVfx.AttachAura(ball, planet, rarity)

	model.Parent = pad.Parent
	return model, ball
end

local function harvest(player, state)
	if not state.grown or not state.visuals or state.owner ~= player then
		return
	end
	local planet = PlanetConfig.Get(state.planetId)
	if not planet then
		return
	end
	local rarity = PlanetConfig.GetRarity(planet)
	local model = state.visuals
	state.visuals = nil
	removePlant(state)
	if state.billboard then
		state.billboard.Enabled = false
	end
	if model then
		popOff(model, Color3.fromRGB(rarity.Color[1], rarity.Color[2], rarity.Color[3]), state.ringTilt, planetPitch(planet))
	end
	PlayerData.AddPlanet(player, planet.Id, 1)
	local harvestBonus = math.max(1, math.floor(planet.SellValue * 0.02))
	PlayerData.AddCoins(player, harvestBonus)
	print(("[GardenServer] %s harvested a %s %s (+%d coins)"):format(player.Name, planet.Rarity, planet.Name, harvestBonus))
end

local function completeGrowth(state)
	state.grown = true
	local planet = state.growing.planet
	local model = state.visuals
	state.label.TextColor3 = Color3.new(1, 1, 1)
	state.label.Text = planet.Name .. " — READY! Press E to harvest"
	state.ringTilt = state.growing.ringTilt
	state.basePos = state.growing.baseCF * CFrame.new(0, GROWN_HOVER + planet.Diameter / 2, 0)
	grownPlanets[model] = { state = state, angle = math.random() * math.pi * 2 }
	local ball = state.growing.ball
	ball.Size = Vector3.new(planet.Diameter, planet.Diameter, planet.Diameter)
	local ring = model:FindFirstChild("Ring")
	if ring then
		ring.Size = Vector3.new(0.4, ball.Size.X * 1.9, ball.Size.Z * 1.9)
	end
	local rarity = PlanetConfig.GetRarity(planet)
	PlanetVisuals.Apply(ball, planet, rarity)
	PlanetVfx.AttachAura(ball, planet, rarity)
	PlanetVfx.ReadyBurst(ball.Position, planet)
	fxSparkles(ball.Position, Color3.fromRGB(rarity.Color[1], rarity.Color[2], rarity.Color[3]), 24 + rarity.Weight * 8, 12)
	fxRingFlash(ball.Position, Color3.fromRGB(rarity.Color[1], rarity.Color[2], rarity.Color[3]), 5 + planet.Diameter * 1.2)
	playFx(ball.Position, "rbxasset://sounds/electronicpingshort.wav", 0.6, planetPitch(planet) * 1.25)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HarvestPrompt"
	prompt.ActionText = "Harvest"
	prompt.ObjectText = planet.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = ball
	prompt.Triggered:Connect(function(player)
		harvest(player, state)
	end)

	print(("[GardenServer] %s's %s is ready to harvest"):format(state.owner.Name, planet.Name))
	growingPlanets[state] = nil
	state.growing = nil
end

local function growPlanet(player, pad, planet, state, spotCF)
	local model, ball = buildPlanetModel(pad, planet)
	state.visuals = model
	local billboard, label = makeBillboard(ball)
	state.billboard = billboard
	state.label = label
	billboard.Enabled = true

	local rarity = PlanetConfig.GetRarity(planet)
	label.TextColor3 = Color3.fromRGB(rarity.Color[1], rarity.Color[2], rarity.Color[3])
	label.Text = "Planting " .. planet.Name .. "..."

	state.growing = {
		model = model,
		ball = ball,
		ring = model:FindFirstChild("Ring"),
		planet = planet,
		startClock = os.clock(),
		baseCF = spotCF * CFrame.new(0, 1.2, 0),
		spin = math.random() * math.pi * 2,
		ringTilt = planet.Id == "Saturn" and CFrame.Angles(0, 0, math.rad(20)) or CFrame.Angles(0, 0, math.rad(85)),
		rarity = rarity,
		auraSize = 0.5,
		auraStep = math.max(planet.Diameter / 6, 0.25),
	}
	growingPlanets[state] = state.growing
end

local function findSpot(pad, states, planet, hitPos)
	local size = pad.Size
	local halfX = math.max(size.X / 2 - 2, 1)
	local halfZ = math.max(size.Z / 2 - 2, 1)
	local cf = pad.CFrame

	local function clampToPad(worldPos)
		local rel = cf:PointToObjectSpace(worldPos)
		rel = Vector3.new(
			math.clamp(rel.X, -halfX, halfX),
			size.Y / 2,
			math.clamp(rel.Z, -halfZ, halfZ)
		)
		return cf * CFrame.new(rel)
	end

	local function isFree(spot)
		for _, st in states do
			local stPlanet = PlanetConfig.Get(st.planetId)
			local minDist = stPlanet and (stPlanet.Diameter / 2 + planet.Diameter / 2 + 1.5) or 4
			if (spot.Position - st.spotPos).Magnitude < minDist then
				return false
			end
		end
		return true
	end

	local candidates = {}
	local base = hitPos and clampToPad(hitPos) or nil
	if base then
		table.insert(candidates, base)
	end
	for _ = 1, 12 do
		if base then
			local jitter = base * CFrame.new((math.random() * 2 - 1) * 4, 0, (math.random() * 2 - 1) * 4)
			table.insert(candidates, clampToPad(jitter.Position))
		else
			local rel = Vector3.new((math.random() * 2 - 1) * halfX, size.Y / 2, (math.random() * 2 - 1) * halfZ)
			table.insert(candidates, cf * CFrame.new(rel))
		end
	end
	for _, spot in candidates do
		if isFree(spot) then
			return spot
		end
	end
	return candidates[1]
end

local lastPlantAt = {} -- [player] = os.clock() of last plant (debounces double triggers)

local function plantSeed(player, pad, hitPos)
	local now = os.clock()
	if lastPlantAt[player] and now - lastPlantAt[player] < 0.75 then
		return
	end
	if not padStates[pad] then
		setupPad(pad)
	end
	local states = padStates[pad]
	if not states or #states >= MAX_PLANTS_PER_PAD then
		return
	end

	local seeds = PlayerData.GetSeedCounts(player)
	local chosenId = nil
	for _, planet in ipairs(PlanetConfig.Planets) do
		if (seeds[planet.Id] or 0) > 0 then
			chosenId = planet.Id
			break
		end
	end
	if not chosenId then
		return
	end

	if not PlayerData.RemoveSeed(player, chosenId) then
		return
	end

	local planet = PlanetConfig.Get(chosenId)
	local spotCF = findSpot(pad, states, planet, hitPos)
	local state = {
		pad = pad,
		owner = player,
		planetId = chosenId,
		grown = false,
		spotPos = spotCF.Position,
	}
	table.insert(states, state)
	lastPlantAt[player] = now
	fxSparkles(spotCF.Position + Vector3.new(0, 1.5, 0), Color3.fromRGB(120, 235, 120), 18, 8)
	PlanetVfx.PlantBurst(spotCF.Position + Vector3.new(0, 1, 0))
	playFx(spotCF.Position + Vector3.new(0, 1.5, 0), "rbxasset://sounds/snap.mp3", 0.5, 0.85)

	task.spawn(growPlanet, player, pad, planet, state, spotCF)
end

local PAD_TAG = "GardenPad"
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local plantAtPad = Remotes:FindFirstChild("PlantAtPad")
if not plantAtPad then
	plantAtPad = Instance.new("RemoteEvent")
	plantAtPad.Name = "PlantAtPad"
	plantAtPad.Parent = Remotes
end

plantAtPad.OnServerEvent:Connect(function(player, pad, hitPos)
	if typeof(pad) ~= "Instance" or not pad:IsA("BasePart") or not CollectionService:HasTag(pad, PAD_TAG) then
		return
	end
	if typeof(hitPos) ~= "Vector3" then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - pad.Position).Magnitude > 90 then
		return
	end
	plantSeed(player, pad, hitPos)
end)

function setupPad(pad)
	if padStates[pad] then
		return
	end
	padStates[pad] = {}
end

for _, pad in CollectionService:GetTagged("GardenPad") do
	setupPad(pad)
end
CollectionService:GetInstanceAddedSignal("GardenPad"):Connect(setupPad)

-- sweep: catch pads tagged before/while this script was still loading
task.spawn(function()
	while true do
		for _, pad in CollectionService:GetTagged("GardenPad") do
			if not padStates[pad] then
				setupPad(pad)
			end
		end
		task.wait(1)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, states in pairs(padStates) do
		for i = #states, 1, -1 do
			if states[i].owner == player then
				removePlant(states[i])
			end
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for state, growing in pairs(growingPlanets) do
		if state.visuals ~= growing.model then
			growingPlanets[state] = nil
			continue
		end
		local planet = growing.planet
		local alpha = math.clamp((now - growing.startClock) / planet.GrowTime, 0, 1)
		local ball = growing.ball
		if not ball.Parent then
			growingPlanets[state] = nil
			continue
		end
		if alpha >= 1 then
			completeGrowth(state)
			continue
		end
		local eased = alpha * alpha * (3 - 2 * alpha)
		local size = Vector3.new(0.5, 0.5, 0.5):Lerp(
			Vector3.new(planet.Diameter, planet.Diameter, planet.Diameter),
			eased
		)
		growing.spin += dt * 1.2
		local bob = math.sin(now * 2.2) * 0.25
		ball.Size = size
		-- re-attach the aura at size milestones so the VFX grows with the planet
		if math.abs(size.X - growing.auraSize) >= (growing.auraStep or 0.5) then
			growing.auraSize = size.X
			PlanetVfx.AttachAura(ball, planet, growing.rarity)
		end
		ball.CFrame = growing.baseCF
			* CFrame.new(0, size.Y / 2 - 0.25 + bob, 0)
			* CFrame.Angles(0, growing.spin, 0)
		local ring = growing.ring
		if ring then
			ring.CFrame = ball.CFrame * growing.ringTilt
			ring.Size = Vector3.new(0.4, size.X * 1.9, size.Z * 1.9)
		end
		state.label.Text = ("%s %d%%"):format(planet.Name, math.floor(alpha * 100))
		if state.billboard then
			state.billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 2.5, 0)
		end
	end

	for model, info in pairs(grownPlanets) do
		local state = info.state
		if not state or not state.grown or not state.visuals then
			grownPlanets[model] = nil
			continue
		end
		local ball = model:FindFirstChild("Ball")
		if not ball then
			grownPlanets[model] = nil
			continue
		end
		info.angle += dt * 0.8
		local planet = PlanetConfig.Get(state.planetId)
		local radius = planet and (1.5 + planet.Diameter * 0.08) or 1.5
		local offset = CFrame.new(
			math.cos(info.angle) * radius,
			math.sin(now * 1.5) * 0.4,
			math.sin(info.angle) * radius
		) * CFrame.Angles(0, info.angle * 2, 0)
		ball.CFrame = state.basePos * offset
		local ring = model:FindFirstChild("Ring")
		if ring then
			ring.CFrame = ball.CFrame * (state.ringTilt or CFrame.Angles(0, 0, math.rad(20)))
		end
		if state.billboard then
			state.billboard.StudsOffsetWorldSpace = Vector3.new(0, ball.Size.Y / 2 + 2.5, 0)
		end
		local glow = ball:FindFirstChild("Glow")
		if glow then
			local rarity = planet and PlanetConfig.GetRarity(planet)
			local base = (rarity and rarity.Weight >= 5) and 2 or 1
			glow.Brightness = base + math.sin(now * 2.4) * 0.6
		end
	end
end)

print("[GardenServer] Ready - waiting for plantings")