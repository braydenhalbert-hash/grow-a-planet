--[[
	TutorialClient  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	The interactive tutorial. Guides (GuideNPC) pop in next to you, walk with you, point at things,
	and react to what you actually do in the game: one mechanic at a time, no walls of text.

	  * New players: Cosmo, Zib and Sprocket teach the loop (buy a seed -> plant -> grow -> harvest -> sell),
	    then pop back later when something new becomes useful (packs, upgrading, sprinklers, black holes...).
	  * A glowing path, a bouncing arrow, an outline and a sparkle ring show where to go;
	    an arrow on the edge of the screen points there when it's behind you.
	  * The objective card (top-right) shows the current goal and has a SKIP button.
	  * Settings > Replay Tutorial gives a hint during a lesson, or replays the tutorial.
	  * Progress is saved (TutorialServer). Players who already played skip the basics automatically.

	It only LISTENS to the game (remotes the game already sends, your hotbar, the planted planets),
	so it never changes how anything works. Lines live in TutorialSteps (ReplicatedStorage).

	Needs: GuideNPC + TutorialSteps + Stardust (ReplicatedStorage), TutorialServer (ServerScriptService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GuideNPC = require(ReplicatedStorage:WaitForChild("GuideNPC"))
local Steps = require(ReplicatedStorage:WaitForChild("TutorialSteps"))
local Stardust = require(ReplicatedStorage:WaitForChild("Stardust"))
local ScreenFit = require(ReplicatedStorage:WaitForChild("ScreenFit")) -- phone layout
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local stateRemote = remotes:WaitForChild("TutorialState", 30)
local eventRemote = remotes:WaitForChild("TutorialEvent", 30)
if not stateRemote or not eventRemote then
	warn("[TutorialClient] TutorialServer isn't running")
	return
end

local rgb = Color3.fromRGB
local V3 = Vector3.new

local NEAR_DISTANCE = 22      -- "near a shop" for triggers + discoveries
local HINT_AFTER = 22          -- seconds without progress before a hint
local REACTION_GAP = 8         -- seconds between quick reactions
local KNOWN_KINDS = { Seed = true, Pack = true, Gear = true, Planet = true }

local fx = Instance.new("Folder")
fx.Name = "TutorialFX"
fx.Parent = workspace

---------------------------------------------------------------------
-- Saved progress
---------------------------------------------------------------------
local progress = { Done = {}, Skipped = false, Experienced = false }
local function isDone(id)
	return progress.Done[id] == true
end
local function markDone(id)
	if not isDone(id) then
		progress.Done[id] = true
		eventRemote:FireServer("done", id)
	end
end

---------------------------------------------------------------------
-- Signals: everything the game already tells us, turned into simple events
---------------------------------------------------------------------
local listeners = {}
local function on(name, fn)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
	return function()
		local list = listeners[name]
		local i = list and table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end
local function emit(name, ...)
	for _, fn in ipairs(table.clone(listeners[name] or {})) do
		task.spawn(fn, ...)
	end
end

local function hookRemote(name, fn)
	task.spawn(function()
		local remote = remotes:WaitForChild(name, 60)
		if remote then
			remote.OnClientEvent:Connect(fn)
		end
	end)
end

hookRemote("AudioCue", function(cue, a, b)
	if type(cue) == "string" then
		emit(cue, a, b) -- plant, claim, grow_ready, sell, buy_seed, buy_pack ...
	end
end)
hookRemote("PlantHarvested", function(name, weight, tierName)
	emit("harvest", name, weight, tierName)
end)
hookRemote("PackRoll", function(packId, planetId)
	emit("pack_roll", packId, planetId)
end)
hookRemote("MutationGained", function(model, mutId)
	if typeof(model) == "Instance" and model:GetAttribute("Owner") == player.UserId then
		emit("mutation", mutId, model)
	end
end)
hookRemote("CoinReward", function(value)
	emit("collect", value)
end)
hookRemote("Notice", function(text, kind)
	if kind == "error" and type(text) == "string" then
		emit("error", text)
	end
end)

task.spawn(function()
	local folder = workspace:WaitForChild("Sprinklers", 60)
	if folder then
		folder.ChildAdded:Connect(function(model)
			task.wait(0.1)
			if model:GetAttribute("Owner") == player.UserId then
				emit("sprinkler_placed", model:GetAttribute("GearId"))
			end
		end)
	end
end)

-- inventory: notice when the hotbar gains something (works for shops, packs, harvests, admin gifts...)
local function toolKey(tool)
	local kind = tool:GetAttribute("Kind")
	if not kind then
		return nil
	end
	local id = tool:GetAttribute("PlanetId") or tool:GetAttribute("PackId") or tool:GetAttribute("GearId") or tool.Name
	return kind, id
end
local function allTools()
	local tools = {}
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") then
					table.insert(tools, t)
				end
			end
		end
	end
	return tools
end
local function snapshot()
	local counts, tools = {}, {}
	for _, tool in ipairs(allTools()) do
		local kind, id = toolKey(tool)
		if kind then
			local key = kind .. "\0" .. tostring(id)
			counts[key] = (counts[key] or 0) + (tool:GetAttribute("Count") or 1)
			tools[key] = tool
		end
	end
	return counts, tools
end
local lastCounts = snapshot()
local quietUntil = os.clock() + 3 -- just joined / respawned: everything "appears", that's not a purchase
local diffQueued = false
local function queueDiff()
	if diffQueued then
		return
	end
	diffQueued = true
	task.delay(0.35, function()
		diffQueued = false
		local counts, tools = snapshot()
		if os.clock() > quietUntil then
			for key, n in pairs(counts) do
				local before = lastCounts[key] or 0
				if n > before then
					local kind, id = string.match(key, "^(.-)%z(.*)$")
					emit("got_" .. kind, id, n - before, tools[key])
					emit("got_item", kind, id, tools[key])
				end
			end
		end
		lastCounts = counts
	end)
end
local function watchContainer(container)
	if not container then
		return
	end
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			child:GetAttributeChangedSignal("Count"):Connect(queueDiff)
			queueDiff()
		end
	end)
	container.ChildRemoved:Connect(queueDiff)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			child:GetAttributeChangedSignal("Count"):Connect(queueDiff)
		end
	end
end
local function onCharacter(character)
	quietUntil = os.clock() + 3
	watchContainer(character)
	watchContainer(player:WaitForChild("Backpack", 10))
	task.delay(3.2, function()
		lastCounts = snapshot()
	end)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- a rarer seed than Common counts as "upgrading"
on("got_Seed", function(id)
	local planet = PlanetCatalog.Get(id)
	local rarity = planet and PlanetCatalog.Rarities[planet.Rarity]
	if rarity and (rarity.Order or 1) >= 2 then
		emit("buy_rarer", id)
	end
end)

---------------------------------------------------------------------
-- Looking at the world
---------------------------------------------------------------------
local function root()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function findShop(name)
	local shops = workspace:FindFirstChild("SHOPS")
	local model = (shops and shops:FindFirstChild(name, true)) or workspace:FindFirstChild(name, true)
	if model and not model:IsA("Model") then
		model = model:FindFirstAncestorOfClass("Model") or model
	end
	return model
end

local function mainPart(inst)
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	return inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
end

local function myPlants()
	local list = {}
	local folder = workspace:FindFirstChild("PlantedPlanets")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:GetAttribute("Owner") == player.UserId then
				table.insert(list, m)
			end
		end
	end
	return list
end

local function isReadyModel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("TextLabel") and string.find(d.Text, "READY", 1, true) then
			return true
		end
	end
	return false
end

local function nearest(list, getPos)
	local r = root()
	local best, bestD
	for _, item in ipairs(list) do
		local p = getPos(item)
		if p then
			local d = r and (p - r.Position).Magnitude or 0
			if not bestD or d < bestD then
				best, bestD = item, d
			end
		end
	end
	return best, bestD
end

local function pads(filter)
	local list = {}
	for _, pad in ipairs(CollectionService:GetTagged("GardenPad")) do
		if pad:IsA("BasePart") and pad:IsDescendantOf(workspace) and filter(pad) then
			table.insert(list, pad)
		end
	end
	return list
end

local function isBlackHole(model)
	local planet = PlanetCatalog.Get(model:GetAttribute("PlanetId") or "")
	return planet and planet.Group == "BlackHole"
end

-- target kinds -> (part to point at, model to outline)
local Targets = {}
function Targets.npc(t)
	local model = findShop(t.Name)
	return mainPart(model), model
end
function Targets.myBase()
	local mine = pads(function(p)
		return p:GetAttribute("BaseOwner") == player.UserId
	end)
	local pad = nearest(mine, function(p)
		return p.Position
	end)
	return pad, pad
end
function Targets.base()
	local pad = Targets.myBase()
	if pad then
		return pad, pad
	end
	local empty = pads(function(p)
		return p:GetAttribute("BaseOwner") == 0
	end)
	if #empty == 0 then
		empty = pads(function(p)
			return p:GetAttribute("BaseOwner") == nil
		end)
	end
	pad = nearest(empty, function(p)
		return p.Position
	end)
	return pad, pad
end
function Targets.myPlant()
	local m = nearest(myPlants(), function(model)
		return model:GetPivot().Position
	end)
	return mainPart(m), m
end
function Targets.readyPlant()
	local ready = {}
	for _, m in ipairs(myPlants()) do
		if isReadyModel(m) then
			table.insert(ready, m)
		end
	end
	local m = nearest(#ready > 0 and ready or myPlants(), function(model)
		return model:GetPivot().Position
	end)
	return mainPart(m), m
end
function Targets.blackHole()
	local holes = {}
	for _, m in ipairs(myPlants()) do
		if isBlackHole(m) then
			table.insert(holes, m)
		end
	end
	local m = nearest(holes, function(model)
		return model:GetPivot().Position
	end)
	return mainPart(m), m
end

-- checks used by SkipIf / Trigger
local function countKind(kind)
	local n = 0
	for _, tool in ipairs(allTools()) do
		local k = tool:GetAttribute("Kind")
		if k == kind then
			n += 1
		elseif kind == "Sprinkler" and k == "Gear" then
			local gear = GearCatalog.Get(tool:GetAttribute("GearId") or "")
			if gear and gear.Kind == "Sprinkler" then
				n += 1
			end
		end
	end
	return n
end
local function hasTool(kind, attr, id)
	for _, tool in ipairs(allTools()) do
		if tool:GetAttribute("Kind") == kind and tool:GetAttribute(attr) == id then
			return true
		end
	end
	return false
end
local Checks = {
	hasSeed = function()
		return countKind("Seed") > 0
	end,
	hasMoonSeed = function()
		return hasTool("Seed", "PlanetId", "moon")
	end,
	hasBasicSprinkler = function()
		return hasTool("Gear", "GearId", "sprinkler_basic")
	end,
	hasPlant = function()
		return #myPlants() > 0
	end,
	hasReadyPlant = function()
		for _, m in ipairs(myPlants()) do
			if isReadyModel(m) then
				return true
			end
		end
		return false
	end,
	noPlanet = function()
		return countKind("Planet") == 0
	end,
	hasPack = function()
		return countKind("Pack") > 0
	end,
	hasSprinkler = function()
		return countKind("Sprinkler") > 0
	end,
	placedSprinkler = function()
		local folder = workspace:FindFirstChild("Sprinklers")
		for _, m in ipairs(folder and folder:GetChildren() or {}) do
			if m:GetAttribute("Owner") == player.UserId then
				return true
			end
		end
		return false
	end,
	hasRareSeed = function()
		for _, tool in ipairs(allTools()) do
			if tool:GetAttribute("Kind") == "Seed" then
				local planet = PlanetCatalog.Get(tool:GetAttribute("PlanetId") or "")
				local info = planet and PlanetCatalog.Rarities[planet.Rarity]
				if info and (info.Order or 1) >= 2 then
					return true
				end
			end
		end
		return false
	end,
}

local function coins()
	return player:GetAttribute("Coins") or 0
end

local function nearShop(name)
	local r = root()
	local part = mainPart(findShop(name))
	return r and part and (part.Position - r.Position).Magnitude <= NEAR_DISTANCE
end

local function triggerMet(trigger)
	if not trigger then
		return true
	end
	if trigger.Near and not nearShop(trigger.Near) then
		return false
	end
	if trigger.Coins and coins() < trigger.Coins then
		if not (trigger.OrNear and nearShop(trigger.OrNear)) then
			return false
		end
	end
	if trigger.Has and countKind(trigger.Has) == 0 then
		return false
	end
	if trigger.Items and #allTools() < trigger.Items then
		return false
	end
	if trigger.Plant == "BlackHole" then
		local any = false
		for _, m in ipairs(myPlants()) do
			if isBlackHole(m) then
				any = true
			end
		end
		if not any then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------
-- UI: objective card, skip button, ? button, screen-edge arrow
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "TutorialUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 30
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local FONT = Enum.Font.FredokaOne
local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = p
	return c
end
local function stroke(p, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end
local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = rgb(255, 255, 255)
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local card = Instance.new("Frame")
card.Name = "Objective"
card.AnchorPoint = Vector2.new(1, 0)
local CARD_Y = 132 -- phones move it up (set further down)
card.Position = UDim2.new(1, 340, 0, CARD_Y)
card.Size = UDim2.fromOffset(300, 96)
card.BackgroundColor3 = rgb(18, 16, 34)
card.BackgroundTransparency = 0.08
card.Parent = gui
corner(card, 16)
local cardStroke = stroke(card, rgb(90, 255, 140), 2.5)
local stripe = Instance.new("Frame")
stripe.Size = UDim2.new(0, 6, 1, -24)
stripe.Position = UDim2.fromOffset(10, 12)
stripe.BackgroundColor3 = rgb(90, 255, 140)
stripe.Parent = card
corner(stripe, 3)
local whoLabel = label(card, { Position = UDim2.fromOffset(26, 9), Size = UDim2.new(1, -40, 0, 16), TextSize = 13, TextColor3 = rgb(90, 255, 140), Text = "COSMO" })
local goalLabel = label(card, { Position = UDim2.fromOffset(26, 27), Size = UDim2.new(1, -40, 0, 42), TextSize = 19, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
local infoLabel = label(card, { Position = UDim2.fromOffset(26, 70), Size = UDim2.new(1, -40, 0, 16), TextSize = 13, TextColor3 = rgb(170, 165, 200), Text = "" })

local skipButton = Instance.new("TextButton")
skipButton.AnchorPoint = Vector2.new(1, 0)
skipButton.Position = UDim2.new(1, 0, 1, 8)
skipButton.Size = UDim2.fromOffset(130, 30)
skipButton.BackgroundColor3 = rgb(40, 32, 66)
skipButton.Font = FONT
skipButton.TextSize = 15
skipButton.TextColor3 = rgb(255, 255, 255)
skipButton.Text = "SKIP TUTORIAL  »"
skipButton.AutoButtonColor = true
skipButton.Parent = card
corner(skipButton, 15)
stroke(skipButton, rgb(255, 110, 140), 2)

local cardShown = false
local function showCard(show)
	if show == cardShown then
		return
	end
	cardShown = show
	TweenService:Create(card, TweenInfo.new(0.45, show and Enum.EasingStyle.Back or Enum.EasingStyle.Quad, show and Enum.EasingDirection.Out or Enum.EasingDirection.In), {
		Position = show and UDim2.new(1, -16, 0, CARD_Y) or UDim2.new(1, 340, 0, CARD_Y),
	}):Play()
end

local function setCard(step, guideColor, info)
	cardStroke.Color = guideColor
	stripe.BackgroundColor3 = guideColor
	whoLabel.TextColor3 = guideColor
	whoLabel.Text = string.upper(step.Guide) .. "  ·  " .. string.upper((Steps.Guides[step.Guide] or {}).Title or "")
	goalLabel.Text = step.Goal or ""
	goalLabel.TextColor3 = rgb(255, 255, 255)
	infoLabel.Text = info or ""
end

local function cardDone()
	goalLabel.Text = "DONE!  " .. goalLabel.Text
	goalLabel.TextColor3 = rgb(110, 255, 150)
	-- a little pop (uses the card's own scale, which is smaller on phones)
	local s = card:FindFirstChild("PhoneScale")
	if s then
		local base = ScreenFit.IsPhone() and 0.72 or 1
		s.Scale = base * 1.08
		TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = base }):Play()
	end
end

-- edge arrow (when the target is behind you or off screen)
local edge = Instance.new("Frame")
edge.AnchorPoint = Vector2.new(0.5, 0.5)
edge.Size = UDim2.fromOffset(64, 64)
edge.BackgroundTransparency = 1
edge.Visible = false
edge.Parent = gui
local chevron = Instance.new("Frame")
chevron.AnchorPoint = Vector2.new(0.5, 0.5)
chevron.Position = UDim2.fromScale(0.5, 0.5)
chevron.Size = UDim2.fromOffset(44, 44)
chevron.BackgroundTransparency = 1
chevron.Parent = edge
for _, sign in ipairs({ 1, -1 }) do
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(1, 0.5)
	bar.Position = UDim2.new(1, -4, 0.5, sign * 9)
	bar.Size = UDim2.fromOffset(28, 9)
	bar.Rotation = sign * 40
	bar.BackgroundColor3 = rgb(255, 255, 255)
	bar.Parent = chevron
	corner(bar, 5)
	bar.Name = "Bar"
end
local edgeDist = label(edge, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(80, 18), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4 })

-- confirm box for "replay the tutorial?"
local confirm = Instance.new("Frame")
confirm.AnchorPoint = Vector2.new(0.5, 0.5)
confirm.Position = UDim2.fromScale(0.5, 0.42)
confirm.Size = UDim2.fromOffset(300, 128)
confirm.BackgroundColor3 = rgb(18, 16, 34)
confirm.Visible = false
confirm.Parent = gui
corner(confirm, 16)
stroke(confirm, rgb(90, 255, 140), 2.5)
label(confirm, { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 50), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "Replay the tutorial with Cosmo?" })
local function smallButton(parent, text, color, x)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(0.5, x, 1, -46)
	b.Size = UDim2.fromOffset(120, 34)
	b.BackgroundColor3 = color
	b.Font = FONT
	b.TextSize = 18
	b.TextColor3 = rgb(25, 20, 40)
	b.Text = text
	b.Parent = parent
	corner(b, 17)
	return b
end
local yesButton = smallButton(confirm, "Yes!", rgb(110, 255, 150), -128)
local noButton = smallButton(confirm, "No thanks", rgb(200, 195, 225), 8)

-- the ? button (top-right, styled like the game's own round buttons)
local helpButton = Instance.new("TextButton")
helpButton.Name = "TutorialHelpButton"
helpButton.AnchorPoint = Vector2.new(1, 0)
helpButton.Size = UDim2.fromOffset(56, 56)
helpButton.Position = UDim2.new(1, -16, 0, 64)
helpButton.BackgroundColor3 = rgb(30, 30, 40)
helpButton.BackgroundTransparency = 0.15
helpButton.Font = FONT
helpButton.TextSize = 32
helpButton.TextColor3 = rgb(255, 255, 255)
helpButton.Text = "?"
helpButton.Parent = gui
local helpCorner = Instance.new("UICorner")
helpCorner.CornerRadius = UDim.new(1, 0)
helpCorner.Parent = helpButton
stroke(helpButton, rgb(190, 200, 190), 2, 0.4)

-- PHONES: a smaller objective card higher up, and a smaller ? button
ScreenFit.ScaleOnPhone(card, 0.72)
ScreenFit.Watch(function()
	local phone = ScreenFit.IsPhone()
	CARD_Y = phone and 124 or 132
	card.Position = UDim2.new(1, cardShown and -10 or 340, 0, CARD_Y)
	helpButton.Size = phone and UDim2.fromOffset(44, 44) or UDim2.fromOffset(56, 56)
	helpButton.Position = phone and UDim2.new(1, -10, 0, 64) or UDim2.new(1, -16, 0, 64)
	confirm.Size = UDim2.fromOffset(300, 128)
end)
task.spawn(function()
	-- copy the look of GardenHotbar's round buttons
	local tools
	for _ = 1, 40 do
		tools = playerGui:FindFirstChild("ToolsButton", true)
		if tools then
			break
		end
		task.wait(0.25)
	end
	if tools and tools:IsA("GuiObject") then
		helpButton.BackgroundColor3 = tools.BackgroundColor3
		helpButton.BackgroundTransparency = tools.BackgroundTransparency
	end
end)

---------------------------------------------------------------------
-- Indicators in the world: glowing path, bouncing arrow, outline, sparkle ring
---------------------------------------------------------------------
local function fxPart(props)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = fx
	return p
end

local indicator = {}
local function buildIndicator(color)
	local arrow = Instance.new("Model")
	arrow.Name = "TutorialArrow"
	local parts = {}
	local function piece(size, offset)
		local p = fxPart({ Size = size, Color = color, Material = Enum.Material.Neon })
		p.Parent = arrow
		table.insert(parts, { Part = p, Offset = offset })
		return p
	end
	piece(V3(0.7, 2.2, 0.7), CFrame.new(0, 1.6, 0))
	piece(V3(0.7, 2.0, 0.7), CFrame.new(-0.55, 0.35, 0) * CFrame.Angles(0, 0, math.rad(-40)))
	piece(V3(0.7, 2.0, 0.7), CFrame.new(0.55, 0.35, 0) * CFrame.Angles(0, 0, math.rad(40)))
	piece(V3(0.7, 0.7, 2.0), CFrame.new(0, 0.35, -0.55) * CFrame.Angles(math.rad(40), 0, 0))
	piece(V3(0.7, 0.7, 2.0), CFrame.new(0, 0.35, 0.55) * CFrame.Angles(math.rad(-40), 0, 0))
	arrow.Parent = fx
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 14
	glow.Brightness = 2
	glow.Parent = parts[1].Part
	local sparkle = Stardust.Emitter("Star", { rgb(255, 255, 255), color, color }, {
		Rate = 10, Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
	})
	sparkle.Parent = parts[1].Part

	local ring = fxPart({ Shape = Enum.PartType.Cylinder, Size = V3(0.12, 9, 9), Color = color, Material = Enum.Material.Neon, Transparency = 0.6 })
	local ringDust = Stardust.Emitter("Dust", { rgb(255, 255, 255), color, color }, {
		Rate = 14, Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(1.5, 3), EmissionDirection = Enum.NormalId.Right,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
	})
	ringDust.Parent = ring

	local beamEnd = fxPart({ Size = V3(0.2, 0.2, 0.2), Transparency = 1 })
	local a1 = Instance.new("Attachment")
	a1.Parent = beamEnd
	local beam = Instance.new("Beam")
	beam.Texture = Stardust.Texture("Flow")
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 1
	beam.TextureSpeed = 1.2
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.15, 0.25), NumberSequenceKeypoint.new(0.9, 0.25), NumberSequenceKeypoint.new(1, 0.9) })
	beam.Width0, beam.Width1 = 1.4, 1.4
	beam.FaceCamera = true
	beam.Segments = 20
	beam.Attachment1 = a1
	beam.Parent = beamEnd

	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.8
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = fx

	return { Arrow = arrow, Parts = parts, Ring = ring, Beam = beam, BeamEnd = beamEnd, A1 = a1, Highlight = highlight, Color = color }
end

local function clearTarget()
	if indicator.Visual then
		local v = indicator.Visual
		v.Arrow:Destroy()
		v.Ring:Destroy()
		v.BeamEnd:Destroy()
		v.Highlight:Destroy()
		if v.A0 then
			v.A0:Destroy()
		end
	end
	indicator = {}
	edge.Visible = false
end

local function setTarget(target, color)
	clearTarget()
	if not target or not Targets[target.Kind] then
		return
	end
	indicator = { Target = target, Visual = buildIndicator(color), NextResolve = 0 }
end

local function targetPosition()
	return indicator.Part and indicator.Part.Parent and indicator.Part.Position or nil
end

local function updateIndicator(dt, t)
	local v = indicator.Visual
	if not v then
		return
	end
	if os.clock() > indicator.NextResolve then
		indicator.NextResolve = os.clock() + 0.5
		local part, model = Targets[indicator.Target.Kind](indicator.Target)
		indicator.Part, indicator.Model = part, model
		v.Highlight.Adornee = model or part
	end
	local part = indicator.Part
	local r = root()
	if not part or not part.Parent or not r then
		v.Arrow.Parent, v.Ring.Parent, v.BeamEnd.Parent = nil, nil, nil
		edge.Visible = false
		return
	end
	v.Arrow.Parent, v.Ring.Parent, v.BeamEnd.Parent = fx, fx, fx

	-- top of the target (models: their bounding box)
	local topY, groundY
	local model = indicator.Model
	if model and model:IsA("Model") then
		local cf, size = model:GetBoundingBox()
		topY, groundY = cf.Position.Y + size.Y / 2, cf.Position.Y - size.Y / 2
	else
		topY, groundY = part.Position.Y + part.Size.Y / 2, part.Position.Y + part.Size.Y / 2
	end
	local center = part.Position
	local bounce = math.abs(math.sin(t * 3.2)) * 1.4
	local arrowCF = CFrame.new(center.X, topY + 2.5 + bounce, center.Z) * CFrame.Angles(0, t * 1.5, 0)
	local parts, cfs = {}, {}
	for _, piece in ipairs(v.Parts) do
		table.insert(parts, piece.Part)
		table.insert(cfs, arrowCF * piece.Offset)
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	local pulse = 1 + 0.12 * math.sin(t * 4)
	v.Ring.Size = V3(0.12, 9 * pulse, 9 * pulse)
	v.Ring.CFrame = CFrame.new(center.X, groundY + 0.15, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	v.Highlight.FillTransparency = 0.72 + 0.12 * math.sin(t * 4)

	-- the glowing path on the ground from you to the target
	if not v.A0 or v.A0.Parent ~= r then
		if v.A0 then
			v.A0:Destroy()
		end
		v.A0 = Instance.new("Attachment")
		v.A0.Name = "TutorialPath"
		v.A0.Position = V3(0, -2.6, 0)
		v.A0.Parent = r
		v.Beam.Attachment0 = v.A0
	end
	v.BeamEnd.CFrame = CFrame.new(center.X, groundY + 0.3, center.Z)
	local dist = (V3(center.X, r.Position.Y, center.Z) - r.Position).Magnitude
	v.Beam.Enabled = dist > 9

	-- edge arrow
	local camera = workspace.CurrentCamera
	local screen, onScreen = camera:WorldToViewportPoint(center)
	local vp = camera.ViewportSize
	if onScreen and screen.X > 40 and screen.X < vp.X - 40 and screen.Y > 40 and screen.Y < vp.Y - 40 then
		edge.Visible = false
	else
		edge.Visible = true
		local rel = camera.CFrame:PointToObjectSpace(center)
		local dir = Vector2.new(rel.X, -rel.Y)
		if dir.Magnitude < 1e-3 then
			dir = Vector2.new(0, 1)
		end
		dir = dir.Unit
		local half = vp / 2 - Vector2.new(70, 70)
		local k = math.min(math.abs(half.X / (dir.X ~= 0 and dir.X or 1e-3)), math.abs(half.Y / (dir.Y ~= 0 and dir.Y or 1e-3)))
		local pos = vp / 2 + dir * k
		edge.Position = UDim2.fromOffset(pos.X, pos.Y)
		chevron.Rotation = math.deg(math.atan2(dir.Y, dir.X))
		edgeDist.Text = math.floor(dist) .. "m"
		for _, bar in ipairs(chevron:GetChildren()) do
			bar.BackgroundColor3 = v.Color
		end
		edge.Size = UDim2.fromOffset(64 + 6 * math.sin(t * 6), 64 + 6 * math.sin(t * 6))
	end
	if cardShown then
		infoLabel.Text = math.floor(dist) .. "m away"
	end
end

---------------------------------------------------------------------
-- Guides
---------------------------------------------------------------------
local guides = {} -- name -> GuideNPC
local activeGuide = nil
local guideMode = "talk" -- talk | escort | leave
local lastHop = 0

local function spotNear(distanceAhead, side)
	local r = root()
	if not r then
		return nil
	end
	local look = r.CFrame.LookVector
	local flat = V3(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or V3(0, 0, -1)
	local right = flat:Cross(V3(0, 1, 0))
	return r.Position + flat * distanceAhead + right * (side or 3) - V3(0, 2.5, 0)
end

local function ignoreList()
	local list = { fx }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in ipairs({ "PlantedPlanets", "Sprinklers", "HeldPlanets", "MutationFX", "SprinklerFX" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

local function dismiss(guide, walkAway)
	if not guide or guide.Dead then
		return
	end
	if guides[guide.Name] == guide then
		guides[guide.Name] = nil
	end
	if activeGuide == guide then
		activeGuide = nil
	end
	guide:Hush()
	if walkAway then
		guide:Play("wave", 1.2)
		task.wait(1.1)
	end
	guide:Poof()
	guide:Destroy()
end

local function summon(name)
	for other, g in pairs(guides) do
		if other ~= name then
			task.spawn(dismiss, g, false)
		end
	end
	local g = guides[name]
	if not g or g.Dead then
		g = GuideNPC.new(name, fx)
		guides[name] = g
		local spot = spotNear(7, 3) or V3(0, 10, 0)
		g:Appear(spot)
		local r = root()
		if r then
			g:LookAt(r.Position)
		end
	end
	activeGuide = g
	return g
end

-- every frame: guides walk with you, look at you, point at the target
local pointTimer = 0
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	updateIndicator(dt, t)
	local r = root()
	local ignore = nil
	for _, g in pairs(guides) do
		if not g.Dead then
			ignore = ignore or ignoreList()
			if r and g == activeGuide then
				local myPos = r.Position
				local gPos = g:Position()
				local flatDist = V3(gPos.X - myPos.X, 0, gPos.Z - myPos.Z).Magnitude
				if flatDist > 70 then
					g:Poof()
					g:Teleport(spotNear(5, 4) or myPos)
					g:Poof()
				end
				local target = targetPosition()
				local want
				if guideMode == "escort" and target and (V3(target.X, myPos.Y, target.Z) - myPos).Magnitude < 24 then
					local away = V3(myPos.X - target.X, 0, myPos.Z - target.Z)
					away = away.Magnitude > 0.1 and away.Unit or V3(1, 0, 0)
					want = target + away * 6 + away:Cross(V3(0, 1, 0)) * 3
					pointTimer -= dt
					if pointTimer < 0 and g.Action == "idle" then
						pointTimer = 5
						g:PointAt(target, 2)
					end
				elseif guideMode == "escort" then
					want = spotNear(-1.5, 4.5)
				else
					want = flatDist > 9 and spotNear(5, 3) or nil
				end
				if want and (V3(want.X, gPos.Y, want.Z) - gPos).Magnitude > 2 then
					g:WalkTo(want)
				end
				if g.Action ~= "point" then
					g:LookAt(myPos)
				end
			end
			g:Update(dt, ignore)
		end
	end
end)

-- guides hop when you jump next to them
local function hookJump(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping and activeGuide and os.clock() - lastHop > 2.5 then
				local r = root()
				if r and (activeGuide:Position() - r.Position).Magnitude < 14 and activeGuide.Action == "idle" and not activeGuide.Talking then
					lastHop = os.clock()
					activeGuide:Play("hop", 0.6)
				end
			end
		end)
	end
end
player.CharacterAdded:Connect(hookJump)
if player.Character then
	task.spawn(hookJump, player.Character)
end

local function pick(list)
	return list[math.random(1, #list)]
end
local function fill(line, values)
	return (string.gsub(line, "{(%w+)}", function(k)
		return tostring(values[k] or k)
	end))
end

local function playSound(id, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.4
	s.Parent = playerGui
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

---------------------------------------------------------------------
-- On-screen pointer: a glowing, pulsing outline + a bouncing arrow on the button you need
-- (the item in a shop, its buy button, the hotbar slot). Step field: Ui (see TutorialSteps).
---------------------------------------------------------------------
local uiPointer = { Want = nil, Target = nil, Glow = nil, Arrow = nil, Scrolled = nil }

local function clearUiGlow()
	if uiPointer.Glow then
		uiPointer.Glow:Destroy()
	end
	if uiPointer.Arrow then
		uiPointer.Arrow:Destroy()
	end
	uiPointer.Glow, uiPointer.Arrow, uiPointer.Target = nil, nil, nil
end

local function setUiPointer(want, color)
	clearUiGlow()
	uiPointer.Want = want
	uiPointer.Color = color or rgb(90, 255, 140)
	uiPointer.Scrolled = nil
end

local function openShopFrame(shopKind)
	local gui = playerGui:FindFirstChild("Shop_" .. shopKind)
	local main = gui and gui:FindFirstChild("Main")
	if main and main.Visible then
		return main
	end
	return nil
end

-- which GuiObject should glow right now (nil = nothing on screen to press yet)
local function resolveUiTarget(want)
	if not want then
		return nil
	end
	if want.Shop then
		local main = openShopFrame(want.Shop)
		local list = main and main:FindFirstChild("List", true)
		local slot = list and list:FindFirstChild(want.Item)
		if not slot then
			return nil
		end
		-- scroll the item into view once
		if uiPointer.Scrolled ~= slot and list:IsA("ScrollingFrame") then
			uiPointer.Scrolled = slot
			local y = slot.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y
			list.CanvasPosition = Vector2.new(0, math.max(0, y - 10))
		end
		local buyRow = slot:FindFirstChild("BuyRow")
		if buyRow and buyRow.Visible and buyRow:FindFirstChild("CoinBuy") then
			return buyRow.CoinBuy
		end
		return slot:FindFirstChild("CardHolder")
	elseif want.Hotbar then
		local character = player.Character
		local held = character and character:FindFirstChildOfClass("Tool")
		if held and held:GetAttribute("Kind") == want.Hotbar then
			return nil -- already holding it: now the world arrow shows where to click
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		local names = {}
		for _, tool in ipairs(backpack and backpack:GetChildren() or {}) do
			if tool:IsA("Tool") and tool:GetAttribute("Kind") == want.Hotbar then
				names[tool.Name] = true
			end
		end
		local bar = playerGui:FindFirstChild("GardenHotbar")
		bar = bar and bar:FindFirstChild("Bar")
		for _, slot in ipairs(bar and bar:GetChildren() or {}) do
			if slot:IsA("GuiButton") and slot.Visible then
				local label = slot:FindFirstChild("ItemName")
				if label and names[label.Text] then
					return slot
				end
			end
		end
	end
	return nil
end

local function buildUiGlow(target, color)
	local glow = Instance.new("Frame")
	glow.Name = "TutorialGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 10, 1, 10)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.85
	glow.ZIndex = 50
	glow.Active = false
	glow.Parent = target
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = glow
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = 5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = glow

	-- shop cards sit at the top of a scrolling list (an arrow above would be cut off), so they get
	-- a sideways arrow inside the card; everything else gets a bouncing arrow on top
	local side = target.Name == "CardHolder"
	local arrow = Instance.new("TextLabel")
	arrow.Name = "TutorialArrow"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = side and Vector2.new(1, 0.5) or Vector2.new(0.5, 1)
	arrow.Position = side and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0.5, 0, 0, -6)
	arrow.Size = UDim2.fromOffset(60, 46)
	arrow.Font = Enum.Font.FredokaOne
	arrow.Text = side and "◀" or "▼"
	arrow.TextSize = 44
	arrow.TextColor3 = color
	arrow.ZIndex = 51
	arrow.Parent = target
	local ast = Instance.new("UIStroke")
	ast.Color = rgb(20, 20, 30)
	ast.Thickness = 3
	ast.Parent = arrow
	return glow, arrow, st
end

RunService.RenderStepped:Connect(function()
	local want = uiPointer.Want
	if not want then
		return
	end
	local target = resolveUiTarget(want)
	if target ~= uiPointer.Target then
		clearUiGlow()
		if target then
			uiPointer.Target = target
			uiPointer.Glow, uiPointer.Arrow, uiPointer.Stroke = buildUiGlow(target, uiPointer.Color)
		end
	end
	if uiPointer.Glow then
		local t = os.clock()
		uiPointer.Stroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(t * 6))
		uiPointer.Glow.BackgroundTransparency = 0.8 + 0.12 * math.sin(t * 6)
		local bounce = math.abs(math.sin(t * 5)) * 12
		if uiPointer.Arrow.Text == "◀" then
			uiPointer.Arrow.Position = UDim2.new(1, -16 + bounce, 0.5, 0)
		else
			uiPointer.Arrow.Position = UDim2.new(0.5, 0, 0, -6 - bounce)
		end
	end
end)

---------------------------------------------------------------------
-- Running steps
---------------------------------------------------------------------
local runToken = 0
local stepActive = nil
local lastReaction = 0

local function cancelStep()
	runToken += 1
	stepActive = nil
	setUiPointer(nil)
	clearTarget()
	showCard(false)
end

local function runStep(step)
	runToken += 1
	local my = runToken
	local function alive()
		return runToken == my and not progress.Skipped
	end
	stepActive = step
	local guide = summon(step.Guide)
	guideMode = "talk"

	local finished = false
	local unhook = {}
	if step.Event then
		table.insert(unhook, on(step.Event, function()
			finished = true
		end))
		if step.AlsoEvent then
			table.insert(unhook, on(step.AlsoEvent, function()
				finished = true
			end))
		end
		setTarget(step.Target, guide.Color)
		setUiPointer(step.Ui, guide.Color)
	end
	setCard(step, guide.Color, "")
	if not step.Goal then
		goalLabel.Text = "Chat with " .. step.Guide .. "!"
	end
	showCard(true)
	local function cleanup()
		for _, fn in ipairs(unhook) do
			fn()
		end
		if stepActive == step or stepActive == nil then
			setUiPointer(nil)
		end
	end

	task.wait(0.6) -- let it pop in first
	for i, line in ipairs(step.Intro or {}) do
		if not alive() or finished then
			break
		end
		if i == #step.Intro and step.Target then
			task.delay(0.3, function()
				local p = targetPosition()
				if p and guide == activeGuide then
					guide:PointAt(p, 2.6)
				end
			end)
		end
		guide:Say(line)
	end
	if not alive() then
		cleanup()
		return false
	end
	guide:Hush()

	if not step.Event then
		markDone(step.Id)
		stepActive = nil
		cleanup()
		return true
	end

	guideMode = "escort"
	local lastHint = os.clock()
	local hintIndex = 1
	local shopWasOpen = false
	local lastUiTarget = nil
	while alive() and not finished do
		task.wait(0.2)
		-- the player opened the shop we're teaching: say what to press (the button is glowing)
		if step.Ui and step.Ui.Shop and step.ShopLine then
			local open = openShopFrame(step.Ui.Shop) ~= nil
			if open and not shopWasOpen then
				lastHint = os.clock()
				task.spawn(function()
					guide:Play("point", 1.5)
					if guide:Say(step.ShopLine, 5) and stepActive == step then
						guide:Hush()
					end
				end)
			end
			shopWasOpen = open
		end
		-- a hotbar slot just lit up: tell them to press it
		if step.Ui and step.Ui.Hotbar and uiPointer.Target ~= lastUiTarget then
			lastUiTarget = uiPointer.Target
			if lastUiTarget then
				lastHint = os.clock()
				task.spawn(function()
					if guide:Say("Click the glowing one down there!", 3) and stepActive == step then
						guide:Hush()
					end
				end)
			end
		end
		if step.SkipIf and Checks[step.SkipIf] and Checks[step.SkipIf]() and step.SkipIf ~= "noPlanet" then
			finished = true
		end
		if os.clock() - lastHint > HINT_AFTER and step.Hint then
			lastHint = os.clock()
			local p = targetPosition()
			if p then
				guide:PointAt(p, 2.6)
			else
				guide:Play("think", 2)
			end
			task.spawn(function()
				if guide:Say(step.Hint[hintIndex]) and stepActive == step then
					guide:Hush()
				end
			end)
			hintIndex = hintIndex % #step.Hint + 1
		end
	end
	cleanup()
	if not alive() then
		return false
	end

	-- success!
	clearTarget()
	cardDone()
	markDone(step.Id)
	playSound("rbxasset://sounds/electronicpingshort.wav", 0.5)
	guideMode = "talk"
	guide:Play("cheer", 1.8)
	guide:Confetti()
	guide:Say((step.Done and step.Done[1]) or pick((Steps.Guides[step.Guide] or {}).Cheer or { "Nice!" }))
	guide:Hush()
	stepActive = nil
	return true
end

-- a guide pops in, says one line, and (if nothing else is going on) leaves again
local function react(guideName, line, action, force)
	if progress.Skipped then
		return
	end
	if not force and os.clock() - lastReaction < REACTION_GAP then
		return
	end
	lastReaction = os.clock()
	if stepActive and activeGuide then
		local g = activeGuide
		g:Play(action or "surprised", 1.5)
		task.spawn(function()
			if g:Say(line) and stepActive and g == activeGuide then
				g:Hush()
			end
		end)
		return
	end
	task.spawn(function()
		local g = summon(guideName)
		guideMode = "talk"
		task.wait(0.4)
		g:Play(action or "cheer", 1.6)
		if action == "cheer" then
			g:Confetti()
		end
		g:Say(line)
		task.wait(0.6)
		if not stepActive and activeGuide == g then
			dismiss(g, true)
		end
	end)
end

---------------------------------------------------------------------
-- Reactions to what you do
---------------------------------------------------------------------
on("error", function(text)
	if progress.Skipped or not activeGuide then
		return
	end
	local lower = string.lower(text)
	for _, m in ipairs(Steps.Mistakes) do
		for _, word in ipairs(m.Words) do
			if string.find(lower, word, 1, true) then
				react(m.Guide, pick(m.Lines), m.Action, true)
				return
			end
		end
	end
	react(activeGuide.Name, pick((Steps.Guides[activeGuide.Name] or {}).Oops or { "Oops!" }), "shrug", true)
end)

on("claim", function()
	if activeGuide and stepActive then
		react(activeGuide.Name, "This base is YOURS now! Welcome home!", "cheer", true)
	end
end)

on("harvest", function(_, _, tierName)
	if type(tierName) == "string" and tierName ~= "" and not stepActive then
		react("Cosmo", fill(pick(Steps.Reactions.BigHarvest), { tier = string.upper(tierName) }), "surprised")
	end
end)

on("got_item", function(kind, id, tool)
	if kind == "Seed" or kind == "Planet" then
		local planet = PlanetCatalog.Get(id)
		local info = planet and PlanetCatalog.Rarities[planet.Rarity]
		if info and (info.Order or 1) >= 3 and not isDone("rarity:" .. planet.Rarity) then
			markDone("rarity:" .. planet.Rarity)
			react("Cosmo", fill(pick(Steps.Reactions.FirstRarity), { rarity = string.upper(planet.Rarity) }), "cheer")
		end
	elseif not KNOWN_KINDS[kind] and not isDone("kind:" .. tostring(kind)) then
		markDone("kind:" .. tostring(kind))
		react("Cosmo", fill(pick(Steps.Reactions.NewItem), { item = tool and tool.Name or kind }), "surprised")
	end
end)

on("mutation", function(mutId)
	if type(mutId) == "string" and not isDone("mut:" .. mutId) then
		markDone("mut:" .. mutId)
		local m = MutationCatalog.Get(mutId)
		react("Cosmo", fill(pick(Steps.Reactions.FirstMutation), { mutation = string.upper(m and m.Name or mutId) }), "surprised")
	end
end)

-- weather + events from the admin panel / LiveOps
task.spawn(function()
	local live = ReplicatedStorage:WaitForChild("LiveOps", 60)
	if not live then
		return
	end
	live:GetAttributeChangedSignal("Weather"):Connect(function()
		local w = live:GetAttribute("Weather")
		if w and w ~= "clear" and not isDone("weather:" .. w) then
			markDone("weather:" .. w)
			local okConfig, WeatherConfig = pcall(require, ReplicatedStorage:FindFirstChild("WeatherConfig"))
			local info = okConfig and WeatherConfig and WeatherConfig.Get(w)
			react("Cosmo", fill(pick(Steps.Reactions.Weather), { weather = string.upper(info and info.Name or w) }), "surprised")
		end
	end)
	live:GetAttributeChangedSignal("Event"):Connect(function()
		local e = live:GetAttribute("Event")
		if e and e ~= "" and not isDone("event:" .. e) then
			markDone("event:" .. e)
			local m = MutationCatalog.Get(e)
			react("Cosmo", fill(pick(Steps.Reactions.Event), { mutation = string.upper(m and m.Name or e) }), "cheer")
		end
	end)
end)

---------------------------------------------------------------------
-- Discoveries: new shops + anything tagged TutorialHint
---------------------------------------------------------------------
local coveredShops = {}
for _, list in ipairs({ Steps.Core, Steps.Side }) do
	for _, step in ipairs(list) do
		if step.Target and step.Target.Kind == "npc" then
			coveredShops[step.Target.Name] = true
		end
		if step.Trigger and (step.Trigger.Near or step.Trigger.OrNear) then
			coveredShops[step.Trigger.Near or step.Trigger.OrNear] = true
		end
	end
end

local function prettyName(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local name = humanoid and humanoid.DisplayName ~= "" and humanoid.DisplayName or model.Name
	return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

local function checkDiscoveries()
	local r = root()
	if not r then
		return
	end
	local shops = workspace:FindFirstChild("SHOPS")
	if shops then
		for _, model in ipairs(shops:GetDescendants()) do
			if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and not coveredShops[model.Name] and not isDone("shop:" .. model.Name) then
				local part = mainPart(model)
				if part and (part.Position - r.Position).Magnitude < NEAR_DISTANCE then
					markDone("shop:" .. model.Name)
					react("Zib", fill(pick(Steps.Reactions.NewShop), { shop = prettyName(model) }), "point")
					if activeGuide then
						activeGuide:PointAt(part.Position, 2.5)
					end
					return
				end
			end
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged("TutorialHint")) do
		local text = inst:GetAttribute("HintText")
		local id = "poi:" .. (inst:GetAttribute("HintId") or inst:GetFullName())
		if type(text) == "string" and #id <= 60 and not isDone(id) then
			local part = mainPart(inst)
			if part and (part.Position - r.Position).Magnitude < (inst:GetAttribute("HintDistance") or NEAR_DISTANCE) then
				markDone(id)
				react(inst:GetAttribute("HintGuide") or "Cosmo", text, "point")
				if activeGuide then
					activeGuide:PointAt(part.Position, 2.5)
				end
				return
			end
		end
	end
end

---------------------------------------------------------------------
-- The tutorial itself
---------------------------------------------------------------------
local coreRunning = false

local function coreDone()
	for _, step in ipairs(Steps.Core) do
		if not isDone(step.Id) then
			return false
		end
	end
	return true
end

local function runCore()
	if coreRunning then
		return
	end
	coreRunning = true
	for _, step in ipairs(Steps.Core) do
		if progress.Skipped then
			break
		end
		if not isDone(step.Id) then
			if step.SkipIf and Checks[step.SkipIf] and Checks[step.SkipIf]() then
				markDone(step.Id)
			elseif not runStep(step) then
				break
			end
		end
	end
	if not stepActive then
		showCard(false)
	end
	if coreDone() and activeGuide and not stepActive then
		local g = activeGuide
		g:Play("dance", 2.4)
		g:Confetti()
		task.wait(2.4)
		if not stepActive and activeGuide == g then
			dismiss(g, true)
		end
	end
	coreRunning = false
end

local function sideAfterOk(step)
	return not step.After or isDone(step.After)
end

local SIDE_GAP = 40 -- seconds between side lessons, so players aren't flooded
local nextSide = 0
local function sideLoop()
	while true do
		task.wait(1.5)
		if not progress.Skipped and not stepActive and not coreRunning and (coreDone() or progress.Experienced) then
			for _, step in ipairs(Steps.Side) do
				if not isDone(step.Id) and sideAfterOk(step) and step.SkipIf and Checks[step.SkipIf] and Checks[step.SkipIf]() then
					markDone(step.Id) -- they already know this one
				end
			end
			for _, step in ipairs(Steps.Side) do
				if os.clock() < nextSide then
					break
				end
				if not isDone(step.Id) and sideAfterOk(step) and triggerMet(step.Trigger) then
					local ok = runStep(step)
					nextSide = os.clock() + SIDE_GAP
					if not stepActive then
						showCard(false)
					end
					if ok and activeGuide and not stepActive then
						task.wait(0.5)
						if not stepActive then
							dismiss(activeGuide, true)
						end
					end
					break
				end
			end
			if not stepActive then
				checkDiscoveries()
			end
		end
	end
end

local function skipAll()
	progress.Skipped = true
	eventRemote:FireServer("skip")
	cancelStep()
	local g = activeGuide
	if g then
		task.spawn(function()
			g:Play("shrug", 1.2)
			g:Say(Steps.Reactions.Skip[1], 1.6)
			g:Say(Steps.Reactions.Skip[2], 2)
			dismiss(g, true)
		end)
	end
end
skipButton.MouseButton1Click:Connect(skipAll)

local function restart()
	confirm.Visible = false
	progress.Skipped = false
	progress.Experienced = false
	for _, list in ipairs({ Steps.Core, Steps.Side }) do
		for _, step in ipairs(list) do
			progress.Done[step.Id] = nil
		end
	end
	eventRemote:FireServer("restart")
	cancelStep()
	coreRunning = false
	task.spawn(runCore)
end
yesButton.MouseButton1Click:Connect(restart)
noButton.MouseButton1Click:Connect(function()
	confirm.Visible = false
end)

local function openHelp()
	if stepActive and activeGuide then
		-- repeat the hint right now
		local g = activeGuide
		local p = targetPosition()
		if p then
			g:PointAt(p, 2.6)
		end
		local lines = stepActive.Hint or stepActive.Intro or {}
		if lines[1] then
			task.spawn(function()
				if g:Say(lines[1]) and stepActive and g == activeGuide then
					g:Hush()
				end
			end)
		end
	else
		confirm.Visible = not confirm.Visible
	end
end
helpButton.MouseButton1Click:Connect(openHelp)

-- the Replay Tutorial button lives in Settings now (GardenHotbar fires this); the ? button is hidden
local openHelpEvent = Instance.new("BindableEvent")
openHelpEvent.Name = "OpenHelp"
openHelpEvent.Parent = gui
openHelpEvent.Event:Connect(openHelp)
helpButton.Visible = false

---------------------------------------------------------------------
-- Start
---------------------------------------------------------------------
task.spawn(function()
	local state
	for _ = 1, 5 do
		local ok, result = pcall(function()
			return stateRemote:InvokeServer()
		end)
		if ok and type(result) == "table" then
			state = result
			break
		end
		task.wait(2)
	end
	if not state then
		warn("[TutorialClient] couldn't load tutorial progress")
		return
	end
	progress.Done = type(state.Done) == "table" and state.Done or {}
	progress.Skipped = state.Skipped == true
	progress.Experienced = state.Experienced == true

	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(4) -- let the loading screen finish

	if progress.Experienced and not progress.Skipped and not isDone("react:welcomeback") then
		markDone("react:welcomeback")
		local g = summon("Cosmo")
		task.wait(0.5)
		g:SayLines(Steps.Reactions.WelcomeBack)
		dismiss(g, true)
	elseif not progress.Skipped and not coreDone() then
		runCore()
	end
	task.spawn(sideLoop)
end)

print("[TutorialClient] ready")
