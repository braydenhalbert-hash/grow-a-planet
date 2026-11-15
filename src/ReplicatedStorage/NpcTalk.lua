--[[
	NpcTalk  (ModuleScript)  -- ReplicatedStorage

	Grow-a-Garden style NPC talking, used by SeedShopUI (shop NPCs) and SellDialogue (Planet Buyer).
	Client only.

	NpcTalk.Say(part, text, holdSeconds)
	    White outlined text that types itself out above `part` (an NPC's head or a player's head),
	    stays a moment, then fades. A new line on the same part replaces the old one.
	    Returns how long the typing takes.

	NpcTalk.OutlineWhenNear(npc, prompt)
	    A white outline appears around `npc` while you're close enough to see its prompt.

	NpcTalk.Focus(kind) / NpcTalk.Unfocus(kind)
	    "shop": strong blur + the camera zooms in (shop windows)
	    "talk": slight blur on the far background + a small zoom (talking to an NPC)
	    The strongest active one wins; everything eases back when they're all gone.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NpcTalk = {}

local FONT = Enum.Font.FredokaOne
local TYPE_SPEED = 0.03 -- seconds per letter

-- text size for talking (smaller on phones)
function NpcTalk.TextSize()
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return math.min(view.X, view.Y) < 560 and 15 or 21
end

---------------------------------------------------------------------
-- Speech above heads
---------------------------------------------------------------------
local speeches = {} -- part -> { Gui, Id }
local speechId = 0

function NpcTalk.Say(part, text, holdSeconds)
	if not part or not part.Parent then
		return 0
	end
	speechId += 1
	local id = speechId
	local old = speeches[part]
	if old then
		old.Gui:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "NpcSpeech"
	gui.Adornee = part
	gui.Size = UDim2.fromOffset(560, 60) -- fixed size on screen, like Grow a Garden
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2.6, 0)
	gui.AlwaysOnTop = true -- stays sharp when the background is blurred
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.TextSize = NpcTalk.TextSize()
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.TextColor3 = Color3.new(1, 1, 1)
	label.RichText = true -- coloured coin amounts etc. work too
	label.Text = text
	label.MaxVisibleGraphemes = 0
	label.Parent = gui
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(25, 20, 30)
	outline.Thickness = 1.6
	outline.Parent = label

	speeches[part] = { Gui = gui, Id = id }
	local total = utf8.len(label.ContentText) or #label.ContentText
	task.spawn(function()
		for i = 1, total do
			if not gui.Parent then
				return
			end
			label.MaxVisibleGraphemes = i
			task.wait(TYPE_SPEED)
		end
		label.MaxVisibleGraphemes = -1
		task.wait(holdSeconds or 3)
		if not gui.Parent then
			return
		end
		local fade = TweenInfo.new(0.5)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(outline, fade, { Transparency = 1 }):Play()
		task.wait(0.55)
		gui:Destroy()
		if speeches[part] and speeches[part].Id == id then
			speeches[part] = nil
		end
	end)
	return total * TYPE_SPEED
end

function NpcTalk.Clear(part)
	local old = speeches[part]
	if old then
		old.Gui:Destroy()
		speeches[part] = nil
	end
end

-- the head of a model (falls back to any part)
function NpcTalk.HeadOf(model)
	if not model then
		return nil
	end
	return model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
end

---------------------------------------------------------------------
-- White outline while you're in range
---------------------------------------------------------------------
local outlines = {} -- prompt -> Highlight

function NpcTalk.OutlineWhenNear(npc, prompt)
	local highlight = Instance.new("Highlight")
	highlight.Name = "NearOutline"
	highlight.Adornee = npc
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = playerGui
	outlines[prompt] = highlight
end

local function fadeOutline(prompt, show)
	local highlight = outlines[prompt]
	if not highlight then
		return
	end
	if show then
		highlight.Enabled = true
	end
	local tween = TweenService:Create(highlight, TweenInfo.new(0.2), { OutlineTransparency = show and 0 or 1 })
	tween:Play()
	if not show then
		tween.Completed:Connect(function()
			if highlight.OutlineTransparency >= 0.99 then
				highlight.Enabled = false
			end
		end)
	end
end
ProximityPromptService.PromptShown:Connect(function(prompt)
	fadeOutline(prompt, true)
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	fadeOutline(prompt, false)
end)

---------------------------------------------------------------------
-- Blur + zoom
---------------------------------------------------------------------
local LOOKS = {
	shop = { Blur = 18, Zoom = 12, Rank = 2 },
	talk = { Blur = 0, Zoom = 8, Far = 0.55, Rank = 1 },
}
local active = {} -- kind -> count
local blur, dof = nil, nil
local baseFov = nil

local function effects()
	if not blur or not blur.Parent then
		blur = Instance.new("BlurEffect")
		blur.Name = "NpcFocusBlur"
		blur.Size = 0
		blur.Parent = Lighting
	end
	if not dof or not dof.Parent then
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "NpcFocusDepth"
		dof.FarIntensity = 0
		dof.NearIntensity = 0
		dof.InFocusRadius = 14
		dof.FocusDistance = 12
		dof.Parent = Lighting
	end
end

local function apply()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local look = nil
	for kind, count in pairs(active) do
		if count > 0 and (not look or LOOKS[kind].Rank > look.Rank) then
			look = LOOKS[kind]
		end
	end
	effects()
	local ease = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if look then
		baseFov = baseFov or camera.FieldOfView
		TweenService:Create(blur, ease, { Size = look.Blur }):Play()
		TweenService:Create(dof, ease, { FarIntensity = look.Far or 0 }):Play()
		TweenService:Create(camera, ease, { FieldOfView = baseFov - look.Zoom }):Play()
	else
		TweenService:Create(blur, ease, { Size = 0 }):Play()
		TweenService:Create(dof, ease, { FarIntensity = 0 }):Play()
		if baseFov then
			TweenService:Create(camera, ease, { FieldOfView = baseFov }):Play()
			baseFov = nil
		end
	end
end

function NpcTalk.Focus(kind)
	if not LOOKS[kind] then
		return
	end
	active[kind] = (active[kind] or 0) + 1
	if active[kind] == 1 then
		apply()
	end
end

function NpcTalk.Unfocus(kind)
	if not active[kind] or active[kind] <= 0 then
		return
	end
	active[kind] -= 1
	if active[kind] == 0 then
		apply()
	end
end

function NpcTalk.IsFocused(kind)
	return (active[kind] or 0) > 0
end

return NpcTalk
