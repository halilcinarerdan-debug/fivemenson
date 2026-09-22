-- =====================================================================
-- ★★★ OTONOM ALT HÜCRE BÖLÜNMESİ (FragmentTerritory / Splinter Cells) ★★★
-- Bir otonom çete lideri (bot.role == 'Leader') 'deceased' durumuna
-- düştüğünde (bkz. server/main.lua Matrix.RemoveBot), o trap house'a bağlı
-- TÜM matrix_district_hubs kayıtları bu tabloya "parçalanır" -- yeni bir
-- paralel ekonomi İCAT EDİLMEZ, yalnızca server/district_hubs.lua'nın
-- ZATEN VAR OLAN ProcessHubDemandCycle'ı + server/rendezvous.lua'nın
-- ZATEN VAR OLAN pusu event'i (matrix:client:rendezvous:triggerAmbush) +
-- server/bureau.lua'nın ZATEN VAR OLAN Matrix.Bureau.TriggerPropaganda
-- (siber-sızıntı) formülü bu yeni düğümlere BAĞLANIR.
-- =====================================================================
CREATE TABLE IF NOT EXISTS `matrix_splinter_cells` (
    `id`               INT          NOT NULL AUTO_INCREMENT,
    `parent_hub_id`    INT          NULL,
    `trap_house_id`    INT          NOT NULL,
    `splinter_index`   INT          NOT NULL,
    `coord_x`          FLOAT        NOT NULL,
    `coord_y`          FLOAT        NOT NULL,
    `coord_z`          FLOAT        NOT NULL,
    `active`           TINYINT(1)   NOT NULL DEFAULT 1,
    `created_at`       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_matrix_splinter_cells_trap_house` (`trap_house_id`),
    CONSTRAINT `fk_matrix_splinter_cells_trap_house`
        FOREIGN KEY (`trap_house_id`) REFERENCES `matrix_trap_houses` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
