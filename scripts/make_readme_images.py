#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Smart Fishing (docs/images/ui_*.png, settings_*.png).

The session HUD with its sound panel, the fishing log window, the World Map legend and pins,
a fish tooltip and the settings window are rebuilt from the sizes, coordinates, colours and
strings in the addon code (UI/HUD.lua, Modules/SoundBoost.lua, UI/JournalWindow.lua,
Core/Widgets.lua, UI/MapLegend.lua, UI/MapPins.lua, Modules/TooltipHook.lua,
UI/OptionsWindow.lua, Core/Style.lua, Core/Locales.lua), in game pixels x scale.
Fish and chances are the bundled Westfall data; icons are simplified drawings.

usage: python scripts/make_readme_images.py .
Renders with a local headless Chrome (set CHROME=<path> if it is not found).
"""
import base64
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PAGE_W = 1600

# ---------------------------------------------------------------------------
# Small readers for the Lua code
# ---------------------------------------------------------------------------


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def find_file(root, *names):
    """First existing file of names (case-insensitive on every system)."""
    for name in names:
        p = root / name
        if p.exists():
            return p
        parent = p.parent
        if parent.exists():
            for q in parent.iterdir():
                if q.name.lower() == p.name.lower():
                    return q
    raise FileNotFoundError(names)


def rgb_list(body):
    return [float(v) for v in body.split(",") if v.strip()]


def lua_table(src, start_pattern):
    """Text of the Lua table that starts at start_pattern (balanced braces)."""
    m = re.search(start_pattern, src)
    if not m:
        raise ValueError(start_pattern)
    i = src.index("{", m.start())
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[i + 1:j]
    raise ValueError("unbalanced " + start_pattern)


def lua_strings(block):
    """key = "value" pairs of a Lua table body (plain keys and ["keys"])."""
    out = {}
    for k1, k2, v in re.findall(r'(?:^|[\s,{])(?:(\w+)|\["((?:[^"\\]|\\.)*)"\])\s*=\s*"((?:[^"\\]|\\.)*)"', block, re.M):
        out[k1 or k2] = unlua(v)
    return out


def unlua(v):
    return v.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def toc_version(root):
    for p in root.glob("*.toc"):
        m = re.search(r"^## Version:\s*(\S+)", p.read_text(encoding="utf-8"), re.M)
        if m:
            return m.group(1)
    return ""


def css(c, alpha=None, mul=1.0):
    r, g, b = (round(min(1, v * mul) * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


def hexc(c):
    return "#%02x%02x%02x" % tuple(round(v * 255) for v in c[:3])


def esc(s):
    return html.escape(str(s), quote=False)


def wow(s):
    """Game text -> HTML: |cffRRGGBB..|r colours, |n / \\n line breaks, icons dropped."""
    s = esc(s)
    s = re.sub(r"\|T[^|]*\|t", "", s)
    s = re.sub(r"\|A[^|]*\|a", "", s)
    out, depth = [], 0
    pos = 0
    for m in re.finditer(r"\|c[0-9a-fA-F]{2}([0-9a-fA-F]{6})|\|r", s):
        out.append(s[pos:m.start()])
        if m.group(0) == "|r":
            if depth:
                out.append("</span>")
                depth -= 1
        else:
            out.append(f'<span style="color:#{m.group(1)}">')
            depth += 1
        pos = m.end()
    out.append(s[pos:])
    out.append("</span>" * depth)
    return "".join(out).replace("|n", "<br>").replace("\n", "<br>")


# ---------------------------------------------------------------------------
# Page parts (game px x S -> page px)
# ---------------------------------------------------------------------------
S = 1.3


def px(v):
    return f"{v * S:.2f}px"


OUTLINE = "text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000,0 0 2px #000;"
SHADOW = "text-shadow:1px 1px 0 #000,0 0 2px rgba(0,0,0,.8);"

# client colours used by several mock-ups
QUALITY = {0: "#9d9d9d", 1: "#ffffff", 2: "#1eff00", 3: "#0070dd", 4: "#a335ee", 5: "#ff8000"}
CLASS_HEX = {"WARRIOR": "#c69b6d", "PALADIN": "#f48cba", "HUNTER": "#aad372", "ROGUE": "#fff468", "PRIEST": "#ffffff",
             "SHAMAN": "#0070dd", "MAGE": "#3fc7eb", "WARLOCK": "#8788ee", "DRUID": "#ff7c0a"}
GOLD = "#ffd100"

THEME = {
    "bg": (0.071, 0.094, 0.122, 0.97), "bgSub": (0.114, 0.157, 0.192, 0.96), "border": (0.204, 0.298, 0.357, 1),
    "text": (0.929, 0.957, 0.969, 1), "muted": (0.655, 0.725, 0.773, 1), "accent": (0.5, 0.8, 0.9, 1),
}


def page_css(call):
    return f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
html, body {{ width: {PAGE_W}px; overflow: hidden; }}
body {{ background: #0e141a; font-family: 'Noto Sans KR','Malgun Gothic',sans-serif; color: #edf4f7; position: relative; }}
.sky {{ position: absolute; left: 0; top: 0; width: {PAGE_W}px; height: 100%;
  background: radial-gradient(ellipse at 25% 0%, #1d2b38 0%, #151f28 45%, #10171d 75%, #0c1115 100%); }}
.hills {{ position: absolute; left: 0; bottom: 0; width: {PAGE_W}px; height: 260px; }}
.page {{ position: relative; padding: 34px 50px 0; }}
h1 {{ color: {call}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {call}; color: #10161c; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #d5dde2; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.t {{ position: absolute; white-space: nowrap; line-height: 1.15; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {call}; color: #10161c; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #10161c; box-shadow: 0 0 0 2px {call}55; z-index: 60; }}
.notes {{ position: absolute; }}
.note {{ display: flex; gap: 12px; margin-bottom: 11px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {call}; color: #10161c; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; }}
.note b {{ color: #fff; }}
.foot {{ position: absolute; color: #7d8d98; font-size: 13.5px; line-height: 1.5; }}
.fit {{ display: inline-block; white-space: nowrap; }}
.tip {{ position: absolute; z-index: 30; }}
.tip .row {{ display: flex; justify-content: space-between; gap: 18px; white-space: nowrap; }}
"""


HILLS = ('<svg class="hills" viewBox="0 0 1600 260" preserveAspectRatio="none">'
         '<path d="M0 150 C 220 70 420 90 640 140 C 860 190 1060 60 1300 80 C 1440 92 1540 120 1600 130 V260 H0 Z" fill="#141c23" opacity=".9"/>'
         '<path d="M0 210 C 260 160 520 170 800 205 C 1080 240 1340 170 1600 190 V260 H0 Z" fill="#0b1014"/></svg>')

FIT_JS = """
<script>
document.querySelectorAll('[data-fit]').forEach(function (e) {
  var max = parseFloat(e.dataset.fit), min = parseFloat(e.dataset.min || 8);
  var fs = parseFloat(getComputedStyle(e).fontSize);
  while (e.scrollWidth > max && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
  if (e.scrollWidth > max) { e.style.maxWidth = max + 'px'; e.style.overflow = 'hidden'; e.style.textOverflow = 'ellipsis'; }
});
// place the footnote under the lowest element, then record the page height
var bottom = 0;
document.querySelectorAll('.page *, body > .abs, body > .notes, body > .call, body > .tip').forEach(function (e) {
  var r = e.getBoundingClientRect(); if (r.height > 0 && r.bottom > bottom) bottom = r.bottom;
});
var foot = document.querySelector('.foot');
if (foot) { foot.style.top = (bottom + 26) + 'px'; bottom = foot.getBoundingClientRect().bottom; }
document.body.setAttribute('data-h', Math.ceil(bottom + 34));
document.body.style.height = Math.ceil(bottom + 34) + 'px';
</script>
"""


def box(x, y, w, h, style="", inner=""):
    return f'<div class="abs" style="left:{px(x)};top:{px(y)};width:{px(w)};height:{px(h)};{style}">{inner}</div>'


def text(x, y, s, size, color="#fff", anchor="left", style="", fit=None, shadow=SHADOW):
    """Font string; y is the vertical centre (game px)."""
    tr = {"left": "translate(0,-50%)", "right": "translate(-100%,-50%)", "center": "translate(-50%,-50%)"}[anchor]
    inner = s if fit is None else f'<span class="fit" data-fit="{fit * S:.1f}" data-min="{size * 0.7 * S:.1f}">{s}</span>'
    return (f'<div class="t" style="left:{px(x)};top:{px(y)};font-size:{px(size)};color:{color};'
            f'transform:{tr};{shadow}{style}">{inner}</div>')


def text_top(x, y, s, size, color="#fff", width=None, style="", shadow=SHADOW):
    """Font string anchored at its top-left (TOPLEFT points)."""
    w = f"width:{px(width)};white-space:normal;" if width else ""
    return (f'<div class="t" style="left:{px(x)};top:{px(y)};font-size:{px(size)};color:{color};line-height:1.3;'
            f'{w}{shadow}{style}">{s}</div>')


class Window:
    """A flat EzWoW style window: header strip, accent line, icon, title, sub title, close box."""

    def __init__(self, th, w, h, title, sub="", icon=None, header=56, close=22, close_off=10, title_color=None):
        self.th, self.w, self.h = th, w, h
        self.p = []
        acc = css(th["accent"], 1)
        if header:
            self.p.append(box(1, 1, w - 2, header, f"background:{css(th['bgSub'], .98)}"))
            self.p.append(box(1, header - 1, w - 2, 2, f"background:{acc}"))
            if icon:
                self.p.append(f'<img class="abs" src="{icon}" style="left:{px(14)};top:{px(14)};width:{px(28)};height:{px(28)}">')
            self.p.append(text_top(48, 10, esc(title), 16, title_color or acc))
            if sub:
                self.p.append(text_top(48, 32, sub, 10, css(th["muted"]), width=w - 120))
            if close:
                self.button(w - 1 - close_off - close, close_off + 1, close, close, "X", size=12)

    def add(self, s):
        self.p.append(s)

    def section(self, x, y, label, width=None, line_dy=18):
        acc = css(self.th["accent"], 1)
        self.p.append(text_top(x, y, label, 13, acc))
        w = width if width else self.w - x - 20
        self.p.append(box(x, y + line_dy, w, 1, f"background:{css(self.th['border'], .85)}"))

    def check(self, x, y, label, on, size=24, label_w=180, font=12, disabled=False, color=None):
        mark = (f'<div class="t" style="left:{px(size * 0.1)};top:{px(-size * 0.12)};font-size:{px(size * 0.9)};color:#ffd200;'
                f'text-shadow:0 0 1px #000,1px 1px 0 #6b4a00">&#10004;</div>') if on else ""
        b = size * 0.72
        o = (size - b) / 2
        alpha = ";opacity:.55" if disabled else ""
        self.p.append(box(x + o, y + o, b, b, f"border:1px solid #6d6a5d;background:#191919;border-radius:2px;overflow:visible{alpha}", mark))
        col = color or css(self.th["muted"] if disabled else self.th["text"])
        self.p.append(text(x + size + 4, y + size / 2, label, font, col, fit=label_w))

    def radio(self, x, y, label, on, size=22, label_w=150, font=12):
        dot = box(size * .32, size * .32, size * .36, size * .36, "border-radius:50%;background:#ffd200;box-shadow:0 0 3px #ffb000") if on else ""
        self.p.append(box(x + 2, y + 2, size - 4, size - 4, "border:1px solid #7a7a7a;border-radius:50%;background:#151515", dot))
        self.p.append(text(x + size + 4, y + size / 2, label, font, css(self.th["text"]), fit=label_w))

    def button(self, x, y, w, h, label, accent=False, size=12, color=None, bg=None, border=None):
        th = self.th
        bgc = bg or css(th["bgSub"])
        bd = border or (css(th["accent"]) if accent else css(th["border"]))
        col = color or (css(th["accent"]) if accent else css(th["text"]))
        self.p.append(box(x, y, w, h, f"background:{bgc};border:1px solid {bd};display:flex;align-items:center;justify-content:center",
                          f'<span class="fit" data-fit="{(w - 10) * S:.1f}" data-min="{size * .7 * S:.1f}" '
                          f'style="font-size:{px(size)};color:{col};{SHADOW}">{label}</span>'))

    def stepper(self, x, y, label, value, minus_dx, plus_dx, bw=25, bh=25, label_dy=6, label_w=84, value_color=None, font=12):
        self.p.append(text_top(x, y + label_dy, f'<span class="fit" data-fit="{label_w * S:.1f}" data-min="{9 * S:.1f}">{label}</span>',
                               font, css(self.th["text"])))
        self.button(x + minus_dx, y, bw, bh, "-", size=14)
        self.button(x + plus_dx, y, bw, bh, "+", size=14)
        cx = x + minus_dx + bw / 2 + (plus_dx - minus_dx) / 2
        self.p.append(text(cx, y + bh / 2, value, font, value_color or css(self.th["text"]), anchor="center"))

    def html(self, ox, oy, extra_style=""):
        th = self.th
        return (f'<div class="abs" style="left:{ox}px;top:{oy}px;width:{px(self.w)};height:{px(self.h)};background:{css(th["bg"])};'
                f'border:1px solid {css(th["border"])};box-shadow:0 10px 40px rgba(0,0,0,.45);{extra_style}">' + "".join(self.p) + "</div>")


def tooltip(x, y, lines, border="#344c5b", width=None, pad=10, bg="rgba(18,24,31,.95)", gloss=True, bar=None, font=12,
            title_size=14, left_pad=0, z=30, extra=""):
    """A tooltip card at page px (x, y). lines: list of str | (left, right) | ("gap",); first line is the title.
    Strings are already HTML. bar: (fraction, colour, label) drawn along the bottom."""
    rows = []
    for i, ln in enumerate(lines):
        fs = title_size if i == 0 else font
        if ln == ("gap",):
            rows.append(f'<div style="height:{px(font * .7)}"></div>')
        elif isinstance(ln, tuple):
            rows.append(f'<div class="row" style="font-size:{px(fs)};line-height:1.42"><span>{ln[0]}</span><span>{ln[1]}</span></div>')
        else:
            rows.append(f'<div style="font-size:{px(fs)};line-height:1.42;white-space:nowrap">{ln}</div>')
    w = f"width:{px(width)};" if width else ""
    glo = (f'<div class="abs" style="left:0;right:0;top:0;height:{px(26)};background:linear-gradient(to bottom,rgba(255,255,255,.07),'
           f'rgba(255,255,255,0))"></div>') if gloss else ""
    bar_h = ""
    bottom_pad = pad
    if bar:
        frac, col, label = bar
        bottom_pad = pad + 10
        bar_h = (f'<div class="abs" style="left:{px(1)};right:{px(1)};bottom:{px(1)};height:{px(8)};background:rgba(0,0,0,.6)">'
                 f'<div class="abs" style="left:0;top:0;bottom:0;width:{frac * 100:.1f}%;background:{col}"></div>'
                 f'<div class="abs" style="inset:0;display:flex;align-items:center;justify-content:center;font-size:{px(7.5)};color:#fff;{OUTLINE}">{label}</div></div>')
    return (f'<div class="tip" style="left:{x:.0f}px;top:{y:.0f}px;{w}background:{bg};border:1px solid {border};'
            f'padding:{px(pad)} {px(pad)} {px(bottom_pad)} {px(pad + left_pad)};{SHADOW}z-index:{z};{extra}">'
            f'{glo}{"".join(rows)}{bar_h}</div>')


def callouts(points):
    return "".join(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>' for i, (x, y) in enumerate(points, 1))


def notes_html(notes, start=1):
    return "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{esc(a)}</b> — {b}</div></div>'
                   for i, (a, b) in enumerate(notes))


def notes_block(x, y, w, notes, start=1):
    return f'<div class="notes" style="left:{x:.0f}px;top:{y:.0f}px;width:{w:.0f}px">{notes_html(notes, start)}</div>'


def heading(title, lead, badge=None):
    b = f' <span class="badge">{esc(badge)}</span>' if badge else ""
    return f'<div class="page"><h1>{esc(title)}{b}</h1><div class="lead">{lead}</div></div>'


def icon_data(path):
    return "data:image/png;base64," + base64.b64encode(Path(path).read_bytes()).decode()


# simple square icon art (stands in for game icons)
ICON_ART = {
    "potion": ("#3a1418", '<path d="M40 14 H60 V34 C76 40 82 54 82 64 A32 26 0 0 1 18 64 C18 54 24 40 40 34 Z" fill="#d8323c"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "mana": ("#121e3e", '<path d="M40 14 H60 V34 C76 40 82 54 82 64 A32 26 0 0 1 18 64 C18 54 24 40 40 34 Z" fill="#3d7cf0"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "elixir": ("#14301e", '<path d="M44 12 H56 V40 L74 80 H26 L44 40 Z" fill="#5fd05a"/><rect x="40" y="8" width="20" height="8" fill="#b08860"/>'),
    "stone": ("#1c2a1c", '<path d="M50 12 L80 40 L62 86 H38 L20 40 Z" fill="#62e07a"/><path d="M50 12 L62 40 L50 86 L38 40 Z" fill="#a8f5b4"/>'),
    "helm": ("#2a2a30", '<path d="M18 64 C18 30 34 16 50 16 C66 16 82 30 82 64 L72 80 H28 Z" fill="#a8adb8"/><rect x="30" y="50" width="40" height="10" fill="#2a2a30"/>'),
    "glove": ("#2a2420", '<path d="M30 86 V44 L26 22 H36 L40 40 V16 H48 V40 V12 H56 V40 V16 H64 V44 L74 34 L80 40 L66 62 V86 Z" fill="#b58a5a"/>'),
    "ring": ("#2a2418", '<circle cx="50" cy="56" r="24" fill="none" stroke="#e8c050" stroke-width="10"/><path d="M42 26 L50 14 L58 26 L50 34 Z" fill="#6ad0ff"/>'),
    "sword": ("#202830", '<path d="M70 14 L84 16 L86 30 L44 72 L30 58 Z" fill="#cfd8e0"/><path d="M26 54 L46 74 L40 80 L20 60 Z" fill="#b08040"/><path d="M28 72 L18 82" stroke="#806030" stroke-width="8"/>'),
    "food": ("#3a2412", '<ellipse cx="50" cy="58" rx="30" ry="20" fill="#c87838"/><circle cx="64" cy="40" r="12" fill="#f0e0c0"/>'),
    "drink": ("#14283a", '<path d="M30 20 H70 L64 84 H36 Z" fill="#8fd0f0" opacity=".85"/><rect x="30" y="20" width="40" height="10" fill="#e0f4ff"/>'),
    "bandage": ("#2c2c2c", '<rect x="18" y="38" width="64" height="26" rx="12" fill="#e8e0d0" transform="rotate(-35 50 50)"/>'),
    "hearth": ("#1a2a3a", '<circle cx="50" cy="50" r="26" fill="#7fd0ff"/><circle cx="50" cy="50" r="12" fill="#e0f6ff"/>'),
    "pet": ("#2a2018", '<ellipse cx="50" cy="62" rx="26" ry="18" fill="#d8a060"/><circle cx="66" cy="38" r="14" fill="#d8a060"/><path d="M60 26 L62 14 L70 24 Z M72 28 L80 18 L80 32 Z" fill="#a06a30"/><circle cx="70" cy="38" r="3" fill="#201008"/>'),
    "pick": ("#2a2a2a", '<path d="M20 30 C40 14 64 14 82 30 L76 36 C62 26 42 26 26 36 Z" fill="#bcc4cc"/><rect x="46" y="28" width="8" height="58" fill="#8a6030"/>'),
    "herb": ("#1c3018", '<path d="M50 86 V40" stroke="#5a9040" stroke-width="6"/><ellipse cx="36" cy="44" rx="14" ry="8" fill="#70c050" transform="rotate(-30 36 44)"/><ellipse cx="64" cy="40" rx="14" ry="8" fill="#70c050" transform="rotate(30 64 40)"/><circle cx="50" cy="28" r="10" fill="#e070d0"/>'),
    "fire": ("#3a1a0a", '<path d="M50 12 C62 34 80 44 70 70 A22 22 0 0 1 30 70 C22 50 40 40 42 26 C48 36 50 30 50 12 Z" fill="#ff8a2a"/><path d="M50 46 C58 58 62 64 56 76 A10 10 0 0 1 42 74 C40 64 48 58 50 46 Z" fill="#ffe070"/>'),
    "holy": ("#3a3010", '<circle cx="50" cy="50" r="20" fill="#ffe680"/><path d="M50 10 V30 M50 70 V90 M10 50 H30 M70 50 H90 M22 22 L36 36 M64 64 L78 78 M22 78 L36 64 M64 36 L78 22" stroke="#ffe680" stroke-width="6"/>'),
    "shield": ("#1e2836", '<path d="M50 10 L84 22 C84 56 72 78 50 90 C28 78 16 56 16 22 Z" fill="#7aa4d8"/><path d="M50 22 L72 30 C72 54 64 70 50 78 Z" fill="#b8d4f4"/>'),
    "shadow": ("#1e1430", '<circle cx="50" cy="50" r="28" fill="#8a5ad8"/><circle cx="50" cy="50" r="14" fill="#2a1840"/>'),
    "frost": ("#14283a", '<path d="M50 12 V88 M17 31 L83 69 M17 69 L83 31" stroke="#bfe6ff" stroke-width="9" stroke-linecap="round"/>'),
    "nature": ("#203a1c", '<path d="M50 84 C20 70 18 36 50 14 C82 36 80 70 50 84 Z" fill="#7cd060"/><path d="M50 84 V30" stroke="#2a5a1c" stroke-width="5"/>'),
    "arcane": ("#2a1840", '<path d="M50 14 L58 42 L86 50 L58 58 L50 86 L42 58 L14 50 L42 42 Z" fill="#d79cff"/>'),
    "claw": ("#3a1414", '<path d="M25 80 L45 20 M45 82 L62 22 M65 84 L80 28" stroke="#ff6a5a" stroke-width="9" stroke-linecap="round"/>'),
    "bear": ("#2e2014", '<circle cx="50" cy="56" r="26" fill="#8a5a30"/><circle cx="30" cy="30" r="10" fill="#8a5a30"/><circle cx="70" cy="30" r="10" fill="#8a5a30"/><circle cx="42" cy="52" r="4" fill="#1a0a00"/><circle cx="58" cy="52" r="4" fill="#1a0a00"/>'),
    "cat": ("#3a2a1a", '<path d="M24 82 L24 34 L36 18 L44 34 L56 34 L64 18 L76 34 L76 82 Z" fill="#c9965a"/><circle cx="40" cy="50" r="5" fill="#2a1a0a"/><circle cx="60" cy="50" r="5" fill="#2a1a0a"/>'),
    "heal": ("#14301e", '<rect x="40" y="18" width="20" height="64" fill="#8cf08c"/><rect x="18" y="40" width="64" height="20" fill="#8cf08c"/>'),
    "book": ("#2a1e14", '<rect x="20" y="16" width="60" height="70" rx="4" fill="#8a4a2a"/><rect x="28" y="16" width="6" height="70" fill="#5a2a14"/><rect x="40" y="30" width="30" height="6" fill="#e8c890"/>'),
    "scroll": ("#2e2616", '<rect x="24" y="22" width="52" height="56" fill="#e8d8a8"/><rect x="18" y="16" width="64" height="10" rx="5" fill="#b89860"/><rect x="18" y="74" width="64" height="10" rx="5" fill="#b89860"/><path d="M34 40 H66 M34 52 H66 M34 64 H56" stroke="#8a6a3a" stroke-width="4"/>'),
    "flask": ("#2a1a3a", '<circle cx="50" cy="60" r="24" fill="#b070f0"/><rect x="42" y="14" width="16" height="26" fill="#b070f0"/><rect x="38" y="10" width="24" height="8" fill="#b08860"/>'),
    "thread": ("#1a2840", '<rect x="34" y="16" width="32" height="68" rx="6" fill="#d8b070"/><rect x="30" y="30" width="40" height="40" fill="#3a78d8"/>'),
    "hammer": ("#2a2a2a", '<rect x="22" y="18" width="56" height="22" rx="3" fill="#a0a8b0"/><rect x="45" y="40" width="10" height="46" fill="#8a6030"/>'),
    "fish": ("#10304a", '<path d="M14 50 C30 26 62 26 74 50 C62 74 30 74 14 50 Z" fill="#7fb8e0"/><path d="M74 50 L90 34 V66 Z" fill="#7fb8e0"/><circle cx="30" cy="46" r="4" fill="#0a1a2a"/>'),
    "gear": ("#26303a", '<circle cx="50" cy="50" r="22" fill="none" stroke="#c0c8d0" stroke-width="12" stroke-dasharray="9 6"/><circle cx="50" cy="50" r="10" fill="#c0c8d0"/>'),
    "bolt": ("#24204a", '<path d="M56 10 L26 56 H48 L40 90 L76 40 H54 Z" fill="#ffe14a"/>'),
    "chest": ("#2a1e10", '<rect x="18" y="38" width="64" height="42" fill="#9a6a30"/><path d="M18 38 C18 18 82 18 82 38 Z" fill="#b8843c"/><rect x="44" y="44" width="12" height="14" fill="#e8c050"/>'),
    "arrow": ("#2a2418", '<path d="M18 82 L72 28" stroke="#c8a870" stroke-width="7"/><path d="M64 20 L84 16 L80 36 Z" fill="#c0c8d0"/><path d="M18 82 L26 66 M18 82 L34 74" stroke="#e8e0d0" stroke-width="5"/>'),
    "kick": ("#2e1c14", '<path d="M30 20 L48 20 L54 56 L80 64 L78 80 L34 80 Z" fill="#c9965a"/>'),
    "stealth": ("#1a1a24", '<circle cx="50" cy="50" r="30" fill="#4a4a6a"/><path d="M26 50 C38 34 62 34 74 50 C62 66 38 66 26 50 Z" fill="#1a1a24"/><circle cx="50" cy="50" r="8" fill="#9aa0d0"/>'),
}


def icon_svg(kind):
    bg, shape = ICON_ART[kind]
    return (f'<svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none" style="display:block">'
            f'<defs><linearGradient id="sh_{kind}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".18"/>'
            f'<stop offset=".55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".35"/></linearGradient></defs>'
            f'<rect width="100" height="100" fill="{bg}"/>{shape}<rect width="100" height="100" fill="url(#sh_{kind})"/></svg>')


def icon_box(x, y, size, kind, border="#000", style=""):
    return box(x, y, size, size, f"border:1px solid {border};overflow:hidden;{style}", icon_svg(kind))


# ---------------------------------------------------------------------------
# Rendering (local headless Chrome)
# ---------------------------------------------------------------------------
def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


def chrome_args(chrome, tmp):
    return [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--user-data-dir={Path(tmp) / 'chrome_profile'}", "--virtual-time-budget=3000"]


def render(chrome, body, call, out_png, tmp):
    doc = (f'<!doctype html><html><head><meta charset="utf-8"><style>{page_css(call)}</style></head>'
           f'<body><div class="sky"></div>{HILLS}{body}{FIT_JS}</body></html>')
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(doc, encoding="utf-8")
    # pass 1: let the page measure itself, pass 2: screenshot at that height
    dom = subprocess.run(chrome_args(chrome, tmp) + ["--window-size=1600,4000", "--dump-dom", page.as_uri()],
                         check=True, capture_output=True, timeout=600).stdout.decode("utf-8", "replace")
    m = re.search(r'data-h="(\d+)"', dom)
    height = int(m.group(1)) if m else 1200
    subprocess.run(chrome_args(chrome, tmp) + [f"--window-size={PAGE_W},{height}", f"--screenshot={out_png}", page.as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    return height


def run_pages(root, pages, call):
    """pages: list of (file stem, function returning page body html)."""
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezwow_readme_")
    try:
        for stem, fn in pages:
            png = out / f"{stem}.png"
            h = render(chrome, fn(), call, png, tmp)
            print("wrote", png, h)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# EzWoW - Smart Fishing
# ---------------------------------------------------------------------------
TITLE = "EzWoW - Smart Fishing"

FISH_SHAPE = ('<path d="M14 50 C30 26 62 26 74 50 C62 74 30 74 14 50 Z" fill="{c}"/>'
              '<path d="M74 50 L90 34 V66 Z" fill="{c}"/><circle cx="30" cy="46" r="4" fill="#0a1a2a"/>'
              '<path d="M40 40 C46 46 46 54 40 60" stroke="#0a1a2a" stroke-width="3" fill="none" opacity=".5"/>')
for _k, _bg, _c in (("f6361", "#123a5a", "#6fc0f0"), ("f6358", "#1e2630", "#9aa2ae"), ("f6303", "#14324a", "#a8d8e0"),
                    ("f6289", "#3a2a14", "#d0a060"), ("f6308", "#2a3020", "#b0b070"), ("f6291", "#3a1a30", "#f0a040")):
    ICON_ART[_k] = (_bg, FISH_SHAPE.format(c=_c))
ICON_ART["f3820"] = ("#1c3018", '<path d="M50 88 C40 64 60 44 46 14" stroke="#7cc060" stroke-width="7" fill="none"/>'
                     '<path d="M52 70 C66 58 70 44 66 30" stroke="#5aa048" stroke-width="6" fill="none"/>'
                     '<path d="M46 62 C32 52 28 40 32 28" stroke="#5aa048" stroke-width="6" fill="none"/>')

# real item IDs of the Westfall data; names are the game's item names
FISH = {
    6361: ("무지개날개다랑어", "Raw Rainbow Fin Albacore"),
    6358: ("기름기 많은 아귀", "Oily Blackmouth"),
    6303: ("줄무늬고등어", "Raw Slitherskin Mackerel"),
    6289: ("긴주둥이진흙퉁돔", "Raw Longjaw Mud Snapper"),
    6308: ("표범메기", "Raw Bristle Whisker Catfish"),
    6291: ("비단잉어", "Raw Brilliant Smallfish"),
    3820: ("갈래물풀", "Stranglekelp"),
}
ZONE = {1436: ("서부 몰락지대", "Westfall"), 1437: ("저습지", "Wetlands"), 1421: ("은빛소나무 숲", "Silverpine Forest"),
        1434: ("가시덤불 골짜기", "Stranglethorn Vale"), 1439: ("어둠해안", "Darkshore")}
WESTFALL = 1436


def lua_kv(src, prefix):
    """["key"] = "value" pairs that follow prefix (table body or single assignments); keys and values unescaped."""
    out = {}
    body = lua_table(src, re.escape(prefix) + r" = \{")
    for k, v in re.findall(r'\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"', body):
        out[unlua(k)] = unlua(v)
    q = r'"((?:[^"\\]|\\.)*)"'
    p = re.escape(prefix)
    for k, v in re.findall(rf'^{p}\[{q}\]\s*=\s*{q}', src, re.M):
        out[unlua(k)] = unlua(v)
    for k1, k2, v1, v2 in re.findall(rf'^{p}\[{q}\],\s*{p}\[{q}\]\s*=\s*{q},\s*{q}', src, re.M):
        out[unlua(k1)], out[unlua(k2)] = unlua(v1), unlua(v2)
    return out


def load(root):
    loc = read(root, "Core/Locales.lua")
    style_src = read(root, "Core/Style.lua")
    ow = read(root, "UI/OptionsWindow.lua")
    hud = read(root, "UI/HUD.lua")
    jw = read(root, "UI/JournalWindow.lua")
    lg = read(root, "UI/MapLegend.lua")
    pins = read(root, "UI/MapPins.lua")
    data = read(root, "Data/FishData.lua")
    mg = read(root, "Libs/EzWoWMiniGames/MiniGames.lua")
    st = {k: rgb_list(v) for k, v in re.findall(r"StyleService\.(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", style_src)}
    opt = {k: rgb_list(v) for k, v in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", lua_table(ow, r"local Theme = \{"))}
    en = lua_kv(loc, "translationHelper.enUS")
    ring = {k: rgb_list(v) for k, v in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", lua_table(pins, r"local RING = \{"))}
    size = {k: int(v) for k, v in re.findall(r"(\w+) = (\d+)", lua_table(pins, r"local SIZE = \{"))}
    zf = re.search(rf"\[{WESTFALL}\] = \{{ s = (\d+), f = \{{([^}}]*)\}}", data)
    f = zf.group(2).split(",")
    rates = {int(f[i]): float(f[i + 1]) for i in range(0, len(f), 2)}
    mg_title = {"ko": re.search(r'koKR = \{\s*title = "([^"]+)"', mg).group(1), "en": re.search(r'enUS = \{\s*title = "([^"]+)"', mg).group(1)}
    hs = re.search(r"windowFrame:SetSize\((\d+), (\d+)\)", hud)
    js = re.search(r"local frameWidth, frameHeight = (\d+), (\d+)", jw)
    os_ = re.search(r"windowFrame:SetSize\((\d+), (\d+)\)", ow)
    return {
        "st": st, "opt": opt, "en": en, "ring": ring, "pinSize": size, "rates": rates, "zoneSkill": int(zf.group(1)),
        "zoneCount": len(rates), "mg": mg_title,
        "hudW": int(hs.group(1)), "hudH": int(hs.group(2)), "jW": int(js.group(1)), "jH": int(js.group(2)),
        "oW": int(os_.group(1)), "oH": int(os_.group(2)),
        "lgW": int(re.search(r"local frameWidth = (\d+)", lg).group(1)),
        "lgRows": int(re.search(r"local rowWidgets = (\d+)", lg).group(1)),
        "icon": icon_data(find_file(root, "Media/icon.png")),
    }


class Loc:
    def __init__(self, lang, en):
        self.lang, self.en = lang, en

    def __getitem__(self, key):
        if self.lang == "ko":
            return key
        if key not in self.en:
            raise KeyError("no English text for " + key)
        return self.en[key]


def fish_name(fid, lang):
    return FISH[fid][0 if lang == "ko" else 1]


def zone_name(mid, lang):
    return ZONE[mid][0 if lang == "ko" else 1]


T = {
    "ko": {
        "lead": "키 하나로 던지고 건지는 원버튼 낚시, 세션 HUD와 낚시 소리, 낚시 일지 · 도감, 세계지도 낚시 지점 · 물고기 떼 · 어종 확률",
        "pinLegend": "● 내가 낚은 지점 · <span style='color:#4d94ff'>●</span> 물고기 떼 · <span style='color:#cc9e40'>●</span> 공유받은 지점",
        "notes": [
            ("세션 HUD", "낚싯대를 들면 나타납니다. 현재 숙련(장비 보너스 포함)과 지역 권장 숙련, 미끼 남은 시간, 시간 · 낚은 수 · 성공률 · 시간당, 마지막 물고기. 클릭: 기록 창, 우클릭: 설정, 끌어서 이동."),
            ("미니게임 · 낚시 종료", "찌를 기다리는 동안 미니게임 창을 엽니다(키를 받지 않아 원버튼 키는 그대로 낚시). 낚시 종료는 세션을 마치고 원래 무기로 돌아갑니다."),
            ("낚시 소리", "던져 기다리는 동안만 효과음을 키웁니다. +/-로 10~200%(100%를 넘기면 주 음량까지), 스피커 버튼으로 켜기/끄기."),
            ("기록 창 탭 (/ezsf)", "세션 · 기록(최근에 낚은 물고기와 장소 · 시각) · 도감(처음 낚은 날 · 장소 · 마리 수) · 지역(현재 지역 어종과 기대 확률)."),
            ("세션 통계", "시간 · 던짐 · 낚음 · 놓침 · 성공률 · 시간당과 이번 세션 어종별 비율. “새 세션”으로 다시 시작합니다."),
            ("물고기 툴팁", "잘 잡히는 지역 3곳과 확률(권장 숙련), 물고기 떼가 나오는 지역, 내가 낚은 수."),
            ("세계지도 어종 범례", "왼쪽 아래 버튼으로 펼칩니다. 지역의 일반 낚시 어종과 확률, 핀 숨김 · 설정, “물고기 선택”으로 물고기별 지점과 잡히는 지역."),
            ("지도 핀", "내가 낚은 지점(가장 많이 낚은 어종 아이콘), 물고기 떼 출현 지점(파란 테두리), 공유받은 지점(금색 테두리)."),
        ],
        "foot": "애드온 코드의 창 크기 · 좌표 · 색상 · 문구로 재현한 예시 화면입니다. 어종과 확률은 애드온에 들어 있는 서부 몰락지대 데이터이고, 세션 숫자는 예시이며 아이콘은 단순화했습니다.",
        "sLead": "/ezsf config · 원버튼 낚시와 키, 낚시 소리, 장비 교체, 화면 표시, 공유와 기록 관리",
        "sTitle": "설정창",
        "sNotes": [
            ("언어 · 낚시", "언어(자동 + 8개 언어), 원버튼 낚시, 자동 획득, 미끼 자동 사용, 찌 자동 인식, 찌 인식 범위 넓히기."),
            ("원버튼 키", "목록에서 스페이스 · F · G · R · T · V · 마우스 휠 클릭 · 마우스 4/5번을 고릅니다(우클릭: 다음 키). /ezsf key 로 다른 키도 지정."),
            ("낚시 소리", "낚시 중 소리 키우기(켬), 음악 · 주변 소리 줄이기(끔)."),
            ("장비", "전투가 시작되면 무기로, 끝나면 낚싯대로 자동 교체. 낚싯대 ↔ 평소 무기 바꾸기, 기록 창 열기."),
            ("화면", "세션 HUD, 지도 낚시 지점, 세계지도 버튼과 좌하단 정렬, 툴팁, 미니맵 버튼, 어종 목록, 물고기 떼, 지역별 확률, 새 물고기 알림."),
            ("크기", "세션 창 70~150%, 지도 핀 60~160%."),
            ("공유 · 기록", "길드 · 파티와 낚은 위치를 주고받고, 내 기록 전체 보내기, 현재 지역 · 공유받은 · 전체 기록 지우기(확인 창이 뜹니다)."),
            ("위치 초기화 · 후원", ""),
        ],
        "sFoot": "애드온 코드의 창 크기 · 좌표 · 색상 · 문구로 재현한 예시 화면입니다. 선택 상태는 기본값입니다.",
    },
    "en": {
        "lead": "One-button fishing, a session HUD with louder fishing sound, a log and journal, and fishing spots, fish schools and catch chances on the World Map",
        "pinLegend": "● my catch spots · <span style='color:#4d94ff'>●</span> fish schools · <span style='color:#cc9e40'>●</span> shared spots",
        "notes": [
            ("Session HUD", "Appears when you equip a pole: your skill (with gear bonus) vs. the zone's recommended skill, lure timer, time, catches, success rate, per hour and your last catch. Click: log, right-click: settings, drag to move."),
            ("Mini games · Stop fishing", "Opens the mini games while you wait for a bite (the window takes no keys, so the one-button key keeps fishing). Stop fishing ends the session and puts your weapons back on."),
            ("Fishing sound", "Turns sound effects up only while your line is out. +/- set 10–200% (above 100% the master volume goes up too); the speaker button toggles it."),
            ("Log tabs (/ezsf)", "Session · Log (recent catches with place and time) · Journal (first catch, place, count) · Zone (fish and expected chances here)."),
            ("Session stats", "Time, casts, caught, missed, success, per hour and the share per fish this session. “New session” restarts."),
            ("Fish tooltip", "The three best zones with chances (and recommended skill), zones with fish schools, and how many you have caught."),
            ("World Map fish legend", "Opened from the button at the bottom-left. Open-water fish and chances for the zone, hide pins and settings, and “Filter fish” for the spots and zones of one fish."),
            ("Map pins", "Your catch spots (icon of the most-caught fish), fish school spawn points (blue rim) and shared spots (gold rim)."),
        ],
        "foot": "Mock-ups rebuilt from the window sizes, coordinates, colours and strings in the addon code. Fish and chances are the bundled Westfall data; session numbers are examples and icons are simplified.",
        "sLead": "/ezsf config · one-button fishing and key, fishing sound, gear swap, display, sharing and records",
        "sTitle": "Settings",
        "sNotes": [
            ("Language · fishing", "Language (Auto + 8 languages), one-button fishing, auto loot, auto apply lure, auto-detect bobber, widen bobber detection."),
            ("One-button key", "Pick Space, F, G, R, T, V, middle mouse or mouse 4/5 from the list (right-click: next key). Any other key with /ezsf key."),
            ("Fishing sound", "Louder sound while fishing (on), mute music & ambience (off)."),
            ("Gear", "Swap to weapons when combat starts and back to the pole after. Swap pole ↔ weapons, open the log."),
            ("Display", "Session HUD, spots on the map, world map button and bottom-left alignment, tooltips, minimap button, fish list, fish schools, zone chances, new fish alert."),
            ("Size", "Session panel 70–150%, map pins 60–160%."),
            ("Sharing · records", "Share catch spots with guild and party, send all your records, clear this zone / shared / all records (asks to confirm)."),
            ("Reset position · support", ""),
        ],
        "sFoot": "Mock-up rebuilt from the window size, coordinates, colours and strings in the addon code. The selections show the defaults.",
    },
}

LINE_COL = None


def panel(ox, oy, w, h, inner, bg, border, extra=""):
    """A frame at page px (ox, oy), w x h game px."""
    return (f'<div class="abs" style="left:{ox:.1f}px;top:{oy:.1f}px;width:{px(w)};height:{px(h)};background:{bg};'
            f'border:1px solid {border};{extra}">{inner}</div>')


def round_icon(x, y, size, kind, extra=""):
    return icon_box(x, y, size, kind, border="transparent", style="border-radius:50%;" + extra)


def flex_row(x, y, h, items, right=None, width=None, gap=4):
    """A row of inline parts (game px); anchored left at x, or right at `right` from the parent's right edge."""
    pos = f"right:{px(right)};" if right is not None else f"left:{px(x)};"
    w = f"width:{px(width)};" if width else ""
    return (f'<div class="abs" style="{pos}top:{px(y)};height:{px(h)};{w}display:flex;align-items:center;gap:{px(gap)}">'
            + "".join(items) + "</div>")


def small_btn(label, h, size, color, bg, border, pad=8, min_w=None):
    mw = f"min-width:{px(min_w)};" if min_w else ""
    return (f'<div style="flex:none;height:{px(h)};padding:0 {px(pad)};{mw}box-sizing:border-box;background:{bg};border:1px solid {border};'
            f'display:flex;align-items:center;justify-content:center;font-size:{px(size)};color:{color};white-space:nowrap;{SHADOW}">{label}</div>')


SPEAKER = ('<svg viewBox="0 0 24 24" width="100%" height="100%"><path d="M3 9 H7 L12 5 V19 L7 15 H3 Z" fill="{c}"/>'
           '<path d="M15 9 C16.5 10.5 16.5 13.5 15 15 M17.5 6.5 C20.5 9.5 20.5 14.5 17.5 17.5" stroke="{c}" stroke-width="2" fill="none" stroke-linecap="round"/></svg>')


def hud_html(ox, oy, ctx, lang):
    L = Loc(lang, ctx["en"])
    st = ctx["st"]
    W, H = ctx["hudW"], ctx["hudH"]
    acc, mut, txt = css(st["accent"]), css(st["muted"]), css(st["text"])
    line = css(st["line"])
    p = []
    skill = L["숙련 %s%d|r%s%s"].replace("%s", "|cffeeeff2", 1).replace("%d", "167", 1)
    skill = skill.replace("%s", "|cff8c94a3(+25)|r", 1).replace("%s", "  |cff8c94a3" + L["권장 %d"].replace("%d", str(ctx["zoneSkill"])) + "|r", 1)
    p.append(text_top(10, 7, wow(skill), 11, mut))
    lure = L["미끼 %s"].replace("%s", "|cff45c7e07:42|r")
    p.append(f'<div class="t" style="right:{px(10)};top:{px(7)};font-size:{px(11)};color:{mut};line-height:1.3;{SHADOW}">{wow(lure)}</div>')
    cell = (W - 20) / 4
    for i, (k, v) in enumerate((("시간", "18:20"), ("낚음", "37"), ("성공률", "92%"), ("시간당", "121"))):
        p.append(text_top(10 + i * cell, 23, v, 14, txt))
        p.append(text_top(10 + i * cell, 42, esc(L[k]), 9, mut))
    p.append(box(0, H - 24, W - 2, 1, f"background:{line}"))
    btn_bg = "rgba(255,255,255,.04)"
    border = css(st["border"])
    name = (f'<div style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:{px(11)};'
            f'color:{txt};{SHADOW}">{esc(fish_name(6361, lang))}</div>')
    icon = f'<div style="flex:none;width:{px(14)};height:{px(14)};border-radius:50%;overflow:hidden">{icon_svg("f6361")}</div>'
    games = small_btn(esc(ctx["mg"][lang]), 18, 10, acc, btn_bg, border)
    stop = small_btn(esc(L["낚시 종료"]), 18, 10, txt, btn_bg, border)
    p.append(flex_row(10, H - 21, 18, [icon, name, games, stop], width=W - 10 - 6, gap=5))
    hud = panel(ox, oy, W, H, "".join(p), css(st["bg"]), border, "box-shadow:0 10px 30px rgba(0,0,0,.4)")
    # sound panel on the right of the HUD
    sp = []
    sp.append(flex_row(4, 5, 18, [small_btn("+", 18, 11, txt, btn_bg, border, pad=0, min_w=40)]))
    sp.append(text(24, 5 + 18 + 4 + 6, "100%", 11, txt, anchor="center"))
    sp.append(flex_row(4, 5 + 18 + 4 + 11 + 4, 18, [small_btn("-", 18, 11, txt, btn_bg, border, pad=0, min_w=40)]))
    spk = f'<div style="width:{px(14)};height:{px(14)}">{SPEAKER.format(c=acc)}</div>'
    sp.append(flex_row(4, H - 3 - 18, 18, [small_btn(spk, 18, 11, txt, btn_bg, border, pad=0, min_w=40)]))
    sound = panel(ox + (W + 3) * S, oy, 48, H, "".join(sp), css(st["bg"]), border, "box-shadow:0 10px 30px rgba(0,0,0,.4)")
    return hud + sound


def list_row(x, y, w, kind, title, right, right2, bar, st, sub=None):
    acc, mut, txt = css(st["accent"]), css(st["muted"]), css(st["text"])
    p = [round_icon(x + 8, y + 6, 24, kind)]
    p.append(text_top(x + 42, y + 4, title, 12, txt))
    p.append(f'<div class="t" style="right:{px(JW_CUR[0] - (x + w) + 8)};top:{px(y + 5)};font-size:{px(12)};color:{txt};line-height:1.2;{SHADOW}">{right}</div>')
    p.append(f'<div class="t" style="right:{px(JW_CUR[0] - (x + w) + 8)};top:{px(y + 21)};font-size:{px(10)};color:{mut};line-height:1.2;{SHADOW}">{right2}</div>')
    if bar is not None:
        tw = w - 42 - 64
        p.append(box(x + 42, y + 26, tw, 3, "background:rgba(255,255,255,.07)"))
        p.append(box(x + 42, y + 26, max(1, tw * bar), 3, f"background:{acc}"))
    elif sub:
        p.append(text_top(x + 42, y + 20, sub, 10, mut))
    return "".join(p)


JW_CUR = [0]


def journal_html(ox, oy, ctx, lang):
    L = Loc(lang, ctx["en"])
    st = ctx["st"]
    W, H, PAD = ctx["jW"], ctx["jH"], 14
    JW_CUR[0] = W
    acc, mut, txt, border = css(st["accent"]), css(st["muted"]), css(st["text"]), css(st["border"])
    line = css(st["line"])
    p = []
    p.append(f'<img class="abs" src="{ctx["icon"]}" style="left:{px(PAD)};top:{px(PAD)};width:{px(26)};height:{px(26)};border-radius:50%">')
    p.append(text_top(PAD + 36, PAD - 2, TITLE, 14, txt))
    p.append(text_top(PAD + 36, PAD + 16, esc(zone_name(WESTFALL, lang)), 11, mut))
    p.append(text(W - 8 - 11, 8 + 11, "×", 16, mut, anchor="center"))
    p.append(flex_row(0, 8, 22, [small_btn(esc(L["설정"]), 22, 12, txt, "rgba(255,255,255,.03)", border, pad=10)], right=8 + 22 + 4))
    tabW = (W - PAD * 2) / 4
    for i, k in enumerate(("세션", "기록", "도감", "지역")):
        on = i == 0
        p.append(text(PAD + i * tabW + tabW / 2, 52 + 15, esc(L[k]), 12, txt if on else mut, anchor="center"))
        if on:
            p.append(box(PAD + i * tabW + 8, 52 + 28, tabW - 16, 2, f"background:{acc}"))
    p.append(box(0, 82, W - 2, 1, f"background:{line}"))
    # session page (TOPLEFT 14, 96)
    top = 96
    gap = 6
    bw = (W - PAD * 2 - gap * 2) / 3
    stats = (("시간", "18:20"), ("던짐", "40"), ("낚음", "37"), ("놓침", "3"), ("성공률", "92%"), ("시간당", "121"))
    for i, (k, v) in enumerate(stats):
        c, r = i % 3, i // 3
        x, y = PAD + c * (bw + gap), top + r * (50 + gap)
        p.append(box(x, y, bw, 50, "background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06)"))
        p.append(text_top(x + 10, y + 6, v, 16, txt))
        p.append(text_top(x + 10, y + 28, esc(L[k]), 10, mut))
    sk = L["낚시 숙련 |cffeeeff2%d / %d|r%s"].replace("%d", "142", 1).replace("%d", "150", 1).replace("%s", "  |cff45c7e0+25|r", 1)
    p.append(text_top(PAD, top + 118, wow(sk), 11, mut))
    p.append(f'<div class="t" style="right:{px(PAD)};top:{px(top + 118)};font-size:{px(11)};color:{mut};line-height:1.3;{SHADOW}">'
             f'{wow(L["미끼 %s"].replace("%s", "|cff45c7e07:42|r"))}</div>')
    p.append(box(0, top + 142, W - 2, 1, f"background:{line}"))
    p.append(text_top(PAD, top + 152, esc(L["이번 세션에 잡은 것"]), 12, txt))
    p.append(flex_row(0, top + 149, 22, [small_btn(esc(L["새 세션"]), 22, 12, txt, "rgba(255,255,255,.03)", border, pad=12)], right=PAD))
    counts = ((6361, 12), (6358, 8), (6303, 7), (6289, 5), (6308, 3), (6291, 2))
    total = sum(c for _, c in counts)
    y = top + 182
    for fid, c in counts:
        p.append(list_row(PAD - 6, y, W - PAD * 2 + 12, "f%d" % fid, esc(fish_name(fid, lang)), f"{c / total * 100:.0f}%",
                          esc(L["%d마리"].replace("%d", str(c))), c / counts[0][1], st))
        y += 36
    return panel(ox, oy, W, H, "".join(p), css(st["bg"]), border, "box-shadow:0 10px 40px rgba(0,0,0,.45)")


def pct_text(v):
    return f"{v:.0f}%" if v >= 10 else f"{v:.1f}%"


def legend_html(ox, oy, ctx, lang):
    """The fish legend, its bottom-left at page px (ox, oy)."""
    L = Loc(lang, ctx["en"])
    st = ctx["st"]
    W = ctx["lgW"]
    acc, mut, txt, border = css(st["accent"]), css(st["muted"]), css(st["text"]), css(st["border"])
    rates = ctx["rates"]
    shown = [fid for fid in sorted(rates, key=lambda k: -rates[k]) if fid in FISH][:ctx["lgRows"]]
    H = 62 + len(shown) * 20 + 22
    p = [box(0, 0, W - 2, 29, f"background:{css(st['bgSub'])}"), box(0, 29, W - 2, 1, f"background:{acc}")]
    p.append(text_top(10, 6, esc(zone_name(WESTFALL, lang)), 12, acc))
    bg = css(st["bg"])
    p.append(flex_row(0, 5, 20, [small_btn(esc(L["핀 숨김"]), 20, 10, txt, bg, border, pad=5, min_w=56),
                                 small_btn(esc(L["설정"]), 20, 10, txt, bg, border, pad=5, min_w=40),
                                 small_btn("X", 20, 12, mut, bg, border, pad=0, min_w=20)], right=5, gap=3))
    p.append(text_top(10, 37, esc(L["권장 숙련 %d"].replace("%d", str(ctx["zoneSkill"]))), 10, mut))
    p.append(flex_row(0, 35, 20, [small_btn(esc(L["물고기 선택"]) + " ▾", 20, 10, acc, css(st["bgSub"]), border, pad=6, min_w=72)], right=6))
    p.append(box(6, 58, W - 14, 1, f"background:{css(st['line'])}"))
    for i, fid in enumerate(shown):
        y = 62 + i * 20
        p.append(round_icon(6 + 4, y + 2, 16, "f%d" % fid))
        p.append(text(6 + 27, y + 10, esc(fish_name(fid, lang)), 11, txt))
        p.append(text(W - 6 - 4 - 2, y + 10, pct_text(rates[fid]), 11, mut, anchor="right"))
    foot = L["외 %d가지 · 확률은 예상치"].replace("%d", str(ctx["zoneCount"] - len(shown)))
    p.append(text_top(10, H - 6 - 13, esc(foot), 9, mut))
    return panel(ox, oy - H * S, W, H, "".join(p), css(st["bg"]), border, "z-index:5;box-shadow:0 8px 24px rgba(0,0,0,.45)"), H


def pin(cx, cy, kind, fish, ctx):
    """A round map pin centred at page px (cx, cy)."""
    ring = ctx["ring"][kind]
    size = ctx["pinSize"][kind] * S
    inset = (3 if kind == "pool" else 2) * S
    alpha = ";opacity:.9" if kind == "pool" else ""
    return (f'<div class="abs" style="left:{cx - size / 2:.1f}px;top:{cy - size / 2:.1f}px;width:{size:.1f}px;height:{size:.1f}px;'
            f'border-radius:50%;background:{css(ring, ring[3] if len(ring) > 3 else 1)};box-shadow:0 1px 3px rgba(0,0,0,.7){alpha}">'
            f'<div class="abs" style="left:{inset:.1f}px;top:{inset:.1f}px;right:{inset:.1f}px;bottom:{inset:.1f}px;border-radius:50%;overflow:hidden">'
            f'{icon_svg("f%d" % fish)}</div></div>')


MAP_SVG = ('<svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none" style="display:block">'
           '<defs><linearGradient id="sea" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2b5a78"/><stop offset="1" stop-color="#173a55"/></linearGradient>'
           '<linearGradient id="land" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6b6a45"/><stop offset="1" stop-color="#4f5534"/></linearGradient></defs>'
           '<rect width="100" height="100" fill="url(#land)"/>'
           '<path d="M64 0 C58 14 66 24 60 36 C54 48 62 60 58 72 C55 84 62 92 60 100 H100 V0 Z" fill="url(#sea)"/>'
           '<path d="M64 0 C58 14 66 24 60 36 C54 48 62 60 58 72 C55 84 62 92 60 100" stroke="#c8b98a" stroke-width=".8" fill="none" opacity=".7"/>'
           '<path d="M8 20 C20 26 30 18 42 24 M6 52 C18 48 28 56 40 50" stroke="#80784e" stroke-width=".6" fill="none" opacity=".6"/>'
           '<path d="M30 60 C34 58 40 62 38 66 C34 70 28 66 30 60 Z" fill="#2b5a78" opacity=".9"/></svg>')


def tooltip_html(x, y, lang, ctx):
    L = Loc(lang, ctx["en"])
    zones = ((1437, 150, 23.71), (1436, 75, 20.94), (1421, 75, 14.18))
    lines = [f'<span style="color:#fff">{esc(fish_name(6358, lang))}</span>', ("gap",)]
    for mid, s, pc in zones:
        lines.append((f'<span style="color:{css((0.85, 0.86, 0.90))}">{esc(zone_name(mid, lang))}  <span style="color:#8c94a3">{s}</span></span>',
                      f'<span style="color:#fff">{pc:.0f}%</span>'))
    pools = ", ".join(zone_name(m, lang) for m in (1434, 1439))
    lines.append(f'<span style="color:{css((0.43, 0.64, 1.0))}">{esc(L["물고기 떼: %s"].replace("%s", pools))}</span>')
    lines.append(f'<span style="color:{css((0.55, 0.58, 0.64))}">{esc(L["내가 낚은 수: %d"].replace("%d", "64"))}</span>')
    lines.append(("", f'<span style="color:#808080;font-size:{px(10)}">{TITLE}</span>'))
    return tooltip(x, y, lines, gloss=False, bg="rgba(8,12,18,.96)", border="#5d6d7a", font=12, title_size=14)


def ui_page(lang, ctx):
    global S
    S = 1.25
    t = T[lang]
    top = 160
    parts = [heading(TITLE, esc(t["lead"]))]
    hx = 62
    parts.append(hud_html(hx, top, ctx, lang))
    hud_bottom = top + ctx["hudH"] * S
    tip_y = hud_bottom + 58
    parts.append(tooltip_html(hx, tip_y, lang, ctx))
    jx = 500
    parts.append(journal_html(jx, top, ctx, lang))
    # World Map area with the dock button, the legend and pins
    mx, mw = jx + ctx["jW"] * S + 50, None
    mw = PAGE_W - 50 - mx
    mh = ctx["jH"] * S
    parts.append(f'<div class="abs" style="left:{mx:.0f}px;top:{top}px;width:{mw:.0f}px;height:{mh:.0f}px;border:1px solid #344c5b;'
                 f'overflow:hidden;box-shadow:0 10px 40px rgba(0,0,0,.45)">{MAP_SVG}</div>')
    bsz = 28 * S
    bx, by = mx + 10, top + mh - 10 - bsz
    parts.append(f'<img class="abs" src="{ctx["icon"]}" style="left:{bx:.0f}px;top:{by:.0f}px;width:{bsz:.0f}px;height:{bsz:.0f}px;'
                 f'border-radius:50%;box-shadow:0 0 0 2px #60cea3,0 2px 6px rgba(0,0,0,.6)">')
    leg, lh = legend_html(bx + bsz + 6 * S, top + mh - 10, ctx, lang)
    parts.append(leg)
    # pins on the coast (sea is the right part of the map)
    def mp(fx, fy):
        return mx + mw * fx, top + mh * fy
    for fx, fy, kind, fid in ((0.62, 0.08, "own", 6361), (0.56, 0.22, "own", 6358), (0.70, 0.30, "pool", 6358),
                              (0.60, 0.40, "own", 6303), (0.83, 0.16, "pool", 6358), (0.78, 0.45, "shared", 6289),
                              (0.47, 0.12, "shared", 6361), (0.88, 0.58, "pool", 6358), (0.72, 0.72, "own", 6361),
                              (0.36, 0.30, "own", 6308)):
        parts.append(pin(*mp(fx, fy), kind, fid, ctx))
    parts.append(f'<div class="t" style="left:{mx + 12:.0f}px;top:{top + 10:.0f}px;font-size:13px;color:#fff;background:rgba(10,14,18,.75);'
                 f'padding:3px 8px;border-radius:3px;{SHADOW}">{t["pinLegend"]}</div>')
    calls = [(hx - 30, top + 12), (hx + ctx["hudW"] * S - 60, hud_bottom + 24), (hx + (ctx["hudW"] + 51) * S + 22, top + 12),
             (jx - 26, top + 67 * S), (jx - 26, top + 160 * S), (hx - 30, tip_y + 14),
             (bx + bsz + 6 * S - 20, top + mh - 10 - lh * S + 14), (mx + mw * 0.47 - 30, top + mh * 0.12)]
    parts.append(callouts(calls))
    ny = top + mh + 34
    half = PAGE_W / 2
    parts.append(notes_block(50, ny, half - 80, [(a, esc(b_)) for a, b_ in t["notes"][:4]]))
    parts.append(notes_block(half + 10, ny, half - 60, [(a, esc(b_)) for a, b_ in t["notes"][4:]], start=5))
    parts.append(f'<div class="foot" style="left:50px;width:1500px">{esc(t["foot"])}</div>')
    return "".join(parts)


def settings_page(lang, ctx):
    global S
    S = 1.3
    t = T[lang]
    L = Loc(lang, ctx["en"])
    o = ctx["opt"]
    th = {k: o[k] for k in ("bg", "bgSub", "border", "text", "muted", "accent")}
    W, H = ctx["oW"], ctx["oH"]
    win = Window(th, W, H, TITLE, "", ctx["icon"], header=56, close=24, close_off=10)
    mut = css(th["muted"])
    # sub title: one line, shrunk to the 365 px the code gives it
    win.add(text(48, 39, esc(L["낚싯대를 들고 있을 때 키 하나로 던지고, 찌가 물면 같은 키로 건져 올립니다."]), 10, mut, fit=365))
    acc_bg = "rgba(31,56,48,.96)"

    def chk(x, y, key):
        win.check(x, y, esc(L[key]), True if key not in ("음악·주변 소리 줄이기",) else False, label_w=180, font=11)

    def btn(x, y, w, h, label, accent=False):
        win.button(x, y, w, h, esc(label), accent=accent, size=10.5, bg=acc_bg if accent else None)

    win.section(20, 70, esc(L["낚시"]), line_dy=18)
    btn(250, 66, 190, 20, L["언어"] + ": " + L["자동 (게임 언어)"] + " ▼")
    chk(18, 94, "원버튼 낚시")
    chk(232, 94, "자동 획득")
    chk(18, 120, "미끼 자동 사용")
    chk(232, 120, "찌 자동 인식")
    chk(18, 146, "찌 인식 범위 넓히기")
    btn(236, 148, 204, 22, L["원버튼 키"] + ": " + L["스페이스"] + " ▼")
    chk(18, 172, "낚시 중 소리 키우기")
    chk(232, 172, "음악·주변 소리 줄이기")
    win.section(20, 208, esc(L["장비"]))
    chk(18, 232, "전투가 시작되면 무기로 교체")
    chk(232, 232, "전투가 끝나면 낚싯대 다시 들기")
    btn(20, 262, 204, 24, L["낚싯대 / 평소 무기"] + " (" + L["바꾸기"] + ")")
    btn(236, 262, 204, 24, L["낚시 기록 창"] + " (/ezsf)")
    win.section(20, 298, esc(L["화면"]))
    rows = (("낚싯대를 들면 세션 창 표시", "지도에 낚시 지점 표시"), ("세계지도에 물고기 선택 버튼 표시", "세계지도 버튼 좌하단 자동 정렬"),
            ("아이템 툴팁에 잡히는 곳 표시", "미니맵 버튼 표시"), ("세계지도에 일반 낚시 어종 목록 표시", "물고기 떼 출현 지점 표시"),
            ("물고기가 나오는 지역과 확률 표시", "처음 낚은 물고기 알림"))
    for i, (a, b_) in enumerate(rows):
        chk(18, 322 + i * 26, a)
        chk(232, 322 + i * 26, b_)
    for x, key in ((20, "세션 창 크기"), (234, "지도 핀 크기")):
        y = 458
        win.add(text_top(x, y + 2, f'<span class="fit" data-fit="{115 * S:.1f}" data-min="{8 * S:.1f}">{esc(L[key])}</span>', 10.5, mut))
        win.button(x + 118, y, 22, 20, "-", size=12)
        win.add(text(x + 118 + 22 + 2 + 21, y + 10, "100%", 11, css(th["text"]), anchor="center"))
        win.button(x + 184, y, 22, 20, "+", size=12)
    win.section(20, 492, esc(L["공유"] + " · " + L["기록"]))
    chk(18, 516, "낚은 위치를 길드·파티에 공유")
    chk(232, 516, "다른 플레이어의 공유 받기")
    chk(18, 542, "공유받은 위치 지도에 표시")
    btn(236, 544, 204, 22, L["내 낚시 기록 전체"] + " " + L["보내기"])
    btn(20, 574, 134, 22, L["현재 지역 낚시 지점"] + " " + L["지우기"])
    btn(163, 574, 134, 22, L["공유받은 기록"] + " " + L["지우기"])
    btn(306, 574, 134, 22, L["모든 낚시 기록"] + " " + L["전부 지우기"])
    btn(20, 612, 204, 28, L["세계지도 버튼 위치"] + " · " + L["아이콘"] + " " + L["처음 위치로"])
    btn(236, 612, 204, 28, L["후원하기"], accent=True)
    win.add(f'<div class="t" style="left:{px(20)};bottom:{px(8)};font-size:{px(10)};color:{mut};{SHADOW}">{esc(L["/ezsf key 로 변경"])}</div>')
    win.add(f'<div class="t" style="right:{px(20)};bottom:{px(8)};font-size:{px(10)};color:{mut};{SHADOW}">{TITLE} · /ezsf</div>')
    ox, oy = 60, 150
    spans = [(66, 144), (146, 172), (172, 198), (208, 288), (298, 452), (456, 480), (492, 598), (610, 642)]
    calls = [(ox + W * S + 24, oy + (a + b_) / 2 * S) for a, b_ in spans]
    nx = ox + W * S + 70
    notes = [(a, esc(b_)) for a, b_ in t["sNotes"]]
    return (heading(TITLE, esc(t["sLead"]), t["sTitle"]) + win.html(ox, oy) + callouts(calls)
            + notes_block(nx, oy + 6, PAGE_W - nx - 40, notes).replace(" — </div>", "</div>")
            + f'<div class="foot" style="left:50px;width:1500px">{esc(t["sFoot"])}</div>')


def main(root: Path):
    ctx = load(root)
    call = hexc(ctx["st"]["accent"])
    run_pages(root, [(f"{n}_{lang}", (lambda n=n, lang=lang: (ui_page if n == "ui" else settings_page)(lang, ctx)))
                     for lang in ("ko", "en") for n in ("ui", "settings")], call)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
