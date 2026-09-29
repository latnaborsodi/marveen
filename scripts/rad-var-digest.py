#!/usr/bin/env python3
"""Build the "rád vár" digest: every open item that waits on Donat, one line each.

Single registry rule (Donat, 2026-09-09, tightened the same evening): the registry
is GitHub. An item counts only if it has a labelled issue. The kanban is xBoss's own
work tool and is NOT read here, even when a card exists for the same item; if the two
disagree, the issue wins. Anything that was only said on Telegram is not an item.

TWO BLOCKS (Donat, 2026-09-10). The single-label version had a hole: at issue #86 the
DECISION was answered, so the `donat-dontes` label came off, but part of the EXECUTION
stayed with Donat (paste a script, click through a browser consent). That step would
have dropped out of the list entirely, which is the exact failure the digest exists to
prevent. So the digest now lists both:

  donat-dontes  DÖNTÉS VÁR RÁD  -- a decision only Donat can make
  donat-munka   MUNKA VÁR RÁD   -- a step only Donat can perform: browser consent,
                                   typing a password, clicking in the Google or NAV
                                   interface, approving a PR

An issue carrying both labels appears only under the decision block: until the decision
is made, the work cannot start, and listing it twice would just add noise.

Work items must name the NEXT CONCRETE STEP, not just the topic. The body carries it as
"[KOVETKEZO: ...]". If it is missing, the line says so out loud rather than hiding it,
because a work item without a next step is not actionable.

Output is plain text for the Telegram reply tool. No em dash, no double hyphen:
the outgoing copy gate rejects both.
"""
import json
import re
import subprocess
import sys
from datetime import date, datetime

BLOCKS = [
    ("donat-dontes", "DÖNTÉS VÁR RÁD"),
    ("donat-munka", "MUNKA VÁR RÁD"),
]
REPOS = ["latnaborsodi/tebez"]
STALE_DAYS = 3

# The issue body carries an explicit "[VAR-OTA: YYYY-MM-DD]" marker because an issue
# is often opened long after the item actually started waiting on Donat. Without it the
# age would reset to the day the issue was filed, and stale items would lose their mark.
MARKER = re.compile(r"\[VAR-OTA:\s*(\d{4}-\d{2}-\d{2})\s*\]")
NEXT_STEP = re.compile(r"\[KOVETKEZO:\s*(.+?)\s*\]", re.S)


def age_days(d: date) -> int:
    return (date.today() - d).days


def since_label(d: date) -> str:
    n = age_days(d)
    if n <= 0:
        return "ma óta"
    if n == 1:
        return "1 napja"
    return "%d napja" % n


def fetch(repo: str, label: str):
    """Return (rows, error). A dead gh must not kill the digest: the caller reports it."""
    try:
        raw = subprocess.run(
            ["gh", "issue", "list", "-R", repo, "--label", label,
             "--state", "open", "--json", "number,title,createdAt,url,body"],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout
        return json.loads(raw or "[]"), None
    except Exception as exc:  # noqa: BLE001
        return [], "%s / %s: %s" % (repo, label, exc)


def collect(label: str):
    items, errors = [], []
    for repo in REPOS:
        rows, err = fetch(repo, label)
        if err:
            errors.append(err)
            continue
        for it in rows:
            body = it.get("body") or ""
            m = MARKER.search(body)
            started = (
                datetime.strptime(m.group(1), "%Y-%m-%d").date()
                if m
                else datetime.fromisoformat(it["createdAt"].replace("Z", "+00:00")).date()
            )
            step = NEXT_STEP.search(body)
            items.append({
                "url": it["url"],
                "title": it["title"],
                "started": started,
                "next": " ".join(step.group(1).split()) if step else None,
            })
    items.sort(key=lambda r: r["started"])
    return items, errors


def render_block(heading: str, items, with_next: bool):
    lines = [heading, ""]
    if not items:
        lines.append("Nincs nyitott tétel.")
        return lines
    for it in items:
        mark = "(!) " if age_days(it["started"]) >= STALE_DAYS else ""
        lines.append("%s%s | %s | %s" % (mark, it["title"], since_label(it["started"]), it["url"]))
        if with_next:
            lines.append("    következő lépés: %s"
                         % (it["next"] or "NINCS MEGADVA, pótolni kell az issue-ban"))
    return lines


def main() -> int:
    when = "reggeli" if datetime.now().hour < 12 else "délutáni"
    out = ["RÁD VÁR (%s, %s)" % (when, date.today().isoformat()), ""]
    errors = []
    seen = set()

    for i, (label, heading) in enumerate(BLOCKS):
        items, errs = collect(label)
        errors.extend(errs)
        # An issue carrying both labels belongs to the decision block only.
        items = [it for it in items if it["url"] not in seen]
        for it in items:
            seen.add(it["url"])
        if i:
            out.append("")
        out.extend(render_block(heading, items, with_next=(label == "donat-munka")))

    if errors:
        out.append("")
        out.append("FIGYELEM, a lista hiányos lehet: " + "; ".join(errors))

    out.append("")
    out.append("(!) = három napnál régebb óta áll")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
