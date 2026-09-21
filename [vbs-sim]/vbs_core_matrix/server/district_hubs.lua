-- =====================================================================
-- ★★★ KATMAN 7 [T4] FAZ 1: TOPLU SATIŞ HUB'LARI (District Distribution) ★★★
-- YENİ dosya. Mevcut hiçbir tabloya/formüle dokunmaz -- yalnızca zaten var
-- olan sistemlere (matrix_trap_stash_<id> ox_inventory stash'i, server/
-- market.lua Matrix.CashDecay.Deposit kirli-nakit hattı, server/bureau.lua
-- [T4] Matrix.Bureau.IsLockedDown) bağlanır.
--
-- F10 -> "Toplu Satış Hub Ata" (client menüsü bu resource'ta değil; burada
-- sunucu tarafı yetki/kalıcılık uç noktası hazırdır -- bkz. RegisterNetEvent
-- 'matrix:server:districtHubs:assign' ve test komutu /hubata) kritik bir
-- kavşağa bir hub atar. Atanan hub, HubDemandCycleSeconds periyodunda trap
-- house'un ortak deposundan (matrix_trap_stash_<id>) sabit/RNG'siz bir
-- miktar çeker ve MEVCUT Config.Market.StreetBasePricePerGram birim
-- fiyatıyla kirli nakite çevirir -- yeni bir ekonomi formülü İCAT EDİLMEZ.
--
-- BÜRO KİLİDİ: server/bureau.lua [T4]'ün 'matrix:internal:bureauLockdown'
-- yayınını dinler (raidIssued/raidResolved İLE AYNI pasif desen). Kilit
-- aktifken o trap house'a bağlı TÜM hub'lar dondurulur (active=0, locked=1)
-- -- demand-cycle ticker'ı onları otomatik atlar.
--
-- SIFIR RNG: bu dosyada math.random YOK.
-- =====================================================================

Matrix.DistrictHubs = Matrix.DistrictHubs or {}

local pairs, ipairs, tonumber, type = pairs, ipairs, tonumber, type

local Hubs      = {}   -- [id] = { id, trap_house_id, label, coords, active, locked }
local dirtyHubs = {}

local function Reply(src, msg)
    if type(src) == 'number' and src > 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { '[HUB]', msg } })
    else
        print(('[MATRIX:DISTRICT_HUBS:CONSOLE] %s'):format(msg))
    end
end

local function IsValidCoords(c)
    if type(c) ~= 'table' and type(c) ~= 'userdata' and type(c) ~= 'vector3' and type(c) ~= 'vector4' then return false end
    if c.x == nil or c.y == nil or c.z == nil then return false end
    if type(c.x) ~= 'number' or type(c.y) ~= 'number' or type(c.z) ~= 'number' then return false end
    if c.x ~= c.x or c.y ~= c.y or c.z ~= c.z then return false end
    return true
end

-- =====================================================================
-- LOAD / PERSIST (LoadTrapHouses İLE AYNI kalıp)
-- =====================================================================
function Matrix.DistrictHubs.LoadHubs()
    local rows = MySQL.query.await('SELECT * FROM matrix_district_hubs', {}) or {}
    for _, row in ipairs(rows) do
        Hubs[row.id] = {
            id            = row.id,
            trap_house_id = row.trap_house_id,
            label         = row.label or ('Hub #' .. row.id),
            coords        = vector3(row.coord_x or 0.0, row.coord_y or 0.0, row.coord_z or 0.0),
            active        = row.active == 1,
            locked        = row.locked == 1
        }
    end
    Matrix.Log('DISTRICT_HUB', '%d Toplu Satis Hub RAM onbellege yuklendi.', #rows)
end

CreateThread(function()
    Matrix.DistrictHubs.LoadHubs()
end)

local function FlushDirtyHubs()
    for id in pairs(dirtyHubs) do
        local hub = Hubs[id]
        if hub then
            MySQL.prepare('UPDATE matrix_district_hubs SET active = ?, locked = ? WHERE id = ?',
                { hub.active and 1 or 0, hub.locked and 1 or 0, id })
        end
        dirtyHubs[id] = nil
    end
end

CreateThread(function()
    local interval = Config.Persistence.TrapHouseFlushIntervalMs or 20000
    while true do
        Wait(interval)
        FlushDirtyHubs()
    end
end)

-- =====================================================================
-- ATAMA (F10 -> "Toplu Satış Hub Ata" arka ucu)
-- =====================================================================
function Matrix.DistrictHubs.Assign(trapHouseId, label, coords, dispatcherSrc)
    trapHouseId = tonumber(trapHouseId)
    if not trapHouseId or not Matrix.TrapHouses or not Matrix.TrapHouses[trapHouseId] then
        return false, 'no_trap_house'
    end
    if not IsValidCoords(coords) then return false, 'bad_coords' end

    if Matrix.Bureau and Matrix.Bureau.IsLockedDown and Matrix.Bureau.IsLockedDown(trapHouseId) then
        return false, 'bureau_lockdown'
    end

    local existingForTrap = 0
    for _, hub in pairs(Hubs) do
        if hub.trap_house_id == trapHouseId then existingForTrap = existingForTrap + 1 end
    end
    if existingForTrap >= (Config.DistrictHubs.MaxPerTrapHouse or 3) then
        return false, 'hub_limit_reached'
    end

    label = (type(label) == 'string' and label ~= '') and label or ('Hub #' .. trapHouseId)

    MySQL.insert([[
        INSERT INTO matrix_district_hubs (trap_house_id, label, coord_x, coord_y, coord_z, active, locked, created_at)
        VALUES (?, ?, ?, ?, ?, 1, 0, NOW())
    ]], { trapHouseId, label, coords.x, coords.y, coords.z },
    function(insertId)
        if not insertId then return end
        Hubs[insertId] = {
            id = insertId, trap_house_id = trapHouseId, label = label,
            coords = vector3(coords.x, coords.y, coords.z), active = true, locked = false
        }
        Matrix.Log('DISTRICT_HUB', 'Yeni Toplu Satis Hub #%d (trap #%d, %s) kuruldu.', insertId, trapHouseId, label)
    end)

    return true
end

RegisterNetEvent('matrix:server:districtHubs:assign', function(trapHouseId, label, coords)
    local src = source
    local ok, reason = Matrix.DistrictHubs.Assign(trapHouseId, label, coords, src)
    if not ok then
        Reply(src, reason == 'bureau_lockdown'
            and '[ADLI ANOMALI: BURO KILIDI DEVREDE] - Hub atamasi reddedildi.'
            or ('Hub atamasi basarisiz: %s'):format(tostring(reason)))
    else
        Reply(src, 'Toplu Satis Hub atama istegi gonderildi (async). /hublistele ile dogrulayin.')
    end
end)

-- /hubata [trapHouseId] [label] [x] [y] [z] -- F10 client menüsü henüz bu
-- resource'ta değilken de sunucu tarafını test etmek için (bkz. /traphouseekle
-- İLE AYNI disiplin: boşlukla ayrılmış argümanlar, virgül YOK).
RegisterCommand('hubata', function(src, args)
    local trapHouseId = tonumber(args[1])
    local label        = args[2]
    local x, y, z       = tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    if not trapHouseId or not x or not y or not z then
        Reply(src, 'Kullanim: /hubata [trapHouseId] [label] [x] [y] [z]'); return
    end

    local ok, reason = Matrix.DistrictHubs.Assign(trapHouseId, label, vector3(x, y, z), src)
    if not ok then
        Reply(src, ('Hub atamasi basarisiz: %s'):format(tostring(reason)))
    else
        Reply(src, 'Hub atama istegi gonderildi (async). /hublistele ile dogrulayin.')
    end
end, false)

RegisterCommand('hublistele', function(src)
    local count = 0
    for id, hub in pairs(Hubs) do
        count = count + 1
        Reply(src, ('#%d trap#%d "%s" | Aktif:%s Kilit:%s'):format(
            id, hub.trap_house_id, hub.label, tostring(hub.active), tostring(hub.locked)))
    end
    Reply(src, ('--- Toplam %d hub ---'):format(count))
end, false)


-- ★ KATMAN 7 FAZ 2: F10 "Otonom Depo Lojistigi" paneli. getRegionalFinancialReport
-- (server/market.lua) ILE AYNI desen: duz metin satirlari, yeni bir formul
-- ICAT EDILMEZ -- yalnizca yukaridaki Hubs tablosu okunur.
lib.callback.register('matrix:callback:getDistrictHubsReport', function(src)
    local lines = { '=== OTONOM DEPO LOJISTIGI (TOPLU SATIS HUBLARI) ===' }

    local count = 0
    for id, hub in pairs(Hubs) do
        count = count + 1
        local house = Matrix.TrapHouses and Matrix.TrapHouses[hub.trap_house_id]
        lines[#lines + 1] = ('Hub #%d -> Trap #%d (%s) | "%s" | Aktif:%s | Kilit:%s'):format(
            id, hub.trap_house_id, (house and house.label) or '?', hub.label,
            tostring(hub.active), tostring(hub.locked))
    end
    if count == 0 then
        lines[#lines + 1] = 'Henuz atanmis bir Toplu Satis Hub yok.'
    end

    return lines
end)

-- =====================================================================
-- BÜRO KİLİDİ DİNLEYİCİSİ (raidIssued/raidResolved İLE AYNI pasif desen)
-- =====================================================================
AddEventHandler('matrix:internal:bureauLockdown', function(trapHouseId, active)
    for id, hub in pairs(Hubs) do
        if hub.trap_house_id == trapHouseId then
            hub.locked = active and true or false
            if active then hub.active = false end
            dirtyHubs[id] = true
        end
    end
    if active then
        Matrix.Log('DISTRICT_HUB', 'Trap #%d icin tum hublar Buro Kilidi nedeniyle donduruldu.', trapHouseId)
    end
end)

-- =====================================================================
-- TALEP DÖNGÜSÜ: sabit-miktar (RNG'siz) toplu satış
-- Depo: matrix_trap_stash_<trapHouseId> (MEVCUT ox_inventory stash --
-- server/logistics.lua Matrix.Logistics.DispatchAmmoRun İLE AYNI API).
-- Ciro: Matrix.CashDecay.Deposit (server/market.lua, MEVCUT kirli-nakit
-- hattı) + Config.Market.StreetBasePricePerGram (MEVCUT birim fiyat).
-- =====================================================================
local function ProcessHubDemandCycle(hubId, hub)
    if not hub.active or hub.locked then return end
    if Matrix.Bureau and Matrix.Bureau.IsLockedDown and Matrix.Bureau.IsLockedDown(hub.trap_house_id) then return end

    local stashId = ('matrix_trap_stash_%d'):format(hub.trap_house_id)
    local invOk, inv = pcall(exports['ox_inventory'].GetInventory, exports['ox_inventory'], stashId)
    if not invOk or type(inv) ~= 'table' or type(inv.items) ~= 'table' then return end

    local batchGrams = Config.DistrictHubs.SaleBatchGrams or 10

    for _, item in pairs(inv.items) do
        if type(item) == 'table' and type(item.name) == 'string' and (tonumber(item.count) or 0) >= batchGrams then
            local removeOk = pcall(function()
                return exports['ox_inventory']:RemoveItem(stashId, item.name, batchGrams, item.metadata)
            end)
            if removeOk then
                local proceeds = batchGrams * (Config.Market.StreetBasePricePerGram or 20.0)
                Matrix.CashDecay.Deposit(hub.trap_house_id, proceeds)
                Matrix.Log('DISTRICT_HUB', 'Hub #%d (trap #%d, %s) toplu satis: %s x%d, ciro=%.1f (kirli nakite eklendi).',
                    hubId, hub.trap_house_id, hub.label, item.name, batchGrams, proceeds)
            end
            break
        end
    end
end

CreateThread(function()
    while true do
        Wait((Config.DistrictHubs.DemandCycleSeconds or 45) * 1000)
        for hubId, hub in pairs(Hubs) do
            local ok, err = pcall(ProcessHubDemandCycle, hubId, hub)
            if not ok then
                Matrix.Log('DISTRICT_HUB', '[HATA] ProcessHubDemandCycle #%d hata verdi (yutuldu): %s', hubId, tostring(err))
            end
        end
    end
end)

-- =====================================================================
-- ★★★ [FAZ 2] KATMAN 3: ON-DEMAND LOJİSTİK SEVK EMRİ (TEK SEFERLİK) ★★★
-- TAMAMEN YENİ bir EKLEMEDİR. Yukarıdaki periyodik ticker (Config.
-- DistrictHubs.DemandCycleSeconds, DEĞİŞTİRİLMEDİ) hâlâ pasif ekonomi
-- simülasyonu olarak çalışmaya devam eder -- bu, ONUN YERİNE GEÇMEZ, EK
-- bir yoldur: talep "Lojistik sevkiyat SADECE oyuncu F10 menüsünden emir
-- verdiğinde TEK SEFERLİK başlatılmalı" -- bu fonksiyon TAM OLARAK budur,
-- ProcessHubDemandCycle'ın (yukarıda, DEĞİŞTİRİLMEDİ) AYNI mantığını,
-- ticker'ı BEKLEMEDEN, oyuncunun tetiklediği AN bir kez çalıştırır. Yeni
-- bir ekonomi formülü İCAT EDİLMEZ.
-- =====================================================================
function Matrix.DistrictHubs.TriggerDispatch(src, hubId)
    hubId = tonumber(hubId)
    local hub = hubId and Hubs[hubId]
    if not hub then return false, 'bad_hub' end
    if not hub.active then return false, 'hub_inactive' end
    if hub.locked then return false, 'hub_locked' end
    if Matrix.Bureau and Matrix.Bureau.IsLockedDown and Matrix.Bureau.IsLockedDown(hub.trap_house_id) then
        return false, 'bureau_lockdown'
    end

    local ok, err = pcall(ProcessHubDemandCycle, hubId, hub)
    if not ok then
        Matrix.Log('DISTRICT_HUB', '[HATA][FAZ2] TriggerDispatch (on-demand) #%d hata verdi (yutuldu): %s', hubId, tostring(err))
        return false, 'processing_error'
    end

    Matrix.Log('DISTRICT_HUB', '[FAZ2][ON-DEMAND] Hub #%d icin tek seferlik lojistik sevk emri islendi (src=%s).',
        hubId, tostring(src))
    return true
end

lib.callback.register('matrix:callback:districtHubsDispatch', function(src, hubId)
    return Matrix.DistrictHubs.TriggerDispatch(src, hubId)
end)

-- /lojistiksevket [hubId] -- F10 "Lojistik Sevk Emri Ver" arka ucu; diğer
-- tüm test komutlarıyla AYNI disiplin (kısıtlama YOK, ACE'ye bırakılır).
RegisterCommand('lojistiksevket', function(src, args)
    local hubId = tonumber(args[1])
    if not hubId then Reply(src, 'Kullanim: /lojistiksevket [hubId]'); return end

    local ok, reason = Matrix.DistrictHubs.TriggerDispatch(src, hubId)
    if ok then
        Reply(src, ('Hub #%d icin tek seferlik lojistik sevk emri islendi.'):format(hubId))
    else
        local reasons = {
            bad_hub          = 'Gecersiz hub ID.',
            hub_inactive     = 'Hub aktif degil.',
            hub_locked       = 'Hub kilitli (Buro Ablukasi).',
            bureau_lockdown  = 'Baglantili trap house Buro Kilidi altinda.',
            processing_error = 'Isleme hatasi (log dosyasina bakin).'
        }
        Reply(src, ('Sevk basarisiz: %s'):format(reasons[reason] or tostring(reason)))
    end
end, false)

exports('TriggerHubDispatch', function(src, hubId) return Matrix.DistrictHubs.TriggerDispatch(src, hubId) end)


-- =====================================================================
-- ★★★ [FAZ 3] KATMAN 1: OTONOM SLIME ÇETE BÖLÜNMESİ VE SAVAŞ MOTORU ★★★
-- TAMAMEN YENİ bir EKLEMEDİR. Yukarıdaki hub sistemi (Hubs/ProcessHub
-- DemandCycle/TriggerDispatch) HİÇ DEĞİŞTİRİLMEDİ.
--
-- DÜRÜST KAPSAM NOTU: bu blok fiziksel/görsel düşman NPC'ler DOĞURMAZ
-- (ped spawn + combat AI, client tarafı gerektirir ve bu projenin sunucu-
-- ekonomisi mimarisinin TAMAMEN dışındadır). "Agresif alt fraksiyon"
-- burada EKONOMİK/İSTİHBARİ SAVAŞ olarak modellenir: her yeni slime hücresi,
-- ZATEN VAR OLAN Bureau sinyallerini (TriggerPropaganda/AdvanceDecryption/
-- RecordRadioBreach, server/bureau.lua, DEĞİŞTİRİLMEDİ) kullanarak AYNI
-- bölgedeki OYUNCU trap house'larını Büro'ya ihbar eder -- rakip çete,
-- rekabeti ortadan kaldırmak için Büro'yu SİLAH olarak kullanır (klasik
-- çete-savaşı troposunun deterministik/ekonomik karşılığı).
-- =====================================================================

Matrix.GangLearningCore = Matrix.GangLearningCore or {}

local SplinterCells      = {}   -- [id] = { id, origin_trap_house_id, zone_id, label, aggression_level, cyber_leak_heat, active }
local dirtySplinterCells = {}
local nextSplinterCellId


function Matrix.GangLearningCore.LoadSplinterCells()
    local rows = MySQL.query.await('SELECT * FROM matrix_gang_learning_core', {}) or {}
    local maxId = 0
    for _, row in ipairs(rows) do
        SplinterCells[row.id] = {
            id                   = row.id,
            origin_trap_house_id = row.origin_trap_house_id,
            zone_id              = row.zone_id,
            label                = row.label,
            aggression_level     = tonumber(row.aggression_level) or Config.DistrictHubs.SplinterBaseAggression,
            cyber_leak_heat      = tonumber(row.cyber_leak_heat) or 0.0,
            active               = row.active == 1
        }
        if row.id > maxId then maxId = row.id end
    end
    nextSplinterCellId = maxId + 1
    Matrix.Log('DISTRICT_HUB', '[FAZ3] %d slime hucresi RAM onbellege yuklendi.', #rows)
end

CreateThread(function()
    local ok, err = pcall(Matrix.GangLearningCore.LoadSplinterCells)
    if not ok then Matrix.Log('DISTRICT_HUB', '[HATA][FAZ3] LoadSplinterCells basarisiz (yutuldu): %s', tostring(err)) end
end)


function Matrix.GangLearningCore.CreateSplinterCell(originTrapHouseId, zoneId, label)
    if not nextSplinterCellId then return nil end

    local id = nextSplinterCellId
    nextSplinterCellId = nextSplinterCellId + 1

    SplinterCells[id] = {
        id                   = id,
        origin_trap_house_id = originTrapHouseId,
        zone_id              = zoneId,
        label                = label or ('Slime Hucre #%d'):format(id),
        aggression_level     = Config.DistrictHubs.SplinterBaseAggression,
        cyber_leak_heat      = 0.0,
        active               = true
    }
    dirtySplinterCells[id] = true
    return id
end


local function FlushDirtySplinterCells()
    for id in pairs(dirtySplinterCells) do
        local cell = SplinterCells[id]
        if cell then
            MySQL.prepare([[
                INSERT INTO matrix_gang_learning_core (id, origin_trap_house_id, zone_id, label, aggression_level, cyber_leak_heat, active)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    aggression_level = VALUES(aggression_level),
                    cyber_leak_heat  = VALUES(cyber_leak_heat),
                    active           = VALUES(active)
            ]], { id, cell.origin_trap_house_id, cell.zone_id, cell.label, cell.aggression_level, cell.cyber_leak_heat, cell.active and 1 or 0 })
        end
        dirtySplinterCells[id] = nil
    end
end

CreateThread(function()
    local interval = Config.Persistence.TrapHouseFlushIntervalMs or 20000
    while true do
        Wait(interval)
        FlushDirtySplinterCells()
    end
end)


-- Trap house'un lideri: o eve atanmış EN DÜŞÜK ID'li bot (deterministik
-- "kıdem" -- yeni bir rütbe/persist alanı İCAT EDİLMEZ). Matrix.Kitchen.
-- GetLogisticsManagerBot (server/kitchen.lua, role='runner' ile
-- SINIRLANDIRILMIŞ) İLE KARIŞTIRILMASIN -- lider TÜM rollerden en kıdemlisidir.
local function IsTrapHouseLeader(botId, trapHouseId)
    for otherId, otherBot in pairs(Matrix.Bots or {}) do
        if otherBot.state and otherBot.state.trap_house_id == trapHouseId and otherId < botId then
            return false
        end
    end
    return true
end


-- Hub'ları KALICI olarak dağıtır + bölgeyi (zone) 2-3 bağımsız slime
-- hücresine böler. RNG YOK: hücre sayısı trap house ID'sinin çift/tek
-- olmasından TÜRETİLİR -- sabit, tekrar-üretilebilir, "rastgele görünen
-- ama HER ZAMAN aynı trap house için aynı sonucu veren" bir kural (Katman
-- 6'nın ChecksumOf/deterministik-üretim felsefesiyle AYNI ruh).
function Matrix.DistrictHubs.FragmentTerritory(trapHouseId, cause)
    trapHouseId = tonumber(trapHouseId)
    local house = trapHouseId and Matrix.TrapHouses and Matrix.TrapHouses[trapHouseId]
    if not house then return false, 'no_trap_house' end

    local dissolved = 0
    for id, hub in pairs(Hubs) do
        if hub.trap_house_id == trapHouseId and not hub.locked then
            hub.active = false
            hub.locked = true
            dirtyHubs[id] = true
            dissolved = dissolved + 1
        end
    end

    local zoneId = Matrix.Inspector and Matrix.Inspector.GetZoneForTrapHouse
        and Matrix.Inspector.GetZoneForTrapHouse(trapHouseId)

    local splinterCount = (trapHouseId % 2 == 0) and 2 or 3
    local created = {}
    for i = 1, splinterCount do
        local id = Matrix.GangLearningCore.CreateSplinterCell(trapHouseId, zoneId, ('%s - Hucre %d'):format(house.label, i))
        if id then created[#created + 1] = id end
    end

    Matrix.Log('DISTRICT_HUB',
        '[FAZ3][PARCALANMA] Trap #%d (%s) lideri dustu (sebep:%s) -- %d hub dagitildi, %d yeni bagimsiz slime hucresi dogdu (Bolge #%s).',
        trapHouseId, house.label, tostring(cause), dissolved, #created, tostring(zoneId))

    return true, created
end


-- server/logistics.lua Matrix.Logistics.OnDealerEliminated'in (DEĞİŞTİRİLMEDİ,
-- yalnızca guard'lı tek satırlık bir çağrı eklendi) her BAŞARILI ölümünde
-- çağırdığı giriş noktası. Ölen bot lider DEĞİLSE hiçbir şey yapmaz.
function Matrix.DistrictHubs.OnGangLeaderEliminated(botId, trapHouseId, cause)
    botId = tonumber(botId)
    trapHouseId = tonumber(trapHouseId)
    if not botId or not trapHouseId or not Matrix.TrapHouses or not Matrix.TrapHouses[trapHouseId] then return false end

    if not IsTrapHouseLeader(botId, trapHouseId) then return false end

    return Matrix.DistrictHubs.FragmentTerritory(trapHouseId, cause)
end


-- "Pusu ve siber sızıntı döngüsü": aynı bölgede (zone_id) aktif bir OYUNCU
-- trap house'u varsa, rakip hücre rekabeti azaltmak için Büro'ya ihbar eder
-- -- MEVCUT Matrix.Bureau.TriggerPropaganda/RecordRadioBreach (server/
-- bureau.lua, DEĞİŞTİRİLMEDİ) YENİDEN kullanılır, yeni bir sızıntı formülü
-- İCAT EDİLMEZ. Pusu, forensics.lua'nın jam_accumulator'ı İLE AYNI 0-RNG
-- biriktirici deseniyle tetiklenir: aggression_level her döngüde birikir,
-- 1.0'ı geçtiği AN gerçek bir ihbar (RecordRadioBreach) patlar.
local function ProcessSplinterCellCycle(cell)
    if not cell.active or not cell.zone_id then return end

    local targetId = nil
    for id, house in pairs(Matrix.TrapHouses or {}) do
        if not house.raid_ordered and id ~= cell.origin_trap_house_id then
            local zoneOfHouse = Matrix.Inspector and Matrix.Inspector.GetZoneForTrapHouse and Matrix.Inspector.GetZoneForTrapHouse(id)
            if zoneOfHouse == cell.zone_id then
                targetId = id
                break
            end
        end
    end
    if not targetId then return end

    if Matrix.Bureau and Matrix.Bureau.TriggerPropaganda then
        Matrix.Bureau.TriggerPropaganda(targetId)
    end

    cell.cyber_leak_heat = (cell.cyber_leak_heat or 0.0) + cell.aggression_level
    if cell.cyber_leak_heat >= 1.0 then
        cell.cyber_leak_heat = cell.cyber_leak_heat - 1.0
        if Matrix.Bureau and Matrix.Bureau.RecordRadioBreach then
            Matrix.Bureau.RecordRadioBreach(targetId)
        end
        Matrix.Log('DISTRICT_HUB', '[FAZ3][PUSU] Slime Hucre #%d (%s) -- Bolge #%s icindeki Trap #%d icin Buroya ihbarda bulundu.',
            cell.id, cell.label, tostring(cell.zone_id), targetId)
    end

    dirtySplinterCells[cell.id] = true
end

CreateThread(function()
    while true do
        Wait((Config.DistrictHubs.SplinterCycleSeconds or 90) * 1000)
        for _, cell in pairs(SplinterCells) do
            local ok, err = pcall(ProcessSplinterCellCycle, cell)
            if not ok then
                Matrix.Log('DISTRICT_HUB', '[HATA][FAZ3] ProcessSplinterCellCycle #%d hata verdi (yutuldu): %s', cell.id, tostring(err))
            end
        end
    end
end)


RegisterCommand('slimedurum', function(src)
    local count = 0
    for id, cell in pairs(SplinterCells) do
        count = count + 1
        Reply(src, ('#%d "%s" -> Bolge:%s | Kokenttrap:%d | Agresyon:%.2f | Siber-Iz:%.2f | Aktif:%s'):format(
            id, cell.label, tostring(cell.zone_id), cell.origin_trap_house_id, cell.aggression_level, cell.cyber_leak_heat, tostring(cell.active)))
    end
    Reply(src, ('--- Toplam %d slime hucresi ---'):format(count))
end, false)

-- /liderdustu [trapHouseId] -- test amaçlı, gerçek bir ölüm beklemeden
-- parçalanmayı manuel tetikler (bkz. /baskinzorla İLE AYNI disiplin).
RegisterCommand('liderdustu', function(src, args)
    local trapHouseId = tonumber(args[1])
    if not trapHouseId or not Matrix.TrapHouses[trapHouseId] then Reply(src, 'Kullanim: /liderdustu [trapHouseId]'); return end
    local ok, created = Matrix.DistrictHubs.FragmentTerritory(trapHouseId, 'test_command')
    Reply(src, ok and ('Parcalanma tetiklendi -- %d yeni slime hucresi.'):format(#created) or 'Parcalanma basarisiz.')
end, false)

exports('FragmentTerritory',       function(trapHouseId, cause) return Matrix.DistrictHubs.FragmentTerritory(trapHouseId, cause) end)
exports('OnGangLeaderEliminated',  function(botId, trapHouseId, cause) return Matrix.DistrictHubs.OnGangLeaderEliminated(botId, trapHouseId, cause) end)