"""
FRANCKY TRI-FLUX - SINGLE SOURCE OF TRUTH for enums and input parameters.

Everything that is user-configurable is declared here ONCE. tools/generate.py turns it into:
  * Core/InputEnums.mqh            (both trees, identical)   - enums shown in the Inputs dialog
  * Inputs.mqh  (MQL5 + MQL4)      - input declarations (MT5 uses `input group`, MT4 uses separators)
  * Core/Config.mqh (both trees)   - CConfig class: fields + LoadFromInputs() + Validate() + DumpLines()
  * .set presets (per platform / symbol / test stage, optimization sets)
  * Strategy Tester .ini files (MT5 + MT4)
  * docs/05_Input_Parameters_Reference.md

RULES
  * `var`   = MQL variable name (Inp...). Config field name = var without the 'Inp' prefix.
  * `label` = the text after `//` in the MQL source = the name the user sees in the Inputs tab.
              The user manual always refers to parameters by this label.
  * `sym`   = per-symbol override used by the per-symbol .set files.
  * `opt`   = (start, step, stop) range written into optimization .set files.
"""

# ----------------------------------------------------------------------------------------------
# ENUMS  (name, [(constant, value, dropdown label)], description)
# ----------------------------------------------------------------------------------------------
ENUMS = [
    ("ENUM_FTF_MODE", [
        ("FTF_MODE_SPEED", 0, "SPEED (delay 1500 ms)"),
        ("FTF_MODE_AGGRESSIVE", 1, "AGGRESSIVE (delay 750 ms)"),
        ("FTF_MODE_ULTRA", 2, "ULTRA (delay 300 ms)"),
    ], "Reactivity profile. No NORMAL mode exists (spec Table 3)."),
    ("ENUM_FTF_H1_FILTER", [
        ("FTF_H1_OFF", 0, "OFF - H1 ignored"),
        ("FTF_H1_SOFT", 1, "SOFT - context only, never blocks"),
        ("FTF_H1_STRICT", 2, "STRICT - may block entries against clear H1 trend"),
    ], "H1 context filter (spec section A)."),
    ("ENUM_FTF_DELAY_USAGE", [
        ("FTF_DELAY_COOLDOWN", 0, "Cooldown between entries of the same engine"),
        ("FTF_DELAY_CONFIRM", 1, "Signal must stay valid during the delay"),
        ("FTF_DELAY_BOTH", 2, "Both cooldown and confirmation"),
    ], "How the SPEED/AGGRESSIVE/ULTRA delay is applied (open question Q2)."),
    ("ENUM_FTF_SAMEDIR", [
        ("FTF_SAMEDIR_STACK", 0, "Stack within the limits"),
        ("FTF_SAMEDIR_IGNORE", 1, "Ignore if a same-direction position exists"),
    ], "Same-direction signal policy (Table 12)."),
    ("ENUM_FTF_RISK_MODE", [
        ("FTF_RISK_FIXED_LOT", 0, "Fixed lot"),
        ("FTF_RISK_PCT_BALANCE", 1, "% of balance at real SL distance"),
        ("FTF_RISK_PCT_EQUITY", 2, "% of equity at real SL distance"),
    ], "Position sizing mode (B.5)."),
    ("ENUM_FTF_STOPS_POLICY", [
        ("FTF_STOPS_ADJUST", 0, "Widen SL/TP to broker minimum and re-size"),
        ("FTF_STOPS_REJECT", 1, "Reject the signal"),
    ], "What to do when SL/TP is closer than the broker stops level."),
    ("ENUM_FTF_DD_REF", [
        ("FTF_DDREF_PEAK_EQUITY", 0, "Peak equity (high-water mark)"),
        ("FTF_DDREF_START_BALANCE", 1, "Balance when EA started"),
        ("FTF_DDREF_DAY_START_EQUITY", 2, "Equity at start of the server day"),
    ], "Reference used to measure the 10% equity drawdown."),
    ("ENUM_FTF_NEWS_SOURCE", [
        ("FTF_NEWS_AUTO", 0, "AUTO (MT5 live: calendar, else CSV)"),
        ("FTF_NEWS_CALENDAR", 1, "MT5 built-in economic calendar"),
        ("FTF_NEWS_CSV", 2, "CSV file (works in tester, MT4 and MT5)"),
        ("FTF_NEWS_WEB", 3, "Web XML feed (live only, URL must be allowed)"),
        ("FTF_NEWS_CALENDAR_AND_CSV", 4, "MT5 calendar + CSV file"),
    ], "News data source (B.1)."),
    ("ENUM_FTF_IMPACT", [
        ("FTF_IMPACT_LOW", 1, "Low and above"),
        ("FTF_IMPACT_MEDIUM", 2, "Medium and above"),
        ("FTF_IMPACT_HIGH", 3, "High only"),
    ], "Minimum news impact that blocks entries."),
    ("ENUM_FTF_TIME_BASIS", [
        ("FTF_TIME_SERVER", 0, "Broker server time"),
        ("FTF_TIME_UTC", 1, "UTC / GMT"),
    ], "Time basis of custom session hours."),
    ("ENUM_FTF_SESSION_PRESET", [
        ("FTF_SESS_CUSTOM", 0, "CUSTOM (Trading start/end below)"),
        ("FTF_SESS_LONDON", 1, "LONDON 07:00-16:00 UTC"),
        ("FTF_SESS_NEWYORK", 2, "NEW YORK 12:00-21:00 UTC"),
        ("FTF_SESS_LONDON_NY", 3, "LONDON + NEW YORK 07:00-21:00 UTC"),
        ("FTF_SESS_ASIA", 4, "ASIA 23:00-08:00 UTC"),
        ("FTF_SESS_ASIA_LONDON_NY", 5, "ASIA + LONDON + NEW YORK 23:00-21:00 UTC"),
    ], "Session window preset (B.2)."),
    ("ENUM_FTF_GMT_MODE", [
        ("FTF_GMT_AUTO", 0, "AUTO (live: server-GMT; tester: manual)"),
        ("FTF_GMT_MANUAL", 1, "MANUAL (offset below)"),
    ], "How the broker GMT offset is obtained."),
    ("ENUM_FTF_LOSS_SCOPE", [
        ("FTF_SCOPE_ENGINE", 0, "Per engine"),
        ("FTF_SCOPE_INSTANCE", 1, "Whole instance (symbol)"),
    ], "Consecutive-loss counting scope (B.4)."),
    ("ENUM_FTF_EXECQ_ACTION", [
        ("FTF_EXECQ_LOG_ONLY", 0, "Log only"),
        ("FTF_EXECQ_BLOCK", 1, "Block new entries for a cooldown"),
        ("FTF_EXECQ_REDUCE_LOT", 2, "Reduce lot size"),
    ], "Action when execution quality is out of tolerance (Table 13)."),
    ("ENUM_FTF_MI_GUARD", [
        ("FTF_MI_OFF", 0, "OFF (own-magic isolation only)"),
        ("FTF_MI_ISOLATE", 1, "ISOLATE + block duplicate Instance ID"),
        ("FTF_MI_BLOCK_DUPLICATES", 2, "ISOLATE + block cross-instance duplicate entries"),
    ], "Multi-instance guard (Table 12)."),
    ("ENUM_FTF_EXPOSURE_MODE", [
        ("FTF_EXPO_OFF", 0, "OFF"),
        ("FTF_EXPO_CURRENCY", 1, "Currency decomposition (net USD/EUR/XAU/BTC risk)"),
        ("FTF_EXPO_CORRELATION", 2, "Currency + measured correlation"),
    ], "Aggregate exposure guard (B.6)."),
    ("ENUM_FTF_VEL_METRIC", [
        ("FTF_VEL_TICKS", 0, "Tick count per window"),
        ("FTF_VEL_PRICE_PATH", 1, "Price path (sum of |price changes|)"),
    ], "Tick velocity metric."),
    ("ENUM_FTF_CTX_USE", [
        ("FTF_CTX_OFF", 0, "OFF"),
        ("FTF_CTX_SOFT", 1, "SOFT (log only)"),
        ("FTF_CTX_STRICT", 2, "STRICT (must agree)"),
    ], "Use of an internal context confirmation."),
    ("ENUM_FTF_FVG_ENTRY", [
        ("FTF_FVG_TOUCH", 0, "TOUCH - first touch of the zone edge"),
        ("FTF_FVG_CE", 1, "CE - 50% of the gap"),
        ("FTF_FVG_REJECTION", 2, "REJECTION - candle rejects the zone"),
    ], "FVG entry mode."),
    ("ENUM_FTF_FVG_SL", [
        ("FTF_FVGSL_ZONE", 0, "Beyond the FVG invalidation edge"),
        ("FTF_FVGSL_SWING", 1, "Beyond the 3-candle swing extreme"),
    ], "FVG stop-loss anchor."),
    ("ENUM_FTF_TP_MODE", [
        ("FTF_TP_LIQUIDITY", 0, "Next liquidity / swing (fallback R multiple)"),
        ("FTF_TP_ATR", 1, "ATR multiple"),
        ("FTF_TP_RR", 2, "R multiple of SL distance"),
    ], "FVG take-profit mode."),
    ("ENUM_FTF_STRUCT_MODE", [
        ("FTF_STRUCT_BOS", 1, "BOS"),
        ("FTF_STRUCT_CHOCH", 2, "CHoCH"),
        ("FTF_STRUCT_ANY", 3, "BOS or CHoCH"),
    ], "Structure event used when BOS_REQUIRED = true."),
    ("ENUM_FTF_RANGE_TP", [
        ("FTF_RTP_MID", 0, "Range middle"),
        ("FTF_RTP_OPPOSITE", 1, "Opposite boundary"),
    ], "Range take-profit target."),
    ("ENUM_FTF_RANGE_CONFIRM", [
        ("FTF_RCONF_NONE", 0, "None"),
        ("FTF_RCONF_SLOWDOWN", 1, "Tick slowdown"),
        ("FTF_RCONF_REJECTION", 2, "Candle rejection wick"),
        ("FTF_RCONF_EITHER", 3, "Slowdown OR rejection"),
        ("FTF_RCONF_BOTH", 4, "Slowdown AND rejection"),
    ], "Range edge confirmation."),
    ("ENUM_FTF_SYMBOL_CHECK", [
        ("FTF_SYMCHK_OFF", 0, "OFF"),
        ("FTF_SYMCHK_WARN", 1, "WARN on unsupported symbol"),
        ("FTF_SYMCHK_BLOCK", 2, "BLOCK entries on unsupported symbol"),
    ], "Supported-symbol check (EURUSD / XAUUSD / BTCUSD)."),
    ("ENUM_FTF_LOG_LEVEL", [
        ("FTF_LOG_OFF", 0, "OFF"),
        ("FTF_LOG_ERROR", 1, "ERROR"),
        ("FTF_LOG_WARN", 2, "WARN"),
        ("FTF_LOG_INFO", 3, "INFO"),
        ("FTF_LOG_DEBUG", 4, "DEBUG"),
        ("FTF_LOG_TRACE", 5, "TRACE (very verbose)"),
    ], "Log verbosity."),
    ("ENUM_FTF_OPT_CRITERION", [
        ("FTF_OPT_NET_PROFIT", 0, "Net profit"),
        ("FTF_OPT_PROFIT_FACTOR", 1, "Profit factor"),
        ("FTF_OPT_EXPECTANCY", 2, "Expectancy per trade"),
        ("FTF_OPT_WINRATE", 3, "Win rate (with min trades)"),
        ("FTF_OPT_ROBUST", 4, "Robust score (expectancy, PF, DD, trades)"),
    ], "Value returned by OnTester() for custom optimization."),
]

# Timeframes allowed as inputs (MT5 value, MT4 value)
TF_VALUES = {"PERIOD_M1": (1, 1), "PERIOD_M5": (5, 5), "PERIOD_M15": (15, 15)}
CORNER_VALUES = {"CORNER_LEFT_UPPER": 0, "CORNER_RIGHT_UPPER": 1, "CORNER_LEFT_LOWER": 2, "CORNER_RIGHT_LOWER": 3}

SYMBOLS = ["EURUSD", "XAUUSD", "BTCUSD"]

# ----------------------------------------------------------------------------------------------
# INPUTS
# Each: dict(g=group, var, t=type, d=default, label, desc, [opt=(start,step,stop)], [sym={...}],
#            [mt4=default for MT4], [min], [max])
# t: bool | int | double | string | ENUM_xxx | ENUM_TIMEFRAMES | ENUM_BASE_CORNER
# ----------------------------------------------------------------------------------------------
G = {}
INPUTS = []


def grp(key, title):
    G[key] = title


def I(g, var, t, d, label, desc, **kw):
    e = dict(g=g, var=var, t=t, d=d, label=label, desc=desc)
    e.update(kw)
    INPUTS.append(e)


# ---- 01 GENERAL -------------------------------------------------------------------------------
grp("GEN", "01. GENERAL / INSTANCE")
I("GEN", "InpEnableTrading", "bool", True, "Enable new entries (master switch)",
  "OFF = the EA keeps managing open positions (BE, trailing, time-stops, exits) but opens nothing new.")
I("GEN", "InpTradingMode", "ENUM_FTF_MODE", "FTF_MODE_AGGRESSIVE", "Trading mode (SPEED / AGGRESSIVE / ULTRA)",
  "Reactivity profile. Selects the entry delay and the maximum spread used by all three engines.")
I("GEN", "InpInstanceId", "int", 1, "Instance ID (1-999, unique per chart on one account)",
  "Identifies this chart/instance. Two charts on the same account and symbol must use different IDs.", min=1, max=999)
I("GEN", "InpMagicBase", "int", 5100000, "Magic number base (magic = base + ID x 10 + engine)",
  "Momentum = base+ID*10+1, FVG = +2, Range = +3. MT5 and MT4 use different default bases.", mt4=4100000, min=0)
I("GEN", "InpCommentPrefix", "string", "FTF", "Order comment prefix",
  "Short text written in every order comment (brokers may truncate comments; the magic number is the real ID).")
I("GEN", "InpSymbolCheck", "ENUM_FTF_SYMBOL_CHECK", "FTF_SYMCHK_WARN", "Supported-symbol check (EURUSD/XAUUSD/BTCUSD)",
  "The V1 markets are EURUSD, XAUUSD and BTCUSD (broker suffixes such as EURUSD.m are recognised). WARN only warns; BLOCK refuses new entries on any other symbol.")
I("GEN", "InpTimerMs", "int", 250, "Internal timer period (ms)",
  "Background heartbeat for pauses, retries, dashboard and state saving when no tick arrives.", min=50, max=5000)

# ---- 02 ENGINES -------------------------------------------------------------------------------
grp("ENG", "02. STRATEGY ENGINES ON/OFF")
I("ENG", "InpMomEnabled", "bool", True, "Engine A - Momentum / Micro-breakout ON",
  "Turns the Momentum engine on or off. Each engine is independent; no engine waits for another.")
I("ENG", "InpFvgEnabled", "bool", True, "Engine B - FVG (Fair Value Gap) ON", "Turns the FVG engine on or off.")
I("ENG", "InpRngEnabled", "bool", True, "Engine C - Range / Mean Reversion ON", "Turns the Range engine on or off.")

# ---- 03 MODES ---------------------------------------------------------------------------------
grp("MODE", "03. MODES - DELAYS AND SPREAD LIMITS")
I("MODE", "InpDelaySpeedMs", "int", 1500, "SPEED mode entry delay (ms)", "Initial value 1500 ms (spec Table 15).", min=0, opt=(500, 250, 2500))
I("MODE", "InpDelayAggressiveMs", "int", 750, "AGGRESSIVE mode entry delay (ms)", "Initial value 750 ms.", min=0, opt=(250, 125, 1500))
I("MODE", "InpDelayUltraMs", "int", 300, "ULTRA mode entry delay (ms)", "Initial value 300 ms.", min=0, opt=(0, 50, 600))
I("MODE", "InpDelayUsage", "ENUM_FTF_DELAY_USAGE", "FTF_DELAY_COOLDOWN", "How the mode delay is applied",
  "Cooldown = minimum time between two entries of the same engine. Confirm = the signal must stay valid for the whole delay before the order is sent. Both = both rules.")
I("MODE", "InpMaxSpreadPtsSpeed", "int", 0, "Max spread SPEED (points, 0 = auto)",
  "Entry refused when spread is above this value. 0 = automatic limit (see 'Auto max spread').", min=0,
  sym={"EURUSD": 12, "XAUUSD": 35, "BTCUSD": 0})
I("MODE", "InpMaxSpreadPtsAggressive", "int", 0, "Max spread AGGRESSIVE (points, 0 = auto)", "As above, for AGGRESSIVE.", min=0,
  sym={"EURUSD": 15, "XAUUSD": 40, "BTCUSD": 0})
I("MODE", "InpMaxSpreadPtsUltra", "int", 0, "Max spread ULTRA (points, 0 = auto)", "As above, for ULTRA.", min=0,
  sym={"EURUSD": 18, "XAUUSD": 45, "BTCUSD": 0})
I("MODE", "InpAutoMaxSpreadAtr", "double", 0.30, "Auto max spread (x ATR M1) when limit = 0",
  "Used only when the mode limit is 0: spread must be <= this fraction of ATR(14) M1.", min=0.0)

# ---- 04 MARKET DATA ---------------------------------------------------------------------------
grp("MD", "04. MARKET DATA / VOLATILITY")
I("MD", "InpAtrPeriod", "int", 14, "ATR period (M1 / M5)", "ATR(14) is the spec value.", min=2)
I("MD", "InpAtrMedianBars", "int", 50, "ATR median length (M1 bars)", "Median of the last 50 M1 ATR values (spec Table 18).", min=5)
I("MD", "InpTickHistorySec", "int", 120, "Tick history kept in memory (s)", "Must exceed the velocity reference window. MT5 pre-loads this history at start.", min=40)
I("MD", "InpMaxTickAgeSec", "int", 60, "Max tick age before market considered stale (s)",
  "No new entries when the last tick is older than this (market closed / feed problem).", min=5,
  sym={"EURUSD": 60, "XAUUSD": 60, "BTCUSD": 120})
I("MD", "InpVolAnomalyAtrMult", "double", 3.0, "Volatility anomaly: ATR > x median ATR",
  "Blocks new entries when ATR(M1) is abnormally high versus its median. 0 = off.", min=0.0)
I("MD", "InpVolAnomalyVelMult", "double", 6.0, "Volatility anomaly: tick velocity > x median",
  "Blocks new entries during abnormal tick bursts. 0 = off.", min=0.0)
I("MD", "InpVolAnomalySpreadMult", "double", 3.0, "Volatility anomaly: spread > x median spread",
  "Blocks new entries when spread widens abnormally versus its recent median. 0 = off.", min=0.0)

# ---- 05 H1 ------------------------------------------------------------------------------------
grp("H1", "05. H1 CONTEXT FILTER (OFF / SOFT / STRICT)")
I("H1", "InpH1Filter", "ENUM_FTF_H1_FILTER", "FTF_H1_SOFT", "H1_FILTER mode",
  "OFF: H1 ignored. SOFT (default): shown and logged, never blocks, never reduces the lot. STRICT: can block entries against a clear H1 trend (rules per engine below).")
I("H1", "InpH1EmaFast", "int", 20, "H1 fast EMA period", "EMA20 (spec A.1).", min=1)
I("H1", "InpH1EmaSlow", "int", 50, "H1 slow EMA period", "EMA50 (spec A.1).", min=2)
I("H1", "InpH1AdxPeriod", "int", 14, "H1 ADX period", "ADX(14).", min=2)
I("H1", "InpH1AdxThreshold", "double", 18.0, "H1 ADX directional threshold", "BULLISH/BEARISH requires ADX above this value. Initial 18.", min=0.0, opt=(14.0, 2.0, 30.0))
I("H1", "InpH1DiMinGap", "double", 0.0, "H1 min +DI/-DI gap", "Dominant DI must exceed the other by at least this value.", min=0.0)
I("H1", "InpH1StrongAdx", "double", 25.0, "H1 'strong trend' ADX (Range STRICT)",
  "In STRICT, Range entries are blocked only when H1 is BULLISH/BEARISH and ADX >= this value. Set equal to the directional threshold to use the plain A.1 definition.", min=0.0)
I("H1", "InpH1StrictMomentum", "bool", True, "STRICT applies to Momentum", "In STRICT, block Momentum entries opposite to a clear H1 trend.")
I("H1", "InpH1StrictFvg", "bool", True, "STRICT applies to FVG", "In STRICT, block FVG entries opposite to a clear H1 trend.")
I("H1", "InpH1StrictRange", "bool", True, "STRICT applies to Range", "In STRICT, block NEW Range entries while a strong H1 trend is established.")

# ---- 06 MOMENTUM ------------------------------------------------------------------------------
grp("MOM", "06. ENGINE A - MOMENTUM / MICRO-BREAKOUT")
I("MOM", "InpMomTickWindow", "int", 50, "Tick window for imbalance (ticks)", "Spec: 50 ticks.", min=5, opt=(30, 10, 80))
I("MOM", "InpMomBuyRatio", "double", 0.62, "BUY: min bullish tick ratio", "Spec: >= 62% bullish ticks.", min=0.5, max=1.0, opt=(0.56, 0.02, 0.70))
I("MOM", "InpMomSymmetric", "bool", True, "SELL ratio = 1 - BUY ratio (symmetric)", "When ON, the SELL threshold is 1 - BUY ratio (0.38 for 0.62) and the next input is ignored.")
I("MOM", "InpMomSellRatio", "double", 0.38, "SELL: max bullish tick ratio", "Spec: <= 38% bullish ticks. Used only when symmetric is OFF.", min=0.0, max=0.5)
I("MOM", "InpMomCountFlatTicks", "bool", False, "Count unchanged ticks in the ratio", "OFF: ratio = up / (up + down). ON: ratio = up / all ticks.")
I("MOM", "InpMomVelMetric", "ENUM_FTF_VEL_METRIC", "FTF_VEL_TICKS", "Velocity metric", "Tick count (default) or price path per window.")
I("MOM", "InpMomVelWindowMs", "int", 2000, "Velocity window (ms)", "Spec: 2 s.", min=200, opt=(1000, 500, 3000))
I("MOM", "InpMomVelRefMs", "int", 30000, "Velocity reference window for median (ms)", "Spec: median over 30 s.", min=2000)
I("MOM", "InpMomVelRatio", "double", 1.25, "Min velocity / median velocity", "Spec: >= 1.25x.", min=0.0, opt=(1.0, 0.05, 1.6))
I("MOM", "InpMomAccelMin", "double", 0.20, "Min acceleration (0.20 = +20%)", "Velocity growth versus the previous window. Spec: +20%.", min=-1.0, opt=(0.0, 0.05, 0.4))
I("MOM", "InpMomMicroRangeTicks", "int", 20, "Micro-range length (ticks)", "Spec: 20 ticks.", min=3, opt=(10, 5, 40))
I("MOM", "InpMomBufSpreadMult", "double", 0.15, "Breakout buffer (x spread)", "Buffer = max(0.15 x spread, 0.02 x ATR).", min=0.0)
I("MOM", "InpMomBufAtrMult", "double", 0.02, "Breakout buffer (x ATR M1)", "See above.", min=0.0)
I("MOM", "InpMomUseRoc", "bool", True, "Confirm with ROC direction", "Directional momentum must agree: ROC > 0 for BUY, < 0 for SELL.")
I("MOM", "InpMomRocPeriod", "int", 5, "ROC period (M1 bars)", "Spec: ROC(5).", min=1)
I("MOM", "InpMomRocMin", "double", 0.0, "Min |ROC| (%)", "Minimum absolute ROC value in percent.", min=0.0)
I("MOM", "InpMomUseEma", "bool", False, "Confirm with M1 EMA fast/slow", "Optional internal confirmation (EMA9 > EMA21 for BUY).")
I("MOM", "InpMomEmaFast", "int", 9, "M1 fast EMA period", "Spec Table 18: EMA9.", min=1)
I("MOM", "InpMomEmaSlow", "int", 21, "M1 slow EMA period", "Spec Table 18: EMA21.", min=2)
I("MOM", "InpMomUseAdx", "bool", False, "Confirm with M1 ADX/DI", "Optional: ADX >= threshold and DI in trade direction.")
I("MOM", "InpMomAdxMin", "double", 18.0, "M1 ADX min", "Spec Table 18: initial ADX threshold 18.", min=0.0)
I("MOM", "InpMomM5Context", "ENUM_FTF_CTX_USE", "FTF_CTX_SOFT", "M5 EMA20/50 context", "SOFT = informational only (spec). STRICT = M5 trend must agree.")
I("MOM", "InpMomTpSpreadMult", "double", 1.2, "TP = max(x spread, ...)", "Spec: TP = max(1.2 x spread, 0.18 x ATR).", min=0.0)
I("MOM", "InpMomTpAtrMult", "double", 0.18, "TP = max(..., x ATR M1)", "See above.", min=0.0, opt=(0.12, 0.02, 0.30))
I("MOM", "InpMomSlSpreadMult", "double", 2.0, "SL = max(x spread, ...)", "Spec: SL = max(2 x spread, 0.35 x ATR).", min=0.0)
I("MOM", "InpMomSlAtrMult", "double", 0.35, "SL = max(..., x ATR M1)", "See above.", min=0.0, opt=(0.25, 0.05, 0.50))
I("MOM", "InpMomSignalTtlMs", "int", 500, "Signal validity (ms)", "A Momentum signal older than this is discarded.", min=50)
I("MOM", "InpMomExitEnabled", "bool", True, "Momentum-loss exit ON", "Exit when the internal score drops and ticks invert persistently.")
I("MOM", "InpMomExitScore", "double", 60.0, "Exit when momentum score below", "Spec: score < 60.", min=0.0, max=100.0)
I("MOM", "InpMomExitInversionMs", "int", 500, "Tick inversion persistence (ms)", "Spec: about 500 ms.", min=0)
I("MOM", "InpMomExitTicks", "int", 10, "Inversion window (ticks)", "Ticks used to detect an inversion against the trade.", min=3)
I("MOM", "InpMomTimeStopSec", "int", 45, "Time-stop (s, 0 = off)",
  "Spec: EURUSD 45 s, XAUUSD 30 s. BTCUSD starts at 30 s and MUST be optimized (GBPUSD value not copied).", min=0,
  sym={"EURUSD": 45, "XAUUSD": 30, "BTCUSD": 30}, opt=(20, 5, 90))
I("MOM", "InpMomMaxPositions", "int", 3, "Max simultaneous positions (Momentum)", "Spec G.2: up to 3 per engine, adjustable.", min=0, max=50)
I("MOM", "InpMomBeTriggerPct", "double", 70.0, "Break-even trigger (% of TP distance)", "Spec: 70%.", min=0.0, opt=(50.0, 5.0, 90.0))
I("MOM", "InpMomBeLockPct", "double", 5.0, "Break-even lock (% of TP distance)", "Profit locked when SL moves to break-even.", min=0.0)
I("MOM", "InpMomTrailTriggerPct", "double", 85.0, "Trailing trigger (% of TP distance)", "Spec: 85%.", min=0.0, opt=(70.0, 5.0, 95.0))
I("MOM", "InpMomTrailDistPct", "double", 25.0, "Trailing distance (% of TP distance)", "Short trailing distance.", min=1.0)
I("MOM", "InpMomTrailStepPct", "double", 5.0, "Trailing min step (% of TP distance)", "Minimum SL improvement before a modification is sent.", min=0.0)

# ---- 07 FVG -----------------------------------------------------------------------------------
grp("FVG", "07. ENGINE B - FVG (FAIR VALUE GAP)")
I("FVG", "InpFvgTimeframe", "ENUM_TIMEFRAMES", "PERIOD_M5", "FVG timeframe", "Spec: M5.")
I("FVG", "InpFvgUseM1Refine", "bool", False, "Use M1 for entry precision", "Spec: optional M1 refinement (used by REJECTION mode).")
I("FVG", "InpFvgScanBars", "int", 60, "Bars scanned for FVGs", "History scanned on start and kept in memory.", min=5)
I("FVG", "InpFvgMaxZones", "int", 20, "Max zones kept", "Oldest zones are dropped beyond this number.", min=1, max=100)
I("FVG", "InpFvgMinGapAtr", "double", 0.25, "Min gap size (x ATR of FVG timeframe)", "Gap filter relative to ATR.", min=0.0, opt=(0.10, 0.05, 0.60))
I("FVG", "InpFvgMinGapSpreadMult", "double", 2.0, "Min gap size (x spread)", "Gap must also exceed this multiple of the spread.", min=0.0)
I("FVG", "InpFvgMaxAgeBars", "int", 48, "Max zone age (bars)", "Older zones expire.", min=1, opt=(12, 12, 96))
I("FVG", "InpFvgMaxMitigations", "int", 2, "Max mitigations (returns into zone)", "Zone stops trading after this number of returns.", min=1, opt=(1, 1, 3))
I("FVG", "InpFvgMaxDistanceAtr", "double", 1.5, "Max price distance to zone (x ATR)", "Zones farther than this are ignored for entries.", min=0.0)
I("FVG", "InpFvgEntryMode", "ENUM_FTF_FVG_ENTRY", "FTF_FVG_TOUCH", "Entry mode (TOUCH / CE 50% / REJECTION)", "To be compared in backtests (spec).")
I("FVG", "InpFvgRejectWickPct", "double", 30.0, "REJECTION: min wick (% of candle range)", "Wick into the zone required for REJECTION mode.", min=0.0, max=100.0)
I("FVG", "InpFvgBosRequired", "bool", False, "BOS_REQUIRED (structure confirmation)", "Spec default false. When true, the displacement must create a BOS/CHoCH (next input).")
I("FVG", "InpFvgStructMode", "ENUM_FTF_STRUCT_MODE", "FTF_STRUCT_BOS", "Structure event accepted when required", "BOS, CHoCH or either.")
I("FVG", "InpStructSwingBars", "int", 3, "Swing strength (bars each side)", "Fractal swing definition for BOS/CHoCH and liquidity targets.", min=1)
I("FVG", "InpStructLookbackBars", "int", 120, "Structure lookback (bars)", "Bars scanned for swings.", min=10)
I("FVG", "InpFvgInvalidBufAtr", "double", 0.10, "Invalidation buffer (x ATR)", "Zone invalidated by a close beyond its far edge + buffer.", min=0.0)
I("FVG", "InpFvgInvalidOnClose", "bool", True, "Invalidate on candle close (else on tick)", "ON: needs a closed candle beyond the edge. OFF: first tick beyond the edge + buffer.")
I("FVG", "InpFvgSlMode", "ENUM_FTF_FVG_SL", "FTF_FVGSL_ZONE", "SL anchor", "Beyond zone invalidation edge or beyond the 3-candle swing.")
I("FVG", "InpFvgSlBufSpreadMult", "double", 1.0, "SL buffer (x spread)", "SL buffer = max(x spread, x ATR).", min=0.0)
I("FVG", "InpFvgSlBufAtr", "double", 0.10, "SL buffer (x ATR)", "See above.", min=0.0)
I("FVG", "InpFvgTpMode", "ENUM_FTF_TP_MODE", "FTF_TP_LIQUIDITY", "TP mode", "Next liquidity/swing, ATR multiple or R multiple.")
I("FVG", "InpFvgTpAtrMult", "double", 1.0, "TP ATR multiple", "Used by TP mode ATR.", min=0.0)
I("FVG", "InpFvgTpRR", "double", 1.0, "TP R multiple", "Used by TP mode RR and as liquidity fallback.", min=0.1, opt=(0.5, 0.25, 2.0))
I("FVG", "InpFvgTpMinRR", "double", 0.5, "TP min R (liquidity mode)", "Liquidity targets closer than this R are skipped.", min=0.0)
I("FVG", "InpFvgTpMaxRR", "double", 2.0, "TP max R (liquidity mode)", "Liquidity targets are capped at this R.", min=0.1)
I("FVG", "InpFvgMaxTradesPerZone", "int", 1, "Max trades per zone", "Duplicate protection: one zone = this many trades max.", min=1, max=3)
I("FVG", "InpFvgSignalTtlMs", "int", 1000, "Signal validity (ms)", "An FVG signal older than this is discarded.", min=50)
I("FVG", "InpFvgExitOnInvalidation", "bool", True, "Exit open trade if zone invalidated", "Close FVG positions when their zone is invalidated.")
I("FVG", "InpFvgTimeStopSec", "int", 120, "Time-stop (s, 0 = off)", "Initial ceiling 120 s; may need a higher value for M5 setups (test).", min=0, opt=(60, 60, 600))
I("FVG", "InpFvgMaxPositions", "int", 3, "Max simultaneous positions (FVG)", "Spec G.2: up to 3 per engine.", min=0, max=50)
I("FVG", "InpFvgBeTriggerPct", "double", 70.0, "Break-even trigger (% of TP distance)", "Spec: 70%.", min=0.0)
I("FVG", "InpFvgBeLockPct", "double", 5.0, "Break-even lock (% of TP distance)", "Profit locked at break-even.", min=0.0)
I("FVG", "InpFvgTrailTriggerPct", "double", 85.0, "Trailing trigger (% of TP distance)", "Spec: 85%.", min=0.0)
I("FVG", "InpFvgTrailDistPct", "double", 25.0, "Trailing distance (% of TP distance)", "Short trailing.", min=1.0)
I("FVG", "InpFvgTrailStepPct", "double", 5.0, "Trailing min step (% of TP distance)", "Minimum SL improvement per modification.", min=0.0)

# ---- 08 RANGE ---------------------------------------------------------------------------------
grp("RNG", "08. ENGINE C - RANGE / MEAN REVERSION")
I("RNG", "InpRngTimeframe", "ENUM_TIMEFRAMES", "PERIOD_M1", "Range timeframe (M1 or M5)", "Spec: M1/M5.")
I("RNG", "InpRngLookbackBars", "int", 30, "Range lookback (bars)", "Range = highest high / lowest low of these closed bars.", min=5, opt=(20, 10, 60))
I("RNG", "InpRngAdxPeriod", "int", 14, "ADX period", "Range needs weak/falling ADX.", min=2)
I("RNG", "InpRngAdxMax", "double", 20.0, "Max ADX for a range", "ADX must be below this value.", min=0.0, opt=(15.0, 2.5, 30.0))
I("RNG", "InpRngRequireAdxFalling", "bool", False, "Require falling ADX", "ADX now <= ADX n bars ago.")
I("RNG", "InpRngAdxSlopeBars", "int", 3, "ADX slope bars", "Look-back for 'falling ADX'.", min=1)
I("RNG", "InpRngEmaFast", "int", 20, "Fast EMA period", "EMA20 (spec).", min=1)
I("RNG", "InpRngEmaSlow", "int", 50, "Slow EMA period", "EMA50 (spec).", min=2)
I("RNG", "InpRngEmaSepMaxAtr", "double", 0.30, "Max |EMA20-EMA50| (x ATR)", "Low EMA separation relative to ATR.", min=0.0, opt=(0.1, 0.05, 0.6))
I("RNG", "InpRngMinWidthAtr", "double", 1.0, "Min range width (x ATR)", "Width must exceed this ATR multiple.", min=0.0, opt=(0.5, 0.25, 2.0))
I("RNG", "InpRngMinWidthSpreadMult", "double", 4.0, "Min range width (x spread)", "Width must exceed this multiple of the spread.", min=0.0)
I("RNG", "InpRngMaxWidthAtr", "double", 6.0, "Max range width (x ATR)", "Wider 'ranges' are treated as trends.", min=0.0)
I("RNG", "InpRngMaxDriftPct", "double", 50.0, "Max net drift (% of width)", "No significant directional swing: |close now - close at lookback start| <= this % of width.", min=0.0, max=100.0)
I("RNG", "InpRngMinTouchesPerSide", "int", 1, "Min touches per boundary", "Bars touching each boundary zone (1 = disabled).", min=1)
I("RNG", "InpRngEdgeZonePct", "double", 20.0, "Entry zone near boundary (% of width)", "BUY in the lowest x%, SELL in the highest x%.", min=1.0, max=49.0, opt=(10.0, 5.0, 30.0))
I("RNG", "InpRngConfirmMode", "ENUM_FTF_RANGE_CONFIRM", "FTF_RCONF_EITHER", "Edge confirmation (slowdown / rejection)", "Spec: rejection/slowdown at the boundary.")
I("RNG", "InpRngRejectWickPct", "double", 40.0, "Rejection: min wick (% of candle range)", "Wick towards the boundary on the last closed candle.", min=0.0, max=100.0)
I("RNG", "InpRngTickWindow", "int", 20, "Tick window for buyer/seller return (ticks)", "Ticks used to detect the return of buyers (BUY) or sellers (SELL).", min=5)
I("RNG", "InpRngTickRatioMin", "double", 0.55, "Min returning tick ratio", "BUY: bullish ratio >= x. SELL: bearish ratio >= x.", min=0.5, max=1.0, opt=(0.50, 0.05, 0.70))
I("RNG", "InpRngMaxVelRatio", "double", 2.0, "Max tick velocity ratio (impulse protection)", "No mean reversion against an abnormal impulse (spec: mandatory).", min=0.0)
I("RNG", "InpRngMaxAtrExpansion", "double", 1.6, "Max ATR / median ATR", "Volatility expansion protection.", min=0.0)
I("RNG", "InpRngSlBufSpreadMult", "double", 1.5, "SL buffer beyond boundary (x spread)", "SL buffer = max(x spread, x ATR).", min=0.0)
I("RNG", "InpRngSlBufAtr", "double", 0.15, "SL buffer beyond boundary (x ATR)", "See above.", min=0.0)
I("RNG", "InpRngTpTarget", "ENUM_FTF_RANGE_TP", "FTF_RTP_MID", "TP target", "Range middle (spec first target) or opposite boundary.")
I("RNG", "InpRngTpOffsetPct", "double", 5.0, "TP offset before target (% of width)", "TP placed slightly before the target.", min=0.0, max=40.0)
I("RNG", "InpRngBreakBufAtr", "double", 0.15, "Breakout confirmation buffer (x ATR)", "Close beyond the boundary + buffer = confirmed breakout.", min=0.0)
I("RNG", "InpRngExitOnBreakout", "bool", True, "Exit quickly on confirmed breakout", "Close Range positions on breakout + volatility expansion.")
I("RNG", "InpRngMaxTradesPerTouch", "int", 1, "Max trades per boundary touch", "Duplicate protection.", min=1, max=3)
I("RNG", "InpRngSignalTtlMs", "int", 1000, "Signal validity (ms)", "A Range signal older than this is discarded.", min=50)
I("RNG", "InpRngTimeStopSec", "int", 120, "Time-stop (s, 0 = off)", "Initial ceiling 120 s.", min=0, opt=(60, 30, 300))
I("RNG", "InpRngMaxPositions", "int", 3, "Max simultaneous positions (Range)", "Spec G.2: up to 3 per engine.", min=0, max=50)
I("RNG", "InpRngBeTriggerPct", "double", 70.0, "Break-even trigger (% of TP distance)", "Spec: 70%.", min=0.0)
I("RNG", "InpRngBeLockPct", "double", 5.0, "Break-even lock (% of TP distance)", "Profit locked at break-even.", min=0.0)
I("RNG", "InpRngTrailTriggerPct", "double", 85.0, "Trailing trigger (% of TP distance)", "Spec: 85%.", min=0.0)
I("RNG", "InpRngTrailDistPct", "double", 25.0, "Trailing distance (% of TP distance)", "Short trailing.", min=1.0)
I("RNG", "InpRngTrailStepPct", "double", 5.0, "Trailing min step (% of TP distance)", "Minimum SL improvement per modification.", min=0.0)

# ---- 09 POSITIONS / CONFLICTS -----------------------------------------------------------------
grp("POS", "09. POSITIONS / CONFLICTS / HEDGING")
I("POS", "InpMaxPositionsSymbol", "int", 9, "Max total positions on this symbol (this instance)", "Spec G.2: up to 9 (3 per engine). Never an obligation to open them.", min=1, max=150)
I("POS", "InpAllowOppositeHedge", "bool", False, "OPPOSITE_HEDGE (allow BUY and SELL together)", "Spec default: false.")
I("POS", "InpSameDirMode", "ENUM_FTF_SAMEDIR", "FTF_SAMEDIR_STACK", "Same-direction signals", "Stack within limits, or ignore when a same-direction position exists.")
I("POS", "InpConflictWindowMs", "int", 300, "Opposite-signal conflict window (ms)", "BUY and SELL from different engines within this window = conflict.", min=0)
I("POS", "InpConflictHoldMs", "int", 300, "Entry block after a conflict (ms)", "Spec: block a few hundred ms, then re-evaluate.", min=0)
I("POS", "InpDupMinDistAtr", "double", 0.10, "Min distance between same-engine entries (x ATR M1)", "Anti-duplicate distance for stacked entries of one engine.", min=0.0)
I("POS", "InpMinEntrySpacingMs", "int", 0, "Min time between any two entries (ms, 0 = off)", "Global spacing between entries of this instance.", min=0)
I("POS", "InpHardMaxHoldSec", "int", 120, "Hard max holding time, all engines (s, 0 = off)", "Spec: 120 s initially, adjustable.", min=0)
I("POS", "InpMinModifyIntervalMs", "int", 300, "Min interval between SL modifications (ms)", "Avoids flooding the server with modifications.", min=0)
I("POS", "InpTwoStepStops", "bool", False, "Send SL/TP after the fill (ECN brokers)", "Open without SL/TP, then attach them immediately.")

# ---- 10 RISK ----------------------------------------------------------------------------------
grp("RISK", "10. RISK MANAGEMENT")
I("RISK", "InpRiskMode", "ENUM_FTF_RISK_MODE", "FTF_RISK_PCT_EQUITY", "RISK_MODE", "Fixed lot, % of balance or % of equity, always computed on the REAL SL distance.")
I("RISK", "InpFixedLot", "double", 0.01, "Fixed lot", "Used in Fixed-lot mode.", min=0.0)
I("RISK", "InpRiskPercent", "double", 0.25, "Risk per trade (%)", "Money lost if the SL is hit, in % of balance or equity.", min=0.0, opt=(0.1, 0.1, 1.0))
I("RISK", "InpMaxRiskPercent", "double", 1.0, "Max risk per trade - hard cap (%)", "Applies in every mode, including martingale.", min=0.0)
I("RISK", "InpMaxLotPerTrade", "double", 0.0, "Max lot per trade (0 = broker max)", "Hard lot cap.", min=0.0)
I("RISK", "InpAllowMinLotOverRisk", "bool", False, "Allow broker min lot even if above max risk", "OFF = refuse the trade when the minimum lot already exceeds the hard cap.")
I("RISK", "InpMaxOpenRiskPct", "double", 5.0, "Max total open risk, this instance (%)", "Sum of risk at SL of all open positions of this instance.", min=0.0)
I("RISK", "InpMaxTotalLots", "double", 0.0, "Max total open lots, this instance (0 = off)", "Total exposure ceiling in lots.", min=0.0)
I("RISK", "InpStopsPolicy", "ENUM_FTF_STOPS_POLICY", "FTF_STOPS_ADJUST", "Broker stops-level policy", "Widen to broker minimum (and re-size), or reject.")
I("RISK", "InpMaxSlTpRatio", "double", 2.0, "SL/TP ratio guard (max SL / TP, 0 = off)", "Spec: SL/TP <= 2. Signals above are refused, never 'fixed' by shrinking TP.", min=0.0)
I("RISK", "InpMartingaleEnabled", "bool", False, "Martingale ON (optional)", "OFF by default. Even when ON a NEW valid setup is required and hard caps apply.")
I("RISK", "InpMartingaleMult", "double", 1.5, "Martingale multiplier", "Risk x multiplier ^ step after each loss (per engine).", min=1.0)
I("RISK", "InpMartingaleMaxSteps", "int", 3, "Martingale max steps", "Step resets after a win or after this many steps.", min=0)

# ---- 11 DRAWDOWN ------------------------------------------------------------------------------
grp("DD", "11. EQUITY DRAWDOWN PROTECTION (10% PAUSE)")
I("DD", "InpDdEnabled", "bool", True, "Equity drawdown pause ON", "At the threshold: STOP new entries, re-activate and verify safeties, restart automatically after the pause.")
I("DD", "InpDdPausePct", "double", 10.0, "Drawdown threshold (%)", "Spec: 10%.", min=0.1)
I("DD", "InpDdPauseSec", "int", 10, "Pause length (s)", "Spec: 10 s. Strict timer - never waits indefinitely.", min=1)
I("DD", "InpDdReference", "ENUM_FTF_DD_REF", "FTF_DDREF_PEAK_EQUITY", "Drawdown reference", "After each pause the reference is re-based to the current equity, so the next pause needs a further drop.")

# ---- 12 NEWS ----------------------------------------------------------------------------------
grp("NEWS", "12. NEWS FILTER (B.1)")
I("NEWS", "InpNewsEnabled", "bool", True, "NEWS_FILTER ON", "No NEW entries inside the news window; open positions are still managed.")
I("NEWS", "InpNewsSource", "ENUM_FTF_NEWS_SOURCE", "FTF_NEWS_AUTO", "News source", "MT5 calendar (live), CSV file (tester/MT4/MT5), or web XML feed (live).")
I("NEWS", "InpNewsMinImpact", "ENUM_FTF_IMPACT", "FTF_IMPACT_HIGH", "Min impact", "Events at or above this impact block entries.")
I("NEWS", "InpNewsCurrencies", "string", "AUTO", "Currencies (AUTO or list e.g. USD,EUR)", "AUTO = currencies of the chart symbol (EURUSD: EUR,USD; XAUUSD and BTCUSD: USD).")
I("NEWS", "InpNewsKeywords", "string", "Non-Farm,Nonfarm,NFP,CPI,FOMC,Federal Funds,Interest Rate,Rate Decision,Fed Chair",
  "Keywords always blocked (any impact)", "Comma list. Events whose title contains a keyword block entries even below the min impact.")
I("NEWS", "InpNewsMinsBefore", "int", 10, "Block minutes BEFORE news", "Window start.", min=0)
I("NEWS", "InpNewsMinsAfter", "int", 10, "Block minutes AFTER news", "Window end.", min=0)
I("NEWS", "InpNewsCsvFile", "string", "FranckyTriFlux\\news.csv", "News CSV file (in Files or Common\\Files)", "Format: yyyy.mm.dd hh:mi;CCY;HIGH|MEDIUM|LOW;Title (times in UTC by default).")
I("NEWS", "InpNewsCsvCommon", "bool", True, "News CSV is in Common\\Files", "Common folder is shared by MT4, MT5 and the tester agents.")
I("NEWS", "InpNewsCsvUtc", "bool", True, "News CSV times are UTC", "OFF = times are broker server time.")
I("NEWS", "InpNewsWebUrl", "string", "https://nfs.faireconomy.media/ff_calendar_thisweek.xml", "Web XML feed URL", "Must be added in Tools > Options > Expert Advisors > Allow WebRequest.")
I("NEWS", "InpNewsRefreshMin", "int", 60, "News refresh interval (min)", "Reload period for the news list.", min=1)
I("NEWS", "InpNewsDraw", "bool", True, "Draw news windows on chart", "Shows blocked windows as shaded areas.")

# ---- 13 SESSIONS ------------------------------------------------------------------------------
grp("SESS", "13. SESSIONS / DAYS (B.2)")
I("SESS", "InpSessionEnabled", "bool", False, "SESSION_FILTER ON", "OFF = trade 24h on every day the broker quotes (needed for BTCUSD weekends).")
I("SESS", "InpSessionPreset", "ENUM_FTF_SESSION_PRESET", "FTF_SESS_LONDON_NY", "Session preset", "Presets are in UTC. CUSTOM uses the hours below.")
I("SESS", "InpSessionTimeBasis", "ENUM_FTF_TIME_BASIS", "FTF_TIME_SERVER", "CUSTOM hours time basis", "Server time or UTC.")
I("SESS", "InpTradingStart", "string", "08:00", "TradingStart (HH:MM)", "CUSTOM window 1 start.")
I("SESS", "InpTradingEnd", "string", "22:00", "TradingEnd (HH:MM)", "CUSTOM window 1 end (may wrap past midnight).")
I("SESS", "InpTradingStart2", "string", "", "TradingStart 2 (HH:MM, empty = none)", "Optional CUSTOM window 2.")
I("SESS", "InpTradingEnd2", "string", "", "TradingEnd 2 (HH:MM)", "Optional CUSTOM window 2 end.")
I("SESS", "InpTradeMonday", "bool", True, "Trade Monday", "Day filter (used when the session filter is ON).")
I("SESS", "InpTradeTuesday", "bool", True, "Trade Tuesday", "")
I("SESS", "InpTradeWednesday", "bool", True, "Trade Wednesday", "")
I("SESS", "InpTradeThursday", "bool", True, "Trade Thursday", "")
I("SESS", "InpTradeFriday", "bool", True, "Trade Friday", "")
I("SESS", "InpTradeSaturday", "bool", False, "Trade Saturday", "BTCUSD preset sets ON.", sym={"EURUSD": False, "XAUUSD": False, "BTCUSD": True})
I("SESS", "InpTradeSunday", "bool", False, "Trade Sunday", "BTCUSD preset sets ON.", sym={"EURUSD": False, "XAUUSD": False, "BTCUSD": True})

# ---- 14 ROLLOVER ------------------------------------------------------------------------------
grp("ROLL", "14. ROLLOVER / DAY CHANGE (B.3)")
I("ROLL", "InpRolloverEnabled", "bool", True, "ROLLOVER_FILTER ON", "No NEW entries around the daily rollover; spread filter stays active.")
I("ROLL", "InpRolloverTime", "string", "00:00", "Rollover time (server, HH:MM)", "Most brokers roll over at 00:00 server time.")
I("ROLL", "InpRolloverMinsBefore", "int", 10, "Block minutes BEFORE rollover", "", min=0)
I("ROLL", "InpRolloverMinsAfter", "int", 15, "Block minutes AFTER rollover", "", min=0)

# ---- 15 TIME ZONE -----------------------------------------------------------------------------
grp("TZ", "15. TIME ZONE (SERVER / UTC)")
I("TZ", "InpGmtMode", "ENUM_FTF_GMT_MODE", "FTF_GMT_AUTO", "Broker GMT offset mode", "AUTO live = server time - GMT. Strategy Tester always uses the MANUAL values.")
I("TZ", "InpGmtOffsetHours", "int", 2, "Manual broker GMT offset (winter, hours)", "Typical: 2 (GMT+2 winter / GMT+3 summer).", min=-12, max=14)
I("TZ", "InpGmtUseUsDst", "bool", True, "Manual offset follows US DST (+1h)", "Adds 1 h between 2nd Sunday of March and 1st Sunday of November (New-York-close brokers).")

# ---- 16 CONSECUTIVE LOSSES --------------------------------------------------------------------
grp("CONS", "16. CONSECUTIVE LOSS PROTECTION (B.4)")
I("CONS", "InpConsecEnabled", "bool", True, "CONSECUTIVE_LOSS_PROTECTION ON", "After X losses in a row: cooldown Y minutes; then a NEW setup is required.")
I("CONS", "InpConsecMaxLosses", "int", 3, "Consecutive losses X", "", min=1, opt=(2, 1, 6))
I("CONS", "InpConsecCooldownMin", "int", 15, "Cooldown Y (minutes)", "", min=1, opt=(5, 5, 60))
I("CONS", "InpConsecScope", "ENUM_FTF_LOSS_SCOPE", "FTF_SCOPE_ENGINE", "Scope", "Per engine or whole instance (one instance = one symbol).")

# ---- 17 EXECUTION -----------------------------------------------------------------------------
grp("EXEC", "17. EXECUTION / RETRIES / QUALITY (B.8)")
I("EXEC", "InpMaxDeviationPts", "int", 0, "Max slippage / deviation (points, 0 = auto)", "Auto = spread x multiplier below.", min=0)
I("EXEC", "InpAutoDeviationSpreadMult", "double", 1.0, "Auto deviation (x spread)", "", min=0.1)
I("EXEC", "InpMaxRetries", "int", 3, "Max retries per order", "Only for transient errors (requote, off quotes, timeout...).", min=0, max=10)
I("EXEC", "InpRetryDelayMs", "int", 150, "Delay between retries (ms)", "Non-blocking: other positions keep being managed.", min=0)
I("EXEC", "InpRetryMaxDriftAtr", "double", 0.15, "Max price drift before a retry (x ATR M1)", "Retry refused if price moved more than this since the signal.", min=0.0)
I("EXEC", "InpFatalErrorCooldownSec", "int", 60, "Pause after a permanent broker error (s)", "E.g. no money, trading disabled, market closed.", min=0)
I("EXEC", "InpExecQualityAction", "ENUM_FTF_EXECQ_ACTION", "FTF_EXECQ_BLOCK", "Execution-quality action", "What to do when average slippage/latency is out of tolerance.")
I("EXEC", "InpExecQualityWindow", "int", 20, "Execution-quality window (trades)", "Rolling number of fills averaged.", min=3)
I("EXEC", "InpMaxAvgSlippageSpreadMult", "double", 1.5, "Max avg adverse slippage (x avg spread, 0 = off)", "", min=0.0)
I("EXEC", "InpMaxAvgLatencyMs", "int", 0, "Max avg order latency (ms, 0 = off)", "Latency target <= 10 ms is MEASURED and reported, not assumed.", min=0)
I("EXEC", "InpExecQualityCooldownSec", "int", 120, "Execution-quality cooldown (s)", "", min=0)
I("EXEC", "InpExecQualityLotFactor", "double", 0.5, "Lot factor when quality is poor", "Used by REDUCE_LOT action.", min=0.01, max=1.0)

# ---- 18 MULTI-INSTANCE / EXPOSURE -------------------------------------------------------------
grp("MI", "18. MULTI-INSTANCE / AGGREGATE EXPOSURE (B.6)")
I("MI", "InpMiGuard", "ENUM_FTF_MI_GUARD", "FTF_MI_ISOLATE", "MULTI_INSTANCE_GUARD", "An instance NEVER manages another instance's orders. ISOLATE also blocks a second chart using the same Instance ID.")
I("MI", "InpMiDupWindowSec", "int", 10, "Cross-instance duplicate window (s)", "Used by BLOCK_DUPLICATES.", min=1)
I("MI", "InpExposureMode", "ENUM_FTF_EXPOSURE_MODE", "FTF_EXPO_CURRENCY", "Aggregate exposure mode", "Controls total open risk across EURUSD / XAUUSD / BTCUSD on the same account.")
I("MI", "InpExposureFamilyOnly", "bool", True, "Count only FRANCKY positions (same magic base)", "OFF = count every position on the account.")
I("MI", "InpMaxAccountRiskPct", "double", 10.0, "Max open risk all symbols (% equity)", "Gross risk at SL of all counted positions.", min=0.0)
I("MI", "InpMaxCurrencyRiskPct", "double", 6.0, "Max net risk per currency, e.g. USD (% equity)", "Net long/short risk per currency leg.", min=0.0)
I("MI", "InpCorrBars", "int", 288, "Correlation lookback (M5 bars)", "Used by correlation mode (288 = 1 day).", min=20)
I("MI", "InpMaxCorrRiskPct", "double", 6.0, "Max correlation-adjusted risk (% equity)", "sqrt(r' C r) using measured correlations.", min=0.0)

# ---- 19 STATE ---------------------------------------------------------------------------------
grp("STATE", "19. RESTART RECOVERY (B.7)")
I("STATE", "InpStateEnabled", "bool", True, "Save and restore state after restart", "Cooldowns, pauses, martingale steps, traded setups, position metadata.")
I("STATE", "InpRestartGraceSec", "int", 5, "No new entries after start (s)", "Lets data and positions resynchronise after a restart/reconnection.", min=0)

# ---- 20 LOGGING -------------------------------------------------------------------------------
grp("LOG", "20. LOGGING / STATISTICS")
I("LOG", "InpLogLevel", "ENUM_FTF_LOG_LEVEL", "FTF_LOG_INFO", "Log level", "DEBUG/TRACE for bug hunting (large files in tester).")
I("LOG", "InpLogToJournal", "bool", True, "Print to Experts journal", "")
I("LOG", "InpLogToFile", "bool", True, "Write text log file", "")
I("LOG", "InpLogCsv", "bool", True, "Write CSV journals (signals, trades, events, stats)", "Exportable logs (acceptance criterion).")
I("LOG", "InpLogCommon", "bool", True, "Log files in Common\\Files", "Easy to find after backtests: %APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\FranckyTriFlux.")
I("LOG", "InpLogSignals", "bool", True, "Log every signal decision", "One CSV row per accepted/rejected setup.")
I("LOG", "InpLogThrottleMs", "int", 2000, "Throttle repeated messages (ms)", "Identical rejections are summarised instead of repeated.", min=0)
I("LOG", "InpLogInOptimization", "bool", False, "Write files during optimization", "Keep OFF: optimization runs thousands of passes.")
I("LOG", "InpStatsEveryMin", "int", 60, "Write stats summary every (min)", "Also written when the EA stops.", min=1)

# ---- 21 CHART ---------------------------------------------------------------------------------
grp("UI", "21. CHART DISPLAY")
I("UI", "InpShowPanel", "bool", True, "Show dashboard panel", "")
I("UI", "InpPanelCorner", "ENUM_BASE_CORNER", "CORNER_LEFT_UPPER", "Panel corner", "")
I("UI", "InpPanelX", "int", 10, "Panel X offset (px)", "", min=0)
I("UI", "InpPanelY", "int", 20, "Panel Y offset (px)", "", min=0)
I("UI", "InpPanelFontSize", "int", 8, "Panel font size", "", min=6, max=20)
I("UI", "InpPanelDark", "bool", True, "Dark panel theme", "")
I("UI", "InpPanelRefreshMs", "int", 250, "Panel refresh (ms)", "", min=50)
I("UI", "InpDrawTrades", "bool", True, "Draw entries / exits", "Arrows, labels (engine, reason) and entry-exit lines.")
I("UI", "InpDrawZones", "bool", True, "Draw FVG zones, ranges, micro-ranges", "")
I("UI", "InpDrawRejected", "bool", False, "Draw rejected signals", "Small grey markers with the rejection reason (busy charts).")
I("UI", "InpMaxChartObjects", "int", 600, "Max chart objects", "Oldest markers are deleted beyond this number.", min=50)
I("UI", "InpKeepObjectsOnExit", "bool", True, "Keep drawings when the EA stops (tester review)", "Live charts are always cleaned on removal unless this is ON.")

# ---- 22 TESTER --------------------------------------------------------------------------------
grp("TEST", "22. TESTER / OPTIMIZATION / STRESS")
I("TEST", "InpOptCriterion", "ENUM_FTF_OPT_CRITERION", "FTF_OPT_ROBUST", "Custom optimization criterion", "Returned by OnTester (choose 'Custom max' in the tester).")
I("TEST", "InpOptMinTrades", "int", 30, "Min trades for a valid pass", "Passes with fewer trades score 0.", min=0)
I("TEST", "InpStressExtraSpreadPts", "int", 0, "Stress: extra spread (points)", "Degraded-execution test: added to the spread in every decision.", min=0)
I("TEST", "InpStressCommissionPerLot", "double", 0.0, "Stress: extra commission per lot (money)", "Subtracted in the EA statistics (net after stress).", min=0.0)

# ----------------------------------------------------------------------------------------------
# TEST STAGES (spec C.2): engine ON/OFF combinations
# ----------------------------------------------------------------------------------------------
STAGES = {
    "MOMENTUM_ONLY": {"InpMomEnabled": True, "InpFvgEnabled": False, "InpRngEnabled": False},
    "FVG_ONLY": {"InpMomEnabled": False, "InpFvgEnabled": True, "InpRngEnabled": False},
    "RANGE_ONLY": {"InpMomEnabled": False, "InpFvgEnabled": False, "InpRngEnabled": True},
    "COMBINED": {"InpMomEnabled": True, "InpFvgEnabled": True, "InpRngEnabled": True},
}
STAGE_OPT_PREFIX = {"MOMENTUM_ONLY": "InpMom", "FVG_ONLY": "InpFvg", "RANGE_ONLY": "InpRng", "COMBINED": None}
