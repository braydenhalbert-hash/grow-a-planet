--[[
	SprinklerClient  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	* Holding a sprinkler (gear shop): a see-through preview and its exact range circle follow your
	  mouse over your garden beds (green = OK, red = can't place there); your planets inside the
	  circle light up green. Click to place. Phones: tap to move it, tap inside the circle to place.
	  Unequip to cancel.
	* Placed sprinklers: rings turn, planets orbit, energy flows; they spray arcs of their own
	  stardust (Stardust module) and it spreads over the whole circle: motes rising, plus galaxies /
	  nebulae / stars / quantum glyphs / void vortexes on the ground, a glowing ground ring, waves,
	  light beams and supernova flashes depending on the sprinkler. Far away: only the model glows.
	* Planets in range: that sprinkler's stardust floats around them. BLACK HOLES suck it in.

	Needs: SprinklerServer, GearCatalog, SprinklerModel, Stardust.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local SprinklerModel = require(ReplicatedStorage:WaitForChild("SprinklerModel"))
local Stardust = require(ReplicatedStorage:WaitForChild("Stardust"))
local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local placeRemote = remotes:WaitForChild("PlaceGear", 30)

local PAD_TAG = "GardenPad"
local SHOW_DISTANCE = 200
local DETAIL_DISTANCE = 110 -- ground effects, beams and waves only this close (keeps phones smooth)
local GRAVITY = 30 -- how fast the stardust arcs fall

local fxFolder = Instance.new("Folder")
fxFolder.Name = "SprinklerFX"
fxFolder.Parent = workspace

local function invisiblePart(name, size, cframe, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = fxFolder
	return p
end

-- a big soft glow ring lying on the ground (our own texture), slowly turning
local function groundGlow(parent, radius, color, transparency)
	if Stardust.Tex.Ground == "" then
		return nil
	end
	local p = invisiblePart("GroundGlow", Vector3.new(radius * 2, 0.05, radius * 2), CFrame.new())
	p.Parent = parent
	local d = Instance.new("Decal")
	d.Face = Enum.NormalId.Top
	d.Texture = Stardust.Tex.Ground
	d.Color3 = color
	d.Transparency = transparency
	d.Parent = p
	return p
end

---------------------------------------------------------------------
-- Placing: see-through sprinkler + range circle + highlight on the planets it will reach
---------------------------------------------------------------------
local camera = workspace.CurrentCamera
local ghost, ghostCircle, ghostGear = nil, nil, nil
local ghostSpot, ghostPad = nil, nil
local ghostAccent, ghostOk, ghostAura, ghostGlow = nil, nil, nil, nil
local touchPoint = nil -- mobile: where the player last tapped in the world
local highlights = {} -- planet model -> Highlight
local MAX_HIGHLIGHTS = 25 -- Roblox only draws about 31 highlights at once
local RED = Color3.fromRGB(255, 70, 70)

local function clearHighlights(keep)
	for model, h in pairs(highlights) do
		if not keep or not keep[model] then
			h:Destroy()
			highlights[model] = nil
		end
	end
end

-- the spot you picked (click or tap); the preview stays there until you press ✓ or X
local lockedSpot, lockedPad = nil, nil

---------------------------------------------------------------------
-- ✓ / X buttons on the right side: confirm placing the sprinkler right where the preview is
---------------------------------------------------------------------
local BUTTON_SIZE = 70
local confirmGui = Instance.new("ScreenGui")
confirmGui.Name = "SprinklerPlaceGui"
confirmGui.ResetOnSpawn = false
confirmGui.DisplayOrder = 5
confirmGui.Parent = player:WaitForChild("PlayerGui")

local confirmHolder = Instance.new("Frame")
confirmHolder.Name = "PlaceButtons"
confirmHolder.AnchorPoint = Vector2.new(1, 0.5)
confirmHolder.Position = UDim2.new(1, -14, 0.45, 0)
confirmHolder.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE * 2 + 14)
confirmHolder.BackgroundTransparency = 1
confirmHolder.Visible = false
confirmHolder.Parent = confirmGui
local confirmLayout = Instance.new("UIListLayout")
confirmLayout.Padding = UDim.new(0, 14)
confirmLayout.SortOrder = Enum.SortOrder.LayoutOrder
confirmLayout.Parent = confirmHolder

local function roundButton(name, order, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.Font = Enum.Font.FredokaOne
	button.Text = text
	button.TextSize = 40
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = confirmHolder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(20, 20, 30)
	textStroke.Thickness = 2
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = button
	return button
end
local confirmButton = roundButton("Place", 1, "✓", Color3.fromRGB(60, 200, 90))
local cancelButton = roundButton("Cancel", 2, "X", Color3.fromRGB(225, 60, 60))

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "Hint"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 1, -120)
hintLabel.Size = UDim2.fromOffset(520, 30)
hintLabel.BackgroundTransparency = 1
hintLabel.Font = Enum.Font.FredokaOne
hintLabel.TextSize = 20
hintLabel.TextColor3 = Color3.new(1, 1, 1)
hintLabel.TextStrokeTransparency = 0.2
hintLabel.Visible = false
hintLabel.Parent = confirmGui

local function unlock()
	lockedSpot, lockedPad = nil, nil
	confirmHolder.Visible = false
end

local function clearGhost()
	unlock()
	hintLabel.Visible = false
	if ghost then
		ghost:Destroy()
	end
	if ghostCircle then
		ghostCircle:Destroy()
	end
	clearHighlights()
	ghost, ghostCircle, ghostGear, ghostSpot, ghostPad, touchPoint, ghostAura, ghostGlow = nil, nil, nil, nil, nil, nil, nil, nil
end

local function makeGhost(gear)
	clearGhost()
	ghostGear = gear
	ghost = SprinklerModel.Build(gear, CFrame.new(0, -500, 0), true)
	ghost.Parent = fxFolder
	ghostCircle = SprinklerModel.RangeCircle(gear.Radius, fxFolder)
	ghostCircle:SetLook(0.78, 0.05, 0.3)
	ghostAccent = SprinklerModel.RarityColor[gear.Rarity] or SprinklerModel.GREEN
	ghostOk = nil
	ghostGlow = groundGlow(ghostCircle.Part, gear.Radius, ghostAccent, 0.35)
	-- Epic and up: their sparkles already dance inside the preview circle
	local tier = SprinklerModel.RarityTier[gear.Rarity] or 1
	if tier >= 4 then
		local disc = invisiblePart("PreviewAura", Vector3.new(gear.Radius * 1.9, 0.2, gear.Radius * 1.9), CFrame.new())
		disc.Parent = ghostCircle.Part
		local e = Instance.new("ParticleEmitter")
		e.Texture = Stardust.Texture("Star")
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Shape = Enum.ParticleEmitterShape.Disc
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.EmissionDirection = Enum.NormalId.Top
		e.Color = ColorSequence.new(Color3.new(1, 1, 1), ghostAccent)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(1, 1.8)
		e.Speed = NumberRange.new(0.6, 1.5)
		e.Rate = 4 + tier * 3
		e.Parent = disc
		ghostAura = disc
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function screenRay()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	if touchOnly then
		local point = touchPoint or camera.ViewportSize / 2
		return camera:ViewportPointToRay(point.X, point.Y)
	end
	return mouse.UnitRay
end

local function aim(ray)
	-- what is the mouse (or finger) pointing at? skips characters, planets, effects
	local ignore = { fxFolder }
	for _, name in ipairs({ "PlantedPlanets", "Sprinklers", "HeldPlanets", "MutationFX", "AudioFX" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	ray = ray or screenRay()
	return workspace:Raycast(ray.Origin, ray.Direction * 600, rayParams)
end

local function canPlaceOn(part)
	if not part or not CollectionService:HasTag(part, PAD_TAG) then
		return false
	end
	return part:GetAttribute("BaseOwner") == player.UserId -- only your own claimed base
end

-- the exact spot the server will use (it snaps onto the top of the bed, 1.2 studs inside its edges)
local function snapToPad(pad, position)
	local localPos = pad.CFrame:PointToObjectSpace(position)
	local half = pad.Size / 2
	localPos = Vector3.new(
		math.clamp(localPos.X, -half.X + 1.2, half.X - 1.2),
		half.Y,
		math.clamp(localPos.Z, -half.Z + 1.2, half.Z - 1.2)
	)
	return pad.CFrame:PointToWorldSpace(localPos)
end

local function heldGear()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("Kind") == "Gear" then
		return tool, GearCatalog.Get(tool:GetAttribute("GearId"))
	end
	return nil, nil
end

local function place()
	if ghostGear and ghostSpot and ghostPad and placeRemote then
		placeRemote:FireServer(ghostGear.Id, ghostSpot, ghostPad)
	end
	unlock()
end

-- pick this spot: the preview stays put and the ✓ / X buttons show up
local function lockAt(hit)
	if not ghostGear or not hit or not canPlaceOn(hit.Instance) then
		return
	end
	lockedPad = hit.Instance
	lockedSpot = snapToPad(hit.Instance, hit.Position)
	confirmHolder.Visible = true
end

confirmButton.Activated:Connect(function()
	if lockedSpot then
		place()
	end
end)
cancelButton.Activated:Connect(function()
	unlock()
	touchPoint = nil
end)

local hooked = setmetatable({}, { __mode = "k" })
local function hookTool(tool)
	if hooked[tool] then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
			return -- phones and tablets pick the spot with a tap (below)
		end
		lockAt(aim(mouse.UnitRay)) -- click = put the preview here, then ✓ places it
	end)
end

-- mobile: a tap moves the preview there, then ✓ places it
UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
	if processedByUI or not ghostGear then
		return
	end
	touchPoint = position
	lockAt(aim(mouse.UnitRay)) -- the game's own ray for the tap: lands right under the finger
end)

local function flatDistance(a, b)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local plantsFolder = workspace:WaitForChild("PlantedPlanets", 30)

local function updateHighlights(spot, radius)
	-- same rule as the server: YOUR planets whose centre is within the radius (flat distance)
	local inRange = {}
	if spot and plantsFolder then
		local list = {}
		for _, model in ipairs(plantsFolder:GetChildren()) do
			if model:GetAttribute("Owner") == player.UserId then
				local d = flatDistance(model:GetPivot().Position, spot)
				if d <= radius then
					table.insert(list, { Model = model, D = d })
				end
			end
		end
		table.sort(list, function(x, y)
			return x.D < y.D
		end)
		for i = 1, math.min(#list, MAX_HIGHLIGHTS) do
			inRange[list[i].Model] = true
		end
	end
	clearHighlights(inRange)
	for model in pairs(inRange) do
		if not highlights[model] then
			local h = Instance.new("Highlight")
			h.Adornee = model
			h.FillColor = SprinklerModel.GREEN
			h.FillTransparency = 0.82
			h.OutlineColor = SprinklerModel.GREEN
			h.OutlineTransparency = 0.35
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = fxFolder
			highlights[model] = h
		end
	end
end

local nextHighlight = 0
RunService.RenderStepped:Connect(function()
	local tool, gear = heldGear()
	if not gear then
		if ghost then
			clearGhost() -- unequipped = placement cancelled
		end
		return
	end
	hookTool(tool)
	if not ghostGear or ghostGear.Id ~= gear.Id then
		makeGhost(gear)
	end
	local ok, spot, hit
	if lockedSpot and lockedPad and lockedPad.Parent and canPlaceOn(lockedPad) then
		ok, spot, hit = true, lockedSpot, { Instance = lockedPad }
	else
		if lockedSpot then
			unlock()
		end
		hit = aim()
		ok = hit and canPlaceOn(hit.Instance)
		spot = hit and (ok and snapToPad(hit.Instance, hit.Position) or hit.Position)
	end
	hintLabel.Visible = true
	if lockedSpot then
		hintLabel.Text = "Press ✓ to place your sprinkler here, or X to move it"
	elseif UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		hintLabel.Text = "Tap your garden to move the sprinkler there"
	else
		hintLabel.Text = "Click your garden to put the sprinkler there"
	end
	ghostSpot = ok and spot or nil
	ghostPad = ok and hit.Instance or nil
	if not spot then
		ghost.Parent, ghostCircle.Part.Parent = nil, nil
		clearHighlights()
		return
	end
	ghost.Parent, ghostCircle.Part.Parent = fxFolder, fxFolder
	ghost:PivotTo(CFrame.new(spot + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)))
	SprinklerModel.Animate(ghost, os.clock())
	ghostCircle:Place(spot)
	if ghostAura then
		ghostAura.CFrame = CFrame.new(spot + Vector3.new(0, 0.3, 0))
	end
	if ghostGlow then
		ghostGlow.CFrame = CFrame.new(spot + Vector3.new(0, 0.09, 0)) * CFrame.Angles(0, os.clock() * 0.3, 0)
	end
	if ok ~= ghostOk then
		-- green = can place, red = can't; the inner line shows the sprinkler's rarity colour
		ghostOk = ok
		local color = ok and SprinklerModel.GREEN or RED
		ghostCircle:SetColor(color, ok and ghostAccent or RED)
		for _, p in ipairs(ghost:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Color = color
			elseif p:IsA("HandleAdornment") then
				p.Color3 = color
			end
		end
	end
	local now = os.clock()
	if now >= nextHighlight then
		nextHighlight = now + 0.1
		updateHighlights(ok and spot or nil, gear.Radius)
	end
end)

---------------------------------------------------------------------
-- Placed sprinklers: spinning head + stardust spray
---------------------------------------------------------------------
local sprinklers = {} -- model -> state (see setupSprinkler)
local scriptStart = os.clock()

local function sprayEmitter(nozzle, style, radius, height, nozzles, tier)
	-- arcs of the sprinkler's own stardust, fast enough to land near the edge of its range
	local speed = math.sqrt(radius * GRAVITY) * 0.95 * math.clamp(1 - height / (radius * 3), 0.6, 1)
	local big = style.Spray == "Galaxy" or style.Spray == "Quantum" or style.Spray == "Wisp"
	local size = (big and 0.75 or 0.5) + tier * 0.03
	local e = Stardust.Emitter(style.Spray, style.Palette, {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.35) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.1, 1.4),
		Speed = NumberRange.new(speed * 0.55, speed),
		SpreadAngle = Vector2.new(6, 6),
		Acceleration = Vector3.new(0, -GRAVITY, 0),
		Rate = math.clamp(84 / nozzles, 10, 26), -- more nozzles = fewer particles each, same total
		RotSpeed = NumberRange.new(-180, 180),
		EmissionDirection = Enum.NormalId.Front,
	})
	e.Parent = nozzle
	return e
end

-- what lies on the ground inside the circle, per style (flat particles facing up)
local GROUND = {
	spin = { Size = { 1.6, 3.2 }, Life = { 4, 6 }, Rot = 25, Rate = 0.35, Base = 1.2, Fade = 0.3 },
	drift = { Size = { 3, 5 }, Life = { 4.5, 6 }, Rot = 8, Rate = 0.3, Base = 1, Fade = 0.55 },
	flare = { Size = { 0.9, 1.7 }, Life = { 1, 1.8 }, Rot = 40, Rate = 0.6, Base = 2, Fade = 0.1 },
	flicker = { Size = { 0.9, 1.5 }, Life = { 0.45, 0.9 }, Rot = 0, Rate = 0.6, Base = 3, Fade = 0.1 },
	void = { Size = { 1.6, 2.8 }, Life = { 3, 4 }, Rot = 70, Rate = 0.3, Base = 1, Fade = 0.25 },
}

local function groundEmitter(parent, style, tier)
	local g = GROUND[style.Mode]
	if not g then
		return nil
	end
	local e = Stardust.Emitter(style.Ground, style.Palette, {
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.02, 0.02),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, g.Size[1] * 0.6), NumberSequenceKeypoint.new(0.5, g.Size[2]), NumberSequenceKeypoint.new(1, g.Size[1]) }),
		Lifetime = NumberRange.new(g.Life[1], g.Life[2]),
		RotSpeed = NumberRange.new(-g.Rot, g.Rot),
		Rate = g.Base + tier * g.Rate,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, g.Fade), NumberSequenceKeypoint.new(0.7, g.Fade), NumberSequenceKeypoint.new(1, 1) }),
	})
	e.Parent = parent
	return e
end

local function flatRing(anchor, R, width, color, transparency)
	local a = Instance.new("CylinderHandleAdornment")
	a.Adornee = anchor
	a.Radius = R
	a.InnerRadius = math.max(0, R - width)
	a.Height = 0.06
	a.Color3 = color
	a.Transparency = transparency
	a.CFrame = CFrame.Angles(math.rad(90), 0, 0)
	a.Parent = anchor
	return a
end

local function randomPointIn(center, radius)
	local r = radius * math.sqrt(math.random()) * 0.92
	local a = math.random() * math.pi * 2
	return center + Vector3.new(math.cos(a) * r, 0.1, math.sin(a) * r)
end

-- one-off flash when a sprinkler is placed: shock ring across its range + a burst of sparkles
local function placementBurst(ground, core, radius, color, size)
	local anchor = invisiblePart("Burst", Vector3.new(0.2, 0.2, 0.2), CFrame.new(ground + Vector3.new(0, 0.12, 0)))
	local ring = flatRing(anchor, 1, 0.6, color, 0)
	local flash = invisiblePart("Flash", Vector3.one, CFrame.new(core), Enum.PartType.Ball)
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Transparency = 0.2
	local e = Instance.new("ParticleEmitter")
	e.Texture = Stardust.Texture("Star")
	e.LightEmission = 1
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.Size = NumberSequence.new(0.5 + size * 0.06, 0)
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(6, 10 + size * 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 2
	e.Enabled = false
	e.Parent = flash
	e:Emit(15 + size * 12)
	local start = os.clock()
	local duration = 0.7 + size * 0.08
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local f = (os.clock() - start) / duration
		if f >= 1 then
			conn:Disconnect()
			anchor:Destroy()
			task.delay(1.5, function()
				flash:Destroy()
			end)
			flash.Transparency = 1
			return
		end
		local ease = 1 - (1 - f) ^ 3
		ring.Radius = 1 + (radius - 1) * ease
		ring.InnerRadius = math.max(0, ring.Radius - 0.5 - size * 0.1)
		ring.Transparency = f
		flash.Size = Vector3.one * (1 + size * 0.9 * ease)
		flash.Transparency = 0.2 + 0.8 * f
	end)
end

local function setupSprinkler(model)
	if not model:IsA("Model") or sprinklers[model] then
		return
	end
	local head = model:WaitForChild("Head", 5)
	local base = model:WaitForChild("Base", 5)
	if not head or not base then
		return
	end
	local gearId = model:GetAttribute("GearId")
	local gear = GearCatalog.Get(gearId or "")
	local fx = SprinklerModel.Fx(gearId)
	local style = Stardust.Get(gearId)
	local tier = SprinklerModel.RarityTier[gear and gear.Rarity or "Uncommon"] or 2
	local color = model:GetAttribute("DustColor") or Color3.new(1, 1, 1)
	local accent = fx.Circle or SprinklerModel.GREEN
	local radius = model:GetAttribute("Radius") or 9
	local ground = base.Position - Vector3.new(0, base.Size.X / 2, 0)
	local height = head.Position.Y - ground.Y

	local emitters, detail = {}, {}
	local nozzles = {}
	for _, nozzle in ipairs(head:GetChildren()) do
		if nozzle:IsA("Attachment") then
			table.insert(nozzles, nozzle)
		end
	end
	for _, nozzle in ipairs(nozzles) do
		table.insert(emitters, sprayEmitter(nozzle, style, radius, height, #nozzles, tier))
	end
	-- the model's own glows/particles (switched off when you're far away)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("PointLight") then
			table.insert(emitters, d)
		end
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = head

	-- soft glowing circle in the sprinkler's colour showing exactly what it covers
	local circle = SprinklerModel.RangeCircle(radius, fxFolder)
	circle:Place(ground)
	circle:SetColor(accent)
	circle:SetLook(0.9, 0.45, 0.8)

	local state = {
		Head = head, Base = base, Emitters = emitters, Angle = math.random() * 6.28, Home = head.CFrame,
		Circle = circle, Fx = fx, Tier = tier, Accent = accent, Radius = radius, Ground = ground,
		Detail = detail, GlowAngle = math.random() * 6.28,
		NextWave = os.clock() + math.random() * 2, NextNova = os.clock() + (fx.Nova or 0), NextBeams = 0,
	}

	-- stardust spreading through the whole watering radius: motes drifting up from the ground...
	local disc = invisiblePart("Aura", Vector3.new(radius * 1.9, 0.2, radius * 1.9), CFrame.new(ground + Vector3.new(0, 0.3, 0)))
	disc.Parent = circle.Part
	local rise = Stardust.Emitter(style.Aura == "Nebula" and "Dust" or style.Aura, style.Palette, {
		Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.3 + tier * 0.03), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1.6, 2.8),
		Speed = NumberRange.new(0.6, 1.6),
		Rate = fx.Aura or (3 + tier * 2),
	})
	rise.Parent = disc
	table.insert(detail, rise)
	-- ...plus galaxies / nebulae / stars / glyphs / vortexes lying on the ground (Rare and up)
	if tier >= 3 then
		local flat = groundEmitter(disc, style, tier)
		if flat then
			table.insert(detail, flat)
		end
		-- void sprinklers: dark motes sink back into the ground
		if style.Mode == "void" then
			local sink = Stardust.Emitter("Dust", { Color3.fromRGB(30, 10, 50), Color3.fromRGB(60, 20, 100), Color3.fromRGB(20, 0, 40) }, {
				LightEmission = 0, Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(0.3, 0.6), Acceleration = Vector3.new(0, -0.8, 0),
				Size = NumberSequence.new(0.5, 0.2), Lifetime = NumberRange.new(1.5, 2), Rate = 4 + tier,
			})
			sink.Parent = disc
			table.insert(detail, sink)
		end
	end
	local glow = groundGlow(circle.Part, radius, accent, math.clamp(0.55 - tier * 0.04, 0.12, 0.5))
	if glow then
		glow.CFrame = CFrame.new(ground + Vector3.new(0, 0.09, 0))
		state.Glow = glow
	end

	-- light streams from the core down into the garden
	if fx.Beams then
		state.Beams = {}
		local src = Instance.new("Attachment")
		src.Parent = head
		for i = 1, fx.Beams do
			local dst = Instance.new("Attachment")
			dst.Parent = circle.Part
			local beam = Instance.new("Beam")
			beam.Attachment0 = src
			beam.Attachment1 = dst
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Segments = 12
			beam.Width0 = 0.18 + tier * 0.02
			beam.Width1 = 0.04
			beam.Color = ColorSequence.new(Color3.new(1, 1, 1), accent)
			beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.7, 0.5), NumberSequenceKeypoint.new(1, 1) })
			beam.Parent = circle.Part
			table.insert(state.Beams, { Beam = beam, Dst = dst })
		end
	end

	-- rolling pulse rings
	if fx.Wave then
		state.WaveAnchor = invisiblePart("Wave", Vector3.new(0.2, 0.2, 0.2), CFrame.new(ground + Vector3.new(0, 0.1, 0)))
		state.WaveAnchor.Parent = circle.Part
		state.WaveRing = flatRing(state.WaveAnchor, 1, 0.35, accent, 1)
	end

	-- supernova flash
	if fx.Nova then
		state.NovaBall = invisiblePart("Nova", Vector3.one, head.CFrame, Enum.PartType.Ball)
		state.NovaBall.Material = Enum.Material.ForceField
		state.NovaBall.Color = accent
		state.NovaBall.Transparency = 1
		state.NovaBall.Parent = circle.Part
	end

	sprinklers[model] = state
	if os.clock() - scriptStart > 3 then
		placementBurst(ground, head.Position, radius, accent, fx.Burst or 2)
	end
end

local sprinklerFolder = workspace:WaitForChild("Sprinklers", 30)
if sprinklerFolder then
	for _, m in ipairs(sprinklerFolder:GetChildren()) do
		task.spawn(setupSprinkler, m)
	end
	sprinklerFolder.ChildAdded:Connect(function(m)
		task.spawn(setupSprinkler, m)
	end)
	sprinklerFolder.ChildRemoved:Connect(function(m)
		if sprinklers[m] then
			sprinklers[m].Circle:Destroy()
			sprinklers[m] = nil
		end
	end)
end

local function updateSprinklerFx(s, now)
	-- pulse rings rolling out to the edge
	if s.WaveRing then
		local period = s.Fx.Wave
		local f = (now - s.NextWave) / 1.6
		if f >= 1 then
			s.NextWave = now + period
			s.WaveRing.Transparency = 1
		elseif f >= 0 then
			local R = 1 + (s.Radius - 1) * f
			s.WaveRing.Radius = R
			s.WaveRing.InnerRadius = math.max(0, R - 0.35)
			s.WaveRing.Transparency = 0.3 + 0.7 * f
		end
	end
	-- beams jump to new spots in the garden
	if s.Beams and now >= s.NextBeams then
		s.NextBeams = now + 0.7
		for _, b in ipairs(s.Beams) do
			b.Dst.WorldPosition = randomPointIn(s.Ground, s.Radius)
			b.Beam.CurveSize0 = math.random(-6, 6)
			b.Beam.CurveSize1 = math.random(-2, 2)
		end
	end
	-- supernova: a bright shell blows out from the core
	if s.NovaBall then
		local f = (now - s.NextNova) / 0.9
		if f >= 1 then
			s.NextNova = now + s.Fx.Nova
			s.NovaBall.Transparency = 1
		elseif f >= 0 then
			s.NovaBall.CFrame = s.Head.CFrame
			s.NovaBall.Size = Vector3.one * (1 + f * (6 + s.Tier))
			s.NovaBall.Transparency = f
		end
	end
	s.Circle.Edge.Transparency = 0.45 + 0.15 * math.sin(now * 2)
end

---------------------------------------------------------------------
-- Stardust around planets in range (black holes suck it in)
---------------------------------------------------------------------
local dusted = {} -- planet model -> { Shell, Emitters }

local function addDust(model)
	local body = model.PrimaryPart
	if not body then
		return nil
	end
	local planet = PlanetCatalog.Get(model:GetAttribute("PlanetId") or "")
	local color = model:GetAttribute("StardustColor") or Color3.new(1, 1, 1)
	local style = Stardust.Get(model:GetAttribute("StardustStyle"))
	local size = model:GetExtentsSize()
	local shellRadius = math.clamp(math.max(size.X, size.Z) * 0.6, 2.5, 18)
	local shell = invisiblePart("StardustShell", Vector3.one * shellRadius * 2, body.CFrame, Enum.PartType.Ball)
	local isBlackHole = model:GetAttribute("Group") == "BlackHole" or (planet and planet.Group == "BlackHole")

	-- the stardust of whichever sprinkler is watering it
	local e = Stardust.Emitter(style.Planet, style.Palette)
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	if isBlackHole then
		-- pulled straight into the middle and gone
		local lifetime = 1.3
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		e.Lifetime = NumberRange.new(lifetime, lifetime)
		e.Speed = NumberRange.new(shellRadius / lifetime * 0.98, shellRadius / lifetime)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.04) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0), NumberSequenceKeypoint.new(1, 0.3) })
		e.Rate = 30
	else
		-- floating around it like a glittering atmosphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Lifetime = NumberRange.new(2, 3.2)
		e.Speed = NumberRange.new(0.2, 0.7)
		e.Drag = 0.6
		e.Acceleration = Vector3.new(0, 0.25, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.32), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0.1)
		e.Rate = 14
	end
	e.Parent = shell
	return { Shell = shell, Emitter = e, Body = body }
end

local function removeDust(model)
	local d = dusted[model]
	if d then
		dusted[model] = nil
		d.Shell:Destroy()
	end
end

local nextScan = 0

RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero

	-- spin the heads
	for model, s in pairs(sprinklers) do
		if not model.Parent then
			s.Circle:Destroy()
			sprinklers[model] = nil
		else
			local dist = (s.Base.Position - camPos).Magnitude
			local near = dist <= SHOW_DISTANCE
			local close = dist <= DETAIL_DISTANCE
			if near ~= s.Near then
				s.Near = near
				for _, e in ipairs(s.Emitters) do
					e.Enabled = near
				end
				s.Circle.Part.Parent = near and fxFolder or nil
			end
			if close ~= s.Close then
				-- far away: keep the model's own glow, drop the ground stardust (saves a lot on phones)
				s.Close = close
				for _, e in ipairs(s.Detail) do
					e.Enabled = close
				end
			end
			if near then
				local now = os.clock()
				s.Angle += dt * 2.4
				s.Head.CFrame = s.Home * CFrame.Angles(0, s.Angle, 0)
				SprinklerModel.Animate(model, now)
				if close then
					updateSprinklerFx(s, now)
					if s.Glow then
						s.GlowAngle += dt * 0.15
						s.Glow.CFrame = CFrame.new(s.Ground + Vector3.new(0, 0.09, 0)) * CFrame.Angles(0, s.GlowAngle, 0)
					end
				end
			end
		end
	end

	-- every half second: which planets are being sprinkled right now?
	local now = os.clock()
	if now < nextScan or not plantsFolder then
		return
	end
	nextScan = now + 0.5
	local serverNow = workspace:GetServerTimeNow()
	for _, model in ipairs(plantsFolder:GetChildren()) do
		local untilTime = model:GetAttribute("StardustUntil")
		local body = model.PrimaryPart
		local on = untilTime and untilTime > serverNow and body and (body.Position - camPos).Magnitude <= SHOW_DISTANCE
		if on and not dusted[model] then
			dusted[model] = addDust(model)
		elseif not on and dusted[model] then
			removeDust(model)
		end
		local d = dusted[model]
		if d and d.Body.Parent then
			d.Shell.CFrame = d.Body.CFrame -- planets rise as they grow
		end
	end
	for model in pairs(dusted) do
		if not model.Parent then
			removeDust(model)
		end
	end
end)

print("[SprinklerClient] ready")
