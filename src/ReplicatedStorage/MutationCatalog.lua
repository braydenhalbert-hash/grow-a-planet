--[[
	MutationCatalog  (ModuleScript)
	Put in: ReplicatedStorage   (name it exactly: MutationCatalog, next to PlanetCatalog)

	Mutations are lucky bonuses a planet can get while it grows in your garden.
	A mutated planet shows a glowing title above it, has its own special effects,
	makes MORE coins from the stuff around it (CoinMult) and SELLS for more (SellMult).

	Chance = chance (0.15 = 15%) that a freshly planted seed gets that mutation.
	Every mutation rolls on its own, so ONE planet can get several and they STACK (see Stacking below).
	Change the numbers here to make mutations more or less common or valuable.
]]

local MutationCatalog = {}

-- How mutations stack on one planet:
--   "add"       (default) 1 + (each boost - 1).  Meteor Shower (3x) + Frozen (2x) = 4x
--   "multiply"  each boost multiplies the last.  Meteor Shower (3x) + Frozen (2x) = 6x   (gets big fast!)
MutationCatalog.Stacking = "add"

MutationCatalog.Order = { "meteor", "frozen", "nebula", "solarflare", "supernova", "stardust",
	"dewdrop", "starlit", "nebulabloom", "cosmicglow", "quantumrain", "eventhorizon", "starforged",
	"divinelight", "heavenly", "singularity", "voidtouched",
	-- weather + live event mutations (see "SPACE WEATHER MUTATIONS" below)
	"starsoaked", "cosmic", "ionized", "molten", "aurora", "glacial", "gravitized", "plasma",
	"radioactive", "starborn", "celestial", "abducted", "blackhole", "starfallen", "coronal",
	"wormhole", "xenoform", "galaxy", "ton618" }

-- Rarity tiers: the colour of the popup / title glow, and how wild the effects get (Tier 1..7)
MutationCatalog.Rarities = {
	Common = { Tier = 1, Color = Color3.fromRGB(205, 215, 230) },
	Uncommon = { Tier = 2, Color = Color3.fromRGB(90, 235, 120) },
	Rare = { Tier = 3, Color = Color3.fromRGB(70, 165, 255) },
	Epic = { Tier = 4, Color = Color3.fromRGB(190, 95, 255) },
	Legendary = { Tier = 5, Color = Color3.fromRGB(255, 195, 45) },
	Mythic = { Tier = 6, Color = Color3.fromRGB(255, 70, 120) },
	Divine = { Tier = 7, Color = Color3.fromRGB(255, 255, 255) },
}

MutationCatalog.Mutations = {
	meteor = {
		Id = "meteor", Rarity = "Uncommon", Name = "Meteor Shower",
		Chance = 0.15, CoinMult = 3, SellMult = 3,
		Color = Color3.fromRGB(255, 150, 60), Color2 = Color3.fromRGB(255, 70, 40),
	},
	frozen = {
		Id = "frozen", Rarity = "Common", Name = "Frozen",
		Chance = 0.10, CoinMult = 2, SellMult = 2,
		Color = Color3.fromRGB(170, 235, 255), Color2 = Color3.fromRGB(90, 160, 255),
	},
	nebula = {
		Id = "nebula", Rarity = "Rare", Name = "Nebula",
		Chance = 0.06, CoinMult = 4, SellMult = 4,
		Color = Color3.fromRGB(255, 120, 230), Color2 = Color3.fromRGB(130, 90, 255),
	},
	solarflare = {
		Id = "solarflare", Rarity = "Epic", Name = "Solar Flare",
		Chance = 0.03, CoinMult = 6, SellMult = 6,
		Color = Color3.fromRGB(255, 225, 80), Color2 = Color3.fromRGB(255, 110, 20),
	},
	supernova = {
		Id = "supernova", Rarity = "Legendary", Name = "Supernova",
		Chance = 0.01, CoinMult = 12, SellMult = 12,
		Color = Color3.fromRGB(255, 255, 255), Color2 = Color3.fromRGB(255, 200, 90),
	},
	-- never happens by itself (Chance = 0): only a BLACK HOLE that swallows stardust from a
	-- Stardust Sprinkler (gear shop) can get it. How likely that is is set per sprinkler in GearCatalog.
	stardust = {
		Id = "stardust", Rarity = "Rare", Name = "Stardust",
		Chance = 0, CoinMult = 5, SellMult = 5,
		Color = Color3.fromRGB(215, 190, 255), Color2 = Color3.fromRGB(120, 230, 255),
	},
}

-- SPRINKLER BONUS MUTATIONS: never happen by themselves (Chance = 0). A running sprinkler gives one to
-- the planets in its circle (every 10 seconds each planet has the sprinkler's BonusChance, see GearCatalog).
-- The pricier the sprinkler, the crazier the bonus. Tex = which Stardust texture the effect uses.
local function bonus(id, name, mult, color, color2, tex)
	MutationCatalog.Mutations[id] = {
		Id = id, Name = name, Chance = 0, CoinMult = mult, SellMult = mult,
		Color = color, Color2 = color2, Style = "sprinkler", Tex = tex, Trigger = "Sprinklers",
		Rarity = mult >= 1000 and "Divine" or mult >= 250 and "Mythic" or mult >= 50 and "Legendary"
			or mult >= 15 and "Epic" or mult >= 5 and "Rare" or "Uncommon",
	}
end
local rgb = Color3.fromRGB
bonus("dewdrop", "Dewdrop", 3, rgb(120, 255, 160), rgb(60, 220, 255), "Dust")
bonus("starlit", "Starlit", 5, rgb(140, 240, 255), rgb(80, 150, 255), "Star")
bonus("nebulabloom", "Nebula Bloom", 8, rgb(255, 120, 230), rgb(150, 90, 255), "Nebula")
bonus("cosmicglow", "Cosmic Glow", 15, rgb(255, 215, 90), rgb(255, 140, 40), "Star")
bonus("quantumrain", "Quantum Rain", 25, rgb(90, 255, 140), rgb(80, 255, 230), "Quantum")
bonus("eventhorizon", "Event Horizon", 50, rgb(190, 100, 255), rgb(255, 90, 200), "Void")
bonus("starforged", "Starforged", 100, rgb(255, 250, 230), rgb(255, 190, 70), "Star")
bonus("divinelight", "Divine Light", 250, rgb(255, 235, 150), rgb(255, 255, 255), "Glint")
bonus("heavenly", "Heavenly", 500, rgb(190, 250, 255), rgb(200, 160, 255), "Galaxy")
bonus("singularity", "Singularity", 1000, rgb(120, 255, 120), rgb(40, 200, 255), "Quantum")
bonus("voidtouched", "Void Touched", 2500, rgb(170, 70, 255), rgb(30, 0, 60), "Void")

---------------------------------------------------------------------
-- SPACE WEATHER MUTATIONS
-- Never happen by themselves (Chance = 0). Weather (WeatherConfig) and live events (EventConfig)
-- give them to planets in gardens while they're running. Trigger = what to tell players.
--
-- Look = how the mutation looks on the planet (MutationVFX draws it). Every size is "times the planet's
-- radius", so it fits tiny moons and huge suns alike. All of it is optional:
--   Outline  glowing outline colour (Fill / FillT = an inner glow)
--   Light    { Color, Range, Brightness, Flicker }
--   Emit     particle layers { Tex, Rate, Life, Size, Speed, Accel, C1, C2, Volume, Inward, Shell, Drag, T0, Spin }
--            Tex = one of Stardust's textures (Star, Dust, Galaxy, Nebula, Glint, Quantum, Void, Wisp, Trail,
--            Flow) or SPARKLE / FIRE / SMOKE
--   Rings    flat glowing rings { Color, R, W, Tilt, Spin, T, Mat, Y }
--   Orbit    things circling the planet { N, Color, S, R, Speed, Tilt, Shape, Mat, Trail }
--   Shell    a see-through cosmic skin around the planet { Color, T, Mat, S }
--   Jets     two beams shooting out of the poles { Color, W, L }
--   Pillar   a column of light coming down from the sky { Color, W, H }
--   Pulse    a shockwave every few seconds { Color, Every, S }
--   Arcs     little lightning arcs crackling around it { Color, Every }
---------------------------------------------------------------------
local function weatherMutation(def)
	def.Chance = 0
	def.CoinMult = def.Mult
	def.SellMult = def.Mult
	def.Style = "weather"
	MutationCatalog.Mutations[def.Id] = def
end

local white = Color3.new(1, 1, 1)

-- COSMIC RAIN ---------------------------------------------------------
weatherMutation({
	Id = "starsoaked", Name = "Starsoaked", Rarity = "Common", Mult = 2, Trigger = "Cosmic Rain",
	Color = rgb(120, 200, 255), Color2 = rgb(60, 120, 255),
	Look = {
		Emit = {
			{ Tex = "Trail", Rate = 14, Life = { 0.6, 0.9 }, Size = { 0.18, 0.05 }, Speed = { 0.5, 1 }, Accel = { 0, -14, 0 }, C1 = rgb(200, 240, 255), C2 = rgb(80, 150, 255) },
			{ Tex = "SPARKLE", Rate = 8, Life = { 0.8, 1.4 }, Size = { 0.12, 0 }, Speed = { 0.2, 0.6 }, C1 = white, C2 = rgb(120, 200, 255) },
		},
		Shell = { Color = rgb(110, 190, 255), T = 0.86, Mat = "Glass", S = 1.04 },
	},
})
weatherMutation({
	Id = "cosmic", Name = "Cosmic", Rarity = "Uncommon", Mult = 4, Trigger = "Cosmic Rain",
	Color = rgb(80, 255, 230), Color2 = rgb(170, 90, 255),
	Look = {
		Outline = rgb(90, 255, 230),
		Emit = {
			{ Tex = "Star", Rate = 10, Life = { 1.2, 2 }, Size = { 0.32, 0 }, Speed = { 0.4, 1.2 }, C1 = rgb(90, 255, 230), C2 = rgb(170, 90, 255), Spin = 120 },
			{ Tex = "Dust", Rate = 6, Life = { 2, 3 }, Size = { 0.25, 0.1 }, Speed = { 0.2, 0.5 }, Volume = true, Shell = 1.6, C1 = rgb(170, 90, 255), C2 = rgb(90, 255, 230) },
		},
		Orbit = { { N = 3, Color = rgb(90, 255, 230), S = 0.12, R = 1.6, Speed = 0.35, Tilt = 20, Trail = true } },
		Light = { Color = rgb(90, 255, 230), Range = 3, Brightness = 1.2 },
	},
})

-- SOLAR STORM ---------------------------------------------------------
weatherMutation({
	Id = "ionized", Name = "Ionized", Rarity = "Uncommon", Mult = 4, Trigger = "Solar Storm",
	Color = rgb(255, 250, 140), Color2 = rgb(120, 200, 255),
	Look = {
		Outline = rgb(255, 250, 160),
		Emit = { { Tex = "SPARKLE", Rate = 18, Life = { 0.2, 0.45 }, Size = { 0.22, 0 }, Speed = { 3, 7 }, C1 = white, C2 = rgb(255, 245, 120) } },
		Arcs = { Color = rgb(200, 240, 255), Every = 0.35 },
		Light = { Color = rgb(255, 250, 180), Range = 3, Brightness = 1.4, Flicker = true },
	},
})
weatherMutation({
	Id = "plasma", Name = "Plasma", Rarity = "Epic", Mult = 12, Trigger = "Solar Storm",
	Color = rgb(255, 80, 200), Color2 = rgb(255, 160, 40),
	Look = {
		Outline = rgb(255, 90, 210),
		Emit = {
			{ Tex = "FIRE", Rate = 30, Life = { 0.6, 1 }, Size = { 0.7, 0 }, Speed = { 1.5, 4 }, Accel = { 0, 3, 0 }, C1 = rgb(255, 80, 200), C2 = rgb(255, 170, 40) },
			{ Tex = "Wisp", Rate = 8, Life = { 0.8, 1.3 }, Size = { 0.6, 0.2 }, Speed = { 1, 2 }, C1 = rgb(255, 140, 240), C2 = rgb(255, 80, 120), Spin = 200 },
		},
		Rings = { { Color = rgb(255, 90, 210), R = 1.35, W = 0.06, Tilt = 70, Spin = 160, T = 0.15 } },
		Light = { Color = rgb(255, 90, 210), Range = 4, Brightness = 2, Flicker = true },
	},
})

-- METEOR SHOWER -------------------------------------------------------
weatherMutation({
	Id = "molten", Name = "Molten", Rarity = "Rare", Mult = 6, Trigger = "Meteor Shower",
	Color = rgb(255, 120, 30), Color2 = rgb(255, 40, 20),
	Look = {
		Outline = rgb(255, 110, 30), Fill = rgb(255, 60, 10), FillT = 0.8,
		Emit = {
			{ Tex = "FIRE", Rate = 18, Life = { 0.8, 1.3 }, Size = { 0.5, 0 }, Speed = { 0.5, 2 }, Accel = { 0, 4, 0 }, C1 = rgb(255, 200, 60), C2 = rgb(255, 50, 20) },
			{ Tex = "SMOKE", Rate = 4, Life = { 2, 3 }, Size = { 0.6, 1.4 }, Speed = { 1, 2 }, Accel = { 0, 2, 0 }, C1 = rgb(80, 40, 30), C2 = rgb(30, 20, 20), T0 = 0.6, LE = 0 },
			{ Tex = "SPARKLE", Rate = 10, Life = { 1, 1.6 }, Size = { 0.1, 0 }, Speed = { 2, 5 }, Accel = { 0, 6, 0 }, C1 = rgb(255, 230, 120), C2 = rgb(255, 90, 20) },
		},
		Light = { Color = rgb(255, 110, 30), Range = 4, Brightness = 2, Flicker = true },
	},
})

-- NEBULA FOG ----------------------------------------------------------
weatherMutation({
	Id = "aurora", Name = "Aurora", Rarity = "Rare", Mult = 6, Trigger = "Nebula Fog",
	Color = rgb(90, 255, 170), Color2 = rgb(255, 110, 220),
	Look = {
		Outline = rgb(110, 255, 190),
		Emit = {
			{ Tex = "Wisp", Rate = 10, Life = { 1.5, 2.5 }, Size = { 0.9, 0.3 }, Speed = { 0.3, 0.8 }, Volume = true, Shell = 1.5, C1 = rgb(90, 255, 170), C2 = rgb(255, 110, 220), Spin = 60 },
			{ Tex = "Nebula", Rate = 4, Life = { 2.5, 3.5 }, Size = { 1.2, 2 }, Speed = { 0.2, 0.5 }, C1 = rgb(90, 255, 170), C2 = rgb(150, 90, 255), T0 = 0.55 },
		},
		Rings = { { Color = rgb(90, 255, 170), R = 1.5, W = 0.12, Tilt = 15, Spin = 25, T = 0.45, Y = 0.9 } },
		Light = { Color = rgb(110, 255, 190), Range = 4, Brightness = 1.3 },
	},
})

-- GALACTIC BLIZZARD -----------------------------------------------------
weatherMutation({
	Id = "glacial", Name = "Glacial", Rarity = "Rare", Mult = 7, Trigger = "Galactic Blizzard",
	Color = rgb(190, 245, 255), Color2 = rgb(60, 150, 255),
	Look = {
		Outline = rgb(190, 245, 255), Fill = rgb(140, 220, 255), FillT = 0.75,
		Emit = {
			{ Tex = "Glint", Rate = 12, Life = { 1.2, 2 }, Size = { 0.3, 0 }, Speed = { 0.3, 1 }, C1 = white, C2 = rgb(120, 200, 255), Spin = 90 },
			{ Tex = "SMOKE", Rate = 3, Life = { 2, 3 }, Size = { 1, 1.8 }, Speed = { 0.2, 0.6 }, C1 = rgb(200, 240, 255), C2 = rgb(120, 190, 255), T0 = 0.8 },
		},
		Orbit = { { N = 6, Color = rgb(170, 235, 255), S = 0.22, R = 1.45, Speed = 0.12, Tilt = 10, Shape = "Wedge", Mat = "Glass" } },
		Shell = { Color = rgb(170, 230, 255), T = 0.75, Mat = "Glass", S = 1.06 },
	},
})

-- GRAVITY STORM -------------------------------------------------------
weatherMutation({
	Id = "gravitized", Name = "Gravitized", Rarity = "Epic", Mult = 10, Trigger = "Gravity Storm",
	Color = rgb(170, 120, 255), Color2 = rgb(90, 60, 200),
	Look = {
		Outline = rgb(170, 120, 255),
		Emit = { { Tex = "Dust", Rate = 10, Life = { 1.5, 2.5 }, Size = { 0.2, 0.05 }, Speed = { 0.5, 1.5 }, Accel = { 0, 3, 0 }, C1 = rgb(200, 170, 255), C2 = rgb(110, 70, 230) } },
		Orbit = {
			{ N = 5, Color = rgb(110, 100, 130), S = 0.2, R = 1.7, Speed = 0.25, Tilt = 25, Shape = "Block", Mat = "Slate" },
			{ N = 3, Color = rgb(150, 140, 170), S = 0.14, R = 2.1, Speed = -0.18, Tilt = -35, Shape = "Block", Mat = "Slate" },
		},
		Rings = { { Color = rgb(170, 120, 255), R = 1.9, W = 0.05, Tilt = 25, Spin = 40, T = 0.3 } },
		Pulse = { Color = rgb(170, 120, 255), Every = 2.6, S = 4 },
	},
})

-- ALIEN ECLIPSE -------------------------------------------------------
weatherMutation({
	Id = "radioactive", Name = "Radioactive", Rarity = "Epic", Mult = 14, Trigger = "Alien Eclipse",
	Color = rgb(120, 255, 60), Color2 = rgb(30, 160, 20),
	Look = {
		Outline = rgb(120, 255, 60), Fill = rgb(90, 255, 40), FillT = 0.7,
		Emit = {
			{ Tex = "SPARKLE", Rate = 16, Life = { 1, 1.8 }, Size = { 0.2, 0 }, Speed = { 1, 2.5 }, Accel = { 0, 3, 0 }, C1 = rgb(200, 255, 120), C2 = rgb(60, 220, 30) },
			{ Tex = "SMOKE", Rate = 5, Life = { 1.5, 2.5 }, Size = { 0.5, 1.4 }, Speed = { 1, 2 }, Accel = { 0, 2, 0 }, C1 = rgb(140, 255, 80), C2 = rgb(40, 120, 20), T0 = 0.7 },
		},
		Light = { Color = rgb(120, 255, 60), Range = 5, Brightness = 2.2, Flicker = true },
		Pulse = { Color = rgb(120, 255, 60), Every = 1.8, S = 2.6 },
	},
})
weatherMutation({
	Id = "abducted", Name = "Abducted", Rarity = "Legendary", Mult = 30, Trigger = "Alien Eclipse / Alien Mothership",
	Color = rgb(60, 255, 140), Color2 = rgb(170, 80, 255),
	Look = {
		Outline = rgb(80, 255, 160),
		Emit = {
			{ Tex = "Flow", Rate = 14, Life = { 1.2, 1.8 }, Size = { 0.4, 0.1 }, Speed = { 2, 4 }, Accel = { 0, 6, 0 }, C1 = rgb(80, 255, 160), C2 = rgb(170, 80, 255) },
			{ Tex = "Quantum", Rate = 6, Life = { 1.5, 2.5 }, Size = { 0.3, 0 }, Speed = { 0.3, 1 }, C1 = rgb(120, 255, 190), C2 = rgb(170, 80, 255), Spin = 90 },
		},
		Pillar = { Color = rgb(80, 255, 160), W = 1.6, H = 26 },
		Rings = {
			{ Color = rgb(80, 255, 160), R = 1.3, W = 0.05, Tilt = 0, Spin = 90, T = 0.2, Y = -0.6 },
			{ Color = rgb(170, 80, 255), R = 1.1, W = 0.05, Tilt = 0, Spin = -90, T = 0.2, Y = 0.7 },
		},
		Light = { Color = rgb(80, 255, 160), Range = 5, Brightness = 2 },
	},
})

-- STARDUST SHOWER -----------------------------------------------------
weatherMutation({
	Id = "starborn", Name = "Starborn", Rarity = "Epic", Mult = 18, Trigger = "Stardust Shower",
	Color = rgb(255, 225, 100), Color2 = rgb(255, 140, 230),
	Look = {
		Outline = rgb(255, 225, 110),
		Emit = {
			{ Tex = "Star", Rate = 22, Life = { 1, 1.8 }, Size = { 0.35, 0 }, Speed = { 0.5, 2 }, C1 = rgb(255, 240, 160), C2 = rgb(255, 140, 230), Spin = 180 },
			{ Tex = "Dust", Rate = 10, Life = { 1.5, 2.5 }, Size = { 0.2, 0 }, Speed = { 0.2, 0.6 }, Volume = true, Shell = 1.8, C1 = rgb(255, 225, 100), C2 = white },
		},
		Rings = { { Color = rgb(255, 225, 100), R = 0.7, W = 0.08, Tilt = 0, Spin = 60, T = 0, Y = 1.35 } },
		Light = { Color = rgb(255, 225, 120), Range = 5, Brightness = 2 },
	},
})

-- SUPERNOVA -----------------------------------------------------------
weatherMutation({
	Id = "celestial", Name = "Celestial", Rarity = "Legendary", Mult = 25, Trigger = "Supernova",
	Color = rgb(255, 245, 210), Color2 = rgb(255, 200, 90),
	Look = {
		Outline = rgb(255, 245, 200), Fill = rgb(255, 240, 200), FillT = 0.8,
		Emit = {
			{ Tex = "Glint", Rate = 20, Life = { 1, 1.6 }, Size = { 0.35, 0 }, Speed = { 1, 3 }, C1 = white, C2 = rgb(255, 210, 110), Spin = 120 },
			{ Tex = "Flow", Rate = 8, Life = { 1.2, 2 }, Size = { 0.5, 0.1 }, Speed = { 2, 3 }, Accel = { 0, 5, 0 }, C1 = rgb(255, 250, 220), C2 = rgb(255, 200, 90) },
		},
		Rings = {
			{ Color = rgb(255, 230, 140), R = 0.75, W = 0.1, Tilt = 0, Spin = 45, T = 0, Y = 1.45 }, -- halo
			{ Color = rgb(255, 250, 230), R = 1.6, W = 0.04, Tilt = 80, Spin = 70, T = 0.25 },
		},
		Orbit = { { N = 4, Color = rgb(255, 240, 190), S = 0.12, R = 1.6, Speed = 0.4, Tilt = 80, Trail = true } },
		Light = { Color = rgb(255, 235, 170), Range = 6, Brightness = 3 },
		Pulse = { Color = rgb(255, 240, 200), Every = 3, S = 3.5 },
	},
})

-- BLACK HOLE STORM ----------------------------------------------------
weatherMutation({
	Id = "blackhole", Name = "Blackhole", Rarity = "Legendary", Mult = 40, Trigger = "Black Hole Storm / The Great Black Hole",
	Color = rgb(190, 90, 255), Color2 = rgb(255, 140, 40),
	Look = {
		Outline = rgb(170, 70, 255), Fill = rgb(10, 0, 20), FillT = 0.35,
		Emit = {
			{ Tex = "SPARKLE", Rate = 30, Life = { 1.2, 1.2 }, Size = { 0.18, 0.04 }, Shell = 3, Inward = true, C1 = rgb(255, 170, 70), C2 = rgb(190, 90, 255) },
			{ Tex = "Void", Rate = 3, Life = { 2, 3 }, Size = { 1.6, 2.4 }, Speed = { 0, 0.1 }, C1 = rgb(190, 90, 255), C2 = rgb(60, 10, 120), T0 = 0.4, Spin = 120 },
		},
		Rings = {
			{ Color = rgb(255, 150, 50), R = 1.7, W = 0.22, Tilt = 78, Spin = 120, T = 0.05 }, -- accretion disk
			{ Color = rgb(190, 90, 255), R = 2.15, W = 0.12, Tilt = 78, Spin = 80, T = 0.3 },
		},
		Light = { Color = rgb(170, 70, 255), Range = 6, Brightness = 2.5 },
	},
})
weatherMutation({
	Id = "wormhole", Name = "Wormhole", Rarity = "Mythic", Mult = 75, Trigger = "Black Hole Storm (very rare)",
	Color = rgb(80, 180, 255), Color2 = rgb(220, 90, 255),
	Look = {
		Outline = rgb(110, 190, 255),
		Emit = {
			{ Tex = "Trail", Rate = 26, Life = { 1, 1 }, Size = { 0.3, 0.05 }, Shell = 2.6, Inward = true, C1 = rgb(80, 180, 255), C2 = rgb(220, 90, 255) },
			{ Tex = "Galaxy", Rate = 4, Life = { 2, 3 }, Size = { 1.2, 2 }, Speed = { 0, 0.2 }, C1 = rgb(120, 200, 255), C2 = rgb(220, 90, 255), T0 = 0.3, Spin = 160 },
		},
		Rings = {
			{ Color = rgb(80, 180, 255), R = 1.6, W = 0.14, Tilt = 0, Spin = 200, T = 0, Y = 0 },
			{ Color = rgb(220, 90, 255), R = 1.6, W = 0.14, Tilt = 90, Spin = -200, T = 0 },
			{ Color = rgb(255, 255, 255), R = 2.3, W = 0.04, Tilt = 45, Spin = 120, T = 0.3 },
		},
		Pulse = { Color = rgb(120, 180, 255), Every = 2.2, S = 4 },
		Light = { Color = rgb(120, 180, 255), Range = 7, Brightness = 3 },
	},
})

-- LIVE EVENTS ---------------------------------------------------------
weatherMutation({
	Id = "starfallen", Name = "Starfallen", Rarity = "Legendary", Mult = 50, Trigger = "Meteor Impact event",
	Color = rgb(255, 200, 80), Color2 = rgb(255, 90, 40),
	Look = {
		Outline = rgb(255, 190, 70),
		Emit = {
			{ Tex = "FIRE", Rate = 16, Life = { 0.6, 1 }, Size = { 0.45, 0 }, Speed = { 1, 2 }, Accel = { 0, 3, 0 }, C1 = rgb(255, 220, 120), C2 = rgb(255, 90, 40) },
			{ Tex = "Star", Rate = 14, Life = { 1, 1.6 }, Size = { 0.3, 0 }, Speed = { 1, 3 }, C1 = white, C2 = rgb(255, 200, 80), Spin = 150 },
		},
		Orbit = {
			{ N = 3, Color = rgb(255, 200, 80), S = 0.2, R = 1.8, Speed = 0.45, Tilt = 30, Trail = true },
			{ N = 4, Color = rgb(90, 70, 60), S = 0.18, R = 1.5, Speed = -0.3, Tilt = -20, Shape = "Block", Mat = "Basalt" },
		},
		Light = { Color = rgb(255, 180, 70), Range = 6, Brightness = 2.5, Flicker = true },
	},
})
weatherMutation({
	Id = "coronal", Name = "Coronal", Rarity = "Mythic", Mult = 60, Trigger = "Mega Solar Flare event",
	Color = rgb(255, 230, 90), Color2 = rgb(255, 80, 20),
	Look = {
		Outline = rgb(255, 220, 80), Fill = rgb(255, 160, 40), FillT = 0.7,
		Emit = {
			{ Tex = "FIRE", Rate = 45, Life = { 0.7, 1.2 }, Size = { 0.9, 0 }, Speed = { 2, 5 }, C1 = rgb(255, 240, 140), C2 = rgb(255, 70, 20) },
			{ Tex = "Wisp", Rate = 12, Life = { 1, 1.5 }, Size = { 0.9, 0.2 }, Speed = { 2, 4 }, C1 = rgb(255, 230, 120), C2 = rgb(255, 100, 30), Spin = 220 },
		},
		Rings = {
			{ Color = rgb(255, 200, 60), R = 1.5, W = 0.3, Tilt = 0, Spin = 90, T = 0.15, Mat = "ForceField" }, -- corona
			{ Color = rgb(255, 120, 30), R = 1.9, W = 0.06, Tilt = 60, Spin = -120, T = 0.1 },
		},
		Arcs = { Color = rgb(255, 210, 90), Every = 0.5 },
		Light = { Color = rgb(255, 200, 80), Range = 8, Brightness = 4, Flicker = true },
		Pulse = { Color = rgb(255, 190, 60), Every = 2.4, S = 4 },
	},
})
weatherMutation({
	Id = "xenoform", Name = "Xenoform", Rarity = "Mythic", Mult = 90, Trigger = "Alien Mothership event",
	Color = rgb(150, 255, 60), Color2 = rgb(200, 60, 255),
	Look = {
		Outline = rgb(160, 255, 70), Fill = rgb(120, 40, 200), FillT = 0.65,
		Emit = {
			{ Tex = "Quantum", Rate = 16, Life = { 1.2, 2 }, Size = { 0.35, 0 }, Speed = { 0.5, 1.5 }, Volume = true, Shell = 1.7, C1 = rgb(160, 255, 70), C2 = rgb(200, 60, 255), Spin = 120 },
			{ Tex = "SMOKE", Rate = 4, Life = { 1.5, 2.5 }, Size = { 0.8, 1.6 }, Speed = { 0.5, 1 }, C1 = rgb(150, 255, 80), C2 = rgb(160, 60, 255), T0 = 0.7 },
		},
		Rings = {
			{ Color = rgb(160, 255, 70), R = 1.35, W = 0.05, Tilt = 0, Spin = 0, T = 0.1, Scan = true }, -- scanner ring sweeping up and down
			{ Color = rgb(200, 60, 255), R = 1.8, W = 0.08, Tilt = 20, Spin = 140, T = 0.2 },
		},
		Orbit = { { N = 3, Color = rgb(200, 255, 120), S = 0.16, R = 2, Speed = 0.5, Tilt = 20, Shape = "Ball", Trail = true } },
		Light = { Color = rgb(160, 255, 70), Range = 7, Brightness = 3, Flicker = true },
	},
})
weatherMutation({
	Id = "galaxy", Name = "Galaxy", Rarity = "Mythic", Mult = 150, Trigger = "The Great Black Hole event",
	Color = rgb(120, 140, 255), Color2 = rgb(255, 120, 220),
	Look = {
		Outline = rgb(150, 160, 255), Fill = rgb(40, 20, 90), FillT = 0.55, Rainbow = true,
		Emit = {
			{ Tex = "Galaxy", Rate = 6, Life = { 2, 3 }, Size = { 2.6, 3.4 }, Speed = { 0, 0.1 }, C1 = rgb(150, 170, 255), C2 = rgb(255, 120, 220), T0 = 0.35, Spin = 70 },
			{ Tex = "Star", Rate = 26, Life = { 1.5, 2.5 }, Size = { 0.25, 0 }, Speed = { 0.2, 0.8 }, Volume = true, Shell = 2.4, C1 = white, C2 = rgb(160, 180, 255), Spin = 160 },
		},
		Rings = {
			{ Color = rgb(150, 160, 255), R = 2.2, W = 0.45, Tilt = 75, Spin = 50, T = 0.35, Mat = "ForceField" }, -- spiral arms
			{ Color = rgb(255, 130, 220), R = 2.9, W = 0.1, Tilt = 75, Spin = 35, T = 0.25 },
		},
		Orbit = { { N = 8, Color = rgb(220, 230, 255), S = 0.08, R = 2.6, Speed = 0.2, Tilt = 75 } },
		Shell = { Color = rgb(120, 110, 255), T = 0.7, Mat = "ForceField", S = 1.08 },
		Light = { Color = rgb(150, 150, 255), Range = 8, Brightness = 3 },
		Pulse = { Color = rgb(180, 170, 255), Every = 3, S = 5 },
	},
})
weatherMutation({
	Id = "ton618", Name = "TON-618", Rarity = "Divine", Mult = 618, Trigger = "TON-618 event (ultra rare)",
	Color = rgb(255, 170, 60), Color2 = rgb(140, 40, 255),
	Look = {
		Outline = rgb(255, 255, 255), Fill = rgb(0, 0, 0), FillT = 0.15, Rainbow = true,
		Emit = {
			{ Tex = "SPARKLE", Rate = 60, Life = { 1.1, 1.1 }, Size = { 0.25, 0.05 }, Shell = 4, Inward = true, C1 = rgb(255, 220, 120), C2 = rgb(160, 60, 255) },
			{ Tex = "Void", Rate = 4, Life = { 2, 3 }, Size = { 2.4, 3.2 }, Speed = { 0, 0.1 }, C1 = rgb(255, 150, 60), C2 = rgb(120, 30, 255), T0 = 0.25, Spin = 200 },
			{ Tex = "Galaxy", Rate = 3, Life = { 2.5, 3.5 }, Size = { 3.5, 4.5 }, Speed = { 0, 0.1 }, C1 = rgb(255, 200, 120), C2 = rgb(150, 60, 255), T0 = 0.5, Spin = -60 },
		},
		Rings = {
			{ Color = rgb(255, 245, 220), R = 1.25, W = 0.08, Tilt = 0, Spin = 260, T = 0 }, -- photon ring
			{ Color = rgb(255, 170, 50), R = 2.2, W = 0.5, Tilt = 80, Spin = 150, T = 0, Mat = "ForceField" }, -- accretion disk
			{ Color = rgb(255, 110, 40), R = 2.9, W = 0.22, Tilt = 80, Spin = 110, T = 0.15 },
			{ Color = rgb(170, 70, 255), R = 3.6, W = 0.1, Tilt = 80, Spin = 70, T = 0.25 },
		},
		Jets = { Color = rgb(170, 200, 255), W = 0.5, L = 9 },
		Arcs = { Color = rgb(220, 180, 255), Every = 0.3 },
		Light = { Color = rgb(255, 170, 80), Range = 12, Brightness = 5, Flicker = true },
		Pulse = { Color = rgb(255, 200, 120), Every = 1.6, S = 7 },
	},
})

-- what to tell players about the older mutations
for id, trigger in pairs({
	meteor = "Meteor Shower", frozen = "Galactic Blizzard", nebula = "Nebula Fog", solarflare = "Solar Storm",
	supernova = "Supernova", stardust = "Stardust Shower / Black Holes + Stardust Sprinklers",
}) do
	if MutationCatalog.Mutations[id] then
		MutationCatalog.Mutations[id].Trigger = trigger
	end
end

-- the rarity info of a mutation ({ Tier, Color })
function MutationCatalog.RarityOf(id)
	local m = MutationCatalog.Get(id)
	return MutationCatalog.Rarities[m and m.Rarity or "Common"] or MutationCatalog.Rarities.Common
end

function MutationCatalog.Get(id)
	return type(id) == "string" and MutationCatalog.Mutations[id] or nil
end

-- "meteor,frozen" (or a list of ids) -> a clean list of valid ids, no repeats
function MutationCatalog.Parse(value)
	local ids, seen = {}, {}
	local function add(id)
		if MutationCatalog.Mutations[id] and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	if type(value) == "string" then
		for id in string.gmatch(value, "[^,]+") do
			add(id)
		end
	elseif type(value) == "table" then
		for _, id in ipairs(value) do
			add(id)
		end
	end
	return ids
end

function MutationCatalog.Join(value)
	return table.concat(MutationCatalog.Parse(value), ",")
end

-- "Meteor Shower Frozen"
function MutationCatalog.Names(value)
	local names = {}
	for _, id in ipairs(MutationCatalog.Parse(value)) do
		table.insert(names, MutationCatalog.Mutations[id].Name)
	end
	return table.concat(names, " ")
end

local function total(value, key)
	local sum, product = 1, 1
	for _, id in ipairs(MutationCatalog.Parse(value)) do
		local m = MutationCatalog.Mutations[id][key]
		sum += m - 1
		product *= m
	end
	return MutationCatalog.Stacking == "multiply" and product or sum
end

-- the boost from ALL of a planet's mutations together (value = "meteor,frozen", a list, or one id)
function MutationCatalog.CoinMult(value)
	return total(value, "CoinMult")
end

function MutationCatalog.SellMult(value)
	return total(value, "SellMult")
end

-- roll once when a seed is planted: every mutation rolls on its own, so a planet can get several
function MutationCatalog.RollAll(rng)
	rng = rng or Random.new()
	local ids = {}
	for _, id in ipairs(MutationCatalog.Order) do
		local chance = MutationCatalog.Mutations[id].Chance
		if MutationCatalog.LuckFor then
			chance = MutationCatalog.LuckFor(id, chance) -- server only: LiveOps luck, events and weather
		end
		if rng:NextNumber() < chance then
			table.insert(ids, id)
		end
	end
	return ids
end

-- (old single roll, still here in case something uses it)
function MutationCatalog.Roll(rng)
	local ids = MutationCatalog.RollAll(rng)
	return ids[1]
end

return MutationCatalog
