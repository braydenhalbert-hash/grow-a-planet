--[[
	OwnerTitleFX  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts   (name it exactly: OwnerTitleFX)

	Makes the OWNER title above your head shimmer, float gently, and twinkle with little
	4-point star sparkles that pop in and out right around the word (everyone sees it).
	The sparkles are drawn inside the title itself, so they stay crisp and always line up
	with the text, even while it floats.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SPARKLES = 12         -- how many twinkle at once
local TWINKLE_TIME = { 0.7, 1.3 } -- seconds each sparkle lives
local SIZE = { 22, 36 }     -- pixels
local COLORS = {
	Color3.fromRGB(255, 225, 90),
	Color3.fromRGB(255, 250, 200),
	Color3.fromRGB(255, 150, 225),
	Color3.fromRGB(255, 195, 60),
}

local rng = Random.new()

-- a 4-point star: two thin bars that fade at the tips, plus a bright centre
local function makeStar(parent)
	local star = Instance.new("Frame")
	star.Name = "Sparkle"
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.BackgroundTransparency = 1
	star.ZIndex = 5
	star.Parent = parent
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	local bars = {}
	for i, rotation in ipairs({ 0, 90 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(1, 0, 0.2, 0)
		bar.Rotation = rotation
		bar.BorderSizePixel = 0
		bar.ZIndex = 5
		bar.Parent = star
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = bar
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = fade
		gradient.Parent = bar
		bars[i] = bar
	end
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.3, 0.3)
	core.Rotation = 45
	core.BorderSizePixel = 0
	core.BackgroundColor3 = Color3.new(1, 1, 1)
	core.ZIndex = 6
	core.Parent = star
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = core
	return { Frame = star, Bars = bars, Core = core, Born = 0, Life = 1, Size = 14, Spin = 0 }
end

-- somewhere on the outline of the word itself (its corners, top and bottom edges, ends)
local function respawn(s, now, text)
	local bounds = text and text.TextBounds or Vector2.new(140, 40)
	if bounds.X < 10 then
		bounds = Vector2.new(140, 40)
	end
	local halfW, halfH = bounds.X / 2, bounds.Y / 2
	local side = rng:NextInteger(1, 6)
	local x, y
	if side <= 2 then -- along the top
		x, y = rng:NextNumber(-halfW, halfW), -halfH + rng:NextNumber(-6, 4)
	elseif side <= 3 then -- along the bottom
		x, y = rng:NextNumber(-halfW, halfW), halfH + rng:NextNumber(-4, 6)
	else -- at the two ends
		x = (side == 4 or side == 6) and (-halfW + rng:NextNumber(-10, 6)) or (halfW + rng:NextNumber(-6, 10))
		y = rng:NextNumber(-halfH, halfH)
	end
	s.Frame.Position = UDim2.new(0.5, x, 0.5, y)
	s.Born = now + rng:NextNumber(0, 0.4) -- small random delay so they don't sync up
	s.Life = rng:NextNumber(TWINKLE_TIME[1], TWINKLE_TIME[2])
	s.Size = rng:NextNumber(SIZE[1], SIZE[2])
	s.Spin = rng:NextNumber(-90, 90)
	local color = COLORS[rng:NextInteger(1, #COLORS)]
	for _, bar in ipairs(s.Bars) do
		bar.BackgroundColor3 = color
	end
	s.Frame.Size = UDim2.fromOffset(0, 0)
end

local titles = {} -- gui -> { sparkles }

local function setup(gui)
	if titles[gui] then
		return
	end
	local list = {}
	local now = os.clock()
	for i = 1, SPARKLES do
		local s = makeStar(gui)
		respawn(s, now, gui:FindFirstChildOfClass("TextLabel"))
		s.Born = now + (i - 1) * 0.12
		table.insert(list, s)
	end
	titles[gui] = list
end

for _, gui in ipairs(CollectionService:GetTagged("OwnerTitle")) do
	setup(gui)
end
CollectionService:GetInstanceAddedSignal("OwnerTitle"):Connect(setup)
CollectionService:GetInstanceRemovedSignal("OwnerTitle"):Connect(function(gui)
	titles[gui] = nil
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for gui, list in pairs(titles) do
		if not gui.Parent then
			titles[gui] = nil
			continue
		end
		-- shimmer + float
		local text = gui:FindFirstChildOfClass("TextLabel")
		local shine = text and text:FindFirstChild("Shine")
		if shine then
			shine.Offset = Vector2.new(math.sin(now * 1.6) * 0.5, 0)
		end
		gui.StudsOffset = Vector3.new(0, 3.5 + math.sin(now * 2) * 0.12, 0)

		-- twinkle: grow, spin a little, shrink away, then pop up somewhere else
		if gui.Enabled then
			for _, s in ipairs(list) do
				local t = (now - s.Born) / s.Life
				if t >= 1 then
					respawn(s, now, text)
				elseif t < 0 then
					s.Frame.Size = UDim2.fromOffset(0, 0)
				else
					local pop = math.sqrt(math.sin(t * math.pi)) -- 0 -> 1 -> 0, staying big for longer
					local size = s.Size * pop
					s.Frame.Size = UDim2.fromOffset(size, size)
					s.Frame.Rotation = s.Spin * t
					s.Core.BackgroundTransparency = 1 - pop
				end
			end
		end
	end
end)
