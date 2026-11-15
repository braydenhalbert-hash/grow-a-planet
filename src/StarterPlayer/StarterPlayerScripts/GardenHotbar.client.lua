--[[
	GardenHotbar  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	A Grow-a-Garden style bar:
	  * Top left: three round buttons: Settings (gear), Backpack, Tools (wrench)
	  * Bottom: dark rounded hotbar with the name of each item you have (first 10)
	  * Click a slot or press 1-9 / 0 to hold it. Do it again to put it away.
	  * The Backpack button opens a panel with EVERYTHING you own. Click one to hold it.
	  * The gear opens Settings (a music on/off switch).

	This REPLACES SeedHotbar and ShowBackpack. DELETE those two scripts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local SLOT_COUNT = 10
local SLOT_WIDTH = 72  -- width and height are the same, so every slot is a true square
local SLOT_HEIGHT = 72
local SLOT_GAP = 8
local BUTTONS_POSITION = UDim2.fromOffset(12, 10) -- top-left buttons. Move them here if the chat covers them.
local BACKGROUND = Color3.fromRGB(28, 36, 30)
local BACKGROUND_SELECTED = Color3.fromRGB(70, 84, 72)

local okCatalog, PlanetCatalog = pcall(function()
	return require(ReplicatedStorage:WaitForChild("PlanetCatalog", 5))
end)

local function rarityColor(tool)
	local rarity = tool:GetAttribute("Rarity")
	if okCatalog and rarity then
		local ok, color = pcall(PlanetCatalog.RarityColor, rarity)
		if ok and color then
			return color
		end
	end
	return Color3.fromRGB(190, 200, 190)
end

---------------------------------------------------------------------
-- Hide Roblox's own hotbar (this one replaces it)
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
-- Screen
---------------------------------------------------------------------
local old = playerGui:FindFirstChild("GardenHotbar")
if old then
	old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "GardenHotbar"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = gui

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

---------------------------------------------------------------------
-- The hotbar
---------------------------------------------------------------------
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -12)
bar.Size = UDim2.fromOffset(SLOT_COUNT * (SLOT_WIDTH + SLOT_GAP) - SLOT_GAP, SLOT_HEIGHT)
bar.BackgroundTransparency = 1
bar.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, SLOT_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

local slots = {}
for i = 1, SLOT_COUNT do
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. i
	button.LayoutOrder = i
	button.Size = UDim2.fromOffset(SLOT_WIDTH, SLOT_HEIGHT)
	button.BackgroundColor3 = BACKGROUND
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = false
	button.Text = ""
	button.Visible = false
	button.Parent = bar
	corner(button, 12)
	local outline = stroke(button, Color3.fromRGB(190, 200, 190), 2, 0.5)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -10, 1, -22)
	label.Position = UDim2.fromOffset(5, 17)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 22
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextWrapped = true
	label.TextScaled = true -- long names shrink to fit instead of getting cut off
	label.Text = ""
	label.Parent = button
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.MinTextSize = 10
	limit.Parent = label

	local number = Instance.new("TextLabel")
	number.BackgroundTransparency = 1
	number.Position = UDim2.fromOffset(6, 2)
	number.Size = UDim2.fromOffset(16, 14)
	number.Font = Enum.Font.FredokaOne
	number.TextSize = 12
	number.TextColor3 = Color3.fromRGB(200, 210, 200)
	number.TextXAlignment = Enum.TextXAlignment.Left
	number.Text = tostring(i % 10)
	number.Parent = button

	slots[i] = { Button = button, Label = label, Stroke = outline, Tool = nil }
end

---------------------------------------------------------------------
-- Items
---------------------------------------------------------------------
local order = {}       -- tools in the order you got them
local inOrder = {}     -- tool -> true
local lastSignature = ""

local function displayName(tool)
	local name = tool.Name
	local count = tool:GetAttribute("Count")
	if count and count > 1 and not name:find("%[") then
		name = name .. " [X" .. count .. "]"
	end
	return name
end

local function allTools()
	local found = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				found[child] = true
			end
		end
	end
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				found[child] = true
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
	if not humanoid or humanoid.Health <= 0 or not tool then
		return
	end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

---------------------------------------------------------------------
-- Backpack panel
---------------------------------------------------------------------
local backpackPanel = Instance.new("Frame")
backpackPanel.Name = "BackpackPanel"
backpackPanel.AnchorPoint = Vector2.new(0.5, 0.5)
backpackPanel.Position = UDim2.fromScale(0.5, 0.45)
backpackPanel.Size = UDim2.fromOffset(500, 360)
backpackPanel.BackgroundColor3 = Color3.fromRGB(24, 30, 26)
backpackPanel.BackgroundTransparency = 0.1
backpackPanel.Visible = false
backpackPanel.Parent = gui
corner(backpackPanel, 16)
stroke(backpackPanel, Color3.fromRGB(190, 200, 190), 2, 0.4)

local backpackTitle = Instance.new("TextLabel")
backpackTitle.BackgroundTransparency = 1
backpackTitle.Position = UDim2.fromOffset(16, 8)
backpackTitle.Size = UDim2.new(1, -70, 0, 34)
backpackTitle.Font = Enum.Font.FredokaOne
backpackTitle.TextSize = 26
backpackTitle.TextColor3 = Color3.new(1, 1, 1)
backpackTitle.TextXAlignment = Enum.TextXAlignment.Left
backpackTitle.Text = "Backpack"
backpackTitle.Parent = backpackPanel

local closeBackpack = Instance.new("TextButton")
closeBackpack.AnchorPoint = Vector2.new(1, 0)
closeBackpack.Position = UDim2.new(1, -12, 0, 10)
closeBackpack.Size = UDim2.fromOffset(34, 34)
closeBackpack.BackgroundColor3 = Color3.fromRGB(190, 40, 40)
closeBackpack.Font = Enum.Font.FredokaOne
closeBackpack.TextSize = 20
closeBackpack.TextColor3 = Color3.new(1, 1, 1)
closeBackpack.Text = "X"
closeBackpack.Parent = backpackPanel
corner(closeBackpack, 10)

local grid = Instance.new("ScrollingFrame")
grid.Position = UDim2.fromOffset(12, 52)
grid.Size = UDim2.new(1, -24, 1, -64)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 6
grid.CanvasSize = UDim2.new()
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.Parent = backpackPanel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(104, 74)
gridLayout.CellPadding = UDim2.fromOffset(8, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

local function rebuildBackpack()
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local held = heldTool()
	for index, tool in ipairs(order) do
		local cell = Instance.new("TextButton")
		cell.LayoutOrder = index
		cell.BackgroundColor3 = (tool == held) and BACKGROUND_SELECTED or BACKGROUND
		cell.BackgroundTransparency = 0.15
		cell.AutoButtonColor = true
		cell.Font = Enum.Font.FredokaOne
		cell.TextSize = 15
		cell.TextColor3 = Color3.new(1, 1, 1)
		cell.TextWrapped = true
		cell.Text = displayName(tool)
		cell.Parent = grid
		corner(cell, 12)
		stroke(cell, rarityColor(tool), 2, 0.2)
		cell.MouseButton1Click:Connect(function()
			toggleTool(tool)
			backpackPanel.Visible = false
		end)
	end
end

local function setBackpackVisible(visible)
	backpackPanel.Visible = visible
	if visible then
		rebuildBackpack()
	end
end

closeBackpack.MouseButton1Click:Connect(function()
	setBackpackVisible(false)
end)

---------------------------------------------------------------------
-- Settings panel (music on / off)
---------------------------------------------------------------------
local settingsPanel = Instance.new("Frame")
settingsPanel.Name = "SettingsPanel"
settingsPanel.Position = UDim2.new(BUTTONS_POSITION.X.Scale, BUTTONS_POSITION.X.Offset, BUTTONS_POSITION.Y.Scale, BUTTONS_POSITION.Y.Offset + 66)
settingsPanel.Size = UDim2.fromOffset(240, 110)
settingsPanel.BackgroundColor3 = Color3.fromRGB(24, 30, 26)
settingsPanel.BackgroundTransparency = 0.1
settingsPanel.Visible = false
settingsPanel.Parent = gui
corner(settingsPanel, 14)
stroke(settingsPanel, Color3.fromRGB(190, 200, 190), 2, 0.4)

local settingsTitle = Instance.new("TextLabel")
settingsTitle.BackgroundTransparency = 1
settingsTitle.Position = UDim2.fromOffset(14, 8)
settingsTitle.Size = UDim2.new(1, -28, 0, 28)
settingsTitle.Font = Enum.Font.FredokaOne
settingsTitle.TextSize = 22
settingsTitle.TextColor3 = Color3.new(1, 1, 1)
settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
settingsTitle.Text = "Settings"
settingsTitle.Parent = settingsPanel

local musicButton = Instance.new("TextButton")
musicButton.Position = UDim2.fromOffset(14, 50)
musicButton.Size = UDim2.new(1, -28, 0, 44)
musicButton.BackgroundColor3 = Color3.fromRGB(60, 150, 70)
musicButton.Font = Enum.Font.FredokaOne
musicButton.TextSize = 20
musicButton.TextColor3 = Color3.new(1, 1, 1)
musicButton.Text = "Music: ON"
musicButton.Parent = settingsPanel
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

musicButton.MouseButton1Click:Connect(function()
	musicMuted = not musicMuted
	musicButton.Text = musicMuted and "Music: OFF" or "Music: ON"
	musicButton.BackgroundColor3 = musicMuted and Color3.fromRGB(170, 50, 50) or Color3.fromRGB(60, 150, 70)
	applyMusicToAll()
end)

workspace.DescendantAdded:Connect(function(descendant)
	if musicMuted then
		task.defer(applyMusic, descendant)
	end
end)
SoundService.DescendantAdded:Connect(function(descendant)
	if musicMuted then
		task.defer(applyMusic, descendant)
	end
end)

---------------------------------------------------------------------
-- Top-left round buttons
---------------------------------------------------------------------
local function roundButton(name, icon, x)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.new(BUTTONS_POSITION.X.Scale, BUTTONS_POSITION.X.Offset + x, BUTTONS_POSITION.Y.Scale, BUTTONS_POSITION.Y.Offset)
	button.Size = UDim2.fromOffset(56, 56)
	button.BackgroundColor3 = BACKGROUND
	button.BackgroundTransparency = 0.15
	button.AutoButtonColor = true
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 30
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = icon
	button.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = button
	stroke(button, Color3.fromRGB(190, 200, 190), 2, 0.4)
	return button
end

local settingsButton = roundButton("SettingsButton", "⚙", 0)
local backpackButton = roundButton("BackpackButton", "🎒", 66)
local toolsButton = roundButton("ToolsButton", "🛠", 132)

settingsButton.MouseButton1Click:Connect(function()
	settingsPanel.Visible = not settingsPanel.Visible
end)
backpackButton.MouseButton1Click:Connect(function()
	setBackpackVisible(not backpackPanel.Visible)
end)
toolsButton.MouseButton1Click:Connect(function()
	-- nothing here yet: tell me what the wrench should open
	toolsButton.Text = "…"
	task.delay(0.6, function()
		toolsButton.Text = "🛠"
	end)
end)

---------------------------------------------------------------------
-- Keeping everything up to date
---------------------------------------------------------------------
local function refresh()
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
	local parts = { held and held.Name or "-" }
	for _, tool in ipairs(order) do
		table.insert(parts, displayName(tool))
	end
	local signature = table.concat(parts, "|")
	if signature == lastSignature then
		return
	end
	lastSignature = signature

	for i = 1, SLOT_COUNT do
		local slot = slots[i]
		local tool = order[i]
		slot.Tool = tool
		if tool then
			slot.Button.Visible = true
			slot.Label.Text = displayName(tool)
			local selected = tool == held
			slot.Button.BackgroundColor3 = selected and BACKGROUND_SELECTED or BACKGROUND
			slot.Button.BackgroundTransparency = selected and 0.1 or 0.25
			slot.Stroke.Color = selected and Color3.new(1, 1, 1) or rarityColor(tool)
			slot.Stroke.Thickness = selected and 3 or 2
			slot.Stroke.Transparency = selected and 0 or 0.35
		else
			slot.Button.Visible = false
		end
	end

	if backpackPanel.Visible then
		rebuildBackpack()
	end
end

for i = 1, SLOT_COUNT do
	slots[i].Button.MouseButton1Click:Connect(function()
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
	local index = numberKeys[input.KeyCode]
	if index then
		toggleTool(slots[index].Tool)
	end
end)

-- scale everything down on small screens (phones)
local function rescale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local width = camera.ViewportSize.X
	local needed = SLOT_COUNT * (SLOT_WIDTH + SLOT_GAP) + 24
	uiScale.Scale = math.clamp(width / needed, 0.5, 1)
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

task.spawn(function()
	while gui.Parent do
		refresh()
		task.wait(0.15)
	end
end)

print("[GardenHotbar] ready")
