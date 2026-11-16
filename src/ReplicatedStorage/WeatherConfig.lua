--[[
	WeatherConfig  (ModuleScript)  -- ReplicatedStorage

	EVERY space weather in the game. WeatherServer picks one now and then (Weight = how likely),
	runs it for a while (Duration), and while it runs every planet in every garden has a chance
	(Mutations) to get that weather's mutation every RollEvery seconds. WeatherClient draws it.

	To add a weather: copy one of the blocks in WeatherConfig.List, give it a new Id and change things.
	It shows up in the admin panel, the weather HUD and the /weather command by itself.

	Fields of a weather:
	  Id, Name, Icon, Desc       names and the little emoji in the HUD
	  Color, Color2              the HUD / banner colours
	  Weight                     how often it's picked compared to the others (bigger = more common)
	  Duration = { min, max }    seconds it lasts
	  Mutations = { { Id, Chance } }   Chance per planet every RollEvery seconds
	  Boost                      this mutation is also 2x as likely on freshly planted seeds
	  Sky                        one of WeatherConfig.Skies (nil = the game's normal sky)
	  Lighting                   Tint, Bright, Sat, Contrast (colour correction), Fog (Atmosphere colour),
	                             Density, Haze, Glare, Bloom, Ambient
	  Particles                  layers that fall / drift around every player's camera
	                             { Tex, Rate, Colors, Speed, Size, Life, Dir ("down"/"side"/"up"/"float"), Spread, Light, Spin }
	  Props                      big things the client builds: "meteors", "lightning", "flares", "vortex",
	                             "eclipse", "bigstar", "debris", "aurora"
	  Gravity                    (optional) players jump higher: 0.6 = 60% gravity
	  Ambient, AmbientVolume     looping sound while it lasts
	  StartSound                 played once when it starts
]]

local WeatherConfig = {}
local rgb = Color3.fromRGB

-- how weather is scheduled (seconds)
WeatherConfig.FirstDelay = 75   -- after a server starts, the first weather comes this soon
WeatherConfig.GapMin = 150      -- clear skies between two weathers: at least...
WeatherConfig.GapMax = 300      -- ...and at most
WeatherConfig.RollEvery = 15    -- planets roll for the weather's mutations this often
WeatherConfig.WarnBefore = 20   -- the HUD says "Incoming: Meteor Shower" this long before it starts

-- sound ids (Pro Sound Effects / APM, free in the Creator Store)
local SND = {
	space = "rbxassetid://1845647305",
	deepspace = "rbxassetid://124292389178542",
	nebula = "rbxassetid://132902548674552",
	eerie = "rbxassetid://123934979964451",
	rain = "rbxassetid://9112853287",
	wind = "rbxassetid://81404060588532",
	drone = "rbxassetid://9125567032",
	drone2 = "rbxassetid://9125566528",
	rumble = "rbxassetid://1842481849",
	thunder = "rbxassetid://72113341430811",
	boom = "rbxassetid://1841340980",
	whoosh = "rbxassetid://1840073793",
}
WeatherConfig.Sounds = SND

-- skyboxes (six faces each)
local function skybox(bk, dn, ft, lf, rt, up)
	return { SkyboxBk = bk, SkyboxDn = dn, SkyboxFt = ft, SkyboxLf = lf, SkyboxRt = rt, SkyboxUp = up }
end
local function decal(id)
	return "http://www.roblox.com/asset/?id=" .. id
end
WeatherConfig.Skies = {
	asteroids = skybox(decal(198433424), decal(198442292), decal(198433337), decal(198437520), decal(198437454), decal(198433823)),
	purple = skybox(decal(132235945), decal(132235897), decal(132235970), decal(132235882), decal(132235923), decal(132235994)),
	deepnebula = skybox("rbxassetid://769708318", "rbxassetid://769708605", "rbxassetid://769708981", "rbxassetid://769710075", "rbxassetid://769710437", "rbxassetid://769710763"),
	clouds = skybox(decal(166574023), decal(166574122), decal(166574061), decal(166574084), decal(166574092), decal(166574066)),
	voidnebula = skybox("rbxassetid://129876530632297", "rbxassetid://108406529909981", "rbxassetid://104400530594543", "rbxassetid://73372229972523", "rbxassetid://87408857415924", "rbxassetid://137817405681365"),
	milkyway = skybox(decal(168387023), decal(168387089), decal(168387054), decal(168534432), decal(168387190), decal(168387135)),
	galaxy = skybox("rbxassetid://4973732129", "rbxassetid://4973732693", "rbxassetid://4973736001", "rbxassetid://4973737338", "rbxassetid://4973739843", "rbxassetid://4973740262"),
}

WeatherConfig.Clear = {
	Id = "clear", Name = "Clear Skies", Icon = "🌌", Desc = "Normal space",
	Color = rgb(120, 200, 255), Color2 = rgb(90, 120, 255),
	Lighting = {}, Particles = {}, Props = {}, Mutations = {},
}

WeatherConfig.List = {
	{
		Id = "meteorshower", Name = "Meteor Shower", Icon = "☄️", Desc = "Flaming meteors rain down on every garden",
		Color = rgb(255, 150, 60), Color2 = rgb(255, 70, 40),
		Weight = 18, Duration = { 120, 180 }, Boost = "meteor",
		Mutations = { { Id = "meteor", Chance = 0.04 }, { Id = "molten", Chance = 0.01 } },
		Sky = "asteroids",
		Lighting = { Tint = rgb(255, 225, 200), Sat = 0.15, Contrast = 0.05, Fog = rgb(255, 150, 90), Density = 0.38, Haze = 1, Bloom = 1.4 },
		Particles = {
			{ Tex = "Dust", Rate = 30, Colors = { rgb(255, 200, 120), rgb(255, 120, 50) }, Speed = 6, Size = 0.6, Life = 4, Dir = "float" },
		},
		Props = { "meteors" },
		Ambient = SND.rumble, AmbientVolume = 0.35, StartSound = SND.whoosh,
	},
	{
		Id = "solarstorm", Name = "Solar Storm", Icon = "🌞", Desc = "Solar wind and lightning crackle across the sky",
		Color = rgb(255, 210, 60), Color2 = rgb(255, 110, 20),
		Weight = 14, Duration = { 120, 180 }, Boost = "solarflare",
		Mutations = { { Id = "ionized", Chance = 0.04 }, { Id = "solarflare", Chance = 0.015 }, { Id = "plasma", Chance = 0.004 } },
		Sky = "clouds",
		Lighting = { Tint = rgb(255, 220, 170), Bright = 0.04, Sat = 0.25, Contrast = 0.08, Fog = rgb(255, 170, 60), Density = 0.42, Glare = 1.5, Haze = 1.5, Bloom = 1.8 },
		Particles = {
			{ Tex = "Wisp", Rate = 40, Colors = { rgb(255, 170, 40), rgb(255, 80, 30), rgb(255, 235, 160) }, Speed = 40, Size = 2, Life = 2, Dir = "side", Spin = 180 },
			{ Tex = "SPARKLE", Rate = 25, Colors = { rgb(255, 255, 200), rgb(255, 200, 80) }, Speed = 50, Size = 0.5, Life = 1.5, Dir = "side" },
		},
		Props = { "lightning", "flares" },
		Ambient = SND.drone, AmbientVolume = 0.35, StartSound = SND.thunder,
	},
	{
		Id = "cosmicrain", Name = "Cosmic Rain", Icon = "🌧️", Desc = "Glowing star water pours from the sky",
		Color = rgb(90, 200, 255), Color2 = rgb(150, 90, 255),
		Weight = 22, Duration = { 150, 210 },
		Mutations = { { Id = "starsoaked", Chance = 0.06 }, { Id = "cosmic", Chance = 0.02 } },
		Sky = "deepnebula",
		Lighting = { Tint = rgb(200, 220, 255), Bright = -0.03, Sat = 0.1, Fog = rgb(110, 140, 255), Density = 0.45, Haze = 2, Bloom = 1.3 },
		Particles = {
			{ Tex = "Trail", Rate = 220, Colors = { rgb(140, 220, 255), rgb(120, 140, 255), rgb(210, 245, 255) }, Speed = 90, Size = 1.6, Life = 1.2, Dir = "down", Stretch = true },
			{ Tex = "Star", Rate = 20, Colors = { rgb(120, 255, 230), rgb(180, 120, 255) }, Speed = 20, Size = 0.8, Life = 3, Dir = "down", Spin = 200 },
		},
		Props = {},
		Ambient = SND.rain, AmbientVolume = 0.4, StartSound = SND.thunder,
	},
	{
		Id = "nebulafog", Name = "Nebula Fog", Icon = "🌫️", Desc = "A thick pink nebula rolls over the world",
		Color = rgb(255, 120, 230), Color2 = rgb(140, 90, 255),
		Weight = 16, Duration = { 150, 210 }, Boost = "nebula",
		Mutations = { { Id = "nebula", Chance = 0.03 }, { Id = "aurora", Chance = 0.01 } },
		Sky = "purple",
		Lighting = { Tint = rgb(255, 215, 245), Sat = 0.25, Fog = rgb(255, 120, 220), Density = 0.62, Haze = 3, Bloom = 1.5, Ambient = rgb(200, 120, 220) },
		Particles = {
			{ Tex = "Nebula", Rate = 14, Colors = { rgb(255, 110, 230), rgb(150, 80, 255), rgb(255, 200, 250) }, Speed = 5, Size = 18, Life = 7, Dir = "float", Spin = 20, Transparency = 0.6 },
			{ Tex = "Dust", Rate = 30, Colors = { rgb(255, 180, 250), rgb(200, 150, 255) }, Speed = 4, Size = 0.7, Life = 5, Dir = "float" },
		},
		Props = { "aurora" },
		Ambient = SND.space, AmbientVolume = 0.45, StartSound = SND.whoosh,
	},
	{
		Id = "gravitystorm", Name = "Gravity Storm", Icon = "🌀", Desc = "Gravity goes haywire: rocks float and everyone jumps higher",
		Color = rgb(170, 120, 255), Color2 = rgb(80, 60, 200),
		Weight = 10, Duration = { 120, 150 },
		Mutations = { { Id = "gravitized", Chance = 0.008 } },
		Sky = "milkyway", Gravity = 0.45,
		Lighting = { Tint = rgb(220, 210, 255), Sat = 0.1, Contrast = 0.1, Fog = rgb(140, 110, 255), Density = 0.4, Haze = 1.5, Bloom = 1.3 },
		Particles = {
			{ Tex = "Dust", Rate = 40, Colors = { rgb(200, 170, 255), rgb(120, 90, 255) }, Speed = 6, Size = 0.8, Life = 5, Dir = "up" },
		},
		Props = { "debris" },
		Ambient = SND.deepspace, AmbientVolume = 0.5, StartSound = SND.rumble,
	},
	{
		Id = "supernova", Name = "Supernova", Icon = "💥", Desc = "A star explodes in the sky, flashing waves of light",
		Color = rgb(255, 245, 200), Color2 = rgb(255, 180, 70),
		Weight = 6, Duration = { 90, 120 }, Boost = "supernova",
		Mutations = { { Id = "supernova", Chance = 0.012 }, { Id = "celestial", Chance = 0.003 } },
		Sky = "galaxy",
		Lighting = { Tint = rgb(255, 245, 225), Bright = 0.05, Sat = 0.2, Fog = rgb(255, 220, 160), Density = 0.3, Glare = 2, Haze = 1, Bloom = 2.2 },
		Particles = {
			{ Tex = "Glint", Rate = 30, Colors = { rgb(255, 255, 255), rgb(255, 220, 140) }, Speed = 12, Size = 1, Life = 3, Dir = "down", Spin = 120 },
		},
		Props = { "bigstar" },
		Ambient = SND.space, AmbientVolume = 0.45, StartSound = SND.boom,
	},
	{
		Id = "blackholestorm", Name = "Black Hole Storm", Icon = "🕳️", Desc = "A black hole swallows the light. Everything gets pulled in",
		Color = rgb(190, 90, 255), Color2 = rgb(255, 140, 40),
		Weight = 3, Duration = { 90, 120 },
		Mutations = { { Id = "blackhole", Chance = 0.006 }, { Id = "wormhole", Chance = 0.0015 } },
		Sky = "voidnebula",
		Lighting = { Tint = rgb(200, 180, 240), Bright = -0.04, Sat = -0.05, Contrast = 0.2, Fog = rgb(90, 40, 140), Density = 0.45, Haze = 2, Bloom = 1.6, Ambient = rgb(120, 90, 170) },
		Particles = {
			{ Tex = "Void", Rate = 8, Colors = { rgb(150, 70, 255), rgb(60, 20, 120) }, Speed = 4, Size = 6, Life = 5, Dir = "float", Spin = 120 },
			{ Tex = "SPARKLE", Rate = 50, Colors = { rgb(255, 170, 80), rgb(200, 120, 255) }, Speed = 40, Size = 0.5, Life = 2, Dir = "toward" },
		},
		Props = { "vortex" },
		Ambient = SND.drone2, AmbientVolume = 0.55, StartSound = SND.rumble,
	},
	{
		Id = "stardustshower", Name = "Stardust Shower", Icon = "✨", Desc = "Glittering stardust falls on every garden",
		Color = rgb(255, 220, 120), Color2 = rgb(255, 140, 230),
		Weight = 14, Duration = { 120, 180 }, Boost = "stardust",
		Mutations = { { Id = "stardust", Chance = 0.02 }, { Id = "starborn", Chance = 0.004 } },
		Sky = "deepnebula",
		Lighting = { Tint = rgb(255, 245, 225), Bright = 0.02, Sat = 0.2, Fog = rgb(255, 200, 150), Density = 0.3, Haze = 1, Bloom = 1.8 },
		Particles = {
			{ Tex = "Dust", Rate = 90, Colors = { rgb(255, 220, 120), rgb(255, 140, 230), rgb(255, 255, 230) }, Speed = 12, Size = 1.2, Life = 4, Dir = "down" },
			{ Tex = "Star", Rate = 25, Colors = { rgb(255, 240, 160), rgb(255, 255, 255) }, Speed = 10, Size = 1.4, Life = 4, Dir = "down", Spin = 160 },
		},
		Props = {},
		Ambient = SND.nebula, AmbientVolume = 0.45, StartSound = SND.whoosh,
	},
	{
		Id = "alieneclipse", Name = "Alien Eclipse", Icon = "👽", Desc = "Something blocks out the sun. The sky turns toxic green",
		Color = rgb(120, 255, 80), Color2 = rgb(160, 60, 255),
		Weight = 6, Duration = { 120, 150 },
		Mutations = { { Id = "radioactive", Chance = 0.01 }, { Id = "abducted", Chance = 0.0025 } },
		Sky = "purple",
		Lighting = { Tint = rgb(200, 255, 190), Bright = -0.03, Sat = 0.15, Contrast = 0.1, Fog = rgb(110, 200, 80), Density = 0.4, Haze = 2, Bloom = 1.6, Ambient = rgb(120, 190, 110) },
		Particles = {
			{ Tex = "Quantum", Rate = 18, Colors = { rgb(140, 255, 80), rgb(190, 90, 255) }, Speed = 4, Size = 1, Life = 4, Dir = "float", Spin = 90 },
			{ Tex = "Dust", Rate = 30, Colors = { rgb(140, 255, 80), rgb(60, 200, 40) }, Speed = 5, Size = 0.6, Life = 4, Dir = "up" },
		},
		Props = { "eclipse" },
		Ambient = SND.eerie, AmbientVolume = 0.5, StartSound = SND.rumble,
	},
	{
		Id = "galacticblizzard", Name = "Galactic Blizzard", Icon = "❄️", Desc = "Freezing space snow howls across the map",
		Color = rgb(180, 240, 255), Color2 = rgb(80, 160, 255),
		Weight = 12, Duration = { 150, 210 }, Boost = "frozen",
		Mutations = { { Id = "frozen", Chance = 0.05 }, { Id = "glacial", Chance = 0.01 } },
		Sky = "milkyway",
		Lighting = { Tint = rgb(220, 242, 255), Bright = 0.05, Sat = -0.15, Fog = rgb(205, 235, 255), Density = 0.55, Haze = 6, Glare = 1, Bloom = 1.2, Ambient = rgb(180, 215, 255) },
		Particles = {
			{ Tex = "SPARKLE", Rate = 240, Colors = { rgb(255, 255, 255), rgb(190, 230, 255) }, Speed = 45, Size = 1.4, Life = 2.6, Dir = "side" },
			{ Tex = "Glint", Rate = 40, Colors = { rgb(220, 245, 255), rgb(140, 200, 255) }, Speed = 35, Size = 2.2, Life = 2.6, Dir = "side", Spin = 200 },
			{ Tex = "Dust", Rate = 60, Colors = { rgb(255, 255, 255), rgb(200, 235, 255) }, Speed = 10, Size = 1, Life = 4, Dir = "down" },
		},
		Props = {},
		Ambient = SND.wind, AmbientVolume = 0.5, StartSound = SND.whoosh,
	},
}

local byId = { clear = WeatherConfig.Clear }
for _, w in ipairs(WeatherConfig.List) do
	byId[w.Id] = w
end

function WeatherConfig.Get(id)
	return byId[id]
end

-- a random weather, by Weight (never the same as `last` if there's a choice)
function WeatherConfig.Pick(rng, last)
	rng = rng or Random.new()
	local total = 0
	for _, w in ipairs(WeatherConfig.List) do
		if w.Id ~= last then
			total += w.Weight
		end
	end
	local roll = rng:NextNumber() * total
	for _, w in ipairs(WeatherConfig.List) do
		if w.Id ~= last then
			roll -= w.Weight
			if roll <= 0 then
				return w
			end
		end
	end
	return WeatherConfig.List[1]
end

-- percent chance of each weather, for the HUD ("Black Hole Storm  3%")
function WeatherConfig.Odds(id)
	local total = 0
	for _, w in ipairs(WeatherConfig.List) do
		total += w.Weight
	end
	local w = byId[id]
	return w and w.Weight and (w.Weight / total) or 0
end

return WeatherConfig
