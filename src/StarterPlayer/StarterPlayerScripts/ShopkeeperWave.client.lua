--[[
	ShopkeeperWave  (LocalScript)  -- StarterPlayer > StarterPlayerScripts

	Shopkeepers come alive:
	  * any NPC with the attribute WaveOnApproach = true turns toward you and WAVES when you walk up
	  * Idle = "work"  (the mechanic): keeps working on the pipe he's holding, with sparks now and then
	  * Idle = "idle"  (the farmer): calm standing idle
	Everything here is just for looks and runs on your own screen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local WAVE_DISTANCE = 16     -- how close you have to be for them to wave
local WAVE_COOLDOWN = 7      -- seconds before the same NPC waves at you again
local TURN_SPEED = 4         -- how fast they turn toward you

-- Roblox's own R15 animations
local ANIM = {
	wave = "rbxassetid://507770239",
	idle = "rbxassetid://507766388",
}

local npcs = {} -- model -> state

-- the mechanic's "working on the pipe" loop: both arms forward on the pipe, the right arm cranking the
-- wrench, head looking down at the work. Built here in code, so nothing has to be uploaded.
local workAnimationId = nil
do
	local function pose(name, cf, children)
		local p = Instance.new("Pose")
		p.Name = name
		p.CFrame = cf or CFrame.new()
		p.EasingStyle = Enum.PoseEasingStyle.Cubic
		p.EasingDirection = Enum.PoseEasingDirection.InOut
		for _, child in ipairs(children or {}) do
			child.Parent = p
		end
		return p
	end
	local function deg(x, y, z)
		return CFrame.Angles(math.rad(x), math.rad(y or 0), math.rad(z or 0))
	end
	local function frame(time, rightUpper, rightLower, rightHand)
		local k = Instance.new("Keyframe")
		k.Time = time
		pose("HumanoidRootPart", nil, {
			pose("LowerTorso", nil, {
				pose("UpperTorso", deg(-8), {
					pose("Head", deg(-18)),
					pose("LeftUpperArm", deg(62, 0, -12), { pose("LeftLowerArm", deg(28), { pose("LeftHand") }) }),
					pose("RightUpperArm", rightUpper, { pose("RightLowerArm", rightLower, { pose("RightHand", rightHand) }) }),
				}),
			}),
		}).Parent = k
		return k
	end
	local sequence = Instance.new("KeyframeSequence")
	sequence.Loop = true
	sequence.Priority = Enum.AnimationPriority.Movement
	frame(0, deg(58, 0, 14), deg(30), deg(0, 0, -30)).Parent = sequence
	frame(0.35, deg(70, 0, 8), deg(10), deg(0, 0, 40)).Parent = sequence
	frame(0.7, deg(58, 0, 14), deg(30), deg(0, 0, -30)).Parent = sequence
	frame(1.05, deg(70, 0, 8), deg(10), deg(0, 0, 40)).Parent = sequence
	frame(1.4, deg(58, 0, 14), deg(30), deg(0, 0, -30)).Parent = sequence
	local ok, id = pcall(function()
		return game:GetService("AnimationClipProvider"):RegisterAnimationClip(sequence)
	end)
	if ok then
		workAnimationId = id
	else
		warn("[ShopkeeperWave] couldn't make the work animation: " .. tostring(id))
	end
end

local function load(animator, id, looped, priority)
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok then
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	return track
end

local starting = {}
local function setup(model)
	if npcs[model] or starting[model] or not model:IsA("Model") then
		return
	end
	starting[model] = true
	-- shopkeepers far away stream in a bit at a time, so wait for their parts to arrive
	local root = model:WaitForChild("HumanoidRootPart", 30)
	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 30)
	starting[model] = nil
	if not humanoid or not root or not model.Parent then
		return
	end
	if model:GetAttribute("Idle") == "work" then
		model:WaitForChild("RightHand", 10)
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local state = {
		Model = model,
		Root = root,
		Home = root.CFrame,
		Wave = load(animator, ANIM.wave, false, Enum.AnimationPriority.Action),
		Idle = load(animator, ANIM.idle, true, Enum.AnimationPriority.Idle),
		LastWave = 0,
		Yaw = 0,
		Kind = model:GetAttribute("Idle") or "idle",
	}
	if state.Idle then
		state.Idle:Play()
	end

	-- the mechanic keeps working on his pipe
	if state.Kind == "work" then
		if workAnimationId then
			state.Work = load(animator, workAnimationId, true, Enum.AnimationPriority.Movement)
			if state.Work then
				state.Work:Play(0.3)
			end
		end
		state.Spark = model:FindFirstChild("Sparks", true)
		state.Turn = 0.35 -- he only glances over, he's busy
	end
	npcs[model] = state
end

local function scan()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("WaveOnApproach") then
			task.spawn(setup, d)
		end
	end
end
scan()
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(function()
			if d:GetAttribute("WaveOnApproach") then
				setup(d)
			end
		end)
	end
end)
-- if a shopkeeper streams out and back in, set it up again
workspace.DescendantRemoving:Connect(function(d)
	if npcs[d] then
		npcs[d] = nil
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local me = character and character:FindFirstChild("HumanoidRootPart")
	local now = os.clock()

	for model, s in pairs(npcs) do
		if not model.Parent then
			npcs[model] = nil
			continue
		end

		local distance = me and (me.Position - s.Home.Position).Magnitude or math.huge
		local close = distance <= WAVE_DISTANCE

		-- turn toward you when you're close, back to their spot when you leave
		local targetYaw = 0
		if close then
			local localDir = s.Home:PointToObjectSpace(me.Position)
			local limit = s.Turn or 1.1
			targetYaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -limit, limit)
		end
		s.Yaw += (targetYaw - s.Yaw) * math.min(1, dt * TURN_SPEED)
		s.Root.CFrame = s.Home * CFrame.Angles(0, s.Yaw, 0)

		-- wave hello
		if close and s.Wave and not s.Wave.IsPlaying and now - s.LastWave > WAVE_COOLDOWN then
			s.LastWave = now
			s.Wave:Play(0.2)
		end
		if not close then
			s.LastWave = math.min(s.LastWave, now - WAVE_COOLDOWN + 1) -- walk away and back: waves again soon
		end

		-- sparks fly from the pipe every time the wrench turns (not while he waves)
		if s.Spark then
			local waving = s.Wave and s.Wave.IsPlaying
			local phase = s.Work and s.Work.IsPlaying and (s.Work.TimePosition % 0.7) or 1
			s.Spark.Enabled = not waving and phase > 0.28 and phase < 0.42
		end
	end
end)
