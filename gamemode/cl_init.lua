-- Things that should be done, regardless of restart or JIT or whatever.
local function miscInit()
    -- Random seed!
    math.randomseed(os.time());

    -- Get rid of useless sandbox notifications.
    timer.Remove("HintSystem_OpeningMenu");
    timer.Remove("HintSystem_Annoy1");
    timer.Remove("HintSystem_Annoy2");
end

-- Base relies on sandbox elements.
DeriveGamemode("sandbox");

-- For now, we wil not be supporting JIT updates. However,
-- there is an OnReload hook to use.
if bash and bash.started then
    miscInit();
    hook.Run("OnReload", bash);
    return;
end

MsgC(Color(0, 255, 255), "======================== BASE STARTED ========================\n");

-- Global table for bash elements.
bash = bash or {};
bash.IsValid = function() return true; end
bash.startTime = SysTime();
bash.nonVolatile = bash.nonVolatile or {};

-- Refresh global table on restart.
bash.meta = {};
bash.services = {};
bash.plugins = {};

-- Include required base files.
include("core/cl_util.lua");
include("core/sh_const.lua");
include("core/sh_util.lua");
include("shared.lua");

-- Add default client data.
addClientData("Country", system.GetCountry);
addClientData("OS", function()
    if system.IsWindows() then
        return OS_WIN;
    elseif system.IsWindows() then
        return OS_OSX;
    elseif system.IsLinux() then
        return OS_LIN;
    else
        return OS_UNK;
    end
end);

-- Hooks for init process.
MsgLog(LOG_INIT, "Gathering preliminary data...");
hook.Run("GatherPrelimData_Base"); -- For all prelims that MUST come first.
hook.Run("GatherPrelimData");      -- Add network variable structures, finalize DB structure, etc.
MsgLog(LOG_INIT, "Initializing services...");
hook.Run("InitService_Base");      -- For all inits that MUST come first.
hook.Run("InitService");           -- Connect to DB, load /data files, etc.

-- Report startup time.
local len = math.Round(SysTime() - bash.startTime, 8);
MsgLog(LOG_INIT, "Successfully initialized base client-side. Startup: %fs", len);
MsgLog(color_cyan, "======================== BASE COMPLETE ========================");
bash.started = true;

MsgLog(LOG_DEF, "Doing post-init calls...");
hook.Run("PostInit_Base");         -- For all post-inits that MUST come first.
hook.Run("PostInit");              -- Finish up.
