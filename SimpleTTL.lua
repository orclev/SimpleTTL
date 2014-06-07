-----------------------------------------------------------------------------------------------
-- Client Lua Script for SimpleTTL
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
 
-----------------------------------------------------------------------------------------------
-- SimpleTTL Module Definition
-----------------------------------------------------------------------------------------------
local SimpleTTL = {}
local NAME = "SimpleTTL"
local RESTED_MULT = 1.5
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function SimpleTTL:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	o.t0 = os.time() -- init with start time
	o.t = 0
	o.cmaClassXp = 0
	o.classXp = 0
	o.cmaQuestXp = 0
	o.cmaQuests = 0
	o.questXp = 0
	o.quests = 0
	o.totalQuests = 0
	o.cmaXpPerKill = 0
	o.killXp = 0
	o.kills = 0
	o.cmaKills = 0
	o.totalKills = 0
	o.cmaPathXp = 0
	o.pathXp = 0
	o.elder = false
    return o
end

function SimpleTTL:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- SimpleTTL OnLoad
-----------------------------------------------------------------------------------------------
function SimpleTTL:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("SimpleTTL.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- SimpleTTL OnDocLoaded
-----------------------------------------------------------------------------------------------
function SimpleTTL:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "SimpleTTLForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)

		self.timer = ApolloTimer.Create(10.0, true, "OnTimer", self)
		self.timer2 = ApolloTimer.Create(1.0, true, "OnTimer2", self)

		-- Do additional Addon initialization here
		Apollo.RegisterEventHandler("ExperienceGained", "OnExperienceGained", self)
		Apollo.RegisterEventHandler("ElderPointsGained", "OnElderPointsGained", self)
		Apollo.RegisterEventHandler("UpdatePathXp", "OnPathExperienceGained", self)
		Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
		Apollo.RegisterEventHandler("STTLMenuClicked", "ToggleWindow", self)
	end
end

function SimpleTTL:ToggleWindow()
	self.wndMain:Show(not self.wndMain:IsVisible(), false)
end

function SimpleTTL:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn", NAME, {"STTLMenuClicked", "", nil})
end

function SimpleTTL:OnExperienceGained(eReason, unitTarget, strText, fDelay, nAmount)
	if eReason == CombatFloater.CodeEnumExpReason.KillPerformance 
		or eReason == CombatFloater.CodeEnumExpReason.MultiKill 
		or eReason == CombatFloater.CodeEnumExpReason.KillingSpree then
		self.classXp = self.classXp + nAmount
	elseif eReason == CombatFloater.CodeEnumExpReason.KillCreature then
		self.killXp = self.killXp + nAmount
		self.kills = self.kills + 1
	elseif eReason == CombatFloater.CodeEnumExpReason.Quest or eReason == CombatFloater.CodeEnumExpReason.DailyQuest then
		-- self.classXp = self.classXp + nAmount -- TODO: Remove this
		self.questXp = self.questXp + nAmount
		self.quests = self.quests + 1
	elseif eReason == CombatFloater.CodeEnumExpReason.Rested then
		return -- Don't care
	else
		self.classXp = self.classXp + nAmount
	end
end

function SimpleTTL:OnElderPointsGained(nAmount)
	o.elder = true
	self.classXp = self.classXp + nAmount
end

function SimpleTTL:OnPathExperienceGained(nAmount, strText)
	self.pathXp = self.pathXp + nAmount
end

-----------------------------------------------------------------------------------------------
-- SimpleTTL Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on timer
function SimpleTTL:OnTimer()
	self:RollUpAverages()
end

function SimpleTTL:OnTimer2()
	local killsNeeded = self:KillsToLevel()
	local questsToLevel = self:QuestsToLevel()
	local timeToLevel = self:TimeToLevel()
	local strKills = ''
	local strTime = ''
	local strStat = ''
	local strQuests = ''
	if questsToLevel ~= -1 then
		strQuests = string.format('Quests Needed: %d', questsToLevel)
	else
		strQuests = 'Quests Needed: N/A'
	end
	if killsNeeded ~= -1 then
		strKills = string.format('Kills Needed: %d', killsNeeded)
	else
		strKills = 'Kills Needed: N/A'
	end
	if timeToLevel ~= -1 then
		local time = self.DeltaToTime(math.max(0, timeToLevel - self:cmaDelta()))
		strTime = string.format('Time to Level: %d days %d hour %d minutes %d seconds'
			, time.days, time.hours, time.minutes, time.seconds)
	else
		strTime = 'Time to Level: N/A'
	end
	if GetRestXp() > 0 then
		strStat = string.format('Average XP per kill (rested): %d\nAverage XP/s: %.2f'
			, math.floor(self.cmaXpPerKill * RESTED_MULT)
			, self:AvgClassXPPerSecond())
	else
		strStat = string.format('Average XP per kill: %d\nAverage XP/s: %.2f'
			, math.floor(self.cmaXpPerKill)
			, self:AvgClassXPPerSecond())
	end
	local combined = strTime .. '\n' .. strQuests .. '\n' .. strKills .. '\n' .. strStat
	self.UpdateMenuList(combined, killsNeeded)
	local label = self.wndMain:FindChild("Label")
	label:SetText(combined)
end

function SimpleTTL:AvgClassXPPerSecond()
	return self:AvgKillXpPerSecond() + self.cmaClassXp + self:AvgQuestXpPerSecond()
end

function SimpleTTL:AvgQuestXpPerSecond()
	return self.cmaQuests * self.cmaQuestXp
end

function SimpleTTL:AvgKillXpPerSecond()
	if GetRestXp() > 0 then
		return self.cmaKills * (self.cmaXpPerKill * RESTED_MULT)
	else
		return self.cmaKills * self.cmaXpPerKill
	end
end

function SimpleTTL:TimeTillRestedRunsOut()
	local killXpPerSec = math.floor(self.cmaKills * self.cmaXpPerKill * 0.5)
	return math.ceil(GetRestXp() / killXpPerSec)
end

function SimpleTTL:KillsTillRestedRunsOut()
	return math.ceil(GetRestXp() / math.floor(self.cmaXpPerKill * 0.5))
end

function SimpleTTL.DeltaToTime(nDelta)
	local tminutes = math.floor(nDelta / 60)
	local thours = math.floor(nDelta / (60 * 60))
	local tday = math.floor(nDelta / (24 * 60 * 60))
	local result = {}
	result.seconds = nDelta % 60
	result.minutes = tminutes % 60
	result.hours = thours % 24
	result.days = tday
	return result
end

function SimpleTTL.UpdateMenuList(strLabel, nValue)
	Event_FireGenericEvent("InterfaceMenuList_AlertAddOn", NAME, {false, strLabel, nValue})
end

function SimpleTTL:cmaDelta()
	local now = os.time() - self.t0
	return now - self.t
end

function SimpleTTL:RollUpAverages()
	local now = os.time() - self.t0
	local avgKillXp = 0
	local avgQuestXp = 0
	local combinedKills = self.totalKills + self.kills
	local combinedQuests = self.totalQuests + self.quests
	if self.kills ~= 0 then
		avgKillXp = self.killXp / self.kills
	end
	if self.quests ~= 0 then
		avgQuestXp = self.questXp / self.quests
	end
	if combinedQuests > 0 then
		self.cmaQuestXp = (self.totalQuests * self.cmaQuestXp + self.questXp) / combinedQuests
	end
	self.cmaQuests = (self.t * self.cmaQuests + self.quests) / now
	self.cmaClassXp = (self.t * self.cmaClassXp + self.classXp) / now
	self.classXp = 0
	if combinedKills > 0 then
		self.cmaXpPerKill = (self.totalKills * self.cmaXpPerKill + self.killXp) / combinedKills
	end
	self.cmaKills = (self.t * self.cmaKills + self.kills) / now
	self.killXp = 0
	self.kills = 0
	self.questXp = 0
	self.quests = 0
	self.cmaPathXp = (self.t * self.cmaPathXp + self.pathXp) / now
	self.pathXp = 0
	self.t = now
	self.totalKills = combinedKills
	self.totalQuest = combinedQuests
end

function SimpleTTL:QuestsToLevel()
	if self.cmaQuestXp == 0 then
		return -1
	end
	if self.elder then
		local nCurrentEP = GetElderPoints()
		local nCurrentToDailyMax = GetPeriodicElderPoints()
		local nEPToAGem = GameLib.ElderPointsPerGem
		local nEPNeeded = nEPToAGem - nCurrentEP

		return self:CalcQuestsToLevel(nCurrentEP, nEPNeeded, nCurrentToDailyMax)
	else
		local nCurrentXP = GetXp() - GetXpToCurrentLevel()
		local nNeededXP = GetXpToNextLevel()
		
		return self:CalcQuestsToLevel(nCurrentXP, nNeededXP - nCurrentXP, nil)
	end
end

function SimpleTTL:CalcQuestsToLevel(nCurrentXP, nNeededXP, nCurrentToDailyMax)
	local nTarget = nNeededXP
	if nCurrentToDailyMax ~= nil then
		nTarget = math.min(nNeededXP, nCurrentToDailyMax)
		if nCurrentToDailyMax == 0 then
			return -1
		end
	end
	if nTarget == nil then
		return -1
	end
	return math.ceil(nTarget / self.cmaQuestXp)
end

function SimpleTTL:KillsToLevel()
	if self.cmaXpPerKill == 0 then
		return -1
	end
	if self.elder then
		local nCurrentEP = GetElderPoints()
		local nCurrentToDailyMax = GetPeriodicElderPoints()
		local nEPToAGem = GameLib.ElderPointsPerGem
		local nEPNeeded = nEPToAGem - nCurrentEP

		return self:CalcKillsPerLevel(nCurrentEP, nEPNeeded, nCurrentToDailyMax)
	else
		local nCurrentXP = GetXp() - GetXpToCurrentLevel()
		local nNeededXP = GetXpToNextLevel()
		
		return self:CalcKillsPerLevel(nCurrentXP, nNeededXP - nCurrentXP, nil)
	end
end

function SimpleTTL:CalcKillsPerLevel(nCurrentXP, nNeededXP, nCurrentToDailyMax)
	local nRestedXP = GetRestXp()
	local nRestedXPPool = GetRestXpKillCreaturePool()
	local nTarget = nNeededXP
	if nCurrentToDailyMax ~= nil then
		nTarget = math.min(nNeededXP, nCurrentToDailyMax)
		if nCurrentToDailyMax == 0 then
			return -1
		end
	end
	if nTarget == nil or nCurrentXP == nil then
		return -1
	end
	local avgRestedKill = math.floor(self.cmaXpPerKill * RESTED_MULT)
	if nRestedXP > 0 then
		if nCurrentXP + nRestedXPPool > nTarget then
			return math.ceil(nTarget / avgRestedKill)
		else
			local restedKills = self:KillsTillRestedRunsOut()
			local restedKillXp = restedKills * avgRestedKill
			local remaining = nTarget - restedKillXp
			return math.ceil(remaining / self.cmaXpPerKill) + restedKills
		end
	else
		return math.ceil(nTarget / self.cmaXpPerKill)
	end
end

function SimpleTTL:RestExceedsLevel(nCurrentXP, nNeededXP)
	local nRestedXP = GetRestXp()
	local nRestedXPPool = GetRestXpKillCreaturePool()
	if nRestedXP > 0 then
		if nCurrentXP + nRestedXPPool > nTarget then
			return true
		else
			return false
		end	
	else
		return false
	end
end

function SimpleTTL:AbsTimeToLevel()
	return self.t0 + SimpleTTL:TimeToLevel()
end

function SimpleTTL:TimeToLevel()
	if self.elder then
		local nCurrentEP = GetElderPoints()
		local nCurrentToDailyMax = GetPeriodicElderPoints()
		local nEPToAGem = GameLib.ElderPointsPerGem
		local nEPNeeded = nEPToAGem - nCurrentEP

		return self:CalcTimeToLevel(nCurrentEP, nEPNeeded, nCurrentToDailyMax)
	else
		local nCurrentXP = GetXp() - GetXpToCurrentLevel()
		local nNeededXP = GetXpToNextLevel()
		
		return self:CalcTimeToLevel(nCurrentXP, nNeededXP - nCurrentXP, nil)
	end
end

function SimpleTTL:CalcTimeToLevel(nCurrentXP, nNeededXP, nCurrentToDailyMax)
	local nRestedXP = GetRestXp()
	local nRestedXPPool = GetRestXpKillCreaturePool()
	local nTarget = nNeededXP
	if nCurrentToDailyMax ~= nil then
		nTarget = math.min(nNeededXP, nCurrentToDailyMax)
		if nCurrentToDailyMax == 0 then
			return -1
		end
	end
	if nTarget == nil or nCurrentXP == nil then
		return -1
	end
	local endOfRested = self:TimeTillRestedRunsOut()
	local nonRestedXpS = self:AvgQuestXpPerSecond() + self.cmaClassXp + (self.cmaKills * self.cmaXpPerKill)
	if nonRestedXpS == 0 then
		return -1
	end	
	if endOfRested > 0 then
		local avgRestedKill = math.floor(self.cmaXpPerKill * RESTED_MULT)
		local restedXpS = self:AvgQuestXpPerSecond() + self.cmaClassXp + (self.cmaKills * avgRestedKill)
		local restedXp = restedXpS * endOfRested			
		local nonRestedXp = nTarget - restedXp
		if nonRestedXp < 0 then
			return math.ceil(nTarget / restedXpS)
		else
			return math.ceil(nonRestedXp / nonRestedXpS) + endOfRested
		end
	else
		return math.ceil(nTarget / nonRestedXpS)
	end
end

-----------------------------------------------------------------------------------------------
-- SimpleTTLForm Functions
-----------------------------------------------------------------------------------------------
-- when the OK button is clicked
function SimpleTTL:OnOK()
	self.wndMain:Close() -- hide the window
end

-- when the Cancel button is clicked
function SimpleTTL:OnCancel()
	self.wndMain:Close() -- hide the window
end


-----------------------------------------------------------------------------------------------
-- SimpleTTL Instance
-----------------------------------------------------------------------------------------------
local SimpleTTLInst = SimpleTTL:new()
SimpleTTLInst:Init()
