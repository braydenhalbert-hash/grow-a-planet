--[[
	EventConfig  (ModuleScript)  -- ReplicatedStorage

	The BIG server-wide live events. Every so often WeatherServer announces one, counts down
	(everyone sees the countdown), then runs it. LiveEventClient builds the giant thing in the sky.

	While an event runs:
	  Boosts      server-wide multipliers on top of everything else (Luck, Growth, Coins, Size)
	  Mutations   every planet in every garden rolls for these every RollEvery seconds
	  Reward      when it ends, everyone in the server gets coins: CoinPercent of their coins
	              (at least CoinMin, at most CoinMax)
	Extra per event:
	  Gravity     players jump higher (0.5 = half gravity)
	  Shards      (meteor crash) glowing pieces around the crater: each player can grab each one once.
	              Each gives ShardCoinPercent coins and a ShardMutationChance to put ShardMutation
	              on one of their planets
	  Abductions  (mothership) the ship beams random planets: each beam has BeamChance to give BeamMutation

	To add an event: copy a block, give it a new Id. Its look in the sky is chosen by Visual
	(blackhole / ton618 / meteor / solarflare / mothership); a new Visual needs code in LiveEventClient.
]]

local EventConfig = {}
local rgb = Color3.fromRGB

EventConfig.FirstDelay = 480   -- first event this many seconds after the server starts
EventConfig.GapMin = 900       -- then one every 15...
EventConfig.GapMax = 1500      -- ...to 25 minutes
EventConfig.Countdown = 60     -- seconds of "INCOMING!" countdown before it starts
EventConfig.RollEvery = 10

-- where the meteor crashes (x, z). The height is found automatically.
EventConfig.CrashSite = Vector3.new(39, 0, -46)
-- where the giant things hang in the sky, relative to the middle of the map
EventConfig.SkyCenter = Vector3.new(39, 0, -46)

EventConfig.List = {
	{
		Id = "blackholerift", Name = "The Great Black Hole", Icon = "🕳️", Visual = "blackhole",
		Desc = "A giant black hole tears open above the gardens. Gravity weakens and luck skyrockets!",
		Color = rgb(180, 90, 255), Color2 = rgb(255, 150, 50),
		Weight = 30, Duration = 150,
		Boosts = { Luck = 2 }, Gravity = 0.5,
		Mutations = { { Id = "blackhole", Chance = 0.008 }, { Id = "galaxy", Chance = 0.002 } },
		Reward = { CoinPercent = 0.03, CoinMin = 5000, CoinMax = 5e15 },
		Sound = "rbxassetid://9125566528",
	},
	{
		Id = "ton618", Name = "TON-618", Icon = "🌌", Visual = "ton618",
		Desc = "The most massive black hole in the universe appears. The whole sky changes. 3x Luck, 2x Growth!",
		Color = rgb(255, 170, 60), Color2 = rgb(140, 40, 255),
		Weight = 8, Duration = 180,
		Boosts = { Luck = 3, Growth = 2 }, Gravity = 0.6,
		Mutations = { { Id = "ton618", Chance = 0.001 }, { Id = "blackhole", Chance = 0.01 }, { Id = "galaxy", Chance = 0.003 } },
		Reward = { CoinPercent = 0.08, CoinMin = 25000, CoinMax = 2e16 },
		Sound = "rbxassetid://124292389178542",
	},
	{
		Id = "meteorcrash", Name = "Meteor Impact", Icon = "☄️", Visual = "meteor",
		Desc = "A massive meteor is about to crash into the middle of the map! Grab the glowing shards!",
		Color = rgb(255, 160, 50), Color2 = rgb(255, 60, 30),
		Weight = 30, Duration = 120,
		Boosts = { Coins = 1.5 },
		Mutations = { { Id = "meteor", Chance = 0.03 }, { Id = "molten", Chance = 0.01 } },
		Shards = 8, ShardCoinPercent = 0.02, ShardCoinMin = 1500, ShardMutation = "starfallen", ShardMutationChance = 0.2,
		Reward = { CoinPercent = 0.02, CoinMin = 3000, CoinMax = 5e15 },
		Sound = "rbxassetid://1842481849",
	},
	{
		Id = "solarflare", Name = "Mega Solar Flare", Icon = "🌞", Visual = "solarflare",
		Desc = "The sun erupts! A wave of solar fire sweeps over the gardens. 3x Growth Speed!",
		Color = rgb(255, 220, 70), Color2 = rgb(255, 90, 20),
		Weight = 22, Duration = 120,
		Boosts = { Growth = 3 },
		Mutations = { { Id = "solarflare", Chance = 0.02 }, { Id = "plasma", Chance = 0.006 }, { Id = "coronal", Chance = 0.002 } },
		Reward = { CoinPercent = 0.03, CoinMin = 4000, CoinMax = 5e15 },
		Sound = "rbxassetid://9125567032",
	},
	{
		Id = "mothership", Name = "Alien Mothership", Icon = "🛸", Visual = "mothership",
		Desc = "A gigantic alien ship arrives and starts beaming up planets... and leaving them changed. 2x Coins!",
		Color = rgb(120, 255, 90), Color2 = rgb(170, 70, 255),
		Weight = 18, Duration = 150,
		Boosts = { Coins = 2 },
		Mutations = { { Id = "radioactive", Chance = 0.012 }, { Id = "abducted", Chance = 0.004 } },
		Abductions = true, BeamEvery = 4, BeamChance = 0.3, BeamMutation = "xenoform",
		Reward = { CoinPercent = 0.04, CoinMin = 5000, CoinMax = 5e15 },
		Sound = "rbxassetid://9119413402",
	},
}

local byId = {}
for _, e in ipairs(EventConfig.List) do
	byId[e.Id] = e
end

function EventConfig.Get(id)
	return byId[id]
end

function EventConfig.Pick(rng, last)
	rng = rng or Random.new()
	local total = 0
	for _, e in ipairs(EventConfig.List) do
		if e.Id ~= last then
			total += e.Weight
		end
	end
	local roll = rng:NextNumber() * total
	for _, e in ipairs(EventConfig.List) do
		if e.Id ~= last then
			roll -= e.Weight
			if roll <= 0 then
				return e
			end
		end
	end
	return EventConfig.List[1]
end

return EventConfig
