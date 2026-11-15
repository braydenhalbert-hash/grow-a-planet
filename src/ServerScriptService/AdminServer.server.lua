--[[
	AdminServer  (Script)  -- ServerScriptService

	The server side of the admin panel (AdminPanel). EVERYTHING is checked here: who is staff, what
	their role allows, that every id / amount is valid, and how fast they send requests. The panel only
	shows buttons; a regular player firing the remotes gets nothing.

	STAFF + ROLES (edit below):
	  Owner      everything
	  Admin      everything except resetting players' data
	  Moderator  view players, teleport, kick
	  The game's creator is always Owner. In Studio on an unpublished place you are Owner.

	Item database: built live from PlanetCatalog, PackCatalog, GearCatalog, MutationCatalog and the
	rarity tables every time the panel opens, so new seeds, planets, packs, sprinklers, gear,
	mutations and rarities appear by themselves. Currencies are every number saved in a player's
	data (Coins today), so a new currency shows up too.

	Talks to: GameData, LiveOps, GameServer (InventoryAPI, AdminBridge_Game), PlantingServer
	(GardenAPI, AdminBridge_Garden), SprinklerServer (SprinklerAPI), BaseService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local GameData = require(script.Parent:WaitForChild("GameData"))
local LiveOps = require(script.Parent:WaitForChild("LiveOps"))
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PackCatalog = require(ReplicatedStorage:WaitForChild("PackCatalog"))
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))
local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))
local BaseService do
	local module = script.Parent:FindFirstChild("BaseService")
	BaseService = module and require(module) or { BaseOf = function() return nil end }
end

---------------------------------------------------------------------
-- STAFF
---------------------------------------------------------------------
local STAFF = {
	[446120355] = "Owner", -- boypoooop
	-- [123456789] = "Admin",
	-- [987654321] = "Moderator",
}

local ROLES = {
	Owner = { Rank = 3, Title = "OWNER", Perms = { view = true, items = true, economy = true, world = true, teleport = true, kick = true, ban = true, reset = true } },
	Admin = { Rank = 2, Title = "ADMIN", Perms = { view = true, items = true, economy = true, world = true, teleport = true, kick = true, ban = true } },
	Moderator = { Rank = 1, Title = "MOD", Perms = { view = true, teleport = true, kick = true } },
}

-- which permission each command needs
local NEEDS = {
	give = "items", remove = "items", remove_planet = "items", clear_inventory = "items",
	spawn_plant = "items", garden_remove = "items", garden_grow = "items", garden_harvest = "items", garden_mutate = "items",
	sprinkler_spawn = "items", sprinkler_remove = "items",
	currency = "economy",
	multiplier = "world", event_start = "world", event_stop = "world", weather = "world", announce = "world",
	restock = "world", liveops_reset = "world",
	teleport = "teleport", respawn = "teleport",
	kick = "kick", ban = "ban", unban = "ban", reset = "reset",
}

local MAX_AMOUNT = 1e6        -- most items per command
local MAX_CURRENCY = 1e15     -- currencies never go above this
local MAX_COMMANDS_PER_SECOND = 12

local function roleOf(player)
	local role = STAFF[player.UserId]
	if role and ROLES[role] then
		return role
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and player.UserId == game.CreatorId then
		return "Owner"
	end
	if RunService:IsStudio() and game.CreatorId == 0 then
		return "Owner" -- unpublished place in Studio: you're testing your own game
	end
	return nil
end

local function can(player, perm)
	local role = roleOf(player)
	return role ~= nil and ROLES[role].Perms[perm] == true
end

---------------------------------------------------------------------
-- Staff title above their head (everybody sees it)
---------------------------------------------------------------------
local function addTitle(character, titleText)
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
	gui.Size = UDim2.fromOffset(300, 90) -- room around the word for the sparkles
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.ResetOnSpawn = false
	gui.Parent = head
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromOffset(260, 60)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.Text = titleText
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
	-- the sparkles are drawn by OwnerTitleFX on each player's screen, right around the word
	CollectionService:AddTag(gui, "OwnerTitle") -- OwnerTitleFX (client) makes it shimmer and float
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
local function getRemote(name, class)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(class or "RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end
local queryRemote = getRemote("AdminQuery", "RemoteFunction")
local commandRemote = getRemote("AdminCommand", "RemoteFunction")
local noticeRemote = getRemote("Notice")

local function notice(player, text, kind)
	noticeRemote:FireClient(player, text, kind or "ok")
end

local function api(name)
	return ServerStorage:WaitForChild(name, 10)
end

---------------------------------------------------------------------
-- Bans (saved, so they last across servers)
---------------------------------------------------------------------
local banStore = DataStoreService:GetDataStore("AdminBans_v1")
local banCache = {} -- userId -> ban (or false)

local function banKey(userId)
	return "u" .. userId
end

local function getBan(userId)
	if banCache[userId] ~= nil then
		return banCache[userId] or nil
	end
	local ok, ban = pcall(function()
		return banStore:GetAsync(banKey(userId))
	end)
	if not ok then
		return nil
	end
	if type(ban) == "table" and ban.Until and ban.Until > 0 and os.time() > ban.Until then
		ban = nil -- ran out
	end
	banCache[userId] = ban or false
	return ban
end

local function banMessage(ban)
	local length = (ban.Until or 0) == 0 and "permanently" or ("until " .. os.date("!%Y-%m-%d %H:%M UTC", ban.Until))
	return "You are banned " .. length .. ". Reason: " .. (ban.Reason ~= "" and ban.Reason or "none")
end

local function updateBanIndex(userId, name, add)
	pcall(function()
		banStore:UpdateAsync("index", function(index)
			index = type(index) == "table" and index or {}
			index[tostring(userId)] = add and name or nil
			return index
		end)
	end)
end

---------------------------------------------------------------------
-- Admin log (this server, newest first)
---------------------------------------------------------------------
local logs = {}
local function log(admin, action, target, detail)
	table.insert(logs, 1, { Time = os.time(), Admin = admin.Name, Action = action, Target = target or "", Detail = detail or "" })
	if #logs > 150 then
		table.remove(logs)
	end
	print(string.format("[Admin] %s %s %s %s", admin.Name, action, target or "", detail or ""))
end

---------------------------------------------------------------------
-- Players joining: staff marks + titles, ban check
---------------------------------------------------------------------
local function onJoin(player)
	local ban = getBan(player.UserId)
	if ban and roleOf(player) ~= "Owner" then
		player:Kick(banMessage(ban))
		return
	end
	local role = roleOf(player)
	if role then
		player:SetAttribute("IsAdmin", true)
		player:SetAttribute("AdminRole", role)
		local title = ROLES[role].Title
		player.CharacterAdded:Connect(function(character)
			addTitle(character, title)
		end)
		if player.Character then
			task.spawn(addTitle, player.Character, title)
		end
	end
end
Players.PlayerAdded:Connect(onJoin)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, player)
end

---------------------------------------------------------------------
-- Live item database (nothing hard-coded: every catalog entry shows up)
---------------------------------------------------------------------
local function rarityList()
	local list = {}
	for name, r in pairs(PlanetCatalog.Rarities or {}) do
		table.insert(list, { Name = name, Order = r.Order or 99, Color = r.Color })
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

local function fmt(n)
	if type(n) ~= "number" then
		return "?"
	end
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while math.abs(n) >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	return (i == 1 and string.format("%d", n) or string.format("%.1f", n)) .. units[i]
end

local function tiers()
	local garden = api("GardenAPI")
	local ok, list = pcall(function()
		return garden and garden:Invoke("tiers")
	end)
	return ok and list or {}
end

local function currencyFields()
	-- every top-level number in saved data is a currency (Coins today; new ones appear on their own)
	local fields, seen = {}, {}
	for _, p in ipairs(Players:GetPlayers()) do
		local data = GameData.Get(p)
		if data then
			for key, value in pairs(data) do
				if type(value) == "number" and not seen[key] then
					seen[key] = true
					table.insert(fields, key)
				end
			end
		end
	end
	if not seen.Coins then
		table.insert(fields, 1, "Coins")
	end
	table.sort(fields)
	return fields
end

local function buildDatabase()
	local seeds, planets = {}, {}
	for _, p in ipairs(PlanetCatalog.Planets) do
		local info = string.format("%s · Cost %s · Sells %s · Grows %ss", p.Group or "Planet", fmt(p.Cost), fmt(p.SellValue), fmt(p.GrowTime))
		table.insert(seeds, { Id = p.Id, Name = p.Name .. " Seed", Rarity = p.Rarity, Group = p.Group, Info = info, Shop = p.Buyable ~= false })
		table.insert(planets, { Id = p.Id, Name = p.Name, Rarity = p.Rarity, Group = p.Group,
			Info = string.format("%s · %s-%s kg · Sells %s", p.Group or "Planet", tostring(p.Weight and p.Weight[1] or "?"), tostring(p.Weight and p.Weight[2] or "?"), fmt(p.SellValue)) })
	end
	local packs = {}
	for _, pack in ipairs(PackCatalog.Packs) do
		table.insert(packs, { Id = pack.Id, Name = pack.Name, Rarity = pack.Tier, Info = "Seed pack · Cost " .. fmt(pack.Cost) })
	end
	local gear = {}
	for _, g in ipairs(GearCatalog.Gear) do
		local info = (g.Kind or "Gear") .. " · Cost " .. fmt(g.Cost)
		if g.Radius then
			info ..= string.format(" · Radius %d · %dm · %sx growth", g.Radius, math.floor((g.Duration or 0) / 60), tostring(g.GrowBoost or 1))
		end
		table.insert(gear, { Id = g.Id, Name = g.Name, Rarity = g.Rarity, Group = g.Kind, Info = info, Placeable = g.Kind == "Sprinkler" })
	end
	local mutations, seenMut = {}, {}
	local mutIds = table.clone(MutationCatalog.Order)
	for id in pairs(MutationCatalog.Mutations or {}) do
		if not table.find(mutIds, id) then
			table.insert(mutIds, id) -- added to the catalog but not to Order: still shows up
		end
	end
	for _, id in ipairs(mutIds) do
		local m = MutationCatalog.Get(id)
		if m and not seenMut[id] then
			seenMut[id] = true
			table.insert(mutations, { Id = id, Name = m.Name or id, Info = string.format("%sx coins · %.1f%% chance", tostring(m.CoinMult or 1), (m.Chance or 0) * 100) })
		end
	end
	return {
		Categories = {
			{ Id = "Seed", Name = "Seeds", Items = seeds },
			{ Id = "Planet", Name = "Planets", Items = planets },
			{ Id = "Pack", Name = "Packs", Items = packs },
			{ Id = "Gear", Name = "Gear", Items = gear },
		},
		Mutations = mutations,
		Rarities = rarityList(),
		Tiers = tiers(),
		Currencies = currencyFields(),
		Multipliers = LiveOps.Multipliers,
		Weather = LiveOps.Weather,
		MaxPlaced = GearCatalog.MaxPlaced,
	}
end

---------------------------------------------------------------------
-- Queries (reading)
---------------------------------------------------------------------
local function playerSummary(p)
	local data = GameData.Get(p)
	return {
		UserId = p.UserId, Name = p.Name, DisplayName = p.DisplayName,
		Coins = data and data.Coins or 0, Loaded = data ~= nil,
		Role = roleOf(p), HasBase = BaseService.BaseOf(p) ~= nil,
		Age = p.AccountAge,
	}
end

local function inspect(userId)
	local p = Players:GetPlayerByUserId(userId)
	if not p then
		return nil
	end
	local data = GameData.Get(p)
	local result = playerSummary(p)
	result.Currencies = {}
	for _, field in ipairs(currencyFields()) do
		result.Currencies[field] = data and data[field] or 0
	end
	local inv = api("InventoryAPI")
	local garden = api("GardenAPI")
	local sprinklers = api("SprinklerAPI")
	result.Inventory = inv and select(1, inv:Invoke("inventory", p)) or nil
	result.Garden = garden and garden:Invoke("admin_list", p) or {}
	result.Sprinklers = sprinklers and sprinklers:Invoke("list", p) or {}
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	result.Position = root and root.Position or nil
	return result
end

local lastQuery = {}
queryRemote.OnServerInvoke = function(player, kind, arg)
	if not can(player, "view") or type(kind) ~= "string" then
		return nil
	end
	-- rate limit: 20 reads a second is plenty for the panel
	local t = os.clock()
	local bucket = lastQuery[player]
	if not bucket or t - bucket.Start > 1 then
		bucket = { Start = t, Count = 0 }
		lastQuery[player] = bucket
	end
	bucket.Count += 1
	if bucket.Count > 20 then
		return nil
	end

	if kind == "boot" then
		local role = roleOf(player)
		return { Role = role, Perms = ROLES[role].Perms, Db = buildDatabase(), LiveOps = LiveOps.Snapshot(), JobId = game.JobId }
	elseif kind == "players" then
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(list, playerSummary(p))
		end
		return list
	elseif kind == "inspect" and type(arg) == "number" then
		return inspect(arg)
	elseif kind == "liveops" then
		return LiveOps.Snapshot()
	elseif kind == "logs" then
		return logs
	elseif kind == "bans" and can(player, "ban") then
		local ok, index = pcall(function()
			return banStore:GetAsync("index")
		end)
		local list = {}
		if ok and type(index) == "table" then
			for id, name in pairs(index) do
				table.insert(list, { UserId = tonumber(id), Name = name })
			end
		end
		return list
	end
	return nil
end

---------------------------------------------------------------------
-- Commands (changing things). Returns ok, message.
---------------------------------------------------------------------
local function num(value, low, high)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.clamp(value, low, high)
end

local function str(value, maxLen)
	if type(value) ~= "string" then
		return nil
	end
	return string.sub(value, 1, maxLen or 200)
end

local function mutationList(value)
	local list = {}
	if type(value) == "table" then
		for _, id in ipairs(value) do
			if type(id) == "string" and MutationCatalog.Get(id) and not table.find(list, id) then
				table.insert(list, id)
			end
		end
	end
	return list
end

-- the players a command is for: a userId, or "all"
local function targetsOf(value)
	if value == "all" then
		return Players:GetPlayers()
	end
	local p = type(value) == "number" and Players:GetPlayerByUserId(value)
	return p and { p } or {}
end

local function tierInfo(id)
	for _, t in ipairs(tiers()) do
		if t.Id == id then
			return t
		end
	end
	return nil
end

local catalogs = { Seed = PlanetCatalog, Planet = PlanetCatalog, Pack = PackCatalog, Gear = GearCatalog }

local function itemName(kind, id)
	local c = catalogs[kind]
	local item = c and c.Get(id)
	if not item then
		return id
	end
	return kind == "Seed" and (item.Name .. " Seed") or item.Name
end

local Commands = {}

function Commands.give(admin, p)
	local kind, id = p.Kind, str(p.Id, 80)
	local amount = num(p.Amount, 1, MAX_AMOUNT)
	if not catalogs[kind] or not id or not catalogs[kind].Get(id) or not amount then
		return false, "Pick an item and an amount"
	end
	amount = math.floor(amount)
	local targets = targetsOf(p.Target)
	if #targets == 0 then
		return false, "Pick a player"
	end
	local inv = api("InventoryAPI")
	local name = itemName(kind, id)
	for _, target in ipairs(targets) do
		if kind == "Planet" then
			local tier = p.Tier and tierInfo(p.Tier)
			inv:Invoke("planet_add", target, id, {
				Count = math.min(amount, 100), Tier = tier and tier.Id or nil, TierWeight = tier and tier.Weight or 1,
				Mutations = mutationList(p.Mutations), Weight = num(p.Weight, 0.01, 1e9),
			})
		else
			inv:Invoke("add", target, kind, id, amount)
		end
		if target ~= admin then
			notice(target, "An admin gave you " .. amount .. " x " .. name .. "!", "ok")
		end
	end
	return true, string.format("Gave %d x %s to %s", amount, name, p.Target == "all" and "everyone" or targets[1].DisplayName)
end

function Commands.remove(admin, p)
	local kind, id = p.Kind, str(p.Id, 80)
	local target = targetsOf(p.Target)[1]
	if not target or not catalogs[kind] or not id then
		return false, "Pick a player and an item"
	end
	local inv = api("InventoryAPI")
	if kind == "Planet" then
		local removed = inv:Invoke("planet_remove", target, id)
		return true, string.format("Removed %d %s from %s", removed or 0, itemName(kind, id), target.DisplayName)
	end
	local amount = p.Amount == "all" and MAX_AMOUNT * 1000 or num(p.Amount, 1, MAX_AMOUNT * 1000)
	if not amount then
		return false, "Enter an amount"
	end
	local left = inv:Invoke("add", target, kind, id, -math.floor(amount))
	return true, string.format("%s now has %d x %s", target.DisplayName, left or 0, itemName(kind, id))
end

function Commands.remove_planet(admin, p)
	local target = targetsOf(p.Target)[1]
	local index = num(p.Index, 1, 100000)
	if not target or not index then
		return false, "Pick a planet"
	end
	local removed = api("InventoryAPI"):Invoke("planet_remove", target, math.floor(index))
	return (removed or 0) > 0, removed and removed > 0 and "Planet removed" or "That planet is gone already"
end

function Commands.clear_inventory(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	local inv = api("InventoryAPI")
	local what = p.Kind
	local contents = inv:Invoke("inventory", target)
	if not contents then
		return false, "Their data hasn't loaded"
	end
	local map = { Seed = "Seeds", Pack = "Packs", Gear = "Gear" }
	for kind, key in pairs(map) do
		if what == "all" or what == kind then
			for id, count in pairs(contents[key]) do
				inv:Invoke("add", target, kind, id, -count)
			end
		end
	end
	if what == "all" or what == "Planet" then
		inv:Invoke("planet_remove", target, "all")
	end
	return true, "Cleared " .. (what == "all" and "the whole inventory" or (what .. "s")) .. " of " .. target.DisplayName
end

function Commands.currency(admin, p)
	local field = str(p.Field, 40)
	local amount = num(p.Amount, 0, MAX_CURRENCY)
	if not field or not table.find(currencyFields(), field) or not amount then
		return false, "Pick a currency and an amount"
	end
	local mode = p.Mode
	local targets = targetsOf(p.Target)
	if #targets == 0 then
		return false, "Pick a player"
	end
	for _, target in ipairs(targets) do
		local data = GameData.Get(target)
		if data then
			local current = type(data[field]) == "number" and data[field] or 0
			local new = mode == "set" and amount or (mode == "remove" and current - amount or current + amount)
			data[field] = math.floor(math.clamp(new, 0, MAX_CURRENCY))
			target:SetAttribute(field, data[field])
			if target ~= admin and mode == "add" then
				notice(target, "An admin gave you " .. fmt(amount) .. " " .. field .. "!", "ok")
			end
		end
	end
	local who = p.Target == "all" and "everyone" or targets[1].DisplayName
	local verb = mode == "set" and "Set" or (mode == "remove" and "Removed" or "Added")
	return true, string.format("%s %s %s %s %s", verb, fmt(amount), field, mode == "set" and "for" or (mode == "remove" and "from" or "to"), who)
end

function Commands.spawn_plant(admin, p)
	local target = targetsOf(p.Target)[1]
	local id = str(p.Id, 80)
	if not target or not id or not PlanetCatalog.Get(id) then
		return false, "Pick a player and a planet"
	end
	local made, err = api("GardenAPI"):Invoke("admin_spawn", target, {
		Id = id, Tier = p.Tier, Mutations = mutationList(p.Mutations), Grown = p.Grown == true, Count = num(p.Count, 1, 25) or 1,
	})
	if (made or 0) == 0 then
		return false, err or "Couldn't plant it"
	end
	return true, string.format("Planted %d %s in %s's garden", made, PlanetCatalog.Get(id).Name, target.DisplayName)
end

function Commands.garden_remove(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	local key = p.Key == "all" and "all" or num(p.Key, 1, 1e9)
	local removed = api("GardenAPI"):Invoke("admin_remove", target, key)
	return true, string.format("Removed %d planet%s from %s's garden", removed or 0, removed == 1 and "" or "s", target.DisplayName)
end

function Commands.garden_grow(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	local key = p.Key == "all" and "all" or num(p.Key, 1, 1e9)
	local grown = api("GardenAPI"):Invoke("admin_grow", target, key)
	return true, string.format("Finished growing %d planet%s", grown or 0, grown == 1 and "" or "s")
end

function Commands.garden_harvest(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	api("AdminBridge_Garden"):Fire(target, "harvest")
	return true, "Harvesting " .. target.DisplayName .. "'s garden"
end

function Commands.garden_mutate(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	local id = nil
	if p.Id ~= "none" then
		if type(p.Id) ~= "string" or not MutationCatalog.Get(p.Id) then
			return false, "Pick a mutation"
		end
		id = p.Id
	end
	api("AdminBridge_Garden"):Fire(target, "mutate", id)
	return true, id and ("Gave every planet in the garden " .. MutationCatalog.Get(id).Name) or "Removed mutations from the garden"
end

function Commands.sprinkler_spawn(admin, p)
	local target = targetsOf(p.Target)[1]
	local id = str(p.Id, 80)
	local gear = id and GearCatalog.Get(id)
	if not target or not gear or gear.Kind ~= "Sprinkler" then
		return false, "Pick a player and a sprinkler"
	end
	local made, err = api("SprinklerAPI"):Invoke("spawn", target, id, num(p.Count, 1, GearCatalog.MaxPlaced) or 1)
	if (made or 0) == 0 then
		return false, err or "Couldn't place it"
	end
	return true, string.format("Placed %d %s in %s's base", made, gear.Name, target.DisplayName)
end

function Commands.sprinkler_remove(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	local key = p.Key == "all" and "all" or num(p.Key, 1, 1e9)
	local removed = api("SprinklerAPI"):Invoke("remove", target, key)
	return true, string.format("Removed %d sprinkler%s", removed or 0, removed == 1 and "" or "s")
end

function Commands.multiplier(admin, p)
	local value = num(p.Value, 0, 100)
	local seconds = num(p.Seconds, 0, 7 * 86400) or 0
	if type(p.Id) ~= "string" or not value then
		return false, "Pick a multiplier and a value"
	end
	local ok, set = LiveOps.SetMultiplier(p.Id, value, seconds)
	if not ok then
		return false, "Unknown multiplier"
	end
	return true, string.format("%s multiplier set to %sx%s", p.Id, tostring(set), seconds > 0 and (" for " .. math.floor(seconds / 60) .. " min") or "")
end

function Commands.event_start(admin, p)
	local boost = num(p.Boost, 1, 100) or 5
	local seconds = num(p.Seconds, 0, 7 * 86400) or 0
	if type(p.Id) ~= "string" or not LiveOps.StartEvent(p.Id, boost, seconds) then
		return false, "Pick a mutation for the event"
	end
	local m = MutationCatalog.Get(p.Id)
	LiveOps.Announce(m.Name .. " EVENT! " .. boost .. "x chance" .. (seconds > 0 and (" for " .. math.floor(seconds / 60) .. " minutes") or ""), admin.DisplayName)
	return true, m.Name .. " event started"
end

function Commands.event_stop()
	LiveOps.StopEvent()
	return true, "Event stopped"
end

function Commands.weather(admin, p)
	local seconds = num(p.Seconds, 0, 7 * 86400) or 0
	if type(p.Id) ~= "string" or not LiveOps.SetWeather(p.Id, seconds) then
		return false, "Pick a weather"
	end
	local w = LiveOps.WeatherInfo(p.Id)
	if p.Id ~= "clear" then
		LiveOps.Announce("The weather is now " .. w.Name .. "!", admin.DisplayName)
	end
	return true, "Weather: " .. w.Name
end

function Commands.announce(admin, p)
	local text = str(p.Text, 200)
	if not text or text:gsub("%s", "") == "" then
		return false, "Type a message"
	end
	local filtered = text
	pcall(function()
		local result = game:GetService("TextService"):FilterStringAsync(text, admin.UserId)
		filtered = result:GetNonChatStringForBroadcastAsync()
	end)
	LiveOps.Announce(filtered, admin.DisplayName)
	return true, "Announcement sent"
end

function Commands.restock()
	api("InventoryAPI"):Invoke("restock")
	return true, "Every shop restocked"
end

function Commands.liveops_reset()
	LiveOps.ResetAll()
	return true, "Multipliers, event and weather back to normal"
end

function Commands.teleport(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target or not target.Character then
		return false, "Pick a player who is in the game"
	end
	local myRoot = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart")
	local theirRoot = target.Character:FindFirstChild("HumanoidRootPart")
	if not theirRoot then
		return false, "They haven't spawned"
	end
	if p.Mode == "goto" and myRoot then
		admin.Character:PivotTo(theirRoot.CFrame * CFrame.new(0, 0, 4))
		return true, "Teleported to " .. target.DisplayName
	elseif p.Mode == "bring" and myRoot then
		target.Character:PivotTo(myRoot.CFrame * CFrame.new(0, 0, -4))
		return true, "Brought " .. target.DisplayName
	elseif p.Mode == "base" then
		local base = BaseService.BaseOf(target)
		if not base then
			return false, target.DisplayName .. " has no base"
		end
		target.Character:PivotTo(CFrame.new(base.Center + Vector3.new(0, 5, 0)))
		return true, "Sent " .. target.DisplayName .. " to their base"
	end
	return false, "Unknown teleport"
end

function Commands.respawn(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	target:LoadCharacter()
	return true, "Respawned " .. target.DisplayName
end

local function outranks(admin, target)
	local mine = ROLES[roleOf(admin) or ""]
	local theirs = ROLES[roleOf(target) or ""]
	return not theirs or (mine and mine.Rank > theirs.Rank)
end

function Commands.kick(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	if target == admin or not outranks(admin, target) then
		return false, "You can't kick that player"
	end
	local reason = str(p.Reason, 120) or ""
	target:Kick("Kicked by an admin." .. (reason ~= "" and (" Reason: " .. reason) or ""))
	return true, "Kicked " .. target.Name
end

local function resolveUserId(value)
	if type(value) == "number" then
		return value
	end
	if type(value) == "string" then
		local asNumber = tonumber(value)
		if asNumber then
			return asNumber
		end
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(value)
		end)
		return ok and id or nil
	end
	return nil
end

function Commands.ban(admin, p)
	local userId = resolveUserId(p.Target)
	if not userId then
		return false, "Couldn't find that player"
	end
	if userId == admin.UserId then
		return false, "You can't ban yourself"
	end
	local online = Players:GetPlayerByUserId(userId)
	if online and not outranks(admin, online) then
		return false, "You can't ban that player"
	end
	if STAFF[userId] == "Owner" then
		return false, "You can't ban an owner"
	end
	local seconds = num(p.Seconds, 0, 10 * 365 * 86400) or 0
	local ban = { Reason = str(p.Reason, 120) or "", By = admin.Name, At = os.time(), Until = seconds > 0 and (os.time() + seconds) or 0 }
	local name = online and online.Name or tostring(p.Target)
	local ok, err = pcall(function()
		banStore:SetAsync(banKey(userId), ban)
	end)
	if not ok then
		return false, "Couldn't save the ban: " .. tostring(err)
	end
	banCache[userId] = ban
	updateBanIndex(userId, name, true)
	if online then
		online:Kick(banMessage(ban))
	end
	return true, string.format("Banned %s %s", name, seconds > 0 and ("for " .. math.floor(seconds / 3600) .. "h") or "permanently")
end

function Commands.unban(admin, p)
	local userId = resolveUserId(p.Target)
	if not userId then
		return false, "Couldn't find that player"
	end
	local ok = pcall(function()
		banStore:RemoveAsync(banKey(userId))
	end)
	if not ok then
		return false, "Couldn't reach the ban list, try again"
	end
	banCache[userId] = false
	updateBanIndex(userId, nil, false)
	return true, "Unbanned " .. tostring(p.Target)
end

function Commands.reset(admin, p)
	local target = targetsOf(p.Target)[1]
	if not target then
		return false, "Pick a player"
	end
	if p.Confirm ~= "RESET" then
		return false, "Type RESET to confirm"
	end
	if target ~= admin and not outranks(admin, target) then
		return false, "You can't reset that player"
	end
	api("GardenAPI"):Invoke("admin_remove", target, "all")
	api("SprinklerAPI"):Invoke("remove", target, "all")
	GameData.Reset(target)
	-- a clean rejoin makes every other system start fresh too (the reset save is written on leave)
	target:Kick("Your progress was reset by an admin. Please rejoin.")
	return true, "Reset " .. target.Name .. "'s data"
end

local recent = {}
commandRemote.OnServerInvoke = function(player, action, payload)
	if type(action) ~= "string" or type(payload) ~= "table" then
		return false, "Bad request"
	end
	local perm = NEEDS[action]
	if not perm or not Commands[action] then
		return false, "Unknown command"
	end
	if not can(player, perm) then
		log(player, "DENIED " .. action)
		return false, "You don't have permission for that"
	end
	-- rate limit
	local t = os.clock()
	local list = recent[player] or {}
	recent[player] = list
	while list[1] and t - list[1] > 1 do
		table.remove(list, 1)
	end
	if #list >= MAX_COMMANDS_PER_SECOND then
		return false, "Slow down a little"
	end
	table.insert(list, t)

	local ok, success, message = pcall(Commands[action], player, payload)
	if not ok then
		warn("[AdminServer] " .. action .. " failed: " .. tostring(success))
		return false, "Something went wrong (see Output)"
	end
	local target = payload.Target
	local targetName = target == "all" and "everyone" or (type(target) == "number" and Players:GetPlayerByUserId(target) and Players:GetPlayerByUserId(target).Name) or tostring(target or "")
	log(player, action, targetName, message)
	return success, message
end

Players.PlayerRemoving:Connect(function(player)
	recent[player] = nil
	lastQuery[player] = nil
end)

print("[AdminServer] ready")
