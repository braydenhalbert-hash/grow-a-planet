-- ShopServer: opens shop UIs from NPC prompts, handles buying seeds and selling planets
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlanetConfig = require(ReplicatedStorage:WaitForChild("PlanetConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openShop = remotes:WaitForChild("OpenShop")
local buySeed = remotes:WaitForChild("BuySeed")
local sellPlanet = remotes:WaitForChild("SellPlanet")

local RESTOCK_PERIOD = 300
local RESTOCK_RANGES = {
	Common = { 6, 10 },
	Uncommon = { 4, 8 },
	Rare = { 3, 6 },
	Epic = { 2, 4 },
	Legendary = { 1, 3 },
	Mythic = { 1, 2 },
}

-- Shared seed stock lives in ReplicatedStorage attributes so every client's UI
-- can read it and react to changes without extra remotes.
local stockFolder = Instance.new("Folder")
stockFolder.Name = "SeedShopStock"
stockFolder.Parent = ReplicatedStorage

local stock = {}

local function restock()
	for _, planet in ipairs(PlanetConfig.Planets) do
		local range = RESTOCK_RANGES[planet.Rarity] or { 4, 8 }
		local count = math.random(range[1], range[2])
		stock[planet.Id] = count
		stockFolder:SetAttribute(planet.Id, count)
	end
	stockFolder:SetAttribute("RestockAt", os.time() + RESTOCK_PERIOD)
	print("[ShopServer] Seed shop restocked")
end

restock()
task.spawn(function()
	while true do
		task.wait(RESTOCK_PERIOD)
		restock()
	end
end)

-- Instant restock via Robux developer product.
-- Create the product in Creator Hub (Monetization > Developer Products),
-- then paste its ID here. Until it is set, the RESTOCK button only warns.
local MarketplaceService = game:GetService("MarketplaceService")
local RESTOCK_PRODUCT_ID = 0

local promptRestock = remotes:FindFirstChild("PromptRestock")
if not promptRestock then
	promptRestock = Instance.new("RemoteEvent")
	promptRestock.Name = "PromptRestock"
	promptRestock.Parent = remotes
end

promptRestock.OnServerEvent:Connect(function(player)
	if RESTOCK_PRODUCT_ID <= 0 then
		warn("[ShopServer] RESTOCK_PRODUCT_ID is not set - create a Developer Product and paste its ID into ShopServer")
		return
	end
	MarketplaceService:PromptProductPurchase(player, RESTOCK_PRODUCT_ID)
end)

MarketplaceService.ProcessReceipt = function(receiptInfo)
	if receiptInfo.ProductId ~= RESTOCK_PRODUCT_ID then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	restock()
	print("[ShopServer] " .. receiptInfo.PlayerName .. " bought an instant restock")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function setupPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local shopKind = prompt:GetAttribute("ShopKind")
	if not shopKind then
		return
	end
	prompt.Triggered:Connect(function(player)
		openShop:FireClient(player, shopKind)
	end)
end

for _, descendant in Workspace:GetDescendants() do
	setupPrompt(descendant)
end
Workspace.DescendantAdded:Connect(setupPrompt)

buySeed.OnServerEvent:Connect(function(player, planetId)
	local planet = typeof(planetId) == "string" and PlanetConfig.Get(planetId)
	if not planet then
		return
	end
	if (stock[planet.Id] or 0) <= 0 then
		return
	end
	if PlayerData.GetCoins(player) < planet.Cost then
		return
	end
	PlayerData.AddCoins(player, -planet.Cost)
	PlayerData.AddSeed(player, planet.Id, 1)
	stock[planet.Id] -= 1
	stockFolder:SetAttribute(planet.Id, stock[planet.Id])
	print(("[ShopServer] %s bought a %s seed for %d coins (%d left in stock)"):format(player.Name, planet.Name, planet.Cost, stock[planet.Id]))
end)

sellPlanet.OnServerEvent:Connect(function(player, planetId)
	local planet = typeof(planetId) == "string" and PlanetConfig.Get(planetId)
	if not planet then
		return
	end
	if not PlayerData.RemovePlanet(player, planet.Id) then
		return
	end
	PlayerData.AddCoins(player, planet.SellValue)
	print(("[ShopServer] %s sold a %s for %d coins"):format(player.Name, planet.Name, planet.SellValue))
end)

print("[ShopServer] Ready")