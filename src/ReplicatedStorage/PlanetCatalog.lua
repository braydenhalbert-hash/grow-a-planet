--[[
	PlanetCatalog  (ModuleScript)  -- REPLACES the earlier PlanetCatalog
	Put in: ReplicatedStorage   (name it exactly: PlanetCatalog)

	Every planet, star and black hole: price, sell value, grow time, weight range, rarity,
	and how the model looks. The shop, packs, planting and selling all read from this.

	Group:   "Planet"    sold in the Planet shop (the green stand)
	         "Star"      sold in the Sun shop (the yellow stand at the back)
	         "BlackHole" only comes out of Black Hole Packs
	RestockChance (optional): 0.2 = only comes into stock at 20% of restocks (1 = every restock).
	          The rarer and pricier a seed, the lower its chance. The shop's ODDS list shows these.

	Look fields (all optional except Size and Color):
	  Size      diameter in studs
	  Color     body color        Material  body material
	  Tilt      axis tilt in degrees (tilts rings, bands, moons, the spin axis)
	  Spin      how fast the surface details (continents, clouds, spots) turn, radians/second
	  Glow      { Color, Size (x diameter), Transparency }   soft atmosphere shell
	  Bands     { Pos (-1..1), Thick (x diameter), Color }
	  Patches   { Color, Count, Size (x diameter), Material }        random continents / craters / sunspots
	  Spots     list of { Lat, Lon, Size, Color, Material }          placed exactly (polar caps, storms)
	  Clouds    { Color, Count, Size, Transparency }                 puffs that turn a bit faster than the ground
	  Rings     list of separate rings (use ringBand to make lots of them)
	  Moons     list of { Size, Distance (x diameter), Angle, Color, Speed (radians/second, negative = backwards), Neon }
	  Debris    { Count, Color, Size, MinRadius, MaxRadius, Height, Speed }   orbiting rocks
	  Halo      black hole / star light that always faces the camera (see the black holes below)
	  Light     { Color, Range, Brightness }
]]

local PlanetCatalog = {}

local function c(r, g, b)
	return Color3.fromRGB(r, g, b)
end

---------------------------------------------------------------------
-- Ring helpers
---------------------------------------------------------------------
local function sampleColors(colors, a)
	local n = #colors
	if n == 1 then
		return colors[1]
	end
	local pos = a * (n - 1)
	local i = math.floor(pos) + 1
	local frac = pos - math.floor(pos)
	return colors[i]:Lerp(colors[math.min(i + 1, n)], frac)
end

-- Makes many thin, separate rings between two sizes (From / To = outer diameter in planet diameters).
--   Colors      colors blended from the inside to the outside
--   Speed       degrees/second of the innermost ring (outer rings turn slower, like real orbits)
--   Fill        how much of the gap between rings each ring fills (0.3 thin lines .. 0.9 almost solid)
--   Neon        glowing rings        Streak: rings get bright/dark streaks so you can see them turn
local function ringBand(spec)
	local rings = {}
	local rng = Random.new(spec.Seed or 1)
	local count = spec.Count
	local step = count > 1 and (spec.To - spec.From) / (count - 1) or 0
	local fill = spec.Fill or 0.6

	for i = 1, count do
		local a = count > 1 and (i - 1) / (count - 1) or 0
		local scale = spec.From + step * (i - 1)
		local color = sampleColors(spec.Colors, a)
		color = color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, spec.Dim or 0.2))

		local thick = (step / 2) * fill * rng:NextNumber(0.7, 1.3)
		if count == 1 then
			thick = spec.Thick or 0.02
		end

		table.insert(rings, {
			Scale = scale,
			Thick = math.max(thick, 0.004),
			Color = color,
			Neon = spec.Neon or false,
			Transparency = (spec.Transparency or 0) + rng:NextNumber(0, spec.TransparencyVar or 0),
			Streak = spec.Streak ~= false,
			StreakAmount = spec.StreakAmount or 0.7,
			Speed = (spec.Speed or 10) * (spec.From / scale) ^ 1.5 * (spec.Direction or 1),
		})
	end
	return rings
end

-- joins several ring bands into one list, biggest ring first
local function joinRings(...)
	local all = {}
	for _, list in ipairs({ ... }) do
		for _, ring in ipairs(list) do
			table.insert(all, ring)
		end
	end
	table.sort(all, function(a, b)
		return a.Scale > b.Scale
	end)
	return all
end

---------------------------------------------------------------------
-- Rarities
---------------------------------------------------------------------
PlanetCatalog.Rarities = {
	Common    = { Order = 1, Color = c(165, 165, 180), Stock = { 6, 10 } },
	Uncommon  = { Order = 2, Color = c(90, 210, 120),  Stock = { 4, 8 } },
	Rare      = { Order = 3, Color = c(80, 150, 255),  Stock = { 3, 6 } },
	Epic      = { Order = 4, Color = c(200, 90, 255),  Stock = { 2, 4 } },
	Legendary = { Order = 5, Color = c(255, 175, 60),  Stock = { 1, 3 } },
	Mythic    = { Order = 6, Color = c(255, 70, 120),  Stock = { 1, 2 } },
	Divine    = { Order = 7, Color = c(255, 230, 140), Stock = { 1, 1 } }, -- sprinklers only
	Celestial = { Order = 8, Color = c(120, 240, 255), Stock = { 1, 1 } }, -- sprinklers only
	Cosmic    = { Order = 9, Color = c(90, 255, 120),  Stock = { 1, 1 } }, -- sprinklers only
	Limited   = { Order = 10, Color = c(190, 140, 255), Stock = { 1, 1 } }, -- sprinklers only
}

---------------------------------------------------------------------
-- Planets, the Sun, and black holes
---------------------------------------------------------------------
PlanetCatalog.Planets = {
	----------------------------------------------------------------- planets
	{
		Id = "moon", Name = "Moon", Group = "Planet", Rarity = "Common", RestockChance = 1,
		Cost = 100, SellValue = 150, GrowTime = 30, Weight = { 0.8, 1.4 },
		Description = "A small, cratered rock. Great for beginners.",
		Look = {
			Size = 4, Color = c(190, 190, 196), Material = Enum.Material.Concrete, Spin = 0.06,
			Patches = { Color = c(140, 140, 150), Count = 10, Size = 0.2 },
			Spots = {
				{ Lat = 35, Lon = 80, Size = 0.15, Color = c(226, 226, 232) },
				{ Lat = -30, Lon = 200, Size = 0.11, Color = c(218, 218, 224) },
				{ Lat = 10, Lon = 290, Size = 0.09, Color = c(122, 122, 132) },
			},
		},
	},
	{
		Id = "mercury", Name = "Mercury", Group = "Planet", Rarity = "Common", RestockChance = 0.85,
		Cost = 250, SellValue = 375, GrowTime = 50, Weight = { 1.0, 2.0 },
		Description = "Tiny, scorched and covered in craters.",
		Look = {
			Size = 5, Color = c(155, 145, 135), Material = Enum.Material.Rock, Spin = 0.05,
			Patches = { Color = c(112, 102, 96), Count = 11, Size = 0.19 },
			Spots = {
				{ Lat = 20, Lon = 60, Size = 0.16, Color = c(190, 178, 165) },
				{ Lat = -40, Lon = 230, Size = 0.12, Color = c(95, 86, 80) },
			},
		},
	},
	{
		Id = "venus", Name = "Venus", Group = "Planet", Rarity = "Common", RestockChance = 0.7,
		Cost = 600, SellValue = 870, GrowTime = 75, Weight = { 2.0, 3.5 },
		Description = "Wrapped in thick golden clouds.",
		Look = {
			Size = 7, Color = c(228, 188, 112), Material = Enum.Material.Sand, Tilt = 3, Spin = 0.1,
			Glow = { Color = c(255, 215, 140), Size = 1.1, Transparency = 0.82 },
			Bands = {
				{ Pos = 0.5, Thick = 0.05, Color = c(238, 205, 140) },
				{ Pos = 0.2, Thick = 0.05, Color = c(214, 168, 98) },
				{ Pos = -0.15, Thick = 0.05, Color = c(240, 208, 146) },
				{ Pos = -0.5, Thick = 0.05, Color = c(212, 166, 96) },
			},
			Clouds = { Color = c(252, 236, 190), Count = 10, Size = 0.24, Transparency = 0.3 },
		},
	},
	{
		Id = "earth", Name = "Earth", Group = "Planet", Rarity = "Uncommon", RestockChance = 0.55,
		Cost = 1500, SellValue = 2200, GrowTime = 110, Weight = { 3.0, 5.0 },
		Description = "Oceans, land, ice and one friendly moon.",
		Look = {
			Size = 8, Color = c(40, 110, 212), Material = Enum.Material.SmoothPlastic, Tilt = 23, Spin = 0.22,
			Patches = { Color = c(66, 168, 84), Count = 8, Size = 0.3 },
			Spots = {
				{ Lat = 90, Lon = 0, Size = 0.34, Color = c(245, 248, 255) },
				{ Lat = -90, Lon = 0, Size = 0.34, Color = c(245, 248, 255) },
				{ Lat = 30, Lon = 120, Size = 0.14, Color = c(150, 120, 70) },
				{ Lat = -20, Lon = 250, Size = 0.12, Color = c(160, 130, 76) },
			},
			Clouds = { Color = c(255, 255, 255), Count = 13, Size = 0.13, Transparency = 0.25 },
			Glow = { Color = c(140, 200, 255), Size = 1.09, Transparency = 0.86 },
			Collect = { MoonValue = 20, Regrow = 120 },
			Moons = { { Size = 0.2, Distance = 1.1, Angle = 40, Color = c(190, 190, 196), Speed = 0.55 } },
		},
	},
	{
		Id = "mars", Name = "Mars", Group = "Planet", Rarity = "Uncommon", RestockChance = 0.4,
		Cost = 3500, SellValue = 4900, GrowTime = 150, Weight = { 2.0, 4.0 },
		Description = "The red planet, with two tiny moons.",
		Look = {
			Size = 6, Color = c(196, 88, 52), Material = Enum.Material.Rock, Tilt = 25, Spin = 0.2,
			Patches = { Color = c(138, 60, 38), Count = 8, Size = 0.24 },
			Spots = {
				{ Lat = 90, Lon = 0, Size = 0.24, Color = c(244, 240, 236) },
				{ Lat = -90, Lon = 0, Size = 0.2, Color = c(238, 232, 226) },
				{ Lat = 5, Lon = 70, Size = 0.18, Color = c(104, 44, 30) },
			},
			Glow = { Color = c(220, 140, 110), Size = 1.06, Transparency = 0.9 },
			Collect = { MoonValue = 35, Regrow = 120 },
			Moons = {
				{ Size = 0.1, Distance = 0.85, Angle = 20, Color = c(130, 110, 100), Speed = 1.4 },
				{ Size = 0.07, Distance = 1.1, Angle = 200, Color = c(120, 100, 90), Speed = 0.8 },
			},
		},
	},
	{
		Id = "jupiter", Name = "Jupiter", Group = "Planet", Rarity = "Rare", RestockChance = 0.25,
		Cost = 18000, SellValue = 25000, GrowTime = 300, Weight = { 8.0, 14.0 },
		Description = "A giant striped gas planet with a crowd of moons.",
		Look = {
			Size = 16, Color = c(214, 168, 118), Material = Enum.Material.SmoothPlastic, Tilt = 3, Spin = 0.38,
			Bands = {
				{ Pos = -0.82, Thick = 0.05, Color = c(176, 112, 76) },
				{ Pos = -0.66, Thick = 0.05, Color = c(232, 212, 182) },
				{ Pos = -0.5, Thick = 0.055, Color = c(190, 122, 82) },
				{ Pos = -0.33, Thick = 0.05, Color = c(240, 222, 196) },
				{ Pos = -0.15, Thick = 0.06, Color = c(200, 130, 86) },
				{ Pos = 0.04, Thick = 0.055, Color = c(244, 228, 204) },
				{ Pos = 0.22, Thick = 0.055, Color = c(196, 124, 80) },
				{ Pos = 0.4, Thick = 0.05, Color = c(238, 220, 192) },
				{ Pos = 0.58, Thick = 0.05, Color = c(176, 112, 74) },
				{ Pos = 0.76, Thick = 0.045, Color = c(226, 204, 172) },
			},
			Spots = {
				{ Lat = -20, Lon = 30, Size = 0.2, Color = c(206, 74, 54) },
				{ Lat = 28, Lon = 200, Size = 0.09, Color = c(250, 240, 224) },
				{ Lat = -40, Lon = 120, Size = 0.07, Color = c(250, 240, 224) },
			},
			Clouds = { Color = c(252, 238, 214), Count = 9, Size = 0.12, Transparency = 0.45 },
			Collect = { MoonValue = 330, Regrow = 120 },
			Glow = { Color = c(230, 190, 140), Size = 1.04, Transparency = 0.9 },
			Moons = {
				{ Size = 0.08, Distance = 0.8, Angle = 10, Color = c(240, 210, 120), Speed = 1.6 },
				{ Size = 0.06, Distance = 0.95, Angle = 130, Color = c(235, 235, 240), Speed = 1.1 },
				{ Size = 0.075, Distance = 1.1, Angle = 250, Color = c(150, 130, 110), Speed = 0.7 },
				{ Size = 0.07, Distance = 1.28, Angle = 330, Color = c(90, 84, 80), Speed = 0.45 },
			},
		},
	},
	{
		Id = "saturn", Name = "Saturn", Group = "Planet", Rarity = "Rare", RestockChance = 0.15,
		Cost = 45000, SellValue = 60000, GrowTime = 420, Weight = { 7.0, 12.0 },
		Description = "Famous for its glittering rings.",
		Look = {
			Size = 14, Color = c(226, 202, 150), Material = Enum.Material.SmoothPlastic, Tilt = 27, Spin = 0.3,
			Bands = {
				{ Pos = 0.62, Thick = 0.05, Color = c(206, 176, 122) },
				{ Pos = 0.38, Thick = 0.055, Color = c(240, 224, 178) },
				{ Pos = 0.12, Thick = 0.06, Color = c(214, 184, 130) },
				{ Pos = -0.14, Thick = 0.055, Color = c(240, 224, 180) },
				{ Pos = -0.4, Thick = 0.055, Color = c(206, 176, 122) },
				{ Pos = -0.65, Thick = 0.05, Color = c(232, 212, 168) },
			},
			Clouds = { Color = c(250, 238, 205), Count = 6, Size = 0.12, Transparency = 0.5 },
			Collect = { MoonValue = 500, Regrow = 120 },
			Glow = { Color = c(240, 220, 170), Size = 1.04, Transparency = 0.9 },
			Rings = joinRings(
				-- faint inner ring
				ringBand({ From = 1.3, To = 1.55, Count = 4, Colors = { c(110, 96, 78), c(140, 122, 96) },
					Speed = 16, Transparency = 0.35, Fill = 0.5, Seed = 11 }),
				-- bright main ring
				ringBand({ From = 1.62, To = 2.2, Count = 14, Colors = { c(232, 212, 168), c(210, 186, 142), c(242, 226, 188) },
					Speed = 12, Fill = 0.7, TransparencyVar = 0.15, Seed = 12 }),
				-- outer ring (the dark gap between the two is on purpose)
				ringBand({ From = 2.32, To = 2.66, Count = 7, Colors = { c(208, 188, 148), c(188, 168, 128) },
					Speed = 9, Fill = 0.6, Seed = 13 }),
				-- one thin outer ring
				ringBand({ From = 2.78, To = 2.78, Count = 1, Thick = 0.01, Colors = { c(232, 218, 184) },
					Speed = 7, Seed = 14 })
			),
			Moons = {
				{ Size = 0.08, Distance = 1.65, Angle = 60, Color = c(214, 150, 70), Speed = 0.35 },
				{ Size = 0.035, Distance = 1.5, Angle = 200, Color = c(240, 244, 250), Speed = 0.7 },
				{ Size = 0.045, Distance = 1.85, Angle = 300, Color = c(180, 178, 174), Speed = 0.25 },
			},
		},
	},
	{
		Id = "uranus", Name = "Uranus", Group = "Planet", Rarity = "Epic", RestockChance = 0.08,
		Cost = 300000, SellValue = 400000, GrowTime = 720, Weight = { 6.0, 10.0 },
		Description = "An icy planet spinning on its side, with thin dark rings.",
		Look = {
			Size = 11, Color = c(150, 222, 228), Material = Enum.Material.SmoothPlastic, Tilt = 82, Spin = 0.18,
			Glow = { Color = c(175, 240, 245), Size = 1.1, Transparency = 0.84 },
			Clouds = { Color = c(235, 252, 255), Count = 5, Size = 0.12, Transparency = 0.55 },
			Collect = { MoonValue = 3400, Regrow = 120 },
			Rings = joinRings(
				ringBand({ From = 1.5, To = 2.1, Count = 9, Colors = { c(190, 226, 232), c(150, 190, 200), c(205, 238, 244) },
					Speed = 14, Fill = 0.35, Transparency = 0.15, TransparencyVar = 0.2, Seed = 21 })
			),
			Moons = {
				{ Size = 0.05, Distance = 1.35, Angle = 90, Color = c(205, 210, 214), Speed = 0.6 },
				{ Size = 0.04, Distance = 1.6, Angle = 270, Color = c(170, 176, 182), Speed = 0.4 },
			},
		},
	},
	{
		Id = "neptune", Name = "Neptune", Group = "Planet", Rarity = "Epic", RestockChance = 0.04,
		Cost = 800000, SellValue = 1050000, GrowTime = 900, Weight = { 6.0, 10.0 },
		Description = "Deep blue and stormy, far from the sun.",
		Look = {
			Size = 10.5, Color = c(52, 92, 218), Material = Enum.Material.SmoothPlastic, Tilt = 28, Spin = 0.25,
			Glow = { Color = c(80, 130, 255), Size = 1.1, Transparency = 0.84 },
			Bands = {
				{ Pos = 0.5, Thick = 0.05, Color = c(40, 76, 196) },
				{ Pos = 0.2, Thick = 0.05, Color = c(78, 124, 240) },
				{ Pos = -0.1, Thick = 0.055, Color = c(34, 66, 178) },
				{ Pos = -0.4, Thick = 0.05, Color = c(84, 130, 246) },
			},
			Spots = {
				{ Lat = -20, Lon = 100, Size = 0.17, Color = c(20, 38, 128) },
				{ Lat = -35, Lon = 230, Size = 0.07, Color = c(240, 246, 255) },
			},
			Clouds = { Color = c(240, 246, 255), Count = 7, Size = 0.1, Transparency = 0.4 },
			Collect = { MoonValue = 6500, Regrow = 120 },
			Rings = joinRings(
				ringBand({ From = 1.5, To = 1.9, Count = 4, Colors = { c(120, 150, 230) },
					Speed = 12, Fill = 0.3, Transparency = 0.55, Seed = 31 })
			),
			Moons = { { Size = 0.1, Distance = 1.2, Angle = 150, Color = c(215, 195, 195), Speed = -0.5 } },
		},
	},

	----------------------------------------------------------------- suns (the Sun shop)
	{
		Id = "red_dwarf", Name = "Red Dwarf", Group = "Star", Rarity = "Uncommon", RestockChance = 0.85,
		Cost = 7500, SellValue = 10500, GrowTime = 200, Weight = { 4.0, 7.0 },
		Description = "A small, cool, glowing red star. The most common star there is.",
		Look = {
			Size = 9, Color = c(255, 96, 52), Material = Enum.Material.Neon, Tilt = 5, Spin = 0.05,
			Patches = { Color = c(200, 50, 30), Count = 7, Size = 0.17, Material = Enum.Material.Neon },
			Glow = { Color = c(255, 80, 40), Size = 1.16, Transparency = 0.8 },
			Halo = { Scale = 2.2, Brightness = 1.6, Glow = { Color = c(255, 90, 50), Scale = 2.0, Layers = 6, Opacity = 0.06 } },
			Light = { Color = c(255, 110, 70), Range = 22, Brightness = 1.4 },
		},
	},
	{
		Id = "white_dwarf", Name = "White Dwarf", Group = "Star", Rarity = "Rare", RestockChance = 0.4,
		Cost = 110000, SellValue = 150000, GrowTime = 540, Weight = { 6.0, 10.0 },
		Description = "The tiny, white-hot core left behind by a dead star.",
		Look = {
			Size = 6, Color = c(235, 244, 255), Material = Enum.Material.Neon, Tilt = 0, Spin = 0.1,
			Glow = { Color = c(190, 220, 255), Size = 1.25, Transparency = 0.75 },
			Halo = {
				Scale = 2.6, Brightness = 2,
				Glow = { Color = c(200, 225, 255), Scale = 2.4, Layers = 7, Opacity = 0.06 },
				Flare = { Color = c(230, 240, 255), Length = 2.6, Thick = 0.02 },
			},
			Light = { Color = c(210, 230, 255), Range = 26, Brightness = 1.8 },
		},
	},
	{
		Id = "blue_giant", Name = "Blue Giant", Group = "Star", Rarity = "Epic", RestockChance = 0.15,
		Cost = 2000000, SellValue = 2600000, GrowTime = 1200, Weight = { 12.0, 20.0 },
		Description = "A huge, scorching blue star that burns brighter than anything near it.",
		Look = {
			Size = 18, Color = c(110, 170, 255), Material = Enum.Material.Neon, Tilt = 8, Spin = 0.07,
			Patches = { Color = c(200, 230, 255), Count = 9, Size = 0.14, Material = Enum.Material.Neon },
			Glow = { Color = c(90, 150, 255), Size = 1.2, Transparency = 0.76 },
			Halo = {
				Scale = 2.8, Brightness = 2.2,
				Glow = { Color = c(110, 170, 255), Scale = 2.6, Layers = 8, Opacity = 0.06 },
				Flare = { Color = c(190, 220, 255), Length = 2.6, Thick = 0.022 },
			},
			Light = { Color = c(140, 190, 255), Range = 44, Brightness = 2 },
		},
	},
	{
		Id = "sun", Name = "Sun", Group = "Star", Rarity = "Legendary", RestockChance = 0.07,
		Cost = 6000000, SellValue = 7800000, GrowTime = 1800, Weight = { 15.0, 25.0 },
		Description = "A blazing star. It lights up everything around it.",
		Look = {
			Size = 22, Color = c(255, 202, 64), Material = Enum.Material.Neon, Tilt = 7, Spin = 0.06,
			Patches = { Color = c(255, 125, 25), Count = 8, Size = 0.15, Material = Enum.Material.Neon },
			Glow = { Color = c(255, 150, 40), Size = 1.18, Transparency = 0.78 },
			Halo = {
				Scale = 2.6, Brightness = 2,
				Glow = { Color = c(255, 170, 60), Scale = 2.4, Layers = 8, Opacity = 0.06 },
				Flare = { Color = c(255, 215, 130), Length = 2.3, Thick = 0.02 },
			},
			Light = { Color = c(255, 200, 120), Range = 48, Brightness = 2 },
		},
	},
	{
		Id = "betelgeuse", Name = "Betelgeuse", Group = "Star", Rarity = "Legendary", RestockChance = 0.03,
		Cost = 18000000, SellValue = 22500000, GrowTime = 2700, Weight = { 30.0, 50.0 },
		Description = "A red supergiant so big it would swallow Jupiter's orbit. Glowing gas boils off its surface.",
		Look = {
			Size = 28, Color = c(255, 120, 50), Material = Enum.Material.Neon, Tilt = 4, Spin = 0.04,
			Patches = { Color = c(210, 60, 25), Count = 12, Size = 0.18, Material = Enum.Material.Neon },
			Clouds = { Color = c(255, 170, 90), Count = 8, Size = 0.16, Transparency = 0.5 },
			Glow = { Color = c(255, 100, 40), Size = 1.22, Transparency = 0.74 },
			Halo = {
				Scale = 3.0, Brightness = 2.2,
				Glow = { Color = c(255, 110, 50), Scale = 2.8, Layers = 9, Opacity = 0.06 },
				Flare = { Color = c(255, 190, 120), Length = 2.6, Thick = 0.022 },
			},
			Light = { Color = c(255, 140, 80), Range = 54, Brightness = 2.2 },
		},
	},
	{
		Id = "pulsar", Name = "Pulsar", Group = "Star", Rarity = "Mythic", RestockChance = 0.01,
		Cost = 60000000, SellValue = 75000000, GrowTime = 3600, Weight = { 80.0, 140.0 },
		Description = "A spinning neutron star that fires beams of light across space.",
		Look = {
			Size = 7, Color = c(200, 235, 255), Material = Enum.Material.Neon, Tilt = 20, Spin = 1.2,
			Glow = { Color = c(120, 200, 255), Size = 1.35, Transparency = 0.7 },
			Rings = joinRings(
				ringBand({ From = 1.6, To = 2.6, Count = 6, Colors = { c(170, 225, 255), c(110, 160, 255) },
					Neon = true, Speed = 160, Fill = 0.35, TransparencyVar = 0.35, Seed = 91 })
			),
			Halo = {
				Scale = 3.6, Brightness = 2.6,
				Glow = { Color = c(140, 210, 255), Scale = 3.0, Layers = 9, Opacity = 0.06 },
				Flare = { Color = c(220, 245, 255), Length = 4.2, Thick = 0.03 },
			},
			Light = { Color = c(170, 220, 255), Range = 50, Brightness = 2.4 },
		},
	},

	----------------------------------------------------------------- black holes (packs only)
	{
		Id = "bh_micro", Name = "Micro Black Hole", Group = "BlackHole", Rarity = "Common", Buyable = false,
		Cost = 300, SellValue = 400, GrowTime = 30, Weight = { 0.5, 1.2 },
		Description = "Tiny, but it still bends the light around it.",
		Look = {
			Size = 2.5, Color = c(2, 2, 5), Material = Enum.Material.SmoothPlastic, Tilt = 10,
			Rings = joinRings(
				ringBand({ From = 1.5, To = 2.2, Count = 5, Colors = { c(255, 170, 80), c(255, 215, 160), c(255, 120, 40) },
					Neon = true, Speed = 120, Fill = 0.6, TransparencyVar = 0.3, Seed = 41 })
			),
			Halo = {
				Scale = 2.4, Brightness = 2,
				Photon = { Color = c(255, 235, 200), Scale = 1.06, Thick = 0.015 },
				Arcs = { { Scale = 1.3, Thick = 0.04, Color = c(255, 190, 110), Transparency = 0.35 } },
				Glow = { Color = c(255, 150, 60), Scale = 1.8, Layers = 5, Opacity = 0.05 },
			},
			Collect = { MoonValue = 10, Regrow = 120 },
			Moons = { { Size = 0.12, Distance = 1.5, Angle = 30, Color = c(150, 150, 158), Speed = 1.8 } },
			Light = { Color = c(255, 170, 90), Range = 14, Brightness = 1 },
		},
	},
	{
		Id = "bh_stellar", Name = "Stellar Black Hole", Group = "BlackHole", Rarity = "Uncommon", Buyable = false,
		Cost = 3000, SellValue = 4000, GrowTime = 90, Weight = { 3.0, 6.0 },
		Description = "What's left when a big star collapses. A blue star circles it.",
		Look = {
			Size = 4.5, Color = c(2, 2, 5), Material = Enum.Material.SmoothPlastic, Tilt = 12,
			Rings = joinRings(
				ringBand({ From = 1.45, To = 2.7, Count = 9, Colors = { c(255, 235, 200), c(255, 160, 60), c(235, 100, 30) },
					Neon = true, Speed = 90, Fill = 0.6, TransparencyVar = 0.3, Seed = 42 })
			),
			Halo = {
				Scale = 3.0, Brightness = 2,
				Photon = { Color = c(255, 238, 205), Scale = 1.05, Thick = 0.014 },
				Arcs = {
					{ Scale = 1.25, Thick = 0.05, Color = c(255, 225, 170), Transparency = 0.25 },
					{ Scale = 1.4, Thick = 0.07, Color = c(255, 150, 60), Transparency = 0.55 },
				},
				Glow = { Color = c(255, 150, 60), Scale = 2.0, Layers = 6, Opacity = 0.05 },
			},
			Collect = { MoonValue = 50, Regrow = 120 },
			Moons = { { Size = 0.2, Distance = 1.9, Angle = 200, Color = c(150, 190, 255), Speed = 0.9, Neon = true } },
			Light = { Color = c(255, 170, 90), Range = 22, Brightness = 1.4 },
		},
	},
	{
		Id = "bh_nova", Name = "Nova Black Hole", Group = "BlackHole", Rarity = "Rare", Buyable = false,
		Cost = 30000, SellValue = 40000, GrowTime = 240, Weight = { 8.0, 15.0 },
		Description = "A violent one: a fiery core, swirling rings and flying rocks.",
		Look = {
			Size = 7, Color = c(40, 6, 4), Material = Enum.Material.SmoothPlastic, Tilt = 12,
			Glow = { Color = c(255, 90, 20), Size = 1.3, Transparency = 0.72 },
			Rings = joinRings(
				-- white-hot inner rings
				ringBand({ From = 1.25, To = 1.6, Count = 5, Colors = { c(255, 235, 170), c(255, 150, 50), c(255, 90, 20) },
					Neon = true, Speed = 140, Fill = 0.7, Seed = 51 }),
				-- wide grey swirl
				ringBand({ From = 1.9, To = 3.6, Count = 14, Colors = { c(240, 240, 245), c(150, 150, 160), c(215, 215, 225), c(120, 120, 130) },
					Speed = 22, Fill = 0.55, Transparency = 0.1, TransparencyVar = 0.35, StreakAmount = 0.85, Seed = 52 })
			),
			Halo = {
				Scale = 3.4, Brightness = 2.2,
				Photon = { Color = c(255, 222, 150), Scale = 1.05, Thick = 0.02 },
				Arcs = { { Scale = 1.25, Thick = 0.04, Color = c(255, 160, 60), Transparency = 0.2 } },
				Flare = { Color = c(255, 205, 115), Length = 3.0, Thick = 0.035 },
				Glow = { Color = c(255, 110, 30), Scale = 2.0, Layers = 8, Opacity = 0.07 },
			},
			Collect = { DebrisValue = 160, Regrow = 120 },
			Debris = { Count = 14, Color = c(255, 140, 60), Size = 0.07, MinRadius = 0.95, MaxRadius = 1.7, Height = 0.12, Speed = 0.9, Neon = true },
			Light = { Color = c(255, 120, 40), Range = 32, Brightness = 2 },
		},
	},
	{
		Id = "bh_sgra", Name = "Sagittarius A*", Group = "BlackHole", Rarity = "Epic", Buyable = false,
		Cost = 450000, SellValue = 600000, GrowTime = 600, Weight = { 20.0, 40.0 },
		Description = "The black hole at the heart of our galaxy. A tiny dark moon drifts by.",
		Look = {
			Size = 10, Color = c(3, 3, 5), Material = Enum.Material.SmoothPlastic, Tilt = 6,
			Rings = joinRings(
				ringBand({ From = 1.4, To = 3.4, Count = 18, Colors = { c(255, 250, 235), c(255, 238, 200), c(255, 220, 160) },
					Neon = true, Speed = 60, Fill = 0.6, TransparencyVar = 0.3, StreakAmount = 0.8, Seed = 61 })
			),
			Halo = {
				Scale = 3.6, Brightness = 2.4,
				Photon = { Color = c(255, 255, 245), Scale = 1.04, Thick = 0.012 },
				Arcs = {
					{ Scale = 1.18, Thick = 0.05, Color = c(255, 250, 230), Transparency = 0.1 },
					{ Scale = 1.3, Thick = 0.06, Color = c(255, 240, 200), Transparency = 0.35 },
					{ Scale = 1.45, Thick = 0.08, Color = c(255, 225, 170), Transparency = 0.6 },
				},
				Glow = { Color = c(255, 235, 190), Scale = 2.2, Layers = 8, Opacity = 0.05 },
			},
			Collect = { MoonValue = 3000, Regrow = 120 },
			Moons = { { Size = 0.08, Distance = 2.0, Angle = 180, Color = c(110, 140, 230), Speed = 0.35 } },
			Light = { Color = c(255, 240, 210), Range = 36, Brightness = 1.6 },
		},
	},
	{
		Id = "bh_m87", Name = "M87*", Group = "BlackHole", Rarity = "Legendary", Buyable = false,
		Cost = 6000000, SellValue = 8000000, GrowTime = 1500, Weight = { 60.0, 110.0 },
		Description = "A giant glowing orange ring, the first black hole ever photographed.",
		Look = {
			Size = 14, Color = c(2, 2, 4), Material = Enum.Material.SmoothPlastic, Tilt = 8,
			Rings = joinRings(
				ringBand({ From = 1.3, To = 1.8, Count = 8, Colors = { c(255, 245, 225), c(255, 200, 120) },
					Neon = true, Speed = 70, Fill = 0.65, Seed = 71 }),
				ringBand({ From = 1.9, To = 3.8, Count = 22, Colors = { c(255, 200, 130), c(255, 150, 60), c(220, 100, 30), c(160, 65, 20) },
					Neon = true, Speed = 40, Fill = 0.6, TransparencyVar = 0.35, Dim = 0.25, Seed = 72 })
			),
			Halo = {
				Scale = 4.0, Brightness = 2.4,
				Photon = { Color = c(255, 240, 205), Scale = 1.04, Thick = 0.014 },
				Arcs = {
					{ Scale = 1.2, Thick = 0.05, Color = c(255, 235, 190), Transparency = 0.1 },
					{ Scale = 1.35, Thick = 0.07, Color = c(255, 190, 100), Transparency = 0.3 },
					{ Scale = 1.5, Thick = 0.09, Color = c(240, 130, 50), Transparency = 0.55 },
				},
				Glow = { Color = c(255, 150, 60), Scale = 2.4, Layers = 9, Opacity = 0.05 },
			},
			Moons = {
				{ Size = 0.07, Distance = 2.2, Angle = 40, Color = c(255, 210, 150), Speed = 0.5, Neon = true },
				{ Size = 0.05, Distance = 2.45, Angle = 220, Color = c(255, 140, 90), Speed = -0.3, Neon = true },
			},
			Collect = { MoonValue = 32000, Regrow = 120 },
			Light = { Color = c(255, 160, 70), Range = 46, Brightness = 2 },
		},
	},
	{
		Id = "bh_ton618", Name = "TON 618", Group = "BlackHole", Rarity = "Mythic", Buyable = false,
		Cost = 45000000, SellValue = 60000000, GrowTime = 3600, Weight = { 150.0, 300.0 },
		Description = "One of the biggest black holes ever found. Huge, blazing and surrounded by wreckage.",
		Look = {
			Size = 22, Color = c(1, 1, 3), Material = Enum.Material.SmoothPlastic, Tilt = 5,
			Glow = { Color = c(255, 150, 60), Size = 1.12, Transparency = 0.9 },
			Rings = joinRings(
				-- white-hot inner rings
				ringBand({ From = 1.25, To = 1.7, Count = 8, Colors = { c(255, 250, 235), c(255, 225, 160) },
					Neon = true, Speed = 80, Fill = 0.65, Seed = 81 }),
				-- blazing main disk
				ringBand({ From = 1.8, To = 3.0, Count = 18, Colors = { c(255, 240, 200), c(255, 190, 100), c(255, 130, 40) },
					Neon = true, Speed = 55, Fill = 0.6, TransparencyVar = 0.3, Seed = 82 }),
				-- dusty outer disk
				ringBand({ From = 3.1, To = 4.4, Count = 14, Colors = { c(200, 120, 60), c(150, 80, 40), c(110, 60, 60) },
					Speed = 28, Fill = 0.55, Transparency = 0.15, TransparencyVar = 0.3, Seed = 83 })
			),
			Halo = {
				Scale = 4.8, Brightness = 2.6,
				Photon = { Color = c(255, 252, 240), Scale = 1.04, Thick = 0.012 },
				Arcs = {
					{ Scale = 1.2, Thick = 0.05, Color = c(255, 252, 235), Transparency = 0.05 },
					{ Scale = 1.3, Thick = 0.06, Color = c(255, 235, 190), Transparency = 0.25 },
					{ Scale = 1.4, Thick = 0.08, Color = c(255, 190, 100), Transparency = 0.45 },
					{ Scale = 1.5, Thick = 0.1, Color = c(240, 130, 50), Transparency = 0.65 },
				},
				Flare = { Color = c(255, 220, 160), Length = 3.4, Thick = 0.025 },
				Glow = { Color = c(255, 160, 70), Scale = 2.8, Layers = 10, Opacity = 0.05 },
			},
			-- the glowing rocks and stars orbiting TON 618 can be collected for coins (they grow back)
			Collect = { MoonValue = 120000, DebrisValue = 15000, Regrow = 120 },
			Debris = { Count = 18, Color = c(255, 150, 60), Size = 0.1, MinRadius = 1.0, MaxRadius = 2.1, Height = 0.1, Speed = 1.1, Neon = true },
			Moons = {
				{ Size = 0.11, Distance = 2.4, Angle = 20, Color = c(255, 205, 120), Speed = 0.45, Neon = true },
				{ Size = 0.1, Distance = 2.55, Angle = 140, Color = c(120, 170, 255), Speed = -0.35, Neon = true },
				{ Size = 0.1, Distance = 2.3, Angle = 260, Color = c(255, 255, 255), Speed = 0.55, Neon = true },
			},
			Light = { Color = c(255, 175, 90), Range = 60, Brightness = 2.4 },
		},
	},
}

---------------------------------------------------------------------
-- Lookups and helpers
---------------------------------------------------------------------
PlanetCatalog.ById = {}
for index, planet in ipairs(PlanetCatalog.Planets) do
	planet.Index = index
	PlanetCatalog.ById[planet.Id] = planet

	-- how wide the whole thing is (in planet diameters), used to space things out
	local look = planet.Look
	local extent = 1
	for _, ring in ipairs(look.Rings or {}) do
		extent = math.max(extent, ring.Scale)
	end
	for _, moon in ipairs(look.Moons or {}) do
		extent = math.max(extent, moon.Distance * 2)
	end
	if look.Debris then
		extent = math.max(extent, look.Debris.MaxRadius * 2)
	end
	look.Extent = extent
end

function PlanetCatalog.Get(id)
	return PlanetCatalog.ById[id]
end

function PlanetCatalog.RarityColor(rarity)
	local info = PlanetCatalog.Rarities[rarity]
	return info and info.Color or PlanetCatalog.Rarities.Common.Color
end

-- Random weight (kg) for a freshly grown planet, rounded to 2 decimals
function PlanetCatalog.RollWeight(planet, rng)
	rng = rng or Random.new()
	local w = rng:NextNumber(planet.Weight[1], planet.Weight[2])
	return math.floor(w * 100 + 0.5) / 100
end

-- Heavier ones sell for more: average weight sells for SellValue
function PlanetCatalog.SellValueFor(planet, weight, mutations)
	local average = (planet.Weight[1] + planet.Weight[2]) / 2
	local value = planet.SellValue * (weight / average)
	if mutations and mutations ~= "" then
		-- mutations (Meteor Shower, Nebula...) boost the selling price, and they stack
		local module = script.Parent:FindFirstChild("MutationCatalog")
		if module then
			local ok, MutationCatalog = pcall(require, module)
			if ok then
				value *= MutationCatalog.SellMult(mutations)
			end
		end
	end
	return math.max(1, math.floor(value + 0.5))
end

-- Random shop stock for a planet, based on its rarity
function PlanetCatalog.RollStock(planet, rng)
	rng = rng or Random.new()
	local range = PlanetCatalog.Rarities[planet.Rarity].Stock
	return rng:NextInteger(range[1], range[2])
end

return PlanetCatalog
