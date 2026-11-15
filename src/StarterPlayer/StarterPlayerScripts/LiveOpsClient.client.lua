--[[
	LiveOpsClient  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	What every player sees from the admin panel's World controls (LiveOps on the server):
	  * weather       sky tint + falling stardust around the camera
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
local Stardust = require(ReplicatedStorage:WaitForChild("Stardust"))
local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))

local rgb = Color3.fromRGB
local function tween(o, t, props)
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

---------------------------------------------------------------------
-- Weather
---------------------------------------------------------------------
local WEATHER = {
	clear = { Tint = rgb(255, 255, 255), Bright = 0, Sat = 0, Rate = 0 },
	starfall = { Tint = rgb(225, 235, 255), Bright = 0, Sat = 0.1, Rate = 40, Tex = "Star", Colors = { rgb(255, 245, 200), rgb(150, 200, 255), rgb(255, 255, 255) }, Speed = 70, Size = 1.6 },
	nebulastorm = { Tint = rgb(240, 200, 255), Bright = 0, Sat = 0.25, Rate = 25, Tex = "Nebula", Colors = { rgb(255, 110, 230), rgb(150, 80, 255), rgb(255, 210, 250) }, Speed = 12, Size = 6 },
	solarstorm = { Tint = rgb(255, 215, 170), Bright = 0.03, Sat = 0.2, Rate = 45, Tex = "Wisp", Colors = { rgb(255, 160, 40), rgb(255, 70, 30), rgb(255, 235, 160) }, Speed = 25, Size = 2.2 },
	aurora = { Tint = rgb(200, 255, 240), Bright = 0, Sat = 0.15, Rate = 30, Tex = "Glint", Colors = { rgb(80, 255, 200), rgb(80, 180, 255), rgb(220, 255, 250) }, Speed = 8, Size = 1.4 },
	eclipse = { Tint = rgb(170, 160, 210), Bright = -0.12, Sat = -0.2, Rate = 18, Tex = "Void", Colors = { rgb(150, 70, 255), rgb(60, 20, 120), rgb(220, 160, 255) }, Speed = 6, Size = 3 },
	stardust = { Tint = rgb(255, 245, 225), Bright = 0.02, Sat = 0.15, Rate = 70, Tex = "Dust", Colors = { rgb(255, 220, 120), rgb(255, 140, 230), rgb(255, 255, 230) }, Speed = 14, Size = 1.2 },
}

local cc = Lighting:FindFirstChild("LiveOpsWeather") or Instance.new("ColorCorrectionEffect")
cc.Name = "LiveOpsWeather"
cc.Parent = Lighting

local sky = Instance.new("Part")
sky.Name = "LiveOpsWeatherEmitter"
sky.Anchored, sky.CanCollide, sky.CanQuery, sky.CanTouch = true, false, false, false
sky.Transparency = 1
sky.Size = Vector3.new(160, 1, 160)
sky.Parent = workspace.CurrentCamera
local emitter = Instance.new("ParticleEmitter")
emitter.EmissionDirection = Enum.NormalId.Bottom
emitter.Lifetime = NumberRange.new(3, 5)
emitter.LightEmission = 1
emitter.LightInfluence = 0
emitter.Rotation = NumberRange.new(0, 360)
emitter.RotSpeed = NumberRange.new(-60, 60)
emitter.Transparency = Stardust.FADE
emitter.Rate = 0
emitter.Parent = sky

local function applyWeather()
	local w = WEATHER[state:GetAttribute("Weather") or "clear"] or WEATHER.clear
	tween(cc, 2, { TintColor = w.Tint, Brightness = w.Bright, Saturation = w.Sat })
	emitter.Rate = w.Rate
	if w.Rate > 0 then
		emitter.Texture = Stardust.Texture(w.Tex)
		emitter.Color = Stardust.Colors(w.Colors)
		emitter.Speed = NumberRange.new(w.Speed * 0.7, w.Speed)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, w.Size), NumberSequenceKeypoint.new(1, w.Size * 0.4) })
	end
end
state:GetAttributeChangedSignal("Weather"):Connect(applyWeather)
applyWeather()

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if camera and emitter.Rate > 0 then
		if sky.Parent ~= camera then
			sky.Parent = camera
		end
		sky.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
	end
end)

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
local WEATHER_NAMES = { starfall = "Starfall", nebulastorm = "Nebula Storm", solarstorm = "Solar Storm", aurora = "Cosmic Aurora", eclipse = "Eclipse", stardust = "Stardust Rain" }

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
	local weather = state:GetAttribute("Weather") or "clear"
	if WEATHER_NAMES[weather] then
		pill(WEATHER_NAMES[weather] .. timeLeft(state:GetAttribute("WeatherUntil")), rgb(255, 200, 90))
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
