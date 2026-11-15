--[[
	GardenHotbar  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	The custom hotbar and backpack (Roblox's own backpack is turned off):
	  * Bottom: space-themed hotbar with a 3D picture of each item, its count and its name.
	    Tap a slot (or press 1-9 / 0) to hold it, again to put it away.
	    Phones get 6 bigger-to-tap slots that sit between the joystick and the jump button.
	  * The BACKPACK button at the end of the hotbar (or the ` key) opens the backpack:
	    every item you own, sorted by type and rarity, with search and filter tabs
	    (All / Seeds / Planets / Gear / Packs). Tap an item to hold it.
	  * The gear button opens Settings (music on/off). Top-left on computers, left side on phones.

	Needs ReplicatedStorage > ItemIcons and ScreenFit (ModuleScripts).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local ItemIcons = require(ReplicatedStorage:WaitForChild("ItemIcons"))
local ScreenFit = require(ReplicatedStorage:WaitForChild("ScreenFit"))

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local SLOTS_COMPUTER = 10 -- keys 1-9 and 0
local SLOTS_PHONE = 6
local SLOT_SIZE = 74
local SLOT_GAP = 8
local FONT = Enum.Font.FredokaOne

local COLORS = {
	Slot = Color3.fromRGB(16, 16, 44),
	SlotTop = Color3.fromRGB(46, 40, 110),
	SlotBottom = Color3.fromRGB(12, 12, 34),
	PanelTop = Color3.fromRGB(22, 22, 66),
	PanelBottom = Color3.fromRGB(6, 8, 26),
	HeaderTop = Color3.fromRGB(96, 74, 224),
	HeaderBottom = Color3.fromRGB(40, 28, 130),
	GlowA = Color3.fromRGB(90, 190, 255),
	GlowB = Color3.fromRGB(170, 90, 255),
	Backpack = Color3.fromRGB(128, 52, 230),
	Text = Color3.new(1, 1, 1),
	Dim = Color3.fromRGB(175, 170, 215),
	Close = Color3.fromRGB(205, 45, 70),
}

-- the backpack's filter tabs, in order
local CATEGORIES = {
	{ Id = "All", Text = "ALL" },
	{ Id = "Seed", Text = "SEEDS" },
	{ Id = "Planet", Text = "PLANETS" },
	{ Id = "Gear", Text = "GEAR" },
	{ Id = "Pack", Text = "PACKS" },
}
local KIND_ORDER = { Seed = 1, Gear = 2, Pack = 3, Planet = 4 }

---------------------------------------------------------------------
-- Turn off Roblox's own backpack/hotbar (this one replaces it)
---------------------------------------------------------------------
task.spawn(function()
	for _ = 1, 20 do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = radius == "round" and UDim.new(1, 0) or UDim.new(0, radius) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function gradient(parent, top, bottom)
	return make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, parent)
end

local function text(parent, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = COLORS.Text,
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = Color3.fromRGB(10, 6, 30),
	}, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	return l
end

local function rarityColor(tool)
	return PlanetCatalog.RarityColor(tool:GetAttribute("Rarity") or "Common")
end

local function rarityOrder(tool)
	local info = PlanetCatalog.Rarities[tool:GetAttribute("Rarity") or ""]
	return info and info.Order or 0
end

local function kindOf(tool)
	return tool:GetAttribute("Kind") or "Other"
end

local function commas(n)
	local s = tostring(math.floor(n))
	repeat
		local changed
		s, changed = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until changed == 0
	return s
end

-- the small line under an item's name: "x12" for stacks, "1.24 kg" for harvested planets
local function detailOf(tool)
	local weight = tool:GetAttribute("Weight")
	if weight then
		return string.format("%.2f kg", weight)
	end
	local count = tool:GetAttribute("Count")
	if count and count > 1 then
		return "x" .. commas(count)
	end
	return ""
end

-- press feedback for buttons (they shrink a little while held)
local function pressEffect(button)
	local scale = make("UIScale", { Name = "PressScale" }, button)
	local function to(value)
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = value }):Play()
	end
	button.MouseButton1Down:Connect(function()
		to(0.92)
	end)
	button.MouseButton1Up:Connect(function()
		to(1)
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
	return scale
end

---------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------
local old = playerGui:FindFirstChild("GardenHotbar")
if old then
	old:Destroy()
end

local gui = make("ScreenGui", {
	Name = "GardenHotbar",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- the backpack window goes on its own screen so it sits above the shop windows
local panelGui = make("ScreenGui", {
	Name = "BackpackScreen",
	ResetOnSpawn = false,
	DisplayOrder = 55,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

---------------------------------------------------------------------
-- Items
---------------------------------------------------------------------
local order = {} -- tools in the order you got them (the hotbar shows the first few)
local inOrder = {}

local function allTools()
	local found = {}
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") then
					found[child] = true
				end
			end
		end
	end
	return found
end

local function heldTool()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool")
end

local function toggleTool(tool)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not tool or not tool.Parent then
		return
	end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

-- the 3D picture inside a slot or card; falls back to a coloured ball
local function fillIcon(holder, tool)
	for _, child in ipairs(holder:GetChildren()) do
		child:Destroy()
	end
	if not tool then
		return
	end
	local icon = ItemIcons.Make(holder, tool)
	if not icon then
		local ball = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			BackgroundColor3 = ItemIcons.Color(tool),
		}, holder)
		corner(ball, "round")
		make("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(90, 90, 110)),
			Rotation = 60,
		}, ball)
	end
	-- seeds get a little SEED tag so they don't look like grown planets
	if kindOf(tool) == "Seed" then
		local tag = text(holder, {
			Name = "SeedTag",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(0.7, 0, 0, 13),
			BackgroundTransparency = 0.1,
			BackgroundColor3 = Color3.fromRGB(60, 170, 80),
			TextSize = 10,
			Text = "SEED",
			ZIndex = 4,
		})
		corner(tag, 6)
	end
end

---------------------------------------------------------------------
-- The hotbar
---------------------------------------------------------------------
local bar = make("Frame", {
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(100, SLOT_SIZE),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, SLOT_GAP),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, bar)
local barScale = make("UIScale", { Name = "FitScale" }, bar)

local slots = {}
for i = 1, SLOTS_COMPUTER do
	local button = make("TextButton", {
		Name = "Slot" .. i,
		LayoutOrder = i,
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.12,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, bar)
	corner(button, 14)
	local fill = gradient(button, COLORS.SlotTop, COLORS.SlotBottom)
	local outline = stroke(button, Color3.new(1, 1, 1), 2, 0.2)
	pressEffect(button)

	local iconHolder = make("Frame", {
		Name = "IconHolder",
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 1, -22),
		BackgroundTransparency = 1,
	}, button)

	local name = text(button, {
		Name = "ItemName",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -6, 0, 16),
		TextScaled = true,
		Text = "",
		ZIndex = 3,
	})
	make("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 7 }, name)

	local count = text(button, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		Size = UDim2.fromOffset(40, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(255, 230, 120),
		TextSize = 13,
		Text = "",
		ZIndex = 3,
	})

	local key = text(button, {
		Name = "Key",
		Position = UDim2.fromOffset(6, 2),
		Size = UDim2.fromOffset(14, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLORS.Dim,
		TextSize = 12,
		Text = tostring(i % 10),
		ZIndex = 3,
	})

	slots[i] = {
		Button = button,
		Icon = iconHolder,
		Name = name,
		Count = count,
		Key = key,
		Stroke = outline,
		Fill = fill,
		Tool = nil,
		IconFor = nil,
	}
end

-- the BACKPACK button at the end of the hotbar
local backpackButton = make("TextButton", {
	Name = "BackpackButton",
	LayoutOrder = 100,
	Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
	BackgroundColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = false,
	Text = "",
}, bar)
corner(backpackButton, 14)
gradient(backpackButton, Color3.fromRGB(176, 96, 255), Color3.fromRGB(84, 30, 170))
local backpackStroke = stroke(backpackButton, Color3.new(1, 1, 1), 2.5, 0)
make("UIGradient", {
	Color = ColorSequence.new(COLORS.GlowA, COLORS.GlowB),
}, backpackStroke)
pressEffect(backpackButton)
text(backpackButton, {
	Position = UDim2.fromOffset(0, 2),
	Size = UDim2.new(1, 0, 1, -20),
	TextSize = 32,
	Text = "🎒",
})
text(backpackButton, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -3),
	Size = UDim2.new(1, -4, 0, 16),
	TextScaled = true,
	Text = "BACKPACK",
})
local backpackBadge = text(backpackButton, {
	Name = "Badge",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 8, 0, -8),
	Size = UDim2.fromOffset(28, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(255, 70, 120),
	TextSize = 13,
	Text = "0",
	Visible = false,
	ZIndex = 4,
})
corner(backpackBadge, 11)
make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, backpackBadge)

---------------------------------------------------------------------
-- The backpack window
---------------------------------------------------------------------
local PANEL_SIZE = Vector2.new(680, 420)

local dim = make("TextButton", {
	Name = "Dim",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.55,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
}, panelGui)

local panel = make("Frame", {
	Name = "BackpackPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Visible = false,
}, panelGui)
corner(panel, 18)
gradient(panel, COLORS.PanelTop, COLORS.PanelBottom)
local panelStroke = stroke(panel, Color3.new(1, 1, 1), 4)
local panelGlow = make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.GlowA),
		ColorSequenceKeypoint.new(0.5, COLORS.GlowB),
		ColorSequenceKeypoint.new(1, COLORS.GlowA),
	}),
}, panelStroke)
local panelScale = make("UIScale", { Name = "FitScale" }, panel)

-- a few twinkling stars in the background
do
	local rng = Random.new(7)
	for _ = 1, 40 do
		local size = rng:NextInteger(1, 3)
		make("Frame", {
			Position = UDim2.fromScale(rng:NextNumber(0.02, 0.98), rng:NextNumber(0.2, 0.98)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = rng:NextNumber(0.3, 0.75),
			BorderSizePixel = 0,
		}, panel)
	end
end

local header = make("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 64),
	BackgroundColor3 = Color3.new(1, 1, 1),
	ZIndex = 2,
}, panel)
corner(header, 16)
gradient(header, COLORS.HeaderTop, COLORS.HeaderBottom)

text(header, {
	Position = UDim2.fromOffset(16, 0),
	Size = UDim2.fromOffset(44, 64),
	TextSize = 34,
	Text = "🎒",
	ZIndex = 3,
})
text(header, {
	Position = UDim2.fromOffset(64, 8),
	Size = UDim2.fromOffset(220, 30),
	TextSize = 30,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "BACKPACK",
	ZIndex = 3,
})
local itemCount = text(header, {
	Position = UDim2.fromOffset(66, 38),
	Size = UDim2.fromOffset(220, 18),
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLORS.Dim,
	Text = "0 items",
	ZIndex = 3,
})

local searchBox = make("TextBox", {
	Name = "Search",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -76, 0.5, 0),
	Size = UDim2.fromOffset(210, 40),
	BackgroundColor3 = Color3.fromRGB(14, 12, 40),
	BackgroundTransparency = 0.1,
	ClearTextOnFocus = false,
	Font = FONT,
	PlaceholderText = "🔍 Search...",
	PlaceholderColor3 = Color3.fromRGB(150, 145, 190),
	Text = "",
	TextColor3 = COLORS.Text,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
}, header)
corner(searchBox, 12)
stroke(searchBox, Color3.fromRGB(150, 130, 255), 2, 0.3)
make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8) }, searchBox)

local closeButton = make("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(48, 48),
	BackgroundColor3 = COLORS.Close,
	Font = FONT,
	TextSize = 26,
	TextColor3 = COLORS.Text,
	Text = "X",
	AutoButtonColor = true,
	ZIndex = 3,
}, header)
corner(closeButton, 12)
stroke(closeButton, Color3.fromRGB(255, 140, 160), 2)
pressEffect(closeButton)

-- filter tabs
local tabRow = make("Frame", {
	Name = "Tabs",
	Position = UDim2.fromOffset(14, 74),
	Size = UDim2.new(1, -28, 0, 38),
	BackgroundTransparency = 1,
	ZIndex = 2,
}, panel)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabRow)

local activeCategory = "All"
local tabButtons = {}
local rebuildGrid -- set below
local setBackpackOpen -- set below

local function styleTabs()
	for id, t in pairs(tabButtons) do
		local on = id == activeCategory
		t.Button.BackgroundColor3 = on and Color3.fromRGB(120, 90, 255) or Color3.fromRGB(30, 26, 72)
		t.Stroke.Transparency = on and 0 or 0.6
	end
end

for index, cat in ipairs(CATEGORIES) do
	local b = make("TextButton", {
		Name = cat.Id,
		LayoutOrder = index,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(30, 26, 72),
		Font = FONT,
		TextSize = 17,
		TextColor3 = COLORS.Text,
		Text = cat.Text,
		AutoButtonColor = true,
		ZIndex = 3,
	}, tabRow)
	corner(b, 19)
	make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, b)
	local s = stroke(b, Color3.fromRGB(190, 170, 255), 2, 0.6)
	tabButtons[cat.Id] = { Button = b, Stroke = s, Text = cat.Text }
	b.Activated:Connect(function()
		activeCategory = cat.Id
		styleTabs()
		rebuildGrid()
	end)
end
styleTabs()

local grid = make("ScrollingFrame", {
	Name = "Grid",
	Position = UDim2.fromOffset(10, 120),
	Size = UDim2.new(1, -20, 1, -130),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = Color3.fromRGB(150, 130, 255),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ZIndex = 2,
}, panel)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 8),
}, grid)
make("UIGridLayout", {
	CellSize = UDim2.fromOffset(114, 136),
	CellPadding = UDim2.fromOffset(10, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)

local emptyLabel = text(panel, {
	Name = "Empty",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 50),
	Size = UDim2.new(0.8, 0, 0, 60),
	TextSize = 22,
	TextWrapped = true,
	TextColor3 = COLORS.Dim,
	Text = "",
	Visible = false,
	ZIndex = 3,
})

-- one card per item, kept between rebuilds so the 3D pictures aren't remade every time
local cards = {} -- tool -> card info

local function makeCard(tool)
	local color = rarityColor(tool)
	local card = make("TextButton", {
		Name = "Card",
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		ZIndex = 3,
	}, grid)
	corner(card, 14)
	gradient(card, color:Lerp(Color3.fromRGB(20, 18, 50), 0.62), Color3.fromRGB(12, 10, 32))
	local outline = stroke(card, color, 2.5, 0.1)
	pressEffect(card)

	local iconHolder = make("Frame", {
		Name = "IconHolder",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 72),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, card)
	fillIcon(iconHolder, tool)

	local rarity = text(card, {
		Name = "Rarity",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35),
		TextSize = 11,
		Text = string.upper(tool:GetAttribute("Rarity") or ""),
		ZIndex = 5,
	})
	corner(rarity, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, rarity)
	rarity.Visible = rarity.Text ~= ""

	local name = text(card, {
		Name = "ItemName",
		Position = UDim2.fromOffset(6, 82),
		Size = UDim2.new(1, -12, 0, 32),
		TextScaled = true,
		TextWrapped = true,
		Text = tool.Name,
		ZIndex = 4,
	})
	make("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 8 }, name)

	local detail = text(card, {
		Name = "Detail",
		Position = UDim2.fromOffset(6, 114),
		Size = UDim2.new(1, -12, 0, 16),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 230, 120),
		Text = "",
		ZIndex = 4,
	})

	local equipped = text(card, {
		Name = "Equipped",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(40, 200, 90),
		TextSize = 11,
		Text = "HOLDING",
		Visible = false,
		ZIndex = 5,
	})
	corner(equipped, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, equipped)

	local info = { Card = card, Name = name, Detail = detail, Equipped = equipped, Stroke = outline, Color = color }
	card.Activated:Connect(function()
		toggleTool(tool)
		if ScreenFit.IsPhone() then
			task.delay(0.05, function()
				-- on phones the window covers the game, so close it once you pick something
				if panel.Visible and heldTool() == tool then
					setBackpackOpen(false)
				end
			end)
		end
	end)
	return info
end

local function matchesSearch(tool, query)
	if query == "" then
		return true
	end
	return string.find(string.lower(tool.Name), query, 1, true) ~= nil
end

local function sortedTools()
	local list = table.clone(order)
	table.sort(list, function(a, b)
		local ka, kb = KIND_ORDER[kindOf(a)] or 9, KIND_ORDER[kindOf(b)] or 9
		if ka ~= kb then
			return ka < kb
		end
		local ra, rb = rarityOrder(a), rarityOrder(b)
		if ra ~= rb then
			return ra > rb
		end
		local wa, wb = a:GetAttribute("Weight") or 0, b:GetAttribute("Weight") or 0
		if wa ~= wb then
			return wa > wb
		end
		return a.Name < b.Name
	end)
	return list
end

function rebuildGrid()
	local held = heldTool()
	local query = string.lower(searchBox.Text)
	local counts = { All = 0 }
	local shown = 0

	-- forget cards for items you no longer have
	for tool, info in pairs(cards) do
		if not inOrder[tool] then
			info.Card:Destroy()
			cards[tool] = nil
		end
	end

	for index, tool in ipairs(sortedTools()) do
		local kind = kindOf(tool)
		counts.All += 1
		counts[kind] = (counts[kind] or 0) + 1
		local visible = (activeCategory == "All" or activeCategory == kind) and matchesSearch(tool, query)
		local info = cards[tool]
		if visible and not info then
			info = makeCard(tool)
			cards[tool] = info
		end
		if info then
			info.Card.Visible = visible
			info.Card.LayoutOrder = index
			info.Name.Text = tool.Name
			info.Detail.Text = detailOf(tool)
			local isHeld = tool == held
			info.Equipped.Visible = isHeld
			info.Stroke.Color = isHeld and Color3.new(1, 1, 1) or info.Color
			info.Stroke.Thickness = isHeld and 3.5 or 2.5
		end
		if visible then
			shown += 1
		end
	end

	for id, t in pairs(tabButtons) do
		local n = counts[id] or 0
		t.Button.Text = t.Text .. "  " .. n
	end
	itemCount.Text = counts.All == 1 and "1 item" or (commas(counts.All) .. " items")

	emptyLabel.Visible = shown == 0
	if counts.All == 0 then
		emptyLabel.Text = "Your backpack is empty!\nBuy seeds from the Seed Seller."
	elseif shown == 0 then
		emptyLabel.Text = "Nothing here" .. (query ~= "" and (' matches "' .. searchBox.Text .. '"') or " yet")
	end
end

local function fitPanel()
	if not ScreenFit.IsPhone() then
		panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		return ScreenFit.Fit(PANEL_SIZE, 0.9)
	end
	-- phones: fit the height, then use the wide screen for more cards per row
	local size = ScreenFit.Size()
	local scale = math.min(1, size.Y * 0.96 / PANEL_SIZE.Y)
	local width = math.clamp(size.X * 0.92 / scale, 480, 900)
	panel.Size = UDim2.fromOffset(width, PANEL_SIZE.Y)
	-- centre it in the space below Roblox's top bar buttons
	local camera = workspace.CurrentCamera
	local inset = camera and (camera.ViewportSize.Y - size.Y) or 0
	panel.Position = UDim2.new(0.5, 0, 0, inset + size.Y / 2)
	return scale
end

setBackpackOpen = function(open)
	if open == panel.Visible then
		return
	end
	if open then
		rebuildGrid()
		local target = fitPanel()
		panelScale.Scale = target * 0.85
		panel.Visible = true
		dim.Visible = true
		TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	else
		panel.Visible = false
		dim.Visible = false
		searchBox:ReleaseFocus()
	end
end

closeButton.Activated:Connect(function()
	setBackpackOpen(false)
end)
dim.Activated:Connect(function()
	setBackpackOpen(false)
end)
backpackButton.Activated:Connect(function()
	setBackpackOpen(not panel.Visible)
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if panel.Visible then
		rebuildGrid()
	end
end)

-- the glowing border slowly turns while the window is open
task.spawn(function()
	while gui.Parent do
		if panel.Visible then
			panelGlow.Rotation = (panelGlow.Rotation + 2) % 360
			task.wait(1 / 30)
		else
			task.wait(0.3)
		end
	end
end)

---------------------------------------------------------------------
-- Settings (music on / off)
---------------------------------------------------------------------
local settingsButton = make("TextButton", {
	Name = "SettingsButton",
	Size = UDim2.fromOffset(52, 52),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.1,
	AutoButtonColor = false,
	Font = FONT,
	TextSize = 30,
	TextColor3 = COLORS.Text,
	Text = "⚙",
}, gui)
corner(settingsButton, "round")
gradient(settingsButton, COLORS.SlotTop, COLORS.SlotBottom)
stroke(settingsButton, Color3.fromRGB(150, 130, 255), 2, 0.2)
pressEffect(settingsButton)

local settingsPanel = make("Frame", {
	Name = "SettingsPanel",
	Size = UDim2.fromOffset(240, 112),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Visible = false,
}, gui)
corner(settingsPanel, 14)
gradient(settingsPanel, COLORS.PanelTop, COLORS.PanelBottom)
stroke(settingsPanel, Color3.fromRGB(150, 130, 255), 2, 0.2)
text(settingsPanel, {
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -28, 0, 28),
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Settings",
})
local musicButton = make("TextButton", {
	Position = UDim2.fromOffset(14, 50),
	Size = UDim2.new(1, -28, 0, 46),
	BackgroundColor3 = Color3.fromRGB(60, 170, 80),
	Font = FONT,
	TextSize = 20,
	TextColor3 = COLORS.Text,
	Text = "Music: ON",
}, settingsPanel)
corner(musicButton, 10)

local musicMuted = false
local function applyMusic(sound)
	if sound:IsA("Sound") and sound.Looped then
		if sound:GetAttribute("OriginalVolume") == nil then
			sound:SetAttribute("OriginalVolume", sound.Volume)
		end
		sound.Volume = musicMuted and 0 or sound:GetAttribute("OriginalVolume")
	end
end
local function applyMusicToAll()
	for _, root in ipairs({ workspace, SoundService }) do
		for _, descendant in ipairs(root:GetDescendants()) do
			applyMusic(descendant)
		end
	end
end
musicButton.Activated:Connect(function()
	musicMuted = not musicMuted
	musicButton.Text = musicMuted and "Music: OFF" or "Music: ON"
	musicButton.BackgroundColor3 = musicMuted and Color3.fromRGB(170, 50, 50) or Color3.fromRGB(60, 170, 80)
	applyMusicToAll()
end)
for _, root in ipairs({ workspace, SoundService }) do
	root.DescendantAdded:Connect(function(descendant)
		if musicMuted then
			task.defer(applyMusic, descendant)
		end
	end)
end
settingsButton.Activated:Connect(function()
	settingsPanel.Visible = not settingsPanel.Visible
end)

---------------------------------------------------------------------
-- Keeping everything up to date
---------------------------------------------------------------------
local lastSignature = ""

local function slotCount()
	return ScreenFit.IsPhone() and SLOTS_PHONE or SLOTS_COMPUTER
end

local function refresh(force)
	local found = allTools()
	for index = #order, 1, -1 do
		local tool = order[index]
		if not found[tool] then
			table.remove(order, index)
			inOrder[tool] = nil
		end
	end
	for tool in pairs(found) do
		if not inOrder[tool] then
			inOrder[tool] = true
			table.insert(order, tool)
		end
	end

	local held = heldTool()
	local parts = { held and held.Name or "-", tostring(slotCount()) }
	for _, tool in ipairs(order) do
		table.insert(parts, tool.Name .. detailOf(tool))
	end
	local signature = table.concat(parts, "|")
	if signature == lastSignature and not force then
		return
	end
	lastSignature = signature

	local shownSlots = slotCount()
	for i = 1, SLOTS_COMPUTER do
		local slot = slots[i]
		local tool = i <= shownSlots and order[i] or nil
		slot.Tool = tool
		slot.Button.Visible = tool ~= nil
		if tool then
			if slot.IconFor ~= tool then
				slot.IconFor = tool
				fillIcon(slot.Icon, tool)
			end
			slot.Name.Text = tool.Name
			local detail = detailOf(tool)
			slot.Count.Text = tool:GetAttribute("Weight") and "" or detail
			local selected = tool == held
			slot.Stroke.Color = selected and Color3.new(1, 1, 1) or rarityColor(tool)
			slot.Stroke.Thickness = selected and 3.5 or 2
			slot.Stroke.Transparency = selected and 0 or 0.15
			slot.Fill.Color = selected
					and ColorSequence.new(Color3.fromRGB(110, 90, 255), Color3.fromRGB(40, 28, 120))
				or ColorSequence.new(COLORS.SlotTop, COLORS.SlotBottom)
		elseif slot.IconFor then
			slot.IconFor = nil
			fillIcon(slot.Icon, nil)
		end
	end

	local total = #order
	backpackBadge.Visible = total > 0
	backpackBadge.Text = total > 999 and "999+" or tostring(total)

	if panel.Visible then
		rebuildGrid()
	end
end

for i = 1, SLOTS_COMPUTER do
	slots[i].Button.Activated:Connect(function()
		toggleTool(slots[i].Tool)
	end)
end

local numberKeys = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("DialogueOpen") then
		return
	end
	if input.KeyCode == Enum.KeyCode.Backquote then
		setBackpackOpen(not panel.Visible)
		return
	end
	local index = numberKeys[input.KeyCode]
	if index then
		toggleTool(slots[index].Tool)
	end
end)

---------------------------------------------------------------------
-- Fit the screen: phones get fewer, bigger-to-tap slots that fit between the joystick and jump button
---------------------------------------------------------------------
ScreenFit.Watch(function()
	local phone = ScreenFit.IsPhone()
	local size = ScreenFit.Size()
	local count = phone and SLOTS_PHONE or SLOTS_COMPUTER
	local width = (count + 1) * (SLOT_SIZE + SLOT_GAP)
	if phone then
		-- keep clear of the joystick (left) and jump button (right): use the middle ~58% of the screen
		barScale.Scale = math.clamp(size.X * 0.58 / width, 0.55, 0.9)
		bar.Position = UDim2.new(0.5, 0, 1, -6)
	else
		barScale.Scale = math.clamp((size.X - 24) / width, 0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -10)
	end
	for i = 1, SLOTS_COMPUTER do
		slots[i].Key.Visible = not phone and UserInputService.KeyboardEnabled
	end

	-- settings: top-left on computers, left side (under the coins) on phones
	if phone then
		settingsButton.Size = UDim2.fromOffset(44, 44)
		settingsButton.Position = UDim2.fromOffset(8, 48)
		settingsPanel.Position = UDim2.fromOffset(60, 48)
	else
		settingsButton.Size = UDim2.fromOffset(52, 52)
		settingsButton.Position = UDim2.fromOffset(12, 10)
		settingsPanel.Position = UDim2.fromOffset(12, 72)
	end

	if panel.Visible then
		panelScale.Scale = fitPanel()
	end
	refresh(true)
end)

-- the hotbar hides while a shop window is open (it would cover the bottom of the window)
local function windowOpen()
	if player:GetAttribute("DialogueOpen") then
		return true
	end
	for _, screen in ipairs(playerGui:GetChildren()) do
		if screen:IsA("ScreenGui") and string.sub(screen.Name, 1, 5) == "Shop_" then
			local main = screen:FindFirstChild("Main")
			if main and main.Visible then
				return true
			end
		end
	end
	return false
end

task.spawn(function()
	while gui.Parent do
		refresh(false)
		-- shop windows take the whole view (blurred background), so the hotbar steps aside
		local hide = windowOpen()
		bar.Visible = not hide
		settingsButton.Visible = not hide
		task.wait(0.15)
	end
end)

print("[GardenHotbar] ready")
