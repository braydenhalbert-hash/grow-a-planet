--[[
	AudioConfig  (ModuleScript)
	Put in: ReplicatedStorage   (name it exactly: AudioConfig)

	ONE place for every sound and music track in the game: the Roblox sound ID, the volume, a little
	random pitch so repeated sounds don't get boring, and limits so nothing overlaps annoyingly.

	An empty Id ("") is simply silent, so the game works fine while you are still uploading audio.
	After you upload a file, paste its ID like  Id = "rbxassetid://123456789".
	The generate_audio.py kit makes every file below, named exactly like the keys here.

	Volumes:  Music tracks and SFX volumes are multiplied by the two group volumes below.
	Pitch = { low, high }  each play picks a random speed between the two.
	Cooldown   = shortest time (seconds) between two plays of the same sound.
	MaxAtOnce  = how many copies of that sound may play at the same time.
	Fallback   = if this sound has no Id, play that sound instead.
]]

local AudioConfig = {}

AudioConfig.MusicGroupVolume = 0.6   -- all music together
AudioConfig.SfxGroupVolume = 0.9     -- all sound effects together

AudioConfig.MusicFade = 2.2          -- seconds to crossfade between music tracks
AudioConfig.ZoneRadius = 14          -- how close to an NPC the area music starts
AudioConfig.ZoneExitRadius = 20     -- how far you must walk away before it goes back (stops flip-flopping)
AudioConfig.RollRevealDelay = 7.0    -- seconds from "pack starts opening" to the reveal sound (match ROLL_SECONDS in SeedShopUI)
AudioConfig.SellBigCount = 5         -- selling this many planets at once plays the big jackpot sound
AudioConfig.SellBigCoins = 250000    -- ...or earning this many coins from one sale

-- Which NPC model name has which area music
AudioConfig.Zones = {
	{ Names = { R6 = true }, Track = "blackhole" },          -- black hole pack stand
	{ Names = { SeedSeller = true }, Track = "shop" },       -- planet seed shop
	{ Names = { SunFarmer = true }, Track = "sunshop" },     -- sun shop (yellow stand)
	{ Names = { GearMechanic = true }, Track = "gearshop" }, -- gear shop (green stand)
	{ Names = { PlanetBuyer = true }, Track = "sell" },      -- planet buyer
}
AudioConfig.DefaultTrack = "garden"

---------------------------------------------------------------------
-- MUSIC (loops). Make them loop-friendly: generate_audio.py crossfades the end into the start.
---------------------------------------------------------------------
AudioConfig.Music = {
	garden    = { Id = "rbxassetid://106023275930403", Volume = 0.55 },  -- your base / out and about
	shop      = { Id = "rbxassetid://108797043528422", Volume = 0.55 },  -- near the seed seller
	blackhole = { Id = "rbxassetid://130734272836362", Volume = 0.6 },   -- near the black hole pack stand
	sell      = { Id = "rbxassetid://71114418010280", Volume = 0.55 },  -- near the planet buyer
	roll      = { Id = "rbxassetid://88877139760019", Volume = 0.65 },  -- while a pack is opening
	sunshop   = { Id = "rbxassetid://75000804482938", Volume = 0.55 },  -- near the Sun Farmer
	gearshop  = { Id = "rbxassetid://103601846432436", Volume = 0.55 }, -- near the Mechanic
}

---------------------------------------------------------------------
-- SOUND EFFECTS
---------------------------------------------------------------------
local P = { 0.96, 1.05 } -- a little pitch variety
AudioConfig.Sfx = {
	-- planting and growing
	plant        = { Id = "rbxassetid://114770024548256", Volume = 0.7, Pitch = P, Cooldown = 0.10, MaxAtOnce = 3 },
	plant_huge   = { Id = "rbxassetid://103964207860925", Volume = 0.85, Cooldown = 0.2, MaxAtOnce = 2, Fallback = "plant" },
	plant_insane = { Id = "rbxassetid://129586892847378", Volume = 0.9, Cooldown = 0.2, MaxAtOnce = 2, Fallback = "plant_huge" },
	plant_crazy  = { Id = "rbxassetid://88502250848454", Volume = 1.0, Cooldown = 0.2, MaxAtOnce = 2, Fallback = "plant_insane" },
	grow_ready   = { Id = "rbxassetid://87485743227529", Volume = 0.6, Pitch = { 0.98, 1.08 }, Cooldown = 0.25, MaxAtOnce = 2 },
	claim        = { Id = "rbxassetid://134312500177835", Volume = 0.8, Cooldown = 1, MaxAtOnce = 1 },

	-- harvesting (the pitch climbs automatically during a harvest streak)
	harvest      = { Id = "rbxassetid://134442144088047", Volume = 0.65, Pitch = { 1, 1 }, Cooldown = 0.04, MaxAtOnce = 5 },
	harvest_big  = { Id = "rbxassetid://114162475322225", Volume = 0.85, Pitch = { 1, 1 }, Cooldown = 0.12, MaxAtOnce = 3, Fallback = "harvest" },

	-- shopping
	buy_seed     = { Id = "rbxassetid://131907875167003", Volume = 0.7, Pitch = P, Cooldown = 0.12, MaxAtOnce = 2 },
	buy_pack     = { Id = "rbxassetid://72201036443408", Volume = 0.85, Cooldown = 0.2, MaxAtOnce = 2, Fallback = "buy_seed" },
	error        = { Id = "rbxassetid://88372898960691", Volume = 0.45, Cooldown = 0.35, MaxAtOnce = 1 },
	restock      = { Id = "rbxassetid://135203525352912", Volume = 0.7, Cooldown = 1, MaxAtOnce = 1 },         -- (SeedShopUI plays this one, see RESTOCK_SOUND_ID)
	restock_rare = { Id = "rbxassetid://97338091047226", Volume = 0.8, Cooldown = 1, MaxAtOnce = 1 },         -- (same)

	-- selling
	sell         = { Id = "rbxassetid://74400520281305", Volume = 0.75, Cooldown = 0.2, MaxAtOnce = 2 },
	sell_big     = { Id = "rbxassetid://128933489373879", Volume = 0.9, Cooldown = 0.5, MaxAtOnce = 1, Fallback = "sell" },

	-- opening packs
	pack_charge  = { Id = "rbxassetid://138330777392114", Volume = 0.75, Cooldown = 1, MaxAtOnce = 1 },
	reveal_common    = { Id = "rbxassetid://127066310576923", Volume = 0.7, Cooldown = 0.5, MaxAtOnce = 1 },
	reveal_uncommon  = { Id = "rbxassetid://115219860852772", Volume = 0.75, Cooldown = 0.5, MaxAtOnce = 1, Fallback = "reveal_common" },
	reveal_rare      = { Id = "rbxassetid://89926918850867", Volume = 0.8, Cooldown = 0.5, MaxAtOnce = 1, Fallback = "reveal_uncommon" },
	reveal_epic      = { Id = "rbxassetid://105659744069540", Volume = 0.9, Cooldown = 0.5, MaxAtOnce = 1, Fallback = "reveal_rare" },
	reveal_legendary = { Id = "rbxassetid://133311886959876", Volume = 1.0, Cooldown = 0.5, MaxAtOnce = 1, Fallback = "reveal_epic" },
	reveal_mythic    = { Id = "rbxassetid://78619372449083", Volume = 1.0, Cooldown = 0.5, MaxAtOnce = 1, Fallback = "reveal_legendary" },
	blackhole_discover = { Id = "rbxassetid://133850834931462", Volume = 0.9, Cooldown = 1, MaxAtOnce = 1 },   -- layered on top for rare black holes

	-- mutations (3D: you hear them from where the planet is)
	mutation_meteor     = { Id = "rbxassetid://102932302593381", Volume = 0.9, Cooldown = 0.3, MaxAtOnce = 3 },
	mutation_frozen     = { Id = "rbxassetid://137419053920063", Volume = 0.9, Cooldown = 0.3, MaxAtOnce = 3 },
	mutation_nebula     = { Id = "rbxassetid://136353270886268", Volume = 0.9, Cooldown = 0.3, MaxAtOnce = 3 },
	mutation_solarflare = { Id = "rbxassetid://100458096119597", Volume = 0.95, Cooldown = 0.3, MaxAtOnce = 3 },
	mutation_supernova  = { Id = "rbxassetid://120340597894345", Volume = 1.0, Cooldown = 0.3, MaxAtOnce = 2 },
	mutation_stardust   = { Id = "", Fallback = "mutation_nebula" }, -- paste its own sound here; until then it uses the Nebula one
	meteor_impact       = { Id = "rbxassetid://104525134789069", Volume = 0.55, Pitch = { 0.85, 1.2 }, Cooldown = 0.12, MaxAtOnce = 4 },
	-- space weather mutations: paste their own sounds here; until then they borrow the closest one
	mutation_starsoaked  = { Id = "", Fallback = "mutation_frozen" },
	mutation_cosmic      = { Id = "", Fallback = "mutation_nebula" },
	mutation_ionized     = { Id = "", Fallback = "mutation_solarflare" },
	mutation_molten      = { Id = "", Fallback = "mutation_meteor" },
	mutation_aurora      = { Id = "", Fallback = "mutation_nebula" },
	mutation_glacial     = { Id = "", Fallback = "mutation_frozen" },
	mutation_gravitized  = { Id = "", Fallback = "mutation_nebula" },
	mutation_plasma      = { Id = "", Fallback = "mutation_solarflare" },
	mutation_radioactive = { Id = "", Fallback = "mutation_nebula" },
	mutation_starborn    = { Id = "", Fallback = "mutation_supernova" },
	mutation_celestial   = { Id = "", Fallback = "mutation_supernova" },
	mutation_abducted    = { Id = "", Fallback = "mutation_nebula" },
	mutation_blackhole   = { Id = "", Fallback = "mutation_supernova" },
	mutation_starfallen  = { Id = "", Fallback = "mutation_meteor" },
	mutation_coronal     = { Id = "", Fallback = "mutation_solarflare" },
	mutation_wormhole    = { Id = "", Fallback = "mutation_supernova" },
	mutation_xenoform    = { Id = "", Fallback = "mutation_nebula" },
	mutation_galaxy      = { Id = "", Fallback = "mutation_supernova" },
	mutation_ton618      = { Id = "", Fallback = "mutation_supernova" },

	-- weather + live events (WeatherHUD / LiveEventClient)
	weather_start   = { Id = "rbxassetid://1840073793", Volume = 0.6, Cooldown = 2, MaxAtOnce = 1 },
	event_alarm     = { Id = "rbxassetid://9119661709", Volume = 0.45, Cooldown = 3, MaxAtOnce = 1 },
	event_tick      = { Id = "rbxassetid://123087446204451", Volume = 0.8, Cooldown = 0.2, MaxAtOnce = 2 },
	event_boom      = { Id = "rbxassetid://1841340980", Volume = 1.0, Cooldown = 0.5, MaxAtOnce = 2 },
	event_reward    = { Id = "", Fallback = "sell_big" },
	thunder         = { Id = "rbxassetid://72113341430811", Volume = 0.7, Pitch = { 0.85, 1.1 }, Cooldown = 0.3, MaxAtOnce = 3 },
	discover_common = { Id = "", Fallback = "reveal_uncommon" },
	discover_rare   = { Id = "", Fallback = "reveal_rare" },
	discover_epic   = { Id = "", Fallback = "reveal_epic" },
	discover_legendary = { Id = "", Fallback = "reveal_legendary" },
	discover_mythic = { Id = "", Fallback = "reveal_mythic" },
}

return AudioConfig
