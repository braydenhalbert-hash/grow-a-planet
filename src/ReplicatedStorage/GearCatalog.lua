--[[
	GearCatalog  (ModuleScript)  -- ReplicatedStorage

	Everything the GEAR shop (the green stand at the back, the mechanic) sells.

	Stardust Sprinklers: equip one and click a garden bed in YOUR base to place it.
	While it runs it sprays stardust over every planet in its Radius:
	  * GrowBoost        those planets grow this many times faster (1.5 = 50% faster)
	  * StardustChance   every 10 seconds, each BLACK HOLE in range has this chance to swallow
	                     the stardust and get the Stardust mutation (see MutationCatalog)
	  * Duration         seconds it keeps running (it keeps counting while you're offline)
	RestockChance (optional): 0.3 = only in stock at 30% of restocks.
]]

local GearCatalog = {}

GearCatalog.MaxPlaced = 8 -- sprinklers one player can have running at once

GearCatalog.Gear = {
	{
		Id = "sprinkler_stardust", Name = "Stardust Sprinkler", Kind = "Sprinkler", Rarity = "Uncommon",
		Cost = 2000, Stock = { 2, 5 },
		Radius = 9, Duration = 300, GrowBoost = 1.25, StardustChance = 0.03,
		Color = Color3.fromRGB(150, 200, 255), DustColor = Color3.fromRGB(200, 225, 255),
		Description = "Sprays a little stardust. Planets grow 25% faster.",
	},
	{
		Id = "sprinkler_nebula", Name = "Nebula Sprinkler", Kind = "Sprinkler", Rarity = "Rare",
		Cost = 12000, Stock = { 1, 3 },
		Radius = 12, Duration = 420, GrowBoost = 1.5, StardustChance = 0.06,
		Color = Color3.fromRGB(200, 120, 255), DustColor = Color3.fromRGB(235, 170, 255),
		Description = "A wider spray of pink stardust. Planets grow 50% faster.",
	},
	{
		Id = "sprinkler_cosmic", Name = "Cosmic Sprinkler", Kind = "Sprinkler", Rarity = "Legendary",
		Cost = 80000, Stock = { 1, 2 }, RestockChance = 0.35,
		Radius = 16, Duration = 600, GrowBoost = 2, StardustChance = 0.12,
		Color = Color3.fromRGB(255, 215, 110), DustColor = Color3.fromRGB(255, 240, 180),
		Description = "Golden stardust everywhere. Planets grow twice as fast.",
	},
}

GearCatalog.ById = {}
for index, gear in ipairs(GearCatalog.Gear) do
	gear.Index = index
	GearCatalog.ById[gear.Id] = gear
end

function GearCatalog.Get(id)
	return GearCatalog.ById[id]
end

function GearCatalog.RollStock(gear, rng)
	rng = rng or Random.new()
	return rng:NextInteger(gear.Stock[1], gear.Stock[2])
end

return GearCatalog
