--[[
	LiveOpsClient  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	What every player sees from the admin panel's World controls (LiveOps on the server):
	  * announcements a glowing banner at the top of the screen
	  * boosts        little pills under it: "2x Coins 12:30", "Meteor Event x5", "Starfall"
	Reads the attributes on ReplicatedStorage.LiveOps, so it changes the moment an admin presses a button.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("LiveOps", 60)
if not state then
	return
end
local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))

local rgb = Color3.fromRGB
local function tween(o, t, props)
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

-- (the weather itself is drawn by WeatherClient, and its HUD card by WeatherHUD)

---------------------------------------------------------------------
-- Banner + boost pills
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "LiveOpsHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, -120)
banner.Size = UDim2.fromOffset(560, 64)
banner.BackgroundColor3 = rgb(10, 12, 24)
banner.BackgroundTransparency = 0.1
banner.Visible = false
banner.Parent = gui
-- phones: a smaller announcement banner
require(game:GetService("ReplicatedStorage"):WaitForChild("ScreenFit")).ScaleOnPhone(banner, 0.7)
Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 14)
local bStroke = Instance.new("UIStroke", banner)
bStroke.Thickness = 2
local bGrad = Instance.new("UIGradient", bStroke)
bGrad.Color = ColorSequence.new(rgb(0, 220, 255), rgb(150, 90, 255))
local bTitle = Instance.new("TextLabel")
bTitle.BackgroundTransparency = 1
bTitle.Size = UDim2.new(1, -30, 0, 16)
bTitle.Position = UDim2.fromOffset(15, 8)
bTitle.Font = Enum.Font.GothamBold
bTitle.TextSize = 11
bTitle.TextColor3 = rgb(0, 220, 255)
bTitle.TextXAlignment = Enum.TextXAlignment.Left
bTitle.Parent = banner
local bText = Instance.new("TextLabel")
bText.BackgroundTransparency = 1
bText.Size = UDim2.new(1, -30, 0, 30)
bText.Position = UDim2.fromOffset(15, 24)
bText.Font = Enum.Font.GothamBold
bText.TextScaled = true
bText.TextColor3 = rgb(235, 242, 255)
bText.TextXAlignment = Enum.TextXAlignment.Left
bText.Parent = banner
local tsc = Instance.new("UITextSizeConstraint", bText)
tsc.MaxTextSize = 20

local shown = 0
local function showBanner()
	local message = state:GetAttribute("Announce") or ""
	local at = state:GetAttribute("AnnounceAt") or 0
	if message == "" or workspace:GetServerTimeNow() - at > 10 then
		return
	end
	shown += 1
	local mine = shown
	bTitle.Text = "📢  ANNOUNCEMENT" .. ((state:GetAttribute("AnnounceBy") or "") ~= "" and ("  ·  " .. state:GetAttribute("AnnounceBy")) or "")
	bText.Text = message
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, -120)
	tween(banner, 0.5, { Position = UDim2.new(0.5, 0, 0, 70) })
	task.delay(7, function()
		if shown == mine then
			tween(banner, 0.5, { Position = UDim2.new(0.5, 0, 0, -120) })
		end
	end)
end
state:GetAttributeChangedSignal("AnnounceAt"):Connect(showBanner)

local pills = Instance.new("Frame")
pills.AnchorPoint = Vector2.new(0.5, 0)
pills.Position = UDim2.new(0.5, 0, 0, 40)
pills.Size = UDim2.fromOffset(700, 24)
pills.BackgroundTransparency = 1
pills.Parent = gui
local layout = Instance.new("UIListLayout", pills)
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 6)

local NAMES = { Coins = "Coins", Growth = "Growth", Luck = "Luck", Size = "Size Luck" }

local function timeLeft(untilTime)
	if not untilTime or untilTime <= 0 then
		return ""
	end
	local left = math.max(0, untilTime - workspace:GetServerTimeNow())
	return string.format("  %d:%02d", math.floor(left / 60), math.floor(left % 60))
end

local function pill(textValue, color)
	local p = Instance.new("TextLabel")
	p.Size = UDim2.fromOffset(0, 24)
	p.AutomaticSize = Enum.AutomaticSize.X
	p.BackgroundColor3 = rgb(10, 12, 24)
	p.BackgroundTransparency = 0.15
	p.Font = Enum.Font.GothamBold
	p.TextSize = 12
	p.TextColor3 = color
	p.Text = textValue
	Instance.new("UICorner", p).CornerRadius = UDim.new(0, 12)
	local s = Instance.new("UIStroke", p)
	s.Color = color
	s.Transparency = 0.4
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local pd = Instance.new("UIPadding", p)
	pd.PaddingLeft = UDim.new(0, 10)
	pd.PaddingRight = UDim.new(0, 10)
	p.Parent = pills
end

local function drawPills()
	for _, c in ipairs(pills:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for id, name in pairs(NAMES) do
		local v = state:GetAttribute("Mult_" .. id) or 1
		if v ~= 1 then
			pill(string.format("%sx %s", tostring(math.floor(v * 100) / 100), name) .. timeLeft(state:GetAttribute("Until_" .. id)), rgb(0, 220, 255))
		end
	end
	local event = state:GetAttribute("Event") or ""
	if event ~= "" then
		local m = MutationCatalog.Get(event)
		pill(string.format("%s Event x%s", m and m.Name or event, tostring(state:GetAttribute("EventBoost") or 1)) .. timeLeft(state:GetAttribute("EventUntil")), rgb(190, 120, 255))
	end
end
state.AttributeChanged:Connect(drawPills)
drawPills()
task.spawn(function()
	while true do
		task.wait(1)
		drawPills()
	end
end)
