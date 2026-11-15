--[[
	Audio  (ModuleScript)
	Put in: ReplicatedStorage   (name it exactly: Audio)

	The sound engine every other script uses (it only runs on the player's screen):

	  Audio.Play("plant")                              play a sound effect from AudioConfig
	  Audio.Play("harvest", { Pitch = 1.3 })           a bit higher
	  Audio.Play("mutation_nebula", { Position = v })  3D: heard from that spot in the world
	  Audio.SetMusic("garden")                         crossfade to a music track (nil = fade out)
	  Audio.Duck(0.2, 4)                               turn the music down to 20% for 4 seconds, then back up

	It handles volume groups, a little random pitch, cool-downs and "max at once" so nothing piles up.
	Sounds with an empty Id are skipped quietly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("AudioConfig"))

local Audio = {}

---------------------------------------------------------------------
-- Volume groups (so music and effects can be balanced in one place)
---------------------------------------------------------------------
local function getGroup(name, volume, parent)
	local group = (parent or SoundService):FindFirstChild(name)
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Parent = parent or SoundService
	end
	group.Volume = volume
	return group
end

local musicGroup = getGroup("GameMusic", Config.MusicGroupVolume)
local sfxGroup = getGroup("GameSfx", Config.SfxGroupVolume)

local fxFolder = workspace:FindFirstChild("AudioFX")
if not fxFolder then
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "AudioFX"
	fxFolder.Parent = workspace
end

---------------------------------------------------------------------
-- Sound effects
---------------------------------------------------------------------
local lastPlayed = {}  -- name -> os.clock()
local playing = {}     -- name -> how many copies are playing
local rng = Random.new()

local function resolve(name)
	-- follow Fallback links until a sound with an Id turns up
	local seen = {}
	local current = name
	while current and not seen[current] do
		seen[current] = true
		local def = Config.Sfx[current]
		if not def then
			return nil, nil
		end
		if def.Id and def.Id ~= "" then
			return current, def
		end
		current = def.Fallback
	end
	return nil, nil
end

function Audio.Play(name, options)
	options = options or {}
	local key, def = resolve(name)
	if not def then
		return nil
	end

	local now = os.clock()
	if def.Cooldown and lastPlayed[key] and now - lastPlayed[key] < def.Cooldown then
		return nil
	end
	if def.MaxAtOnce and (playing[key] or 0) >= def.MaxAtOnce then
		return nil
	end
	lastPlayed[key] = now

	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = (def.Volume or 0.7) * (options.Volume or 1)
	local pitch = def.Pitch
	local speed = pitch and rng:NextNumber(pitch[1], pitch[2]) or 1
	sound.PlaybackSpeed = speed * (options.Pitch or 1)
	sound.SoundGroup = sfxGroup

	local container = sound
	if options.Position then
		-- 3D sound: an invisible part at that spot carries it
		local part = Instance.new("Part")
		part.Name = "Sfx_" .. key
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Position = options.Position
		part.Parent = fxFolder
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = options.MinDistance or 25
		sound.RollOffMaxDistance = options.MaxDistance or 260
		sound.Parent = part
		container = part
	else
		sound.Parent = SoundService
	end

	playing[key] = (playing[key] or 0) + 1
	local finished = false
	local function done()
		if finished then
			return
		end
		finished = true
		playing[key] = math.max(0, (playing[key] or 1) - 1)
		if container.Parent then
			container:Destroy()
		end
	end
	sound.Ended:Connect(done)
	sound.Destroying:Connect(done)
	task.delay(20, done) -- safety, in case a sound never loads
	sound:Play()
	return sound
end

---------------------------------------------------------------------
-- Music (crossfades, loops, ducking)
---------------------------------------------------------------------
local tracks = {}       -- name -> { Sound, Group }
local currentName = nil
local fadeToken = 0
local duckToken = 0

local function trackFor(name)
	local def = Config.Music[name]
	if not def or def.Id == "" then
		return nil
	end
	local track = tracks[name]
	if not track then
		local group = getGroup("Track_" .. name, 0, musicGroup)
		local sound = Instance.new("Sound")
		sound.Name = "Music_" .. name
		sound.SoundId = def.Id
		sound.Volume = def.Volume or 0.55
		sound.Looped = true -- (the Music on/off switch in the settings mutes every looping sound, so these respect it)
		sound.SoundGroup = group
		sound.Parent = SoundService
		track = { Sound = sound, Group = group }
		tracks[name] = track
	end
	return track
end

function Audio.SetMusic(name, fade)
	if name == currentName then
		return
	end
	currentName = name
	fadeToken += 1
	local token = fadeToken
	fade = fade or Config.MusicFade

	-- fade out whatever is playing
	for otherName, track in pairs(tracks) do
		if otherName ~= name and track.Sound.IsPlaying then
			local tween = TweenService:Create(track.Group, TweenInfo.new(fade, Enum.EasingStyle.Sine), { Volume = 0 })
			tween:Play()
			tween.Completed:Connect(function()
				if currentName ~= otherName then
					track.Sound:Stop()
				end
			end)
		end
	end

	-- fade in the new one
	local track = name and trackFor(name)
	if track then
		if not track.Sound.IsPlaying then
			track.Sound:Play()
		end
		TweenService:Create(track.Group, TweenInfo.new(fade, Enum.EasingStyle.Sine), { Volume = 1 }):Play()
	end
	return token
end

function Audio.CurrentMusic()
	return currentName
end

-- turn the music down to `level` (0-1 of normal) for `seconds`, then back up
function Audio.Duck(level, seconds, fadeBack)
	duckToken += 1
	local token = duckToken
	local normal = Config.MusicGroupVolume
	TweenService:Create(musicGroup, TweenInfo.new(0.25), { Volume = normal * level }):Play()
	task.delay(seconds or 3, function()
		if duckToken == token then
			TweenService:Create(musicGroup, TweenInfo.new(fadeBack or 1.2), { Volume = normal }):Play()
		end
	end)
end

return Audio
