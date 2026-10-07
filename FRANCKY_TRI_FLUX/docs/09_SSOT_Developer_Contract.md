# 09 - Single Source of Truth (SSOT) - Developer & Agent Contract

> **Read this first before changing any code.** This file is the contract between all modules of
> FRANCKY TRI-FLUX. Every class name, method signature, struct field, file path, CSV column and
> reason code listed here is binding for the MT5 **and** the MT4 version. When the code changes, this
> file changes in the same commit.
>
> Companion sources of truth:
> * `tools/ftf_spec.py` - every enum shown in the Inputs dialog and every input parameter
>   (generated into `Inputs.mqh`, `Core/InputEnums.mqh`, `Core/Config.mqh`, `.set`, `.ini`, docs/05).
> * `docs/03_Strategy_Logic.md` - exact trading rules of the 3 engines.

---

## 1. Design principles

1. **One shared Core, two thin platform layers.** All strategy, risk, protection, logging and UI
   logic lives in `Include/FranckyTriFlux/Core/*.mqh` and is **byte-identical** in the MQL5 and
   MQL4 trees (`python3 tools/check_core.py` verifies this). Everything that differs between
   MetaTrader 5 and MetaTrader 4 (orders, positions, history, indicators, ticks, symbol/account
   info, calendar) is behind one class, `CPlatform`, implemented twice:
   `MQL5/Include/FranckyTriFlux/Platform/Platform.mqh` and `MQL4/.../Platform/Platform.mqh`.
2. **Event-driven, tick-by-tick (HFT-style retail).** `OnTick` runs the full pipeline. `OnTimer`
   (default 250 ms) runs the same housekeeping when no tick arrives (pause expiry, retries, UI,
   state save). The MT4 Strategy Tester does not call `OnTimer`, so nothing critical depends on it.
3. **Three independent engines.** An engine never reads another engine's state. No global score.
   Each engine returns its own `SSignal` with its own SL/TP/invalidation/reason.
4. **Filters and protections never touch strategy logic.** They can only accept/reject a signal
   (with a reason code) or manage exits. Rejected setups are still counted (setups/day statistics).
5. **One instance = one chart symbol.** All trading calls use the chart symbol captured at
   `OnInit`. Other symbols are only *read* by the aggregate-exposure guard (risk), never traded.
6. **Isolation.** An instance only modifies/closes positions whose magic number belongs to its own
   magic set `{base+ID*10+1, +2, +3}` **and** whose symbol is the chart symbol.
7. **Everything is logged with a reason.** Every rejection has a reason code, every exit an exit
   code, every protection state change an event row.

## 2. File structure

```
FRANCKY_TRI_FLUX/
  MQL5/Experts/FranckyTriFlux/FranckyTriFlux.mq5         main EA (event handlers only)
  MQL5/Include/FranckyTriFlux/Inputs.mqh                 GENERATED inputs (input group)
  MQL5/Include/FranckyTriFlux/Platform/Platform.mqh      CPlatform for MT5 (CTrade, CopyTicks, handles, calendar)
  MQL5/Include/FranckyTriFlux/Core/*.mqh                 shared core (identical in MQL4 tree)
  MQL5/Scripts/FranckyTriFlux/FranckyNewsExporter.mq5    exports MT5 calendar -> Common\Files news.csv
  MQL5/Presets/FranckyTriFlux/*.set                      GENERATED presets (UTF-16LE)
  MQL4/Experts/FranckyTriFlux/FranckyTriFlux.mq4         main EA MT4 (#property strict)
  MQL4/Include/FranckyTriFlux/Inputs.mqh                 GENERATED inputs (separator strings)
  MQL4/Include/FranckyTriFlux/Platform/Platform.mqh      CPlatform for MT4 (OrderSend, iATR, ...)
  MQL4/Include/FranckyTriFlux/Core/*.mqh                 shared core (identical)
  MQL4/Presets/FranckyTriFlux/*.set                      GENERATED presets (ANSI)
  Tester/MT5/*.ini, Tester/MT5/sets/*.set                GENERATED tester configs
  Tester/MT4/*.ini, Tester/MT4/sets/*.set
  tools/ftf_spec.py   tools/generate.py   tools/check_core.py   tools/analyze_logs.py
  docs/ ...
```

### 2.1 Core files and include order (each file has an include guard `FTF_<NAME>_MQH`)

| # | File | Contents | Depends on |
|---|------|----------|-----------|
| 1 | `Core/InputEnums.mqh` | GENERATED enums for inputs | - |
| 2 | `Core/Defines.mqh` | constants, internal enums, reason/exit/event codes | 1 |
| 3 | `Core/Types.mqh` | structs `STick SSignal STrackedPos SClosedTrade SPosInfo SExecResult SNewsEvent SSymbolSpec` | 2 |
| 4 | `Core/Utils.mqh` | free functions `FTF_*` | 2,3 |
| 5 | `Core/Config.mqh` | GENERATED `CConfig` | 1 (+ Inp* globals) |
| 6 | `Core/Logger.mqh` | `CLogger` | 2,4 |
| 7 | `Core/Journal.mqh` | `CTradeJournal` (CSV signals/trades/events) | 3,4,6 |
| 8 | `Core/Stats.mqh` | `CStats` | 2,4 |
| 9 | `Core/StateStore.mqh` | `CStateStore` | 4,6 |
| 10 | `Platform/Platform.mqh` | `CPlatform` (MT5 or MT4 implementation) | 3,4,6 |
| 11 | `Core/Clock.mqh` | `CClock` server/UTC conversion | 5,10 |
| 12 | `Core/TickBuffer.mqh` | `CTickBuffer` | 3,4 |
| 13 | `Core/MarketData.mqh` | `CMarketData` | 5,6,10,12 |
| 14 | `Core/H1Context.mqh` | `CH1Context` | 5,6,10 |
| 15 | `Core/Structure.mqh` | `CStructure` (swings, BOS/CHoCH) | 10 |
| 16 | `Core/ChartUI.mqh` | `CChartUI` | 5,6 |
| 17 | `Core/Context.mqh` | `CFtfContext` (service locator) | 5..16 |
| 18 | `Core/EngineBase.mqh` | `CEngineBase` | 17 |
| 19 | `Core/EngineMomentum.mqh` | `CEngineMomentum` | 18 |
| 20 | `Core/EngineFVG.mqh` | `CEngineFVG` | 18,15 |
| 21 | `Core/EngineRange.mqh` | `CEngineRange` | 18 |
| 22 | `Core/EngineManager.mqh` | `CEngineManager` | 19,20,21 |
| 23 | `Core/PositionTracker.mqh` | `CPositionTracker` | 17 |
| 24 | `Core/Protections.mqh` | `CDrawdownGuard CConsecLossGuard CExecQualityGuard` | 17 |
| 25 | `Core/Filters.mqh` | `CNewsFilter CSessionFilter CRolloverFilter` | 17 |
| 26 | `Core/RiskManager.mqh` | `CRiskManager CExposureGuard CMultiInstanceGuard` | 17,23 |
| 27 | `Core/ConflictResolver.mqh` | `CConflictResolver CSignalConfirmer` | 17 |
| 28 | `Core/Execution.mqh` | `CExecutionEngine` | 17,23,24 |
| 29 | `Core/SafetyGate.mqh` | `CSafetyGate` | 22..28 |
| 30 | `Core/PositionManager.mqh` | `CPositionManager` | 22,23,28 |
| 31 | `Core/Controller.mqh` | `CFranckyController` (the application) | all |

Includes always use the terminal include root: `#include <FranckyTriFlux\Core\Types.mqh>`.
The main EA file includes exactly: `Core\Defines.mqh`, `Inputs.mqh`, `Core\Controller.mqh`.
`Controller.mqh` includes every other file in the order above.

## 3. Portability rules for Core (MQL4 + MQL5 identical source)

Core code MUST compile unchanged with MetaEditor 5 and MetaEditor 4 (`#property strict`).

**Forbidden in Core:** `input`/`sinput`, `input group`, `#property`, templates, `ArraySort`,
`MqlTick`, `CopyTicks*`, `CTrade`, `Position*`/`Order*`/`History*`/`Deal*` functions, `i*` indicator
functions or handles, `CopyBuffer`, `SymbolInfo*`, `AccountInfo*`, `MarketInfo`, `Calendar*`,
`WebRequest`, `OnTradeTransaction` types, `StringTrimLeft/Right`, `StringToUpper/Lower`,
`ObjectsDeleteAll`, function pointers, `override`/`final`, pure virtual `=0`, static class members,
returning structs/arrays from functions (pass by reference), `Sleep`.
Platform-specific behaviour goes to `CPlatform`. A tiny `#ifdef __MQL5__ ... #endif` is allowed in
Core only for chart-object cosmetics (e.g. `OBJPROP_FILL`).

**Reserved names (MQL4 predefined variables/functions) that must not be used as identifiers:**
`Bid Ask Point Digits Bars Time Open High Low Close Volume Symbol Period Comment Print Alert
ErrorDescription`. Use `BidPrice()`, `PointSize()`, `BarClose()` ... instead.

**Warning hygiene (acceptance: no critical warnings):** explicit casts for double->int, long->int,
ulong<->long; `IntegerToString`/`DoubleToString` instead of implicit number->string; check return
values of `FileOpen`, `ObjectCreate`, `GlobalVariableSet`; no unused locals; every switch has
`default`; all array accesses guarded by size checks.

**Pointers:** objects are owned as members of `CFranckyController` (no `new` except none); modules
receive raw pointers in `Init(...)`. Access with `.` (MQL syntax). Never `delete` a pointer you
received.

## 4. Internal enums & codes (`Core/Defines.mqh`)

```cpp
#define FTF_NAME        "FRANCKY TRI-FLUX"
#define FTF_VERSION     "1.00"
#define FTF_ENGINE_COUNT 3          // engine ids 1..3; index 0 = TOTAL in statistics
#define FTF_MAX_SIGNALS  16         // max signals per cycle
#define FTF_TRADED_RING  64         // traded/burned setup ids remembered per engine
// FTF_PLATFORM is "MT5" under __MQL5__, "MT4" otherwise.

enum ENUM_FTF_ENGINE { FTF_ENG_NONE=0, FTF_ENG_MOMENTUM=1, FTF_ENG_FVG=2, FTF_ENG_RANGE=3 };
enum ENUM_FTF_DIR    { FTF_DIR_NONE=0, FTF_DIR_BUY=1, FTF_DIR_SELL=-1 };
enum ENUM_FTF_H1_STATE { FTF_H1S_NEUTRAL=0, FTF_H1S_BULLISH=1, FTF_H1S_BEARISH=-1 };
enum ENUM_FTF_ERRCLASS { FTF_ERR_NONE=0, FTF_ERR_TRANSIENT=1, FTF_ERR_PERMANENT=2, FTF_ERR_FATAL=3 };
enum ENUM_FTF_DD_STATE { FTF_DDS_ARMED=0, FTF_DDS_PAUSED=1 };
enum ENUM_FTF_ZONE_STATE { FTF_ZS_INTACT=0, FTF_ZS_MITIGATED=1, FTF_ZS_INVALIDATED=2, FTF_ZS_EXPIRED=3, FTF_ZS_EXHAUSTED=4 };
enum ENUM_FTF_RANGE_STATE { FTF_RS_NONE=0, FTF_RS_ACTIVE=1, FTF_RS_BROKEN=2 };
```

### 4.1 Reason codes (`ENUM_FTF_REASON`) - rejection reasons, logged as text by `FTF_ReasonStr()`

| Code | Text | Raised by |
|---|---|---|
| `FTF_OK`=0 | OK | - |
| `FTF_REJ_WARMUP` | WARMUP | gate (not enough data / restart grace) |
| `FTF_REJ_TRADING_OFF` | TRADING_OFF | gate (master switch) |
| `FTF_REJ_TERMINAL` | TERMINAL | gate (AutoTrading off, not connected, account/EA trading not allowed) |
| `FTF_REJ_SYMBOL` | SYMBOL | gate (unsupported symbol in BLOCK mode, trade mode disabled/close-only) |
| `FTF_REJ_STALE_TICK` | STALE_TICK | gate (market closed / no ticks) |
| `FTF_REJ_DD_PAUSE` | DD_PAUSE | gate (10 % drawdown pause) |
| `FTF_REJ_CONSEC_LOSS` | CONSEC_LOSS | gate (B.4 cooldown) |
| `FTF_REJ_NEWS` | NEWS | gate (B.1) |
| `FTF_REJ_SESSION` | SESSION | gate (B.2) |
| `FTF_REJ_ROLLOVER` | ROLLOVER | gate (B.3) |
| `FTF_REJ_SPREAD` | SPREAD | gate |
| `FTF_REJ_VOLATILITY` | VOLATILITY | gate (anomaly ATR / velocity / spread) |
| `FTF_REJ_EXEC_QUALITY` | EXEC_QUALITY | gate |
| `FTF_REJ_ERROR_COOLDOWN` | ERROR_COOLDOWN | gate (after permanent broker error) |
| `FTF_REJ_CONFLICT` | CONFLICT | conflict resolver (opposite signals) |
| `FTF_REJ_H1_STRICT` | H1_STRICT | gate (H1 STRICT) |
| `FTF_REJ_COOLDOWN` | ENGINE_COOLDOWN | gate (mode delay used as cooldown) |
| `FTF_REJ_SPACING` | ENTRY_SPACING | gate (global min spacing) |
| `FTF_REJ_MAX_POS_ENGINE` | MAX_POS_ENGINE | gate |
| `FTF_REJ_MAX_POS_SYMBOL` | MAX_POS_SYMBOL | gate |
| `FTF_REJ_HEDGE` | HEDGE_OFF | gate (opposite position open, hedge disabled) |
| `FTF_REJ_SAME_DIR` | SAME_DIR_IGNORE | gate |
| `FTF_REJ_DUPLICATE` | DUPLICATE | gate (setup already traded/burned or too close to last same-engine entry) |
| `FTF_REJ_MULTI_INSTANCE` | MULTI_INSTANCE | gate (duplicate instance ID or cross-instance duplicate) |
| `FTF_REJ_SIGNAL_EXPIRED` | SIGNAL_EXPIRED | resolver/confirmer/retry |
| `FTF_REJ_SIGNAL_INVALID` | SIGNAL_INVALID | confirmer/retry revalidation |
| `FTF_REJ_PRICE_DRIFT` | PRICE_DRIFT | retry revalidation |
| `FTF_REJ_SLTP_INVALID` | SLTP_INVALID | gate (SL/TP on wrong side, zero distance) |
| `FTF_REJ_SLTP_RATIO` | SLTP_RATIO | gate (SL/TP > max ratio) |
| `FTF_REJ_STOPS_LEVEL` | STOPS_LEVEL | gate (REJECT policy) |
| `FTF_REJ_RISK` | RISK | risk (min lot above hard cap, risk money 0) |
| `FTF_REJ_LOT` | LOT | risk (lot invalid after normalisation) |
| `FTF_REJ_MARGIN` | MARGIN | risk |
| `FTF_REJ_EXPOSURE` | EXPOSURE | risk (instance open risk / lots ceiling) |
| `FTF_REJ_AGGREGATE` | AGGREGATE_EXPOSURE | exposure guard (account / currency / correlation) |
| `FTF_REJ_NETTING` | NETTING_ACCOUNT | gate (netting account allows 1 position) |
| `FTF_REJ_ORDER_FAILED` | ORDER_FAILED | execution (final failure) |
| `FTF_REJ_CONFIRM_PENDING` | CONFIRM_PENDING | confirmer (informational, not counted as rejection) |
| `FTF_REJ_COUNT` | - | sentinel (array size) |

### 4.2 Exit codes (`ENUM_FTF_EXIT`) - `FTF_ExitStr()`

`FTF_EXIT_NONE=0, FTF_EXIT_TP, FTF_EXIT_SL, FTF_EXIT_BE, FTF_EXIT_TRAIL, FTF_EXIT_TIME_STOP,
FTF_EXIT_HARD_MAX, FTF_EXIT_MOM_LOSS, FTF_EXIT_MOM_INVALID, FTF_EXIT_FVG_INVALID,
FTF_EXIT_RANGE_BREAK, FTF_EXIT_MANUAL, FTF_EXIT_STOP_OUT, FTF_EXIT_OFFLINE, FTF_EXIT_UNKNOWN, FTF_EXIT_COUNT`.
Texts: `TP SL BREAKEVEN_SL TRAILING_SL TIME_STOP HARD_MAX_TIME MOMENTUM_LOSS MOMENTUM_INVALIDATION
FVG_INVALIDATED RANGE_BREAKOUT MANUAL_OR_OTHER STOP_OUT CLOSED_WHILE_OFFLINE UNKNOWN`.

### 4.3 Event categories (events.csv `category` column)
`INIT DEINIT CONFIG STATE RECOVERY PROTECTION DD NEWS SESSION ROLLOVER CONSEC EXECQ ORDER RETRY
ERROR CONFLICT EXPOSURE INSTANCE SAFETY_CHECK STATS`.

## 5. Structs (`Core/Types.mqh`) - every struct has `void Reset(void)` that zeroes all fields

```cpp
struct STick        { long msc; double bid; double ask; int dir; /* +1 bid up, -1 bid down, 0 same vs previous tick */ };
struct SSignal
  {
   long     id;            // unique, ctx.NextSignalId()
   int      engine;        // ENUM_FTF_ENGINE
   int      dir;           // ENUM_FTF_DIR
   string   setupId;       // fingerprint, e.g. "MOM-B-1.08523", "FVG-S-2026.10.07 10:35", "RNG-B-<rangeId>-T3"
   string   tfText;        // "TICK/M1", "M5", "M1" ... (logging)
   long     timeMsc;       // server ms when generated
   long     firstSeenMsc;  // used by the confirmer
   long     expiryMsc;     // timeMsc + engine TTL
   double   price;         // reference entry price at signal time (ask for BUY, bid for SELL)
   double   sl;            // absolute price (engine computed)
   double   tp;            // absolute price
   double   invalidation;  // engine invalidation level (logged/drawn)
   double   quality;       // 0..100 engine-internal (ordering only, never a global score)
   double   atr;           // ATR used by the engine for this setup
   double   spreadPts;     // spread at signal (points)
   int      h1State;       // ENUM_FTF_H1_STATE at signal time
   bool     structOk;      // BOS/CHoCH present (FVG) - informational unless required
   string   reason;        // human-readable entry reason with key numbers
  };
struct STrackedPos
  {
   ulong  ticket;      long positionId;   int engine;   int dir;   string setupId;
   double lots;        double openPrice;  double initialSL;  double initialTP;  double sl;  double tp;
   long   openMsc;     long signalMsc;
   double signalPrice; double requestedPrice; double slippagePts; double latencyMs; double decisionMs;
   double spreadPts;   int retries;       double riskMoney;  double equityAtEntry; double ddPctAtEntry;
   int    h1State;     int mode;          string entryReason; string tfText;
   double maePts;      double mfePts;     bool beDone;       bool trailActive;     long lastModifyMsc;
   int    pendingExit; string pendingExitDetail; long exitRequestMsc; int exitAttempts; bool recovered;
   long   invStartMsc;   // Momentum: start of the current tick inversion (0 = none), managed by the engine
   double refLevel;      // = SSignal.invalidation at entry (Momentum breakout level, FVG zone far edge, Range boundary)
  };
struct SClosedTrade
  {
   bool   found;   ulong ticket; long positionId; double closePrice; long closeMsc;
   double profit;  double commission; double swap; double net; int exitReason; string exitDetail;
  };
struct SPosInfo
  {
   ulong ticket; long positionId; string symbol; long magic; int dir; double lots;
   double openPrice; double sl; double tp; long openMsc; double profit; double swap; string comment;
  };
struct SExecResult
  {
   bool ok; int retcode; string retcodeText; int errClass; ulong ticket; long positionId;
   double requestedPrice; double fillPrice; double lots; double latencyMs;
  };
struct SNewsEvent   { datetime timeServer; string currency; int impact; string title; string source; };
struct SSymbolSpec
  {
   string name; double point; int digits; double tickSize; double tickValue; double contractSize;
   double lotMin; double lotMax; double lotStep; int stopsLevelPts; int freezeLevelPts;
   string baseCcy; string profitCcy; string marginCcy;
   bool canBuy; bool canSell; bool tradeAllowed; bool hedging;
  };
```

## 6. Utils (`Core/Utils.mqh`) - free functions

```cpp
double FTF_Clamp(const double v,const double lo,const double hi);
double FTF_Median(const double &src[],const int n);           // copies + insertion sort, n<=0 -> 0
string FTF_Upper(const string s);                              // ASCII only, char by char
string FTF_Trim(const string s);
bool   FTF_ListContains(const string csv,const string item);   // case-insensitive, comma list
int    FTF_SplitList(const string csv,string &out[]);          // trimmed, empty items skipped
int    FTF_ParseHHMM(const string s);                          // minutes since midnight, -1 if invalid/empty
int    FTF_MinuteOfDay(const datetime t);
int    FTF_DayOfWeek(const datetime t);                        // 0=Sunday
datetime FTF_DayStart(const datetime t);
bool   FTF_InMinuteWindow(const int minute,const int startMin,const int endMin); // wraps midnight
bool   FTF_IsUsDst(const datetime t);                          // 2nd Sun March 07:00 UTC .. 1st Sun Nov 06:00 UTC approx
string FTF_TimeMscStr(const long msc);                         // "yyyy.mm.dd hh:mi:ss.mmm"
string FTF_TimeStr(const datetime t);                          // "yyyy.mm.dd hh:mi:ss"
string FTF_DirStr(const int dir);                              // BUY / SELL / NONE
string FTF_EngineCode(const int e);                            // MOM FVG RNG ALL
string FTF_EngineName(const int e);                            // Momentum / FVG / Range / TOTAL
string FTF_ModeStr(const int mode);                            // SPEED AGGRESSIVE ULTRA
string FTF_H1StateStr(const int s);                            // BULLISH BEARISH NEUTRAL
string FTF_ReasonStr(const int code);
string FTF_ExitStr(const int code);
string FTF_D(const double v,const int digits);                 // DoubleToString shortcut
double FTF_NormalizePrice(const double price,const double tickSize,const int digits);
double FTF_NormalizeLotsDown(const double lots,const double step,const double lotMin,const double lotMax); // floor to step, 0 if < min
string FTF_SymbolClass(const string symbol);                   // "EURUSD" "XAUUSD" "BTCUSD" or "" (handles suffix/prefix, GOLD, XBTUSD)
string FTF_SafeFilePart(const string s);                       // keeps [A-Za-z0-9_-.]
```

## 7. Module contracts (public API - signatures are binding)

### 7.1 `CLogger` (Core/Logger.mqh)
```cpp
bool   Init(const int level,const bool toJournal,const bool toFile,const string folder,const bool useCommon,const string tag);
void   Deinit(void);
void   SetTimeMsc(const long msc);          // controller sets server ms each cycle (timestamps)
bool   IsEnabled(const int level);
void   Error(const string src,const string msg);
void   Warn (const string src,const string msg);
void   Info (const string src,const string msg);
void   Debug(const string src,const string msg);
void   Trace(const string src,const string msg);
void   Throttled(const int level,const string key,const int intervalMs,const string src,const string msg); // repeats summarised "(xN suppressed)"
void   Flush(void);
string Folder(void);
```
Line format: `2026.10.07 10:35:01.123 | INFO  | MOM  | message`. File: `<folder>\ftf.log`.

### 7.2 `CTradeJournal` (Core/Journal.mqh) - separator `;`, header written when file is new
```cpp
bool Init(CLogger *log,const string folder,const bool useCommon,const bool enabled,const bool logSignals,
          const string platform,const string symbol,const int instanceId,const string modeText);
void Deinit(void);
void LogSignal(const SSignal &s,const bool accepted,const int reason,const string detail,const double bid,const double ask,const double lots);
void LogTrade(const STrackedPos &p,const SClosedTrade &t,const double stressCommission);
void LogEvent(const long msc,const string category,const string code,const string detail);
void SetDigits(const int digits);   // price formatting (called by the controller after the symbol spec is known)
void Flush(void);
```
`signals.csv`: `time;msc;platform;symbol;instance;mode;engine_id;engine;tf;signal_id;setup_id;dir;signal_price;bid;ask;spread_pts;sl;tp;sl_pts;tp_pts;quality;h1;struct_ok;lots;decision;reason_code;reason;detail;entry_reason`
`trades.csv`: `ticket;position_id;platform;symbol;instance;mode;engine_id;engine;tf;setup_id;dir;lots;signal_time;open_time;close_time;duration_s;signal_price;requested_price;open_price;close_price;slippage_pts;decision_ms;latency_ms;spread_pts;initial_sl;initial_tp;final_sl;risk_money;gross_pnl;commission;swap;net_pnl;stress_commission;net_after_stress;r_multiple;mae_pts;mfe_pts;equity_at_entry;dd_pct_at_entry;h1;retries;recovered;entry_reason;exit_code;exit_reason;exit_detail`
`events.csv`: `time;msc;platform;symbol;instance;category;code;detail`

### 7.3 `CStats` (Core/Stats.mqh) - index 0 = TOTAL, 1..3 = engines
```cpp
void   Init(const datetime startServerTime,const double startEquity);
void   OnSetup(const int engine);                         // every signal generated
void   OnReject(const int engine,const int reason);
void   OnEntry(const int engine,const double slippagePts,const double latencyMs,const double spreadPts);
void   OnClose(const int engine,const double net,const double durationSec,const double maePts,const double mfePts);
void   OnDayChange(const datetime serverTime);           // resets "today" counters
int    Setups(const int e);   int Rejects(const int e);   int Trades(const int e);   int Wins(const int e);
double WinRatePct(const int e);  double ProfitFactor(const int e);  double Expectancy(const int e);
double NetProfit(const int e);   double MaxDrawdownMoney(const int e); double AvgWin(const int e); double AvgLoss(const int e);
double AvgDurationSec(const int e); double AvgSlippagePts(const int e); double AvgLatencyMs(const int e);
double SetupsPerDay(const int e,const datetime now); double TradesPerDay(const int e,const datetime now);
double ExecRatePct(const int e);   // trades / setups
int    RejectCount(const int e,const int reason);
int    TodayTrades(const int e); int TodayWins(const int e); double TodayNet(const int e);
string SummaryLine(const int e,const datetime now);
bool   WriteCsv(const string fileName,const bool useCommon,const datetime now,const string header); // stats.csv (overwrite)
double OptCriterion(const int criterion,const int minTrades);   // OnTester value
```

### 7.4 `CStateStore` (Core/StateStore.mqh) - text file `key=value` per line
```cpp
bool   Init(CLogger *log,const string fileName,const bool useCommon,const bool enabled);
bool   Load(void);  bool Save(void);  void SaveIfDirty(const long nowMsc,const int minIntervalMs);
bool   Has(const string key);
void   SetString(const string key,const string v); string GetString(const string key,const string def);
void   SetDouble(const string key,const double v); double GetDouble(const string key,const double def);
void   SetLong  (const string key,const long v);   long   GetLong  (const string key,const long def);
void   Remove(const string key); void RemovePrefix(const string prefix);
int    KeysWithPrefix(const string prefix,string &keys[]);
bool   Enabled(void);
```
State keys: `dd.state dd.ref dd.peak dd.pauseEnd dd.triggers dd.dayStart dd.dayRef`,
`cl.<e>.count cl.<e>.until` (e=0 instance scope), `mg.<e>.step`, `eng.<e>.lastEntry`,
`eng.<e>.ring` (`|`-joined traded/burned setup ids), `pos.<ticket>.<field>` (see 7.14), `meta.saved`.

### 7.5 `CPlatform` (Platform/Platform.mqh) - **the only file that differs MT5/MT4**
```cpp
bool   Init(CLogger *log,const string symbol,const bool twoStepStops);
void   Deinit(void);
string Name(void);                        // "MT5" / "MT4"
bool   IsTester(void); bool IsOptimization(void); bool IsVisual(void);
bool   IsConnected(void);
bool   TradeAllowed(string &why);         // terminal AutoTrading + EA permission + account + expert trading
bool   IsHedging(void);                   // MT4 always true
long   Login(void); string AccountCurrency(void); string Company(void); string Server(void);
double Balance(void); double Equity(void); double FreeMargin(void); double MarginLevel(void);
bool   RefreshSpec(SSymbolSpec &spec);    // chart symbol
bool   SymbolTradable(string &why);       // trade mode / session allows opening now
datetime ServerTime(void);                // TimeCurrent()
long   NowMsc(void);                      // server time in ms (MT5: last tick time_msc; MT4: synthetic, see 08)
bool   AutoGmtOffset(long &secs);         // false in tester or if unknown
ulong  Micros(void);                      // GetMicrosecondCount()
int    FetchNewTicks(STick &out[],const int maxCount);   // chronological new ticks since last call
int    PreloadTicks(STick &out[],const int seconds);     // MT5 history warm-up; MT4 returns 0
bool   CurrentTick(STick &t);
datetime BarTime(const ENUM_TIMEFRAMES tf,const int shift);
double BarOpen(const ENUM_TIMEFRAMES tf,const int shift);  double BarHigh(const ENUM_TIMEFRAMES tf,const int shift);
double BarLow(const ENUM_TIMEFRAMES tf,const int shift);   double BarClose(const ENUM_TIMEFRAMES tf,const int shift);
int    BarsCount(const ENUM_TIMEFRAMES tf);
int    RegisterATR(const ENUM_TIMEFRAMES tf,const int period);
int    RegisterEMA(const ENUM_TIMEFRAMES tf,const int period);
int    RegisterADX(const ENUM_TIMEFRAMES tf,const int period);   // buffers: 0 main, 1 +DI, 2 -DI
double IndValue(const int id,const int buffer,const int shift);   // EMPTY_VALUE if not ready
bool   IndReady(const int id);
bool   OtherSymbolCloses(const string sym,const ENUM_TIMEFRAMES tf,const int count,double &closes[]); // [0]=newest closed bar
bool   OtherSymbolCurrencies(const string sym,string &baseCcy,string &profitCcy);
double LossPerLot(const string sym,const int dir,const double entry,const double sl);       // money, >0
double MarginRequired(const int dir,const double lots,const double price);
int    GetPositions(SPosInfo &out[],const bool allSymbols);                                   // open market positions
bool   GetClosedTrade(const ulong ticket,const long positionId,SClosedTrade &out);           // history lookup
bool   OpenMarket(const int dir,const double lots,const double sl,const double tp,const long magic,
                  const string comment,const int deviationPts,SExecResult &res);
bool   ModifyPosition(const ulong ticket,const double sl,const double tp,SExecResult &res);
bool   ClosePosition(const ulong ticket,const double lots,const int deviationPts,SExecResult &res);
int    ClassifyError(const int code);    // ENUM_FTF_ERRCLASS
string ErrorText(const int code);
int    LoadCalendar(const datetime fromSrv,const datetime toSrv,const string &currencies[],const int nCcy,SNewsEvent &out[]); // MT5 native, MT4 returns 0
bool   HttpGet(const string url,const int timeoutMs,string &body,int &httpCode);           // WebRequest wrapper
```
Exit-code mapping inside `GetClosedTrade`: MT5 `DEAL_REASON_SL`->`FTF_EXIT_SL`, `DEAL_REASON_TP`->`FTF_EXIT_TP`,
`DEAL_REASON_SO`->`FTF_EXIT_STOP_OUT`, `CLIENT/MOBILE/WEB`->`FTF_EXIT_MANUAL`, `EXPERT`->`FTF_EXIT_UNKNOWN`
(the tracker replaces it by its own pending exit code). MT4: comment `[sl]`/`[tp]`/`so:` or close price within
1 tick of SL/TP.

### 7.6 `CClock` (Core/Clock.mqh)
```cpp
void     Init(CConfig *cfg,CPlatform *pf,CLogger *log);
long     OffsetSec(const datetime serverTime);     // server - UTC
datetime ServerToUtc(const datetime s);  datetime UtcToServer(const datetime u);
string   Describe(void);                           // "GMT+3 (AUTO)" ...
```

### 7.7 `CTickBuffer` (Core/TickBuffer.mqh) - ring buffer, index 0 = newest
```cpp
bool   Init(const int capacityPow2);
void   Add(const STick &t);                 // sets t.dir vs previous bid
int    Count(void);   long LastMsc(void);
bool   At(const int i,STick &t);  double BidAt(const int i);  long MscAt(const int i);  int DirAt(const int i);
double UpRatio(const int nTicks,const bool countFlat,int &up,int &down);   // -1 if no directional tick
int    CountBetween(const long fromMscExcl,const long toMscIncl);
double PathBetween(const long fromMscExcl,const long toMscIncl);           // sum |delta bid|
bool   Velocity(const long nowMsc,const int winMs,const int refMs,const int metric,
                double &cur,double &prev,double &median,double &ratio,double &accel);
bool   MicroRange(const int nTicks,const int skipNewest,double &hi,double &lo,long &fromMsc);
double MedianSpread(const int nTicks);                                      // price units
void   TrimOlderThan(const long minMsc);
```
Velocity: buckets of `winMs` ending at `nowMsc`; bucket 0 = current, bucket 1 = previous,
reference = buckets 1..(refMs/winMs). `ratio = cur / max(median, 1e-9 floor = 1 tick or 1 point)`,
`accel = (cur - prev) / max(prev, floor)`.

### 7.8 `CMarketData` (Core/MarketData.mqh)
```cpp
bool   Init(CConfig *cfg,CLogger *log,CPlatform *pf,CTickBuffer *ticks);
bool   Update(void);                 // ingest ticks, snapshot, new-bar flags, indicator cache; true if new tick(s)
long   NowMsc(void); datetime ServerTime(void);
double BidPrice(void); double AskPrice(void); double MidPrice(void);
double Spread(void);                 // price units, includes stress extra spread
double SpreadPts(void);  double PointSize(void); int DigitsCount(void); double TickSize(void);
bool   IsNewBar(const ENUM_TIMEFRAMES tf);   // true during the cycle where tf opened a new bar (M1,M5,H1,FVG tf, Range tf)
datetime LastBarTime(const ENUM_TIMEFRAMES tf);
double AtrM1(void); double AtrM1Median(void); double AtrM5(void);
double EmaM1Fast(void); double EmaM1Slow(void); double EmaM5Fast(void); double EmaM5Slow(void);  // M5 = 20/50
double AdxM1(void); double PlusDiM1(void); double MinusDiM1(void);
double RocM1(void);                  // % over InpMomRocPeriod closed bars
double VelCur(void); double VelPrev(void); double VelMedian(void); double VelRatio(void); double VelAccel(void);
double MedianSpread(void);           // recent median spread (price)
bool   TickFresh(void);  long TickAgeMs(void);
bool   IsWarm(string &why);          // bars + indicators ready (engines check their own tick coverage)
bool   TicksWarm(const int needMs,const int needTicks); // tick buffer spans >= needMs and holds >= needTicks
SSymbolSpec spec;                    // public, refreshed in Init and every 60 s
int    TicksThisCycle(void);
```

### 7.9 `CH1Context` (Core/H1Context.mqh)
```cpp
bool   Init(CConfig *cfg,CLogger *log,CPlatform *pf);
void   Update(const bool newH1Bar);   // recompute on new H1 bar (closed bar 1) and at init
int    State(void);                   // ENUM_FTF_H1_STATE per spec A.1
bool   IsStrong(void);                // State()!=NEUTRAL && ADX >= InpH1StrongAdx
double Adx(void); double PlusDi(void); double MinusDi(void); double EmaFast(void); double EmaSlow(void);
int    CheckEntry(const int engine,const int dir,string &detail);  // FTF_OK or FTF_REJ_H1_STRICT (OFF/SOFT never block)
string Describe(void);
```

### 7.10 `CStructure` (Core/Structure.mqh) - fractal swings on one timeframe
```cpp
void   Init(CPlatform *pf,const ENUM_TIMEFRAMES tf,const int swingBars,const int lookback);
void   Update(void);                                         // call on new bar of tf
bool   NearestSwingHighAbove(const double price,double &level);
bool   NearestSwingLowBelow(const double price,double &level);
bool   HasBos(const int dir,const datetime fromTime);        // close beyond last swing (formed before fromTime) at/after fromTime
bool   HasChoch(const int dir,const datetime fromTime);      // BOS against the prior structure direction
int    SwingHighs(void); int SwingLows(void);
```

### 7.11 `CChartUI` (Core/ChartUI.mqh) - object prefix `FTF<id>_`
```cpp
bool Init(CConfig *cfg,CLogger *log,const int instanceId,const bool enabled);
void Deinit(const bool deleteObjects);
bool Enabled(void);
void PanelLine(const int row,const string text,const color clr);   // rows 0..23
void PanelRender(void);
void DrawEntry(const ulong ticket,const int engine,const int dir,const datetime t,const double price,const string text);
void DrawExit(const ulong ticket,const int engine,const int dir,const datetime tOpen,const double pOpen,
              const datetime tClose,const double pClose,const double net,const string text);
void DrawRect(const string id,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,const bool fill,const string tip);
void DrawSegment(const string id,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,const int style,const string tip);
void DrawVLine(const string id,const datetime t,const color clr,const string tip);
void DrawText(const string id,const datetime t,const double price,const string text,const color clr);
void DrawRejected(const int engine,const int dir,const datetime t,const double price,const string reason);
void Remove(const string id);
void Redraw(void);
color EngineColor(const int engine);
```

### 7.12 `CFtfContext` (Core/Context.mqh) - shared services
```cpp
class CFtfContext
  {
public:
   CConfig *cfg; CLogger *log; CTradeJournal *journal; CStats *stats; CStateStore *state; CPlatform *pf;
   CClock *clock; CTickBuffer *ticks; CMarketData *md; CH1Context *h1; CChartUI *ui;
   string symbol; int instanceId; long magicBase; int mode; long startMsc; long signalSeq;
   long   NextSignalId(void);
   long   NowMsc(void);                           // md.NowMsc() (pf.NowMsc() before md exists)
   int    EngineOfFamilyMagic(const long magic);  // engine id of any family magic
   long   MagicFor(const int engine);             // magicBase + instanceId*10 + engine
   int    EngineFromMagic(const long magic);      // 1..3 if own magic, else 0
   bool   IsFamilyMagic(const long magic);        // any instance of this magic base (engine 1..3)
   int    InstanceFromMagic(const long magic);
   string Tag(void);                              // "MT5|EURUSD|I1|AGGRESSIVE"
   void   Event(const string category,const string code,const string detail); // journal + log INFO
  };
```

### 7.13 Engines (`CEngineBase` + 3 derived)
```cpp
class CEngineBase
  {
protected: CFtfContext *m_ctx; int m_id; string m_code; string m_name; bool m_enabled;
           long m_lastEntryMsc; string m_ring[]; int m_ringPos; string m_status; string m_lastInfo;
public:
   virtual bool   Init(CFtfContext *ctx);
   virtual void   OnNewBar(const ENUM_TIMEFRAMES tf) {}
   virtual int    Evaluate(SSignal &out[],const int startIndex,const int maxOut) { return 0; } // appends at out[startIndex..]
   virtual bool   IsStillValid(const SSignal &sig,string &why) { return true; }
   virtual int    CheckExit(STrackedPos &pos,string &detail) { return FTF_EXIT_NONE; }
   virtual void   OnEntry(const SSignal &sig,const STrackedPos &pos);     // base: lastEntry + MarkTraded
   virtual void   OnClosed(const STrackedPos &pos,const SClosedTrade &tr) {}
   virtual void   Draw(void) {}
   virtual string StatusLine(void);
   virtual void   SaveState(void);   virtual void LoadState(void);       // base: lastEntry + ring
   int    Id(void); string Code(void); string Name(void); bool Enabled(void);
   long   LastEntryMsc(void);
   void   MarkTraded(const string setupId);  bool WasTraded(const string setupId);   // ring of FTF_TRADED_RING
   void   SetInfo(const string s);           // last decision/status shown on panel
   string Info(void);
   // protected helpers: Log(level,msg), LogThrottled(level,key,msg), PrepareSignal(s,dir,setupId,tfText), Norm(price)
  };
```
`CEngineMomentum` adds `double ScoreFor(const int dir)` (0..100 internal momentum score).
`CEngineFVG` keeps `SFvgZone m_zones[]` (struct declared in EngineFVG.mqh: `id dir top bottom ce t1 t3 created
age mitigations trades state inside lastTouchMsc`). `CEngineRange` keeps the active range
(`id state hi lo mid width touchesB touchesS createdBar`).

**Signal field conventions per engine:** `invalidation` = Momentum: broken micro-range edge (BUY: range high,
SELL: range low); FVG: zone far edge (bullish: bottom, bearish: top); Range: boundary (BUY: lo, SELL: hi).
The execution engine copies it into `STrackedPos.refLevel`. `setupId` prefixes: `MOM-`, `<zoneId>-T<n>`
(zone ids start with `FVG-`), `<rangeId>-<B|S>-T<n>` (range ids start with `RNG-`). Engines find their
zone/range of an open position by prefix match on `pos.setupId`.

### 7.14 `CPositionTracker` (Core/PositionTracker.mqh)
```cpp
bool  Init(CFtfContext *ctx);
STrackedPos pos[];   int total;                      // public array, index 0..total-1
int   Sync(STrackedPos &closedPos[],SClosedTrade &closedInfo[]);  // returns n closed since last call; adds recovered positions
void  Add(const STrackedPos &p);
int   IndexOf(const ulong ticket);
int   CountEngine(const int engine); int CountDir(const int dir); int CountEngineDir(const int engine,const int dir);
bool  HasDir(const int dir);
double OpenRiskMoney(void); double OpenLots(void);
double LastEntryPrice(const int engine,const int dir,long &msc);
void  SaveMeta(const int i); void SaveAll(void); void RemoveMeta(const ulong ticket);
int   RecoverOnStart(void);                          // rebuild from platform + state, returns count
```
Per-position state keys: `pos.<ticket>.{eng,dir,setup,isl,itp,omsc,smsc,sp,rp,slip,lat,dec,spr,ret,risk,eq,dd,h1,mode,er,tf,mae,mfe,be,tr}`.

### 7.15 Protections (Core/Protections.mqh)
```cpp
class CDrawdownGuard   { bool Init(CFtfContext*); void Update(void); bool IsPaused(void); int State(void);
                         long PauseRemainingMs(void); double DdPct(void); double RefEquity(void); double PeakEquity(void);
                         int Triggers(void); bool TakeVerifyRequest(void); void Save(void); void Load(void); string Describe(void); bool SelfCheck(string &d); };
class CConsecLossGuard { bool Init(CFtfContext*); void OnClosed(const int engine,const double net); bool IsBlocked(const int engine,string &detail);
                         long RemainingMs(const int engine); int Count(const int engine); void Save(void); void Load(void); string Describe(void); bool SelfCheck(string &d); };
class CExecQualityGuard{ bool Init(CFtfContext*); void OnFill(const double adverseSlipPts,const double latencyMs,const double spreadPts);
                         bool IsBlocked(string &detail); double LotFactor(void); double AvgSlipPts(void); double AvgLatencyMs(void);
                         double MaxLatencyMs(void); string Describe(void); bool SelfCheck(string &d); };
```

### 7.16 Filters (Core/Filters.mqh)
```cpp
class CNewsFilter    { bool Init(CFtfContext*); void Refresh(const bool force); bool IsBlocked(string &detail);
                       bool NextEvent(SNewsEvent &ev); int Count(void); void Draw(void); string Describe(void); bool SelfCheck(string &d); };
class CSessionFilter { bool Init(CFtfContext*); bool IsAllowed(string &detail); string Describe(void); bool SelfCheck(string &d); };
class CRolloverFilter{ bool Init(CFtfContext*); bool IsBlocked(string &detail); string Describe(void); bool SelfCheck(string &d); };
```
News CSV line: `yyyy.mm.dd hh:mi;CCY;HIGH|MEDIUM|LOW;Title` (header lines starting with `#` or `date` ignored).

### 7.17 Risk (Core/RiskManager.mqh)
```cpp
class CRiskManager       { bool Init(CFtfContext*,CPositionTracker*); int CalcLots(const SSignal &sig,const double entry,const double lotFactor,
                           double &lots,double &riskMoney,string &detail); int CheckInstanceExposure(const double addRisk,const double addLots,string &detail);
                           void OnClosed(const int engine,const double net); int MartingaleStep(const int engine); void Save(void); void Load(void); string Describe(void); };
class CExposureGuard     { bool Init(CFtfContext*); int Check(const SSignal &sig,const double lots,const double riskMoney,string &detail);
                           void Refresh(const bool force); string Describe(void); bool SelfCheck(string &d); };
class CMultiInstanceGuard{ bool Init(CFtfContext*,CPositionTracker*); bool Acquire(string &why); void Heartbeat(void); void Release(void);
                           bool IsDuplicateInstance(void); int CheckSignal(const SSignal &sig,string &detail); string Describe(void); bool SelfCheck(string &d); };
```

### 7.18 Conflicts (Core/ConflictResolver.mqh)
```cpp
class CConflictResolver { bool Init(CFtfContext*); int Resolve(SSignal &sigs[],const int n,int &reasons[],string &details[]);
                          bool IsHolding(void); long HoldRemainingMs(void); string Describe(void); };
class CSignalConfirmer  { bool Init(CFtfContext*); bool Add(const SSignal &s); int Count(void);
                          bool Get(const int i,SSignal &s); void RemoveAt(const int i); bool HasSetup(const string setupId); void Clear(void); };
```
`Resolve` sorts by quality (desc) then engine id; drops expired (`SIGNAL_EXPIRED`); if signals in both
directions exist this cycle, or a signal opposes another engine's signal seen within
`InpConflictWindowMs`, all of them get `CONFLICT` and entries are held for `InpConflictHoldMs`.

### 7.19 Execution (Core/Execution.mqh)
```cpp
class CExecutionEngine
  {
   bool Init(CFtfContext*,CPositionTracker*,CExecQualityGuard*);
   int  Open(const SSignal &sig,const double lots,const double riskMoney,const int attempt,const ulong cycleStartUs,
             STrackedPos &outPos,string &detail);       // FTF_OK, FTF_REJ_ORDER_FAILED (retry queued if transient)
   bool PopDueRetry(SSignal &sig,double &lots,double &riskMoney,int &attempt);
   int  PendingRetries(void);
   bool InErrorCooldown(string &detail);
   bool Close(const int idx,const int exitCode,const string detail);    // tracker index; sets pendingExit, retried next cycles
   bool ModifySL(const int idx,const double newSL,const string why);    // checks stops/freeze/min interval
   int  DeviationPts(void);
  };
```

### 7.20 `CSafetyGate` (Core/SafetyGate.mqh)
```cpp
bool Init(CFtfContext*,CEngineManager*,CPositionTracker*,CDrawdownGuard*,CConsecLossGuard*,CExecQualityGuard*,
          CNewsFilter*,CSessionFilter*,CRolloverFilter*,CRiskManager*,CExposureGuard*,CMultiInstanceGuard*,
          CExecutionEngine*,CConflictResolver*);
int  GlobalCheck(string &detail);          // once per cycle, cached; order in section 8
int  LastGlobal(void); string LastGlobalDetail(void);
int  CheckSignal(SSignal &sig,double &lots,double &riskMoney,string &detail); // may adjust sig.sl/tp (stops policy)
int  Revalidate(SSignal &sig,string &detail);  // before retry/confirm: engine validity, expiry, drift, spread, terminal
```

### 7.21 `CPositionManager` (Core/PositionManager.mqh)
```cpp
bool Init(CFtfContext*,CPositionTracker*,CExecutionEngine*,CEngineManager*);
void Manage(void);      // for each own position: MAE/MFE, pending exit retry, engine exit, time-stop, hard max, BE, trailing
```

### 7.22 `CEngineManager` (Core/EngineManager.mqh)
```cpp
bool Init(CFtfContext*);   CEngineBase *Get(const int engine);
void OnNewBars(void);      int Evaluate(SSignal &out[]);   void DrawAll(void);
void SaveAll(void);        void LoadAll(void);             int EnabledCount(void);
long LastAnyEntryMsc(void);   // latest entry of any engine (global entry spacing)
```

### 7.23 `CFranckyController` (Core/Controller.mqh)
```cpp
int    OnInitHandler(void);  void OnDeinitHandler(const int reason);  void OnTickHandler(void);
void   OnTimerHandler(void); void OnTradeHandler(void);               double OnTesterHandler(void);
```

## 8. Processing pipeline (one "cycle")

```
OnTick / OnTimer
 1. md.Update()                        ticks -> TickBuffer, snapshot, new-bar flags, indicator cache
 2. logger time, day change -> stats.OnDayChange, ddGuard day reference
 3. on new bars: h1.Update, engineMgr.OnNewBars, structure updates (inside engines)
 4. ddGuard.Update()                   ARMED -> PAUSED at threshold (event + verification request)
    if ddGuard.TakeVerifyRequest(): RunSafetyVerification()  (re-activate & verify all safeties, log report)
 5. tracker.Sync()                     closed positions -> exit reason, journal.LogTrade, stats, consec/martingale, engine.OnClosed, UI exit
 6. posMgr.Manage()                    exits, time-stops, BE, trailing (always runs, also during any pause/filter)
 7. gate.GlobalCheck()                 cached reason for this cycle
 8. retries: exec.PopDueRetry -> gate.Revalidate -> exec.Open
 9. confirmations: confirmer items -> engine.IsStillValid -> when delay elapsed -> step 11
10. engineMgr.Evaluate()               signals (only on new tick; engines skipped while not warm)
    stats.OnSetup for each; resolver.Resolve (conflict/expiry)
11. for each signal (quality order):  global reason? -> gate.CheckSignal (lots) -> confirm-delay? -> exec.Open
    -> journal.LogSignal (+ stats.OnReject or OnEntry), engine.OnEntry, tracker.Add, ui.DrawEntry
12. periodic: state save (2 s), MI heartbeat (2 s), news refresh, exposure refresh, stats.csv, panel (InpPanelRefreshMs)
```

**GlobalCheck order:** TRADING_OFF -> SYMBOL -> TERMINAL -> STALE_TICK -> WARMUP -> MULTI_INSTANCE(duplicate ID)
-> DD_PAUSE -> ERROR_COOLDOWN -> NEWS -> SESSION -> ROLLOVER -> SPREAD -> VOLATILITY -> EXEC_QUALITY -> CONFLICT(hold).
**CheckSignal order:** SIGNAL_EXPIRED -> SLTP_INVALID -> CONSEC_LOSS -> H1_STRICT -> COOLDOWN -> SPACING -> NETTING
-> MAX_POS_ENGINE -> MAX_POS_SYMBOL -> HEDGE -> SAME_DIR -> DUPLICATE -> MULTI_INSTANCE(cross) -> STOPS_LEVEL
-> SLTP_RATIO -> RISK/LOT/MARGIN -> EXPOSURE -> AGGREGATE.

## 9. 10 % drawdown sequence (spec G.4 as agreed with the client)

```
ARMED: dd% = (ref - equity) / ref * 100 ; ref per InpDdReference (peak / start balance / day start)
  dd% >= InpDdPausePct  ->  1 STOP     : state PAUSED, pauseEnd = now + InpDdPauseSec, event DD/TRIGGER
                            2 REACTIVATE: request verification -> controller re-initialises filters
                                          (news refresh, session/rollover recompute, exposure refresh,
                                          spec refresh, MI heartbeat, position reconcile)
                            3 VERIFY   : each module SelfCheck() -> SAFETY_CHECK events (PASS/WARN) - informational,
                                          never extends the pause
PAUSED: no NEW entries (reason DD_PAUSE); open positions fully managed
  now >= pauseEnd       ->  4 RESTART  : state ARMED, ref re-based to current equity (peak = equity), event DD/RESUME
```
The pause is a strict timer. Nothing can keep FRANCKY waiting after `InpDdPauseSec`.

## 10. Chart objects

Prefix `FTF<id>_`. Names: `P_<row>` (panel), `E_<ticket>` / `ET_<ticket>` (entry arrow/text),
`X_<ticket>` / `XT_<ticket>` / `L_<ticket>` (exit arrow/text/line), `FVG_<zoneId>`, `FVGCE_<zoneId>`,
`RNG_<rangeId>`, `RNGMID_<rangeId>`, `MR_<signalId>` (micro-range), `NEWS_<n>`, `DD_<n>`, `REJ_<n>`.
Colors: Momentum `clrDodgerBlue`, FVG `clrOrange`, Range `clrMediumOrchid`; BUY `clrLime`, SELL `clrRed`.

## 11. Log and state file locations

* Live: `<Files>\FranckyTriFlux\<PLATFORM>_<SYMBOL>_I<id>\` (Files = `MQL5\Files`, `MQL4\Files`, or
  `Terminal\Common\Files` when *Log files in Common\Files* is ON - default).
* Tester: `...\FranckyTriFlux\TEST_<PLATFORM>_<SYMBOL>_I<id>_<yyyymmdd-of-first-tick>_<runtag>\`.
* State: `<Files>\FranckyTriFlux\state\<PLATFORM>_<login>_<SYMBOL>_I<id>.state` (never in tester).
* News CSV: `Common\Files\FranckyTriFlux\news.csv` (default).

## 12. Change protocol for agents

1. Change behaviour -> update `docs/03_Strategy_Logic.md` / this file first.
2. New/changed input -> edit `tools/ftf_spec.py`, run `python3 tools/generate.py`.
3. Core change -> edit the MQL5 copy, run `python3 tools/check_core.py --sync` to copy into MQL4, then
   `python3 tools/check_core.py` (identity + forbidden-API scan).
4. Platform change -> edit both `Platform.mqh` files with the same public API.
5. Compile both EAs in MetaEditor (F7): 0 errors, 0 warnings expected.
