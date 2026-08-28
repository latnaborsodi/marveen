#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Epuletgepeszet napi hianycikk-jelentes -- 2. lepes, FUT A TEBEZ-PROD
# SZERVEREN (SSH-n keresztul masolva/futtatva a marveen-src oldalrol,
# NEM resze a tebez repo-nak, csak felhasznalja azt require_relative-vel).
#
# Bemenet: --tkods FAJL (soronkent egy RS3 cikkszam, UTF-8)
# Kimenet: JSON stdout-ra (vagy --out FAJL-ba):
#   { "termekek": { TKOD => [ {beszallito ajanlat...}, ... ], ... },
#     "forras_nelkul": [TKOD, ...] }
#
# Amit csinal:
#   1. A valodi rs3_matcher.rb parositasi logikaval (marka + cikkszam + kezi
#      parositas, OLVASVA a mar meglevo modult, UPDATE nelkul) megkeresi
#      minden hianycikkhez a megfelelo (nem Megbizo) supplier_products sorokat.
#   2. Beszallitonkent csoportositva, parhuzamosan (max 6 szal, egy beszalli-
#      tohoz SOHA nem ket egyidejü keres) scrape-single-lel frissiti azokat a
#      termekeket, amiknek van scraper-je (Suppliers::Scrapers.has_scraper?).
#   3. Ujra lekerdezi a friss supplier_products + legutobbi supplier_price_
#      history sort minden parositott ajanlathoz (akkor is, ha a scrape-single
#      nem futott le ra -- pl. mert csak batch-parancs adja a nagyker arat,
#      lasd rs3-direct-access-from-marveen skill buktato).
#
# NEM ir az RS3-ba. A Postgres-be csak a scrape-single sajat, mar letezo
# irasai irnak (ugyanaz mint kezi futtataskor), a parositas maga csak SELECT.

require 'json'
require 'optparse'
require 'pg'

TEBEZ_DIR = ENV['TEBEZ_DIR'] || File.expand_path('~/tebez')
Dir.chdir(TEBEZ_DIR)
File.readlines('.env').each do |line|
  line = line.sub(/\r$/, '').strip
  next if line.empty? || line.start_with?('#')
  k, v = line.split('=', 2)
  ENV[k] ||= v if k && v
end

$LOAD_PATH.unshift(TEBEZ_DIR)
require File.join(TEBEZ_DIR, 'lib/suppliers/scrapers')

tkods_file = nil
out_path = nil
max_workers = 6
skip_refresh = false
OptionParser.new do |o|
  o.on('--tkods FILE') { |v| tkods_file = v }
  o.on('--out FILE') { |v| out_path = v }
  o.on('--workers N', Integer) { |v| max_workers = v }
  o.on('--skip-refresh', 'Ne hivja a scrape-single-t, csak a mar meglevo adatot kerdezze le') { skip_refresh = true }
end.parse!(ARGV)

abort('--tkods FILE kotelezo') unless tkods_file
tkods = File.readlines(tkods_file, encoding: 'UTF-8').map(&:strip).reject(&:empty?)
warn "Beolvasva #{tkods.size} hianycikk"

MEGBIZO_ID = 10

def pg_connect
  PG.connect(
    host: ENV.fetch('DB_HOST', 'localhost'),
    dbname: ENV.fetch('DB_NAME'),
    user: ENV.fetch('DB_USER'),
    password: ENV.fetch('DB_PASSWORD', ''),
    port: ENV.fetch('DB_PORT', '5432')
  )
end

# ---- 1. Parositas (read-only, a rs3_matcher.rb 5-agu SKU-egyezes + brand-szures logikaja) ----
matches = {} # tkod => [{ supplier_product_id:, supplier_id:, supplier_code:, supplier_name: }]
db = pg_connect
begin
  db.exec('BEGIN')
  db.exec('CREATE TEMP TABLE shortage_tkods (tkod text)')
  pg_array = '{' + tkods.map { |t| '"' + t.gsub('\\', '\\\\\\\\').gsub('"', '\\"') + '"' }.join(',') + '}'
  db.exec_params("INSERT INTO shortage_tkods (tkod) SELECT unnest($1::text[])", [pg_array])

  db.exec(<<~SQL)
    CREATE TEMP TABLE _megbizo_skus AS
    SELECT sp.id, sp.tkod_helper, sp.manufacturer_sku, sp.brand, sp.brand_id,
           normalize_sku(sp.manufacturer_sku) AS norm_mfr,
           normalize_sku(sp.supplier_sku) AS norm_sup,
           LOWER(sp.supplier_sku) AS lower_sup_sku
    FROM (
      SELECT sp.*, st.tkod AS tkod_helper
      FROM supplier_products sp JOIN shortage_tkods st ON st.tkod = sp.supplier_sku
      WHERE sp.supplier_id = #{MEGBIZO_ID} AND sp.is_active = TRUE
    ) sp
  SQL

  db.exec(<<~SQL)
    CREATE TEMP TABLE _supplier_skus AS
    SELECT id, manufacturer_sku, supplier_sku, brand, brand_id, supplier_id,
           normalized_sku AS norm_mfr, normalize_sku(supplier_sku) AS norm_sup,
           LOWER(supplier_sku) AS lower_sup_sku, LOWER(manufacturer_sku) AS lower_mfr_sku
    FROM supplier_products WHERE supplier_id <> #{MEGBIZO_ID} AND is_active = TRUE
  SQL

  db.exec(<<~SQL)
    CREATE TEMP TABLE _sku_matches AS
    SELECT DISTINCT m.id AS megbizo_id, s.id AS supplier_id
    FROM _megbizo_skus m JOIN _supplier_skus s ON m.norm_mfr = s.norm_mfr
    WHERE m.norm_mfr IS NOT NULL AND m.norm_mfr != '' AND s.norm_mfr IS NOT NULL AND s.norm_mfr != ''
    UNION
    SELECT DISTINCT m.id, s.id FROM _megbizo_skus m JOIN _supplier_skus s ON m.norm_mfr = s.norm_sup
    WHERE m.norm_mfr IS NOT NULL AND s.norm_sup IS NOT NULL
    UNION
    SELECT DISTINCT m.id, s.id FROM _megbizo_skus m JOIN _supplier_skus s ON m.norm_sup = s.norm_mfr
    WHERE m.norm_sup IS NOT NULL AND s.norm_mfr IS NOT NULL
    UNION
    SELECT DISTINCT m.id, s.id FROM _megbizo_skus m JOIN _supplier_skus s ON m.lower_sup_sku = s.lower_sup_sku
    WHERE m.lower_sup_sku IS NOT NULL AND s.lower_sup_sku IS NOT NULL
    UNION
    SELECT DISTINCT m.id, s.id FROM _megbizo_skus m JOIN _supplier_skus s ON m.lower_sup_sku = s.lower_mfr_sku
    WHERE m.lower_sup_sku IS NOT NULL AND s.lower_mfr_sku IS NOT NULL
  SQL

  rows = db.exec(<<~SQL)
    SELECT mb.tkod_helper AS tkod, s.id AS supplier_product_id, s.supplier_id, sup.code, sup.name
    FROM _sku_matches sm
    JOIN _megbizo_skus mb ON mb.id = sm.megbizo_id
    JOIN _supplier_skus s ON s.id = sm.supplier_id
    JOIN suppliers sup ON sup.id = s.supplier_id
    WHERE mb.brand IS NOT NULL AND mb.brand <> '' AND s.brand IS NOT NULL AND s.brand <> ''
      AND ( (mb.brand_id IS NOT NULL AND s.brand_id IS NOT NULL AND mb.brand_id = s.brand_id)
            OR ((mb.brand_id IS NULL OR s.brand_id IS NULL) AND LOWER(mb.brand) = LOWER(s.brand)) )
    UNION
    -- kezi (custom_matches) parositas is szamit
    SELECT mb.tkod_helper AS tkod, s.id AS supplier_product_id, s.supplier_id, sup.code, sup.name
    FROM _megbizo_skus mb
    JOIN custom_matches cm ON cm.megbizo_product_id = mb.id
    JOIN _supplier_skus s ON s.id = cm.supplier_product_id
    JOIN suppliers sup ON sup.id = s.supplier_id
  SQL

  rows.each do |r|
    (matches[r['tkod']] ||= []) << {
      'supplier_product_id' => r['supplier_product_id'].to_i,
      'supplier_id' => r['supplier_id'].to_i,
      'supplier_code' => r['code'],
      'supplier_name' => r['name'],
    }
  end
ensure
  db.exec('ROLLBACK')
  db.close
end

no_source = tkods - matches.keys
warn "Parositva: #{matches.size} termek, forras nelkul: #{no_source.size}"

# ---- 2. Celzott frissites, beszallitonkent csoportositva, parhuzamosan ----
unless skip_refresh
  by_supplier = Hash.new { |h, k| h[k] = [] }
  matches.each_value do |offers|
    offers.each { |o| by_supplier[o['supplier_code']] << o['supplier_product_id'] }
  end

  scrapeable = by_supplier.select { |code, _| Suppliers::Scrapers.has_scraper?(code) }
  warn "Frissitendo beszallitok: #{scrapeable.keys.join(', ')} (osszesen #{scrapeable.values.flatten.size} termek)"

  require 'thread'
  queue = Queue.new
  scrapeable.each { |code, ids| queue << [code, ids.uniq] }
  workers = [max_workers, scrapeable.size].min
  workers = 1 if workers < 1
  threads = Array.new(workers) do
    Thread.new do
      loop do
        code, ids = begin
          queue.pop(true)
        rescue ThreadError
          break
        end
        ids.each do |pid|
          system('xvfb-run', '-a', RbConfig.ruby, 'suppliers.rb', 'scrape-single', '-p', pid.to_s,
                 chdir: TEBEZ_DIR, out: File::NULL, err: File::NULL)
        end
        warn "  kesz: #{code} (#{ids.size} termek)"
      end
    end
  end
  threads.each(&:join)
end

# ---- 3. Friss adat ujralekerdezese minden parositott ajanlathoz ----
all_ids = matches.values.flatten.map { |o| o['supplier_product_id'] }.uniq
fresh = {}
if all_ids.any?
  db2 = pg_connect
  begin
    rows = db2.exec_params(<<~SQL, ['{' + all_ids.join(',') + '}'])
      SELECT sp.id, sp.purchase_price, sp.list_price, sp.stock_quantity, sp.stock_status, sp.last_scraped_at,
             h.gepesz_price, h.cu_price, h.nagyker_price, h.recorded_at AS nagyker_recorded_at
      FROM supplier_products sp
      LEFT JOIN LATERAL (
        -- legutobbi sor, aminek VAN legalabb egy kitoltott nagyker-jellegu ara
        -- (nem feltetlenul a legutobbi sor osszesitve -- egy friss kisker-only
        -- scrape-single futas felulirna a "legutobbi"-t regi nagyker ar nelkul)
        SELECT gepesz_price, cu_price, nagyker_price, recorded_at
        FROM supplier_price_history
        WHERE supplier_product_id = sp.id
          AND (gepesz_price IS NOT NULL OR cu_price IS NOT NULL OR nagyker_price IS NOT NULL)
        ORDER BY recorded_at DESC LIMIT 1
      ) h ON TRUE
      WHERE sp.id = ANY($1::int[])
    SQL
    rows.each { |r| fresh[r['id'].to_i] = r }
  ensure
    db2.close
  end
end

# Arcimke eldontese, Donat 2026-08-28-i dontese szerint:
#  - ha van tarolt nagyker-jellegu ar (gepesz/cu/nagyker_price barmelyike),
#    azt mutassuk, a sajat datumaval (utolso ismert ertek, NEM friss kell legyen)
#  - ha nincs, de van kisker (list_price/purchase_price) ar, azt mutassuk,
#    de EGYERTELMUEN "KISKER" cimkevel (pl. ferenczi, szerelvenybolt)
#  - ha semmi, "nincs aradat"
def price_label(f)
  if f['gepesz_price'] || f['cu_price'] || f['nagyker_price']
    szint = if f['gepesz_price'] then 'gépész szintű nagyker'
            elsif f['cu_price'] then 'cu szintű nagyker'
            else 'nagyker' end
    { 'cimke' => szint, 'netto_ar' => f['gepesz_price'] || f['cu_price'] || f['nagyker_price'],
      'ar_datuma' => f['nagyker_recorded_at'] }
  elsif f['list_price'] || f['purchase_price']
    { 'cimke' => 'kisker (nincs nagyker ár ehhez a beszállítóhoz)',
      'netto_ar' => f['list_price'] || f['purchase_price'], 'ar_datuma' => f['last_scraped_at'] }
  else
    { 'cimke' => 'nincs ár', 'netto_ar' => nil, 'ar_datuma' => nil }
  end
end

result = { 'termekek' => {}, 'forras_nelkul' => no_source }
matches.each do |tkod, offers|
  result['termekek'][tkod] = offers.map do |o|
    f = fresh[o['supplier_product_id']] || {}
    ar = price_label(f)
    {
      'beszallito_kod' => o['supplier_code'],
      'beszallito_nev' => o['supplier_name'],
      'ar_cimke' => ar['cimke'],
      'netto_ar' => ar['netto_ar'],
      'ar_datuma' => ar['ar_datuma'],
      'keszlet_mennyiseg' => f['stock_quantity'],
      'keszlet_statusz' => f['stock_status'],
      'keszlet_frissitve' => f['last_scraped_at'],
    }
  end
end

json = JSON.pretty_generate(result)
if out_path
  File.write(out_path, json, encoding: 'UTF-8')
  warn "Irva: #{out_path}"
else
  puts json
end
