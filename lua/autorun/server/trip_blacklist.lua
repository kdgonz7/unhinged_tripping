if SERVER then
    util.AddNetworkString("npc_trip_get_blacklist")
    util.AddNetworkString("npc_trip_sync_blacklist")
    util.AddNetworkString("npc_trip_add_blacklist")
    util.AddNetworkString("npc_trip_remove_blacklist")
    util.AddNetworkString("npc_trip_clear_blacklist")

    net.Receive("npc_trip_get_blacklist", function(len, ply)
        if not ply:IsAdmin() or not TripBlacklist then return end
        net.Start("npc_trip_sync_blacklist")
        net.WriteTable(TripBlacklist)
        net.Send(ply)
    end)

    net.Receive("npc_trip_add_blacklist", function(len, ply)
        if not ply:IsAdmin() then return end
        local entry = net.ReadString()
        if entry and entry ~= "" then
            TripBlacklist[entry] = true
            SaveTripBlacklist()
        end
    end)

    net.Receive("npc_trip_remove_blacklist", function(len, ply)
        if not ply:IsAdmin() then return end
        local entry = net.ReadString()
        if entry then
            TripBlacklist[entry] = nil
            SaveTripBlacklist()
        end
    end)

    net.Receive("npc_trip_clear_blacklist", function(len, ply)
        if not ply:IsAdmin() then return end
        TripBlacklist = {}
        SaveTripBlacklist()
    end)
end
