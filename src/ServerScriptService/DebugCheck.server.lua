--[[
	DebugCheck  (Script)
	Put in: ServerScriptService   (new Script, name it exactly: DebugCheck)

	TEMPORARY. Press Play, wait about 25 seconds, then it prints a report in the Output window
	starting with "===== DEBUGCHECK". Copy everything from that line down and send it to me.
	Delete this script afterwards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function report(title)
	print("===== DEBUGCHECK (" .. title .. ") =====")

	print("-- ServerScriptService:")
	for _, child in ipairs(ServerScriptService:GetChildren()) do
		local extra = ""
		if child:IsA("BaseScript") then
			extra = child.Enabled and " (enabled)" or " (DISABLED!)"
		end
		print("   " .. child.Name .. "  [" .. child.ClassName .. "]" .. extra)
	end

	print("-- ReplicatedStorage:")
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		print("   " .. child.Name .. "  [" .. child.ClassName .. "]")
	end

	local folder = workspace:FindFirstChild("PlantedPlanets")
	print("-- workspace.PlantedPlanets: " .. (folder and (#folder:GetChildren() .. " planets") or "MISSING"))
	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			print(string.format("   %s  owner=%s  mutation=%s  at %s", model.Name, tostring(model:GetAttribute("Owner")),
				tostring(model:GetAttribute("Mutation")), tostring(model:GetPivot().Position)))
		end
	end

	local okData, GameData = pcall(function()
		return require(ServerScriptService:FindFirstChild("GameData"))
	end)
	print("-- GameData loads: " .. tostring(okData) .. (okData and "" or ("  ERROR: " .. tostring(GameData))))

	local okBase, BaseService = pcall(function()
		return require(ServerScriptService:FindFirstChild("BaseService"))
	end)
	print("-- BaseService loads: " .. tostring(okBase) .. (okBase and "" or ("  ERROR: " .. tostring(BaseService))))

	for _, player in ipairs(Players:GetPlayers()) do
		local data = okData and GameData.Get(player)
		if data then
			print(string.format("-- %s: coins=%s  saved plants=%d  harvested planets=%d  saved base=%s", player.Name,
				tostring(data.Coins), #data.Plants, #data.Planets, data.Base and "yes" or "NO"))
			for i, entry in ipairs(data.Plants) do
				print(string.format("   plant %d: %s at (%.0f, %.0f, %.0f) mut=%s", i, tostring(entry.Id),
					entry.X or 0, entry.Y or 0, entry.Z or 0, tostring(entry.Mut)))
			end
		else
			print("-- " .. player.Name .. ": GameData has NOT loaded for this player")
		end
		if okBase then
			local base = BaseService.BaseOf(player)
			print("-- " .. player.Name .. " base: " .. (base and ("yes, centre " .. tostring(base.Center)) or "NONE"))
		end
	end
	print("===== END DEBUGCHECK =====")
end

task.delay(25, report, "25 seconds in")
task.delay(70, report, "70 seconds in")
