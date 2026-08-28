#!/usr/bin/env python3
"""Epuletgepeszet napi hianycikk-jelentes -- 3. lepes: a nyitott rendeleseket
(shortages.json) es a beszallitoi ajanlatokat (offers.json) egyesiti a
specifikacio 6. pontja szerinti vegso szerkezetbe (report.json). Meg NEM
formaz emailt, csak a strukturalt adatot allitja ossze."""
import json
import sys


def main():
    shortages_path, offers_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    shortages = json.load(open(shortages_path, encoding="utf-8"))
    offers = json.load(open(offers_path, encoding="utf-8"))

    termekek = offers.get("termekek", {})
    forras_nelkul = set(offers.get("forras_nelkul", []))

    # 6.1 -- rendelesenkenti bontas: minden sorhoz csatoljuk a beszallitoi ajanlatokat
    rendelesek = []
    for r in shortages["rendelesek"]:
        sorok = []
        for s in r["sorok"]:
            tkod = s["tkod"]
            sorok.append({
                "tkod": tkod,
                "termek_nev": s["termek_nev"],
                "hianyzo_mennyiseg": s["hianyzo_mennyiseg"],
                "van_forras": tkod not in forras_nelkul,
                "beszallitok": termekek.get(tkod, []),
            })
        rendelesek.append({
            "mkod": r["mkod"],
            "datum": r["datum"],
            "vevo_nev": r["vevo_nev"],
            "forras": r["forras"],
            "kor_jelzes": r["kor_jelzes"],
            "sorok": sorok,
        })

    # 6.2 -- termekenkenti osszesito, ar szerint rendezett beszallitokkal
    def price_sort_key(offer):
        ar = offer.get("netto_ar")
        return (ar is None, ar if ar is not None else 0)

    osszesito = []
    for p in shortages["termek_osszesito"]:
        tkod = p["tkod"]
        beszallitok = sorted(termekek.get(tkod, []), key=price_sort_key)
        osszesito.append({
            "tkod": tkod,
            "termek_nev": p["termek_nev"],
            "osszes_hianyzo_mennyiseg": p["osszes_hianyzo_mennyiseg"],
            "erintett_rendelesek": p["rendelesek"],
            "van_forras": tkod not in forras_nelkul,
            "beszallitok": beszallitok,
        })

    report = {
        "generalva": shortages["generalva"],
        "kriterium": shortages["kriterium"],
        "osszes_rendeles": shortages["osszes_rendeles"],
        "osszes_termek": shortages["osszes_termek"],
        "forras_nelkuli_termekszam": len(forras_nelkul),
        "rendelesenkenti_bontas": rendelesek,
        "termek_osszesito": osszesito,
    }

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(f"Kesz: {out_path} ({len(rendelesek)} rendeles, {len(osszesito)} termek, "
          f"{len(forras_nelkul)} forras nelkul)")


if __name__ == "__main__":
    main()
