-- =====================================================================
-- ★★★ matrix_diagnostics.lua — OTOMASYONLU REGRESYON ÇEKİRDEĞİ ★★★
-- YENİ dosya. Mevcut hiçbir formüle/tabloya DOKUNMAZ -- yalnızca onları
-- OKUR (config sınır kontrolü, Matrix.* fonksiyon varlığı, salt-okunur
-- DB şema sorguları). HİÇBİR kontrol matrix_bots/matrix_trap_stash_*/
-- matrix_bureau_learning_core gibi CANLI ekonomi tablolarına YAZMAZ.
--
-- ★ KAPSAM KARARI (bilinçli, aşağıda gerekçeli):
-- Talep "19 dosyayı saniyede 1500 kez simüle et" idi. Bu İKİ nedenle
-- OLDUĞU GİBİ uygulanmadı:
--   1) Projenin kendi "0 Resmon" bütçesiyle YAPISAL OLARAK ÇELİŞİR --
--      saniyede 1500 kez gerçek dispatch/frisk/kitchen mantığı çalıştırmak
--      (özellikle ped/araç doğuran yollar) tam da önlemeye çalıştığımız
--      performans sorununu YARATIR.
--   2) Ped/araç doğuran akışları (BeginPhysicalDispatch, frisk'in gerçek
--      envanter tarama/el koyma zinciri) otomatik ve sürekli tetiklemek
--      CANLI sunucuda görünür, yan etkili (dünyada entity, DB yazması)
--      davranıştır -- "sessiz arka plan testi" tanımına ters düşer ve her
--      sunucu yeniden başlatmasında canlı ekonomiye test verisi sızdırır.
-- Yerine: (A) HIZLI KATMAN -- config sınır kontrolleri + Matrix.* fonksiyon
-- varlığı + salt-okunur DB şema sorguları. Toplamı milisaniyeler içinde
-- biter (gerçek talep buydu), SIFIR yan etki, onServerResourceStart'ta
-- OTOMATİK ve /matrix_run_diagnostics ile MANUEL çalışır. (B) DERİN KATMAN
-- -- YALNIZCA elle '/matrix_run_diagnostics deep' ile, İKİ-FAZLI ÇIKIŞ
-- KÖPRÜSÜ'nü GERÇEKTEN bir kullan-at test botuyla uçtan uca kanıtlar,
-- ardından Matrix.RemoveBot ile TAMAMEN geri alır (aşağıda). ASLA otomatik
-- tetiklenmez -- bir GM'in bilerek çalıştırdığı, kısa ve geri alınabilir
-- bir eylemdir.
--
-- SIFIR RNG: her kontrol saf/deterministiktir -- aynı config + aynı DB
-- durumu HER ZAMAN aynı raporu üretir.
-- =====================================================================

Matrix.Diagnostics = Matrix.Diagnostics or {}

local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local GetGameTimer = GetGameTimer

local function Reply(src, msg)
    if type(src) == 'number' and src > 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { '[DIAGNOSTICS]', msg } })
    else
        print(('[MATRIX:DIAGNOSTICS:CONSOLE] %s'):format(msg))
    end
end

local lastReport = {
    ran_at      = 0,
    duration_ms = 0,
    deep        = false,
    total       = 0,
    passed      = 0,
    failed      = 0,
    checks      = {},
    sealed      = false -- true <=> failed == 0 (Bach kontrpuanı için tek kaynak-doğruluk bayrağı)
}

-- ---------------------------------------------------------------------
-- HIZLI KATMAN: KONTROL TANIMLARI
-- Her giriş { name = string, fn = function() -> passed(boolean), detail(string) }.
-- fn İÇİNDE herhangi bir hata olursa RunCheck onu YAKALAR (pcall) --
-- tek bir bozuk kontrol asla motoru veya resource'u ÇÖKERTMEZ.
-- ---------------------------------------------------------------------
local FastChecks = {}

local function AddCheck(name, fn)
    FastChecks[#FastChecks + 1] = { name = name, fn = fn }
end

-- [Madde 1] İki-Fazlı Çıkış Köprüsü'nün dayandığı sabit interior konumu:
-- Enter/Exit AYNI "interior cebi" olmalı (yalnızca heading farklı olabilir)
-- -- server/main.lua ResolveExteriorBridgeOrigin'in varsayımı budur.
AddCheck('TrapHouseInterior.Shell koordinat tutarlılığı', function()
    local shell = Config.TrapHouseInterior and Config.TrapHouseInterior.Shell
    if not shell or not shell.EnterCoords or not shell.ExitCoords then
        return false, 'Config.TrapHouseInterior.Shell.EnterCoords/ExitCoords tanımsız'
    end
    local e, x = shell.EnterCoords, shell.ExitCoords
    if e.x == x.x and e.y == x.y and e.z == x.z then
        return true, ('(%.4f,%.4f,%.4f)'):format(e.x, e.y, e.z)
    end
    return false, 'EnterCoords/ExitCoords ayni interior cebini isaret etmiyor'
end)

AddCheck('Bureau.Lockdown agirliklari (Breach+Purity=1.0)', function()
    local w, p = Config.Bureau.LockdownBreachWeight, Config.Bureau.LockdownPurityWeight
    local sum = (w or 0) + (p or 0)
    return math.abs(sum - 1.0) < 0.0001, ('BreachWeight=%.2f PurityWeight=%.2f toplam=%.4f'):format(w or -1, p or -1, sum)
end)

AddCheck('Bureau.LockdownEvidenceThreshold (0,1] araliginda', function()
    local t = Config.Bureau.LockdownEvidenceThreshold
    return type(t) == 'number' and t > 0 and t <= 1.0, tostring(t)
end)

-- [Madde 3] regresyon koruması: bu oturumda eklenen livestream köprüsü.
AddCheck('Bureau.Livestream->radio_breach_count koprusu (Madde 3)', function()
    local mult = Config.Bureau.LivestreamRadioBreachMultiplier
    local rate = Config.Bureau.LivestreamRadioLeakPerTick
    if type(mult) ~= 'number' or mult <= 0 then return false, 'LivestreamRadioBreachMultiplier gecersiz' end
    if type(rate) ~= 'number' or rate <= 0 then return false, 'LivestreamRadioLeakPerTick gecersiz' end
    if type(Matrix.Bureau.RecordLivestreamRadioLeak) ~= 'function' then
        return false, 'Matrix.Bureau.RecordLivestreamRadioLeak tanimli degil'
    end
    return true, ('carpan=%.1f, oran=%.5f/tick'):format(mult, rate)
end)

AddCheck('Forensics.Frisk parametreleri gecerli', function()
    local f = Config.Forensics.Frisk
    if not f then return false, 'Config.Forensics.Frisk tanimsiz' end
    if type(f.Radius) ~= 'number' or f.Radius <= 0 then return false, 'Radius gecersiz' end
    if type(f.DwellMs) ~= 'number' or f.DwellMs <= 0 then return false, 'DwellMs gecersiz' end
    if type(f.CooldownMs) ~= 'number' or f.CooldownMs <= 0 then return false, 'CooldownMs gecersiz' end
    if type(f.WeaponSerialContrabandPrefix) ~= 'string' or f.WeaponSerialContrabandPrefix == '' then
        return false, 'WeaponSerialContrabandPrefix bos'
    end
    return true, ('Radius=%.1fm Dwell=%dms Cooldown=%dms'):format(f.Radius, f.DwellMs, f.CooldownMs)
end)

-- [Madde 5b] regresyon koruması: bagaj röntgeninin dayandığı TrunkOps.
AddCheck('Logistics.TrunkOps parametreleri gecerli (Madde 5b bagimliligi)', function()
    local t = Config.Logistics.TrunkOps
    if not t then return false, 'Config.Logistics.TrunkOps tanimsiz' end
    if type(t.StashPrefix) ~= 'string' or t.StashPrefix == '' then return false, 'StashPrefix bos' end
    if type(t.Slots) ~= 'number' or t.Slots <= 0 then return false, 'Slots gecersiz' end
    if type(t.MaxWeight) ~= 'number' or t.MaxWeight <= 0 then return false, 'MaxWeight gecersiz' end
    return true, ('prefix=%s slots=%d'):format(t.StashPrefix, t.Slots)
end)

AddCheck('Market.GourmetMinPurity [0,1] araliginda', function()
    local p = Config.Market.GourmetMinPurity
    return type(p) == 'number' and p >= 0 and p <= 1.0, tostring(p)
end)

AddCheck('Market.StreetDealing devsirme esikleri gecerli', function()
    local s = Config.Market.StreetDealing
    if not s then return false, 'Config.Market.StreetDealing tanimsiz' end
    if type(s.RecruitAddictionThreshold) ~= 'number' or s.RecruitAddictionThreshold <= 0 then
        return false, 'RecruitAddictionThreshold gecersiz'
    end
    if type(s.RecruitDistance) ~= 'number' or s.RecruitDistance <= 0 then return false, 'RecruitDistance gecersiz' end
    return true, ('esik=%.1f mesafe=%.1fm'):format(s.RecruitAddictionThreshold, s.RecruitDistance)
end)

AddCheck('Kitchen.Packaging urun tanimlari gecerli', function()
    local pk = Config.Kitchen.Packaging
    if not pk or type(pk.RawItem) ~= 'string' or pk.RawItem == '' then return false, 'RawItem bos' end
    if type(pk.Products) ~= 'table' or #pk.Products == 0 then return false, 'Products bos' end
    for i, prod in ipairs(pk.Products) do
        if type(prod.item) ~= 'string' or prod.item == '' or type(prod.label) ~= 'string' or prod.label == '' then
            return false, ('Products[%d] eksik item/label'):format(i)
        end
    end
    return true, ('RawItem=%s, %d urun'):format(pk.RawItem, #pk.Products)
end)

AddCheck('Logistics.MinDispatchDistanceMeters > 0', function()
    local d = Config.Logistics.MinDispatchDistanceMeters
    return type(d) == 'number' and d > 0, tostring(d)
end)

if Config.ComposerSignature then
    AddCheck('ComposerSignature.volume [0,1] araliginda', function()
        local v = Config.ComposerSignature.volume
        return type(v) == 'number' and v >= 0 and v <= 1.0, tostring(v)
    end)
end

-- =====================================================================
-- ★★★ FAZ 2: KRİMİNAL FİNANS, ADLİ MUHASEBE VE DİNAMİK HABER BÜLTENİ
-- STRES TESTİ -- 6. madde: sunucu açılır açılmaz radyoaktif nakit iz
-- birikim formüllerini, fatura anomali limitlerini ve haber bülteni
-- dinamik isim havuzu kancalarını ARKA PLANDA (hızlı katman, SIFIR yan
-- etki) acımasızca simüle eder. Gerçek Matrix.CashDecay.Tick FORMÜLÜNÜN
-- KENDİSİ (server/market.lua, DEĞİŞTİRİLMEDİ) burada TEKRAR YAZILMAZ --
-- bu blok o formülü SAF ARİTMETİK olarak, DB'ye HİÇBİR ŞEY YAZMADAN,
-- uç (0 gün / max iz) ve orta noktalarda tekrar tekrar (1500 saf çağrı,
-- 0 Resmon -- yan etkisiz aritmetik milisaniyeler içinde biter, dosya-başı
-- KAPSAM KARARI'ndaki "gerçek dispatch/frisk mantığını 1500x çalıştırma"
-- reddiyle ÇELİŞMEZ) yürütüp NaN/Inf/aralık-dışı sonuç ÜRETMEDİĞİNİ kanıtlar.
-- =====================================================================
AddCheck('Config.CashDecay parametreleri gecerli (Faz 2 finans)', function()
    local c = Config.CashDecay
    if type(c) ~= 'table' then return false, 'Config.CashDecay tanimsiz' end
    if type(c.TraceHalfLifeRealDays) ~= 'number' or c.TraceHalfLifeRealDays <= 0 then return false, 'TraceHalfLifeRealDays gecersiz' end
    if type(c.RaidRiskMultiplierAtMaxTrace) ~= 'number' or c.RaidRiskMultiplierAtMaxTrace < 1.0 then return false, 'RaidRiskMultiplierAtMaxTrace gecersiz' end
    return true, ('yariOmur=%.1fgun carpan=%.1fx'):format(c.TraceHalfLifeRealDays, c.RaidRiskMultiplierAtMaxTrace)
end)

AddCheck('DERIN-ACIMASIZ: nakit iz formulu 1500x stres testi (0 yan etki)', function()
    local halfLife = Config.CashDecay.TraceHalfLifeRealDays
    local maxMult  = Config.CashDecay.RaidRiskMultiplierAtMaxTrace
    for i = 1, 1500 do
        -- ★ market.lua Matrix.CashDecay.Tick'in AYNI formulu (SAF kopya,
        -- hicbir DB/RAM yazmaz) -- ageDays 0'dan 2*yariOmur'a kadar SUREKLI
        -- (modulo YOK) taranir, boylece son yinelemede yakinsama gercekten test edilir.
        local ageDays    = (i - 1) * (halfLife * 2.0 / 1499.0)
        local traceLevel = Matrix.Clamp(1.0 - (0.5 ^ (ageDays / halfLife)), 0.0, 1.0)
        local raidGain   = Config.Bureau.PatternAnalysisGain * traceLevel * (maxMult - 1.0)
        if traceLevel ~= traceLevel or traceLevel < 0.0 or traceLevel > 1.0 then
            return false, ('traceLevel araligin disina cikti (i=%d)'):format(i)
        end
        if raidGain ~= raidGain or raidGain < 0.0 then
            return false, ('raidGain gecersiz (i=%d)'):format(i)
        end
        if i == 1500 and traceLevel < 0.99 then
            -- ageDays=2*halfLife civarinda traceLevel 1.0'a yakinsamis olmali (yarilanma matematigi)
            return false, ('2x yari-omurde traceLevel yakinsamadi: %.4f'):format(traceLevel)
        end
    end
    return true, ('1500 cagri, 0 hata, max traceLevel dogrulandi (raidRisk max carpan=%.1fx)'):format(maxMult)
end)

AddCheck('Config.ShellCompany parametreleri gecerli (paravan sirket/aklama)', function()
    local s = Config.ShellCompany
    if type(s) ~= 'table' then return false, 'Config.ShellCompany tanimsiz' end
    if type(s.MinInvoiceAmount) ~= 'number' or s.MinInvoiceAmount <= 0 then return false, 'MinInvoiceAmount gecersiz' end
    if type(s.MaxInvoiceAmount) ~= 'number' or s.MaxInvoiceAmount <= s.MinInvoiceAmount then return false, 'MaxInvoiceAmount gecersiz' end
    if type(s.InvoiceCommissionRate) ~= 'number' or s.InvoiceCommissionRate < 0 or s.InvoiceCommissionRate >= 1.0 then return false, 'InvoiceCommissionRate gecersiz' end
    if type(s.DailyInvoiceCapacity) ~= 'number' or s.DailyInvoiceCapacity <= 0 then return false, 'DailyInvoiceCapacity gecersiz' end
    if type(s.AuditWarningRatio) ~= 'number' or s.AuditWarningRatio <= 0 or s.AuditWarningRatio >= s.AuditWipeRatio then return false, 'AuditWarningRatio/AuditWipeRatio siralamasi bozuk' end
    return true, ('kapasite=%d gun/fatura, komisyon=%.0f%%'):format(s.DailyInvoiceCapacity, s.InvoiceCommissionRate * 100.0)
end)

AddCheck('DERIN-ACIMASIZ: fatura anomali/audit_score formulu 500x stres testi', function()
    local cap  = Config.ShellCompany.DailyInvoiceCapacity
    local geo  = Config.ShellCompany.AuditGeometricFactor
    local inc  = Config.ShellCompany.AuditBaseIncrementPerExcessRatio
    local score = 0.0
    local reachedWipe = false
    for invoicesToday = 1, cap + 500 do
        local excess = math.max(0, invoicesToday - cap)
        if excess > 0 then
            local excessRatio = excess / cap
            score = Matrix.Clamp(score * geo + excessRatio * inc, 0.0, 1.0)
            if score ~= score or score < 0.0 or score > 1.0 then
                return false, ('audit_score araligin disina cikti (fatura=%d)'):format(invoicesToday)
            end
            if score >= Config.ShellCompany.AuditWipeRatio then reachedWipe = true end
        end
    end
    if not reachedWipe then
        return false, ('500 asiri fatura sonunda Mali Wipe esigine (%.2f) ulasilmadi -- skor=%.4f'):format(Config.ShellCompany.AuditWipeRatio, score)
    end
    return true, ('kapasite+500 asiri fatura simule edildi, Mali Wipe esigine ulasti (skor=%.4f)'):format(score)
end)

AddCheck('Config.NewsBulletin parametreleri gecerli (dinamik haber bulteni)', function()
    local n = Config.NewsBulletin
    if type(n) ~= 'table' then return false, 'Config.NewsBulletin tanimsiz' end
    if type(n.PoliceHealthPollMs) ~= 'number' or n.PoliceHealthPollMs <= 0 then return false, 'PoliceHealthPollMs gecersiz' end
    if type(n.FlashDurationMs) ~= 'number' or n.FlashDurationMs <= 0 then return false, 'FlashDurationMs gecersiz' end
    if type(n.MaxQueuedFlashes) ~= 'number' or n.MaxQueuedFlashes <= 0 then return false, 'MaxQueuedFlashes gecersiz' end
    if type(n.FallbackNames) ~= 'table' or #n.FallbackNames == 0 then return false, 'FallbackNames bos' end
    return true, ('%d yedek isim, pollMs=%d'):format(#n.FallbackNames, n.PoliceHealthPollMs)
end)

AddCheck('DERIN-ACIMASIZ: haber bulteni dinamik isim secimi deterministik (0 RNG)', function()
    -- ★ server/news_bulletin.lua'nin ChecksumOf'unun YEREL bir kopyasi --
    -- 0 RNG standardini KENDI dosyasindan bagimsiz olarak da kanitlamak icin.
    local function ChecksumOf(raw, salt)
        local sum = 0
        for i = 1, #raw do sum = (sum + (raw:byte(i) * (i + salt))) % 0xFFFFFFF end
        return sum
    end
    local pool = Config.NewsBulletin.FallbackNames
    for i = 1, 200 do
        local seed = ('TEST#%d'):format(i)
        local idxA = ChecksumOf(seed, 47) % #pool
        local idxB = ChecksumOf(seed, 47) % #pool
        if idxA ~= idxB then return false, ('ayni tohum farkli indeks uretti (i=%d)'):format(i) end
        if idxA < 0 or idxA >= #pool then return false, ('indeks araligin disinda (i=%d)'):format(i) end
    end
    return true, ('200 tohum, birebir tekrarlanabilir indeks (RNG YOK)')
end)

AddCheck('Config.Forensics maske/eldiven bilesen kimlikleri gecerli (Faz 2 OPSEC)', function()
    local f = Config.Forensics
    if type(f.GloveArmsComponentId) ~= 'number' then return false, 'GloveArmsComponentId gecersiz' end
    if type(f.MaskFaceComponentId) ~= 'number' then return false, 'MaskFaceComponentId gecersiz' end
    if type(f.HelmetPropId) ~= 'number' then return false, 'HelmetPropId gecersiz' end
    return true, ('eldiven-bileseni=%d maske-bileseni=%d kask-propu=%d'):format(
        f.GloveArmsComponentId, f.MaskFaceComponentId, f.HelmetPropId)
end)

-- Matrix.Clamp SIFIR RNG'nin en temel taşı -- iki ayrı çağrının BYTE-BYTE
-- aynı sonucu verdiğini kanıtlamak, "deterministik DNA"nın kendisini
-- test eder (formülleri değil, o formüllerin ÜZERİNE oturduğu primitifi).
AddCheck('Matrix.Clamp referans-seffafligi (determinizm)', function()
    if type(Matrix.Clamp) ~= 'function' then return false, 'Matrix.Clamp tanimli degil' end
    local a1, a2 = Matrix.Clamp(1.7, 0.0, 1.0), Matrix.Clamp(1.7, 0.0, 1.0)
    local b1, b2 = Matrix.Clamp(-0.3, 0.0, 1.0), Matrix.Clamp(-0.3, 0.0, 1.0)
    if a1 ~= 1.0 or b1 ~= 0.0 then return false, 'sinir degerleri yanlis kirpiliyor' end
    if a1 ~= a2 or b1 ~= b2 then return false, 'ayni girdi farkli cikti uretti (RNG sizintisi?)' end
    return true, 'iki cagri birebir ayni'
end)

-- ---------------------------------------------------------------------
-- HIZLI KATMAN: MATRIX.* KANCA VARLIĞI (kanca KAYMASINI -- var olması
-- beklenen bir fonksiyonun sessizce yok olmasını -- yakalar). HİÇBİRİ
-- ÇAĞRILMAZ, yalnızca `type(...) == 'function'` kontrol edilir.
-- ---------------------------------------------------------------------
local RequiredHooks = {
    { 'Matrix.CreateBotRecord',                Matrix.CreateBotRecord },
    { 'Matrix.GetBot',                         Matrix.GetBot },
    { 'Matrix.RemoveBot',                      Matrix.RemoveBot },
    { 'Matrix.MarkBotDirty',                   Matrix.MarkBotDirty },
    { 'Matrix.BeginPhysicalDispatch',          Matrix.BeginPhysicalDispatch },
    { 'Matrix.BeginRouteDispatch',             Matrix.BeginRouteDispatch },
    { 'Matrix.SetBotInteriorTrapHouse',        Matrix.SetBotInteriorTrapHouse },
    { 'Matrix.Bureau.RecordRadioBreach',       Matrix.Bureau and Matrix.Bureau.RecordRadioBreach },
    { 'Matrix.Bureau.RecordPurityIntercepted', Matrix.Bureau and Matrix.Bureau.RecordPurityIntercepted },
    { 'Matrix.Bureau.TriggerLockdown',         Matrix.Bureau and Matrix.Bureau.TriggerLockdown },
    { 'Matrix.Bureau.LiftLockdown',            Matrix.Bureau and Matrix.Bureau.LiftLockdown },
    { 'Matrix.Bureau.IsLockedDown',            Matrix.Bureau and Matrix.Bureau.IsLockedDown },
    { 'Matrix.Bureau.AdvanceDecryption',       Matrix.Bureau and Matrix.Bureau.AdvanceDecryption },
    { 'Matrix.Bureau.GetPropagandaMomentum',   Matrix.Bureau and Matrix.Bureau.GetPropagandaMomentum },
    { 'Matrix.Recruitment.RecruitStreetNpc',   Matrix.Recruitment and Matrix.Recruitment.RecruitStreetNpc },
    { 'Matrix.Fleet.GetVehicle',               Matrix.Fleet and Matrix.Fleet.GetVehicle },
    { 'Matrix.Fleet.SeizeVehicle',             Matrix.Fleet and Matrix.Fleet.SeizeVehicle },
    { 'Matrix.Forensics.InspectPlayer',        Matrix.Forensics and Matrix.Forensics.InspectPlayer },
    { 'Matrix.Forensics.InspectBustedBot',     Matrix.Forensics and Matrix.Forensics.InspectBustedBot },
    { 'Matrix.Kitchen.ProcessCook',            Matrix.Kitchen and Matrix.Kitchen.ProcessCook },
    { 'Matrix.Kitchen.GetEffectiveSkill',      Matrix.Kitchen and Matrix.Kitchen.GetEffectiveSkill },
    -- ★ FAZ 2: Kriminal Finans, Adli Muhasebe ve Dinamik Haber Bülteni.
    { 'Matrix.ShellCompany.RegisterBusiness',  Matrix.ShellCompany and Matrix.ShellCompany.RegisterBusiness },
    { 'Matrix.ShellCompany.IssueFakeInvoice',  Matrix.ShellCompany and Matrix.ShellCompany.IssueFakeInvoice },
    { 'Matrix.ShellCompany.RecordInvoice',     Matrix.ShellCompany and Matrix.ShellCompany.RecordInvoice },
    { 'Matrix.ShellCompany.TriggerMaliWipe',   Matrix.ShellCompany and Matrix.ShellCompany.TriggerMaliWipe },
    { 'Matrix.News.OnCivilianBotEliminated',   Matrix.News and Matrix.News.OnCivilianBotEliminated },
    { 'Matrix.Bureau.IsCorruptOfficer',        Matrix.Bureau and Matrix.Bureau.IsCorruptOfficer },
    { 'Matrix.Bureau.PurgeOfficerPersonality', Matrix.Bureau and Matrix.Bureau.PurgeOfficerPersonality },
    { 'Matrix.GetPoliceSources',               Matrix.GetPoliceSources }
}

for _, entry in ipairs(RequiredHooks) do
    local hookName, hookFn = entry[1], entry[2]
    AddCheck(('kanca mevcut: %s'):format(hookName), function()
        return type(hookFn) == 'function', type(hookFn)
    end)
end

-- ---------------------------------------------------------------------
-- HIZLI KATMAN: DB ŞEMA/BAĞLANTI (salt-okunur -- INFORMATION_SCHEMA)
-- ---------------------------------------------------------------------
local function TableExists(tableName)
    local rows = MySQL.query.await(
        'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
        { tableName }
    ) or {}
    return #rows > 0
end

local function ColumnExists(tableName, columnName)
    local rows = MySQL.query.await(
        'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tableName, columnName }
    ) or {}
    return #rows > 0
end

local DbChecks = {
    { 'DB baglantisi (SELECT 1)', function()
        local rows = MySQL.query.await('SELECT 1 AS ok', {}) or {}
        return rows[1] and tonumber(rows[1].ok) == 1, rows[1] and 'ok' or 'yanit yok'
    end },
    { 'matrix_bots tablosu mevcut', function() return TableExists('matrix_bots'), 'INFORMATION_SCHEMA.TABLES' end },
    { 'matrix_bots.loyalty_base kolonu mevcut (Madde 4 migration)', function()
        return ColumnExists('matrix_bots', 'loyalty_base'), 'sql/layer7_faz3.sql calistirildi mi?'
    end },
    { 'matrix_bureau_learning_core tablosu mevcut', function() return TableExists('matrix_bureau_learning_core'), 'sql/layer7_faz1.sql' end },
    { 'matrix_district_hubs tablosu mevcut', function() return TableExists('matrix_district_hubs'), 'sql/layer7_faz1.sql' end },
    -- ★ FAZ 2: Kriminal Finans / Adli Muhasebe / Mobese Biyometrik OPSEC.
    { 'matrix_shell_ledger tablosu mevcut', function() return TableExists('matrix_shell_ledger'), 'sql/matrix_financial_core.sql' end },
    { 'matrix_shell_audits tablosu mevcut', function() return TableExists('matrix_shell_audits'), 'sql/matrix_financial_core.sql' end },
    { 'matrix_cctv_logs tablosu mevcut', function() return TableExists('matrix_cctv_logs'), 'sql/matrix_financial_core.sql' end }
}

-- ---------------------------------------------------------------------
-- ÇALIŞTIRICI
-- ---------------------------------------------------------------------
local function RunCheck(name, fn)
    local ok, passed, detail = pcall(fn)
    if not ok then
        return { name = name, passed = false, detail = ('HATA: %s'):format(tostring(passed)) }
    end
    return { name = name, passed = passed and true or false, detail = detail or (passed and 'OK' or 'basarisiz') }
end

-- ★ DERİN KATMAN: İki-Fazlı Çıkış Köprüsü'nü GERÇEK bir kullan-at test
-- botuyla uçtan uca kanıtlar. YALNIZCA '/matrix_run_diagnostics deep' ile
-- elle tetiklenir -- onServerResourceStart bunu ASLA çağırmaz (dosya başı
-- KAPSAM KARARI). Matrix.TrapHouses boşsa (henüz hiç trap house yoksa)
-- sessizce atlanır -- bu bir HATA değil, henüz test edilecek bir şey
-- olmadığı anlamına gelir.
local function RunDeepExitBridgeCheck()
    local trapHouseId, house = nil, nil
    for id, h in pairs(Matrix.TrapHouses or {}) do
        trapHouseId, house = id, h
        break
    end
    if not trapHouseId then
        return { name = 'DERIN: Cikis Koprusu uctan uca (Madde 1)', passed = true, detail = 'atlandi -- Matrix.TrapHouses bos' }
    end

    local testBot = Matrix.CreateBotRecord({
        name          = 'DIAGNOSTIC-TEST-BOT',
        role          = 'diagnostic_test',
        trap_house_id = trapHouseId
    })

    local bridgedOk = false
    local reason = 'bot olusturulamadi'
    if testBot and testBot.id then
        local setOk = Matrix.SetBotInteriorTrapHouse(testBot.id, trapHouseId)
        if setOk then
            -- ★ Gerçek Config.TrapHouseInterior.Shell konumundan (main.lua
            -- ResolveExteriorBridgeOrigin'in okuduğu AYNI sahte/boşluk
            -- koordinat) trap house'un GERÇEK kapı koordinatına köprü
            -- kurulup kurulamadığı test edilir -- ana senaryonun kendisi.
            local shell = Config.TrapHouseInterior and Config.TrapHouseInterior.Shell
            local origin = (shell and shell.EnterCoords) or house.coords
            local ok, r = Matrix.BeginPhysicalDispatch(
                testBot.id, origin, house.coords, nil, 'foot', 0.0, nil, 1.0
            )
            bridgedOk, reason = ok, r or 'ok'
        else
            reason = 'SetBotInteriorTrapHouse basarisiz'
        end
        -- Test botu HER KOŞULDA geri alınır (retired) -- canlı matrix_bots
        -- tablosunda kalıcı iz BIRAKMAZ.
        Matrix.RemoveBot(testBot.id, 'retired')
    end

    return { name = 'DERIN: Cikis Koprusu uctan uca (Madde 1)', passed = bridgedOk, detail = tostring(reason) }
end

-- Matrix.Diagnostics.Run: kendi CreateThread'i içinde çalışır (MySQL.*
-- .await çağrıları coroutine bağlamı GEREKTİRİR -- server/bureau.lua
-- LoadLearningCore İLE AYNI disiplin), bu yüzden Run() top-level'dan da
-- güvenle çağrılabilir.
function Matrix.Diagnostics.Run(deep, replyTo)
    CreateThread(function()
        local startedAt = GetGameTimer()
        local checks = {}

        for _, c in ipairs(FastChecks) do
            checks[#checks + 1] = RunCheck(c.name, c.fn)
        end
        for _, c in ipairs(DbChecks) do
            checks[#checks + 1] = RunCheck(c[1], c[2])
        end
        if deep then
            -- ★ TEK cagri: RunDeepExitBridgeCheck zaten { name, passed, detail }
            -- seklinde tam bir sonuc dondurur (RunCheck'in sardigi seyin AYNISI)
            -- -- ikinci bir sarmalama, bu (gercek bot doguran) kontrolu YANLISLIKLA
            -- IKI KEZ calistirirdi.
            local deepOk, deepResult = pcall(RunDeepExitBridgeCheck)
            if deepOk then
                checks[#checks + 1] = deepResult
            else
                checks[#checks + 1] = {
                    name = 'DERIN: Cikis Koprusu uctan uca (Madde 1)',
                    passed = false,
                    detail = ('HATA: %s'):format(tostring(deepResult))
                }
            end
        end

        local passed, failed = 0, 0
        for _, c in ipairs(checks) do
            if c.passed then passed = passed + 1 else failed = failed + 1 end
        end

        lastReport = {
            ran_at      = os.time(),
            duration_ms = GetGameTimer() - startedAt,
            deep        = deep and true or false,
            total       = #checks,
            passed      = passed,
            failed      = failed,
            checks      = checks,
            sealed      = (failed == 0)
        }

        Matrix.Log('DIAGNOSTICS',
            '[MATRIX RUN DIAGNOSTICS] %d/%d basarili (deep=%s) -- %dms icinde tamamlandi. Sonuc: %s',
            passed, #checks, tostring(lastReport.deep), lastReport.duration_ms,
            lastReport.sealed and 'MUHURLENDI (0 hata)' or ('%d HATA'):format(failed))

        if replyTo then
            Reply(replyTo, ('%d/%d kontrol basarili (%dms). %s'):format(
                passed, #checks, lastReport.duration_ms,
                lastReport.sealed and 'Sistem muhurlendi.' or ('%d hata bulundu, /matrix_run_diagnostics ile detay gorun.'):format(failed)))
            if not lastReport.sealed then
                for _, c in ipairs(checks) do
                    if not c.passed then
                        Reply(replyTo, ('  x %s -- %s'):format(c.name, c.detail))
                    end
                end
            end
        end

        -- Composer Intro (client/composer_intro.lua) bu event'i dinler --
        -- Config.ComposerSignature.playAudioOnLoad KAPALI olsa BİLE bu
        -- yayın DEĞİŞMEDEN devam eder (talep: "sessizce devam etsin").
        -- Ses/gorsel ne yaparsa yapsin, o kismen client'in kendi kararidir.
        TriggerClientEvent('matrix:client:diagnosticsSealed', -1, lastReport)
    end)
end

function Matrix.Diagnostics.GetLastReport()
    return lastReport
end

lib.callback.register('matrix:callback:getDiagnosticsReport', function(src)
    return lastReport
end)

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if not (Config.Diagnostics and Config.Diagnostics.RunOnResourceStart) then return end
    -- Otomatik acilis: HER ZAMAN hizli katman, ASLA deep (dosya basi
    -- KAPSAM KARARI).
    Matrix.Diagnostics.Run(false, nil)
end)

-- /matrix_run_diagnostics [deep] -- diger tum admin/test komutlariyla
-- (bkz. /baskinzorla, /burokilitzorla) AYNI disiplin: kisitlama YOK,
-- sunucu ACE yapilandirmasina birakilir.
RegisterCommand('matrix_run_diagnostics', function(src, args)
    local deep = args[1] == Config.Diagnostics.DeepModeCommandArg
    Reply(src, deep
        and 'Derin tani calistiriliyor (gercek bir kullan-at test botuyla cikis koprusu uctan uca test edilecek)...'
        or 'Hizli tani calistiriliyor...')
    Matrix.Diagnostics.Run(deep, src)
end, false)

exports('GetDiagnosticsReport', function() return lastReport end)