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
         ml.tkod, c.megnev AS termek_nev, (ml.menny - ml.szalliton) AS hianyzo_mennyiseg,
         ml.ar AS eladasi_ar_netto, c.csopkod, cs.megnev AS csopnev
  FROM megrendfej mf
  JOIN megrendlab ml ON ml.mkod = mf.mkod
  JOIN cikk c ON c.tkod = ml.tkod
  LEFT JOIN csoport cs ON cs.kod = c.csopkod
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
seen_groups = {} # csopkod (int) => csopnev, minden a mai listaban elofordulo csoport

rows.each do |r|
  csopkod = r['csopkod']&.to_i
  seen_groups[csopkod] = fix_enc(r['csopnev']) || '(nincs csoportnev)' if csopkod
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
  # A megrendelesen szereplo netto eladasi egysegar (megrendlab.ar) -- Milan
  # kerese (2026-08-28 21:08): a beszerzo azonnal lassa, milyen ar ALATT kell
  # beszerezni, hogy maradjon arres. Rendelesenkent (nem termekenkent) lehet
  # eltero, ezert soronkent adjuk at, es a termek-osszesitonel tartomanykent.
  eladasi_ar = r['eladasi_ar_netto'] ? r['eladasi_ar_netto'].to_f : nil
  orders[mkod]['sorok'] << {
    'tkod' => tkod,
    'termek_nev' => termek_nev,
    'hianyzo_mennyiseg' => menny,
    'eladasi_ar_netto' => eladasi_ar,
  }
  pt = (product_totals[tkod] ||= { 'tkod' => tkod, 'termek_nev' => termek_nev, 'osszes_hianyzo_mennyiseg' => 0.0, 'rendelesek' => 0, 'eladasi_arak' => [] })
  pt['osszes_hianyzo_mennyiseg'] += menny
  pt['rendelesek'] += 1
  pt['eladasi_arak'] << eladasi_ar if eladasi_ar
end

# RS3 sajat beszerzesi elozmeny -- bevet + bevetlab (TENYLEGES bevetelezes,
# valodi szallitoi szamlaval), NEM megrendfejk/megrendlabk (az csak a kimeno
# beszerzesi RENDELES, ami sok esetben nincs is kitoltve meg ha a bevetelezes
# megtortent -- 2026-08-28-an Milan konkret peldaval (VG-739072, Fogarasi
# Ep-Gepesz Kft, szamla FO1026B-09580, bevet.bkod=33623) buktatta meg a
# korabbi megrendfejk-alapu verziot: a valodi vasarlas nem szerepelt benne,
# mert oda a formalis rendeles-lepes nelkul is bevetelezhet. A bevet tablaban
# a szallneve mezo mar keszen van, nincs szukseg szallito-join-ra.
# Lefedettseg osszehasonlitva a 2026-08-28-i 60-as hianycikk-mintan:
# megrendfejk 10/60, bevet/bevetlab 49/60 -- ez az elsodleges forras.
def rs3_purchase_history(tkod)
  esc = tkod.gsub("'", "''")
  sql = <<~SQL
    SELECT b.datum, b.szallneve AS beszallito, bl.ar, bl.db AS menny
    FROM bevet b
    JOIN bevetlab bl ON bl.bkod = b.bkod
    WHERE bl.tkod = '#{esc}'
    ORDER BY b.datum DESC
    LIMIT 3
  SQL
  SuppliersDB::MegbizoConnection.query(sql).map do |r|
    {
      'datum' => r['datum']&.strftime('%Y-%m-%d'),
      'beszallito' => fix_enc(r['beszallito']) || 'ismeretlen (bevet.szallneve ures)',
      'egysegar' => r['ar'],
      'mennyiseg' => r['menny'],
    }
  end
end

product_totals.each_value do |pt|
  pt['rs3_beszerzesi_elozmeny'] = rs3_purchase_history(pt['tkod'])
  arak = pt.delete('eladasi_arak')
  pt['eladasi_ar_netto_min'] = arak.min
  pt['eladasi_ar_netto_max'] = arak.max
end

# Uj termekcsoport-eszleles (Donat kerese, 2026-08-30): ha a hianycikkek kozott
# olyan csopkod bukkan fel, ami korabban meg SOHA nem szerepelt ebben a
# jelentesben, azt jelezzuk a report vegen -- nem zarjuk ki, nem dontunk
# helyette, csak lathatova tesszuk. Ugyanazt a hibaosztalyt fedi le ami a
# "Szallitasi koltseg WEB"/"Utanvet dij EPGEP" csoportoknal harom het alatt
# derult ki (lasd a fenti kizaras kommentjet): igy mar az elso elofordulaskor
# lathato, nem csak amikor mar furcsan nez ki a jelentes.
known_groups_path = out_path ? File.join(File.dirname(out_path), 'known_groups.json') : nil
# Az allapotfajl a store/ alatt van, NINCS verziokezelve (mint korabban az
# outgoing-copy-gate-rules.json, aminek elveszese fel napba kerult -- Donat,
# 2026-08-30). Ha eltunik, a kovetkezo futas csendben ujraseedelne es minden
# csoportot ismertnek jelolne -- pont akkor nyelne el nemán egy uj csoportot,
# amikor a detektalasnak mukodnie kene. Ezert kulon jelezzuk ha ujraepult.
known_groups_missing = known_groups_path ? !File.exist?(known_groups_path) : false
known_groups = {}
if known_groups_path && File.exist?(known_groups_path)
  JSON.parse(File.read(known_groups_path, encoding: 'UTF-8')).each { |k, v| known_groups[k.to_i] = v }
end
uj_termekcsoportok = seen_groups.reject { |kod, _| known_groups.key?(kod) }
                                 .map { |kod, nev| { 'csopkod' => kod, 'csopnev' => nev } }
                                 .sort_by { |g| g['csopkod'] }
if known_groups_path
  File.write(known_groups_path, JSON.pretty_generate(known_groups.merge(seen_groups)), encoding: 'UTF-8')
end

result = {
  'generalva' => now.strftime('%Y-%m-%d %H:%M:%S'),
  'kriterium' => 'thkod=7, archivalva IS NULL, menny-szalliton>0, cikk.szabad<=0',
  'rendelesek' => orders.values,
  'termek_osszesito' => product_totals.values.sort_by { |p| -p['osszes_hianyzo_mennyiseg'] },
  'osszes_rendeles' => orders.size,
  'osszes_termek' => product_totals.size,
  'uj_termekcsoportok' => uj_termekcsoportok,
  'allapotfajl_ujraepult' => known_groups_missing,
  'allapotfajl_csoport_szam' => seen_groups.size,
}

json = JSON.pretty_generate(result)
if out_path
  File.write(out_path, json, encoding: 'UTF-8')
  warn "Irva: #{out_path} (#{orders.size} rendeles, #{product_totals.size} hianycikk)"
else
  puts json
end
