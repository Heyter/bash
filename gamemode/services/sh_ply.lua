defineService_start("CPlayer");

-- Service info.
SVC.Name = "Core Player";
SVC.Author = "LilSumac";
SVC.Desc = "The main player functions for the gamemode.";
SVC.Depends = {"CDatabase", "CTableNet"};

-- Custom errors.
addErrType("MultiPlyRows", "Player '%s' has multiple player rows, using the first one. This can cause conflicts! Remove all duplicate rows ASAP!");

-- Local functions.
local function createPlyData(ply)
    MsgCon(color_sql, "Creating new entry for '%s'...", ply:Name());

    local tablenet = getService("CTableNet");
    local vars = tablenet:GetDomainVars("Player");
    local data = {};
    for id, var in pairs(vars) do
        data[id] = handleFunc(var.OnGenerate, var, ply);
    end

    local db = getService("CDatabase");
    db:InsertRow(
        "bash_plys",            -- Table to query.
        data,                   -- Data to insert.

        function(_ply, results) -- Callback function upon completion.
            ply.PreInitTask:PassData("SQLData", data);
            ply.PreInitTask:Update("WaitForSQL", 1);
        end,

        ply                     -- Argument #1 for callback.
    );
end

local function getPlyData(ply)
    MsgCon(color_sql, "Gathering player data for '%s'...", ply:Name());

    local db = getService("CDatabase");
    db:GetRow(
        "bash_plys",                                -- Table to query.
        "*",                                        -- Columns to get.
        Format("SteamID = \'%s\'", ply:SteamID()),  -- Condition to compare against.

        function(_ply, results)                     -- Callback function upon completion.
            if #results > 1 then
                MsgErr("MultiPlyRows", ply:Name());
            end

            results = results[1];
            if table.IsEmpty(results.data) then
                createPlyData(_ply);
            else
                MsgN("Found row...");
                ply.PreInitTask:PassData("SQLData", results.Data);
                ply.PreInitTask:Update("WaitForSQL", 1);
            end
        end,

        ply                                         -- Argument #1 for callback.
    );
end



if SERVER then

    -- Network pool.
    util.AddNetworkString("bash_test");

    -- Hooks.
    hook.Add("GatherPrelimData", "CPlayer_AddTasks", function()
        local ctask = getService("CTask");
        ctask:AddTaskCondition("bash_PlayerPreInit", "WaitForSQL", TASK_NUMERIC, 0, 1);

        ctask:AddTaskCallback("bash_PlayerPreInit", function(data)
            local tabnet = getService("CTableNet");
            tabnet:NewTable("Player", data["SQLData"], data["Player"]);
        end);
    end);

    hook.Add("PrePlayerInit", "CPlayer_CreatePlyNet", function(ply)
        getPlyData(ply);
    end);

end

-- Hooks.
hook.Add("GatherPrelimData_Base", "CPlayer_AddTables", function()
    local tablenet = getService("CTableNet");
    tablenet:AddDomain{
        ID = "Player",
        ParentMeta = FindMetaTable("Player"),
        StoredInSQL = true,
        SQLTable = "bash_plys"
    };

    tablenet:AddVariable{
        ID = "Name",
        Domain = "Player",
        Type = "string",
        MaxLength = 32,
        Public = true,
        InSQL = true,
        OnGenerate = function(_self, ply)
            return _self:OnInitialize(ply);
        end,
        OnInitialize = function(_self, ply, oldVal)
            return ply:Name();
        end
    };

    tablenet:AddVariable{
        ID = "SteamID",
        Domain = "Player",
        Type = "string",
        MaxLength = 18,
        Public = true,
        InSQL = true,
        PrimaryKey = true,
        OnGenerate = function(_self, ply)
            return ply:SteamID();
        end
    };

    tablenet:AddVariable{
        ID = "Addresses",
        Domain = "Player",
        Type = "table",
        MaxLength = 255,
        InSQL = true,
        OnGenerate = function(_self, ply)
            return {[ply:IPAddress()] = true};
        end,
        OnInitServer = function(_self, ply, oldVal)
            oldVal[ply:IPAddress()] = true;
            return oldVal;
        end
    };

    tablenet:AddVariable{
        ID = "FirstLogin",
        Domain = "Player",
        Type = "number",
        MaxLength = 10,
        Public = true,
        InSQL = true,
        OnGenerate = function(_self, ply)
            return os.time();
        end
    };

    tablenet:AddVariable{
        ID = "NewPlayer",
        Domain = "Player",
        Type = "boolean",
        Public = true,
        InSQL = true,
        OnGenerate = true,
        OnInitServer = function(_self, ply, oldVal)
            local playtime = ply:GetNetVar("Player", "Playtime");
            if playtime > 21600 then
                ply:SetNetVar("Player", "NewPlayer", false);
            end
        end
    };

    tablenet:AddVariable{
        ID = "Playtime",
        Domain = "Player",
        Type = "number",
        MaxLength = 10,
        Public = true,
        InSQL = true,
        OnGenerate = 0,
        OnInitServer = function(_self, ply, oldVal)
            ply.StartTime = CurTime();
        end,
        OnDeinitServer = function(_self, ply, oldVal)
            local startTime = ply.StartTime or CurTime();
            local played = CurTime() - startTime;
            local newTime = oldVal + played;
            ply:SetNetVar("Player", "Playtime", newTime);
        end
    };
end);

defineService_end();
