#!/usr/bin/env python3
"""Копирует политику и соглашение из docs/legal в приложение (assets/legal)
и в публичную страницу (legal-site/), убирая служебный комментарий для команды.
Запуск из корня репозитория: python3 scripts/sync-legal.py
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = {"privacy": ROOT / "docs/legal/privacy-policy.md", "terms": ROOT / "docs/legal/terms-of-use.md"}
TITLES = {"privacy": "Политика обработки персональных данных — Аватар",
          "terms": "Пользовательское соглашение — Аватар"}


def public_text(path: pathlib.Path) -> str:
    return re.sub(r"<!--.*?-->\s*", "", path.read_text(encoding="utf-8"), flags=re.S).strip() + "\n"


def inline(t: str) -> str:
    t = html.escape(t, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    return re.sub(r"(https://[^\s<)]+)", r'<a href="\1">\1</a>', t)


def to_html(md: str, title: str, other: str) -> str:
    out, para, lines, i = [], [], md.split("\n"), 0

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()

    while i < len(lines):
        line = lines[i]
        if line.startswith("# "):
            flush(); out.append("<h1>" + inline(line[2:]) + "</h1>")
        elif line.startswith("## "):
            flush(); out.append("<h2>" + inline(line[3:]) + "</h2>")
        elif line.startswith("|"):
            flush(); rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip("|").split("|")]); i += 1
            t = '<div class="tbl"><table><thead><tr>' + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr></thead><tbody>"
            for r in rows[2:]:
                t += "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>"
            out.append(t + "</tbody></table></div>"); continue
        elif line.startswith("- "):
            flush(); items = []
            while i < len(lines) and (lines[i].startswith("- ") or lines[i].startswith("  ")):
                if lines[i].startswith("- "): items.append(lines[i][2:])
                else: items[-1] += " " + lines[i].strip()
                i += 1
            out.append("<ul>" + "".join(f"<li>{inline(x)}</li>" for x in items) + "</ul>"); continue
        elif not line.strip():
            flush()
        else:
            para.append(line.strip())
        i += 1
    flush()
    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
:root{{--bg:#F4F6FA;--panel:#fff;--ink:#101828;--line:#DDE3EC;--link:#1D5BA6}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0b1320;--panel:#121c2c;--ink:#e8eef7;--line:#22314a;--link:#6ea4ea}}}}
body{{font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:var(--ink);line-height:1.6;margin:0}}
.wrap{{max-width:780px;margin:0 auto;padding:32px 16px 48px;background:var(--panel);min-height:100vh;box-sizing:border-box}}
h1{{font-size:26px;line-height:1.25}} h2{{font-size:19px;margin-top:28px}} p,li,td,th{{font-size:15px}}
a{{color:var(--link)}} nav{{font-size:14px;margin-bottom:16px}}
.tbl{{overflow-x:auto;margin:12px 0}} table{{border-collapse:collapse;width:100%;min-width:480px}}
th,td{{border:1px solid var(--line);padding:8px 10px;text-align:left;vertical-align:top}}
</style>
</head>
<body>
<div class="wrap">
<!-- Сгенерировано scripts/sync-legal.py из docs/legal — правьте markdown. -->
<nav>{other}</nav>
{chr(10).join(out)}
</div>
</body>
</html>
"""


if __name__ == "__main__":
    site = ROOT / "legal-site"
    site.mkdir(exist_ok=True)
    nav = {"privacy": '<a href="terms.html">Пользовательское соглашение</a>',
           "terms": '<a href="privacy.html">Политика обработки персональных данных</a>'}
    for name, path in DOCS.items():
        text = public_text(path)
        (ROOT / f"avatar-front/assets/legal/{name}.md").write_text(text, encoding="utf-8")
        (site / f"{name}.html").write_text(to_html(text, TITLES[name], nav[name]), encoding="utf-8")
    (site / "index.html").write_text(
        '<!DOCTYPE html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=privacy.html">'
        '<title>Аватар</title><a href="privacy.html">Политика</a> · <a href="terms.html">Соглашение</a>\n',
        encoding="utf-8")
    print("synced: assets/legal/*.md, legal-site/*.html")
