--[[
	HeldPlanetClient  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	When you hold a harvested planet (click its slot in the hotbar, or press its number), the
	REAL planet floats in the air just above and in front of you, with all its rings, moons,
	clouds and glow. It bobs gently, and everything on it moves: moons orbit, rings spin,
	black hole halos face the camera. Put it away and it disappears.

	The planet is the EXACT size it was when you harvested it, with no size limit: a Moon is
	small, Jupiter is big, and a HUGE / INSANE / CRAZY one is as big as it grew in your garden.
	Seed packs show too: the 3D pack model floats in front of you with its front facing you.
	Other players' held planets and packs show on your screen too (when they're close).

	This REPLACES the old server Script named HeldPlanet. DELETE that old Script.

	Needs:  PlanetCatalog + PlanetBuilder (ReplicatedStorage)
	        PlanetSpinner (LocalScript in StarterPlayerScripts), it does the moving and spinning
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PlanetBuilder = require(ReplicatedStorage:WaitForChild("PlanetBuilder"))
-- the MODULESCRIPT named PackModels (there is also a Folder with the same name, so check the type)
local okPacks, PackModels = pcall(function()
	for _ = 1, 150 do
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			if child.Name == "PackModels" and child:IsA("ModuleScript") then
				return require(child)
			end
		end
		task.wait(0.1)
	end
	error("PackModels ModuleScript not found in ReplicatedStorage")
end)
if not okPacks then
	warn("[HeldPlanetClient] seed pack models unavailable: " .. tostring(PackModels))
end

local localPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
-- The planet in your hand is the EXACT size it was in your garden when you harvested it. No limits.
local DEFAULT_GARDEN_SCALE = 0.2   -- only used if the server doesn't say (the server sends its garden size automatically)
local TIER_SIZE = { huge = 2, insane = 4, crazy = 8 } -- how much bigger each size grows. Must match TIERS in PlantingServer.
local HELD_PACK_SCALE = 0.4    -- how big a seed pack looks in your hand (1 = the full model, about 8 studs tall)
local HELD_PACK_UP = 0.9      -- studs from your middle up to the BOTTOM of a seed pack
local HOLD_FORWARD = 2        -- studs in front of you
local HOLD_UP = 3.4           -- studs from your middle up to the BOTTOM of the planet
local BOB_HEIGHT = 0.25       -- how far it bobs up and down
local BOB_SPEED = 2
local SHOW_DISTANCE = 120     -- other players' planets only show when they're this close to you

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local folder = workspace:FindFirstChild("HeldPlanets")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "HeldPlanets"
	folder.Parent = workspace
end

local equipped = {}                                -- character -> the planet Tool it is holding
local displays = {}                                -- character -> { Model, Tool, Seed, HalfHeight }
local failed = setmetatable({}, { __mode = "k" })  -- tools that couldn't be built (so we don't retry every frame)

local function destroyDisplay(character)
	local display = displays[character]
	if display then
		displays[character] = nil
		display.Model:Destroy()
	end
end

---------------------------------------------------------------------
-- Building the planet
---------------------------------------------------------------------
local function buildPackDisplay(character, tool)
	local model = okPacks and PackModels.Get(tool.Name)
	if not model then
		return nil -- that pack's model isn't in ReplicatedStorage.PackModels yet
	end
	model.Name = "Held_" .. tool.Name
	model.Parent = folder
	model:ScaleTo(HELD_PACK_SCALE)
	local _, size = model:GetBoundingBox()
	return {
		Model = model,
		Tool = tool,
		Seed = math.random() * 6.28,
		HalfHeight = size.Y / 2,
		Up = HELD_PACK_UP,
		IsPack = true,
	}
end

local function buildDisplay(character, tool)
	if tool:GetAttribute("Kind") == "Pack" then
		return buildPackDisplay(character, tool)
	end

	local planet = PlanetCatalog.Get(tool:GetAttribute("PlanetId"))
	if not planet then
		warn("[HeldPlanetClient] unknown planet id on tool " .. tool.Name .. ": " .. tostring(tool:GetAttribute("PlanetId")))
		return nil
	end

	-- the exact size it grew to in the garden: the garden scale times its HUGE / INSANE / CRAZY size
	local remotes = ReplicatedStorage:FindFirstChild("PlanetRemotes")
	local gardenScale = remotes and remotes:GetAttribute("GardenScale") or DEFAULT_GARDEN_SCALE
	local scale = gardenScale * (TIER_SIZE[tool:GetAttribute("SizeTier")] or 1)

	-- the FULL model (not the simple icon one), so it has every ring, moon and glow
	local ok, model = pcall(PlanetBuilder.Build, planet, folder, nil, scale)
	if not ok then
		warn("[HeldPlanetClient] couldn't build " .. planet.Name .. ": " .. tostring(model))
		return nil
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false -- clicks and the planting preview go straight through it
			descendant.CanTouch = false
			descendant.CastShadow = false
		elseif descendant:IsA("Light") then
			descendant:Destroy() -- no pool of light on the ground from something you're holding
		end
	end

	model.Name = "Held_" .. planet.Name
	print(string.format("[HeldPlanetClient] showing %s above %s (scale %.2f)", planet.Name, character.Name, scale))

	return {
		Model = model,
		Tool = tool,
		Seed = math.random() * 6.28,
		HalfHeight = planet.Look.Size * scale / 2,
	}
end

---------------------------------------------------------------------
-- Every frame: build, move or remove each held planet
---------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local now = os.clock()

	for character, tool in pairs(equipped) do
		local root = character:FindFirstChild("HumanoidRootPart")
		local isMine = character == localPlayer.Character
		local near = root ~= nil and (isMine or (root.Position - cameraPosition).Magnitude <= SHOW_DISTANCE)

		local display = displays[character]
		if display and (display.Tool ~= tool or not near) then
			destroyDisplay(character)
			display = nil
		end

		if near and not display and not failed[tool] then
			display = buildDisplay(character, tool)
			if display then
				displays[character] = display
			else
				failed[tool] = true
			end
		end

		if display and root then
			-- in front of the way the character faces, but always upright (so the planet's tilt stays right)
			local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if flat.Magnitude < 0.01 then
				flat = Vector3.new(0, 0, -1)
			else
				flat = flat.Unit
			end
			local bob = math.sin(now * BOB_SPEED + display.Seed) * BOB_HEIGHT
			local lift = (display.Up or HOLD_UP) + display.HalfHeight + bob
			local position = root.Position + flat * HOLD_FORWARD + Vector3.new(0, lift, 0)
			if display.IsPack then
				-- the front of the pack faces YOU (back toward the camera), with a little sway
				local sway = math.sin(now * 1.5 + display.Seed) * 0.12
				display.Model:PivotTo(CFrame.lookAt(position, position + flat) * CFrame.Angles(0, sway, 0))
			else
				display.Model:PivotTo(CFrame.new(position))
			end
		end
	end
end)

---------------------------------------------------------------------
-- Watching for planets being equipped and put away
---------------------------------------------------------------------
local function isPlanetTool(instance)
	local kind = instance:GetAttribute("Kind")
	return instance:IsA("Tool") and (kind == "Planet" or kind == "Pack")
end

local function watch(character)
	local function consider(child)
		if isPlanetTool(child) then
			equipped[character] = child
		end
	end

	character.ChildAdded:Connect(consider)

	character.ChildRemoved:Connect(function(child)
		if equipped[character] == child then
			equipped[character] = nil
			destroyDisplay(character)
		end
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			equipped[character] = nil
			destroyDisplay(character)
		end
	end)

	for _, child in ipairs(character:GetChildren()) do
		consider(child)
	end
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

print("[HeldPlanetClient] ready")
