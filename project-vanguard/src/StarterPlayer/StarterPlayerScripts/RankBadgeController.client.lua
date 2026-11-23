-- RankBadgeController: 3D rank badges out in the lobby world, built locally on each client.
--  * Head tags: badge + rank name over every player's head (hidden while that player is in a match).
--  * Leaderboard sign: a badge on each row of the TOP RANKED board (the server only sets a Tier attribute per row).
-- ViewportFrames only draw inside GUIs that live in PlayerGui, so both use PlayerGui + Adornee.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local RankConfig = require(Modules:WaitForChild("RankConfig"))
local RankBadge = require(Modules:WaitForChild("RankBadge"))

---------------------------------------------------------------- head tags
local tags: { [Player]: BillboardGui } = {}

local function removeTag(p: Player)
	local bb = tags[p]
	if bb then
		tags[p] = nil
		bb:Destroy()
	end
end

local function buildTag(p: Player, char: Model)
	removeTag(p)
	local head = char:WaitForChild("Head", 10) :: BasePart?
	if not head or char.Parent == nil then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "RankTag_" .. p.UserId
	bb.ResetOnSpawn = false -- lifetime is managed here
	bb.Adornee = head
	bb.Size = UDim2.fromScale(4.4, 1.25) -- in studs
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	bb.Enabled = false
	local view = RankBadge.Viewport({ Parent = bb, Name = "Badge", Size = UDim2.fromScale(0.3, 1) })
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.fromScale(0.68, 0.62)
	label.Position = UDim2.fromScale(0.31, 0.19)
	label.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = bb
	bb.Parent = playerGui
	tags[p] = bb

	local function refresh()
		local rating = p:GetAttribute("Rating")
		if typeof(rating) ~= "number" or p:GetAttribute("MatchId") ~= nil then
			bb.Enabled = false
			return
		end
		local info = RankConfig.Get(rating)
		view.Set(info.Tier.Id)
		label.Text = info.Name
		label.TextColor3 = info.Tier.Color
		bb.Enabled = true
	end
	local c1 = p:GetAttributeChangedSignal("Rating"):Connect(refresh)
	local c2 = p:GetAttributeChangedSignal("MatchId"):Connect(refresh)
	bb.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
	refresh()
end

local function watch(p: Player)
	p.CharacterAdded:Connect(function(char) buildTag(p, char) end)
	p.CharacterRemoving:Connect(function() removeTag(p) end)
	if p.Character then task.spawn(buildTag, p, p.Character) end
end

for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(removeTag)

---------------------------------------------------------------- leaderboard sign badges
task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby")
	local sign: BasePart? = nil
	while not sign do
		sign = lobby:FindFirstChild("RankedBoard", true) :: BasePart?
		if not sign then task.wait(1) end
	end
	local serverGui = (sign :: BasePart):WaitForChild("BoardGui") :: SurfaceGui
	local rows: Instance? = nil
	while not rows do
		rows = serverGui:FindFirstChild("Rows", true)
		if not rows then task.wait(0.5) end
	end
	-- an overlay SurfaceGui on the same face, in the same pixel space, drawn just in front
	local overlay = Instance.new("SurfaceGui")
	overlay.Name = "RankedBoardBadges"
	overlay.ResetOnSpawn = false
	overlay.Adornee = sign
	overlay.Face = serverGui.Face
	overlay.SizingMode = serverGui.SizingMode
	overlay.PixelsPerStud = serverGui.PixelsPerStud
	overlay.LightInfluence = 0
	overlay.ZOffset = 1
	overlay.Parent = playerGui
	for i = 1, 10 do
		local row = (rows :: Instance):WaitForChild("Row" .. i) :: GuiObject
		local view = RankBadge.Viewport({ Parent = overlay, Name = "Badge" .. i })
		local function place()
			local origin = serverGui.AbsolutePosition
			local pos, size = row.AbsolutePosition - origin, row.AbsoluteSize
			view.Frame.Size = UDim2.fromOffset(size.Y * 1.2, size.Y * 1.2)
			view.Frame.Position = UDim2.fromOffset(pos.X + size.X * 0.62, pos.Y - size.Y * 0.1)
		end
		local function update()
			local tier = row:GetAttribute("Tier")
			view.Set(typeof(tier) == "string" and tier or nil)
		end
		row:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		row:GetAttributeChangedSignal("Tier"):Connect(update)
		place()
		update()
	end
end)
