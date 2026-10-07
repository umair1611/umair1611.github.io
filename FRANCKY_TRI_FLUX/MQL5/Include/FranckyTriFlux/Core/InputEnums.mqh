//+------------------------------------------------------------------+
//| FRANCKY TRI-FLUX HFT-style Ultra Scalping                          |
//| GENERATED FILE - DO NOT EDIT BY HAND.                              |
//| Source of truth: tools/ftf_spec.py  ->  python3 tools/generate.py |
//+------------------------------------------------------------------+

#ifndef FTF_INPUT_ENUMS_MQH
#define FTF_INPUT_ENUMS_MQH

// Reactivity profile. No NORMAL mode exists (spec Table 3).
enum ENUM_FTF_MODE
  {
   FTF_MODE_SPEED=0, // SPEED (delay 1500 ms)
   FTF_MODE_AGGRESSIVE=1, // AGGRESSIVE (delay 750 ms)
   FTF_MODE_ULTRA=2 // ULTRA (delay 300 ms)
  };

// H1 context filter (spec section A).
enum ENUM_FTF_H1_FILTER
  {
   FTF_H1_OFF=0, // OFF - H1 ignored
   FTF_H1_SOFT=1, // SOFT - context only, never blocks
   FTF_H1_STRICT=2 // STRICT - may block entries against clear H1 trend
  };

// How the SPEED/AGGRESSIVE/ULTRA delay is applied (open question Q2).
enum ENUM_FTF_DELAY_USAGE
  {
   FTF_DELAY_COOLDOWN=0, // Cooldown between entries of the same engine
   FTF_DELAY_CONFIRM=1, // Signal must stay valid during the delay
   FTF_DELAY_BOTH=2 // Both cooldown and confirmation
  };

// Same-direction signal policy (Table 12).
enum ENUM_FTF_SAMEDIR
  {
   FTF_SAMEDIR_STACK=0, // Stack within the limits
   FTF_SAMEDIR_IGNORE=1 // Ignore if a same-direction position exists
  };

// Position sizing mode (B.5).
enum ENUM_FTF_RISK_MODE
  {
   FTF_RISK_FIXED_LOT=0, // Fixed lot
   FTF_RISK_PCT_BALANCE=1, // % of balance at real SL distance
   FTF_RISK_PCT_EQUITY=2 // % of equity at real SL distance
  };

// What to do when SL/TP is closer than the broker stops level.
enum ENUM_FTF_STOPS_POLICY
  {
   FTF_STOPS_ADJUST=0, // Widen SL/TP to broker minimum and re-size
   FTF_STOPS_REJECT=1 // Reject the signal
  };

// Reference used to measure the 10% equity drawdown.
enum ENUM_FTF_DD_REF
  {
   FTF_DDREF_PEAK_EQUITY=0, // Peak equity (high-water mark)
   FTF_DDREF_START_BALANCE=1, // Balance when EA started
   FTF_DDREF_DAY_START_EQUITY=2 // Equity at start of the server day
  };

// News data source (B.1).
enum ENUM_FTF_NEWS_SOURCE
  {
   FTF_NEWS_AUTO=0, // AUTO (MT5 live: calendar, else CSV)
   FTF_NEWS_CALENDAR=1, // MT5 built-in economic calendar
   FTF_NEWS_CSV=2, // CSV file (works in tester, MT4 and MT5)
   FTF_NEWS_WEB=3, // Web XML feed (live only, URL must be allowed)
   FTF_NEWS_CALENDAR_AND_CSV=4 // MT5 calendar + CSV file
  };

// Minimum news impact that blocks entries.
enum ENUM_FTF_IMPACT
  {
   FTF_IMPACT_LOW=1, // Low and above
   FTF_IMPACT_MEDIUM=2, // Medium and above
   FTF_IMPACT_HIGH=3 // High only
  };

// Time basis of custom session hours.
enum ENUM_FTF_TIME_BASIS
  {
   FTF_TIME_SERVER=0, // Broker server time
   FTF_TIME_UTC=1 // UTC / GMT
  };

// Session window preset (B.2).
enum ENUM_FTF_SESSION_PRESET
  {
   FTF_SESS_CUSTOM=0, // CUSTOM (Trading start/end below)
   FTF_SESS_LONDON=1, // LONDON 07:00-16:00 UTC
   FTF_SESS_NEWYORK=2, // NEW YORK 12:00-21:00 UTC
   FTF_SESS_LONDON_NY=3, // LONDON + NEW YORK 07:00-21:00 UTC
   FTF_SESS_ASIA=4, // ASIA 23:00-08:00 UTC
   FTF_SESS_ASIA_LONDON_NY=5 // ASIA + LONDON + NEW YORK 23:00-21:00 UTC
  };

// How the broker GMT offset is obtained.
enum ENUM_FTF_GMT_MODE
  {
   FTF_GMT_AUTO=0, // AUTO (live: server-GMT; tester: manual)
   FTF_GMT_MANUAL=1 // MANUAL (offset below)
  };

// Consecutive-loss counting scope (B.4).
enum ENUM_FTF_LOSS_SCOPE
  {
   FTF_SCOPE_ENGINE=0, // Per engine
   FTF_SCOPE_INSTANCE=1 // Whole instance (symbol)
  };

// Action when execution quality is out of tolerance (Table 13).
enum ENUM_FTF_EXECQ_ACTION
  {
   FTF_EXECQ_LOG_ONLY=0, // Log only
   FTF_EXECQ_BLOCK=1, // Block new entries for a cooldown
   FTF_EXECQ_REDUCE_LOT=2 // Reduce lot size
  };

// Multi-instance guard (Table 12).
enum ENUM_FTF_MI_GUARD
  {
   FTF_MI_OFF=0, // OFF (own-magic isolation only)
   FTF_MI_ISOLATE=1, // ISOLATE + block duplicate Instance ID
   FTF_MI_BLOCK_DUPLICATES=2 // ISOLATE + block cross-instance duplicate entries
  };

// Aggregate exposure guard (B.6).
enum ENUM_FTF_EXPOSURE_MODE
  {
   FTF_EXPO_OFF=0, // OFF
   FTF_EXPO_CURRENCY=1, // Currency decomposition (net USD/EUR/XAU/BTC risk)
   FTF_EXPO_CORRELATION=2 // Currency + measured correlation
  };

// Tick velocity metric.
enum ENUM_FTF_VEL_METRIC
  {
   FTF_VEL_TICKS=0, // Tick count per window
   FTF_VEL_PRICE_PATH=1 // Price path (sum of |price changes|)
  };

// Use of an internal context confirmation.
enum ENUM_FTF_CTX_USE
  {
   FTF_CTX_OFF=0, // OFF
   FTF_CTX_SOFT=1, // SOFT (log only)
   FTF_CTX_STRICT=2 // STRICT (must agree)
  };

// FVG entry mode.
enum ENUM_FTF_FVG_ENTRY
  {
   FTF_FVG_TOUCH=0, // TOUCH - first touch of the zone edge
   FTF_FVG_CE=1, // CE - 50% of the gap
   FTF_FVG_REJECTION=2 // REJECTION - candle rejects the zone
  };

// FVG stop-loss anchor.
enum ENUM_FTF_FVG_SL
  {
   FTF_FVGSL_ZONE=0, // Beyond the FVG invalidation edge
   FTF_FVGSL_SWING=1 // Beyond the 3-candle swing extreme
  };

// FVG take-profit mode.
enum ENUM_FTF_TP_MODE
  {
   FTF_TP_LIQUIDITY=0, // Next liquidity / swing (fallback R multiple)
   FTF_TP_ATR=1, // ATR multiple
   FTF_TP_RR=2 // R multiple of SL distance
  };

// Structure event used when BOS_REQUIRED = true.
enum ENUM_FTF_STRUCT_MODE
  {
   FTF_STRUCT_BOS=1, // BOS
   FTF_STRUCT_CHOCH=2, // CHoCH
   FTF_STRUCT_ANY=3 // BOS or CHoCH
  };

// Range take-profit target.
enum ENUM_FTF_RANGE_TP
  {
   FTF_RTP_MID=0, // Range middle
   FTF_RTP_OPPOSITE=1 // Opposite boundary
  };

// Range edge confirmation.
enum ENUM_FTF_RANGE_CONFIRM
  {
   FTF_RCONF_NONE=0, // None
   FTF_RCONF_SLOWDOWN=1, // Tick slowdown
   FTF_RCONF_REJECTION=2, // Candle rejection wick
   FTF_RCONF_EITHER=3, // Slowdown OR rejection
   FTF_RCONF_BOTH=4 // Slowdown AND rejection
  };

// Supported-symbol check (EURUSD / XAUUSD / BTCUSD).
enum ENUM_FTF_SYMBOL_CHECK
  {
   FTF_SYMCHK_OFF=0, // OFF
   FTF_SYMCHK_WARN=1, // WARN on unsupported symbol
   FTF_SYMCHK_BLOCK=2 // BLOCK entries on unsupported symbol
  };

// Log verbosity.
enum ENUM_FTF_LOG_LEVEL
  {
   FTF_LOG_OFF=0, // OFF
   FTF_LOG_ERROR=1, // ERROR
   FTF_LOG_WARN=2, // WARN
   FTF_LOG_INFO=3, // INFO
   FTF_LOG_DEBUG=4, // DEBUG
   FTF_LOG_TRACE=5 // TRACE (very verbose)
  };

// Value returned by OnTester() for custom optimization.
enum ENUM_FTF_OPT_CRITERION
  {
   FTF_OPT_NET_PROFIT=0, // Net profit
   FTF_OPT_PROFIT_FACTOR=1, // Profit factor
   FTF_OPT_EXPECTANCY=2, // Expectancy per trade
   FTF_OPT_WINRATE=3, // Win rate (with min trades)
   FTF_OPT_ROBUST=4 // Robust score (expectancy, PF, DD, trades)
  };

#endif // FTF_INPUT_ENUMS_MQH
