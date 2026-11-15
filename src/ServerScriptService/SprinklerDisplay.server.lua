--[[
	SprinklerDisplay  (Script)  -- ServerScriptService

	Puts a real, working-looking sprinkler next to the Gear Mechanic's stand so players can see
	what they'd be buying. It's built from the same SprinklerModel as a placed sprinkler, so it
	spins, sprays stardust and glows exactly like one, but it belongs to nobody and doesn't water
	anything (Owner = 0, small display circle).

	Change DISPLAY_GEAR to show a different sprinkler (any Id from GearCatalog).
	Change OFFSET to move it (studs from the Gear Mechanic: +X = to his left as you face him).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
local SprinklerModel = require(ReplicatedStorage:WaitForChild("SprinklerModel"))

local DISPLAY_GEAR = "sprinkler_voidstardust" -- the LIMITED one
local OFFSET = Vector3.new(13, 0, 2.4)
local DISPLAY_RADIUS = 7 -- size of the glowing circle on the ground (real one is bigger)

local gear = GearCatalog.Get(DISPLAY_GEAR)
if not gear then
	warn("[SprinklerDisplay] no gear called " .. DISPLAY_GEAR)
	return
end

local shops = workspace:WaitForChild("SHOPS", 30)
local npc = shops and shops:WaitForChild("GearMechanic", 30)
local root = npc and (npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart", true))
if not root then
	warn("[SprinklerDisplay] couldn't find the GearMechanic")
	return
end

-- stand it on the ground beside the stand
local spot = root.Position + OFFSET
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { npc }
local hit = workspace:Raycast(spot + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
local ground = hit and hit.Position or (spot - Vector3.new(0, 3, 0))

local folder = workspace:FindFirstChild("Sprinklers")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Sprinklers"
	folder.Parent = workspace
end

local old = folder:FindFirstChild("ShopDisplay")
if old then
	old:Destroy()
end

local model = SprinklerModel.Build(gear, CFrame.new(ground))
model.Name = "ShopDisplay"
model:SetAttribute("Display", true)
model:SetAttribute("Owner", 0)
model:SetAttribute("GearId", gear.Id)
model:SetAttribute("Radius", DISPLAY_RADIUS)
model:SetAttribute("DustColor", gear.DustColor)

-- sign floating above it
local anchor = model:FindFirstChild("Origin") or model.PrimaryPart
local sign = Instance.new("BillboardGui")
sign.Name = "Sign"
sign.Size = UDim2.fromOffset(240, 78)
sign.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("CoreY") or 6) + 4, 0)
sign.MaxDistance = 90
sign.LightInfluence = 0
sign.Adornee = anchor
sign.Parent = anchor

local function line(text, size, color, y, h)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.Text = text
	l.Parent = sign
	return l
end
local rarityColor = Color3.fromRGB(190, 140, 255)
line("- LIMITED -", 16, rarityColor, 0, 20)
line(gear.Name, 22, gear.DustColor, 20, 28)
line(string.format("Planets grow %gx faster  ·  Gear shop", gear.GrowBoost or 1), 14, Color3.new(1, 1, 1), 50, 20)

model.Parent = folder
print("[SprinklerDisplay] showing " .. gear.Name .. " next to the Gear Mechanic")
