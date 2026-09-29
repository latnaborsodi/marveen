#!/usr/bin/env python3
"""Marveen puska: SKILL.md -> HTML Donat asztalara, frissen tartva.

Miert letezik: a puska forrasa a Claude skill-gyorsitotaraban levo SKILL.md,
ami valtozik. A Desktopon levo HTML kezzel keszult (2026-09-08), es kezzel
elavul. Ez a szkript ujragenerálja, ha a forras frissebb.

Tervezesi kikotesek:
  - A plugin-azonositok VALTOZNAK, ezert nincs fix utvonal: a legfrissebb
    egyezo SKILL.md-t keressuk meg.
  - A megjelenes NEM a szkriptbe van drotozva, hanem a repo templates/
    konyvtaraban (marveen-puska.css + marveen-puska.html.tpl), hogy
    verziokovetve legyen es a kinezet ne romoljon el.
  - Ha a forras nem talalhato, NEM irunk felul semmit es NEM hibazunk
    zajosan: naplozunk es 0-val lepunk ki.
  - Kulso fuggoseg nincs. A gepen nincs pandoc es nincs python-markdown
    (merve 2026-09-09), es a flotta tanulsaga szerint arra kell tervezni,
    hogy egy eszkoz NINCS telepitve. A renderelo ezert a stdlib-re epul, es
    pontosan azokat a markdown-elemeket kezeli, amiket ez a dokumentum
    hasznal: cim, lista, szamozott lista, tablazat, kodblokk, sorkozi kod,
    felkover, vizszintes vonal.

Kimenet: exit 0 minden vart agon (generalt / nem kellett / forras hianyzik),
exit 1 csak valodi hibanal (sablon hianyzik, iras nem sikerult).
"""
import html
import os
import re
import sys
import time
from datetime import datetime

SEARCH_ROOT = "/mnt/c/Users/user/AppData/Roaming/Claude/local-agent-mode-sessions/skills-plugin"
SKILL_SUFFIX = os.path.join("marveen-uzemeltetes", "SKILL.md")
TARGET = "/mnt/c/Users/user/Desktop/marveen-puska.html"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL_HTML = os.path.join(REPO, "templates", "marveen-puska.html.tpl")
TPL_CSS = os.path.join(REPO, "templates", "marveen-puska.css")
LOG = os.path.join(REPO, "store", "marveen-puska.log")

# Ha a renderelt torzs ennel kevesebb szekciot ad, valami elromlott a
# forrasban vagy a parserben -- ilyenkor NEM irjuk felul a meglevo lapot.
# Egy kapu, ami sosem fog, nem kapu: ezt a kuszobot a 2026-09-09-i forras
# 16 szekciojahoz merten valasztottuk.
MIN_SECTIONS = 5


def log(msg: str) -> None:
    line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}"
    print(line)
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def find_source() -> str | None:
    """A legfrissebb egyezo SKILL.md. A plugin-azonositok valtoznak, ezert
    keresunk, nem fix utat hasznalunk."""
    best, best_mtime = None, -1.0
    if not os.path.isdir(SEARCH_ROOT):
        return None
    for dirpath, _dirnames, filenames in os.walk(SEARCH_ROOT):
        if "SKILL.md" not in filenames:
            continue
        p = os.path.join(dirpath, "SKILL.md")
        if not p.endswith(os.sep + SKILL_SUFFIX):
            continue
        try:
            m = os.path.getmtime(p)
        except OSError:
            continue
        if m > best_mtime:
            best, best_mtime = p, m
    return best


# ---------------------------------------------------------------- markdown

def slug(text: str) -> str:
    t = text.lower()
    for a, b in (("á", "a"), ("é", "e"), ("í", "i"), ("ó", "o"), ("ö", "o"),
                 ("ő", "o"), ("ú", "u"), ("ü", "u"), ("ű", "u")):
        t = t.replace(a, b)
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")
    return "s-" + (t[:40] or "szakasz")


def inline(text: str) -> str:
    """Sorkozi formazas. A kodot ELOSZOR emeljuk ki es helyorzore csereljuk,
    kulonben a kodban levo csillag felkovernek latszana."""
    codes: list[str] = []

    def stash(m: re.Match[str]) -> str:
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<i>\1</i>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return re.sub(r"\x00(\d+)\x00",
                  lambda m: "<code>" + html.escape(codes[int(m.group(1))], quote=False) + "</code>",
                  text)


_STRUCT = re.compile(r"^(\s*)(#{1,4}\s|[-*]\s|\d+\.\s|\||```|>|(-{3,}|\*{3,}|_{3,})\s*$)")


def join_wrapped(lines: list[str]) -> list[str]:
    """A forras tordelt sorokat hasznal: egy lista-elem vagy bekezdes tobb
    soron at fut. Ezeket ossze KELL fuzni a feldolgozas elott, kulonben ket
    baj tortenik: a folytatas kulon bekezdesbe esik, es a sorhataron atnyulo
    **felkover** jeloles nyersen latszik, mert a nyito es a zaro csillagpar
    ket kulon sorba kerul. (2026-09-09, Donat jelezte, 14 nyers ** a lapon.)

    Kodblokkon belul NEM fuzunk: ott a sortores jelentes."""
    out: list[str] = []
    in_fence = False
    for line in lines:
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence or not line.strip() or _STRUCT.match(line) or not out or not out[-1].strip():
            out.append(line)
            continue
        if _STRUCT.match(out[-1]) or out[-1].strip():
            out[-1] = out[-1].rstrip() + " " + line.strip()
            continue
        out.append(line)
    return out


def render(md: str) -> tuple[str, str]:
    """(cim, torzs-HTML). A torzs <section> elemekbol all, h2-nkent egy."""
    md = re.sub(r"\A---\n.*?\n---\n", "", md, flags=re.S)  # YAML frontmatter
    lines = join_wrapped(md.split("\n"))
    title = "Marveen / xBoss üzemeltetési puska"
    out: list[str] = []
    open_section = False
    list_stack: list[str] = []   # 'ul' / 'ol'
    i = 0

    def close_lists() -> None:
        while list_stack:
            out.append(f"</{list_stack.pop()}>")

    def close_section() -> None:
        nonlocal open_section
        close_lists()
        if open_section:
            out.append("</section>")
            open_section = False

    while i < len(lines):
        raw = lines[i]
        line = raw.rstrip()

        # kodblokk
        if line.startswith("```"):
            close_lists()
            lang = line[3:].strip()
            buf: list[str] = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            cls = f' class="lang-{html.escape(lang)}"' if lang else ""
            out.append(f"<pre><code{cls}>" + html.escape("\n".join(buf), quote=False) + "</code></pre>")
            continue

        # tablazat: fejlec + elvalaszto + sorok
        if line.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:\-|]+\|?\s*$", lines[i + 1]):
            close_lists()
            def cells(s: str) -> list[str]:
                return [c.strip() for c in s.strip().strip("|").split("|")]
            head = cells(line)
            i += 2
            rows: list[list[str]] = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(cells(lines[i]))
                i += 1
            out.append("<table><thead><tr>" + "".join(f"<th>{inline(h)}</th>" for h in head) + "</tr></thead><tbody>")
            for r in rows:
                r = (r + [""] * len(head))[:len(head)]
                out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
            out.append("</tbody></table>")
            continue

        # cimek
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            level, text = len(m.group(1)), m.group(2).strip()
            if level == 1:
                title = re.sub(r"<[^>]+>", "", inline(text)) or title
                i += 1
                continue
            if level == 2:
                close_section()
                out.append(f'<section id="{slug(text)}">')
                open_section = True
                out.append(f"<h2>{inline(text)}</h2>")
            else:
                close_lists()
                out.append(f"<h{level}>{inline(text)}</h{level}>")
            i += 1
            continue

        # vizszintes vonal: szakaszhatarkent mar a h2 kezeli, itt eldobjuk
        if re.match(r"^(-{3,}|\*{3,}|_{3,})$", line):
            i += 1
            continue

        # listak (egy szint beljebb huzas is)
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", line)
        if m:
            indent, marker, text = len(m.group(1)), m.group(2), m.group(3)
            kind = "ol" if marker.endswith(".") else "ul"
            depth = 1 + (indent >= 2)
            while len(list_stack) > depth:
                out.append(f"</{list_stack.pop()}>")
            if len(list_stack) < depth:
                out.append(f"<{kind}>")
                list_stack.append(kind)
            elif list_stack and list_stack[-1] != kind:
                out.append(f"</{list_stack.pop()}>")
                out.append(f"<{kind}>")
                list_stack.append(kind)
            out.append(f"<li>{inline(text)}</li>")
            i += 1
            continue

        if not line.strip():
            close_lists()
            i += 1
            continue

        close_lists()
        out.append(f"<p>{inline(line.strip())}</p>")
        i += 1

    close_section()
    return title, "\n".join(out)


# ------------------------------------------------------------------- main

def main() -> int:
    force = "--force" in sys.argv
    src = find_source()
    if not src:
        log("forras nem talalhato (skills-plugin gyorsitotar) -- nem irok felul semmit")
        return 0

    src_mtime = os.path.getmtime(src)
    tgt_mtime = os.path.getmtime(TARGET) if os.path.exists(TARGET) else -1.0
    if not force and tgt_mtime >= src_mtime:
        log(f"nem kell generalni: a cel ({datetime.fromtimestamp(tgt_mtime):%m-%d %H:%M:%S}) "
            f"nem regebbi a forrasnal ({datetime.fromtimestamp(src_mtime):%m-%d %H:%M:%S})")
        return 0

    try:
        tpl = open(TPL_HTML, encoding="utf-8").read()
        css = open(TPL_CSS, encoding="utf-8").read()
    except OSError as e:
        log(f"HIBA: sablon nem olvashato ({e})")
        return 1

    title, body = render(open(src, encoding="utf-8").read())
    n_sections = body.count("<section ")
    if n_sections < MIN_SECTIONS:
        log(f"HIBA: a renderelt torzs csak {n_sections} szekciot tartalmaz (minimum {MIN_SECTIONS}) "
            f"-- gyanus, NEM irom felul a meglevo lapot")
        return 1

    page = (tpl
            .replace("{{CSS}}", css)
            .replace("{{TITLE}}", html.escape(title, quote=False))
            .replace("{{SUBTITLE}}", "Donát flottája és a tebez-prod szerver")
            .replace("{{SOURCE_PATH}}", html.escape(src, quote=False))
            .replace("{{SOURCE_MTIME}}", f"{datetime.fromtimestamp(src_mtime):%Y-%m-%d %H:%M:%S}")
            .replace("{{GENERATED}}", f"{datetime.now():%Y-%m-%d %H:%M:%S}")
            .replace("{{BODY}}", body))

    tmp = TARGET + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(page)
        os.replace(tmp, TARGET)
        # A cel mtime-ja legyen a MOSTANI ido, hogy a kovetkezo futas
        # frissebbnek lassa a forrasnal -- kulonben orokke ujragenerálna.
        os.utime(TARGET, (time.time(), time.time()))
    except OSError as e:
        log(f"HIBA: iras nem sikerult ({e})")
        try:
            os.remove(tmp)
        except OSError:
            pass
        return 1

    log(f"generalva: {n_sections} szekcio, {len(page)} byte, forras mtime "
        f"{datetime.fromtimestamp(src_mtime):%Y-%m-%d %H:%M:%S}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
