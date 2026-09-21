-- =====================================================================
-- ★★★ MATRIX FINANCIAL CORE — TEK DOSYA KONSOLİDASYON MÜHÜRÜ ★★★
-- matrix_financial_core.sql
--
-- Bu dosya, projenin daha önce 9 ayrı dosyaya (matrix.sql,
-- layer5_ultimate.sql, layer6_trap_house.sql, matrix_cctv_network.sql,
-- matrix_security_hardening.sql, layer7_faz1.sql, layer7_faz3.sql,
-- layer7_faz4_front_business.sql, layer7_faz5_mercenary.sql) dağılmış TÜM
-- şema geçmişinin, TEK BİR SATIR BİLE ATLANMADAN, ORİJİNAL SIRAYLA
-- (bağımlılık zincirini bozmayacak şekilde: temel şema -> katman 5 -> 6 ->
-- CCTV -> güvenlik sertleştirme -> katman 7 faz 1/3/4/5) BİRLEŞTİRİLMİŞ
-- HALİDİR. Her bölüm, hangi eski dosyadan geldiğini gösteren bir "★ KAYNAK"
-- başlığıyla ayrılmıştır (bu başlıklar YENİ eklenen organizasyonel
-- işaretlerdir, orijinal içerikten HİÇBİR ŞEY ÇIKARILMAMIŞTIR/DEĞİŞTİRİLMEMİŞTİR).
--
-- ÇALIŞTIRMA: bu TEK dosyayı, doğrudan (baştan sona) sırayla import edin.
-- Ayrı ayrı çalıştırma adımı ARTIK YOKTUR.
--
-- ★ DOĞRULAMA (opsiyonel — çalıştırıldıktan sonra en az 22+4+3+1+1+2+0(kolon)
-- +0(kolon)+2(tablo+kolon) tablo/kolon değişikliği beklenir — ayrıntı için
-- aşağıdaki her bölümün KENDİ doğrulama yorumuna bakın, hiçbiri silinmedi):
-- SELECT COUNT(*) AS matrix_financial_core_table_count
-- FROM information_schema.tables WHERE table_schema = DATABASE();
-- =====================================================================


-- =======================================================================
-- ★ KAYNAK: sql/matrix.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

-- =====================================================================
-- MATRIX SCHEMA v3 — Katman 5 (Qbox Co-op Kartel Hiyerarşisi & Piyasa)
-- Katman 1-2-3-4-5 Birlesik Motor - Kalici Veri Tabani
--
-- ★ DEĞİŞİKLİK NOTU (v2 → v3):
--   (1) KATMAN 5 tabloları eklendi: matrix_hierarchy (co-op rütbe),
--       matrix_market_zones (bölgesel piyasa fiyat çarpanı), matrix_cash_decay
--       (kirlenen nakit sönümlenmesi). v2'nin "ON UPDATE CURRENT_TIMESTAMP
--       KULLANMA" politikası aynen sürdürüldü — `updated_at` uygulama
--       katmanında (market.lua) her UPDATE/UPSERT'te explicit NOW() ile
--       yazılır.
--   (2) matrix_cash_decay, matrix_trap_houses'a FK ile bağlı olduğundan
--       FOREIGN_KEY_CHECKS=0 sarması İÇİNE, diğer Katman 1-4 tablolarından
--       SONRA eklendi (parent zaten mevcut).
--   (3) Katman 1-4 tabloları/yorumları HİÇ DEĞİŞMEDİ (aşağıdaki v1→v2 notu
--       olduğu gibi korunmuştur).
--
-- ★ DEĞİŞİKLİK NOTU (v1 → v2):
--   (1) Tüm `DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP`
--       kombinasyonları KALDIRILDI. Neden: bazı MariaDB/MySQL derlemeleri
--       bu kombinasyonu kolon-tanımı parser'ında reddediyor ve CREATE
--       TABLE sessizce başarısız oluyordu → matrix_fleet ve
--       matrix_supplier_trust gibi Katman 4 tabloları hiç yaratılmıyordu.
--       Uygulama katmanı `updated_at = NOW()`'u her UPDATE/UPSERT
--       sorgusunda explicit gönderiyor (main.lua BOT_UPSERT_TAIL,
--       logistics.lua FlushDirtyFleet / FlushDirtySupplierTrust), bu
--       yüzden DB-seviyesi auto-update KAYBI YOKTUR.
--
--   (2) Tüm tablolar parent→child sırasına göre yeniden dizildi:
--       matrix_trap_houses  →  pattern_log/bureau_intel/raid_log/...
--       matrix_ballistic_weapons  →  matrix_forensic_evidence
--       matrix_bots  →  matrix_snitch_events
--
--   (3) `SET FOREIGN_KEY_CHECKS = 0` sarması eklendi: mevcut bir şemayı
--       yeniden import ederken FK ihlali yaşanmaz. Sonunda tekrar 1'e
--       döndürülür.
--
--   (4) Tüm kolon tipleri FULL MySQL 5.7 / MariaDB 10.x uyumludur.
--       DECIMAL ve ENUM sınırları korunmuştur.
--
-- ★ ADLİ KAYIT POLİTİKASI (DOKUNULMADI):
--   matrix_forensic_evidence, matrix_ballistic_weapons, matrix_touch_log,
--   matrix_alpr_hits, matrix_vehicle_seizures, matrix_dead_drop_events,
--   matrix_raid_log, matrix_livestream_events — asla silinmez, yalnızca
--   eklenir. Uygulama katmanı DELETE yalnızca matrix_bots ve matrix_fleet
--   için çağırır (hard-delete politika).
--
-- ★ KATMAN 8 NOTU (Hard-Wipe / E_total): İstek metninde tanımlanan "Ortak
--   Risk Kontratı" (çete-çapında kümülatif kanıt matrisi tetiklendiğinde
--   TÜM oyuncu verisinin aynı saniyede DROP edilmesi) BİLİNÇLİ OLARAK bu
--   şemaya EKLENMEDİ. Eşik/kapsam/hangi tabloların etkileneceği tanımsız;
--   tanımsız bir toplu-silme mekanizmasını tahminle şemaya kilitlemek,
--   yanlış bir tasarımı geri alınması güç hale getirir. Katman 8 netleşince
--   ayrı bir migration olarak eklenmelidir.
-- =====================================================================


SET FOREIGN_KEY_CHECKS = 0;


-- =====================================================================
-- KATMAN 1: CORE MATRIX  (Kalıcı Kimlik ve Biyoloji)
-- =====================================================================


-- ---------------------------------------------------------------------
-- Bot / Dealer Kalıcı Kimlik ve Biyoloji Profili
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_bots` (
    `id`                         INT          NOT NULL,
    `dna_id`                     VARCHAR(64)  NOT NULL,
    `name`                       VARCHAR(100) NOT NULL,
    `role`                       VARCHAR(32)  NOT NULL DEFAULT 'runner',
    -- ★ [FAZ 2][ADLİ ZİNCİR KORUMASI] 'deceased' -- KALICI ÖLÜM durumu.
    -- server/logistics.lua Matrix.Logistics.OnDealerEliminated ARTIK bu
    -- satırı ASLA SİLMEZ, yalnızca status='deceased' yazar (Matrix.RemoveBot
    -- üzerinden). Matrix.LoadBots (server/main.lua) yalnızca status='active'
    -- satırlarını RAM'e yükler -- 'deceased' bir bot bir daha ASLA lojistiğe
    -- sevk edilemez/canlandırılamaz, ama satırın kendisi (ve ona bağlı
    -- matrix_touch_log/matrix_forensic_evidence/matrix_ballistic_weapons/
    -- matrix_snitch_events kayıtları) kalıcı olarak korunur.
    `status`                     ENUM('active','burned','deceased','retired') NOT NULL DEFAULT 'active',
    `fear_factor`                FLOAT        NOT NULL DEFAULT 0.0,
    `resilience`                 FLOAT        NOT NULL DEFAULT 0.5,
    `snitch_tendency`            FLOAT        NOT NULL DEFAULT 0.0,
    `economic_pressure`          FLOAT        NOT NULL DEFAULT 0.0,
    `cognitive_shifter`          FLOAT        NOT NULL DEFAULT 0.5,
    `skill_chemistry`            FLOAT        NOT NULL DEFAULT 0.3,
    `skill_cyber`                FLOAT        NOT NULL DEFAULT 0.0,
    `skill_logistics`            FLOAT        NOT NULL DEFAULT 0.0,
    `fatigue_level`              FLOAT        NOT NULL DEFAULT 0.0,
    `cortisol_level`             FLOAT        NOT NULL DEFAULT 0.0,
    `withdrawal_index`           FLOAT        NOT NULL DEFAULT 0.0,
    `addiction_level`            FLOAT        NOT NULL DEFAULT 0.0,
    `base_cortisol_recovery_rate` FLOAT       NOT NULL DEFAULT 0.05,
    `trap_house_id`              INT          NULL,
    `created_at`                 DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`                 DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_matrix_bots_dna_id` (`dna_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Oyuncu Kalıcı Bio-Durumu (fingerprint/kortizol formülleri için)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_player_state` (
    `citizenid`      VARCHAR(50) NOT NULL,
    `cortisol_level` FLOAT       NOT NULL DEFAULT 0.0,
    `fatigue_level`  FLOAT       NOT NULL DEFAULT 0.0,
    `updated_at`     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Kalıcı Balistik Silah Kaydı (yiv-set imza kodu ile)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_ballistic_weapons` (
    `ballistic_id`            VARCHAR(64) NOT NULL,
    `weapon_serial`           VARCHAR(64) NOT NULL,
    `wear_level`              FLOAT       NOT NULL DEFAULT 0.0,
    `sealed_as_crime_weapon`  TINYINT(1)  NOT NULL DEFAULT 0,
    `seal_certainty`          FLOAT       NULL,
    `first_registered`        DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`ballistic_id`),
    UNIQUE KEY `uq_matrix_ballistic_weapon_serial` (`weapon_serial`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Kalıcı Adli Kanıt Veri Tabanı (asla silinmez)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_forensic_evidence` (
    `id`                      INT          NOT NULL AUTO_INCREMENT,
    `ballistic_id`            VARCHAR(64)  NOT NULL,
    `evidence_type`           VARCHAR(32)  NOT NULL DEFAULT 'casing',
    `striation_quality`       FLOAT        NOT NULL,
    `fingerprint_id`          VARCHAR(64)  NOT NULL,
    `fingerprint_quality`     FLOAT        NOT NULL,
    `match_certainty`         FLOAT        NOT NULL,
    `sealed_as_crime_weapon`  TINYINT(1)   NOT NULL DEFAULT 0,
    `coords_x`                FLOAT        NOT NULL DEFAULT 0.0,
    `coords_y`                FLOAT        NOT NULL DEFAULT 0.0,
    `coords_z`                FLOAT        NOT NULL DEFAULT 0.0,
    `created_at`              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_forensic_evidence_ballistic_id` (`ballistic_id`),
    CONSTRAINT `fk_matrix_forensic_evidence_ballistic`
        FOREIGN KEY (`ballistic_id`) REFERENCES `matrix_ballistic_weapons` (`ballistic_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Dokunulan Nesneler - Genel Parmak İzi Günlüğü (asla silinmez)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_touch_log` (
    `id`                  INT          NOT NULL AUTO_INCREMENT,
    `fingerprint_id`      VARCHAR(64)  NOT NULL,
    `fingerprint_quality` FLOAT        NOT NULL,
    `inventory_id`        VARCHAR(64)  NOT NULL,
    `slot_id`             INT          NOT NULL,
    `created_at`          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_touch_log_fingerprint_id` (`fingerprint_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Karanlık Mülakat - Müşteri Havuzu (deterministik trait çıkarımı)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_customer_pool` (
    `citizenid`                  VARCHAR(50)  NOT NULL,
    `name`                       VARCHAR(100) NOT NULL,
    -- ★ [FAZ 2] Şema-tutarlılık kolonu (talep: "matrix_customer_pool'u da
    -- is_dead mantığına göre güncelle"). DÜRÜST NOT: matrix_customer_pool
    -- GERÇEK OYUNCU citizenid'lerini tutar (bot DEĞİL) -- bu projede
    -- kalıcı oyuncu ölümü/permadeath mekaniği YOKTUR, bu yüzden şu an
    -- HİÇBİR kod bu kolonu OKUMAZ/YAZMAZ. Yalnızca gelecekteki bir
    -- permadeath entegrasyonu için hazır, zararsız bir varsayılan (0) taşır.
    `is_dead`                    TINYINT(1)   NOT NULL DEFAULT 0,
    `police_encounters_nearby`   INT          NOT NULL DEFAULT 0,
    `completed_deals`            INT          NOT NULL DEFAULT 0,
    `times_reported`             INT          NOT NULL DEFAULT 0,
    `failed_payments`            INT          NOT NULL DEFAULT 0,
    `chemistry_hints`            INT          NOT NULL DEFAULT 0,
    `addiction_level`            FLOAT        NOT NULL DEFAULT 0.0,
    `promoted_to_candidate`      TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`                 DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Karanlık Mülakat - Sorgu Oturumu Sonuç Günlüğü
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_recruitment_sessions` (
    `id`                     INT          NOT NULL AUTO_INCREMENT,
    `candidate_citizenid`    VARCHAR(50)  NOT NULL,
    `fear_factor`            FLOAT        NOT NULL,
    `resilience`             FLOAT        NOT NULL,
    `lies_told`              INT          NOT NULL DEFAULT 0,
    `confessions`            INT          NOT NULL DEFAULT 0,
    `outcome`                ENUM('recruited','released','burned') NOT NULL,
    `created_at`             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_recruitment_sessions_candidate` (`candidate_citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- KATMAN 2: THE BUREAU  (Trap House + Desifre + Baskin + Yayin)
-- =====================================================================


-- ---------------------------------------------------------------------
-- Trap House Kayıtları (üçgenleme/desifre hedefleri)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_trap_houses` (
    `id`                    INT          NOT NULL AUTO_INCREMENT,
    `label`                 VARCHAR(100) NOT NULL,
    `coord_x`               FLOAT        NOT NULL,
    `coord_y`               FLOAT        NOT NULL,
    `coord_z`               FLOAT        NOT NULL,
    `decryption_confidence` FLOAT        NOT NULL DEFAULT 0.0,
    `cyber_leak_intensity`  FLOAT        NOT NULL DEFAULT 0.0,
    `raid_ordered`          TINYINT(1)   NOT NULL DEFAULT 0,
    `last_raid_at`          DATETIME     NULL,
    `created_at`            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Pattern Desifre Dongusu - Saat/Gun Kalibi Gunlugu
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_pattern_log` (
    `id`               INT      NOT NULL AUTO_INCREMENT,
    `trap_house_id`    INT      NOT NULL,
    `day_of_week`      TINYINT  NOT NULL,
    `hour_of_day`      TINYINT  NOT NULL,
    `occurrence_count` INT      NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_matrix_pattern_log_bucket` (`trap_house_id`, `day_of_week`, `hour_of_day`),
    CONSTRAINT `fk_matrix_pattern_log_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Buro Istihbarat Katmani (ucgenleme / siber sizinti yogunlugu)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_bureau_intel` (
    `id`             INT          NOT NULL AUTO_INCREMENT,
    `trap_house_id`  INT          NOT NULL,
    `category`       ENUM('triangulation','cyber_leak','pattern') NOT NULL,
    `intensity`      FLOAT        NOT NULL DEFAULT 0.0,
    `updated_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_matrix_bureau_intel_bucket` (`trap_house_id`, `category`),
    CONSTRAINT `fk_matrix_bureau_intel_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Fiziksel Safak Baskini Gunlugu - murettebat/breach/sonuc kaydi
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_raid_log` (
    `id`                             INT          NOT NULL AUTO_INCREMENT,
    `trap_house_id`                  INT          NOT NULL,
    `squad_size`                     INT          NOT NULL,
    `breach_method`                  VARCHAR(32)  NOT NULL DEFAULT 'ram',
    `decryption_confidence_at_raid`  FLOAT        NOT NULL,
    `escape_window_seconds`          INT          NOT NULL DEFAULT 0,
    `outcome`                        ENUM('pending','captured','escaped','eliminated') NOT NULL DEFAULT 'pending',
    `created_at`                     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `resolved_at`                    DATETIME     NULL,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_raid_log_trap_house` (`trap_house_id`),
    CONSTRAINT `fk_matrix_raid_log_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- qb-phone Canli Yayin / Siber Propaganda Gunlugu (asla silinmez)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_livestream_events` (
    `id`               INT          NOT NULL AUTO_INCREMENT,
    `citizenid`        VARCHAR(50)  NOT NULL,
    `duration_seconds` INT          NOT NULL DEFAULT 0,
    `hype_multiplier`  FLOAT        NOT NULL DEFAULT 1.0,
    `heat_added`       FLOAT        NOT NULL DEFAULT 0.0,
    `trap_house_id`    INT          NULL,
    `created_at`       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- KATMAN 3: İHANET & MUTFAK
-- =====================================================================


-- ---------------------------------------------------------------------
-- Ihanet & Muhbirlik Gunlugu
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_snitch_events` (
    `id`             INT         NOT NULL AUTO_INCREMENT,
    `bot_id`         INT         NOT NULL,
    `trap_house_id`  INT         NOT NULL,
    `snitch_index`   FLOAT       NOT NULL,
    `lied`           TINYINT(1)  NOT NULL DEFAULT 0,
    `created_at`     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_snitch_events_bot` (`bot_id`),
    CONSTRAINT `fk_matrix_snitch_events_bot`
        FOREIGN KEY (`bot_id`) REFERENCES `matrix_bots` (`id`),
    CONSTRAINT `fk_matrix_snitch_events_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Mutfak Motoru - Seyreltme/Kesme Isletim Gunlugu
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_kitchen_batches` (
    `id`                           INT          NOT NULL AUTO_INCREMENT,
    `trap_house_id`                INT          NOT NULL,
    `actor_identifier`             VARCHAR(64)  NOT NULL,
    `raw_weight`                   FLOAT        NOT NULL,
    `raw_purity`                   FLOAT        NOT NULL,
    `agent_weight`                 FLOAT        NOT NULL,
    `theoretical_purity`           FLOAT        NOT NULL,
    `error_coefficient`            FLOAT        NOT NULL,
    `output_purity`                FLOAT        NOT NULL,
    `waste_volume`                 FLOAT        NOT NULL,
    `theft_amount`                 FLOAT        NOT NULL DEFAULT 0.0,
    `rival_infiltration_triggered` TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`                   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_kitchen_batches_trap_house` (`trap_house_id`),
    CONSTRAINT `fk_matrix_kitchen_batches_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- KATMAN 4: İLLEGAL FİLO + TOPTANCI İLİŞKİ MATRİSİ + DEAD DROP
-- =====================================================================


-- ---------------------------------------------------------------------
-- İllegal Filo - Aktif Araç Havuzu. Bir araç ele geçirilirse (çatışma/
-- baskın) bu tablodan hard-delete edilir; kalıcı adli mühür ayrı olarak
-- matrix_vehicle_seizures'a yazılır.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_fleet` (
    `id`                      INT          NOT NULL AUTO_INCREMENT,
    `plate`                   VARCHAR(32)  NOT NULL,
    `vehicle_class`           ENUM('motorbike','car') NOT NULL DEFAULT 'car',
    `vin_status`              ENUM('factory','scratched','hot') NOT NULL DEFAULT 'hot',
    `vehicle_wear`            FLOAT        NOT NULL DEFAULT 0.0,
    `registered_by_citizenid` VARCHAR(50)  NULL,
    `assigned_bot_id`         INT          NULL,
    `assignment_mode`         ENUM('permanent','temporary') NULL,
    `verified_stolen_plate`   TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_matrix_fleet_plate` (`plate`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Büro ALPR / Görsel Eşkal Eşleşme Günlüğü (asla silinmez).
-- Plaka + dealer fingerprint_dna_id + organizasyon imzası bağlanır.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_alpr_hits` (
    `id`                     INT          NOT NULL AUTO_INCREMENT,
    `plate`                  VARCHAR(32)  NOT NULL,
    `fingerprint_dna_id`     VARCHAR(64)  NOT NULL,
    `organization_signature` VARCHAR(50)  NOT NULL,
    `trap_house_id`          INT          NOT NULL,
    `created_at`             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_alpr_hits_plate` (`plate`),
    CONSTRAINT `fk_matrix_alpr_hits_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Ele Geçirilen Araç Mührü - kalıcı kanıt katsayısı (asla silinmez).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_vehicle_seizures` (
    `id`                     INT          NOT NULL AUTO_INCREMENT,
    `plate`                  VARCHAR(32)  NOT NULL,
    `vin_status`             ENUM('factory','scratched','hot') NOT NULL,
    `vehicle_wear`           FLOAT        NOT NULL DEFAULT 0.0,
    `fingerprint_dna_id`     VARCHAR(64)  NOT NULL,
    `organization_signature` VARCHAR(50)  NOT NULL,
    `seizure_cause`          VARCHAR(32)  NOT NULL DEFAULT 'unknown',
    `seal_certainty`         FLOAT        NOT NULL,
    `coords_x`               FLOAT        NOT NULL DEFAULT 0.0,
    `coords_y`               FLOAT        NOT NULL DEFAULT 0.0,
    `coords_z`               FLOAT        NOT NULL DEFAULT 0.0,
    `created_at`              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_vehicle_seizures_plate` (`plate`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Toptancı Güven Matrisi - oyuncu/toptancı ilişkisi kalıcıdır.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_supplier_trust` (
    `citizenid`      VARCHAR(50) NOT NULL,
    `supplier_id`    INT         NOT NULL,
    `trust`          FLOAT       NOT NULL DEFAULT 0.5,
    `late_payments`  INT         NOT NULL DEFAULT 0,
    `forensic_leaks` INT         NOT NULL DEFAULT 0,
    `created_at`     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`, `supplier_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Dead Drop Teslim Alma Günlüğü (asla silinmez)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_dead_drop_events` (
    `id`                    INT          NOT NULL AUTO_INCREMENT,
    `drop_id`               INT          NOT NULL,
    `supplier_id`           INT          NOT NULL,
    `citizenid`             VARCHAR(50)  NOT NULL,
    `heat_at_pickup`        FLOAT        NOT NULL DEFAULT 0.0,
    `forensic_trace_left`   TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_dead_drop_events_drop` (`drop_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- KATMAN 5: QBOX CO-OP KARTEL HİYERARŞİSİ + BÖLGESEL PİYASA +
-- KILCAL DAMAR HARDCORE MEKANİKLER
-- =====================================================================


-- ---------------------------------------------------------------------
-- Co-op Kartel Rütbe Ataması (CitizenID bazlı, kalıcı)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_hierarchy` (
    `citizenid`   VARCHAR(50) NOT NULL,
    `rank`        ENUM('Leader','Logistics_Officer','Chemist') NOT NULL DEFAULT 'Chemist',
    `assigned_by` VARCHAR(50) NULL,
    `created_at`  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Bölgesel Piyasa - anlık fiyat çarpanı / reddedilen parti sayacı
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_market_zones` (
    `zone_id`          INT      NOT NULL,
    `price_multiplier` FLOAT    NOT NULL DEFAULT 1.0,
    `rejected_streak`  INT      NOT NULL DEFAULT 0,
    `updated_at`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`zone_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- Kirlenen Nakit Sönümlenmesi - trap house başına biriken kirli nakit ve
-- ilk yatırılma zamanı (adli koku/seri no izi τ=90 gün formülü buradan
-- türetilir; bkz. market.lua Matrix.CashDecay).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_cash_decay` (
    `trap_house_id`  INT      NOT NULL,
    `dirty_amount`   FLOAT    NOT NULL DEFAULT 0.0,
    `deposited_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`trap_house_id`),
    CONSTRAINT `fk_matrix_cash_decay_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- =====================================================================
-- FOREIGN KEY CHECK'LERİNİ YENİDEN AÇ
-- =====================================================================
SET FOREIGN_KEY_CHECKS = 1;


-- =====================================================================
-- DOĞRULAMA SORGUSU (opsiyonel — çalıştırıldığında 22 dönmeli)
-- =====================================================================
-- SELECT COUNT(*) AS matrix_table_count
-- FROM information_schema.tables
-- WHERE table_schema = DATABASE()
--   AND table_name LIKE 'matrix\_%';


-- =====================================================================
-- BAKIM: Sıfırdan yeniden kurmak isterseniz aşağıdaki blok
-- (yalnızca FK sırasına göre tersten) DROP eder. Yorumdan çıkarıp
-- çalıştırın. Bu blok TÜM VERİYİ SİLER — dikkatli kullanın.
-- =====================================================================
-- SET FOREIGN_KEY_CHECKS = 0;
-- DROP TABLE IF EXISTS `matrix_cash_decay`;
-- DROP TABLE IF EXISTS `matrix_market_zones`;
-- DROP TABLE IF EXISTS `matrix_hierarchy`;
-- DROP TABLE IF EXISTS `matrix_livestream_events`;
-- DROP TABLE IF EXISTS `matrix_dead_drop_events`;
-- DROP TABLE IF EXISTS `matrix_supplier_trust`;
-- DROP TABLE IF EXISTS `matrix_vehicle_seizures`;
-- DROP TABLE IF EXISTS `matrix_alpr_hits`;
-- DROP TABLE IF EXISTS `matrix_fleet`;
-- DROP TABLE IF EXISTS `matrix_kitchen_batches`;
-- DROP TABLE IF EXISTS `matrix_snitch_events`;
-- DROP TABLE IF EXISTS `matrix_raid_log`;
-- DROP TABLE IF EXISTS `matrix_bureau_intel`;
-- DROP TABLE IF EXISTS `matrix_pattern_log`;
-- DROP TABLE IF EXISTS `matrix_trap_houses`;
-- DROP TABLE IF EXISTS `matrix_recruitment_sessions`;
-- DROP TABLE IF EXISTS `matrix_customer_pool`;
-- DROP TABLE IF EXISTS `matrix_touch_log`;
-- DROP TABLE IF EXISTS `matrix_forensic_evidence`;
-- DROP TABLE IF EXISTS `matrix_ballistic_weapons`;
-- DROP TABLE IF EXISTS `matrix_player_state`;
-- DROP TABLE IF EXISTS `matrix_bots`;
-- SET FOREIGN_KEY_CHECKS = 1;

-- =======================================================================
-- ★ KAYNAK: sql/layer5_ultimate.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

-- =====================================================================
-- MATRIX SCHEMA — KATMAN 5 ULTIMATE EK MİGRASYONU (sql/layer5_ultimate.sql)
-- Co-Op & SIGINT/COMINT Bali-Logistics Matrix
--
-- ★ BU DOSYA TAMAMEN EKLEMELİDİR (ADDITIVE-ONLY):
--   matrix.sql'deki (v3) 16 tabloya HİÇBİRİNE DOKUNULMAZ — ALTER YOK,
--   DROP YOK, kolon eklenmedi. Yalnızca 4 YENİ tablo eklenir. matrix.sql'i
--   İMPORT ETTİKTEN SONRA bu dosyayı çalıştırın.
--
--   Bu dosya, matrix.sql ile AYNI konvansiyonları izler:
--     - ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
--     - "DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP" KULLANILMAZ
--       (bazı MariaDB/MySQL derlemelerinde CREATE TABLE'ı sessizce
--       başarısız kılıyordu — v1→v2 notu, bkz. matrix.sql). `updated_at`/
--       `flagged_at`/`assigned_at` uygulama katmanında (server/market.lua,
--       server/blackmarket.lua) her UPSERT'te explicit NOW() ile yazılır.
--     - Tablo/kolon adları geriye dönük `matrix_` önekini korur.
--
--   ★ KASITLI TASARIM KARARI — FK YOK: `matrix_zone_inspectors.bot_id` ve
--     `matrix_mole_flags.bot_id`, KASITLI OLARAK `matrix_bots.id`'ye FOREIGN
--     KEY İLE BAĞLANMAZ. Sebep: server/logistics.lua'nın Matrix.Logistics.
--     OnDealerEliminated'i (F10 "Operatif Tasfiye Et" -> /operatiftasfiye,
--     bkz. server/main.lua) matrix_bots satırını GERÇEK bir DELETE ile
--     kalıcı olarak siler (hard-delete politikası, matrix.sql başlığında
--     zaten tanımlı). Bir Inspector'a atanmış veya köstebek olarak
--     işaretlenmiş bir botu tasfiye etmek İSTİSNASIZ ÇALIŞMALIDIR — bir FK
--     kısıtı (varsayılan RESTRICT/NO ACTION) bu hard-delete'i SESSİZCE
--     BLOKE ederdi. RAM tarafında (server/market.lua Matrix.Inspector)
--     zaten stale bot_id'lere karşı dayanıklı: silinen bir bot bir
--     sonraki taramada otomatik olarak atamadan düşer (self-healing).
-- =====================================================================


SET FOREIGN_KEY_CHECKS = 0;


-- ---------------------------------------------------------------------
-- [U2] Karaborsa Ticaret Ağı - satın alma günlüğü (asla silinmez; mevcut
-- "adli kayıt politikası" ruhuna uygun kalıcı bir kâğıt izi).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_blackmarket_purchases` (
    `id`          INT          NOT NULL AUTO_INCREMENT,
    `citizenid`   VARCHAR(50)  NOT NULL,
    `item_type`   ENUM('vehicle','weapon','barrel','burner_phone') NOT NULL,
    `item_ref`    VARCHAR(64)  NOT NULL,
    `price_paid`  FLOAT        NOT NULL DEFAULT 0.0,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_blackmarket_purchases_citizenid` (`citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- [U4] SIGINT - Bölge Denetleyicisi (Inspector) ataması. Bölge başına
-- TEK aktif denetleyici (PRIMARY KEY = zone_id); yeniden atama UPSERT ile
-- öncekinin yerini alır.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_zone_inspectors` (
    `zone_id`                INT         NOT NULL,
    `bot_id`                 INT         NOT NULL,
    `assigned_by_citizenid`  VARCHAR(50) NULL,
    `assigned_at`            DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`zone_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- [U4] SIGINT - Köstebek/muhbir tarama sonucu kalıcı bülteni. Bir botun
-- Operatif Tasfiye Et ile arındırılmasından SONRA da (kanıt/denetim amaçlı)
-- kalır; matrix_bots.id hard-delete sonrası hiçbir zaman yeniden
-- kullanılmaz (Matrix.NextBotId monoton artar), bu yüzden stale satır bir
-- sonraki bot ile ASLA çakışmaz.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_mole_flags` (
    `bot_id`           INT      NOT NULL,
    `snitch_tendency`  FLOAT    NOT NULL DEFAULT 0.0,
    `flagged_at`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`bot_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- [U6] Bölgesel Mali Rapor - bölge başına yuvarlanan (rolling) kâr/zarar
-- bilançosu. matrix_market_zones (fiyat çarpanı/ardarda-red) ile AYNI
-- zone_id uzayını paylaşır ama BAĞIMSIZ bir tablodur (o da zone_id'ye FK
-- taşımıyor — zone'lar Config.Market.Zones'ta statik tanımlı, ayrı bir
-- "zones" ebeveyn tablosu hiç var olmadı).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_zone_ledger` (
    `zone_id`            INT      NOT NULL,
    `sale_count`         INT      NOT NULL DEFAULT 0,
    `total_grams`        FLOAT    NOT NULL DEFAULT 0.0,
    `gross_revenue`      FLOAT    NOT NULL DEFAULT 0.0,
    `net_profit`         FLOAT    NOT NULL DEFAULT 0.0,
    `price_crash_count`  INT      NOT NULL DEFAULT 0,
    `updated_at`         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`zone_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


SET FOREIGN_KEY_CHECKS = 1;


-- =====================================================================
-- DOĞRULAMA SORGUSU (opsiyonel — bu dosya çalıştırıldıktan sonra 4 dönmeli)
-- =====================================================================
-- SELECT COUNT(*) AS layer5_ultimate_table_count
-- FROM information_schema.tables
-- WHERE table_schema = DATABASE()
--   AND table_name IN (
--       'matrix_blackmarket_purchases',
--       'matrix_zone_inspectors',
--       'matrix_mole_flags',
--       'matrix_zone_ledger'
--   );


-- =====================================================================
-- BAKIM: Yalnızca bu migrasyonun eklediği 4 tabloyu geri almak isterseniz
-- (matrix.sql'in 16 tablosuna DOKUNMAZ). Yorumdan çıkarıp çalıştırın.
-- =====================================================================
-- SET FOREIGN_KEY_CHECKS = 0;
-- DROP TABLE IF EXISTS `matrix_zone_ledger`;
-- DROP TABLE IF EXISTS `matrix_mole_flags`;
-- DROP TABLE IF EXISTS `matrix_zone_inspectors`;
-- DROP TABLE IF EXISTS `matrix_blackmarket_purchases`;
-- SET FOREIGN_KEY_CHECKS = 1;

-- =======================================================================
-- ★ KAYNAK: sql/layer6_trap_house.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

-- =====================================================================
-- MATRIX SCHEMA — KATMAN 6 EK MİGRASYONU (sql/layer6_trap_house.sql)
-- Siber-Taktik Operasyon ve Stratejik Trap House Mimarisi
--
-- ★ BU DOSYA TAMAMEN EKLEMELİDİR (ADDITIVE-ONLY):
--   matrix.sql (v3, 22 tablo) ve sql/layer5_ultimate.sql (4 tablo)
--   HİÇBİR ŞEKİLDE değiştirilmez — ALTER YOK, DROP YOK, kolon eklenmedi.
--   Yalnızca 3 YENİ tablo eklenir. matrix.sql VE layer5_ultimate.sql'i
--   İMPORT ETTİKTEN SONRA bu dosyayı çalıştırın.
--
--   Aynı konvansiyonlar korunur: ENGINE=InnoDB DEFAULT CHARSET=utf8mb4,
--   "ON UPDATE CURRENT_TIMESTAMP" KULLANILMAZ (uygulama katmanı NOW() ile
--   yazar), `matrix_` öneki korunur, FK'ler yalnızca gerçekten var olan
--   kalıcı ebeveyn tablolara (matrix_trap_houses) bağlanır.
-- =====================================================================


SET FOREIGN_KEY_CHECKS = 0;


-- ---------------------------------------------------------------------
-- [K6-4] Kapı Sürgü Tahkimatı — trap house başına TEK aktif seviye
-- (0-3). server/door_reinforcement.lua tarafından okunur/yazılır.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_door_reinforcement` (
    `trap_house_id` INT      NOT NULL,
    `level`         TINYINT  NOT NULL DEFAULT 0,
    `installed_by_citizenid` VARCHAR(50) NULL,
    `updated_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`trap_house_id`),
    CONSTRAINT `fk_matrix_door_reinforcement_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- [K6-1] Rendezvous / Dead Drop teslimatı adli kaydı — asla silinmez
-- (mevcut "adli kayıt politikası" ile aynı ruh: bir pusu/teslimatın
-- gerçekten olup olmadığı sonradan denetlenebilir kalır).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_rendezvous_events` (
    `id`               INT          NOT NULL AUTO_INCREMENT,
    `citizenid`        VARCHAR(50)  NOT NULL,
    `catalog_type`     ENUM('weapon','ammo') NOT NULL,
    `catalog_id`       VARCHAR(64)  NOT NULL,
    `handoff_x`        FLOAT        NOT NULL DEFAULT 0.0,
    `handoff_y`        FLOAT        NOT NULL DEFAULT 0.0,
    `handoff_z`        FLOAT        NOT NULL DEFAULT 0.0,
    `trace_level_at_handoff` FLOAT  NOT NULL DEFAULT 0.0,
    `ambush_triggered` TINYINT(1)   NOT NULL DEFAULT 0,
    `outcome`          ENUM('pending','delivered','expired') NOT NULL DEFAULT 'pending',
    `created_at`       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `resolved_at`      DATETIME     NULL,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_rendezvous_events_citizenid` (`citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


-- ---------------------------------------------------------------------
-- [K6-3] Paketleme Odası çalışma durumu — trap house başına TEK kayıt.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_packaging_room_state` (
    `trap_house_id` INT      NOT NULL,
    `active`        TINYINT(1) NOT NULL DEFAULT 0,
    `started_by_citizenid` VARCHAR(50) NULL,
    `updated_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`trap_house_id`),
    CONSTRAINT `fk_matrix_packaging_room_state_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;


SET FOREIGN_KEY_CHECKS = 1;


-- =====================================================================
-- DOĞRULAMA SORGUSU (opsiyonel — bu dosya çalıştırıldıktan sonra 3 dönmeli)
-- =====================================================================
-- SELECT COUNT(*) AS layer6_table_count
-- FROM information_schema.tables
-- WHERE table_schema = DATABASE()
--   AND table_name IN (
--       'matrix_door_reinforcement',
--       'matrix_rendezvous_events',
--       'matrix_packaging_room_state'
--   );


-- =====================================================================
-- BAKIM: Yalnızca bu migrasyonun eklediği 3 tabloyu geri almak isterseniz
-- (matrix.sql/layer5_ultimate.sql'e DOKUNMAZ). Yorumdan çıkarıp çalıştırın.
-- =====================================================================
-- SET FOREIGN_KEY_CHECKS = 0;
-- DROP TABLE IF EXISTS `matrix_packaging_room_state`;
-- DROP TABLE IF EXISTS `matrix_rendezvous_events`;
-- DROP TABLE IF EXISTS `matrix_door_reinforcement`;
-- SET FOREIGN_KEY_CHECKS = 1;

-- =======================================================================
-- ★ KAYNAK: sql/matrix_cctv_network.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

-- =====================================================================
-- MATRIX CCTV NETWORK PATCH / sql/matrix_cctv_network.sql
--
-- Bu migration, server/forensics.lua ★ [OPSEC FAZ 1 EK] FİZİKSEL VE SİBER
-- DELİL İMHA MEKANİZMASI (Matrix.Forensics.HackCCTVNetwork) için TEK yeni
-- tabloyu taşır. matrix.sql'in (veya son layer/hardening dosyasının)
-- KENDİSİ değiştirilmedi -- bu proje layer5_ultimate.sql / layer6_trap_
-- house.sql / layer7_faz1.sql / layer7_faz3.sql / matrix_security_
-- hardening.sql İLE AYNI "ek (additive) migration" disiplinini izler.
-- matrix.sql'den (veya son migration dosyasından) SONRA, FOREIGN_KEY_CHECKS
-- zaten 1'e dönmüş haldeyken import edilmelidir.
--
-- ★ KAPSAM NOTU: bu migration YALNIZCA HackCCTVNetwork'ün SİLDİĞİ tabloyu
-- tanımlar. Mobese ağının oyuncu/bot kıyafet eşleşmesini GERÇEKTEN nasıl
-- TESPİT EDİP bu tabloya YAZACAĞI (bir algılama/computer-vision motoru)
-- bu görevin kapsamı DIŞINDADIR -- Config.AI_Matrix_Brain'in "altyapı
-- hazır, motor gelecekte devreye girer" (enabled=false) köprüsüyle AYNI
-- bilinçli erteleme. server/forensics.lua'daki /cctvkaydet test komutu,
-- gerçek bir algılama motoru olmadan bu tabloyu manuel doldurmak için
-- (bkz. server/bureau.lua /dropsizintiekle İLE AYNI "test-veri-ekleme"
-- disiplini) eklendi.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Mobese Dağıtım Kutusu Kayıtları — bölge başına, zaman damgalı kıyafet/
-- maskeleme eşleşme günlüğü. HackCCTVNetwork yalnızca `masked = 0`
-- (maskesiz/şüpheli) VE son 30 dakika içindeki satırları siler; maskeli
-- (masked = 1) satırlar veya 30 dakikadan eski satırlar HİÇ ETKİLENMEZ.
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
-- DOĞRULAMA SORGUSU (opsiyonel — bu dosya çalıştırıldıktan sonra 1 dönmeli)
-- =====================================================================
-- SELECT COUNT(*) AS matrix_cctv_network_table_count
-- FROM information_schema.tables
-- WHERE table_schema = DATABASE()
--   AND table_name IN ('matrix_cctv_logs');


-- =====================================================================
-- BAKIM: Yalnızca bu migrasyonun eklediği tabloyu geri almak isterseniz.
-- Yorumdan çıkarıp çalıştırın.
-- =====================================================================
-- DROP TABLE IF EXISTS `matrix_cctv_logs`;

-- =======================================================================
-- ★ KAYNAK: sql/matrix_security_hardening.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

-- =====================================================================
-- MATRIX SECURITY HARDENING PATCH / sql/matrix_security_hardening.sql
--
-- Bu migration, server/blackmarket.lua + server/bureau.lua ADLİ GÜVENLİK
-- DENETİMİ (7 maddelik zafiyet raporu) sonucu eklenen TEK yeni tabloyu
-- taşır: [SEC-2] "Hard Drop-Out / Orphan State" düzeltmesinin son çare
-- (son-kertede) tahsilat defteri.
--
-- matrix.sql'in KENDİSİ değiştirilmedi (mevcut şemaya elle dokunmak
-- riskli) -- bu proje layer5_ultimate.sql / layer6_trap_house.sql /
-- layer7_faz1.sql / layer7_faz3.sql ile AYNI "ek (additive) migration"
-- disiplinini izler. matrix.sql'den (veya son layer dosyasından) SONRA,
-- FOREIGN_KEY_CHECKS zaten 1'e dönmüş haldeyken import edilmelidir.
--
-- NOT: bu dosya "layer8" olarak ADLANDIRILMADI -- matrix.sql'in kendi
-- yorumunda KATMAN 8 zaten "Hard-Wipe / E_total" adlı, henüz tanımsız ve
-- BİLİNÇLİ OLARAK ertelenmiş ayrı bir özelliğe ayrılmış. Bu dosya o
-- katmanla KARIŞTIRILMASIN diye bağımsız bir isim taşır.
-- =====================================================================


-- ---------------------------------------------------------------------
-- ★ [SEC-2] Offline İade Son Çare Defteri
--
-- RefundCash (server/blackmarket.lua) şu sırayla dener:
--   1) Oyuncu çevrimiçiyse: Matrix.QBX Functions.AddMoney (anında).
--   2) Değilse: players.money JSON_SET ile ACID tek-UPDATE offline iade.
--   3) O UPDATE 0 satır etkilerse (citizenid players'ta yok -- silinmiş/
--      tanınmayan karakter): bu tabloya yazılır. Para HİÇBİR KOŞULDA
--      sessizce kaybolmaz; bir admin bu tabloyu görüp manuel mutabakat
--      yapabilir. Asla otomatik silinmez/işlenmez (yalnızca INSERT).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_pending_refunds` (
    `id`          INT          NOT NULL AUTO_INCREMENT,
    `citizenid`   VARCHAR(50)  NOT NULL,
    `amount`      DECIMAL(12,2) NOT NULL,
    `reason`      VARCHAR(100) NOT NULL,
    `resolved`    TINYINT(1)   NOT NULL DEFAULT 0,
    `resolved_by` VARCHAR(50)  DEFAULT NULL,
    `resolved_at` DATETIME     DEFAULT NULL,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_pending_refunds_citizenid` (`citizenid`),
    KEY `idx_matrix_pending_refunds_resolved` (`resolved`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- =======================================================================
-- ★ KAYNAK: sql/layer7_faz1.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

-- =====================================================================
-- KATMAN 7 [T4] FAZ 1: OTONOM DEPO LOJISTIGI VE BURO KILIDI
-- Additive migration. Yukaridaki (matrix.sql / layer5_ultimate.sql /
-- layer6_trap_house.sql) hicbir tablosu/alani DEGISTIRILMEDI -- her
-- ifade IF NOT EXISTS ile guvenlidir.
--
-- ★ KAPSAM NOTU: 'matrix_trap_stash' burada BULUNMUYOR -- trap house'un
-- ortak deposu zaten server/logistics.lua ve server/main.lua'nin
-- matrix_trap_stash_<id> ox_inventory stash'i (RegisterStash/AddItem/
-- RemoveItem) olarak MEVCUT. Ikinci bir SQL tablosu acmak veri
-- tutarsizligina yol acardi.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Kalici Kolektif Ogrenme Hafizasi -- trap house basina, RAID'LERDE
-- SIFIRLANMAYAN, birikimli telsiz ihlali + ele gecirilen urun saflik
-- kaydi. server/bureau.lua [T4] blogunun Buro Kilidi (lockdown_active)
-- karari BU tablodan turer; matrix_bureau_intel (mevcut) ile KARISTIRILMAZ
-- -- o yalnizca heat/triangulation/pattern yogunlugu tasir.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_bureau_learning_core` (
    `id`                          INT      NOT NULL AUTO_INCREMENT,
    `trap_house_id`               INT      NOT NULL,
    `frequent_zones`              TEXT     NULL COMMENT 'JSON array: bu trap house icin tekrarlanan ihlal etiketleri',
    `radio_breach_count`          INT      NOT NULL DEFAULT 0,
    `average_purity_intercepted`  FLOAT    NOT NULL DEFAULT 0.0 COMMENT '[0,1] olcek, matrix_kitchen_batches.output_purity ile ayni',
    `purity_sample_count`         INT      NOT NULL DEFAULT 0 COMMENT 'average_purity_intercepted hareketli ortalamasinin kendi bagimsiz sayaci',
    `lockdown_active`             TINYINT(1) NOT NULL DEFAULT 0,
    `updated_at`                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_matrix_learning_core_trap_house` (`trap_house_id`),
    CONSTRAINT `fk_matrix_learning_core_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- ---------------------------------------------------------------------
-- Toplu Satis Hub'lari (District Distribution Hubs) -- F10 ile kritik
-- kavsaklara atanan, trap house'un ortak deposundan (matrix_trap_stash_
-- <id>) sabit miktarli/RNG'siz toplu satis dongusu yuruten dugumler.
-- `locked`, server/bureau.lua [T4]'un 'matrix:internal:bureauLockdown'
-- yayinindan senkronize edilir (server/district_hubs.lua).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `matrix_district_hubs` (
    `id`             INT          NOT NULL AUTO_INCREMENT,
    `trap_house_id`  INT          NOT NULL,
    `label`          VARCHAR(100) NOT NULL,
    `coord_x`        FLOAT        NOT NULL,
    `coord_y`        FLOAT        NOT NULL,
    `coord_z`        FLOAT        NOT NULL,
    `active`         TINYINT(1)   NOT NULL DEFAULT 1,
    `locked`         TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_district_hubs_trap_house` (`trap_house_id`),
    CONSTRAINT `fk_matrix_district_hubs_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- =======================================================================
-- ★ KAYNAK: sql/layer7_faz3.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

-- =====================================================================
-- KATMAN 7 [T4] FAZ 3: OX_TARGET SOKAK DEVSIRME KOPRUSU
-- Additive migration. Yukaridaki (matrix.sql / layer5_ultimate.sql /
-- layer6_trap_house.sql / layer7_faz1.sql) hicbir tablosu/alani
-- DEGISTIRILMEDI -- ayni disiplin, yeni bir ALTER TABLE.
--
-- loyalty_base: [0,1] olcek, diger psychology alanlari (resilience,
-- snitch_tendency, ...) ILE AYNI sekilde matrix_bots'a eklenir.
-- server/recruitment.lua Matrix.Recruitment.RecruitStreetNpc'nin
-- ustunde calistigi TEK psikoloji semasi budur -- ikinci bir tablo
-- ACILMAZ. Varsayilan 0.5 (mevcut resilience/cognitive_shifter
-- varsayilanlariyla AYNI taban); yalnizca Ox_Target "Kadroya Kat"
-- devsirmesi (server/market.lua, /sokakdevsir test komutu ile AYNI
-- disiplin) bunu acikca 1.0 (mutlak sadik) yazar.
--
-- NOT: `ADD COLUMN IF NOT EXISTS`, MySQL 8.0.29+ / MariaDB 10.0+
-- gerektirir (oxmysql'in desteklediği surumlerin tamami bunu karsilar).
-- =====================================================================
ALTER TABLE `matrix_bots`
    ADD COLUMN IF NOT EXISTS `loyalty_base` FLOAT NOT NULL DEFAULT 0.5
        COMMENT '[0,1]; Ox_Target ile devsirilen ajanlar 1.0 (mutlak sadik) alir'
        AFTER `snitch_tendency`;

-- =======================================================================
-- ★ KAYNAK: sql/layer7_faz4_front_business.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

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


-- =======================================================================
-- ★ KAYNAK: sql/layer7_faz5_mercenary.sql (orijinal içerik, birebir aşağıda, hiçbir satır atlanmadı)
-- =======================================================================

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
-- ★★★ [FAZ 2] KALICI ÖLÜM (ADLİ ZİNCİR KORUMASI) -- SAVUNMACI ALTER ★★★
-- Yukarıdaki `matrix_customer_pool` CREATE TABLE tanımı `is_dead` kolonunu
-- ZATEN içerir (yeni/temiz kurulumlar için) -- CREATE TABLE IF NOT EXISTS
-- bir tablo ZATEN VARSA hiçbir şey yapmaz. Bu dosya daha önce (bu kolon
-- eklenmeden ÖNCE) bir veritabanına çalıştırılmış olabileceğinden, aşağıdaki
-- ADD COLUMN IF NOT EXISTS o durumda da kolonu güvenle ekler -- iki durumda
-- da (temiz kurulum veya yeniden çalıştırma) nihai şema AYNIDIR.
-- =====================================================================
ALTER TABLE `matrix_customer_pool`
    ADD COLUMN IF NOT EXISTS `is_dead` TINYINT(1) NOT NULL DEFAULT 0
        COMMENT 'Sema-tutarlilik kolonu -- su an hicbir kod okumaz/yazmaz (bkz. CREATE TABLE yorumu)'
        AFTER `name`;

-- =====================================================================
-- DOĞRULAMA SORGUSU (opsiyonel)
-- =====================================================================
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'matrix_bots'
--   AND COLUMN_NAME IN ('accounting_precision','loss_report_total','on_strike');
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'matrix_zone_inspectors'
--   AND COLUMN_NAME IN ('audit_score','warning_level','is_wiped');
-- SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'matrix_customer_pool'
--   AND COLUMN_NAME = 'is_dead';


