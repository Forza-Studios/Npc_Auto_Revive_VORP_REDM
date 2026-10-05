-- coi_med_rev / server.lua

local Core = nil
pcall(function()
    Core = exports.vorp_core:GetCore()
end)

RegisterNetEvent("coi_med_rev:checkDoctors")
AddEventHandler("coi_med_rev:checkDoctors", function()
    local src = source
    if not Config.OnlyWhenNoDoctorsOnline then
        TriggerClientEvent("coi_med_rev:doRevive", src, true)
        return
    end

    local doctorCount = 0
    if Core and Core.getUsers then
        local ok, users = pcall(Core.getUsers)
        if ok and type(users) == "table" then
            for _, user in pairs(users) do
                if user and user.getUsedCharacter then
                    local char = user.getUsedCharacter
                    -- vorp: getUsedCharacter is a table with .job in most versions,
                    -- or a function in others - handle both
                    if type(char) == "function" then
                        local okc, c = pcall(char, user)
                        if okc and c and c.job == Config.DoctorJobName then
                            doctorCount = doctorCount + 1
                        end
                    elseif type(char) == "table" then
                        if char.job == Config.DoctorJobName then
                            doctorCount = doctorCount + 1
                        end
                    end
                end
            end
        end
    end

    if doctorCount == 0 then
        TriggerClientEvent("coi_med_rev:doRevive", src, true)
    else
        TriggerClientEvent("coi_med_rev:doRevive", src, false)
    end
end)

RegisterNetEvent("coi_med_rev:payFee")
AddEventHandler("coi_med_rev:payFee", function(amount)
    local src = source
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    if not Core then return end

    local ok, user = pcall(Core.getUser, src)
    if not ok or not user then return end

    local char = user.getUsedCharacter
    if type(char) == "function" then
        local okc, c = pcall(char, user)
        if okc and c and c.removeCurrency then
            pcall(c.removeCurrency, c, 0, amount)
        end
    elseif type(char) == "table" and char.removeCurrency then
        pcall(char.removeCurrency, char, 0, amount)
    end

    local msg = string.format(Config.Texts.feePaid, tostring(amount))
    TriggerClientEvent('vorp:TipBottom', src, msg, 4000)
end)
