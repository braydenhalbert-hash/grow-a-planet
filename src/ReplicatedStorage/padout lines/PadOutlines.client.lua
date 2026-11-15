-- PadOutlines: outlines the garden pads near the player, using a dynamic
-- highlight pool so the game never exceeds Roblox's 31-highlight render limit
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local POOL_SIZE = 18
local RANGE = 100
local BLACK = Color3.fromRGB (0, 0, 0)

local active = {} -- [pad] = Highlight

local function release(pad)
	local h = active[pad]
	if h then
		active[pad] = nil
		h:Destroy()
	end
end

while true do
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")

	local candidates = {}
	if root then
		for _, pad in CollectionService:GetTagged("GardenPad") do
			if pad:IsA("BasePart") then
				local dist = (pad.Position - root.Position).Magnitude
				if dist <= RANGE then
					table.insert(candidates, { pad = pad, dist = dist })
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.dist < b.dist
		end)
	end

	local keep = {}
	for i, c in ipairs(candidates) do
		if i > POOL_SIZE then
			break
		end
		keep[c.pad] = true
		if not active[c.pad] then
			local h = Instance.new("Highlight")
			h.Name = "PadOutline"
			h.FillTransparency = 1
			h.OutlineColor = BLACK
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = c.pad
			h.Parent = script
			active[c.pad] = h
		end
	end
	for pad in pairs(active) do
		if not keep[pad] then
			release(pad)
		end
	end

	task.wait(0.4)
end