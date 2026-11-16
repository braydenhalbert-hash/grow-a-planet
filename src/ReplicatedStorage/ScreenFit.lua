--[[
	ScreenFit  (ModuleScript)  -- ReplicatedStorage

	Helps every screen fit phones. Used by GardenHotbar, SeedShopUI, TutorialClient, LiveOpsClient,
	AdminPanel and SellDialogue.

	ScreenFit.IsPhone()               true on a small touch screen (phones, small tablets)
	ScreenFit.Size()                  the usable screen size (below Roblox's top bar), as a Vector2
	ScreenFit.Fit(design, margin)     a scale (max 1) that makes a box of `design` size fit the screen
	ScreenFit.Watch(fn)               calls fn() now and again whenever the screen size changes
	ScreenFit.ScaleOnPhone(gui, s)    gives gui a UIScale of s on phones (1 on bigger screens)
	ScreenFit.SideRoom()              phones with a notch / island (iPhone Pro...) keep the game UI inside a
	                                  "safe area"; this is how many pixels of real screen there are beside it
	                                  on each side (0 on normal screens). Client only.
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local ScreenFit = {}

local PHONE_SHORT_SIDE = 560 -- screens shorter than this (in points) count as phones

local function camera()
	return workspace.CurrentCamera
end

function ScreenFit.Size()
	local cam = camera()
	local view = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	return Vector2.new(view.X, view.Y - inset.Y)
end

function ScreenFit.IsPhone()
	local cam = camera()
	if not cam then
		return false
	end
	local view = cam.ViewportSize
	return UserInputService.TouchEnabled and math.min(view.X, view.Y) < PHONE_SHORT_SIDE
end

-- margin: how much of the screen the box may use (0.94 = 94%)
function ScreenFit.Fit(design, margin)
	margin = margin or 0.94
	local size = ScreenFit.Size()
	return math.min(1, size.X * margin / design.X, size.Y * margin / design.Y)
end

local watchers = {}
local hooked = nil
local function hook()
	local cam = camera()
	if not cam or hooked == cam then
		return
	end
	hooked = cam
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		for _, fn in ipairs(watchers) do
			task.spawn(fn)
		end
	end)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hook()
	for _, fn in ipairs(watchers) do
		task.spawn(fn)
	end
end)

function ScreenFit.Watch(fn)
	hook()
	table.insert(watchers, fn)
	task.spawn(fn)
end

local probe = nil
function ScreenFit.SideRoom()
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player and player:FindFirstChild("PlayerGui")
	if not playerGui then
		return 0
	end
	if not probe or not probe.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "ScreenFitProbe"
		gui.ScreenInsets = Enum.ScreenInsets.None -- the whole screen, edge to edge
		gui.ResetOnSpawn = false
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = gui
		gui.Parent = playerGui
		probe = frame
	end
	local cam = camera()
	local view = cam and cam.ViewportSize or Vector2.zero
	if probe.AbsoluteSize.X <= 0 then
		return 0
	end
	return math.max(0, (probe.AbsoluteSize.X - view.X) / 2)
end

function ScreenFit.ScaleOnPhone(gui, phoneScale)
	local scale = gui:FindFirstChild("PhoneScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "PhoneScale"
		scale.Parent = gui
	end
	ScreenFit.Watch(function()
		scale.Scale = ScreenFit.IsPhone() and phoneScale or 1
	end)
	return scale
end

return ScreenFit
