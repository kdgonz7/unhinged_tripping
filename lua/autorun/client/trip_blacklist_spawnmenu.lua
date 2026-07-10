-- NPC Trip Blacklist Manager - Spawnmenu Entry
-- Only accessible to server admins

if not LocalPlayer():IsAdmin() then return end

local function CreateTripBlacklistMenu()
    local frame = vgui.Create("DFrame")
    frame:SetTitle("NPC Trip Blacklist Manager")
    frame:SetSize(500, 600)
    frame:Center()
    frame:MakePopup()
    frame:SetDeleteOnClose(true)

    local list = vgui.Create("DListView", frame)
    list:Dock(FILL)
    list:DockMargin(5, 5, 5, 5)
    list:SetMultiSelect(false)
    list:AddColumn("Class / Model")
    list:AddColumn("Type")

    -- Refresh list function
    local function RefreshList()
        list:Clear()

        net.Start("npc_trip_get_blacklist")
        net.SendToServer()

        -- Wait for response
        net.Receive("npc_trip_sync_blacklist", function()
            local blacklist = net.ReadTable()
            for entry, _ in pairs(blacklist) do
                local line = list:AddLine(entry, "Unknown")
                line.EntryValue = entry
            end
        end)
    end

    local addPanel = vgui.Create("DPanel", frame)
    addPanel:Dock(BOTTOM)
    addPanel:SetHeight(100)
    addPanel:DockMargin(5, 5, 5, 5)

    local entryLabel = vgui.Create("DLabel", addPanel)
    entryLabel:SetText("Enter NPC Class or Model:")
    entryLabel:Dock(TOP)
    entryLabel:DockMargin(0, 5, 0, 5)

    local entryBox = vgui.Create("DTextEntry", addPanel)
    entryBox:Dock(TOP)
    entryBox:DockMargin(0, 0, 0, 5)
    entryBox:SetPlaceholderText("e.g., npc_zombie_torso or models/zombie/classic.mdl")

    local buttonPanel = vgui.Create("DPanel", addPanel)
    buttonPanel:Dock(TOP)
    buttonPanel:SetHeight(30)
    buttonPanel:DockMargin(0, 5, 0, 0)

    local addButton = vgui.Create("DButton", buttonPanel)
    addButton:SetText("Add to Blacklist")
    addButton:Dock(LEFT)
    addButton:SetWidth(150)
    addButton:DockMargin(0, 0, 5, 0)
    addButton.DoClick = function()
        local entry = entryBox:GetValue()
        if entry and entry ~= "" then
            net.Start("npc_trip_add_blacklist")
            net.WriteString(entry)
            net.SendToServer()
            entryBox:SetText("")
            RefreshList()
        end
    end

    local removeButton = vgui.Create("DButton", buttonPanel)
    removeButton:SetText("Remove Selected")
    removeButton:Dock(LEFT)
    removeButton:SetWidth(150)
    removeButton:DockMargin(0, 0, 5, 0)
    removeButton.DoClick = function()
        local selected = list:GetSelectedLine()
        if selected then
            local line = list:GetLine(selected)
            if line and line.EntryValue then
                net.Start("npc_trip_remove_blacklist")
                net.WriteString(line.EntryValue)
                net.SendToServer()
                RefreshList()
            end
        end
    end

    local clearButton = vgui.Create("DButton", buttonPanel)
    clearButton:SetText("Clear All")
    clearButton:Dock(LEFT)
    clearButton:SetWidth(100)
    clearButton.DoClick = function()
        net.Start("npc_trip_clear_blacklist")
        net.SendToServer()
        RefreshList()
    end

    -- Help text
    local helpPanel = vgui.Create("DPanel", frame)
    helpPanel:Dock(BOTTOM)
    helpPanel:SetHeight(80)
    helpPanel:DockMargin(5, 5, 5, 5)

    local helpLabel = vgui.Create("DLabel", helpPanel)
    helpLabel:SetText([[
Blacklist Tips:
- Add NPC class names (e.g., npc_zombie_torso) to prevent them from being tripped
- Add model paths to blacklist specific models
- This prevents tripping on legless NPCs and small creatures
- Changes take effect immediately
    ]])
    helpLabel:Dock(FILL)
    helpLabel:SetWrap(true)
    helpLabel:SetAutoStretchVertical(true)

    RefreshList()

    return frame
end

hook.Add("PopulateToolMenu", "NPCTripBlacklistMenu", function()
    spawnmenu.AddToolMenuOption("Utilities",
        "NPC Tripping System",
        "NPCTrippingBlackList",
        "NPC Tripping Blacklist",
        "",
        "",
        function(panel)
            panel:ClearControls()

            local btn = vgui.Create("DButton")
            btn:SetText("Open Blacklist Manager")
            btn:SetSize(200, 30)
            btn.DoClick = function()
                CreateTripBlacklistMenu()
            end

            panel:AddItem(btn)

            panel:Help("Manage which NPCs can be tripped over")
            panel:Help("Only server administrators can access this menu")
        end)
end)

net.Receive("npc_trip_sync_blacklist", function()
end)
