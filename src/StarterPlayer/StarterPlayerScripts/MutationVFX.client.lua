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
local Stardust = require(ReplicatedStorage:WaitForChild("Stardust"))
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

-- sprinkler bonus mutations (Style = "sprinkler"): their own stardust texture orbits the planet,
-- a soft halo pulses around it, and sparkles rise off it. Bigger multiplier = more of everything.
local function sprinklerAura(body, r, m)
	local power = math.clamp(math.log10(math.max(m.SellMult or 2, 2)), 0.3, 3.4) -- 3x ~ 0.5, 2500x ~ 3.4
	local tex = Stardust.Texture(m.Tex or "Star")
	emitter(body, {
		Texture = tex, Rate = 6 + power * 6, Lifetime = NumberRange.new(1.2, 2), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, r * (0.35 + power * 0.1)), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(0.3, 1), RotSpeed = NumberRange.new(-60, 60), Rotation = NumberRange.new(0, 360),
		Color = seq(m.Color, m.Color2), LightEmission = 1,
	})
	emitter(body, {
		Texture = SPARKLE, Rate = 4 + power * 5, Lifetime = NumberRange.new(1.5, 2.5), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new(r * 0.12, 0), Speed = NumberRange.new(1, 2.5), Acceleration = Vector3.new(0, 2.5, 0),
		Color = seq(Color3.new(1, 1, 1), m.Color2), LightEmission = 1,
	})
	local light = Instance.new("PointLight")
	light.Color = m.Color
	light.Range = math.clamp(r * 4 + power * 6, 10, 40)
	light.Brightness = 1 + power * 0.6
	light.Parent = body
end

---------------------------------------------------------------------
-- SPACE WEATHER mutations (Style = "weather"): every look is described in MutationCatalog (Look = {...})
-- and built here out of particle layers, glowing rings, orbiting bits, shells, beams and outlines.
-- The rings / orbiters / beams live in their own folder per planet and follow the planet every frame
-- (planets grow, so everything is sized from the planet's CURRENT radius).
---------------------------------------------------------------------
local TEXTURES = { SPARKLE = SPARKLE, FIRE = FIRE, SMOKE = SMOKE }
local function lookTexture(name)
	return TEXTURES[name] or Stardust.Texture(name)
end

local function liveRadius(body)
	return math.max(body.Size.X, body.Size.Y, body.Size.Z) / 2
end

local function lookPart(parent, shape, color, material, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape or Enum.PartType.Block
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0
	p.Size = Vector3.one
	p.Parent = parent
	return p
end

-- a glowing ring drawn on a thin invisible plate (crisp at any size, glows with Bloom)
local function ringPlate(parent, def)
	local plate = lookPart(parent, Enum.PartType.Block, Color3.new(), Enum.Material.SmoothPlastic, 1)
	plate.Name = "Ring"
	local strokes = {}
	for _, face in ipairs({ Enum.NormalId.Top, Enum.NormalId.Bottom }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(256, 256)
		gui.LightInfluence = 0
		gui.Brightness = def.Glow or 2.5
		gui.AlwaysOnTop = false
		gui.Parent = plate
		local circle = Instance.new("Frame")
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = UDim2.fromScale(0.5, 0.5)
		circle.Size = UDim2.fromScale(1, 1)
		circle.BackgroundTransparency = 1
		circle.Parent = gui
		Instance.new("UICorner", circle).CornerRadius = UDim.new(0.5, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Transparency = def.T or 0
		-- W is the band's width compared with the ring's radius
		stroke.Thickness = math.clamp(128 * (def.W or 0.08) / (def.R or 1.5), 2, 110)
		stroke.Parent = circle
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, def.Color),
			ColorSequenceKeypoint.new(0.5, def.Color2 or Color3.new(1, 1, 1):Lerp(def.Color, 0.55)),
			ColorSequenceKeypoint.new(1, def.Color),
		})
		gradient.Parent = stroke
		table.insert(strokes, { Stroke = stroke, Gradient = gradient })
	end
	return plate, strokes
end

local function lookAura(body, r, m)
	local look = m.Look or {}
	local k = math.clamp(r / 3, 0.5, 3) -- particle speeds grow a little with the planet
	local emitters = {}
	local holder = Instance.new("Folder")
	holder.Name = "Look_" .. m.Id

	-- particle layers
	for _, e in ipairs(look.Emit or {}) do
		local host = body
		local shellRadius = r * (e.Shell or 1)
		if e.Shell then
			host = Instance.new("Part")
			host.Name = "LookShell"
			host.Shape = Enum.PartType.Ball
			host.Size = Vector3.one * shellRadius * 2
			host.Anchored = true
			host.CanCollide = false
			host.CanQuery = false
			host.CanTouch = false
			host.Transparency = 1
			host.CFrame = body.CFrame
			host.Parent = body
		end
		local life = e.Life or { 1, 2 }
		local speed = e.Speed or { 0.5, 1.5 }
		local t0 = e.T0 or 0
		local spin = e.Spin or 60
		local em = emitter(host, {
			Texture = lookTexture(e.Tex), Rate = e.Rate or 10,
			Lifetime = NumberRange.new(life[1], life[2]),
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = e.Volume and Enum.ParticleEmitterShapeStyle.Volume or Enum.ParticleEmitterShapeStyle.Surface,
			Size = NumberSequence.new(r * (e.Size and e.Size[1] or 0.3), r * (e.Size and e.Size[2] or 0)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, t0), NumberSequenceKeypoint.new(1, 1) }),
			Speed = e.Inward and NumberRange.new((shellRadius - r * 0.9) / life[1]) or NumberRange.new(speed[1] * k, speed[2] * k),
			RotSpeed = NumberRange.new(-spin, spin),
			Acceleration = e.Accel and Vector3.new(e.Accel[1], e.Accel[2], e.Accel[3]) * k or Vector3.zero,
			Drag = e.Drag or 0,
			Color = seq(e.C1 or m.Color, e.C2 or m.Color2),
			LightEmission = e.LE or 1,
		})
		if e.Inward then
			em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		end
		table.insert(emitters, em)
	end

	-- light
	local flickerLight = nil
	if look.Light then
		local light = Instance.new("PointLight")
		light.Name = "LookLight"
		light.Color = look.Light.Color or m.Color
		light.Range = math.clamp(r * (look.Light.Range or 4), 8, 60)
		light.Brightness = look.Light.Brightness or 1.5
		light.Parent = body
		if look.Light.Flicker then
			flickerLight = light
		end
		table.insert(emitters, light)
	end

	local anim = { Holder = holder, Rings = {}, Orbit = {}, Look = look, Mutation = m, Born = os.clock(),
		Light = flickerLight, LightBase = look.Light and look.Light.Brightness or 1.5 }

	for _, def in ipairs(look.Rings or {}) do
		local plate, strokes = ringPlate(holder, def)
		table.insert(anim.Rings, { Part = plate, Def = def, Strokes = strokes, Phase = math.random() * 360 })
	end

	for _, def in ipairs(look.Orbit or {}) do
		for i = 1, def.N or 3 do
			local shape = def.Shape == "Block" and Enum.PartType.Block or def.Shape == "Wedge" and Enum.PartType.Wedge or Enum.PartType.Ball
			local material = def.Mat and Enum.Material[def.Mat] or Enum.Material.Neon
			local p = lookPart(holder, shape, def.Color, material, def.Mat == "Glass" and 0.3 or 0)
			p.Name = "Orbiter"
			if def.Trail then
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, 0.5, 0)
				a0.Parent = p
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(0, -0.5, 0)
				a1.Parent = p
				local trail = Instance.new("Trail")
				trail.Attachment0 = a0
				trail.Attachment1 = a1
				trail.Color = ColorSequence.new(def.Color)
				trail.LightEmission = 1
				trail.LightInfluence = 0
				trail.Lifetime = 0.45
				trail.Transparency = NumberSequence.new(0.2, 1)
				trail.FaceCamera = true
				trail.Parent = p
			end
			table.insert(anim.Orbit, { Part = p, Def = def, Offset = (i - 1) / (def.N or 3), Spin = Vector3.new(math.random(), math.random(), math.random()) })
		end
	end

	if look.Shell then
		local s = look.Shell
		anim.Shell = lookPart(holder, Enum.PartType.Ball, s.Color, s.Mat and Enum.Material[s.Mat] or Enum.Material.ForceField, s.T or 0.6)
		anim.Shell.Name = "Shell"
	end

	local function beam(a0, a1, color, width0, width1, tex, speed)
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Color = ColorSequence.new(color, Color3.new(1, 1, 1):Lerp(color, 0.4))
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Texture = Stardust.Texture(tex or "Flow")
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = 6
		b.TextureSpeed = speed or 1.5
		b.Width0 = width0
		b.Width1 = width1
		b.FaceCamera = true
		b.Segments = 1
		b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		b.Parent = a0.Parent
		return b
	end

	if look.Jets or look.Pillar then
		anim.Anchor = lookPart(holder, Enum.PartType.Block, Color3.new(), Enum.Material.SmoothPlastic, 1)
		anim.Anchor.Name = "BeamAnchor"
		local center = Instance.new("Attachment")
		center.Parent = anim.Anchor
		anim.Center = center
		anim.Beams = {}
		if look.Jets then
			for _, dir in ipairs({ 1, -1 }) do
				local tip = Instance.new("Attachment")
				tip.Parent = anim.Anchor
				local b = beam(center, tip, look.Jets.Color, 1, 1, "Flow", 4)
				table.insert(anim.Beams, { Beam = b, Tip = tip, Dir = dir, Kind = "jet" })
			end
		end
		if look.Pillar then
			local top = Instance.new("Attachment")
			top.Parent = anim.Anchor
			local b = beam(center, top, look.Pillar.Color, 1, 1, "Flow", -2)
			b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.85) })
			table.insert(anim.Beams, { Beam = b, Tip = top, Dir = 1, Kind = "pillar" })
		end
	end

	anim.NextPulse = os.clock() + math.random() * 2
	anim.NextArc = os.clock() + math.random()
	return emitters, anim
end

local function arcBolt(center, radius, color)
	-- a short jagged spark hopping across the planet's surface
	local a = Random.new():NextUnitVector() * radius * 1.05
	local b = (a + Random.new():NextUnitVector() * radius * 0.9).Unit * radius * 1.1
	local points = { center + a }
	for i = 1, 3 do
		local p = center + a:Lerp(b, i / 4)
		points[#points + 1] = p + Random.new():NextUnitVector() * radius * 0.12
	end
	points[#points + 1] = center + b
	for i = 1, #points - 1 do
		local p0, p1 = points[i], points[i + 1]
		local len = (p1 - p0).Magnitude
		local seg = fxPart((p0 + p1) / 2, Vector3.new(radius * 0.04, radius * 0.04, len), color, Enum.PartType.Block, 0)
		seg.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
		Debris:AddItem(seg, 0.12)
	end
end

local function hueShift(color, now, speed)
	local h, s, v = color:ToHSV()
	return Color3.fromHSV((h + now * (speed or 0.15)) % 1, math.max(s, 0.55), v)
end

-- moves everything that follows a planet (called every frame for nearby planets)
local function updateLook(anim, body, now, dt)
	local cf = body.CFrame
	local pos = cf.Position
	local r = liveRadius(body)
	local look = anim.Look
	local age = now - anim.Born

	for _, ring in ipairs(anim.Rings) do
		local d = ring.Def
		local diameter = r * 2 * (d.R or 1.5)
		local y = (d.Y or 0) * r
		local tilt = CFrame.Angles(math.rad(d.Tilt or 0), 0, 0)
		local offset = Vector3.new(0, y, 0)
		if d.Scan then
			offset = Vector3.new(0, math.sin(age * 2.2) * r * 0.95, 0)
			local scale = math.sqrt(math.max(0, 1 - (offset.Y / (r * 1.05)) ^ 2))
			diameter = r * 2 * (d.R or 1.3) * math.max(scale, 0.25)
		end
		ring.Part.Size = Vector3.new(diameter, 0.05, diameter)
		ring.Part.CFrame = CFrame.new(pos + offset) * tilt * CFrame.Angles(0, math.rad(ring.Phase + age * (d.Spin or 0)), 0)
		for _, s in ipairs(ring.Strokes) do
			s.Gradient.Rotation = (age * 90 + ring.Phase) % 360
			if look.Rainbow then
				s.Stroke.Color = hueShift(Color3.new(1, 0.4, 0.4), now + ring.Phase, 0.12)
			end
		end
	end

	for _, o in ipairs(anim.Orbit) do
		local d = o.Def
		local angle = (o.Offset + age * (d.Speed or 0.3)) * math.pi * 2
		local radius = r * (d.R or 1.6)
		local local3 = Vector3.new(math.cos(angle) * radius, math.sin(angle * 2) * r * 0.08, math.sin(angle) * radius)
		local tilted = CFrame.Angles(math.rad(d.Tilt or 0), 0, 0):VectorToWorldSpace(local3)
		local size = r * (d.S or 0.15)
		o.Part.Size = Vector3.one * size
		o.Part.CFrame = CFrame.new(pos + tilted) * CFrame.Angles(o.Spin.X * age * 2, o.Spin.Y * age * 2, o.Spin.Z * age * 2)
	end

	if anim.Shell then
		local s = look.Shell.S or 1.05
		anim.Shell.Size = Vector3.one * r * 2 * s
		anim.Shell.CFrame = cf * CFrame.Angles(0, age * 0.3, 0)
	end

	if anim.Anchor then
		anim.Anchor.CFrame = CFrame.new(pos)
		for _, b in ipairs(anim.Beams) do
			if b.Kind == "jet" then
				local jet = look.Jets
				b.Tip.Position = Vector3.new(0, b.Dir * r * (jet.L or 8) * (0.9 + math.sin(age * 6) * 0.1), 0)
				b.Beam.Width0 = r * (jet.W or 0.4)
				b.Beam.Width1 = r * (jet.W or 0.4) * 2.5
			else
				local pillar = look.Pillar
				b.Tip.Position = Vector3.new(0, pillar.H or 26, 0)
				b.Beam.Width0 = r * (pillar.W or 1.5) * 1.2
				b.Beam.Width1 = r * (pillar.W or 1.5) * 2.2
			end
		end
	end

	if look.Pulse and now >= anim.NextPulse then
		anim.NextPulse = now + (look.Pulse.Every or 2.5)
		local p = look.Pulse
		local ball = fxPart(pos, Vector3.one * r * 2, look.Rainbow and hueShift(p.Color, now) or p.Color, Enum.PartType.Ball, 0.55)
		ball.Material = Enum.Material.ForceField
		local big = r * (p.S or 4)
		TweenService:Create(ball, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.one * big, Transparency = 1 }):Play()
		Debris:AddItem(ball, 1.2)
	end

	if look.Arcs and now >= anim.NextArc then
		anim.NextArc = now + (look.Arcs.Every or 0.4) * (0.6 + math.random() * 0.8)
		arcBolt(pos, r, look.Arcs.Color)
	end
end

-- glowing outlines: Roblox only draws a limited number of Highlights at once, so only the
-- closest outlined planets get one
local MAX_OUTLINES = 14
local outlinePool = {}
local function getOutline(i)
	local h = outlinePool[i]
	if not h then
		h = Instance.new("Highlight")
		h.Name = "MutationOutline"
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Enabled = false
		h.Parent = fxFolder
		outlinePool[i] = h
	end
	return h
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
			item:Destroy() -- (some are hidden with no parent while you're far away)
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
		local anims, outline = {}, nil
		-- every mutation keeps its own look, so a planet with two mutations shows both
		for _, id in ipairs(ids) do
			has[id] = true
			local before = {}
			for _, child in ipairs(body:GetChildren()) do
				before[child] = true
			end
			local info = MutationCatalog.Get(id)
			if info and info.Style == "weather" then
				local made, anim = lookAura(body, r, info)
				for _, item in ipairs(made) do
					table.insert(items, item)
				end
				anim.Holder.Parent = fxFolder
				table.insert(items, anim.Holder)
				table.insert(anims, anim)
				local look = info.Look or {}
				local tier = MutationCatalog.RarityOf(id).Tier
				if look.Outline and (not outline or tier > outline.Tier) then
					outline = { Color = look.Outline, Fill = look.Fill, FillT = look.FillT, Rainbow = look.Rainbow, Tier = tier }
				end
			else
				local build = auraBuilders[id] or (info and info.Style == "sprinkler" and sprinklerAura)
				if build then
					build(body, r, MutationCatalog.Get(id))
				end
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
			Anims = anims, Outline = outline,
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

local nextOutlineSort = 0
RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local now = os.clock()
	local filtered = false
	local outlined = (now >= nextOutlineSort) and {} or nil

	for model, info in pairs(active) do
		if not model.Parent or not info.Body.Parent then
			clearActive(model)
		else
			local center = info.Body.Position
			local distance = (center - camPos).Magnitude
			local near = distance <= SHOW_DISTANCE

			-- space weather looks: rings, orbiters, beams... (hidden when you're far away)
			for _, anim in ipairs(info.Anims or {}) do
				local parent = near and fxFolder or nil
				if anim.Holder.Parent ~= parent then
					anim.Holder.Parent = parent
				end
				if near then
					updateLook(anim, info.Body, now, dt)
					if anim.Light then
						anim.Light.Brightness = anim.LightBase * (0.6 + math.noise(now * 6, info.Seed) * 0.8 + 0.4 * math.random())
					end
				end
			end
			if outlined and info.Outline and near then
				table.insert(outlined, { Model = model, Distance = distance, Outline = info.Outline })
			end

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

	-- glowing outlines go to the closest outlined planets (rarest first when it's a tie)
	if outlined then
		nextOutlineSort = now + 0.5
		table.sort(outlined, function(a, b)
			return a.Distance - a.Outline.Tier * 12 < b.Distance - b.Outline.Tier * 12
		end)
		for i = 1, MAX_OUTLINES do
			local entry = outlined[i]
			local h = outlinePool[i] or (entry and getOutline(i))
			if h then
				if entry then
					local o = entry.Outline
					h.Adornee = entry.Model
					h.OutlineColor = o.Color
					h.OutlineTransparency = 0
					h.FillColor = o.Fill or o.Color
					h.FillTransparency = o.FillT or 1
					h:SetAttribute("Rainbow", o.Rainbow == true)
					h:SetAttribute("Base", o.Color)
					h.Enabled = true
				else
					h.Enabled = false
					h.Adornee = nil
				end
			end
		end
	end
	for _, h in ipairs(outlinePool) do
		if h.Enabled and h:GetAttribute("Rainbow") then
			h.OutlineColor = hueShift(Color3.fromRGB(255, 90, 90), now, 0.2)
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

-- a sprinkler bonus lands: stardust rains INTO the planet, then it flashes (bigger multiplier = bigger boom)
local function sprinklerBurst(pos, r, m)
	r = math.max(r, 1)
	local power = math.clamp(math.log10(math.max(m.SellMult or 2, 2)), 0.3, 3.4)
	local tex = Stardust.Texture(m.Tex or "Star")
	for i = 1, math.floor(10 + power * 8) do
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5)
		local start = pos + dir.Unit * r * (5 + power * 2)
		local mote = fxPart(start, Vector3.new(0.4, 0.4, 0.4), i % 2 == 0 and m.Color or m.Color2, Enum.PartType.Ball, 0)
		local seconds = 0.5 + math.random() * 0.4
		TweenService:Create(mote, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = pos, Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		Debris:AddItem(mote, seconds + 0.05)
	end
	task.delay(0.9, function()
		flash(pos, m.Color, r * 8 + power * 10, 0.9)
		shockwave(pos, m.Color, r, r * (5 + power * 2), 0.7, 0.3)
		groundRing(pos - Vector3.new(0, r, 0), m.Color2, r * (7 + power * 3), 0.9)
		burstParticles(pos, {
			Texture = tex, Lifetime = NumberRange.new(1, 2), Size = NumberSequence.new(r * 0.5, 0),
			Speed = NumberRange.new(6, 18 + power * 6), RotSpeed = NumberRange.new(-120, 120), Color = seq(m.Color, m.Color2), LightEmission = 1,
		}, math.floor(30 + power * 30))
	end)
end

-- space weather mutations: the rarer, the bigger the show
local function weatherBurst(pos, r, m)
	local tier = MutationCatalog.RarityOf(m.Id).Tier
	local look = m.Look or {}
	local c1, c2 = m.Color, m.Color2
	flash(pos, c1, r * (6 + tier * 2), 0.6 + tier * 0.15)
	shockwave(pos, c1, r, r * (5 + tier * 1.5), 0.6 + tier * 0.08, 0.3)
	if tier >= 3 then
		task.delay(0.12, function()
			shockwave(pos, c2, r, r * (7 + tier * 2), 0.9 + tier * 0.1, 0.45)
		end)
		groundRing(pos - Vector3.new(0, r, 0), c1, r * (6 + tier * 2.5), 1)
	end
	local first = look.Emit and look.Emit[1]
	burstParticles(pos, {
		Texture = first and lookTexture(first.Tex) or SPARKLE, Lifetime = NumberRange.new(1, 2),
		Size = NumberSequence.new(r * 0.4, 0), Speed = NumberRange.new(8, 16 + tier * 5),
		RotSpeed = NumberRange.new(-150, 150), Color = seq(c1, c2),
	}, 30 + tier * 25)
	if tier >= 5 then
		-- a beam of light shoots up into the sky so the whole server sees it
		local column = fxPart(pos + Vector3.new(0, 60, 0), Vector3.new(r * 1.2, 120, r * 1.2), c1, Enum.PartType.Cylinder, 0.2)
		column.CFrame = CFrame.new(pos + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		column.Size = Vector3.new(120, r * 1.2, r * 1.2)
		TweenService:Create(column, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(220, r * 0.1, r * 0.1), Transparency = 1 }):Play()
		Debris:AddItem(column, 2)
		burstParticles(pos, {
			Texture = SPARKLE, Lifetime = NumberRange.new(1.5, 3), Size = NumberSequence.new(r * 0.5, 0),
			Speed = NumberRange.new(20, 50), Color = seq(Color3.new(1, 1, 1), c2),
		}, 60 + tier * 20)
	end
	if tier >= 6 then
		for i = 1, tier - 4 do
			task.delay(0.25 * i, function()
				shockwave(pos, i % 2 == 0 and c1 or c2, r, r * (14 + i * 6), 1.4, 0.4)
			end)
		end
	end
	if tier >= 7 then
		-- TON-618 level: the light bends inward first, then everything explodes outward
		local implode = fxPart(pos, Vector3.one * r * 30, c2, Enum.PartType.Ball, 0.85)
		implode.Material = Enum.Material.ForceField
		TweenService:Create(implode, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = Vector3.one * r, Transparency = 0.2 }):Play()
		Debris:AddItem(implode, 0.75)
		task.delay(0.7, function()
			flash(pos, Color3.new(1, 1, 1), r * 40, 2.5)
			shockwave(pos, Color3.new(1, 1, 1), r, r * 45, 2, 0.1)
			groundRing(pos - Vector3.new(0, r, 0), c1, r * 60, 2.2)
		end)
	end
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
	local style = burstStyles[mutId] or (mutation.Style == "sprinkler" and sprinklerBurst)
		or (mutation.Style == "weather" and weatherBurst)
	if style then
		pcall(style, body.Position, r, mutation, model)
	end
end)

print("[MutationVFX] ready")
