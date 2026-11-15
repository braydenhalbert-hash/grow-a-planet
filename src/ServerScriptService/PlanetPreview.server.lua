--[[
	PlanetPreview  (Script, NOT a LocalScript)
	Put in: ServerScriptService

	TEMPORARY: only runs inside Roblox Studio. When you press Play it lays out every planet
	in two rows in front of your character (planets and the Sun in the front row, black holes
	behind them) so you can look at them. They spin and orbit, because PlanetSpinner animates them.
	Delete this script when you're done looking.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PlanetBuilder = require(ReplicatedStorage:WaitForChild("PlanetBuilder"))

local PREVIEW_SCALE = 0.5   -- make smaller if a row is too wide
local GAP = 5               -- studs between planets
local HEIGHT = 18           -- how high above you
local DISTANCE = 70         -- how far in front of you (front row)
local ROW_SPACING = 80      -- how much farther back the black hole row is

local built = false

local function extent(planet)
	return planet.Look.Size * planet.Look.Extent * PREVIEW_SCALE
end

local function buildRow(folder, planets, origin)
	local total = 0
	for _, planet in ipairs(planets) do
		total += extent(planet) + GAP
	end

	local x = -total / 2
	for _, planet in ipairs(planets) do
		local width = extent(planet)
		local model = PlanetBuilder.Build(planet, folder, origin * CFrame.new(x + width / 2, 0, 0), PREVIEW_SCALE)
		x += width + GAP

		-- name + rarity label
		local color = PlanetCatalog.RarityColor(planet.Rarity)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 56)
		gui.StudsOffset = Vector3.new(0, planet.Look.Size * PREVIEW_SCALE * 0.9 + 4, 0)
		gui.AlwaysOnTop = true
		gui.Parent = model.PrimaryPart

		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.FredokaOne
		text.TextSize = 20
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0
		text.RichText = true
		text.Text = string.format(
			'%s\n<font color="#%s" size="15">%s</font>',
			planet.Name,
			color:ToHex(),
			string.upper(planet.Rarity)
		)
		text.Parent = gui
	end
end

local function buildAll(root)
	local folder = Instance.new("Folder")
	folder.Name = "PlanetPreview"
	folder.Parent = workspace

	local front, back = {}, {}
	for _, planet in ipairs(PlanetCatalog.Planets) do
		if planet.Group == "BlackHole" then
			table.insert(back, planet)
		else
			table.insert(front, planet)
		end
	end

	local origin = root.CFrame * CFrame.new(0, HEIGHT, -DISTANCE)
	buildRow(folder, front, origin)
	buildRow(folder, back, origin * CFrame.new(0, 0, -ROW_SPACING))
end

local function setup(player)
	local function onCharacter(character)
		if built then
			return
		end
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and not built then
			built = true
			buildAll(root)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(setup)
for _, player in ipairs(Players:GetPlayers()) do
	setup(player)
end
