local PlanetConfig = {}

PlanetConfig.StartCoins = 50

PlanetConfig.Rarities = {
	Common = { Name = "COMMON", Color = { 176, 176, 176 }, Weight = 1 },
	Uncommon = { Name = "UNCOMMON", Color = { 85, 212, 92 }, Weight = 2 },
	Rare = { Name = "RARE", Color = { 58, 159, 255 }, Weight = 3 },
	Epic = { Name = "EPIC", Color = { 172, 85, 247 }, Weight = 4 },
	Legendary = { Name = "LEGENDARY", Color = { 255, 196, 56 }, Weight = 5 },
	Mythic = { Name = "MYTHIC", Color = { 255, 105, 180 }, Weight = 6 },
}

PlanetConfig.Planets = {
	{ Id = "Mercury", Name = "Mercury", Cost = 25, GrowTime = 6, SellValue = 60, Color = { 176, 164, 152 }, Diameter = 3.5, Rarity = "Common" },
	{ Id = "Venus", Name = "Venus", Cost = 75, GrowTime = 40, SellValue = 200, Color = { 222, 184, 106 }, Diameter = 4.5, Rarity = "Common" },
	{ Id = "Earth", Name = "Earth", Cost = 200, GrowTime = 80, SellValue = 600, Color = { 64, 128, 220 }, Diameter = 5.5, Rarity = "Uncommon" },
	{ Id = "Mars", Name = "Mars", Cost = 600, GrowTime = 150, SellValue = 2000, Color = { 196, 84, 54 }, Diameter = 6.5, Rarity = "Rare" },
	{ Id = "Jupiter", Name = "Jupiter", Cost = 2000, GrowTime = 300, SellValue = 7500, Color = { 214, 152, 98 }, Diameter = 8, Rarity = "Epic" },
	{ Id = "Saturn", Name = "Saturn", Cost = 6000, GrowTime = 600, SellValue = 25000, Color = { 226, 196, 118 }, Diameter = 9, Rarity = "Legendary" },
	{ Id = "Uranus", Name = "Uranus", Cost = 15000, GrowTime = 900, SellValue = 65000, Color = { 148, 228, 233 }, Diameter = 9.5, Rarity = "Mythic" },
	{ Id = "Neptune", Name = "Neptune", Cost = 40000, GrowTime = 1500, SellValue = 180000, Color = { 52, 92, 235 }, Diameter = 10, Rarity = "Mythic" },
}

function PlanetConfig.Get(id)
	for _, planet in ipairs(PlanetConfig.Planets) do
		if planet.Id == id then
			return planet
		end
	end
	return nil
end

function PlanetConfig.GetRarity(planet)
	return PlanetConfig.Rarities[planet.Rarity] or PlanetConfig.Rarities.Common
end

return PlanetConfig