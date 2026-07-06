---@diagnostic disable: inject-field, undefined-field

local TripEnabled = CreateConVar("npc_trip_enabled", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY })
local TripTimeThreshold = CreateConVar("npc_trip_time", "5", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Time in seconds before a tripped NPC gets up")
local TripRaycastLength = CreateConVar("npc_trip_ray_length", "50", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Distance to check for props at NPC feet")

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
    npc:Remove()

    return rag
end

local trippedNPCs = {}

hook.Add("Think", "NPCTripping_Check", function()
    if not TripEnabled:GetBool() then return end

    for _, ent in ents.Iterator() do
        if not ent:IsNPC() or trippedNPCs[ent] then continue end
        if not IsValid(ent) or not ent:IsNPC() or ent:Health() <= 0 then continue end

        local pos = ent:GetPos()
        local forward = ent:GetForward()
        local down = Vector(0, 0, -1)

        local startPos = pos + Vector(0, 0, 10) -- Slightly above feet
        local endPos = startPos + forward * TripRaycastLength:GetFloat() + down * 5

        local trace = util.TraceLine({
            start = startPos,
            endpos = endPos,
            filter = { ent, ent:GetActiveWeapon() }, -- Ignore self and weapon
            mask = MASK_SHOT
        })

        if trace.Hit
            and trace.Entity
            and trace.Entity:IsValid()
            and (trace.Entity:GetClass() == "prop_physics"
                or trace.Entity:GetClass() == "prop_ragdoll") then
            local weapon        = ent:GetActiveWeapon()
            local weaponClass   = weapon and weapon:IsValid() and weapon:GetClass() or nil
            local npcClass      = ent:GetClass()
            local oldModel      = ent:GetModel()

            local npcVelocity   = ent:GetVelocity()
            local forwardForce  = forward * (math.max(npcVelocity:Length(), 150) * 1.5)
            local upwardForce   = Vector(0, 0, 80)
            local totalVelocity = npcVelocity + forwardForce + upwardForce

            local ragdoll       = CreateRagdollFromNPC(ent)
            if ! ragdoll or not IsValid(ragdoll) or ! ent:Alive() then return end

            for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
                local phys = ragdoll:GetPhysicsObjectNum(i)
                if IsValid(phys) then
                    phys:SetVelocity(totalVelocity)

                    if i == 0 then -- Head/Chest area usually
                        phys:AddAngleVelocity(ent:GetRight() * 15)
                    end
                end
            end

            trippedNPCs[ragdoll] = {
                trippedTime = CurTime(),
                oldClass = npcClass,
                oldWeapon = weaponClass,
                oldModel = oldModel,
                TripHealth = ent.Health and ent:Health() or 100
            }

            ent:Remove()
        end
    end

    for ragdoll, data in pairs(trippedNPCs) do
        if not ragdoll or not ragdoll:IsValid() then
            trippedNPCs[ragdoll] = nil
            continue
        end

        if CurTime() - data.trippedTime >= TripTimeThreshold:GetFloat() then
            local newNPC = ents.Create(data.oldClass)

            if not newNPC or not newNPC:IsValid() then
                trippedNPCs[ragdoll] = nil
                ragdoll:Remove()
                continue
            end

            PrintTable(data)

            newNPC:SetPos(ragdoll:GetPos() + Vector(0, 0, 10))
            newNPC:SetAngles(ragdoll:GetAngles())
            newNPC:SetHealth(data.TripHealth)
            newNPC:Spawn()

            newNPC:SetModel(data.oldModel)
            newNPC:SetSkin(ragdoll:GetSkin())

            -- 3. Restore those bodygroups we talked about earlier
            for i = 0, ragdoll:GetNumBodyGroups() - 1 do
                newNPC:SetBodygroup(i, ragdoll:GetBodygroup(i))
            end

            if data.oldWeapon then
                timer.Simple(0.1, function()
                    if newNPC and newNPC:IsValid() then
                        newNPC:Give(data.oldWeapon)

                        timer.Simple(0.05, function()
                            if newNPC and newNPC:IsValid() then
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
        if ragdoll and ragdoll:IsValid() then
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

    if ! target:IsRagdoll() then return end
    if not (dmg:IsDamageType(DMG_BULLET) or
            dmg:IsDamageType(DMG_SLASH) or
            dmg:IsDamageType(DMG_BUCKSHOT) or
            dmg:IsDamageType(DMG_VEHICLE)) then
        return
    end

    --- health mod
    if trippedNPCs[target] then
        local targRef = trippedNPCs[target]
        targRef.TripHealth = targRef.TripHealth - dmg:GetDamage()
        if targRef.TripHealth <= 0 then
            trippedNPCs[target] = nil
        end
    end
end)
