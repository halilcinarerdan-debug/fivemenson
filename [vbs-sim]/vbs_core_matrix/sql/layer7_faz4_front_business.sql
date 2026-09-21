-- =====================================================================
-- KATMAN 7 [FAZ 2] KATMAN 3: PARAVAN ISLETME MUHASEBE KOPRUSU
-- Additive migration. matrix_zone_ledger (layer5_ultimate.sql) hicbir
-- MEVCUT kolonu (zone_id/sale_count/total_grams/gross_revenue/net_profit/
-- price_crash_count/updated_at) DEGISTIRILMEDI -- server/market.lua'nin
-- KENDI zone-ekonomisi akisi bu migrasyondan ETKILENMEZ. Yalnizca BES
-- YENI, NULL/DEFAULT'lu kolon eklenir; bunlar server/bureau.lua'nin YENI
-- Matrix.FrontBusiness blogu tarafindan BAGIMSIZ okunur/yazilir.
--
-- NOT: `ADD COLUMN IF NOT EXISTS`, MySQL 8.0.29+ / MariaDB 10.0+ gerektirir
-- (sql/layer7_faz3.sql ILE AYNI konvansiyon -- oxmysql'in desteklediği
-- surumlerin tamami bunu karsilar).
-- =====================================================================
ALTER TABLE `matrix_zone_ledger`
    ADD COLUMN IF NOT EXISTS `owner_citizenid` VARCHAR(50) NULL
        COMMENT 'Paravan isletmeyi sahiplenen oyuncu; NULL = sahipsiz'
        AFTER `zone_id`,
    ADD COLUMN IF NOT EXISTS `business_label` VARCHAR(100) NULL
        COMMENT 'Config.FrontBusiness.Businesses[].business_label anlik kopyasi'
        AFTER `owner_citizenid`,
    ADD COLUMN IF NOT EXISTS `clean_balance` DOUBLE NOT NULL DEFAULT 0.0
        COMMENT 'Sahte fatura ile temizlenip bankaya aktarilan kumulatif toplam (rapor amacli)'
        AFTER `business_label`,
    ADD COLUMN IF NOT EXISTS `dirty_cash_pool` DOUBLE NOT NULL DEFAULT 0.0
        COMMENT 'Isletme kasasinda bekleyen, henuz aklanmamis kirli nakit'
        AFTER `clean_balance`,
    ADD COLUMN IF NOT EXISTS `dirty_deposited_at` DATETIME NULL
        COMMENT 'dirty_cash_pool icindeki yatirimin zamani -- Config.CashDecay.TraceHalfLifeRealDays ILE AYNI formul icin'
        AFTER `dirty_cash_pool`;

-- =====================================================================
-- DOĞRULAMA SORGUSU (opsiyonel)
-- =====================================================================
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'matrix_zone_ledger'
--   AND COLUMN_NAME IN ('owner_citizenid','business_label','clean_balance','dirty_cash_pool','dirty_deposited_at');
