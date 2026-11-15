--[[
	PlanetBuilder  (ModuleScript)  -- REPLACES the earlier PlanetBuilder
	Put in: ReplicatedStorage   (name it exactly: PlanetBuilder, next to PlanetCatalog)

	Builds a planet / star / black hole Model out of Parts and glowing rings drawn on
	invisible discs (so every ring is a real, separate ring with an empty middle).

	  PlanetBuilder.Build("earth", workspace)                                  -- full detail, at the origin
	  PlanetBuilder.Build("saturn", workspace, CFrame.new(0, 20, 0), 0.5)      -- placed + half size
	  PlanetBuilder.Build("saturn", viewportFrame, nil, nil, "icon")           -- simple version for small icons

	"icon" mode skips the things a ViewportFrame can't show (glowing rings, halo, debris).

	Full-detail models are tagged "SpinningPlanet". The PlanetSpinner LocalScript makes their
	moons orbit, their rings turn and their surface details rotate on each player's screen.
]]

local CollectionService = game:GetService("CollectionService")

local PlanetCatalog = require(script.Parent:WaitForChild("PlanetCatalog"))

local PlanetBuilder = {}

local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic
local DEFAULT_MOON_COLOR = Color3.fromRGB(190, 190, 196)
local CANVAS = 1024          -- size (in pixels) of the picture drawn on each ring disc
local SPIN_TAG = "SpinningPlanet"

---------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------
local function hashId(id)
	local h = 0
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 100000
	end
	return h
end

local function newPart(props, model)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = model
	return part
end

-- point on a sphere from latitude / longitude in degrees
local function direction(latDeg, lonDeg)
	local lat, lon = math.rad(latDeg), math.rad(lonDeg)
	return Vector3.new(math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon))
end

-- a small ball sitting on the surface (continent, crater, storm, cloud...)
-- `dir` is a direction in the tilted frame; `inset` is how deep the ball sinks in (fraction of its size)
local function addCap(model, tilt, name, dir, diameter, color, material, transparency, R, spin, inset)
	local part = newPart({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		Color = color,
		Material = material,
		Transparency = transparency or 0,
		CastShadow = false,
		CFrame = tilt * CFrame.new(dir * (R - diameter * inset)),
	}, model)
	if spin and spin ~= 0 then
		part:SetAttribute("SpinSpeed", spin)
	end
	return part
end

---------------------------------------------------------------------
-- Rings and glows drawn on invisible discs (SurfaceGui)
---------------------------------------------------------------------
local function addSurfaceGui(part, face, brightness)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(CANVAS, CANVAS)
	gui.LightInfluence = 0
	gui.Brightness = brightness or 1
	gui.AlwaysOnTop = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	return gui
end

-- one thin ring: an empty circle with an outline
local function addRing(gui, outerPx, thickPx, color, transparency, gradient)
	thickPx = math.clamp(thickPx, 1, math.max(outerPx / 2 - 1, 1))
	local innerPx = math.max(outerPx - 2 * thickPx, 2)

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(innerPx, innerPx)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickPx
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	if gradient then
		gradient.Parent = stroke
	end

	frame.Parent = gui
	return frame
end

-- bright and dark streaks along a ring, so you can see it turn
local function streakGradient(rng, amount, count)
	count = count or 10
	local keys = {}
	for i = 0, count do
		local value = (i == 0 or i == count) and 0.12 or rng:NextNumber(0, amount)
		table.insert(keys, NumberSequenceKeypoint.new(i / count, value))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new(keys)
	return gradient
end

-- full detail: every ring is its own turning circle on a flat invisible disc
local function buildRingDisk(model, look, D, tilt, rng)
	local rings = look.Rings
	local maxScale = 0
	local neon = false
	for _, ring in ipairs(rings) do
		maxScale = math.max(maxScale, ring.Scale)
		neon = neon or ring.Neon
	end

	local width = maxScale * D
	local disk = newPart({
		Name = "RingDisk",
		Size = Vector3.new(width, 0.05, width),
		Transparency = 1,
		CastShadow = false,
		CanQuery = false,
		CFrame = tilt,
	}, model)

	for _, face in ipairs({ Enum.NormalId.Top, Enum.NormalId.Bottom }) do
		local gui = addSurfaceGui(disk, face, neon and 2.2 or 1)
		for _, ring in ipairs(rings) do
			local outerPx = ring.Scale / maxScale * CANVAS
			local thickPx = ring.Thick / maxScale * CANVAS
			local gradient = nil
			if ring.Streak then
				gradient = streakGradient(rng, ring.StreakAmount or 0.7)
			end
			local frame = addRing(gui, outerPx, thickPx, ring.Color, ring.Transparency, gradient)
			frame:SetAttribute("SpinSpeed", ring.Speed or 0) -- degrees per second
			frame:SetAttribute("SpinPhase", rng:NextNumber(0, 360))
		end
	end
end

-- icon mode: a few solid stacked discs (a ViewportFrame can't show the glowing rings)
local function buildIconRings(model, look, D, tilt)
	local rings = look.Rings
	local count = #rings
	local n = math.min(4, count)
	local maxScale, minScale = rings[1].Scale, rings[count].Scale

	for k = 1, n do
		local index = (n == 1) and 1 or (1 + math.floor((k - 1) * (count - 1) / (n - 1) + 0.5))
		local ring = rings[index]
		local t = (maxScale == minScale) and 0 or (ring.Scale - minScale) / (maxScale - minScale)
		local diameter = (1.3 + t * 0.8) * D -- compressed so icons stay compact
		newPart({
			Name = "Ring" .. k,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(math.max(0.012 * D * k, 0.05), diameter, diameter),
			Color = ring.Color,
			Material = ring.Neon and Enum.Material.Neon or DEFAULT_MATERIAL,
			CastShadow = false,
			CFrame = tilt * CFrame.Angles(0, 0, math.rad(90)),
		}, model)
	end
end

-- light that always faces the camera: soft glow, bent-light arcs above and below, photon ring, star flare
local function buildHalo(model, look, D)
	local halo = look.Halo
	local width = halo.Scale * D

	local part = newPart({
		Name = "Halo",
		Size = Vector3.new(width, width, 0.05),
		Transparency = 1,
		CastShadow = false,
		CanQuery = false,
		CFrame = CFrame.new(0, 0, 0),
	}, model)
	part:SetAttribute("FaceCamera", true)

	local gui = addSurfaceGui(part, Enum.NormalId.Front, halo.Brightness or 2)

	local function px(inDiameters)
		return inDiameters / halo.Scale * CANVAS
	end

	-- soft glow: stacked see-through circles, biggest first
	local glow = halo.Glow
	if glow then
		for i = 1, glow.Layers do
			local a = (i - 1) / math.max(glow.Layers - 1, 1)
			local size = px(glow.Scale) * (1 - 0.75 * a)

			local circle = Instance.new("Frame")
			circle.AnchorPoint = Vector2.new(0.5, 0.5)
			circle.Position = UDim2.fromScale(0.5, 0.5)
			circle.Size = UDim2.fromOffset(size, size)
			circle.BackgroundColor3 = glow.Color
			circle.BackgroundTransparency = 1 - glow.Opacity
			circle.BorderSizePixel = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = circle
			circle.Parent = gui
		end
	end

	-- arcs of bent light: bright above and below, faint at the sides
	for _, arc in ipairs(halo.Arcs or {}) do
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.28, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.93),
			NumberSequenceKeypoint.new(0.72, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		addRing(gui, px(arc.Scale), px(arc.Thick), arc.Color, arc.Transparency or 0, gradient)
	end

	-- thin bright ring hugging the black hole
	local photon = halo.Photon
	if photon then
		addRing(gui, px(photon.Scale), math.max(px(photon.Thick), 2), photon.Color, 0, nil)
	end

	-- 4-point star flare
	local flare = halo.Flare
	if flare then
		local length = px(flare.Length)
		local thick = math.max(px(flare.Thick), 3)
		for _, rotation in ipairs({ 0, 90 }) do
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.fromOffset(length, thick)
			bar.BackgroundColor3 = flare.Color
			bar.BorderSizePixel = 0
			bar.Rotation = rotation

			local fade = Instance.new("UIGradient")
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			fade.Parent = bar
			bar.Parent = gui
		end
	end
end

---------------------------------------------------------------------
-- Build
---------------------------------------------------------------------
function PlanetBuilder.Build(planetOrId, parent, cframe, scale, mode)
	local planet = planetOrId
	if type(planetOrId) == "string" then
		planet = PlanetCatalog.Get(planetOrId)
	end
	assert(planet, "PlanetBuilder: unknown planet " .. tostring(planetOrId))

	local icon = (mode == "icon")
	local look = planet.Look
	local D = look.Size
	local R = D / 2
	local bodyMaterial = look.Material or DEFAULT_MATERIAL
	local rng = Random.new(hashId(planet.Id))
	local tilt = CFrame.Angles(0, 0, math.rad(look.Tilt or 0))
	local spin = look.Spin or 0

	local model = Instance.new("Model")
	model.Name = planet.Name
	model:SetAttribute("PlanetId", planet.Id)
	model:SetAttribute("Rarity", planet.Rarity)
	model:SetAttribute("Tilt", look.Tilt or 0)
	model:SetAttribute("CollectRegrow", look.Collect and look.Collect.Regrow or nil)

	-- Body (the model's pivot; NOT tilted, everything else is tilted around it)
	local body = newPart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(D, D, D),
		Color = look.Color,
		Material = bodyMaterial,
		CFrame = CFrame.new(0, 0, 0),
	}, model)
	model.PrimaryPart = body

	-- Bands: thin belts wrapped around the planet (gas giants)
	for i, band in ipairs(look.Bands or {}) do
		local h = band.Pos * R
		local thick = band.Thick * D
		local inner = math.max(math.abs(h) - thick / 2, 0)
		local radius = math.sqrt(math.max(R * R - inner * inner, 0)) * 1.01
		newPart({
			Name = "Band" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thick, radius * 2, radius * 2),
			Color = band.Color,
			Material = bodyMaterial,
			CastShadow = false,
			CFrame = tilt * CFrame.new(0, h, 0) * CFrame.Angles(0, 0, math.rad(90)),
		}, model)
	end

	-- Patches: continents, craters, sunspots (spread evenly, then they turn with the planet)
	local patches = look.Patches
	if patches then
		for i = 1, patches.Count do
			local y = 1 - (i - 0.5) / patches.Count * 2
			local ring = math.sqrt(math.max(1 - y * y, 0))
			local theta = GOLDEN_ANGLE * i + rng:NextNumber(0, 1.2)
			local dir = Vector3.new(math.cos(theta) * ring, y, math.sin(theta) * ring)
			local size = patches.Size * D * rng:NextNumber(0.7, 1.2)
			addCap(model, tilt, "Patch" .. i, dir, size, patches.Color, patches.Material or bodyMaterial, 0, R, spin, 0.25)
		end
	end

	-- Spots: placed exactly (polar ice caps, storms)
	for i, spot in ipairs(look.Spots or {}) do
		local size = spot.Size * D
		addCap(model, tilt, "Spot" .. i, direction(spot.Lat, spot.Lon), size, spot.Color,
			spot.Material or bodyMaterial, 0, R, spin, 0.25)
	end

	-- Clouds: puffs that turn a little faster than the ground
	local clouds = look.Clouds
	if clouds then
		for i = 1, clouds.Count do
			local y = 1 - (i - 0.5) / clouds.Count * 2
			local ring = math.sqrt(math.max(1 - y * y, 0))
			local theta = GOLDEN_ANGLE * i * 1.7 + rng:NextNumber(0, 1.5)
			local dir = Vector3.new(math.cos(theta) * ring, y, math.sin(theta) * ring)
			local size = clouds.Size * D * rng:NextNumber(0.7, 1.3)
			addCap(model, tilt, "Cloud" .. i, dir, size, clouds.Color, DEFAULT_MATERIAL,
				clouds.Transparency or 0.35, R, spin * 1.7, 0.1)
		end
	end

	-- Atmosphere glow
	local glow = look.Glow
	if glow then
		local size = D * glow.Size
		newPart({
			Name = "Glow",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			Color = glow.Color,
			Material = Enum.Material.Neon,
			Transparency = glow.Transparency,
			CastShadow = false,
			CanQuery = false,
			CFrame = CFrame.new(0, 0, 0),
		}, model)
	end

	-- Rings
	if look.Rings and #look.Rings > 0 then
		if icon then
			buildIconRings(model, look, D, tilt)
		else
			buildRingDisk(model, look, D, tilt, rng)
		end
	end

	-- Moons (they orbit: the PlanetSpinner moves them)
	for i, moon in ipairs(look.Moons or {}) do
		local size = moon.Size * D
		local collectible = look.Collect ~= nil and look.Collect.MoonValue ~= nil
		if collectible then
			size = math.max(size, 2.4) -- keep collectible moons big enough to spot once the planet is small
		end
		local angle = math.rad(moon.Angle or (i * 120))
		local distance = moon.Distance * D
		local part = newPart({
			Name = "Moon" .. i,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			Color = moon.Color or DEFAULT_MOON_COLOR,
			Material = (moon.Neon or collectible) and Enum.Material.Neon or Enum.Material.Concrete, -- glowing = collectible
			CFrame = tilt * CFrame.new(math.cos(angle) * distance, 0, math.sin(angle) * distance),
		}, model)
		if moon.Speed and moon.Speed ~= 0 then
			part:SetAttribute("SpinSpeed", moon.Speed)
		end
		if look.Collect and look.Collect.MoonValue then
			part:SetAttribute("CoinValue", look.Collect.MoonValue) -- can be collected for coins
		end
	end

	-- Debris: rocks orbiting the black hole
	local debris = look.Debris
	if debris and not icon then
		for i = 1, debris.Count do
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(debris.MinRadius, debris.MaxRadius)
			local height = rng:NextNumber(-debris.Height, debris.Height) * D
			local size = debris.Size * D * rng:NextNumber(0.5, 1.3)
			if look.Collect and look.Collect.DebrisValue then
				size = math.max(size, 1.8) -- keep collectible rocks big enough to spot
			end
			local shade = rng:NextNumber(0.7, 1.15)
			local part = newPart({
				Name = "Debris" .. i,
				Size = Vector3.new(size, size * rng:NextNumber(0.5, 1), size * rng:NextNumber(0.6, 1.2)),
				Color = Color3.new(
					math.min(debris.Color.R * shade, 1),
					math.min(debris.Color.G * shade, 1),
					math.min(debris.Color.B * shade, 1)
				),
				Material = debris.Neon and Enum.Material.Neon or Enum.Material.Slate,
				CastShadow = false,
				CFrame = tilt
					* CFrame.new(math.cos(angle) * radius * D, height, math.sin(angle) * radius * D)
					* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			}, model)
			-- inner rocks orbit faster than outer ones
			part:SetAttribute("SpinSpeed", debris.Speed * (debris.MinRadius / radius) ^ 1.5)
			if look.Collect and look.Collect.DebrisValue then
				part:SetAttribute("CoinValue", look.Collect.DebrisValue) -- can be collected for coins
			end
		end
	end

	-- Halo (always faces the camera)
	if look.Halo and not icon then
		buildHalo(model, look, D)
	end

	-- Light (sun, black holes)
	local light = look.Light
	if light then
		-- a short light that shines straight down: a pool of light right under the planet, not across the whole garden
		local spotLight = Instance.new("SpotLight")
		spotLight.Face = Enum.NormalId.Bottom
		spotLight.Angle = 110
		spotLight.Color = light.Color
		spotLight.Range = math.min(light.Range, D * 1.3)
		spotLight.Brightness = light.Brightness
		spotLight.Shadows = false
		spotLight.Parent = body
	end

	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	if cframe then
		model:PivotTo(cframe)
	end
	if not icon then
		-- keep every part of the model together when the game streams parts in and out
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	model.Parent = parent

	if not icon then
		CollectionService:AddTag(model, SPIN_TAG)
	end

	return model
end

return PlanetBuilder
