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

local rgb = Color3.fromRGB
local function sprinkler(t)
	t.Kind = "Sprinkler"
	return t
end

-- cheapest first. Every sprinkler's 3D design + effects live in SprinklerModel.
GearCatalog.Gear = {
	sprinkler({
		Id = "sprinkler_basic", Name = "Basic Sprinkler", Rarity = "Common",
		Cost = 500, Stock = { 8, 12 },
		Radius = 7, Duration = 240, GrowBoost = 1.15, StardustChance = 0.01,
		Color = rgb(110, 200, 130), DustColor = rgb(190, 240, 200),
		Description = "A simple starter sprinkler. Planets grow 15% faster.",
	}),
	sprinkler({
		Id = "sprinkler_stardust", Name = "Stardust Sprinkler", Rarity = "Uncommon",
		Cost = 4000, Stock = { 2, 5 },
		Radius = 9, Duration = 300, GrowBoost = 1.25, StardustChance = 0.03,
		Color = rgb(150, 200, 255), DustColor = rgb(200, 225, 255),
		Description = "Sprays a little stardust. Planets grow 25% faster.",
	}),
	sprinkler({
		Id = "sprinkler_nebula", Name = "Nebula Sprinkler", Rarity = "Rare",
		Cost = 30000, Stock = { 1, 3 },
		Radius = 12, Duration = 420, GrowBoost = 1.5, StardustChance = 0.06,
		Color = rgb(200, 120, 255), DustColor = rgb(235, 170, 255),
		Description = "A wider spray of pink stardust. Planets grow 50% faster.",
	}),
	sprinkler({
		Id = "sprinkler_cosmic", Name = "Cosmic Sprinkler", Rarity = "Legendary",
		Cost = 1500000, Stock = { 1, 2 }, RestockChance = 0.35,
		Radius = 16, Duration = 600, GrowBoost = 2, StardustChance = 0.12,
		Color = rgb(255, 215, 110), DustColor = rgb(255, 240, 180),
		Description = "Golden stardust everywhere. Planets grow twice as fast.",
	}),
	-- Epic
	sprinkler({
		Id = "sprinkler_nebulacloud", Name = "Nebula Cloud Sprinkler", Rarity = "Epic",
		Cost = 50000000, Stock = { 1, 2 }, RestockChance = 0.3,
		Radius = 18, Duration = 720, GrowBoost = 2.2, StardustChance = 0.14,
		Color = rgb(255, 110, 220), DustColor = rgb(255, 170, 235),
		Description = "A living cloud of pink nebula gas. Planets grow 2.2x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_celestialtree", Name = "Celestial Tree Sprinkler", Rarity = "Epic",
		Cost = 60000000, Stock = { 1, 2 }, RestockChance = 0.28,
		Radius = 18, Duration = 750, GrowBoost = 2.3, StardustChance = 0.15,
		Color = rgb(80, 230, 255), DustColor = rgb(170, 245, 255),
		Description = "A glowing star tree with orbs on every branch. Planets grow 2.3x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_quasar", Name = "Quasar Sprinkler", Rarity = "Epic",
		Cost = 75000000, Stock = { 1, 2 }, RestockChance = 0.26,
		Radius = 19, Duration = 780, GrowBoost = 2.4, StardustChance = 0.16,
		Color = rgb(120, 230, 255), DustColor = rgb(255, 230, 150),
		Description = "A blazing core firing twin jets inside a gold gyroscope. Planets grow 2.4x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_darkmatter", Name = "Dark Matter Sprinkler", Rarity = "Epic",
		Cost = 90000000, Stock = { 1, 2 }, RestockChance = 0.25,
		Radius = 19, Duration = 810, GrowBoost = 2.45, StardustChance = 0.17,
		Color = rgb(170, 80, 255), DustColor = rgb(210, 160, 255),
		Description = "A caged void orb with floating dark cubes. Planets grow 2.45x as fast.",
	}),
	-- Legendary
	sprinkler({
		Id = "sprinkler_voidspiral", Name = "Void Spiral Sprinkler", Rarity = "Legendary",
		Cost = 200000000, Stock = { 1, 1 }, RestockChance = 0.2,
		Radius = 20, Duration = 900, GrowBoost = 2.6, StardustChance = 0.18,
		Color = rgb(140, 90, 255), DustColor = rgb(200, 170, 255),
		Description = "A spiral of light pouring into a purple black hole. Planets grow 2.6x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_blackhole", Name = "Black Hole Sprinkler", Rarity = "Legendary",
		Cost = 250000000, Stock = { 1, 1 }, RestockChance = 0.19,
		Radius = 20, Duration = 930, GrowBoost = 2.7, StardustChance = 0.22,
		Color = rgb(255, 140, 40), DustColor = rgb(255, 190, 110),
		Description = "A fiery accretion disk around a real black hole. Best for black hole mutations.",
	}),
	sprinkler({
		Id = "sprinkler_timedilation", Name = "Time Dilation Sprinkler", Rarity = "Legendary",
		Cost = 300000000, Stock = { 1, 1 }, RestockChance = 0.18,
		Radius = 21, Duration = 960, GrowBoost = 2.8, StardustChance = 0.19,
		Color = rgb(255, 200, 70), DustColor = rgb(255, 230, 150),
		Description = "A golden hourglass that bends time. Planets grow 2.8x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_planetaryring", Name = "Planetary Ring Sprinkler", Rarity = "Legendary",
		Cost = 350000000, Stock = { 1, 1 }, RestockChance = 0.17,
		Radius = 21, Duration = 990, GrowBoost = 2.9, StardustChance = 0.2,
		Color = rgb(255, 150, 50), DustColor = rgb(255, 210, 140),
		Description = "A whole solar system on giant rings around a blazing sun. Planets grow 2.9x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_orbitalstation", Name = "Orbital Station Sprinkler", Rarity = "Legendary",
		Cost = 400000000, Stock = { 1, 1 }, RestockChance = 0.16,
		Radius = 22, Duration = 1020, GrowBoost = 3, StardustChance = 0.21,
		Color = rgb(80, 160, 255), DustColor = rgb(170, 210, 255),
		Description = "A spinning space station with satellites. Planets grow 3x as fast.",
	}),
	-- Mythic
	sprinkler({
		Id = "sprinkler_supernova", Name = "Supernova Sprinkler", Rarity = "Mythic",
		Cost = 1000000000, Stock = { 1, 1 }, RestockChance = 0.1,
		Radius = 23, Duration = 1200, GrowBoost = 3.2, StardustChance = 0.25,
		Color = rgb(255, 90, 220), DustColor = rgb(255, 180, 240),
		Description = "An exploding star bursting with crystal spikes. Planets grow 3.2x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_galaxycore", Name = "Galaxy Core Sprinkler", Rarity = "Mythic",
		Cost = 1300000000, Stock = { 1, 1 }, RestockChance = 0.09,
		Radius = 24, Duration = 1260, GrowBoost = 3.4, StardustChance = 0.27,
		Color = rgb(170, 80, 255), DustColor = rgb(220, 180, 255),
		Description = "A spinning galaxy in a crystal-crowned sphere. Planets grow 3.4x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_cosmicsupreme", Name = "Cosmic Supreme Sprinkler", Rarity = "Mythic",
		Cost = 1600000000, Stock = { 1, 1 }, RestockChance = 0.08,
		Radius = 25, Duration = 1350, GrowBoost = 3.6, StardustChance = 0.3,
		Color = rgb(180, 90, 255), DustColor = rgb(200, 220, 255),
		Description = "A massive black hole wrapped in a galaxy. Planets grow 3.6x as fast.",
	}),
	-- Divine
	sprinkler({
		Id = "sprinkler_divine", Name = "Divine Starforge Sprinkler", Rarity = "Divine",
		Cost = 4000000000, Stock = { 1, 1 }, RestockChance = 0.05,
		Radius = 27, Duration = 1500, GrowBoost = 4, StardustChance = 0.35,
		Color = rgb(255, 225, 130), DustColor = rgb(255, 245, 200),
		Description = "A white-gold star forged in a golden armillary. Planets grow 4x as fast.",
	}),
	-- Celestial
	sprinkler({
		Id = "sprinkler_celestial", Name = "Celestial Universe Sprinkler", Rarity = "Celestial",
		Cost = 8000000000, Stock = { 1, 1 }, RestockChance = 0.03,
		Radius = 30, Duration = 1800, GrowBoost = 5, StardustChance = 0.45,
		Color = rgb(120, 240, 255), DustColor = rgb(200, 250, 255),
		Description = "An entire universe on a pedestal. Planets grow 5x as fast.",
	}),
	-- THE STARDUST LINE
	sprinkler({
		Id = "sprinkler_galaxystardust", Name = "Galaxy Stardust Sprinkler", Rarity = "Epic",
		Cost = 120000000, Stock = { 1, 2 }, RestockChance = 0.24,
		Radius = 19, Duration = 840, GrowBoost = 2.5, StardustChance = 0.18,
		Color = rgb(170, 80, 255), DustColor = rgb(200, 160, 255),
		Description = "A spinning galaxy that sprays galaxy stardust. Planets grow 2.5x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_solarstardust", Name = "Solar Stardust Sprinkler", Rarity = "Legendary",
		Cost = 500000000, Stock = { 1, 1 }, RestockChance = 0.16,
		Radius = 21, Duration = 1020, GrowBoost = 3, StardustChance = 0.21,
		Color = rgb(255, 200, 60), DustColor = rgb(255, 225, 130),
		Description = "A blazing sun with a crown of flames and golden star dust. Planets grow 3x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_blackholestardust", Name = "Black Hole Stardust Sprinkler", Rarity = "Mythic",
		Cost = 2000000000, Stock = { 1, 1 }, RestockChance = 0.08,
		Radius = 24, Duration = 1260, GrowBoost = 3.6, StardustChance = 0.34,
		Color = rgb(255, 60, 200), DustColor = rgb(255, 150, 230),
		Description = "A magenta black hole in a storm of debris. The best for black hole mutations.",
	}),
	sprinkler({
		Id = "sprinkler_nebulastardust", Name = "Nebula Stardust Sprinkler", Rarity = "Divine",
		Cost = 5000000000, Stock = { 1, 1 }, RestockChance = 0.045,
		Radius = 27, Duration = 1500, GrowBoost = 4.2, StardustChance = 0.37,
		Color = rgb(80, 230, 255), DustColor = rgb(170, 240, 255),
		Description = "A living nebula with a crystal heart. Planets grow 4.2x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_supernovastardust", Name = "Supernova Stardust Sprinkler", Rarity = "Celestial",
		Cost = 10000000000, Stock = { 1, 1 }, RestockChance = 0.028,
		Radius = 30, Duration = 1800, GrowBoost = 5.2, StardustChance = 0.42,
		Color = rgb(255, 210, 90), DustColor = rgb(255, 240, 200),
		Description = "A star exploding into crystal spikes and golden stardust. Planets grow 5.2x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_celestialstardust", Name = "Celestial Stardust Sprinkler", Rarity = "Celestial",
		Cost = 12500000000, Stock = { 1, 1 }, RestockChance = 0.024,
		Radius = 31, Duration = 1950, GrowBoost = 5.6, StardustChance = 0.46,
		Color = rgb(200, 250, 255), DustColor = rgb(230, 250, 255),
		Description = "A heavenly orb with wings and a living constellation. Planets grow 5.6x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_quantumstardust", Name = "Quantum Stardust Sprinkler", Rarity = "Cosmic",
		Cost = 20000000000, Stock = { 1, 1 }, RestockChance = 0.018,
		Radius = 33, Duration = 2100, GrowBoost = 6.2, StardustChance = 0.5,
		Color = rgb(80, 255, 110), DustColor = rgb(180, 255, 190),
		Description = "Nested quantum cubes bending space. Planets grow 6.2x as fast.",
	}),
	sprinkler({
		Id = "sprinkler_voidstardust", Name = "Void Stardust Sprinkler", Rarity = "Limited",
		Cost = 30000000000, Stock = { 1, 1 }, RestockChance = 0.012,
		Radius = 35, Duration = 2400, GrowBoost = 7, StardustChance = 0.6,
		Color = rgb(150, 70, 255), DustColor = rgb(200, 160, 255),
		Description = "LIMITED. An obsidian crown around a violet black hole. Planets grow 7x as fast.",
	}),
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
