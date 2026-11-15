--[[
	SprinklerModel  (ModuleScript)  -- ReplicatedStorage

	Builds the Solar Sprinkler: dark metal pedestal with neon-green strips, a dome core,
	tilted orbit rings and little planets that ride them. Used by SprinklerServer (the real one)
	and SprinklerClient (the see-through placement preview), so both always look the same.

	Bigger sprinklers get more rings and planets:
	  Stardust = 1 ring, 2 planets   Nebula = 2 rings, 3 planets   Cosmic = 3 rings, 4 planets

	SprinklerModel.Build(gear, cframe, ghost) -> model   (PrimaryPart = "Base", spinning part = "Head")
	SprinklerModel.Animate(model, t)                      (client: turns the rings, moves the planets)
	SprinklerModel.RangeCircle(radius, parent) -> circle  (client: green circle on the ground)
]]

local SprinklerModel = {}

SprinklerModel.GREEN = Color3.fromRGB(70, 255, 95)
local GREEN = SprinklerModel.GREEN
local DARK = Color3.fromRGB(34, 37, 44)
local DARKER = Color3.fromRGB(18, 19, 23)
local RING_GREY = Color3.fromRGB(176, 182, 192)
local CENTER_Y = 2.15 -- height of the orbit centre above the ground

local RINGS = {
	{ Radius = 1.5, Tilt = CFrame.Angles(math.rad(12), 0, math.rad(10)), Speed = 0.35 },
	{ Radius = 1.85, Tilt = CFrame.Angles(math.rad(-10), 0, math.rad(-14)), Speed = -0.25 },
	{ Radius = 2.2, Tilt = CFrame.Angles(math.rad(18), 0, math.rad(-4)), Speed = 0.18 },
}
local PLANETS = {
	{ Color = Color3.fromRGB(255, 196, 40), Size = 0.6, Neon = true, Speed = 0.9 },   -- sun
	{ Color = Color3.fromRGB(60, 140, 255), Size = 0.46, Speed = 0.7 },               -- blue
	{ Color = Color3.fromRGB(228, 230, 236), Size = 0.4, Speed = 1.1 },               -- moon
	{ Color = Color3.fromRGB(255, 110, 70), Size = 0.4, Speed = 0.8 },                -- red
}
local TIER = {
	sprinkler_stardust = { Rings = 1, Planets = 2 },
	sprinkler_nebula = { Rings = 2, Planets = 3 },
	sprinkler_cosmic = { Rings = 3, Planets = 4 },
}

local FLAT = CFrame.Angles(math.rad(90), 0, 0) -- handle adornments point along Z; this lays them flat
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder parts lie on X; this stands them up

local function newPart(model, ghost, props)
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
	if ghost then
		p.Material = Enum.Material.Neon
		p.Color = GREEN
		p.Transparency = props.Transparency == 1 and 1 or 0.62
	end
	p.Parent = model
	return p
end

local function arc(adornee, ghost, props)
	local a = Instance.new("CylinderHandleAdornment")
	a.Adornee = adornee
	a.AlwaysOnTop = false
	a.ZIndex = 0
	for k, v in pairs(props) do
		a[k] = v
	end
	if ghost then
		a.Color3 = GREEN
		a.Transparency = 0.5
	end
	a.Parent = adornee
	return a
end

function SprinklerModel.Build(gear, cf, ghost)
	local tier = TIER[gear.Id] or TIER.sprinkler_stardust
	local model = Instance.new("Model")
	model.Name = ghost and "SprinklerPreview" or gear.Name

	-- pedestal
	local base = newPart(model, ghost, {
		Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.3, 2.3),
		CFrame = cf * CFrame.new(0, 0.15, 0) * UPRIGHT, Color = DARK, Material = Enum.Material.Metal,
	})
	newPart(model, ghost, {
		Name = "FootGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 2.42, 2.42),
		CFrame = cf * CFrame.new(0, 0.05, 0) * UPRIGHT, Color = GREEN, Material = Enum.Material.Neon,
	})
	newPart(model, ghost, {
		Name = "Step", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 1.55, 1.55),
		CFrame = cf * CFrame.new(0, 0.36, 0) * UPRIGHT, Color = DARKER, Material = Enum.Material.Metal,
	})
	newPart(model, ghost, {
		Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 0.95, 0.95),
		CFrame = cf * CFrame.new(0, 1.15, 0) * UPRIGHT, Color = DARK, Material = Enum.Material.Metal,
	})
	for i = 1, 4 do
		newPart(model, ghost, {
			Name = "Strip", Size = Vector3.new(0.14, 1.05, 0.06),
			CFrame = cf * CFrame.new(0, 1.15, 0) * CFrame.Angles(0, (i - 1) * math.pi / 2, 0) * CFrame.new(0, 0, -0.47),
			Color = GREEN, Material = Enum.Material.Neon,
		})
	end
	newPart(model, ghost, {
		Name = "CollarGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, 1.32, 1.32),
		CFrame = cf * CFrame.new(0, 1.88, 0) * UPRIGHT, Color = GREEN, Material = Enum.Material.Neon,
	})
	newPart(model, ghost, {
		Name = "Collar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 1.6, 1.6),
		CFrame = cf * CFrame.new(0, 2.02, 0) * UPRIGHT, Color = DARKER, Material = Enum.Material.Metal,
	})

	-- dome core (spins on the client; the stardust sprays out of its nozzles)
	local head = newPart(model, ghost, {
		Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.45, 1.45, 1.45),
		CFrame = cf * CFrame.new(0, 2.1, 0), Color = DARKER, Material = Enum.Material.Metal, Reflectance = 0.08,
	})
	if not ghost then
		for i = 1, 3 do
			local nozzle = Instance.new("Attachment")
			nozzle.Name = "Nozzle" .. i
			nozzle.CFrame = CFrame.Angles(0, (i - 1) * math.pi * 2 / 3, 0) * CFrame.new(0, 0.35, -0.6) * CFrame.Angles(math.rad(45), 0, 0)
			nozzle.Parent = head
		end
	end
	newPart(model, ghost, {
		Name = "Antenna", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 0.1, 0.1),
		CFrame = cf * CFrame.new(0, 2.98, 0) * UPRIGHT, Color = RING_GREY, Material = Enum.Material.Metal,
	})
	newPart(model, ghost, {
		Name = "AntennaTip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = cf * CFrame.new(0, 3.25, 0), Color = gear.Color or GREEN, Material = Enum.Material.Neon,
	})

	-- orbit rings: an invisible centre part holds the ring adornments (cheap, and the client can turn them)
	local core = newPart(model, ghost, {
		Name = "OrbitCore", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = cf * CFrame.new(0, CENTER_Y, 0), Transparency = 1,
	})
	for r = 1, tier.Rings do
		local ring = RINGS[r]
		local R = ring.Radius
		-- metal track, a bright neon line inside it, and a soft glow around both
		arc(core, ghost, { Name = "Ring" .. r, Radius = R, InnerRadius = R - 0.22, Height = 0.16, Color3 = RING_GREY, Transparency = 0 })
		arc(core, ghost, { Name = "Ring" .. r, Radius = R - 0.23, InnerRadius = R - 0.36, Height = 0.1, Color3 = GREEN, Transparency = 0 })
		arc(core, ghost, { Name = "Ring" .. r, Radius = R + 0.12, InnerRadius = R - 0.5, Height = 0.03, Color3 = GREEN, Transparency = 0.75 })
	end
	for i = 1, tier.Planets do
		local info = PLANETS[i]
		local r = ((i - 1) % tier.Rings) + 1
		local p = newPart(model, ghost, {
			Name = "Planet", Shape = Enum.PartType.Ball, Size = Vector3.one * info.Size,
			Color = info.Color, Material = info.Neon and Enum.Material.Neon or Enum.Material.SmoothPlastic,
		})
		p:SetAttribute("Ring", r)
		p:SetAttribute("Phase", (i - 1) * 2.4 + r)
		p:SetAttribute("Speed", info.Speed)
	end
	model.PrimaryPart = base
	SprinklerModel.Animate(model, 0)
	return model
end

-- turn the rings and move the planets along them (client only; t = seconds)
function SprinklerModel.Animate(model, t)
	local core = model:FindFirstChild("OrbitCore")
	if not core then
		return
	end
	local center = core.CFrame
	for _, a in ipairs(core:GetChildren()) do
		if a:IsA("CylinderHandleAdornment") then
			local ring = RINGS[tonumber(string.sub(a.Name, 5))]
			if ring then
				a.CFrame = ring.Tilt * CFrame.Angles(0, t * ring.Speed, 0) * FLAT
			end
		end
	end
	local parts, cframes = {}, {}
	for _, p in ipairs(model:GetChildren()) do
		if p.Name == "Planet" then
			local ring = RINGS[p:GetAttribute("Ring")]
			local angle = p:GetAttribute("Phase") + t * p:GetAttribute("Speed")
			table.insert(parts, p)
			table.insert(cframes, center * ring.Tilt * CFrame.Angles(0, angle, 0) * CFrame.new(ring.Radius - 0.11, 0, 0))
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- a green circle lying on the ground: soft fill + bright edge. Move it with circle:Place(position).
function SprinklerModel.RangeCircle(radius, parent)
	local anchor = Instance.new("Part")
	anchor.Name = "RangeCircle"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = parent
	local fill = arc(anchor, false, { Name = "Fill", Radius = radius, InnerRadius = 0, Height = 0.04, Color3 = GREEN, Transparency = 0.8, CFrame = FLAT })
	local edge = arc(anchor, false, { Name = "Edge", Radius = radius, InnerRadius = radius - 0.28, Height = 0.08, Color3 = GREEN, Transparency = 0.1, CFrame = FLAT })
	local inner = arc(anchor, false, { Name = "Inner", Radius = radius - 0.55, InnerRadius = radius - 0.65, Height = 0.06, Color3 = GREEN, Transparency = 0.6, CFrame = FLAT })

	local circle = { Part = anchor, Fill = fill, Edge = edge, Inner = inner }
	function circle:Place(position)
		anchor.CFrame = CFrame.new(position + Vector3.new(0, 0.07, 0))
	end
	function circle:SetColor(color)
		fill.Color3, edge.Color3, inner.Color3 = color, color, color
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
