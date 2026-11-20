"""Check a guide catalog using the same skeleton keys as the locale builders.

    python tools/locale/check_guide_locale.py deDE
    python tools/locale/check_guide_locale.py esES

Phrase-only catalogs and scoped catalogs with titles, names and literals are
supported. Optional metadata is checked when the catalog provides it.
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from guide_skeleton import skeleton

STRING = r'"(?:\\.|[^"\\])*"'


def table_body(source, name):
    match = re.search(r"(?m)^([ \t]*)(?:addon\.)?" + name + r"\s*=\s*\{\s*$", source)
    if not match:
        return None
    end = re.search(r"(?m)^" + re.escape(match[1]) + r"\}[^\S\n]*,?[^\S\n]*$", source[match.end():])
    if not end:
        raise ValueError("Unclosed catalog table: " + name)
    return source[match.end():match.end() + end.start()]


def lua_string(value):
    # The generated catalogs use JSON-compatible double-quoted strings.
    return json.loads(value.replace("\\'", "'"))


def translations(body):
    return {lua_string(m[1]): lua_string(m[2]) for m in re.finditer(
        r"\[(" + STRING + r")\]\s*=\s*(" + STRING + r")", body or "")}


def check(root, catalog):
    source = catalog.read_text(encoding="utf-8")
    sections = {name: table_body(source, name) for name in ("groups", "titles", "names", "literals", "phrases")}
    phrase_body = sections["phrases"]
    if phrase_body is None:
        phrase_body = table_body(source, "guidePhrases")
    if phrase_body is None:
        raise ValueError("Catalog has neither phrases nor addon.guidePhrases")
    groups = {lua_string(m[1]) for m in re.finditer(r"\[(" + STRING + r")\]\s*=\s*true", sections["groups"] or "")}
    titles, names, literals = (translations(sections[name]) for name in ("titles", "names", "literals"))
    phrases = translations(phrase_body)
    unused = {"titles": set(titles), "literals": set(literals), "phrases": set(phrases)}
    manifest = (root / "Guides/GuideList-forever.xml").read_text(encoding="utf-8")
    files = re.findall(r'<Script\s+file="(Guides/[^"\n]+\.lua)"', manifest)
    if not files:
        raise ValueError("No guide files in Guides/GuideList-forever.xml")
    checked, problems = set(), []
    chapters = steps = texts = 0

    for file in files:
        raw = (root / file).read_text(encoding="utf-8")
        for block in re.finditer(r"\[\[([\s\S]*?)\]\]", raw):
            if not re.search(r"(?m)^\s*#name\s+", block[1]):
                continue
            chapters += 1
            first_line = raw.count("\n", 0, block.start()) + 1
            for offset, row in enumerate(block[1].splitlines()):
                location = f"{file}:{first_line + offset}"
                line = re.split(r"\s*<<\s*", re.sub(r"--.*$", "", row).strip())[0].rstrip()
                header = re.match(r"#(name|displayname|group)\s+(.+)$", line)
                if header:
                    kind, title = header.groups()
                    if kind == "group":
                        if sections["groups"] is not None and title not in groups:
                            problems.append(f"{location} Uncovered guide group: {title}")
                    elif sections["titles"] is not None:
                        if not titles.get(title):
                            problems.append(f"{location} Missing title: {title}")
                        unused["titles"].discard(title)
                    continue
                steps += bool(re.match(r"step\b", line))
                tag = re.match(r"\.(\S+)", line)
                inline = re.search(r">>\s*(.+)$", line)
                text = inline or re.match(r"[+*](.+)$", line)
                if not text or tag and tag[1] in ("accept", "turnin", "macro"):
                    continue
                text = text[1] if inline else text[1].replace("\\n", "\n")
                if text.startswith("/"):
                    continue
                texts += 1
                if text in checked:
                    continue
                checked.add(text)
                if sections["names"] is not None:
                    for label in re.finditer(r"\[([^\]\n]+)\]|\|cRXP_(?:LOOT|PICK)_([^|\n]+)\|r", text):
                        name = re.sub(r"^\|cRXP_[A-Z]+_(.*?)\|r$", r"\1", label[1] or label[2])
                        if name not in names:
                            problems.append(f"{location} Missing item or object name: {name}")
                if text in literals:
                    unused["literals"].discard(text)
                    continue
                key, _ = skeleton(text)
                if key in phrases:
                    expected = sorted(re.findall(r"\{[A-Z]\}", key))
                    actual = sorted(re.findall(r"\{[A-Z]\}", phrases[key]))
                    if key in unused["phrases"] and expected != actual:
                        problems.append(f"{location} Placeholder mismatch: {key}")
                    unused["phrases"].discard(key)
                elif not (re.fullmatch(r"[\s\d=.,]+", text) or re.fullmatch(r"\|T.*?\|t(?:\[.*\])?", text)
                          or key and re.fullmatch(r"(?:\{[A-Z]\}){1,2}", key)):
                    problems.append(f"{location} Missing text: {text}")

    for name, entries in unused.items():
        for key in sorted(entries):
            problems.append(f"{catalog.name} Unused {name} entry: {key}")
    for problem in problems:
        print(problem)
    print(f"{catalog.stem}: {len(files)} guide files, {chapters} chapters, {steps} steps, "
          f"{texts} instruction texts, {len(problems)} differences")
    return bool(problems)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("locale", help="Client locale, such as deDE or esES")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--catalog", type=Path, help="Override locale/<locale>_guide.lua")
    args = parser.parse_args()
    catalog = args.catalog or args.root / "locale" / f"{args.locale}_guide.lua"
    return check(args.root, catalog)


if __name__ == "__main__":
    raise SystemExit(main())
