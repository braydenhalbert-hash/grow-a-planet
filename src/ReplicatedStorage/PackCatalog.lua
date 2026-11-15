--[[
	PackCatalog  (ModuleScript)
	Put in: ReplicatedStorage   (name it exactly: PackCatalog, next to PlanetCatalog)

	The Black Hole seed packs: price, shop stock and the odds for each rarity.
	Opening a pack rolls a rarity from Common to Mythic using Odds, then gives one
	random BLACK HOLE seed of that rarity (packs only give black holes, from tiny to TON 618).

	Odds are weights, not percentages: they don't have to add up to 100.
	Set a rarity to 0 to make it impossible in that pack.

	The expensive packs only give their own rarity and the one below it (plus a small chance
	of the next one up), so a Quasar or Void Heart pack almost always gives you something good.
]]

local PlanetCatalog = require(script.Parent:WaitForChild("PlanetCatalog"))

local PackCatalog = {}

PackCatalog.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

PackCatalog.Packs = {
	{
		Id = "pack_singularity", Name = "Singularity Pack", Tier = "Rare",
		Cost = 150000, Stock = { 8, 12 },
		Odds = { Common = 60, Uncommon = 28, Rare = 9, Epic = 2.5, Legendary = 0.45, Mythic = 0.05 },
	},
	{
		-- Epic + Rare, small chance of Legendary / Mythic
		Id = "pack_horizon", Name = "Event Horizon Pack", Tier = "Epic",
		Cost = 1250000, Stock = { 5, 8 },
		Odds = { Common = 0, Uncommon = 0, Rare = 52, Epic = 45, Legendary = 2.5, Mythic = 0.5 },
	},
	{
		-- Legendary + Epic, small chance of Mythic
		Id = "pack_quasar", Name = "Quasar Pack", Tier = "Legendary",
		Cost = 7500000, Stock = { 3, 5 },
		Odds = { Common = 0, Uncommon = 0, Rare = 0, Epic = 72, Legendary = 25, Mythic = 3 },
	},
	{
		-- Mythic + Legendary only
		Id = "pack_voidheart", Name = "Void Heart Pack", Tier = "Mythic",
		Cost = 25000000, Stock = { 1, 3 },
		Odds = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 85, Mythic = 15 },
	},
}

PackCatalog.ById = {}
for _, pack in ipairs(PackCatalog.Packs) do
	PackCatalog.ById[pack.Id] = pack
end

function PackCatalog.Get(id)
	return PackCatalog.ById[id]
end

function PackCatalog.TotalOdds(pack)
	local total = 0
	for _, rarity in ipairs(PackCatalog.RarityOrder) do
		total += pack.Odds[rarity] or 0
	end
	return total
end

-- chance (0-100) of a rarity in this pack
function PackCatalog.Percent(pack, rarity)
	local total = PackCatalog.TotalOdds(pack)
	if total <= 0 then
		return 0
	end
	return (pack.Odds[rarity] or 0) / total * 100
end

-- the rarest rarity this pack can give
function PackCatalog.TopRarity(pack)
	for i = #PackCatalog.RarityOrder, 1, -1 do
		local rarity = PackCatalog.RarityOrder[i]
		if (pack.Odds[rarity] or 0) > 0 then
			return rarity
		end
	end
	return "Common"
end

function PackCatalog.RollRarity(pack, rng)
	rng = rng or Random.new()
	local roll = rng:NextNumber(0, PackCatalog.TotalOdds(pack))
	local running = 0
	for _, rarity in ipairs(PackCatalog.RarityOrder) do
		local weight = pack.Odds[rarity] or 0
		if weight > 0 then
			running += weight
			if roll <= running then
				return rarity
			end
		end
	end
	return PackCatalog.TopRarity(pack)
end

local function planetsOf(rarity)
	local list = {}
	for _, planet in ipairs(PlanetCatalog.Planets) do
		if planet.Rarity == rarity and planet.Group == "BlackHole" then
			table.insert(list, planet)
		end
	end
	return list
end

-- roll a rarity, then a random black hole of that rarity
function PackCatalog.RollPlanet(pack, rng)
	rng = rng or Random.new()
	local rarity = PackCatalog.RollRarity(pack, rng)
	local candidates = planetsOf(rarity)

	-- if nothing exists at that rarity, fall back to the next one down
	local index = table.find(PackCatalog.RarityOrder, rarity) or 1
	while #candidates == 0 and index > 1 do
		index -= 1
		candidates = planetsOf(PackCatalog.RarityOrder[index])
	end
	if #candidates == 0 then
		for _, planet in ipairs(PlanetCatalog.Planets) do
			if planet.Group == "BlackHole" then
				table.insert(candidates, planet)
			end
		end
	end

	return candidates[rng:NextInteger(1, #candidates)]
end

function PackCatalog.RollStock(pack, rng)
	rng = rng or Random.new()
	return rng:NextInteger(pack.Stock[1], pack.Stock[2])
end

return PackCatalog
