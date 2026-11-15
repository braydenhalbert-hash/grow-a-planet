--[[
	SprinklerModel  (ModuleScript)  -- ReplicatedStorage

	Builds every sprinkler's 3D model, its animation and its look/effect settings.
	Used by SprinklerServer (the real ones), SprinklerClient (placement preview + effects)
	and SeedShopUI (the 3D picture in the gear shop), so they always match.

	Rarity ladder (each step looks clearly better than the one before):
	  Common -> Uncommon -> Rare -> Epic -> Legendary -> Mythic -> Divine -> Celestial

	SprinklerModel.Build(gear, cframe, ghost) -> model    PrimaryPart "Base" (on the ground), "Head" (nozzles)
	SprinklerModel.Animate(model, t)                      turns rings, moves planets/crystals (client)
	SprinklerModel.Fx(gearId) -> table                    effect settings for SprinklerClient
	SprinklerModel.RangeCircle(radius, parent) -> circle  green circle on the ground (client)

	Everything is made of plain parts + flat ring adornments (no meshes, no uploads) and models
	stream in as one piece, so they stay light on phones.
]]

local SprinklerModel = {}

---------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------
local rgb = Color3.fromRGB
SprinklerModel.GREEN = rgb(70, 255, 95)
local GREEN = SprinklerModel.GREEN
local C = {
	Green = GREEN, Cyan = rgb(80, 230, 255), Blue = rgb(60, 140, 255), DeepBlue = rgb(40, 80, 255),
	Purple = rgb(170, 80, 255), Violet = rgb(120, 60, 255), Pink = rgb(255, 90, 220), Magenta = rgb(255, 60, 170),
	Orange = rgb(255, 140, 40), Fire = rgb(255, 90, 30), Gold = rgb(255, 200, 70), Yellow = rgb(255, 225, 90),
	White = rgb(240, 245, 255), Red = rgb(255, 70, 60), Teal = rgb(60, 255, 200),
	Metal = rgb(34, 37, 44), Dark = rgb(18, 19, 23), Grey = rgb(176, 182, 192), Steel = rgb(120, 126, 136),
	GoldMetal = rgb(214, 160, 64), Silver = rgb(200, 206, 216), Bronze = rgb(176, 120, 60), Black = rgb(0, 0, 0),
	Rock = rgb(70, 62, 58),
}
SprinklerModel.Colors = C
local METAL_COLORS = { [C.Metal] = true, [C.Dark] = true, [C.Grey] = true, [C.Steel] = true, [C.GoldMetal] = true, [C.Silver] = true, [C.Bronze] = true }

SprinklerModel.RarityColor = {
	Common = rgb(165, 165, 180), Uncommon = rgb(90, 210, 120), Rare = rgb(80, 150, 255), Epic = rgb(200, 90, 255),
	Legendary = rgb(255, 175, 60), Mythic = rgb(255, 70, 120), Divine = rgb(255, 230, 140), Celestial = rgb(120, 240, 255),
}
SprinklerModel.RarityTier = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Divine = 7, Celestial = 8 }

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local FLAT = CFrame.Angles(math.rad(90), 0, 0)    -- ring adornments point along Z; this lays them flat
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder parts lie on X; this stands them up
local SELF_AXIS = Vector3.new(0.35, 1, 0.2).Unit  -- tumble axis for rocks/crystals
local Y = Vector3.yAxis

local function seq(a, b)
	return ColorSequence.new(a, b or a)
end

---------------------------------------------------------------------
-- Builder: every piece is placed relative to the ground centre ("origin").
-- Animated pieces store how they move as attributes; Animate() reads them.
---------------------------------------------------------------------
local B = {}
B.__index = B

local function newBuilder(model, origin, ghost, icon)
	local self = setmetatable({ model = model, origin = origin, ghost = ghost, icon = icon }, B)
	local o = Instance.new("Part")
	o.Name = "Origin"
	o.Size = Vector3.new(0.2, 0.2, 0.2)
	o.Transparency = 1
	o.Anchored, o.CanCollide, o.CanQuery, o.CanTouch, o.CastShadow = true, false, false, false, false
	o.CFrame = origin
	o.Parent = model
	self.originPart = o
	return self
end

function B:part(name, shape, size, rel, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Color = color or C.Metal
	p.Material = material or Enum.Material.SmoothPlastic
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	if self.ghost and p.Transparency < 1 then
		p.Material = Enum.Material.Neon
		p.Color = GREEN
		p.Transparency = 0.62
	end
	p.CFrame = self.origin * rel
	p.Parent = self.model
	return p
end

function B:wedge(name, size, rel, color, material)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if self.ghost then
		p.Material, p.Color, p.Transparency = Enum.Material.Neon, GREEN, 0.62
	end
	p.CFrame = self.origin * rel
	p.Parent = self.model
	return p
end

-- upright cylinder: h tall, d wide, centre at height y (or a full CFrame)
function B:cyl(name, h, d, at, color, material, props)
	local rel = typeof(at) == "number" and CFrame.new(0, at, 0) or at
	return self:part(name, Enum.PartType.Cylinder, Vector3.new(h, d, d), rel * UPRIGHT, color, material, props)
end

function B:ball(name, d, at, color, material, props)
	local rel = typeof(at) == "number" and CFrame.new(0, at, 0) or (typeof(at) == "Vector3" and CFrame.new(at) or at)
	return self:part(name, Enum.PartType.Ball, Vector3.one * d, rel, color, material, props)
end

function B:neon(name, d, at, color, transparency)
	return self:ball(name, d, at, color, Enum.Material.Neon, { Transparency = transparency or 0 })
end

-- make a part move: it sits at Rel inside a frame (Piv) that turns around Ax at Spd rad/s
--   opts: Piv, Rel, Ax, Spd, Ph, Self (tumble speed), Bob (height), BobSpd, Pulse (size %), PulseSpd
function B:anim(obj, opts)
	obj:SetAttribute("Anim", true)
	obj:SetAttribute("Piv", opts.Piv or CFrame.new())
	obj:SetAttribute("Rel", opts.Rel or CFrame.new())
	obj:SetAttribute("Ax", opts.Ax or Y)
	obj:SetAttribute("Spd", opts.Spd or 0)
	obj:SetAttribute("Ph", opts.Ph or 0)
	if opts.Self then
		obj:SetAttribute("Self", opts.Self)
	end
	if opts.Bob then
		obj:SetAttribute("Bob", opts.Bob)
		obj:SetAttribute("BobSpd", opts.BobSpd or 1.5)
	end
	if opts.Pulse and obj:IsA("BasePart") then
		obj:SetAttribute("Pulse", opts.Pulse)
		obj:SetAttribute("PulseSpd", opts.PulseSpd or 3)
		obj:SetAttribute("Sz", obj.Size)
	end
	return obj
end

-- a flat ring (annulus) drawn with a handle adornment: cheap, crisp, any size
function B:ring(R, width, thick, color, transparency, opts)
	opts = opts or {}
	if self.icon then
		-- shop pictures (ViewportFrames can't show adornments): build the ring from block segments
		if (transparency or 0) >= 0.7 then
			return nil
		end
		local n = R > 2 and 18 or 14
		local mid = R - width / 2
		local chord = 2 * math.pi * mid / n * 1.06
		for k = 1, n do
			local rel = (opts.Rel or CFrame.new()) * CFrame.Angles(0, (k - 1) * math.pi * 2 / n, 0) * CFrame.new(mid, 0, 0)
			local seg = self:part("RingSeg", Enum.PartType.Block, Vector3.new(width, thick, chord), (opts.Piv or CFrame.new()) * rel, color,
				METAL_COLORS[color] and Enum.Material.Metal or Enum.Material.Neon, { Transparency = transparency or 0 })
			self:anim(seg, { Piv = opts.Piv or CFrame.new(), Rel = rel, Ax = opts.Ax, Spd = opts.Spd, Ph = opts.Ph })
		end
		return nil
	end
	local a = Instance.new("CylinderHandleAdornment")
	a.Name = "Ring"
	a.Adornee = self.originPart
	a.Radius = R
	a.InnerRadius = math.max(0, R - width)
	a.Height = thick
	a.Color3 = self.ghost and GREEN or color
	a.Transparency = self.ghost and 0.5 or (transparency or 0)
	a.AlwaysOnTop = false
	a.ZIndex = 0
	self:anim(a, { Piv = opts.Piv or CFrame.new(), Rel = opts.Rel or CFrame.new(), Ax = opts.Ax, Spd = opts.Spd, Ph = opts.Ph })
	a.CFrame = (opts.Piv or CFrame.new()) * (opts.Rel or CFrame.new()) * FLAT
	a.Parent = self.originPart
	return a
end

-- a metal track with a neon line in it and a soft glow: the signature ring of every sprinkler
function B:track(R, metal, line, opts)
	opts = opts or {}
	local w = opts.Width or 0.22
	self:ring(R, w, opts.Thick or 0.16, metal, 0, opts)
	self:ring(R - w - 0.01, 0.13, (opts.Thick or 0.16) * 0.65, line, 0, opts)
	if opts.Glow ~= false then
		self:ring(R + 0.12, w + 0.4, 0.03, line, 0.75, opts)
	end
end

-- something riding a ring: centre frame `piv` (position + tilt), radius R
function B:orbit(part, piv, R, spd, ph, extra)
	local o = { Piv = piv, Rel = CFrame.new(R, 0, 0), Spd = spd, Ph = ph }
	if extra then
		for k, v in pairs(extra) do
			o[k] = v
		end
	end
	return self:anim(part, o)
end

-- ticks/pods fixed on a ring so you can see it turn (mechanical look)
function B:teeth(n, piv, R, size, color, material, spd)
	for i = 1, n do
		local p = self:part("Tooth", Enum.PartType.Block, size, piv, color, material)
		self:anim(p, { Piv = piv, Rel = CFrame.new(R, 0, 0), Spd = spd, Ph = (i - 1) * math.pi * 2 / n })
	end
end

-- crystal shard: a tall prism with a gem tip (2 parts). `rel` = base of the shard, pointing along its +Y
function B:crystal(rel, h, w, color, opts)
	opts = opts or {}
	local mat = opts.Glass and Enum.Material.Glass or Enum.Material.Neon
	local tr = opts.Transparency or (opts.Glass and 0.25 or 0.15)
	local body = self:part("Crystal", Enum.PartType.Block, Vector3.new(w, h, w), rel * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0), color, mat, { Transparency = tr })
	local tipSize = w * 0.72
	local tip = self:part("Crystal", Enum.PartType.Block, Vector3.one * tipSize, rel * CFrame.new(0, h, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), color, mat, { Transparency = tr })
	if opts.Anim then
		local a = opts.Anim
		self:anim(body, { Piv = a.Piv, Rel = a.Rel * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0), Ax = a.Ax, Spd = a.Spd, Ph = a.Ph, Bob = a.Bob, BobSpd = a.BobSpd })
		self:anim(tip, { Piv = a.Piv, Rel = a.Rel * CFrame.new(0, h, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Ax = a.Ax, Spd = a.Spd, Ph = a.Ph, Bob = a.Bob, BobSpd = a.BobSpd })
	end
	return body, tip
end

-- small floating gem (one rotated cube)
function B:gem(at, size, color, opts)
	local g = self:part("Gem", Enum.PartType.Block, Vector3.one * size, at * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), color, Enum.Material.Neon, { Transparency = 0.1 })
	return g
end

function B:emitter(parent, props)
	if self.ghost then
		return nil
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "SFX"
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.LightInfluence = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

function B:light(parent, color, range, brightness)
	if self.ghost then
		return
	end
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 10
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parent
end

---------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------
-- Pedestal. o = { W, H, Tiers, Accent, Metal, Trim, ColD, Glass, Core (tube colour), Bands, Strips, Spikes, SpikeColor, Fins }
-- returns the height of its top
local function pedestal(b, o)
	local W, H = o.W, o.H
	local metal, trim, accent = o.Metal or C.Metal, o.Trim or C.Dark, o.Accent or GREEN
	b:cyl("FootGlow", 0.08, W + 0.14, 0.04, accent, Enum.Material.Neon)
	local y = 0
	for i = 1, (o.Tiers or 1) do
		local d = W * (1 - 0.2 * (i - 1))
		local h = i == 1 and 0.32 or 0.24
		local p = b:cyl(i == 1 and "Base" or "Tier", h, d, y + h / 2, i % 2 == 1 and metal or trim, Enum.Material.Metal)
		if i == 1 then
			b.base = p
		end
		y += h
		b:cyl("TierGlow", 0.06, d * 0.82, y + 0.02, accent, Enum.Material.Neon)
	end
	-- buttresses / claws around the base
	if o.Spikes then
		for i = 1, o.Spikes do
			local a = (i - 1) * math.pi * 2 / o.Spikes + math.pi / o.Spikes
			b:wedge("Claw", Vector3.new(0.34, 0.75, 1.05), CFrame.Angles(0, a, 0) * CFrame.new(0, 0.37, -(W / 2 - 0.05)), o.SpikeColor or trim, Enum.Material.Metal)
			b:neon("ClawTip", 0.2, CFrame.Angles(0, a, 0) * CFrame.new(0, 0.12, -(W / 2 + 0.5)), accent)
		end
	end
	-- column
	local colD = o.ColD or W * 0.36
	local colY = y + H / 2
	if o.Glass then
		b:cyl("Tube", H, colD, colY, o.Core or accent, Enum.Material.Glass, { Transparency = 0.45 })
		b:cyl("TubeCore", H, colD * 0.42, colY, o.Core or accent, Enum.Material.Neon)
		b:cyl("TubeCap", 0.14, colD + 0.14, y + 0.07, trim, Enum.Material.Metal)
	else
		b:cyl("Pillar", H, colD, colY, metal, Enum.Material.Metal)
		for i = 1, (o.Strips or 4) do
			b:part("Strip", Enum.PartType.Block, Vector3.new(0.14, H * 0.72, 0.06), CFrame.new(0, colY, 0) * CFrame.Angles(0, (i - 1) * math.pi * 2 / (o.Strips or 4), 0) * CFrame.new(0, 0, -colD / 2 + 0.01), accent, Enum.Material.Neon)
		end
	end
	for i = 1, (o.Bands or 0) do
		local by = y + H * i / ((o.Bands or 0) + 1)
		b:cyl("Band", 0.1, colD + 0.16, by, o.BandColor or trim, Enum.Material.Metal)
		b:cyl("BandGlow", 0.04, colD + 0.2, by, accent, Enum.Material.Neon)
	end
	if o.Fins then
		for i = 1, o.Fins do
			b:part("Fin", Enum.PartType.Block, Vector3.new(0.1, H * 0.45, 0.55), CFrame.new(0, y + H * 0.25, 0) * CFrame.Angles(0, (i - 1) * math.pi * 2 / o.Fins, 0) * CFrame.new(colD / 2 + 0.2, 0, 0), trim, Enum.Material.Metal)
		end
	end
	y += H
	-- collar (cup the core sits in)
	b:cyl("CollarGlow", 0.07, colD * 1.55, y - 0.1, accent, Enum.Material.Neon)
	b:cyl("Collar", 0.24, colD * 1.85, y + 0.08, trim, Enum.Material.Metal)
	return y + 0.2
end

-- black hole: dark sphere, layered spinning accretion disk with glowing clumps, halo, inward particles
local function blackHole(b, at, d, cols, tilt, extent)
	local piv = CFrame.new(at) * tilt
	local hole = b:ball("Hole", d, at, C.Black, Enum.Material.SmoothPlastic)
	b:ball("Halo", d * 1.35, at, cols[2], Enum.Material.ForceField, { Transparency = 0 })
	local R0, R1 = d * 0.62, extent
	b:ring(R0 + 0.22, 0.24, 0.05, cols[1], 0, { Piv = piv })                 -- hot inner edge
	b:ring((R0 + R1) * 0.55, (R1 - R0) * 0.5, 0.04, cols[2], 0.15, { Piv = piv })
	b:ring(R1, (R1 - R0) * 0.45, 0.03, cols[3], 0.45, { Piv = piv })        -- cool outer edge
	b:ring(R1 + 0.25, R1 - R0 + 0.6, 0.02, cols[3], 0.85, { Piv = piv })
	-- a tilted photon ring over the top so it reads as a black hole from every side
	b:ring(d * 0.6, 0.1, 0.04, cols[1], 0.05, { Piv = CFrame.new(at) * CFrame.Angles(0, 0, 0), Rel = CFrame.Angles(math.rad(90), 0, 0), Spd = 0.4 })
	for i = 1, 8 do
		local clump = b:neon("Clump", 0.16 + (i % 3) * 0.06, at, i % 2 == 0 and cols[1] or cols[2])
		b:orbit(clump, piv, R0 + (R1 - R0) * ((i * 0.37) % 1), 2.2 - (i % 4) * 0.3, i * 0.8)
	end
	b:emitter(hole, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, Color = seq(cols[1], cols[2]),
		Size = NumberSequence.new(0.25, 0.02), Lifetime = NumberRange.new(0.9, 0.9), Speed = NumberRange.new(d * 0.9, d),
		Rate = 22, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 0.4) }),
	})
	b:light(hole, cols[2], 14, 2)
	return hole
end

-- glowing star core with a shimmering halo and a slow pulse
local function star(b, at, d, core, halo)
	local s = b:neon("Star", d, at, core)
	b:anim(s, { Rel = CFrame.new(at), Pulse = 0.05, PulseSpd = 2.4 })
	local h = b:ball("StarHalo", d * 1.45, at, halo, Enum.Material.ForceField, { Transparency = 0 })
	b:anim(h, { Rel = CFrame.new(at), Pulse = 0.08, PulseSpd = 1.6 })
	b:emitter(s, {
		Color = seq(C.White, halo), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(1, 2.5), Rate = 12, SpreadAngle = Vector2.new(180, 180),
		Shape = Enum.ParticleEmitterShape.Sphere,
	})
	b:light(s, halo, 16, 2.5)
	return s
end

-- spiral galaxy: bright centre + arms of glowing dots, all turning together
local function galaxy(b, at, R, arms, dots, cols, tilt, spd)
	local piv = CFrame.new(at) * tilt
	b:neon("GalaxyCore", R * 0.28, at, C.White)
	b:ring(R * 0.9, R * 0.75, 0.02, cols[1], 0.82, { Piv = piv })
	for a = 1, arms do
		for i = 1, dots do
			local f = i / dots
			local r = R * (0.18 + 0.82 * f)
			local ang = (a - 1) * math.pi * 2 / arms + f * 3.4
			local col = cols[1]:Lerp(cols[2], f)
			local dot = b:neon("Star", math.max(0.09, 0.3 * (1 - f * 0.65)), at, col, f * 0.35)
			b:anim(dot, { Piv = piv, Rel = CFrame.new(r, 0, 0), Spd = spd, Ph = ang })
		end
	end
end

-- planet riding a ring
local function planet(b, piv, R, d, color, material, spd, ph)
	local p = b:ball("Planet", d, piv, color, material or Enum.Material.SmoothPlastic)
	b:orbit(p, piv, R, spd, ph)
	return p
end

local function rock(b, piv, R, size, spd, ph)
	local p = b:part("Rock", Enum.PartType.Block, Vector3.new(size, size * 0.75, size * 0.85), piv, C.Rock, Enum.Material.Slate)
	b:orbit(p, piv, R, spd, ph, { Self = 1.3 })
	return p
end

local function tilt(x, z)
	return CFrame.Angles(math.rad(x), 0, math.rad(z))
end

---------------------------------------------------------------------
-- The designs. Each returns { Core = height of the nozzle head }
---------------------------------------------------------------------
local Designs = {}

-- COMMON: small grey pedestal, one ring, one little planet
Designs.sprinkler_basic = function(b)
	local top = pedestal(b, { W = 1.8, H = 0.9, Accent = rgb(110, 200, 130), Metal = rgb(70, 74, 82), Trim = rgb(52, 55, 62), ColD = 0.6, Strips = 2 })
	local cy = top + 0.35
	b:ball("Dome", 0.95, cy, rgb(80, 85, 94), Enum.Material.Metal)
	b:cyl("Cap", 0.06, 0.7, cy + 0.33, rgb(110, 200, 130), Enum.Material.Neon)
	local piv = CFrame.new(0, cy, 0) * tilt(10, 6)
	b:track(1.05, C.Steel, rgb(110, 200, 130), { Piv = piv, Width = 0.14, Thick = 0.1, Glow = false })
	planet(b, piv, 0.98, 0.32, rgb(110, 200, 130), Enum.Material.SmoothPlastic, 0.8, 0)
	return { Core = cy }
end

-- UNCOMMON: the green solar sprinkler (1 ring, 2 planets)
local function solarSprinkler(b, gear, nRings, nPlanets, accent, trim)
	local top = pedestal(b, { W = 2.3, H = 1.5, Tiers = 2, Accent = accent, Trim = trim, ColD = 0.95 })
	local cy = top + 0.05
	b:ball("Dome", 1.45, cy, C.Dark, Enum.Material.Metal, { Reflectance = 0.08 })
	b:cyl("Antenna", 0.5, 0.1, cy + 0.88, C.Grey, Enum.Material.Metal)
	b:neon("AntennaTip", 0.2, cy + 1.15, gear.Color or accent)
	local rings = {
		{ R = 1.5, T = tilt(12, 10), S = 0.35 }, { R = 1.85, T = tilt(-10, -14), S = -0.25 }, { R = 2.2, T = tilt(18, -4), S = 0.18 },
	}
	local cols = { rgb(255, 196, 40), rgb(60, 140, 255), rgb(228, 230, 236), rgb(255, 110, 70) }
	for r = 1, nRings do
		b:track(rings[r].R, C.Grey, accent, { Piv = CFrame.new(0, cy, 0) * rings[r].T, Spd = rings[r].S })
	end
	for i = 1, nPlanets do
		local r = rings[((i - 1) % nRings) + 1]
		planet(b, CFrame.new(0, cy, 0) * r.T, r.R - 0.11, i == 1 and 0.6 or 0.42, cols[i], i == 1 and Enum.Material.Neon or nil, 0.7 + i * 0.12, i * 2.4)
	end
	return { Core = cy }
end

Designs.sprinkler_stardust = function(b, gear)
	return solarSprinkler(b, gear, 1, 2, GREEN, C.Dark)
end

-- RARE: Nebula - blue strips, shimmering nebula core, two rings, three planets
Designs.sprinkler_nebula = function(b, gear)
	local top = pedestal(b, { W = 2.45, H = 1.7, Tiers = 2, Accent = C.Blue, Trim = C.Dark, ColD = 1, Bands = 1 })
	local cy = top + 0.3
	b:neon("NebulaCore", 0.75, cy, C.Pink)
	local cloud = b:ball("Nebula", 1.5, cy, C.Purple, Enum.Material.ForceField)
	b:anim(cloud, { Rel = CFrame.new(0, cy, 0), Pulse = 0.06, PulseSpd = 1.4 })
	b:emitter(cloud, { Texture = SMOKE, Color = seq(C.Pink, C.Blue), Size = NumberSequence.new(0.8, 1.4), Transparency = NumberSequence.new(0.75, 1), Lifetime = NumberRange.new(1.5, 2.2), Speed = NumberRange.new(0.2, 0.5), Rate = 6, Shape = Enum.ParticleEmitterShape.Sphere })
	b:light(cloud, C.Purple, 12, 1.6)
	local r1, r2 = CFrame.new(0, cy, 0) * tilt(14, 8), CFrame.new(0, cy, 0) * tilt(-12, -16)
	b:track(1.65, C.Grey, C.Blue, { Piv = r1, Spd = 0.3 })
	b:track(2.05, C.Grey, C.Pink, { Piv = r2, Spd = -0.22 })
	planet(b, r1, 1.55, 0.5, C.Pink, Enum.Material.Neon, 0.9, 0)
	planet(b, r2, 1.95, 0.44, C.Blue, nil, 0.7, 2)
	planet(b, r1, 1.55, 0.36, C.White, nil, 0.9, 3.4)
	return { Core = cy }
end

-- LEGENDARY (starter price): Cosmic - golden sun, three geared rings, four planets
Designs.sprinkler_cosmic = function(b)
	local top = pedestal(b, { W = 2.7, H = 1.9, Tiers = 2, Accent = C.Gold, Trim = C.GoldMetal, ColD = 1.05, Bands = 2, BandColor = C.GoldMetal, Fins = 4 })
	local cy = top + 0.55
	star(b, Vector3.new(0, cy, 0), 1.15, C.Yellow, C.Orange)
	local rings = { { 1.75, tilt(12, 10), 0.35 }, { 2.15, tilt(-10, -14), -0.25 }, { 2.55, tilt(20, -4), 0.18 } }
	for i, r in ipairs(rings) do
		local piv = CFrame.new(0, cy, 0) * r[2]
		b:track(r[1], C.GoldMetal, C.Gold, { Piv = piv, Spd = r[3] })
		b:teeth(6, piv, r[1] - 0.11, Vector3.new(0.18, 0.2, 0.22), C.Yellow, Enum.Material.Neon, r[3])
	end
	local pc = { C.Blue, C.Red, C.White, C.Teal }
	for i = 1, 4 do
		local r = rings[((i - 1) % 3) + 1]
		planet(b, CFrame.new(0, cy, 0) * r[2], r[1] - 0.11, 0.42, pc[i], nil, 0.6 + i * 0.15, i * 1.9)
	end
	return { Core = cy }
end

-- EPIC: Nebula Cloud - glass tube, big shimmering cloud of pink/purple/blue, orbiting orbs
Designs.sprinkler_nebulacloud = function(b)
	local top = pedestal(b, { W = 2.9, H = 2.1, Tiers = 2, Glass = true, Core = C.Cyan, Accent = C.Cyan, Trim = C.Dark, ColD = 0.9, Bands = 2 })
	local cy = top + 1.0
	local at = Vector3.new(0, cy, 0)
	local puffs = {
		{ Vector3.new(0, 0, 0), 1.6, C.Purple }, { Vector3.new(0.6, 0.25, 0.2), 1.1, C.Pink }, { Vector3.new(-0.55, 0.2, -0.3), 1.05, C.Blue },
		{ Vector3.new(0.1, 0.6, -0.4), 0.95, C.Magenta }, { Vector3.new(-0.2, -0.4, 0.5), 1.0, C.Violet }, { Vector3.new(0.45, -0.3, -0.5), 0.85, C.Cyan },
	}
	for i, p in ipairs(puffs) do
		local puff = b:ball("Cloud", p[2], at + p[1], p[3], Enum.Material.ForceField)
		b:anim(puff, { Piv = CFrame.new(at), Rel = CFrame.new(p[1]), Spd = 0.25, Bob = 0.12, BobSpd = 1 + i * 0.2, Ph = i, Pulse = 0.07, PulseSpd = 1.2 + i * 0.15 })
	end
	b:neon("CloudCore", 0.7, at, C.White, 0.1)
	local glow = b:neon("CloudGlow", 1.3, at, C.Pink, 0.55)
	b:emitter(glow, { Texture = SMOKE, Color = seq(C.Pink, C.Purple), Size = NumberSequence.new(1, 2), Transparency = NumberSequence.new(0.7, 1), Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(0.2, 0.6), Rate = 8, Shape = Enum.ParticleEmitterShape.Sphere })
	b:emitter(glow, { Color = seq(C.White, C.Pink), Size = NumberSequence.new(0.25, 0), Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(0.5, 1.2), Rate = 14, Shape = Enum.ParticleEmitterShape.Sphere, SpreadAngle = Vector2.new(180, 180) })
	b:light(glow, C.Pink, 16, 2)
	local piv = CFrame.new(at) * tilt(16, -8)
	b:track(2.0, C.Metal, C.Cyan, { Piv = piv, Spd = 0.3, Width = 0.26 })
	local oc = { C.Pink, C.Blue, C.Purple, C.White, C.Cyan }
	for i = 1, 5 do
		planet(b, piv, 1.88, 0.34 + (i % 2) * 0.08, oc[i], Enum.Material.Neon, 0.6, i * 1.25)
	end
	return { Core = cy }
end

-- EPIC: Celestial Tree - glowing bronze trunk, branches holding orbs, crystal-blue crown
Designs.sprinkler_celestialtree = function(b)
	local top = pedestal(b, { W = 3.0, H = 0.35, Tiers = 2, Accent = C.Cyan, Trim = C.Dark, ColD = 1.2 })
	-- twisting trunk: three leaning segments with glowing veins
	local y = top - 0.1
	local seg = { { 1.1, 0.75, 8 }, { 1.0, 0.6, -10 }, { 0.9, 0.48, 7 } }
	for _, s in ipairs(seg) do
		local cf = CFrame.new(0, y + s[1] / 2, 0) * CFrame.Angles(0, 0, math.rad(s[3]))
		b:cyl("Trunk", s[1], s[2], cf, C.Bronze, Enum.Material.Wood)
		b:part("Vein", Enum.PartType.Block, Vector3.new(0.07, s[1], 0.07), cf * CFrame.new(s[2] / 2 - 0.02, 0, 0), C.Cyan, Enum.Material.Neon)
		b:part("Vein", Enum.PartType.Block, Vector3.new(0.07, s[1], 0.07), cf * CFrame.new(-s[2] / 2 + 0.02, 0, 0.1), C.Cyan, Enum.Material.Neon)
		y += s[1] * 0.92
	end
	-- branches with orbs at the tips
	for i = 1, 6 do
		local a = (i - 1) * math.pi * 2 / 6
		local len = 1.5 + (i % 2) * 0.3
		local cf = CFrame.new(0, y - 0.2, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(-50)) * CFrame.new(len / 2, 0, 0)
		b:part("Branch", Enum.PartType.Cylinder, Vector3.new(len, 0.2, 0.2), cf, C.Bronze, Enum.Material.Wood)
		local tip = (CFrame.new(0, y - 0.2, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(-50)) * CFrame.new(len, 0, 0)).Position
		local orb = b:neon("Orb", 0.42, tip, i % 2 == 0 and C.Cyan or C.Blue)
		b:anim(orb, { Rel = CFrame.new(tip), Bob = 0.12, BobSpd = 1.6, Ph = i })
	end
	local cy = y + 0.6
	b:ball("Crown", 1.35, cy, C.Blue, Enum.Material.Glass, { Transparency = 0.35 })
	b:neon("CrownCore", 0.7, cy, C.Cyan)
	local piv = CFrame.new(0, cy, 0) * tilt(14, 10)
	b:track(1.5, C.GoldMetal, C.Cyan, { Piv = piv, Spd = 0.35, Width = 0.18 })
	planet(b, piv, 1.4, 0.32, C.White, Enum.Material.Neon, 0.9, 0)
	local leaf = b:neon("LeafGlow", 2.6, cy - 0.3, C.Cyan, 0.93)
	b:emitter(leaf, { Color = seq(C.Cyan, C.Teal), Size = NumberSequence.new(0.2, 0), Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(0.2, 0.6), Acceleration = Vector3.new(0, -0.6, 0), Rate = 10, Shape = Enum.ParticleEmitterShape.Sphere })
	b:light(leaf, C.Cyan, 16, 1.8)
	return { Core = cy }
end

-- EPIC: Quasar - blazing core with twin jets, gold gyroscope cage, hanging crystals
Designs.sprinkler_quasar = function(b)
	local top = pedestal(b, { W = 2.9, H = 2.2, Tiers = 2, Glass = true, Core = C.Cyan, Accent = C.Gold, Trim = C.GoldMetal, Metal = C.Metal, ColD = 0.95, Bands = 3, BandColor = C.GoldMetal })
	local cy = top + 1.0
	local at = Vector3.new(0, cy, 0)
	star(b, at, 1.05, C.White, C.Cyan)
	-- twin jets
	for _, dir in ipairs({ 1, -1 }) do
		local jet = b:cyl("Jet", 2.0, 0.16, CFrame.new(0, cy + dir * 1.45, 0), C.Cyan, Enum.Material.Neon, { Transparency = 0.15 })
		b:anim(jet, { Rel = CFrame.new(0, cy + dir * 1.45, 0) * UPRIGHT, Pulse = 0.25, PulseSpd = 5 })
		b:cyl("JetGlow", 2.1, 0.5, CFrame.new(0, cy + dir * 1.45, 0), C.Cyan, Enum.Material.Neon, { Transparency = 0.8 })
		if dir == 1 then
			b:emitter(jet, { Color = seq(C.White, C.Cyan), Size = NumberSequence.new(0.3, 0), Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(4, 6), EmissionDirection = Enum.NormalId.Right, Rate = 25, SpreadAngle = Vector2.new(4, 4) })
		end
	end
	-- gold gyroscope: two vertical rings turning around the core
	b:ring(1.35, 0.12, 0.12, C.GoldMetal, 0, { Piv = CFrame.new(at), Rel = CFrame.Angles(math.rad(90), 0, 0), Spd = 0.8 })
	b:ring(1.2, 0.1, 0.1, C.Gold, 0, { Piv = CFrame.new(at), Rel = CFrame.Angles(0, 0, math.rad(90)), Spd = -0.6 })
	-- big horizontal ring with blue orbs and hanging crystals
	local piv = CFrame.new(at) * tilt(6, 4)
	b:track(2.0, C.GoldMetal, C.Gold, { Piv = piv, Spd = 0.25, Width = 0.24 })
	for i = 1, 6 do
		planet(b, piv, 1.9, 0.34, C.Blue, Enum.Material.Neon, 0.25, i * math.pi / 3)
	end
	for i = 1, 4 do
		local a = (i - 1) * math.pi / 2 + 0.4
		b:crystal(CFrame.new(math.cos(a) * 1.9, cy - 1.05, math.sin(a) * 1.9) * CFrame.Angles(math.rad(180), 0, 0) * CFrame.new(0, -0.5, 0), 0.55, 0.2, C.Cyan, {
			Anim = { Piv = piv, Rel = CFrame.new(1.9, -0.45, 0) * CFrame.Angles(math.rad(180), 0, 0), Spd = 0.25, Ph = a, Bob = 0.08 },
		})
	end
	return { Core = cy }
end

-- EPIC: Dark Matter - purple void orb in a three-axis cage, floating dark cubes
Designs.sprinkler_darkmatter = function(b)
	local top = pedestal(b, { W = 3.0, H = 1.9, Tiers = 3, Accent = C.Purple, Trim = C.Dark, Metal = rgb(28, 24, 40), ColD = 1.0, Bands = 2 })
	local cy = top + 0.95
	local at = Vector3.new(0, cy, 0)
	b:ball("Void", 1.05, at, rgb(10, 4, 20), Enum.Material.SmoothPlastic)
	local shell = b:ball("VoidShell", 1.7, at, C.Purple, Enum.Material.ForceField)
	b:anim(shell, { Rel = CFrame.new(at), Pulse = 0.06, PulseSpd = 1.3 })
	b:neon("VoidSpark", 0.3, at, C.Pink)
	b:emitter(shell, { Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, Color = seq(C.Pink, C.Purple), Size = NumberSequence.new(0.22, 0.02), Lifetime = NumberRange.new(0.8, 0.8), Speed = NumberRange.new(1.6, 2), Rate = 20 })
	b:light(shell, C.Purple, 14, 2)
	-- cage rings on three axes
	b:ring(1.35, 0.12, 0.1, C.Purple, 0, { Piv = CFrame.new(at), Rel = CFrame.new(), Ax = Vector3.xAxis, Spd = 0.7 })
	b:ring(1.5, 0.12, 0.1, C.Violet, 0, { Piv = CFrame.new(at), Rel = CFrame.Angles(0, 0, math.rad(90)), Ax = Vector3.zAxis, Spd = -0.55 })
	b:track(1.95, C.Metal, C.Purple, { Piv = CFrame.new(at) * tilt(10, -6), Spd = 0.3 })
	-- floating cubes
	for i = 1, 7 do
		local cube = b:part("Cube", Enum.PartType.Block, Vector3.one * (0.3 + (i % 3) * 0.08), CFrame.new(at), rgb(60, 20, 110), Enum.Material.Neon, { Transparency = 0.15 })
		b:orbit(cube, CFrame.new(at) * tilt(-8 + i * 3, 12 - i * 2), 2.3 + (i % 3) * 0.25, 0.5 + (i % 2) * 0.2, i * 0.9, { Self = 1.2, Bob = 0.15, BobSpd = 1.2 })
	end
	return { Core = cy }
end

-- LEGENDARY: Void Spiral - a helix of light climbing the pillar into a purple black hole
Designs.sprinkler_voidspiral = function(b)
	local top = pedestal(b, { W = 2.9, H = 2.5, Tiers = 2, Accent = C.Violet, Trim = C.Dark, Metal = rgb(26, 22, 40), ColD = 0.75 })
	-- double helix around the pillar
	local n = 18
	for s = 0, 1 do
		for i = 1, n do
			local f = i / n
			local yy = 0.8 + f * (top - 0.9)
			local a = f * math.pi * 4 + s * math.pi
			local dot = b:neon("Helix", 0.2 + f * 0.12, Vector3.new(0, yy, 0), s == 0 and C.Violet or C.Pink, 0.05)
			b:anim(dot, { Piv = CFrame.new(0, yy, 0), Rel = CFrame.new(0.75 + f * 0.25, 0, 0), Spd = 1.4, Ph = a })
		end
	end
	local cy = top + 1.2
	blackHole(b, Vector3.new(0, cy, 0), 1.25, { rgb(220, 200, 255), C.Violet, C.DeepBlue }, tilt(14, -6), 2.4)
	-- swirl ring above
	b:ring(2.8, 0.1, 0.06, C.Pink, 0.2, { Piv = CFrame.new(0, cy, 0) * tilt(-8, 10), Spd = 0.4 })
	for i = 1, 3 do
		planet(b, CFrame.new(0, cy, 0) * tilt(-8, 10), 2.75, 0.3, C.Pink, Enum.Material.Neon, 0.8, i * 2.1)
	end
	return { Core = cy }
end

-- LEGENDARY: Black Hole - fiery base with claws, huge orange accretion disk, orbiting debris
Designs.sprinkler_blackhole = function(b)
	local top = pedestal(b, { W = 3.4, H = 2.4, Tiers = 3, Accent = C.Fire, Trim = rgb(30, 20, 16), Metal = rgb(40, 28, 22), ColD = 1.1, Bands = 2, Spikes = 6, SpikeColor = rgb(30, 22, 18) })
	local cy = top + 1.5
	local at = Vector3.new(0, cy, 0)
	local hole = blackHole(b, at, 2.0, { C.Yellow, C.Orange, C.Red }, tilt(12, 4), 3.9)
	-- extra bright inner disk so the fire reads from across the map
	b:ring(2.2, 0.7, 0.06, C.Orange, 0, { Piv = CFrame.new(at) * tilt(12, 4) })
	b:emitter(hole, { Texture = FIRE, Color = seq(C.Yellow, C.Fire), Size = NumberSequence.new(0.6, 0.1), Transparency = NumberSequence.new(0.3, 1), Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.5, 1), Rate = 18, Shape = Enum.ParticleEmitterShape.Sphere })
	for i = 1, 9 do
		rock(b, CFrame.new(at) * tilt(12 + (i % 3) * 4, 4 - (i % 2) * 6), 2.3 + (i % 4) * 0.35, 0.28 + (i % 3) * 0.1, 0.6 + (i % 3) * 0.2, i * 0.7)
	end
	return { Core = cy }
end

-- LEGENDARY: Time Dilation - golden hourglass with falling light, counter-rotating clock rings
Designs.sprinkler_timedilation = function(b)
	local top = pedestal(b, { W = 2.8, H = 1.4, Tiers = 2, Glass = true, Core = C.Cyan, Accent = C.Gold, Trim = C.GoldMetal, ColD = 0.9, Bands = 1, BandColor = C.GoldMetal })
	local y0 = top
	local hgH = 2.6
	local cy = y0 + hgH / 2
	b:cyl("HourBase", 0.18, 1.8, y0 + 0.09, C.GoldMetal, Enum.Material.Metal)
	b:cyl("HourTop", 0.18, 1.8, y0 + hgH - 0.09, C.GoldMetal, Enum.Material.Metal)
	b:cyl("HourTopGlow", 0.05, 1.9, y0 + hgH, C.Gold, Enum.Material.Neon)
	for i = 1, 3 do
		local a = (i - 1) * math.pi * 2 / 3
		b:cyl("Post", hgH - 0.3, 0.12, CFrame.new(math.cos(a) * 0.82, cy, math.sin(a) * 0.82), C.GoldMetal, Enum.Material.Metal)
	end
	-- glass bulbs: stacked discs narrowing to the neck
	for i = 1, 5 do
		local f = (i - 0.5) / 5
		local d = 1.35 - f * 1.15
		local hh = (hgH / 2 - 0.25) / 5
		b:cyl("Glass", hh, d, y0 + 0.2 + (i - 0.5) * hh, C.Cyan, Enum.Material.Glass, { Transparency = 0.6 })
		b:cyl("Glass", hh, d, y0 + hgH - 0.2 - (i - 0.5) * hh, C.Cyan, Enum.Material.Glass, { Transparency = 0.6 })
	end
	b:cyl("SandBottom", 0.35, 0.95, y0 + 0.36, C.Gold, Enum.Material.Neon)
	b:cyl("SandTop", 0.3, 0.65, y0 + hgH - 0.55, C.Gold, Enum.Material.Neon)
	local stream = b:cyl("SandStream", hgH / 2 - 0.3, 0.07, cy - 0.35, C.Yellow, Enum.Material.Neon)
	b:emitter(stream, { Color = seq(C.Yellow, C.Gold), Size = NumberSequence.new(0.12, 0.05), Lifetime = NumberRange.new(0.5, 0.5), Speed = NumberRange.new(2, 2), EmissionDirection = Enum.NormalId.Left, Rate = 20 })
	b:light(stream, C.Gold, 12, 1.8)
	-- clock rings turning opposite ways, with hour ticks
	local p1, p2 = CFrame.new(0, y0 + 0.75, 0), CFrame.new(0, y0 + hgH - 0.55, 0)
	b:track(2.1, C.GoldMetal, C.Gold, { Piv = p1, Spd = 0.35, Width = 0.22 })
	b:teeth(12, p1, 1.98, Vector3.new(0.08, 0.22, 0.24), C.Yellow, Enum.Material.Neon, 0.35)
	b:track(2.5, C.GoldMetal, C.Cyan, { Piv = p2, Spd = -0.25, Width = 0.2 })
	b:teeth(12, p2, 2.38, Vector3.new(0.08, 0.22, 0.24), C.Cyan, Enum.Material.Neon, -0.25)
	for i = 1, 3 do
		planet(b, CFrame.new(0, cy, 0) * tilt(20, -10), 2.9, 0.34, C.Gold, Enum.Material.Neon, 0.35, i * 2.1)
	end
	return { Core = cy }
end

-- LEGENDARY: Planetary Ring - blazing sun, three giant rings carrying a whole solar system
Designs.sprinkler_planetaryring = function(b)
	local top = pedestal(b, { W = 3.1, H = 2.3, Tiers = 2, Glass = true, Core = C.Cyan, Accent = C.Orange, Trim = C.Dark, ColD = 0.95, Bands = 2 })
	local cy = top + 1.15
	local at = Vector3.new(0, cy, 0)
	star(b, at, 1.6, C.Yellow, C.Orange)
	local rings = { { 2.2, tilt(14, 8), 0.3 }, { 2.75, tilt(-8, -14), -0.22 }, { 3.3, tilt(22, -2), 0.15 } }
	for _, r in ipairs(rings) do
		b:track(r[1], C.Grey, C.Orange, { Piv = CFrame.new(at) * r[2], Spd = r[3], Width = 0.26, Thick = 0.18 })
	end
	b:teeth(10, CFrame.new(at) * rings[3][2], rings[3][1] - 0.12, Vector3.new(0.14, 0.24, 0.26), C.Orange, Enum.Material.Neon, rings[3][3])
	local ps = {
		{ 1, 0.5, C.Fire }, { 1, 0.36, C.Steel }, { 2, 0.55, C.Blue }, { 2, 0.4, rgb(220, 180, 120) }, { 3, 0.62, C.Orange }, { 3, 0.44, C.Red }, { 3, 0.34, C.White },
	}
	for i, p in ipairs(ps) do
		local r = rings[p[1]]
		planet(b, CFrame.new(at) * r[2], r[1] - 0.12, p[2], p[3], nil, 0.45 + (i % 3) * 0.15, i * 1.7)
	end
	return { Core = cy }
end

-- LEGENDARY: Orbital Station - glass core, rotating habitat ring with pods and spokes, satellites
Designs.sprinkler_orbitalstation = function(b)
	local top = pedestal(b, { W = 3.0, H = 2.6, Tiers = 2, Glass = true, Core = C.Blue, Accent = C.Blue, Trim = C.Silver, Metal = C.Metal, ColD = 0.9, Bands = 2, BandColor = C.Silver })
	local cy = top + 1.0
	local at = Vector3.new(0, cy, 0)
	b:ball("Hub", 1.35, at, C.Blue, Enum.Material.Glass, { Transparency = 0.3 })
	local core = b:neon("HubCore", 0.7, at, C.Cyan)
	b:light(core, C.Blue, 14, 2)
	-- habitat ring: wide silver band + pods + spokes, all turning together
	local hab = CFrame.new(at)
	b:ring(2.1, 0.4, 0.3, C.Silver, 0, { Piv = hab, Spd = 0.3 })
	b:ring(1.75, 0.08, 0.32, C.Blue, 0, { Piv = hab, Spd = 0.3 })
	b:teeth(8, hab, 1.9, Vector3.new(0.4, 0.42, 0.5), C.Silver, Enum.Material.Metal, 0.3)
	for i = 1, 8 do
		local w = b:part("Window", Enum.PartType.Block, Vector3.new(0.42, 0.12, 0.3), hab, C.Cyan, Enum.Material.Neon)
		b:anim(w, { Piv = hab, Rel = CFrame.new(2.16, 0, 0), Spd = 0.3, Ph = (i - 1) * math.pi / 4 })
	end
	for i = 1, 4 do
		local s = b:part("Spoke", Enum.PartType.Cylinder, Vector3.new(1.4, 0.1, 0.1), hab, C.Silver, Enum.Material.Metal)
		b:anim(s, { Piv = hab, Rel = CFrame.new(1.05, 0, 0), Spd = 0.3, Ph = (i - 1) * math.pi / 2 })
	end
	-- hanging lights under the ring
	for i = 1, 4 do
		local l = b:neon("Lamp", 0.26, at, C.Cyan)
		b:anim(l, { Piv = hab, Rel = CFrame.new(1.9, -0.55, 0), Spd = 0.3, Ph = (i - 1) * math.pi / 2 + 0.4, Bob = 0.06 })
	end
	-- outer tilted ring with satellites
	local piv = CFrame.new(at) * tilt(18, -10)
	b:track(2.8, C.Grey, C.Blue, { Piv = piv, Spd = -0.25, Width = 0.16 })
	for i = 1, 4 do
		planet(b, piv, 2.7, 0.32, C.Blue, Enum.Material.Neon, -0.5, i * math.pi / 2)
	end
	-- antenna + dish
	b:cyl("Mast", 0.9, 0.1, cy + 1.1, C.Silver, Enum.Material.Metal)
	b:part("Dish", Enum.PartType.Ball, Vector3.new(0.9, 0.25, 0.9), CFrame.new(0, cy + 1.6, 0), C.Silver, Enum.Material.Metal)
	b:neon("Beacon", 0.18, cy + 1.75, C.Red)
	return { Core = cy }
end

-- MYTHIC: Supernova - exploding pink star, crystal spikes bursting out, shock rings
Designs.sprinkler_supernova = function(b)
	local top = pedestal(b, { W = 3.3, H = 2.4, Tiers = 3, Accent = C.Magenta, Trim = rgb(40, 20, 50), Metal = rgb(34, 24, 48), ColD = 1.0, Bands = 2, Spikes = 6, SpikeColor = rgb(60, 20, 80) })
	local cy = top + 1.35
	local at = Vector3.new(0, cy, 0)
	star(b, at, 1.3, rgb(255, 230, 255), C.Pink)
	-- crystal spikes bursting outward in all directions, slowly turning
	local dirs = {}
	for i = 1, 10 do
		local phi = math.acos(1 - 2 * (i - 0.5) / 10)
		local theta = math.pi * (1 + 5 ^ 0.5) * i
		table.insert(dirs, Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)))
	end
	for i, d in ipairs(dirs) do
		local rel = CFrame.lookAt(Vector3.zero, d) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, 0.55, 0)
		b:crystal(CFrame.new(at) * rel, 0.9 + (i % 3) * 0.35, 0.24, i % 2 == 0 and C.Pink or C.Purple, { Anim = { Piv = CFrame.new(at), Rel = rel, Spd = 0.25 } })
	end
	b:ring(2.6, 0.12, 0.05, C.Pink, 0.15, { Piv = CFrame.new(at) * tilt(18, 6), Spd = 0.4 })
	b:ring(2.9, 0.08, 0.04, C.Purple, 0.3, { Piv = CFrame.new(at) * tilt(-14, -12), Spd = -0.3 })
	for i = 1, 6 do
		local g = b:gem(CFrame.new(at), 0.28, i % 2 == 0 and C.Pink or C.White)
		b:orbit(g, CFrame.new(at) * tilt(18, 6), 2.55, 0.5, i * math.pi / 3, { Self = 2 })
	end
	local glow = b:neon("NovaGlow", 2.4, at, C.Pink, 0.88)
	b:anim(glow, { Rel = CFrame.new(at), Pulse = 0.18, PulseSpd = 2 })
	b:emitter(glow, { Color = seq(C.White, C.Pink), Size = NumberSequence.new(0.35, 0), Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(3, 5), Rate = 22, Shape = Enum.ParticleEmitterShape.Sphere, SpreadAngle = Vector2.new(180, 180) })
	return { Core = cy }
end

-- MYTHIC: Galaxy Core - spiral galaxy in a glass sphere, crystal crown, crystal-claw base
Designs.sprinkler_galaxycore = function(b)
	local top = pedestal(b, { W = 3.4, H = 2.2, Tiers = 3, Accent = C.Purple, Trim = rgb(30, 26, 50), Metal = rgb(30, 28, 46), ColD = 1.0, Bands = 2, Spikes = 8, SpikeColor = rgb(50, 40, 90) })
	-- crystal claws rising from the base
	for i = 1, 6 do
		local a = (i - 1) * math.pi / 3
		b:crystal(CFrame.new(math.cos(a) * 1.25, 0.6, math.sin(a) * 1.25) * CFrame.Angles(math.sin(a) * 0.35, 0, -math.cos(a) * 0.35), 0.9, 0.22, i % 2 == 0 and C.Cyan or C.Purple)
	end
	local cy = top + 1.5
	local at = Vector3.new(0, cy, 0)
	b:ball("Sphere", 2.6, at, rgb(90, 110, 255), Enum.Material.Glass, { Transparency = 0.5 })
	b:ball("SphereShimmer", 2.7, at, C.Purple, Enum.Material.ForceField)
	galaxy(b, at, 1.15, 2, 9, { C.Pink, C.Purple }, tilt(25, 10), 0.9)
	local glow = b:neon("GalaxyGlow", 2.2, at, C.Purple, 0.8)
	b:light(glow, C.Purple, 16, 2.2)
	-- crown of crystals above
	for i = 1, 8 do
		local a = (i - 1) * math.pi / 4
		local rel = CFrame.new(math.cos(a) * 0.9, cy + 1.05, math.sin(a) * 0.9) * CFrame.Angles(math.sin(a) * 0.45, 0, -math.cos(a) * 0.45)
		b:crystal(rel, 0.8 + (i % 2) * 0.4, 0.22, i % 2 == 0 and C.Cyan or C.Purple)
	end
	b:crystal(CFrame.new(0, cy + 1.2, 0), 1.9, 0.46, C.Purple, { Anim = { Piv = CFrame.new(0, cy + 1.2, 0), Rel = CFrame.new(), Spd = 0.5, Bob = 0.1 } })
	-- gold ring + floating crystals
	local piv = CFrame.new(at) * tilt(12, -8)
	b:track(2.4, C.GoldMetal, C.Gold, { Piv = piv, Spd = 0.3, Width = 0.22 })
	for i = 1, 5 do
		planet(b, piv, 2.28, 0.32, i % 2 == 0 and C.Cyan or C.Pink, Enum.Material.Neon, 0.3, i * 1.25)
	end
	for i = 1, 6 do
		local g = b:gem(CFrame.new(at), 0.3, i % 2 == 0 and C.Cyan or C.Purple)
		b:orbit(g, CFrame.new(at) * tilt(-10, 14), 2.9, -0.4, i * math.pi / 3, { Self = 1.5, Bob = 0.15, BobSpd = 1.3 })
	end
	return { Core = cy }
end

-- MYTHIC: Cosmic Supreme - massive purple black hole, galaxy swirl, glass bubble planets, crystals
Designs.sprinkler_cosmicsupreme = function(b)
	local top = pedestal(b, { W = 3.7, H = 2.6, Tiers = 3, Glass = true, Core = C.Purple, Accent = C.Purple, Trim = rgb(44, 40, 64), Metal = rgb(30, 28, 46), ColD = 1.05, Bands = 3, Spikes = 6, SpikeColor = rgb(50, 40, 90) })
	local cy = top + 1.55
	local at = Vector3.new(0, cy, 0)
	blackHole(b, at, 1.8, { rgb(230, 220, 255), C.Purple, C.Blue }, tilt(14, -8), 3.3)
	galaxy(b, at, 3.4, 2, 9, { C.Cyan, C.Pink }, tilt(14, -8), 0.45)
	-- two big crossing rings full of glass bubble planets
	local r1, r2 = CFrame.new(at) * tilt(28, 12), CFrame.new(at) * tilt(-22, -18)
	b:track(3.7, C.Silver, C.Purple, { Piv = r1, Spd = 0.25, Width = 0.24 })
	b:track(4.1, C.Silver, C.Cyan, { Piv = r2, Spd = -0.18, Width = 0.2 })
	local bc = { C.Cyan, C.Pink, C.Orange, C.Blue, C.Teal, C.Purple, C.White, C.Gold, C.Magenta, C.Blue }
	for i = 1, 10 do
		local ring = i % 2 == 0 and r1 or r2
		local R = i % 2 == 0 and 3.58 or 4.0
		local p = b:ball("Bubble", 0.4 + (i % 3) * 0.12, at, bc[i], Enum.Material.Glass, { Transparency = 0.15 })
		b:orbit(p, ring, R, i % 2 == 0 and 0.25 or -0.18, i * 0.63)
	end
	for i = 1, 4 do
		local a = (i - 1) * math.pi / 2 + 0.6
		b:crystal(CFrame.new(math.cos(a) * 2.4, cy + 1.3, math.sin(a) * 2.4), 0.9, 0.28, C.Purple, { Anim = { Piv = CFrame.new(0, cy + 1.3, 0), Rel = CFrame.new(2.4, 0, 0), Spd = 0.2, Ph = a, Bob = 0.2, BobSpd = 1.2 } })
	end
	return { Core = cy }
end

-- DIVINE: Starforge - white-gold star in a gold armillary, feathered halo wings, crown of gold
Designs.sprinkler_divine = function(b)
	local top = pedestal(b, { W = 3.9, H = 2.8, Tiers = 3, Glass = true, Core = C.Gold, Accent = C.Gold, Trim = C.GoldMetal, Metal = rgb(240, 236, 226), ColD = 1.1, Bands = 3, BandColor = C.GoldMetal, Spikes = 8, SpikeColor = C.GoldMetal })
	local cy = top + 1.6
	local at = Vector3.new(0, cy, 0)
	star(b, at, 1.6, C.White, C.Gold)
	-- armillary: three gold rings turning on three axes
	b:ring(1.55, 0.14, 0.12, C.GoldMetal, 0, { Piv = CFrame.new(at), Rel = CFrame.new(), Ax = Vector3.xAxis, Spd = 0.6 })
	b:ring(1.75, 0.14, 0.12, C.Gold, 0, { Piv = CFrame.new(at), Rel = CFrame.Angles(0, 0, math.rad(90)), Ax = Vector3.zAxis, Spd = -0.45 })
	b:ring(1.95, 0.14, 0.12, C.GoldMetal, 0, { Piv = CFrame.new(at) * tilt(12, 0), Spd = 0.3 })
	-- halo wings: blades fanning out behind the star, slowly turning
	for i = 1, 12 do
		local a = (i - 1) * math.pi * 2 / 12
		local blade = b:part("Wing", Enum.PartType.Block, Vector3.new(0.14, 1.5, 0.42), CFrame.new(at), i % 2 == 0 and C.Gold or C.White, Enum.Material.Neon, { Transparency = 0.2 })
		b:anim(blade, { Piv = CFrame.new(at) * CFrame.Angles(math.rad(75), 0, 0), Rel = CFrame.new(2.7, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), Spd = 0.2, Ph = a })
	end
	-- big halo above with orbiting gems
	local halo = CFrame.new(0, cy + 2.0, 0)
	b:track(2.2, C.GoldMetal, C.White, { Piv = halo, Spd = 0.3, Width = 0.2 })
	for i = 1, 8 do
		local g = b:gem(halo, 0.28, i % 2 == 0 and C.Gold or C.White)
		b:orbit(g, halo, 2.1, 0.3, i * math.pi / 4, { Self = 2 })
	end
	for i = 1, 6 do
		local a = (i - 1) * math.pi / 3
		b:crystal(CFrame.new(math.cos(a) * 1.0, cy + 1.0, math.sin(a) * 1.0) * CFrame.Angles(math.sin(a) * 0.4, 0, -math.cos(a) * 0.4), 0.9, 0.24, C.Gold)
	end
	local glow = b:neon("DivineGlow", 3.2, at, C.Gold, 0.9)
	b:anim(glow, { Rel = CFrame.new(at), Pulse = 0.12, PulseSpd = 1.5 })
	b:emitter(glow, { Color = seq(C.White, C.Gold), Size = NumberSequence.new(0.35, 0), Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(0.5, 1.5), Acceleration = Vector3.new(0, 1.2, 0), Rate = 20, Shape = Enum.ParticleEmitterShape.Sphere })
	return { Core = cy }
end

-- CELESTIAL: Universe Engine - galaxy around a black hole, a sun above, eight planets on three
-- huge rings, an asteroid belt and floating crystals: a whole universe on a pedestal
Designs.sprinkler_celestial = function(b)
	local top = pedestal(b, { W = 4.3, H = 3.0, Tiers = 3, Glass = true, Core = C.Cyan, Accent = C.Cyan, Trim = rgb(30, 40, 60), Metal = rgb(26, 32, 48), ColD = 1.2, Bands = 3, BandColor = C.Silver, Spikes = 8, SpikeColor = rgb(40, 60, 100), Fins = 6 })
	local cy = top + 1.9
	local at = Vector3.new(0, cy, 0)
	blackHole(b, at, 1.4, { C.White, C.Cyan, C.Purple }, tilt(16, -6), 2.4)
	galaxy(b, at, 3.6, 3, 10, { C.Cyan, C.Magenta }, tilt(16, -6), 0.35)
	local sunAt = Vector3.new(0, cy + 2.5, 0)
	star(b, sunAt, 0.9, C.Yellow, C.Orange)
	local rings = { { 3.9, tilt(30, 10), 0.22 }, { 4.4, tilt(-24, -16), -0.16 }, { 4.9, tilt(8, 28), 0.12 } }
	local rc = { C.Cyan, C.Pink, C.Gold }
	for i, r in ipairs(rings) do
		b:track(r[1], C.Silver, rc[i], { Piv = CFrame.new(at) * r[2], Spd = r[3], Width = 0.26, Thick = 0.18 })
	end
	local pc = { C.Blue, C.Orange, C.Teal, C.Red, C.White, C.Purple, rgb(220, 180, 120), C.Pink }
	for i = 1, 8 do
		local r = rings[((i - 1) % 3) + 1]
		planet(b, CFrame.new(at) * r[2], r[1] - 0.13, 0.42 + (i % 3) * 0.14, pc[i], i % 4 == 0 and Enum.Material.Neon or nil, r[3] * 2, i * 0.8)
	end
	for i = 1, 10 do
		rock(b, CFrame.new(at) * tilt(16, -6), 3.0 + (i % 3) * 0.3, 0.24 + (i % 2) * 0.1, 0.5 + (i % 4) * 0.1, i * 0.63)
	end
	for i = 1, 6 do
		local a = (i - 1) * math.pi / 3
		b:crystal(CFrame.new(math.cos(a) * 2.6, cy - 1.4, math.sin(a) * 2.6), 1.0, 0.3, i % 2 == 0 and C.Cyan or C.Magenta, { Anim = { Piv = CFrame.new(0, cy - 1.4, 0), Rel = CFrame.new(2.6, 0, 0), Spd = -0.2, Ph = a, Bob = 0.2, BobSpd = 1 } })
	end
	local aurora = b:ball("Aurora", 5.2, at, C.Cyan, Enum.Material.ForceField)
	b:anim(aurora, { Rel = CFrame.new(at), Pulse = 0.05, PulseSpd = 0.8 })
	b:emitter(aurora, { Color = seq(C.Cyan, C.Magenta), Size = NumberSequence.new(0.3, 0), Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(0.3, 0.8), Rate = 26, Shape = Enum.ParticleEmitterShape.Sphere })
	return { Core = cy }
end

---------------------------------------------------------------------
-- Effects per sprinkler (SprinklerClient reads these)
--   Nozzles  how many streams of stardust spray out
--   Circle   colour of the coverage circle once placed
--   Wave     seconds between pulses rolling out across the circle (nil = none)
--   Aura     sparkles rising from the whole covered area
--   Beams    light streams from the core down to the ground
--   Nova     big flash + shock ring every few seconds
--   Burst    size of the placement explosion (1-8)
---------------------------------------------------------------------
local FX = {
	sprinkler_basic = { Nozzles = 2, Circle = rgb(110, 200, 130), Burst = 1 },
	sprinkler_stardust = { Nozzles = 3, Circle = GREEN, Burst = 2 },
	sprinkler_nebula = { Nozzles = 3, Circle = C.Blue, Wave = 6, Burst = 3 },
	sprinkler_cosmic = { Nozzles = 4, Circle = C.Gold, Wave = 5, Beams = 3, Burst = 4 },
	sprinkler_nebulacloud = { Nozzles = 4, Circle = C.Pink, Wave = 5, Aura = 8, Burst = 4 },
	sprinkler_celestialtree = { Nozzles = 4, Circle = C.Cyan, Wave = 5, Aura = 10, Burst = 4 },
	sprinkler_quasar = { Nozzles = 5, Circle = C.Cyan, Wave = 4, Beams = 4, Burst = 4 },
	sprinkler_darkmatter = { Nozzles = 4, Circle = C.Purple, Wave = 4, Aura = 10, Burst = 4 },
	sprinkler_voidspiral = { Nozzles = 5, Circle = C.Violet, Wave = 4, Beams = 5, Aura = 10, Burst = 5 },
	sprinkler_blackhole = { Nozzles = 5, Circle = C.Orange, Wave = 4, Beams = 5, Aura = 12, Burst = 5 },
	sprinkler_timedilation = { Nozzles = 5, Circle = C.Gold, Wave = 3, Beams = 5, Aura = 10, Burst = 5 },
	sprinkler_planetaryring = { Nozzles = 6, Circle = C.Orange, Wave = 4, Beams = 6, Aura = 12, Burst = 5 },
	sprinkler_orbitalstation = { Nozzles = 6, Circle = C.Blue, Wave = 4, Beams = 6, Aura = 12, Burst = 5 },
	sprinkler_supernova = { Nozzles = 7, Circle = C.Pink, Wave = 3, Beams = 7, Aura = 16, Nova = 5, Burst = 6 },
	sprinkler_galaxycore = { Nozzles = 7, Circle = C.Purple, Wave = 3, Beams = 7, Aura = 16, Burst = 6 },
	sprinkler_cosmicsupreme = { Nozzles = 8, Circle = C.Purple, Wave = 3, Beams = 8, Aura = 18, Nova = 6, Burst = 6 },
	sprinkler_divine = { Nozzles = 8, Circle = C.Gold, Wave = 2.5, Beams = 10, Aura = 22, Nova = 5, Burst = 7 },
	sprinkler_celestial = { Nozzles = 8, Circle = C.Cyan, Wave = 2, Beams = 12, Aura = 28, Nova = 4, Burst = 8 },
}

function SprinklerModel.Fx(gearId)
	return FX[gearId] or FX.sprinkler_stardust
end

---------------------------------------------------------------------
-- Build
---------------------------------------------------------------------
function SprinklerModel.Build(gear, cf, ghost, icon)
	local model = Instance.new("Model")
	model.Name = ghost and "SprinklerPreview" or gear.Name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local b = newBuilder(model, cf, ghost, icon)
	local design = Designs[gear.Id] or Designs.sprinkler_stardust
	local info = design(b, gear)

	-- the nozzle head the stardust sprays from (invisible; the client spins it)
	local head = b:part("Head", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, info.Core, 0), C.Dark, nil, { Transparency = 1 })
	if not ghost then
		local n = SprinklerModel.Fx(gear.Id).Nozzles
		local reach = 0.6
		for i = 1, n do
			local nozzle = Instance.new("Attachment")
			nozzle.Name = "Nozzle" .. i
			nozzle.CFrame = CFrame.Angles(0, (i - 1) * math.pi * 2 / n, 0) * CFrame.new(0, 0.2, -reach) * CFrame.Angles(math.rad(40), 0, 0)
			nozzle.Parent = head
		end
	end
	model:SetAttribute("CoreY", info.Core)
	model.PrimaryPart = b.base
	SprinklerModel.Animate(model, 0)
	return model
end

---------------------------------------------------------------------
-- Animate: called every frame for sprinklers near the camera (and the preview / shop icon)
---------------------------------------------------------------------
local cache = setmetatable({}, { __mode = "k" })

local function collect(model)
	local entry = { parts = {}, adorns = {}, dirty = false }
	entry.origin = model:FindFirstChild("Origin")
	for _, d in ipairs(model:GetDescendants()) do
		if d:GetAttribute("Anim") then
			local a = {
				obj = d, Piv = d:GetAttribute("Piv"), Rel = d:GetAttribute("Rel"), Ax = d:GetAttribute("Ax"),
				Spd = d:GetAttribute("Spd"), Ph = d:GetAttribute("Ph"), Self = d:GetAttribute("Self"),
				Bob = d:GetAttribute("Bob"), BobSpd = d:GetAttribute("BobSpd"), Pulse = d:GetAttribute("Pulse"),
				PulseSpd = d:GetAttribute("PulseSpd"), Sz = d:GetAttribute("Sz"),
			}
			if d:IsA("HandleAdornment") then
				table.insert(entry.adorns, a)
			else
				table.insert(entry.parts, a)
			end
		end
	end
	entry.conn = model.DescendantAdded:Connect(function()
		entry.dirty = true
	end)
	return entry
end

function SprinklerModel.Animate(model, t)
	local entry = cache[model]
	if not entry or entry.dirty then
		if entry and entry.conn then
			entry.conn:Disconnect()
		end
		entry = collect(model)
		cache[model] = entry
	end
	local originPart = entry.origin
	if not originPart then
		return
	end
	local origin = originPart.CFrame
	for _, a in ipairs(entry.adorns) do
		a.obj.CFrame = a.Piv * CFrame.fromAxisAngle(a.Ax, a.Ph + t * a.Spd) * a.Rel * FLAT
	end
	local parts, cframes = {}, {}
	for _, a in ipairs(entry.parts) do
		local cf = origin * a.Piv * CFrame.fromAxisAngle(a.Ax, a.Ph + t * a.Spd) * a.Rel
		if a.Self then
			cf *= CFrame.fromAxisAngle(SELF_AXIS, t * a.Self)
		end
		if a.Bob then
			cf += Vector3.new(0, math.sin(t * a.BobSpd + a.Ph) * a.Bob, 0)
		end
		if a.Pulse then
			a.obj.Size = a.Sz * (1 + math.sin(t * a.PulseSpd) * a.Pulse)
		end
		table.insert(parts, a.obj)
		table.insert(cframes, cf)
	end
	if #parts > 0 then
		if model:IsDescendantOf(workspace) then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		else
			for i, p in ipairs(parts) do
				p.CFrame = cframes[i]
			end
		end
	end
end

---------------------------------------------------------------------
-- Range circle: soft fill + bright edge + inner line. circle:Place(position)
---------------------------------------------------------------------
local function flatRing(anchor, name, R, inner, h, color, tr)
	local a = Instance.new("CylinderHandleAdornment")
	a.Name = name
	a.Adornee = anchor
	a.Radius = R
	a.InnerRadius = inner
	a.Height = h
	a.Color3 = color
	a.Transparency = tr
	a.CFrame = FLAT
	a.AlwaysOnTop = false
	a.ZIndex = 0
	a.Parent = anchor
	return a
end

function SprinklerModel.RangeCircle(radius, parent)
	local anchor = Instance.new("Part")
	anchor.Name = "RangeCircle"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Parent = parent
	local fill = flatRing(anchor, "Fill", radius, 0, 0.04, GREEN, 0.8)
	local edge = flatRing(anchor, "Edge", radius, radius - 0.28, 0.08, GREEN, 0.1)
	local inner = flatRing(anchor, "Inner", radius - 0.55, radius - 0.65, 0.06, GREEN, 0.6)

	local circle = { Part = anchor, Fill = fill, Edge = edge, Inner = inner, Radius = radius }
	function circle:Place(position)
		anchor.CFrame = CFrame.new(position + Vector3.new(0, 0.07, 0))
	end
	function circle:SetColor(color, innerColor)
		fill.Color3, edge.Color3, inner.Color3 = color, color, innerColor or color
	end
	function circle:SetLook(fillT, edgeT, innerT)
		fill.Transparency, edge.Transparency, inner.Transparency = fillT, edgeT, innerT
	end
	function circle:Destroy()
		anchor:Destroy()
	end
	return circle
end

return SprinklerModel
