--[[
    Client utility functions.
]]

--
-- Local storage.
--

-- Micro-optimizations.
local bash          = bash;
local handleFunc    = handleFunc;
local Material      = Material;
local MsgErr        = MsgErr;
local pairs         = pairs;
local vnet          = vnet;

--
-- Utility functions.
--

-- Store all client data in a global table.
function bash.Util.AddClientData(id, generate)
    bash.ClientData = bash.ClientData or {};
    bash.ClientData[id] = generate;
end

-- Send stored client data to server.
function bash.Util.SendClientData()
    local send = vnet.CreatePacket("bash_Net_SendClientData");
    local data = {};
    for id, generate in pairs(bash.ClientData) do
        data[id] = handleFunc(generate);
    end

    send:Table(data);
    send:AddServer();
    send:Send();
end

-- Store and cache used materials for optimization.
function bash.Util.GetMaterial(mat)
    bash.Materials[mat] = bash.Materials[mat] or Material(mat);
    return bash.Materials[mat];
end
