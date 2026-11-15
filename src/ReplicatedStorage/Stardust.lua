--[[
	Stardust  (ModuleScript)  -- ReplicatedStorage

	The game's own stardust: hand-made particle textures (uploaded as Decals) and a "style" for every
	sprinkler: its neon colours, which stardust shapes it sprays, what floats around the model and what
	glows on the ground inside its watering radius.
	Used by SprinklerModel (the models' own particles), SprinklerClient (spray, ground effects,
	stardust around planets) and nothing else.

	Ground modes (what happens on the ground inside the circle):
	  rise     glowing motes drift up
	  spin     little galaxies lie on the ground and slowly turn
	  drift    soft nebula clouds float across
	  flare    stars twinkle on and off
	  flicker  quantum glyphs blink in and out
	  void     dark vortexes turn, motes sink into them
]]

local Stardust = {}
local rgb = Color3.fromRGB

-- our own textures (made for this game, uploaded by boypoooop). Source PNGs: Obsidian\GrowAPlanet_Stardust
local FALLBACK = "rbxasset://textures/particles/sparkles_main.dds"
Stardust.Tex = {
	Star = "rbxassetid://82992618098435",    -- 4-point twinkle star
	Dust = "rbxassetid://104418445989695",   -- glowing cosmic dust mote with tiny sparkles
	Galaxy = "rbxassetid://111710289514898", -- mini spiral galaxy
	Nebula = "rbxassetid://136251505454051", -- soft nebula cloud
	Glint = "rbxassetid://73378168977146",   -- crystal glint
	Quantum = "rbxassetid://91861615151121", -- hexagon quantum glyph
	Void = "rbxassetid://82483345601163",    -- dark vortex with glowing rim
	Wisp = "rbxassetid://120085574363501",   -- curling energy wisp
	Trail = "rbxassetid://78448793228988",   -- sparkling streak (planet trails)
	Flow = "rbxassetid://103448788920640",   -- pulses of energy (flows up the pillars)
	Ground = "rbxassetid://83588891245594",  -- big soft ring glow (on the ground)
}

local function style(t)
	t.Spray = t.Spray or "Star"
	t.Aura = t.Aura or "Dust"
	t.Ground = t.Ground or "Dust"
	t.Mode = t.Mode or "rise"
	t.Planet = t.Planet or "Dust"
	return t
end

-- palettes: { main, second, highlight }
local P = {
	green = { rgb(70, 255, 110), rgb(60, 255, 220), rgb(220, 255, 220) },
	cyan = { rgb(80, 230, 255), rgb(60, 140, 255), rgb(225, 250, 255) },
	blue = { rgb(60, 140, 255), rgb(255, 110, 230), rgb(210, 230, 255) },
	gold = { rgb(255, 200, 60), rgb(255, 140, 40), rgb(255, 245, 200) },
	pink = { rgb(255, 90, 220), rgb(170, 80, 255), rgb(255, 225, 250) },
	purple = { rgb(170, 80, 255), rgb(60, 120, 255), rgb(240, 210, 255) },
	violet = { rgb(140, 70, 255), rgb(255, 80, 210), rgb(220, 200, 255) },
	fire = { rgb(255, 140, 40), rgb(255, 60, 30), rgb(255, 230, 150) },
	magenta = { rgb(255, 60, 200), rgb(150, 60, 255), rgb(255, 210, 245) },
	white = { rgb(255, 250, 240), rgb(255, 210, 90), rgb(255, 120, 210) },
	heaven = { rgb(200, 250, 255), rgb(255, 225, 130), rgb(190, 160, 255) },
	quantum = { rgb(80, 255, 110), rgb(80, 255, 230), rgb(190, 255, 80) },
	void = { rgb(150, 70, 255), rgb(220, 80, 255), rgb(40, 10, 70) },
}
Stardust.Palettes = P

Stardust.Styles = {
	sprinkler_basic = style({ Palette = P.green, Spray = "Dust" }),
	sprinkler_stardust = style({ Palette = P.green }),
	sprinkler_nebula = style({ Palette = P.blue, Aura = "Nebula", Ground = "Nebula", Mode = "drift" }),
	sprinkler_cosmic = style({ Palette = P.gold, Ground = "Star", Mode = "flare" }),
	sprinkler_nebulacloud = style({ Palette = P.pink, Aura = "Nebula", Ground = "Nebula", Mode = "drift" }),
	sprinkler_celestialtree = style({ Palette = P.cyan, Aura = "Glint", Ground = "Glint", Mode = "flare" }),
	sprinkler_quasar = style({ Palette = P.cyan, Aura = "Star", Ground = "Star", Mode = "flare" }),
	sprinkler_darkmatter = style({ Palette = P.purple, Aura = "Void", Ground = "Void", Mode = "void" }),
	sprinkler_voidspiral = style({ Palette = P.violet, Aura = "Wisp", Ground = "Void", Mode = "void" }),
	sprinkler_blackhole = style({ Palette = P.fire, Aura = "Wisp", Ground = "Void", Mode = "void" }),
	sprinkler_timedilation = style({ Palette = P.gold, Aura = "Glint", Ground = "Star", Mode = "flare" }),
	sprinkler_planetaryring = style({ Palette = P.fire, Ground = "Galaxy", Mode = "spin" }),
	sprinkler_orbitalstation = style({ Palette = P.blue, Aura = "Glint", Ground = "Quantum", Mode = "flicker" }),
	sprinkler_supernova = style({ Palette = P.pink, Aura = "Star", Ground = "Star", Mode = "flare" }),
	sprinkler_galaxycore = style({ Palette = P.purple, Spray = "Galaxy", Ground = "Galaxy", Mode = "spin" }),
	sprinkler_cosmicsupreme = style({ Palette = P.purple, Spray = "Galaxy", Aura = "Wisp", Ground = "Galaxy", Mode = "spin" }),
	sprinkler_divine = style({ Palette = P.gold, Aura = "Glint", Ground = "Star", Mode = "flare" }),
	sprinkler_celestial = style({ Palette = P.cyan, Spray = "Galaxy", Aura = "Wisp", Ground = "Galaxy", Mode = "spin" }),
	-- the Stardust line
	sprinkler_galaxystardust = style({ Palette = P.purple, Spray = "Galaxy", Aura = "Star", Ground = "Galaxy", Mode = "spin", Planet = "Galaxy" }),
	sprinkler_solarstardust = style({ Palette = P.gold, Spray = "Star", Aura = "Wisp", Ground = "Star", Mode = "flare", Planet = "Star" }),
	sprinkler_blackholestardust = style({ Palette = P.magenta, Spray = "Dust", Aura = "Wisp", Ground = "Void", Mode = "void", Planet = "Wisp" }),
	sprinkler_nebulastardust = style({ Palette = P.cyan, Spray = "Glint", Aura = "Nebula", Ground = "Nebula", Mode = "drift", Planet = "Nebula" }),
	sprinkler_supernovastardust = style({ Palette = P.white, Spray = "Star", Aura = "Glint", Ground = "Star", Mode = "flare", Planet = "Star" }),
	sprinkler_celestialstardust = style({ Palette = P.heaven, Spray = "Glint", Aura = "Star", Ground = "Galaxy", Mode = "spin", Planet = "Glint" }),
	sprinkler_quantumstardust = style({ Palette = P.quantum, Spray = "Quantum", Aura = "Glint", Ground = "Quantum", Mode = "flicker", Planet = "Quantum" }),
	sprinkler_voidstardust = style({ Palette = P.void, Spray = "Wisp", Aura = "Void", Ground = "Void", Mode = "void", Planet = "Void" }),
}

function Stardust.Get(gearId)
	return Stardust.Styles[gearId or ""] or Stardust.Styles.sprinkler_stardust
end

function Stardust.Texture(name)
	local t = Stardust.Tex[name]
	return (t and t ~= "") and t or FALLBACK
end

function Stardust.Colors(palette)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette[3]),
		ColorSequenceKeypoint.new(0.45, palette[1]),
		ColorSequenceKeypoint.new(1, palette[2]),
	})
end

-- fade in, hold, fade out
Stardust.FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.05),
	NumberSequenceKeypoint.new(0.75, 0.15), NumberSequenceKeypoint.new(1, 1),
})

-- a glowing particle emitter using one of the stardust textures
function Stardust.Emitter(texName, palette, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Stardust"
	e.Texture = Stardust.Texture(texName)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = Stardust.Colors(palette)
	e.Transparency = Stardust.FADE
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	for k, v in pairs(props or {}) do
		e[k] = v
	end
	return e
end

return Stardust
