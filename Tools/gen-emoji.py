#!/usr/bin/env python3
"""Generate Tinycast/Core/Emoji/EmojiData.generated.swift from Unicode + CLDR data.

Usage: python3 Tools/gen-emoji.py [emoji-test.txt annotations.json annotationsDerived.json]
Downloads the sources when paths aren't given. Run once, commit the output.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

# Emoji added after this version may lack glyphs on the oldest supported macOS (26.0 ships Emoji 16.0).
MAX_EMOJI_VERSION = 16.0

SOURCES = [
    ("emoji-test.txt", "https://unicode.org/Public/emoji/latest/emoji-test.txt"),
    ("annotations.json", "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json"),
    ("annotationsDerived.json", "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-derived-full/annotationsDerived/en/annotations.json"),
]

GROUP_TO_CATEGORY = {
    "Smileys & Emotion": "sp",
    "People & Body": "sp",
    "Animals & Nature": "an",
    "Food & Drink": "fd",
    "Activities": "ac",
    "Travel & Places": "tp",
    "Objects": "ob",
    "Symbols": "sy",
    "Flags": "fl",
}

TONE_SCALARS = set(range(0x1F3FB, 0x1F400))
VS16 = 0xFE0F
MAX_KEYWORDS = 8

# Curated text symbols: (glyph, name, keywords). Names lowercase like the emoji dataset.
ARROWS = [
    ("←", "leftwards arrow", "left back previous"),
    ("↑", "upwards arrow", "up top"),
    ("→", "rightwards arrow", "right next forward"),
    ("↓", "downwards arrow", "down bottom"),
    ("↖", "north west arrow", "diagonal up left"),
    ("↗", "north east arrow", "diagonal up right"),
    ("↘", "south east arrow", "diagonal down right"),
    ("↙", "south west arrow", "diagonal down left"),
    ("↔", "left right arrow", "horizontal both"),
    ("↕", "up down arrow", "vertical both"),
    ("↩", "leftwards arrow with hook", "return undo back"),
    ("↪", "rightwards arrow with hook", "redo forward"),
    ("↰", "upwards arrow with tip leftwards", "turn"),
    ("↱", "upwards arrow with tip rightwards", "turn"),
    ("↲", "downwards arrow with tip leftwards", "turn"),
    ("↳", "downwards arrow with tip rightwards", "turn branch"),
    ("⇄", "rightwards arrow over leftwards arrow", "swap exchange sync"),
    ("⇅", "upwards arrow leftwards of downwards arrow", "swap sort"),
    ("⇐", "leftwards double arrow", "implies"),
    ("⇑", "upwards double arrow", "shift"),
    ("⇒", "rightwards double arrow", "implies therefore"),
    ("⇓", "downwards double arrow", ""),
    ("⇔", "left right double arrow", "iff equivalent"),
    ("⇧", "upwards white arrow", "shift key"),
    ("⇪", "upwards white arrow from bar", "caps lock key"),
    ("➔", "heavy wide-headed rightwards arrow", "pointer"),
    ("➜", "heavy round-tipped rightwards arrow", "pointer"),
    ("➤", "black rightwards arrowhead", "pointer bullet"),
]
CURRENCY = [
    ("$", "dollar sign", "usd money currency"),
    ("¢", "cent sign", "money currency"),
    ("£", "pound sign", "gbp sterling money currency"),
    ("€", "euro sign", "eur money currency"),
    ("¥", "yen sign", "jpy yuan money currency"),
    ("₹", "indian rupee sign", "inr money currency"),
    ("₩", "won sign", "krw money currency"),
    ("₽", "ruble sign", "rub money currency"),
    ("₺", "turkish lira sign", "try money currency"),
    ("₫", "dong sign", "vnd money currency"),
    ("₴", "hryvnia sign", "uah money currency"),
    ("₦", "naira sign", "ngn money currency"),
    ("₪", "new shekel sign", "ils money currency"),
    ("฿", "baht sign", "thb money currency"),
    ("₿", "bitcoin sign", "btc crypto money currency"),
    ("₡", "colon sign", "crc money currency"),
    ("₱", "peso sign", "php money currency"),
    ("₨", "rupee sign", "pkr money currency"),
    ("₸", "tenge sign", "kzt money currency"),
    ("¤", "generic currency sign", "money"),
]
MATH = [
    ("+", "plus sign", "add addition"),
    ("−", "minus sign", "subtract subtraction"),
    ("×", "multiplication sign", "times multiply"),
    ("÷", "division sign", "divide"),
    ("=", "equals sign", "equal"),
    ("≠", "not equal to", "unequal"),
    ("≈", "almost equal to", "approximately"),
    ("<", "less-than sign", ""),
    (">", "greater-than sign", ""),
    ("≤", "less-than or equal to", ""),
    ("≥", "greater-than or equal to", ""),
    ("±", "plus-minus sign", "plus or minus"),
    ("¬", "not sign", "negation"),
    ("√", "square root", "radical"),
    ("∛", "cube root", "radical"),
    ("∞", "infinity", "forever"),
    ("∑", "n-ary summation", "sum sigma"),
    ("∏", "n-ary product", "pi product"),
    ("∫", "integral", "calculus"),
    ("∂", "partial differential", "calculus derivative"),
    ("∆", "increment", "delta difference"),
    ("∇", "nabla", "gradient del"),
    ("∈", "element of", "set member"),
    ("∉", "not an element of", "set"),
    ("∩", "intersection", "set"),
    ("∪", "union", "set"),
    ("⊂", "subset of", "set"),
    ("⊃", "superset of", "set"),
    ("∅", "empty set", "null"),
    ("∧", "logical and", "conjunction"),
    ("∨", "logical or", "disjunction"),
    ("⊕", "circled plus", "xor direct sum"),
    ("∝", "proportional to", ""),
    ("∴", "therefore", ""),
    ("∵", "because", "since"),
    ("°", "degree sign", "temperature angle"),
    ("‰", "per mille sign", "permille thousand"),
    ("µ", "micro sign", "mu micro"),
    ("π", "greek small letter pi", "math constant"),
    ("Ω", "greek capital letter omega", "ohm resistance"),
    ("¼", "vulgar fraction one quarter", "fourth"),
    ("½", "vulgar fraction one half", ""),
    ("¾", "vulgar fraction three quarters", ""),
    ("ƒ", "latin small letter f with hook", "function florin"),
]
SHAPES = [
    ("■", "black square", "shape filled"),
    ("□", "white square", "shape outline"),
    ("▪", "black small square", "shape"),
    ("▫", "white small square", "shape"),
    ("▲", "black up-pointing triangle", "shape"),
    ("△", "white up-pointing triangle", "shape"),
    ("▶", "black right-pointing triangle", "play shape"),
    ("▷", "white right-pointing triangle", "play shape"),
    ("▼", "black down-pointing triangle", "shape"),
    ("▽", "white down-pointing triangle", "shape"),
    ("◀", "black left-pointing triangle", "shape"),
    ("◁", "white left-pointing triangle", "shape"),
    ("●", "black circle", "dot shape filled"),
    ("○", "white circle", "shape outline"),
    ("◆", "black diamond", "shape"),
    ("◇", "white diamond", "shape"),
    ("★", "black star", "favorite shape filled"),
    ("☆", "white star", "favorite shape outline"),
    ("✓", "check mark", "tick done yes"),
    ("✗", "ballot x", "cross no wrong"),
    ("♠", "black spade suit", "cards"),
    ("♣", "black club suit", "cards"),
    ("♥", "black heart suit", "cards love"),
    ("♦", "black diamond suit", "cards"),
    ("•", "bullet", "list point dot"),
    ("◦", "white bullet", "list point"),
    ("‣", "triangular bullet", "list point"),
    ("·", "middle dot", "interpunct"),
    ("—", "em dash", "long dash punctuation"),
    ("–", "en dash", "dash range punctuation"),
    ("…", "horizontal ellipsis", "dots punctuation"),
    ("«", "left-pointing double angle quotation mark", "guillemet quote"),
    ("»", "right-pointing double angle quotation mark", "guillemet quote"),
    ("‘", "left single quotation mark", "quote"),
    ("’", "right single quotation mark", "quote apostrophe"),
    ("“", "left double quotation mark", "quote"),
    ("”", "right double quotation mark", "quote"),
    ("„", "double low-9 quotation mark", "quote"),
    ("†", "dagger", "footnote"),
    ("‡", "double dagger", "footnote"),
    ("§", "section sign", "paragraph law"),
    ("¶", "pilcrow sign", "paragraph"),
    ("©", "copyright sign", "legal"),
    ("®", "registered sign", "trademark legal"),
    ("™", "trade mark sign", "trademark legal"),
    ("№", "numero sign", "number"),
    ("¡", "inverted exclamation mark", "spanish punctuation"),
    ("¿", "inverted question mark", "spanish punctuation"),
]
SYMBOL_SECTIONS = [("xa", ARROWS), ("xc", CURRENCY), ("xm", MATH), ("xs", SHAPES)]

LINE_RE = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E(\d+\.\d+)\s+(.*)$")


def load(paths):
    texts = []
    for (name, url), given in zip(SOURCES, paths + [None] * (len(SOURCES) - len(paths))):
        if given:
            texts.append(Path(given).read_text())
        else:
            print(f"fetching {url}")
            texts.append(urllib.request.urlopen(url).read().decode("utf-8"))
    return texts


def base_key(scalars):
    return tuple(s for s in scalars if s not in TONE_SCALARS and s != VS16)


def clean_field(s):
    return s.replace("|", " ").replace(",", " ").strip()


def keywords_for(glyph, name, annotations):
    words = annotations.get(glyph) or annotations.get(glyph.replace("️", "")) or []
    name_words = set(name.lower().split())
    out = []
    for w in words:
        w = clean_field(w.lower())
        if w and w not in name_words and w not in out:
            out.append(w)
    return out[:MAX_KEYWORDS]


def main():
    emoji_test, ann_json, derived_json = load(sys.argv[1:4])
    ann = json.loads(ann_json)["annotations"]["annotations"]
    derived = json.loads(derived_json)["annotationsDerived"]["annotations"]
    annotations = {g: v.get("default", []) for g, v in {**derived, **ann}.items()}

    group = None
    entries = []  # (glyph, name, category, scalars)
    toned_bases = set()
    for line in emoji_test.splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        m = LINE_RE.match(line)
        if not m or group not in GROUP_TO_CATEGORY:
            continue
        codes, glyph, version, name = m.groups()
        if float(version) > MAX_EMOJI_VERSION:
            continue
        scalars = tuple(int(c, 16) for c in codes.split())
        if any(s in TONE_SCALARS for s in scalars):
            toned_bases.add(base_key(scalars))
            continue
        entries.append((glyph, name.strip(), GROUP_TO_CATEGORY[group], scalars))

    lines = []
    for glyph, name, category, scalars in entries:
        tone_capable = base_key(scalars) in toned_bases and len(base_key(scalars)) == 1
        keywords = keywords_for(glyph, name, annotations)
        lines.append((glyph, clean_field(name.lower()), category, "1" if tone_capable else "0", " ".join(keywords)))
    for category, table in SYMBOL_SECTIONS:
        for glyph, name, keywords in table:
            lines.append((glyph, clean_field(name), category, "0", clean_field(keywords)))

    seen = set()
    records = []
    for fields in lines:
        assert fields[0] not in seen, f"duplicate glyph {fields[0]!r}"
        seen.add(fields[0])
        record = "|".join(fields)
        assert '"""' not in record and "\\" not in record, f"unsafe record {record!r}"
        records.append(record)
    assert len(records) > 1500, f"suspiciously few records: {len(records)}"

    out = Path(__file__).resolve().parent.parent / "Tinycast/Core/Emoji/EmojiData.generated.swift"
    out.parent.mkdir(parents=True, exist_ok=True)
    body = "\n".join(records)
    out.write_text(
        "// Generated by Tools/gen-emoji.py — do not edit by hand.\n"
        f"// Unicode emoji ≤ E{MAX_EMOJI_VERSION} + curated symbols; fields: glyph|name|category|tone|keywords.\n"
        "enum EmojiData {\n"
        f"    static let raw = \"\"\"\n{body}\n\"\"\"\n"
        "}\n"
    )
    print(f"wrote {out} ({len(records)} records)")


if __name__ == "__main__":
    main()
