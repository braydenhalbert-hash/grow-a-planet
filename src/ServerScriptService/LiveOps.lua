--[[
	LiveOps  (ModuleScript)  -- ServerScriptService

	Server-wide game controls the admin panel drives:
	  * Multipliers  Coins (selling + collecting), Growth (how fast planets grow),
	                 Luck (mutation chances), Size (Huge / Insane / Crazy chances). Each can run for a time.
	  * Events       pick ANY mutation in MutationCatalog: its chance is boosted for everyone for a while.
	  * Weather      space weather the whole server sees (LiveOpsClient draws it). Some weather also
	                 boosts a matching mutation, if that mutation exists.
	  * Announce     a banner message for every player.

	Everything is published as attributes on ReplicatedStorage.LiveOps so clients can show it.
	Hooks into the game: SellServer + Collectibles (Coins), PlantingServer (Size), MutationCatalog.RollAll (Luck,
	events, weather), and the growth loop below (Growth, through GardenAPI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MutationCatalog = require(ReplicatedStorage:WaitForChild("MutationCatalog"))

local LiveOps = {}

LiveOps.Multipliers = {
	{ Id = "Coins", Name = "Coins", Desc = "Coins from selling and collecting", Max = 100 },
	{ Id = "Growth", Name = "Growth Speed", Desc = "How fast planets grow", Max = 100 },
	{ Id = "Luck", Name = "Mutation Luck", Desc = "Chance of every mutation", Max = 50 },
	{ Id = "Size", Name = "Size Luck", Desc = "Chance of Huge / Insane / Crazy planets", Max = 50 },
}

-- Boost = the mutation this weather makes twice as likely (skipped if that mutation doesn't exist)
LiveOps.Weather = {
	{ Id = "clear", Name = "Clear Skies", Desc = "Normal space" },
	{ Id = "starfall", Name = "Starfall", Desc = "Shooting stars rain down", Boost = "meteor" },
	{ Id = "nebulastorm", Name = "Nebula Storm", Desc = "Pink and purple nebula clouds", Boost = "nebula" },
	{ Id = "solarstorm", Name = "Solar Storm", Desc = "Blazing orange sky", Boost = "solarflare" },
	{ Id = "aurora", Name = "Cosmic Aurora", Desc = "Icy green-blue glow", Boost = "frozen" },
	{ Id = "eclipse", Name = "Eclipse", Desc = "The sky goes dark", Boost = "supernova" },
	{ Id = "stardust", Name = "Stardust Rain", Desc = "Glittering stardust everywhere", Boost = "stardust" },
}

local state = Instance.new("Folder")
state.Name = "LiveOps"
state.Parent = ReplicatedStorage

local function now()
	return workspace:GetServerTimeNow()
end

for _, m in ipairs(LiveOps.Multipliers) do
	state:SetAttribute("Mult_" .. m.Id, 1)
	state:SetAttribute("Until_" .. m.Id, 0)
end
state:SetAttribute("Event", "")
state:SetAttribute("EventBoost", 1)
state:SetAttribute("EventUntil", 0)
state:SetAttribute("Weather", "clear")
state:SetAttribute("WeatherUntil", 0)
state:SetAttribute("Announce", "")
state:SetAttribute("AnnounceBy", "")
state:SetAttribute("AnnounceAt", 0)

local function weatherInfo(id)
	for _, w in ipairs(LiveOps.Weather) do
		if w.Id == id then
			return w
		end
	end
	return nil
end
LiveOps.WeatherInfo = weatherInfo

-- current value of a multiplier (1 when it isn't running)
function LiveOps.Get(id)
	local value = state:GetAttribute("Mult_" .. id)
	if type(value) ~= "number" then
		return 1
	end
	local untilTime = state:GetAttribute("Until_" .. id) or 0
	if untilTime > 0 and now() > untilTime then
		return 1
	end
	return value
end

-- seconds = 0 means "until changed"
function LiveOps.SetMultiplier(id, value, seconds)
	for _, m in ipairs(LiveOps.Multipliers) do
		if m.Id == id then
			value = math.clamp(value, 0, m.Max)
			state:SetAttribute("Mult_" .. id, value)
			state:SetAttribute("Until_" .. id, (seconds and seconds > 0) and (now() + seconds) or 0)
			return true, value
		end
	end
	return false
end

function LiveOps.StartEvent(mutationId, boost, seconds)
	if not MutationCatalog.Get(mutationId) then
		return false
	end
	state:SetAttribute("Event", mutationId)
	state:SetAttribute("EventBoost", math.clamp(boost or 5, 1, 100))
	state:SetAttribute("EventUntil", (seconds and seconds > 0) and (now() + seconds) or 0)
	return true
end

function LiveOps.StopEvent()
	state:SetAttribute("Event", "")
	state:SetAttribute("EventBoost", 1)
	state:SetAttribute("EventUntil", 0)
end

function LiveOps.SetWeather(id, seconds)
	if not weatherInfo(id) then
		return false
	end
	state:SetAttribute("Weather", id)
	state:SetAttribute("WeatherUntil", (id ~= "clear" and seconds and seconds > 0) and (now() + seconds) or 0)
	return true
end

function LiveOps.Announce(text, by)
	state:SetAttribute("Announce", string.sub(text, 1, 200))
	state:SetAttribute("AnnounceBy", by or "")
	state:SetAttribute("AnnounceAt", now())
end

function LiveOps.ResetAll()
	for _, m in ipairs(LiveOps.Multipliers) do
		LiveOps.SetMultiplier(m.Id, 1, 0)
	end
	LiveOps.StopEvent()
	LiveOps.SetWeather("clear", 0)
end

-- a snapshot for the admin panel
function LiveOps.Snapshot()
	local mults = {}
	for _, m in ipairs(LiveOps.Multipliers) do
		mults[m.Id] = { Value = LiveOps.Get(m.Id), Until = state:GetAttribute("Until_" .. m.Id) }
	end
	return {
		Multipliers = mults,
		Event = state:GetAttribute("Event"),
		EventBoost = state:GetAttribute("EventBoost"),
		EventUntil = state:GetAttribute("EventUntil"),
		Weather = state:GetAttribute("Weather"),
		WeatherUntil = state:GetAttribute("WeatherUntil"),
		Now = now(),
	}
end

-- the chance of one mutation right now (MutationCatalog.RollAll asks this when a seed is planted)
function LiveOps.MutationChance(id, chance)
	local c = chance
	if state:GetAttribute("Event") == id then
		c = math.max(c, 0.02) * (state:GetAttribute("EventBoost") or 1) -- events even unlock never-by-itself mutations
	end
	local w = weatherInfo(state:GetAttribute("Weather"))
	if w and w.Boost == id then
		c = math.max(c, 0.01) * 2
	end
	c *= LiveOps.Get("Luck")
	return math.min(c, 0.95)
end
MutationCatalog.LuckFor = LiveOps.MutationChance

-- timers running out + faster growing
task.spawn(function()
	local gardenApi = ServerStorage:WaitForChild("GardenAPI", 60)
	while true do
		local dt = task.wait(1)
		local t = now()
		for _, m in ipairs(LiveOps.Multipliers) do
			local untilTime = state:GetAttribute("Until_" .. m.Id) or 0
			if untilTime > 0 and t > untilTime then
				state:SetAttribute("Mult_" .. m.Id, 1)
				state:SetAttribute("Until_" .. m.Id, 0)
			end
		end
		local eventUntil = state:GetAttribute("EventUntil") or 0
		if eventUntil > 0 and t > eventUntil then
			LiveOps.StopEvent()
		end
		local weatherUntil = state:GetAttribute("WeatherUntil") or 0
		if weatherUntil > 0 and t > weatherUntil then
			LiveOps.SetWeather("clear", 0)
		end
		-- Growth: every planet still growing gets (multiplier - 1) extra seconds each second
		local growth = LiveOps.Get("Growth")
		if growth > 1 and gardenApi then
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, list = pcall(function()
					return gardenApi:Invoke("plants", player)
				end)
				if ok and type(list) == "table" then
					for _, p in ipairs(list) do
						if not p.Ready then
							gardenApi:Invoke("boost", p.Model, (growth - 1) * dt)
						end
					end
				end
			end
		end
	end
end)

return LiveOps
