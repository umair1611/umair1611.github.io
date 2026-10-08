#!/usr/bin/env python3
"""
FRANCKY TRI-FLUX - cross-module member checker (a light "type checker" for MQL, no compiler needed).

For every access  <var>.<member>  (also chained: m_ctx.md.AtrM1(), m_tracker.pos[i].sl) it resolves the type
of <var> from declarations (class members, function parameters, locals) and verifies that <member> is declared
in that class/struct (including base classes). Unknown types are skipped.

    python3 tools/check_api.py            # checks MQL5 tree + MQL4 platform
Exit code 1 when unresolved members are found.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from check_core import strip  # noqa: E402

FILES = []
for tree in ("MQL5", "MQL4"):
    for base, _, files in os.walk(os.path.join(ROOT, tree)):
        for f in files:
            if f.endswith((".mqh", ".mq5", ".mq4")):
                FILES.append(os.path.join(base, f))

# ----------------------------------------------------------------------------------------------
# 1. collect class / struct definitions: name -> (base, members{name: type})
# ----------------------------------------------------------------------------------------------
TYPES = {}
DECL_RE = re.compile(r"^\s*(?:const\s+)?(?:static\s+)?(?:virtual\s+)?([A-Za-z_]\w*)\s*(\*|&)?\s*([A-Za-z_]\w*)\s*(\[[^\]]*\])?\s*(;|=|\()")


def parse_types(code):
    lines = code.split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"^\s*(class|struct)\s+([A-Za-z_]\w*)\s*(?::\s*public\s+([A-Za-z_]\w*))?\s*$", lines[i])
        if not m:
            i += 1
            continue
        name, base = m.group(2), m.group(3)
        depth = 0
        members = {}
        j = i + 1
        started = False
        while j < len(lines):
            ln = lines[j]
            if depth == 1:
                d = DECL_RE.match(ln)
                if d and d.group(1) not in ("return", "if", "for", "while", "else", "switch", "case", "delete", "new"):
                    typ, ptr, mem, arr = d.group(1), d.group(2), d.group(3), d.group(4)
                    if typ in ("public", "private", "protected"):
                        pass
                    else:
                        members[mem] = (typ, bool(arr))
                # constructor lines (no return type)
                c = re.match(r"^\s+~?([A-Za-z_]\w*)\s*\(", ln)
                if c:
                    members.setdefault(c.group(1), ("void", False))
            depth += ln.count("{") - ln.count("}")
            if "{" in ln:
                started = True
            if started and depth <= 0:
                break
            j += 1
        if name in TYPES:
            TYPES[name][1].update(members)
        else:
            TYPES[name] = (base, members)
        i = j + 1


for path in FILES:
    parse_types(strip(open(path, encoding="utf-8", errors="replace").read()))


def has_member(typ, mem, seen=None):
    seen = seen or set()
    if typ not in TYPES or typ in seen:
        return None
    seen.add(typ)
    base, members = TYPES[typ]
    if mem in members:
        return members[mem]
    if base:
        return has_member(base, mem, seen)
    return False


# built-in MQL structs we use
TYPES.setdefault("MqlDateTime", (None, {k: ("int", False) for k in
                 ("year", "mon", "day", "hour", "min", "sec", "day_of_week", "day_of_year")}))
TYPES.setdefault("MqlTick", (None, {k: ("double", False) for k in
                 ("time", "bid", "ask", "last", "volume", "time_msc", "flags", "volume_real")}))

# ----------------------------------------------------------------------------------------------
# 2. scan accesses
# ----------------------------------------------------------------------------------------------
VAR_DECL = re.compile(r"\b([A-Z][A-Za-z_0-9]*)\s*(\*|&)?\s*([A-Za-z_]\w*)\s*(\[[^\]]*\])?\s*(?=[;=,)\[])")
ACCESS = re.compile(r"\b([A-Za-z_]\w*)((?:\s*\[[^\[\]]*\])?(?:\s*\.\s*[A-Za-z_]\w*(?:\s*\[[^\[\]]*\])?)+)")

problems = []
for path in FILES:
    rel = os.path.relpath(path, ROOT)
    code = strip(open(path, encoding="utf-8", errors="replace").read())
    lines = code.split("\n")
    decls = []          # (var, type, depth) - innermost last
    depth = 0
    for lineno, ln in enumerate(lines, 1):
        d0 = depth
        # parameters of a function header belong to the body (depth+1); locals to the current depth
        is_header = bool(re.search(r"\)\s*(const\s*)?(\{.*)?$", ln)) and not re.match(r"^\s*(if|for|while|switch|return)\b", ln)
        for d in VAR_DECL.finditer(ln):
            typ, var = d.group(1), d.group(3)
            if typ in TYPES:
                inside_parens = ln[:d.start()].count("(") > ln[:d.start()].count(")")
                decls.append((var, typ, d0 + 1 if (inside_parens and is_header) else d0))
        scope = {}
        for var, typ, dd in decls:
            scope[var] = typ
        for a in ACCESS.finditer(ln):
            head = a.group(1)
            chain = re.findall(r"\.\s*([A-Za-z_]\w*)", a.group(2))
            typ = scope.get(head)
            if typ is None:
                continue
            cur = typ
            for mem in chain:
                r = has_member(cur, mem)
                if r is None:
                    break
                if r is False:
                    problems.append("%s:%d  %s has no member '%s'  (in '%s')" % (rel, lineno, cur, mem,
                                                                                 (head + a.group(2)).strip()[:80]))
                    break
                cur = r[0]
                if cur not in TYPES:
                    break
        depth += ln.count("{") - ln.count("}")
        decls = [x for x in decls if x[2] <= depth or (x[2] == depth + 1 and is_header and "{" not in ln)]

for p in problems:
    print("ERROR " + p)
print("%d unresolved member access(es); %d classes/structs indexed" % (len(problems), len(TYPES)))


# ----------------------------------------------------------------------------------------------
# 3. arity check: method calls on resolved types + FTF_* free functions
# ----------------------------------------------------------------------------------------------
def split_args(s):
    depth, cur, out = 0, "", []
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    out = [x.strip() for x in out]
    if len(out) == 1 and (out[0] == "" or out[0] == "void"):
        return []
    return out


def balanced(code, pos):
    """code[pos] == '(' -> content up to the matching ')'"""
    depth = 0
    for i in range(pos, len(code)):
        if code[i] == "(":
            depth += 1
        elif code[i] == ")":
            depth -= 1
            if depth == 0:
                return code[pos + 1:i]
    return None


SIGS = {}      # (type, method) -> list of (min, max)
FREE = {}      # FTF_ function -> list of (min, max)
for path in FILES:
    code = strip(open(path, encoding="utf-8", errors="replace").read())
    # class bodies: find "class X" then member declarations "name(" at depth 1
    for m in re.finditer(r"\b(class|struct)\s+([A-Za-z_]\w*)\s*(?::\s*public\s+\w+)?\s*\{", code):
        name = m.group(2)
        i = m.end()
        depth = 1
        j = i
        while j < len(code) and depth > 0:
            c = code[j]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            elif c == "(" and depth == 1:
                k = j - 1
                while k > 0 and code[k] in " \t":
                    k -= 1
                e = k + 1
                while k >= 0 and (code[k].isalnum() or code[k] == "_"):
                    k -= 1
                meth = code[k + 1:e]
                args = balanced(code, j)
                if meth and args is not None:
                    ps = split_args(args)
                    mx = len(ps)
                    mn = len([p for p in ps if "=" not in p])
                    SIGS.setdefault((name, meth), []).append((mn, mx))
                    j += len(args) + 1
            j += 1
    for m in re.finditer(r"(?m)^[A-Za-z_][\w]*\s+\*?\s*(FTF_\w+)\s*\(", code):
        args = balanced(code, m.end() - 1)
        if args is not None:
            ps = split_args(args)
            FREE.setdefault(m.group(1), []).append((len([p for p in ps if "=" not in p]), len(ps)))


def arity_ok(sigs, n):
    return any(mn <= n <= mx for mn, mx in sigs)


arity_problems = []
for path in FILES:
    rel = os.path.relpath(path, ROOT)
    code = strip(open(path, encoding="utf-8", errors="replace").read())
    lines = code.split("\n")
    offsets = []
    off = 0
    for ln in lines:
        offsets.append(off)
        off += len(ln) + 1
    decls = []
    depth = 0
    for lineno, ln in enumerate(lines, 1):
        d0 = depth
        is_header = bool(re.search(r"\)\s*(const\s*)?(\{.*)?$", ln)) and not re.match(r"^\s*(if|for|while|switch|return)\b", ln)
        for d in VAR_DECL.finditer(ln):
            typ, var = d.group(1), d.group(3)
            if typ in TYPES:
                inside_parens = ln[:d.start()].count("(") > ln[:d.start()].count(")")
                decls.append((var, typ, d0 + 1 if (inside_parens and is_header) else d0))
        scope = {}
        for var, typ, dd in decls:
            scope[var] = typ
        for a in ACCESS.finditer(ln):
            head = a.group(1)
            typ = scope.get(head)
            if typ is None:
                continue
            parts = re.findall(r"\.\s*([A-Za-z_]\w*)", a.group(2))
            cur = typ
            ok = True
            for mem in parts[:-1]:
                r = has_member(cur, mem)
                if not r:
                    ok = False
                    break
                cur = r[0]
            if not ok or not parts:
                continue
            meth = parts[-1]
            endpos = offsets[lineno - 1] + a.end()
            rest = code[endpos:endpos + 3]
            if not rest.lstrip().startswith("("):
                continue
            p = code.index("(", endpos)
            args = balanced(code, p)
            if args is None:
                continue
            n = len(split_args(args))
            # look up in type and bases
            t = cur
            sigs = None
            seen = set()
            while t and t not in seen:
                seen.add(t)
                if (t, meth) in SIGS:
                    sigs = SIGS[(t, meth)]
                    break
                t = TYPES.get(t, (None, {}))[0]
            if sigs and not arity_ok(sigs, n):
                arity_problems.append("%s:%d  %s.%s called with %d arg(s), declared %s" % (rel, lineno, cur, meth, n, sigs))
        for f in re.finditer(r"(?<![\w.])(FTF_\w+)\s*\(", ln):
            name = f.group(1)
            if name not in FREE:
                continue
            if re.match(r"^[A-Za-z_][\w]*\s+\*?\s*" + name + r"\s*\(", ln.strip()) and ln == ln.lstrip():
                continue   # definition
            p = offsets[lineno - 1] + f.end() - 1
            args = balanced(code, p)
            if args is None:
                continue
            n = len(split_args(args))
            if not arity_ok(FREE[name], n):
                arity_problems.append("%s:%d  %s called with %d arg(s), declared %s" % (rel, lineno, name, n, FREE[name]))
        depth += ln.count("{") - ln.count("}")
        decls = [x for x in decls if x[2] <= depth or (x[2] == depth + 1 and is_header and "{" not in ln)]

for p in arity_problems:
    print("ERROR " + p)
print("%d arity problem(s); %d method signatures, %d FTF_ functions indexed" % (len(arity_problems), len(SIGS), len(FREE)))
sys.exit(1 if (problems or arity_problems) else 0)
