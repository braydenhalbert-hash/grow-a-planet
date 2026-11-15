--[[
	SprinklerClient  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	* Holding a sprinkler (gear shop): a see-through preview and its range circle follow your mouse
	  over your garden beds (green = OK, red = can't place there). Click / tap to place it.
	* Placed sprinklers: the head spins and sprays arcs of stardust.
	* Planets in range: stardust floats around them. BLACK HOLES suck the stardust in.

	Needs: SprinklerServer, GearCatalog.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
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
-- Placing (preview + click)
---------------------------------------------------------------------
local ghost, ghostRing, ghostGearId = nil, nil, nil

local function clearGhost()
	if ghost then
		ghost:Destroy()
	end
	if ghostRing then
		ghostRing:Destroy()
	end
	ghost, ghostRing, ghostGearId = nil, nil, nil
end

local function makeGhost(gear)
	clearGhost()
	ghostGearId = gear.Id
	ghost = Instance.new("Model")
	ghost.Name = "SprinklerPreview"
	local function piece(size, offset, color, shape)
		local p = invisiblePart("Piece", size, CFrame.new(offset), shape)
		p.Transparency = 0.45
		p.Material = Enum.Material.Neon
		p.Color = color
		p:SetAttribute("Offset", offset)
		p.Parent = ghost
		return p
	end
	piece(Vector3.new(2.2, 0.35, 2.2), Vector3.new(0, 0.18, 0), Color3.fromRGB(80, 86, 94))
	piece(Vector3.new(0.42, 2.1, 0.42), Vector3.new(0, 1.4, 0), Color3.fromRGB(150, 156, 164))
	piece(Vector3.new(1.1, 0.35, 1.1), Vector3.new(0, 2.6, 0), gear.Color, Enum.PartType.Ball)
	ghost.Parent = fxFolder

	-- the range circle on the ground
	ghostRing = invisiblePart("Range", Vector3.new(0.12, gear.Radius * 2, gear.Radius * 2), CFrame.new(), Enum.PartType.Cylinder)
	ghostRing.Material = Enum.Material.Neon
	ghostRing.Color = gear.DustColor
	ghostRing.Transparency = 0.75
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function aim()
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
	local ray = mouse.UnitRay
	return workspace:Raycast(ray.Origin, ray.Direction * 600, rayParams)
end

local function canPlaceOn(part)
	if not part or not CollectionService:HasTag(part, PAD_TAG) then
		return false
	end
	local owner = part:GetAttribute("BaseOwner")
	return owner == nil or owner == player.UserId
end

local function heldGear()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("Kind") == "Gear" then
		return tool, GearCatalog.Get(tool:GetAttribute("GearId"))
	end
	return nil, nil
end

local hooked = setmetatable({}, { __mode = "k" })
local function hookTool(tool)
	if hooked[tool] then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		local gear = GearCatalog.Get(tool:GetAttribute("GearId"))
		local hit = aim()
		if gear and hit and placeRemote then
			placeRemote:FireServer(gear.Id, hit.Position, hit.Instance)
		end
	end)
end

RunService.RenderStepped:Connect(function()
	local tool, gear = heldGear()
	if not gear then
		if ghost then
			clearGhost()
		end
		return
	end
	hookTool(tool)
	if ghostGearId ~= gear.Id then
		makeGhost(gear)
	end
	local hit = aim()
	if not hit then
		ghost.Parent = nil
		ghostRing.Parent = nil
		return
	end
	ghost.Parent = fxFolder
	ghostRing.Parent = fxFolder
	local ok = canPlaceOn(hit.Instance)
	local at = hit.Position
	for _, p in ipairs(ghost:GetChildren()) do
		p.CFrame = CFrame.new(at + p:GetAttribute("Offset"))
	end
	ghostRing.CFrame = CFrame.new(at + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ghostRing.Color = ok and gear.DustColor or Color3.fromRGB(255, 70, 70)
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
	sprinklers[model] = { Head = head, Base = base, Emitters = emitters, Angle = math.random() * 6.28, Home = head.CFrame }
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
		sprinklers[m] = nil
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

local plantsFolder = workspace:WaitForChild("PlantedPlanets", 30)
local nextScan = 0

RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero

	-- spin the heads
	for model, s in pairs(sprinklers) do
		if not model.Parent then
			sprinklers[model] = nil
		else
			s.Angle += dt * 2.4
			s.Head.CFrame = s.Home * CFrame.Angles(0, s.Angle, 0)
			local near = (s.Base.Position - camPos).Magnitude <= SHOW_DISTANCE
			for _, e in ipairs(s.Emitters) do
				e.Enabled = near
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
