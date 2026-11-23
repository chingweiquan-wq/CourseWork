--!strict
-- RankConfig: ranked tiers shared by server (RankedService) and client (lobby/results UI).
-- Rating (RP) -> tier + division. Each division is DivisionSize RP wide.
-- Bronze..Diamond have 3 divisions (III -> II -> I); Master and Vanguard have none.
local RankConfig = {}

export type Tier = { Id: string, Name: string, Min: number, Color: Color3, Divisions: number, Icon: string }

RankConfig.DivisionSize = 100

RankConfig.Tiers = {
	{ Id = "Bronze",   Name = "BRONZE",   Min = 0,    Color = Color3.fromRGB(214, 133, 74),  Divisions = 3, Icon = "Rank_Bronze" },
	{ Id = "Silver",   Name = "SILVER",   Min = 300,  Color = Color3.fromRGB(200, 212, 230), Divisions = 3, Icon = "Rank_Silver" },
	{ Id = "Gold",     Name = "GOLD",     Min = 600,  Color = Color3.fromRGB(255, 200, 60),  Divisions = 3, Icon = "Rank_Gold" },
	{ Id = "Platinum", Name = "PLATINUM", Min = 900,  Color = Color3.fromRGB(70, 230, 210),  Divisions = 3, Icon = "Rank_Platinum" },
	{ Id = "Diamond",  Name = "DIAMOND",  Min = 1200, Color = Color3.fromRGB(90, 160, 255),  Divisions = 3, Icon = "Rank_Diamond" },
	{ Id = "Master",   Name = "MASTER",   Min = 1500, Color = Color3.fromRGB(180, 90, 255),  Divisions = 1, Icon = "Rank_Master" },
	{ Id = "Vanguard", Name = "VANGUARD", Min = 1800, Color = Color3.fromRGB(255, 60, 70),   Divisions = 1, Icon = "Rank_Vanguard" },
} :: { Tier }

local ROMAN = { "I", "II", "III", "IV", "V" }

export type RankInfo = {
	Tier: Tier,
	Division: number?, -- 3 = lowest, 1 = highest; nil for tiers without divisions
	Name: string,      -- e.g. "GOLD II"
	Progress: number,  -- 0..1 inside the current division (1 for the top tier)
	NextAt: number?,   -- RP needed for the next division / tier
}

function RankConfig.Get(rating: number): RankInfo
	rating = math.max(0, math.floor(rating))
	local tiers = RankConfig.Tiers
	local idx = 1
	for i, t in ipairs(tiers) do
		if rating >= t.Min then idx = i end
	end
	local tier = tiers[idx]
	local nextTier = tiers[idx + 1]
	if tier.Divisions <= 1 then
		local top = nextTier and nextTier.Min or nil
		local progress = top and (rating - tier.Min) / (top - tier.Min) or 1
		return { Tier = tier, Division = nil, Name = tier.Name, Progress = math.clamp(progress, 0, 1), NextAt = top }
	end
	local step = math.floor((rating - tier.Min) / RankConfig.DivisionSize)
	step = math.clamp(step, 0, tier.Divisions - 1)
	local division = tier.Divisions - step
	local divMin = tier.Min + step * RankConfig.DivisionSize
	return {
		Tier = tier,
		Division = division,
		Name = tier.Name .. " " .. ROMAN[division],
		Progress = math.clamp((rating - divMin) / RankConfig.DivisionSize, 0, 1),
		NextAt = divMin + RankConfig.DivisionSize,
	}
end

return RankConfig
