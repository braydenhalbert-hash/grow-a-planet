--[[
	SeedShopUI  (LocalScript)  -- REPLACES the earlier SeedShopUI
	Put in: StarterPlayer > StarterPlayerScripts

	What this script does:
	  * Two shop windows
	      PLANETS shop (deep space blue): planet seeds only, no Sun or Black Hole
	      PACKS shop (black hole purple): Black Hole Packs
	  * Tap a row to buy it. Rows push in when you hover and push in more when you press.
	  * Top buttons: SEEDS / GARDEN / SELL teleport you to those places
	  * Coins counter, pop-up messages, click + sold-out sounds
	  * Pack opening: a roll strip that scrolls through the rarities and lands on your seed (SKIP to jump ahead)

	Which NPC opens which shop is set by NPC_SHOPS below.

	Needs: GameServer + GameData (ServerScriptService),
	       PlanetCatalog + PlanetBuilder + PackCatalog (ReplicatedStorage).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PlanetBuilder = require(ReplicatedStorage:WaitForChild("PlanetBuilder"))
local PackCatalog = require(ReplicatedStorage:WaitForChild("PackCatalog"))
-- the 3D seed pack models (optional: if they aren't set up yet, the old glowing-circle icon is used)
-- (it must be the MODULESCRIPT named PackModels; there is also a Folder with the same name)
local okPacks, PackModels = pcall(function()
	for _ = 1, 100 do
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
	warn("[SeedShopUI] seed pack models unavailable: " .. tostring(PackModels))
end

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local buySeedRemote = remotes:WaitForChild("BuySeed")
local buyPackRemote = remotes:WaitForChild("BuyPack")
local restockRemote = remotes:WaitForChild("RestockRequest")
local noticeRemote = remotes:WaitForChild("Notice")
local restockAnnounceRemote = remotes:WaitForChild("RestockAnnounce", 15) -- "shop restocked" pop-ups (made by GameServer)
local rollRemote = remotes:WaitForChild("PackRoll")
local finishRemote = remotes:WaitForChild("PackFinished")
local stockFolder = ReplicatedStorage:WaitForChild("PlanetShopStock")
local buyRobuxRemote = remotes:WaitForChild("BuyRobux", 15) -- Robux buy + gift (made by GameServer)
local buyGearRemote = remotes:WaitForChild("BuyGear", 15) -- gear shop (made by GameServer)
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
local SprinklerModel = require(ReplicatedStorage:WaitForChild("SprinklerModel"))
local ScreenFit = require(ReplicatedStorage:WaitForChild("ScreenFit")) -- phone layout
local NpcTalk = require(ReplicatedStorage:WaitForChild("NpcTalk")) -- NPC lines, outline, blur + zoom

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
-- NPC model name (or Humanoid display name) -> which shop it opens ("planets" or "packs")
-- R6 is the guy at the purple stand, SeedSeller is the one at the green stand.
local NPC_SHOPS = {
	R6 = "packs",
	SeedSeller = "planets",
	SunFarmer = "suns",      -- the farmer in the sun hat at the yellow stand (back of the map)
	GearMechanic = "gear",   -- the mechanic with the pipe at the green stand (back of the map)
}
-- what each shop NPC says (typed above their head) right before their shop opens
local NPC_LINES = {
	planets = "Here are the seeds that are in stock",
	suns = "Here are the sun seeds that are in stock",
	gear = "Here's the gear that's in stock",
	packs = "Here are the packs that are in stock",
}
local BUYER_NAMES = { PlanetBuyer = true } -- the SELL button teleports here
local CLOSE_DISTANCE = 16
local FONT = Enum.Font.FredokaOne

local CLICK_SOUND_ID = "rbxassetid://123087446204451"
local CLICK_VOLUME = 0.6
local SOLD_OUT_SOUND_ID = "rbxassetid://108295046133967"
local SOLD_OUT_VOLUME = 0.7
-- sound when the shops restock: a springy rubber-band twang (Roblox's own "Rubber band" sound,
-- Grow a Garden style). Paste your own "rbxassetid://..." here to use a different sound.
local RESTOCK_SOUND_ID = "rbxassetid://12222106"
local RESTOCK_VOLUME = 0.8

-- STUD LOOK inside the shop windows (round studs)
local STUD_TEXTURE = "rbxassetid://75195146818356"
-- BRICK LOOK for the top buttons (SEEDS / GARDEN / SELL) and the pop-ups: brown square studs like Grow a Garden.
-- Upload brick.png (Asset Manager > Images > Add), copy its ID and paste it here like "rbxassetid://123456789".
-- Leave it "" and the round studs above are used instead.
local BRICK_TEXTURE = ""

local THEMES = {
	planets = {
		Title = "PLANET SEEDS",
		Icon = "🪐",
		ObjectText = "Seed Seller",
		FrameTop = Color3.fromRGB(18, 20, 58),
		FrameBottom = Color3.fromRGB(6, 8, 26),
		GlowA = Color3.fromRGB(90, 190, 255),
		GlowB = Color3.fromRGB(160, 90, 255),
		HeaderTop = Color3.fromRGB(86, 70, 214),
		HeaderBottom = Color3.fromRGB(38, 28, 126),
		CardTop = Color3.fromRGB(40, 34, 98),
		CardBottom = Color3.fromRGB(20, 16, 56),
		CardStroke = Color3.fromRGB(110, 130, 255),
		IconBg = Color3.fromRGB(8, 8, 28),
		StockColor = Color3.fromRGB(205, 210, 235),
		PriceColor = Color3.fromRGB(70, 255, 110),
		BuyColor = Color3.fromRGB(34, 200, 70),
		Accent = Color3.fromRGB(46, 140, 255),
		ScrollBar = Color3.fromRGB(130, 150, 255),
	},
	suns = {
		Title = "SUN SEEDS",
		Icon = "☀️",
		ObjectText = "Sun Farmer",
		FrameTop = Color3.fromRGB(70, 34, 6),
		FrameBottom = Color3.fromRGB(28, 12, 2),
		GlowA = Color3.fromRGB(255, 220, 90),
		GlowB = Color3.fromRGB(255, 120, 30),
		HeaderTop = Color3.fromRGB(240, 170, 30),
		HeaderBottom = Color3.fromRGB(170, 80, 10),
		CardTop = Color3.fromRGB(110, 60, 14),
		CardBottom = Color3.fromRGB(56, 26, 6),
		CardStroke = Color3.fromRGB(255, 200, 80),
		IconBg = Color3.fromRGB(26, 10, 2),
		StockColor = Color3.fromRGB(255, 225, 170),
		PriceColor = Color3.fromRGB(255, 235, 110),
		BuyColor = Color3.fromRGB(34, 200, 70),
		Accent = Color3.fromRGB(235, 140, 20),
		ScrollBar = Color3.fromRGB(255, 200, 90),
	},
	gear = {
		Title = "GEAR",
		Icon = "🔧",
		ObjectText = "Gear Mechanic",
		FrameTop = Color3.fromRGB(14, 46, 22),
		FrameBottom = Color3.fromRGB(4, 18, 8),
		GlowA = Color3.fromRGB(110, 255, 140),
		GlowB = Color3.fromRGB(120, 200, 255),
		HeaderTop = Color3.fromRGB(48, 150, 64),
		HeaderBottom = Color3.fromRGB(20, 76, 30),
		CardTop = Color3.fromRGB(30, 84, 40),
		CardBottom = Color3.fromRGB(14, 40, 18),
		CardStroke = Color3.fromRGB(120, 230, 140),
		IconBg = Color3.fromRGB(6, 20, 10),
		StockColor = Color3.fromRGB(200, 240, 205),
		PriceColor = Color3.fromRGB(110, 255, 140),
		BuyColor = Color3.fromRGB(34, 200, 70),
		Accent = Color3.fromRGB(40, 160, 70),
		ScrollBar = Color3.fromRGB(130, 230, 150),
	},
	packs = {
		Title = "BLACK HOLE PACKS",
		Icon = "🌑",
		ObjectText = "Black Hole Packs",
		FrameTop = Color3.fromRGB(34, 12, 60),
		FrameBottom = Color3.fromRGB(12, 5, 26),
		GlowA = Color3.fromRGB(190, 90, 255),
		GlowB = Color3.fromRGB(255, 150, 60),
		HeaderTop = Color3.fromRGB(128, 58, 214),
		HeaderBottom = Color3.fromRGB(54, 20, 104),
		CardTop = Color3.fromRGB(70, 32, 120),
		CardBottom = Color3.fromRGB(34, 14, 62),
		CardStroke = Color3.fromRGB(170, 100, 255),
		IconBg = Color3.fromRGB(12, 5, 24),
		StockColor = Color3.fromRGB(215, 190, 255),
		PriceColor = Color3.fromRGB(255, 225, 110),
		BuyColor = Color3.fromRGB(34, 200, 70),
		Accent = Color3.fromRGB(150, 60, 240),
		ScrollBar = Color3.fromRGB(180, 110, 255),
	},
}

---------------------------------------------------------------------
-- SOUNDS
---------------------------------------------------------------------
local clickSound = Instance.new("Sound")
clickSound.Name = "ClickSound"
clickSound.SoundId = CLICK_SOUND_ID
clickSound.Volume = CLICK_VOLUME

local soldOutSound = Instance.new("Sound")
soldOutSound.Name = "SoldOutSound"
soldOutSound.SoundId = SOLD_OUT_SOUND_ID
soldOutSound.Volume = SOLD_OUT_VOLUME

-- plays a copy so fast clicks can overlap
local function playCopy(sound)
	local copy = sound:Clone()
	copy.Parent = playerGui
	copy:Play()
	Debris:AddItem(copy, 3)
end

local function playClick()
	playCopy(clickSound)
end

local function playSoldOut()
	playCopy(soldOutSound)
end

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- NOTE: a gradient multiplies the frame's own color, so frames that use one
-- keep BackgroundColor3 white and let the gradient supply the real colors.
local function gradient(parent, c0, c1, rotation)
	return make("UIGradient", {
		Color = ColorSequence.new(c0, c1),
		Rotation = rotation or 90,
	}, parent)
end

local function label(props, parent)
	local base = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	local l = make("TextLabel", base, parent)
	make("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, l)
	return l
end

-- Shrinks `scaleObject` a little on hover and more while pressed, and plays the click sound
-- (or the sold-out sound if the clickable has the attribute SoldOut = true).
local function addPressEffect(clickable, scaleObject, hoverScale, pressScale)
	local hovering = false
	local function tweenTo(target, duration)
		TweenService:Create(
			scaleObject,
			TweenInfo.new(duration or 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = target }
		):Play()
	end
	clickable.MouseEnter:Connect(function()
		hovering = true
		tweenTo(hoverScale)
	end)
	clickable.MouseLeave:Connect(function()
		hovering = false
		tweenTo(1)
	end)
	clickable.MouseButton1Down:Connect(function()
		if clickable:GetAttribute("SoldOut") then
			playSoldOut()
		else
			playClick()
		end
		tweenTo(pressScale, 0.06)
	end)
	clickable.MouseButton1Up:Connect(function()
		tweenTo(hovering and hoverScale or 1)
	end)
end

local function button(props, parent)
	local base = {
		AutoButtonColor = true,
		Font = FONT,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 20,
		BorderSizePixel = 0,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	local b = make("TextButton", base, parent)
	make("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, b)
	addPressEffect(b, make("UIScale", { Scale = 1 }, b), 0.95, 0.86)
	return b
end

local function commas(n)
	local s = tostring(math.floor(n))
	local formatted = s
	repeat
		s = formatted
		formatted = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until formatted == s
	return formatted
end

local function formatTime(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function formatPercent(p)
	return (string.format("%.2f", p):gsub("%.?0+$", ""))
end

---------------------------------------------------------------------
-- PLANET ICONS (the real 3D model in a small viewport)
---------------------------------------------------------------------
local function iconRadiusUnits(look)
	local r = 0.5
	for _, ring in ipairs(look.Rings or {}) do
		r = math.max(r, math.min(ring.Scale / 2, 1.05))
	end
	if look.Glow then
		r = math.max(r, look.Glow.Size / 2)
	end
	for _, moon in ipairs(look.Moons or {}) do
		r = math.max(r, math.min(moon.Distance + moon.Size / 2, 0.85))
	end
	return r
end

local function makePlanetIcon(parent, planet)
	local viewport = make("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 160, 190),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -0.5, -0.7),
	}, parent)

	local model = PlanetBuilder.Build(planet, viewport, nil, nil, "icon")

	local radius = planet.Look.Size * iconRadiusUnits(planet.Look)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = radius / math.tan(math.rad(15)) * 1.1
	camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.3, distance), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport, model
end

-- the real 3D sprinkler in a viewport (same model as in the world), centred so it can turn on the spot
local function makeGearIcon(parent, gear)
	local viewport = make("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 150, 175),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.5, -0.6, -0.8),
	}, parent)
	local model = SprinklerModel.Build(gear, CFrame.new(), false, true)
	model.Parent = viewport
	local box, size = model:GetBoundingBox()
	model.PrimaryPart.PivotOffset = model.PrimaryPart.CFrame:ToObjectSpace(CFrame.new(box.Position))
	model:PivotTo(CFrame.new())
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local fit = math.max(size.Y, size.X * 0.9) / 2
	camera.CFrame = CFrame.lookAt(Vector3.new(0, fit * 0.35, fit / math.tan(math.rad(15)) * 1.08), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport, model
end

-- the real 3D seed pack in a viewport. Returns the viewport, or nil if that pack's model isn't set up.
local function makePackViewport(parent, packName)
	if not okPacks then
		return nil
	end
	local model = PackModels.Get(packName)
	if not model then
		return nil
	end

	local viewport = make("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(190, 180, 215),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.5, -0.6, -0.8),
	}, parent)

	model.Parent = viewport
	model:PivotTo(CFrame.new(0, 0, 0))
	local _, size = model:GetBoundingBox()

	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = (size.Y / 2) / math.tan(math.rad(15)) * 1.25
	camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.3, distance * 0.16, distance), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport, model
end

-- a black hole drawn with frames: glowing ring around a black center
local function makeHoleIcon(parent, color)
	local ring = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	gradient(ring, color, Color3.fromRGB(60, 20, 110), 45)

	local inner = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.new(0, 0, 0),
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, inner)
end

---------------------------------------------------------------------
-- TOP BAR: coins, SEEDS / GARDEN / SELL buttons, pop-up messages
---------------------------------------------------------------------
local topGui = make("ScreenGui", {
	Name = "TopBar",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local hud = make("Frame", {
	Name = "Coins",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16), -- bottom left corner of the screen
	Size = UDim2.fromOffset(190, 40),
	BackgroundTransparency = 1, -- no box, no border: just the coins
}, topGui)

local hudCoin = make("Frame", {
	Position = UDim2.new(0, 10, 0.5, -12),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color3.fromRGB(255, 195, 50),
}, hud)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, hudCoin)
stroke(hudCoin, Color3.fromRGB(150, 90, 10), 2)
label({
	Text = "$",
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
}, hudCoin)

local coinLabel = label({
	Name = "Amount",
	Text = "0",
	TextSize = 24,
	TextColor3 = Color3.fromRGB(255, 225, 110),
	Position = UDim2.new(0, 44, 0, 0),
	Size = UDim2.new(1, -54, 1, 0),
}, hud)

local showToast -- the pop-up messages are made further down (they use the stud look)
local showRestock -- the "restocked" pop-ups too
noticeRemote.OnClientEvent:Connect(function(text, kind)
	if showToast then
		showToast(text, kind)
	end
end)

-- finds an NPC's main part by model name or Humanoid display name
local function findNpcRoot(names)
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and not Players:GetPlayerFromCharacter(inst) then
			local humanoid = inst:FindFirstChildOfClass("Humanoid")
			if names[inst.Name] or (humanoid and names[humanoid.DisplayName]) then
				return inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart", true)
			end
		end
	end
	return nil
end

local function teleportTo(position, lookAt)
	local char = player.Character
	if not char then
		return
	end
	if lookAt then
		char:PivotTo(CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
	else
		char:PivotTo(CFrame.new(position))
	end
end

local function goToNpc(names, failText)
	local root = findNpcRoot(names)
	if not root then
		showToast(failText, "error")
		return
	end
	teleportTo(root.Position + root.CFrame.LookVector * 8 + Vector3.new(0, 3, 0), root.Position)
end

-- brown square studs (or the round ones if BRICK_TEXTURE is empty)
local function addBricks(parent, zIndex, transparency, radius, tile)
	local texture = BRICK_TEXTURE ~= "" and BRICK_TEXTURE or STUD_TEXTURE
	if texture == "" then
		return
	end
	local studs = make("ImageLabel", {
		Name = "Bricks",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = texture,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(tile or 40, tile or 40),
		ImageTransparency = transparency,
		ZIndex = zIndex,
		Active = false,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 0) }, studs)
end

local tabs = make("Frame", {
	Name = "Tabs",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(560, 64),
	BackgroundTransparency = 1,
}, topGui)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, -- SEEDS, GARDEN, SELL in that order
	Padding = UDim.new(0, 12),
}, tabs)

-- chunky studded buttons like Grow a Garden: square corners, thick colored border, big outlined text
local function makeTab(text, color, strokeColor, order, onClick, width, height, textSize)
	local tab = button({
		Name = text,
		Text = "",
		LayoutOrder = order,
		Size = UDim2.fromOffset(width or 140, height or 46),
		BackgroundColor3 = color,
	}, tabs)
	corner(tab, 4)
	stroke(tab, strokeColor, 3.5)
	addBricks(tab, 1, 0.2, 4, 36)
	local words = label({
		Text = text,
		TextSize = textSize or 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, tab)
	local outline = words:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Thickness = 3
	end
	tab.Activated:Connect(onClick)
end

makeTab("SEEDS", Color3.fromRGB(46, 140, 255), Color3.fromRGB(120, 200, 255), 1, function()
	goToNpc({ SeedSeller = true }, "Couldn't find the Seed Seller.")
end)

makeTab("GARDEN", Color3.fromRGB(110, 72, 40), Color3.fromRGB(100, 200, 70), 2, function()
	-- YOUR garden: the beds of the base you own (BaseService marks each bed with its owner)
	local sum, count, top, anyOwnerMark = Vector3.zero, 0, -math.huge, false
	local fallback = nil
	for _, pad in ipairs(CollectionService:GetTagged("GardenPad")) do
		if pad:IsA("BasePart") then
			fallback = fallback or pad
			local owner = pad:GetAttribute("BaseOwner")
			if owner ~= nil then
				anyOwnerMark = true
			end
			if owner == player.UserId then
				sum += pad.Position
				count += 1
				top = math.max(top, pad.Position.Y + pad.Size.Y / 2)
			end
		end
	end
	if count > 0 then
		local center = sum / count
		teleportTo(Vector3.new(center.X, top + 4, center.Z))
	elseif anyOwnerMark then
		showToast("You don't have a garden yet! Walk to an empty base and plant a seed to claim it.", "error")
	elseif fallback then
		teleportTo(fallback.Position + Vector3.new(0, fallback.Size.Y / 2 + 4, 0))
	else
		showToast("Couldn't find your garden.", "error")
	end
end, 200, 56, 34)

makeTab("SELL", Color3.fromRGB(215, 38, 44), Color3.fromRGB(255, 120, 120), 3, function()
	goToNpc(BUYER_NAMES, "Couldn't find the Planet Buyer.")
end)

---------------------------------------------------------------------
-- SHOP WINDOWS
---------------------------------------------------------------------
local shops = {} -- kind -> { Open, Close, Refresh, TimerLabel }

-- STUD LOOK: upload studs.png to Roblox (Asset Manager > Images > Add), copy its ID, and paste it
-- here like  "rbxassetid://123456789".  Leave it "" and the shop simply has no studs.

local function addStuds(parent, zIndex, transparency, radius)
	if STUD_TEXTURE == "" then
		return
	end
	local studs = make("ImageLabel", {
		Name = "Studs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = STUD_TEXTURE,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(44, 44),
		ImageTransparency = transparency,
		ZIndex = zIndex,
		Active = false,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, studs)
end

local function stars(parent, count)
	local rng = Random.new(7)
	local holder = make("Frame", {
		Name = "Stars",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, parent)
	for _ = 1, count do
		local size = rng:NextInteger(2, 4)
		local star = make("Frame", {
			Position = UDim2.fromScale(rng:NextNumber(0.02, 0.98), rng:NextNumber(0.02, 0.98)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = rng:NextNumber() < 0.2 and Color3.fromRGB(190, 170, 255) or Color3.new(1, 1, 1),
			BackgroundTransparency = rng:NextNumber(0.15, 0.75),
			ZIndex = 1,
		}, holder)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, star)
	end
	return holder
end

---------------------------------------------------------------------
-- POP-UP MESSAGES (the new look: dark space card, glowing border, studs, icon, timer bar)
---------------------------------------------------------------------
local toastHolder = make("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 62),
	Size = UDim2.fromOffset(400, 320),
	BackgroundTransparency = 1,
}, topGui)
make("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, toastHolder)

local toastCounter = 0
local TOAST_SECONDS = 3.4

-- a check mark made of two bars, so it works with any font
local function checkMark(parent)
	local long = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.58, 0.46), Size = UDim2.fromOffset(4, 15),
		Rotation = 40, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 5,
	}, parent)
	corner(long, 2)
	local short = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.36, 0.58), Size = UDim2.fromOffset(4, 8),
		Rotation = -40, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 5,
	}, parent)
	corner(short, 2)
end

showToast = function(text, kind)
	local isError = kind == "error"
	local colorA = isError and Color3.fromRGB(235, 80, 80) or Color3.fromRGB(105, 215, 80)
	local colorB = isError and Color3.fromRGB(150, 30, 40) or Color3.fromRGB(40, 140, 60)

	-- never more than 4 at once: the oldest goes
	local existing = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(x, y)
		return x.LayoutOrder < y.LayoutOrder
	end)
	while #existing >= 4 do
		table.remove(existing, 1):Destroy()
	end

	toastCounter += 1
	local slot = make("Frame", {
		Name = "ToastSlot",
		Size = UDim2.fromOffset(380, #text > 44 and 68 or 50),
		BackgroundTransparency = 1,
		LayoutOrder = toastCounter,
	}, toastHolder)

	local body = make("CanvasGroup", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, -18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		GroupTransparency = 1,
	}, slot)
	corner(body, 8)
	gradient(body, Color3.fromRGB(140, 90, 56), Color3.fromRGB(100, 62, 38), 90)
	stroke(body, Color3.fromRGB(52, 26, 12), 3.5)
	addBricks(body, 1, 0.25, 8, 40)

	-- round icon with a glow
	local icon = make("Frame", {
		Position = UDim2.fromOffset(9, 8), Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3,
	}, body)
	corner(icon, 8)
	gradient(icon, colorA, colorB, 90)
	stroke(icon, Color3.fromRGB(52, 26, 12), 2.5)
	if isError then
		label({
			Text = "!", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1), ZIndex = 5,
		}, icon)
	else
		checkMark(icon)
	end

	label({
		Text = text, TextSize = 17, TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -64, 1, -4), ZIndex = 4,
	}, body)

	-- time bar along the bottom
	local barBack = make("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -3), Size = UDim2.new(1, -24, 0, 3),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 4,
	}, body)
	corner(barBack, 2)
	local bar = make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = colorA, BorderSizePixel = 0, ZIndex = 5,
	}, barBack)
	corner(bar, 2)

	TweenService:Create(body, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(0, 0), GroupTransparency = 0,
	}):Play()
	TweenService:Create(bar, TweenInfo.new(TOAST_SECONDS, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	task.delay(TOAST_SECONDS, function()
		if not slot.Parent then
			return
		end
		local out = TweenService:Create(body, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(0, -14), GroupTransparency = 1,
		})
		out:Play()
		out.Completed:Wait()
		if slot.Parent then
			slot:Destroy()
		end
	end)
end

-- "SEEDS RESTOCKED!" / "PACKS RESTOCKED!" cards, top right, with a sound
local restockHolder = make("Frame", {
	Name = "Restocks",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 64),
	Size = UDim2.fromOffset(330, 400),
	BackgroundTransparency = 1,
}, topGui)
make("UIListLayout", {
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
}, restockHolder)

-- SEEDS / GARDEN / SELL sit up in Roblox's own top bar row (next to the Roblox menu buttons,
-- never on top of them), so the game view underneath stays clear.
-- PHONES: smaller pop-ups, and the coins move to the top-left (the joystick lives bottom-left)
ScreenFit.ScaleOnPhone(toastHolder, 0.75)
ScreenFit.ScaleOnPhone(restockHolder, 0.7)
local tabsScale = make("UIScale", { Name = "TopBarScale" }, tabs)
local TABS_W, TABS_H = 560, 64
local function placeTabs()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local width = camera.ViewportSize.X
	local inset = GuiService:GetGuiInset().Y
	local free = GuiService.TopbarInset -- the part of the top bar Roblox's buttons don't use
	local left = free.Width > 0 and free.Min.X or 0
	local right = free.Width > 0 and free.Max.X or width
	if inset < 30 then
		-- no top bar row (rare): just below the top of the screen
		tabsScale.Scale = ScreenFit.IsPhone() and 0.5 or 0.8
		tabs.AnchorPoint = Vector2.new(0.5, 0)
		tabs.Position = UDim2.new(0.5, 0, 0, 6)
		return
	end
	-- as tall as the top bar row allows, and narrow enough to fit beside the Roblox buttons
	local scale = math.min((inset - 6) / TABS_H, (right - left - 16) / TABS_W, 0.9)
	tabsScale.Scale = scale
	local half = TABS_W * scale / 2
	local center = math.clamp(width / 2, left + 8 + half, right - 8 - half)
	tabs.AnchorPoint = Vector2.new(0.5, 0.5)
	tabs.Position = UDim2.new(0, center, 0, -inset / 2)
end
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeTabs)
ScreenFit.Watch(function()
	placeTabs()
	if ScreenFit.IsPhone() then
		hud.AnchorPoint = Vector2.new(0, 0)
		hud.Position = UDim2.fromOffset(6, 4)
		toastHolder.Position = UDim2.new(0.5, 0, 0, 8)
		restockHolder.Position = UDim2.new(1, -8, 0, 68)
	else
		hud.AnchorPoint = Vector2.new(0, 1)
		hud.Position = UDim2.new(0, 16, 1, -16)
		toastHolder.Position = UDim2.new(0.5, 0, 0, 12)
		restockHolder.Position = UDim2.new(1, -16, 0, 64)
	end
end)

---------------------------------------------------------------------
-- ANNOUNCEMENTS: big outlined lines of text in the middle of the screen, Grow a Garden style
--   "Seed Shop, Sun Shop, Gear Shop and Pack Shop stocks have restocked!"
-- Shop names are coloured. Lines stack, then fade away on their own.
---------------------------------------------------------------------
local announceHolder = make("Frame", {
	Name = "Announcements",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.17, 0),
	Size = UDim2.new(1, -40, 0, 200),
	BackgroundTransparency = 1,
}, topGui)
make("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, announceHolder)
ScreenFit.ScaleOnPhone(announceHolder, 0.62)
ScreenFit.Watch(function()
	-- the phone scale shrinks the width too, so give it more room to keep lines on one row
	announceHolder.Size = ScreenFit.IsPhone() and UDim2.new(1.5, 0, 0, 200) or UDim2.new(1, -40, 0, 200)
end)

local ANNOUNCE_SECONDS = 6
local announceCount = 0
local function announce(richText)
	announceCount += 1
	-- never more than 4 lines: the oldest goes
	local lines = {}
	for _, child in ipairs(announceHolder:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #lines >= 4 do
		table.remove(lines, 1):Destroy()
	end

	local line = make("TextLabel", {
		Name = "Line",
		LayoutOrder = announceCount,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, -- long lines wrap onto a second line on narrow screens
		BackgroundTransparency = 1,
		Font = FONT,
		RichText = true,
		Text = richText,
		TextSize = 34,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextWrapped = true,
	}, announceHolder)
	local outline = make("UIStroke", {
		Color = Color3.fromRGB(20, 14, 40),
		Thickness = 2.5,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, line)
	local pop = make("UIScale", { Scale = 0.85 }, line)
	local fadeIn = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(line, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(outline, fadeIn, { Transparency = 0 }):Play()
	TweenService:Create(pop, fadeIn, { Scale = 1 }):Play()
	task.delay(ANNOUNCE_SECONDS, function()
		if not line.Parent then
			return
		end
		local fadeOut = TweenInfo.new(0.6)
		TweenService:Create(line, fadeOut, { TextTransparency = 1 }):Play()
		TweenService:Create(outline, fadeOut, { Transparency = 1 }):Play()
		task.wait(0.65)
		line:Destroy()
	end)
end

local restockSound = make("Sound", { Name = "RestockSound", SoundId = RESTOCK_SOUND_ID, Volume = RESTOCK_VOLUME }, playerGui)

-- shop names in the colour of their stand
local SHOP_NAMES = {
	{ Id = "planets", Text = "Seed Shop", Color = "#5ac8ff" },
	{ Id = "suns", Text = "Sun Shop", Color = "#ffd24a" },
	{ Id = "gear", Text = "Gear Shop", Color = "#6cff6c" },
	{ Id = "packs", Text = "Pack Shop", Color = "#c98cff" },
}
local function colored(text, hex)
	return '<font color="' .. hex .. '">' .. text .. "</font>"
end
local function joinNames(names)
	if #names == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end
local function rarityHex(rarity)
	return "#" .. PlanetCatalog.RarityColor(rarity):ToHex()
end

-- the planet list from the server holds seeds from both the Seed Shop and the Sun Shop
local function shopOfPlanet(name)
	for _, planet in ipairs(PlanetCatalog.Planets) do
		if planet.Name == name then
			return planet.Group == "Star" and "suns" or "planets"
		end
	end
	return "planets"
end

showRestock = function(planetItems, packItems)
	local restocked = { gear = true } -- the gear shop rolls new stock every time
	local best = nil
	local function consider(item, shopId)
		restocked[shopId] = true
		local info = PlanetCatalog.Rarities[item.Rarity]
		local order = info and info.Order or 0
		if order >= 4 and (not best or order > best.Order) then
			best = { Order = order, Item = item, Shop = shopId }
		end
	end
	for _, item in ipairs(planetItems) do
		consider(item, shopOfPlanet(item.Name))
	end
	for _, item in ipairs(packItems) do
		consider(item, "packs")
	end

	local names = {}
	local shopText = {}
	for _, shop in ipairs(SHOP_NAMES) do
		shopText[shop.Id] = colored(shop.Text, shop.Color)
		if restocked[shop.Id] then
			table.insert(names, shopText[shop.Id])
		end
	end
	announce(joinNames(names) .. " stocks have restocked!")

	-- something Epic or better came in: a second line, like a rare event message
	if best then
		local item = best.Item
		local itemName = best.Shop == "packs" and item.Name or (item.Name .. " Seed")
		task.delay(0.35, function()
			announce("Rare restock! " .. colored(itemName, rarityHex(item.Rarity)) .. " is in the " .. shopText[best.Shop] .. "!")
		end)
	end

	local copy = restockSound:Clone()
	copy.Parent = playerGui
	if best then
		copy.PlaybackSpeed = 1.25
	end
	copy:Play()
	Debris:AddItem(copy, 4)
end

if restockAnnounceRemote then
	restockAnnounceRemote.OnClientEvent:Connect(function(planetItems, packItems)
		showRestock(type(planetItems) == "table" and planetItems or {}, type(packItems) == "table" and packItems or {})
	end)
end

-- a small decorative planet (with an optional ring) made from frames
local function decoPlanet(parent, position, size, colorA, colorB, ringColor)
	local holder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 9,
	}, parent)
	if ringColor then
		local ring = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.9, 0.5),
			Rotation = -22,
			BackgroundTransparency = 1,
			ZIndex = 8,
		}, holder)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		stroke(ring, ringColor, 3, 0.15)
	end
	local body = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 9,
	}, holder)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, body)
	gradient(body, colorA, colorB, 45)
	return holder
end

-- the popup that lets you pick who to gift to
local giftGui = make("ScreenGui", {
	Name = "GiftPicker",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 12,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local giftPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(380, 360),
	BackgroundColor3 = Color3.fromRGB(16, 12, 40),
	Visible = false,
	Active = true,
}, giftGui)
corner(giftPanel, 14)
stroke(giftPanel, Color3.fromRGB(150, 110, 255), 3)

local giftTitle = label({
	Text = "Gift",
	TextSize = 24,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.new(1, -70, 0, 30),
}, giftPanel)

local giftClose = button({
	Text = "X",
	TextSize = 20,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8),
	Size = UDim2.fromOffset(36, 36),
	BackgroundColor3 = Color3.fromRGB(205, 45, 70),
}, giftPanel)
corner(giftClose, 8)
giftClose.Activated:Connect(function()
	giftPanel.Visible = false
end)

local giftList = make("ScrollingFrame", {
	Position = UDim2.fromOffset(12, 54),
	Size = UDim2.new(1, -24, 1, -66),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, giftPanel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, giftList)

local function openGiftPicker(item, robuxPrice)
	for _, child in ipairs(giftList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local count = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			count += 1
			local entry = button({
				Text = other.DisplayName .. "  (@" .. other.Name .. ")",
				TextSize = 18,
				LayoutOrder = count,
				Size = UDim2.new(1, -8, 0, 42),
				BackgroundColor3 = Color3.fromRGB(60, 50, 140),
			}, giftList)
			corner(entry, 8)
			entry.Activated:Connect(function()
				giftPanel.Visible = false
				if buyRobuxRemote then
					buyRobuxRemote:FireServer(item.Id, other.UserId)
				end
			end)
		end
	end

	if count == 0 then
		showToast("No other players in this server to gift to.", "error")
		return
	end

	giftTitle.Text = "Gift " .. item.Name .. (robuxPrice and ("  (R$ " .. robuxPrice .. ")") or "")
	giftPanel.Visible = true
end

local function createShop(kind)
	local theme = THEMES[kind]

	-- what this shop sells
	local items = {}
	if kind == "gear" then
		for _, gear in ipairs(GearCatalog.Gear) do
			table.insert(items, {
				Id = gear.Id,
				Name = gear.Name,
				Cost = gear.Cost,
				Rarity = gear.Rarity,
				Color = PlanetCatalog.RarityColor(gear.Rarity),
				TagText = string.upper(gear.Rarity),
				Gear = gear,
				Remote = buyGearRemote,
			})
		end
	elseif kind == "planets" or kind == "suns" then
		local group = kind == "suns" and "Star" or "Planet"
		for _, planet in ipairs(PlanetCatalog.Planets) do
			if planet.Buyable ~= false and planet.Group == group then
				table.insert(items, {
					Id = planet.Id,
					Name = planet.Name .. " Seed",
					Cost = planet.Cost,
					Rarity = planet.Rarity,
					Color = PlanetCatalog.RarityColor(planet.Rarity),
					TagText = string.upper(planet.Rarity),
					Planet = planet,
					Remote = buySeedRemote,
				})
			end
		end
	else
		for _, pack in ipairs(PackCatalog.Packs) do
			local top = PackCatalog.TopRarity(pack)
			table.insert(items, {
				Id = pack.Id,
				Name = pack.Name,
				Cost = pack.Cost,
				Rarity = pack.Tier,
				Color = PlanetCatalog.RarityColor(pack.Tier),
				TagText = "★ " .. string.upper(top) .. " " .. formatPercent(PackCatalog.Percent(pack, top)) .. "%",
				TagColor = PlanetCatalog.RarityColor(top),
				Pack = pack,
				Remote = buyPackRemote,
			})
		end
	end

	local gui = make("ScreenGui", {
		Name = "Shop_" .. kind,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	local main = make("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromScale(0.56, 0.84),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
	}, gui)
	corner(main, 16)
	gradient(main, theme.FrameTop, theme.FrameBottom, 90)
	make("UISizeConstraint", {
		MinSize = Vector2.new(460, 380),
		MaxSize = Vector2.new(720, 680),
	}, main)
	local scale = make("UIScale", { Scale = 1 }, main)

	-- phones: a fixed-size window shrunk to fit below Roblox's top bar
	local fit = 1
	ScreenFit.Watch(function()
		local safe = ScreenFit.Size()
		local camera = workspace.CurrentCamera
		local inset = camera and (camera.ViewportSize.Y - safe.Y) or 0
		main.Position = UDim2.new(0.5, 0, 0, inset + safe.Y / 2)
		if ScreenFit.IsPhone() then
			local design = Vector2.new(720, 470)
			main.Size = UDim2.fromOffset(design.X, design.Y)
			fit = ScreenFit.Fit(design, 0.96)
		else
			-- computers: the same window blown up to ~90% of the screen height (big screens get a big shop)
			local design = Vector2.new(720, 640)
			main.Size = UDim2.fromOffset(design.X, design.Y)
			fit = math.clamp(math.min(safe.Y * 0.9 / design.Y, safe.X * 0.62 / design.X), 0.6, 2.2)
		end
		if main.Visible then
			scale.Scale = fit
		end
	end)

	-- glowing border: a gradient that slowly turns
	local frameStroke = stroke(main, Color3.new(1, 1, 1), 5)
	local frameGlow = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.GlowA),
			ColorSequenceKeypoint.new(0.5, theme.GlowB),
			ColorSequenceKeypoint.new(1, theme.GlowA),
		}),
	}, frameStroke)

	addStuds(main, 1, 0.82, 16)
	stars(main, 55)

	-- planets peeking out of the corners
	decoPlanet(main, UDim2.new(1, -4, 0, 100), 46, Color3.fromRGB(255, 170, 70), Color3.fromRGB(160, 60, 40), Color3.fromRGB(255, 220, 160))
	decoPlanet(main, UDim2.new(0, 2, 1, -6), 38, Color3.fromRGB(90, 170, 255), Color3.fromRGB(40, 60, 170), nil)

	-- header
	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
	}, main)
	corner(header, 14)
	gradient(header, theme.HeaderTop, theme.HeaderBottom, 90)
	addStuds(header, 3, 0.7, 14)

	-- little black hole badge: dark center, spinning glow ring, a tiny planet going around
	local badge = make("Frame", {
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.fromOffset(60, 60),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, header)
	local ring = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
	}, badge)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	local ringGlow = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 80)),
			ColorSequenceKeypoint.new(0.5, theme.GlowB),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 80)),
		}),
	}, ring)
	local hole = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 5,
	}, badge)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, hole)
	local orbit = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.25, 1.25),
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, badge)
	local moon = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = Color3.fromRGB(120, 200, 255),
		ZIndex = 6,
	}, orbit)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, moon)

	local timerLabel = label({
		Name = "Timer",
		Text = "New stock in --",
		TextSize = 30,
		Position = UDim2.new(0, 88, 0, 0),
		Size = UDim2.new(1, -260, 1, 0),
		ZIndex = 4,
	}, header)

	local closeX = button({
		Name = "CloseX",
		Text = "X",
		TextSize = 26,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(50, 50),
		BackgroundColor3 = Color3.fromRGB(205, 45, 70),
		ZIndex = 4,
	}, header)
	corner(closeX, 8)
	stroke(closeX, Color3.fromRGB(255, 130, 150), 2)

	local restockBtn = button({
		Name = "Restock",
		Text = "RESTOCK",
		TextSize = 20,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -72, 0.5, 0),
		Size = UDim2.fromOffset(132, 50),
		BackgroundColor3 = theme.Accent,
		ZIndex = 4,
	}, header)
	corner(restockBtn, 8)
	stroke(restockBtn, theme.GlowA, 2)

	-- ODDS button (floats above the window) and its popup
	local oddsBtn = button({
		Name = "Odds",
		Text = "Odds",
		TextSize = 26,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromOffset(120, 46),
		BackgroundColor3 = theme.Accent,
	}, main)
	corner(oddsBtn, 8)
	stroke(oddsBtn, theme.GlowA, 3)

	local oddsPanel = make("Frame", {
		Name = "OddsPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -60, 1, -120),
		BackgroundColor3 = Color3.fromRGB(12, 9, 32),
		Visible = false,
		ZIndex = 20,
		Active = true,
	}, main)
	corner(oddsPanel, 14)
	stroke(oddsPanel, theme.GlowB, 3)
	label({
		Text = "Odds",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 34),
		ZIndex = 21,
	}, oddsPanel)
	local oddsScroll = make("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 50),
		Size = UDim2.new(1, -24, 1, -112),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 21,
	}, oddsPanel)
	local oddsText = make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		ZIndex = 21,
	}, oddsScroll)
	local oddsClose = button({
		Text = "CLOSE",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(140, 44),
		BackgroundColor3 = Color3.fromRGB(205, 45, 70),
		ZIndex = 22,
	}, oddsPanel)
	corner(oddsClose, 8)

	local function buildOddsText()
		local lines = {}
		if kind == "gear" then
			for _, item in ipairs(items) do
				local g = item.Gear
				table.insert(lines, string.format(
					'<font color="#%s"><b>%s</b></font>\n%s\nRange %d studs  ·  lasts %d min  ·  black holes: %s%% Stardust chance every 10 s\n',
					item.Color:ToHex(), item.Name, g.Description, g.Radius, math.floor(g.Duration / 60), formatPercent(g.StardustChance * 100)
				))
			end
		elseif kind == "packs" then
			for _, item in ipairs(items) do
				local parts = {}
				for _, rarity in ipairs(PackCatalog.RarityOrder) do
					if (item.Pack.Odds[rarity] or 0) > 0 then
						table.insert(parts, string.format(
							'<font color="#%s">%s %s%%</font>',
							PlanetCatalog.RarityColor(rarity):ToHex(),
							rarity,
							formatPercent(PackCatalog.Percent(item.Pack, rarity))
							))
					end
				end
				table.insert(lines, string.format('<b>%s</b>\n%s\n', item.Name, table.concat(parts, "  ·  ")))
			end
		else
			-- how likely each seed is to show up in a restock (if the game says), grouped by rarity
			local total, weights = 0, {}
			for _, item in ipairs(items) do
				local ok, w = pcall(PlanetCatalog.RollWeight, item.Planet)
				if not (ok and type(w) == "number") then
					ok, w = pcall(PlanetCatalog.RollWeight, item.Planet.Rarity)
				end
				weights[item.Id] = (ok and type(w) == "number") and w or nil
				total += weights[item.Id] or 0
			end
			for _, item in ipairs(items) do
				local chance = (total > 0 and weights[item.Id]) and string.format("  %s%%", formatPercent(weights[item.Id] / total * 100)) or ""
				table.insert(lines, string.format(
					'<font color="#%s">%s  —  %s%s</font>',
					item.Color:ToHex(), item.Name, item.Rarity, chance
					))
			end
		end
		oddsText.Text = table.concat(lines, "\n")
	end
	buildOddsText()

	oddsBtn.Activated:Connect(function()
		oddsPanel.Visible = not oddsPanel.Visible
	end)
	oddsClose.Activated:Connect(function()
		oddsPanel.Visible = false
	end)

	-- list of seed cards
	local list = make("ScrollingFrame", {
		Name = "List",
		Position = UDim2.new(0, 12, 0, 96),
		Size = UDim2.new(1, -24, 1, -108),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = theme.ScrollBar,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 2,
	}, main)
	make("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	make("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8) }, list)

	local rowList = {}
	local selected = nil -- the row whose buy buttons are showing

	local function selectRow(row)
		if selected and selected ~= row then
			selected.buyRow.Visible = false
			selected.cardStroke.Thickness = 3
		end
		if selected == row then
			row.buyRow.Visible = false
			row.cardStroke.Thickness = 3
			selected = nil
			return
		end
		selected = row
		row.buyRow.Visible = true
		row.cardStroke.Thickness = 5
	end

	for i, item in ipairs(items) do
		-- slot: the card, plus the buy buttons that appear under it when you click it
		local slot = make("Frame", {
			Name = item.Id,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, list)
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, slot)

		local cardHolder = make("Frame", {
			Name = "CardHolder",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 150),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, slot)

		local card = make("Frame", {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 2,
		}, cardHolder)
		corner(card, 12)
		local cardStroke = stroke(card, theme.CardStroke, 3)
		local cardGradient = gradient(card, theme.CardTop, theme.CardBottom, 90)
		addStuds(card, 2, 0.75, 12)
		local cardScale = make("UIScale", { Scale = 1 }, card)

		-- seed picture
		local iconFrame = make("Frame", {
			Name = "Icon",
			Position = UDim2.fromOffset(14, 15),
			Size = UDim2.fromOffset(120, 120),
			BackgroundColor3 = theme.IconBg,
			ZIndex = 3,
		}, card)
		corner(iconFrame, 10)
		stroke(iconFrame, item.Color, 2)
		local iconViewport, iconModel, iconIsPack, iconIsGear
		if item.Planet then
			iconViewport, iconModel = makePlanetIcon(iconFrame, item.Planet)
		elseif item.Gear then
			-- the real 3D sprinkler (turns and animates when you point at it)
			iconViewport, iconModel = makeGearIcon(iconFrame, item.Gear)
			iconIsGear = true
		else
			if item.Pack then
				iconViewport, iconModel = makePackViewport(iconFrame, item.Pack.Name)
				iconIsPack = true
			end
			if not iconViewport then
				makeHoleIcon(iconFrame, item.Color)
			end
		end
		local iconScale
		if iconViewport then
			iconScale = make("UIScale", { Scale = 1 }, iconViewport)
			iconViewport.AnchorPoint = Vector2.new(0.5, 0.5)
			iconViewport.Position = UDim2.fromScale(0.5, 0.5)
		end

		label({
			Name = "ItemName",
			Text = item.Name,
			TextSize = 36,
			Position = UDim2.new(0, 150, 0, 10),
			Size = UDim2.new(1, -164, 0, 46),
			ZIndex = 3,
		}, card)

		local stockLabel = label({
			Name = "Stock",
			Text = "X0 Stock",
			TextSize = 24,
			TextColor3 = theme.StockColor,
			Position = UDim2.new(0, 150, 0, 62),
			Size = UDim2.new(0.5, -150, 0, 28),
			ZIndex = 3,
		}, card)

		local priceLabel = label({
			Name = "Price",
			Text = commas(item.Cost) .. "¢",
			TextSize = 36,
			TextColor3 = theme.PriceColor,
			Position = UDim2.new(0, 150, 0, 92),
			Size = UDim2.new(0.6, -150, 0, 44),
			ZIndex = 3,
		}, card)

		-- rarity tag (bottom right)
		local tag = make("Frame", {
			Name = "RarityTag",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -14, 1, -14),
			Size = UDim2.fromOffset(kind == "packs" and 190 or 160, 46),
			BackgroundColor3 = item.TagColor or item.Color,
			ZIndex = 3,
		}, card)
		corner(tag, 8)
		stroke(tag, Color3.new(1, 1, 1), 2, 0.55)
		label({
			Text = item.TagText,
			TextSize = kind == "packs" and 20 or 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}, tag)

		-- clicking the card shows / hides its buy buttons
		local click = make("TextButton", {
			Name = "Click",
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
		}, cardHolder)
		addPressEffect(click, cardScale, 0.985, 0.95)

		-- buy buttons: coins, Robux, Gift
		local buyRow = make("Frame", {
			Name = "BuyRow",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 88),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Visible = false,
			ZIndex = 2,
		}, slot)
		corner(buyRow, 12)
		stroke(buyRow, theme.CardStroke, 2)
		gradient(buyRow, theme.CardBottom, theme.FrameBottom, 90)
		addStuds(buyRow, 2, 0.75, 12)
		local coinBtn = button({
			Name = "CoinBuy",
			Text = commas(item.Cost) .. "¢",
			TextSize = 34,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0.03, 0, 0.5, 0),
			Size = UDim2.new(0.36, 0, 0, 62),
			BackgroundColor3 = theme.BuyColor,
			ZIndex = 3,
		}, buyRow)
		stroke(coinBtn, Color3.fromRGB(190, 255, 200), 2, 0.4)

		local robuxBtn = button({
			Name = "RobuxBuy",
			Text = "R$ ?",
			TextSize = 34,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0.41, 0, 0.5, 0),
			Size = UDim2.new(0.36, 0, 0, 62),
			BackgroundColor3 = Color3.fromRGB(128, 40, 230),
			ZIndex = 3,
		}, buyRow)
		stroke(robuxBtn, Color3.fromRGB(210, 170, 255), 2, 0.3)

		local giftBtn = button({
			Name = "Gift",
			Text = "🎁\nGift",
			TextSize = 22,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0.79, 0, 0.5, 0),
			Size = UDim2.new(0.18, 0, 0, 62),
			BackgroundColor3 = Color3.fromRGB(46, 140, 255),
			ZIndex = 3,
		}, buyRow)
		stroke(giftBtn, Color3.fromRGB(170, 215, 255), 2, 0.3)


		local row = {
			item = item,
			slot = slot,
			click = click,
			buyRow = buyRow,
			cardStroke = cardStroke,
			stockLabel = stockLabel,
			priceLabel = priceLabel,
			gradient = cardGradient,
			coinBtn = coinBtn,
			robuxBtn = robuxBtn,
			giftBtn = giftBtn,
			-- hover animation: the planet / pack in the picture comes alive
			viewport = iconViewport,
			model = iconModel,
			isPack = iconIsPack,
			isGear = iconIsGear,
			iconScale = iconScale,
			hover = 0,
			angle = 0,
			hovering = false,
		}
		table.insert(rowList, row)

		click.MouseEnter:Connect(function()
			row.hovering = true
		end)
		click.MouseLeave:Connect(function()
			row.hovering = false
		end)

		click.Activated:Connect(function()
			selectRow(row)
		end)

		coinBtn.Activated:Connect(function()
			if coinBtn:GetAttribute("SoldOut") then
				return
			end
			item.Remote:FireServer(item.Id)
		end)

		robuxBtn.Activated:Connect(function()
			if buyRobuxRemote then
				buyRobuxRemote:FireServer(item.Id)
			end
		end)

		giftBtn.Activated:Connect(function()
			openGiftPicker(item, stockFolder:GetAttribute("Robux_" .. item.Id))
		end)
	end

	local function refresh()
		local coins = player:GetAttribute("Coins") or 0
		for _, r in ipairs(rowList) do
			local stock = stockFolder:GetAttribute(r.item.Id) or 0
			local soldOut = stock <= 0
			local affordable = coins >= r.item.Cost
			r.coinBtn:SetAttribute("SoldOut", soldOut)

			r.stockLabel.Text = "X" .. stock .. " Stock"
			if soldOut then
				r.priceLabel.Text = "NO STOCK"
				r.priceLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
				r.coinBtn.Text = "NO STOCK"
				r.coinBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 132)
			else
				r.priceLabel.Text = commas(r.item.Cost) .. "¢"
				r.priceLabel.TextColor3 = affordable and theme.PriceColor or Color3.fromRGB(255, 100, 100)
				r.coinBtn.Text = commas(r.item.Cost) .. "¢"
				r.coinBtn.BackgroundColor3 = affordable and theme.BuyColor or Color3.fromRGB(170, 60, 70)
			end

			-- items without a Robux product get one big coin button
			local robux = stockFolder:GetAttribute("Robux_" .. r.item.Id)
			r.robuxBtn.Text = robux and ("R$ " .. robux) or "R$ ?"
			r.robuxBtn.Visible = robux ~= nil
			r.giftBtn.Visible = robux ~= nil
			r.coinBtn.Size = robux and UDim2.new(0.36, 0, 0, 62) or UDim2.new(0.94, 0, 0, 62)
		end
	end
	refresh()

	local animation = nil
	local function startAnimation()
		if animation then
			return
		end
		animation = RunService.RenderStepped:Connect(function(dt)
			local t = os.clock()
			frameGlow.Rotation = (t * 40) % 360
			ringGlow.Rotation = (t * 130) % 360
			orbit.Rotation = (t * 150) % 360

			-- planets and packs come alive when you point at them (or when their buy buttons are open)
			for _, r in ipairs(rowList) do
				if r.model and r.model.Parent then
					local target = (r.hovering or selected == r) and 1 or 0
					r.hover += (target - r.hover) * math.min(1, dt * 9)
					if r.hover > 0.005 then
						if r.isPack then
							-- the pack sways side to side and tilts like it's being shown off
							local yaw = math.sin(t * 2.4) * 0.65 * r.hover
							local pitch = math.sin(t * 1.7) * 0.12 * r.hover
							r.model:PivotTo(CFrame.Angles(pitch, yaw, 0))
						elseif r.isGear then
							-- the sprinkler turns slowly and its rings, planets and crystals move
							r.angle += dt * 1.2 * r.hover
							r.model:PivotTo(CFrame.Angles(0, r.angle, 0))
							SprinklerModel.Animate(r.model, t)
						else
							-- the planet spins (moons and rocks on it go around with it)
							r.angle += dt * 2.2 * r.hover
							r.model:PivotTo(CFrame.Angles(0.15 * r.hover, r.angle, 0))
						end
						r.iconScale.Scale = 1 + 0.16 * r.hover + math.sin(t * 5) * 0.025 * r.hover
						r.viewport.Position = UDim2.new(0.5, 0, 0.5, math.sin(t * 4) * 3 * r.hover)
					elseif r.iconScale.Scale ~= 1 then
						r.iconScale.Scale = 1
						r.viewport.Position = UDim2.fromScale(0.5, 0.5)
						if r.isPack then
							r.model:PivotTo(CFrame.new())
						end
					end
				end
			end
		end)
	end
	local function stopAnimation()
		if animation then
			animation:Disconnect()
			animation = nil
		end
	end

	local shop = {}
	shop.Refresh = refresh
	shop.TimerLabel = timerLabel

	function shop.Open()
		if main.Visible then
			return
		end
		refresh()
		scale.Scale = 0.8 * fit
		main.Visible = true
		startAnimation()
		-- the world behind the window blurs, the camera leans in, and the top buttons step aside
		NpcTalk.Focus("shop")
		tabs.Visible = false
		TweenService:Create(
			scale,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = fit }
		):Play()
	end

	function shop.Close()
		if main.Visible then
			NpcTalk.Unfocus("shop")
			task.defer(function()
				-- bring the top buttons back once no shop is open
				for _, other in pairs(shops) do
					if other.IsOpen() then
						return
					end
				end
				tabs.Visible = true
			end)
		end
		main.Visible = false
		oddsPanel.Visible = false
		giftPanel.Visible = false
		stopAnimation()
	end

	function shop.IsOpen()
		return main.Visible
	end

	closeX.Activated:Connect(shop.Close)
	local function showRestockPrice()
		local robux = stockFolder:GetAttribute("Robux_Restock")
		restockBtn.Text = robux and ("RESTOCK\nR$ " .. robux) or "RESTOCK"
	end
	showRestockPrice()
	stockFolder:GetAttributeChangedSignal("Robux_Restock"):Connect(showRestockPrice)
	restockBtn.Activated:Connect(function()
		restockRemote:FireServer()
	end)

	shops[kind] = shop
	return shop
end

createShop("planets")
createShop("packs")
createShop("suns")
createShop("gear")

---------------------------------------------------------------------
-- COIN NUMBER + FLYING COINS
---------------------------------------------------------------------
local COIN_SOUND_ID = "rbxassetid://330274138"      -- optional: paste a sound ID here for a "ding" each time a coin lands
local COIN_SOUND_VOLUME = 0.5

-- plays once when you collect a piece, right before the coins start flying
local PICKUP_SOUND_ID = "rbxassetid://133570405319995"
local PICKUP_SOUND_VOLUME = 0.7

local pickupSound = Instance.new("Sound")
pickupSound.Name = "PickupSound"
pickupSound.SoundId = PICKUP_SOUND_ID
pickupSound.Volume = PICKUP_SOUND_VOLUME

local coinSound = Instance.new("Sound")
coinSound.Name = "CoinSound"
coinSound.SoundId = COIN_SOUND_ID
coinSound.Volume = COIN_SOUND_VOLUME

-- the number on the coin bar. It jumps right away when you spend, but when coins are
-- flying in from a reward it only goes up as each coin lands.
local shownCoins = player:GetAttribute("Coins") or 0
local pendingReward = 0 -- coins that are still flying toward the coin bar
local coinCheckId = 0

local function renderCoins()
	coinLabel.Text = commas(shownCoins)
end
renderCoins()

local function refreshAll()
	for _, shop in pairs(shops) do
		shop.Refresh()
	end

	local actual = player:GetAttribute("Coins") or 0
	if actual <= shownCoins then
		shownCoins = actual -- spending shows right away
		renderCoins()
	else
		-- coins went up: wait a moment in case they're about to fly in from a reward
		coinCheckId += 1
		local id = coinCheckId
		task.delay(0.15, function()
			if id == coinCheckId and pendingReward <= 0 then
				shownCoins = player:GetAttribute("Coins") or 0
				renderCoins()
			end
		end)
	end
end

refreshAll()
player:GetAttributeChangedSignal("Coins"):Connect(refreshAll)
stockFolder.AttributeChanged:Connect(refreshAll)

local flyGui = make("ScreenGui", {
	Name = "CoinFlyGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 30,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local hudScale = make("UIScale", { Scale = 1 }, hud)
local function pulseHud()
	hudScale.Scale = 1.12
	TweenService:Create(
		hudScale,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

local function landCoin(value)
	pendingReward = math.max(pendingReward - value, 0)
	shownCoins += value
	renderCoins()
	pulseHud()
	if COIN_SOUND_ID ~= "" then
		playCopy(coinSound)
	end

	-- after the last coin lands, make sure the number is exactly right
	if pendingReward <= 0 then
		task.delay(0.1, function()
			if pendingReward <= 0 then
				shownCoins = player:GetAttribute("Coins") or 0
				renderCoins()
			end
		end)
	end
end

local flyingCoins = {}
local coinRng = Random.new()

local function spawnCoin(start, value, delay)
	local frame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Color3.fromRGB(255, 195, 50),
		Visible = false,
	}, flyGui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
	stroke(frame, Color3.fromRGB(150, 90, 10), 2)
	label({
		Text = "$",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	}, frame)

	table.insert(flyingCoins, {
		Frame = frame,
		Start = start,
		Sideways = coinRng:NextNumber(-110, 110),
		Value = value,
		Born = os.clock(),
		Delay = delay,
		Duration = coinRng:NextNumber(0.7, 0.95),
	})
end

local function showPopup(position, amount)
	local text = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 28,
		TextColor3 = Color3.fromRGB(255, 225, 110),
		Text = "+" .. commas(amount),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(160, 40),
	}, flyGui)
	local textStroke = make("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, text)

	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(text, info, {
		Position = UDim2.fromOffset(position.X, position.Y - 60),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(textStroke, info, { Transparency = 1 }):Play()
	Debris:AddItem(text, 1)
end

local function onCoinReward(amount, worldPosition)
	if typeof(amount) ~= "number" or typeof(worldPosition) ~= "Vector3" or amount <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	pendingReward += amount

	-- where the piece was on your screen (the middle of the screen if it's off to the side)
	local point, onScreen = camera:WorldToViewportPoint(worldPosition)
	local start = Vector2.new(point.X, point.Y)
	if not onScreen then
		start = camera.ViewportSize / 2
	end

	showPopup(start, amount)
	if PICKUP_SOUND_ID ~= "" then
		playCopy(pickupSound)
	end

	local count = math.clamp(math.ceil(amount / 40), 3, 10)
	local each = math.floor(amount / count)
	local remainder = amount - each * count
	for i = 1, count do
		local value = each + ((i == count) and remainder or 0)
		spawnCoin(start, value, (i - 1) * 0.05 + coinRng:NextNumber(0, 0.1))
	end
end

RunService.RenderStepped:Connect(function()
	if #flyingCoins == 0 then
		return
	end

	local now = os.clock()
	-- the coin icon's spot, in the same screen units the coins fly in
	local target = hudCoin.AbsolutePosition + hudCoin.AbsoluteSize / 2 + GuiService:GetGuiInset()

	for i = #flyingCoins, 1, -1 do
		local coin = flyingCoins[i]
		local elapsed = now - coin.Born - coin.Delay
		if elapsed >= 0 then
			coin.Frame.Visible = true
			local a = math.min(elapsed / coin.Duration, 1)
			local e = a * a -- speeds up as it nears the bar
			local control = (coin.Start + target) / 2 + Vector2.new(coin.Sideways, -120)
			local p = coin.Start * ((1 - e) ^ 2) + control * (2 * (1 - e) * e) + target * (e ^ 2)
			coin.Frame.Position = UDim2.fromOffset(p.X, p.Y)

			if a >= 1 then
				coin.Frame:Destroy()
				table.remove(flyingCoins, i)
				landCoin(coin.Value)
			end
		end
	end
end)

local function hookCoinReward(remote)
	if remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(onCoinReward)
	end
end
local existingReward = remotes:FindFirstChild("CoinReward")
if existingReward then
	hookCoinReward(existingReward)
end
remotes.ChildAdded:Connect(function(child)
	if child.Name == "CoinReward" then
		hookCoinReward(child)
	end
end)

task.spawn(function()
	while true do
		local restockAt = stockFolder:GetAttribute("RestockAt")
		local remaining = restockAt and math.max(0, restockAt - os.time()) or 0
		local text = string.format("New stock in %dm %02ds", math.floor(remaining / 60), remaining % 60)
		for _, shop in pairs(shops) do
			shop.TimerLabel.Text = text
		end
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------
-- PACK OPENING (big, immersive roll)
---------------------------------------------------------------------
local Lighting = game:GetService("Lighting")

local CARD_W, CARD_H, CARD_STEP = 170, 216, 184
local LAND_INDEX = 26
local TOTAL_CARDS = 36
local ROLL_SECONDS = 7
local WINDOW_H = 270
local STAGE_Y = 0.66            -- where the strip sits on screen (0 = top, 1 = bottom)
local PACK_W, PACK_H = 230, 280
local PACK_OFFSET = -(WINDOW_H / 2 + PACK_H / 2 + 14) -- the pack and black hole sit above the strip
local SHAKE_RARITIES = { Legendary = true, Mythic = true }

-- tick + pop every time a card passes under the marker while the strip rolls
local ROLL_TICK_SOUND_ID = CLICK_SOUND_ID -- paste another "rbxassetid://..." here for a different tick sound
local ROLL_TICK_VOLUME = 0.45
local ROLL_TICK_MIN_GAP = 0.04 -- seconds between ticks at most (keeps the fast start from turning into noise)
local ROLL_POP_SCALE = 1.09 -- how big a card pops as it passes the marker

local rollTickSound = Instance.new("Sound")
rollTickSound.Name = "RollTick"
rollTickSound.SoundId = ROLL_TICK_SOUND_ID
rollTickSound.Volume = ROLL_TICK_VOLUME
local lastRollTick = 0

-- record = { Card, Stroke, Scale } of the card now under the marker; progress = 0 (start) to 1 (about to land)
local function tickCard(record, progress)
	local now = os.clock()
	if now - lastRollTick >= ROLL_TICK_MIN_GAP then
		lastRollTick = now
		local tick = rollTickSound:Clone()
		tick.PlaybackSpeed = 0.9 + 0.5 * progress -- pitch climbs as the roll slows down
		tick.Parent = playerGui
		tick:Play()
		Debris:AddItem(tick, 1.5)
	end
	if record then
		record.Scale.Scale = ROLL_POP_SCALE
		TweenService:Create(record.Scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local rollGui = make("ScreenGui", {
	Name = "PackRollGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local rollRoot = make("Frame", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.08,
	Active = true, -- blocks clicks from reaching the game while it's open
	Visible = false,
}, rollGui)
gradient(rollRoot, Color3.fromRGB(30, 12, 66), Color3.fromRGB(3, 2, 10), 90)
addStuds(rollRoot, 1, 0.9, 0)
stars(rollRoot, 110)

-- everything lives on a stage that shrinks to fit small screens
local stage = make("Frame", {
	Name = "Stage",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 2,
}, rollRoot)
local stageScale = make("UIScale", { Scale = 1 }, stage)

local function fitStage()
	local camera = workspace.CurrentCamera
	if camera then
		local v = camera.ViewportSize
		stageScale.Scale = math.clamp(math.min(v.Y / 760, v.X / 760), 0.5, 1.15)
	end
end
fitStage()

local rollTitle = label({
	Text = "",
	TextSize = 42,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.new(0.9, 0, 0, 52),
	ZIndex = 8,
}, stage)

-- the black hole portal behind the pack
local portal = make("Frame", {
	Name = "Portal",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, STAGE_Y, PACK_OFFSET),
	Size = UDim2.fromOffset(440, 440),
	BackgroundTransparency = 1,
	ZIndex = 3,
}, stage)
local function portalRing(size, transparency)
	local ring = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = transparency,
		ZIndex = 3,
	}, portal)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	return make("UIGradient", {}, ring)
end
local portalOuter = portalRing(1, 0.55)
local portalInner = portalRing(0.8, 0.2)
local portalHole = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.62, 0.62),
	BackgroundColor3 = Color3.new(0, 0, 0),
	ZIndex = 4,
}, portal)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, portalHole)

-- the pack you're opening: it shakes while the strip rolls, then bursts when your seed lands
local rollPackHolder = make("Frame", {
	Name = "PackHolder",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, STAGE_Y, PACK_OFFSET),
	Size = UDim2.fromOffset(PACK_W, PACK_H),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 5,
}, stage)
local packPulse = make("UIScale", { Scale = 1 }, rollPackHolder)

local window = make("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, STAGE_Y, 0),
	Size = UDim2.new(0.86, 0, 0, WINDOW_H),
	BackgroundColor3 = Color3.new(1, 1, 1),
	ClipsDescendants = true,
	ZIndex = 6,
}, stage)
corner(window, 16)
gradient(window, Color3.fromRGB(38, 16, 76), Color3.fromRGB(14, 6, 32), 90)
make("UISizeConstraint", { MaxSize = Vector2.new(1100, WINDOW_H), MinSize = Vector2.new(300, WINDOW_H) }, window)
addStuds(window, 6, 0.78, 16)
local windowStroke = stroke(window, Color3.new(1, 1, 1), 5)
local windowGlow = make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 100, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 160, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 100, 255)),
	}),
}, windowStroke)

local track = make("Frame", {
	Name = "Track",
	Position = UDim2.fromOffset(10, 44),
	Size = UDim2.fromOffset(TOTAL_CARDS * CARD_STEP, CARD_H),
	BackgroundTransparency = 1,
	ZIndex = 7,
}, window)

-- glowing line the strip stops under, with arrows above and below
make("Frame", {
	Name = "Marker",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0, 4, 1, 0),
	BackgroundColor3 = Color3.fromRGB(255, 225, 120),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	ZIndex = 20,
}, window)
label({
	Name = "ArrowTop",
	Text = "▼",
	TextSize = 30,
	TextColor3 = Color3.fromRGB(255, 225, 120),
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 4),
	Size = UDim2.fromOffset(40, 34),
	ZIndex = 21,
}, window)
label({
	Name = "ArrowBottom",
	Text = "▲",
	TextSize = 24,
	TextColor3 = Color3.fromRGB(255, 225, 120),
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -1),
	Size = UDim2.fromOffset(40, 24),
	ZIndex = 21,
}, window)

-- the big "You got ..." text (shown where the pack was)
local resultLabel = label({
	Name = "Result",
	Text = "",
	TextSize = 46,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, STAGE_Y, PACK_OFFSET),
	Size = UDim2.new(0.9, 0, 0, 120),
	Visible = false,
	ZIndex = 12,
}, stage)
resultLabel.TextWrapped = true
local resultScale = make("UIScale", { Scale = 1 }, resultLabel)

local oddsLabel = label({
	Name = "Odds",
	Text = "",
	TextSize = 16,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, STAGE_Y, WINDOW_H / 2 + 12),
	Size = UDim2.new(0.95, 0, 0, 24),
	ZIndex = 8,
}, stage)

local skipBtn = button({
	Name = "Skip",
	Text = "SKIP",
	TextSize = 24,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, STAGE_Y, WINDOW_H / 2 + 46),
	Size = UDim2.fromOffset(160, 44),
	BackgroundColor3 = Color3.fromRGB(215, 38, 44),
	ZIndex = 8,
}, stage)
corner(skipBtn, 8)
stroke(skipBtn, Color3.fromRGB(255, 120, 120), 3)

-- flash over the whole screen when the seed lands
local flash = make("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	Active = false,
	ZIndex = 40,
}, rollRoot)

local function oddsText(pack)
	local parts = {}
	for _, rarity in ipairs(PackCatalog.RarityOrder) do
		if (pack.Odds[rarity] or 0) > 0 then
			table.insert(parts, string.format(
				'<font color="#%s">%s %s%%</font>',
				PlanetCatalog.RarityColor(rarity):ToHex(),
				rarity,
				formatPercent(PackCatalog.Percent(pack, rarity))
				))
		end
	end
	return table.concat(parts, "  ·  ")
end

local function makeCard(index, planet)
	local color = PlanetCatalog.RarityColor(planet.Rarity)

	local card = make("Frame", {
		Name = "Card" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5), -- centred, so the pop grows from the middle of the card
		Position = UDim2.fromOffset((index - 1) * CARD_STEP + CARD_W / 2, CARD_H / 2),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 8,
	}, track)
	corner(card, 12)
	local cardStroke = stroke(card, color, 4)
	gradient(card, Color3.fromRGB(56, 26, 98), Color3.fromRGB(24, 10, 46), 90)
	addStuds(card, 8, 0.78, 12)
	local cardScale = make("UIScale", { Scale = 1 }, card)

	local iconHolder = make("Frame", {
		Position = UDim2.new(0.5, -62, 0, 10),
		Size = UDim2.fromOffset(124, 124),
		BackgroundColor3 = Color3.fromRGB(10, 5, 22),
		ZIndex = 9,
	}, card)
	corner(iconHolder, 10)
	stroke(iconHolder, color, 2, 0.4)
	makePlanetIcon(iconHolder, planet)

	local nameLabel = label({
		Text = planet.Name,
		TextSize = 22,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 6, 0, 140),
		Size = UDim2.new(1, -12, 0, 30),
		ZIndex = 9,
	}, card)
	make("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 9 }, nameLabel)

	label({
		Text = string.upper(planet.Rarity),
		TextSize = 17,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 6, 0, 174),
		Size = UDim2.new(1, -12, 0, 26),
		ZIndex = 9,
	}, card)

	return card, cardStroke, cardScale
end

local rollSession = 0
local rollState = nil -- { revealed, tween, finalX, result, started, landed }
local rollConnection = nil
local blur = nil

local function setBlur(size)
	if size > 0 then
		if not blur then
			blur = Instance.new("BlurEffect")
			blur.Size = 0
			blur.Parent = Lighting
		end
		TweenService:Create(blur, TweenInfo.new(0.5), { Size = size }):Play()
	elseif blur then
		local old = blur
		blur = nil
		local tween = TweenService:Create(old, TweenInfo.new(0.4), { Size = 0 })
		tween.Completed:Connect(function()
			old:Destroy()
		end)
		tween:Play()
	end
end

local function stopRollAnimation()
	if rollConnection then
		rollConnection:Disconnect()
		rollConnection = nil
	end
end

local function startRollAnimation()
	stopRollAnimation()
	rollConnection = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local rolling = rollState and not rollState.revealed
		local boost = rolling and 1 or 0.5
		portalOuter.Rotation = (t * 80 * boost) % 360
		portalInner.Rotation = (-t * 130 * boost) % 360
		windowGlow.Rotation = (t * 50) % 360

		-- which card is under the marker right now? when it changes: tick sound + that card pops
		if rolling and rollState.cards and rollState.windowWidth then
			local underMarker = rollState.windowWidth / 2 - track.Position.X.Offset
			local index = math.clamp(math.floor(underMarker / CARD_STEP) + 1, 1, TOTAL_CARDS)
			if index ~= rollState.lastIndex then
				rollState.lastIndex = index
				tickCard(rollState.cards[index], math.clamp((t - rollState.started) / ROLL_SECONDS, 0, 1))
			end
		end

		if rolling and rollPackHolder.Visible then
			local elapsed = t - rollState.started
			local calm = math.max(0.2, 1 - elapsed / ROLL_SECONDS)
			rollPackHolder.Rotation = math.sin(t * 28) * 7 * calm
			packPulse.Scale = 1 + math.sin(t * 9) * 0.035
		end
	end)
end

local function closeRoll(session)
	if session ~= rollSession or not rollState then
		return
	end
	rollState = nil
	rollRoot.Visible = false
	stopRollAnimation()
	setBlur(0)
	finishRemote:FireServer()
end

-- sparks that fly out from the black hole
local function burst(color)
	local rng = Random.new()
	for _ = 1, 34 do
		local size = rng:NextInteger(6, 14)
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(180, 460)
		local spark = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, STAGE_Y, PACK_OFFSET),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = rng:NextNumber() < 0.35 and Color3.new(1, 1, 1) or color,
			Rotation = rng:NextInteger(0, 90),
			ZIndex = 11,
		}, stage)
		make("UICorner", { CornerRadius = UDim.new(rng:NextNumber() < 0.5 and 1 or 0.2, 0) }, spark)
		local duration = rng:NextNumber(0.7, 1.3)
		TweenService:Create(spark, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(angle) * distance, STAGE_Y, PACK_OFFSET + math.sin(angle) * distance),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
			Rotation = spark.Rotation + 200,
		}):Play()
		task.delay(duration + 0.1, function()
			spark:Destroy()
		end)
	end
end

local function shakeStage(seconds, strength)
	task.spawn(function()
		local rng = Random.new()
		local started = os.clock()
		while os.clock() - started < seconds do
			local fade = 1 - (os.clock() - started) / seconds
			stage.Position = UDim2.new(0.5, rng:NextInteger(-strength, strength) * fade, 0.5, rng:NextInteger(-strength, strength) * fade)
			task.wait()
		end
		stage.Position = UDim2.fromScale(0.5, 0.5)
	end)
end

local function revealRoll(session)
	if session ~= rollSession or not rollState or rollState.revealed then
		return
	end
	rollState.revealed = true
	-- tell the sound system the seed is being shown NOW (natural stop or SKIP), so the charge-up sound stops
	Players.LocalPlayer:SetAttribute("PackRevealAt", os.clock())
	if rollState.tween then
		rollState.tween:Cancel()
	end
	track.Position = UDim2.fromOffset(rollState.finalX, 44)

	local planet = rollState.result
	local color = PlanetCatalog.RarityColor(planet.Rarity)

	-- the pack bursts open
	local packView = rollPackHolder:FindFirstChildOfClass("ViewportFrame")
	if rollPackHolder.Visible and packView then
		rollPackHolder.Rotation = 0
		TweenService:Create(packPulse, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.6 }):Play()
		TweenService:Create(packView, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
	end

	-- screen flash in the seed's rarity color, sparks, and a bigger black hole for a moment
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.35
	TweenService:Create(flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
	burst(color)
	TweenService:Create(portal, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(540, 540) }):Play()
	if SHAKE_RARITIES[planet.Rarity] then
		shakeStage(0.7, 9)
	end

	-- the winning card pops
	if rollState.landed then
		rollState.landed.Stroke.Thickness = 8
		rollState.landed.Card.ZIndex = 12
		TweenService:Create(rollState.landed.Scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 }):Play()
	end

	resultLabel.Text = string.format(
		'You got\n<font color="#%s">%s Seed</font>\n<font size="26">%s</font>',
		color:ToHex(),
		planet.Name,
		string.upper(planet.Rarity)
	)
	resultScale.Scale = 0.3
	resultLabel.Visible = true
	TweenService:Create(resultScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.delay(3.2, function()
		closeRoll(session)
	end)
end

rollRemote.OnClientEvent:Connect(function(packId, planetId)
	local pack = PackCatalog.Get(packId)
	local result = PlanetCatalog.Get(planetId)
	if not pack or not result then
		finishRemote:FireServer()
		return
	end

	rollSession += 1
	local session = rollSession

	for _, child in ipairs(track:GetChildren()) do
		child:Destroy()
	end

	local rng = Random.new()
	local landed
	local cards = {}
	for i = 1, TOTAL_CARDS do
		-- filler cards come from the pack's own odds, so you only ever see its rarities flash by; the landing card is the real result
		local card, cardStroke, cardScale = makeCard(i, i == LAND_INDEX and result or PackCatalog.RollPlanet(pack, rng))
		cards[i] = { Card = card, Stroke = cardStroke, Scale = cardScale }
		if i == LAND_INDEX then
			landed = { Card = card, Stroke = cardStroke, Scale = cardScale }
		end
	end

	-- the 3D pack above the strip
	for _, child in ipairs(rollPackHolder:GetChildren()) do
		if not child:IsA("UIScale") then
			child:Destroy()
		end
	end
	packPulse.Scale = 1
	rollPackHolder.Rotation = 0
	rollPackHolder.Visible = makePackViewport(rollPackHolder, pack.Name) ~= nil

	-- the portal and border take the pack's color
	local tierColor = PlanetCatalog.RarityColor(pack.Tier)
	local gold = Color3.fromRGB(255, 190, 80)
	local sequence = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tierColor),
		ColorSequenceKeypoint.new(0.5, gold),
		ColorSequenceKeypoint.new(1, tierColor),
	})
	portalOuter.Color = sequence
	portalInner.Color = sequence
	windowGlow.Color = sequence
	portal.Size = UDim2.fromOffset(440, 440)
	flash.BackgroundTransparency = 1

	rollTitle.Text = "Opening " .. pack.Name
	oddsLabel.Text = oddsText(pack)
	resultLabel.Visible = false
	track.Position = UDim2.fromOffset(10, 44)
	fitStage()
	stage.Position = UDim2.fromScale(0.5, 0.5)
	rollRoot.Visible = true
	setBlur(20)

	task.wait() -- let the window size itself before measuring it

	local windowWidth = window.AbsoluteSize.X / math.max(stageScale.Scale, 0.01)
	local jitter = rng:NextInteger(-math.floor(CARD_W / 3), math.floor(CARD_W / 3))
	local finalX = windowWidth / 2 - ((LAND_INDEX - 1) * CARD_STEP + CARD_W / 2) + jitter

	local tween = TweenService:Create(
		track,
		TweenInfo.new(ROLL_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(finalX, 44) }
	)
	rollState = {
		revealed = false,
		tween = tween,
		finalX = finalX,
		result = result,
		started = os.clock(),
		landed = landed,
		cards = cards,
		windowWidth = windowWidth,
		lastIndex = 1, -- the strip starts on the first card, so the first tick is when card 2 arrives
	}
	startRollAnimation()

	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			revealRoll(session)
		end
	end)
	tween:Play()
end)

skipBtn.Activated:Connect(function()
	if not rollState then
		return
	end
	if rollState.revealed then
		closeRoll(rollSession)
	else
		revealRoll(rollSession)
	end
end)

---------------------------------------------------------------------
-- NPCs: a prompt (and click) on every NPC listed in NPC_SHOPS
---------------------------------------------------------------------
local activeRoot = nil
local attachedCount = 0

local function openShopFor(kind, root)
	for otherKind, shop in pairs(shops) do
		if otherKind ~= kind then
			shop.Close()
		end
	end
	activeRoot = root
	shops[kind].Open()
end

local function attachToNpc(npc, kind)
	if not npc:IsA("Model") or npc:GetAttribute("SeedShopAttached") then
		return
	end
	if Players:GetPlayerFromCharacter(npc) then
		return
	end
	npc:SetAttribute("SeedShopAttached", true)

	local root = npc:FindFirstChild("HumanoidRootPart")
		or npc:WaitForChild("HumanoidRootPart", 5)
		or npc:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		warn("SeedShopUI: couldn't find a part inside " .. npc:GetFullName())
		return
	end

	-- hide any leftover prompt from the old shop system on this NPC
	for _, descendant in ipairs(npc:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("ShopKind") ~= nil then
			descendant.Enabled = false
		end
	end

	-- talking to the NPC: they type a line above their head, then the shop opens
	local head = NpcTalk.HeadOf(npc)
	local talking = false
	local function open()
		if talking or shops[kind].IsOpen() then
			return
		end
		talking = true
		NpcTalk.Say(head, NPC_LINES[kind] or "Here's what's in stock", 3)
		task.delay(0.45, function()
			talking = false
			openShopFor(kind, root)
		end)
	end

	local prompt = make("ProximityPrompt", {
		ActionText = "Talk",
		ObjectText = THEMES[kind].ObjectText,
		HoldDuration = 0,
		MaxActivationDistance = 12,
		RequiresLineOfSight = false,
	}, root)
	prompt.Triggered:Connect(open)
	NpcTalk.OutlineWhenNear(npc, prompt) -- white outline while you're close enough to talk

	local click = make("ClickDetector", { MaxActivationDistance = 14 }, npc)
	click.MouseClick:Connect(open)

	attachedCount += 1
	print("SeedShopUI: " .. kind .. " shop attached to " .. npc:GetFullName())
end

local function consider(inst)
	if inst:IsA("Model") and NPC_SHOPS[inst.Name] then
		task.spawn(attachToNpc, inst, NPC_SHOPS[inst.Name])
	elseif inst:IsA("Humanoid") and NPC_SHOPS[inst.DisplayName] and inst.Parent and inst.Parent:IsA("Model") then
		task.spawn(attachToNpc, inst.Parent, NPC_SHOPS[inst.DisplayName])
	end
end

for _, inst in ipairs(workspace:GetDescendants()) do
	consider(inst)
end
workspace.DescendantAdded:Connect(consider)

task.delay(10, function()
	if attachedCount == 0 then
		warn("SeedShopUI: found no NPC matching NPC_SHOPS after 10 seconds. Check the names at the top of the script.")
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		if activeRoot then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - activeRoot.Position).Magnitude > CLOSE_DISTANCE then
				for _, shop in pairs(shops) do
					shop.Close()
				end
				activeRoot = nil
			end
		end
	end
end)
