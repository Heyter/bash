-- Base relies on sandbox elements.
DeriveGamemode("sandbox");

-- Use a reload hook that calls BEFORE files have been loaded.
if bash and bash.started then
    hook.Call("PreReload", bash);
end

-- Global table for bash elements.
bash = bash or {};
bash.IsValid = function() return true; end
bash.startTime = SysTime();
bash.nonVolatile = bash.nonVolatile or {};

-- Refresh global table on restart.
bash.meta = {};
bash.services = {};
bash.plugins = {};
bash.volatile = {};

-- Random seed!
math.randomseed(os.time());

-- Send required base files to client.
AddCSLuaFile("cl_init.lua");
AddCSLuaFile("core/sh_const.lua");
AddCSLuaFile("core/sh_util.lua");
AddCSLuaFile("shared.lua");

-- Include required base files.
include("core/sh_const.lua");
include("core/sh_util.lua");
include("shared.lua");

-- Report startup time.
local len = math.Round(SysTime() - bash.startTime, 8);
MsgCon(color_green, "Successfully initialized base server-side.  Startup: %fs", len);
bash.started = true;

-- Handle catching client data.
bash.clientData = getNonVolatileEntry("ClientData", EMPTY_TABLE);
vnet.Watch("bash_sendClientData", function(pck)
    local ply = pck.Source;
    local data = pck:Table();
    bash.clientData = bash.clientData or {};
    bash.clientData[ply:EntIndex()] = data;
end);
