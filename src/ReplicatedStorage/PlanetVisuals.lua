-- PlanetVisuals: per-planet surface detail, shine, and particle effects
local PlanetVisuals = {}

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

PlanetVisuals.Styles = {
	Mercury = { Material = Enum.Material.Slate, Reflectance = 0.2 },
	Venus = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.08 },
	Earth = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.08 },
	Mars = { Material = Enum.Material.Slate },
	Jupiter = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.06 },
	Saturn = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.12 },
	Uranus = { Material = Enum.Material.Ice, Reflectance = 0.25 },
	Neptune = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.15 },
}

local function weldTo(base, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
end

local function makeDetailPart(parent, name, shape, size, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addSpot(ball, direction, sizeFraction, color, material, transparency)
	local R = ball.Size.X / 2
	local size = R * 2 * sizeFraction
	local part = makeDetailPart(ball, "Spot", Enum.PartType.Ball, Vector3.new(size, size, size), color, material, transparency)
	part.CFrame = ball.CFrame * CFrame.new(direction.Unit * (R * 0.8))
	weldTo(ball, part)
	return part
end

local function addBands(ball, bands)
	local R = ball.Size.X / 2
	for _, band in ipairs(bands) do
		local y = band.y * R
		local faceRadius = math.sqrt(math.max(R * R - y * y, 1)) + R * 0.04
		local part = makeDetailPart(
			ball,
			"Band",
			Enum.PartType.Cylinder,
			Vector3.new(R * band.thickness, faceRadius * 2, faceRadius * 2),
			Color3.fromRGB(band.color[1], band.color[2], band.color[3]),
			Enum.Material.SmoothPlastic,
			band.transparency
		)
		part.CFrame = ball.CFrame * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
		weldTo(ball, part)
	end
end

local function addShell(ball, scale, color, transparency)
	local part = makeDetailPart(ball, "Clouds", Enum.PartType.Ball, ball.Size * scale, color, Enum.Material.Glass, transparency)
	part.Reflectance = 0.15
	part.CFrame = ball.CFrame
	weldTo(ball, part)
	return part
end

local DECOR = {
	Mercury = function(ball)
		for i = 1, 7 do
			local angle = (i / 7) * math.pi * 2
			addSpot(ball, Vector3.new(math.cos(angle), math.sin(angle * 1.7), math.sin(angle)), 0.16 + (i % 3) * 0.05, Color3.fromRGB(120, 110, 100), Enum.Material.Slate)
		end
	end,
	Venus = function(ball)
		addSpot(ball, Vector3.new(0.4, 0.8, 0.3), 0.5, Color3.fromRGB(240, 205, 140), Enum.Material.SmoothPlastic, 0.25)
		addSpot(ball, Vector3.new(-0.7, -0.3, 0.4), 0.4, Color3.fromRGB(248, 220, 160), Enum.Material.SmoothPlastic, 0.25)
		addShell(ball, 1.1, Color3.fromRGB(255, 236, 180), 0.35)
	end,
	Earth = function(ball)
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			addSpot(ball, Vector3.new(math.cos(angle), math.sin(i * 1.3), math.sin(angle)), 0.34, Color3.fromRGB(76, 160, 80), Enum.Material.Grass)
		end
		addSpot(ball, Vector3.new(0.2, 0.9, 0.5), 0.28, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 0.2)
		addSpot(ball, Vector3.new(-0.8, 0.2, 0.4), 0.24, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 0.2)
		addSpot(ball, Vector3.new(0.3, -0.5, -0.8), 0.26, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 0.2)
		addShell(ball, 1.15, Color3.fromRGB(255, 255, 255), 0.45)
	end,
	Mars = function(ball)
		for i = 1, 5 do
			local angle = (i / 5) * math.pi * 2 + 0.4
			addSpot(ball, Vector3.new(math.cos(angle), math.sin(i * 2.1), math.sin(angle)), 0.3, Color3.fromRGB(140, 58, 36), Enum.Material.Slate)
		end
		addSpot(ball, Vector3.new(0, 1, 0), 0.4, Color3.fromRGB(245, 245, 250), Enum.Material.Ice)
	end,
	Jupiter = function(ball)
		addBands(ball, {
			{ y = 0.55, thickness = 0.16, color = { 224, 186, 140 } },
			{ y = 0.25, thickness = 0.14, color = { 176, 118, 76 } },
			{ y = 0, thickness = 0.18, color = { 236, 206, 166 } },
			{ y = -0.3, thickness = 0.16, color = { 170, 112, 74 } },
			{ y = -0.6, thickness = 0.14, color = { 224, 186, 140 } },
		})
		addSpot(ball, Vector3.new(0.8, -0.35, 0.6), 0.22, Color3.fromRGB(200, 92, 60))
	end,
	Saturn = function(ball)
		addBands(ball, {
			{ y = 0.35, thickness = 0.12, color = { 240, 214, 156 } },
			{ y = 0, thickness = 0.16, color = { 214, 178, 110 } },
			{ y = -0.4, thickness = 0.12, color = { 240, 214, 156 } },
		})
	end,
	Uranus = function(ball)
		addShell(ball, 1.08, Color3.fromRGB(200, 250, 255), 0.4)
	end,
	Neptune = function(ball)
		addSpot(ball, Vector3.new(0.7, -0.4, 0.6), 0.3, Color3.fromRGB(28, 52, 150))
		addShell(ball, 1.06, Color3.fromRGB(120, 170, 255), 0.45)
	end,
}

-- Apply decoration, glow light, and rarity shine to a full-size planet ball
function PlanetVisuals.Apply(ball, planet, rarity)
	local decor = DECOR[planet.Id]
	if decor then
		decor(ball)
	end

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(planet.Color[1], planet.Color[2], planet.Color[3])
	light.Brightness = rarity.Weight >= 5 and 2 or 1
	light.Range = ball.Size.X * 2.2
	light.Parent = ball

	local highlight = ball:FindFirstChild("Shine") or Instance.new("Highlight")
	highlight.Name = "Shine"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(rarity.Color[1], rarity.Color[2], rarity.Color[3])
	highlight.OutlineTransparency = 0
	highlight.Adornee = ball
	highlight.Parent = ball
end

-- Style a freshly planted ball: material, shine, and ambient particles
function PlanetVisuals.StyleGrowing(ball, ring, planet, rarity)
	local style = PlanetVisuals.Styles[planet.Id] or {}
	ball.Material = planet.Rarity == "Mythic" and Enum.Material.ForceField or (style.Material or Enum.Material.SmoothPlastic)
	ball.Reflectance = style.Reflectance or 0

	local shimmer = Instance.new("ParticleEmitter")
	shimmer.Name = "Shimmer"
	shimmer.Color = ColorSequence.new(Color3.fromRGB(planet.Color[1], planet.Color[2], planet.Color[3]), Color3.new(1, 1, 1))
	shimmer.Texture = SPARKLE_TEXTURE
	shimmer.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	shimmer.Lifetime = NumberRange.new(0.8, 1.4)
	shimmer.Rate = 2 + rarity.Weight * 2
	shimmer.Speed = NumberRange.new(0.4, 1.2)
	shimmer.SpreadAngle = Vector2.new(180, 180)
	shimmer.LightEmission = 1
	shimmer.Parent = ball

	if rarity.Weight >= 4 then
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "Aura"
		aura.Color = ColorSequence.new(Color3.fromRGB(rarity.Color[1], rarity.Color[2], rarity.Color[3]))
		aura.Texture = SPARKLE_TEXTURE
		aura.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		aura.Lifetime = NumberRange.new(0.6, 1)
		aura.Rate = rarity.Weight * 2
		aura.Speed = NumberRange.new(1.5, 3)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.LightEmission = 1
		aura.Parent = ball
	end

	local shine = ball:FindFirstChild("Shine") or Instance.new("Highlight")
	shine.Name = "Shine"
	shine.FillTransparency = 1
	shine.OutlineColor = Color3.new(1, 1, 1)
	shine.OutlineTransparency = 0.2
	shine.Adornee = ball
	shine.Parent = ball

	if ring then
		ring.CanQuery = false
		ring.Reflectance = 0.25
		local dust = Instance.new("ParticleEmitter")
		dust.Name = "RingDust"
		dust.Color = ColorSequence.new(ring.Color, Color3.new(1, 1, 1))
		dust.Texture = SPARKLE_TEXTURE
		dust.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.14),
			NumberSequenceKeypoint.new(1, 0),
		})
		dust.Lifetime = NumberRange.new(0.6, 1.1)
		dust.Rate = 6
		dust.Speed = NumberRange.new(0.3, 0.8)
		dust.SpreadAngle = Vector2.new(180, 180)
		dust.LightEmission = 1
		dust.Parent = ring
	end
end

return PlanetVisuals
