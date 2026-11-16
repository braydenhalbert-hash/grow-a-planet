--[[
	WeatherClient  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	Draws the space weather everyone in the server is having (WeatherServer picks it, WeatherConfig
	describes it): the skybox, lighting, fog, particles around your camera, the big things in the sky
	(meteors, lightning, a vortex, an eclipse, an exploding star...), the ambient sound and low gravity.
	Everything fades in and out smoothly. Phones get fewer particles.

	Needs: WeatherConfig, EventConfig, SpaceFX, ScreenFit (ReplicatedStorage), WeatherServer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("LiveOps", 60)
if not state then
	return
end
local WeatherConfig = require(ReplicatedStorage:WaitForChild("WeatherConfig"))
local EventConfig = require(ReplicatedStorage:WaitForChild("EventConfig"))
local SpaceFX = require(ReplicatedStorage:WaitForChild("SpaceFX"))
local ScreenFit = require(ReplicatedStorage:WaitForChild("ScreenFit"))
local okAudio, Audio = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Audio", 5))
end)

local FADE = 2.5            -- seconds for lighting to change
local PARTICLE_SCALE = ScreenFit.IsPhone() and 0.45 or 1
local rng = Random.new()

local function tween(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props)
	tw:Play()
	return tw
end

---------------------------------------------------------------------
-- The normal look (so we can always go back to it)
---------------------------------------------------------------------
local cc = Lighting:FindFirstChild("LiveOpsWeather") or Instance.new("ColorCorrectionEffect")
cc.Name = "LiveOpsWeather"
cc.Parent = Lighting

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local sky = Lighting:FindFirstChildOfClass("Sky")
local base = {
	Ambient = Lighting.Ambient,
	Bloom = bloom and bloom.Intensity,
}
if atmosphere then
	base.Fog = atmosphere.Color
	base.Decay = atmosphere.Decay
	base.Density = atmosphere.Density
	base.Haze = atmosphere.Haze
	base.Glare = atmosphere.Glare
end
local baseSky = nil
if sky then
	baseSky = {}
	for _, face in ipairs({ "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }) do
		baseSky[face] = sky[face]
	end
end
local baseGravity = workspace.Gravity

---------------------------------------------------------------------
-- Lighting + sky
---------------------------------------------------------------------
local skyToken = 0
local function setSky(faces)
	if not sky then
		return
	end
	faces = faces or baseSky
	skyToken += 1
	local mine = skyToken
	-- dip to dark, swap the skybox, come back (a skybox can't fade by itself)
	SpaceFX.Flash(Color3.fromRGB(20, 10, 40), -0.25, 1.2)
	task.delay(0.25, function()
		if mine == skyToken then
			for face, id in pairs(faces) do
				sky[face] = id
			end
		end
	end)
end

local function applyLighting(w)
	local l = w.Lighting or {}
	tween(cc, FADE, {
		TintColor = l.Tint or Color3.new(1, 1, 1),
		Brightness = l.Bright or 0,
		Saturation = l.Sat or 0,
		Contrast = l.Contrast or 0,
	})
	if atmosphere then
		local fog = l.Fog or base.Fog
		tween(atmosphere, FADE, {
			Color = fog,
			Decay = l.Fog and fog:Lerp(Color3.new(0, 0, 0), 0.55) or base.Decay,
			Density = l.Density or base.Density,
			Haze = l.Haze or base.Haze,
			Glare = l.Glare or base.Glare,
		})
	end
	if bloom then
		tween(bloom, FADE, { Intensity = l.Bloom or base.Bloom })
	end
	tween(Lighting, FADE, { Ambient = l.Ambient or base.Ambient })
	local faces = w.Sky and WeatherConfig.Skies[w.Sky] or nil
	setSky(faces)
end

---------------------------------------------------------------------
-- Particles around the camera
---------------------------------------------------------------------
local layerParts = {}

local function clearLayers()
	for _, layer in ipairs(layerParts) do
		local part = layer.Part
		layer.Emitter.Enabled = false
		Debris:AddItem(part, 6) -- let the last particles finish
	end
	table.clear(layerParts)
end

local DIRS = {
	down = { Size = Vector3.new(170, 1, 170), Offset = Vector3.new(0, 45, 0), Dir = Enum.NormalId.Bottom, Spread = Vector2.new(6, 6) },
	up = { Size = Vector3.new(160, 1, 160), Offset = Vector3.new(0, -18, 0), Dir = Enum.NormalId.Top, Spread = Vector2.new(15, 15) },
	side = { Size = Vector3.new(1, 90, 170), Offset = Vector3.new(-75, 25, 0), Dir = Enum.NormalId.Right, Spread = Vector2.new(8, 12) },
	float = { Size = Vector3.new(150, 60, 150), Offset = Vector3.new(0, 10, 0), Dir = Enum.NormalId.Top, Spread = Vector2.new(180, 180), Volume = true },
	toward = { Size = Vector3.new(170, 70, 170), Offset = Vector3.new(0, 10, 0), Dir = Enum.NormalId.Top, Spread = Vector2.new(180, 180), Volume = true },
}

local function buildLayers(w)
	clearLayers()
	for _, def in ipairs(w.Particles or {}) do
		local d = DIRS[def.Dir or "down"] or DIRS.down
		local part = SpaceFX.Part({ Name = "WeatherLayer", Size = d.Size, Transparency = 1 })
		local emitter = SpaceFX.Emitter(part, {
			Tex = def.Tex, Colors = def.Colors, Rate = (def.Rate or 30) * PARTICLE_SCALE,
			Speed = def.Speed or 10, Size = def.Size or 1, SizeStart = 1, SizeEnd = 0.6, Life = def.Life or 3,
			Spread = d.Spread, Direction = d.Dir, Spin = def.Spin or 30, Transparency = def.Transparency or 0,
			Stretch = def.Stretch and 2 or (def.Dir == "side" and 0.8 or nil),
			Shape = d.Volume and Enum.ParticleEmitterShape.Box or nil,
			Acceleration = def.Dir == "side" and Vector3.new(0, -8, 0) or (def.Dir == "float" and Vector3.new(0, 0.5, 0) or Vector3.zero),
			LightEmission = def.Tex == "Nebula" and 0.6 or 1,
		})
		table.insert(layerParts, { Part = part, Emitter = emitter, Def = def, Offset = d.Offset })
	end
end

---------------------------------------------------------------------
-- Big things in the sky (Props)
---------------------------------------------------------------------
local center = EventConfig.SkyCenter
local groundY = 901
task.spawn(function()
	groundY = SpaceFX.GroundAt(center.X, center.Z).Y
end)

local propBuilders = {}

-- flaming meteors streak across the sky and crash all over the map
propBuilders.meteors = function(w)
	local rocks = {}
	local nextAt = 0
	local api = {}
	function api.Update(now, dt, camPos)
		if now >= nextAt and #rocks < math.floor(9 * PARTICLE_SCALE + 1) then
			nextAt = now + rng:NextNumber(0.3, 0.9) / PARTICLE_SCALE
			local target = SpaceFX.GroundAt(camPos.X + rng:NextNumber(-170, 170), camPos.Z + rng:NextNumber(-170, 170), groundY)
			local start = target + Vector3.new(-170 + rng:NextNumber(-60, 60), 240 + rng:NextNumber(0, 80), 110 + rng:NextNumber(-60, 60))
			local size = rng:NextNumber(2.5, 6)
			local rock = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = start,
				Color = Color3.fromRGB(255, 170, 70), Material = Enum.Material.Neon })
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, size * 0.45, 0)
			a0.Parent = rock
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -size * 0.45, 0)
			a1.Parent = rock
			local trail = Instance.new("Trail")
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.Lifetime = 0.5
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 70, 30))
			trail.Transparency = NumberSequence.new(0, 1)
			trail.WidthScale = NumberSequence.new(1, 0.2)
			trail.Parent = rock
			SpaceFX.Emitter(rock, { Tex = "FIRE", Colors = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 70, 20) }, Rate = 40,
				Size = size * 0.9, Life = 0.5, Speed = 2, Spread = Vector2.new(180, 180) })
			table.insert(rocks, { Rock = rock, Start = start, Target = target, T = 0, Duration = rng:NextNumber(1.3, 2), Size = size })
		end
		for i = #rocks, 1, -1 do
			local m = rocks[i]
			m.T += dt / m.Duration
			if m.T >= 1 then
				local hit = m.Target
				SpaceFX.Disc(hit + Vector3.new(0, 0.3, 0), Color3.fromRGB(255, 140, 50), m.Size * 6, 0.6)
				SpaceFX.Shock(hit, Color3.fromRGB(255, 190, 90), m.Size, m.Size * 4, 0.5, 0.2, Enum.Material.Neon)
				local anchor = SpaceFX.Part({ Size = Vector3.one * 0.2, Position = hit, Transparency = 1 })
				local burst = SpaceFX.Emitter(anchor, { Tex = "FIRE", Colors = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 60, 20) },
					Rate = 0, Size = m.Size * 1.2, Life = 0.8, Speed = 18, Spread = Vector2.new(70, 70) })
				burst:Emit(18)
				Debris:AddItem(anchor, 2)
				if okAudio and (hit - camPos).Magnitude < 260 then
					Audio.Play("meteor_impact", { Position = hit, MinDistance = 30, MaxDistance = 300 })
				end
				m.Rock:Destroy()
				table.remove(rocks, i)
			else
				local eased = m.T * m.T * 0.5 + m.T * 0.5
				m.Rock.CFrame = CFrame.lookAt(m.Start:Lerp(m.Target, eased), m.Target) * CFrame.Angles(math.pi / 2, 0, 0)
			end
		end
	end
	function api.Destroy()
		for _, m in ipairs(rocks) do
			m.Rock:Destroy()
		end
	end
	return api
end

-- lightning strikes near you
propBuilders.lightning = function(w)
	local nextAt = os.clock() + 2
	local api = {}
	function api.Update(now, dt, camPos)
		if now < nextAt then
			return
		end
		nextAt = now + rng:NextNumber(1.2, 3.6)
		local target = SpaceFX.GroundAt(camPos.X + rng:NextNumber(-140, 140), camPos.Z + rng:NextNumber(-140, 140), groundY)
		local from = target + Vector3.new(rng:NextNumber(-60, 60), 230, rng:NextNumber(-60, 60))
		local color = rng:NextNumber() < 0.5 and Color3.fromRGB(255, 245, 170) or Color3.fromRGB(190, 230, 255)
		SpaceFX.Bolt(from, target, color, 0.9, 0.22)
		SpaceFX.Disc(target + Vector3.new(0, 0.3, 0), color, 26, 0.5)
		SpaceFX.Flash(color, 0.18, 0.4)
		local light = SpaceFX.Part({ Size = Vector3.one * 0.2, Position = target + Vector3.new(0, 10, 0), Transparency = 1 })
		local pl = Instance.new("PointLight")
		pl.Color = color
		pl.Range = 60
		pl.Brightness = 6
		pl.Parent = light
		tween(pl, 0.5, { Brightness = 0 })
		Debris:AddItem(light, 0.6)
		if okAudio then
			Audio.Play("thunder", { Position = target, MinDistance = 60, MaxDistance = 800 })
		end
	end
	function api.Destroy() end
	return api
end

-- the sun on the horizon, throwing out huge flares
propBuilders.flares = function(w)
	local pos = Vector3.new(center.X + 420, groundY + 230, center.Z - 330)
	local sun = SpaceFX.Part({ Name = "StormSun", Shape = Enum.PartType.Ball, Size = Vector3.one * 130, Position = pos,
		Color = Color3.fromRGB(255, 170, 50), Material = Enum.Material.Neon })
	SpaceFX.Emitter(sun, { Tex = "FIRE", Colors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 80, 20) }, Rate = 30,
		Size = 70, SizeEnd = 0.2, Life = 2.5, Speed = 25, Spread = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface })
	local flares = {}
	local nextAt = 0
	local api = {}
	function api.Update(now, dt)
		if now >= nextAt then
			nextAt = now + rng:NextNumber(2.5, 5)
			local a0 = Instance.new("Attachment")
			a0.Position = rng:NextUnitVector() * 62
			a0.Parent = sun
			local a1 = Instance.new("Attachment")
			a1.Position = (a0.Position + rng:NextUnitVector() * 70).Unit * 62
			a1.Parent = sun
			local beam = SpaceFX.Beam(a0, a1, { Color = Color3.fromRGB(255, 220, 90), Color2 = Color3.fromRGB(255, 80, 20), Tex = "Wisp",
				Width0 = 18, Width1 = 18, Curve0 = 0, Curve1 = 0, TextureSpeed = 1, Segments = 20 })
			table.insert(flares, { Beam = beam, A0 = a0, A1 = a1, Born = now })
		end
		for i = #flares, 1, -1 do
			local f = flares[i]
			local t = (now - f.Born) / 3
			if t >= 1 then
				f.Beam:Destroy()
				f.A0:Destroy()
				f.A1:Destroy()
				table.remove(flares, i)
			else
				local arc = math.sin(t * math.pi) * 160
				f.Beam.CurveSize0 = arc
				f.Beam.CurveSize1 = -arc
				f.Beam.Transparency = NumberSequence.new(t * t)
			end
		end
		sun.Size = Vector3.one * (130 + math.sin(now * 1.3) * 6)
	end
	function api.Destroy()
		sun:Destroy()
	end
	return api
end

-- a black hole vortex hanging over the map
propBuilders.vortex = function(w)
	local pos = Vector3.new(center.X, groundY + 260, center.Z)
	local core = SpaceFX.Part({ Name = "VortexCore", Shape = Enum.PartType.Ball, Size = Vector3.one * 70, Position = pos,
		Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic })
	local rings = {}
	for i, def in ipairs({
		{ D = 110, W = 0.05, C = Color3.fromRGB(255, 240, 220), C2 = Color3.fromRGB(255, 170, 70), Tilt = 0, Spin = 90 },
		{ D = 220, W = 0.18, C = Color3.fromRGB(255, 150, 50), C2 = Color3.fromRGB(190, 90, 255), Tilt = 14, Spin = 40 },
		{ D = 330, W = 0.1, C = Color3.fromRGB(190, 90, 255), C2 = Color3.fromRGB(255, 120, 200), Tilt = 14, Spin = 25 },
	}) do
		local plate, ctl = SpaceFX.Ring(def.C, def.C2, def.W, 3)
		plate.Size = Vector3.new(def.D, 0.05, def.D)
		rings[i] = { Plate = plate, Ctl = ctl, Def = def }
	end
	local swirl = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 300, Position = pos, Transparency = 1 })
	local e = SpaceFX.Emitter(swirl, { Tex = "SPARKLE", Colors = { Color3.fromRGB(255, 180, 90), Color3.fromRGB(190, 110, 255) },
		Rate = 60 * PARTICLE_SCALE, Size = 4, SizeEnd = 0.3, Life = 3, Speed = 45, Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface })
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	local api = {}
	function api.Update(now)
		for _, r in ipairs(rings) do
			r.Plate.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(r.Def.Tilt), 0, 0) * CFrame.Angles(0, math.rad(now * r.Def.Spin), 0)
			r.Ctl.Spin(now * 60)
		end
	end
	function api.Destroy()
		core:Destroy()
		swirl:Destroy()
		for _, r in ipairs(rings) do
			r.Plate:Destroy()
		end
	end
	api.Focus = pos
	return api
end

-- an alien eclipse: a black disc with a glowing green corona
propBuilders.eclipse = function(w)
	local pos = Vector3.new(center.X - 300, groundY + 260, center.Z - 380)
	local corona = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 120, Position = pos,
		Color = Color3.fromRGB(140, 255, 80), Material = Enum.Material.Neon, Transparency = 0.15 })
	local towardMap = (Vector3.new(center.X, groundY + 40, center.Z) - pos).Unit
	local disc = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 112, Position = pos + towardMap * 8,
		Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic })
	SpaceFX.Emitter(corona, { Tex = "Wisp", Colors = { Color3.fromRGB(150, 255, 90), Color3.fromRGB(170, 70, 255) }, Rate = 14,
		Size = 50, SizeEnd = 0.3, Life = 3, Speed = 12, Spread = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Spin = 40 })
	local plate, ctl = SpaceFX.Ring(Color3.fromRGB(150, 255, 90), Color3.fromRGB(190, 90, 255), 0.04, 4)
	plate.Size = Vector3.new(180, 0.05, 180)
	local api = {}
	function api.Update(now)
		plate.CFrame = CFrame.lookAt(pos, pos + towardMap) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, now * 0.4, 0)
		ctl.Spin(now * 40)
		corona.Transparency = 0.15 + math.sin(now * 2) * 0.08
	end
	function api.Destroy()
		corona:Destroy()
		disc:Destroy()
		plate:Destroy()
	end
	return api
end

-- a giant star that keeps exploding in waves of light
propBuilders.bigstar = function(w)
	local pos = Vector3.new(center.X + 260, groundY + 300, center.Z + 360)
	local star = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 50, Position = pos,
		Color = Color3.fromRGB(255, 250, 230), Material = Enum.Material.Neon })
	SpaceFX.Emitter(star, { Tex = "Glint", Colors = { Color3.new(1, 1, 1), Color3.fromRGB(255, 200, 100) }, Rate = 12,
		Size = 60, SizeEnd = 0.2, Life = 1.5, Speed = 10, Spread = Vector2.new(180, 180), Spin = 60 })
	local nextBoom = os.clock() + 3
	local api = {}
	function api.Update(now)
		local pulse = 1 + math.sin(now * 3) * 0.08
		star.Size = Vector3.one * 50 * pulse
		if now >= nextBoom then
			nextBoom = now + rng:NextNumber(6, 10)
			SpaceFX.Flash(Color3.fromRGB(255, 245, 220), 0.35, 1.2)
			SpaceFX.Shock(pos, Color3.fromRGB(255, 240, 200), 60, 900, 3, 0.3, Enum.Material.ForceField)
			task.delay(0.25, function()
				SpaceFX.Shock(pos, Color3.fromRGB(255, 170, 80), 60, 650, 2.5, 0.4, Enum.Material.ForceField)
			end)
			SpaceFX.Sound(WeatherConfig.Sounds.boom, 0.5)
			SpaceFX.Shake(1, 0.8)
		end
	end
	function api.Destroy()
		star:Destroy()
	end
	return api
end

-- rocks floating up around you (gravity storm)
propBuilders.debris = function(w)
	local rocks = {}
	local api = {}
	function api.Update(now, dt, camPos)
		if #rocks < math.floor(26 * PARTICLE_SCALE) then
			local size = rng:NextNumber(0.8, 3.5)
			local p = SpaceFX.Part({ Size = Vector3.new(size, size * rng:NextNumber(0.6, 1.1), size * rng:NextNumber(0.7, 1.3)),
				Position = SpaceFX.GroundAt(camPos.X + rng:NextNumber(-90, 90), camPos.Z + rng:NextNumber(-90, 90), groundY),
				Color = Color3.fromRGB(110, 100, 130), Material = Enum.Material.Slate })
			table.insert(rocks, { Part = p, Speed = rng:NextNumber(2, 7), Spin = rng:NextUnitVector() * rng:NextNumber(0.5, 2), Born = now, Life = rng:NextNumber(7, 12) })
		end
		for i = #rocks, 1, -1 do
			local r = rocks[i]
			local t = (now - r.Born) / r.Life
			if t >= 1 then
				r.Part:Destroy()
				table.remove(rocks, i)
			else
				r.Part.CFrame = (r.Part.CFrame + Vector3.new(0, r.Speed * dt, 0)) * CFrame.Angles(r.Spin.X * dt, r.Spin.Y * dt, r.Spin.Z * dt)
				r.Part.Transparency = t > 0.8 and (t - 0.8) * 5 or 0
			end
		end
	end
	function api.Destroy()
		for _, r in ipairs(rocks) do
			r.Part:Destroy()
		end
	end
	return api
end

-- huge aurora ribbons waving in the sky (nebula fog)
propBuilders.aurora = function(w)
	local anchor = SpaceFX.Part({ Size = Vector3.one, Position = Vector3.new(center.X, groundY + 180, center.Z), Transparency = 1 })
	local ribbons = {}
	for i = 1, 4 do
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-420, i * 18, -260 + i * 120)
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(420, i * 18 + 20, -200 + i * 110)
		a1.Parent = anchor
		local colors = i % 2 == 0 and { Color3.fromRGB(90, 255, 180), Color3.fromRGB(255, 120, 220) } or { Color3.fromRGB(255, 120, 220), Color3.fromRGB(140, 110, 255) }
		local beam = SpaceFX.Beam(a0, a1, { Color = colors[1], Color2 = colors[2], Tex = "Flow", Width0 = 70, Width1 = 70,
			TextureSpeed = 0.2, TextureLength = 1, Segments = 30, FaceCamera = false,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 1) }) })
		ribbons[i] = { Beam = beam, Seed = i * 1.7 }
	end
	local api = {}
	function api.Update(now)
		for _, r in ipairs(ribbons) do
			r.Beam.CurveSize0 = math.sin(now * 0.5 + r.Seed) * 140
			r.Beam.CurveSize1 = math.cos(now * 0.4 + r.Seed) * 140
		end
	end
	function api.Destroy()
		anchor:Destroy()
	end
	return api
end

---------------------------------------------------------------------
-- Ambient sound
---------------------------------------------------------------------
local ambient = nil -- { Sound, Group }
-- during a live event only the event's music plays, so the weather's sound goes quiet
local function ambientVolume()
	local phase = state:GetAttribute("LiveEventPhase") or ""
	return (phase == "countdown" or phase == "active") and 0 or 1
end
state:GetAttributeChangedSignal("LiveEventPhase"):Connect(function()
	if ambient then
		tween(ambient.Group, 2, { Volume = ambientVolume() })
	end
end)
local function setAmbient(id, volume)
	if ambient then
		local old = ambient
		ambient = nil
		tween(old.Group, 2.5, { Volume = 0 }).Completed:Connect(function()
			old.Sound:Destroy()
			old.Group:Destroy()
		end)
	end
	if not id then
		return
	end
	local group = Instance.new("SoundGroup")
	group.Name = "WeatherAmbience"
	group.Volume = 0
	group.Parent = SoundService:FindFirstChild("GameSfx") or SoundService
	local sound = Instance.new("Sound")
	sound.Name = "WeatherAmbient"
	sound.SoundId = id
	sound.Volume = volume or 0.4
	sound.Looped = true
	sound.SoundGroup = group
	sound.Parent = SoundService
	sound:Play()
	tween(group, 3, { Volume = ambientVolume() })
	ambient = { Sound = sound, Group = group }
end

---------------------------------------------------------------------
-- Putting it together
---------------------------------------------------------------------
local activeProps = {}
local currentId = nil

local function clearProps()
	for _, p in ipairs(activeProps) do
		pcall(p.Destroy)
	end
	table.clear(activeProps)
end

local function applyWeather()
	local id = state:GetAttribute("Weather") or "clear"
	if id == currentId then
		return
	end
	local first = currentId == nil
	currentId = id
	local w = WeatherConfig.Get(id) or WeatherConfig.Clear
	applyLighting(w)
	buildLayers(w)
	clearProps()
	for _, name in ipairs(w.Props or {}) do
		local build = propBuilders[name]
		if build then
			local ok, api = pcall(build, w)
			if ok and api then
				table.insert(activeProps, api)
			else
				warn("[WeatherClient] prop " .. name .. ": " .. tostring(api))
			end
		end
	end
	setAmbient(w.Ambient, w.AmbientVolume)
	if not first and id ~= "clear" and w.StartSound then
		SpaceFX.Sound(w.StartSound, 0.6)
	end
end
state:GetAttributeChangedSignal("Weather"):Connect(applyWeather)
task.defer(applyWeather)

-- gravity (weather + events can lower it; it only changes how YOUR character moves)
local function applyGravity()
	local g = state:GetAttribute("Gravity") or 1
	tween(workspace, 1.5, { Gravity = baseGravity * g })
end
state:GetAttributeChangedSignal("Gravity"):Connect(applyGravity)
applyGravity()

RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	for _, layer in ipairs(layerParts) do
		layer.Part.CFrame = CFrame.new(camPos + layer.Offset)
		if layer.Def.Dir == "toward" then
			-- pulled toward the vortex
			local focus = activeProps[1] and activeProps[1].Focus
			if focus then
				layer.Emitter.Acceleration = (focus - camPos).Unit * 35
			end
		end
	end
	local now = os.clock()
	for _, p in ipairs(activeProps) do
		local ok, err = pcall(p.Update, now, dt, camPos)
		if not ok then
			warn("[WeatherClient] " .. tostring(err))
			p.Update = function() end
		end
	end
end)

print("[WeatherClient] ready")
