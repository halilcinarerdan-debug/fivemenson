-- =====================================================================
-- ★★★ REGRESYON: 9 DB ŞEMA KONTROLÜ + ADLİ RPG / KOR NOKTA ŞEMASI ★★★
-- matrix_diagnostics.lua DbChecks tablosuna geri enjekte edilen 9 kontrolün
-- dayandığı şema + /davaac (Adli RPG), FragmentTerritory (Gang Learning
-- Core) ve /telefonuyoket (Adli Sabotaj) için gereken YENİ tablolar/kolonlar.
-- Bu dosya defalarca çalıştırılabilir (IF NOT EXISTS / kolon varlık
-- kontrolü olmayan ALTER'lar için, MySQL 8+ üzerinde ADD COLUMN IF NOT
-- EXISTS kullanılır; eski MySQL 5.7 için elle bir kez uygulayın).
-- =====================================================================

-- [1] matrix_zone_ledger.dirty_cash_pool -- bölgeye bağlı, henüz aklanmamış
-- kirli nakit havuzu (Matrix.CashDecay ile AYNI "kirli nakit" kavramı,
-- yalnızca bölge bazında ayrı bir toplam).
ALTER TABLE `matrix_zone_ledger`
    ADD COLUMN IF NOT EXISTS `dirty_cash_pool` FLOAT NOT NULL DEFAULT 0.0;

-- [2] matrix_bots.accounting_precision -- botun kendi nakit/envanter
-- muhasebesinin (BotStreetCash vb.) ne kadar "temiz" tutulduğunu ölçen,
-- [0,1] ölçekli bir sağlık katsayısı.
ALTER TABLE `matrix_bots`
    ADD COLUMN IF NOT EXISTS `accounting_precision` FLOAT NOT NULL DEFAULT 1.0;

-- [KOR NOKTA] matrix_bots.handler_citizenid + genişletilmiş status ENUM'u
-- (server/bureau.lua Matrix.Bureau.ExecuteVerdict bulk-disband hedeflemesi
-- + Koma Modu için).
ALTER TABLE `matrix_bots`
    ADD COLUMN IF NOT EXISTS `handler_citizenid` VARCHAR(50) NULL;
ALTER TABLE `matrix_bots`
    MODIFY COLUMN `status` ENUM('active','burned','deceased','retired','disbanded','comatose') NOT NULL DEFAULT 'active';

-- [3] matrix_zone_inspectors.is_wiped -- bir Denetleyici'nin istihbaratı
-- (kendi kayıtları) bir /kameralogutemizle veya /telefonuyoket sabotajıyla
-- kazınmışsa işaretlenir.
ALTER TABLE `matrix_zone_inspectors`
    ADD COLUMN IF NOT EXISTS `is_wiped` TINYINT(1) NOT NULL DEFAULT 0;

-- [4] matrix_purchase_logs -- Büro'nun saatlik mali denetiminin (bkz.
-- server/bureau.lua Matrix.Bureau.RunHourlyFinancialAudit) 24 saatten eski
-- satırları otonom budadığı genel fatura/işlem günlüğü.
CREATE TABLE IF NOT EXISTS `matrix_purchase_logs` (
    `id`          INT          NOT NULL AUTO_INCREMENT,
    `citizenid`   VARCHAR(50)  NULL,
    `item_ref`    VARCHAR(100) NOT NULL,
    `amount`      FLOAT        NOT NULL DEFAULT 0.0,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_purchase_logs_created_at` (`created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- [5] matrix_customer_pool.is_dead -- bir sokak müşterisinin (keş) kalıcı
-- olarak havuzdan düşmesi gerektiğini işaretler (aşırı doz/koma zinciriyle
-- AYNI felsefe, bkz. Koma Modu).
ALTER TABLE `matrix_customer_pool`
    ADD COLUMN IF NOT EXISTS `is_dead` TINYINT(1) NOT NULL DEFAULT 0;

-- [6] matrix_gang_learning_core -- FragmentTerritory (server/district_hubs.lua)
-- her bölünmede bir satır işler: hangi trap house'un cete lideri düştü,
-- kaç Alt Hücre'ye (Splinter Cell) bölündü.
CREATE TABLE IF NOT EXISTS `matrix_gang_learning_core` (
    `id`               INT      NOT NULL AUTO_INCREMENT,
    `trap_house_id`    INT      NOT NULL,
    `splinter_count`   INT      NOT NULL DEFAULT 0,
    `aggression_level` FLOAT    NOT NULL DEFAULT 0.0,
    `updated_at`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_gang_learning_core_trap_house` (`trap_house_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- [7] matrix_trial_records -- /davaac + /davasorgula (server/bureau.lua)
-- çift fazlı adli RPG diyalog zincirinin kalıcı dava dosyası.
CREATE TABLE IF NOT EXISTS `matrix_trial_records` (
    `id`                   INT          NOT NULL AUTO_INCREMENT,
    `defendant_citizenid`  VARCHAR(50)  NOT NULL,
    `dna_id`               VARCHAR(64)  NOT NULL,
    `ballistic_id`         VARCHAR(64)  NULL,
    `match_certainty`      FLOAT        NOT NULL DEFAULT 0.0,
    `lie_count`            INT          NOT NULL DEFAULT 0,
    `conviction_weight`    FLOAT        NOT NULL DEFAULT 0.0,
    `verdict`              VARCHAR(20)  NOT NULL DEFAULT 'pending',
    `opened_at`            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `closed_at`            DATETIME     NULL,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_trial_records_defendant` (`defendant_citizenid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- [8] matrix_player_state.imprisoned -- /davaac verdict %100 mahkumiyette
-- karakter kilidi (Karakter Wipe + DropPlayer).
ALTER TABLE `matrix_player_state`
    ADD COLUMN IF NOT EXISTS `imprisoned` TINYINT(1) NOT NULL DEFAULT 0;

-- [9] matrix_legal_plate_evidence -- plaka-bazlı adli delil izi (matrix_fleet
-- ile AYNI plaka kimlik uzayı; ikinci bir "plaka" kavramı İCAT EDİLMEZ).
CREATE TABLE IF NOT EXISTS `matrix_legal_plate_evidence` (
    `id`            INT          NOT NULL AUTO_INCREMENT,
    `plate`         VARCHAR(32)  NOT NULL,
    `citizenid`     VARCHAR(50)  NULL,
    `ballistic_id`  VARCHAR(64)  NULL,
    `recorded_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_legal_plate_evidence_plate` (`plate`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- [KOR NOKTA] /telefonuyoket adli sabotaj komutunun sildiği kriptolu mesaj
-- günlüğü (YENİ tablo -- matrix_forensic_evidence'ın evidence_type='cyber'
-- satırlarıyla BİRLİKTE, aynı atomik transaction'da silinir).
CREATE TABLE IF NOT EXISTS `matrix_encrypted_messages` (
    `id`           INT          NOT NULL AUTO_INCREMENT,
    `dna_id`       VARCHAR(64)  NOT NULL,
    `content_hash` VARCHAR(64)  NOT NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_encrypted_messages_dna_id` (`dna_id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
