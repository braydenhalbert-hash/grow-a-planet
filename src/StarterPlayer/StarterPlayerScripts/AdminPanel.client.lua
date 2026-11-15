--[[
	AdminPanel  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	The admin console. Only staff see it (AdminServer decides, and checks every button again on the server).
	Open / close: F2 or the ADMIN button (bottom-right).

	  Players     search everyone in the server, inspect them, teleport, respawn, kick
	  Items       give / remove ANY seed, planet, pack, sprinkler or gear (the list comes live from the catalogs)
	  Inventory   everything the selected player owns: inventory, garden, placed sprinklers, with remove buttons
	  Spawn       plant planets straight into a garden (any tier and mutations), place sprinklers, mutate gardens
	  Economy     add / remove / set every currency, for one player or everyone
	  World       multipliers (coins, growth, luck, size), mutation events, weather, restock, announcements
	  Moderation  kick, ban (timed or forever), unban, reset a player's data
	  Logs        every admin action in this server
	  Me          walk speed, jump power, god mode, fly

	Type numbers like 5k, 2.5m, 3b, 1t.
	Needs: AdminServer + LiveOps (ServerScriptService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local TOGGLE_KEY = Enum.KeyCode.F2
local FLY_SPEED = 70

---------------------------------------------------------------------
-- Only for staff (the server decides)
---------------------------------------------------------------------
do
	local deadline = os.clock() + 15
	while not player:GetAttribute("IsAdmin") and os.clock() < deadline do
		task.wait(0.25)
	end
	if not player:GetAttribute("IsAdmin") then
		return
	end
end

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local queryRemote = remotes:WaitForChild("AdminQuery", 20)
local commandRemote = remotes:WaitForChild("AdminCommand", 20)
if not queryRemote or not commandRemote then
	warn("[AdminPanel] AdminServer isn't running")
	return
end
local liveState = ReplicatedStorage:WaitForChild("LiveOps", 20)

---------------------------------------------------------------------
-- Look
---------------------------------------------------------------------
local rgb = Color3.fromRGB
local C = {
	BG = rgb(8, 10, 19), Side = rgb(12, 15, 28), Panel = rgb(16, 19, 34), Card = rgb(21, 25, 44),
	Row = rgb(29, 34, 58), Hover = rgb(40, 47, 78), Line = rgb(44, 52, 86),
	Accent = rgb(0, 220, 255), Accent2 = rgb(150, 90, 255),
	Good = rgb(50, 225, 140), Bad = rgb(255, 75, 100), Warn = rgb(255, 190, 60),
	Text = rgb(232, 240, 255), Dim = rgb(125, 140, 175),
}
local FONT, BOLD, HEAVY = Enum.Font.Gotham, Enum.Font.GothamMedium, Enum.Font.GothamBold

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local function corner(p, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end
local function stroke(p, color, thick, transparency)
	return make("UIStroke", { Color = color or C.Line, Thickness = thick or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function pad(p, a, b)
	return make("UIPadding", { PaddingTop = UDim.new(0, a), PaddingBottom = UDim.new(0, a), PaddingLeft = UDim.new(0, b or a), PaddingRight = UDim.new(0, b or a) }, p)
end
local function vlist(p, gap)
	return make("UIListLayout", { Padding = UDim.new(0, gap or 8), SortOrder = Enum.SortOrder.LayoutOrder }, p)
end
local function hlist(p, gap, wrap)
	return make("UIListLayout", { Padding = UDim.new(0, gap or 8), FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
		Wraps = wrap ~= false, VerticalAlignment = Enum.VerticalAlignment.Center }, p)
end
local function tween(o, t, props)
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local function fmt(n)
	if type(n) ~= "number" then
		return tostring(n or "-")
	end
	local units = { "", "K", "M", "B", "T", "Qa", "Qi" }
	local i, v = 1, n
	while math.abs(v) >= 1000 and i < #units do
		v /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(math.floor(v * 100 + 0.5) / 100)
	end
	return string.format("%.2f", v):gsub("%.?0+$", "") .. units[i]
end

local SUFFIX = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15 }
local function parseNumber(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:lower():gsub("[,%s]", "")
	local number, suffix = text:match("^(%-?[%d%.]+)(%a*)$")
	number = tonumber(number)
	if not number then
		return nil
	end
	if suffix ~= "" then
		if not SUFFIX[suffix] then
			return nil
		end
		number *= SUFFIX[suffix]
	end
	return number
end

---------------------------------------------------------------------
-- Boot data (role, permissions, live item database)
---------------------------------------------------------------------
local boot
local function loadBoot()
	local ok, result = pcall(function()
		return queryRemote:InvokeServer("boot")
	end)
	if ok and type(result) == "table" then
		boot = result
	end
	return boot
end
loadBoot()
if not boot then
	warn("[AdminPanel] couldn't load admin data")
	return
end

local function perm(name)
	return boot.Perms and boot.Perms[name] == true
end

local rarityColor = {}
local function indexDb()
	rarityColor = {}
	for _, r in ipairs(boot.Db.Rarities) do
		rarityColor[r.Name] = r.Color
	end
end
indexDb()
local function colorOf(rarity)
	return rarityColor[rarity or ""] or C.Dim
end
local function categoryItems(kind)
	for _, c in ipairs(boot.Db.Categories) do
		if c.Id == kind then
			return c.Items
		end
	end
	return {}
end
local function findItem(kind, id)
	for _, item in ipairs(categoryItems(kind)) do
		if item.Id == id then
			return item
		end
	end
	return nil
end
local function mutationName(id)
	for _, m in ipairs(boot.Db.Mutations) do
		if m.Id == id then
			return m.Name
		end
	end
	return id
end
local function tierName(id)
	for _, t in ipairs(boot.Db.Tiers) do
		if t.Id == id then
			return t.Name
		end
	end
	return id
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
local gui = make("ScreenGui", { Name = "AdminConsole", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

local W, H = 980, 600
local window = make("Frame", { Name = "Window", Size = UDim2.fromOffset(W, H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = C.BG, BorderSizePixel = 0, Visible = false, ClipsDescendants = true }, gui)
corner(window, 14)
local frameStroke = stroke(window, C.Accent, 1.5, 0.2)
make("UIGradient", { Color = ColorSequence.new(C.Accent, C.Accent2), Rotation = 30 }, frameStroke)
local scale = make("UIScale", {}, window)
local function fitScale()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	return math.min(1, (vp.X - 30) / W, (vp.Y - 30) / H)
end

-- subtle grid glow in the background
make("UIGradient", { Color = ColorSequence.new(rgb(14, 18, 34), rgb(8, 10, 19)), Rotation = 90 }, window)

-- top bar
local top = make("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = C.Side, BorderSizePixel = 0 }, window)
make("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = C.Line, BorderSizePixel = 0 }, top)
local logo = make("Frame", { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(16, 11), BackgroundColor3 = C.Accent }, top)
corner(logo, 9)
make("UIGradient", { Color = ColorSequence.new(C.Accent, C.Accent2), Rotation = 45 }, logo)
make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "◆", Font = HEAVY, TextSize = 18, TextColor3 = C.BG }, logo)
make("TextLabel", { Size = UDim2.fromOffset(300, 20), Position = UDim2.fromOffset(60, 9), BackgroundTransparency = 1, Text = "ADMIN CONSOLE",
	Font = HEAVY, TextSize = 17, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left }, top)
make("TextLabel", { Size = UDim2.fromOffset(300, 16), Position = UDim2.fromOffset(60, 30), BackgroundTransparency = 1, Text = "GROW A PLANET  //  CONTROL CENTER",
	Font = BOLD, TextSize = 11, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left }, top)

local roleBadge = make("TextLabel", { Size = UDim2.fromOffset(84, 24), Position = UDim2.fromOffset(250, 16), BackgroundColor3 = C.Accent2, BackgroundTransparency = 0.75,
	Text = string.upper(boot.Role or "STAFF"), Font = HEAVY, TextSize = 11, TextColor3 = C.Text }, top)
corner(roleBadge, 12)
stroke(roleBadge, C.Accent2, 1, 0.3)

-- target chip (who the panel acts on)
local targetChip = make("Frame", { Size = UDim2.fromOffset(300, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 8), BackgroundColor3 = C.Card }, top)
corner(targetChip, 10)
local targetStroke = stroke(targetChip, C.Line)
local targetImage = make("ImageLabel", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = C.Row, Image = "" }, targetChip)
corner(targetImage, 15)
make("TextLabel", { Size = UDim2.new(1, -46, 0, 12), Position = UDim2.fromOffset(42, 5), BackgroundTransparency = 1, Text = "TARGET",
	Font = HEAVY, TextSize = 10, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left }, targetChip)
local targetName = make("TextLabel", { Size = UDim2.new(1, -46, 0, 18), Position = UDim2.fromOffset(42, 17), BackgroundTransparency = 1, Text = "No player selected",
	Font = BOLD, TextSize = 14, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, targetChip)

local closeButton = make("TextButton", { Size = UDim2.fromOffset(36, 36), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), BackgroundColor3 = C.Card,
	Text = "X", Font = HEAVY, TextSize = 16, TextColor3 = C.Dim, AutoButtonColor = false }, top)
corner(closeButton, 10)

-- sidebar
local side = make("Frame", { Size = UDim2.new(0, 186, 1, -56), Position = UDim2.fromOffset(0, 56), BackgroundColor3 = C.Side, BorderSizePixel = 0 }, window)
make("Frame", { Size = UDim2.new(0, 1, 1, -56), Position = UDim2.fromOffset(185, 56), BackgroundColor3 = C.Line, BorderSizePixel = 0, ZIndex = 2 }, window)
pad(side, 12, 10)
vlist(side, 4)

-- content
local content = make("Frame", { Size = UDim2.new(1, -186, 1, -56 - 36), Position = UDim2.fromOffset(186, 56), BackgroundTransparency = 1 }, window)

-- status bar (results of every action)
local statusBar = make("Frame", { Size = UDim2.new(1, -186, 0, 36), Position = UDim2.new(0, 186, 1, -36), BackgroundColor3 = C.Side, BorderSizePixel = 0 }, window)
make("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Line, BorderSizePixel = 0 }, statusBar)
local statusDot = make("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 16, 0.5, -4), BackgroundColor3 = C.Good }, statusBar)
corner(statusDot, 4)
local statusText = make("TextLabel", { Size = UDim2.new(1, -200, 1, 0), Position = UDim2.fromOffset(32, 0), BackgroundTransparency = 1, Text = "Ready.",
	Font = BOLD, TextSize = 13, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, statusBar)
local serverText = make("TextLabel", { Size = UDim2.fromOffset(170, 36), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), BackgroundTransparency = 1,
	Text = "", Font = FONT, TextSize = 11, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Right }, statusBar)

local function say(text, kind)
	local color = kind == "bad" and C.Bad or (kind == "warn" and C.Warn or (kind == "good" and C.Good or C.Dim))
	statusText.Text = text
	statusText.TextColor3 = kind and color or C.Dim
	statusDot.BackgroundColor3 = color
	statusDot.Size = UDim2.fromOffset(14, 14)
	statusDot.Position = UDim2.new(0, 13, 0.5, -7)
	tween(statusDot, 0.4, { Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 16, 0.5, -4) })
end

---------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------
local function hover(b, base, over)
	b.MouseEnter:Connect(function()
		tween(b, 0.15, { BackgroundColor3 = over })
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.2, { BackgroundColor3 = base() })
	end)
end

local STYLE = {
	primary = { Bg = C.Accent, Text = C.BG },
	violet = { Bg = C.Accent2, Text = C.Text },
	good = { Bg = C.Good, Text = C.BG },
	bad = { Bg = C.Bad, Text = C.Text },
	ghost = { Bg = C.Row, Text = C.Text },
}

local function button(parent, text, style, onClick, width, height)
	local s = STYLE[style or "ghost"]
	local b = make("TextButton", { Size = UDim2.fromOffset(width or 120, height or 32), BackgroundColor3 = s.Bg, Text = text, Font = HEAVY, TextSize = 12,
		TextColor3 = s.Text, AutoButtonColor = false, TextTruncate = Enum.TextTruncate.AtEnd }, parent)
	corner(b, 8)
	if style == "ghost" or style == nil then
		stroke(b, C.Line)
	end
	local baseColor = s.Bg
	hover(b, function()
		return baseColor
	end, baseColor:Lerp(Color3.new(1, 1, 1), 0.18))
	local baseSize = b.Size
	b.MouseButton1Click:Connect(function()
		b.Size = baseSize - UDim2.fromOffset(4, 2)
		tween(b, 0.2, { Size = baseSize })
		if onClick then
			onClick()
		end
	end)
	return b
end

local function input(parent, placeholder, width, default)
	local box = make("TextBox", { Size = UDim2.fromOffset(width or 140, 32), BackgroundColor3 = C.BG, Text = default or "", PlaceholderText = placeholder or "",
		PlaceholderColor3 = C.Dim, Font = BOLD, TextSize = 13, TextColor3 = C.Text, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, parent)
	corner(box, 8)
	local s = stroke(box, C.Line)
	pad(box, 0, 10)
	box.Focused:Connect(function()
		tween(s, 0.15, { Color = C.Accent })
	end)
	box.FocusLost:Connect(function()
		tween(s, 0.2, { Color = C.Line })
	end)
	return box
end

local function text(parent, str, size, color, font, height)
	return make("TextLabel", { Size = UDim2.new(1, 0, 0, height or (size or 13) + 6), BackgroundTransparency = 1, Text = str, Font = font or BOLD, TextSize = size or 13,
		TextColor3 = color or C.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, RichText = true }, parent)
end

local function row(parent, gap)
	local f = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, parent)
	hlist(f, gap or 8)
	return f
end

local function scroller(parent, size, position)
	local s = make("ScrollingFrame", { Size = size or UDim2.fromScale(1, 1), Position = position or UDim2.new(), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageColor3 = C.Accent, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y }, parent)
	return s
end

local function card(parent, title, subtitle)
	local f = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Card }, parent)
	corner(f, 12)
	stroke(f, C.Line, 1, 0.3)
	pad(f, 14)
	vlist(f, 10)
	if title then
		local head = make("Frame", { Size = UDim2.new(1, 0, 0, subtitle and 34 or 18), BackgroundTransparency = 1, LayoutOrder = -100 }, f)
		make("Frame", { Size = UDim2.fromOffset(3, 14), Position = UDim2.fromOffset(0, 2), BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, head)
		make("TextLabel", { Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1, Text = string.upper(title), Font = HEAVY,
			TextSize = 13, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left }, head)
		if subtitle then
			make("TextLabel", { Size = UDim2.new(1, -12, 0, 14), Position = UDim2.fromOffset(10, 19), BackgroundTransparency = 1, Text = subtitle, Font = FONT,
				TextSize = 11, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, head)
		end
	end
	return f
end

-- a row of selectable chips. options = { {Id, Name, Color} }. multi = several at once.
local function chips(parent, options, multi, onChange, initial)
	local holder = row(parent, 6)
	local selected = {}
	local buttons = {}
	local api = {}
	local function paint()
		for id, b in pairs(buttons) do
			local on = selected[id] == true
			tween(b, 0.15, { BackgroundColor3 = on and C.Hover or C.BG })
			b.UIStroke.Color = on and (b:GetAttribute("Tint") and Color3.fromHex(b:GetAttribute("Tint")) or C.Accent) or C.Line
			b.UIStroke.Thickness = on and 1.5 or 1
		end
	end
	function api.Get()
		if multi then
			local list = {}
			for id, on in pairs(selected) do
				if on then
					table.insert(list, id)
				end
			end
			return list
		end
		for id, on in pairs(selected) do
			if on then
				return id
			end
		end
		return nil
	end
	function api.Set(id)
		if not multi then
			table.clear(selected)
		end
		if id ~= nil then
			selected[id] = true
		end
		paint()
	end
	function api.Clear()
		table.clear(selected)
		paint()
	end
	function api.Build(list)
		for _, b in pairs(buttons) do
			b:Destroy()
		end
		table.clear(buttons)
		for i, o in ipairs(list) do
			local b = make("TextButton", { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.BG, Text = o.Name, Font = BOLD,
				TextSize = 12, TextColor3 = o.Color or C.Text, AutoButtonColor = false, LayoutOrder = i }, holder)
			if o.Color then
				b:SetAttribute("Tint", o.Color:ToHex())
			end
			corner(b, 13)
			stroke(b, C.Line)
			pad(b, 0, 11)
			b.MouseButton1Click:Connect(function()
				if multi then
					selected[o.Id] = not selected[o.Id] or nil
				else
					local was = selected[o.Id]
					table.clear(selected)
					selected[o.Id] = not was or (initial ~= nil) or nil
				end
				paint()
				if onChange then
					onChange(api.Get())
				end
			end)
			buttons[o.Id] = b
		end
		paint()
	end
	api.Frame = holder
	api.Build(options)
	if initial ~= nil then
		api.Set(initial)
	end
	return api
end

local function clearChildren(frame, keepLayouts)
	for _, child in ipairs(frame:GetChildren()) do
		if not (keepLayouts and child:IsA("UIComponent")) then
			child:Destroy()
		end
	end
end

-- a list row: coloured bar, title, subtitle, and room for buttons on the right
local function itemRow(parent, title, subtitle, color, order)
	local f = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.Row, LayoutOrder = order or 0 }, parent)
	corner(f, 8)
	make("Frame", { Size = UDim2.new(0, 3, 1, -14), Position = UDim2.fromOffset(6, 7), BackgroundColor3 = color or C.Accent, BorderSizePixel = 0 }, f)
	make("TextLabel", { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(16, 5), BackgroundTransparency = 1, Text = title, Font = BOLD, TextSize = 13,
		TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, Name = "Title" }, f)
	make("TextLabel", { Size = UDim2.new(1, -20, 0, 14), Position = UDim2.fromOffset(16, 24), BackgroundTransparency = 1, Text = subtitle or "", Font = FONT, TextSize = 11,
		TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, Name = "Sub" }, f)
	local right = make("Frame", { Size = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, Name = "Right" }, f)
	local l = hlist(right, 5, false)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	return f, right
end

local function emptyNote(parent, str)
	local t = text(parent, str, 12, C.Dim, FONT)
	t.TextXAlignment = Enum.TextXAlignment.Center
	return t
end

---------------------------------------------------------------------
-- Server calls
---------------------------------------------------------------------
local refreshers = {} -- run after every command so every page shows the new state

local busy = false
local function run(action, payload, after)
	if busy then
		say("Working...", "warn")
		return
	end
	busy = true
	say("Working...", "warn")
	task.spawn(function()
		local ok, success, message = pcall(function()
			return commandRemote:InvokeServer(action, payload)
		end)
		busy = false
		if not ok then
			say("The server didn't answer", "bad")
			return
		end
		say(message or (success and "Done" or "Failed"), success and "good" or "bad")
		if after then
			after(success)
		end
		for _, fn in pairs(refreshers) do
			task.spawn(fn)
		end
	end)
end

local function query(kind, arg)
	local ok, result = pcall(function()
		return queryRemote:InvokeServer(kind, arg)
	end)
	return ok and result or nil
end

---------------------------------------------------------------------
-- Target player
---------------------------------------------------------------------
local target = nil -- userId
local targetListeners = {}
local function targetPlayer()
	return target and Players:GetPlayerByUserId(target)
end
local function setTarget(userId)
	target = userId
	local p = targetPlayer()
	if p then
		targetName.Text = p.DisplayName .. "  <font color=\"#7d8caf\">@" .. p.Name .. "</font>"
		targetName.RichText = true
		targetStroke.Color = C.Accent
		task.spawn(function()
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			end)
			if ok and target == userId then
				targetImage.Image = image
			end
		end)
	else
		target = nil
		targetName.Text = "No player selected"
		targetStroke.Color = C.Line
		targetImage.Image = ""
	end
	for _, fn in ipairs(targetListeners) do
		task.spawn(fn)
	end
end
Players.PlayerRemoving:Connect(function(p)
	if p.UserId == target then
		setTarget(nil)
	end
end)

local function needTarget()
	if not targetPlayer() then
		say("Select a player first (Players tab)", "warn")
		return nil
	end
	return target
end

-- "Selected player / Everyone" switch used by Items and Economy
local function scopeSwitch(parent)
	local api = { All = false }
	local holder = row(parent, 6)
	text(holder, "SEND TO", 11, C.Dim, HEAVY).Size = UDim2.fromOffset(60, 26)
	local c = chips(holder, { { Id = "one", Name = "Selected player" }, { Id = "all", Name = "Everyone in server" } }, false, function(v)
		api.All = v == "all"
	end, "one")
	function api.Target()
		if api.All then
			return "all"
		end
		return needTarget()
	end
	api.Chips = c
	return api
end

---------------------------------------------------------------------
-- Pages + sidebar
---------------------------------------------------------------------
local pages, tabButtons, order = {}, {}, 0
local currentPage

local function page(name, icon, permission)
	if permission and not perm(permission) then
		return nil
	end
	order += 1
	local f = make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
	local b = make("TextButton", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.Side, Text = "", AutoButtonColor = false, LayoutOrder = order }, side)
	corner(b, 9)
	local bar = make("Frame", { Size = UDim2.fromOffset(3, 18), Position = UDim2.new(0, 0, 0.5, -9), BackgroundColor3 = C.Accent, BackgroundTransparency = 1, BorderSizePixel = 0 }, b)
	corner(bar, 2)
	make("TextLabel", { Size = UDim2.fromOffset(26, 38), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1, Text = icon, Font = HEAVY, TextSize = 16,
		TextColor3 = C.Dim, Name = "Icon" }, b)
	make("TextLabel", { Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(42, 0), BackgroundTransparency = 1, Text = name, Font = BOLD, TextSize = 14,
		TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Name = "Label" }, b)
	pages[name] = { Frame = f, Button = b, Bar = bar }
	b.MouseEnter:Connect(function()
		if currentPage ~= name then
			tween(b, 0.15, { BackgroundColor3 = C.Card })
		end
	end)
	b.MouseLeave:Connect(function()
		if currentPage ~= name then
			tween(b, 0.2, { BackgroundColor3 = C.Side })
		end
	end)
	tabButtons[name] = b
	return f
end

local function showPage(name)
	if not pages[name] then
		return
	end
	currentPage = name
	for n, p in pairs(pages) do
		local on = n == name
		p.Frame.Visible = on
		tween(p.Button, 0.2, { BackgroundColor3 = on and C.Card or C.Side })
		tween(p.Bar, 0.2, { BackgroundTransparency = on and 0 or 1 })
		p.Button.Icon.TextColor3 = on and C.Accent or C.Dim
		p.Button.Label.TextColor3 = on and C.Text or C.Dim
	end
	if pages[name].OnShow then
		task.spawn(pages[name].OnShow)
	end
end

local function standardPage(f)
	local s = scroller(f, UDim2.new(1, -24, 1, -20), UDim2.fromOffset(12, 10))
	vlist(s, 12)
	pad(s, 2, 4)
	return s
end

---------------------------------------------------------------------
-- PLAYERS
---------------------------------------------------------------------
local playersPage = page("Players", "◉", "view")
local inspectData = nil
local refreshInspect

do
	local left = make("Frame", { Size = UDim2.new(0, 290, 1, -20), Position = UDim2.fromOffset(12, 10), BackgroundColor3 = C.Panel }, playersPage)
	corner(left, 12)
	stroke(left, C.Line, 1, 0.3)
	local search = input(left, "Search players...", 266)
	search.Position = UDim2.fromOffset(12, 12)
	local countLabel = make("TextLabel", { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 50), BackgroundTransparency = 1, Text = "",
		Font = HEAVY, TextSize = 10, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left }, left)
	local list = scroller(left, UDim2.new(1, -16, 1, -76), UDim2.fromOffset(8, 70))
	vlist(list, 4)

	local right = scroller(playersPage, UDim2.new(1, -326, 1, -20), UDim2.fromOffset(314, 10))
	vlist(right, 12)
	pad(right, 0, 4)

	local playerList = {}
	local function drawList()
		clearChildren(list, true)
		local q = search.Text:lower()
		local shown = 0
		for i, p in ipairs(playerList) do
			if q == "" or p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true) then
				shown += 1
				local f = make("TextButton", { Size = UDim2.new(1, -4, 0, 50), BackgroundColor3 = p.UserId == target and C.Hover or C.Row, Text = "", AutoButtonColor = false, LayoutOrder = i }, list)
				corner(f, 9)
				if p.UserId == target then
					stroke(f, C.Accent, 1)
				end
				local img = make("ImageLabel", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = C.BG }, f)
				corner(img, 18)
				task.spawn(function()
					local ok, image = pcall(function()
						return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
					end)
					if ok then
						img.Image = image
					end
				end)
				make("TextLabel", { Size = UDim2.new(1, -60, 0, 18), Position = UDim2.fromOffset(52, 7), BackgroundTransparency = 1, Text = p.DisplayName .. (p.Role and ("  <font color=\"#9a5aff\">" .. string.upper(p.Role) .. "</font>") or ""),
					RichText = true, Font = BOLD, TextSize = 13, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, f)
				make("TextLabel", { Size = UDim2.new(1, -60, 0, 14), Position = UDim2.fromOffset(52, 27), BackgroundTransparency = 1, Text = "@" .. p.Name .. "  ·  " .. fmt(p.Coins) .. " coins",
					Font = FONT, TextSize = 11, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, f)
				f.MouseButton1Click:Connect(function()
					setTarget(p.UserId)
					drawList()
				end)
			end
		end
		countLabel.Text = string.format("%d / %d PLAYERS ONLINE", shown, #playerList)
		if shown == 0 then
			emptyNote(list, "No players match")
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(drawList)

	local function refreshList()
		local result = query("players")
		if type(result) == "table" then
			table.sort(result, function(a, b)
				return a.Name:lower() < b.Name:lower()
			end)
			playerList = result
			drawList()
		end
	end

	local function stat(parent, label, value, color)
		local f = make("Frame", { Size = UDim2.fromOffset(150, 58), BackgroundColor3 = C.Row }, parent)
		corner(f, 10)
		make("TextLabel", { Size = UDim2.new(1, -20, 0, 14), Position = UDim2.fromOffset(10, 9), BackgroundTransparency = 1, Text = string.upper(label), Font = HEAVY,
			TextSize = 10, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left }, f)
		make("TextLabel", { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 26), BackgroundTransparency = 1, Text = value, Font = HEAVY,
			TextSize = 19, TextColor3 = color or C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, f)
	end

	local function drawInspect()
		clearChildren(right, true)
		local d = inspectData
		local p = targetPlayer()
		if not p or not d then
			local c = card(right, "Inspector", "Pick a player on the left to see everything about them")
			emptyNote(c, "No player selected")
			return
		end
		local head = card(right, p.DisplayName, "@" .. p.Name .. "  ·  UserId " .. p.UserId .. "  ·  Account age " .. (d.Age or 0) .. " days" .. (d.Role and ("  ·  " .. d.Role) or ""))
		local stats = row(head, 8)
		for _, field in ipairs(boot.Db.Currencies) do
			stat(stats, field, fmt(d.Currencies and d.Currencies[field] or 0), C.Warn)
		end
		local inv = d.Inventory or { Seeds = {}, Packs = {}, Gear = {}, Planets = {} }
		local function total(t)
			local n = 0
			for _, v in pairs(t or {}) do
				n += v
			end
			return n
		end
		stat(stats, "Seeds", fmt(total(inv.Seeds)))
		stat(stats, "Packs", fmt(total(inv.Packs)))
		stat(stats, "Gear", fmt(total(inv.Gear)))
		stat(stats, "Planets held", fmt(#(inv.Planets or {})))
		stat(stats, "Garden", fmt(#(d.Garden or {})), C.Good)
		stat(stats, "Sprinklers", fmt(#(d.Sprinklers or {})), C.Accent)
		stat(stats, "Base", d.HasBase and "Claimed" or "None", d.HasBase and C.Good or C.Dim)
		if not d.Loaded then
			text(head, "⚠ Their data hasn't loaded yet", 12, C.Warn)
		end

		local actions = card(right, "Quick actions")
		local r1 = row(actions, 8)
		if perm("teleport") then
			button(r1, "Go to them", "primary", function()
				run("teleport", { Target = p.UserId, Mode = "goto" })
			end)
			button(r1, "Bring here", "ghost", function()
				run("teleport", { Target = p.UserId, Mode = "bring" })
			end)
			button(r1, "Send to base", "ghost", function()
				run("teleport", { Target = p.UserId, Mode = "base" })
			end)
			button(r1, "Respawn", "ghost", function()
				run("respawn", { Target = p.UserId })
			end)
		end
		local r2 = row(actions, 8)
		if perm("items") then
			button(r2, "Open inventory", "violet", function()
				showPage("Inventory")
			end)
			button(r2, "Give items", "ghost", function()
				showPage("Items")
			end)
		end
		if perm("economy") then
			button(r2, "Economy", "ghost", function()
				showPage("Economy")
			end)
		end
		if perm("kick") then
			button(r2, "Moderate", "bad", function()
				showPage("Moderation")
			end)
		end
	end

	refreshInspect = function()
		if target then
			inspectData = query("inspect", target)
		else
			inspectData = nil
		end
		if currentPage == "Players" then
			drawInspect()
		end
	end
	table.insert(targetListeners, refreshInspect)
	refreshers.players = function()
		if currentPage == "Players" then
			refreshList()
			refreshInspect()
		end
	end

	pages.Players.OnShow = function()
		refreshList()
		refreshInspect()
	end
	Players.PlayerAdded:Connect(function()
		if currentPage == "Players" and window.Visible then
			refreshList()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if currentPage == "Players" and window.Visible then
			task.wait(0.2)
			refreshList()
		end
	end)
end

---------------------------------------------------------------------
-- ITEMS  (give / remove anything, list comes from the live database)
---------------------------------------------------------------------
local itemsPage = page("Items", "◈", "items")
if itemsPage then
	local left = make("Frame", { Size = UDim2.new(0, 380, 1, -20), Position = UDim2.fromOffset(12, 10), BackgroundColor3 = C.Panel }, itemsPage)
	corner(left, 12)
	stroke(left, C.Line, 1, 0.3)
	local filters = make("Frame", { Size = UDim2.new(1, -24, 0, 0), Position = UDim2.fromOffset(12, 12), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, left)
	vlist(filters, 8)
	local search = input(filters, "Search items...", 356)

	local kind = "Seed"
	local rarityFilter = nil
	local selectedItem = nil
	local drawItems, drawDetail

	local catOptions = {}
	for _, c in ipairs(boot.Db.Categories) do
		table.insert(catOptions, { Id = c.Id, Name = c.Name .. " (" .. #c.Items .. ")" })
	end
	chips(filters, catOptions, false, function(v)
		kind = v or "Seed"
		selectedItem = nil
		drawItems()
		drawDetail()
	end, "Seed")

	local rarityOptions = {}
	for _, r in ipairs(boot.Db.Rarities) do
		table.insert(rarityOptions, { Id = r.Name, Name = r.Name, Color = r.Color })
	end
	chips(filters, rarityOptions, false, function(v)
		rarityFilter = v
		drawItems()
	end)

	local list = scroller(left, UDim2.new(1, -16, 1, -150), UDim2.fromOffset(8, 142))
	vlist(list, 4)
	local function placeList()
		local h = filters.AbsoluteSize.Y / math.max(scale.Scale, 0.01) + 22
		list.Position = UDim2.fromOffset(8, h)
		list.Size = UDim2.new(1, -16, 1, -h - 8)
	end
	filters:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeList)
	scale:GetPropertyChangedSignal("Scale"):Connect(placeList)

	local right = scroller(itemsPage, UDim2.new(1, -416, 1, -20), UDim2.fromOffset(404, 10))
	vlist(right, 12)
	pad(right, 0, 4)

	drawItems = function()
		clearChildren(list, true)
		local q = search.Text:lower()
		local shown = 0
		for i, item in ipairs(categoryItems(kind)) do
			if (not rarityFilter or item.Rarity == rarityFilter) and (q == "" or item.Name:lower():find(q, 1, true) or item.Id:lower():find(q, 1, true)) then
				shown += 1
				if shown <= 250 then
					local f = itemRow(list, item.Name .. "  <font color=\"#" .. colorOf(item.Rarity):ToHex() .. "\">" .. (item.Rarity or "") .. "</font>", item.Info, colorOf(item.Rarity), i)
					if selectedItem == item then
						f.BackgroundColor3 = C.Hover
						stroke(f, C.Accent, 1)
					end
					local hit = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, f)
					hit.MouseButton1Click:Connect(function()
						selectedItem = item
						drawItems()
						drawDetail()
					end)
				end
			end
		end
		if shown == 0 then
			emptyNote(list, "Nothing matches")
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(drawItems)

	drawDetail = function()
		clearChildren(right, true)
		local item = selectedItem
		if not item then
			local c = card(right, "Item database", "Every item in the game, read live from the catalogs")
			local counts = {}
			for _, cat in ipairs(boot.Db.Categories) do
				table.insert(counts, cat.Name .. ": <b>" .. #cat.Items .. "</b>")
			end
			table.insert(counts, "Mutations: <b>" .. #boot.Db.Mutations .. "</b>")
			table.insert(counts, "Rarities: <b>" .. #boot.Db.Rarities .. "</b>")
			text(c, table.concat(counts, "   ·   "), 13, C.Text)
			text(c, "New seeds, planets, packs, sprinklers, gear, mutations and rarities you add to the catalogs show up here automatically. Pick an item on the left to give or remove it.", 12, C.Dim, FONT)
			button(c, "Reload database", "ghost", function()
				loadBoot()
				indexDb()
				say("Database reloaded: " .. #categoryItems("Seed") .. " seeds, " .. #categoryItems("Gear") .. " gear", "good")
				drawItems()
				drawDetail()
			end, 150)
			return
		end

		local head = card(right, item.Name, (item.Rarity or "") .. "  ·  " .. kind .. "  ·  id: " .. item.Id)
		text(head, item.Info or "", 12, C.Dim, FONT)

		local give = card(right, "Give", "Goes straight into their inventory")
		local scope = scopeSwitch(give)
		local r = row(give, 8)
		local amount = input(r, "Amount (5, 10k...)", 150, "1")
		for _, n in ipairs({ 1, 10, 100, 1000 }) do
			button(r, "×" .. fmt(n), "ghost", function()
				amount.Text = tostring(n)
			end, 56)
		end

		local tierChips, mutChips, weightBox
		if kind == "Planet" then
			text(give, "SIZE", 11, C.Dim, HEAVY)
			local tierOptions = {}
			for _, t in ipairs(boot.Db.Tiers) do
				table.insert(tierOptions, { Id = t.Id, Name = t.Name, Color = t.Color })
			end
			tierChips = chips(give, tierOptions, false)
			text(give, "MUTATIONS", 11, C.Dim, HEAVY)
			local mutOptions = {}
			for _, m in ipairs(boot.Db.Mutations) do
				table.insert(mutOptions, { Id = m.Id, Name = m.Name })
			end
			mutChips = chips(give, mutOptions, true)
			local wr = row(give, 8)
			text(wr, "WEIGHT (kg, blank = random)", 11, C.Dim, HEAVY).Size = UDim2.fromOffset(190, 26)
			weightBox = input(wr, "random", 120)
		end

		button(give, "GIVE " .. string.upper(item.Name), "primary", function()
			local t = scope.Target()
			local n = parseNumber(amount.Text)
			if not t then
				return
			end
			if not n or n < 1 then
				say("Enter an amount", "warn")
				return
			end
			run("give", {
				Target = t, Kind = kind, Id = item.Id, Amount = math.floor(n),
				Tier = tierChips and tierChips.Get() or nil, Mutations = mutChips and mutChips.Get() or nil,
				Weight = weightBox and parseNumber(weightBox.Text) or nil,
			})
		end, 260, 38)

		local remove = card(right, "Remove", kind == "Planet" and "Removes every held planet of this type from the selected player" or "Takes it out of the selected player's inventory")
		local rr = row(remove, 8)
		local removeAmount
		if kind ~= "Planet" then
			removeAmount = input(rr, "Amount", 120, "1")
		end
		button(rr, kind == "Planet" and "Remove all of these" or "Remove", "bad", function()
			local t = needTarget()
			if not t then
				return
			end
			local n = removeAmount and parseNumber(removeAmount.Text)
			if removeAmount and (not n or n < 1) then
				say("Enter an amount", "warn")
				return
			end
			run("remove", { Target = t, Kind = kind, Id = item.Id, Amount = n and math.floor(n) or "all" })
		end, 160)
		if kind ~= "Planet" then
			button(rr, "Remove all", "ghost", function()
				local t = needTarget()
				if t then
					run("remove", { Target = t, Kind = kind, Id = item.Id, Amount = "all" })
				end
			end, 110)
		end

		if kind == "Planet" and perm("items") then
			local plant = card(right, "Spawn in garden", "Plant it straight into the selected player's garden (Spawn tab has more options)")
			button(plant, "Plant 1 (fully grown)", "violet", function()
				local t = needTarget()
				if t then
					run("spawn_plant", { Target = t, Id = item.Id, Count = 1, Grown = true, Tier = tierChips and tierChips.Get(), Mutations = mutChips and mutChips.Get() })
				end
			end, 200)
		elseif kind == "Gear" and item.Placeable then
			local place = card(right, "Place in base", "Puts a running sprinkler in the selected player's base")
			button(place, "Place 1 now", "violet", function()
				local t = needTarget()
				if t then
					run("sprinkler_spawn", { Target = t, Id = item.Id, Count = 1 })
				end
			end, 160)
		end
	end

	pages.Items.OnShow = function()
		task.defer(placeList)
		drawItems()
		drawDetail()
	end
end

---------------------------------------------------------------------
-- INVENTORY  (what the selected player owns, with remove buttons)
---------------------------------------------------------------------
local invPage = page("Inventory", "▤", "items")
if invPage then
	local body = standardPage(invPage)
	local function draw()
		clearChildren(body, true)
		local p = targetPlayer()
		local d = p and query("inspect", target)
		if not p or not d then
			local c = card(body, "Inventory", "Select a player on the Players tab")
			emptyNote(c, "No player selected")
			return
		end
		local inv = d.Inventory or { Seeds = {}, Packs = {}, Gear = {}, Planets = {} }

		local top = card(body, p.DisplayName .. "'s things", "Changes save to their data instantly")
		local r = row(top, 8)
		button(r, "Clear seeds", "ghost", function()
			run("clear_inventory", { Target = target, Kind = "Seed" })
		end, 110)
		button(r, "Clear packs", "ghost", function()
			run("clear_inventory", { Target = target, Kind = "Pack" })
		end, 110)
		button(r, "Clear gear", "ghost", function()
			run("clear_inventory", { Target = target, Kind = "Gear" })
		end, 110)
		button(r, "Clear held planets", "ghost", function()
			run("clear_inventory", { Target = target, Kind = "Planet" })
		end, 150)
		button(r, "Clear EVERYTHING", "bad", function()
			run("clear_inventory", { Target = target, Kind = "all" })
		end, 150)

		local function section(title, map, kind)
			local entries = {}
			for id, count in pairs(map or {}) do
				if count > 0 then
					table.insert(entries, { Id = id, Count = count, Item = findItem(kind, id) })
				end
			end
			table.sort(entries, function(a, b)
				return (a.Item and a.Item.Name or a.Id) < (b.Item and b.Item.Name or b.Id)
			end)
			local c = card(body, title .. "  (" .. #entries .. ")")
			if #entries == 0 then
				emptyNote(c, "None")
			end
			for i, e in ipairs(entries) do
				local name = e.Item and e.Item.Name or e.Id
				local rarity = e.Item and e.Item.Rarity
				local _, right = itemRow(c, name .. "  <font color=\"#ffbe3c\">×" .. fmt(e.Count) .. "</font>", rarity or "", colorOf(rarity), i)
				for _, n in ipairs({ 1, 10 }) do
					button(right, "−" .. n, "ghost", function()
						run("remove", { Target = target, Kind = kind, Id = e.Id, Amount = n })
					end, 44, 28)
				end
				button(right, "+1", "ghost", function()
					run("give", { Target = target, Kind = kind, Id = e.Id, Amount = 1 })
				end, 44, 28)
				button(right, "All", "bad", function()
					run("remove", { Target = target, Kind = kind, Id = e.Id, Amount = "all" })
				end, 44, 28)
			end
		end
		section("Seeds", inv.Seeds, "Seed")
		section("Packs", inv.Packs, "Pack")
		section("Gear & sprinklers (in inventory)", inv.Gear, "Gear")

		local held = card(body, "Held planets  (" .. #(inv.Planets or {}) .. ")", "Harvested planets in their hotbar")
		if #(inv.Planets or {}) == 0 then
			emptyNote(held, "None")
		end
		for i, pl in ipairs(inv.Planets or {}) do
			local muts = {}
			for _, m in ipairs(pl.Mutations or {}) do
				table.insert(muts, mutationName(m))
			end
			local sub = string.format("%s kg%s%s", tostring(pl.Weight and (math.floor(pl.Weight * 100) / 100) or "?"),
				pl.Tier and ("  ·  " .. tierName(pl.Tier)) or "", #muts > 0 and ("  ·  " .. table.concat(muts, ", ")) or "")
			local _, right = itemRow(held, pl.Name .. "  <font color=\"#" .. colorOf(pl.Rarity):ToHex() .. "\">" .. (pl.Rarity or "") .. "</font>", sub, colorOf(pl.Rarity), i)
			button(right, "Remove", "bad", function()
				run("remove_planet", { Target = target, Index = pl.Index })
			end, 70, 28)
		end

		local garden = card(body, "Garden  (" .. #(d.Garden or {}) .. " planted)", "Planets growing in their base")
		local gr = row(garden, 8)
		button(gr, "Grow all now", "good", function()
			run("garden_grow", { Target = target, Key = "all" })
		end, 120)
		button(gr, "Harvest all", "ghost", function()
			run("garden_harvest", { Target = target })
		end, 110)
		button(gr, "Remove all", "bad", function()
			run("garden_remove", { Target = target, Key = "all" })
		end, 110)
		if #(d.Garden or {}) == 0 then
			emptyNote(garden, "Nothing planted")
		end
		for i, pl in ipairs(d.Garden or {}) do
			local muts = {}
			for _, m in ipairs(pl.Mutations or {}) do
				table.insert(muts, mutationName(m))
			end
			local sub = (pl.Ready and "<font color=\"#32e18c\">Ready</font>" or (math.floor((pl.Progress or 0) * 100) .. "% grown"))
				.. (pl.Tier and ("  ·  " .. tierName(pl.Tier)) or "") .. (#muts > 0 and ("  ·  " .. table.concat(muts, ", ")) or "")
			local _, right = itemRow(garden, pl.Name .. "  <font color=\"#" .. colorOf(pl.Rarity):ToHex() .. "\">" .. (pl.Rarity or "") .. "</font>", sub, colorOf(pl.Rarity), i)
			if not pl.Ready then
				button(right, "Grow", "good", function()
					run("garden_grow", { Target = target, Key = pl.Key })
				end, 56, 28)
			end
			button(right, "Remove", "bad", function()
				run("garden_remove", { Target = target, Key = pl.Key })
			end, 70, 28)
		end

		local spr = card(body, "Placed sprinklers  (" .. #(d.Sprinklers or {}) .. ")", "Running in their base")
		if #(d.Sprinklers or {}) > 0 then
			button(spr, "Remove all sprinklers", "bad", function()
				run("sprinkler_remove", { Target = target, Key = "all" })
			end, 180)
		else
			emptyNote(spr, "None placed")
		end
		for i, s in ipairs(d.Sprinklers or {}) do
			local left = s.Left and (math.floor(s.Left / 60) .. "m " .. math.floor(s.Left % 60) .. "s left") or ""
			local _, right = itemRow(spr, s.Name .. "  <font color=\"#" .. colorOf(s.Rarity):ToHex() .. "\">" .. (s.Rarity or "") .. "</font>", left, colorOf(s.Rarity), i)
			button(right, "Remove", "bad", function()
				run("sprinkler_remove", { Target = target, Key = s.Key })
			end, 70, 28)
		end
	end
	pages.Inventory.OnShow = draw
	refreshers.inventory = function()
		if currentPage == "Inventory" then
			draw()
		end
	end
	table.insert(targetListeners, refreshers.inventory)
end

---------------------------------------------------------------------
-- SPAWN  (garden + base)
---------------------------------------------------------------------
local spawnPage = page("Spawn", "+", "items")
if spawnPage then
	local body = standardPage(spawnPage)

	-- plant planets
	local plant = card(body, "Plant planets in a garden", "Straight onto the selected player's base, any size and mutations")
	local search = input(plant, "Search planets...", 300)
	local planetChips = chips(plant, {}, false)
	local function buildPlanetChips()
		local q = search.Text:lower()
		local opts = {}
		for _, item in ipairs(categoryItems("Planet")) do
			if q == "" or item.Name:lower():find(q, 1, true) then
				table.insert(opts, { Id = item.Id, Name = item.Name, Color = colorOf(item.Rarity) })
				if #opts >= 60 then
					break
				end
			end
		end
		planetChips.Build(opts)
	end
	search:GetPropertyChangedSignal("Text"):Connect(buildPlanetChips)
	buildPlanetChips()
	text(plant, "SIZE", 11, C.Dim, HEAVY)
	local tierOptions = {}
	for _, t in ipairs(boot.Db.Tiers) do
		table.insert(tierOptions, { Id = t.Id, Name = t.Name, Color = t.Color })
	end
	local tierChips = chips(plant, tierOptions, false)
	text(plant, "MUTATIONS", 11, C.Dim, HEAVY)
	local mutOptions = {}
	for _, m in ipairs(boot.Db.Mutations) do
		table.insert(mutOptions, { Id = m.Id, Name = m.Name })
	end
	local mutChips = chips(plant, mutOptions, true)
	local pr = row(plant, 8)
	local count = input(pr, "How many (1-25)", 130, "1")
	local grownChips = chips(pr, { { Id = "grown", Name = "Fully grown" }, { Id = "seed", Name = "Just planted" } }, false, nil, "grown")
	_ = grownChips
	button(plant, "PLANT", "primary", function()
		local t = needTarget()
		local id = planetChips.Get()
		if not t then
			return
		end
		if not id then
			say("Pick a planet", "warn")
			return
		end
		run("spawn_plant", { Target = t, Id = id, Tier = tierChips.Get(), Mutations = mutChips.Get(), Count = parseNumber(count.Text) or 1, Grown = grownChips.Get() ~= "seed" })
	end, 200, 38)

	-- place sprinklers
	local spr = card(body, "Place sprinklers", "Running sprinklers at free spots in the selected player's base")
	local sprOptions = {}
	for _, item in ipairs(categoryItems("Gear")) do
		if item.Placeable then
			table.insert(sprOptions, { Id = item.Id, Name = item.Name, Color = colorOf(item.Rarity) })
		end
	end
	local sprChips = chips(spr, sprOptions, false)
	local sr = row(spr, 8)
	local sprCount = input(sr, "How many", 110, "1")
	button(sr, "PLACE", "primary", function()
		local t = needTarget()
		local id = sprChips.Get()
		if not t then
			return
		end
		if not id then
			say("Pick a sprinkler", "warn")
			return
		end
		run("sprinkler_spawn", { Target = t, Id = id, Count = parseNumber(sprCount.Text) or 1 })
	end, 140)
	text(spr, "Max " .. tostring(boot.Db.MaxPlaced or "?") .. " placed per player.", 11, C.Dim, FONT)

	-- mutate the garden
	local mut = card(body, "Mutate a whole garden", "Every planet in the selected player's garden gets this mutation")
	local gardenMut = chips(mut, mutOptions, false)
	local mr = row(mut, 8)
	button(mr, "Apply mutation", "violet", function()
		local t = needTarget()
		local id = gardenMut.Get()
		if t and id then
			run("garden_mutate", { Target = t, Id = id })
		elseif t then
			say("Pick a mutation", "warn")
		end
	end, 150)
	button(mr, "Remove all mutations", "ghost", function()
		local t = needTarget()
		if t then
			run("garden_mutate", { Target = t, Id = "none" })
		end
	end, 170)
	button(mr, "Grow whole garden", "good", function()
		local t = needTarget()
		if t then
			run("garden_grow", { Target = t, Key = "all" })
		end
	end, 160)
end

---------------------------------------------------------------------
-- ECONOMY
---------------------------------------------------------------------
local ecoPage = page("Economy", "$", "economy")
if ecoPage then
	local body = standardPage(ecoPage)
	local c = card(body, "Currency", "Add, remove or set any currency. Type 5k, 2.5m, 3b, 1t")
	local scope = scopeSwitch(c)
	text(c, "CURRENCY", 11, C.Dim, HEAVY)
	local curOptions = {}
	for _, f in ipairs(boot.Db.Currencies) do
		table.insert(curOptions, { Id = f, Name = f, Color = C.Warn })
	end
	local curChips = chips(c, curOptions, false, nil, boot.Db.Currencies[1])
	local r = row(c, 8)
	local amount = input(r, "Amount", 180, "1000")
	for _, n in ipairs({ 1e3, 1e5, 1e6, 1e9, 1e12 }) do
		button(r, fmt(n), "ghost", function()
			amount.Text = fmt(n)
		end, 58)
	end
	local r2 = row(c, 8)
	local function go(mode)
		local t = scope.Target()
		local n = parseNumber(amount.Text)
		if not t then
			return
		end
		if not n or n < 0 then
			say("Enter an amount", "warn")
			return
		end
		run("currency", { Target = t, Field = curChips.Get() or "Coins", Amount = n, Mode = mode })
	end
	button(r2, "ADD", "good", function()
		go("add")
	end, 130, 36)
	button(r2, "REMOVE", "bad", function()
		go("remove")
	end, 130, 36)
	button(r2, "SET TO", "primary", function()
		go("set")
	end, 130, 36)

	local overview = card(body, "Selected player's balance")
	local function drawOverview()
		for _, ch in ipairs(overview:GetChildren()) do
			if ch:IsA("TextLabel") and ch.Name == "Bal" then
				ch:Destroy()
			end
		end
		local p = targetPlayer()
		if not p then
			text(overview, "No player selected", 12, C.Dim, FONT).Name = "Bal"
			return
		end
		local d = query("inspect", target)
		local parts = {}
		for _, f in ipairs(boot.Db.Currencies) do
			table.insert(parts, f .. ": <font color=\"#ffbe3c\"><b>" .. fmt(d and d.Currencies and d.Currencies[f] or 0) .. "</b></font>")
		end
		text(overview, p.DisplayName .. "   ·   " .. table.concat(parts, "   ·   "), 14, C.Text).Name = "Bal"
	end
	pages.Economy.OnShow = drawOverview
	refreshers.economy = function()
		if currentPage == "Economy" then
			drawOverview()
		end
	end
	table.insert(targetListeners, refreshers.economy)

	local mult = card(body, "Coin multiplier", "Server-wide boost to coins from selling and collecting (World tab has all boosts)")
	local mr = row(mult, 8)
	for _, v in ipairs({ 1, 2, 3, 5, 10 }) do
		button(mr, v .. "x", v == 1 and "ghost" or "violet", function()
			run("multiplier", { Id = "Coins", Value = v, Seconds = 0 })
		end, 64)
	end
end

---------------------------------------------------------------------
-- WORLD  (multipliers, events, weather, shops, announcements)
---------------------------------------------------------------------
local worldPage = page("World", "◎", "world")
if worldPage then
	local body = standardPage(worldPage)
	local function attr(name)
		return liveState and liveState:GetAttribute(name)
	end
	local function timeLeft(untilTime)
		if not untilTime or untilTime <= 0 then
			return "no time limit"
		end
		local left = math.max(0, untilTime - workspace:GetServerTimeNow())
		return string.format("%d:%02d left", math.floor(left / 60), math.floor(left % 60))
	end

	-- live status strip
	local live = card(body, "Live status")
	local liveText = text(live, "", 13, C.Text)
	local function updateLive()
		local parts = {}
		for _, m in ipairs(boot.Db.Multipliers) do
			local v = attr("Mult_" .. m.Id) or 1
			table.insert(parts, string.format("%s <font color=\"#%s\"><b>%sx</b></font>", m.Name, (v ~= 1 and C.Accent or C.Dim):ToHex(), fmt(v)))
		end
		local event = attr("Event")
		local weather = attr("Weather") or "clear"
		local wName = weather
		for _, w in ipairs(boot.Db.Weather) do
			if w.Id == weather then
				wName = w.Name
			end
		end
		liveText.Text = table.concat(parts, "   ·   ")
			.. "\nEvent: " .. ((event and event ~= "") and ("<font color=\"#9a5aff\"><b>" .. mutationName(event) .. " ×" .. tostring(attr("EventBoost")) .. "</b></font> (" .. timeLeft(attr("EventUntil")) .. ")") or "none")
			.. "   ·   Weather: <b>" .. wName .. "</b>" .. (weather ~= "clear" and (" (" .. timeLeft(attr("WeatherUntil")) .. ")") or "")
	end
	button(live, "Reset everything to normal", "bad", function()
		run("liveops_reset", {})
	end, 220)

	-- multipliers
	local mc = card(body, "Multipliers", "Server-wide. Minutes = 0 keeps it on until you change it")
	for _, m in ipairs(boot.Db.Multipliers) do
		local f, right = itemRow(mc, m.Name, m.Desc .. "  ·  max " .. m.Max .. "x", C.Accent)
		f.Size = UDim2.new(1, 0, 0, 48)
		local value = input(right, "x", 60, "2")
		value.Size = UDim2.fromOffset(60, 30)
		local minutes = input(right, "min", 60, "30")
		minutes.Size = UDim2.fromOffset(60, 30)
		button(right, "Set", "primary", function()
			local v, mins = parseNumber(value.Text), parseNumber(minutes.Text) or 0
			if not v then
				say("Enter a multiplier", "warn")
				return
			end
			run("multiplier", { Id = m.Id, Value = v, Seconds = mins * 60 })
		end, 56, 30)
		button(right, "Reset", "ghost", function()
			run("multiplier", { Id = m.Id, Value = 1, Seconds = 0 })
		end, 60, 30)
	end

	-- events
	local ec = card(body, "Mutation event", "Boost any mutation's chance for everyone. New mutations appear here automatically")
	local mutOptions = {}
	for _, m in ipairs(boot.Db.Mutations) do
		table.insert(mutOptions, { Id = m.Id, Name = m.Name })
	end
	local eventChips = chips(ec, mutOptions, false)
	local er = row(ec, 8)
	text(er, "BOOST", 11, C.Dim, HEAVY).Size = UDim2.fromOffset(44, 26)
	local boost = input(er, "x", 70, "5")
	text(er, "MINUTES", 11, C.Dim, HEAVY).Size = UDim2.fromOffset(58, 26)
	local eventMinutes = input(er, "min", 70, "15")
	button(er, "Start event", "violet", function()
		local id = eventChips.Get()
		if not id then
			say("Pick a mutation", "warn")
			return
		end
		run("event_start", { Id = id, Boost = parseNumber(boost.Text) or 5, Seconds = (parseNumber(eventMinutes.Text) or 0) * 60 })
	end, 120)
	button(er, "Stop", "ghost", function()
		run("event_stop", {})
	end, 70)

	-- weather
	local wc = card(body, "Weather", "Everyone sees it. Some weather boosts a matching mutation")
	local wOptions = {}
	for _, w in ipairs(boot.Db.Weather) do
		table.insert(wOptions, { Id = w.Id, Name = w.Name })
	end
	local weatherChips = chips(wc, wOptions, false, nil, "clear")
	local wr = row(wc, 8)
	text(wr, "MINUTES", 11, C.Dim, HEAVY).Size = UDim2.fromOffset(58, 26)
	local wMinutes = input(wr, "min", 70, "10")
	button(wr, "Set weather", "primary", function()
		run("weather", { Id = weatherChips.Get() or "clear", Seconds = (parseNumber(wMinutes.Text) or 0) * 60 })
	end, 130)

	-- shops + announce
	local sc = card(body, "Server")
	local ar = row(sc, 8)
	local msg = input(ar, "Announcement for everyone...", 420)
	button(ar, "Announce", "violet", function()
		if msg.Text:gsub("%s", "") == "" then
			say("Type a message", "warn")
			return
		end
		run("announce", { Text = msg.Text }, function(ok)
			if ok then
				msg.Text = ""
			end
		end)
	end, 110)
	button(sc, "Restock every shop", "ghost", function()
		run("restock", {})
	end, 170)

	pages.World.OnShow = updateLive
	if liveState then
		liveState.AttributeChanged:Connect(function()
			if currentPage == "World" and window.Visible then
				updateLive()
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			if currentPage == "World" and window.Visible then
				updateLive()
			end
		end
	end)
end

---------------------------------------------------------------------
-- MODERATION
---------------------------------------------------------------------
local modPage = page("Moderation", "!", "kick")
if modPage then
	local body = standardPage(modPage)

	local kc = card(body, "Kick", "Removes the selected player from this server")
	local kr = row(kc, 8)
	local kickReason = input(kr, "Reason (optional)", 360)
	button(kr, "Kick selected", "bad", function()
		local t = needTarget()
		if t then
			run("kick", { Target = t, Reason = kickReason.Text })
		end
	end, 140)

	if perm("ban") then
		local bc = card(body, "Ban", "Works on anyone, even offline: type a username or UserId (blank = selected player)")
		local br = row(bc, 8)
		local who = input(br, "Username or UserId", 200)
		local reason = input(br, "Reason", 260)
		local length = chips(bc, {
			{ Id = 3600, Name = "1 hour" }, { Id = 86400, Name = "1 day" }, { Id = 7 * 86400, Name = "7 days" },
			{ Id = 30 * 86400, Name = "30 days" }, { Id = 0, Name = "Permanent", Color = C.Bad },
		}, false, nil, 86400)
		local banList
		local drawBans
		button(bc, "BAN", "bad", function()
			local t = who.Text ~= "" and who.Text or needTarget()
			if not t then
				return
			end
			run("ban", { Target = t, Reason = reason.Text, Seconds = length.Get() or 0 }, function(ok)
				if ok then
					who.Text = ""
					drawBans()
				end
			end)
		end, 140, 36)

		local uc = card(body, "Unban")
		local ur = row(uc, 8)
		local unbanWho = input(ur, "Username or UserId", 240)
		button(ur, "Unban", "good", function()
			if unbanWho.Text == "" then
				say("Type who to unban", "warn")
				return
			end
			run("unban", { Target = unbanWho.Text }, function(ok)
				if ok then
					unbanWho.Text = ""
					drawBans()
				end
			end)
		end, 110)
		banList = card(body, "Banned players")
		drawBans = function()
			clearChildren(banList, true)
			make("TextLabel", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "BANNED PLAYERS", Font = HEAVY, TextSize = 13, TextColor3 = C.Text,
				TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = -100 }, banList)
			local list = query("bans") or {}
			if #list == 0 then
				emptyNote(banList, "Nobody is banned")
			end
			for i, b in ipairs(list) do
				local _, right = itemRow(banList, tostring(b.Name), "UserId " .. tostring(b.UserId), C.Bad, i)
				button(right, "Unban", "good", function()
					run("unban", { Target = b.UserId }, function()
						drawBans()
					end)
				end, 70, 28)
			end
		end
		pages.Moderation.OnShow = drawBans
	end

	if perm("reset") then
		local rc = card(body, "Reset player data", "Wipes the selected player's coins, inventory, garden, sprinklers and base. Cannot be undone")
		local rr = row(rc, 8)
		local confirm = input(rr, "Type RESET to confirm", 200)
		button(rr, "Reset selected player", "bad", function()
			local t = needTarget()
			if t then
				run("reset", { Target = t, Confirm = confirm.Text }, function(ok)
					if ok then
						confirm.Text = ""
					end
				end)
			end
		end, 190)
	end
end

---------------------------------------------------------------------
-- LOGS
---------------------------------------------------------------------
local logPage = page("Logs", "≡", "view")
if logPage then
	local body = standardPage(logPage)
	local function draw()
		clearChildren(body, true)
		local c = card(body, "Admin log", "Every admin action in this server, newest first")
		button(c, "Refresh", "ghost", draw, 100)
		local list = query("logs") or {}
		if #list == 0 then
			emptyNote(c, "Nothing yet")
		end
		for i, l in ipairs(list) do
			local denied = l.Action:sub(1, 6) == "DENIED"
			itemRow(c, string.format("<b>%s</b>  %s  <font color=\"#7d8caf\">%s</font>", l.Admin, l.Action, l.Target ~= "" and ("→ " .. l.Target) or ""),
				os.date("%H:%M:%S", l.Time) .. "  ·  " .. l.Detail, denied and C.Bad or C.Accent2, i)
		end
	end
	pages.Logs.OnShow = draw
end

---------------------------------------------------------------------
-- ME  (your own character)
---------------------------------------------------------------------
local mePage = page("Me", "☺")
do
	local body = standardPage(mePage)
	local function humanoid()
		local character = player.Character
		return character and character:FindFirstChildOfClass("Humanoid"), character
	end

	local mc = card(body, "Movement")
	local r = row(mc, 8)
	text(r, "WALK SPEED", 11, C.Dim, HEAVY).Size = UDim2.fromOffset(80, 26)
	local speedBox = input(r, "16", 80, "50")
	button(r, "Set", "primary", function()
		local v, hum = parseNumber(speedBox.Text), humanoid()
		if v and hum then
			hum.WalkSpeed = math.clamp(v, 0, 500)
			say("Walk speed " .. hum.WalkSpeed, "good")
		end
	end, 60)
	text(r, "JUMP POWER", 11, C.Dim, HEAVY).Size = UDim2.fromOffset(80, 26)
	local jumpBox = input(r, "50", 80, "100")
	button(r, "Set", "primary", function()
		local v, hum = parseNumber(jumpBox.Text), humanoid()
		if v and hum then
			hum.UseJumpPower = true
			hum.JumpPower = math.clamp(v, 0, 500)
			say("Jump power " .. hum.JumpPower, "good")
		end
	end, 60)
	button(mc, "Reset speed and jump", "ghost", function()
		local hum = humanoid()
		if hum then
			hum.WalkSpeed = 16
			hum.UseJumpPower = true
			hum.JumpPower = 50
			say("Speed and jump reset", "good")
		end
	end, 180)

	local tc = card(body, "Toggles")
	local tr = row(tc, 8)

	-- god mode
	local god = false
	local function applyGod(character)
		if not character then
			return
		end
		local existing = character:FindFirstChild("AdminGodField")
		if god and not existing then
			make("ForceField", { Name = "AdminGodField", Visible = false }, character)
		elseif not god and existing then
			existing:Destroy()
		end
	end
	local godButton
	godButton = button(tr, "God mode: OFF", "ghost", function()
		god = not god
		godButton.Text = "God mode: " .. (god and "ON" or "OFF")
		godButton.TextColor3 = god and C.Good or C.Text
		applyGod(player.Character)
	end, 160, 36)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5)
		applyGod(character)
	end)

	-- fly
	local flying = false
	local flyConnection
	local flyButton
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
		flyButton.Text = "Fly: " .. (flying and "ON" or "OFF")
		flyButton.TextColor3 = flying and C.Good or C.Text
	end
	flyButton = button(tr, "Fly: OFF", "ghost", function()
		setFly(not flying)
	end, 160, 36)
	text(tc, "Fly: W A S D to move, Space up, Left Ctrl down.", 11, C.Dim, FONT)
	player.CharacterAdded:Connect(function()
		if flying then
			setFly(false)
		end
	end)
end

-- tab clicks (pages were made above)
for name, b in pairs(tabButtons) do
	b.MouseButton1Click:Connect(function()
		showPage(name)
	end)
end

---------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------
local toggleButton = make("TextButton", { Size = UDim2.fromOffset(96, 34), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16),
	BackgroundColor3 = C.BG, Text = "◆ ADMIN", TextColor3 = C.Text, Font = HEAVY, TextSize = 13, AutoButtonColor = false }, gui)
corner(toggleButton, 10)
local tStroke = stroke(toggleButton, C.Accent, 1.5)
make("UIGradient", { Color = ColorSequence.new(C.Accent, C.Accent2), Rotation = 30 }, tStroke)

local function setOpen(open)
	if open == window.Visible then
		return
	end
	if open then
		window.Visible = true
		local s = fitScale()
		scale.Scale = s * 0.92
		window.BackgroundTransparency = 0.3
		tween(scale, 0.25, { Scale = s })
		tween(window, 0.25, { BackgroundTransparency = 0 })
		serverText.Text = "Server " .. string.sub(boot.JobId ~= "" and boot.JobId or "studio", 1, 8) .. "  ·  " .. #Players:GetPlayers() .. " online"
		if currentPage and pages[currentPage].OnShow then
			task.spawn(pages[currentPage].OnShow)
		end
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
UserInputService.InputBegan:Connect(function(inputObject, processed)
	if not processed and inputObject.KeyCode == TOGGLE_KEY then
		setOpen(not window.Visible)
	end
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if window.Visible then
			scale.Scale = fitScale()
		end
	end)
end

-- dragging the window by its top bar
do
	local dragging, startPos, startInput
	top.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, startPos, startInput = true, window.Position, i.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local delta = i.Position - startInput
			window.Position = startPos + UDim2.fromOffset(delta.X, delta.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

showPage(pages.Players and "Players" or "Me")
print("[AdminPanel] ready (" .. tostring(boot.Role) .. ", F2 or the ADMIN button)")
