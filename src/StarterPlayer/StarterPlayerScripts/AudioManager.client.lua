--[[
	AudioManager  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts   (name it exactly: AudioManager)

	The "sound director". It decides WHEN things play, using the sound engine (Audio) and your sound list (AudioConfig):

	MUSIC
	  * garden music when you are out and about / at your base
	  * seed shop, black hole pack stand and planet buyer each have their own music when you walk up to them
	  * tense "roll" music while a pack is opening, then the music ducks for the reveal
	SOUND EFFECTS
	  * plant (bigger sounds for HUGE / INSANE / CRAZY), planet ready chime, claiming a base
	  * harvest, with the pitch climbing during a harvest streak, and a bigger sound for big ones
	  * buy a seed / pack, error buzz, sell (and a jackpot sound for big sales)
	  * pack opening: charge-up, a reveal sound for every rarity (Common to Mythic), plus a black hole
	    discovery sound layered on top for the rare ones
	  * every mutation has its own sound, heard from where the planet is; meteors thud when they land

	Needs: Audio + AudioConfig + PlanetCatalog (ReplicatedStorage), the PlanetRemotes remotes.
	The server scripts send small "AudioCue" messages (plant, ready, buy, sell, claim).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local Config = require(ReplicatedStorage:WaitForChild("AudioConfig"))
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))
local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")

local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }

---------------------------------------------------------------------
-- Area music
---------------------------------------------------------------------
local eventMusic = false       -- true while a pack is opening (the zone music waits)
local zoneModels = {}          -- { Model, Track }
local currentZoneTrack = nil

local function findZoneModels()
	table.clear(zoneModels)
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("Model") and not Players:GetPlayerFromCharacter(instance) then
			for _, zone in ipairs(Config.Zones) do
				if zone.Names[instance.Name] and instance:FindFirstChildWhichIsA("BasePart", true) then
					table.insert(zoneModels, { Model = instance, Track = zone.Track })
				end
			end
		end
	end
end

task.spawn(function()
	findZoneModels()
	while true do
		task.wait(8)
		findZoneModels() -- picks up NPCs that stream in later
	end
end)

task.spawn(function()
	-- start the garden music as soon as the character exists
	while true do
		task.wait(0.5)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and not eventMusic then
			local best, bestDistance = nil, math.huge
			for _, zone in ipairs(zoneModels) do
				if zone.Model.Parent then
					local distance = (zone.Model:GetPivot().Position - root.Position).Magnitude
					-- already in this zone? use the bigger exit radius so it doesn't flip-flop
					local limit = (zone.Track == currentZoneTrack) and Config.ZoneExitRadius or Config.ZoneRadius
					if distance < limit and distance < bestDistance then
						best, bestDistance = zone, distance
					end
				end
			end
			local wanted = best and best.Track or Config.DefaultTrack
			if wanted ~= currentZoneTrack or Audio.CurrentMusic() ~= wanted then
				currentZoneTrack = wanted
				Audio.SetMusic(wanted)
			end
		end
	end
end)

---------------------------------------------------------------------
-- Opening a pack
---------------------------------------------------------------------
local rollToken = 0
local rollRemote = remotes:WaitForChild("PackRoll")
local chargeSound = nil   -- the charge-up that is playing right now
local activeReveal = nil  -- call it to do the reveal now (used when the roll is skipped)

-- cut the charge-up short (quick fade so it doesn't click)
local function stopCharge()
	local sound = chargeSound
	chargeSound = nil
	if sound and sound.Parent then
		local start = sound.Volume
		task.spawn(function()
			for i = 1, 6 do
				if not sound.Parent then
					return
				end
				sound.Volume = start * (1 - i / 6)
				task.wait(0.02)
			end
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end
end

-- SeedShopUI stamps this the moment the seed is shown: when the strip stops by itself AND when you press SKIP
player:GetAttributeChangedSignal("PackRevealAt"):Connect(function()
	if activeReveal then
		activeReveal()
	end
end)

rollRemote.OnClientEvent:Connect(function(_, planetId)
	rollToken += 1
	local token = rollToken
	local planet = PlanetCatalog.Get(planetId)
	local rarity = planet and planet.Rarity or "Common"
	local rank = RARITY_ORDER[rarity] or 1

	eventMusic = true
	Audio.SetMusic("roll", 0.6)
	stopCharge() -- a charge-up left over from the pack before this one
	chargeSound = Audio.Play("pack_charge")

	local revealed = false
	local function reveal()
		if rollToken ~= token or revealed then
			return
		end
		revealed = true
		stopCharge() -- skipped early? the build-up stops here instead of playing its climax later
		Audio.Duck(rank >= 5 and 0.08 or 0.2, rank >= 5 and 6 or 4)
		Audio.Play("reveal_" .. string.lower(rarity))
		if planet and planet.Group == "BlackHole" and rank >= 3 then
			-- discovering a rare black hole: a deep rumble under the fanfare
			task.delay(0.15, function()
				Audio.Play("blackhole_discover", { Volume = rank >= 5 and 1 or 0.7 })
			end)
		end
		task.delay(rank >= 5 and 5.5 or 3.5, function()
			if rollToken == token then
				eventMusic = false
				currentZoneTrack = nil -- the area loop above chooses the right music again
			end
		end)
	end
	activeReveal = reveal
	task.delay(Config.RollRevealDelay, reveal) -- safety net if the shop never reports the reveal
end)

---------------------------------------------------------------------
-- Harvesting (the pitch climbs when you harvest quickly)
---------------------------------------------------------------------
local harvestedRemote = remotes:WaitForChild("PlantHarvested")
local streak, lastHarvest = 0, 0

harvestedRemote.OnClientEvent:Connect(function(planetName, _, tierName)
	local now = os.clock()
	if now - lastHarvest < 1.2 then
		streak = math.min(streak + 1, 14)
	else
		streak = 0
	end
	lastHarvest = now
	local pitch = 1 + streak * 0.04

	local big = type(tierName) == "string" and tierName ~= ""
	Audio.Play(big and "harvest_big" or "harvest", { Pitch = pitch })

	-- harvesting a rare black hole
	for _, planet in ipairs(PlanetCatalog.Planets) do
		if planet.Name == planetName then
			if planet.Group == "BlackHole" and (RARITY_ORDER[planet.Rarity] or 1) >= 4 then
				Audio.Play("blackhole_discover", { Volume = 0.6 })
			end
			break
		end
	end
end)

---------------------------------------------------------------------
-- Mutations: heard from where the planet is
---------------------------------------------------------------------
local mutationRemote = remotes:WaitForChild("MutationGained", 15)
if mutationRemote then
	mutationRemote.OnClientEvent:Connect(function(model, mutationId)
		if typeof(model) ~= "Instance" or type(mutationId) ~= "string" then
			return
		end
		local mine = model:GetAttribute("Owner") == player.UserId
		local ok, pivot = pcall(function()
			return model:GetPivot()
		end)
		if not ok then
			return
		end
		Audio.Play("mutation_" .. mutationId, {
			Position = pivot.Position,
			Volume = mine and 1 or 0.55,
			MinDistance = mine and 60 or 25,
			MaxDistance = 320,
		})
	end)
end

---------------------------------------------------------------------
-- Messages and cues from the server
---------------------------------------------------------------------
local noticeRemote = remotes:WaitForChild("Notice")
noticeRemote.OnClientEvent:Connect(function(_, kind)
	if kind == "error" then
		Audio.Play("error")
	end
end)

local cueRemote = remotes:WaitForChild("AudioCue", 15)
if cueRemote then
	cueRemote.OnClientEvent:Connect(function(name, a, b)
		if name == "plant" then
			Audio.Play(type(a) == "string" and ("plant_" .. a) or "plant")
		elseif name == "grow_ready" then
			Audio.Play("grow_ready")
		elseif name == "claim" then
			Audio.Play("claim")
		elseif name == "buy_seed" then
			Audio.Play("buy_seed")
		elseif name == "buy_pack" then
			Audio.Play("buy_pack")
		elseif name == "sell" then
			local count, coins = tonumber(a) or 1, tonumber(b) or 0
			if count >= Config.SellBigCount or coins >= Config.SellBigCoins then
				Audio.Play("sell_big")
			else
				Audio.Play("sell")
			end
		end
	end)
else
	warn("[AudioManager] no AudioCue remote yet (is the updated GameServer / PlantingServer / SellServer in?)")
end

print("[AudioManager] ready")
