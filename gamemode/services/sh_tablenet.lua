defineService_start("CTableNet");

-- Service info.
SVC.Name = "Core TableNet";
SVC.Author = "LilSumac";
SVC.Desc = "A framework for creating, networking, and adding persistant variables to tables and objects.";
SVC.Depends = {"CDatabase"};

-- Custom errors.
addErrType("TableNotRegistered", "This table has not been registered in TableNet! (%s)");
addErrType("NoDomainInTable", "No domain with that ID exists in that table! (%s -> %s)");
addErrType("UnauthorizedSend", "Tried sending a table to an unauthorized recipient! To force, use the 'force' argument. (%s:%s -> %s)");
addErrType("MultiSingleTable", "Tried to create a single table when one already exists! (%s)");

-- Service storage.
local domains = {};
local vars = {};
local registry = getNonVolatileEntry("CTableNet_Registry", EMPTY_TABLE);
local singlesMade = {};

-- Local functions.
local function runInits(tab, domain)
    local tablenet = getService("CTableNet");
    local varInfo, initFunc;
    for id, val in pairs(tab.TableNet[domain]) do
        varInfo = vars[domain][id];
        if !varInfo then continue; end

        if CLIENT and varInfo.OnInitClient then
            initFunc = varInfo.OnInitClient;
        elseif SERVER and varInfo.OnInitServer then
            initFunc = varInfo.OnInitServer;
        end
        if initFunc then
            initFunc(varInfo, tab, val);
        end
    end
end

function SVC:AddDomain(domain)
    if !domain then
        MsgErr("NilArgs", "domain");
        return;
    end
    if !domain.ID then
        MsgErr("NilField", "ID", "domain");
        return;
    end
    if domains[domain.ID] then
        MsgErr("DupEntry", domain.ID);
        return;
    end

    -- Domain fields.
    -- domain.ID = domain.ID; (Redundant, no default)
    -- domain.ParentMeta = domain.ParentMeta; (Redundant, no default);
    domain.StoredInSQL = domain.StoredInSQL or false;
    if SERVER and domain.StoredInSQL then
        if !domain.SQLTable then
            MsgErr("NilField", "SQLTable", "domain");
            return;
        end

        local cdb = getService("CDatabase");
        cdb:AddTable(domain.SQLTable);
    end

    domain.SingleTable = domain.SingleTable or false;

    local meta = domain.ParentMeta;
    if meta and !meta.GetNetVar then
        meta.GetNetVar = function(_self, domain, id)
            return _self:GetNetVars(domain, {id});
        end
        meta.GetNetVars = function(_self, domain, ids)
            if !domain then
                MsgErr("NilArgs", "domain");
                return;
            end
            if !ids then
                MsgErr("NilArgs", "ids");
                return;
            end

            if !_self.RegistryID or !_self.TableNet then
                MsgErr("TableNotRegistered", tostring(_self));
                return;
            end

            if !_self.TableNet[domain] then
                MsgErr("NoDomainInTable", domain, tostring(_self));
                return;
            end

            local tablenet = getService("CTableNet");
            if !tablenet:GetDomain(domain) then
                MsgErr("NilEntry", domain);
                return;
            end

            local results = {};
            for _, id in ipairs(ids) do
                if !tablenet:GetVariable(domain, id) then continue; end
                results[#results + 1] = _self.TableNet[domain][id];
            end

            return unpack(results);
        end
    end
    if SERVER and meta and !meta.SetNetVar then
        meta.SetNetVar = function(_self, domain, id, val)
            _self:SetNetVars(domain, {[id] = val});
        end
        meta.SetNetVars = function(_self, domain, data)
            if !domain then
                MsgErr("NilArgs", "domain");
                return;
            end
            if !data then
                MsgErr("NilArgs", "data");
                return;
            end

            if !_self.RegistryID or !_self.TableNet then
                MsgErr("TableNotRegistered", tostring(_self));
                return;
            end

            if !_self.TableNet[domain] then
                MsgErr("NoDomainInTable", domain, tostring(_self));
                return;
            end

            local tablenet = getService("CTableNet");
            if !tablenet:GetDomain(domain) then
                MsgErr("NilEntry", domain);
                return;
            end

            local ids = {};
            for id, val in pairs(data) do
                if !tablenet:GetVariable(domain, id) then continue; end

                _self.TableNet[domain][id] = val;
                ids[#ids + 1] = id;
            end

            tablenet:NetworkTable(_self.RegistryID, domain, ids);
        end
    end

    domain.GetRecipients = domain.GetRecipients or function(_self, tab)
        return player.GetInitializedAsKeys();
    end
    domain.GetPrivateRecipients = domain.GetPrivateRecipients or function(_self, tab)
        return {};
    end

    MsgCon("Registering domain: %s", domain.ID);
    domains[domain.ID] = domain;
    vars[domain.ID] = {};
end

function SVC:GetDomain(dom)
    return domains[dom];
end

function SVC:AddVariable(var)
    if !var then
        MsgErr("NilArgs", "var");
        return;
    end
    if !var.ID or !var.Domain then
        MsgErr("NilField", "ID/Domain", "var");
        return;
    end
    if !vars[var.Domain] then
        MsgErr("NilEntry", var.Domain);
        return;
    end
    if vars[var.Domain][var.ID] then
        MsgErr("DupEntry", var.ID);
        return;
    end

    -- Variable fields.
    -- var.ID = var.ID; (Redundant, no default)
    -- var.Domain = var.Domain; (Redundant, no default)
    var.Type = var.Type or "string";
    -- var.MaxLength = var.MaxLength;
    var.Public = var.Public or false;

    if SERVER then
        var.InSQL = var.InSQL or false;

        -- Charvar functions/hooks.
        var.OnGenerate = var.OnGenerate or DEFAULTS[var.Type];
        var.OnInitClient = nil;
        var.OnDeinitClient = nil;
        -- var.OnInitServer = var.OnInitServer; (Redundant, no default)
        -- var.OnDeinitServer = var.OnDeinitServer; (Redundant, no default)
    elseif CLIENT then
        var.OnGenerate = nil;
        var.OnInitServer = nil;
        var.OnDeinitServer = nil;
        -- var.OnInitClient = var.OnInitClient; (Redundant, no default)
        -- var.OnDeinitClient = var.OnDeinitClient; (Redundant, no default)
    end

    MsgCon(color_green, "Registering netvar %s in domain %s.", var.ID, var.Domain);
    vars[var.Domain][var.ID] = var;

    if SERVER and var.InSQL then
        local cdb = getService("CDatabase");
        local domInfo = domains[var.Domain];
        if !domInfo.StoredInSQL then return; end
        cdb:AddColumn(domInfo.SQLTable, {
            Name = var.ID,
            Type = var.Type,
            MaxLength = var.MaxLength
        }, var.PrimaryKey or false);
    end
end

function SVC:GetVariable(domain, var)
    return vars[domain][var];
end

function SVC:GetDomainVars(domain)
    if !domain then
        MsgErr("NilArgs", "domain");
        return;
    end

    if !vars[domain] then
        MsgErr("NilEntry", domain);
        return;
    end

    return vars[domain];
end

function SVC:NewTable(domain, data, obj, regID)
    if !domain then
        MsgErr("NilArgs", "domain");
        return;
    end

    local domInfo = domains[domain];
    if !domInfo then
        MsgErr("NilEntry", domain);
        return;
    end

    if domInfo.SingleTable and singlesMade[domain] then
        MsgErr("MultiSingleTable", domain);
        return;
    end

    local tab;
    if !obj then
        if domInfo.ParentMeta then
            tab = setmetatable({}, domInfo.ParentMeta);
        else
            tab = {};
        end
    else
        tab = obj;
    end

    data = data or {};
    local _data = {};
    for id, var in pairs(vars[domain]) do
        if CLIENT and !var.Public then continue; end

        if data[id] != nil then
            _data[id] = data[id];
        elseif SERVER and var.OnGenerate then
            _data[id] = handleFunc(var.OnGenerate, var, tab);
        end
    end

    tab.TableNet = tab.TableNet or {};
    tab.TableNet[domain] = _data;

    if regID then
        tab.RegistryID = regID;
        registry[regID] = tab;
    elseif !tab.RegistryID then
        local id = string.random(8, CHAR_ALL);
        while registry[id] do
            id = string.random(8, CHAR_ALL);
        end
        tab.RegistryID = id;
        registry[id] = tab;
    end

    if domInfo.SingleTable then
        singlesMade[domain] = tab.RegistryID;
    end

    MsgCon(color_blue, "Registering table in TableNet with domain %s. (%s)", domain, tab.RegistryID);
    PrintTable(registry);

    if SERVER then self:NetworkTable(tab.RegistryID, domain); end
    runInits(tab, domain);
    return tab;
end

function SVC:RemoveTable(id, domain)
    if !id then
        MsgErr("NilArgs", "id");
        return;
    end
    if !domain then
        MsgErr("NilArgs", "domain");
        return;
    end

    local tab = registry[id];
    if !tab then return; end
    if !tab.TableNet then return; end
    if !tab.TableNet[domain] then return; end

    if SERVER then
        local removePck = vnet.CreatePacket("CTableNet_Net_ObjOutOfScope");
        removePck:String(id);
        removePck:String(domain);
        removePck:Broadcast();
    end

    tab.TableNet[domain] = nil;
    if table.IsEmpty(tab.TableNet) then
        registry[id] = nil;
    end

    if singlesMade[domain] then
        singlesMade[domain] = nil;
    end
end

function SVC:GetNetVars(domain, ids)
    if !domain then
        MsgErr("NilArgs", "domain");
        return;
    end
    if !ids then
        MsgErr("NilArgs", "ids");
        return;
    end

    local tab = singlesMade[domain];
    if !tab then
        MsgErr("TableNotRegistered", domain);
        return;
    end
    tab = registry[tab];

    if !tab.TableNet[domain] then
        MsgErr("NoDomainInTable", domain, tostring(tab));
        return;
    end

    if !domains[domain] then
        MsgErr("NilEntry", domain);
        return;
    end

    local results = {};
    for _, id in ipairs(ids) do
        if !vars[domain][id] then continue; end

        --add onget?
        results[#results + 1] = tab.TableNet[domain][id];
    end

    return unpack(results);
end

function SVC:SetNetVars(domain, data)
    if !domain then
        MsgErr("NilArgs", "domain");
        return;
    end
    if !data then
        MsgErr("NilArgs", "data");
        return;
    end

    local tab = singlesMade[domain];
    if !tab then
        MsgErr("TableNotRegistered", domain);
        return;
    end
    tab = registry[tab];

    if !tab.TableNet[domain] then
        MsgErr("NoDomainInTable", domain, tostring(tab));
        return;
    end

    if !domains[domain] then
        MsgErr("NilEntry", domain);
        return;
    end

    local ids = {};
    for id, val in pairs(data) do
        if !vars[domain][id] then continue; end

        tab.TableNet[domain][id] = val;
        ids[#ids + 1] = id;
    end

    self:NetworkTable(tab.RegistryID, domain, ids);
end

if SERVER then

    -- Network pool.
    util.AddNetworkString("CTableNet_Net_ObjCount");
    util.AddNetworkString("CTableNet_Net_ObjUpdate");
    util.AddNetworkString("CTableNet_Net_ObjOutOfScope");

    local function onPlayerInit(ply)
        local tablenet = getService("CTableNet");
        if table.IsEmpty(registry) then
            MsgN("Empty registry!");
            -- jump past this step
            return;
        end

        net.Start("CTableNet_Net_ObjCount");
            net.WriteInt(table.Count(registry), 8);
        net.Send(ply);

        local delay = 0.1;
        for id, obj in pairs(registry) do
            if obj == NULL then continue; end

            for dom, vars in pairs(obj.TableNet) do
                timer.Simple(delay, function()
                    tablenet:SendTable(ply, id, dom);
                end);
                delay = delay + 0.1;
            end
        end

        timer.Simple(delay, function()
            ply.OnInitTask:Update("WaitForTableNet", 1);
        end);
    end

    -- Functions.
    function SVC:NetworkTable(id, domain, ids)
        if !id or !domain then
            MsgErr("NilArgs", "id/domain");
            return;
        end
        if !registry[id] then
            MsgErr("NilEntry", id);
            return;
        end
        if !domains[domain] then
            MsgErr("NilEntry", "domain");
            return;
        end
        local domInfo = domains[domain];

        local tab = registry[id];
        if !tab.RegistryID or !tab.TableNet then
            MsgErr("TableNotRegistered", tostring(tab));
            return;
        end
        if !tab.TableNet[domain] then
            MsgErr("NoDomainInTable", domain, tostring(tab));
            return;
        end

        local pubRecip = domInfo:GetRecipients(tab);
        local privRecip = domInfo:GetPrivateRecipients(tab);
        if pubRecip and privRecip and table.IsEmpty(pubRecip) and table.IsEmpty(privRecip) then return; end

        local pubPack = vnet.CreatePacket("CTableNet_Net_ObjUpdate");
        local privPack = vnet.CreatePacket("CTableNet_Net_ObjUpdate");
        pubPack:String(tab.RegistryID);
        pubPack:String(domain);
        privPack:String(tab.RegistryID);
        privPack:String(domain);

        local public = {};
        local private = {};
        local val;
        if ids then
            local varData;
            if type(ids) == "table" then
                for _, id in pairs(ids) do
                    varData = vars[domain][id];
                    if !varData then
                        MsgErr("NilEntry", id);
                        continue;
                    end

                    val = tab.TableNet[domain][id];
                    private[id] = val;
                    if varData.Public then
                        public[id] = val;
                    end
                end
            else
                varData = vars[domain][ids];
                if !varData then
                    MsgErr("NilEntry", ids);
                else
                    val = tab.TableNet[domain][ids];
                    private[ids] = val;
                    if varData.Public then
                        public[ids] = val;
                    end
                end
            end
        else
            for _id, _var in pairs(vars[domain]) do
                val = tab.TableNet[domain][_id];
                if val != nil then
                    private[_id] = val;
                    if _var.Public then
                        public[_id] = val;
                    end
                end
            end
        end

        pubPack:Table(public);
        pubPack:Bool(false);
        privPack:Table(private);
        privPack:Bool(false);
        if isentity(tab) or isplayer(tab) then
            pubPack:Bool(true);
            pubPack:Entity(tab);
            privPack:Bool(true);
            privPack:Entity(tab);
        else
            pubPack:Bool(false);
            privPack:Bool(false);
        end

        local excluded = player.GetAllAsKeys();

        if table.IsEmpty(pubRecip) then
            pubPack:Discard();
        else
            pubPack:AddTargets(pubRecip);
            pubPack:Send();

            for ply, _ in pairs(pubRecip) do
                excluded[ply] = nil;
            end
        end

        if table.IsEmpty(privRecip) then
            privPack:Discard();
        else
            privPack:AddTargets(privRecip);
            privPack:Send();

            for ply, _ in pairs(privRecip) do
                excluded[ply] = nil;
            end
        end

        if !table.IsEmpty(excluded) then
            local scopePck = vnet.CreatePacket("CTableNet_Net_ObjOutOfScope");
            scopePck:String(tab.RegistryID);
            scopePck:String(domain);
            scopePck:AddTargets(excluded);
            scopePck:Send();
        end
    end

    function SVC:SendTable(ply, id, domain, sendVars, force)
        if !isplayer(ply) then
            MsgErr("InvalidPly");
            return;
        end
        if !id then
            MsgErr("NilArgs", "id");
            return;
        end
        if !domain then
            MsgErr("NilArgs", "domain");
            return;
        end

        local domInfo = domains[domain];
        if !domInfo then
            MsgErr("NilEntry", "domain");
            return;
        end

        if !registry[id] then
            MsgErr("NilEntry", id);
            return;
        end

        local tab = registry[id];
        if !tab.RegistryID or !tab.TableNet then
            MsgErr("TableNotRegistered", tostring(tab));
            return;
        end
        if !tab.TableNet[domain] then
            MsgErr("NoDomainInTable", domain, tostring(tab));
            return;
        end

        local data = {};
        local recip;
        local isRecip, isPrivate = false, false;
        recip = domInfo:GetRecipients();
        isRecip = recip and recip[ply] or false;
        if !isRecip and !force then
            MsgErr("UnauthorizedSend", id, domain, tostring(ply));
            return;
        end

        recip = domInfo:GetPrivateRecipients();
        isPrivate = recip and recip[ply] or false;
        if sendVars then
            for _, _id in pairs(sendVars) do
                if !vars[domain][_id] then continue; end
                if !tab.TableNet[domain][_id] then continue; end

                if isPrivate or vars[domain][_id].Public then
                    data[_id] = val;
                end
            end
        else
            for _id, val in pairs(tab.TableNet[domain]) do
                if isPrivate or vars[domain][_id].Public then
                    data[_id] = val;
                end
            end
        end

        local sendPck = vnet.CreatePacket("CTableNet_Net_ObjUpdate");
        sendPck:String(tab.RegistryID);
        sendPck:String(domain);
        sendPck:Table(data);
        sendPck:Bool(false);
        if isentity(tab) or isplayer(tab) then
            sendPck:Bool(true);
            sendPck:Entity(tab);
        else
            sendPck:Bool(false);
        end

        sendPck:AddTargets(ply);
        sendPck:Send();
    end

    -- Hooks.
    hook.Add("GatherPrelimData", "CTableNet_AddTasks", function()
        local ctask = getService("CTask");
        ctask:AddTaskCallback("bash_PlayerPreInit", function(data)
            onPlayerInit(data["Player"]);
        end);
        ctask:AddTaskCondition("bash_PlayerOnInit", "WaitForTableNet", TASK_NUMERIC, 0, 1);
    end);

elseif CLIENT then

    -- Network hooks.
    net.Receive("CTableNet_Net_ObjCount", function(len)
        local tablenet = getService("CTableNet");
        local objs = net.ReadInt(8);
        tablenet.InitialSend = true;
        tablenet.WaitingOn = objs;
        tablenet.Received = 0;
        MsgCon(color_blue, "Waiting on %d networked objects...", objs);
    end);

    vnet.Watch("CTableNet_Net_ObjUpdate", function(pck)
        local regID = pck:String();
        local domain = pck:String();
        local data = pck:Table();
        local firstSend = pck:Bool();
        local obj;
        if pck:Bool() then
            obj = pck:Entity();
        end

        local tablenet = getService("CTableNet");
        local domInfo = tablenet:GetDomain(domain);
        local tab;
        if registry[regID] then
            tab = registry[regID];
            for id, val in pairs(data) do
                tab.TableNet[domain][id] = val;
            end
        else
            tab = tablenet:NewTable(domain, data, obj, regID);
        end

        if firstSend then
            tablenet.Received = tablenet.Received + 1;
            if tablenet.Received == tablenet.WaitingOn then
                MsgCon(color_blue, "Received all networked objects!");
            end
        end
    end);

    vnet.Watch("CTableNet_Net_ObjOutOfScope", function(pck)
        local regID = pck:String();
        local domain = pck:String();
        local tablenet = getService("CTableNet");
        tablenet:RemoveTable(regID, domain);
    end);

end

defineService_end();
