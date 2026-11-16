--[[
	SellDialogue  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	Talking to the Planet Buyer, Grow a Garden style:
	  * Walk up: a white outline appears around him and the "Talk" prompt shows.
	  * Talk: the background softly blurs and the camera leans in. He types
	    "Got anything to sell?" above his head, then your choices type out next to him:

	       #1 ["I want to sell my inventory"]
	       #2 ["I want to sell this"]
	       #3 ["How much is this worth?"]
	       #4 ["Nevermind"]

	  * Click / tap a choice (it slides over when you point at it). Your character says it,
	    then he answers above his head. Walk away or pick Nevermind to finish.
	("I want to sell this" and "How much is this worth?" use the planet in your hand.)
	The number keys stay with your hotbar so you can switch planets while talking.

	Needs: SellServer (ServerScriptService), ReplicatedStorage > NpcTalk.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NpcTalk = require(ReplicatedStorage:WaitForChild("NpcTalk"))

local remotes = ReplicatedStorage:WaitForChild("PlanetRemotes")
local sellRemote = remotes:WaitForChild("SellRequest")
local replyRemote = remotes:WaitForChild("SellReply")

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local BUYER_NAMES = { PlanetBuyer = true } -- model name or Humanoid display name of the buyer NPC
local CLOSE_DISTANCE = 18                  -- the talk ends if you walk this far away

local FONT = Enum.Font.FredokaOne
local GREETING = "Got anything to sell?"
local GOODBYE = "Come back anytime!"
local TYPE_SPEED = 0.012 -- seconds per letter for the choices (smaller = faster)

-- where the choices float: to the right of the buyer (in studs) and a bit below his head
local CHOICES_OFFSET = Vector3.new(4.5, -0.8, 0)

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
-- The floating choices
---------------------------------------------------------------------
local choicesGui = Instance.new("BillboardGui")
choicesGui.Name = "SellChoices"
choicesGui.StudsOffset = CHOICES_OFFSET -- camera-relative: always to the right on screen
choicesGui.AlwaysOnTop = true           -- stays sharp over the blurred background
choicesGui.LightInfluence = 0
choicesGui.MaxDistance = 60
choicesGui.Active = true
choicesGui.ResetOnSpawn = false
choicesGui.Enabled = false
choicesGui.Parent = playerGui

-- fixed size on screen (smaller on phones)
local function sizeChoices()
	local textSize = NpcTalk.TextSize()
	choicesGui.Size = UDim2.fromOffset(textSize * 17, (textSize + 8) * 4)
	return textSize
end

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = choicesGui

local function optionText(i, hovered)
	-- pointing at a choice slides it over a little, like in Grow a Garden
	return string.format('#%d%s["%s"]', i, hovered and "    " or " ", OPTIONS[i].Text)
end

local lines = {}
for i in ipairs(OPTIONS) do
	local line = Instance.new("TextButton")
	line.Name = "Option" .. i
	line.LayoutOrder = i
	line.Size = UDim2.new(1, 0, 1 / #OPTIONS, 0)
	line.BackgroundTransparency = 1
	line.AutoButtonColor = false
	line.Font = FONT
	line.TextSize = 20
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = Color3.new(1, 1, 1)
	line.Text = optionText(i, false)
	line.Parent = choicesGui
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(25, 20, 30)
	outline.Thickness = 1.6
	outline.Parent = line
	lines[i] = line
end

---------------------------------------------------------------------
-- Talking
---------------------------------------------------------------------
local isOpen = false
local waiting = false
local activeRoot, activeHead = nil, nil
local activePrompt = nil
local session = 0
local hovered = nil

local function myHead()
	return NpcTalk.HeadOf(player.Character)
end

-- types the choices out one after another
local function showChoices(id)
	choicesGui.Adornee = activeRoot
	local textSize = sizeChoices()
	for _, line in ipairs(lines) do
		line.TextSize = textSize
	end
	choicesGui.Enabled = true
	hovered = nil
	for i, line in ipairs(lines) do
		line.Text = optionText(i, false)
		line.MaxVisibleGraphemes = 0
	end
	for _, line in ipairs(lines) do
		local total = utf8.len(line.Text) or #line.Text
		for n = 1, total do
			if session ~= id or not choicesGui.Enabled then
				return
			end
			line.MaxVisibleGraphemes = n
			NpcTalk.TypeSound(n, string.sub(line.Text, n, n))
			task.wait(TYPE_SPEED)
		end
		line.MaxVisibleGraphemes = -1
	end
end

local function hideChoices()
	choicesGui.Enabled = false
end

local function closeDialogue()
	if not isOpen then
		return
	end
	isOpen = false
	waiting = false
	session += 1
	hideChoices()
	activeRoot, activeHead = nil, nil
	if activePrompt then
		activePrompt.Enabled = true -- the Talk prompt comes back
		activePrompt = nil
	end
	NpcTalk.Unfocus("talk")
	player:SetAttribute("DialogueOpen", false)
end

local function openDialogue(npc, root, prompt)
	if isOpen then
		return
	end
	activePrompt = prompt
	if prompt then
		prompt.Enabled = false -- no "Talk" prompt while you're already talking
	end
	isOpen = true
	waiting = false
	session += 1
	local id = session
	activeRoot = root
	activeHead = NpcTalk.HeadOf(npc)
	NpcTalk.Focus("talk")
	-- the number keys stay with the hotbar; choices react to a click or tap
	player:SetAttribute("DialogueOpen", false)
	local typing = NpcTalk.Say(activeHead, GREETING, 2.5)
	task.delay(typing + 0.15, function()
		if session == id then
			showChoices(id)
		end
	end)
end

local function choose(index)
	local option = OPTIONS[index]
	if not option or not isOpen or waiting then
		return
	end
	playSound(CLICK_SOUND_ID, CLICK_VOLUME)
	hideChoices()
	session += 1
	local id = session

	-- your character says the line first
	local head = myHead()
	local typing = head and NpcTalk.Say(head, option.Text, 2.5) or 0

	if option.Action == "close" then
		task.delay(typing + 0.3, function()
			if session ~= id then
				return
			end
			if activeHead then
				NpcTalk.Say(activeHead, GOODBYE, 2)
			end
			closeDialogue()
		end)
		return
	end

	waiting = true
	task.delay(typing + 0.2, function()
		if session == id and isOpen then
			sellRemote:FireServer(option.Action)
		end
	end)
	task.delay(typing + 3, function()
		-- no answer came back: let them pick again
		if session == id and waiting then
			waiting = false
			showChoices(id)
		end
	end)
end

replyRemote.OnClientEvent:Connect(function(ok, message)
	if not isOpen or not activeHead then
		return
	end
	waiting = false
	if not ok then
		playSound(FAIL_SOUND_ID, FAIL_VOLUME)
	end
	session += 1
	local id = session
	local head = myHead()
	if head then
		NpcTalk.Clear(head) -- your line goes away when he answers, so they never overlap
	end
	local typing = NpcTalk.Say(activeHead, message, 3)
	-- after he answers, the choices come back so you can keep selling
	task.delay(typing + 0.6, function()
		if session == id and isOpen then
			showChoices(id)
		end
	end)
end)

for i, line in ipairs(lines) do
	line.MouseEnter:Connect(function()
		hovered = i
		local shown = line.MaxVisibleGraphemes
		line.Text = optionText(i, true)
		if shown ~= -1 then
			line.MaxVisibleGraphemes = shown
		end
	end)
	line.MouseLeave:Connect(function()
		if hovered == i then
			hovered = nil
		end
		local shown = line.MaxVisibleGraphemes
		line.Text = optionText(i, false)
		if shown ~= -1 then
			line.MaxVisibleGraphemes = shown
		end
	end)
	line.Activated:Connect(function()
		choose(i)
	end)
end

-- the talk ends when you walk away
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
-- Talk prompt (and white outline) on the Planet Buyer NPC
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

	local prompt
	local function talk()
		openDialogue(npc, root, prompt)
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Planet Buyer"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(talk)
	NpcTalk.OutlineWhenNear(npc, prompt)

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 14
	click.Parent = npc
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
