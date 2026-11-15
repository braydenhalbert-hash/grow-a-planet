--[[
	AdminPanel  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts   (new LocalScript, name it exactly: AdminPanel)

	Your personal admin panel. It only shows up for the people AdminServer allows (you).
	Open / close it with the ADMIN button in the bottom-right corner, or press F2.

	  Money   add / remove / set coins (type 5k, 2m, 3b, 1t for thousands, millions...)
	  Items   give any planet seed, give any seed pack
	  Garden  grow every planet of yours instantly, harvest them all, restock the shops,
	          give all your planets a mutation (or remove it)
	  Player  walk speed, jump power, god mode, fly (W A S D, Space up, Left Ctrl down)

	Needs: AdminServer (ServerScriptService), PlanetCatalog + PackCatalog + MutationCatalog (ReplicatedStorage)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local TOGGLE_KEY = Enum.KeyCode.F2
local FLY_SPEED = 70

---------------------------------------------------------------------
-- Only for admins (the server decides)
---------------------------------------------------------------------
if not player:GetAttribute("IsAdmin") then
	local deadline = os.clock() + 15
	while not player:GetAttribute("IsAdmin") and os.clock() < deadline do
		task.wait(0.25)
	end
	if not player:GetAttribute("IsAdmin") then
		return
	end
end

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PackCatalog = require(ReplicatedStorage:WaitForChild("PackCatalog"))
local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))
local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local actionRemote = remotes:WaitForChild("AdminAction", 15)
local noticeRemote = remotes:FindFirstChild("Notice")
if not actionRemote then
	warn("[AdminPanel] AdminServer isn't running (no AdminAction remote)")
	return
end

---------------------------------------------------------------------
-- Look
---------------------------------------------------------------------
local C = {
	Window = Color3.fromRGB(20, 11, 36),
	Header = Color3.fromRGB(38, 20, 66),
	Panel = Color3.fromRGB(33, 19, 56),
	Row = Color3.fromRGB(45, 27, 74),
	Accent = Color3.fromRGB(150, 90, 255),
	Good = Color3.fromRGB(70, 190, 110),
	Bad = Color3.fromRGB(210, 70, 80),
	Text = Color3.fromRGB(240, 232, 255),
	Dim = Color3.fromRGB(165, 150, 195),
}

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or C.Accent
	s.Thickness = thickness or 1.5
	s.Parent = parent
	return s
end

local function label(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size or 14
	l.TextColor3 = color or C.Text
	l.Font = font or Enum.Font.GothamBold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, (size or 14) + 6)
	l.Parent = parent
	return l
end

local function button(parent, text, color, onClick, height)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 14
	b.Font = Enum.Font.GothamBold
	b.BackgroundColor3 = color or C.Accent
	b.Size = UDim2.new(1, 0, 0, height or 34)
	b.Parent = parent
	corner(b, 8)
	local base = b.BackgroundColor3
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.18) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = base }):Play()
	end)
	b.MouseButton1Click:Connect(function()
		local ui = b:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", b)
		ui.Scale = 0.94
		TweenService:Create(ui, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		if onClick then
			onClick()
		end
	end)
	return b
end

local function textBox(parent, default, placeholder)
	local t = Instance.new("TextBox")
	t.BackgroundColor3 = C.Row
	t.TextColor3 = C.Text
	t.PlaceholderColor3 = C.Dim
	t.PlaceholderText = placeholder or ""
	t.Text = default or ""
	t.TextSize = 14
	t.Font = Enum.Font.GothamBold
	t.ClearTextOnFocus = false
	t.Size = UDim2.new(1, 0, 0, 34)
	t.Parent = parent
	corner(t, 8)
	stroke(t, C.Accent, 1)
	return t
end

local function listLayout(parent, padding)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

-- 5k, 2.5m, 3b, 1t, 1,000,000
local function parseNumber(text)
	text = string.lower((string.gsub(text or "", "[%s,]", "")))
	local number, suffix = string.match(text, "^(-?[%d%.]+)([kmbt]?)$")
	local value = tonumber(number)
	if not value then
		return nil
	end
	local mult = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
	return value * (mult[suffix] or 1)
end

local function send(action, a, b)
	actionRemote:FireServer(action, a, b)
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AdminPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(440, 560)
window.Position = UDim2.new(0, 24, 0.5, -280)
window.BackgroundColor3 = C.Window
window.Visible = false
window.Parent = gui
corner(window, 14)
stroke(window, C.Accent, 2)

local scale = Instance.new("UIScale")
scale.Parent = window

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = C.Header
header.Parent = window
corner(header, 14)

local headerFix = Instance.new("Frame") -- squares off the bottom corners of the header
headerFix.Size = UDim2.new(1, 0, 0, 14)
headerFix.Position = UDim2.new(0, 0, 1, -14)
headerFix.BackgroundColor3 = C.Header
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.fromOffset(16, 0)
title.Text = "ADMIN PANEL"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextSize = 20
title.Font = Enum.Font.FredokaOne
title.TextColor3 = C.Text
title.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.Position = UDim2.new(1, -38, 0, 7)
closeButton.BackgroundColor3 = C.Bad
closeButton.Text = "X"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.AutoButtonColor = true
closeButton.Parent = header
corner(closeButton, 8)

-- drag the window by its header
do
	local dragging, dragStart, startPos
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, window.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local tabRow = Instance.new("Frame")
tabRow.BackgroundTransparency = 1
tabRow.Size = UDim2.new(1, -24, 0, 34)
tabRow.Position = UDim2.fromOffset(12, 52)
tabRow.Parent = window
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabRow

local pages = {}
local tabButtons = {}

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -24, 0, 22)
status.Position = UDim2.new(0, 12, 1, -28)
status.Text = "Ready"
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextSize = 13
status.Font = Enum.Font.GothamMedium
status.TextColor3 = C.Dim
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Parent = window

local function say(text, color)
	status.Text = text
	status.TextColor3 = color or C.Dim
end

if noticeRemote then
	noticeRemote.OnClientEvent:Connect(function(text, kind)
		if window.Visible and type(text) == "string" then
			say(text, kind == "error" and C.Bad or C.Good)
		end
	end)
end

local function newPage(name)
	local page = Instance.new("ScrollingFrame")
	page.Name = name
	page.BackgroundColor3 = C.Panel
	page.BorderSizePixel = 0
	page.Size = UDim2.new(1, -24, 1, -126)
	page.Position = UDim2.fromOffset(12, 94)
	page.ScrollBarThickness = 5
	page.ScrollBarImageColor3 = C.Accent
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new()
	page.Visible = false
	page.Parent = window
	corner(page, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = page
	listLayout(page, 8)
	pages[name] = page
	return page
end

local function selectTab(name)
	for pageName, page in pairs(pages) do
		page.Visible = pageName == name
	end
	for tabName, tab in pairs(tabButtons) do
		tab.BackgroundColor3 = tabName == name and C.Accent or C.Row
	end
end

local function addTab(name, order)
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(0.25, -5, 1, 0)
	tab.BackgroundColor3 = C.Row
	tab.Text = name
	tab.TextColor3 = C.Text
	tab.TextSize = 14
	tab.Font = Enum.Font.GothamBold
	tab.AutoButtonColor = true
	tab.LayoutOrder = order
	tab.Parent = tabRow
	corner(tab, 8)
	tab.MouseButton1Click:Connect(function()
		selectTab(name)
	end)
	tabButtons[name] = tab
end

---------------------------------------------------------------------
-- MONEY
---------------------------------------------------------------------
addTab("Money", 1)
addTab("Items", 2)
addTab("Garden", 3)
addTab("Player", 4)

local money = newPage("Money")
label(money, "Amount (5k, 2.5m, 3b, 1t all work)", 13, C.Dim)
local amountBox = textBox(money, "1m", "amount")

local function amountOrWarn()
	local value = parseNumber(amountBox.Text)
	if not value or value < 0 then
		say("Type a number like 5000 or 5k or 2m", C.Bad)
		return nil
	end
	return value
end

button(money, "Add coins", C.Good, function()
	local v = amountOrWarn()
	if v then
		send("coins_add", v)
	end
end)
button(money, "Remove coins", C.Bad, function()
	local v = amountOrWarn()
	if v then
		send("coins_add", -v)
	end
end)
button(money, "Set coins to this amount", C.Accent, function()
	local v = amountOrWarn()
	if v then
		send("coins_set", v)
	end
end)

label(money, "Quick add", 13, C.Dim)
local quick = Instance.new("Frame")
quick.BackgroundTransparency = 1
quick.Size = UDim2.new(1, 0, 0, 74)
quick.Parent = money
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.333, -6, 0, 34)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.Parent = quick
for _, entry in ipairs({ { "+1K", 1e3 }, { "+100K", 1e5 }, { "+1M", 1e6 }, { "+1B", 1e9 }, { "+1T", 1e12 }, { "+1Q", 1e15 } }) do
	button(quick, entry[1], C.Row, function()
		send("coins_add", entry[2])
	end)
end
button(money, "Reset coins to 100", C.Bad, function()
	send("coins_set", 100)
end)

---------------------------------------------------------------------
-- ITEMS
---------------------------------------------------------------------
local items = newPage("Items")
label(items, "How many per click", 13, C.Dim)
local countBox = textBox(items, "1", "amount")

local function countOrWarn()
	local v = parseNumber(countBox.Text)
	if not v or v < 1 then
		say("Type how many (1 or more)", C.Bad)
		return nil
	end
	return math.floor(v)
end

label(items, "Seed packs", 13, C.Dim)
for _, pack in ipairs(PackCatalog.Packs) do
	button(items, "Give  " .. pack.Name, C.Accent, function()
		local n = countOrWarn()
		if n then
			send("give_pack", pack.Id, n)
		end
	end)
end

label(items, "Planet seeds", 13, C.Dim)
local search = textBox(items, "", "search planets...")
local seedButtons = {}
for _, planet in ipairs(PlanetCatalog.Planets) do
	local color = PlanetCatalog.RarityColor(planet.Rarity)
	local b = button(items, planet.Name .. "   (" .. tostring(planet.Rarity) .. ")", C.Row, function()
		local n = countOrWarn()
		if n then
			send("give_seed", planet.Id, n)
		end
	end)
	b.TextColor3 = color
	b.TextXAlignment = Enum.TextXAlignment.Left
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.Parent = b
	table.insert(seedButtons, { Button = b, Name = string.lower(planet.Name .. " " .. tostring(planet.Rarity)) })
end
search:GetPropertyChangedSignal("Text"):Connect(function()
	local query = string.lower(search.Text)
	for _, entry in ipairs(seedButtons) do
		entry.Button.Visible = query == "" or string.find(entry.Name, query, 1, true) ~= nil
	end
end)

---------------------------------------------------------------------
-- GARDEN
---------------------------------------------------------------------
local garden = newPage("Garden")
label(garden, "Your planets", 13, C.Dim)
button(garden, "Grow all my planets instantly", C.Good, function()
	send("grow")
end)
button(garden, "Grow + harvest everything", C.Good, function()
	send("harvest")
end)
button(garden, "Restock the shops now", C.Accent, function()
	send("restock")
end)

label(garden, "Add a mutation to ALL my planets (they stack)", 13, C.Dim)
for _, id in ipairs(MutationCatalog.Order) do
	local mutation = MutationCatalog.Get(id)
	button(garden, string.format("%s   (%dx coins, %dx sell)", mutation.Name, mutation.CoinMult, mutation.SellMult), mutation.Color2, function()
		send("mutate", id)
	end)
end
button(garden, "Remove mutations", C.Bad, function()
	send("mutate", "none")
end)

---------------------------------------------------------------------
-- PLAYER (done on your own screen, it only affects your own character)
---------------------------------------------------------------------
local playerPage = newPage("Player")

local function humanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character
end

label(playerPage, "Walk speed (normal is 16)", 13, C.Dim)
local speedBox = textBox(playerPage, "50", "speed")
button(playerPage, "Set walk speed", C.Accent, function()
	local v = parseNumber(speedBox.Text)
	local hum = humanoid()
	if v and hum then
		hum.WalkSpeed = math.clamp(v, 0, 500)
		say("Walk speed " .. hum.WalkSpeed, C.Good)
	end
end)
label(playerPage, "Jump power (normal is 50)", 13, C.Dim)
local jumpBox = textBox(playerPage, "100", "jump power")
button(playerPage, "Set jump power", C.Accent, function()
	local v = parseNumber(jumpBox.Text)
	local hum = humanoid()
	if v and hum then
		hum.UseJumpPower = true
		hum.JumpPower = math.clamp(v, 0, 500)
		say("Jump power " .. hum.JumpPower, C.Good)
	end
end)
button(playerPage, "Reset speed and jump", C.Row, function()
	local hum = humanoid()
	if hum then
		hum.WalkSpeed = 16
		hum.UseJumpPower = true
		hum.JumpPower = 50
		say("Speed and jump reset", C.Good)
	end
end)

-- god mode
local god = false
local function applyGod(character)
	if not character then
		return
	end
	local existing = character:FindFirstChild("AdminGodField")
	if god and not existing then
		local field = Instance.new("ForceField")
		field.Name = "AdminGodField"
		field.Visible = false
		field.Parent = character
	elseif not god and existing then
		existing:Destroy()
	end
end
local godButton
godButton = button(playerPage, "God mode: OFF", C.Row, function()
	god = not god
	godButton.Text = "God mode: " .. (god and "ON" or "OFF")
	godButton.BackgroundColor3 = god and C.Good or C.Row
	applyGod(player.Character)
end)
player.CharacterAdded:Connect(function(character)
	task.wait(0.5)
	applyGod(character)
end)

-- fly
local flying = false
local flyConnection
local function setFly(on)
	flying = on
	local hum, character = humanoid()
	if flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
	if hum then
		hum.PlatformStand = on
	end
	if on and character then
		flyConnection = RunService.RenderStepped:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart")
			local camera = workspace.CurrentCamera
			if not root or not camera or UserInputService:GetFocusedTextBox() then
				if root then
					root.AssemblyLinearVelocity = Vector3.zero
				end
				return
			end
			local look, right = camera.CFrame.LookVector, camera.CFrame.RightVector
			local dir = Vector3.zero
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += look end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= look end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += right end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= right end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
			root.AssemblyLinearVelocity = dir.Magnitude > 0 and dir.Unit * FLY_SPEED or Vector3.zero
			root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(look.X, 0, look.Z))
		end)
	end
end
local flyButton
flyButton = button(playerPage, "Fly: OFF   (W A S D, Space up, Ctrl down)", C.Row, function()
	setFly(not flying)
	flyButton.Text = "Fly: " .. (flying and "ON" or "OFF") .. "   (W A S D, Space up, Ctrl down)"
	flyButton.BackgroundColor3 = flying and C.Good or C.Row
end)
player.CharacterAdded:Connect(function()
	flying = false
	flyButton.Text = "Fly: OFF   (W A S D, Space up, Ctrl down)"
	flyButton.BackgroundColor3 = C.Row
	if flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
end)

---------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------
local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.fromOffset(86, 32)
toggleButton.AnchorPoint = Vector2.new(1, 1)
toggleButton.Position = UDim2.new(1, -16, 1, -16)
toggleButton.BackgroundColor3 = C.Header
toggleButton.Text = "ADMIN"
toggleButton.TextColor3 = C.Text
toggleButton.Font = Enum.Font.FredokaOne
toggleButton.TextSize = 16
toggleButton.Parent = gui
corner(toggleButton, 10)
stroke(toggleButton, C.Accent, 1.5)

local function setOpen(open)
	if open == window.Visible then
		return
	end
	if open then
		window.Visible = true
		scale.Scale = 0.85
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	else
		window.Visible = false
	end
end

toggleButton.MouseButton1Click:Connect(function()
	setOpen(not window.Visible)
end)
closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == TOGGLE_KEY then
		setOpen(not window.Visible)
	end
end)

selectTab("Money")
print("[AdminPanel] ready (F2 or the ADMIN button)")
