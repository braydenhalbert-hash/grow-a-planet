--[[
	WeatherHUD  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	The weather & events screen stuff:
	  * WEATHER CARD (top left): the current weather with its icon, time left, a progress bar and the
	    mutations it can give; on clear skies it shows what's coming next and when.
	  * EVENT CARD (under it): the live event, "INCOMING 0:42" during the countdown, then time left + its boosts.
	  * BANNERS in the middle of the screen when a weather starts / ends and when an event is coming / arrives,
	    and a giant 10..1 countdown right before an event.
	  * MUTATION POPUPS on the right when one of YOUR planets mutates (rarity colours, "NEW DISCOVERY!"
	    the first time you ever get that mutation). Mythic and Divine ones light up the whole screen.
	  * REWARDS: event coins and meteor shards.
	Phones get a smaller version.

	Needs: WeatherConfig, EventConfig, MutationCatalog, ScreenFit, Audio (ReplicatedStorage), WeatherServer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local state = ReplicatedStorage:WaitForChild("LiveOps", 60)
if not state then
	return
end
local WeatherConfig = require(ReplicatedStorage:WaitForChild("WeatherConfig"))
local EventConfig = require(ReplicatedStorage:WaitForChild("EventConfig"))
local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))
local ScreenFit = require(ReplicatedStorage:WaitForChild("ScreenFit"))
local okAudio, Audio = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Audio", 5))
end)
local weatherRemotes = ReplicatedStorage:WaitForChild("WeatherRemotes", 60)

local rgb = Color3.fromRGB
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local DARK = rgb(12, 14, 30)
local IS_PHONE = ScreenFit.IsPhone()

local function play(name, options)
	if okAudio then
		Audio.Play(name, options)
	end
end

local function now()
	return workspace:GetServerTimeNow()
end

local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc" }
local function shortCoins(n)
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local index = math.min(math.floor(math.log10(n) / 3), #SUFFIXES)
	local value = n / 10 ^ (index * 3)
	local text = string.format("%.1f", math.floor(value * 10) / 10):gsub("%.0$", "")
	return text .. SUFFIXES[index]
end

local function hex(c)
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

---------------------------------------------------------------------
-- little UI helpers
---------------------------------------------------------------------
local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = props and props.Parent
	return inst
end
local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end
local function stroke(color, thickness, transparency)
	return new("UIStroke", { Color = color or Color3.new(1, 1, 1), Thickness = thickness or 2, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function textStroke(thickness)
	return new("UIStroke", { Color = rgb(15, 10, 25), Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end
local function gradient(c1, c2, rotation)
	return new("UIGradient", { Color = ColorSequence.new(c1, c2 or c1), Rotation = rotation or 0 })
end
local function label(props, children)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or BODY_FONT
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return new("TextLabel", props, children)
end

local gui = new("ScreenGui", { Name = "WeatherHUD", ResetOnSpawn = false, DisplayOrder = 35, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })

---------------------------------------------------------------------
-- 1) The cards (top left, next to the settings button)
---------------------------------------------------------------------
local panel = new("Frame", {
	Name = "WeatherPanel", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0),
	Position = IS_PHONE and UDim2.fromOffset(48, 6) or UDim2.fromOffset(72, 10), Size = UDim2.fromOffset(250, 220), Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
ScreenFit.ScaleOnPhone(panel, 0.52)
local PHONE_SCALE = 0.52

local function card(name, order)
	local frame = new("Frame", {
		Name = name, LayoutOrder = order, Size = UDim2.fromOffset(250, 64), BackgroundColor3 = DARK, BackgroundTransparency = 0.12,
		ClipsDescendants = false, Parent = panel,
	}, { corner(14) })
	local border = stroke(Color3.new(1, 1, 1), 2)
	border.Parent = frame
	local borderGradient = gradient(rgb(120, 200, 255), rgb(90, 120, 255), 0)
	borderGradient.Parent = border
	-- soft inner shine
	new("Frame", { Name = "Shine", Size = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.94, Parent = frame },
		{ corner(14) })
	local icon = new("Frame", { Name = "Icon", Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.new(1, 1, 1), Parent = frame },
		{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local iconGradient = gradient(rgb(120, 200, 255), rgb(90, 120, 255), 45)
	iconGradient.Parent = icon
	local iconStroke = stroke(Color3.new(1, 1, 1), 2, 0.4)
	iconStroke.Parent = icon
	local emoji = label({ Size = UDim2.fromScale(1, 1), Text = "🌌", TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Parent = icon },
		{ new("UIPadding", { PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7), PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }) })
	local header = label({ Name = "Header", Position = UDim2.fromOffset(64, 7), Size = UDim2.new(1, -96, 0, 12), TextSize = 10, Text = "WEATHER", Parent = frame })
	local title = label({ Name = "Title", Position = UDim2.fromOffset(64, 19), Size = UDim2.new(1, -96, 0, 22), Font = TITLE_FONT, TextSize = 20,
		Text = "Clear Skies", TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame }, { textStroke(1.6) })
	local sub = label({ Name = "Sub", Position = UDim2.fromOffset(64, 41), Size = UDim2.new(1, -72, 0, 14), TextSize = 12, RichText = true,
		TextColor3 = rgb(210, 220, 245), Text = "", TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	local barBack = new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -5), Size = UDim2.new(1, -24, 0, 3),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, Visible = false, Parent = frame }, { corner(2) })
	local barFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = barBack }, { corner(2) })
	local barGradient = gradient(rgb(120, 200, 255), rgb(90, 120, 255))
	barGradient.Parent = barFill
	local chips = new("Frame", { Name = "Chips", Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -24, 0, 18), BackgroundTransparency = 1, Visible = false, Parent = frame },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
	return {
		Frame = frame, Border = borderGradient, Icon = iconGradient, Emoji = emoji, Header = header, Title = title, Sub = sub,
		Bar = barBack, Fill = barFill, BarGradient = barGradient, Chips = chips,
	}
end

local weatherCard = card("WeatherCard", 1)
local eventCard = card("EventCard", 2)
eventCard.Frame.Visible = false

-- hide / show: the "-" button folds the cards into one small round weather icon; tap it to open them again
local mini = new("TextButton", {
	Name = "WeatherMini", Size = UDim2.fromOffset(46, 46), Position = panel.Position, BackgroundColor3 = DARK,
	BackgroundTransparency = 0.1, Text = "", AutoButtonColor = true, Visible = false, Parent = gui,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
local miniStroke = stroke(Color3.new(1, 1, 1), 2)
miniStroke.Parent = mini
local miniGradient = gradient(rgb(120, 200, 255), rgb(90, 120, 255), 0)
miniGradient.Parent = miniStroke
local miniEmoji = label({ Size = UDim2.fromScale(1, 1), Text = "🌌", TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Parent = mini },
	{ new("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9), PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }) })
local miniDot = new("Frame", { Size = UDim2.fromOffset(13, 13), Position = UDim2.new(1, -12, 0, -1), BackgroundColor3 = rgb(255, 80, 80),
	Visible = false, Parent = mini }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(DARK, 1.5) })
ScreenFit.ScaleOnPhone(mini, 0.72)

local hideButton = new("TextButton", {
	Name = "Hide", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 5), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = DARK,
	BackgroundTransparency = 0.1, Font = TITLE_FONT, Text = "-", TextSize = 22, TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = true, Parent = weatherCard.Frame,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(Color3.new(1, 1, 1), 1.5, 0.5) })

-- computers: top left. Phones: up in the top-right corner of Roblox's top bar row, just left of the
-- settings button (the event card, when there is one, hangs below it)
local function placePanel()
	if ScreenFit.IsPhone() then
		local inset = GuiService:GetGuiInset().Y
		local cardHeight = 64 * PHONE_SCALE
		local y = inset > cardHeight and -(inset + cardHeight) / 2 or 6
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.new(1, -(8 + 34 + 8), 0, y)
		mini.AnchorPoint = Vector2.new(1, 0)
		mini.Position = UDim2.new(1, -(8 + 34 + 8), 0, inset > 33 and -(inset + 33) / 2 or 6)
	else
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UDim2.fromOffset(72, 10)
		mini.AnchorPoint = Vector2.new(0, 0)
		mini.Position = panel.Position
	end
end
ScreenFit.Watch(placePanel)
task.delay(1, placePanel) -- (Roblox's top bar size is only known a moment later)

local function setCollapsed(collapsed)
	panel.Visible = not collapsed
	mini.Visible = collapsed
end
hideButton.Activated:Connect(function()
	setCollapsed(true)
end)
mini.Activated:Connect(function()
	setCollapsed(false)
end)

local function colorCard(c, color, color2)
	c.Border.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(0.5, color2), ColorSequenceKeypoint.new(1, color) })
	c.Icon.Color = ColorSequence.new(color, color2)
	c.BarGradient.Color = ColorSequence.new(color, color2)
	c.Header.TextColor3 = color
end

local function setChips(c, list)
	for _, child in ipairs(c.Chips:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, item in ipairs(list) do
		label({
			LayoutOrder = i, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.25,
			BackgroundColor3 = rgb(25, 25, 45), TextSize = 11, Text = item.Text, TextColor3 = item.Color, Parent = c.Chips,
		}, { corner(9), stroke(item.Color, 1, 0.45), new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
	end
	c.Chips.Visible = #list > 0
	c.Frame.Size = UDim2.fromOffset(250, #list > 0 and 90 or 64)
	c.Bar.Position = UDim2.new(0, 12, 0, 58)
end

local function mutationChips(list)
	local chips = {}
	for _, m in ipairs(list or {}) do
		local info = MutationCatalog.Get(m.Id)
		if info then
			table.insert(chips, { Text = info.Name, Color = MutationCatalog.RarityOf(m.Id).Color })
		end
	end
	return chips
end

local shownWeather = nil
local function refreshWeather()
	local id = state:GetAttribute("Weather") or "clear"
	local w = WeatherConfig.Get(id) or WeatherConfig.Clear
	if shownWeather ~= id then
		shownWeather = id
		colorCard(weatherCard, w.Color, w.Color2)
		weatherCard.Emoji.Text = w.Icon or "🌌"
		miniEmoji.Text = w.Icon or "🌌"
		miniGradient.Color = ColorSequence.new(w.Color, w.Color2)
		weatherCard.Title.Text = w.Name
		setChips(weatherCard, id ~= "clear" and mutationChips(w.Mutations) or {})
	end
	local t = now()
	if id ~= "clear" then
		local untilAt = state:GetAttribute("WeatherUntil") or 0
		local started = state:GetAttribute("WeatherStarted") or t
		weatherCard.Header.Text = "WEATHER  ·  ACTIVE"
		if untilAt > 0 then
			local left = untilAt - t
			weatherCard.Sub.Text = clock(left) .. " left"
			weatherCard.Bar.Visible = true
			weatherCard.Fill.Size = UDim2.fromScale(math.clamp(left / math.max(1, untilAt - started), 0, 1), 1)
		else
			weatherCard.Sub.Text = "until it's changed"
			weatherCard.Bar.Visible = false
		end
	else
		weatherCard.Header.Text = "WEATHER"
		weatherCard.Bar.Visible = false
		local nextId = state:GetAttribute("WeatherNext") or ""
		local nextAt = state:GetAttribute("WeatherNextAt") or 0
		local nextW = WeatherConfig.Get(nextId)
		if nextW and nextAt > 0 then
			local left = nextAt - t
			if left <= WeatherConfig.WarnBefore then
				weatherCard.Sub.Text = string.format('<font color="%s">%s %s</font> in %s', hex(nextW.Color), nextW.Icon, nextW.Name, clock(left))
			else
				weatherCard.Sub.Text = string.format("Next weather in %s", clock(left))
			end
		else
			weatherCard.Sub.Text = "Calm space"
		end
	end
end

local function boostText(event)
	local parts = {}
	for id, value in pairs(event.Boosts or {}) do
		table.insert(parts, { Text = string.format("%sx %s", tostring(value), id), Color = rgb(255, 230, 120) })
	end
	if event.Gravity then
		table.insert(parts, { Text = "Low Gravity", Color = rgb(190, 160, 255) })
	end
	if event.Shards then
		table.insert(parts, { Text = "Shards!", Color = rgb(255, 190, 80) })
	end
	return parts
end

local shownEvent = nil
local function refreshEvent()
	local id = state:GetAttribute("LiveEvent") or ""
	local phase = state:GetAttribute("LiveEventPhase") or ""
	local event = EventConfig.Get(id)
	if not event or phase == "" then
		eventCard.Frame.Visible = false
		miniDot.Visible = false
		shownEvent = nil
		return
	end
	eventCard.Frame.Visible = true
	miniDot.Visible = true -- a live event is on (shows on the folded-up icon too)
	local key = id .. phase
	if shownEvent ~= key then
		shownEvent = key
		colorCard(eventCard, event.Color, event.Color2)
		eventCard.Emoji.Text = event.Icon
		eventCard.Title.Text = event.Name
		setChips(eventCard, phase == "active" and boostText(event) or {})
	end
	local t = now()
	local startAt = state:GetAttribute("LiveEventStart") or t
	local untilAt = state:GetAttribute("LiveEventUntil") or t
	if phase == "countdown" then
		local left = startAt - t
		local blink = math.floor(t * 2) % 2 == 0
		eventCard.Header.Text = "⚠ LIVE EVENT INCOMING"
		eventCard.Header.TextColor3 = blink and rgb(255, 90, 90) or rgb(255, 220, 120)
		eventCard.Sub.Text = string.format('Starts in <font color="#ffe16e"><b>%s</b></font>', clock(left))
		eventCard.Bar.Visible = true
		eventCard.Fill.Size = UDim2.fromScale(math.clamp(1 - left / EventConfig.Countdown, 0, 1), 1)
	elseif phase == "active" then
		local left = untilAt - t
		eventCard.Header.Text = "● LIVE EVENT"
		eventCard.Header.TextColor3 = (math.floor(t * 2) % 2 == 0) and event.Color or Color3.new(1, 1, 1)
		eventCard.Sub.Text = clock(left) .. " left"
		eventCard.Bar.Visible = true
		eventCard.Fill.Size = UDim2.fromScale(math.clamp(left / math.max(1, untilAt - startAt), 0, 1), 1)
	else
		eventCard.Header.Text = "LIVE EVENT"
		eventCard.Sub.Text = "Ended! Rewards sent"
		eventCard.Bar.Visible = false
	end
end

-- the borders slowly shimmer
RunService.RenderStepped:Connect(function()
	local r = (os.clock() * 60) % 360
	weatherCard.Border.Rotation = r
	eventCard.Border.Rotation = -r
end)

---------------------------------------------------------------------
-- 2) Big banners in the middle
---------------------------------------------------------------------
local bannerHolder = new("Frame", { Name = "Banners", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.19, 0),
	Size = UDim2.fromOffset(560, 120), BackgroundTransparency = 1, Parent = gui })
ScreenFit.ScaleOnPhone(bannerHolder, 0.62)

local bannerQueue = {}
local bannerBusy = false

local function showBanner(info)
	bannerBusy = true
	local frame = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -20), Size = UDim2.fromOffset(560, 104),
		BackgroundColor3 = DARK, BackgroundTransparency = 0.08, Parent = bannerHolder }, { corner(18) })
	local scale = new("UIScale", { Scale = 0.6, Parent = frame })
	local border = stroke(Color3.new(1, 1, 1), 3)
	border.Parent = frame
	local borderGradient = gradient(info.Color, info.Color2)
	borderGradient.Parent = border
	local small = label({ Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, Text = info.Header,
		TextColor3 = info.Color, TextXAlignment = Enum.TextXAlignment.Center, Parent = frame })
	local title = label({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 42), Font = TITLE_FONT, TextSize = 38, Text = info.Title,
		TextXAlignment = Enum.TextXAlignment.Center, Parent = frame }, { textStroke(2.5) })
	local titleGradient = gradient(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
	titleGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, info.Color), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, info.Color2) })
	titleGradient.Parent = title
	label({ Position = UDim2.fromOffset(20, 70), Size = UDim2.new(1, -40, 0, 28), TextSize = 13, Text = info.Desc or "", TextWrapped = true,
		TextColor3 = rgb(215, 222, 245), TextXAlignment = Enum.TextXAlignment.Center, Parent = frame })
	if info.Sound then
		play(info.Sound)
	end
	tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(frame, 0.45, { Position = UDim2.new(0.5, 0, 0, 0) }, Enum.EasingStyle.Back)
	local start = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		titleGradient.Offset = Vector2.new(math.sin(t * 2) * 0.35, 0)
		borderGradient.Rotation = (t * 120) % 360
	end)
	task.delay(info.Hold or 4.5, function()
		tween(scale, 0.35, { Scale = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, d in ipairs(frame:GetDescendants()) do
			if d:IsA("TextLabel") then
				tween(d, 0.35, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				tween(d, 0.35, { Transparency = 1 })
			end
		end
		tween(frame, 0.35, { BackgroundTransparency = 1 })
		task.wait(0.4)
		conn:Disconnect()
		frame:Destroy()
		bannerBusy = false
		local nextOne = table.remove(bannerQueue, 1)
		if nextOne then
			showBanner(nextOne)
		end
	end)
end

local function banner(info)
	if bannerBusy then
		-- the newest news replaces anything still waiting
		bannerQueue = { info }
	else
		showBanner(info)
	end
end

-- weather starts / ends
local lastWeather = state:GetAttribute("Weather") or "clear"
state:GetAttributeChangedSignal("Weather"):Connect(function()
	local id = state:GetAttribute("Weather") or "clear"
	if id == lastWeather then
		return
	end
	local old = WeatherConfig.Get(lastWeather)
	lastWeather = id
	if id ~= "clear" then
		local w = WeatherConfig.Get(id)
		if w then
			local names = {}
			for _, chip in ipairs(mutationChips(w.Mutations)) do
				table.insert(names, chip.Text)
			end
			banner({
				Header = "SPACE WEATHER", Title = w.Icon .. "  " .. string.upper(w.Name) .. "  " .. w.Icon,
				Desc = w.Desc .. (#names > 0 and ("  ·  Can mutate: " .. table.concat(names, ", ")) or ""),
				Color = w.Color, Color2 = w.Color2, Sound = "weather_start",
			})
		end
	elseif old then
		banner({ Header = "WEATHER", Title = "The " .. old.Name .. " has ended", Desc = "Clear skies again... for now.",
			Color = old.Color, Color2 = old.Color2, Hold = 3 })
	end
end)

-- events
local lastPhase = state:GetAttribute("LiveEventPhase") or ""
local function onEventPhase()
	local phase = state:GetAttribute("LiveEventPhase") or ""
	if phase == lastPhase then
		return
	end
	lastPhase = phase
	local event = EventConfig.Get(state:GetAttribute("LiveEvent") or "")
	if not event then
		return
	end
	if phase == "countdown" then
		banner({ Header = "⚠  LIVE EVENT INCOMING  ⚠", Title = event.Icon .. "  " .. string.upper(event.Name), Desc = event.Desc,
			Color = event.Color, Color2 = event.Color2, Sound = "event_alarm", Hold = 6 })
	elseif phase == "active" then
		local boosts = {}
		for _, b in ipairs(boostText(event)) do
			table.insert(boosts, b.Text)
		end
		banner({ Header = "LIVE EVENT", Title = string.upper(event.Name) .. " HAS ARRIVED!", Desc = table.concat(boosts, "  ·  "),
			Color = event.Color, Color2 = event.Color2, Sound = "event_boom", Hold = 5 })
	end
end
state:GetAttributeChangedSignal("LiveEventPhase"):Connect(onEventPhase)

---------------------------------------------------------------------
-- 3) The giant 10..1 countdown
---------------------------------------------------------------------
local bigCount = label({ Name = "BigCountdown", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.fromOffset(300, 160), Font = TITLE_FONT, TextSize = 130, Text = "", TextXAlignment = Enum.TextXAlignment.Center,
	TextTransparency = 1, Visible = false, Parent = gui }, { textStroke(5) })
local bigScale = new("UIScale", { Parent = bigCount })
local bigGradient = gradient(rgb(255, 240, 150), rgb(255, 90, 60), 90)
bigGradient.Parent = bigCount
ScreenFit.ScaleOnPhone(bigCount, 0.6)
local lastShownNumber = nil

local function refreshBigCountdown()
	local phase = state:GetAttribute("LiveEventPhase") or ""
	local left = (state:GetAttribute("LiveEventStart") or 0) - now()
	local n = math.ceil(left)
	if phase == "countdown" and n >= 1 and n <= 10 then
		if n ~= lastShownNumber then
			lastShownNumber = n
			bigCount.Text = tostring(n)
			bigCount.Visible = true
			bigCount.TextTransparency = 0
			bigScale.Scale = 1.6
			tween(bigScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			play("event_tick", { Pitch = 1 + (10 - n) * 0.04 })
		end
		bigCount.TextTransparency = math.clamp((n - left - 0.6) * 2.5, 0, 1) -- each number fades near the end of its second
	elseif lastShownNumber then
		lastShownNumber = nil
		-- (the text outline doesn't fade with the text, so the label is hidden once it's faded)
		if phase == "" then
			bigCount.Visible = false
			return
		end
		bigCount.Text = "GO!"
		bigCount.Visible = true
		bigCount.TextTransparency = 0
		bigScale.Scale = 2
		tween(bigScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(1, function()
			tween(bigCount, 0.4, { TextTransparency = 1 })
			task.wait(0.45)
			if not lastShownNumber then
				bigCount.Visible = false
			end
		end)
	end
end

---------------------------------------------------------------------
-- 4) Mutation popups (right side)
---------------------------------------------------------------------
local popupHolder = new("Frame", { Name = "MutationPopups", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.46, 0),
	Size = UDim2.fromOffset(300, 360), BackgroundTransparency = 1, Parent = gui }, {
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right }),
})
ScreenFit.ScaleOnPhone(popupHolder, 0.66)

local screenGlow = new("Frame", { Name = "RareGlow", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0, Parent = gui })
local glowStroke = new("UIStroke", { Thickness = 0, Transparency = 1, Parent = screenGlow })
local glowGradient = gradient(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
glowGradient.Parent = glowStroke

local popupOrder = 0
local function rareScreen(color, color2, tier)
	glowGradient.Color = ColorSequence.new(color, color2)
	glowStroke.Thickness = tier >= 7 and 40 or 24
	glowStroke.Transparency = 0.1
	tween(glowStroke, tier >= 7 and 4 or 2.5, { Transparency = 1, Thickness = 4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

local RARITY_SOUND = { [1] = "discover_common", [2] = "discover_common", [3] = "discover_rare", [4] = "discover_epic",
	[5] = "discover_legendary", [6] = "discover_mythic", [7] = "discover_mythic" }

local function mutationPopup(mutId, planetName, isNew)
	local m = MutationCatalog.Get(mutId)
	if not m then
		return
	end
	local rarity = MutationCatalog.RarityOf(mutId)
	local tier = rarity.Tier
	popupOrder += 1
	-- outer holder keeps its place in the list while the card slides in
	local holder = new("Frame", { LayoutOrder = popupOrder, Size = UDim2.fromOffset(300, 86), BackgroundTransparency = 1, Parent = popupHolder })
	local frame = new("Frame", { Position = UDim2.fromOffset(330, 0), Size = UDim2.fromOffset(300, 86), BackgroundColor3 = DARK,
		BackgroundTransparency = 0.06, Parent = holder }, { corner(16) })
	local border = stroke(Color3.new(1, 1, 1), tier >= 5 and 3 or 2)
	border.Parent = frame
	local borderGradient = gradient(m.Color, m.Color2)
	borderGradient.Parent = border
	-- tinted background wash
	local wash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, Parent = frame }, { corner(16) })
	local washGradient = gradient(m.Color, m.Color2, 0)
	washGradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	washGradient.Parent = wash
	-- orb icon
	local orb = new("Frame", { Size = UDim2.fromOffset(58, 58), Position = UDim2.fromOffset(12, 14), BackgroundColor3 = Color3.new(1, 1, 1), Parent = frame },
		{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local orbGradient = gradient(m.Color, m.Color2, 45)
	orbGradient.Parent = orb
	local orbStroke = stroke(Color3.new(1, 1, 1), 2, 0.2)
	orbStroke.Parent = orb
	label({ Size = UDim2.fromScale(1, 1), Text = tier >= 7 and "🌟" or tier >= 5 and "✨" or "⭐", Font = TITLE_FONT, TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center, Parent = orb }, { textStroke(2) })
	-- text
	local top = label({ Position = UDim2.fromOffset(80, 9), Size = UDim2.new(1, -90, 0, 14), TextSize = 11,
		Text = isNew and "⭐ NEW DISCOVERY! ⭐" or "MUTATION!", TextColor3 = isNew and rgb(255, 230, 110) or rarity.Color, Parent = frame })
	local name = label({ Position = UDim2.fromOffset(80, 22), Size = UDim2.new(1, -90, 0, 30), Font = TITLE_FONT, TextSize = 26, Text = m.Name,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame }, { textStroke(2) })
	local nameGradient = gradient(m.Color, m.Color2)
	nameGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, m.Color), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, m.Color2) })
	nameGradient.Parent = name
	label({ Position = UDim2.fromOffset(80, 53), Size = UDim2.new(1, -90, 0, 14), TextSize = 12, RichText = true,
		Text = string.format('on your %s  ·  <font color="#78ff96">x%s value</font>', planetName or "planet", tostring(m.SellMult or 1)),
		TextColor3 = rgb(210, 220, 245), TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	label({ Position = UDim2.fromOffset(80, 68), Size = UDim2.new(1, -90, 0, 12), TextSize = 10, Text = string.upper(m.Rarity or "Common"),
		TextColor3 = rarity.Color, Parent = frame })
	-- a shine that sweeps across
	local shine = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, Parent = frame }, { corner(16) })
	local shineGradient = new("UIGradient", { Rotation = 20, Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = shine })

	play(RARITY_SOUND[tier] or "discover_common")
	if tier >= 6 then
		rareScreen(m.Color, m.Color2, tier)
	end
	if tier >= 7 then
		banner({ Header = "🌟 DIVINE MUTATION 🌟", Title = string.upper(m.Name) .. "!!!", Desc = "Your " .. (planetName or "planet") .. " is now worth x" .. tostring(m.SellMult) .. "!",
			Color = m.Color, Color2 = m.Color2, Hold = 6 })
	end

	tween(frame, 0.5, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	tween(shineGradient, 1.1, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local start = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		borderGradient.Rotation = (t * (60 + tier * 25)) % 360
		nameGradient.Offset = Vector2.new(math.sin(t * 2.5) * 0.4, 0)
		if m.Look and m.Look.Rainbow then
			local h = (t * 0.25) % 1
			borderGradient.Color = ColorSequence.new(Color3.fromHSV(h, 0.7, 1), Color3.fromHSV((h + 0.4) % 1, 0.7, 1))
		end
		orbStroke.Transparency = 0.2 + math.sin(t * 5) * 0.2
	end)
	task.delay(tier >= 6 and 7 or 5, function()
		tween(frame, 0.4, { Position = UDim2.fromOffset(330, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.45)
		conn:Disconnect()
		tween(holder, 0.25, { Size = UDim2.fromOffset(300, 0) })
		task.wait(0.3)
		holder:Destroy()
	end)
	-- never more than 4 at once
	local cards = {}
	for _, child in ipairs(popupHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #cards - 4 do
		cards[i]:Destroy()
	end
end

---------------------------------------------------------------------
-- 5) Rewards
---------------------------------------------------------------------
local function rewardToast(title, amountText, sub, color)
	local frame = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(380, 92),
		BackgroundColor3 = DARK, BackgroundTransparency = 0.08, Parent = gui }, { corner(18) })
	ScreenFit.ScaleOnPhone(frame, 0.7)
	local scale = new("UIScale", { Scale = 0.4, Parent = frame })
	local border = stroke(Color3.new(1, 1, 1), 3)
	border.Parent = frame
	gradient(color, rgb(255, 255, 255)).Parent = border
	label({ Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, Text = title, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center, Parent = frame })
	label({ Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 40), Font = TITLE_FONT, TextSize = 38, Text = amountText,
		TextColor3 = rgb(255, 225, 90), TextXAlignment = Enum.TextXAlignment.Center, Parent = frame }, { textStroke(2.5) })
	label({ Position = UDim2.fromOffset(10, 64), Size = UDim2.new(1, -20, 0, 18), TextSize = 12, Text = sub or "", TextColor3 = rgb(215, 222, 245),
		TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	play("event_reward")
	tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3.5, function()
		tween(scale, 0.3, { Scale = 0.5 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(frame, 0.3, { BackgroundTransparency = 1 })
		for _, d in ipairs(frame:GetDescendants()) do
			if d:IsA("TextLabel") then
				tween(d, 0.3, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				tween(d, 0.3, { Transparency = 1 })
			end
		end
		task.wait(0.35)
		frame:Destroy()
	end)
end

if weatherRemotes then
	local discovered = weatherRemotes:WaitForChild("MutationDiscovered", 30)
	if discovered then
		discovered.OnClientEvent:Connect(function(mutId, model, planetName, isNew)
			mutationPopup(mutId, planetName, isNew)
		end)
	end
	local fx = weatherRemotes:WaitForChild("EventFx", 30)
	if fx then
		fx.OnClientEvent:Connect(function(kind, a, b, c)
			if kind == "reward" then
				local event = EventConfig.Get(a)
				if event and b and b > 0 then
					rewardToast("EVENT REWARD  ·  " .. string.upper(event.Name), "+" .. shortCoins(b) .. "¢", "Thanks for being here! Stay for the next one.", event.Color)
				end
			elseif kind == "shard" then
				local m = b and MutationCatalog.Get(b)
				rewardToast("☄️  METEOR SHARD", "+" .. shortCoins(a or 0) .. "¢",
					m and ("Your " .. tostring(c) .. " became " .. m.Name .. "!") or "Grab the other shards too!", rgb(255, 180, 70))
			end
		end)
	end
end

---------------------------------------------------------------------
-- Ticking
---------------------------------------------------------------------
state.AttributeChanged:Connect(function()
	refreshWeather()
	refreshEvent()
end)
refreshWeather()
refreshEvent()
RunService.Heartbeat:Connect(function()
	refreshBigCountdown()
end)
task.spawn(function()
	while true do
		task.wait(0.25)
		refreshWeather()
		refreshEvent()
	end
end)

print("[WeatherHUD] ready")
