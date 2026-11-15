--[[
	TutorialSteps  (ModuleScript)  -- ReplicatedStorage

	Everything the tutorial guides teach and say. TutorialClient runs it, TutorialServer saves it.
	Edit lines here; you don't need to touch the scripts.

	CORE   taught in order the first time someone plays
	       (buy a Moon seed -> plant it -> buy + place a Basic Sprinkler -> grow -> harvest -> sell)
	       New players start with 600 coins: Moon (100) + Basic Sprinkler (500).
	SIDE   unlocked while playing, one at a time, when they become useful
	       (enough coins for a pack or sprinkler, walking up to a shop, planting a black hole...)
	Reactions: what the guides say when something happens (mistakes, big harvests, mutations...)

	A step:
	  Id         unique name (saved, so don't rename it once the game is live)
	  Guide      "Cosmo" | "Zib" | "Sprocket"
	  Goal       the short objective shown in the tracker (nil = just talk)
	  Target     where the arrow points: { Kind = "npc", Name = "SeedSeller" } | { Kind = "base" } | { Kind = "myBase" }
	             | { Kind = "myPlant" } | { Kind = "readyPlant" } | { Kind = "blackHole" } | nil
	  Event      what finishes it (see TutorialClient "Signals"): got_Seed, got_Pack, got_Gear, plant, grow_ready,
	             harvest, sell, pack_roll, sprinkler_placed, collect, buy_rarer
	  Intro      lines said when the step starts (keep them short!)
	  Hint       said if the player seems stuck
	  Done       said when it's finished
	  SkipIf     a check (see TutorialClient) that marks it done without teaching it: hasSeed, hasPlant,
	             hasReadyPlant, noPlanet, hasPack, hasSprinkler, placedSprinkler, hasRareSeed
	  Trigger    (side steps) when it unlocks: { Coins = n } and/or { Near = "ShopName" } and/or { Has = "Pack" }
	             and/or { Plant = "BlackHole" }; After = "otherStepId"

	FUTURE FEATURES
	  * Any new shop NPC you put in workspace.SHOPS gets a "discovery" moment automatically.
	  * Tag ANY part or model with the CollectionService tag  TutorialHint  and give it a string attribute
	    HintText (optional: HintGuide = "Zib", HintTitle = "Space Fountain"): the first time a player walks near it,
	    a guide pops up and says it.
	  * New rarities, mutations and item kinds get first-time reactions automatically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PackCatalog = require(ReplicatedStorage:WaitForChild("PackCatalog"))
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local GearCatalog = require(ReplicatedStorage:WaitForChild("GearCatalog"))

local T = {}

local function cheapest(list, filter)
	local best
	for _, item in ipairs(list) do
		if (not filter or filter(item)) and type(item.Cost) == "number" and (not best or item.Cost < best) then
			best = item.Cost
		end
	end
	return best or 1000
end
local PACK_COST = cheapest(PackCatalog.Packs)
-- the cheapest seed that's better than Common (the "upgrade" lesson unlocks when you can afford it)
local UPGRADE_COST = cheapest(PlanetCatalog.Planets, function(p)
	local r = PlanetCatalog.Rarities[p.Rarity]
	return p.Buyable ~= false and r and (r.Order or 1) >= 2
end)

T.Guides = {
	Cosmo = {
		Title = "Garden Astronaut",
		Personality = "hyper, loves puns",
		Idle = { "Space gardening: 10/10, no notes.", "Did you know planets are just big seeds? (They're not.)", "*jetpack noises*" },
		Cheer = { "WOOHOO!", "Nailed it!", "Stellar work!", "You're a natural!", "Out of this world!" },
		Oops = { "Whoops! Try again!", "Close one!", "Happens to the best of us!" },
	},
	Zib = {
		Title = "Galactic Trader",
		Personality = "money-obsessed, dramatic",
		Cheer = { "Ka-CHING!", "Beautiful. Profitable. Beautiful.", "Now THAT'S business!", "I'm so proud. *sniff*" },
		Oops = { "Ouch. My wallet felt that.", "No refunds! ...I'm kidding. Mostly." },
	},
	Sprocket = {
		Title = "Grumpy Engineer",
		Personality = "grumpy but secretly proud",
		Cheer = { "Hmph. Not bad.", "Fine. That was impressive.", "Beep boop. Approved." },
		Oops = { "That's not how machines work.", "*sigh* Again." },
	},
}

T.Core = {
	{
		Id = "welcome", Guide = "Cosmo",
		Intro = { "Whoa, a new gardener! Hi, I'm Cosmo!", "Here we grow PLANETS. Real ones!", "You've got 600 coins. Let's get you set up!" },
	},
	{
		Id = "buy_seed", Guide = "Zib", Goal = "Buy a seed from the Seed Seller",
		Target = { Kind = "npc", Name = "SeedSeller" }, Event = "got_Seed", SkipIf = "hasSeed",
		Intro = { "Zib here. Best deals in the galaxy!", "Grab a Moon seed from the Seed Seller. Just 100 coins!" },
		Hint = { "The Seed Seller is RIGHT there. Follow the glowing path!", "Walk up and press E. Go on, spend!" },
		Done = { "Pleasure doing business! Hehe." },
	},
	{
		Id = "plant", Guide = "Cosmo", Goal = "Hold your seed and click a garden bed",
		Target = { Kind = "base" }, Event = "plant", SkipIf = "hasPlant",
		Intro = { "Now the fun part! Find an empty garden.", "Hold your seed (press its number) and click the dirt!" },
		Hint = { "Pick your seed in the hotbar, then click a bed!", "The glowing dirt! Click the glowing dirt!" },
		Done = { "IT'S ALIVE! Your very own planet!" },
	},
	{
		Id = "sprinkler", Guide = "Sprocket", Goal = "Buy a Basic Sprinkler from the Gear Mechanic",
		Target = { Kind = "npc", Name = "GearMechanic" }, Event = "got_Gear", SkipIf = "hasSprinkler",
		Intro = { "Ugh, fine. I'm Sprocket. I build stuff.", "You've got 500 coins left. Buy a Basic Sprinkler!" },
		Hint = { "The Gear Mechanic. Back of the map. Follow the line.", "Press E on the Gear Mechanic." },
		Done = { "Hmph. Good choice." },
	},
	{
		Id = "place_sprinkler", Guide = "Sprocket", Goal = "Hold the sprinkler and click next to your Moon",
		Target = { Kind = "myPlant" }, Event = "sprinkler_placed", SkipIf = "placedSprinkler",
		Intro = { "Hold it, then click your garden, near your Moon.", "Planets inside the green circle grow FASTER." },
		Hint = { "Press its number to hold it, then click a bed in YOUR garden." },
		Done = { "...Okay that looks really cool." },
	},
	{
		Id = "grow", Guide = "Cosmo", Goal = "Wait for your planet to grow",
		Target = { Kind = "myPlant" }, Event = "grow_ready", AlsoEvent = "harvest", SkipIf = "hasReadyPlant",
		Intro = { "Planets need a little time to grow.", "See the timer? Almost there..." },
		Hint = { "Patience, space farmer!", "Tip: you can plant more while you wait!" },
		Done = { "DING! It's ready!" },
	},
	{
		Id = "harvest", Guide = "Cosmo", Goal = "Walk up to it and HOLD E to harvest",
		Target = { Kind = "readyPlant" }, Event = "harvest",
		Intro = { "Walk up to it and HOLD E!", "Keep holding to harvest a bunch at once!" },
		Hint = { "Get close to it, then hold E!", "On a phone? Hold the button that pops up!" },
		Done = { "Look at that beauty!" },
	},
	{
		Id = "sell", Guide = "Zib", Goal = "Sell your planet to the Planet Buyer",
		Target = { Kind = "npc", Name = "PlanetBuyer" }, Event = "sell", SkipIf = "noPlanet",
		Intro = { "Ooh, shiny! You know what's shinier? COINS.", "Take it to the Planet Buyer and sell it!" },
		Hint = { "Follow the path to the Planet Buyer!", "Talk to them and pick 'sell my inventory'." },
		Done = { "Ka-CHING! Music to my antennae." },
	},
	{
		Id = "finale", Guide = "Cosmo",
		Intro = { "That's the whole loop: buy, plant, grow, harvest, sell!", "Bigger seeds = bigger coins. Go get rich!", "I'll pop in when there's something new. Bye!" },
	},
}

T.Side = {
	{
		Id = "packs", Guide = "Zib", Goal = "Buy a seed pack at the purple stand",
		Trigger = { Coins = PACK_COST },
		Target = { Kind = "npc", Name = "R6" }, Event = "got_Pack", SkipIf = "hasPack",
		Intro = { "Psst. You can afford a seed pack now!", "Packs roll BLACK HOLES. Some are super rare!" },
		Hint = { "The purple stand! With the black hole!" },
		Done = { "Ooh, a mystery! Let's open it!" },
	},
	{
		Id = "open_pack", Guide = "Zib", Goal = "Hold the pack and click to open it",
		Trigger = { Has = "Pack" }, After = "packs", Event = "pack_roll",
		Intro = { "Hold the pack (press its number) and click!" },
		Hint = { "Equip the pack from your hotbar, then click anywhere!" },
		Done = { "Ooooh! Plant that one!" },
	},
	{
		Id = "upgrade", Guide = "Zib", Goal = "Buy a rarer seed (Uncommon or better)",
		Trigger = { Coins = UPGRADE_COST }, After = "finale",
		Target = { Kind = "npc", Name = "SeedSeller" }, Event = "buy_rarer", SkipIf = "hasRareSeed",
		Intro = { "You've got coins! Time to UPGRADE.", "Rarer seeds sell for WAY more. Treat yourself!" },
		Hint = { "Back to the Seed Seller! Pick something fancy!" },
		Done = { "Look at you, big spender!" },
	},
	{
		Id = "collect", Guide = "Cosmo", Goal = "Run through the moons orbiting your black hole",
		Trigger = { Plant = "BlackHole" }, Target = { Kind = "blackHole" }, Event = "collect",
		Intro = { "WHOA, you planted a black hole!", "When it's ready, run into its orbiting moons for coins!" },
		Hint = { "Run right through the glowing moons!" },
		Done = { "Free money from space! Love it." },
	},
	{
		Id = "suns", Guide = "Zib",
		Trigger = { Near = "SunFarmer" },
		Intro = { "The Sun Farmer! Fancy stuff.", "Suns aren't cheap... but they're SUNS." },
	},
	{
		Id = "backpack", Guide = "Cosmo",
		Trigger = { Items = 9 },
		Intro = { "You've got a LOT of stuff!", "Tap the backpack button (top-left) to see everything." },
	},
}

-- mistakes: the first keyword found in an error message picks the line
T.Mistakes = {
	{ Words = { "afford", "enough coins", "not enough", "need" }, Guide = "Zib", Lines = { "Broke? Sell some planets!", "Your wallet says no. Sell something!" }, Action = "facepalm" },
	{ Words = { "not your", "someone else", "claim" }, Guide = "Cosmo", Lines = { "Hey! That's someone else's garden!", "Find an EMPTY base, or your own!" }, Action = "shrug" },
	{ Words = { "closer", "too far", "walk" }, Guide = "Cosmo", Lines = { "Your arms aren't THAT long. Get closer!" }, Action = "facepalm" },
	{ Words = { "room", "space", "too close", "full", "already" }, Guide = "Sprocket", Lines = { "No room there. Try another spot.", "Squished. Pick somewhere else." }, Action = "shrug" },
	{ Words = { "sold out", "stock" }, Guide = "Zib", Lines = { "Sold out! It'll restock soon." }, Action = "shrug" },
}

T.Reactions = {
	BigHarvest = { "WHOA! A {tier} one!", "{tier}?! That's HUGE news!", "Look at the SIZE of that!" },
	FirstRarity = { "Your first {rarity}! Fancy!", "A {rarity}?! I'm screaming!" },
	FirstMutation = { "Your planet got {mutation}! It's worth more now!", "{mutation}! That one's special!" },
	Weather = { "The sky! Something's happening!", "Is that... {weather}?!" },
	Event = { "A {mutation} event! Plant NOW for bonus luck!" },
	NewShop = { "Ooh, {shop}! Wonder what they sell?", "Haven't been to {shop} yet? Go look!" },
	NewItem = { "Ooh, something new: {item}!" },
	WelcomeBack = { "Welcome back, pro! I'll only pop in for new stuff.", "Tap ? (top-right) if you want the tour again." },
	Skip = { "Okay okay! You've got this!", "Tap ? (top-right) if you need me!" },
}

-- every id the server will accept as "done" (plus "poi:", "rarity:", "mut:" ... discoveries)
T.ValidIds = {}
for _, list in ipairs({ T.Core, T.Side }) do
	for _, step in ipairs(list) do
		T.ValidIds[step.Id] = true
	end
end
T.DiscoveryPrefixes = { "poi:", "shop:", "rarity:", "mut:", "kind:", "weather:", "event:", "react:" }

function T.IsValidId(id)
	if type(id) ~= "string" or #id > 60 then
		return false
	end
	if T.ValidIds[id] then
		return true
	end
	for _, prefix in ipairs(T.DiscoveryPrefixes) do
		if string.sub(id, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

return T
