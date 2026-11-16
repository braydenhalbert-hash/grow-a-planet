--[[
	SellServer  (Script, NOT a LocalScript)
	Put in: ServerScriptService

	Lets players sell harvested planets to the Planet Buyer:
	  "all"       sell every planet you're holding
	  "held"      sell the planet in your hand
	  "appraise"  just tell you what the planet in your hand is worth

	A planet's price is its SellValue from PlanetCatalog, scaled by its weight
	(heavier than average = worth more).

	The player has to be standing near an NPC named in BUYER_NAMES.

	Needs: GameData (same folder), PlanetCatalog (ReplicatedStorage).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(script.Parent:WaitForChild("GameData"))
local LiveOps = require(script.Parent:WaitForChild("LiveOps"))

-- Friend Boost (FriendBoost script): +10% per friend in the server, e.g. 20 -> x1.2
local function friendMultiplier(player)
	return 1 + (player:GetAttribute("FriendBoost") or 0) / 100
end
local PlanetCatalog = require(ReplicatedStorage:WaitForChild("PlanetCatalog"))

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local BUYER_NAMES = { PlanetBuyer = true } -- model name or Humanoid display name of the buyer NPC
local MAX_SELL_DISTANCE = 30
local COOLDOWN = 0.3

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("PlanetRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "PlanetRemotes"
	remotes.Parent = ReplicatedStorage
end

local function getRemote(name)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end

local sellRemote = getRemote("SellRequest") -- client -> server: "all" | "held" | "appraise"
local replyRemote = getRemote("SellReply")  -- server -> client: (ok, message)
local audioCueRemote = getRemote("AudioCue") -- server -> client: sound cues (AudioManager plays them)

local function reply(player, ok, text)
	replyRemote:FireClient(player, ok, text)
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function commas(n)
	local s = tostring(math.floor(n))
	local formatted = s
	repeat
		s = formatted
		formatted = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until formatted == s
	return formatted
end

local function gold(amount)
	return '<font color="#ffe16e">' .. commas(amount) .. "¢</font>"
end

-- find the buyer NPC(s) so we can check the player is standing next to one
local buyers = {} -- model -> root part

local function registerBuyer(model)
	if not model:IsA("Model") or buyers[model] then
		return
	end
	if Players:GetPlayerFromCharacter(model) then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if BUYER_NAMES[model.Name] or (humanoid and BUYER_NAMES[humanoid.DisplayName]) then
		local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
		if root then
			buyers[model] = root
		end
	end
end

for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("Model") then
		registerBuyer(inst)
	end
end

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") then
		task.defer(registerBuyer, inst)
	elseif inst:IsA("Humanoid") and inst.Parent then
		task.defer(registerBuyer, inst.Parent)
	end
end)

task.delay(5, function()
	if next(buyers) == nil then
		warn("[SellServer] Couldn't find an NPC named PlanetBuyer, so the distance check is OFF. "
			.. "Fix the name in BUYER_NAMES at the top of SellServer.")
	end
end)

local function nearBuyer(player)
	if next(buyers) == nil then
		return true -- no buyer found (see the warning above)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for model, part in pairs(buyers) do
		if part.Parent then
			if (part.Position - root.Position).Magnitude <= MAX_SELL_DISTANCE then
				return true
			end
		else
			buyers[model] = nil
		end
	end
	return false
end

local function heldPlanetTool(player)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("Kind") == "Planet" then
		return tool
	end
	return nil
end

-- index of this planet in the saved list (matched by planet and weight)
local function findOwned(data, planetId, weight)
	for index, owned in ipairs(data.Planets) do
		if owned.Id == planetId and type(owned.Weight) == "number" and math.abs(owned.Weight - weight) < 0.001 then
			return index
		end
	end
	return nil
end

local function destroyPlanetTools(player)
	local containers = {}
	if player:FindFirstChild("Backpack") then
		table.insert(containers, player.Backpack)
	end
	if player.Character then
		table.insert(containers, player.Character)
	end
	for _, container in ipairs(containers) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("Kind") == "Planet" then
				child:Destroy()
			end
		end
	end
end

---------------------------------------------------------------------
-- Selling
---------------------------------------------------------------------
local lastRequest = {}

sellRemote.OnServerEvent:Connect(function(player, action)
	if typeof(action) ~= "string" then
		return
	end

	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < COOLDOWN then
		return
	end
	lastRequest[player] = now

	local data = GameData.Get(player)
	if not data then
		reply(player, false, "Give me a second, your things are still loading.")
		return
	end

	if not nearBuyer(player) then
		reply(player, false, "Come a bit closer so I can see what you've got.")
		return
	end

	if action == "all" then
		local count, total = 0, 0
		for _, owned in ipairs(data.Planets) do
			local planet = PlanetCatalog.Get(owned.Id)
			if planet and type(owned.Weight) == "number" then
				count += 1
				total += PlanetCatalog.SellValueFor(planet, owned.Weight, owned.Mut)
			end
		end

		if count == 0 then
			reply(player, false, "You don't have any planets to sell.")
			return
		end

		total = math.floor(total * LiveOps.Get("Coins") * friendMultiplier(player) + 0.5) -- admin coin multiplier + Friend Boost
		table.clear(data.Planets)
		destroyPlanetTools(player)
		GameData.AddCoins(player, total)
		reply(player, true, string.format("Sold %d planet%s for %s!", count, count == 1 and "" or "s", gold(total)))
		audioCueRemote:FireClient(player, "sell", count, total)

	elseif action == "held" or action == "appraise" then
		local tool = heldPlanetTool(player)
		if not tool then
			reply(player, false, "Hold the planet you want me to look at first.")
			return
		end

		local planet = PlanetCatalog.Get(tool:GetAttribute("PlanetId"))
		local weight = tool:GetAttribute("Weight")
		if not planet or type(weight) ~= "number" then
			reply(player, false, "Hmm, I can't tell what that is.")
			return
		end

		local value = math.floor(PlanetCatalog.SellValueFor(planet, weight, tool:GetAttribute("Mutations")) * LiveOps.Get("Coins") * friendMultiplier(player) + 0.5)

		if action == "appraise" then
			reply(player, true, string.format("I'd value your %.2f kg %s at %s.", weight, planet.Name, gold(value)))
			return
		end

		local index = findOwned(data, planet.Id, weight)
		if not index then
			reply(player, false, "Hmm, that one doesn't look right to me.")
			return
		end

		table.remove(data.Planets, index)
		tool:Destroy()
		GameData.AddCoins(player, value)
		reply(player, true, string.format("Sold your %.2f kg %s for %s!", weight, planet.Name, gold(value)))
		audioCueRemote:FireClient(player, "sell", 1, value)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

print("[SellServer] Ready")
