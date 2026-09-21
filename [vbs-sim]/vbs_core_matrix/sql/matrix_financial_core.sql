-- =====================================================================
-- MATRIX FİNANSAL ÇEKİRDEK KONSOLİDASYONU / sql/matrix_financial_core.sql
--
-- ★ KAPSAM KARARI (bilinçli, gerekçeli):
-- Talep, projedeki TÜM finansal tabloları (matrix_cash_decay,
-- matrix_zone_ledger, matrix_zone_inspectors, matrix_blackmarket_purchases,
-- matrix_pending_refunds) ve matrix_cctv_network.sql'in içeriğini TEK bir
-- ana dosyada birleştirmekti. Bu OLDUĞU GİBİ uygulanmadı -- bilinçli
-- gerekçe:
--
--   matrix_cash_decay (sql/matrix.sql), matrix_zone_ledger/
--   matrix_zone_inspectors/matrix_blackmarket_purchases (sql/
--   layer5_ultimate.sql) ve matrix_pending_refunds (sql/
--   matrix_security_hardening.sql) HÂLİHAZIRDA server/market.lua,
--   server/blackmarket.lua ve server/matrix_diagnostics.lua tarafından
--   BİREBİR bu şemalarla (bu görevin 1. maddesinde istenen
--   business_name/clean_balance/dirty_cash_pool veya audit_score/
--   warning_level/is_wiped kolonlarıyla DEĞİL -- gerçek üretim şeması
--   farklıdır) canlı olarak kullanılıyor. Bu tabloları burada AYNI isimle
--   FARKLI bir şemayla yeniden CREATE ETMEK ya (a) CREATE TABLE IF NOT
--   EXISTS sayesinde sessizce YOK SAYILIR (yanıltıcı, ölü kod) ya da (b)
--   birileri "gerçek" tanımı burada sanıp ADLİ MİGRASYON DİSİPLİNİNİ
--   (bkz. sql/layer5_ultimate.sql başlığı: "matrix.sql'deki tablolara
--   HİÇBİRİNE DOKUNULMAZ") ihlal ederdi. Bu yüzden mevcut 5 tablo burada
--   YENİDEN YAZILMAZ -- konumları aşağıda tek bir referans haritasında
--   belgelenir.
--
-- Bunun yerine bu dosya GERÇEK konsolidasyonu üstlenir:
--   (A) sql/matrix_cctv_network.sql'in TEK tablosu (matrix_cctv_logs)
--       BURAYA TAŞINDI -- eski dosya artık YOKTUR, bu onun yerine geçen
--       tek gerçek kaynaktır (server/forensics.lua hiçbir yerde eski
--       dosya adına referans vermiyordu, bu yüzden taşıma GÜVENLİDİR).
--   (B) FAZ 2 "Paravan Şirket / Sahte Fatura / Adli Muhasebe Anomalisi"
--       özelliğinin İKİ YENİ tablosu (matrix_shell_ledger,
--       matrix_shell_audits) burada TANIMLANIR -- bunlar bu görevin 1.
--       maddesindeki business_name/clean_balance/dirty_cash_pool ve
--       audit_score/warning_level/is_wiped kolon sözleşmesini BİREBİR
--       karşılar (bkz. server/shell_company.lua).
--
-- Tüm konvansiyonlar sql/layer5_ultimate.sql ile AYNI:
--   - ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
--   - "ON UPDATE CURRENT_TIMESTAMP" KULLANILMAZ (bazı MariaDB/MySQL
--     derlemelerinde CREATE TABLE'ı sessizce başarısız kılıyordu) --
--     `updated_at` uygulama katmanında (server/shell_company.lua) her
--     UPSERT'te explicit NOW() ile yazılır.
--   - FK YOK (matrix_zone_inspectors İLE AYNI kasıtlı tasarım kararı):
--     citizenid burada bir oyuncu karakterini işaret eder ve hard-delete
--     edilmez, ama bu tablolar KENDİ ekonomisinin dışına FK ile bağlanıp
--     ileride bir migration/temizlik akışını bloke etmesin diye bilinçli
--     olarak gevşek bağlı tutulur.
--
-- matrix.sql + layer5_ultimate.sql + layer6_trap_house.sql +
-- layer7_faz1.sql + layer7_faz3.sql + matrix_security_hardening.sql
-- İMPORT EDİLDİKTEN SONRA, FOREIGN_KEY_CHECKS zaten 1'e dönmüş haldeyken
-- import edilmelidir.
-- =====================================================================


-- =====================================================================
-- (A) MOBESE DAĞITIM KUTUSU KAYITLARI — eski sql/matrix_cctv_network.sql
-- içeriğinin AYNISI, yalnızca taşındı. server/forensics.lua
-- Matrix.Forensics.HackCCTVNetwork bu tabloyu (zone başına, son 30dk,
-- maskesiz/şüpheli satırlar) siler. ★ Artık (bu FAZ 2 güncellemesiyle)
-- server/forensics.lua Matrix.Forensics.InspectPlayer (mobese/üst arama
-- döngüsü) HER dwell tamamlanan şüpheli için GERÇEK bir maske/kask
-- gözlemi (GetPedDrawableVariation/GetPedPropIndex) yazar -- eskiden
-- YALNIZCA /cctvkaydet test komutuyla elle doldurulan bu tablo artık
-- CANLI bir algılama motoruna sahiptir (eski "kapsam dışı" kararı bu
-- FAZ 2 ile kapatıldı).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_cctv_logs` (
    `id`           INT          NOT NULL AUTO_INCREMENT,
    `zone_id`      INT          NOT NULL,
    `dna_id`       VARCHAR(64)  NOT NULL,
    `masked`       TINYINT(1)   NOT NULL DEFAULT 0,
    `clothing_tag` VARCHAR(64)  NOT NULL DEFAULT 'unknown',
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_cctv_logs_zone_time` (`zone_id`, `created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- (B) FAZ 2: PARAVAN ŞİRKET DEFTERİ (server/shell_company.lua)
-- Oyuncu başına TEK aktif paravan şirket (PRIMARY KEY = citizenid).
-- clean_balance/dirty_cash_pool SALT-RAPORLAMA sayaçlarıdır -- gerçek
-- para hareketi HER ZAMAN qbx_core Functions.AddMoney/RemoveMoney VE
-- MEVCUT Matrix.CashDecay.Launder üzerinden yürür; bu tablo o hareketin
-- şirket cephesinden görünen bilançosunu tutar.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_shell_ledger` (
    `citizenid`       VARCHAR(50)  NOT NULL,
    `zone_id`         INT          NOT NULL,
    `business_name`   VARCHAR(80)  NOT NULL,
    `clean_balance`   DOUBLE       NOT NULL DEFAULT 0.0,
    `dirty_cash_pool` DOUBLE       NOT NULL DEFAULT 0.0,
    `created_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    KEY `idx_matrix_shell_ledger_zone` (`zone_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- (B) FAZ 2: ADLİ MUHASEBE DENETİM MOTORU (server/shell_company.lua)
-- Oyuncu başına TEK denetim durumu. `is_wiped=1` -> Büro bu şirketin
-- paravan olduğunu öğrendi ve Mali Wipe (kalıcı el koyma) uygulandı;
-- Matrix.ShellCompany.IssueFakeInvoice bu bayrak set'liyken KOŞULSUZ
-- reddeder.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_shell_audits` (
    `citizenid`         VARCHAR(50) NOT NULL,
    `invoices_today`    INT         NOT NULL DEFAULT 0,
    `invoice_day_stamp` DATE        NOT NULL,
    `audit_score`       DOUBLE      NOT NULL DEFAULT 0.0,
    `warning_level`     INT         NOT NULL DEFAULT 0,
    `is_wiped`          TINYINT(1)  NOT NULL DEFAULT 0,
    `updated_at`        DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- REFERANS HARİTASI — bu görevin 1. maddesinin istediği, ama İSİM
-- ÇAKIŞMASI nedeniyle burada YENİDEN TANIMLANMAYAN, hâlihazırda canlı
-- olan finansal tablolar (yalnızca dokümantasyon, hiçbir DDL çalıştırmaz):
--
--   matrix_cash_decay          -> sql/matrix.sql               (server/market.lua Matrix.CashDecay)
--   matrix_zone_ledger         -> sql/layer5_ultimate.sql       (server/market.lua Matrix.Market zone P&L)
--   matrix_zone_inspectors     -> sql/layer5_ultimate.sql       (server/market.lua Matrix.Inspector)
--   matrix_blackmarket_purchases -> sql/layer5_ultimate.sql     (server/blackmarket.lua)
--   matrix_pending_refunds     -> sql/matrix_security_hardening.sql (server/blackmarket.lua RefundCash)
-- =====================================================================


-- =====================================================================
-- DOĞRULAMA SORGUSU (opsiyonel — bu dosya çalıştırıldıktan sonra 3 dönmeli)
-- =====================================================================
-- SELECT COUNT(*) AS matrix_financial_core_table_count
-- FROM information_schema.tables
-- WHERE table_schema = DATABASE()
--   AND table_name IN ('matrix_cctv_logs', 'matrix_shell_ledger', 'matrix_shell_audits');


-- =====================================================================
-- BAKIM: Yalnızca bu migrasyonun eklediği tabloları geri almak isterseniz.
-- Yorumdan çıkarıp çalıştırın.
-- =====================================================================
-- DROP TABLE IF EXISTS `matrix_shell_audits`;
-- DROP TABLE IF EXISTS `matrix_shell_ledger`;
-- DROP TABLE IF EXISTS `matrix_cctv_logs`;
