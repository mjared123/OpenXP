"""Guide step text -> skeleton key, the same way Locale.lua's GuideText does it.

A skeleton is the step's ">>" text with names, icons, [item] links and
numbers swapped for {A}, {B}, ... tokens, so one translated sentence covers
every step that only differs in those. Keep this in step with GuideText in
Locale.lua: a key that comes out different there just shows English.
"""
import re

NAME_KINDS = {"FRIENDLY", "ENEMY", "LOOT", "PICK"}


def skeleton(text):
    """Returns (key, suffix) or (None, None) when the text has too many slots."""
    m = re.match(r'^(.*?)(\s*<<.*)$', text, re.S)
    body, suffix = (m.group(1), m.group(2)) if m else (text, "")
    body = re.sub(r'\s+$', '', body)
    n = [0]
    over = [False]

    def slot(_):
        n[0] += 1
        if n[0] > 26:
            over[0] = True
            return _.group(0)
        return "{%s}" % chr(64 + n[0])

    def names(mm):
        return slot(mm) if mm.group(1) in NAME_KINDS else mm.group(0)

    body = re.sub(r'\|cRXP_([A-Z]+)_(.*?)\|r', names, body, flags=re.S)
    body = re.sub(r'\|T.*?\|t', slot, body, flags=re.S)
    body = re.sub(r'\[.*?\]', slot, body, flags=re.S)
    body = re.sub(r'[0-9]+\.[0-9]+', slot, body)
    body = re.sub(r'[0-9]+', slot, body)
    if over[0]:
        return None, None
    return body, suffix


def guide_texts(paths):
    """Yields every ">>" text and "+" objective text in the guide files that
    GuideText translates."""
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                # GuideLoader drops "--" comments from the whole guide first,
                # then a "<< class" tag and everything after it on the line.
                line = re.sub(r'--[^\r\n]*', '', line.rstrip("\r\n"))
                line = re.sub(r'\s*<<\s*(.+)', '', line)
                m = re.search(r'>>\s*(.*)$', line)
                if not m or not m.group(1).strip():
                    # "+text" objective line (GuideLoader: line:sub(2, -1))
                    if line.strip().startswith("+") and line.strip()[1:].strip():
                        yield line.strip()[1:]
                    continue
                tag = re.match(r'\s*\.(\S+)', line)
                if tag and tag.group(1) in ("accept", "turnin"):
                    continue
                yield m.group(1)
