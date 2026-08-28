#!/usr/bin/env python3
"""Epuletgepeszet napi hianycikk-jelentes -- 4. lepes: report.json-t olvashato
email-szoveggé formazza a specifikacio 6. pontja szerint (rendelesenkenti
bontas + termek-osszesito). Sima szoveg, nincs HTML/markdown."""
import json
import sys


def fmt_price(offer):
    if offer["netto_ar"] is None:
        return "nincs ár"
    return f"{float(offer['netto_ar']):,.0f} Ft".replace(",", " ")


def fmt_stock(offer):
    qty = offer.get("keszlet_mennyiseg")
    status = offer.get("keszlet_statusz") or "?"
    if qty is not None:
        return f"{qty} db ({status})"
    return status


def fmt_date(s):
    if not s:
        return "?"
    return s[:10]


def render_offer_line(o):
    return (f"      - {o['beszallito_nev']}: {fmt_price(o)} [{o['ar_cimke']}, "
            f"{fmt_date(o['ar_datuma'])}] | készlet: {fmt_stock(o)} "
            f"(frissítve: {fmt_date(o['keszlet_frissitve'])})")


def render_rs3_history(elozmeny):
    if not elozmeny:
        return ["      (RS3 saját beszerzési előzmény: nincs korábbi vásárlás)"]
    lines = ["      RS3 saját beszerzési előzmény (utolsó 3 alkalom):"]
    for h in elozmeny:
        ar = f"{float(h['egysegar']):,.0f} Ft".replace(",", " ") if h.get("egysegar") is not None else "nincs ár"
        menny = h.get("mennyiseg")
        menny_txt = f"{float(menny):g} db" if menny is not None else "?"
        lines.append(f"        * {fmt_date(h.get('datum'))} | {h.get('beszallito') or '?'} | "
                      f"{ar} | {menny_txt}")
    return lines


def main():
    report = json.load(open(sys.argv[1], encoding="utf-8"))
    out = []
    out.append(f"Épületgépészet napi hiánycikk-jelentés: {report['generalva'][:10]}")
    out.append("")
    out.append(f"Nyitott rendelés hiánycikkel: {report['osszes_rendeles']}")
    out.append(f"Különböző hiánycikk: {report['osszes_termek']}")
    out.append(f"Ebből ismert beszerzési forrás nélkül: {report['forras_nelkuli_termekszam']}")
    out.append("")
    out.append("=" * 70)
    out.append("1. RENDELÉSENKÉNTI BONTÁS")
    out.append("=" * 70)
    for r in report["rendelesenkenti_bontas"]:
        cimke = f" [{r['kor_jelzes']}]" if r["kor_jelzes"] != "friss" else ""
        out.append("")
        out.append(f"Rendelés {r['mkod']} | {r['datum']} | {r['vevo_nev']} ({r['forras']}){cimke}")
        for s in r["sorok"]:
            ar_txt = (f"{float(s['eladasi_ar_netto']):,.0f} Ft".replace(",", " ")
                      if s.get("eladasi_ar_netto") is not None else "nincs ár a rendelésen")
            out.append(f"  * {s['tkod']} | {s['termek_nev']} | hiányzik: {s['hianyzo_mennyiseg']:g} "
                       f"| eladási ár (megrendelésen): {ar_txt}")
            if not s["van_forras"]:
                out.append("      (nincs ismert beszerzési forrás a beszállítói adatbázisból)")
            else:
                for o in s["beszallitok"]:
                    out.append(render_offer_line(o))
            out.extend(render_rs3_history(s.get("rs3_beszerzesi_elozmeny", [])))
    out.append("")
    out.append("=" * 70)
    out.append("2. TERMÉK-ÖSSZESÍTŐ")
    out.append("=" * 70)
    for p in report["termek_osszesito"]:
        out.append("")
        out.append(f"{p['tkod']} | {p['termek_nev']}")
        out.append(f"  Összes hiányzó mennyiség: {p['osszes_hianyzo_mennyiseg']:g} "
                    f"({p['erintett_rendelesek']} rendelésen)")
        ar_min, ar_max = p.get("eladasi_ar_netto_min"), p.get("eladasi_ar_netto_max")
        if ar_min is None:
            ar_line = "nincs ár a rendeléseken"
        elif ar_min == ar_max:
            ar_line = f"{float(ar_min):,.0f} Ft".replace(",", " ")
        else:
            ar_line = (f"{float(ar_min):,.0f} - {float(ar_max):,.0f} Ft"
                       .replace(",", " "))
        out.append(f"  Eladási ár (megrendeléseken): {ar_line}")
        if not p["van_forras"]:
            out.append("  (nincs ismert beszerzési forrás a beszállítói adatbázisból)")
        else:
            for o in p["beszallitok"]:
                out.append(render_offer_line(o))
        out.extend(render_rs3_history(p.get("rs3_beszerzesi_elozmeny", [])))

    text = "\n".join(out)
    if len(sys.argv) > 2:
        open(sys.argv[2], "w", encoding="utf-8").write(text)
        print(f"Írva: {sys.argv[2]} ({len(text)} karakter)")
    else:
        print(text)


if __name__ == "__main__":
    main()
