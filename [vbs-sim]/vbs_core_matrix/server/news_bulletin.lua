-- =====================================================================
-- ★★★ FAZ 2: DİNAMİK İSİM HAVUZLU ÖLÜM VE KRİMİNAL HABER BÜLTENİ ★★★
-- (server/news_bulletin.lua) — YENİ dosya. Mevcut hiçbir formüle/tabloya
-- DOKUNMAZ, yalnızca OKUR (Matrix.GetPoliceSources, matrix_customer_pool,
-- Matrix.Bureau.IsCorruptOfficer/PurgeOfficerPersonality) ve YENİ bir
-- yayın (client/hud.lua F10 HUD alt bandı) besler.
--
-- İKİ TETİKLEYİCİ:
--   (1) SİVİL BOT/AJAN ÖLÜMÜ — server/logistics.lua Matrix.Logistics.
--       OnDealerEliminated'in LETHAL_ELIMINATION_CAUSES kümesindeki bir
--       sebeple (combat/police_collision/police_busted) çağırdığı
--       Matrix.News.OnCivilianBotEliminated köprüsü.
--   (2) POLİS MEMURU ÖLÜMÜ — bu dosyanın KENDİ can takibi: main.lua
--       RefreshPoliceCache İLE AYNI ritimde (Config.NewsBulletin.
--       PoliceHealthPollMs), Matrix.GetPoliceSources()'taki her src'nin
--       GetEntityHealth(ped) değerini örnekler; >0'dan <=0'a geçiş
--       "öldürüldü" sayılır. Harici bir ölüm-olayı kaynağına (baseevents/
--       qb-ambulancejob) BAĞIMLI OLUNMAZ -- proje zaten bu dosya-yerel
--       "kendi ölçümünü kendin al" disiplinini main.lua/forensics.lua'da
--       (RefreshPoliceCache/RefreshFriskPoliceCache) KULLANIYOR.
--
-- İSİM SEÇİMİ: matrix_customer_pool'dan (MEVCUT tablo, YENİ bir isim
-- tablosu İCAT EDİLMEZ) asenkron çekilir. Hangi satırın seçileceği
-- ChecksumOf tabanlı deterministik bir OFFSET ile belirlenir -- ORDER BY
-- RAND() KULLANILMAZ (0 RNG standardı, server/bureau.lua/blackmarket.lua
-- İLE AYNI yerel-kopya ChecksumOf konvansiyonu).
-- =====================================================================

Matrix.News = Matrix.News or {}

local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local math_floor = math.floor

-- ★ bureau.lua/blackmarket.lua İLE AYNI yerel-kopya konvansiyonu -- "salt
-- her zaman kod içinde bir literal sabittir, Config'e TAŞINMAZ".
local function ChecksumOf(raw, salt)
    local sum = 0
    for i = 1, #raw do
        sum = (sum + (raw:byte(i) * (i + salt))) % 0xFFFFFFF
    end
    return sum
end


-- =====================================================================
-- YAYIN
-- =====================================================================
local queuedFlashCount = 0

local function BroadcastFlash(text)
    if not (Config.NewsBulletin and Config.NewsBulletin.Enabled) then return end
    if type(text) ~= 'string' or text == '' then return end

    -- ★ [S2] İLE AYNI disiplin: sınırsız kuyruk büyümesi istemcide RAM-bomb
    -- olur -- server tarafında da (bilgi amaçlı) bir tavan tutulur, aşımda
    -- en eski yayın atlanmadan (client kendi kuyruğunu kendi yönetir) yalnızca
    -- log seviyesinde bir uyarı basılır.
    queuedFlashCount = queuedFlashCount + 1
    if queuedFlashCount > (Config.NewsBulletin.MaxQueuedFlashes or 5) then
        queuedFlashCount = Config.NewsBulletin.MaxQueuedFlashes or 5
    end

    TriggerClientEvent('matrix:client:newsFlash', -1, {
        text     = text,
        duration = Config.NewsBulletin.FlashDurationMs or 9000
    })
    Matrix.Log('NEWS', text)
end


-- =====================================================================
-- DİNAMİK İSİM HAVUZU — matrix_customer_pool'dan deterministik seçim.
-- `name` kolonu tek bir serbest metin alanıdır (bkz. sql/matrix.sql) --
-- ilk boşluktan bölünerek firstname/lastname türetilir (şema DEĞİŞTİRİLMEZ).
-- =====================================================================
local function SplitName(fullName)
    if type(fullName) ~= 'string' or fullName == '' then
        return 'Bilinmeyen', 'Sahis'
    end
    local first, last = fullName:match('^(%S+)%s+(.+)$')
    if first and last then return first, last end
    return fullName, ''
end


local function PickFallbackName(seedKey)
    local pool = (Config.NewsBulletin and Config.NewsBulletin.FallbackNames) or { 'Bilinmeyen Sahis' }
    local idx = (ChecksumOf(tostring(seedKey), 47) % #pool) + 1
    return SplitName(pool[idx])
end


-- Asenkron: `callback(firstname, lastname)` sonuçla (veya fallback ile)
-- HER ZAMAN çağrılır -- DB hatasında/boş havuzda dahi bülten SESSİZCE
-- düşmez, edebi bir fallback isim kullanır.
local function ResolveDynamicName(seedKey, callback)
    local ok = pcall(function()
        MySQL.scalar('SELECT COUNT(*) FROM matrix_customer_pool', {}, function(total)
            total = tonumber(total) or 0
            if total <= 0 then
                local f, l = PickFallbackName(seedKey)
                callback(f, l)
                return
            end

            local idx = ChecksumOf(tostring(seedKey), 47) % total
            MySQL.query('SELECT name FROM matrix_customer_pool LIMIT 1 OFFSET ?', { idx }, function(rows)
                local row = type(rows) == 'table' and rows[1]
                if row and type(row.name) == 'string' and row.name ~= '' then
                    local f, l = SplitName(row.name)
                    callback(f, l)
                else
                    local f, l = PickFallbackName(seedKey)
                    callback(f, l)
                end
            end)
        end)
    end)
    if not ok then
        local f, l = PickFallbackName(seedKey)
        callback(f, l)
    end
end


-- =====================================================================
-- BÖLGE ETİKETİ — Matrix.Market.FindNearestZone (MEVCUT, market.lua)
-- üzerinden; bulunamazsa jenerik bir etiket kullanılır.
-- =====================================================================
local function ResolveZoneLabel(coords)
    if not coords or not (Matrix.Market and Matrix.Market.FindNearestZone) then
        return 'Bilinmeyen Bolge'
    end
    local zoneId = Matrix.Market.FindNearestZone(coords)
    if not zoneId then return 'Bilinmeyen Bolge' end
    for _, zoneCfg in ipairs(Config.Market.Zones) do
        if zoneCfg.id == zoneId then return zoneCfg.label end
    end
    return 'Bilinmeyen Bolge'
end


-- =====================================================================
-- (1) SİVİL BOT/AJAN ÖLÜMÜ
-- ★ ÖNEMLİ: OnDealerEliminated'i ÇAĞIRAN Matrix.Logistics.OnDealerEliminated
-- bu fonksiyonu bot SİLİNMEDEN ÖNCE (bkz. server/logistics.lua) çağırır --
-- bot.name/bot.state.coords burada HÂLÂ GEÇERLİDİR.
-- =====================================================================
function Matrix.News.OnCivilianBotEliminated(botId, bot, cause)
    if not (Config.NewsBulletin and Config.NewsBulletin.Enabled) then return end
    if not bot then return end

    local coords    = bot.state and bot.state.coords
    local zoneLabel = ResolveZoneLabel(coords)
    local seedKey   = ('BOT#%d#%s'):format(botId, tostring(cause))

    ResolveDynamicName(seedKey, function(firstname, lastname)
        BroadcastFlash(('[KRIMINAL BULTEN] %s bolgesinde cikan catismada sokak operatifi %s %s hayatini kaybetti.'):format(
            zoneLabel, firstname, lastname))
    end)
end


-- =====================================================================
-- (2) POLİS MEMURU ÖLÜMÜ — kendi can takibi (dış olay kaynağına bağımlı
-- DEĞİL, main.lua RefreshPoliceCache İLE AYNI "kendi ölçümünü kendin al"
-- disiplini).
-- =====================================================================
local LastOfficerHealth = {} -- src -> son bilinen can


local function HandleOfficerDeath(src, officerPed)
    local ok, player = pcall(function() return Matrix.QBX:GetPlayer(src) end)
    local citizenid  = ok and player and player.PlayerData and player.PlayerData.citizenid

    local coords    = officerPed and officerPed ~= 0 and GetEntityCoords(officerPed) or nil
    local zoneLabel = ResolveZoneLabel(coords)
    local seedKey   = ('OFFICER#%s#%d'):format(tostring(citizenid or src), Matrix.Now())

    -- ★ [OPSEC] YOZLAŞMIŞ POLİS TEMİZLİĞİ: bu memur en az bir kez rüşvet
    -- kabul ettiyse (bkz. server/bureau.lua CorruptOfficers), kişilik
    -- genetiği önbelleği VE rüşvet kanalı KALICI olarak imha edilir.
    local wasCorrupt = false
    if citizenid and Matrix.Bureau and Matrix.Bureau.IsCorruptOfficer and Matrix.Bureau.IsCorruptOfficer(citizenid) then
        wasCorrupt = true
        if Matrix.Bureau.PurgeOfficerPersonality then
            Matrix.Bureau.PurgeOfficerPersonality(citizenid)
        end
    end

    ResolveDynamicName(seedKey, function(firstname, lastname)
        local suffix = wasCorrupt and ' [OPSEC: yozlasmis kisilik genetigi ve rusvet kanali imha edildi]' or ''
        BroadcastFlash(('[BURO YASTA] %s bolgesinde cikan catismada Memur %s %s hayatini kaybetti!%s'):format(
            zoneLabel, firstname, lastname, suffix))
    end)
end


CreateThread(function()
    while true do
        Wait((Config.NewsBulletin and Config.NewsBulletin.PoliceHealthPollMs) or 1000)

        if Config.NewsBulletin and Config.NewsBulletin.Enabled and Matrix.GetPoliceSources then
            local sources = Matrix.GetPoliceSources()
            local seenNow = {}

            for src in pairs(sources) do
                seenNow[src] = true
                local ped = GetPlayerPed(src)
                if ped and ped ~= 0 then
                    local okHealth, health = pcall(GetEntityHealth, ped)
                    if okHealth and type(health) == 'number' then
                        local previous = LastOfficerHealth[src]
                        if previous and previous > 0 and health <= 0 then
                            local ok, err = pcall(HandleOfficerDeath, src, ped)
                            if not ok then
                                Matrix.Log('NEWS', '[HATA] HandleOfficerDeath hata verdi (yutuldu): %s', tostring(err))
                            end
                        end
                        LastOfficerHealth[src] = health
                    end
                else
                    LastOfficerHealth[src] = nil
                end
            end

            -- ayrılan/görevden çıkan memurların stale can kaydı temizlenir.
            for src in pairs(LastOfficerHealth) do
                if not seenNow[src] then LastOfficerHealth[src] = nil end
            end
        end
    end
end)
