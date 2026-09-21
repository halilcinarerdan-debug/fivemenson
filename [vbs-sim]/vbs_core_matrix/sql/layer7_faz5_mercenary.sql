-- =====================================================================
-- KATMAN 7 [FAZ 2] KATMAN 1+4: PARALI ASKER EKONOMİSİ + MALİ DENETİM
-- Additive migration. matrix.sql/layer5_ultimate.sql/layer7_faz*.sql'in
-- HİÇBİR mevcut tablosu/kolonu DEĞİŞTİRİLMEDİ, tek istisna aşağıda AÇIKÇA
-- gerekçelendirilen tek bir MODIFY COLUMN (nullability gevşetmesi, veri
-- kaybı YOK, mevcut satırlar etkilenmez).
-- =====================================================================

-- ---------------------------------------------------------------------
-- KATMAN 1: matrix_bots -- Ajan Maaşları / Zimmet için 3 yeni kolon.
-- accounting_precision: [0,1], diğer skill_* alanlarıYLA AYNI ölçek --
-- botun zimmet sırasındaki "verimliliği" (ne kadar yüksekse o kadar fazla
-- çalar). loss_report_total: atanan Lojistik Müdürü botun hanesine yazılan
-- kümülatif Kayıp Raporu (dolar). on_strike: maaş ödenemediğinde GREV
-- modu -- server/kitchen.lua Matrix.Kitchen.OnCaptured bunu okuyup
-- doğrudan (kısıtlamasız) sızıntı tetikler.
-- ---------------------------------------------------------------------
ALTER TABLE `matrix_bots`
    ADD COLUMN IF NOT EXISTS `accounting_precision` FLOAT NOT NULL DEFAULT 0.5
        COMMENT '[0,1]; zimmet formülünün verimlilik çarpanı'
        AFTER `loyalty_base`,
    ADD COLUMN IF NOT EXISTS `loss_report_total` FLOAT NOT NULL DEFAULT 0.0
        COMMENT 'Bu bot Lojistik Müdürü iken sorumlu tutulduğu kümülatif zimmet ($)'
        AFTER `accounting_precision`,
    ADD COLUMN IF NOT EXISTS `on_strike` TINYINT(1) NOT NULL DEFAULT 0
        COMMENT 'Maaş ödenemedi -- grev modu; yakalanınca DOĞRUDAN Büro sızıntısı tetikler'
        AFTER `loss_report_total`;

-- ---------------------------------------------------------------------
-- KATMAN 4: matrix_purchase_logs -- YENİ tablo. Her sahte fatura kaydı
-- (server/bureau.lua Matrix.FrontBusiness.RecordAuditableInvoice) buraya
-- düşer; günlük anomali sayacı (RAM) bu tablodan BESLENİR ama kalıcı
-- kanıt kaydı (asla silinmez) BURADADIR -- matrix_forensic_evidence İLE
-- AYNI "adli kayıt asla silinmez" felsefesi.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_purchase_logs` (
    `id`          INT          NOT NULL AUTO_INCREMENT,
    `zone_id`     INT          NOT NULL,
    `citizenid`   VARCHAR(50)  NULL,
    `amount`      DOUBLE       NOT NULL DEFAULT 0.0,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_purchase_logs_zone_created` (`zone_id`, `created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- ---------------------------------------------------------------------
-- KATMAN 4: matrix_zone_inspectors -- Mali Denetim Anomalisi 3 yeni kolonu
-- (zone_id PK, layer5_ultimate.sql'DEKİ SIGINT Inspector ataması İLE AYNI
-- tabloyu paylaşır -- talebin kendisi "matrix_zone_inspectors tablosunu
-- kullanarak" diyor).
--
-- ★ TEK MODIFY: `bot_id` NOT NULL'dan NULL'a gevşetilir. GEREKÇE: bu tablo
-- şimdiye kadar YALNIZCA "bu bölgeye SIGINT Inspector'ı atandı" satırları
-- tutuyordu (bot_id her zaman doluydu). Artık bir bölge, HİÇBİR Inspector
-- atanmadan da salt mali-denetim amaçlı bir satır taşıyabilir (audit_score/
-- warning_level/is_wiped). server/market.lua Matrix.Inspector.
-- LoadZoneInspectors zaten `row.bot_id` üzerinde bir TRUTHY kontrolü yapıyor
-- (`if row and row.zone_id and row.bot_id then`) -- NULL bot_id'li satırlar
-- o yükleyici tarafından SESSİZCE ATLANIR, mevcut SIGINT davranışı BİREBİR
-- AYNI kalır. Mevcut (dolu) satırlar bu MODIFY'dan hiçbir şekilde etkilenmez.
-- ---------------------------------------------------------------------
ALTER TABLE `matrix_zone_inspectors`
    MODIFY COLUMN `bot_id` INT NULL
        COMMENT 'NULL = bu satır yalnızca mali-denetim amaçlı, SIGINT Inspector atanmamış';

ALTER TABLE `matrix_zone_inspectors`
    ADD COLUMN IF NOT EXISTS `audit_score` DOUBLE NOT NULL DEFAULT 0.0
        COMMENT '[0,1]; matrix_purchase_logs hacminden türetilen doygun-üssel anomali skoru'
        AFTER `assigned_at`,
    ADD COLUMN IF NOT EXISTS `warning_level` INT NOT NULL DEFAULT 0
        COMMENT '0-3; Config.FrontBusiness.AuditWarningThresholds ile eşlenir'
        AFTER `audit_score`,
    ADD COLUMN IF NOT EXISTS `is_wiped` TINYINT(1) NOT NULL DEFAULT 0
        COMMENT 'audit_score=1.0 -> Mali Wipe tetiklendi, işletme KALICI olarak kapatıldı'
        AFTER `warning_level`;

-- =====================================================================
-- DOĞRULAMA SORGUSU (opsiyonel)
-- =====================================================================
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'matrix_bots'
--   AND COLUMN_NAME IN ('accounting_precision','loss_report_total','on_strike');
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'matrix_zone_inspectors'
--   AND COLUMN_NAME IN ('audit_score','warning_level','is_wiped');
