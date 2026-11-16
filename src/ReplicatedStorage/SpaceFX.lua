--[[
	SpaceFX  (ModuleScript)  -- ReplicatedStorage

	Small toolbox of client-side effects shared by WeatherClient and LiveEventClient:
	  SpaceFX.Part(props)                 an anchored, non-colliding effect part (props are set on it)
	  SpaceFX.Ring(color, color2, width)  a crisp glowing ring on an invisible plate (size the plate to size the ring)
	  SpaceFX.Emitter(parent, props)      a ParticleEmitter (Tex = a Stardust texture name or SPARKLE / FIRE / SMOKE)
	  SpaceFX.Beam(a0, a1, props)         a glowing Beam between two attachments
	  SpaceFX.Bolt(from, to, color, width)  a jagged lightning bolt that flickers out
	  SpaceFX.Shock(pos, color, from, to, seconds, transparency, material)  an expanding ball
	  SpaceFX.Disc(pos, color, to, seconds)  an expanding flat ring on the ground
	  SpaceFX.GroundAt(x, z)              the ground height at x, z (ignores players and effects)
	  SpaceFX.Shake(strength, seconds)    shakes the camera
	  SpaceFX.Flash(color, strength, seconds)  flashes the whole screen
	  SpaceFX.Sound(id, volume, props)    a sound (3D if props.Position is given), cleaned up when done
	Client only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local Stardust = require(ReplicatedStorage:WaitForChild("Stardust"))

local SpaceFX = {}

local folder = workspace:FindFirstChild("SpaceFX")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "SpaceFX"
	folder.Parent = workspace
end
SpaceFX.Folder = folder

SpaceFX.Tex = {
	SPARKLE = "rbxasset://textures/particles/sparkles_main.dds",
	FIRE = "rbxasset://textures/particles/fire_main.dds",
	SMOKE = "rbxasset://textures/particles/smoke_main.dds",
}
function SpaceFX.Texture(name)
	return SpaceFX.Tex[name] or Stardust.Texture(name or "Star")
end

function SpaceFX.Part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local parent = folder
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- a glowing ring: returns the plate (set its Size X/Z to the ring's diameter) and a little control table
function SpaceFX.Ring(color, color2, width, glow, parent)
	local plate = SpaceFX.Part({ Name = "Ring", Size = Vector3.new(10, 0.05, 10), Transparency = 1, Material = Enum.Material.SmoothPlastic, Parent = parent })
	local ctl = { Plate = plate, Strokes = {}, Gradients = {} }
	for _, face in ipairs({ Enum.NormalId.Top, Enum.NormalId.Bottom }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(512, 512)
		gui.LightInfluence = 0
		gui.Brightness = glow or 3
		gui.Parent = plate
		local circle = Instance.new("Frame")
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = UDim2.fromScale(0.5, 0.5)
		circle.Size = UDim2.fromScale(1, 1)
		circle.BackgroundTransparency = 1
		circle.Parent = gui
		Instance.new("UICorner", circle).CornerRadius = UDim.new(0.5, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = math.clamp(256 * (width or 0.06), 2, 240)
		stroke.Parent = circle
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(0.5, color2 or color),
			ColorSequenceKeypoint.new(1, color),
		})
		gradient.Parent = stroke
		table.insert(ctl.Strokes, stroke)
		table.insert(ctl.Gradients, gradient)
	end
	function ctl.SetTransparency(t)
		for _, s in ipairs(ctl.Strokes) do
			s.Transparency = t
		end
	end
	function ctl.Spin(degrees)
		for _, g in ipairs(ctl.Gradients) do
			g.Rotation = degrees % 360
		end
	end
	return plate, ctl
end

function SpaceFX.Emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SpaceFX.Texture(props.Tex)
	local colors = props.Colors
	if colors then
		e.Color = #colors >= 3 and Stardust.Colors(colors) or ColorSequence.new(colors[1], colors[2] or colors[1])
	else
		e.Color = ColorSequence.new(props.Color or Color3.new(1, 1, 1), props.Color2 or props.Color or Color3.new(1, 1, 1))
	end
	e.LightEmission = props.LightEmission or 1
	e.LightInfluence = 0
	local size = props.Size or 1
	e.Size = typeof(size) == "NumberSequence" and size or NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * (props.SizeStart or 1)), NumberSequenceKeypoint.new(1, size * (props.SizeEnd or 0.4)) })
	local t = props.Transparency or 0
	e.Transparency = typeof(t) == "NumberSequence" and t or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, t), NumberSequenceKeypoint.new(0.8, t), NumberSequenceKeypoint.new(1, 1) })
	local life = props.Life or 2
	e.Lifetime = typeof(life) == "NumberRange" and life or NumberRange.new(life * 0.7, life)
	local speed = props.Speed or 5
	e.Speed = typeof(speed) == "NumberRange" and speed or NumberRange.new(speed * 0.7, speed)
	e.SpreadAngle = props.Spread or Vector2.new(10, 10)
	e.Rate = props.Rate or 10
	e.Rotation = NumberRange.new(0, 360)
	local spin = math.abs(props.Spin or 30)
	e.RotSpeed = NumberRange.new(-spin, spin)
	e.Acceleration = props.Acceleration or Vector3.zero
	e.Drag = props.Drag or 0
	e.EmissionDirection = props.Direction or Enum.NormalId.Top
	if props.Stretch then
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Squash = NumberSequence.new(props.Stretch == true and 1.6 or props.Stretch)
	end
	if props.Shape then
		e.Shape = props.Shape
		e.ShapeStyle = props.ShapeStyle or Enum.ParticleEmitterShapeStyle.Volume
	end
	if props.ZOffset then
		e.ZOffset = props.ZOffset
	end
	e.Enabled = props.Enabled ~= false
	e.Parent = parent
	return e
end

function SpaceFX.Beam(a0, a1, props)
	props = props or {}
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color = props.ColorSequence or ColorSequence.new(props.Color or Color3.new(1, 1, 1), props.Color2 or props.Color or Color3.new(1, 1, 1))
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Brightness = props.Brightness or 2
	b.Texture = SpaceFX.Texture(props.Tex or "Flow")
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureLength = props.TextureLength or 1
	b.TextureSpeed = props.TextureSpeed or 0
	b.Width0 = props.Width0 or 4
	b.Width1 = props.Width1 or props.Width0 or 4
	b.CurveSize0 = props.Curve0 or 0
	b.CurveSize1 = props.Curve1 or 0
	b.FaceCamera = props.FaceCamera ~= false
	b.Segments = props.Segments or 10
	b.Transparency = props.Transparency or NumberSequence.new(0)
	b.Parent = props.Parent or a0.Parent
	return b
end

local rng = Random.new()

function SpaceFX.Bolt(from, to, color, width, life)
	width = width or 0.6
	life = life or 0.18
	local parts = {}
	local function segment(a, b, w)
		local len = (b - a).Magnitude
		local p = SpaceFX.Part({ Size = Vector3.new(w, w, len), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color })
		table.insert(parts, p)
	end
	local function zig(a, b, steps, jitter, w, branch)
		local last = a
		for i = 1, steps do
			local p = a:Lerp(b, i / steps)
			if i < steps then
				p += Vector3.new(rng:NextNumber(-jitter, jitter), rng:NextNumber(-jitter, jitter) * 0.3, rng:NextNumber(-jitter, jitter))
			end
			segment(last, p, w)
			if branch and i > 1 and i < steps - 1 and rng:NextNumber() < 0.3 then
				local away = p + (b - a).Unit * (b - a).Magnitude * 0.18 + Vector3.new(rng:NextNumber(-25, 25), 0, rng:NextNumber(-25, 25))
				zig(p, away, 4, jitter * 0.5, w * 0.5, false)
			end
			last = p
		end
	end
	local length = (to - from).Magnitude
	zig(from, to, math.clamp(math.floor(length / 14), 6, 16), math.clamp(length / 18, 2, 12), width, true)
	-- flicker then vanish
	task.spawn(function()
		task.wait(life * 0.4)
		for _, p in ipairs(parts) do
			p.Transparency = 0.7
		end
		task.wait(0.05)
		for _, p in ipairs(parts) do
			p.Transparency = 0
		end
		task.wait(life * 0.6)
		for _, p in ipairs(parts) do
			p:Destroy()
		end
	end)
end

function SpaceFX.Shock(pos, color, fromSize, toSize, seconds, transparency, material)
	local ball = SpaceFX.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * fromSize, Position = pos, Color = color,
		Transparency = transparency or 0.4, Material = material or Enum.Material.ForceField })
	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * toSize, Transparency = 1 }):Play()
	Debris:AddItem(ball, seconds + 0.1)
	return ball
end

function SpaceFX.Disc(pos, color, toSize, seconds, transparency)
	local ring = SpaceFX.Part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 1, 1), Color = color, Transparency = transparency or 0.2,
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2) })
	TweenService:Create(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.4, toSize, toSize), Transparency = 1 }):Play()
	Debris:AddItem(ring, seconds + 0.1)
	return ring
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
function SpaceFX.GroundAt(x, z, fallbackY)
	local ignore = { folder }
	for _, name in ipairs({ "PlantedPlanets", "MutationFX", "LiveEventFX", "HeldPlanets" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	if workspace.CurrentCamera then
		table.insert(ignore, workspace.CurrentCamera)
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -1700, 0), groundParams)
	return hit and hit.Position or Vector3.new(x, fallbackY or 901, z)
end

-- camera shake (added on top of the normal camera every frame)
local shakes = {}
RunService:BindToRenderStep("SpaceFXShake", Enum.RenderPriority.Camera.Value + 1, function()
	if #shakes == 0 then
		return
	end
	local now = os.clock()
	local strength = 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local t = (now - s.Start) / s.Duration
		if t >= 1 then
			table.remove(shakes, i)
		else
			strength += s.Strength * (1 - t)
		end
	end
	local camera = workspace.CurrentCamera
	if camera and strength > 0 then
		local n = now * 40
		camera.CFrame *= CFrame.Angles(math.noise(n, 1) * strength * 0.03, math.noise(n, 2) * strength * 0.03, math.noise(n, 3) * strength * 0.02)
	end
end)
function SpaceFX.Shake(strength, seconds)
	table.insert(shakes, { Strength = strength, Duration = seconds or 0.6, Start = os.clock() })
end

local flashCC = Lighting:FindFirstChild("SpaceFXFlash") or Instance.new("ColorCorrectionEffect")
flashCC.Name = "SpaceFXFlash"
flashCC.Parent = Lighting
function SpaceFX.Flash(color, strength, seconds)
	flashCC.TintColor = color or Color3.new(1, 1, 1)
	flashCC.Brightness = strength or 0.4
	TweenService:Create(flashCC, TweenInfo.new(seconds or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
end

local sfxGroup = nil
local function group()
	if not sfxGroup or not sfxGroup.Parent then
		sfxGroup = SoundService:FindFirstChild("GameSfx")
	end
	return sfxGroup
end
function SpaceFX.Sound(id, volume, props)
	props = props or {}
	if not id or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.Looped = props.Looped == true
	sound.PlaybackSpeed = props.Speed or 1
	local g = group()
	if g and g:IsA("SoundGroup") then
		sound.SoundGroup = g
	end
	local container = sound
	if props.Position then
		local holder = SpaceFX.Part({ Size = Vector3.one * 0.2, Position = props.Position, Transparency = 1 })
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = props.MinDistance or 40
		sound.RollOffMaxDistance = props.MaxDistance or 700
		sound.Parent = holder
		container = holder
	else
		sound.Parent = props.Parent or SoundService
	end
	sound:Play()
	if not sound.Looped then
		sound.Ended:Connect(function()
			container:Destroy()
		end)
		Debris:AddItem(container, props.Life or 30)
	end
	return sound, container
end

return SpaceFX
