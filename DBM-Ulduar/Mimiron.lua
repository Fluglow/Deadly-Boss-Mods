local mod	= DBM:NewMod("Mimiron", "DBM-Ulduar")
local L		= mod:GetLocalizedStrings()

mod:SetRevision(("$Revision: 4338 $"):sub(12, -3))
mod:SetCreatureID(33432)
mod:SetUsedIcons(1, 2, 3, 4, 5, 6, 7, 8)

mod:RegisterCombat("yell", L.YellPull)
mod:RegisterCombat("yell", L.YellHardPull)

mod:RegisterEvents(
	"SPELL_CAST_START",
	"SPELL_CAST_SUCCESS",
	"SPELL_AURA_APPLIED",
	"CHAT_MSG_MONSTER_YELL",
	"SPELL_AURA_REMOVED",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"CHAT_MSG_LOOT"
)

local blastWarn					= mod:NewTargetAnnounce(64529, 4)
local shellWarn					= mod:NewTargetAnnounce(63666, 2)
local lootannounce				= mod:NewAnnounce("MagneticCore", 1)
local warnBombSpawn				= mod:NewAnnounce("WarnBombSpawn", 3)
local warnFrostBomb				= mod:NewSpellAnnounce(64623, 3)

local warnShockBlast			= mod:NewSpecialWarning("WarningShockBlast", nil, false)
mod:AddBoolOption("ShockBlastWarningInP1", mod:IsMelee(), "announce")
mod:AddBoolOption("ShockBlastWarningInP4", mod:IsMelee(), "announce")
local warnDarkGlare				= mod:NewSpecialWarningSpell(63293)

local enrage 					= mod:NewBerserkTimer(900)
local timerHardmode				= mod:NewTimer(600, "TimerHardmode", 64582)
local timerRoleplay				= mod:NewTimer(31.5, "TimerRoleplay")
local timerP1toP2				= mod:NewTimer(54.5, "TimeToPhase2")
local timerP2toP3				= mod:NewTimer(28, "TimeToPhase3")
local timerP3toP4				= mod:NewTimer(22, "TimeToPhase4")
local timerProximityMines		= mod:NewNextTimer(35, 63027)
local timerShockBlast			= mod:NewCastTimer(63631)
local timerSpinUp				= mod:NewCastTimer(4, 63414)
local timerDarkGlareCast		= mod:NewCastTimer(10, 63274)
local timerNextDarkGlare		= mod:NewNextTimer(41, 63274)
local timerNextShockblast		= mod:NewNextTimer(49, 63631)
local timerPlasmaBlastCD		= mod:NewCDTimer(38, 64529)
local timerShell				= mod:NewBuffActiveTimer(6, 63666)
local timerFlameSuppressant		= mod:NewCastTimer(63, 64570)
local timerNextFlameSuppressant	= mod:NewNextTimer(16, 65192)
local timerNextFlames			= mod:NewNextTimer(26, 64566)
local timerNextFrostBomb        = mod:NewNextTimer(60, 64623)
local timerBombExplosion		= mod:NewCastTimer(13.5, 65333)
local timerNextBarrage			= mod:NewNextTimer(65, 63293)
local timerNextBombBot			= mod:NewNextTimer(19, 63811)
local timerAerialGrounded		= mod:NewBuffActiveTimer(20, 64436)

mod:AddBoolOption("PlaySoundOnShockBlast", isMelee)
mod:AddBoolOption("PlaySoundOnDarkGlare", true)
mod:AddBoolOption("HealthFramePhase4", true)
mod:AddBoolOption("AutoChangeLootToFFA", true)
mod:AddBoolOption("SetIconOnNapalm", true)
mod:AddBoolOption("SetIconOnPlasmaBlast", true)
mod:AddBoolOption("RangeFrame")

local hardmode = false
local phase						= 0 
local lootmethod, masterlooterRaidID

local spinningUp				= GetSpellInfo(63414)
local lastSpinUp				= 0
local is_spinningUp				= false
local napalmShellTargets = {}
local napalmShellIcon 	= 7

local isGrounded 				= false

local function warnNapalmShellTargets()
	shellWarn:Show(table.concat(napalmShellTargets, "<, >"))
	table.wipe(napalmShellTargets)
	napalmShellIcon = 7
end

function mod:OnCombatStart(delay)
    hardmode = false
	enrage:Start(-delay)
	phase = 0
	is_spinningUp = false
	napalmShellIcon = 7
	table.wipe(napalmShellTargets)
	self:NextPhase()

	timerRoleplay:Start(delay)
	timerPlasmaBlastCD:Start(31.5 + 12 - delay)
	timerProximityMines:Start(31.5 + 6 - delay)

	if DBM:GetRaidRank() == 2 then
		lootmethod, _, masterlooterRaidID = GetLootMethod()
	end
	if self.Options.RangeFrame then
		DBM.RangeCheck:Show(6)
	end
end

function mod:OnCombatEnd()
	DBM.BossHealth:Hide()
	if self.Options.RangeFrame then
		DBM.RangeCheck:Hide()
	end
	if self.Options.AutoChangeLootToFFA and DBM:GetRaidRank() == 2 then
		if masterlooterRaidID then
			SetLootMethod(lootmethod, "raid"..masterlooterRaidID)
		else
			SetLootMethod(lootmethod)
		end
	end
end

function mod:Flames()
	timerNextFlames:Start()
	self:ScheduleMethod(26, "Flames")
end

function mod:BombBotTimer()
	if phase == 3 and isGrounded then
		timerNextBombBot:Start()
		self:ScheduleMethod(19, "BombBotTimer")
	end
end

function mod:groundedCallback()
	isGrounded = false
end

function mod:UNIT_SPELLCAST_CHANNEL_STOP(unit, spell)
	if spell == spinningUp and GetTime() - lastSpinUp < 3.9 then
		is_spinningUp = false
		self:SendSync("SpinUpFail")
	end
end

function mod:CHAT_MSG_LOOT(msg)
	-- DBM:AddMsg(msg) --> Meridium receives loot: [Magnetic Core]
	local player, itemID = msg:match(L.LootMsg)
	if player and itemID and tonumber(itemID) == 46029 then
		lootannounce:Show(player)
	end
end

function mod:SPELL_CAST_START(args)
	if args:IsSpellID(63631) then
		if phase == 1 and self.Options.ShockBlastWarningInP1 or phase == 4 and self.Options.ShockBlastWarningInP4 then
			warnShockBlast:Show()
		end
		timerShockBlast:Start()
		timerNextShockblast:Start()
		if self.Options.PlaySoundOnShockBlast then
			PlaySoundFile("Sound\\Creature\\HoodWolf\\HoodWolfTransformPlayer01.wav")
		end
	end
	if args:IsSpellID(64529, 62997) then -- plasma blast
		timerPlasmaBlastCD:Start()
		timerNextShockblast:Start(17)
	end
	if args:IsSpellID(64570) then
		timerFlameSuppressant:Start()
	end
	if args:IsSpellID(64623) then
		warnFrostBomb:Show()
		timerBombExplosion:Start()

		if phase == 4 then
			timerNextFrostBomb:Start(40)
		else
			timerNextFrostBomb:Start()
		end
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args:IsSpellID(63666, 65026) and args:IsDestTypePlayer() then -- Napalm Shell
		napalmShellTargets[#napalmShellTargets + 1] = args.destName
		timerShell:Start()
		if self.Options.SetIconOnNapalm then
			self:SetIcon(args.destName, napalmShellIcon, 6)
			napalmShellIcon = napalmShellIcon - 1
		end
		self:Unschedule(warnNapalmShellTargets)
		self:Schedule(0.3, warnNapalmShellTargets)
	elseif args:IsSpellID(64529, 62997) then -- Plasma Blast
		blastWarn:Show(args.destName)
		if self.Options.SetIconOnPlasmaBlast then
			self:SetIcon(args.destName, 8, 6)
		end
	elseif args:IsSpellID(64582) and args.destName == "Bomb Bot" then
		-- Bomb Bot spawn detection hackfix, HM only.
		-- If the boss is grounded, the bomb bot timer will still reset.
		-- To cover for this case, start the timer again in 19s if the boss is grounded.
		warnBombSpawn:Show()
		timerNextBombBot:Start()
		self:ScheduleMethod(19, "BombBotTimer")
	end
end

local function show_warning_for_spinup()
	if is_spinningUp then
		warnDarkGlare:Show()
		if mod.Options.PlaySoundOnDarkGlare then
			PlaySoundFile("Sound\\Creature\\HoodWolf\\HoodWolfTransformPlayer01.wav")
		end
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args:IsSpellID(63027) then				-- mines
		timerProximityMines:Start()

	elseif args:IsSpellID(63414) then			-- Spinning UP (before Dark Glare)
		is_spinningUp = true
		timerSpinUp:Start()
		timerNextBarrage:Start()
		timerDarkGlareCast:Schedule(4)
		timerNextDarkGlare:Schedule(19)			-- 4 (cast spinup) + 15 sec (cast dark glare)
		DBM:Schedule(0.15, show_warning_for_spinup)	-- wait 0.15 and then announce it, otherwise it will sometimes fail
		lastSpinUp = GetTime()

	elseif args:IsSpellID(65192) then
		timerNextFlameSuppressant:Start()

	elseif args:IsSpellID(64444) then
		isGrounded = true
		timerAerialGrounded:Start()
		self:UnscheduleMethod("groundedCallback")
		self:ScheduleMethod(20, "groundedCallback")
	end
end

function mod:NextPhase()
	phase = phase + 1
	if phase == 1 then
		if self.Options.HealthFrame then
			DBM.BossHealth:Clear()
			DBM.BossHealth:AddBoss(33432, L.MobPhase1)
		end

	elseif phase == 2 then
		timerNextShockblast:Stop()
		timerProximityMines:Stop()
		timerFlameSuppressant:Stop()
		timerPlasmaBlastCD:Stop()
		timerP1toP2:Start()
		timerNextBarrage:Start(119.5)
		if self.Options.HealthFrame then
			DBM.BossHealth:Clear()
			DBM.BossHealth:AddBoss(33651, L.MobPhase2)
		end
		if self.Options.RangeFrame then
			DBM.RangeCheck:Hide()
		end
		if hardmode then
            timerNextFrostBomb:Start(63)
			timerFlameSuppressant:Start(55.5)
        end

	elseif phase == 3 then
		if self.Options.AutoChangeLootToFFA and DBM:GetRaidRank() == 2 then
			SetLootMethod("freeforall")
		end
		timerDarkGlareCast:Cancel()
		timerNextDarkGlare:Cancel()
		timerNextFrostBomb:Cancel()
		timerNextBarrage:Cancel()
		timerNextBombBot:Start(48)
		timerP2toP3:Start()
		if self.Options.HealthFrame then
			DBM.BossHealth:Clear()
			DBM.BossHealth:AddBoss(33670, L.MobPhase3)
		end

	elseif phase == 4 then
		timerNextBombBot:Cancel()
		timerAerialGrounded:Cancel()
		isGrounded = false

		if self.Options.AutoChangeLootToFFA and DBM:GetRaidRank() == 2 then
			if masterlooterRaidID then
				SetLootMethod(lootmethod, "raid"..masterlooterRaidID)
			else
				SetLootMethod(lootmethod)
			end
		end
		timerP3toP4:Start()
		timerNextShockblast:Start(67)
		timerNextBarrage:Start(87)

		if self.Options.HealthFramePhase4 or self.Options.HealthFrame then
			DBM.BossHealth:Show(L.name)
			DBM.BossHealth:AddBoss(33670, L.MobPhase3)
			DBM.BossHealth:AddBoss(33651, L.MobPhase2)
			DBM.BossHealth:AddBoss(33432, L.MobPhase1)
		end
		if hardmode then
            timerNextFrostBomb:Start(37)
        end
	end
end

do
	local count = 0
	local last = 0
	local lastPhaseChange = 0
	function mod:SPELL_AURA_REMOVED(args)
		local cid = self:GetCIDFromGUID(args.destGUID)
		if GetTime() - lastPhaseChange > 30 and (cid == 33432 or cid == 33651 or cid == 33670) then
			if args.timestamp == last then	-- all events in the same tick to detect the phases earlier (than the yell) and localization-independent
				count = count + 1
				if (mod:IsDifficulty("heroic10") and count > 4) or (mod:IsDifficulty("heroic25") and count > 9) then
					lastPhaseChange = GetTime()
					self:NextPhase()
				end
			else
				count = 1
			end
			last = args.timestamp
		elseif args:IsSpellID(63666, 65026) then -- Napalm Shell
			if self.Options.SetIconOnNapalm then
				self:SetIcon(args.destName, 0)
			end
		end
	end
end

function mod:CHAT_MSG_MONSTER_YELL(msg)
	if (msg == L.YellPhase2 or msg:find(L.YellPhase2)) and mod:LatencyCheck() then
		--DBM:AddMsg("ALPHA: yell detect phase2, syncing to clients")
		self:SendSync("Phase2")	-- untested alpha! (this will result in a wrong timer)

	elseif (msg == L.YellPhase3 or msg:find(L.YellPhase3)) and mod:LatencyCheck() then
		--DBM:AddMsg("ALPHA: yell detect phase3, syncing to clients")
		self:SendSync("Phase3")	-- untested alpha! (this will result in a wrong timer)

	elseif (msg == L.YellPhase4 or msg:find(L.YellPhase4)) and mod:LatencyCheck() then
		--DBM:AddMsg("ALPHA: yell detect phase3, syncing to clients")
		self:SendSync("Phase4") -- SPELL_AURA_REMOVED detection might fail in phase 3...there are simply not enough debuffs on him

	elseif msg == L.YellHardPull then
		timerHardmode:Start()
		timerFlameSuppressant:Start(31.5 + 62)
		enrage:Stop()
		hardmode = true
		timerRoleplay:Start(delay)
		timerNextFlames:Start(8)
		self:ScheduleMethod(8, "Flames")
	end
end


function mod:OnSync(event, args)
	if event == "SpinUpFail" then
		is_spinningUp = false
		timerSpinUp:Cancel()
		timerDarkGlareCast:Cancel()
		timerNextDarkGlare:Cancel()
		warnDarkGlare:Cancel()
	elseif event == "Phase2" and phase == 1 then -- alternate localized-dependent detection
		self:NextPhase()
	elseif event == "Phase3" and phase == 2 then
		self:NextPhase()
	elseif event == "Phase4" and phase == 3 then
		self:NextPhase()
	end
end