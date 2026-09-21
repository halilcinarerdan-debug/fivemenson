-- =====================================================================
-- ★★★ FAZ 2: PARAVAN ŞİRKET / SAHTE FATURA / ADLİ MUHASEBE ANOMALİSİ ★★★
-- (server/shell_company.lua) — YENİ dosya. Config.CashDecay/
-- Matrix.CashDecay.Launder (server/market.lua) ZATEN VAR ve DEĞİŞTİRİLMEDİ
-- -- bu dosya yeni bir ekonomi hattı İCAT ETMEZ, o MEVCUT aklama hattının
-- üzerine "meşru cephe" (paravan şirket) katmanı ekler:
--   trap house kirli nakdi -> Matrix.CashDecay.Launder -> qbx bank hesabı.
--
-- KAYIT UZAYI: matrix_zone_ledger/matrix_zone_inspectors ZATEN VAR ve
-- TAMAMEN FARKLI bir amaca (bölgesel P&L raporu / SIGINT denetleyici
-- ataması) hizmet ediyor -- bu FAZ 2 özelliği İÇİN o tabloları YENİDEN
-- KULLANMAK/EZMEK veri karışıklığına yol açardı. Bu yüzden İKİ YENİ tablo
-- (matrix_shell_ledger, matrix_shell_audits, bkz. sql/
-- matrix_financial_core.sql) kullanılır -- bkz. o dosyanın başlığındaki
-- KAPSAM KARARI.
--
-- SIFIR RNG: audit_score büyümesi Bureau.CyberLeakGeometricFactor İLE AYNI
-- üssel-biriktirici felsefesiyle SAF aritmetiktir.
-- =====================================================================

Matrix.ShellCompany = Matrix.ShellCompany or {}

local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local math_max = math.max

local function Reply(src, msg)
    if type(src) == 'number' and src > 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { '[PARAVAN SIRKET]', msg } })
    else
        print(('[MATRIX:SHELLCO:CONSOLE] %s'):format(msg))
    end
end


-- =====================================================================
-- RAM ÖNBELLEĞİ + YÜKLEME (LoadCashDecay İLE AYNI async-callback deseni)
-- =====================================================================
local ShellLedger = {} -- citizenid -> { zone_id, business_name, clean_balance, dirty_cash_pool }
local ShellAudits = {} -- citizenid -> { invoices_today, invoice_day_stamp, audit_score, warning_level, is_wiped }

local dirtyLedger = {}
local dirtyAudits = {}


local function LoadShellLedger()
    local callOk = pcall(function()
        MySQL.query('SELECT citizenid, zone_id, business_name, clean_balance, dirty_cash_pool FROM matrix_shell_ledger', {}, function(rows)
            pcall(function()
                if type(rows) == 'table' then
                    for _, row in ipairs(rows) do
                        if row and row.citizenid then
                            ShellLedger[row.citizenid] = {
                                zone_id         = tonumber(row.zone_id) or 0,
                                business_name   = row.business_name or 'Isimsiz Isletme',
                                clean_balance   = tonumber(row.clean_balance) or 0.0,
                                dirty_cash_pool = tonumber(row.dirty_cash_pool) or 0.0
                            }
                        end
                    end
                    Matrix.Log('SHELLCO', '%d paravan sirket defteri yuklendi.', #rows)
                end
            end)
        end)
    end)
    if not callOk then
        Matrix.Log('SHELLCO', '[HATA] matrix_shell_ledger sorgu cagrisi reddedildi; RAM bos baslatildi.')
    end
end


local function LoadShellAudits()
    local callOk = pcall(function()
        MySQL.query('SELECT citizenid, invoices_today, invoice_day_stamp, audit_score, warning_level, is_wiped FROM matrix_shell_audits', {}, function(rows)
            pcall(function()
                if type(rows) == 'table' then
                    for _, row in ipairs(rows) do
                        if row and row.citizenid then
                            ShellAudits[row.citizenid] = {
                                invoices_today    = tonumber(row.invoices_today) or 0,
                                invoice_day_stamp = row.invoice_day_stamp or os.date('%Y-%m-%d'),
                                audit_score       = tonumber(row.audit_score) or 0.0,
                                warning_level     = tonumber(row.warning_level) or 0,
                                is_wiped          = tonumber(row.is_wiped) == 1
                            }
                        end
                    end
                    Matrix.Log('SHELLCO', '%d mali denetim kaydi yuklendi.', #rows)
                end
            end)
        end)
    end)
    if not callOk then
        Matrix.Log('SHELLCO', '[HATA] matrix_shell_audits sorgu cagrisi reddedildi; RAM bos baslatildi.')
    end
end


CreateThread(function()
    LoadShellLedger()
    LoadShellAudits()
end)


local function TodayStamp() return os.date('%Y-%m-%d') end


local function EnsureAuditRow(citizenid)
    local audit = ShellAudits[citizenid]
    if not audit then
        audit = {
            invoices_today    = 0,
            invoice_day_stamp = TodayStamp(),
            audit_score       = 0.0,
            warning_level     = 0,
            is_wiped          = false
        }
        ShellAudits[citizenid] = audit
    end
    return audit
end


local function ResetDailyIfNeeded(audit)
    local today = TodayStamp()
    if audit.invoice_day_stamp ~= today then
        audit.invoice_day_stamp = today
        audit.invoices_today    = 0
    end
end


-- =====================================================================
-- İŞLETME KAYDI
-- =====================================================================
function Matrix.ShellCompany.RegisterBusiness(citizenid, zoneId, businessName)
    if type(citizenid) ~= 'string' or citizenid == '' then return false, 'bad_citizenid' end
    zoneId = tonumber(zoneId)
    if not zoneId then return false, 'bad_zone' end
    if type(businessName) ~= 'string' or businessName == '' then return false, 'bad_name' end
    businessName = businessName:sub(1, 80)

    local zoneExists = false
    for _, zoneCfg in ipairs(Config.Market.Zones) do
        if zoneCfg.id == zoneId then zoneExists = true break end
    end
    if not zoneExists then return false, 'bad_zone' end

    local ledger = ShellLedger[citizenid]
    if ledger then
        ledger.zone_id       = zoneId
        ledger.business_name = businessName
    else
        ledger = { zone_id = zoneId, business_name = businessName, clean_balance = 0.0, dirty_cash_pool = 0.0 }
        ShellLedger[citizenid] = ledger
    end
    dirtyLedger[citizenid] = true
    EnsureAuditRow(citizenid)
    dirtyAudits[citizenid] = true

    Matrix.Log('SHELLCO', '[PARAVAN SIRKET KURULDU] %s -> "%s" (bolge #%d)', citizenid, businessName, zoneId)
    return true
end


function Matrix.ShellCompany.GetStatus(citizenid)
    local ledger = citizenid and ShellLedger[citizenid]
    if not ledger then return nil end
    local audit = EnsureAuditRow(citizenid)
    ResetDailyIfNeeded(audit)
    return {
        zone_id         = ledger.zone_id,
        business_name   = ledger.business_name,
        clean_balance   = ledger.clean_balance,
        dirty_cash_pool = ledger.dirty_cash_pool,
        invoices_today  = audit.invoices_today,
        audit_score     = audit.audit_score,
        warning_level   = audit.warning_level,
        is_wiped        = audit.is_wiped
    }
end


-- =====================================================================
-- ★ ADLİ MUHASEBE ANOMALİSİ (0 RNG, Bureau.CyberLeakGeometricFactor İLE
-- AYNI üssel-biriktirici felsefesi):
--   excess = max(0, invoices_today - DailyInvoiceCapacity)
--   excessRatio = excess / DailyInvoiceCapacity
--   audit_score = clamp(audit_score*AuditGeometricFactor + excessRatio*AuditBaseIncrementPerExcessRatio, 0, 1)
--   >= AuditWarningRatio -> Mali Anomali Alarmi (bir kez, warning_level=1)
--   >= AuditWipeRatio    -> Mali Wipe (kalici el koyma, warning_level=2)
-- Kapasite İÇİNDEKİ fatura akışı audit_score'u HİÇ ETKİLEMEZ.
-- =====================================================================
function Matrix.ShellCompany.RecordInvoice(citizenid)
    local audit = EnsureAuditRow(citizenid)
    ResetDailyIfNeeded(audit)
    audit.invoices_today = audit.invoices_today + 1
    dirtyAudits[citizenid] = true

    local cap = Config.ShellCompany.DailyInvoiceCapacity
    local excess = math_max(0, audit.invoices_today - cap)
    if excess <= 0 then return end

    local excessRatio = excess / cap
    audit.audit_score = Matrix.Clamp(
        (audit.audit_score * Config.ShellCompany.AuditGeometricFactor)
            + (excessRatio * Config.ShellCompany.AuditBaseIncrementPerExcessRatio),
        0.0, 1.0
    )

    if audit.audit_score >= Config.ShellCompany.AuditWipeRatio and not audit.is_wiped then
        Matrix.ShellCompany.TriggerMaliWipe(citizenid)
        return
    end

    if audit.audit_score >= Config.ShellCompany.AuditWarningRatio and audit.warning_level < 1 then
        audit.warning_level = 1
        Matrix.Log('SHELLCO',
            '[MALI ANOMALI ALARMI] %s isletmesinde supheli fatura yogunlugu (bugun:%d/%d, skor=%.3f)',
            citizenid, audit.invoices_today, cap, audit.audit_score)
    end
end


-- ★ MALİ WIPE: Büro bu şirketin paravan olduğunu öğrendi -- yasal
-- şirketin BU SİSTEMİN takip ettiği tüm mal varlığına (clean_balance/
-- dirty_cash_pool) kalıcı olarak el konulur ve gelecekteki TÜM fatura
-- girişimleri koşulsuz reddedilir (bkz. IssueFakeInvoice is_wiped kontrolü).
function Matrix.ShellCompany.TriggerMaliWipe(citizenid)
    local audit = EnsureAuditRow(citizenid)
    audit.is_wiped      = true
    audit.warning_level = 2
    dirtyAudits[citizenid] = true

    local ledger = ShellLedger[citizenid]
    local seizedClean, seizedDirty = 0.0, 0.0
    if ledger then
        seizedClean, seizedDirty = ledger.clean_balance, ledger.dirty_cash_pool
        ledger.clean_balance   = 0.0
        ledger.dirty_cash_pool = 0.0
        dirtyLedger[citizenid] = true
    end

    Matrix.Log('SHELLCO',
        '[MALI WIPE] %s -- Buro paravan sirketi tespit etti. El konulan: temiz=%.1f kirli=%.1f (audit_score=%.3f)',
        citizenid, seizedClean, seizedDirty, audit.audit_score)
end


-- =====================================================================
-- SAHTE HİZMET FATURASI — MEVCUT Matrix.CashDecay.Launder üzerinden bir
-- trap house'un kirli nakdini bu paravan şirket cephesinden yasal bankaya
-- aktarır (LaunderReducesAmount kuralı: komisyon kesintisi otonom
-- hesaplanır).
-- =====================================================================
function Matrix.ShellCompany.IssueFakeInvoice(src, trapHouseId, amount)
    if type(src) ~= 'number' or src <= 0 then return false, 'bad_source' end
    trapHouseId = tonumber(trapHouseId)
    amount      = tonumber(amount)
    if not trapHouseId or not Matrix.TrapHouses or not Matrix.TrapHouses[trapHouseId] then
        return false, 'bad_trap_house'
    end
    if not amount or amount ~= amount then return false, 'bad_amount' end

    local ok, player = pcall(function() return Matrix.QBX:GetPlayer(src) end)
    if not ok or not player or not player.PlayerData then return false, 'player_unresolved' end
    local citizenid = player.PlayerData.citizenid
    if not citizenid then return false, 'player_unresolved' end

    local ledger = ShellLedger[citizenid]
    if not ledger then return false, 'no_business' end

    local audit = EnsureAuditRow(citizenid)
    if audit.is_wiped then return false, 'wiped' end

    amount = Matrix.Clamp(amount, Config.ShellCompany.MinInvoiceAmount, Config.ShellCompany.MaxInvoiceAmount)

    -- ★ MEVCUT aklama hattı: yetersiz kirli nakit VEYA Buro Kilidi
    -- (lockdown_active) aktifse Launder KENDİSİ reddeder -- burada
    -- İKİNCİ bir kontrol İCAT EDİLMEZ.
    local launderedOk, launderErr = Matrix.CashDecay.Launder(trapHouseId, amount)
    if not launderedOk then
        return false, launderErr or 'launder_failed'
    end

    local commission  = amount * Config.ShellCompany.InvoiceCommissionRate
    local netAmount    = amount - commission

    pcall(function() player.Functions.AddMoney('bank', netAmount, 'shell-company-invoice') end)

    ledger.clean_balance = ledger.clean_balance + netAmount
    dirtyLedger[citizenid] = true

    Matrix.ShellCompany.RecordInvoice(citizenid)

    Matrix.Log('SHELLCO',
        '[SAHTE FATURA] %s ("%s") -- trap #%d kirli nakit: -%.1f | komisyon:-%.1f | yasal bankaya:+%.1f',
        citizenid, ledger.business_name, trapHouseId, amount, commission, netAmount)

    return true, {
        gross_amount  = amount,
        commission    = commission,
        net_amount    = netAmount,
        audit_score   = audit.audit_score,
        warning_level = audit.warning_level
    }
end


-- =====================================================================
-- PERSISTENCE (FlushIntervalMs periyodik, market.lua FlushDirtyCash İLE
-- AYNI disiplin)
-- =====================================================================
local function FlushShellLedger()
    for citizenid in pairs(dirtyLedger) do
        local ledger = ShellLedger[citizenid]
        if ledger then
            MySQL.prepare([[
                INSERT INTO matrix_shell_ledger
                    (citizenid, zone_id, business_name, clean_balance, dirty_cash_pool, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, NOW(), NOW())
                ON DUPLICATE KEY UPDATE
                    zone_id = VALUES(zone_id), business_name = VALUES(business_name),
                    clean_balance = VALUES(clean_balance), dirty_cash_pool = VALUES(dirty_cash_pool),
                    updated_at = NOW()
            ]], { citizenid, ledger.zone_id, ledger.business_name, ledger.clean_balance, ledger.dirty_cash_pool })
        end
        dirtyLedger[citizenid] = nil
    end
end


local function FlushShellAudits()
    for citizenid in pairs(dirtyAudits) do
        local audit = ShellAudits[citizenid]
        if audit then
            MySQL.prepare([[
                INSERT INTO matrix_shell_audits
                    (citizenid, invoices_today, invoice_day_stamp, audit_score, warning_level, is_wiped, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, NOW())
                ON DUPLICATE KEY UPDATE
                    invoices_today = VALUES(invoices_today), invoice_day_stamp = VALUES(invoice_day_stamp),
                    audit_score = VALUES(audit_score), warning_level = VALUES(warning_level),
                    is_wiped = VALUES(is_wiped), updated_at = NOW()
            ]], { citizenid, audit.invoices_today, audit.invoice_day_stamp, audit.audit_score,
                  audit.warning_level, audit.is_wiped and 1 or 0 })
        end
        dirtyAudits[citizenid] = nil
    end
end


CreateThread(function()
    while true do
        Wait(Config.ShellCompany.FlushIntervalMs or 20000)
        local ok, err = pcall(function()
            FlushShellLedger()
            FlushShellAudits()
        end)
        if not ok then
            Matrix.Log('SHELLCO', '[HATA] Flush hata verdi (yutuldu): %s', tostring(err))
        end
    end
end)


-- =====================================================================
-- OX_LIB KÖPRÜSÜ + KOMUTLAR (diğer tüm mekaniklerle AYNI disiplin)
-- =====================================================================
lib.callback.register('matrix:callback:shellco:getStatus', function(src)
    local ok, player = pcall(function() return Matrix.QBX:GetPlayer(src) end)
    local citizenid = ok and player and player.PlayerData and player.PlayerData.citizenid
    if not citizenid then return nil end
    return Matrix.ShellCompany.GetStatus(citizenid)
end)


lib.callback.register('matrix:callback:shellco:registerBusiness', function(src, zoneId, businessName)
    local ok, player = pcall(function() return Matrix.QBX:GetPlayer(src) end)
    local citizenid = ok and player and player.PlayerData and player.PlayerData.citizenid
    if not citizenid then return false, 'player_unresolved' end
    return Matrix.ShellCompany.RegisterBusiness(citizenid, zoneId, businessName)
end)


lib.callback.register('matrix:callback:shellco:issueInvoice', function(src, trapHouseId, amount)
    return Matrix.ShellCompany.IssueFakeInvoice(src, trapHouseId, amount)
end)


RegisterCommand('paravankur', function(src, args)
    local zoneId = tonumber(args[1])
    table.remove(args, 1)
    local businessName = table.concat(args, ' ')
    if not zoneId or businessName == '' then
        Reply(src, 'Kullanim: /paravankur [bolgeId] [isletme adi]'); return
    end

    local ok, player = pcall(function() return Matrix.QBX:GetPlayer(src) end)
    local citizenid = ok and player and player.PlayerData and player.PlayerData.citizenid
    if not citizenid then Reply(src, 'Karakter cozumlenemedi.'); return end

    local regOk, reason = Matrix.ShellCompany.RegisterBusiness(citizenid, zoneId, businessName)
    Reply(src, regOk and ('Paravan sirket kuruldu: "%s" (bolge #%d)'):format(businessName, zoneId)
             or ('Basarisiz: %s'):format(tostring(reason)))
end, false)


RegisterCommand('sahtefatura', function(src, args)
    local trapHouseId = tonumber(args[1])
    local amount = tonumber(args[2])
    if not trapHouseId or not amount then
        Reply(src, 'Kullanim: /sahtefatura [trapHouseId] [tutar]'); return
    end

    local ok, result = Matrix.ShellCompany.IssueFakeInvoice(src, trapHouseId, amount)
    if ok then
        Reply(src, ('Sahte fatura kesildi: brut:%.1f komisyon:-%.1f net-bankaya:+%.1f (denetim skoru:%.3f)'):format(
            result.gross_amount, result.commission, result.net_amount, result.audit_score))
    else
        Reply(src, ('Basarisiz: %s'):format(tostring(result)))
    end
end, false)


RegisterCommand('paravandurum', function(src)
    local ok, player = pcall(function() return Matrix.QBX:GetPlayer(src) end)
    local citizenid = ok and player and player.PlayerData and player.PlayerData.citizenid
    local status = citizenid and Matrix.ShellCompany.GetStatus(citizenid)
    if not status then Reply(src, 'Kayitli bir paravan sirketiniz yok.'); return end

    Reply(src, ('"%s" | Temiz:%.1f Kirli:%.1f | Bugunku fatura:%d | Denetim skoru:%.3f | Uyari seviyesi:%d | Mali-Wipe:%s'):format(
        status.business_name, status.clean_balance, status.dirty_cash_pool,
        status.invoices_today, status.audit_score, status.warning_level, tostring(status.is_wiped)))
end, false)


exports('RegisterShellBusiness', function(citizenid, zoneId, name) return Matrix.ShellCompany.RegisterBusiness(citizenid, zoneId, name) end)
exports('IssueFakeInvoice',      function(src, trapHouseId, amount) return Matrix.ShellCompany.IssueFakeInvoice(src, trapHouseId, amount) end)
exports('GetShellCompanyStatus', function(citizenid) return Matrix.ShellCompany.GetStatus(citizenid) end)
