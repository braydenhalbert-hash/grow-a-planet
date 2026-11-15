--[[
	AdminServer  (Script)
	Put in: ServerScriptService   (new Script, name it exactly: AdminServer)

	The server side of your personal admin panel. ONLY the people listed in OWNER_USER_IDS
	(and the owner of the game) can use it. Everything is checked here on the server, so nobody
	else can use the panel even if they find the buttons.

	Needs: GameData (ServerScriptService), PlanetCatalog + PackCatalog + MutationCatalog (ReplicatedStorage),
	       and the updated GameServer + PlantingServer (they listen for the admin requests).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local GameData = require(script.Parent:WaitForChild("GameData"))
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PackCatalog = require(ReplicatedStorage:WaitForChild("PackCatalog"))
local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local OWNER_USER_IDS = {
	446120355, -- boypoooop (you). Add more Roblox user ids here, separated by commas, if you ever want to
}
local MAX_COINS = 1e15       -- the panel never sets coins above this
local MAX_GIVE = 999         -- most seeds / packs per click

---------------------------------------------------------------------
-- Who is an admin
---------------------------------------------------------------------
local function isAdmin(player)
	if table.find(OWNER_USER_IDS, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and player.UserId == game.CreatorId then
		return true
	end
	-- unpublished place being tested in Studio: you are the owner
	if RunService:IsStudio() and game.CreatorId == 0 then
		return true
	end
	return false
end

---------------------------------------------------------------------
-- The "OWNER" title above your head (everybody sees it)
---------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")
local TITLE_TEXT = "OWNER"

local function addTitle(character)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	local old = head:FindFirstChild("OwnerTitle")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerTitle"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(260, 60)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.ResetOnSpawn = false
	gui.Parent = head

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.Text = TITLE_TEXT
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Parent = gui

	local outline = Instance.new("UIStroke")
	outline.Thickness = 3.5
	outline.Color = Color3.fromRGB(40, 10, 70)
	outline.Parent = text

	local shine = Instance.new("UIGradient")
	shine.Name = "Shine"
	shine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 60)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 245, 190)),
		ColorSequenceKeypoint.new(0.65, Color3.fromRGB(255, 140, 220)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 60)),
	})
	shine.Parent = text

	-- the little sparkles drifting off it
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 150, 230))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.5, 0)
	sparkle.Lifetime = NumberRange.new(0.8, 1.5)
	sparkle.Rate = 6
	sparkle.Speed = NumberRange.new(0.5, 2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	local anchor = Instance.new("Attachment")
	anchor.Position = Vector3.new(0, 3.5, 0)
	anchor.Parent = head
	sparkle.Parent = anchor

	CollectionService:AddTag(gui, "OwnerTitle") -- OwnerTitleFX (client) makes it shimmer and float
end

local function watchOwner(player)
	if not isAdmin(player) then
		return
	end
	player.CharacterAdded:Connect(addTitle)
	if player.Character then
		task.spawn(addTitle, player.Character)
	end
end
Players.PlayerAdded:Connect(watchOwner)
for _, player in ipairs(Players:GetPlayers()) do
	watchOwner(player)
end

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("PlanetRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "PlanetRemotes"
	remotes.Parent = ReplicatedStorage
end
local function getRemote(name)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end
local actionRemote = getRemote("AdminAction")
local noticeRemote = getRemote("Notice")

local function notice(player, text, kind)
	noticeRemote:FireClient(player, text, kind or "ok")
end

local function mark(player)
	player:SetAttribute("IsAdmin", isAdmin(player) or nil)
end
Players.PlayerAdded:Connect(mark)
for _, player in ipairs(Players:GetPlayers()) do
	mark(player)
end

---------------------------------------------------------------------
-- The other scripts (GameServer / PlantingServer) do the item and garden work
---------------------------------------------------------------------
local function bridge(name)
	return ServerStorage:WaitForChild(name, 10)
end

local function toNumber(value, low, high)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.clamp(value, low, high)
end

---------------------------------------------------------------------
-- Requests from the panel
---------------------------------------------------------------------
local last = {}

actionRemote.OnServerEvent:Connect(function(player, action, a, b)
	if not isAdmin(player) or type(action) ~= "string" then
		return
	end
	local now = os.clock()
	if last[player] and now - last[player] < 0.08 then
		return
	end
	last[player] = now

	local data = GameData.Get(player)
	if not data then
		notice(player, "Your data hasn't loaded yet.", "error")
		return
	end

	if action == "coins_add" then
		local amount = toNumber(a, -MAX_COINS, MAX_COINS)
		if not amount then
			return
		end
		data.Coins = math.clamp(data.Coins + amount, 0, MAX_COINS)
		player:SetAttribute("Coins", data.Coins)
		notice(player, string.format("Coins changed by %s", string.format("%.0f", amount)))

	elseif action == "coins_set" then
		local amount = toNumber(a, 0, MAX_COINS)
		if not amount then
			return
		end
		data.Coins = math.floor(amount)
		player:SetAttribute("Coins", data.Coins)
		notice(player, "Coins set to " .. string.format("%.0f", data.Coins))

	elseif action == "give_seed" then
		local planet = type(a) == "string" and PlanetCatalog.Get(a)
		local amount = toNumber(b, 1, MAX_GIVE)
		if not planet or not amount then
			return
		end
		local event = bridge("AdminBridge_Game")
		if event then
			event:Fire(player, "seed", planet.Id, math.floor(amount))
			notice(player, string.format("Gave %d x %s seed", math.floor(amount), planet.Name))
		end

	elseif action == "give_pack" then
		local pack = type(a) == "string" and PackCatalog.Get(a)
		local amount = toNumber(b, 1, MAX_GIVE)
		if not pack or not amount then
			return
		end
		local event = bridge("AdminBridge_Game")
		if event then
			event:Fire(player, "pack", pack.Id, math.floor(amount))
			notice(player, string.format("Gave %d x %s", math.floor(amount), pack.Name))
		end

	elseif action == "restock" then
		local event = bridge("AdminBridge_Game")
		if event then
			event:Fire(player, "restock")
			notice(player, "Shops restocked")
		end

	elseif action == "grow" or action == "harvest" then
		local event = bridge("AdminBridge_Garden")
		if event then
			event:Fire(player, action)
		end

	elseif action == "mutate" then
		local id = nil
		if a ~= "none" then
			local mutation = type(a) == "string" and MutationCatalog.Get(a)
			if not mutation then
				return
			end
			id = mutation.Id
		end
		local event = bridge("AdminBridge_Garden")
		if event then
			event:Fire(player, "mutate", id)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)

print("[AdminServer] ready (admins: " .. #OWNER_USER_IDS .. " listed)")
