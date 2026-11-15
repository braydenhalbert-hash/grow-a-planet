--[[
	SellDialogue  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	Talk to the Planet Buyer and a dark, see-through text box fades in on the right side
	of the screen (no window, just lines of text, faded at both edges).

	   Got anything to sell?
	   #1  I want to sell my inventory
	   #2  I want to sell this
	   #3  How much is this worth?
	   #4  Nevermind

	Click (or tap) a line to choose it. The number keys are NOT used by this box: they always go to
	your hotbar, so you can switch the planet in your hand while the box is open.
	("I want to sell this" and "How much is this worth?" use the planet in your hand.)

	Needs: SellServer (ServerScriptService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local sellRemote = remotes:WaitForChild("SellRequest")
local replyRemote = remotes:WaitForChild("SellReply")

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local BUYER_NAMES = { PlanetBuyer = true } -- model name or Humanoid display name of the buyer NPC
local CLOSE_DISTANCE = 18                  -- the box closes if you walk this far away

-- where the box sits: right side of the screen, a little below the middle
local BOX_ANCHOR = Vector2.new(1, 0.5)
local BOX_POSITION = UDim2.new(1, 0, 0.5, 70)
local BOX_WIDTH = 380

local FONT = Enum.Font.GothamMedium
local TEXT_SIZE = 20
local GREETING = "Got anything to sell?"

local CLICK_SOUND_ID = "rbxassetid://123087446204451"
local CLICK_VOLUME = 0.6
local FAIL_SOUND_ID = "rbxassetid://108295046133967"
local FAIL_VOLUME = 0.7

local OPTIONS = {
	{ Text = "I want to sell my inventory", Action = "all" },
	{ Text = "I want to sell this", Action = "held" },
	{ Text = "How much is this worth?", Action = "appraise" },
	{ Text = "Nevermind", Action = "close" },
}

---------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------
local function playSound(id, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = playerGui
	sound:Play()
	Debris:AddItem(sound, 3)
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function outline(parent)
	make("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local gui = make("ScreenGui", {
	Name = "SellDialogue",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 6,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local box = make("Frame", {
	Name = "Box",
	AnchorPoint = BOX_ANCHOR,
	Position = BOX_POSITION,
	Size = UDim2.new(0, BOX_WIDTH, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Visible = false,
}, gui)

-- fades the left and right edges into the background
make("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, box)

make("UIPadding", {
	PaddingTop = UDim.new(0, 16),
	PaddingBottom = UDim.new(0, 16),
	PaddingLeft = UDim.new(0, 40),
	PaddingRight = UDim.new(0, 40),
}, box)

make("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, box)

local function textProps(extra)
	local props = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for k, v in pairs(extra) do
		props[k] = v
	end
	return props
end

local npcLabel = make("TextLabel", textProps({ Name = "NpcText", LayoutOrder = 1, Text = "" }), box)
outline(npcLabel)

make("Frame", {
	Name = "Spacer",
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 4),
	BackgroundTransparency = 1,
}, box)

-- the NPC "types" its line out
local speakId = 0
local function speak(text)
	speakId += 1
	local id = speakId
	npcLabel.Text = text
	npcLabel.MaxVisibleGraphemes = 0
	local total = utf8.len(npcLabel.ContentText) or #npcLabel.ContentText
	task.spawn(function()
		for i = 1, total do
			if speakId ~= id then
				return
			end
			npcLabel.MaxVisibleGraphemes = i
			task.wait(0.018)
		end
		npcLabel.MaxVisibleGraphemes = -1
	end)
end

---------------------------------------------------------------------
-- Open / close / choose
---------------------------------------------------------------------
local isOpen = false
local waiting = false
local activeRoot = nil
local choose

local function closeDialogue()
	if not isOpen then
		return
	end
	isOpen = false
	waiting = false
	speakId += 1
	box.Visible = false
	activeRoot = nil
	player:SetAttribute("DialogueOpen", false)
end

local function openDialogue(root)
	activeRoot = root
	if isOpen then
		return
	end
	isOpen = true
	waiting = false
	box.Visible = true
	speak(GREETING)
	-- no number keys here on purpose: 1-0 stay with the hotbar, the options only react to a click or tap
	player:SetAttribute("DialogueOpen", false)
end

choose = function(index)
	local option = OPTIONS[index]
	if not option or not isOpen then
		return
	end
	playSound(CLICK_SOUND_ID, CLICK_VOLUME)

	if option.Action == "close" then
		closeDialogue()
		return
	end
	if waiting then
		return
	end
	waiting = true
	sellRemote:FireServer(option.Action)
	task.delay(2, function()
		waiting = false
	end)
end

replyRemote.OnClientEvent:Connect(function(ok, message)
	if not isOpen then
		return
	end
	waiting = false
	if not ok then
		playSound(FAIL_SOUND_ID, FAIL_VOLUME)
	end
	speak(message)
end)

-- the numbered lines you can click
for i, option in ipairs(OPTIONS) do
	local line = make("TextButton", textProps({
		Name = "Option" .. i,
		LayoutOrder = 10 + i,
		AutoButtonColor = false,
		Text = string.format('<font color="#ffd45a">></font>   %s', option.Text),
	}), box)
	outline(line)

	line.MouseEnter:Connect(function()
		line.TextColor3 = Color3.fromRGB(255, 235, 150)
	end)
	line.MouseLeave:Connect(function()
		line.TextColor3 = Color3.new(1, 1, 1)
	end)
	line.Activated:Connect(function()
		choose(i)
	end)
end

-- close when you walk away
task.spawn(function()
	while true do
		task.wait(0.5)
		if isOpen and activeRoot then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or (root.Position - activeRoot.Position).Magnitude > CLOSE_DISTANCE then
				closeDialogue()
			end
		end
	end
end)

---------------------------------------------------------------------
-- Talk prompt on the Planet Buyer NPC
---------------------------------------------------------------------
local attachedCount = 0

local function attachToBuyer(npc)
	if not npc:IsA("Model") or npc:GetAttribute("SellAttached") then
		return
	end
	if Players:GetPlayerFromCharacter(npc) then
		return
	end
	npc:SetAttribute("SellAttached", true)

	local root = npc:FindFirstChild("HumanoidRootPart")
		or npc:WaitForChild("HumanoidRootPart", 5)
		or npc:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		warn("SellDialogue: couldn't find a part inside " .. npc:GetFullName())
		return
	end

	-- hide any leftover prompt from the old shop system on this NPC
	for _, descendant in ipairs(npc:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("ShopKind") ~= nil then
			descendant.Enabled = false
		end
	end

	local function talk()
		openDialogue(root)
	end

	local prompt = make("ProximityPrompt", {
		ActionText = "Talk",
		ObjectText = "Planet Buyer",
		HoldDuration = 0,
		MaxActivationDistance = 12,
		RequiresLineOfSight = false,
	}, root)
	prompt.Triggered:Connect(talk)

	local click = make("ClickDetector", { MaxActivationDistance = 14 }, npc)
	click.MouseClick:Connect(talk)

	attachedCount += 1
	print("SellDialogue: attached to " .. npc:GetFullName())
end

local function consider(inst)
	if inst:IsA("Model") and BUYER_NAMES[inst.Name] then
		task.spawn(attachToBuyer, inst)
	elseif inst:IsA("Humanoid") and BUYER_NAMES[inst.DisplayName] and inst.Parent and inst.Parent:IsA("Model") then
		task.spawn(attachToBuyer, inst.Parent)
	end
end

for _, inst in ipairs(workspace:GetDescendants()) do
	consider(inst)
end
workspace.DescendantAdded:Connect(consider)

task.delay(10, function()
	if attachedCount == 0 then
		warn("SellDialogue: found no NPC named PlanetBuyer after 10 seconds. Check BUYER_NAMES at the top of the script.")
	end
end)
