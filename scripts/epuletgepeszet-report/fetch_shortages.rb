#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Epuletgepeszet napi hianycikk-jelentes -- 1. lepes: nyitott bejovo
# megrendelesek + hianycikkek lekerdezese kozvetlenul az RS3 MySQL-bol
# (SSH nelkul, lasd rs3-direct-access-from-marveen skill).
#
# Vegleges definicio (Donat + Milan jovahagyva, 2026-08-28):
#   megrendfej.thkod = 7 (epuletgepeszet telephely)
#   megrendfej.archivalva IS NULL (nyitott, NEM datumszures)
#   megrendlab.menny - megrendlab.szalliton > 0 (teljesitetlen tetel)
#   cikk.szabad <= 0 (globalis hianycikk, NEM telephelyenkenti)
#
# Kimenet: JSON stdout-ra (vagy --out FAJL-ba), amit a kovetkezo lepes
# (beszallito-parositas + celzott frissites, tebez-prod SSH-n) dolgoz fel.
# Csak olvas, semmit nem ir az RS3-ba.

require 'json'
require 'optparse'

TEBEZ_DIR = File.expand_path('~/tebez')
$LOAD_PATH.unshift(TEBEZ_DIR)
Dir.chdir(TEBEZ_DIR) do
  env_file = File.join(TEBEZ_DIR, '.env')
  if File.exist?(env_file)
    File.readlines(env_file).each do |line|
      line = line.sub(/\r$/, '').strip
      next if line.empty? || line.start_with?('#')
      k, v = line.split('=', 2)
      ENV[k] ||= v if k && v
    end
  end
end
require_relative File.join(TEBEZ_DIR, 'suppliers_db/megbizo_connection')

def fix_enc(v)
  return v unless v.is_a?(String)
  v.dup.force_encoding('CP1250').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
end

out_path = nil
OptionParser.new { |o| o.on('--out FILE') { |v| out_path = v } }.parse!(ARGV)

sql = <<~SQL
  SELECT mf.mkod, mf.datum, mf.megnev AS vevo_nev,
         CASE WHEN mf.ocid3 IS NOT NULL AND mf.ocid3 <> 0 THEN 'OC3' ELSE 'kezi' END AS forras,
         ml.tkod, c.megnev AS termek_nev, (ml.menny - ml.szalliton) AS hianyzo_mennyiseg
  FROM megrendfej mf
  JOIN megrendlab ml ON ml.mkod = mf.mkod
  JOIN cikk c ON c.tkod = ml.tkod
  WHERE mf.thkod = 7
    AND mf.archivalva IS NULL
    AND (ml.menny - ml.szalliton) > 0
    AND COALESCE(c.szabad, 0) <= 0
    -- Szolgaltatas/dij/nem-keszletezett tetelek kizarva (2026-08-28: felderitve
    -- amikor "Szallitasi koltseg WEB" es "Utanvet dij EPGEP" 35, illetve 21
    -- rendelesen tuntek fel hianycikkkent -- a szabad<=0 naluk nem valodi hiany).
    -- A csoport tabla TOBB, EGYMASTOL FUGGETLEN faban is tartalmaz ilyen
    -- kategoriat (nem egy kozos gyoker alatt), ezert nev szerint zarjuk ki,
    -- nem csak a mar ismert 4801/4802/4803 kod alatt: Szolgaltatasok (1577,
    -- 4801), Szallitasi koltsegek (1594), Szerviz (1917), Szallitas/anyagmoz-
    -- gatas tobbszoros elofordulasban (2529, 3098, 4118, 5193), Utalvany
    -- (3934), Beszallitoi szallitasi ktsg. (3935), Kiszallitas (4802),
    -- Szolgaltatas (4803), Szallitas (4776).
    AND c.csopkod NOT IN (1577, 1594, 1917, 2529, 3098, 3934, 3935, 4118, 4776, 4801, 4802, 4803, 5193)
  ORDER BY mf.datum ASC, mf.mkod, ml.tkod
SQL

rows = SuppliersDB::MegbizoConnection.query(sql)

cutoff_days = 90
now = Time.now
orders = {}
product_totals = {}

rows.each do |r|
  mkod = r['mkod'].to_i
  datum = r['datum']
  age_days = datum ? ((now - datum) / 86_400.0).round : nil
  orders[mkod] ||= {
    'mkod' => mkod,
    'datum' => datum&.strftime('%Y-%m-%d'),
    'vevo_nev' => fix_enc(r['vevo_nev']),
    'forras' => r['forras'],
    'kor_jelzes' => (age_days && age_days > cutoff_days) ? '90+ napos' : 'friss',
    'sorok' => [],
  }
  tkod = fix_enc(r['tkod'])
  termek_nev = fix_enc(r['termek_nev'])
  menny = r['hianyzo_mennyiseg'].to_f
  orders[mkod]['sorok'] << {
    'tkod' => tkod,
    'termek_nev' => termek_nev,
    'hianyzo_mennyiseg' => menny,
  }
  pt = (product_totals[tkod] ||= { 'tkod' => tkod, 'termek_nev' => termek_nev, 'osszes_hianyzo_mennyiseg' => 0.0, 'rendelesek' => 0 })
  pt['osszes_hianyzo_mennyiseg'] += menny
  pt['rendelesek'] += 1
end

result = {
  'generalva' => now.strftime('%Y-%m-%d %H:%M:%S'),
  'kriterium' => 'thkod=7, archivalva IS NULL, menny-szalliton>0, cikk.szabad<=0',
  'rendelesek' => orders.values,
  'termek_osszesito' => product_totals.values.sort_by { |p| -p['osszes_hianyzo_mennyiseg'] },
  'osszes_rendeles' => orders.size,
  'osszes_termek' => product_totals.size,
}

json = JSON.pretty_generate(result)
if out_path
  File.write(out_path, json, encoding: 'UTF-8')
  warn "Irva: #{out_path} (#{orders.size} rendeles, #{product_totals.size} hianycikk)"
else
  puts json
end
