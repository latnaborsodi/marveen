#!/usr/bin/env python3
"""kinai-outbox-poll --unanswered / --mark-reminded regression test.

The re-ask path only ever fires on a rare, silent failure (a lost approval
reply), so nothing exercises it in normal operation -- a break here would stay
invisible until it costs another 27-hour stall. Hence a test with fabricated
sent/ and inbox/ trees instead of the live agent directory.
"""
import importlib.util
import json
import os
import sys
import tempfile
import time

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "kinai-outbox-poll.py")


def load(tmp):
    spec = importlib.util.spec_from_file_location("poll", SCRIPT)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.AGENT_DIR = tmp
    m.OUTBOX = os.path.join(tmp, "outbox")
    m.SENT = os.path.join(m.OUTBOX, "sent")
    m.INBOX = os.path.join(tmp, "inbox")
    m.STATE_PATH = os.path.join(tmp, "state.json")
    m.ROUTING_PATH = os.path.join(tmp, "routing.json")
    os.makedirs(m.SENT)
    os.makedirs(os.path.join(m.INBOX, "feldolgozva"))
    return m


def write(path, body):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(body)


def due_names(m):
    return sorted(r["name"] for r in m.unanswered() if r["due"])


def main() -> int:
    failures = []

    def check(label, cond):
        print(("ok   " if cond else "FAIL ") + label)
        if not cond:
            failures.append(label)

    with tempfile.TemporaryDirectory() as tmp:
        m = load(tmp)
        now = time.time()
        ask = "Kérdés/kérés: jóváhagyod?"

        overdue = "2026-08-26T100000-teszt-jovahagyas.md"
        fresh = "2026-08-26T101500-masik-jovahagyas.md"
        answered = "2026-08-26T090000-valaszolt-jovahagyas.md"
        memo = "2026-08-26T080000-osszefoglalo.md"
        for name, body in ((overdue, ask), (fresh, ask), (answered, ask)):
            write(os.path.join(m.SENT, name), body)
        write(os.path.join(m.SENT, memo), "Csak tajekoztatas, nincs benne kerdes.")
        write(os.path.join(m.INBOX, "feldolgozva", f"2026-08-26T091000-valasz-{answered}"), "valasz")
        write(m.STATE_PATH, json.dumps({
            overdue: {"forwarded_at": now - 20 * 60},
            fresh: {"forwarded_at": now - 5 * 60},
            answered: {"forwarded_at": now - 90 * 60},
            memo: {"forwarded_at": now - 300 * 60},
        }))

        check("20 perce valasz nelkuli jovahagyas esedekes", due_names(m) == [overdue])
        check("5 perces meg nem esedekes", fresh not in due_names(m))
        rows = {r["name"] for r in m.unanswered()}
        check("megvalaszolt keres kimarad", answered not in rows)
        check("nem-jovahagyas fajl kimarad", memo not in rows)

        m.cmd_mark_reminded([overdue])
        check("emlekezteto utan visszaall a backoff", due_names(m) == [])

        state = json.load(open(m.STATE_PATH))
        state[overdue]["last_reminded_at"] = now - 61 * 60
        write(m.STATE_PATH, json.dumps(state))
        check("61 perc mulva ujra esedekes", due_names(m) == [overdue])

        for _ in range(2):
            state = json.load(open(m.STATE_PATH))
            state[overdue]["last_reminded_at"] = now - 500 * 60
            write(m.STATE_PATH, json.dumps(state))
            m.cmd_mark_reminded([overdue])
        row = next(r for r in m.unanswered() if r["name"] == overdue)
        check("harom emlekezteto utan kimerul, nem spammel", row["exhausted"] and not row["due"])

    with tempfile.TemporaryDirectory() as tmp:
        m = load(tmp)
        write(os.path.join(m.OUTBOX, "uj-jovahagyas.md"), "Kérdés/kérés: jóváhagyod?")
        m.cmd_archive(["uj-jovahagyas.md"])
        stamped = json.load(open(m.STATE_PATH)).get("uj-jovahagyas.md", {})
        check("--archive stampeli a forwarded_at-et", "forwarded_at" in stamped)
        check("frissen tovabbitott meg nem esedekes", due_names(m) == [])

    # Routing: post approvals to Reka, everything else to Donat, and a safe
    # fallback while Reka has no chat id yet.
    with tempfile.TemporaryDirectory() as tmp:
        m = load(tmp)
        ask = "Kérdés/kérés: jóváhagyod?"
        posts = "2026-08-26T120000-ket-poszt-jovahagyas.md"
        price = "2026-08-26T120000-arazas-jovahagyas.md"
        for name in (posts, price):
            write(os.path.join(m.SENT, name), ask)

        write(m.ROUTING_PATH, json.dumps({"default_chat_id": "111", "post_approver_chat_id": None,
                                          "post_approver_name": "Réka"}))
        by = {r["name"]: r["route"] for r in m.unanswered()}
        check("poszt-keres poszt tipusu", by[posts]["kind"] == "poszt")
        check("arazas-keres egyeb tipusu", by[price]["kind"] == "egyeb")
        check("beallitatlan poszt-jovahagyo eseten fallback jelzessel", by[posts]["fallback"] and by[posts]["chat_id"] == "111")

        write(m.ROUTING_PATH, json.dumps({"default_chat_id": "111", "post_approver_chat_id": "222",
                                          "post_approver_name": "Réka"}))
        by = {r["name"]: r["route"] for r in m.unanswered()}
        check("beallitott poszt-jovahagyo megkapja a poszt-kereseket", by[posts]["chat_id"] == "222" and not by[posts]["fallback"])
        check("az arazas akkor is a defaulthoz megy", by[price]["chat_id"] == "111")

    print()
    if failures:
        print(f"{len(failures)} teszt bukott: {failures}")
        return 1
    print("minden teszt zold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
