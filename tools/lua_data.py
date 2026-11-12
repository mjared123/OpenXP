"""Read Lua table literals as Python data, without running any Lua.

Only literals are understood: strings, numbers, true/false/nil and tables
({ value, key = value, ["key"] = value, [1] = value }). Used to read guide
data from other projects safely: nothing in the file is ever executed.

    parse_table(text, pos) -> (value, end)    text[pos] must be "{"
    find_calls(text, "Polestar.RegisterGuide") -> [table, ...]
"""
import re


class LuaDataError(Exception):
    pass


class Ref(str):
    """A variable reference found where a value was expected."""


_ws = re.compile(r"(?:\s+|--\[(=*)\[.*?\]\1\]|--[^\n]*)+", re.S)
_num = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)")
_name = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
_escapes = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b",
            "f": "\f", "v": "\v", "\n": "\n", "0": "\0"}


def _skip(text, i):
    m = _ws.match(text, i)
    return m.end() if m else i


def _string(text, i):
    q = text[i]
    if q == "[":
        m = re.match(r"\[(=*)\[", text[i:])
        close = "]" + m.group(1) + "]"
        start = i + m.end()
        end = text.index(close, start)
        body = text[start:end]
        if body.startswith("\n"):
            body = body[1:]
        return body, end + len(close)
    out = []
    i += 1
    while True:
        c = text[i]
        if c == q:
            return "".join(out), i + 1
        if c == "\\":
            n = text[i + 1]
            if n.isdigit():
                m = re.match(r"\d{1,3}", text[i + 1:])
                out.append(chr(int(m.group(0))))
                i += 1 + m.end()
                continue
            out.append(_escapes.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1


def parse_value(text, i):
    i = _skip(text, i)
    c = text[i]
    if c == "{":
        return parse_table(text, i)
    if c in "\"'" or (c == "[" and re.match(r"\[=*\[", text[i:])):
        return _string(text, i)
    m = _num.match(text, i)
    if m:
        s = m.group(0)
        v = int(s, 16) if s.lower().startswith(("0x", "-0x")) else (float(s) if re.search(r"[.eE]", s) else int(s))
        return v, m.end()
    m = _name.match(text, i)
    if m:
        w = m.group(0)
        if w == "true":
            return True, m.end()
        if w == "false":
            return False, m.end()
        if w == "nil":
            return None, m.end()
        # a reference to a variable (some generated files share tables:
        # candidateRecords[3]): kept as a Ref, never looked up
        j = m.end()
        while j < len(text) and text[j] in ".[":
            if text[j] == ".":
                n = _name.match(text, j + 1)
                j = n.end()
            else:
                depth = 0
                while True:
                    if text[j] == "[":
                        depth += 1
                    elif text[j] == "]":
                        depth -= 1
                        if depth == 0:
                            j += 1
                            break
                    j += 1
        return Ref(text[i:j]), j
    raise LuaDataError("not a literal at %d: %r" % (i, text[i:i + 40]))


def parse_table(text, i):
    """A table as a dict; its array part is under integer keys 1..n."""
    assert text[i] == "{"
    i += 1
    out, n = {}, 0
    while True:
        i = _skip(text, i)
        if text[i] == "}":
            return out, i + 1
        if text[i] == "[" and not re.match(r"\[=*\[", text[i:]):
            key, i = parse_value(text, i + 1)
            i = _skip(text, i)
            if text[i] != "]":
                raise LuaDataError("expected ] at %d" % i)
            i = _skip(text, i + 1)
            if text[i] != "=":
                raise LuaDataError("expected = at %d" % i)
            val, i = parse_value(text, i + 1)
            out[key] = val
        else:
            m = _name.match(text, i)
            j = _skip(text, m.end()) if m else i
            if m and text[j] == "=" and text[j + 1] != "=":
                val, i = parse_value(text, j + 1)
                out[m.group(0)] = val
            else:
                val, i = parse_value(text, i)
                n += 1
                out[n] = val
        i = _skip(text, i)
        if text[i] in ",;":
            i += 1


def as_list(t):
    """The array part of a parsed table, in order."""
    if not isinstance(t, dict):
        return []
    out, k = [], 1
    while k in t:
        out.append(t[k])
        k += 1
    return out


def find_calls(text, name):
    """The table argument of every `name({ ... })` call in the text."""
    out = []
    for m in re.finditer(re.escape(name) + r"\s*\(\s*\{", text):
        start = m.end() - 1
        table, _ = parse_table(text, start)
        out.append(table)
    return out
