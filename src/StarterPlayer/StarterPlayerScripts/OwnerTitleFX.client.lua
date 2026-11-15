--[[
	OwnerTitleFX  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts   (new LocalScript, name it exactly: OwnerTitleFX)

	Makes the OWNER title above your head shimmer and float gently (everyone sees it move).
	Without this script the title still shows, it just doesn't move.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for _, gui in ipairs(CollectionService:GetTagged("OwnerTitle")) do
		local text = gui:FindFirstChildOfClass("TextLabel")
		local shine = text and text:FindFirstChild("Shine")
		if shine then
			shine.Offset = Vector2.new(math.sin(now * 1.6) * 0.5, 0)
		end
		gui.StudsOffset = Vector3.new(0, 3.5 + math.sin(now * 2) * 0.12, 0)
	end
end)
