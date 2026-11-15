while true do
	wait(1)
	local money = script.Parent.Parent.Parent:FindFirstChild("TempMoney")
	
	if money then
		money.Value += 5
	end
end