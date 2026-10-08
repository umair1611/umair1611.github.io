#!/usr/bin/env python3
"""
FRANCKY TRI-FLUX - static checks that do not need MetaEditor.

    python3 tools/check_core.py          # verify Core identity MT5==MT4, forbidden APIs, includes, braces
    python3 tools/check_core.py --sync   # copy MQL5 Core -> MQL4 Core first (MQL5 is the reference tree)

Checks:
  1. Every file in MQL5/Include/FranckyTriFlux/Core exists byte-identical in the MQL4 tree.
  2. Core files do not use platform-specific APIs (see docs/09 section 3).
  3. Every #include <FranckyTriFlux\\...> target exists in both trees.
  4. Braces / parentheses / brackets balance (comments and strings stripped).
  5. Core does not use MQL4 reserved identifiers as variable/method names.
  6. Both Platform.mqh files declare the same public CPlatform method names.
This is NOT a compiler. Always compile with MetaEditor (F7) before delivery.
"""
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE5 = os.path.join(ROOT, "MQL5", "Include", "FranckyTriFlux", "Core")
CORE4 = os.path.join(ROOT, "MQL4", "Include", "FranckyTriFlux", "Core")

FORBIDDEN = [
    r"\binput\s+group\b", r"^\s*input\s", r"^\s*sinput\s", r"#property\b", r"\btemplate\s*<", r"\bArraySort\s*\(",
    r"\bMqlTick\b", r"\bCopyTicks", r"\bCTrade\b", r"\bPosition(Get|Select|sTotal|Close|Modify)", r"\bOrder(Send|Select|Close|Modify|sTotal|sHistoryTotal|Get)",
    r"\bHistory(Select|Deal|Order)", r"\bDEAL_", r"\bi(ATR|MA|ADX|Close|Open|High|Low|Time|Bars)\s*\(", r"\bCopy(Buffer|Rates|Close|Time)\s*\(",
    r"\bSymbolInfo(Double|Integer|String|Tick|SessionTrade)\s*\(", r"\bAccountInfo(Double|Integer|String)\s*\(", r"\bMarketInfo\s*\(",
    r"\bCalendar[A-Z]\w*\s*\(", r"\bWebRequest\s*\(", r"\bStringTrim(Left|Right)\s*\(", r"\bStringTo(Upper|Lower)\s*\(",
    r"\bObjectsDeleteAll\s*\(", r"\boverride\b", r"\bfinal\b", r"\)\s*=\s*0\s*;", r"\bSleep\s*\(", r"\bRefreshRates\s*\(",
    r"\bstatic\s+(int|double|long|bool|string|ulong|datetime)\s+\w+\s*;",
]
RESERVED = ["Bid", "Ask", "Point", "Digits", "Bars", "Time", "Open", "High", "Low", "Close", "Volume"]


def strip(code):
    code = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), code, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    code = re.sub(r'"(\\.|[^"\\])*"', '""', code)
    code = re.sub(r"'(\\.|[^'\\])'", "''", code)
    return code


def mqh_files(d):
    return sorted(f for f in os.listdir(d) if f.endswith(".mqh")) if os.path.isdir(d) else []


def main():
    errors, warnings = [], []
    if "--sync" in sys.argv:
        os.makedirs(CORE4, exist_ok=True)
        for f in mqh_files(CORE5):
            shutil.copyfile(os.path.join(CORE5, f), os.path.join(CORE4, f))
        for f in mqh_files(CORE4):
            if f not in mqh_files(CORE5):
                os.remove(os.path.join(CORE4, f))
        print("synced %d core files MQL5 -> MQL4" % len(mqh_files(CORE5)))

    # 1 identity
    for f in mqh_files(CORE5):
        p4 = os.path.join(CORE4, f)
        if not os.path.exists(p4):
            errors.append("missing in MQL4 Core: " + f)
        elif open(os.path.join(CORE5, f), "rb").read() != open(p4, "rb").read():
            errors.append("Core file differs MT5/MT4: " + f)
    for f in mqh_files(CORE4):
        if not os.path.exists(os.path.join(CORE5, f)):
            errors.append("extra file in MQL4 Core: " + f)

    all_files = []
    for tree in ("MQL5", "MQL4"):
        for base, _, files in os.walk(os.path.join(ROOT, tree)):
            for f in files:
                if f.endswith((".mqh", ".mq5", ".mq4")):
                    all_files.append(os.path.join(base, f))

    for path in all_files:
        rel = os.path.relpath(path, ROOT)
        raw = open(path, "r", encoding="utf-8", errors="replace").read()
        code = strip(raw)
        tree = "MQL5" if rel.startswith("MQL5") else "MQL4"
        # 3 includes
        for m in re.finditer(r"#include\s*<([^>]+)>", raw):
            inc = m.group(1).replace("\\", "/")
            if inc.startswith("FranckyTriFlux/"):
                if not os.path.exists(os.path.join(ROOT, tree, "Include", inc)):
                    errors.append("%s: include target missing: %s" % (rel, inc))
        # 4 balance
        for o, c in (("{", "}"), ("(", ")"), ("[", "]")):
            if code.count(o) != code.count(c):
                errors.append("%s: unbalanced %s%s (%d vs %d)" % (rel, o, c, code.count(o), code.count(c)))
        # 2 forbidden in core (MQL5 copy is enough because identical)
        if "/Core/" in rel.replace("\\", "/") and tree == "MQL5" and not rel.endswith(("InputEnums.mqh",)):
            for ln, line in enumerate(strip(raw).split("\n"), 1):
                if rel.endswith("Config.mqh") and re.search(r"=\s*Inp\w+;", line):
                    continue
                for pat in FORBIDDEN:
                    if re.search(pat, line):
                        # allow #ifdef __MQL5__ OBJPROP_FILL cosmetics
                        errors.append("%s:%d forbidden in Core: /%s/ -> %s" % (rel, ln, pat, line.strip()[:100]))
                for r in RESERVED:
                    if re.search(r"(\b(double|int|long|bool|string|datetime)\s+%s\b|\b%s\s*\()" % (r, r), line):
                        errors.append("%s:%d reserved MQL4 identifier used: %s" % (rel, ln, r))

    # 6 platform API parity
    def api(path):
        """public method names of class CPlatform (declarations at member indentation only)"""
        if not os.path.exists(path):
            return None
        lines = strip(open(path, encoding="utf-8", errors="replace").read()).split("\n")
        inside, access, names = False, "private", set()
        for ln in lines:
            if re.match(r"^class\s+CPlatform\b", ln):
                inside, access = True, "private"
                continue
            if not inside:
                continue
            if re.match(r"^\s*};", ln):
                break
            m = re.match(r"^(public|private|protected):", ln)
            if m:
                access = m.group(1)
                continue
            if access != "public":
                continue
            m = re.match(r"^ {3}(?:virtual\s+)?[A-Za-z_][\w]*\s+\*?\s*([A-Za-z_]\w*)\s*\(", ln)
            if m:
                names.add(m.group(1))
        return names
    a5 = api(os.path.join(ROOT, "MQL5", "Include", "FranckyTriFlux", "Platform", "Platform.mqh"))
    a4 = api(os.path.join(ROOT, "MQL4", "Include", "FranckyTriFlux", "Platform", "Platform.mqh"))
    if a5 is not None and a4 is not None:
        if a5 - a4:
            errors.append("CPlatform methods only in MT5: " + ", ".join(sorted(a5 - a4)))
        if a4 - a5:
            errors.append("CPlatform methods only in MT4: " + ", ".join(sorted(a4 - a5)))
    else:
        warnings.append("Platform.mqh missing in one tree (API parity not checked)")

    for w in warnings:
        print("WARN  " + w)
    for e in errors:
        print("ERROR " + e)
    print("%d error(s), %d warning(s), %d files scanned" % (len(errors), len(warnings), len(all_files)))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
