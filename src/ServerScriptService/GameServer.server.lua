--[[
	GameServer  (Script, NOT a LocalScript)  -- REPLACES the earlier GameServer
	Put in: ServerScriptService

	Runs both shops:
	  * Planet shop: buy planet seeds with coins (Sun and Black Hole are NOT sold here)
	  * Black Hole shop: buy seed packs with coins
	  * Opening a pack (equip it and click): rolls Common -> Mythic and gives one planet seed
	  * Shared stock + restock timer (copied to ReplicatedStorage.PlanetShopStock)
	  * Gives seeds and packs as Tools so the hotbar shows them, and rebuilds them after you respawn

	Needs: GameData (ModuleScript, same folder), PlanetCatalog and PackCatalog (ReplicatedStorage).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local GameData = require(script.Parent:WaitForChild("GameData"))
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local PackCatalog = require(ReplicatedStorage:WaitForChild("PackCatalog"))
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog")) -- sprinklers (the gear shop)

local RESTOCK_PERIOD = 300        -- seconds between restocks
local RESTOCK_PRODUCT_ID = 0      -- paste a Developer Product ID here for the Robux "RESTOCK" button

-- ROBUX PURCHASES (the purple button and Gift button in the shop)
-- Each item costs Robux based on its rarity. Make one Developer Product per price below
-- (Creator Hub > your game > Monetization > Developer Products), give each the SAME Robux price
-- as the number in its [brackets], and paste its ID where the 0 is. Leave a 0 and that price
-- just says "Robux purchases aren't set up yet" when clicked.
local ROBUX_PRICE_BY_RARITY = {
	Common = 19,
	Uncommon = 39,
	Rare = 79,
	Epic = 149,
	Legendary = 299,
	Mythic = 599,
}
-- Planet SEED products: one per price (19, 39, 79, 149, 299, 599)
local ROBUX_PRODUCT_SEED = {
	[19] = 0,
	[39] = 0,
	[79] = 0,
	[149] = 0,
	[299] = 0,
	[599] = 0,
}
-- Black Hole PACK products: Singularity 79, Event Horizon 149, Quasar 299, Void Heart 599
-- (the other prices are only used if you change a pack's rarity)
local ROBUX_PRODUCT_PACK = {
	[19] = 0,
	[39] = 0,
	[79] = 0,
	[149] = 0,
	[299] = 0,
	[599] = 0,
}
local function robuxProductFor(kind, price)
	local table_ = kind == "pack" and ROBUX_PRODUCT_PACK or ROBUX_PRODUCT_SEED
	return table_[price] or 0
end

local BUY_COOLDOWN = 0.15
local PENDING_TIMEOUT = 12        -- if a client never finishes the pack animation, give the seed anyway

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

local buySeedRemote = getRemote("BuySeed")
local buyPackRemote = getRemote("BuyPack")
local restockRemote = getRemote("RestockRequest")
local noticeRemote = getRemote("Notice")
local rollRemote = getRemote("PackRoll")         -- server -> client: (packId, planetId)
local finishRemote = getRemote("PackFinished")   -- client -> server: animation is done
local audioCueRemote = getRemote("AudioCue")      -- server -> client: small sound cues (AudioManager plays them)
local announceRemote = getRemote("RestockAnnounce")  -- server -> everyone: (newPlanetSeeds, newPacks) for the "restocked" pop-ups
local buyRobuxRemote = getRemote("BuyRobux")       -- client -> server: (itemId, optional recipientUserId for a gift)
local buyGearRemote = getRemote("BuyGear")         -- client -> server: (gearId) from the gear shop

local function notice(player, text, kind)
	noticeRemote:FireClient(player, text, kind or "ok")
end

---------------------------------------------------------------------
-- Shop stock (planet seeds + packs share one folder and one timer)
---------------------------------------------------------------------
local stockFolder = Instance.new("Folder")
stockFolder.Name = "PlanetShopStock"
stockFolder.Parent = ReplicatedStorage

-- tell the shop screens how many Robux each item costs
for _, planet in ipairs(PlanetCatalog.Planets) do
	if planet.Buyable ~= false and ROBUX_PRICE_BY_RARITY[planet.Rarity] then
		stockFolder:SetAttribute("Robux_" .. planet.Id, ROBUX_PRICE_BY_RARITY[planet.Rarity])
	end
end
for _, pack in ipairs(PackCatalog.Packs) do
	if ROBUX_PRICE_BY_RARITY[pack.Tier] then
		stockFolder:SetAttribute("Robux_" .. pack.Id, ROBUX_PRICE_BY_RARITY[pack.Tier])
	end
end

local stock = {}

-- How often something comes into stock at each restock (1 = always, 0.25 = a quarter of the time).
-- The rest of the time it stays SOLD OUT, so players keep hunting for it.
local RESTOCK_CHANCE_BY_RARITY = { Epic = 0.25 }        -- the best planet seeds in the shop (Uranus, Neptune)
local RESTOCK_CHANCE_BY_PACK = { pack_voidheart = 0.05 } -- the best seed pack

local function restock()
	local newPlanets, newPacks = {}, {}
	for _, gear in ipairs(GearCatalog.Gear) do
		local count = 0
		if math.random() < (gear.RestockChance or 1) then
			count = GearCatalog.RollStock(gear)
		end
		stock[gear.Id] = count
		stockFolder:SetAttribute(gear.Id, count)
	end
	for _, planet in ipairs(PlanetCatalog.Planets) do
		if planet.Buyable ~= false then
			local count = 0
			if math.random() < (planet.RestockChance or RESTOCK_CHANCE_BY_RARITY[planet.Rarity] or 1) then
				count = PlanetCatalog.RollStock(planet)
			end
			stock[planet.Id] = count
			stockFolder:SetAttribute(planet.Id, count)
			if count > 0 then
				table.insert(newPlanets, { Name = planet.Name, Rarity = planet.Rarity, Count = count })
			end
		end
	end
	for _, pack in ipairs(PackCatalog.Packs) do
		local count = 0
		if math.random() < (RESTOCK_CHANCE_BY_PACK[pack.Id] or 1) then
			count = PackCatalog.RollStock(pack)
		end
		stock[pack.Id] = count
		stockFolder:SetAttribute(pack.Id, count)
		if count > 0 then
			table.insert(newPacks, { Name = pack.Name, Rarity = pack.Tier, Count = count })
		end
	end
	stockFolder:SetAttribute("RestockAt", os.time() + RESTOCK_PERIOD)
	announceRemote:FireAllClients(newPlanets, newPacks)
	print("[GameServer] Shops restocked")
end

restock()
task.spawn(function()
	while true do
		task.wait(RESTOCK_PERIOD)
		restock()
	end
end)

restockRemote.OnServerEvent:Connect(function(player)
	if RESTOCK_PRODUCT_ID <= 0 then
		notice(player, "Instant restock isn't set up yet.", "error")
		return
	end
	MarketplaceService:PromptProductPurchase(player, RESTOCK_PRODUCT_ID)
end)

-- (the receipt handler for restock + Robux purchases is further down, in "Robux purchases")

---------------------------------------------------------------------
-- Tools (what the hotbar shows)
---------------------------------------------------------------------
local openPack -- defined further down

local function seedToolName(planet)
	return planet.Name .. " Seed"
end

local function makeSeedTool(planet, count)
	local tool = Instance.new("Tool")
	tool.Name = seedToolName(planet)
	tool.ToolTip = tool.Name
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("Kind", "Seed")
	tool:SetAttribute("PlanetId", planet.Id)
	tool:SetAttribute("Rarity", planet.Rarity)
	tool:SetAttribute("Count", count)
	return tool
end

-- a harvested planet (each one has its own weight)
local TIER_LABELS = { huge = "Huge", insane = "Insane", crazy = "Crazy" }

local MutationCatalog do
	-- if the MutationCatalog ModuleScript is missing, the game still works (just without mutations)
	local module = ReplicatedStorage:WaitForChild("MutationCatalog", 5)
	if module then
		MutationCatalog = require(module)
	else
		warn("[GameServer] ReplicatedStorage.MutationCatalog is missing, so there are no mutations. Create it (ModuleScript).")
		MutationCatalog = {
			Get = function() return nil end,
			Parse = function() return {} end,
			Join = function() return "" end,
			Names = function() return "" end,
			RollAll = function() return {} end,
			CoinMult = function() return 1 end,
			SellMult = function() return 1 end,
		}
	end
end

local function makePlanetTool(planet, weight, tier, mutId)
	local tool = Instance.new("Tool")
	tool.Name = tier and ((TIER_LABELS[tier] or "Huge") .. " " .. planet.Name) or planet.Name
	local mutationIds = MutationCatalog.Parse(mutId)
	if #mutationIds > 0 then
		tool.Name = MutationCatalog.Names(mutationIds) .. " " .. tool.Name
		tool:SetAttribute("Mutations", MutationCatalog.Join(mutationIds))
	end
	tool.ToolTip = string.format("%s (%.2f kg)", tool.Name, weight)
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("Kind", "Planet")
	tool:SetAttribute("PlanetId", planet.Id)
	tool:SetAttribute("Rarity", planet.Rarity)
	tool:SetAttribute("Weight", weight)
	if tier then
		tool:SetAttribute("SizeTier", tier)
	end
	return tool
end

-- gear from the gear shop (sprinklers): equip it and click a bed in your base to place it (SprinklerServer)
local function makeGearTool(gear, count)
	local tool = Instance.new("Tool")
	tool.Name = gear.Name
	tool.ToolTip = "Click a bed in your garden to place it"
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("Kind", "Gear")
	tool:SetAttribute("GearId", gear.Id)
	tool:SetAttribute("Rarity", gear.Rarity)
	tool:SetAttribute("Count", count)
	return tool
end

local function makePackTool(player, pack, count)
	local tool = Instance.new("Tool")
	tool.Name = pack.Name
	tool.ToolTip = "Click to open"
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("Kind", "Pack")
	tool:SetAttribute("PackId", pack.Id)
	tool:SetAttribute("Rarity", pack.Tier)
	tool:SetAttribute("Count", count)
	-- equip the pack and click to open it
	tool.Activated:Connect(function()
		openPack(player, pack.Id)
	end)
	return tool
end

-- finds the tool whether it's in the backpack or in the player's hand
local function findTool(player, name)
	local containers = {}
	if player:FindFirstChild("Backpack") then
		table.insert(containers, player.Backpack)
	end
	if player.Character then
		table.insert(containers, player.Character)
	end
	for _, container in ipairs(containers) do
		local tool = container:FindFirstChild(name)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end
	return nil
end

-- make the tool match the saved count (create it, update it, or remove it)
local function syncTool(player, toolName, count, makeFn)
	local tool = findTool(player, toolName)
	if count <= 0 then
		if tool then
			tool:Destroy()
		end
	elseif tool then
		tool:SetAttribute("Count", count)
	else
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			makeFn(count).Parent = backpack
		end
	end
end

local function refreshSeed(player, planetId)
	local data = GameData.Get(player)
	local planet = PlanetCatalog.Get(planetId)
	if not data or not planet then
		return
	end
	local count = data.Seeds[planetId] or 0
	if count <= 0 then
		data.Seeds[planetId] = nil
	end
	syncTool(player, seedToolName(planet), count, function(c)
		return makeSeedTool(planet, c)
	end)
end

local function refreshPack(player, packId)
	local data = GameData.Get(player)
	local pack = PackCatalog.Get(packId)
	if not data or not pack then
		return
	end
	local count = data.Packs[packId] or 0
	if count <= 0 then
		data.Packs[packId] = nil
	end
	syncTool(player, pack.Name, count, function(c)
		return makePackTool(player, pack, c)
	end)
end

local function refreshGear(player, gearId)
	local data = GameData.Get(player)
	local gear = GearCatalog.Get(gearId)
	if not data or not gear then
		return
	end
	data.Gear = data.Gear or {}
	local count = data.Gear[gearId] or 0
	if count <= 0 then
		data.Gear[gearId] = nil
	end
	syncTool(player, gear.Name, count, function(c)
		return makeGearTool(gear, c)
	end)
end

-- rebuild every tool from saved data (runs when you join and each time you respawn)
local function rebuild(player)
	local data = GameData.Get(player)
	local backpack = player:FindFirstChild("Backpack")
	if not data or not backpack then
		return
	end

	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Kind") then
			child:Destroy()
		end
	end

	for _, pack in ipairs(PackCatalog.Packs) do
		local count = data.Packs[pack.Id]
		if count and count > 0 then
			makePackTool(player, pack, count).Parent = backpack
		end
	end

	for _, planet in ipairs(PlanetCatalog.Planets) do
		local count = data.Seeds[planet.Id]
		if count and count > 0 then
			makeSeedTool(planet, count).Parent = backpack
		end
	end

	for _, gear in ipairs(GearCatalog.Gear) do
		local count = data.Gear and data.Gear[gear.Id]
		if count and count > 0 then
			makeGearTool(gear, count).Parent = backpack
		end
	end

	-- harvested planets you're holding
	for _, owned in ipairs(data.Planets) do
		local planet = PlanetCatalog.Get(owned.Id)
		if planet and type(owned.Weight) == "number" then
			-- older saves used Huge = true; newer ones use Tier = "huge" / "insane" / "crazy"
			makePlanetTool(planet, owned.Weight, owned.Tier or (owned.Huge and "huge" or nil), owned.Mut).Parent = backpack
		end
	end
end

local function setupPlayer(player)
	local function give()
		if not GameData.WaitFor(player) then
			return
		end
		player:WaitForChild("Backpack")
		task.wait(0.25) -- let the new backpack finish setting up after a respawn
		if player.Parent then
			rebuild(player)
		end
	end

	player.CharacterAdded:Connect(function()
		task.spawn(give)
	end)
	if player.Character then
		task.spawn(give)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

---------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------
local lastBuy = {}

local function onCooldown(player)
	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < BUY_COOLDOWN then
		return true
	end
	lastBuy[player] = now
	return false
end

buySeedRemote.OnServerEvent:Connect(function(player, planetId)
	if typeof(planetId) ~= "string" then
		return
	end
	local planet = PlanetCatalog.Get(planetId)
	if not planet or onCooldown(player) then
		return
	end

	local data = GameData.Get(player)
	if not data then
		notice(player, "Your data is still loading, try again in a moment.", "error")
		return
	end

	if planet.Buyable == false then
		notice(player, planet.Name .. " Seeds can only be found in Black Hole Packs.", "error")
		return
	end
	if (stock[planet.Id] or 0) <= 0 then
		notice(player, planet.Name .. " Seed is sold out!", "error")
		return
	end
	if not GameData.AddCoins(player, -planet.Cost) then
		notice(player, "Not enough coins for a " .. planet.Name .. " Seed.", "error")
		return
	end

	data.Seeds[planet.Id] = (data.Seeds[planet.Id] or 0) + 1
	stock[planet.Id] -= 1
	stockFolder:SetAttribute(planet.Id, stock[planet.Id])

	refreshSeed(player, planet.Id)
	notice(player, "Bought a " .. planet.Name .. " Seed!", "ok")
	audioCueRemote:FireClient(player, "buy_seed")
end)

buyPackRemote.OnServerEvent:Connect(function(player, packId)
	if typeof(packId) ~= "string" then
		return
	end
	local pack = PackCatalog.Get(packId)
	if not pack or onCooldown(player) then
		return
	end

	local data = GameData.Get(player)
	if not data then
		notice(player, "Your data is still loading, try again in a moment.", "error")
		return
	end

	if (stock[pack.Id] or 0) <= 0 then
		notice(player, pack.Name .. " is sold out!", "error")
		return
	end
	if not GameData.AddCoins(player, -pack.Cost) then
		notice(player, "Not enough coins for the " .. pack.Name .. ".", "error")
		return
	end

	data.Packs[pack.Id] = (data.Packs[pack.Id] or 0) + 1
	stock[pack.Id] -= 1
	stockFolder:SetAttribute(pack.Id, stock[pack.Id])

	refreshPack(player, pack.Id)
	notice(player, "Bought a " .. pack.Name .. "! Equip it and click to open.", "ok")
	audioCueRemote:FireClient(player, "buy_pack")
end)

buyGearRemote.OnServerEvent:Connect(function(player, gearId)
	if typeof(gearId) ~= "string" then
		return
	end
	local gear = GearCatalog.Get(gearId)
	if not gear or onCooldown(player) then
		return
	end
	local data = GameData.Get(player)
	if not data then
		notice(player, "Your data is still loading, try again in a moment.", "error")
		return
	end
	if (stock[gear.Id] or 0) <= 0 then
		notice(player, gear.Name .. " is sold out!", "error")
		return
	end
	if not GameData.AddCoins(player, -gear.Cost) then
		notice(player, "Not enough coins for a " .. gear.Name .. ".", "error")
		return
	end

	data.Gear = data.Gear or {}
	data.Gear[gear.Id] = (data.Gear[gear.Id] or 0) + 1
	stock[gear.Id] -= 1
	stockFolder:SetAttribute(gear.Id, stock[gear.Id])

	refreshGear(player, gear.Id)
	notice(player, "Bought a " .. gear.Name .. "! Equip it and click a bed in your garden.", "ok")
	audioCueRemote:FireClient(player, "buy_seed")
end)

-- SprinklerServer uses one piece of gear when it's placed (and gives it back if placing fails)
do
	local ServerStorage = game:GetService("ServerStorage")
	local gearBridge = Instance.new("BindableFunction")
	gearBridge.Name = "GearBridge"
	gearBridge.Parent = ServerStorage
	gearBridge.OnInvoke = function(action, player, gearId)
		local data = GameData.Get(player)
		if not data or not GearCatalog.Get(gearId) then
			return false
		end
		data.Gear = data.Gear or {}
		if action == "use" then
			if (data.Gear[gearId] or 0) <= 0 then
				return false
			end
			data.Gear[gearId] -= 1
		elseif action == "give" then
			data.Gear[gearId] = (data.Gear[gearId] or 0) + 1
		end
		refreshGear(player, gearId)
		return true
	end
end

---------------------------------------------------------------------
-- Robux purchases (buy for yourself, or gift to another player in the server)
-- These ignore stock: Robux buyers can get an item even when the coin button says NO STOCK.
---------------------------------------------------------------------
local pendingRobux = {}   -- buyer userId -> { Kind, Id, Name, Price, RecipientId }
local handledReceipts = {}

buyRobuxRemote.OnServerEvent:Connect(function(player, itemId, recipientId)
	if typeof(itemId) ~= "string" or onCooldown(player) then
		return
	end

	local kind, name, rarity
	local planet = PlanetCatalog.Get(itemId)
	local pack = PackCatalog.Get(itemId)
	if planet and planet.Buyable ~= false then
		kind, name, rarity = "seed", planet.Name .. " Seed", planet.Rarity
	elseif pack then
		kind, name, rarity = "pack", pack.Name, pack.Tier
	else
		return
	end

	local price = ROBUX_PRICE_BY_RARITY[rarity]
	local productId = price and robuxProductFor(kind, price) or 0
	if not price or productId <= 0 then
		notice(player, "Robux purchases aren't set up yet.", "error")
		return
	end

	local recipient = player
	if recipientId ~= nil then
		if typeof(recipientId) ~= "number" then
			return
		end
		recipient = Players:GetPlayerByUserId(recipientId)
		if not recipient then
			notice(player, "That player isn't in this server anymore.", "error")
			return
		end
	end

	pendingRobux[player.UserId] = {
		Kind = kind,
		Id = itemId,
		Name = name,
		Price = price,
		RecipientId = recipient.UserId,
	}
	MarketplaceService:PromptProductPurchase(player, productId)
end)

MarketplaceService.ProcessReceipt = function(receipt)
	if handledReceipts[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- the Robux RESTOCK button
	if RESTOCK_PRODUCT_ID > 0 and receipt.ProductId == RESTOCK_PRODUCT_ID then
		restock()
		handledReceipts[receipt.PurchaseId] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	local entry = buyer and pendingRobux[buyer.UserId]
	if not buyer or not entry or robuxProductFor(entry.Kind, entry.Price) ~= receipt.ProductId then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local recipient = Players:GetPlayerByUserId(entry.RecipientId)
	local data = recipient and GameData.Get(recipient)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if entry.Kind == "seed" then
		data.Seeds[entry.Id] = (data.Seeds[entry.Id] or 0) + 1
		refreshSeed(recipient, entry.Id)
	else
		data.Packs[entry.Id] = (data.Packs[entry.Id] or 0) + 1
		refreshPack(recipient, entry.Id)
	end

	pendingRobux[buyer.UserId] = nil
	handledReceipts[receipt.PurchaseId] = true

	if recipient == buyer then
		notice(buyer, "Bought " .. entry.Name .. " with Robux!", "ok")
	else
		notice(buyer, "Sent " .. entry.Name .. " to " .. recipient.DisplayName .. "!", "ok")
		notice(recipient, buyer.DisplayName .. " gifted you " .. entry.Name .. "!", "ok")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------
-- Opening packs
---------------------------------------------------------------------
local pending = {} -- player -> { PlanetId = id }

-- the seed is already saved when the roll happens; this just shows it in the hotbar
local function finishPending(player)
	local entry = pending[player]
	if not entry then
		return
	end
	pending[player] = nil
	if not player.Parent then
		return
	end
	refreshSeed(player, entry.PlanetId)
	local planet = PlanetCatalog.Get(entry.PlanetId)
	if planet then
		notice(player, "You got a " .. planet.Name .. " Seed! (" .. planet.Rarity .. ")", "ok")
	end
end

openPack = function(player, packId)
	local pack = PackCatalog.Get(packId)
	local data = GameData.Get(player)
	if not pack or not data then
		return
	end
	if pending[player] then
		return -- still opening one
	end
	if (data.Packs[packId] or 0) <= 0 then
		return
	end

	-- use up one pack
	data.Packs[packId] -= 1
	if data.Packs[packId] <= 0 then
		data.Packs[packId] = nil
	end
	refreshPack(player, packId)

	-- the server decides the result, the client only plays the animation
	local planet = PackCatalog.RollPlanet(pack)
	data.Seeds[planet.Id] = (data.Seeds[planet.Id] or 0) + 1

	local entry = { PlanetId = planet.Id }
	pending[player] = entry
	rollRemote:FireClient(player, pack.Id, planet.Id)

	task.delay(PENDING_TIMEOUT, function()
		if pending[player] == entry then
			finishPending(player)
		end
	end)
end

finishRemote.OnServerEvent:Connect(function(player)
	finishPending(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastBuy[player] = nil
	pending[player] = nil
end)

-- admin panel: AdminServer asks us to hand out seeds / packs and restock (server only, nobody else can fire this)
do
	local ServerStorage = game:GetService("ServerStorage")
	local adminBridge = Instance.new("BindableEvent")
	adminBridge.Name = "AdminBridge_Game"
	adminBridge.Parent = ServerStorage
	adminBridge.Event:Connect(function(player, action, id, amount)
		local data = GameData.Get(player)
		if not data then
			return
		end
		if action == "seed" and PlanetCatalog.Get(id) then
			data.Seeds[id] = (data.Seeds[id] or 0) + amount
			refreshSeed(player, id)
		elseif action == "pack" and PackCatalog.Get(id) then
			data.Packs[id] = (data.Packs[id] or 0) + amount
			refreshPack(player, id)
		elseif action == "gear" and GearCatalog.Get(id) then
			data.Gear = data.Gear or {}
			data.Gear[id] = (data.Gear[id] or 0) + amount
			refreshGear(player, id)
		elseif action == "restock" then
			restock()
		end
	end)
end

print("[GameServer] Ready")
