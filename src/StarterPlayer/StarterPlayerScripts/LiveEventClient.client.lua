--[[
	LiveEventClient  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	The giant spectacles of the live events (WeatherServer runs them, EventConfig lists them):
	  blackhole   The Great Black Hole: tears open in the sky, spinning accretion disks, everything pulled in
	  ton618      TON-618: a monster quasar with jets across the whole sky; the entire atmosphere changes
	  meteor      Meteor Impact: a burning meteor grows in the sky during the countdown, then SLAMS into
	              the middle of the map (shockwave, camera shake). Grab the glowing shards around the crater!
	  solarflare  Mega Solar Flare: the sun swells on the horizon and waves of solar fire sweep the map
	  mothership  Alien Mothership: a huge ship hovers over the gardens and beams planets up
	During the countdown the thing slowly appears; when the event ends it fades away.

	Needs: EventConfig, WeatherConfig, SpaceFX (ReplicatedStorage), WeatherServer.
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
local EventConfig = require(ReplicatedStorage:WaitForChild("EventConfig"))
local WeatherConfig = require(ReplicatedStorage:WaitForChild("WeatherConfig"))
local SpaceFX = require(ReplicatedStorage:WaitForChild("SpaceFX"))
local ScreenFit = require(ReplicatedStorage:WaitForChild("ScreenFit"))
local weatherRemotes = ReplicatedStorage:WaitForChild("WeatherRemotes", 60)
local fxRemote = weatherRemotes and weatherRemotes:WaitForChild("EventFx", 30)

local rng = Random.new()
local LOW = ScreenFit.IsPhone() and 0.5 or 1
local rgb = Color3.fromRGB

local function now()
	return workspace:GetServerTimeNow()
end
local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.InOut), props)
	tw:Play()
	return tw
end

local center = EventConfig.SkyCenter
local groundY = 901
task.spawn(function()
	groundY = SpaceFX.GroundAt(center.X, center.Z).Y
end)

-- an extra colour correction + fog only events use (on top of the weather's)
local eventCC = Lighting:FindFirstChild("LiveEventLook") or Instance.new("ColorCorrectionEffect")
eventCC.Name = "LiveEventLook"
eventCC.Parent = Lighting

local function setLook(tint, brightness, saturation, contrast, seconds)
	tween(eventCC, seconds or 3, { TintColor = tint or Color3.new(1, 1, 1), Brightness = brightness or 0, Saturation = saturation or 0, Contrast = contrast or 0 })
end

---------------------------------------------------------------------
-- Ambient sound for the event
---------------------------------------------------------------------
local eventSound = nil
-- the event music is muted while you're at a shop (the shop keeps its own music)
local function eventVolume()
	return player:GetAttribute("InMusicZone") and 0 or 1
end
player:GetAttributeChangedSignal("InMusicZone"):Connect(function()
	if eventSound then
		tween(eventSound.Group, 1.2, { Volume = eventVolume() })
	end
end)
local function setEventSound(id, volume)
	if eventSound then
		local old = eventSound
		eventSound = nil
		tween(old.Group, 2, { Volume = 0 }).Completed:Connect(function()
			old.Sound:Destroy()
			old.Group:Destroy()
		end)
	end
	if not id then
		return
	end
	local group = Instance.new("SoundGroup")
	group.Name = "EventAmbience"
	group.Volume = 0
	group.Parent = SoundService:FindFirstChild("GameSfx") or SoundService
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.5
	sound.Looped = true
	sound.SoundGroup = group
	sound.Parent = SoundService
	sound:Play()
	tween(group, 2.5, { Volume = eventVolume() })
	eventSound = { Sound = sound, Group = group }
end

---------------------------------------------------------------------
-- Visuals. Each returns { Update(now, dt, phase, progress), Arrive(), Destroy() }
--   phase "countdown": progress 0 -> 1 as the countdown runs out
--   phase "active":    progress 0 -> 1 through the event
---------------------------------------------------------------------
local visuals = {}

local function ringSet(pos, defs)
	local rings = {}
	for i, d in ipairs(defs) do
		local plate, ctl = SpaceFX.Ring(d.C, d.C2, d.W, d.Glow or 3)
		rings[i] = { Plate = plate, Ctl = ctl, Def = d }
	end
	return rings
end
local function updateRings(rings, pos, t, scale)
	for _, r in ipairs(rings) do
		local d = r.Def
		local size = d.D * scale
		r.Plate.Size = Vector3.new(size, 0.05, size)
		r.Plate.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(d.Tilt or 0), math.rad(d.Yaw or 0), 0) * CFrame.Angles(0, math.rad(t * (d.Spin or 30)), 0)
		r.Ctl.Spin(t * 50)
	end
end

-- THE GREAT BLACK HOLE ---------------------------------------------
visuals.blackhole = function(event)
	local pos = Vector3.new(center.X, groundY + 330, center.Z - 60)
	local core = SpaceFX.Part({ Name = "GreatBlackHole", Shape = Enum.PartType.Ball, Size = Vector3.one, Position = pos,
		Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic })
	local lens = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one, Position = pos, Color = rgb(190, 110, 255),
		Material = Enum.Material.ForceField, Transparency = 0.3 })
	local rings = ringSet(pos, {
		{ D = 150, W = 0.035, C = rgb(255, 245, 225), C2 = rgb(255, 190, 90), Tilt = 0, Spin = 120, Glow = 5 },
		{ D = 300, W = 0.2, C = rgb(255, 150, 50), C2 = rgb(255, 230, 140), Tilt = 12, Spin = 45 },
		{ D = 430, W = 0.13, C = rgb(200, 90, 255), C2 = rgb(255, 140, 60), Tilt = 12, Spin = 30 },
		{ D = 560, W = 0.06, C = rgb(130, 80, 255), C2 = rgb(255, 120, 220), Tilt = 12, Spin = 18 },
	})
	local swirl = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 520, Position = pos, Transparency = 1 })
	local inward = SpaceFX.Emitter(swirl, { Tex = "SPARKLE", Colors = { rgb(255, 190, 100), rgb(190, 110, 255) }, Rate = 0,
		Size = 6, SizeEnd = 0.3, Life = 3.5, Speed = 70, Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface })
	inward.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	-- debris and dust rising off the ground toward it
	local riser = SpaceFX.Part({ Size = Vector3.new(260, 1, 260), Position = Vector3.new(center.X, groundY + 2, center.Z), Transparency = 1 })
	local rise = SpaceFX.Emitter(riser, { Tex = "Dust", Colors = { rgb(220, 180, 255), rgb(150, 90, 255) }, Rate = 0, Size = 1.5,
		Life = 6, Speed = 45, Spread = Vector2.new(8, 8), Acceleration = Vector3.new(0, 10, 0) })

	local scale = 0
	local api = {}
	function api.Update(t, dt, phase, progress)
		local target = phase == "countdown" and (0.08 + progress * 0.35) or phase == "leaving" and 0 or 1
		scale += (target - scale) * math.min(1, dt * 0.8)
		core.Size = Vector3.one * 110 * scale
		lens.Size = Vector3.one * 135 * scale * (1 + math.sin(t * 2) * 0.03)
		updateRings(rings, pos, t, scale)
		inward.Rate = phase == "active" and 90 * LOW or 15 * LOW * progress
		rise.Rate = phase == "active" and 40 * LOW or 0
	end
	function api.Arrive()
		SpaceFX.Flash(rgb(150, 80, 255), 0.4, 1.5)
		SpaceFX.Shock(pos, rgb(190, 110, 255), 100, 1400, 3, 0.3)
		SpaceFX.Shake(2, 1.5)
		setLook(rgb(205, 185, 255), -0.08, 0.1, 0.15, 3)
	end
	function api.Leave()
		setLook(nil, 0, 0, 0, 4)
	end
	function api.Destroy()
		for _, inst in ipairs({ core, lens, swirl, riser }) do
			inst:Destroy()
		end
		for _, r in ipairs(rings) do
			r.Plate:Destroy()
		end
	end
	return api
end

-- TON-618 -------------------------------------------------------------
visuals.ton618 = function(event)
	local pos = Vector3.new(center.X - 120, groundY + 420, center.Z - 380)
	local core = SpaceFX.Part({ Name = "TON618", Shape = Enum.PartType.Ball, Size = Vector3.one, Position = pos,
		Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic })
	local glow = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one, Position = pos, Color = rgb(255, 150, 60),
		Material = Enum.Material.ForceField, Transparency = 0.15 })
	local rings = ringSet(pos, {
		{ D = 240, W = 0.03, C = rgb(255, 255, 240), C2 = rgb(255, 220, 160), Tilt = 0, Yaw = 0, Spin = 160, Glow = 6 }, -- photon ring
		{ D = 520, W = 0.24, C = rgb(255, 180, 60), C2 = rgb(255, 245, 190), Tilt = 74, Spin = 70, Glow = 5 },
		{ D = 760, W = 0.16, C = rgb(255, 110, 40), C2 = rgb(255, 200, 90), Tilt = 74, Spin = 50 },
		{ D = 1000, W = 0.1, C = rgb(170, 70, 255), C2 = rgb(255, 120, 60), Tilt = 74, Spin = 32 },
		{ D = 1250, W = 0.05, C = rgb(110, 60, 255), C2 = rgb(255, 120, 200), Tilt = 74, Spin = 20 },
	})
	-- relativistic jets shooting across the sky
	local anchor = SpaceFX.Part({ Size = Vector3.one, Position = pos, Transparency = 1 })
	local c = Instance.new("Attachment")
	c.Parent = anchor
	local jets = {}
	for _, dir in ipairs({ 1, -1 }) do
		local tip = Instance.new("Attachment")
		tip.Position = Vector3.new(0, dir * 10, 0)
		tip.Parent = anchor
		local beam = SpaceFX.Beam(c, tip, { Color = rgb(190, 210, 255), Color2 = rgb(140, 90, 255), Tex = "Flow", Width0 = 30, Width1 = 120,
			TextureSpeed = 3, TextureLength = 1, Segments = 2,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.9) }) })
		table.insert(jets, { Beam = beam, Tip = tip, Dir = dir })
	end
	local swirl = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 900, Position = pos, Transparency = 1 })
	local inward = SpaceFX.Emitter(swirl, { Tex = "SPARKLE", Colors = { rgb(255, 210, 120), rgb(170, 80, 255) }, Rate = 0,
		Size = 10, SizeEnd = 0.3, Life = 4, Speed = 105, Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface })
	inward.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward

	local sky = Lighting:FindFirstChildOfClass("Sky")
	local savedSky = nil
	local scale = 0
	local api = {}
	function api.Update(t, dt, phase, progress)
		local target = phase == "countdown" and (0.05 + progress * 0.3) or phase == "leaving" and 0 or 1
		scale += (target - scale) * math.min(1, dt * 0.6)
		core.Size = Vector3.one * 200 * scale
		glow.Size = Vector3.one * 228 * scale * (1 + math.sin(t * 1.5) * 0.04)
		updateRings(rings, pos, t, scale)
		anchor.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(74 - 90), 0, 0)
		for _, j in ipairs(jets) do
			j.Tip.Position = Vector3.new(0, j.Dir * 1400 * scale * (0.92 + math.sin(t * 5) * 0.08), 0)
			j.Beam.Width0 = 30 * scale
			j.Beam.Width1 = 140 * scale
		end
		inward.Rate = phase == "active" and 120 * LOW or 0
	end
	function api.Arrive()
		SpaceFX.Flash(rgb(255, 200, 120), 0.7, 2.5)
		SpaceFX.Shock(pos, rgb(255, 190, 90), 200, 2600, 4, 0.2)
		task.delay(0.3, function()
			SpaceFX.Shock(pos, rgb(170, 80, 255), 200, 2000, 4, 0.35)
		end)
		SpaceFX.Shake(3.5, 2.5)
		SpaceFX.Sound(WeatherConfig.Sounds.boom, 0.9)
		-- the WHOLE atmosphere changes
		setLook(rgb(255, 205, 170), -0.05, 0.35, 0.25, 4)
		if sky and not savedSky then
			savedSky = {}
			for face, id in pairs(WeatherConfig.Skies.voidnebula) do
				savedSky[face] = sky[face]
				sky[face] = id
			end
		end
	end
	function api.Leave()
		setLook(nil, 0, 0, 0, 5)
		if sky and savedSky then
			-- only put the sky back if the weather didn't change it meanwhile
			for face, id in pairs(savedSky) do
				if sky[face] == WeatherConfig.Skies.voidnebula[face] then
					sky[face] = id
				end
			end
			savedSky = nil
		end
	end
	function api.Destroy()
		for _, inst in ipairs({ core, glow, anchor, swirl }) do
			inst:Destroy()
		end
		for _, r in ipairs(rings) do
			r.Plate:Destroy()
		end
	end
	return api
end

-- METEOR IMPACT ---------------------------------------------------------
visuals.meteor = function(event)
	local site = SpaceFX.GroundAt(EventConfig.CrashSite.X, EventConfig.CrashSite.Z, groundY)
	local from = site + Vector3.new(-700, 900, 450)
	local fallTime = 4.6
	local rock = SpaceFX.Part({ Name = "IncomingMeteor", Shape = Enum.PartType.Ball, Size = Vector3.one * 30, Position = from,
		Color = rgb(70, 50, 45), Material = Enum.Material.CrackedLava })
	local glow = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 40, Position = from, Color = rgb(255, 140, 50),
		Material = Enum.Material.ForceField, Transparency = 0.1 })
	local fire = SpaceFX.Emitter(glow, { Tex = "FIRE", Colors = { rgb(255, 230, 140), rgb(255, 70, 20) }, Rate = 60 * LOW,
		Size = 40, SizeEnd = 0.1, Life = 1.5, Speed = 6, Spread = Vector2.new(30, 30), Shape = Enum.ParticleEmitterShape.Sphere })
	local smoke = SpaceFX.Emitter(glow, { Tex = "SMOKE", Colors = { rgb(80, 60, 55), rgb(40, 30, 30) }, Rate = 20 * LOW,
		Size = 50, SizeStart = 0.5, SizeEnd = 1.5, Life = 4, Speed = 2, Transparency = 0.4, LightEmission = 0, Spread = Vector2.new(30, 30) })
	local warning = SpaceFX.Part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 50, 50),
		CFrame = CFrame.new(site + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(255, 60, 40), Transparency = 1 })
	local warnRing, warnCtl = SpaceFX.Ring(rgb(255, 80, 40), rgb(255, 220, 90), 0.05, 4)
	warnRing.Size = Vector3.new(56, 0.05, 56)
	warnRing.CFrame = CFrame.new(site + Vector3.new(0, 0.6, 0))
	local landed = false
	local startTime = nil
	local api = {}
	function api.Update(t, dt, phase, progress)
		if phase == "countdown" then
			-- a burning dot far away, slowly getting bigger
			local far = site + Vector3.new(-1400, 1500, 900)
			local p = far:Lerp(from, progress * 0.4)
			rock.Position = p
			glow.Position = p
			rock.Size = Vector3.one * (8 + progress * 16)
			glow.Size = Vector3.one * (12 + progress * 22)
			warning.Transparency = 0.55 + math.sin(t * 6) * 0.25
			warnCtl.SetTransparency(0.2 + math.sin(t * 6) * 0.2)
			warnCtl.Spin(t * 90)
		elseif phase == "active" and not landed then
			startTime = startTime or (state:GetAttribute("LiveEventStart") or t)
			local k = math.clamp((t - startTime) / fallTime, 0, 1)
			if t - startTime > fallTime + 2 then
				-- joined after it already landed: no show, just tidy up
				landed = true
				api.Destroy()
				return
			end
			local eased = k * k
			local p = from:Lerp(site + Vector3.new(0, 6, 0), eased)
			rock.CFrame = CFrame.lookAt(p, site) * CFrame.Angles(t * 2, 0, 0)
			glow.Position = p
			rock.Size = Vector3.one * 30
			glow.Size = Vector3.one * (40 + k * 25)
			warning.Transparency = 0.3 + math.sin(t * 14) * 0.25
			warnCtl.SetTransparency(0)
			warnCtl.Spin(t * 300)
			if k >= 1 then
				landed = true
				api.Impact()
			end
		end
	end
	function api.Impact()
		rock:Destroy()
		glow:Destroy()
		warning:Destroy()
		warnRing:Destroy()
		local camera = workspace.CurrentCamera
		local distance = camera and (camera.CFrame.Position - site).Magnitude or 100
		SpaceFX.Flash(rgb(255, 210, 150), 0.8, 1.8)
		SpaceFX.Shake(math.clamp(6 - distance / 60, 1, 6), 1.8)
		SpaceFX.Shock(site, rgb(255, 230, 160), 10, 160, 0.8, 0, Enum.Material.Neon)
		SpaceFX.Shock(site, rgb(255, 120, 40), 10, 420, 2.2, 0.2)
		SpaceFX.Disc(site + Vector3.new(0, 0.5, 0), rgb(255, 150, 60), 520, 2.5, 0.1)
		SpaceFX.Sound(WeatherConfig.Sounds.boom, 1, { Position = site, MinDistance = 120, MaxDistance = 2000 })
		SpaceFX.Sound(WeatherConfig.Sounds.rumble, 0.6)
		local anchor = SpaceFX.Part({ Size = Vector3.one, Position = site + Vector3.new(0, 4, 0), Transparency = 1 })
		SpaceFX.Emitter(anchor, { Tex = "FIRE", Colors = { rgb(255, 230, 140), rgb(255, 60, 20) }, Rate = 0, Size = 22, SizeEnd = 0.1,
			Life = 1.6, Speed = 70, Spread = Vector2.new(80, 80) }):Emit(math.floor(80 * LOW))
		SpaceFX.Emitter(anchor, { Tex = "SMOKE", Colors = { rgb(90, 70, 60), rgb(40, 30, 30) }, Rate = 0, Size = 30, SizeStart = 0.6, SizeEnd = 2,
			Life = 5, Speed = 40, Spread = Vector2.new(85, 85), LightEmission = 0, Transparency = 0.3, Drag = 1 }):Emit(math.floor(40 * LOW))
		SpaceFX.Emitter(anchor, { Tex = "SPARKLE", Colors = { rgb(255, 240, 180), rgb(255, 150, 60) }, Rate = 0, Size = 3, Life = 2.5,
			Speed = 110, Spread = Vector2.new(70, 70), Acceleration = Vector3.new(0, -60, 0) }):Emit(math.floor(120 * LOW))
		Debris:AddItem(anchor, 6)
	end
	function api.Arrive() end
	function api.Leave() end
	function api.Destroy()
		for _, inst in ipairs({ rock, glow, warning, warnRing }) do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end
	return api
end

-- MEGA SOLAR FLARE ------------------------------------------------------
visuals.solarflare = function(event)
	local pos = Vector3.new(center.X + 520, groundY + 160, center.Z - 120)
	local sun = SpaceFX.Part({ Name = "FlareSun", Shape = Enum.PartType.Ball, Size = Vector3.one, Position = pos,
		Color = rgb(255, 190, 60), Material = Enum.Material.Neon })
	local corona = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one, Position = pos, Color = rgb(255, 120, 30),
		Material = Enum.Material.ForceField, Transparency = 0.2 })
	local flames = SpaceFX.Emitter(sun, { Tex = "FIRE", Colors = { rgb(255, 240, 150), rgb(255, 70, 20) }, Rate = 0, Size = 110,
		SizeEnd = 0.1, Life = 2.5, Speed = 40, Spread = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface })
	local heat = SpaceFX.Part({ Size = Vector3.new(220, 1, 220), Position = Vector3.new(center.X, groundY + 1, center.Z), Transparency = 1 })
	local embers = SpaceFX.Emitter(heat, { Tex = "Wisp", Colors = { rgb(255, 200, 80), rgb(255, 90, 30) }, Rate = 0, Size = 2,
		Life = 4, Speed = 8, Spread = Vector2.new(20, 20), Spin = 120 })
	local scale = 0
	local nextWave = 0
	local api = {}
	local function wave()
		-- a wall of solar fire rolls across the whole map
		local dir = (Vector3.new(center.X, pos.Y, center.Z) - pos) * Vector3.new(1, 0, 1)
		dir = dir.Unit
		local wall = SpaceFX.Part({ Size = Vector3.new(900, 260, 12), Color = rgb(255, 150, 40), Material = Enum.Material.ForceField,
			Transparency = 0.25, CFrame = CFrame.lookAt(pos * Vector3.new(1, 0, 1) + Vector3.new(0, groundY + 100, 0), pos * Vector3.new(1, 0, 1) + Vector3.new(0, groundY + 100, 0) + dir) })
		local goal = wall.CFrame + dir * 1100
		tween(wall, 6, { CFrame = goal, Transparency = 0.9 }, Enum.EasingStyle.Linear)
		Debris:AddItem(wall, 6.2)
		SpaceFX.Sound(WeatherConfig.Sounds.whoosh, 0.7)
		-- when it passes over you: a hot flash
		task.delay(3, function()
			SpaceFX.Flash(rgb(255, 180, 90), 0.45, 1.5)
			SpaceFX.Shake(1.2, 1)
		end)
	end
	function api.Update(t, dt, phase, progress)
		local target = phase == "countdown" and (0.3 + progress * 0.4) or phase == "leaving" and 0 or 1
		scale += (target - scale) * math.min(1, dt * 0.7)
		local pulse = 1 + math.sin(t * 2.2) * 0.04
		sun.Size = Vector3.one * 200 * scale * pulse
		corona.Size = Vector3.one * 260 * scale * pulse
		flames.Rate = phase == "active" and 40 * LOW or 10 * LOW
		embers.Rate = phase == "active" and 70 * LOW or 0
		if phase == "active" and t >= nextWave then
			nextWave = t + 22
			wave()
		end
	end
	function api.Arrive()
		SpaceFX.Flash(rgb(255, 230, 160), 0.8, 2)
		SpaceFX.Shock(pos, rgb(255, 200, 80), 200, 1800, 3, 0.25)
		SpaceFX.Shake(2.2, 1.5)
		setLook(rgb(255, 225, 185), 0.06, 0.25, 0.08, 2.5)
		nextWave = 0
	end
	function api.Leave()
		setLook(nil, 0, 0, 0, 4)
	end
	function api.Destroy()
		for _, inst in ipairs({ sun, corona, heat }) do
			inst:Destroy()
		end
	end
	return api
end

-- ALIEN MOTHERSHIP ------------------------------------------------------
visuals.mothership = function(event)
	local hover = Vector3.new(center.X, groundY + 140, center.Z)
	local model = Instance.new("Model")
	model.Name = "AlienMothership"
	local function piece(props)
		props.Parent = model
		return SpaceFX.Part(props)
	end
	local hull = piece({ Name = "Hull", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 190, 190), Color = rgb(150, 158, 180), Material = Enum.Material.DiamondPlate })
	local rim = piece({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 205, 205), Color = rgb(95, 100, 120), Material = Enum.Material.Metal })
	local dome = piece({ Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.new(80, 80, 80), Color = rgb(120, 255, 140), Material = Enum.Material.Glass, Transparency = 0.35 })
	local belly = piece({ Name = "Belly", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 70, 70), Color = rgb(120, 255, 120), Material = Enum.Material.Neon })
	local lights = {}
	for i = 1, 16 do
		lights[i] = piece({ Name = "Light", Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Color = rgb(150, 255, 120) })
	end
	local glowRing, glowCtl = SpaceFX.Ring(rgb(120, 255, 120), rgb(190, 90, 255), 0.04, 5, model)
	model.Parent = SpaceFX.Folder
	local hum = SpaceFX.Emitter(belly, { Tex = "Quantum", Colors = { rgb(140, 255, 120), rgb(190, 90, 255) }, Rate = 6 * LOW, Size = 8,
		Life = 2.5, Speed = 12, Spread = Vector2.new(25, 25), Direction = Enum.NormalId.Left, Spin = 90 })

	local y = 900 -- starts high above and descends
	local beams = {}
	local api = {}
	function api.Update(t, dt, phase, progress)
		local targetY = phase == "countdown" and (hover.Y + 600 - progress * 300) or phase == "leaving" and (hover.Y + 900) or hover.Y
		y += (targetY - y) * math.min(1, dt * 0.5)
		local base = CFrame.new(hover.X + math.sin(t * 0.2) * 30, y + math.sin(t * 0.8) * 3, hover.Z + math.cos(t * 0.17) * 30) * CFrame.Angles(0, t * 0.15, 0)
		hull.CFrame = base * CFrame.Angles(0, 0, math.pi / 2)
		rim.CFrame = base * CFrame.new(0, -3, 0) * CFrame.Angles(0, 0, math.pi / 2)
		dome.CFrame = base * CFrame.new(0, 14, 0)
		belly.CFrame = base * CFrame.new(0, -9, 0) * CFrame.Angles(0, 0, math.pi / 2)
		belly.Color = rgb(120, 255, 120):Lerp(rgb(190, 90, 255), (math.sin(t * 2) + 1) / 2)
		glowRing.Size = Vector3.new(214, 0.05, 214)
		glowRing.CFrame = base * CFrame.new(0, -4, 0)
		glowCtl.Spin(t * 120)
		for i, l in ipairs(lights) do
			local a = (i / #lights) * math.pi * 2 + t * 0.8
			l.CFrame = base * CFrame.new(math.cos(a) * 100, -2, math.sin(a) * 100)
			local on = (math.floor(t * 6) + i) % 4 == 0
			l.Color = on and rgb(255, 255, 255) or rgb(150, 255, 120)
		end
		for i = #beams, 1, -1 do
			local b = beams[i]
			local k = (os.clock() - b.Born) / 2.6
			if k >= 1 or not b.Target.Parent then
				b.Part:Destroy()
				table.remove(beams, i)
			else
				local top = (base * CFrame.new(0, -10, 0)).Position
				local bottom = b.Target.Position
				local length = (top - bottom).Magnitude
				local width = b.Width * math.sin(k * math.pi)
				b.Part.Size = Vector3.new(length, width, width)
				b.Part.CFrame = CFrame.lookAt((top + bottom) / 2, bottom) * CFrame.Angles(0, math.pi / 2, 0)
				b.Part.Transparency = 0.35 + k * 0.3
			end
		end
	end
	function api.Beam(target)
		local body = target and (target.PrimaryPart or target:FindFirstChild("Body"))
		if not body then
			return
		end
		local r = target:GetAttribute("BodyRadius") or 3
		local part = SpaceFX.Part({ Name = "TractorBeam", Shape = Enum.PartType.Cylinder, Size = Vector3.one, Color = rgb(120, 255, 140),
			Material = Enum.Material.ForceField, Transparency = 0.4 })
		table.insert(beams, { Part = part, Target = body, Born = os.clock(), Width = math.max(r * 3, 10) })
		local anchor = SpaceFX.Part({ Size = Vector3.one, Position = body.Position, Transparency = 1 })
		SpaceFX.Emitter(anchor, { Tex = "Quantum", Colors = { rgb(140, 255, 120), rgb(190, 90, 255) }, Rate = 0, Size = r * 0.6,
			Life = 2, Speed = 25, Spread = Vector2.new(15, 15), Spin = 120 }):Emit(25)
		Debris:AddItem(anchor, 3)
		SpaceFX.Sound("rbxassetid://100230209655518", 0.6, { Position = body.Position, MinDistance = 30, MaxDistance = 400, Life = 4 })
	end
	function api.Arrive()
		SpaceFX.Flash(rgb(160, 255, 140), 0.35, 1.5)
		SpaceFX.Shake(1.5, 1.2)
		setLook(rgb(215, 255, 215), -0.03, 0.15, 0.08, 3)
	end
	function api.Leave()
		setLook(nil, 0, 0, 0, 4)
	end
	function api.Destroy()
		model:Destroy()
		for _, b in ipairs(beams) do
			b.Part:Destroy()
		end
	end
	return api
end

---------------------------------------------------------------------
-- Running whatever event is on
---------------------------------------------------------------------
local current = nil -- { Id, Event, Visual, Phase }
local leaving = {}  -- events that just ended: they shrink / fly away, then get cleaned up

local function stopCurrent()
	if not current then
		return
	end
	local old = current
	current = nil
	pcall(old.Visual.Leave)
	setEventSound(nil)
	old.Phase = "leaving"
	table.insert(leaving, old)
	task.delay(5, function()
		local i = table.find(leaving, old)
		if i then
			table.remove(leaving, i)
		end
		pcall(old.Visual.Destroy)
	end)
end

local function sync()
	local id = state:GetAttribute("LiveEvent") or ""
	local phase = state:GetAttribute("LiveEventPhase") or ""
	if id == "" or phase == "" or phase == "ended" then
		stopCurrent()
		return
	end
	local event = EventConfig.Get(id)
	if not event then
		return
	end
	if not current or current.Id ~= id then
		stopCurrent()
		local build = visuals[event.Visual]
		if not build then
			return
		end
		local ok, visual = pcall(build, event)
		if not ok then
			warn("[LiveEventClient] " .. tostring(visual))
			return
		end
		current = { Id = id, Event = event, Visual = visual, Phase = phase }
		setEventSound(event.Sound, 0.45)
		if phase == "active" then
			pcall(visual.Arrive)
		end
	elseif current.Phase ~= phase then
		current.Phase = phase
		if phase == "active" then
			pcall(current.Visual.Arrive)
		end
	end
end
state:GetAttributeChangedSignal("LiveEvent"):Connect(sync)
state:GetAttributeChangedSignal("LiveEventPhase"):Connect(sync)
task.defer(sync)

RunService.RenderStepped:Connect(function(dt)
	for _, old in ipairs(leaving) do
		pcall(old.Visual.Update, now(), dt, "leaving", 1)
	end
	if not current then
		return
	end
	local t = now()
	local startAt = state:GetAttribute("LiveEventStart") or t
	local untilAt = state:GetAttribute("LiveEventUntil") or t
	local progress
	if current.Phase == "countdown" then
		local total = math.max(1, EventConfig.Countdown)
		progress = math.clamp(1 - (startAt - t) / total, 0, 1)
	else
		progress = math.clamp((t - startAt) / math.max(1, untilAt - startAt), 0, 1)
	end
	local ok, err = pcall(current.Visual.Update, t, dt, current.Phase, progress)
	if not ok then
		warn("[LiveEventClient] " .. tostring(err))
		current.Visual.Update = function() end
	end
end)

---------------------------------------------------------------------
-- Server effects: alien beams, meteor shards you already grabbed
---------------------------------------------------------------------
if fxRemote then
	fxRemote.OnClientEvent:Connect(function(kind, a)
		if kind == "beam" and current and current.Visual.Beam then
			current.Visual.Beam(a)
		end
	end)
end

-- shards you already took fade away (for you only)
local function watchShard(shard)
	if not shard:IsA("BasePart") or not shard:GetAttribute("MeteorShard") then
		return
	end
	local key = "C" .. player.UserId
	local spin = SpaceFX.Emitter(shard, { Tex = "Star", Colors = { rgb(255, 240, 160), rgb(255, 160, 60) }, Rate = 6, Size = 1.6,
		Life = 1.2, Speed = 2, Spread = Vector2.new(180, 180), Spin = 120 })
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 190, 80)
	light.Range = 12
	light.Brightness = 2
	light.Parent = shard
	local function check()
		if shard:GetAttribute(key) then
			local prompt = shard:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = false
			end
			spin.Enabled = false
			light.Enabled = false
			shard.LocalTransparencyModifier = 0.85
		end
	end
	shard:GetAttributeChangedSignal(key):Connect(check)
	check()
end
local eventFolder = workspace:FindFirstChild("LiveEventFX")
local function hookFolder(f)
	f.DescendantAdded:Connect(function(d)
		task.defer(watchShard, d)
	end)
	for _, d in ipairs(f:GetDescendants()) do
		watchShard(d)
	end
end
if eventFolder then
	hookFolder(eventFolder)
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "LiveEventFX" then
		hookFolder(child)
	end
end)

print("[LiveEventClient] ready")
