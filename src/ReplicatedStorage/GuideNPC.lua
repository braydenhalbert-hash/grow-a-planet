--[[
	GuideNPC  (ModuleScript)  -- ReplicatedStorage

	The tutorial guides: little characters built from parts (no meshes or uploaded animations
	needed), animated in code so they can walk, wave, point at things, cheer, facepalm, shrug,
	dance, think and look surprised. Each one has a face with blinking eyes and a mouth that
	moves when it talks, and a comic speech bubble.

	  Cosmo     a small astronaut gardener with a glass helmet and a jetpack (the main guide)
	  Zib       a three-eyed green alien trader in a purple coat with a gold chain (money stuff)
	  Sprocket  a boxy one-eyed engineer robot with a wrench (sprinklers + gear)

	Only the player who sees them has them (TutorialClient makes them on the client), so every
	player gets their own guide. They can't be clicked, bumped into or hit by raycasts.

	  local npc = GuideNPC.new("Cosmo", parentFolder)
	  npc:Teleport(position)       npc:WalkTo(position)        npc:LookAt(position)
	  npc:Play("wave" | "point" | "cheer" | "facepalm" | "shrug" | "think" | "dance" | "surprised" | "talk", seconds)
	  npc:PointAt(position)        npc:Say(text) (yields)       npc:Poof()     npc:Destroy()
	  npc:Update(dt)               (TutorialClient calls this every frame)
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Stardust = require(script.Parent:WaitForChild("Stardust"))

local GuideNPC = {}
GuideNPC.__index = GuideNPC

local rgb = Color3.fromRGB
local CF, V3 = CFrame.new, Vector3.new
local ANG = CFrame.Angles

---------------------------------------------------------------------
-- Looks
---------------------------------------------------------------------
-- Dim: body proportions (studs). Parts are added to bones: Torso, Head, ArmL, ArmR, LegL, LegR, Root
GuideNPC.Looks = {}

GuideNPC.Looks.Cosmo = {
	Name = "Cosmo",
	Color = rgb(90, 255, 140),
	Dim = { LegLen = 1.1, LegX = 0.42, TorsoH = 1.45, TorsoW = 1.5, ArmLen = 1.25, ArmW = 0.5, HeadR = 0.95, Hover = 0.25 },
	Speed = 22,
	Build = function(add, D)
		local suit, trim, dark = rgb(240, 244, 250), rgb(90, 255, 140), rgb(30, 34, 46)
		-- body
		add("Torso", "Block", V3(D.TorsoW, D.TorsoH, 1.05), CF(), suit, Enum.Material.SmoothPlastic)
		add("Torso", "Block", V3(D.TorsoW + 0.05, 0.22, 1.1), CF(0, -0.35, 0), trim, Enum.Material.Neon)
		add("Torso", "Block", V3(0.55, 0.42, 0.08), CF(0, 0.2, -0.55), dark, Enum.Material.SmoothPlastic) -- chest panel
		add("Torso", "Ball", V3(0.14, 0.14, 0.14), CF(-0.12, 0.25, -0.6), rgb(255, 80, 80), Enum.Material.Neon)
		add("Torso", "Ball", V3(0.14, 0.14, 0.14), CF(0.12, 0.25, -0.6), trim, Enum.Material.Neon)
		-- jetpack with a leaf on top
		add("Torso", "Block", V3(1.1, 1.2, 0.5), CF(0, 0.05, 0.75), rgb(200, 205, 215), Enum.Material.Metal)
		local flameL = add("Torso", "Ball", V3(0.38, 0.38, 0.38), CF(-0.3, -0.72, 0.8), rgb(255, 170, 60), Enum.Material.Neon)
		local flameR = add("Torso", "Ball", V3(0.38, 0.38, 0.38), CF(0.3, -0.72, 0.8), rgb(255, 170, 60), Enum.Material.Neon)
		flameL.Name, flameR.Name = "Flame", "Flame"
		add("Torso", "Block", V3(0.08, 0.5, 0.08), CF(0.3, 0.85, 0.75), rgb(110, 80, 50), Enum.Material.Wood)
		add("Torso", "Block", V3(0.45, 0.1, 0.28), CF(0.45, 1.05, 0.75) * ANG(0, 0, 0.5), trim, Enum.Material.Neon)
		-- head: helmet + dark visor + glowing eyes
		add("Head", "Ball", V3(1.75, 1.75, 1.75), CF(), suit, Enum.Material.SmoothPlastic)
		add("Head", "Ball", V3(1.95, 1.95, 1.95), CF(), rgb(200, 240, 255), Enum.Material.Glass, { Transparency = 0.65 })
		add("Head", "Block", V3(1.25, 0.85, 0.3), CF(0, 0.05, -0.75), dark, Enum.Material.SmoothPlastic)
		add("Head", "Block", V3(0.22, 0.32, 0.08), CF(-0.28, 0.15, -0.92), rgb(120, 255, 200), Enum.Material.Neon).Name = "Eye"
		add("Head", "Block", V3(0.22, 0.32, 0.08), CF(0.28, 0.15, -0.92), rgb(120, 255, 200), Enum.Material.Neon).Name = "Eye"
		add("Head", "Block", V3(0.42, 0.08, 0.08), CF(0, -0.18, -0.92), rgb(120, 255, 200), Enum.Material.Neon).Name = "Mouth"
		-- antenna
		add("Head", "Block", V3(0.07, 0.6, 0.07), CF(0.35, 1.15, 0), rgb(200, 205, 215), Enum.Material.Metal)
		add("Head", "Ball", V3(0.25, 0.25, 0.25), CF(0.35, 1.48, 0), trim, Enum.Material.Neon).Name = "AntennaTip"
		-- arms (with gloves) + legs (with boots)
		for _, side in ipairs({ "ArmL", "ArmR" }) do
			add(side, "Block", V3(D.ArmW, D.ArmLen, D.ArmW), CF(), suit, Enum.Material.SmoothPlastic)
			add(side, "Ball", V3(0.58, 0.58, 0.58), CF(0, -D.ArmLen / 2, 0), trim, Enum.Material.SmoothPlastic).Name = "Hand"
		end
		for _, side in ipairs({ "LegL", "LegR" }) do
			add(side, "Block", V3(0.55, D.LegLen, 0.6), CF(), suit, Enum.Material.SmoothPlastic)
			add(side, "Block", V3(0.65, 0.3, 0.8), CF(0, -D.LegLen / 2 + 0.1, -0.08), dark, Enum.Material.SmoothPlastic)
		end
	end,
}

GuideNPC.Looks.Zib = {
	Name = "Zib",
	Color = rgb(190, 110, 255),
	Dim = { LegLen = 1.05, LegX = 0.36, TorsoH = 1.5, TorsoW = 1.3, ArmLen = 1.45, ArmW = 0.38, HeadR = 0.9, Hover = 0 },
	Speed = 20,
	Build = function(add, D)
		local skin, coat, gold = rgb(120, 225, 110), rgb(110, 50, 190), rgb(255, 205, 70)
		add("Torso", "Block", V3(D.TorsoW, D.TorsoH, 0.85), CF(), coat, Enum.Material.SmoothPlastic)
		add("Torso", "Block", V3(0.45, D.TorsoH, 0.88), CF(0, 0, -0.01), rgb(70, 30, 130), Enum.Material.SmoothPlastic)
		add("Torso", "Block", V3(D.TorsoW + 0.5, 0.25, 1.0), CF(0, D.TorsoH / 2 - 0.05, 0), rgb(150, 80, 230), Enum.Material.SmoothPlastic) -- shoulder pads
		-- gold chain + dollar coin
		add("Torso", "Cylinder", V3(0.1, 0.9, 0.9), CF(0, 0.35, -0.42) * ANG(0, math.rad(90), 0), gold, Enum.Material.Neon)
		add("Torso", "Cylinder", V3(0.08, 0.38, 0.38), CF(0, -0.05, -0.46) * ANG(0, math.rad(90), 0), gold, Enum.Material.Neon).Name = "Coin"
		-- head: big round green head, three eyes, ear fins, antenna stalks
		add("Head", "Ball", V3(1.75, 1.75, 1.75), CF(), skin, Enum.Material.SmoothPlastic)
		for i, x in ipairs({ -0.42, 0, 0.42 }) do
			local y = i == 2 and 0.38 or 0.12
			add("Head", "Ball", V3(0.42, 0.42, 0.42), CF(x, y, -0.66), rgb(255, 255, 255), Enum.Material.SmoothPlastic).Name = "Eye"
			add("Head", "Ball", V3(0.2, 0.2, 0.2), CF(x, y, -0.84), rgb(25, 20, 40), Enum.Material.SmoothPlastic).Name = "Pupil"
		end
		add("Head", "Block", V3(0.55, 0.14, 0.1), CF(0, -0.38, -0.74), rgb(40, 20, 50), Enum.Material.SmoothPlastic).Name = "Mouth"
		add("Head", "Block", V3(0.12, 0.08, 0.1), CF(0.22, -0.3, -0.77), rgb(255, 255, 255), Enum.Material.SmoothPlastic) -- gold tooth? just a grin
		add("Head", "Block", V3(0.5, 0.22, 0.28), CF(-0.92, 0.05, 0) * ANG(0, 0, 0.5), skin, Enum.Material.SmoothPlastic)
		add("Head", "Block", V3(0.5, 0.22, 0.28), CF(0.92, 0.05, 0) * ANG(0, 0, -0.5), skin, Enum.Material.SmoothPlastic)
		add("Head", "Block", V3(0.07, 0.7, 0.07), CF(-0.35, 1.05, 0) * ANG(0, 0, 0.3), skin, Enum.Material.SmoothPlastic)
		add("Head", "Block", V3(0.07, 0.7, 0.07), CF(0.35, 1.05, 0) * ANG(0, 0, -0.3), skin, Enum.Material.SmoothPlastic)
		add("Head", "Ball", V3(0.22, 0.22, 0.22), CF(-0.47, 1.38, 0), gold, Enum.Material.Neon).Name = "AntennaTip"
		add("Head", "Ball", V3(0.22, 0.22, 0.22), CF(0.47, 1.38, 0), gold, Enum.Material.Neon).Name = "AntennaTip"
		for _, side in ipairs({ "ArmL", "ArmR" }) do
			add(side, "Block", V3(D.ArmW + 0.08, D.ArmLen * 0.6, D.ArmW + 0.08), CF(0, D.ArmLen * 0.2, 0), coat, Enum.Material.SmoothPlastic)
			add(side, "Block", V3(D.ArmW, D.ArmLen, D.ArmW), CF(), skin, Enum.Material.SmoothPlastic)
			add(side, "Ball", V3(0.48, 0.48, 0.48), CF(0, -D.ArmLen / 2, 0), skin, Enum.Material.SmoothPlastic).Name = "Hand"
		end
		for _, side in ipairs({ "LegL", "LegR" }) do
			add(side, "Block", V3(0.45, D.LegLen, 0.5), CF(), rgb(50, 30, 80), Enum.Material.SmoothPlastic)
			add(side, "Block", V3(0.55, 0.25, 0.75), CF(0, -D.LegLen / 2 + 0.1, -0.12), gold, Enum.Material.Metal)
		end
	end,
}

GuideNPC.Looks.Sprocket = {
	Name = "Sprocket",
	Color = rgb(255, 200, 60),
	Dim = { LegLen = 0.95, LegX = 0.5, TorsoH = 1.4, TorsoW = 1.8, ArmLen = 1.35, ArmW = 0.45, HeadR = 0.7, Hover = 0 },
	Speed = 18,
	Build = function(add, D)
		local metal, stripe, dark = rgb(150, 160, 175), rgb(255, 200, 60), rgb(40, 44, 54)
		add("Torso", "Block", V3(D.TorsoW, D.TorsoH, 1.2), CF(), metal, Enum.Material.Metal)
		for i = -2, 2 do
			add("Torso", "Block", V3(0.22, 0.3, 0.05), CF(i * 0.36, -0.45, -0.61) * ANG(0, 0, 0.6), i % 2 == 0 and stripe or dark, Enum.Material.SmoothPlastic)
		end
		add("Torso", "Cylinder", V3(0.1, 0.55, 0.55), CF(0, 0.2, -0.62) * ANG(0, math.rad(90), 0), dark, Enum.Material.SmoothPlastic)
		add("Torso", "Ball", V3(0.3, 0.3, 0.3), CF(0, 0.2, -0.66), rgb(255, 120, 60), Enum.Material.Neon).Name = "Core"
		add("Torso", "Cylinder", V3(0.35, 0.22, 0.22), CF(-0.6, D.TorsoH / 2 + 0.15, 0.3) * ANG(0, 0, math.rad(90)), dark, Enum.Material.Metal).Name = "Chimney"
		-- head: a box with one big eye and a grill mouth
		add("Head", "Block", V3(1.4, 1.2, 1.2), CF(), metal, Enum.Material.Metal)
		add("Head", "Block", V3(1.45, 0.18, 1.25), CF(0, 0.55, 0), stripe, Enum.Material.SmoothPlastic)
		add("Head", "Cylinder", V3(0.1, 0.62, 0.62), CF(0, 0.1, -0.6) * ANG(0, math.rad(90), 0), dark, Enum.Material.SmoothPlastic)
		add("Head", "Cylinder", V3(0.1, 0.42, 0.42), CF(0, 0.1, -0.64) * ANG(0, math.rad(90), 0), rgb(80, 230, 255), Enum.Material.Neon).Name = "Eye"
		add("Head", "Block", V3(0.7, 0.16, 0.06), CF(0, -0.34, -0.61), dark, Enum.Material.SmoothPlastic).Name = "Mouth"
		add("Head", "Block", V3(0.08, 0.5, 0.08), CF(0.45, 0.85, 0), dark, Enum.Material.Metal)
		add("Head", "Ball", V3(0.2, 0.2, 0.2), CF(0.45, 1.12, 0), rgb(255, 80, 60), Enum.Material.Neon).Name = "AntennaTip"
		for _, side in ipairs({ "ArmL", "ArmR" }) do
			add(side, "Cylinder", V3(D.ArmLen, D.ArmW, D.ArmW), CF() * ANG(0, 0, math.rad(90)), metal, Enum.Material.Metal)
			add(side, "Block", V3(0.55, 0.4, 0.55), CF(0, -D.ArmLen / 2, 0), dark, Enum.Material.Metal).Name = "Hand"
		end
		-- wrench in the right hand
		add("ArmR", "Block", V3(0.15, 1.1, 0.15), CF(0, -D.ArmLen / 2 - 0.1, -0.45) * ANG(math.rad(90), 0, 0), rgb(200, 205, 215), Enum.Material.Metal)
		add("ArmR", "Block", V3(0.45, 0.15, 0.25), CF(0, -D.ArmLen / 2 - 0.1, -1.0), rgb(200, 205, 215), Enum.Material.Metal)
		for _, side in ipairs({ "LegL", "LegR" }) do
			add(side, "Block", V3(0.6, D.LegLen, 0.7), CF(), dark, Enum.Material.Metal)
			add(side, "Block", V3(0.75, 0.35, 1.05), CF(0, -D.LegLen / 2 + 0.15, -0.1), stripe, Enum.Material.SmoothPlastic)
		end
	end,
}

---------------------------------------------------------------------
-- Building
---------------------------------------------------------------------
local function newPart(shape, size, color, material, extra)
	local p = Instance.new("Part")
	p.Shape = shape == "Ball" and Enum.PartType.Ball or (shape == "Cylinder" and Enum.PartType.Cylinder or Enum.PartType.Block)
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function rotationBetween(from, to)
	local axis = from:Cross(to)
	local dot = math.clamp(from:Dot(to), -1, 1)
	if axis.Magnitude < 1e-4 then
		return dot > 0 and CFrame.identity or ANG(math.pi, 0, 0)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

function GuideNPC.new(lookName, parent)
	local look = GuideNPC.Looks[lookName] or GuideNPC.Looks.Cosmo
	local D = look.Dim
	local self = setmetatable({}, GuideNPC)
	self.Look = look
	self.Name = look.Name
	self.Color = look.Color
	self.D = D
	self.Model = Instance.new("Model")
	self.Model.Name = "Guide_" .. look.Name
	self.Pieces = {} -- { Part, Bone, Offset, BaseSize }
	self.Named = {}
	local function add(bone, shape, size, offset, color, material, extra)
		local p = newPart(shape, size, color, material, extra)
		p.Parent = self.Model
		table.insert(self.Pieces, { Part = p, Bone = bone, Offset = offset, BaseSize = size })
		return p
	end
	look.Build(add, D)
	for _, piece in ipairs(self.Pieces) do
		local list = self.Named[piece.Part.Name] or {}
		table.insert(list, piece)
		self.Named[piece.Part.Name] = list
	end
	-- a soft glow + a name tag so you know who's talking
	local core = newPart("Block", V3(0.2, 0.2, 0.2), look.Color, Enum.Material.SmoothPlastic, { Transparency = 1 })
	core.Name = "Anchor"
	core.Parent = self.Model
	table.insert(self.Pieces, { Part = core, Bone = "Head", Offset = CF(0, D.HeadR + 0.6, 0), BaseSize = core.Size })
	self.Anchor = core
	local light = Instance.new("PointLight")
	light.Color = look.Color
	light.Range = 9
	light.Brightness = 0.8
	light.Parent = core

	-- jetpack / hover dust
	if D.Hover > 0 then
		for _, piece in ipairs(self.Named.Flame or {}) do
			local e = Stardust.Emitter("Dust", { rgb(255, 230, 150), rgb(255, 120, 40), rgb(255, 255, 220) }, {
				Rate = 18, Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(3, 5),
				Size = NumberSequence.new(0.35, 0), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(15, 15),
			})
			e.Parent = piece.Part
		end
	end

	-- state
	self.Root = CF(0, -500, 0)
	self.Yaw = 0
	self.Target = nil         -- where it's walking to
	self.Look_ = nil          -- where it looks
	self.PointTarget = nil
	self.Action, self.ActionUntil = "idle", 0
	self.Move = 0
	self.Hop = 0
	self.Spin = 0
	self.Talking = false
	self.Expression = "happy"
	self.J = { Torso = CFrame.identity, Head = CFrame.identity, ArmL = CFrame.identity, ArmR = CFrame.identity, LegL = CFrame.identity, LegR = CFrame.identity }
	self.T = math.random() * 10
	self.NextBlink = 2
	self.Scale = 1
	self.Ground = nil

	self:_makeBubble()
	self.Model.Parent = parent
	return self
end

---------------------------------------------------------------------
-- Speech bubble
---------------------------------------------------------------------
function GuideNPC:_makeBubble()
	local gui = Instance.new("BillboardGui")
	gui.Name = "Bubble"
	gui.Adornee = self.Anchor
	gui.Size = UDim2.fromOffset(300, 110)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Enabled = false
	gui.Parent = self.Anchor

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local bubble = Instance.new("Frame")
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Position = UDim2.new(0.5, 0, 1, -12)
	bubble.Size = UDim2.fromOffset(0, 0)
	bubble.AutomaticSize = Enum.AutomaticSize.XY
	bubble.BackgroundColor3 = rgb(255, 255, 255)
	bubble.Parent = holder
	Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, 16)
	local outline = Instance.new("UIStroke", bubble)
	outline.Color = self.Color
	outline.Thickness = 3
	local padding = Instance.new("UIPadding", bubble)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 16), UDim.new(0, 10)
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
	local sizeLimit = Instance.new("UISizeConstraint", bubble)
	sizeLimit.MaxSize = Vector2.new(290, 200)
	sizeLimit.MinSize = Vector2.new(90, 30)

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromOffset(0, 0)
	text.AutomaticSize = Enum.AutomaticSize.XY
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 20
	text.TextColor3 = rgb(35, 30, 55)
	text.TextWrapped = true
	text.RichText = true
	text.Text = ""
	text.Parent = bubble
	local textLimit = Instance.new("UISizeConstraint", text)
	textLimit.MaxSize = Vector2.new(262, 180)

	-- name tag sitting on the bubble's top edge
	local tag = Instance.new("TextLabel")
	tag.AnchorPoint = Vector2.new(0, 0.5)
	tag.Position = UDim2.fromOffset(-2, -16)
	tag.Size = UDim2.fromOffset(0, 22)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.BackgroundColor3 = self.Color
	tag.Font = Enum.Font.FredokaOne
	tag.TextSize = 15
	tag.TextColor3 = rgb(25, 20, 40)
	tag.Text = self.Name
	tag.Parent = bubble
	Instance.new("UICorner", tag).CornerRadius = UDim.new(1, 0)
	local tagPad = Instance.new("UIPadding", tag)
	tagPad.PaddingLeft, tagPad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)

	-- little tail pointing down at the guide
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, -12)
	tail.Size = UDim2.fromOffset(16, 16)
	tail.Rotation = 45
	tail.BackgroundColor3 = rgb(255, 255, 255)
	tail.ZIndex = 0
	tail.Parent = holder
	local tailStroke = Instance.new("UIStroke", tail)
	tailStroke.Color = self.Color
	tailStroke.Thickness = 3

	self.Bubble = { Gui = gui, Scale = scale, Text = text }
end

-- talking sound: NpcTalk's typing ticks (client only; quietly does nothing if NpcTalk isn't there)
local npcTalk = nil
local function talkSound(index, character)
	if npcTalk == nil then
		local ok, mod = pcall(function()
			return require(script.Parent:WaitForChild("NpcTalk", 2))
		end)
		npcTalk = ok and mod or false
	end
	if npcTalk and npcTalk.TypeSound then
		npcTalk.TypeSound(index, character)
	end
end

-- shows a line with a typewriter effect, then waits so it can be read. Yields. Returns false if interrupted.
function GuideNPC:Say(line, hold)
	self._sayId = (self._sayId or 0) + 1
	local id = self._sayId
	local b = self.Bubble
	b.Gui.Enabled = true
	b.Text.Text = line
	b.Text.MaxVisibleGraphemes = 0
	b.Scale.Scale = 0.6
	TweenService:Create(b.Scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	self.Talking = true
	if self.Action == "idle" then
		self:Play("talk", 1.2)
	end
	local graphemes = utf8.len(line) or #line
	local plain = b.Text.ContentText
	for i = 1, graphemes do
		if self._sayId ~= id or self.Dead then
			return false
		end
		b.Text.MaxVisibleGraphemes = i
		talkSound(i, string.sub(plain, i, i)) -- the same soft typing ticks the shop NPCs make
		if i % 2 == 0 then
			task.wait(0.022)
		end
	end
	b.Text.MaxVisibleGraphemes = -1
	self.Talking = false
	local waitTime = hold or math.clamp(0.9 + graphemes * 0.045, 1.4, 4.2)
	local t0 = os.clock()
	while os.clock() - t0 < waitTime do
		if self._sayId ~= id or self.Dead then
			return false
		end
		task.wait(0.05)
	end
	return true
end

-- says several lines in a row (stops if interrupted)
function GuideNPC:SayLines(lines)
	for _, line in ipairs(lines or {}) do
		if not self:Say(line) then
			return false
		end
	end
	return true
end

-- keeps a line up until Hush() or the next Say
function GuideNPC:Show(line)
	self._sayId = (self._sayId or 0) + 1
	local b = self.Bubble
	b.Gui.Enabled = true
	b.Text.Text = line
	b.Text.MaxVisibleGraphemes = -1
	b.Scale.Scale = 0.7
	TweenService:Create(b.Scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

function GuideNPC:Hush()
	self._sayId = (self._sayId or 0) + 1
	self.Talking = false
	self.Bubble.Gui.Enabled = false
end

---------------------------------------------------------------------
-- Moving + acting
---------------------------------------------------------------------
function GuideNPC:Teleport(position)
	self.Root = CF(position) * ANG(0, self.Yaw, 0)
	self.Target = nil
	self.Ground = position.Y
end

function GuideNPC:WalkTo(position)
	self.Target = position
end

function GuideNPC:Stop()
	self.Target = nil
end

function GuideNPC:LookAt(position)
	self.LookTarget = position
end

function GuideNPC:Position()
	return self.Root.Position
end

function GuideNPC:HeadPosition()
	return self.Anchor.Position
end

function GuideNPC:Play(action, seconds)
	self.Action = action
	self.ActionUntil = os.clock() + (seconds or 1.5)
	if action == "cheer" or action == "dance" then
		self.Expression = "happy"
	elseif action == "surprised" then
		self.Expression = "open"
	elseif action == "facepalm" or action == "shrug" then
		self.Expression = "flat"
	end
end

function GuideNPC:PointAt(position, seconds)
	self.PointTarget = position
	self:Play("point", seconds or 2.5)
end

function GuideNPC:SetExpression(name)
	self.Expression = name
end

-- a burst of stardust (spawning, leaving, celebrating)
local function burst(position, colors, count, textures)
	local p = newPart("Block", V3(1, 1, 1), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1 })
	p.CFrame = CF(position)
	p.Parent = workspace.CurrentCamera
	for _, tex in ipairs(textures or { "Star", "Dust" }) do
		local e = Stardust.Emitter(tex, colors, {
			Rate = 0, Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }), Drag = 3,
		})
		e.Parent = p
		e:Emit(count or 18)
	end
	Debris:AddItem(p, 2)
end
GuideNPC.Burst = burst

function GuideNPC:Poof()
	local c = self.Color
	burst(self.Root.Position + V3(0, 2, 0), { rgb(255, 255, 255), c, c:Lerp(rgb(255, 255, 255), 0.5) }, 22)
end

function GuideNPC:Confetti()
	local p = newPart("Block", V3(1, 1, 1), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1 })
	p.CFrame = CF(self.Anchor.Position + V3(0, 1, 0))
	p.Parent = workspace.CurrentCamera
	local colors = { rgb(255, 90, 120), rgb(90, 220, 255), rgb(255, 220, 70), rgb(120, 255, 140), rgb(200, 120, 255) }
	for _, color in ipairs(colors) do
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(color)
		e.LightEmission = 0.6
		e.Size = NumberSequence.new(0.45)
		e.Lifetime = NumberRange.new(1.2, 1.8)
		e.Speed = NumberRange.new(12, 20)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Acceleration = V3(0, -25, 0)
		e.RotSpeed = NumberRange.new(-300, 300)
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 0
		e.Parent = p
		e:Emit(10)
	end
	burst(self.Anchor.Position, { rgb(255, 255, 255), self.Color, rgb(255, 230, 120) }, 14, { "Star" })
	Debris:AddItem(p, 2.5)
end

-- pops in (scales up from nothing)
function GuideNPC:Appear(position)
	self:Teleport(position)
	self.Scale = 0.05
	self:Poof()
	self:Play("wave", 1.6)
end

function GuideNPC:Destroy()
	self.Dead = true
	self.Model:Destroy()
end

---------------------------------------------------------------------
-- Animation (called every frame)
---------------------------------------------------------------------
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
GuideNPC.GroundParams = groundParams

local function lerpAlpha(dt, speed)
	return 1 - math.exp(-speed * dt)
end

function GuideNPC:_targets(t)
	local D = self.D
	local J = {}
	local action = self.Action
	if os.clock() > self.ActionUntil and action ~= "idle" then
		self.Action = "idle"
		action = "idle"
		self.PointTarget = nil
		if self.Expression ~= "happy" then
			self.Expression = "happy"
		end
	end
	local m = self.Move
	local swing = math.sin(t * 11) * 0.75 * m
	J.LegL = ANG(swing, 0, 0)
	J.LegR = ANG(-swing, 0, 0)
	J.ArmL = ANG(-swing * 0.8, 0, -0.1 - 0.04 * math.sin(t * 2))
	J.ArmR = ANG(swing * 0.8, 0, 0.1 + 0.04 * math.sin(t * 2))
	J.Torso = ANG(-0.12 * m, 0, 0)
	J.Head = CFrame.identity
	local hop, spin = 0, 0

	if action == "wave" then
		J.ArmR = ANG(0, 0, 2.6 + 0.35 * math.sin(t * 12))
		J.Head = ANG(0, 0, 0.12 * math.sin(t * 6))
	elseif action == "talk" then
		J.ArmR = ANG(0.7 + 0.3 * math.sin(t * 5), 0, 0.35)
		J.ArmL = ANG(0.4 + 0.25 * math.sin(t * 4 + 1), 0, -0.3)
		J.Head = ANG(0.06 * math.sin(t * 7), 0, 0)
	elseif action == "point" and self.PointTarget then
		local torsoCF = self._torsoCF or self.Root
		local shoulder = torsoCF * V3(D.TorsoW / 2 + D.ArmW / 2, D.TorsoH / 2 - 0.15, 0)
		local dir = torsoCF:VectorToObjectSpace((self.PointTarget - shoulder).Unit)
		J.ArmR = rotationBetween(V3(0, -1, 0), dir)
		J.ArmL = ANG(0, 0, -0.25)
	elseif action == "cheer" then
		J.ArmL = ANG(0, 0, -2.8 + 0.25 * math.sin(t * 16))
		J.ArmR = ANG(0, 0, 2.8 - 0.25 * math.sin(t * 16))
		hop = math.abs(math.sin(t * 9)) * 1.1
		J.LegL, J.LegR = ANG(0.3, 0, -0.15), ANG(0.3, 0, 0.15)
	elseif action == "dance" then
		J.ArmL = ANG(0, 0, -1.6 + math.sin(t * 8) * 1.0)
		J.ArmR = ANG(0, 0, 1.6 + math.sin(t * 8) * 1.0)
		J.LegL = ANG(math.max(0, math.sin(t * 8)) * 0.8, 0, 0)
		J.LegR = ANG(math.max(0, -math.sin(t * 8)) * 0.8, 0, 0)
		J.Head = ANG(0, 0, 0.25 * math.sin(t * 8))
		hop = math.abs(math.sin(t * 8)) * 0.4
		spin = t * 4
	elseif action == "facepalm" then
		J.ArmR = ANG(2.3, 0, -0.75)
		J.Head = ANG(-0.35, 0, 0.1)
		J.Torso = ANG(-0.15, 0, 0)
	elseif action == "shrug" then
		J.ArmL = ANG(0.9, 0, -0.9)
		J.ArmR = ANG(0.9, 0, 0.9)
		J.Head = ANG(0, 0, 0.3)
		hop = 0.12
	elseif action == "think" then
		J.ArmR = ANG(2.1, 0, -0.55)
		J.ArmL = ANG(0.6, 0, 0.45)
		J.Head = ANG(0.15, 0, 0.2)
	elseif action == "surprised" then
		J.ArmL = ANG(0, 0, -2.1)
		J.ArmR = ANG(0, 0, 2.1)
		J.Torso = ANG(0.15, 0, 0)
		hop = 0.35
	elseif action == "hop" then
		hop = math.abs(math.sin(t * 9)) * 1.4
		J.ArmL, J.ArmR = ANG(0, 0, -1.2), ANG(0, 0, 1.2)
	end

	-- look at something (turns the head)
	if self.LookTarget and action ~= "facepalm" then
		local rel = self.Root:PointToObjectSpace(self.LookTarget)
		local yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1, 1)
		J.Head = J.Head * ANG(0, yaw, 0)
	end
	return J, hop, spin
end

function GuideNPC:Update(dt, ignoreList)
	if self.Dead then
		return
	end
	self.T += dt
	local t = self.T
	local D = self.D

	-- walking
	local pos = self.Root.Position
	local moving = 0
	if self.Target then
		local flat = V3(self.Target.X - pos.X, 0, self.Target.Z - pos.Z)
		local dist = flat.Magnitude
		if dist > 0.6 then
			local speed = self.Look.Speed * math.clamp(dist / 6, 0.45, 1.35)
			local step = math.min(dist, speed * dt)
			pos += flat.Unit * step
			moving = math.clamp(speed / self.Look.Speed, 0, 1)
			self.Yaw = math.atan2(-flat.X, -flat.Z)
		else
			self.Target = nil
		end
	end
	if moving == 0 and self.LookTarget then
		local rel = self.LookTarget - pos
		if V3(rel.X, 0, rel.Z).Magnitude > 0.5 then
			local wanted = math.atan2(-rel.X, -rel.Z)
			local diff = (wanted - self.Yaw + math.pi) % (2 * math.pi) - math.pi
			self.Yaw += diff * lerpAlpha(dt, 6)
		end
	end
	self.Move += (moving - self.Move) * lerpAlpha(dt, 10)

	-- stay on the ground
	groundParams.FilterDescendantsInstances = ignoreList or { self.Model }
	local hit = workspace:Raycast(pos + V3(0, 6, 0), V3(0, -40, 0), groundParams)
	if hit then
		self.Ground = self.Ground and (self.Ground + (hit.Position.Y - self.Ground) * lerpAlpha(dt, 14)) or hit.Position.Y
	end
	local groundY = self.Ground or pos.Y
	self.Root = CF(pos.X, groundY, pos.Z) * ANG(0, self.Yaw, 0)

	-- pose
	local targets, hop, spin = self:_targets(t)
	local a = lerpAlpha(dt, 14)
	for name, target in pairs(targets) do
		self.J[name] = self.J[name]:Lerp(target, a)
	end
	self.Hop += (hop - self.Hop) * lerpAlpha(dt, 18)
	self.Spin = spin ~= 0 and spin or self.Spin * (1 - lerpAlpha(dt, 8))
	self.Scale += (1 - self.Scale) * lerpAlpha(dt, 9)
	local s = self.Scale

	local bob = D.Hover > 0 and (D.Hover + math.sin(t * 2.4) * 0.18) or math.abs(math.sin(t * 11)) * 0.12 * self.Move
	local base = self.Root * CF(0, (bob + self.Hop) * s, 0) * ANG(0, self.Spin, 0)
	local hip = base * CF(0, D.LegLen * s, 0)
	local torso = hip * self.J.Torso * CF(0, D.TorsoH / 2 * s, 0)
	self._torsoCF = torso
	local bones = {
		Root = base,
		Torso = torso,
		Head = torso * CF(0, D.TorsoH / 2 * s, 0) * self.J.Head * CF(0, D.HeadR * s, 0),
		ArmL = torso * CF(-(D.TorsoW / 2 + D.ArmW / 2) * s, (D.TorsoH / 2 - 0.15) * s, 0) * self.J.ArmL * CF(0, -D.ArmLen / 2 * s, 0),
		ArmR = torso * CF((D.TorsoW / 2 + D.ArmW / 2) * s, (D.TorsoH / 2 - 0.15) * s, 0) * self.J.ArmR * CF(0, -D.ArmLen / 2 * s, 0),
		LegL = hip * CF(-D.LegX * s, 0, 0) * self.J.LegL * CF(0, -D.LegLen / 2 * s, 0),
		LegR = hip * CF(D.LegX * s, 0, 0) * self.J.LegR * CF(0, -D.LegLen / 2 * s, 0),
	}

	-- face: blink, mouth flaps while talking
	self.NextBlink -= dt
	local blink = 1
	if self.NextBlink < 0 then
		blink = 0.1
		if self.NextBlink < -0.12 then
			self.NextBlink = 2 + math.random() * 3
		end
	end
	local mouthOpen = self.Talking and (0.5 + 0.5 * math.abs(math.sin(t * 18))) or 0

	local parts, cframes = {}, {}
	for _, piece in ipairs(self.Pieces) do
		local p = piece.Part
		local offset = piece.Offset
		if s < 0.999 then
			offset = CF(offset.Position * s) * offset.Rotation
		end
		local size = piece.BaseSize * s
		if (p.Name == "Eye" or p.Name == "Pupil") and p.Shape ~= Enum.PartType.Ball then
			size = V3(size.X, size.Y * blink, size.Z)
		elseif p.Name == "Mouth" then
			local e = self.Expression
			local h = (e == "open" and 2.6 or (e == "flat" and 0.8 or 1)) + mouthOpen * 2
			local w = e == "open" and 0.45 or (e == "happy" and 1.1 or 0.9)
			size = V3(size.X * w, size.Y * h, size.Z)
		elseif p.Name == "Flame" then
			local f = 0.75 + 0.35 * math.abs(math.sin(t * 23 + piece.BaseSize.X))
			size = V3(size.X, size.Y * f, size.Z)
		end
		if p.Size ~= size then
			p.Size = size
		end
		table.insert(parts, p)
		table.insert(cframes, bones[piece.Bone] * offset)
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

return GuideNPC
