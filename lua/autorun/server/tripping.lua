---@diagnostic disable: inject-field, undefined-field

local TripEnabled = CreateConVar("npc_trip_enabled", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY })
local TripTimeThreshold = CreateConVar("npc_trip_time", "5", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Time in seconds before a tripped NPC gets up")
local TripRaycastLength = CreateConVar("npc_trip_ray_length", "50", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Distance to check for props at NPC feet")
local TripCooldown = CreateConVar("npc_trip_cooldown", "3", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Seconds before an NPC can trip again")
local TripNextbots = CreateConVar("npc_trip_nextbots", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY })

local function CreateRagdollFromNPC(npc)
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

    if IsValid(npc:GetActiveWeapon()) then
        npc:GetActiveWeapon():Remove()
    end
    npc:Remove()

    return rag
end

local trippedNPCs = {}
local nextCheck = 0

hook.Add("Think", "NPCTripping_Check", function()
    if not TripEnabled:GetBool() then return end

    local currentTime = CurTime()

    if currentTime >= nextCheck then
        nextCheck = currentTime + 0.1

        for _, ent in ents.Iterator() do
            if not IsValid(ent) or ent:Health() <= 0 then continue end
            if not TripNextbots:GetBool() and ent:IsNextBot() then continue end
            if not ent:IsNPC() and not ent:IsNextBot() then continue end

            if ent.NPC_TripCooldown and currentTime < ent.NPC_TripCooldown then continue end

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

            if trace.Hit and IsValid(trace.Entity) and
                (trace.Entity:GetClass() == "prop_physics" or trace.Entity:GetClass() == "prop_ragdoll") then
                local weapon = ent:GetActiveWeapon()
                local weaponClass = IsValid(weapon) and weapon:GetClass() or nil
                local npcClass = ent:GetClass()
                local oldModel = ent:GetModel()

                local npcVelocity = ent:GetVelocity()
                local forwardForce = forward * (math.max(npcVelocity:Length(), 150) * 1.5)
                local upwardForce = Vector(0, 0, 80)
                local totalVelocity = npcVelocity + forwardForce + upwardForce

                local health = ent:Health()
                local maxHealth = ent:GetMaxHealth()

                local ragdoll = CreateRagdollFromNPC(ent)
                if not IsValid(ragdoll) then continue end

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
                    oldClass = npcClass,
                    oldWeapon = weaponClass,
                    oldModel = oldModel,
                    TripHealth = health,
                    TripMaxHealth = maxHealth
                }
            end
        end
    end

    for ragdoll, data in pairs(trippedNPCs) do
        if not IsValid(ragdoll) then
            trippedNPCs[ragdoll] = nil
            continue
        end

        if currentTime - data.trippedTime >= TripTimeThreshold:GetFloat() then
            local newNPC = ents.Create(data.oldClass)

            if not IsValid(newNPC) then
                trippedNPCs[ragdoll] = nil
                ragdoll:Remove()
                continue
            end

            newNPC:SetPos(ragdoll:GetPos() + Vector(0, 0, 10))
            newNPC:SetAngles(ragdoll:GetAngles())
            newNPC:Spawn()

            newNPC:SetModel(data.oldModel)
            newNPC:SetSkin(ragdoll:GetSkin())
            newNPC:SetMaxHealth(data.TripMaxHealth)
            newNPC:SetHealth(data.TripHealth)
            newNPC.NPC_TripCooldown = currentTime + TripCooldown:GetFloat()

            for i = 0, ragdoll:GetNumBodyGroups() - 1 do
                newNPC:SetBodygroup(i, ragdoll:GetBodygroup(i))
            end

            if data.oldWeapon then
                timer.Simple(0.1, function()
                    if IsValid(newNPC) then
                        newNPC:Give(data.oldWeapon)
                        timer.Simple(0.05, function()
                            if IsValid(newNPC) then
                                newNPC:SelectWeapon(data.oldWeapon)
                            end
                        end)
                    end
                end)
            end

            trippedNPCs[ragdoll] = nil
            ragdoll:Remove()
        end
    end
end)

concommand.Add("npc_trip_list", function()
    if not TripEnabled:GetBool() then return end
    print("=== Tripped NPCs ===")
    for ragdoll, data in pairs(trippedNPCs) do
        if IsValid(ragdoll) then
            local timeLeft = (data.trippedTime + TripTimeThreshold:GetFloat() - CurTime())
            print(string.format("Ragdoll %s - Class: %s, Gets up in %.1fs",
                ragdoll:EntIndex(), data.oldClass, timeLeft))
        end
    end
    if table.Count(trippedNPCs) == 0 then
        print("No NPCs are currently tripped")
    end
end)

hook.Add("EntityTakeDamage", "CheckAndKill", function(target, dmg)
    if not TripEnabled:GetBool() then return end
    if not IsValid(target) or not target:IsRagdoll() then return end

    if not (dmg:IsDamageType(DMG_BULLET) or
            dmg:IsDamageType(DMG_SLASH) or
            dmg:IsDamageType(DMG_BUCKSHOT) or
            dmg:IsDamageType(DMG_VEHICLE)) then
        return
    end

    local data = trippedNPCs[target]
    if data then
        data.TripHealth = data.TripHealth - dmg:GetDamage()
        if data.TripHealth <= 0 then
            trippedNPCs[target] = nil
        end
    end
end)
