fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'projeFivem'
description 'Katman 1-2-3-4-5 ULTIMATE + KATMAN 6 Birlesik Motor + KATMAN 7 [T1-T4] Faz 1-2 + SIBER-TAKTIK MIMARI FAZ 2: Core Matrix, Adli Balistik (+ Gercekci Namlu Asinmasi/Tutukluk + Real-Time Ust Arama + Biyometrik Maske/Eldiven OPSEC), Recruitment (+ Propaganda Devsirme Koprusu), The Bureau (+ Buro Kilidi/Nukleer Abluka + AI Danisma Koprusu + Yozlasmis Polis Rusvet Kanali Imhasi), Mutfak & Psikoloji Simulasyonu (+ Paketleme Odasi), Programli Lojistik Sevk (+ Otomatik Rota Teslimati + GTAO Cikis Koprusu + Toplu Satis Hub Lojistigi + Bagaj Ameliyati), Qbox Co-op Kartel Hiyerarsisi & Bolgesel Piyasa (+ Canli Sokak Satis Dongusu), Taktik Karaborsa Ticaret Agi (+ Rendezvous Teslimati/Buro Pususu), SIGINT/COMINT Bolge Denetleyicileri, Sanal Mahalle Evi (Interior Instance), Silah Tamir Tezgahi & Paketleme Odasi, Kapi Surgu Tahkimati, Monokrom Taktik HUD, Paravan Sirket/Sahte Fatura Aklama + Adli Muhasebe Anomalisi (Mali Wipe), Dinamik Isim Havuzlu Kriminal Haber Bulteni'
version '1.7.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    'client/hud.lua',
    'client/trap_house_client.lua',
    -- ★ Bestecinin İmzası: spawn-sonrası monokrom taktik bülten + opsiyonel
    -- Bach ses katmanı (bkz. shared/config.lua Config.ComposerSignature).
    'client/composer_intro.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/forensics.lua',
    'server/recruitment.lua',
    'server/bureau.lua',
    'server/district_hubs.lua',
    'server/kitchen.lua',
    'server/logistics.lua',
    'server/market.lua',
    'server/blackmarket.lua',
    'server/rendezvous.lua',
    'server/trap_house_interior.lua',
    'server/workbench.lua',
    'server/door_reinforcement.lua',
    -- ★ FAZ 2: Kriminal Finans, Adli Muhasebe ve Dinamik Haber Bülteni.
    -- news_bulletin.lua, logistics.lua'nın Matrix.News.OnCivilianBotEliminated
    -- çağrısını (server/logistics.lua) ve bureau.lua'nın CorruptOfficers
    -- bayrağını (server/bureau.lua) RUNTIME'da okuduğu için sıra fonksiyonel
    -- olarak kritik değildir, ama okunabilirlik için diğer FAZ dosyalarının
    -- hemen ardına eklendi.
    'server/shell_company.lua',
    'server/news_bulletin.lua',
    -- ★ Otomasyonlu Regresyon Çekirdeği: diğer TÜM server dosyalarının
    -- Matrix.* kancalarını okuduğu için listenin EN SONUNDA (yalnızca
    -- okunabilirlik için -- kontroller run-time'da çalıştığından, o ana
    -- kadar her dosya zaten tam yüklenmiş olur, sıra fonksiyonel olarak
    -- kritik değildir).
    'server/matrix_diagnostics.lua'
}

-- ★ Bestecinin İmzası ses dosyaları: bu repoda YOK (bkz. shared/config.lua
-- Config.ComposerSignature yorumu). Gerçek .ogg dosyalarınızı BURAYA
-- (resource kökünde 'sounds/') koyduğunuzda FiveM'in NUI köprüsü
-- (client/composer_intro.lua'nın cfx-nui-<resource>/... isteği) onları
-- servis edebilsin diye önceden bildiriliyor -- dosyalar yokken bu satır
-- zararsızdır (yalnızca "yayınlanabilir" bir yol listeler).
files {
    'sounds/*.ogg'
}

dependencies {
    'ox_lib',
    'qbx_core',
    'oxmysql',
    'ox_inventory',
    -- ★ KATMAN 7 [T4] FAZ 3: sokak "keş" NPC'sinde "Kadroya Kat (Ajan
    -- Devşir)" etkileşim seçeneği (client/hud.lua SpawnStreetNpc) için.
    'ox_target',
    -- ★ Bestecinin İmzası: özel .ogg dosyalarını (Config.ComposerSignature)
    -- çalmak için -- DOĞRULANMASI GEREKİR: xsound'un export imzası forka
    -- göre değişebilir, client/composer_intro.lua PlayUrl/Destroy'u
    -- pcall içinde çağırır (yanlış imza -> sessizce ses çalmaz, ÇÖKMEZ).
    -- Kurulum: https://github.com/Xanthenite/xsound -> resources/ klasörüne
    -- çıkarıp server.cfg'ye "start xsound" ekleyin.
    'xsound',
    -- ★ KATMAN 6: Trap house iç mekanı (client/trap_house_client.lua)
    -- GTA Online "düşük gelirli ev" interior'ını doğru render etmek için
    -- bu kaynağı kullanır (bkz. shared/config.lua Config.TrapHouseInterior.
    -- Shell yorumu).
    -- Kurulum: https://github.com/Bob74/bob74_ipl -> resources/ klasörüne
    -- çıkarıp server.cfg'ye "start bob74_ipl" ekleyin (bu satırdan ÖNCE
    -- veya bağımsız bir yerde olabilir, sıra kritik değildir).
    'bob74_ipl'
}