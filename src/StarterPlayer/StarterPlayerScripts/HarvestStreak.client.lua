--[[
	HarvestStreak  (LocalScript)  -- REPLACES the earlier HarvestStreak
	Put in: StarterPlayer > StarterPlayerScripts

	Hold E (or X on a controller, or hold the circle on a phone) next to your ready planets
	and keep holding: after the first one, it harvests the ready planets close to you, one after
	another, a little faster each time. Let go and it starts over from the slow speed.

	On a phone: TAP the circle to harvest one planet, HOLD it to start a streak. When you lift
	your finger the streak stops.

	The "Hold E" pop-up is drawn by this script (it replaces Roblox's own pop-up for harvesting):
	  * it stays up the whole streak and jumps straight to the next planet
	  * the ring around E fills over the time until the next harvest, so it speeds up with the streak
	  * it pops up a bit faster on each new planet

	A "HARVEST STREAK" counter shows how many you've got in a row, and a sound plays on every harvest.

	Needs: PlantingServer (it does the actual harvesting).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local harvestNextRemote = remotes:WaitForChild("HarvestNext")
local harvestedRemote = remotes:WaitForChild("PlantHarvested")

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local START_DELAY = 0.4      -- seconds you hold before the first harvest (the ring fills over this)
local FIRST_INTERVAL = 0.55  -- seconds between the first harvests of a streak
local SPEEDUP = 0.9          -- each harvest makes the next one this much sooner (closer to 1 = gentler)
local MIN_INTERVAL = 0.15    -- the fastest it ever goes (seconds between harvests)
local RESULT_SECONDS = 1.6   -- how long the counter stays up after you let go
local IDLE_RESET = 1.5       -- streak resets if nothing was harvested for this long while holding
local POP_TIME = 0.18        -- how long the pop-up takes to pop in when you're not in a streak

local RING_SEGMENTS = 28     -- the ring around E is made of this many ticks
local RING_RADIUS = 46       -- how far from the E the ticks sit (pixels)

-- sound played on every harvest. Paste a sound ID here, like "rbxassetid://123456789".
local HARVEST_SOUND_ID = "rbxassetid://111442878887237"
local HARVEST_SOUND_VOLUME = 4
local PITCH_RISE = true      -- the sound gets a little higher with every harvest in a streak

local RANGE = remotes:GetAttribute("StreakRange") or 6

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local uiInput = nil          -- the finger / mouse press that is holding the circle right now
local holdStart = nil
local holdByUI = false       -- this hold started on the on-screen circle (phone / mouse)
local firedThisHold = false
local wasHolding = false
local nextFire = 0
local interval = FIRST_INTERVAL
local streak = 0
local lastConfirm = 0
local cycleStart = 0         -- when the current ring fill began
local cycleLength = START_DELAY

local function streakColor(count)
	if count >= 20 then
		return Color3.fromRGB(255, 80, 200)
	elseif count >= 10 then
		return Color3.fromRGB(255, 110, 70)
	elseif count >= 5 then
		return Color3.fromRGB(255, 190, 60)
	end
	return Color3.new(1, 1, 1)
end

-- true only while the finger / mouse that pressed the circle is STILL down
local function uiIsHeld()
	return uiInput ~= nil
		and uiInput.UserInputState ~= Enum.UserInputState.End
		and uiInput.UserInputState ~= Enum.UserInputState.Cancel
end

local function keyIsHeld()
	return UserInputService:IsKeyDown(Enum.KeyCode.E)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonX)
end

local function isHolding()
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	return keyIsHeld() or uiIsHeld()
end

---------------------------------------------------------------------
-- Harvest sound
---------------------------------------------------------------------
local harvestSound = Instance.new("Sound")
harvestSound.Name = "HarvestSound"
harvestSound.SoundId = HARVEST_SOUND_ID
harvestSound.Volume = HARVEST_SOUND_VOLUME

local function playHarvestSound()
	if HARVEST_SOUND_ID == "" then
		return
	end
	local copy = harvestSound:Clone() -- a copy per harvest, so fast harvests can overlap
	if PITCH_RISE then
		copy.PlaybackSpeed = 1 + math.min(streak, 15) * 0.03
	end
	copy.Parent = playerGui
	copy:Play()
	Debris:AddItem(copy, 3)
end

---------------------------------------------------------------------
-- Counter on screen
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HarvestStreakGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local counter = Instance.new("TextLabel")
counter.AnchorPoint = Vector2.new(0.5, 1)
counter.Position = UDim2.new(0.5, 0, 1, -165)
counter.Size = UDim2.fromOffset(420, 44)
counter.BackgroundTransparency = 1
counter.Font = Enum.Font.FredokaOne
counter.TextSize = 30
counter.TextColor3 = Color3.new(1, 1, 1)
counter.TextStrokeTransparency = 0
counter.Text = ""
counter.Visible = false
counter.Parent = gui

local counterScale = Instance.new("UIScale")
counterScale.Parent = counter

local lastItem = Instance.new("TextLabel")
lastItem.AnchorPoint = Vector2.new(0.5, 1)
lastItem.Position = UDim2.new(0.5, 0, 1, -135)
lastItem.Size = UDim2.fromOffset(420, 26)
lastItem.BackgroundTransparency = 1
lastItem.Font = Enum.Font.FredokaOne
lastItem.TextSize = 18
lastItem.TextColor3 = Color3.fromRGB(205, 175, 255)
lastItem.TextStrokeTransparency = 0
lastItem.Text = ""
lastItem.Visible = false
lastItem.Parent = gui

local function hideCounter()
	streak = 0
	counter.Visible = false
	lastItem.Visible = false
end

---------------------------------------------------------------------
-- The "Hold E" pop-up (ours, so it can stay up and speed up)
---------------------------------------------------------------------
local promptGui = Instance.new("BillboardGui")
promptGui.Name = "HarvestPrompt"
promptGui.Size = UDim2.fromOffset(150, 150)
promptGui.AlwaysOnTop = true
promptGui.LightInfluence = 0
promptGui.ResetOnSpawn = false
promptGui.Active = true
promptGui.Enabled = false
promptGui.Parent = playerGui

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = promptGui

local popScale = Instance.new("UIScale")
popScale.Parent = root

local keyButton = Instance.new("TextButton")
keyButton.AnchorPoint = Vector2.new(0.5, 0.5)
keyButton.Position = UDim2.fromScale(0.5, 0.5)
keyButton.Size = UDim2.fromOffset(58, 58)
keyButton.BackgroundColor3 = Color3.fromRGB(22, 16, 34)
keyButton.BackgroundTransparency = 0.1
keyButton.AutoButtonColor = false
keyButton.Font = Enum.Font.FredokaOne
keyButton.TextColor3 = Color3.new(1, 1, 1)
keyButton.Parent = root

if UserInputService.KeyboardEnabled then
	keyButton.Text = "E"
	keyButton.TextSize = 32
elseif UserInputService.GamepadEnabled then
	keyButton.Text = "X"
	keyButton.TextSize = 32
else
	keyButton.Text = "TAP"
	keyButton.TextSize = 18
end

local keyCorner = Instance.new("UICorner")
keyCorner.CornerRadius = UDim.new(1, 0)
keyCorner.Parent = keyButton

local keyStroke = Instance.new("UIStroke")
keyStroke.Color = Color3.new(1, 1, 1)
keyStroke.Thickness = 3
keyStroke.Transparency = 0.3
keyStroke.Parent = keyButton

local actionLabel = Instance.new("TextLabel")
actionLabel.AnchorPoint = Vector2.new(0.5, 0.5)
actionLabel.Position = UDim2.new(0.5, 0, 0.5, RING_RADIUS + 20)
actionLabel.Size = UDim2.fromOffset(120, 22)
actionLabel.BackgroundTransparency = 1
actionLabel.Font = Enum.Font.FredokaOne
actionLabel.TextSize = 18
actionLabel.TextColor3 = Color3.new(1, 1, 1)
actionLabel.TextStrokeTransparency = 0
actionLabel.Text = UserInputService.KeyboardEnabled and "Harvest" or "Tap / hold"
actionLabel.Parent = root

-- the ring: little ticks around the E that light up as the harvest gets closer
local segments = {}
for i = 1, RING_SEGMENTS do
	local angle = math.rad((i - 1) / RING_SEGMENTS * 360)
	local tick = Instance.new("Frame")
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.new(0.5, math.sin(angle) * RING_RADIUS, 0.5, -math.cos(angle) * RING_RADIUS)
	tick.Size = UDim2.fromOffset(5, 13)
	tick.Rotation = math.deg(angle)
	tick.BackgroundColor3 = Color3.new(1, 1, 1)
	tick.BackgroundTransparency = 0.75
	tick.BorderSizePixel = 0
	local tickCorner = Instance.new("UICorner")
	tickCorner.CornerRadius = UDim.new(0, 3)
	tickCorner.Parent = tick
	tick.Parent = root
	segments[i] = tick
end

-- pressing the circle (finger or mouse). We remember THAT press and only count it as
-- held until that same finger / button is lifted, so it can never get stuck on.
keyButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		uiInput = input
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input == uiInput then
		uiInput = nil
	end
end)
-- if the game loses focus (you switch apps), let go
UserInputService.WindowFocusReleased:Connect(function()
	uiInput = nil
end)

---------------------------------------------------------------------
-- Hide Roblox's own "Hold E" pop-up on harvest prompts (ours replaces it)
---------------------------------------------------------------------
local function restyle(instance)
	if instance:IsA("ProximityPrompt") and instance.ActionText == "Harvest" then
		instance.Style = Enum.ProximityPromptStyle.Custom
	end
end
for _, instance in ipairs(workspace:GetDescendants()) do
	restyle(instance)
end
workspace.DescendantAdded:Connect(restyle)

---------------------------------------------------------------------
-- Finding the planet to harvest next
---------------------------------------------------------------------
-- the nearest ready planet of mine that's close enough, or nil
local function findTarget()
	local folder = workspace:FindFirstChild("PlantedPlanets")
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not folder or not rootPart then
		return nil
	end

	local best, bestDistance = nil, math.huge
	for _, model in ipairs(folder:GetChildren()) do
		if model:GetAttribute("Owner") == player.UserId then
			local body = model.PrimaryPart
			local prompt = body and body:FindFirstChildOfClass("ProximityPrompt")
			if prompt and prompt.Enabled then
				local distance = (body.Position - rootPart.Position).Magnitude - (model:GetAttribute("BodyRadius") or 0)
				if distance <= RANGE and distance < bestDistance then
					best, bestDistance = body, distance
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------
-- The streak
---------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	local now = os.clock()

	if not isHolding() then
		if wasHolding then
			-- you let go. A quick tap on the circle (phone / mouse) harvests one planet.
			if holdByUI and not firedThisHold and holdStart and now - holdStart < START_DELAY then
				if findTarget() then
					harvestNextRemote:FireServer()
				end
			end
		end
		wasHolding = false
		holdStart = nil
		interval = FIRST_INTERVAL -- the next streak starts slow again
		if streak > 0 and now - lastConfirm > RESULT_SECONDS then
			hideCounter()
		end
		return
	end

	wasHolding = true
	if not holdStart then
		holdStart = now
		holdByUI = not keyIsHeld()
		firedThisHold = false
		nextFire = now + START_DELAY
		cycleStart = now
		cycleLength = START_DELAY
	end
	if now < nextFire then
		return
	end

	if not findTarget() then
		-- nothing close enough to harvest: start over if it's been quiet for a while
		if streak > 0 and now - lastConfirm > IDLE_RESET then
			hideCounter()
			interval = FIRST_INTERVAL
		end
		return
	end

	harvestNextRemote:FireServer()
	firedThisHold = true

	-- the ring now fills over the time until the NEXT harvest, which gets a little shorter each time
	cycleStart = now
	cycleLength = interval
	nextFire = now + interval
	interval = math.max(interval * SPEEDUP, MIN_INTERVAL)
end)

---------------------------------------------------------------------
-- Drawing the pop-up and the ring every frame
---------------------------------------------------------------------
local currentTarget = nil

RunService.RenderStepped:Connect(function()
	local target = findTarget()
	if not target then
		promptGui.Enabled = false
		currentTarget = nil
		return
	end

	local holding = isHolding() and holdStart ~= nil

	-- a new planet: the pop-up jumps straight to it (it never goes away), popping faster in a streak
	if target ~= currentTarget then
		currentTarget = target
		promptGui.Adornee = target

		local popTime = POP_TIME
		if holding and streak > 0 then
			popTime = math.max(cycleLength * 0.45, 0.04)
		end
		popScale.Scale = 0.55
		TweenService:Create(
			popScale,
			TweenInfo.new(popTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
	promptGui.Enabled = true

	-- the ring
	local progress = 0
	if holding then
		progress = math.clamp((os.clock() - cycleStart) / cycleLength, 0, 1)
	end
	local lit = math.floor(progress * RING_SEGMENTS + 0.0001)
	local color = streakColor(streak)
	for i, tick in ipairs(segments) do
		if i <= lit then
			tick.BackgroundColor3 = color
			tick.BackgroundTransparency = 0
		else
			tick.BackgroundColor3 = Color3.new(1, 1, 1)
			tick.BackgroundTransparency = 0.75
		end
	end
	keyStroke.Color = holding and color or Color3.new(1, 1, 1)
end)

---------------------------------------------------------------------
-- Counter + sound on every harvest
---------------------------------------------------------------------
harvestedRemote.OnClientEvent:Connect(function(planetName, weight, tierName)
	streak += 1
	lastConfirm = os.clock()

	playHarvestSound()

	counter.Text = "HARVEST STREAK x" .. streak
	counter.TextColor3 = streakColor(streak)
	counter.TextSize = math.min(30 + streak, 52)
	counter.Visible = true

	local label = (tierName ~= "" and (tierName .. " ") or "") .. planetName
	lastItem.Text = string.format("%s  %.2f kg", label, weight)
	lastItem.Visible = true

	counterScale.Scale = 1.18
	TweenService:Create(
		counterScale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end)
