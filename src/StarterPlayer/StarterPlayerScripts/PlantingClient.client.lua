--[[
	PlantingClient  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	Equip a seed and point at a garden bed: a see-through preview of the planet follows your
	mouse with a circle on the ground (green = you can plant here, red = you can't).
	Click to plant.
	On phones / tablets: tap the bed to put the planet there (tap again anywhere to move it),
	then press the green check on the right to plant it, or the red X to cancel.

	The server (PlantingServer) checks everything again, so this is only the preview and the click.

	Needs: PlantingServer + GameServer (ServerScriptService),
	       PlanetCatalog + PlanetBuilder (ReplicatedStorage).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PlanetBuilder = require(ReplicatedStorage:WaitForChild("PlanetBuilder"))
local ScreenFit = require(ReplicatedStorage:WaitForChild("ScreenFit"))

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local plantRemote = remotes:WaitForChild("PlantSeed")

---------------------------------------------------------------------
-- CONFIG (these three match PlantingServer automatically)
---------------------------------------------------------------------
local PAD_TAG = "GardenPad"
local DISPLAY_SCALE = remotes:GetAttribute("GardenScale") or 0.3
local HOVER = remotes:GetAttribute("PlantHover") or 1
local MAX_DISTANCE = remotes:GetAttribute("PlantDistance") or 40
local EDGE_MARGIN = 1
local SPACING_PADDING = 0.5
local CLICK_COOLDOWN = 0.25

local OK_COLOR = Color3.fromRGB(90, 255, 120)
local BAD_COLOR = Color3.fromRGB(255, 90, 90)

---------------------------------------------------------------------
-- Hint text above the hotbar
---------------------------------------------------------------------
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "PlantingHint"
hintGui.ResetOnSpawn = false
hintGui.Parent = playerGui

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -112)
hint.Size = UDim2.fromOffset(360, 30)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.FredokaOne
hint.TextSize = 20
hint.TextColor3 = Color3.new(1, 1, 1)
hint.TextStrokeTransparency = 0
hint.Text = "" -- set every frame (different words for touch screens)
hint.Visible = false
hint.TextWrapped = true
hint.Parent = hintGui

local COMPUTER_HINT = "Click a garden bed to plant. Red circles are too close to other planets."
local TOUCH_HINT = "Tap a garden bed to place your planet, then press the check mark."

-- touch screens move the planet with taps and confirm with these buttons (right side)
local TOUCH_BUTTON_SIZE = 70
local confirmHolder = Instance.new("Frame")
confirmHolder.Name = "PlaceButtons"
confirmHolder.AnchorPoint = Vector2.new(1, 0.5)
confirmHolder.Position = UDim2.new(1, -14, 0.38, 0) -- above the jump button
confirmHolder.Size = UDim2.fromOffset(TOUCH_BUTTON_SIZE, TOUCH_BUTTON_SIZE * 2 + 14)
confirmHolder.BackgroundTransparency = 1
confirmHolder.Visible = false
confirmHolder.Parent = hintGui
local confirmLayout = Instance.new("UIListLayout")
confirmLayout.Padding = UDim.new(0, 14)
confirmLayout.SortOrder = Enum.SortOrder.LayoutOrder
confirmLayout.Parent = confirmHolder

local function roundButton(name, order, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(TOUCH_BUTTON_SIZE, TOUCH_BUTTON_SIZE)
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

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
-- the seed you're holding, if any
local function equippedSeed()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("Kind") == "Seed" then
		local planet = PlanetCatalog.Get(tool:GetAttribute("PlanetId"))
		if planet then
			return tool, planet
		end
	end
	return nil
end

-- same size math as the server, so spacing matches
local function footprintRadius(planet)
	local look = planet.Look
	local extent = 1
	for _, ring in ipairs(look.Rings or {}) do
		extent = math.max(extent, ring.Scale)
	end
	for _, moon in ipairs(look.Moons or {}) do
		extent = math.max(extent, moon.Distance * 2)
	end
	return look.Size * extent * DISPLAY_SCALE / 2
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function raycast(ray)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ignore = { camera } -- the preview lives inside the camera, so it's ignored too
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local planted = workspace:FindFirstChild("PlantedPlanets")
	if planted then
		table.insert(ignore, planted)
	end
	rayParams.FilterDescendantsInstances = ignore
	return workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
end

-- would the server accept a seed planted at this raycast hit?
local function isValidSpot(result, planet)
	if not result then
		return false
	end
	local pad = result.Instance
	if not CollectionService:HasTag(pad, PAD_TAG) then
		return false
	end

	-- bases: someone else's base, or an empty one when you already have your own, is red
	local baseOwner = pad:GetAttribute("BaseOwner")
	if baseOwner ~= nil then
		if baseOwner ~= 0 and baseOwner ~= player.UserId then
			return false
		end
		if baseOwner == 0 and player:GetAttribute("HasBase") then
			return false
		end
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - result.Position).Magnitude > MAX_DISTANCE then
		return false
	end

	local localPos = pad.CFrame:PointToObjectSpace(result.Position)
	local half = pad.Size / 2
	if math.abs(localPos.X) > half.X - EDGE_MARGIN or math.abs(localPos.Z) > half.Z - EDGE_MARGIN then
		return false
	end

	local footprint = footprintRadius(planet)
	local planted = workspace:FindFirstChild("PlantedPlanets")
	if planted then
		for _, model in ipairs(planted:GetChildren()) do
			local other = model:GetAttribute("Footprint")
			if other then
				local pos = model:GetPivot().Position
				local dx = pos.X - result.Position.X
				local dz = pos.Z - result.Position.Z
				if math.sqrt(dx * dx + dz * dz) < footprint + other + SPACING_PADDING then
					return false
				end
			end
		end
	end

	return true
end

---------------------------------------------------------------------
-- Preview (ghost planet + colored circle)
---------------------------------------------------------------------
local ghost, ghostPlanetId, marker

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if marker then
		marker:Destroy()
		marker = nil
	end
	ghostPlanetId = nil
end

local function ensureGhost(planet)
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	if ghost and ghostPlanetId == planet.Id then
		return true
	end

	clearGhost()
	ghostPlanetId = planet.Id

	ghost = PlanetBuilder.Build(planet, camera, nil, DISPLAY_SCALE, "icon")
	for _, descendant in ipairs(ghost:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = math.max(descendant.Transparency, 0.55)
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end

	local diameter = math.max(footprintRadius(planet) * 2, 1.5)
	marker = Instance.new("Part")
	marker.Name = "PlantMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.2, diameter, diameter)
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.55
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Color = BAD_COLOR
	marker.Parent = camera

	return true
end

---------------------------------------------------------------------
-- Red circles around planets that are too close to plant next to
---------------------------------------------------------------------
local zones = {} -- planted planet model -> { Part = circle part, Y = ground height }

local function groundUnder(model)
	local position = model:GetPivot().Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { workspace.CurrentCamera, model.Parent }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or (position.Y - 3)
end

local function makeZone()
	local part = Instance.new("Part")
	part.Name = "PlantZone"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(2, 0.1, 2)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(256, 256)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = part

	local circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.new(1, -14, 1, -14)
	circle.BackgroundColor3 = BAD_COLOR
	circle.BackgroundTransparency = 0.82
	circle.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local outline = Instance.new("UIStroke")
	outline.Color = BAD_COLOR
	outline.Thickness = 6
	outline.Transparency = 0.15
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = circle
	circle.Parent = gui

	part.Parent = workspace.CurrentCamera -- only you see these
	return part
end

local function clearZones()
	for model, zone in pairs(zones) do
		zone.Part:Destroy()
		zones[model] = nil
	end
end

-- one red circle around every planet already planted: you can't put the planet you're holding inside it
local function syncZones(planet)
	local folder = workspace:FindFirstChild("PlantedPlanets")
	local mine = footprintRadius(planet)
	local seen = {}

	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			local other = model:GetAttribute("Footprint")
			if model:IsA("Model") and other then
				seen[model] = true
				local zone = zones[model]
				if not zone then
					zone = { Part = makeZone(), Y = groundUnder(model) }
					zones[model] = zone
				end
				local position = model:GetPivot().Position
				local radius = other + mine + SPACING_PADDING
				zone.Part.Size = Vector3.new(radius * 2, 0.1, radius * 2)
				zone.Part.CFrame = CFrame.new(position.X, zone.Y + 0.12, position.Z)
			end
		end
	end

	for model, zone in pairs(zones) do
		if not seen[model] then
			zone.Part:Destroy()
			zones[model] = nil
		end
	end
end

local HIDDEN = CFrame.new(0, -5000, 0)

-- phones and tablets (or anyone whose last input was a touch)
local function touchMode()
	if not UserInputService.TouchEnabled then
		return false
	end
	return not UserInputService.MouseEnabled or UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- on touch screens: where the planet is waiting to be planted ({ Instance, Position } or nil)
local touchSpot = nil
local touchSpotOk = false

RunService.RenderStepped:Connect(function()
	local _, planet = equippedSeed()
	if not planet then
		clearGhost()
		clearZones()
		hint.Visible = false
		touchSpot = nil
		confirmHolder.Visible = false
		return
	end

	local touching = touchMode()
	hint.Text = touching and TOUCH_HINT or COMPUTER_HINT
	-- on phones the coins sit just above the hotbar, so the hint goes a bit higher and smaller
	if ScreenFit.IsPhone() then
		hint.Position = UDim2.new(0.5, 0, 1, -150)
		hint.TextSize = 15
	else
		hint.Position = UDim2.new(0.5, 0, 1, -112)
		hint.TextSize = 20
	end
	hint.Visible = not (touching and touchSpot) -- the buttons explain themselves once a spot is picked
	syncZones(planet)
	if not ensureGhost(planet) then
		return
	end

	local camera = workspace.CurrentCamera
	local result
	if touching then
		result = touchSpot
		confirmHolder.Visible = touchSpot ~= nil
	else
		confirmHolder.Visible = false
		local mouse = UserInputService:GetMouseLocation()
		result = raycast(camera:ViewportPointToRay(mouse.X, mouse.Y))
	end

	if result then
		local ground = result.Position
		local lift = HOVER + (planet.Look.Size / 2) * DISPLAY_SCALE
		ghost:PivotTo(CFrame.new(ground + Vector3.new(0, lift, 0)))
		marker.CFrame = CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local ok = isValidSpot(result, planet)
		marker.Color = ok and OK_COLOR or BAD_COLOR
		if touching then
			touchSpotOk = ok
			-- the check mark is grey while the spot can't be planted on
			confirmButton.BackgroundColor3 = ok and Color3.fromRGB(60, 200, 90) or Color3.fromRGB(120, 125, 130)
		end
	else
		ghost:PivotTo(HIDDEN)
		marker.CFrame = HIDDEN
	end
end)

---------------------------------------------------------------------
-- Planting (click or tap)
---------------------------------------------------------------------
local lastClick = 0

local function tryPlant(ray)
	local _, planet = equippedSeed()
	if not planet then
		return
	end

	local now = os.clock()
	if now - lastClick < CLICK_COOLDOWN then
		return
	end
	lastClick = now

	local result = raycast(ray)
	if result then
		-- the server checks the spot and sends a message if it's not allowed
		plantRemote:FireServer(planet.Id, result.Position)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	tryPlant(camera:ViewportPointToRay(mouse.X, mouse.Y))
end)

-- touch screens: a tap moves the planet there (it isn't planted until you press the check mark)
UserInputService.TouchTapInWorld:Connect(function(position, processed)
	if processed then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or not equippedSeed() then
		return
	end
	local result = raycast(camera:ScreenPointToRay(position.X, position.Y))
	if result then
		touchSpot = { Instance = result.Instance, Position = result.Position }
	end
end)

confirmButton.Activated:Connect(function()
	local _, planet = equippedSeed()
	if not planet or not touchSpot then
		return
	end
	if not touchSpotOk then
		-- let the server explain why (too close, not your base...)
		plantRemote:FireServer(planet.Id, touchSpot.Position)
		return
	end
	local now = os.clock()
	if now - lastClick < CLICK_COOLDOWN then
		return
	end
	lastClick = now
	plantRemote:FireServer(planet.Id, touchSpot.Position)
	touchSpot = nil -- tap somewhere else for the next one
end)

cancelButton.Activated:Connect(function()
	touchSpot = nil
end)
