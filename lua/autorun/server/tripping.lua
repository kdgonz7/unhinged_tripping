---@diagnostic disable: inject-field, undefined-field

local TripEnabled = CreateConVar("npc_trip_enabled", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY })
local TripTimeThreshold = CreateConVar("npc_trip_time", "5", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Time in seconds before a tripped NPC gets up")
local TripRaycastLength = CreateConVar("npc_trip_ray_length", "50", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Distance to check for props at NPC feet")
local TripCooldown = CreateConVar("npc_trip_cooldown", "3", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Seconds before an NPC can trip again")
local TripNextbots = CreateConVar("npc_trip_nextbots", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY })
local TripChance = CreateConVar("npc_trip_chance", "1.0", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY })
local TripWeaponDropChance = CreateConVar("npc_trip_weapon_drop_chance", "0.5",
    { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Chance (0-1) for an NPC to drop their weapon when they trip")
local ScavengeRange = CreateConVar("npc_trip_scavenge_range", "45", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Distance threshold for Combine to play the pickup animation")
local EnableTrippingOverRagdolls = CreateConVar("npc_trip_over_ragdolls", "1",
    { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Enables or disables NPC choreography, including tripping over ragdolls and other behaviors.")
local TripLegCheck = CreateConVar("npc_trip_legcheck", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Check if NPC has leg bones before allowing trip")
local TripForceThreshold = CreateConVar("npc_trip_force_threshold", "50",
    { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Minimum velocity required for forced trip (prevents walking into NPCs)")
local ScannersCanTrip = CreateConVar("npc_trip_scanners", "0",
    { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Should NPC Scanners be able to trip?")

TripBlacklist = {}
local TripBlacklistFile = "npc_trip_blacklist.txt"

function LoadTripBlacklist()
    if not file.Exists(TripBlacklistFile, "DATA") then
        TripBlacklist = {}
        return
    end

    local data = file.Read(TripBlacklistFile, "DATA")
    if data and data ~= "" then
        TripBlacklist = util.JSONToTable(data) or {}
    end
end

function SaveTripBlacklist()
    file.Write(TripBlacklistFile, util.TableToJSON(TripBlacklist))
end

LoadTripBlacklist()

-- Helper: Check if NPC has legs for trip purposes
local function NPCHasLegs(entity)
    if not TripLegCheck:GetBool() then return true end

    if entity:GetClass() == "npc_zombie_torso" or
        entity:GetClass() == "npc_fast_zombie_torso" then
        return false
    end

    local legBones = {
        "ValveBiped.Bip01_L_Foot",
        "ValveBiped.Bip01_R_Foot",
        "ValveBiped.Bip01_L_Thigh",
        "ValveBiped.Bip01_R_Thigh"
    }

    for _, boneName in ipairs(legBones) do
        if entity:LookupBone(boneName) then
            return true
        end
    end

    return false
end

local function IsTrippingBlacklisted(entity)
    if not IsValid(entity) then return true end

    local class = entity:GetClass()
    local model = entity:GetModel()

    -- Check by class
    if TripBlacklist[class] then return true end

    -- Check by model
    if model and TripBlacklist[model] then return true end

    return false
end

local function IsScannerNPC(entity)
    local class = entity:GetClass()
    return class == "npc_combinegunship" or
        class == "npc_helicopter" or
        class == "npc_cscanner" or
        class == "npc_clawscanner" or
        class == "npc_manhack" or
        class == "npc_turret_floor" or
        class == "npc_turret_ceiling"
end

local function CreateRagdollFromNPC(npc, dropWeapon)
    if not IsValid(npc) then return end

    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then return end

    rag:SetModel(npc:GetModel())
    rag:SetPos(npc:GetPos())
    rag:SetAngles(npc:GetAngles())
    rag:Spawn()
    rag:Activate()
    rag:SetSkin(npc:GetSkin())

    for i = 0, npc:GetNumBodyGroups() - 1 do
        rag:SetBodygroup(i, npc:GetBodygroup(i))
    end

    for i = 1, rag:GetPhysicsObjectCount() do
        local bone = rag:GetPhysicsObjectNum(i - 1)
        if IsValid(bone) then
            local boneId = rag:TranslatePhysBoneToBone(i - 1)
            local pos, ang = npc:GetBonePosition(boneId)
            if pos then
                bone:SetPos(pos)
                bone:SetAngles(ang)
                bone:Wake()
            end
        end
    end

    rag:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)

    --*FIX* for undos
    if SERVER then
        undo.ReplaceEntity(npc, rag)
        cleanup.ReplaceEntity(npc, rag)

        local creator = npc:GetCreator()
        if IsValid(creator) then
            rag:SetCreator(creator)
        end
    end

    if dropWeapon and IsValid(npc:GetActiveWeapon()) then
        local weapon = npc:GetActiveWeapon()
        local weaponPos = weapon:GetPos()
        local weaponAng = weapon:GetAngles()

        local droppedWeapon = ents.Create(weapon:GetClass())
        if IsValid(droppedWeapon) then
            droppedWeapon:SetPos(weaponPos + Vector(0, 0, 5))
            droppedWeapon:SetAngles(weaponAng)
            droppedWeapon:Spawn()
            droppedWeapon:Activate()

            local phys = droppedWeapon:GetPhysicsObject()
            if IsValid(phys) then
                phys:Wake()
                phys:SetVelocity(npc:GetForward() * 100 + Vector(0, 0, 50))
                phys:AddAngleVelocity(Vector(200, 100, 50))
            end

            rag.NPC_DroppedWeapon = droppedWeapon
        end

        weapon:Remove()
    else
        -- hide their weapons so it doesn't float in mid-air
        local weapon = npc:GetActiveWeapon()
        if IsValid(weapon) then
            weapon:SetNoDraw(true)
        end
    end

    npc:SetNoDraw(true)
    npc:SetNotSolid(true)
    npc:SetMoveType(MOVETYPE_NONE)
    if npc.CapabilitiesClear then npc:CapabilitiesClear() end

    -- *FIX*: Completely freeze engine AI and Lua/Nextbot thinking loops
    if npc.GetNPCState then
        npc.PreTripNPCState = npc:GetNPCState()
        npc:SetNPCState(NPC_STATE_NONE)
    end

    npc:NextThink(CurTime() + 99999)

    return rag
end

local trippedNPCs = {}
local scavengingNPCs = {}
local nextCheck = 0

hook.Add("Think", "NPCTripping_Check", function()
    if not TripEnabled:GetBool() then return end

    local currentTime = CurTime()

    if currentTime >= nextCheck then
        nextCheck = currentTime + 0.1

        for _, ent in ents.Iterator() do
            if not IsValid(ent) or ent:Health() <= 0 then continue end
            if ent.NPC_IsTrippedGhost then continue end
            if not TripNextbots:GetBool() and ent:IsNextBot() then continue end
            if not ent:IsNPC() and not ent:IsNextBot() then continue end
            if ent.NPC_TripCooldown and currentTime < ent.NPC_TripCooldown then continue end

            -- *FIX: Check if NPC has legs
            if not NPCHasLegs(ent) then continue end

            -- *FIX: Check blacklist and scanner types
            if IsTrippingBlacklisted(ent) then continue end

            -- *FIX Prevent forced tripping with small objects
            local vel = ent:GetVelocity()
            local velLength = vel:Length()

            if IsScannerNPC(ent) and not ScannersCanTrip:GetBool() then continue end
            if velLength < TripForceThreshold:GetFloat() then continue end

            local pos = ent:GetPos()
            local forward = ent:GetForward()
            local startPos = pos + Vector(0, 0, 10)
            local endPos = startPos + forward * TripRaycastLength:GetFloat() + Vector(0, 0, -5)

            local trace = util.TraceLine({
                start = startPos,
                endpos = endPos,
                filter = { ent, ent:GetActiveWeapon() },
                mask = MASK_SHOT
            })

            if trace.Hit and IsValid(trace.Entity) then
                local hitClass = trace.Entity:GetClass()
                local allowedToTrip = false

                if hitClass == "prop_physics" then
                    local phys = trace.Entity:GetPhysicsObject()
                    if IsValid(phys) then
                        local mass = phys:GetMass()
                        local volume = phys:GetVolume()
                        if mass >= 5 and volume >= 1000 then
                            allowedToTrip = true
                        end
                    end
                elseif hitClass == "prop_ragdoll" and EnableTrippingOverRagdolls:GetBool() then
                    allowedToTrip = true
                end

                if not allowedToTrip then continue end

                if math.random() > TripChance:GetFloat() then continue end

                local weapon = ent:GetActiveWeapon()
                local weaponClass = IsValid(weapon) and weapon:GetClass() or nil
                local dropWeapon = weaponClass ~= nil and math.random() <= TripWeaponDropChance:GetFloat()

                local npcVelocity = ent:GetVelocity()
                local forwardForce = forward * (math.max(npcVelocity:Length(), 150) * 1.5)
                local upwardForce = Vector(0, 0, 80)
                local totalVelocity = npcVelocity + forwardForce + upwardForce

                ent.NPC_IsTrippedGhost = true

                local ragdoll = CreateRagdollFromNPC(ent, dropWeapon)
                if not IsValid(ragdoll) then
                    ent.NPC_IsTrippedGhost = nil
                    continue
                end

                for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
                    local phys = ragdoll:GetPhysicsObjectNum(i)
                    if IsValid(phys) then
                        phys:SetVelocity(totalVelocity)
                        if i == 0 then
                            phys:AddAngleVelocity(ent:GetRight() * 15)
                        end
                    end
                end

                trippedNPCs[ragdoll] = {
                    trippedTime = currentTime,
                    npcEnt = ent,
                    oldWeapon = weaponClass,
                    droppedWeapon = dropWeapon and ragdoll.NPC_DroppedWeapon or nil
                }
            end
        end
    end

    for ragdoll, data in pairs(trippedNPCs) do
        if not IsValid(ragdoll) then
            if IsValid(data.npcEnt) then data.npcEnt:Remove() end
            trippedNPCs[ragdoll] = nil
            continue
        end

        local originalNPC = data.npcEnt
        if not IsValid(originalNPC) then
            ragdoll:Remove()
            trippedNPCs[ragdoll] = nil
            continue
        end

        local pelvisBone = ragdoll:LookupBone("ValveBiped.Bip01_Pelvis")
        if pelvisBone then
            local pPos = ragdoll:GetBonePosition(pelvisBone)
            if pPos then originalNPC:SetPos(pPos) end
        else
            originalNPC:SetPos(ragdoll:GetPos())
        end

        if currentTime - data.trippedTime >= TripTimeThreshold:GetFloat() then
            -- kill ragdoll physics velocities and collisions before restoring NPC physics
            ragdoll:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
            for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
                local phys = ragdoll:GetPhysicsObjectNum(i)
                if IsValid(phys) then
                    phys:SetVelocity(Vector(0, 0, 0))
                    phys:AddAngleVelocity(Vector(0, 0, 0))
                    phys:Sleep()
                end
            end

            originalNPC:SetPos(ragdoll:GetPos() + Vector(0, 0, 15))
            originalNPC:SetAngles(Angle(0, ragdoll:GetAngles().y, 0))
            originalNPC:SetNoDraw(false)
            originalNPC:SetNotSolid(true)
            originalNPC:SetMoveType(MOVETYPE_STEP)

            -- *FIX*: Wake the AI back up and restore its old engine state
            originalNPC:NextThink(CurTime())
            if originalNPC.SetNPCState and originalNPC.PreTripNPCState then
                originalNPC:SetNPCState(originalNPC.PreTripNPCState)
                originalNPC.PreTripNPCState = nil
            end

            local weapon = originalNPC:GetActiveWeapon()
            if IsValid(weapon) then
                weapon:SetNoDraw(false)
            end

            if originalNPC.CapabilitiesAdd then
                originalNPC:CapabilitiesAdd(CAP_MOVE_GROUND + CAP_OPEN_DOORS + CAP_TURN_HEAD)
            end

            originalNPC.NPC_TripCooldown = currentTime + TripCooldown:GetFloat()
            originalNPC.NPC_IsTrippedGhost = nil

            if SERVER and IsValid(originalNPC:GetCreator()) then
                undo.ReplaceEntity(ragdoll, originalNPC)
                cleanup.ReplaceEntity(ragdoll, originalNPC)
            end

            local isCombine = string.find(originalNPC:GetClass(), "npc_combine") or
                string.find(originalNPC:GetClass(), "npc_metropolice")
            if isCombine and IsValid(data.droppedWeapon) and data.oldWeapon then
                scavengingNPCs[originalNPC] = {
                    weapon = data.droppedWeapon,
                    wepClass = data.oldWeapon,
                    started = false
                }
            elseif data.oldWeapon and not IsValid(originalNPC:GetActiveWeapon()) then
                timer.Simple(0.1, function()
                    if IsValid(originalNPC) then
                        originalNPC:Give(data.oldWeapon)
                        timer.Simple(0.05, function()
                            if IsValid(originalNPC) then originalNPC:SelectWeapon(data.oldWeapon) end
                        end)
                    end
                end)
            end

            trippedNPCs[ragdoll] = nil
            ragdoll:Remove()
            originalNPC:SetNotSolid(false)
        end
    end

    for npc, data in pairs(scavengingNPCs) do
        if not IsValid(npc) or npc:Health() <= 0 then
            scavengingNPCs[npc] = nil
            continue
        end

        if not IsValid(data.weapon) then
            scavengingNPCs[npc] = nil
            continue
        end

        local dist = npc:GetPos():DistToSqr(data.weapon:GetPos())
        local rangeThresh = ScavengeRange:GetFloat() * ScavengeRange:GetFloat()

        if dist <= rangeThresh then
            scavengingNPCs[npc] = nil
            npc:ClearSchedule()
            npc:SetCondition(COND.IDLE_INTERRUPT)

            local seq = npc:LookupSequence("pickup")
            if seq == -1 then seq = npc:LookupSequence("yield") end
            if seq == -1 then seq = npc:LookupSequence("gesture_item_pickup") end
            if seq == -1 then seq = npc:LookupSequence("combat_stand_to_crouch") end

            if seq ~= -1 then npc:RestartGesture(seq) end

            timer.Simple(0.6, function()
                if not IsValid(npc) or npc:Health() <= 0 then return end
                if IsValid(data.weapon) then data.weapon:Remove() end

                npc:Give(data.wepClass)
                timer.Simple(0.05, function()
                    if IsValid(npc) then
                        npc:SelectWeapon(data.wepClass)
                        npc:ClearCondition(COND.IDLE_INTERRUPT)
                    end
                end)
            end)
        else
            if not data.started or (npc:GetInternalVariable("m_backtracking") == false and math.random() < 0.1) then
                timer.Simple(0.5, function()
                    if IsValid(npc) and IsValid(data.weapon) then
                        npc:SetLastPosition(data.weapon:GetPos())
                        npc:SetSchedule(SCHED_FORCED_GO_RUN)
                        data.started = true
                    end
                end)
            end
        end
    end
end)

hook.Add("EntityTakeDamage", "CheckAndKill", function(target, dmg)
    if not TripEnabled:GetBool() then return end
    if not IsValid(target) or not target:IsRagdoll() then return end

    if dmg:IsDamageType(DMG_CRUSH) then
        dmg:SetDamage(dmg:GetDamage() * 0.2)
    end

    local data = trippedNPCs[target]
    if data and IsValid(data.npcEnt) then
        local npc = data.npcEnt
        local newHealth = npc:Health() - dmg:GetDamage()
        npc:SetHealth(newHealth)

        if newHealth <= 0 then
            trippedNPCs[target] = nil
            target:SetCollisionGroup(COLLISION_GROUP_NONE)
            ---@cast npc NPC
            timer.Simple(0, function()
                if IsValid(npc) then
                    npc:Remove()
                end
            end)
        end
    end
end)
