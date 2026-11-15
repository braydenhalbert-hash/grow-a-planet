--[[
	LoadingScreen  (LocalScript)
	Put it in:  ReplicatedFirst   (name it exactly: LoadingScreen)

	* Spinning black hole (rings + orbiting stars) with "GROW A PLANET" next to it
	* Loading bar that follows the real loading, with rotating game tips
	* When it's done the bar fades away and the black hole sucks the whole background into itself
	* Needs no uploaded images
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
local TITLE_LINE_1 = "GROW A"
local TITLE_LINE_2 = "PLANET"
local TAGLINE = "Plant. Grow. Discover."
local MIN_SECONDS = 5 -- the screen stays at least this long so people can read a tip or two
local MAX_SECONDS = 30 -- never trap anyone longer than this
local TIP_SECONDS = 3.4 -- how long each tip stays
local SUCK_SECONDS = 2.8 -- how long the black hole takes to swallow the background

local TIPS = {
	"Walk up to an empty base and plant a seed to claim it as yours.",
	"Mutations can stack on one planet: Meteor, Frozen, Nebula, Solar Flare and Supernova all add to your profit.",
	"The best planets and rarest packs are usually out of stock. Check the shop after every restock!",
	"Use the SEEDS, GARDEN and SELL buttons at the top of the screen to teleport around.",
	"Press 1 to 0 on your keyboard to hold items from your hotbar.",
	"Heavier planets sell for more. Sell them to the Planet Buyer!",
	"Open black hole packs for a chance at Epic, Legendary and Mythic planets.",
	"Harvest planets quickly one after another to keep your harvest streak going.",
}

local PURPLE = Color3.fromRGB(150, 70, 255)
local VIOLET = Color3.fromRGB(95, 40, 190)
local GOLD = Color3.fromRGB(255, 190, 80)
local ORANGE = Color3.fromRGB(255, 120, 50)
local DEEP = Color3.fromRGB(9, 5, 22)

---------------------------------------------------------------------
-- start: hide Roblox's own loading screen, build our own
---------------------------------------------------------------------
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function circle(parent, props)
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	return frame
end

local gui = make("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 100000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local root = make("Frame", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, gui)

---------------------------------------------------------------------
-- BACKGROUND: one big dark circle (bigger than the screen) full of stars.
-- At the end it shrinks + spins into the black hole, so everything in it gets sucked in.
---------------------------------------------------------------------
local bg = circle(root, {
	Name = "Background",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(4000, 4000), -- fixed up in layout()
	BackgroundColor3 = DEEP,
	ZIndex = 1,
})

local blobColors = {
	Color3.fromRGB(120, 50, 230),
	Color3.fromRGB(40, 90, 220),
	Color3.fromRGB(220, 60, 170),
	Color3.fromRGB(90, 40, 200),
	Color3.fromRGB(40, 150, 220),
	Color3.fromRGB(170, 60, 230),
}
local rng = Random.new(12)
for i = 1, #blobColors do
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(0.05, 0.3)
	local size = rng:NextNumber(0.3, 0.55)
	circle(bg, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.cos(angle) * dist, 0.5 + math.sin(angle) * dist),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = blobColors[i],
		BackgroundTransparency = rng:NextNumber(0.9, 0.95),
	})
end

for _ = 1, 260 do
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = math.sqrt(rng:NextNumber()) * 0.49
	local size = rng:NextNumber(0.0009, 0.0028)
	local tint = rng:NextNumber()
	circle(bg, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.cos(angle) * dist, 0.5 + math.sin(angle) * dist),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1):Lerp(tint < 0.5 and Color3.fromRGB(190, 170, 255) or Color3.fromRGB(255, 220, 170), 0.6),
		BackgroundTransparency = rng:NextNumber(0.05, 0.55),
	})
end

---------------------------------------------------------------------
-- BLACK HOLE
---------------------------------------------------------------------
local holeRoot = make("Frame", {
	Name = "BlackHole",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(300, 300),
	ZIndex = 5,
}, root)
local holeScale = make("UIScale", { Scale = 1 }, holeRoot)

local function centered(size)
	return {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
	}
end

local function glow(size, transparency)
	local props = centered(size)
	props.BackgroundColor3 = PURPLE
	props.BackgroundTransparency = transparency
	props.ZIndex = 5
	return circle(holeRoot, props)
end
glow(1.9, 0.94)
glow(1.55, 0.9)
glow(1.25, 0.84)

-- spinning rings: a stroke with a rotating gradient looks like a spinning glow
local rings = {}
local function addRing(size, colorA, colorB, thicknessFactor, speed)
	local props = centered(size)
	props.BackgroundTransparency = 1
	props.ZIndex = 6
	local frame = circle(holeRoot, props)
	local stroke = make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 6, Transparency = 0 }, frame)
	local gradient = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colorA),
			ColorSequenceKeypoint.new(0.5, colorB),
			ColorSequenceKeypoint.new(1, colorA),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.75),
			NumberSequenceKeypoint.new(0.55, 0.95),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, stroke)
	table.insert(rings, { Stroke = stroke, Gradient = gradient, Factor = thicknessFactor, Speed = speed })
end
addRing(1.0, PURPLE, GOLD, 0.03, 70)
addRing(0.82, GOLD, ORANGE, 0.035, -120)
addRing(0.66, Color3.fromRGB(190, 130, 255), PURPLE, 0.026, 170)

-- the dark centre
do
	local props = centered(0.5)
	props.BackgroundColor3 = Color3.new(0, 0, 0)
	props.ZIndex = 8
	local core = circle(holeRoot, props)
	local edge = make("UIStroke", { Color = GOLD, Thickness = 3, Transparency = 0.15 }, core)
	table.insert(rings, { Stroke = edge, Factor = 0.012, Speed = 0 })
	local inner = centered(0.36)
	inner.BackgroundColor3 = Color3.new(0, 0, 0)
	inner.ZIndex = 9
	local innerFrame = circle(holeRoot, inner)
	make("UIStroke", { Color = VIOLET, Thickness = 2, Transparency = 0.4 }, innerFrame)
end

-- stars circling into the hole
local PARTICLES = 80
local particles = {}
for i = 1, PARTICLES do
	local size = rng:NextNumber(0.018, 0.038)
	local dot = circle(holeRoot, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 7,
	})
	particles[i] = {
		Dot = dot,
		Phase = rng:NextNumber(),
		Angle = rng:NextNumber(0, math.pi * 2),
		Speed = rng:NextNumber(0.07, 0.14),
		Size = size,
	}
end

---------------------------------------------------------------------
-- TEXT + BAR  (plain Frame, NOT a CanvasGroup: a CanvasGroup turns everything into one blurry picture)
---------------------------------------------------------------------
local ui = make("Frame", {
	Name = "UI",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, root)

local title = make("TextLabel", {
	Name = "Title",
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = TITLE_LINE_1 .. "\n" .. TITLE_LINE_2,
	TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	TextSize = 60,
	LineHeight = 0.92,
}, ui)
make("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(215, 190, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 110)),
	}),
}, title)
make("UIStroke", { Color = Color3.fromRGB(40, 12, 90), Thickness = 4, Transparency = 0.05 }, title)

local tagline = make("TextLabel", {
	Name = "Tagline",
	AnchorPoint = Vector2.new(0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = TAGLINE,
	TextColor3 = Color3.fromRGB(200, 170, 255),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 20,
}, ui)

local tipLabel = make("TextLabel", {
	Name = "Tip",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Color3.fromRGB(235, 225, 255),
	TextWrapped = true,
	TextSize = 20,
	TextTransparency = 1,
}, ui)
local tipStroke = make("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.2, Transparency = 1 }, tipLabel)

local track = make("Frame", {
	Name = "BarTrack",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(22, 12, 48),
	BorderSizePixel = 0,
}, ui)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, track)
make("UIStroke", { Color = Color3.fromRGB(120, 70, 220), Thickness = 3 }, track)

local fill = make("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, track)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PURPLE),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(220, 110, 200)),
		ColorSequenceKeypoint.new(1, GOLD),
	}),
}, fill)

local barLabel = make("TextLabel", {
	Name = "Percent",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Loading... 0%",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 20,
	ZIndex = 3,
}, track)
make("UIStroke", { Color = Color3.fromRGB(25, 8, 55), Thickness = 1.2, Transparency = 0.1 }, barLabel)

---------------------------------------------------------------------
-- LAYOUT (wide screens: hole left, title right. Narrow/phone: stacked)
---------------------------------------------------------------------
local holeCenter = Vector2.new(0, 0)

local function px(x) -- whole pixel
	return math.floor(x + 0.5)
end
local function even(x) -- even number, so centred things never land on half a pixel
	return 2 * math.floor(x / 2 + 0.5)
end

local function layout()
	local width, height = root.AbsoluteSize.X, root.AbsoluteSize.Y
	if width < 10 or height < 10 then
		return
	end
	local narrow = width < 720 or width < height * 1.1
	local unit = math.clamp(math.min(width / 1.9, height) / 560, 0.7, 1.5)

	bg.Size = UDim2.fromOffset(math.sqrt(width * width + height * height) + 40, math.sqrt(width * width + height * height) + 40)

	local hole = math.clamp(math.min(width * (narrow and 0.52 or 0.26), height * 0.4), 120, 360)
	holeRoot.Size = UDim2.fromOffset(hole, hole)
	for _, ring in ipairs(rings) do
		ring.Stroke.Thickness = math.max(2, hole * ring.Factor)
	end

	local titleSize = math.min(100, math.floor(hole * 0.3)) -- the engine's biggest text size is 100
	title.TextSize = titleSize
	tagline.TextSize = math.clamp(math.floor(hole * 0.08), 16, 30)

	if narrow then
		holeCenter = Vector2.new(width / 2, height * 0.3)
		title.AnchorPoint = Vector2.new(0.5, 0)
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.Size = UDim2.fromOffset(even(width * 0.9), even(titleSize * 2))
		title.Position = UDim2.fromOffset(px(width / 2), px(holeCenter.Y + hole * 0.62))
		tagline.AnchorPoint = Vector2.new(0.5, 0)
		tagline.TextXAlignment = Enum.TextXAlignment.Center
		tagline.Size = UDim2.fromOffset(even(width * 0.9), 32)
		tagline.Position = UDim2.fromOffset(px(width / 2), px(holeCenter.Y + hole * 0.62 + titleSize * 2 + 4))
	else
		local titleWidth = hole * 1.7
		local gap = hole * 0.28
		local startX = (width - (hole + gap + titleWidth)) / 2
		holeCenter = Vector2.new(startX + hole / 2, height * 0.4)
		title.AnchorPoint = Vector2.new(0, 0.5)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Size = UDim2.fromOffset(even(titleWidth), even(titleSize * 2))
		title.Position = UDim2.fromOffset(px(startX + hole + gap), px(holeCenter.Y - hole * 0.06))
		tagline.AnchorPoint = Vector2.new(0, 0)
		tagline.TextXAlignment = Enum.TextXAlignment.Left
		tagline.Size = UDim2.fromOffset(even(titleWidth), 32)
		tagline.Position = UDim2.fromOffset(px(startX + hole + gap + 4), px(holeCenter.Y - hole * 0.06 + titleSize + 6))
	end
	holeRoot.Position = UDim2.fromOffset(holeCenter.X, holeCenter.Y)

	-- loading bar: taller so the percentage text is crisp, then the tips underneath it
	local barWidth = even(math.clamp(width * 0.6, 240, 700))
	local barHeight = even(math.clamp(34 * unit, 30, 48))
	local barY = px(height * (narrow and 0.84 or 0.8))
	track.Size = UDim2.fromOffset(barWidth, barHeight)
	track.Position = UDim2.fromOffset(px(width / 2), barY)
	barLabel.TextSize = math.floor(barHeight * 0.58)
	tipLabel.Size = UDim2.fromOffset(barWidth, even(70 * unit))
	tipLabel.Position = UDim2.fromOffset(px(width / 2), barY + barHeight / 2 + 14)
	tipLabel.TextSize = math.clamp(math.floor(21 * unit), 17, 30)
end
layout()
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

---------------------------------------------------------------------
-- TIPS (fade out, swap, fade in)
---------------------------------------------------------------------
local tipsRunning = true
task.spawn(function()
	local order = {}
	for i = 1, #TIPS do
		order[i] = i
	end
	for i = #order, 2, -1 do -- shuffle
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local index = 0
	while tipsRunning and gui.Parent do
		index = index % #order + 1
		tipLabel.Text = "TIP:  " .. TIPS[order[index]]
		TweenService:Create(tipLabel, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
		TweenService:Create(tipStroke, TweenInfo.new(0.35), { Transparency = 0.35 }):Play()
		task.wait(TIP_SECONDS)
		if not tipsRunning then
			break
		end
		TweenService:Create(tipLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(tipStroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		task.wait(0.35)
	end
end)

---------------------------------------------------------------------
-- REAL LOADING PROGRESS
---------------------------------------------------------------------
local target = 0 -- 0..1, set by the loading steps below
local loadingDone = false
local startTime = os.clock()

task.spawn(function()
	-- 1) the game itself
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	target = 0.25

	-- 2) pre-load the pictures, meshes and sounds that are already in the world
	local assets = {}
	local function collect(container)
		for _, item in ipairs(container:GetDescendants()) do
			if
				item:IsA("MeshPart")
				or item:IsA("Decal")
				or item:IsA("Texture")
				or item:IsA("SpecialMesh")
				or item:IsA("Sound")
				or item:IsA("ImageLabel")
				or item:IsA("ImageButton")
			then
				table.insert(assets, item)
				if #assets >= 600 then
					return
				end
			end
		end
	end
	collect(workspace)
	collect(ReplicatedStorage)
	collect(playerGui)
	if #assets > 0 then
		local done = 0
		pcall(function()
			ContentProvider:PreloadAsync(assets, function()
				done += 1
				target = math.max(target, 0.25 + 0.55 * math.min(done / #assets, 1))
			end)
		end)
	end
	target = math.max(target, 0.8)

	-- 3) the things the game needs to feel ready
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	target = 0.88
	ReplicatedStorage:WaitForChild("PlanetRemotes", 8)
	target = 0.95
	if player.Character then
		player.Character:WaitForChild("HumanoidRootPart", 5)
	end
	target = 1
	loadingDone = true
end)

---------------------------------------------------------------------
-- FADE HELPER: fades every label/frame/outline one by one (keeps text sharp the whole time)
---------------------------------------------------------------------
local function fadeOut(container, seconds)
	local info = TweenInfo.new(seconds)
	for _, item in ipairs(container:GetDescendants()) do
		local goal
		if item:IsA("TextLabel") then
			goal = { TextTransparency = 1 }
		elseif item:IsA("Frame") and item.BackgroundTransparency < 1 then
			goal = { BackgroundTransparency = 1 }
		elseif item:IsA("UIStroke") then
			goal = { Transparency = 1 }
		end
		if goal then
			TweenService:Create(item, info, goal):Play()
		end
	end
end

---------------------------------------------------------------------
-- ANIMATION LOOP
---------------------------------------------------------------------
local clock = 0
local boost = 1 -- spin speed multiplier (goes up while the background is being sucked in)
local boostTarget = 1
local shown = 0
local finishing = false
local purpleColor, orangeColor = PURPLE, ORANGE

local connection
connection = RunService.RenderStepped:Connect(function(dt)
	boost += (boostTarget - boost) * math.min(1, dt * 3)
	clock += dt * boost

	-- rings spin
	for _, ring in ipairs(rings) do
		if ring.Gradient then
			ring.Gradient.Rotation = (clock * ring.Speed) % 360
		end
	end

	-- stars spiral inward, then start again at the outside
	for _, p in ipairs(particles) do
		local phase = (p.Phase + clock * p.Speed) % 1
		local radius = 0.78 - 0.54 * phase ^ 1.5
		local angle = p.Angle + phase * 5 + clock * 0.35
		p.Dot.Position = UDim2.fromScale(0.5 + math.cos(angle) * radius, 0.5 + math.sin(angle) * radius)
		local fade = math.min(phase / 0.12, 1) * math.min((1 - phase) / 0.1, 1)
		p.Dot.BackgroundTransparency = 1 - fade * 0.95
		p.Dot.BackgroundColor3 = purpleColor:Lerp(orangeColor, phase)
		local scale = p.Size * (1.2 - phase * 0.7)
		p.Dot.Size = UDim2.fromScale(scale, scale)
	end

	-- bar follows the real progress but never finishes before MIN_SECONDS
	local elapsed = os.clock() - startTime
	if elapsed > MAX_SECONDS then
		target = 1
		loadingDone = true
	end
	local allowed = math.clamp(elapsed / MIN_SECONDS, 0, 1)
	local goal = math.min(target, allowed)
	shown += (goal - shown) * math.min(1, dt * 4)
	if shown > 0.999 then
		shown = 1
	end
	fill.Size = UDim2.fromScale(shown, 1)
	if not finishing then
		barLabel.Text = ("Loading... %d%%"):format(math.floor(shown * 100))
	end

	if loadingDone and shown >= 1 and not finishing then
		finishing = true
		task.spawn(function()
			barLabel.Text = "Ready!"
			task.wait(0.5)
			tipsRunning = false

			-- text and bar fade out
			fadeOut(ui, 0.5)
			task.wait(0.5)

			-- the black hole speeds up and swallows the background
			boostTarget = 5
			TweenService:Create(holeScale, TweenInfo.new(SUCK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1.3 }):Play()
			local suck = TweenService:Create(bg, TweenInfo.new(SUCK_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
				Size = UDim2.fromOffset(0, 0),
				Position = UDim2.fromOffset(holeCenter.X, holeCenter.Y),
				Rotation = 900,
			})
			suck:Play()
			suck.Completed:Wait()
			bg.Visible = false

			-- the black hole itself shrinks away, leaving the game
			local vanish = TweenService:Create(holeScale, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
			vanish:Play()
			vanish.Completed:Wait()
			connection:Disconnect()
			gui:Destroy()
		end)
	end
end)