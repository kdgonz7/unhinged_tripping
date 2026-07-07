if CLIENT then
     hook.Add("AddToolMenuTabs", "CreateTrippingTab", function()
        spawnmenu.AddToolCategory("Utilities", "NPC Tripping System", "NPC Tripping System")
    end)

    hook.Add("PopulateToolMenu", "NPCTrippingSettingsMenu", function()
        spawnmenu.AddToolMenuOption(
            "Utilities",
            "NPC Tripping System",
            "NPCTrippingSettings",
            "NPC Tripping Settings",
            "",
            "",
            function(panel)
                panel:ClearControls()
                panel:CheckBox(
                    "Enable NPC Tripping",
                    "npc_trip_enabled"
                )
                panel:NumSlider(
                    "Trip Duration (Seconds)",
                    "npc_trip_time",
                    1,
                    20,
                    0
                )
                panel:NumSlider(
                    "Raycast Length (Distance)",
                    "npc_trip_ray_length",
                    10,
                    150,
                    0
                )
                panel:NumSlider(
                    "Trip Cooldown (Seconds)",
                    "npc_trip_cooldown",
                    0,
                    30,
                    0
                )
                panel:NumSlider(
                    "Trip Chance",
                    "npc_trip_chance",
                    0.1,
                    1.0,
                    2
                )
                panel:ControlHelp("")
                panel:CheckBox(
                    "Allow Nextbots to Trip",
                    "npc_trip_nextbots"
                )
            end
        )
    end)
end
