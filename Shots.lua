local ADDON, ns = ...

local shots = {
	average = nil,
	lastRead = 0,
}
ns.shots = shots

function ns.UpdateAverageShot(now)
	if now - shots.lastRead < 2 then
		return
	end
	shots.lastRead = now
	if ns.InCombat() then
		return
	end
	if type(UnitRangedDamage) ~= "function" then
		return
	end

	local ok, minDamage, maxDamage, posBuff, negBuff, percent = pcall(UnitRangedDamage, "player")
	if not ok then
		return
	end

	local low = ns.PlainNumber(minDamage)
	local high = ns.PlainNumber(maxDamage)
	local positive = ns.PlainNumber(posBuff)
	local negative = ns.PlainNumber(negBuff)
	local scale = ns.PlainNumber(percent)
	if not (low and high and positive and negative and scale) then
		return
	end

	local average = (low + high) / 2
	if average > 0 then
		shots.average = average
	end
end

function ns.AverageShot()
	return shots.average
end

function ns.ShotsToKill()
	local average = shots.average
	if not average or average <= 0 then
		return nil
	end
	local okHealth, health = ns.SafeCall(UnitHealth, "target")
	local okMax, maxHealth = ns.SafeCall(UnitHealthMax, "target")
	local current = okHealth and ns.PlainNumber(health) or nil
	local maximum = okMax and ns.PlainNumber(maxHealth) or nil
	if not current or not maximum then
		return nil
	end
	if current <= 0 or maximum == 100 then
		return nil
	end
	return math.ceil(current / average)
end

function ns.ReportProbe()
	ns.Print("Shots to kill (run this mid-fight):")
	ns.PrintLine("in combat = " .. ns.DescribeCall(UnitAffectingCombat, "player"))
	ns.PrintLine("target health = " .. ns.DescribeCall(UnitHealth, "target"))
	ns.PrintLine("target max health = " .. ns.DescribeCall(UnitHealthMax, "target"))
	ns.PrintLine("UnitHealthPercent exists = " .. tostring(type(_G.UnitHealthPercent) == "function"))
	ns.PrintLine("C_CurveUtil exists = " .. tostring(type(_G.C_CurveUtil) == "table"))
	ns.PrintLine("ranged min damage = " .. ns.DescribeCall(UnitRangedDamage, "player"))
	local average = shots.average
	ns.PrintLine("average shot (cached) = " .. (average and string.format("%.1f", average) or "none yet"))
	local kills = ns.ShotsToKill()
	ns.PrintLine("shots to kill = " .. tostring(kills))
end
