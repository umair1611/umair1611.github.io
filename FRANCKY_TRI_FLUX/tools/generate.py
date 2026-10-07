#!/usr/bin/env python3
"""
FRANCKY TRI-FLUX code/config generator.

    python3 tools/generate.py            # regenerate everything
    python3 tools/generate.py --check    # fail (exit 1) if generated files are out of date

Generates (from tools/ftf_spec.py):
  MQL5/Include/FranckyTriFlux/Core/InputEnums.mqh   (identical copy in MQL4 tree)
  MQL5/Include/FranckyTriFlux/Core/Config.mqh       (identical copy in MQL4 tree)
  MQL5/Include/FranckyTriFlux/Inputs.mqh            (MT5 flavour: input group)
  MQL4/Include/FranckyTriFlux/Inputs.mqh            (MT4 flavour: separator strings)
  MQL5/Presets/FranckyTriFlux/*.set, MQL4/Presets/FranckyTriFlux/*.set
  Tester/MT5/*.ini, Tester/MT4/*.ini (+ the .set files they reference)
  docs/05_Input_Parameters_Reference.md
"""
import os
import sys
import codecs

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ftf_spec as S  # noqa: E402

ENUM_MAP = {name: {c: v for c, v, _ in members} for name, members, _ in S.ENUMS}
ENUM_LABEL = {name: {c: lbl for c, _, lbl in members} for name, members, _ in S.ENUMS}

HEADER = """//+------------------------------------------------------------------+
//| FRANCKY TRI-FLUX HFT-style Ultra Scalping                          |
//| GENERATED FILE - DO NOT EDIT BY HAND.                              |
//| Source of truth: tools/ftf_spec.py  ->  python3 tools/generate.py |
//+------------------------------------------------------------------+
"""

OUT = {}  # path -> (content, encoding)


def emit(rel, content, enc="ascii"):
    OUT[os.path.join(ROOT, rel)] = (content, enc)


def field(var):
    assert var.startswith("Inp"), var
    return var[3:]


def mql_type(t):
    return {"bool": "bool", "int": "int", "double": "double", "string": "string"}.get(t, t)


def mql_literal(t, v):
    if t == "bool":
        return "true" if v else "false"
    if t == "int":
        return str(int(v))
    if t == "double":
        s = repr(float(v))
        return s if ("." in s or "e" in s) else s + ".0"
    if t == "string":
        return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'
    return str(v)  # enum constant


def numeric_value(t, v, platform):
    """Value as written in .set files."""
    if t == "bool":
        if platform == "MT5":
            return "true" if v else "false"
        return "1" if v else "0"
    if t == "int":
        return str(int(v))
    if t == "double":
        return ("%.8f" % float(v)).rstrip("0").rstrip(".") if float(v) != int(float(v)) else str(int(float(v)))
    if t == "string":
        return str(v)
    if t == "ENUM_TIMEFRAMES":
        return str(S.TF_VALUES[v][0 if platform == "MT5" else 1])
    if t == "ENUM_BASE_CORNER":
        return str(S.CORNER_VALUES[v])
    if t in ENUM_MAP:
        return str(ENUM_MAP[t][v])
    raise ValueError(t)


def default_for(inp, platform):
    if platform == "MT4" and "mt4" in inp:
        return inp["mt4"]
    return inp["d"]


# ----------------------------------------------------------------------------------------------
def gen_enums():
    lines = [HEADER, "#ifndef FTF_INPUT_ENUMS_MQH", "#define FTF_INPUT_ENUMS_MQH", ""]
    for name, members, desc in S.ENUMS:
        lines.append("// " + desc)
        lines.append("enum " + name)
        lines.append("  {")
        for i, (c, v, lbl) in enumerate(members):
            comma = "," if i < len(members) - 1 else ""
            lines.append("   %s=%d%s // %s" % (c, v, comma, lbl))
        lines.append("  };")
        lines.append("")
    lines.append("#endif // FTF_INPUT_ENUMS_MQH")
    content = "\n".join(lines) + "\n"
    emit("MQL5/Include/FranckyTriFlux/Core/InputEnums.mqh", content)
    emit("MQL4/Include/FranckyTriFlux/Core/InputEnums.mqh", content)


def gen_inputs(platform):
    lines = [HEADER, "#ifndef FTF_INPUTS_MQH", "#define FTF_INPUTS_MQH", "",
             "#include <FranckyTriFlux\\Core\\InputEnums.mqh>", ""]
    if platform == "MT4":
        lines.append("// MQL4 has no 'input group': groups are shown as read-only separator lines.")
        lines.append("")
    cur = None
    for inp in S.INPUTS:
        if inp["g"] != cur:
            cur = inp["g"]
            title = S.G[cur]
            lines.append("")
            if platform == "MT5":
                lines.append('input group "%s"' % title)
            else:
                lines.append('sinput string InpSep_%s = "==== %s ===="; // ==== %s ====' % (cur, title, title))
        v = default_for(inp, platform)
        lines.append("input %s %s = %s; // %s" % (mql_type(inp["t"]), inp["var"], mql_literal(inp["t"], v), inp["label"]))
    lines += ["", "#endif // FTF_INPUTS_MQH", ""]
    emit("%s/Include/FranckyTriFlux/Inputs.mqh" % ("MQL5" if platform == "MT5" else "MQL4"), "\n".join(lines))


CONFIG_EXTRA = r"""
   //--- derived helpers (hand-written part of the template in tools/generate.py)
   int ModeDelayMs(void) const
     {
      if(TradingMode==FTF_MODE_SPEED)      return DelaySpeedMs;
      if(TradingMode==FTF_MODE_ULTRA)      return DelayUltraMs;
      return DelayAggressiveMs;
     }
   int ModeMaxSpreadPts(void) const
     {
      if(TradingMode==FTF_MODE_SPEED)      return MaxSpreadPtsSpeed;
      if(TradingMode==FTF_MODE_ULTRA)      return MaxSpreadPtsUltra;
      return MaxSpreadPtsAggressive;
     }
   bool UseCooldownDelay(void) const { return (DelayUsage==FTF_DELAY_COOLDOWN || DelayUsage==FTF_DELAY_BOTH); }
   bool UseConfirmDelay(void)  const { return (DelayUsage==FTF_DELAY_CONFIRM  || DelayUsage==FTF_DELAY_BOTH); }
   double MomSellRatioEff(void) const { return (MomSymmetric ? 1.0-MomBuyRatio : MomSellRatio); }
   //--- per-engine accessors (engine id: 1=Momentum 2=FVG 3=Range)
   bool   EngineEnabled(const int e) const    { if(e==1) return MomEnabled;        if(e==2) return FvgEnabled;        if(e==3) return RngEnabled;        return false; }
   int    EngineMaxPositions(const int e) const{ if(e==1) return MomMaxPositions;   if(e==2) return FvgMaxPositions;   if(e==3) return RngMaxPositions;   return 0; }
   int    EngineTimeStopSec(const int e) const { if(e==1) return MomTimeStopSec;    if(e==2) return FvgTimeStopSec;    if(e==3) return RngTimeStopSec;    return 0; }
   int    EngineSignalTtlMs(const int e) const { if(e==1) return MomSignalTtlMs;    if(e==2) return FvgSignalTtlMs;    if(e==3) return RngSignalTtlMs;    return 500; }
   double EngineBeTriggerPct(const int e) const{ if(e==1) return MomBeTriggerPct;   if(e==2) return FvgBeTriggerPct;   if(e==3) return RngBeTriggerPct;   return 0.0; }
   double EngineBeLockPct(const int e) const   { if(e==1) return MomBeLockPct;      if(e==2) return FvgBeLockPct;      if(e==3) return RngBeLockPct;      return 0.0; }
   double EngineTrailTriggerPct(const int e) const{ if(e==1) return MomTrailTriggerPct; if(e==2) return FvgTrailTriggerPct; if(e==3) return RngTrailTriggerPct; return 0.0; }
   double EngineTrailDistPct(const int e) const{ if(e==1) return MomTrailDistPct;   if(e==2) return FvgTrailDistPct;   if(e==3) return RngTrailDistPct;   return 25.0; }
   double EngineTrailStepPct(const int e) const{ if(e==1) return MomTrailStepPct;   if(e==2) return FvgTrailStepPct;   if(e==3) return RngTrailStepPct;   return 5.0; }
   bool   H1StrictAppliesTo(const int e) const { if(e==1) return H1StrictMomentum;  if(e==2) return H1StrictFvg;       if(e==3) return H1StrictRange;     return false; }
"""


def gen_config():
    L = [HEADER, "#ifndef FTF_CONFIG_MQH", "#define FTF_CONFIG_MQH", "",
         "#include <FranckyTriFlux\\Core\\InputEnums.mqh>", "",
         "// CConfig holds a validated copy of every input. Core modules ONLY read CConfig, never Inp* globals.",
         "// The only place where Inp* globals are read is LoadFromInputs() below.",
         "class CConfig", "  {", "public:"]
    cur = None
    for inp in S.INPUTS:
        if inp["g"] != cur:
            cur = inp["g"]
            L.append("   //--- " + S.G[cur])
        L.append("   %-22s %s;  // %s" % (mql_type(inp["t"]), field(inp["var"]), inp["label"]))
    L.append("")
    L.append("   CConfig(void) {}")
    L.append("")
    L.append("   //--- copy every input into the config")
    L.append("   void LoadFromInputs(void)")
    L.append("     {")
    for inp in S.INPUTS:
        L.append("      %s = %s;" % (field(inp["var"]), inp["var"]))
    L.append("     }")
    L.append("")
    # Validate
    L.append("   //--- range checks generated from the spec + cross checks. Returns false on blocking errors.")
    L.append("   bool Validate(string &errors)")
    L.append("     {")
    L.append("      errors=\"\";")
    L.append("      bool ok=true;")
    for inp in S.INPUTS:
        f = field(inp["var"])
        if inp["t"] in ("int", "double"):
            if "min" in inp:
                L.append('      if(%s<%s) { errors+="%s ('"'"'%s'"'"') below %s; "; ok=false; }' %
                         (f, mql_literal(inp["t"], inp["min"]), f, inp["label"].replace('"', "'"), inp["min"]))
            if "max" in inp:
                L.append('      if(%s>%s) { errors+="%s ('"'"'%s'"'"') above %s; "; ok=false; }' %
                         (f, mql_literal(inp["t"], inp["max"]), f, inp["label"].replace('"', "'"), inp["max"]))
    L.append('      if(H1EmaFast>=H1EmaSlow)    { errors+="H1 fast EMA must be < slow EMA; "; ok=false; }')
    L.append('      if(MomEmaFast>=MomEmaSlow)  { errors+="M1 fast EMA must be < slow EMA; "; ok=false; }')
    L.append('      if(RngEmaFast>=RngEmaSlow)  { errors+="Range fast EMA must be < slow EMA; "; ok=false; }')
    L.append('      if(MomVelRefMs<2*MomVelWindowMs) { errors+="Velocity reference window must be >= 2 x velocity window; "; ok=false; }')
    L.append('      if((long)TickHistorySec*1000<(long)MomVelRefMs+2*(long)MomVelWindowMs) { errors+="Tick history too short for the velocity reference window; "; ok=false; }')
    L.append('      if(FvgTpMinRR>FvgTpMaxRR)   { errors+="FVG TP min R must be <= max R; "; ok=false; }')
    L.append('      if(MomMicroRangeTicks>=MomTickWindow*4) { errors+="Micro-range ticks unusually large versus tick window; "; }')
    L.append('      if(RiskMode!=FTF_RISK_FIXED_LOT && RiskPercent>MaxRiskPercent && MaxRiskPercent>0.0) { errors+="Risk per trade above hard cap - hard cap will apply; "; }')
    L.append('      if(MaxPositionsSymbol<MomMaxPositions || MaxPositionsSymbol<FvgMaxPositions || MaxPositionsSymbol<RngMaxPositions) { errors+="Symbol max positions lower than an engine max - symbol limit wins; "; }')
    L.append("      return ok;")
    L.append("     }")
    L.append("")
    # DumpLines
    L.append("   //--- human readable dump of the effective configuration (written to the log at start)")
    L.append("   int DumpLines(string &lines[])")
    L.append("     {")
    L.append("      ArrayResize(lines,%d);" % len(S.INPUTS))
    L.append("      int n=0;")
    for inp in S.INPUTS:
        f = field(inp["var"])
        t = inp["t"]
        if t == "bool":
            val = '(%s ? "true" : "false")' % f
        elif t == "int":
            val = "IntegerToString(%s)" % f
        elif t == "double":
            val = "DoubleToString(%s,4)" % f
        elif t == "string":
            val = f
        else:
            val = "EnumToString(%s)" % f
        L.append('      lines[n++]="[%s] %s = "+%s;' % (inp["g"], inp["label"].replace('"', "'"), val))
    L.append("      return n;")
    L.append("     }")
    L.append(CONFIG_EXTRA)
    L.append("  };")
    L.append("")
    L.append("#endif // FTF_CONFIG_MQH")
    content = "\n".join(L) + "\n"
    emit("MQL5/Include/FranckyTriFlux/Core/Config.mqh", content)
    emit("MQL4/Include/FranckyTriFlux/Core/Config.mqh", content)


# ----------------------------------------------------------------------------------------------
# SET FILES
# ----------------------------------------------------------------------------------------------
def set_value(inp, platform, symbol, stage):
    v = default_for(inp, platform)
    if symbol and "sym" in inp and symbol in inp["sym"]:
        v = inp["sym"][symbol]
    if stage and inp["var"] in S.STAGES[stage]:
        v = S.STAGES[stage][inp["var"]]
    return v


def is_numeric(t):
    return t in ("int", "double") or t in ENUM_MAP or t in ("ENUM_TIMEFRAMES", "ENUM_BASE_CORNER", "bool")


def enum_range(t, platform):
    if t in ENUM_MAP:
        vals = list(ENUM_MAP[t].values())
        return min(vals), max(vals)
    if t == "ENUM_TIMEFRAMES":
        return (0, 49153) if platform == "MT5" else (0, 43200)
    if t == "ENUM_BASE_CORNER":
        return 0, 3
    return None


def set_lines_mt5(symbol, stage, optimize_prefix=None, title=""):
    out = ["; FRANCKY TRI-FLUX - MT5 preset - %s" % title,
           "; Generated by tools/generate.py from tools/ftf_spec.py - edit the spec, not this file.",
           "; Symbol: %s | Stage: %s" % (symbol or "generic", stage or "default"),
           "; Load: Inputs tab > right click > Load (chart: MQL5\\Presets, tester ini: MQL5\\Profiles\\Tester)"]
    cur = None
    for inp in S.INPUTS:
        if inp["g"] != cur:
            cur = inp["g"]
            out.append("; " + S.G[cur])
        t = inp["t"]
        v = set_value(inp, "MT5", symbol, stage)
        val = numeric_value(t, v, "MT5")
        if t == "string":
            out.append("%s=%s" % (inp["var"], val))
            continue
        opt = optimize_prefix is not None and "opt" in inp and inp["var"].startswith(optimize_prefix)
        if t in ("int", "double"):
            if "opt" in inp:
                a, st, b = inp["opt"]
            else:
                a, st, b = v, (1 if t == "int" else 0.1), v
            out.append("%s=%s||%s||%s||%s||%s" % (inp["var"], val, numeric_value(t, a, "MT5"), numeric_value(t, st, "MT5"),
                                                  numeric_value(t, b, "MT5"), "Y" if opt else "N"))
        elif t == "bool":
            out.append("%s=%s||false||0||true||N" % (inp["var"], val))
        else:
            lo, hi = enum_range(t, "MT5")
            out.append("%s=%s||%d||0||%d||N" % (inp["var"], val, lo, hi))
    return out


def mt4_num(t, v):
    if t == "double":
        return "%.8f" % float(v)
    return numeric_value(t, v, "MT4")


def set_lines_mt4(symbol, stage, optimize_prefix=None, title=""):
    out = []
    for inp in S.INPUTS:
        t = inp["t"]
        v = set_value(inp, "MT4", symbol, stage)
        if t == "string":
            out.append("%s=%s" % (inp["var"], numeric_value(t, v, "MT4")))
            continue
        out.append("%s=%s" % (inp["var"], mt4_num(t, v)))
        opt = optimize_prefix is not None and "opt" in inp and inp["var"].startswith(optimize_prefix)
        if t in ("int", "double") and "opt" in inp:
            a, st, b = inp["opt"]
        elif t == "bool":
            a, st, b = 0, 1, 1
        elif t in ("int", "double"):
            a, st, b = v, 0, 0
        else:
            lo, hi = enum_range(t, "MT4")
            a, st, b = lo, 0, hi
        out.append("%s,F=%d" % (inp["var"], 1 if opt else 0))
        tt = t if t in ("int", "double") else "int"
        out.append("%s,1=%s" % (inp["var"], mt4_num(tt, a)))
        out.append("%s,2=%s" % (inp["var"], mt4_num(tt, st)))
        out.append("%s,3=%s" % (inp["var"], mt4_num(tt, b)))
    return out


def write_set(rel, lines, platform):
    text = "\r\n".join(lines) + "\r\n"
    if platform == "MT5":
        emit(rel, text, "utf-16-bom")
    else:
        emit(rel, text, "ascii")


def gen_sets():
    for plat, base in (("MT5", "MQL5"), ("MT4", "MQL4")):
        fn = set_lines_mt5 if plat == "MT5" else set_lines_mt4
        # generic default
        write_set("%s/Presets/FranckyTriFlux/FranckyTriFlux_%s_DEFAULT.set" % (base, plat), fn(None, None, None, "EA defaults"), plat)
        for sym in S.SYMBOLS:
            write_set("%s/Presets/FranckyTriFlux/FranckyTriFlux_%s_%s.set" % (base, plat, sym),
                      fn(sym, "COMBINED", None, "%s live/demo starting preset (3 engines)" % sym), plat)
            for stage, prefix in S.STAGE_OPT_PREFIX.items():
                write_set("Tester/%s/sets/FTF_%s_%s_%s.set" % (plat, plat, sym, stage),
                          fn(sym, stage, None, "%s %s single test" % (sym, stage)), plat)
                if prefix:
                    write_set("Tester/%s/sets/FTF_%s_%s_%s_OPT.set" % (plat, plat, sym, stage),
                              fn(sym, stage, prefix, "%s %s optimization" % (sym, stage)), plat)


# ----------------------------------------------------------------------------------------------
# TESTER INI FILES
# ----------------------------------------------------------------------------------------------
IS_FROM, IS_TO = "2025.01.01", "2025.12.31"        # in-sample
OOS_FROM, OOS_TO = "2026.01.01", "2026.09.30"      # out-of-sample
OPT_FROM, OPT_TO, FWD_DATE = "2025.01.01", "2026.09.30", "2026.01.01"


def gen_ini():
    for sym in S.SYMBOLS:
        for stage, prefix in S.STAGE_OPT_PREFIX.items():
            for period_name, (f, t) in (("IS", (IS_FROM, IS_TO)), ("OOS", (OOS_FROM, OOS_TO))):
                for stress in (False, True):
                    tag = "%s_%s_%s%s" % (sym, stage, period_name, "_STRESS" if stress else "")
                    # ---- MT5
                    ini = ["; FRANCKY TRI-FLUX - MT5 Strategy Tester config - %s" % tag,
                           "; Run:  terminal64.exe /config:\"<full path>\\FTF_MT5_%s.ini\"" % tag,
                           "; Copy the referenced .set file into <MT5 data folder>\\MQL5\\Profiles\\Tester\\ first.",
                           "; Adjust Symbol= if your broker uses a suffix (EURUSD.m, XAUUSDm, BTCUSD.r ...).",
                           "[Tester]",
                           "Expert=FranckyTriFlux\\FranckyTriFlux.ex5",
                           "ExpertParameters=FTF_MT5_%s_%s.set" % (sym, stage),
                           "Symbol=%s" % sym,
                           "Period=M1",
                           "Model=4",
                           "ExecutionMode=%d" % (-1 if stress else 0),
                           "Optimization=0",
                           "FromDate=%s" % f,
                           "ToDate=%s" % t,
                           "ForwardMode=0",
                           "Deposit=10000",
                           "Currency=USD",
                           "Leverage=100",
                           "Visual=0",
                           "Report=FTF_MT5_%s" % tag,
                           "ReplaceReport=1",
                           "UseLocal=1",
                           "ShutdownTerminal=1"]
                    emit("Tester/MT5/FTF_MT5_%s.ini" % tag, "\r\n".join(ini) + "\r\n")
                    # ---- MT4
                    ini4 = ["; FRANCKY TRI-FLUX - MT4 Strategy Tester config - %s" % tag,
                            "; Run:  terminal.exe /portable \"<full path>\\FTF_MT4_%s.ini\"   (MT4 takes the ini path as a plain argument, NOT /config:)" % tag,
                            "; Copy the referenced .set file into <MT4 data folder>\\tester\\ first. Save this ini as ANSI/ASCII.",
                            "; MT4 tester: fixed spread, ticks interpolated from M1 (see docs/08_MT4_Divergences.md).",
                            "TestExpert=FranckyTriFlux\\FranckyTriFlux",
                            "TestExpertParameters=FTF_MT4_%s_%s.set" % (sym, stage),
                            "TestSymbol=%s" % sym,
                            "TestPeriod=M1",
                            "TestModel=0",
                            "TestSpread=%s" % ("0" if not stress else "30"),
                            "TestOptimization=false",
                            "TestDateEnable=true",
                            "TestFromDate=%s" % f,
                            "TestToDate=%s" % t,
                            "TestReport=FTF_MT4_%s" % tag,
                            "TestReplaceReport=true",
                            "TestShutdownTerminal=true",
                            "TestVisualEnable=false"]
                    emit("Tester/MT4/FTF_MT4_%s.ini" % tag, "\r\n".join(ini4) + "\r\n")
            if prefix:
                tag = "%s_%s_OPTIMIZE" % (sym, stage)
                ini = ["; FRANCKY TRI-FLUX - MT5 optimization (in-sample + forward out-of-sample) - %s" % tag,
                       "; Forward period from %s is the out-of-sample check (spec C.3)." % FWD_DATE,
                       "[Tester]",
                       "Expert=FranckyTriFlux\\FranckyTriFlux.ex5",
                       "ExpertParameters=FTF_MT5_%s_%s_OPT.set" % (sym, stage),
                       "Symbol=%s" % sym,
                       "Period=M1",
                       "Model=4",
                       "ExecutionMode=0",
                       "Optimization=2",
                       "OptimizationCriterion=6",
                       "FromDate=%s" % OPT_FROM,
                       "ToDate=%s" % OPT_TO,
                       "ForwardMode=4",
                       "ForwardDate=%s" % FWD_DATE,
                       "Deposit=10000",
                       "Currency=USD",
                       "Leverage=100",
                       "UseLocal=1",
                       "Report=FTF_MT5_%s" % tag,
                       "ReplaceReport=1",
                       "ShutdownTerminal=1"]
                emit("Tester/MT5/FTF_MT5_%s.ini" % tag, "\r\n".join(ini) + "\r\n")
                ini4 = ["; FRANCKY TRI-FLUX - MT4 optimization - %s (in-sample only; run the OOS ini afterwards)" % tag,
                        "TestExpert=FranckyTriFlux\\FranckyTriFlux",
                        "TestExpertParameters=FTF_MT4_%s_%s_OPT.set" % (sym, stage),
                        "TestSymbol=%s" % sym,
                        "TestPeriod=M1",
                        "TestModel=0",
                        "TestSpread=0",
                        "TestOptimization=true",
                        "TestDateEnable=true",
                        "TestFromDate=%s" % IS_FROM,
                        "TestToDate=%s" % IS_TO,
                        "TestReport=FTF_MT4_%s" % tag,
                        "TestReplaceReport=true",
                        "TestShutdownTerminal=true"]
                emit("Tester/MT4/FTF_MT4_%s.ini" % tag, "\r\n".join(ini4) + "\r\n")


# ----------------------------------------------------------------------------------------------
# DOC: input reference
# ----------------------------------------------------------------------------------------------
def human_default(inp, platform="MT5"):
    t = inp["t"]
    v = default_for(inp, platform)
    if t == "bool":
        return "true" if v else "false"
    if t in ENUM_LABEL:
        return ENUM_LABEL[t][v]
    if t == "ENUM_TIMEFRAMES":
        return v.replace("PERIOD_", "")
    if t == "ENUM_BASE_CORNER":
        return v.replace("CORNER_", "").replace("_", " ").title()
    if t == "string":
        return '"%s"' % v if v != "" else "(empty)"
    return str(v)


def gen_doc():
    L = ["# 05 - Input Parameters Reference", "",
         "> Generated from `tools/ftf_spec.py` by `tools/generate.py`. Parameter names below are the names shown in the",
         "> MetaTrader **Inputs** tab (the text after `//` in the source). MT5 and MT4 use the same names and defaults",
         "> unless stated. Per-symbol values are those of the delivered `.set` presets.", ""]
    L.append("Legend: **Opt range** = start / step / stop written in the optimization `.set` files.")
    L.append("")
    cur = None
    for inp in S.INPUTS:
        if inp["g"] != cur:
            cur = inp["g"]
            L += ["", "## " + S.G[cur], "",
                  "| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |",
                  "|---|---|---|---|---|"]
        d = human_default(inp)
        if "mt4" in inp:
            d += " (MT4: %s)" % human_default(inp, "MT4")
        if "sym" in inp:
            vals = []
            for s in S.SYMBOLS:
                x = inp["sym"].get(s, inp["d"])
                if inp["t"] == "bool":
                    x = "true" if x else "false"
                vals.append(str(x) + (" (auto)" if inp["var"].startswith("InpMaxSpreadPts") and x == 0 else ""))
            sv = " / ".join(vals)
        else:
            sv = "same"
        opt = "%s / %s / %s" % inp["opt"] if "opt" in inp else ""
        desc = inp["desc"] or ""
        if inp["t"] in ENUM_LABEL:
            desc += " Choices: " + "; ".join(ENUM_LABEL[inp["t"]].values()) + "."
        L.append("| **%s** | %s | %s | %s | %s |" % (inp["label"].replace("|", "/"), d.replace("|", "/"), sv, opt,
                                                     desc.replace("|", "/")))
    L += ["", "## Developer cross-reference (label -> MQL variable)", "",
          "| Parameter (Inputs tab) | MQL variable | CConfig field | Type |", "|---|---|---|---|"]
    for inp in S.INPUTS:
        L.append("| %s | `%s` | `cfg.%s` | %s |" % (inp["label"].replace("|", "/"), inp["var"], field(inp["var"]), inp["t"]))
    emit("docs/05_Input_Parameters_Reference.md", "\n".join(L) + "\n", "utf-8")


# ----------------------------------------------------------------------------------------------
def encode(content, enc):
    if enc == "utf-16-bom":
        return codecs.BOM_UTF16_LE + content.encode("utf-16-le")
    if enc == "ascii":
        return content.encode("ascii")
    return content.encode("utf-8")


def main():
    gen_enums()
    gen_inputs("MT5")
    gen_inputs("MT4")
    gen_config()
    gen_sets()
    gen_ini()
    gen_doc()
    check = "--check" in sys.argv
    stale = []
    for path, (content, enc) in sorted(OUT.items()):
        data = encode(content, enc)
        if check:
            if not os.path.exists(path) or open(path, "rb").read() != data:
                stale.append(path)
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(data)
    if check:
        if stale:
            print("STALE generated files:\n  " + "\n  ".join(stale))
            sys.exit(1)
        print("generated files up to date (%d files)" % len(OUT))
    else:
        print("generated %d files, %d inputs" % (len(OUT), len(S.INPUTS)))


if __name__ == "__main__":
    main()
