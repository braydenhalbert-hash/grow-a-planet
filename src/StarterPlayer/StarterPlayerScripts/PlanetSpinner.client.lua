--[[
	PlanetSpinner  (LocalScript)  -- REPLACES the earlier PlanetSpinner
	Put in: StarterPlayer > StarterPlayerScripts

	Makes the planets come alive on your screen:
	  * moons and orbiting rocks go around their planet
	  * continents, clouds and storms turn with the planet
	  * every ring spins, inner rings faster than outer ones
	  * a black hole's glowing halo always faces your camera

	Everything is driven by the SERVER clock, so every player sees the moons and rocks in the
	same place at the same moment (and the server can tell where a piece is when you collect it).

	This version keeps looking: parts of a planet that arrive late (which happens on a real
	server with real players) get picked up within a second, and anything that goes away is dropped.
	It only animates planets near you, so it stays smooth.

	Works on any model made by PlanetBuilder (they're tagged "SpinningPlanet").
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "SpinningPlanet"
local RENDER_DISTANCE = 220   -- planets farther than this stand still
local RESCAN_SECONDS = 1      -- how often to look for parts that arrived late
local TAU = math.pi * 2

local tracked = {}
local pending = {}

-- Look for moons / rocks / rings / halos that have arrived since the last look,
-- and forget the ones that are gone.
local function scan(model, info)
	local baseCFrame = info.Body.CFrame * info.Tilt
	local bodySize = info.Body.Size.X

	for i = #info.Parts, 1, -1 do
		local item = info.Parts[i]
		if not item.Part:IsDescendantOf(model) then
			info.Known[item.Part] = nil
			table.remove(info.Parts, i)
		end
	end
	for i = #info.Frames, 1, -1 do
		local item = info.Frames[i]
		if not item.Frame:IsDescendantOf(model) then
			info.Known[item.Frame] = nil
			table.remove(info.Frames, i)
		end
	end
	for i = #info.Facers, 1, -1 do
		local part = info.Facers[i]
		if not part:IsDescendantOf(model) then
			info.Known[part] = nil
			table.remove(info.Facers, i)
		end
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if not info.Known[descendant] then
			if descendant:IsA("BasePart") then
				local speed = descendant:GetAttribute("SpinSpeed")
				if speed and speed ~= 0 then
					-- remember where this part sits, relative to the planet's tilted axis
					local relative = baseCFrame:ToObjectSpace(descendant.CFrame)
					table.insert(info.Parts, {
						Part = descendant,
						Speed = speed,
						Unit = relative.Position / bodySize,
						Rotation = relative - relative.Position,
					})
					info.Known[descendant] = true
				elseif descendant:GetAttribute("FaceCamera") then
					table.insert(info.Facers, descendant)
					info.Known[descendant] = true
				end
			elseif descendant:IsA("GuiObject") then
				local speed = descendant:GetAttribute("SpinSpeed")
				if speed and speed ~= 0 then
					table.insert(info.Frames, {
						Frame = descendant,
						Speed = speed,
						Phase = descendant:GetAttribute("SpinPhase") or 0,
					})
					info.Known[descendant] = true
				end
			end
		end
	end
end

local function register(model)
	if tracked[model] or pending[model] or not model:IsA("Model") then
		return
	end
	pending[model] = true

	task.spawn(function()
		local body = model:WaitForChild("Body", 10)
		if body then
			task.wait() -- a moment for the rest of the model to arrive (scan() keeps checking after this)
		end

		if body and model.Parent then
			local info = {
				Body = body,
				Tilt = CFrame.Angles(0, 0, math.rad(model:GetAttribute("Tilt") or 0)),
				Parts = {},
				Frames = {},
				Facers = {},
				Known = {},
				LastScan = os.clock(),
			}
			scan(model, info)
			tracked[model] = info
		end

		pending[model] = nil
	end)
end

for _, model in ipairs(CollectionService:GetTagged(TAG)) do
	register(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
	tracked[model] = nil
end)

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local serverTime = workspace:GetServerTimeNow()
	local clock = os.clock()

	for model, info in pairs(tracked) do
		local body = info.Body
		if not body.Parent then
			tracked[model] = nil
		elseif (body.Position - cameraPosition).Magnitude < RENDER_DISTANCE then
			if clock - info.LastScan > RESCAN_SECONDS then
				info.LastScan = clock
				scan(model, info)
			end

			local baseCFrame = body.CFrame * info.Tilt
			local bodySize = body.Size.X -- planets grow, so positions are scaled to the current size
			local parts, cframes = {}, {}

			for _, spinner in ipairs(info.Parts) do
				if spinner.Part.Parent then
					table.insert(parts, spinner.Part)
					table.insert(
						cframes,
						baseCFrame
							* CFrame.Angles(0, (spinner.Speed * serverTime) % TAU, 0)
							* (CFrame.new(spinner.Unit * bodySize) * spinner.Rotation)
					)
				end
			end

			for _, facer in ipairs(info.Facers) do
				if facer.Parent then
					table.insert(parts, facer)
					table.insert(cframes, CFrame.lookAt(body.Position, cameraPosition))
				end
			end

			for _, ringFrame in ipairs(info.Frames) do
				ringFrame.Frame.Rotation = (ringFrame.Speed * serverTime + ringFrame.Phase) % 360
			end

			if #parts > 0 then
				local ok = pcall(function()
					workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
				end)
				if not ok then
					-- if one part is the problem, don't let it stop the others
					for i, part in ipairs(parts) do
						pcall(function()
							part.CFrame = cframes[i]
						end)
					end
				end
			end
		end
	end
end)
