--[[
	MutationVFX  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts   (name it exactly: MutationVFX)

	All the visuals for planet mutations:
	  * METEOR SHOWER: meteors with fiery trails keep falling out of the sky around the planet and
	    crash into the ground in little bursts.
	  * Frozen: drifting snow sparkles and an icy shimmer.
	  * Nebula: swirling pink and purple star dust.
	  * Solar Flare: fire and embers licking off the planet.
	  * Supernova: a blazing white-gold glow with pulsing shockwaves.
	  * When a planet GETS a mutation there is a big custom burst (shockwave, flash, sparks, and a
	    meteor barrage for Meteor Shower).
	  * The glowing title above the planet shimmers.

	Needs: MutationCatalog (ReplicatedStorage), PlantingServer (it tells us when a mutation lands).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))
-- sounds are optional: if the Audio module isn't set up, the meteors are just silent
local okAudio, Audio = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Audio", 5))
end)
local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local gainedRemote = remotes:WaitForChild("MutationGained")
local plantsFolder = workspace:WaitForChild("PlantedPlanets")

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local SHOW_DISTANCE = 220        -- effects only run for planets this close to you
local METEOR_EVERY = 0.45        -- seconds between meteors for each Meteor Shower planet
local MAX_METEORS = 36           -- most meteors falling at once (keeps it smooth)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local fxFolder = workspace:FindFirstChild("MutationFX")
if not fxFolder then
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "MutationFX"
	fxFolder.Parent = workspace
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { fxFolder, plantsFolder }
local function refreshRayFilter()
	local list = { fxFolder, plantsFolder }
	local held = workspace:FindFirstChild("HeldPlanets")
	if held then
		table.insert(list, held)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function fxPart(position, size, color, shape, transparency)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Shape = shape or Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Transparency = transparency or 0
	part.Position = position
	part.Parent = fxFolder
	return part
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = props.Texture or SPARKLE
	e.Color = props.Color or ColorSequence.new(Color3.new(1, 1, 1))
	e.LightEmission = props.LightEmission or 1
	e.LightInfluence = 0
	e.Size = props.Size or NumberSequence.new(1)
	e.Transparency = props.Transparency or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = props.Lifetime or NumberRange.new(1, 2)
	e.Speed = props.Speed or NumberRange.new(2, 5)
	e.SpreadAngle = props.Spread or Vector2.new(180, 180)
	e.Rate = props.Rate or 20
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = props.RotSpeed or NumberRange.new(-60, 60)
	e.Acceleration = props.Acceleration or Vector3.zero
	e.Drag = props.Drag or 0
	e.EmissionDirection = props.Direction or Enum.NormalId.Top
	if props.Shape then
		e.Shape = props.Shape
		e.ShapeStyle = props.ShapeStyle or Enum.ParticleEmitterShapeStyle.Surface
	end
	e.Enabled = props.Enabled ~= false
	e.Parent = parent
	return e
end

local function seq(a, b)
	return ColorSequence.new(a, b)
end

---------------------------------------------------------------------
-- Meteors
---------------------------------------------------------------------
local meteors = {}

local function spawnMeteor(center, radius, mutation)
	if #meteors >= MAX_METEORS then
		return
	end
	local spread = math.max(radius * 2.4, 8)
	local angle = math.random() * math.pi * 2
	local dist = math.sqrt(math.random()) * spread
	local flat = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)

	-- find the ground near the planet
	local probe = center + flat + Vector3.new(0, 30, 0)
	local hit = workspace:Raycast(probe, Vector3.new(0, -140, 0), rayParams)
	local target = hit and hit.Position or (center + flat - Vector3.new(0, radius + 1, 0))

	local height = math.max(radius * 5, 18) + math.random() * 14
	local slant = Vector3.new(-0.5 - math.random() * 0.3, 0, 0.25 + math.random() * 0.3) * height
	local start = target + Vector3.new(0, height, 0) + slant

	local size = math.clamp(radius * 0.16, 0.5, 2.6) * (0.7 + math.random() * 0.6)
	local rock = fxPart(start, Vector3.new(size, size, size), mutation.Color2, Enum.PartType.Ball)
	rock.Material = Enum.Material.Neon

	local core = fxPart(start, Vector3.new(size * 0.55, size * 0.55, size * 0.55), Color3.new(1, 1, 0.85), Enum.PartType.Ball)

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.5, 0)
	a0.Parent = rock
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.5, 0)
	a1.Parent = rock
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.55
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), mutation.Color2)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(3.2, 0)
	trail.Parent = rock

	emitter(rock, {
		Texture = FIRE, Rate = 45, Lifetime = NumberRange.new(0.3, 0.6),
		Size = NumberSequence.new(size * 1.6, 0), Speed = NumberRange.new(0, 2),
		Color = seq(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 70, 20)),
	})

	table.insert(meteors, {
		Rock = rock, Core = core, Start = start, Target = target,
		T = 0, Duration = 0.85 + math.random() * 0.5, Color = mutation.Color, Size = size,
	})
end

local function meteorImpact(position, color, size)
	if okAudio then
		Audio.Play("meteor_impact", { Position = position, MinDistance = 12, MaxDistance = 120 })
	end
	local spot = fxPart(position, Vector3.new(0.2, 0.2, 0.2), color, Enum.PartType.Ball, 1)
	emitter(spot, {
		Texture = FIRE, Enabled = false, Rate = 0, Lifetime = NumberRange.new(0.4, 0.8),
		Size = NumberSequence.new(size * 1.8, 0), Speed = NumberRange.new(6, 16),
		Spread = Vector2.new(70, 70), Acceleration = Vector3.new(0, -14, 0),
		Color = seq(Color3.fromRGB(255, 230, 140), Color3.fromRGB(255, 70, 20)),
	}):Emit(14)
	emitter(spot, {
		Texture = SMOKE, Enabled = false, Rate = 0, LightEmission = 0.2,
		Lifetime = NumberRange.new(0.8, 1.4), Size = NumberSequence.new(size * 1.2, size * 3),
		Speed = NumberRange.new(2, 6), Spread = Vector2.new(60, 60),
		Color = seq(Color3.fromRGB(120, 80, 60), Color3.fromRGB(40, 30, 30)),
	}):Emit(5)

	local ring = fxPart(position + Vector3.new(0, 0.15, 0), Vector3.new(0.15, 1, 1), color, Enum.PartType.Cylinder, 0.2)
	ring.CFrame = CFrame.new(ring.Position) * CFrame.Angles(0, 0, math.pi / 2)
	local grow = size * 7
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.15, grow, grow), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.6)
	Debris:AddItem(spot, 1.6)
end

RunService.Heartbeat:Connect(function(dt)
	for i = #meteors, 1, -1 do
		local m = meteors[i]
		m.T += dt / m.Duration
		if m.T >= 1 or not m.Rock.Parent then
			meteorImpact(m.Target, m.Color, m.Size)
			m.Rock:Destroy()
			m.Core:Destroy()
			table.remove(meteors, i)
		else
			local eased = m.T * m.T * 0.4 + m.T * 0.6 -- speeds up as it falls
			local pos = m.Start:Lerp(m.Target, eased)
			m.Rock.Position = pos
			m.Core.Position = pos
		end
	end
end)

---------------------------------------------------------------------
-- Lasting looks for each mutation (they stay on the planet)
---------------------------------------------------------------------
local auraBuilders = {}

auraBuilders.meteor = function(body, r, m)
	-- glowing embers around it (the meteors themselves are made in the loop below)
	emitter(body, {
		Texture = FIRE, Rate = 14, Lifetime = NumberRange.new(0.8, 1.4), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new(r * 0.35, 0), Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, 3, 0), Color = seq(m.Color, m.Color2),
	})
end

auraBuilders.frozen = function(body, r, m)
	emitter(body, {
		Texture = SPARKLE, Rate = 22, Lifetime = NumberRange.new(1.6, 2.6), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new(r * 0.22, r * 0.05), Speed = NumberRange.new(0.5, 2),
		Acceleration = Vector3.new(0, -2.5, 0), Color = seq(Color3.new(1, 1, 1), m.Color2),
	})
	emitter(body, {
		Texture = SMOKE, Rate = 4, LightEmission = 0.6, Lifetime = NumberRange.new(2, 3),
		Shape = Enum.ParticleEmitterShape.Sphere, Size = NumberSequence.new(r * 0.8, r * 1.6),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 1) }),
		Speed = NumberRange.new(0, 1), Color = seq(m.Color, m.Color2),
	})
end

auraBuilders.nebula = function(body, r, m)
	emitter(body, {
		Texture = SMOKE, Rate = 8, LightEmission = 1, Lifetime = NumberRange.new(2.5, 4),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = NumberSequence.new(r * 1.0, r * 2.2),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) }),
		Speed = NumberRange.new(0.5, 1.5), RotSpeed = NumberRange.new(-30, 30), Color = seq(m.Color, m.Color2),
	})
	emitter(body, {
		Texture = SPARKLE, Rate = 26, Lifetime = NumberRange.new(1.5, 2.5),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = NumberSequence.new(r * 0.2, 0), Speed = NumberRange.new(0.5, 2), Color = seq(m.Color, Color3.new(1, 1, 1)),
	})
end

auraBuilders.solarflare = function(body, r, m)
	emitter(body, {
		Texture = FIRE, Rate = 30, Lifetime = NumberRange.new(0.7, 1.2), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new(r * 0.6, 0), Speed = NumberRange.new(2, 6), Acceleration = Vector3.new(0, 4, 0),
		Color = seq(m.Color, m.Color2),
	})
	emitter(body, {
		Texture = SPARKLE, Rate = 16, Lifetime = NumberRange.new(1, 1.8), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new(r * 0.16, 0), Speed = NumberRange.new(4, 9), Color = seq(Color3.new(1, 1, 0.8), m.Color),
	})
end

auraBuilders.supernova = function(body, r, m)
	emitter(body, {
		Texture = SPARKLE, Rate = 40, Lifetime = NumberRange.new(1, 2), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new(r * 0.3, 0), Speed = NumberRange.new(3, 9), Color = seq(Color3.new(1, 1, 1), m.Color2),
	})
	emitter(body, {
		Texture = SMOKE, Rate = 6, Lifetime = NumberRange.new(1.5, 2.2), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new(r * 1.2, r * 3),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
		Speed = NumberRange.new(1, 3), Color = seq(m.Color, m.Color2),
	})
	local light = Instance.new("PointLight")
	light.Color = m.Color2
	light.Range = math.clamp(r * 6, 12, 40)
	light.Brightness = 2
	light.Parent = body
end

auraBuilders.stardust = function(body, r, m)
	-- glittering dust that keeps getting pulled into the black hole (Stardust only comes from sprinklers).
	-- black hole bodies are tiny, so the dust starts on a bigger invisible shell around it
	local shellRadius = math.max(r * 4, 2.5)
	local shell = Instance.new("Part")
	shell.Name = "StardustShell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.one * shellRadius * 2
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.Transparency = 1
	shell.CFrame = body.CFrame
	shell.Parent = body
	local lifetime = 1.4
	local swirl = emitter(shell, {
		Texture = SPARKLE, Rate = 28, Lifetime = NumberRange.new(lifetime, lifetime), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.05) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(1, 0.2) }),
		Speed = NumberRange.new(shellRadius / lifetime, shellRadius / lifetime), RotSpeed = NumberRange.new(-200, 200),
		Color = seq(m.Color, m.Color2),
	})
	swirl.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	emitter(shell, {
		Texture = SPARKLE, Rate = 8, Lifetime = NumberRange.new(2, 3), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Size = NumberSequence.new(0.3, 0),
		Speed = NumberRange.new(0.2, 0.6), Drag = 1, Color = seq(Color3.new(1, 1, 1), m.Color2),
	})
end

---------------------------------------------------------------------
-- Tracking mutated planets
---------------------------------------------------------------------
local active = {} -- model -> { Key, Ids, Has, Items, Body, Radius, NextMeteor, Seed, ... }

local function clearActive(model)
	local info = active[model]
	if info then
		active[model] = nil
		for _, item in ipairs(info.Items) do
			if item.Parent then
				item:Destroy()
			end
		end
	end
end

local function setup(model)
	if not model:IsA("Model") then
		return
	end
	local function refresh()
		local key = model:GetAttribute("Mutations") or ""
		local existing = active[model]
		if existing and existing.Key == key then
			return
		end
		clearActive(model)
		local ids = MutationCatalog.Parse(key)
		local body = model.PrimaryPart or model:FindFirstChild("Body")
		if #ids == 0 or not body then
			return
		end
		local r = model:GetAttribute("BodyRadius") or 3
		local items, has = {}, {}
		-- every mutation keeps its own look, so a planet with two mutations shows both
		for _, id in ipairs(ids) do
			has[id] = true
			local before = {}
			for _, child in ipairs(body:GetChildren()) do
				before[child] = true
			end
			local build = auraBuilders[id]
			if build then
				build(body, r, MutationCatalog.Get(id))
			end
			for _, child in ipairs(body:GetChildren()) do
				if not before[child] then
					table.insert(items, child)
				end
			end
		end
		active[model] = {
			Key = key, Ids = ids, Has = has, Items = items, Body = body, Radius = r,
			NextMeteor = os.clock() + math.random() * METEOR_EVERY, Seed = math.random() * 10,
		}
	end
	model:GetAttributeChangedSignal("Mutations"):Connect(refresh)
	refresh()
end

for _, model in ipairs(plantsFolder:GetChildren()) do
	setup(model)
end
plantsFolder.ChildAdded:Connect(function(model)
	task.defer(setup, model)
end)
plantsFolder.ChildRemoved:Connect(clearActive)

RunService.Heartbeat:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local now = os.clock()
	local filtered = false

	for model, info in pairs(active) do
		if not model.Parent or not info.Body.Parent then
			clearActive(model)
		else
			local center = info.Body.Position
			local near = (center - camPos).Magnitude <= SHOW_DISTANCE

			for _, item in ipairs(info.Items) do
				if item:IsA("ParticleEmitter") then
					if item:GetAttribute("BaseRate") == nil then
						item:SetAttribute("BaseRate", item.Rate)
					end
					item.Rate = near and item:GetAttribute("BaseRate") or 0
				end
			end

			-- falling meteors (Meteor Shower)
			if near and info.Has.meteor and now >= info.NextMeteor then
				if not filtered then
					refreshRayFilter()
					filtered = true
				end
				info.NextMeteor = now + METEOR_EVERY * (0.6 + math.random() * 0.8)
				spawnMeteor(center, info.Radius, MutationCatalog.Get("meteor"))
			end

			-- shimmering titles (one line per mutation)
			local gui = info.Body:FindFirstChild("MutationTitle")
			if gui ~= info.TitleGui then
				info.TitleGui = gui
				info.Gradients = {}
				if gui then
					for _, d in ipairs(gui:GetDescendants()) do
						if d:IsA("UIGradient") then
							table.insert(info.Gradients, d)
						end
					end
				end
			end
			for index, g in ipairs(info.Gradients or {}) do
				g.Offset = Vector2.new(math.sin(now * 1.8 + info.Seed + index) * 0.45, 0)
			end

			-- supernova pulses a shockwave now and then
			if near and info.Has.supernova then
				info.Pulse = info.Pulse or now + 1
				if now >= info.Pulse then
					info.Pulse = now + 2.2
					local ring = fxPart(center, Vector3.new(1, 1, 1), MutationCatalog.Get("supernova").Color2, Enum.PartType.Ball, 0.5)
					local big = info.Radius * 5
					TweenService:Create(ring, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Size = Vector3.new(big, big, big), Transparency = 1 }):Play()
					Debris:AddItem(ring, 1.2)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- The big burst when a planet GETS a mutation
---------------------------------------------------------------------
local function shockwave(position, color, fromSize, toSize, seconds, transparency)
	local ball = fxPart(position, Vector3.new(fromSize, fromSize, fromSize), color, Enum.PartType.Ball, transparency or 0.35)
	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(toSize, toSize, toSize), Transparency = 1 }):Play()
	Debris:AddItem(ball, seconds + 0.1)
end

local function groundRing(position, color, toSize, seconds)
	local ring = fxPart(position, Vector3.new(0.3, 1, 1), color, Enum.PartType.Cylinder, 0.25)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.3, toSize, toSize), Transparency = 1 }):Play()
	Debris:AddItem(ring, seconds + 0.1)
end

local function flash(position, color, range, seconds)
	local anchor = fxPart(position, Vector3.new(0.2, 0.2, 0.2), color, Enum.PartType.Ball, 1)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 8
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(seconds), { Brightness = 0 }):Play()
	Debris:AddItem(anchor, seconds + 0.1)
	return anchor
end

local function burstParticles(position, props, count)
	local anchor = fxPart(position, Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), Enum.PartType.Ball, 1)
	props.Enabled = false
	props.Rate = 0
	emitter(anchor, props):Emit(count)
	Debris:AddItem(anchor, 4)
end

local burstStyles = {}

burstStyles.meteor = function(pos, r, m, model)
	flash(pos, m.Color, r * 8, 0.8)
	shockwave(pos, m.Color, r, r * 7, 0.7)
	shockwave(pos, Color3.new(1, 0.95, 0.8), r * 0.5, r * 4, 0.45, 0.2)
	groundRing(pos - Vector3.new(0, r, 0), m.Color2, r * 9, 0.9)
	burstParticles(pos, {
		Texture = FIRE, Lifetime = NumberRange.new(0.8, 1.6), Size = NumberSequence.new(r * 0.5, 0),
		Speed = NumberRange.new(10, 28), Acceleration = Vector3.new(0, -12, 0), Color = seq(m.Color, m.Color2),
	}, 90)
	burstParticles(pos, {
		Texture = SPARKLE, Lifetime = NumberRange.new(1, 2), Size = NumberSequence.new(r * 0.25, 0),
		Speed = NumberRange.new(12, 30), Color = seq(Color3.new(1, 1, 0.8), m.Color),
	}, 60)
	-- the meteor barrage: a burst of meteors raining down around it
	refreshRayFilter()
	for i = 1, 16 do
		task.delay(i * 0.1 + math.random() * 0.08, function()
			if model.Parent and model.PrimaryPart then
				spawnMeteor(model.PrimaryPart.Position, r, m)
			end
		end)
	end
end

burstStyles.frozen = function(pos, r, m)
	flash(pos, m.Color, r * 7, 0.8)
	shockwave(pos, m.Color, r, r * 6, 0.7)
	groundRing(pos - Vector3.new(0, r, 0), Color3.new(1, 1, 1), r * 8, 0.8)
	burstParticles(pos, {
		Texture = SPARKLE, Lifetime = NumberRange.new(1.2, 2.4), Size = NumberSequence.new(r * 0.35, 0),
		Speed = NumberRange.new(8, 22), Acceleration = Vector3.new(0, -6, 0), Color = seq(Color3.new(1, 1, 1), m.Color2),
	}, 110)
end

burstStyles.nebula = function(pos, r, m)
	flash(pos, m.Color, r * 8, 1)
	shockwave(pos, m.Color, r, r * 7, 0.9)
	task.delay(0.2, function()
		shockwave(pos, m.Color2, r, r * 9, 1.0, 0.5)
	end)
	groundRing(pos - Vector3.new(0, r, 0), m.Color, r * 10, 1.0)
	burstParticles(pos, {
		Texture = SMOKE, Lifetime = NumberRange.new(1.5, 2.6), Size = NumberSequence.new(r * 1.2, r * 3),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Speed = NumberRange.new(5, 14), Color = seq(m.Color, m.Color2),
	}, 40)
	burstParticles(pos, {
		Texture = SPARKLE, Lifetime = NumberRange.new(1.5, 2.6), Size = NumberSequence.new(r * 0.3, 0),
		Speed = NumberRange.new(8, 24), Color = seq(m.Color, Color3.new(1, 1, 1)),
	}, 90)
end

burstStyles.solarflare = function(pos, r, m)
	flash(pos, m.Color, r * 10, 0.9)
	shockwave(pos, m.Color, r, r * 8, 0.6, 0.15)
	shockwave(pos, m.Color2, r, r * 5, 0.5, 0.3)
	groundRing(pos - Vector3.new(0, r, 0), m.Color, r * 10, 0.8)
	burstParticles(pos, {
		Texture = FIRE, Lifetime = NumberRange.new(0.7, 1.4), Size = NumberSequence.new(r * 0.7, 0),
		Speed = NumberRange.new(14, 34), Color = seq(m.Color, m.Color2),
	}, 120)
	burstParticles(pos, {
		Texture = SPARKLE, Lifetime = NumberRange.new(1, 2), Size = NumberSequence.new(r * 0.25, 0),
		Speed = NumberRange.new(14, 36), Color = seq(Color3.new(1, 1, 0.9), m.Color),
	}, 80)
end

burstStyles.supernova = function(pos, r, m)
	flash(pos, Color3.new(1, 1, 1), r * 14, 1.4)
	shockwave(pos, Color3.new(1, 1, 1), r, r * 12, 0.9, 0.05)
	task.delay(0.15, function()
		shockwave(pos, m.Color2, r, r * 16, 1.2, 0.3)
	end)
	task.delay(0.4, function()
		shockwave(pos, m.Color, r, r * 20, 1.5, 0.5)
	end)
	groundRing(pos - Vector3.new(0, r, 0), Color3.new(1, 1, 1), r * 18, 1.2)
	burstParticles(pos, {
		Texture = SPARKLE, Lifetime = NumberRange.new(1.5, 3), Size = NumberSequence.new(r * 0.4, 0),
		Speed = NumberRange.new(16, 44), Color = seq(Color3.new(1, 1, 1), m.Color2),
	}, 200)
	burstParticles(pos, {
		Texture = FIRE, Lifetime = NumberRange.new(1, 1.8), Size = NumberSequence.new(r * 0.8, 0),
		Speed = NumberRange.new(10, 30), Color = seq(m.Color, m.Color2),
	}, 80)
end

burstStyles.stardust = function(pos, r, m)
	-- the dust collapses INTO the black hole, then it flares
	r = math.max(r, 1)
	local spread = math.max(r * 10, 8)
	for i = 1, 40 do
		local dir = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.6, math.random() - 0.5)
		if dir.Magnitude < 0.05 then
			dir = Vector3.new(1, 0, 0)
		end
		local start = pos + dir.Unit * spread * (0.6 + math.random() * 0.4)
		local mote = fxPart(start, Vector3.new(0.35, 0.35, 0.35), i % 2 == 0 and m.Color or m.Color2, Enum.PartType.Ball, 0)
		local seconds = 0.6 + math.random() * 0.5
		TweenService:Create(mote, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = pos, Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		Debris:AddItem(mote, seconds + 0.05)
	end
	task.delay(1.1, function()
		flash(pos, m.Color, r * 10, 1)
		shockwave(pos, m.Color, r, r * 8, 0.8, 0.3)
		groundRing(pos - Vector3.new(0, r, 0), m.Color2, r * 10, 0.9)
		burstParticles(pos, {
			Texture = SPARKLE, Lifetime = NumberRange.new(1.2, 2.2), Size = NumberSequence.new(r * 0.35, 0),
			Speed = NumberRange.new(8, 22), Color = seq(m.Color, m.Color2),
		}, 120)
	end)
end

gainedRemote.OnClientEvent:Connect(function(model, mutId)
	local mutation = MutationCatalog.Get(mutId)
	if typeof(model) ~= "Instance" or not mutation then
		return
	end
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body then
		return
	end
	local r = model:GetAttribute("BodyRadius") or 3
	local style = burstStyles[mutId]
	if style then
		pcall(style, body.Position, r, mutation, model)
	end
end)

print("[MutationVFX] ready")
