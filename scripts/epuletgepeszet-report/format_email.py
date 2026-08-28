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
            out.append(f"  * {s['tkod']} | {s['termek_nev']} | hiányzik: {s['hianyzo_mennyiseg']:g}")
            if not s["van_forras"]:
                out.append("      (nincs ismert beszerzési forrás)")
            else:
                for o in s["beszallitok"]:
                    out.append(render_offer_line(o))
    out.append("")
    out.append("=" * 70)
    out.append("2. TERMÉK-ÖSSZESÍTŐ")
    out.append("=" * 70)
    for p in report["termek_osszesito"]:
        out.append("")
        out.append(f"{p['tkod']} | {p['termek_nev']}")
        out.append(f"  Összes hiányzó mennyiség: {p['osszes_hianyzo_mennyiseg']:g} "
                    f"({p['erintett_rendelesek']} rendelésen)")
        if not p["van_forras"]:
            out.append("  (nincs ismert beszerzési forrás)")
        else:
            for o in p["beszallitok"]:
                out.append(render_offer_line(o))

    text = "\n".join(out)
    if len(sys.argv) > 2:
        open(sys.argv[2], "w", encoding="utf-8").write(text)
        print(f"Írva: {sys.argv[2]} ({len(text)} karakter)")
    else:
        print(text)


if __name__ == "__main__":
    main()
