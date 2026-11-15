--[[
	TonDisplay  (Script, NOT a LocalScript)
	Put in: ServerScriptService

	Puts a big TON 618 on display in the world, where you place a Part named "TON618Spot".
	Its rings spin, its stars orbit and its rocks circle it (the PlanetSpinner LocalScript does the
	moving on each player's screen, so keep that script in StarterPlayerScripts).

	How to place it:
	  1. Insert a Part into Workspace and rename it exactly:  TON618Spot
	  2. Move it onto the ground where you want TON 618 to float above
	  3. Press Play

	The script turns the marker invisible and non-solid by itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PlanetBuilder = require(ReplicatedStorage:WaitForChild("PlanetBuilder"))

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local SPOT_NAME = "TON618Spot"
local PLANET_ID = "bh_ton618"
local DISPLAY_SCALE = 0.4   -- 1 = full size (huge). 0.4 makes the black hole about 9 studs wide
local LIFT = 9              -- how many studs it floats above the marker
local SHOW_LABEL = true     -- name tag over it

---------------------------------------------------------------------
-- Find the marker
---------------------------------------------------------------------
local spot = nil
for _ = 1, 30 do
	spot = workspace:FindFirstChild(SPOT_NAME, true)
	if spot then
		break
	end
	task.wait(1)
end

if not spot or not spot:IsA("BasePart") then
	warn("[TonDisplay] Couldn't find a Part named '" .. SPOT_NAME .. "' in Workspace. "
		.. "Insert a Part, rename it exactly " .. SPOT_NAME .. ", and move it where you want TON 618.")
	return
end

spot.Anchored = true
spot.CanCollide = false
spot.CanQuery = false
spot.CanTouch = false
spot.Transparency = 1

---------------------------------------------------------------------
-- Build it
---------------------------------------------------------------------
local planet = PlanetCatalog.Get(PLANET_ID)
if not planet then
	warn("[TonDisplay] Unknown planet id: " .. PLANET_ID)
	return
end

local folder = workspace:FindFirstChild("Displays")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Displays"
	folder.Parent = workspace
end

local center = spot.Position + Vector3.new(0, LIFT, 0)
local model = PlanetBuilder.Build(planet, folder, CFrame.new(center), DISPLAY_SCALE)
model.Name = "TON618Display"

if SHOW_LABEL then
	local color = PlanetCatalog.RarityColor(planet.Rarity)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 60)
	gui.StudsOffset = Vector3.new(0, planet.Look.Size * DISPLAY_SCALE + 6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 300
	gui.Parent = model.PrimaryPart

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 26
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	text.RichText = true
	text.Text = string.format('%s\n<font color="#%s" size="18">%s</font>', planet.Name, color:ToHex(), string.upper(planet.Rarity))
	text.Parent = gui
end

print("[TonDisplay] TON 618 placed at " .. tostring(center))
