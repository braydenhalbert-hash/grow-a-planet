-- Purges the gray 2x1x2 drop blocks spawned by the cloud Tycoon gameManager
-- script (cloud_7790271034), which cannot be edited from the hierarchy.
-- Only destroys loose, unanchored, childless-looking "Part" blocks that match
-- the dropper fingerprint exactly, so garden/shop/NPC builds are never touched.

local Workspace = game:GetService("Workspace")

local BLOCK_SIZE = Vector3.new(2, 1, 2)
local BLOCK_COLOR = Color3.fromRGB(163, 162, 165)

local function isDroppedBlock(inst)
	if not inst:IsA("Part") then return false end
	if inst.Parent ~= Workspace then return false end
	if inst.Name ~= "Part" then return false end
	if inst.Anchored then return false end
	if inst.Size ~= BLOCK_SIZE then return false end
	if (inst.Color - BLOCK_COLOR).Magnitude > 2 then return false end
	for _, child in ipairs(inst:GetDescendants()) do
		if child:IsA("Script") or child:IsA("LocalScript") then return false end
	end
	return true
end

local function purge()
	local removed = 0
	for _, inst in ipairs(Workspace:GetChildren()) do
		if isDroppedBlock(inst) then
			inst:Destroy()
			removed += 1
		end
	end
	if removed > 0 then
		print(("[BlockJanitor] Removed %d dropped block(s)"):format(removed))
	end
end

purge()

task.spawn(function()
	while true do
		task.wait(1)
		purge()
	end
end)

print("[BlockJanitor] Ready - watching for dropped blocks")
