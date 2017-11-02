--[[
    CDatabase server hooks.
]]

-- Gamemode hooks.
hook.Add("bash_InitService", "CDatabase_OnInit", function()
    local db = getService("CDatabase");
    if db:IsConnected() then
        MsgLog(LOG_DB, "Database still connected, skipping.");
        return;
    end

    db:Connect();
end);
