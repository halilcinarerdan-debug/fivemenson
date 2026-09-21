-- =====================================================================
-- FRONT BUSINESS CLIENT / client/front_business_client.lua
-- ★★★ [FAZ 2] KATMAN 3 KÖPRÜSÜ: PARAVAN İŞLETME OX_LIB PANOSU ★★★
-- TAMAMEN YENİ bir dosyadır. client/hud.lua'nın mevcut monokrom taktik
-- HUD'ına HİÇ DOKUNULMAZ -- sıfırdan bir HUD/NUI paneli ÜRETİLMEZ. Bu dosya
-- yalnızca server/bureau.lua'nın Matrix.FrontBusiness callback'lerini,
-- projenin ZATEN VAR OLAN bağımlılığı ox_lib'in yerel (NUI'siz)
-- lib.registerContext / lib.inputDialog bileşenlerine bağlar.
-- =====================================================================

local function NearestBusinessZone(coords)
    local nearest, nearestDist = nil, math.huge
    for _, z in ipairs(Config.Market.Zones) do
        local d = #(coords - z.coords)
        if d < nearestDist then nearest, nearestDist = z, d end
    end
    if not nearest then return nil end
    return nearest.id, nearestDist, nearest.radius
end


local function OpenInvoiceDialog(zoneId)
    local input = lib.inputDialog('Sahte Hizmet Faturasi Kes', {
        {
            type = 'number',
            label = 'Fatura Tutari ($)',
            description = ('Min:%d Max:%d'):format(Config.FrontBusiness.MinInvoiceAmount, Config.FrontBusiness.MaxInvoiceAmount),
            required = true
        }
    })
    if not input or not input[1] then return end

    local ok, detail = lib.callback.await('matrix:callback:frontBusinessInvoice', false, zoneId, tonumber(input[1]))
    if ok and type(detail) == 'table' then
        lib.notify({
            title = 'Paravan Isletme',
            description = ('Fatura kesildi: $%.0f temiz para bankaya aktarildi (komisyon %%%.1f).'):format(detail.net_clean, detail.commission * 100.0),
            type = 'success'
        })
    else
        lib.notify({ title = 'Paravan Isletme', description = tostring(detail), type = 'error' })
    end
end


local function OpenDepositDialog(zoneId)
    local input = lib.inputDialog('Kirli Nakit Yatir', {
        { type = 'number', label = 'Miktar ($)', required = true }
    })
    if not input or not input[1] then return end

    local ok, detail = lib.callback.await('matrix:callback:frontBusinessDeposit', false, zoneId, tonumber(input[1]))
    lib.notify({
        title = 'Paravan Isletme',
        description = ok and 'Nakit kasaya yatirildi.' or tostring(detail),
        type = ok and 'success' or 'error'
    })
end


local function OpenBusinessMenu(zoneId)
    local ledger = lib.callback.await('matrix:callback:frontBusinessLedger', false, zoneId)
    if not ledger then
        lib.notify({ title = 'Paravan Isletme', description = 'Isletme verisi okunamadi.', type = 'error' })
        return
    end

    local options = {
        {
            title = ledger.business_label or ('Isletme #%d'):format(zoneId),
            description = ('Sahip: %s | Kasa (kirli): $%.0f | Iz: %.0f%% | Komisyon: %%%.1f | Toplam Aklanan: $%.0f'):format(
                ledger.owner_citizenid or 'SAHIPSIZ', ledger.dirty_cash_pool,
                ledger.trace_level * 100.0, ledger.commission_rate * 100.0, ledger.clean_balance),
            disabled = true
        }
    }

    if not ledger.owner_citizenid then
        options[#options + 1] = {
            title = 'Isletmeyi Sahiplen',
            icon = 'building',
            onSelect = function()
                local ok, detail = lib.callback.await('matrix:callback:frontBusinessClaim', false, zoneId)
                lib.notify({
                    title = 'Paravan Isletme',
                    description = ok and 'Isletme sahiplenildi.' or tostring(detail),
                    type = ok and 'success' or 'error'
                })
            end
        }
    else
        options[#options + 1] = {
            title = 'Kirli Nakit Yatir',
            icon = 'money-bill-transfer',
            onSelect = function() OpenDepositDialog(zoneId) end
        }
        options[#options + 1] = {
            title = 'Sahte Hizmet Faturasi Kes',
            icon = 'file-invoice-dollar',
            onSelect = function() OpenInvoiceDialog(zoneId) end
        }
    end

    lib.registerContext({
        id = 'matrix_front_business_' .. tostring(zoneId),
        title = 'Paravan Isletme Panosu',
        options = options
    })
    lib.showContext('matrix_front_business_' .. tostring(zoneId))
end


-- /paravanpanel -- oyuncunun en yakın Config.Market.Zones bölgesinin
-- paravan işletme panosunu açar. Zone'un KENDİ (Katman 5, DEĞİŞTİRİLMEDİ)
-- yarıçapı kapsam kontrolü için yeniden kullanılır -- yeni bir mesafe
-- sabiti İCAT EDİLMEZ.
RegisterCommand('paravanpanel', function()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local zoneId, dist, radius = NearestBusinessZone(coords)

    if not zoneId or dist > (radius or 0.0) then
        lib.notify({ title = 'Paravan Isletme', description = 'Yakinda bir paravan isletme bolgesi yok.', type = 'error' })
        return
    end

    OpenBusinessMenu(zoneId)
end, false)
