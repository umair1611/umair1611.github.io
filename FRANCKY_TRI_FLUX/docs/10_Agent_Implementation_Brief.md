# 10 - Agent Implementation Brief (coding rules for humans and AI agents)

Project root: `FRANCKY_TRI_FLUX/`. Reference tree: `MQL5/`. The `MQL4/Include/FranckyTriFlux/Core` folder is a
copy produced by `python3 tools/check_core.py --sync` - never edit it by hand.

## Read before writing code
1. `docs/09_SSOT_Developer_Contract.md` - binding class names, signatures, include order, pipeline.
2. `docs/03_Strategy_Logic.md` - exact trading rules.
3. Existing Core files: `Defines.mqh Types.mqh Utils.mqh InputEnums.mqh Config.mqh Context.mqh EngineBase.mqh EngineManager.mqh`.
   `Config.mqh` is generated: field name = input name without `Inp` (e.g. `InpMomTickWindow` -> `cfg.MomTickWindow`).
4. `tools/ftf_spec.py` - meaning of every input.

## There is NO compiler in the build environment
Code must compile on the first try in MetaEditor 5 **and** MetaEditor 4 (`#property strict`). Be conservative:

* Pointers use `.` for member access (`m_ctx.log.Info(...)`); `->` does not exist. Test with `CheckPointer(p)!=POINTER_INVALID`.
* Define every method inside the class body (inline) - one class per concept, no out-of-class definitions.
* Every file: include guard `#ifndef FTF_<NAME>_MQH / #define / #endif`, header comment, `#include <FranckyTriFlux\Core\X.mqh>`.
* Initialise every local variable. Explicit casts: `(int)`, `(long)`, `(double)`, `(ulong)`, `(datetime)`.
  Number -> string only with `IntegerToString`, `DoubleToString`, `FTF_D`; never `"x"+5`.
* Integer division: cast to double first. Guard every division by zero.
* Arrays: dynamic arrays need `ArrayResize` before use; check `ArraySize` before indexing; no `ArrayRemove`,
  `ArrayInsert`, `ArraySort`, `ArrayCopy` on struct arrays (copy element by element). 2-D arrays need a constant
  second dimension (`int a[][8]`) - prefer separate 1-D arrays.
* Struct assignment `a=b;` is fine (same type). Never return a struct; fill an out-parameter by reference.
* No `switch` on strings. Variables declared inside `case` need braces `{ }`. Every `switch` has `default:`.
* `enum` <- `int` needs a cast `(ENUM_X)v`. Comparing int with enum constants is fine.
* Ternary operator: both branches same type (`cond ? "a" : "b"`, `cond ? 1.0 : 0.0`).
* No local variable may have the same name as a class member or method (MQL warns "declaration hides member").
  Members use the `m_` prefix; locals never do.
* Forbidden in Core (see docs/09 section 3): `input`, `#property`, templates, `ArraySort`, `MqlTick`, `CopyTicks`,
  `CTrade`, `Position*`/`Order*`/`History*`/`Deal*`, `i*` indicator functions, `CopyBuffer`, `SymbolInfo*`,
  `AccountInfo*`, `MarketInfo`, `Calendar*`, `WebRequest`, `StringTrim*`, `StringToUpper/Lower`, `ObjectsDeleteAll`,
  `Sleep`, `override`, pure virtual `=0`, static members, function pointers. Use `CPlatform` / `FTF_*` helpers.
* Do not use these identifiers (MQL4 predefined): `Bid Ask Point Digits Bars Time Open High Low Close Volume
  Symbol Period Comment`. Use `BidPrice()`, `PointSize()`, `BarClose()`.
* Allowed portable APIs: `Math*`, `String*` (except Trim/ToUpper/ToLower), `StringSplit`, `StringFind`,
  `StringSubstr`, `StringReplace`, `StringLen`, `StringGetCharacter`, `ShortToString`, `StringFormat` (with `%d %s %f %.Nf`
  only - never for long/ulong), `IntegerToString`, `DoubleToString`, `NormalizeDouble`, `TimeToString`,
  `TimeToStruct`, `StructToTime`, `TimeCurrent`, `TimeLocal`, `GetMicrosecondCount`, `File*` (FileOpen,
  FileWriteString, FileReadString, FileIsEnding, FileSeek, FileSize, FileFlush, FileClose, FileIsExist,
  FileDelete, FolderCreate), `GlobalVariable*`, `Object*` single-object functions, `ObjectsTotal`, `ObjectName`,
  `ChartRedraw`, `Print`, `GetLastError`, `ResetLastError`, `CheckPointer`, `GetPointer`, `EnumToString`,
  `MathRand`, `MathSrand`, `EMPTY_VALUE`, `DBL_MAX`, `INT_MAX`, `LONG_MAX`.
* Chart objects: `ObjectCreate(0,name,type,0,t1,p1[,t2,p2])`, `ObjectSetInteger/Double/String(0,name,prop,value)`,
  `ObjectMove(0,name,pointIndex,t,p)`, `ObjectFind(0,name)>=0`, `ObjectDelete(0,name)`. `OBJPROP_FILL` only inside
  `#ifdef __MQL5__`.

## Behaviour rules
* Never trade or modify anything outside the chart symbol and the instance's own magic numbers.
* Every decision is logged with a reason: `INFO` for state changes/entries/exits, `DEBUG` for per-signal
  details, `TRACE` for per-tick internals. Per-tick messages must use `log.Throttled(...)` or DEBUG/TRACE.
* Never call `Print` directly outside `CLogger`.
* Use only `CConfig` values (never `Inp*`), the platform layer for broker data and `md` for prices.
* If you need a tunable that is not an input, add `#define FTF_<NAME> value  // TUNABLE (not an input yet)` at
  the top of your file and report it.
* Keep methods short (<= ~80 lines). Comment the "why" of every non-obvious rule with the spec reference.
* Units: `msc` = server time in ms (long); `pts` = points (price / point); prices are normalised with
  `FTF_NormalizePrice` before being sent.
