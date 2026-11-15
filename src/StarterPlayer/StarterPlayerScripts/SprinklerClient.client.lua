--[[
	SprinklerClient  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	* Holding a sprinkler (gear shop): a see-through preview and its exact range circle follow your
	  mouse over your garden beds (green = OK, red = can't place there); your planets inside the
	  circle light up green. Click to place. Phones: tap to move it, tap inside the circle to place.
	  Unequip to cancel.
	* Placed sprinklers: orbit rings turn, planets orbit, a soft green circle shows what it covers.
	* Placed sprinklers: the head spins and sprays arcs of stardust.
	* Planets in range: stardust floats around them. BLACK HOLES suck the stardust in.

	Needs: SprinklerServer, GearCatalog.
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
local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local placeRemote = remotes:WaitForChild("PlaceGear", 30)

local PAD_TAG = "GardenPad"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SHOW_DISTANCE = 200
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

---------------------------------------------------------------------
-- Placing: see-through sprinkler + range circle + highlight on the planets it will reach
---------------------------------------------------------------------
local camera = workspace.CurrentCamera
local ghost, ghostCircle, ghostGear = nil, nil, nil
local ghostSpot, ghostPad = nil, nil
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

local function clearGhost()
	if ghost then
		ghost:Destroy()
	end
	if ghostCircle then
		ghostCircle:Destroy()
	end
	clearHighlights()
	ghost, ghostCircle, ghostGear, ghostSpot, ghostPad, touchPoint = nil, nil, nil, nil, nil, nil
end

local function makeGhost(gear)
	clearGhost()
	ghostGear = gear
	ghost = SprinklerModel.Build(gear, CFrame.new(0, -500, 0), true)
	ghost.Parent = fxFolder
	ghostCircle = SprinklerModel.RangeCircle(gear.Radius, fxFolder)
	ghostCircle:SetLook(0.78, 0.05, 0.55)
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
	local owner = part:GetAttribute("BaseOwner")
	return owner == nil or owner == player.UserId
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
end

local hooked = setmetatable({}, { __mode = "k" })
local function hookTool(tool)
	if hooked[tool] then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
			return -- phones and tablets use tap-to-move, tap-again-to-place (below)
		end
		place()
	end)
end

-- mobile: first tap moves the preview there, tapping inside the circle again places it
UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
	if processedByUI or not ghostGear then
		return
	end
	local hit = aim(camera:ViewportPointToRay(position.X, position.Y))
	if ghostSpot and hit and canPlaceOn(hit.Instance) and (snapToPad(hit.Instance, hit.Position) - ghostSpot).Magnitude <= 3 then
		place()
	else
		touchPoint = position
	end
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
	local hit = aim()
	local ok = hit and canPlaceOn(hit.Instance)
	local spot = hit and (ok and snapToPad(hit.Instance, hit.Position) or hit.Position)
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
	local color = ok and SprinklerModel.GREEN or RED
	ghostCircle:SetColor(color)
	for _, p in ipairs(ghost:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Color = color
		elseif p:IsA("HandleAdornment") then
			p.Color3 = color
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
local sprinklers = {} -- model -> { Head, Base, Emitters, Angle }

local function sprayEmitter(nozzle, color, radius)
	-- aimed 45 degrees up, fast enough that the arc lands at the edge of its range
	local speed = math.sqrt(radius * GRAVITY) * 0.95
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.15) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.1, 1.4)
	e.Speed = NumberRange.new(speed * 0.55, speed)
	e.SpreadAngle = Vector2.new(6, 6)
	e.Acceleration = Vector3.new(0, -GRAVITY, 0)
	e.Rate = 26
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.EmissionDirection = Enum.NormalId.Front
	e.Parent = nozzle
	return e
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
	local color = model:GetAttribute("DustColor") or Color3.new(1, 1, 1)
	local radius = model:GetAttribute("Radius") or 9
	local emitters = {}
	for _, nozzle in ipairs(head:GetChildren()) do
		if nozzle:IsA("Attachment") then
			table.insert(emitters, sprayEmitter(nozzle, color, radius))
		end
	end
	-- a soft glow on the head
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = head
	-- soft glowing circle showing exactly what it covers
	local circle = SprinklerModel.RangeCircle(radius, fxFolder)
	circle:Place(base.Position - Vector3.new(0, base.Size.X / 2, 0))
	circle:SetLook(0.9, 0.5, 0.85)
	sprinklers[model] = { Head = head, Base = base, Emitters = emitters, Angle = math.random() * 6.28, Home = head.CFrame, Circle = circle }
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
	local size = model:GetExtentsSize()
	local shellRadius = math.clamp(math.max(size.X, size.Z) * 0.6, 2.5, 18)
	local shell = invisiblePart("StardustShell", Vector3.one * shellRadius * 2, body.CFrame, Enum.PartType.Ball)
	local isBlackHole = model:GetAttribute("Group") == "BlackHole" or (planet and planet.Group == "BlackHole")

	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
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
			local near = (s.Base.Position - camPos).Magnitude <= SHOW_DISTANCE
			for _, e in ipairs(s.Emitters) do
				e.Enabled = near
			end
			s.Circle.Part.Parent = near and fxFolder or nil
			if near then
				s.Angle += dt * 2.4
				s.Head.CFrame = s.Home * CFrame.Angles(0, s.Angle, 0)
				SprinklerModel.Animate(model, os.clock())
				s.Circle.Edge.Transparency = 0.5 + 0.15 * math.sin(os.clock() * 2)
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
