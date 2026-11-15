--[[
	BaseService  (ModuleScript)
	Put in: ServerScriptService   (name it exactly: BaseService)

	Garden bases. Each base has a gate. You mark a gate by putting a Part named  BaseGate
	in the gateway (see below). Then:

	  * Every GROWING BEDS pad belongs to the nearest gate's base (or to the gate's own
	    Model / Folder, if you put the BaseGate inside a Model or Folder that holds that base's beds).
	  * One base per player. Planting your first planet on an EMPTY base claims it.
	  * Only the owner can plant on a claimed base.
	  * A title floats over every base: an empty base says so, a claimed one shows the owner's
	    profile picture and name.
	  * Walking through a gate tells you whether the base is empty, yours, or someone else's.
	  * Your base is saved: when you come back it's given to you again if it's free.
	  * When you leave, your base is free for someone else.

	If there are no BaseGate parts in the game, none of this does anything and everyone can
	plant anywhere, like before.

	Used by PlantingServer. Needs GameData (same folder).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local GameData = require(script.Parent:WaitForChild("GameData"))

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local GATE_NAME = "BaseGate"       -- name of the marker Part in each gateway
local PAD_TAG = "GardenPad"        -- your PlantingSpots script tags the GROWING BEDS with this
local TITLE_HEIGHT = 26            -- studs above the highest bed that the title floats
local RECLAIM_RADIUS = 30          -- how close a saved base position has to be to count as the same base
local AUTO_RECLAIM = false       -- false: you only get a base by planting a seed on an empty one (your saved planets move there)
local GATE_MESSAGE_COOLDOWN = 4    -- seconds before the same gate message shows again
local FONT = Enum.Font.FredokaOne

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local BaseService = {}

local bases = {}            -- gate part -> base
local padToBase = {}        -- bed -> base
local playerBase = {}       -- player -> base
local setupDone = {}        -- player -> true once their saved base has been handed back
local lastGateMessage = {}  -- player -> { Base, Time }
local built = false
local rebuildQueued = false

---------------------------------------------------------------------
-- Pop-up messages (the same "Notice" the shop uses)
---------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("PlanetRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "PlanetRemotes"
	remotes.Parent = ReplicatedStorage
end

local noticeRemote = remotes:FindFirstChild("Notice")
if not noticeRemote then
	noticeRemote = Instance.new("RemoteEvent")
	noticeRemote.Name = "Notice"
	noticeRemote.Parent = remotes
end

local function notice(player, text, kind)
	noticeRemote:FireClient(player, text, kind or "ok")
end

---------------------------------------------------------------------
-- Titles above the bases
---------------------------------------------------------------------
local titleFolder = workspace:FindFirstChild("BaseTitles")
if not titleFolder then
	titleFolder = Instance.new("Folder")
	titleFolder.Name = "BaseTitles"
	titleFolder.Parent = workspace
end

local function buildTitle(base)
	local part = Instance.new("Part")
	part.Name = "BaseTitle"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = base.Gate.Position
	part.Parent = titleFolder

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(340, 100)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 800
	gui.LightInfluence = 0
	gui.Adornee = part
	gui.Parent = part

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(10, 6, 20)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = frame
	local frameStroke = Instance.new("UIStroke")
	frameStroke.Thickness = 3
	frameStroke.Color = Color3.fromRGB(150, 150, 165)
	frameStroke.Parent = frame

	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0, 0.5)
	image.Position = UDim2.new(0, 12, 0.5, 0)
	image.Size = UDim2.fromOffset(76, 76)
	image.BackgroundColor3 = Color3.fromRGB(30, 14, 50)
	image.BorderSizePixel = 0
	image.Visible = false
	image.Parent = frame
	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(1, 0)
	imageCorner.Parent = image
	local imageStroke = Instance.new("UIStroke")
	imageStroke.Thickness = 3
	imageStroke.Color = Color3.fromRGB(255, 215, 90)
	imageStroke.Parent = image

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT
	nameLabel.TextSize = 28
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextStrokeTransparency = 0
	nameLabel.Parent = frame

	local subLabel = Instance.new("TextLabel")
	subLabel.BackgroundTransparency = 1
	subLabel.Font = FONT
	subLabel.TextSize = 18
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.TextTruncate = Enum.TextTruncate.AtEnd
	subLabel.TextStrokeTransparency = 0
	subLabel.Parent = frame

	base.Title = {
		Part = part,
		Frame = frame,
		FrameStroke = frameStroke,
		Image = image,
		Name = nameLabel,
		Sub = subLabel,
	}
end

local function setTitle(base)
	local title = base.Title
	local owner = base.Owner

	if owner then
		title.Image.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", owner.UserId)
		title.Image.Visible = true
		title.Name.Position = UDim2.new(0, 100, 0, 14)
		title.Name.Size = UDim2.new(1, -112, 0, 38)
		title.Sub.Position = UDim2.new(0, 100, 0, 54)
		title.Sub.Size = UDim2.new(1, -112, 0, 28)
		title.Name.Text = owner.DisplayName
		title.Sub.Text = "@" .. owner.Name
		title.Sub.TextColor3 = Color3.fromRGB(255, 225, 130)
		title.FrameStroke.Color = Color3.fromRGB(255, 215, 90)
	else
		title.Image.Visible = false
		title.Name.Position = UDim2.new(0, 20, 0, 14)
		title.Name.Size = UDim2.new(1, -40, 0, 38)
		title.Sub.Position = UDim2.new(0, 20, 0, 54)
		title.Sub.Size = UDim2.new(1, -40, 0, 28)
		title.Name.Text = "EMPTY BASE"
		title.Sub.Text = "Plant a seed to claim it"
		title.Sub.TextColor3 = Color3.fromRGB(190, 190, 205)
		title.FrameStroke.Color = Color3.fromRGB(150, 150, 165)
	end
end

local function updateBase(base)
	base.Title.Part.Position = Vector3.new(base.Center.X, base.Top + TITLE_HEIGHT, base.Center.Z)
	setTitle(base)

	-- the planting preview on each player's screen reads this (0 = empty)
	local ownerId = base.Owner and base.Owner.UserId or 0
	for _, pad in ipairs(base.Pads) do
		pad:SetAttribute("BaseOwner", ownerId)
	end
end

---------------------------------------------------------------------
-- Working out which beds belong to which base
---------------------------------------------------------------------
local function nearestBase(position, maxDistance)
	local best, bestDistance = nil, maxDistance
	for _, base in pairs(bases) do
		local dx = base.Center.X - position.X
		local dz = base.Center.Z - position.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < bestDistance then
			best, bestDistance = base, distance
		end
	end
	return best
end

local function rebuild()
	rebuildQueued = false

	for _, base in pairs(bases) do
		base.Pads = {}
	end
	table.clear(padToBase)

	-- a Model/Folder that holds more than one gate can't tell the bases apart, so those don't count
	local gatesInContainer = {}
	for _, base in pairs(bases) do
		if base.Container then
			gatesInContainer[base.Container] = (gatesInContainer[base.Container] or 0) + 1
		end
	end

	for _, pad in ipairs(CollectionService:GetTagged(PAD_TAG)) do
		if pad:IsA("BasePart") then
			-- 1) the gate whose own Model/Folder holds this bed
			local chosen, chosenDepth = nil, -1
			for _, base in pairs(bases) do
				local container = base.Container
				if container and gatesInContainer[container] == 1 and pad:IsDescendantOf(container) then
					local depth, node = 0, container
					while node do
						depth += 1
						node = node.Parent
					end
					if depth > chosenDepth then
						chosen, chosenDepth = base, depth
					end
				end
			end

			-- 2) otherwise the nearest gate
			if not chosen then
				local bestDistance = math.huge
				for _, base in pairs(bases) do
					local distance = (base.Gate.Position - pad.Position).Magnitude
					if distance < bestDistance then
						chosen, bestDistance = base, distance
					end
				end
			end

			if chosen then
				table.insert(chosen.Pads, pad)
				padToBase[pad] = chosen
			end
		end
	end

	for _, base in pairs(bases) do
		if #base.Pads > 0 then
			local minX, maxX, minZ, maxZ, top = math.huge, -math.huge, math.huge, -math.huge, -math.huge
			for _, pad in ipairs(base.Pads) do
				local position, half = pad.Position, pad.Size / 2
				minX = math.min(minX, position.X - half.X)
				maxX = math.max(maxX, position.X + half.X)
				minZ = math.min(minZ, position.Z - half.Z)
				maxZ = math.max(maxZ, position.Z + half.Z)
				top = math.max(top, position.Y + half.Y)
			end
			base.Center = Vector3.new((minX + maxX) / 2, top, (minZ + maxZ) / 2)
			base.Top = top
		else
			base.Center = base.Gate.Position
			base.Top = base.Gate.Position.Y
		end
		updateBase(base)
	end

	built = true
end

local function scheduleRebuild()
	if rebuildQueued then
		return
	end
	rebuildQueued = true
	task.delay(0.5, rebuild)
end

---------------------------------------------------------------------
-- Gates
---------------------------------------------------------------------
local function onGateTouched(base, hit)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local now = os.clock()
	local last = lastGateMessage[player]
	if last and last.Base == base and now - last.Time < GATE_MESSAGE_COOLDOWN then
		return
	end
	lastGateMessage[player] = { Base = base, Time = now }

	-- an empty base + you have no base + you have saved planets: walking up claims it
	if not base.Owner and not playerBase[player] and BaseService.WalkClaim then
		local ok, claimed = pcall(BaseService.WalkClaim, player, base)
		if ok and claimed then
			return
		end
	end

	if base.Owner == player then
		notice(player, "Welcome to your base!", "ok")
	elseif base.Owner then
		notice(player, base.Owner.DisplayName .. "'s base", "ok")
	elseif playerBase[player] then
		notice(player, "This base is empty, but you already have a base.", "ok")
	else
		notice(player, "This base is empty! Plant a seed on it to claim it.", "ok")
	end
end

local function createBase(gate)
	if bases[gate] then
		return
	end

	gate.Anchored = true
	gate.CanCollide = false
	gate.CanQuery = false
	gate.CanTouch = true
	gate.Transparency = 1

	local container = gate.Parent
	if container == workspace then
		container = nil
	end

	local base = {
		Gate = gate,
		Container = container,
		Pads = {},
		Center = gate.Position,
		Top = gate.Position.Y,
		Owner = nil,
	}
	bases[gate] = base
	buildTitle(base)
	updateBase(base)

	gate.Touched:Connect(function(hit)
		onGateTouched(base, hit)
	end)

	scheduleRebuild()
end

local function considerGate(instance)
	if instance:IsA("BasePart") and instance.Name == GATE_NAME then
		createBase(instance)
	end
end

for _, instance in ipairs(workspace:GetDescendants()) do
	considerGate(instance)
end
workspace.DescendantAdded:Connect(considerGate)
CollectionService:GetInstanceAddedSignal(PAD_TAG):Connect(scheduleRebuild)
CollectionService:GetInstanceRemovedSignal(PAD_TAG):Connect(scheduleRebuild)
task.delay(1.5, rebuild)

---------------------------------------------------------------------
-- API (used by PlantingServer)
---------------------------------------------------------------------
function BaseService.HasBases()
	return next(bases) ~= nil
end

function BaseService.BaseForPad(pad)
	return padToBase[pad]
end

function BaseService.BaseOf(player)
	return playerBase[player]
end

-- which base a spot belongs to (a saved planet's position, for example)
function BaseService.BaseAtPosition(position)
	for pad, base in pairs(padToBase) do
		local localPos = pad.CFrame:PointToObjectSpace(position)
		local half = pad.Size / 2
		if math.abs(localPos.X) <= half.X + 2 and math.abs(localPos.Z) <= half.Z + 2 and math.abs(localPos.Y - half.Y) <= 6 then
			return base
		end
	end
	return nearestBase(position, math.huge)
end

function BaseService.Claim(player, base)
	if base.Owner or playerBase[player] then
		return false
	end
	base.Owner = player
	playerBase[player] = base
	player:SetAttribute("HasBase", true)
	updateBase(base)

	-- remember it, so you get this base back next time
	local data = GameData.Get(player)
	if data then
		data.Base = {
			X = base.Center.X, Y = base.Top, Z = base.Center.Z,
			GateX = base.Gate.Position.X, GateZ = base.Gate.Position.Z, -- the gate never moves, so this always matches
		}
	end
	return true
end

function BaseService.Release(player)
	local base = playerBase[player]
	if base then
		base.Owner = nil
		playerBase[player] = nil
		updateBase(base)
	end
end

-- waits until the player's saved base has been handed back (or found taken)
function BaseService.WaitForSetup(player)
	while player.Parent and not setupDone[player] do
		task.wait(0.05)
	end
end

---------------------------------------------------------------------
-- Players
---------------------------------------------------------------------
local function setupPlayer(player)
	local data = GameData.WaitFor(player)
	if not data or not player.Parent then
		return
	end

	-- wait for the beds to be sorted into bases (up to a few seconds), and for the beds to be tagged
	-- (a base's centre moves once its beds are found, so we must not look for your base before that)
	local waited = 0
	while (not built or next(padToBase) == nil) and waited < 15 do
		task.wait(0.1)
		waited += 0.1
	end

	if AUTO_RECLAIM and next(bases) ~= nil then
		local base = nil
		local saved = data.Base

		-- 1) the saved gate (never moves)
		if saved and saved.GateX then
			for _, candidate in pairs(bases) do
				local dx = candidate.Gate.Position.X - saved.GateX
				local dz = candidate.Gate.Position.Z - saved.GateZ
				if math.sqrt(dx * dx + dz * dz) < 8 then
					base = candidate
					break
				end
			end
		end
		-- 2) the saved centre
		if not base and saved then
			base = nearestBase(Vector3.new(saved.X, 0, saved.Z), RECLAIM_RADIUS)
		end
		-- 3) wherever your planets are
		if not base and data.Plants and data.Plants[1] then
			local first = data.Plants[1]
			base = BaseService.BaseAtPosition(Vector3.new(first.X, first.Y, first.Z))
		end

		if base and not base.Owner and player.Parent then
			BaseService.Claim(player, base)
			notice(player, "Welcome back! Your base is ready.", "ok")
		elseif base and base.Owner then
			warn("[BaseService] " .. player.Name .. "'s saved base is taken by " .. base.Owner.Name)
		elseif not base then
			warn("[BaseService] couldn't find " .. player.Name .. "'s saved base")
		end
	end

	setupDone[player] = true
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	BaseService.Release(player)
	setupDone[player] = nil
	lastGateMessage[player] = nil
end)

return BaseService
