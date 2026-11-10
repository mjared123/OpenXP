"""Read a WoW SavedVariables file (too big for Lua's constant limit) in Python.

Handles what the game writes: `Name = value` globals, tables with ["key"] /
[number] keys and positional entries (including nil), strings, numbers,
true/false/nil. Tables come back as dicts with 1-based int keys for
positional entries.
"""
import re

_TOKEN = re.compile(r'''
    \s*(?:
      (?P<str>"(?:[^"\\]|\\.)*")
    | (?P<num>-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?|inf|nan))
    | (?P<word>[A-Za-z_][A-Za-z0-9_]*)
    | (?P<sym>[{}\[\]=,;])
    | (?P<comment>--[^\n]*)
    )''', re.X)

_ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def _unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n.isdigit():
                m = re.match(r"\d{1,3}", s[i + 1:])
                out.append(chr(int(m.group(0))))
                i += 1 + len(m.group(0))
                continue
            out.append(_ESC.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _tokens(text):
    pos, n = 0, len(text)
    while pos < n:
        m = _TOKEN.match(text, pos)
        if not m or m.end() == pos:
            if text[pos:].strip() == "":
                return
            raise ValueError("bad input at %d: %r" % (pos, text[pos:pos + 40]))
        pos = m.end()
        kind = m.lastgroup
        if kind == "comment":
            continue
        yield kind, m.group(kind)


def _num(s):
    try:
        return int(s, 0)
    except ValueError:
        return float(s)


class _Parser:
    def __init__(self, text):
        self.toks = list(_tokens(text))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def value(self):
        kind, v = self.next()
        if kind == "str":
            return _unescape(v[1:-1])
        if kind == "num":
            return _num(v)
        if kind == "word":
            return {"true": True, "false": False, "nil": None}[v]
        if v == "{":
            return self.table()
        raise ValueError("unexpected %r" % v)

    def table(self):
        t, n = {}, 0
        while True:
            kind, v = self.peek()
            if v == "}":
                self.next()
                return t
            if v == "[":
                self.next()
                key = self.value()
                assert self.next()[1] == "]"
                assert self.next()[1] == "="
                val = self.value()
                if val is not None:
                    t[key] = val
            elif kind == "word" and self.toks[self.i + 1][1] == "=":
                self.next()
                self.next()
                val = self.value()
                if val is not None:
                    t[v] = val
            else:
                n += 1
                val = self.value()
                if val is not None:
                    t[n] = val
            if self.peek()[1] in (",", ";"):
                self.next()


def load(path, only=None):
    """{globalName: value} for a SavedVariables file; `only` limits to one global."""
    text = open(path, encoding="utf-8", errors="replace").read()
    if only:
        m = re.search(r"^%s = " % re.escape(only), text, re.M)
        if not m:
            return {}
        nxt = re.search(r"^[A-Za-z_][A-Za-z0-9_]* = ", text[m.end():], re.M)
        text = text[m.start():m.end() + (nxt.start() if nxt else len(text))]
    p = _Parser(text)
    out = {}
    while p.i < len(p.toks):
        kind, name = p.next()
        assert p.next()[1] == "="
        out[name] = p.value()
    return out
