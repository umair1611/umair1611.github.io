# 07 - Testing and Optimization Protocol (spec sections 13, C.1-C.4, G.1)

This protocol produces the reports required by the specification: each engine alone per symbol, then the
combination, in-sample / out-of-sample, sensitivity and degraded execution, then demo/forward and MT4
equivalence. All configuration files are generated (`python3 tools/generate.py`) and delivered in `Tester/`.

## 1. Files delivered

| Folder | Content |
|---|---|
| `Tester/MT5/FTF_MT5_<SYMBOL>_<STAGE>_<IS|OOS>[_STRESS].ini` | Single tests, MT5 real ticks (`Model=4`), M1 chart. `_STRESS` = random execution delay (`ExecutionMode=-1`). |
| `Tester/MT5/FTF_MT5_<SYMBOL>_<STAGE>_OPTIMIZE.ini` | Genetic optimization with forward (out-of-sample) period, custom criterion (`OptimizationCriterion=6` -> `OnTester`). |
| `Tester/MT5/sets/*.set` | Matching parameter files (UTF-16). Copy to `<MT5 data>\MQL5\Profiles\Tester\`. |
| `Tester/MT4/FTF_MT4_<...>.ini`, `Tester/MT4/sets/*.set` | Same for MT4 (`TestModel=0`, ANSI). Copy sets to `<MT4 data>\tester\`. |
| `MQL5/Presets/FranckyTriFlux/*.set`, `MQL4/Presets/FranckyTriFlux/*.set` | Starting presets per symbol for live/demo charts. |

Stages: `MOMENTUM_ONLY`, `FVG_ONLY`, `RANGE_ONLY`, `COMBINED`. Symbols: `EURUSD`, `XAUUSD`, `BTCUSD`.
Default periods (edit `tools/generate.py` constants to change): in-sample 2025.01.01-2025.12.31,
out-of-sample 2026.01.01-2026.09.30, optimization 2025.01.01-2026.09.30 with forward from 2026.01.01.

## 2. Before testing

1. Compile both EAs (MetaEditor F7) - 0 errors expected. Copy `MQL5\...` / `MQL4\...` folders into the terminal
   data folders (File > Open Data Folder).
2. **Symbol names:** if your broker uses suffixes (`EURUSD.m`, `XAUUSDm`, `BTCUSD.r`), edit `Symbol=` / `TestSymbol=`
   in the .ini files (or select the symbol manually in the tester).
3. **Real ticks (MT5, spec C.1):** open the symbol in *View > Symbols > Ticks* and request the period, or let the
   tester download it. After each run, record the "History quality" percentage shown in the report.
4. **News file for backtests:** run the script `Scripts\FranckyTriFlux\FranckyNewsExporter` on a live MT5
   chart (days back = test period). It writes `Common\Files\FranckyTriFlux\news.csv` used by both testers
   (MT5 calendar functions do not work in the tester; MT4 has no calendar).
5. **GMT offset for backtests:** set *Manual broker GMT offset* and *US DST* to your broker's values (most
   GMT+2/+3 brokers: 2 + DST ON). Only sessions, rollover and news windows depend on it.
6. Use a hedging account (several positions per symbol).
7. Logs of every run go to `Terminal\Common\Files\FranckyTriFlux\TEST_...` (one folder per run).

## 3. Running a test

* MT5: `terminal64.exe /config:"C:\path\FTF_MT5_EURUSD_MOMENTUM_ONLY_IS.ini"` (the report
  `FTF_MT5_EURUSD_MOMENTUM_ONLY_IS.htm` is written in the data folder), or load the `.set` in the tester GUI.
* MT4: `terminal.exe /portable "C:\path\FTF_MT4_EURUSD_MOMENTUM_ONLY_IS.ini"` (plain path, no `/config:`).
  Set deposit/currency once in the MT4 tester GUI (not ini keys in MT4).

## 4. Validation sequence (spec C.2 - order is mandatory)

| Step | What | Files | Accept when |
|---|---|---|---|
| 1 | Momentum alone on EURUSD, XAUUSD, BTCUSD (real ticks) | `*_MOMENTUM_ONLY_IS` then `_OPTIMIZE` then `_OOS` | robust OOS: PF > 1.2, positive expectancy after costs, stable neighbours |
| 2 | FVG alone on the 3 symbols | `*_FVG_ONLY_*` | same; compare entry modes TOUCH / CE / REJECTION |
| 3 | Range alone on the 3 symbols | `*_RANGE_ONLY_*` | same |
| 4 | 3 engines combined + Conflict Resolver + all protections | `*_COMBINED_*` | combined DD not worse than the sum; conflicts logged |
| 5 | Degraded execution | `*_STRESS` ini + *Stress: extra spread* (e.g. 30-50 % of typical spread) + *Stress: extra commission per lot* | PF/expectancy still positive |
| 6 | Sensitivity | re-run the best set with each optimized parameter +/-1 step | results do not collapse |
| 7 | MT5 demo / forward on the target broker (2-4 weeks) | live presets | latency/slippage measured; behaviour = backtest |
| 8 | MT4 equivalence per engine/symbol | MT4 ini/sets (same parameters) | FVG/Range comparable; Momentum validated on demo (MT4 tester ticks are synthetic, see docs/08) |

An engine may be switched OFF on a symbol if the data show that it degrades the results (spec 13).

## 5. What to optimize (generated optimization sets)

| Engine | Parameters with ranges (Inputs tab names) |
|---|---|
| Momentum | Tick window, BUY min bullish tick ratio (SELL symmetric), Velocity window, Min velocity / median, Min acceleration, Micro-range length, TP x ATR, SL x ATR, Time-stop, BE trigger, Trailing trigger |
| FVG | Min gap size (x ATR), Max zone age, Max mitigations, TP R multiple, Time-stop (+ manual comparison of Entry mode) |
| Range | Range lookback, Max ADX, Max EMA separation, Min range width, Entry zone %, Min returning tick ratio, Time-stop |
| Common (manual) | Mode delays, H1 ADX threshold, consecutive losses X / cooldown Y, risk % |

Rules (spec 11 and C.4): never shrink TP versus SL to inflate the win rate (the SL/TP ratio guard <= 2 stays ON);
no martingale during optimization; prefer parameter plateaus to single peaks; keep OOS untouched until the
in-sample choice is frozen.

## 6. Custom optimization criterion (`OnTester`)

*Custom optimization criterion* input:
* `ROBUST` (default) = expectancy x sqrt(trades) x min(PF, 3) / (1 + maxDD% / 5); 0 when trades < *Min trades
  for a valid pass*.
* Also available: net profit, profit factor, expectancy, win rate.
Select **Custom max** as the optimization criterion in the MT5 tester (the generated ini already does).

## 7. Reports to deliver (spec 11, 15, C.4)

For every engine x symbol, the combination and each stress/OOS run:
1. The Strategy Tester HTML report (+ MT5 history quality %).
2. The EA's own `stats.csv` (setups/day, trades/day, execution rate, win rate, PF, expectancy, max DD,
   average win/loss, duration, slippage, latency, rejection reasons).
3. A Markdown summary produced by `python3 tools/analyze_logs.py <run folders> --out report.md`
   (add `--stress-commission 7` to re-compute net results with an extra commission per lot).
4. A short statement of the best ROBUST result and its conditions when 90 % is not sustainable (C.4).

## 8. Known limits of backtests
* Even real-tick backtests do not reproduce live latency, rejections and queue position (C.1); demo/forward
  validation is mandatory.
* MT4 tester: fixed spread, interpolated ticks, no timer, no other-symbol data (docs/08).
* News filter in backtests depends on the exported CSV (keep it complete for the tested period).
