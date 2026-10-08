# 06 - Logs and Diagnostics (spec section 12, Table 17, acceptance "exportable logs")

FRANCKY explains every decision. This document lists what is written, where, and how to use it to find bugs
or understand the behaviour in backtests, demo and live.

## 1. Where the files are
* **Log files in Common\Files** ON (default): `%APPDATA%\MetaQuotes\Terminal\Common\Files\FranckyTriFlux\`
  (shared by MT4, MT5 and the local tester agents).
* OFF: `<data folder>\MQL5\Files\FranckyTriFlux\` (MT5), `<data folder>\MQL4\Files\FranckyTriFlux\` (MT4);
  in the tester the agent sandbox (`Tester\Agent-...\MQL5\Files`, MT4 `tester\files`).
* One sub-folder per instance: `MT5_EURUSD_I1`, `MT4_XAUUSD_I2`, ... and one per backtest run:
  `TEST_MT5_EURUSD_I1_<first test day>_<run tag>`.
* Restart state: `FranckyTriFlux\state\<PLATFORM>_<login>_<SYMBOL>_I<id>.state` (live/demo only).
* During optimisation nothing is written unless **Write files during optimization** is ON.

## 2. ftf.log (human readable)
```
2026.10.07 10:35:01.123 | INFO  | MOM  | SIGNAL #412 BUY MOM-B-1.08523 @1.08525 sl 1.08491 tp 1.08545 inval 1.08523 q 96 ttl 300ms | imb 0.66 vel 1.42x acc +31% brk 1.08523+0.6pt ...
2026.10.07 10:35:01.124 | INFO  | EXEC | OPEN send MOM BUY 0.10 lots setup MOM-B-1.08523 @ask 1.08525 (signal 1.08525, bid 1.08523 ask 1.08525) SL 1.08491 (34.0 pts) TP 1.08545 (20.0 pts) spread 2.0 pts dev 4 pts risk 34.00 magic 5100011 'FTF|MOM|I1|MOM-B-1.08523' attempt 1/3 decision 0.21 ms
2026.10.07 10:35:01.131 | INFO  | EXEC | OPEN OK #123456 MOM BUY 0.10 @1.08525 req 1.08525 slip 0.0 pts latency 6.8 ms decision 0.21 ms retries 0 SL 1.08491 TP 1.08545 equity 10000.00 setup MOM-B-1.08523 | ...
2026.10.07 10:35:19.870 | INFO  | EXEC | SL MODIFY OK #123456 MOM BUY SL 1.08491 -> 1.08526 (35.0 pts) TP 1.08545 bid 1.08540 ask 1.08542 latency 5.1 ms | BE: favourable 15.0 pts >= 70.0% of D 20.0 pts -> lock 5.0% at 1.08526
2026.10.07 10:35:31.002 | INFO  | TRK  | CLOSED #123456 MOM BUY 0.10 open 1.08525 close 1.08545 net 2.00 (gross 2.00 comm 0.00 swap 0.00) dur 29.9 s MAE 3.1 MFE 20.4 pts | exit TP | ... | setup MOM-B-1.08523
2026.10.07 10:40:00.000 | INFO  | EVT  | NEWS/BLOCK_START NEWS USD HIGH Non-Farm Payrolls 12:30 (-10m) window 12:20-12:35 server - no new entries
```
Columns: server time with milliseconds | level | module (source tag) | message.

| Tag | Module (file) | What it logs |
|---|---|---|
| `CTRL` | controller (Controller.mqh) | start-up, pipeline, safety verification sequence, periodic summaries |
| `CFG` | configuration dump (Controller.mqh) | every effective input at start (`[GROUP] parameter = value`, ftf.log only) |
| `MOM` `FVG` `RNG` | engines (EngineMomentum / EngineFVG / EngineRange.mqh) | measurements, zones, boxes, signals, engine exits |
| `MGR` | engine manager (EngineManager.mqh) | engine list, enable/disable |
| `CR` | conflict resolver (ConflictResolver.mqh) | opposite signals, hold windows, confirmation queue |
| `GATE` | safety gate (SafetyGate.mqh) | global blocks and every per-signal rejection with numbers |
| `RISK` | risk manager (RiskManager.mqh) | lot sizing, margin, martingale steps |
| `EXPO` | exposure guard (RiskManager.mqh) | currency / correlation exposure checks |
| `MI` | multi-instance guard (RiskManager.mqh) | heartbeat, duplicate instance detection |
| `EXEC` | execution (Execution.mqh) | order send / fill / reject / retry, closes, SL modifications |
| `EXECQ` | execution-quality guard (Protections.mqh) | rolling slippage / latency, BLOCK / REDUCE_LOT |
| `PMG` | position manager (PositionManager.mqh) | exit decisions, break-even, trailing |
| `TRK` | position tracker (PositionTracker.mqh) | tracked positions, closures with exit reason, restart recovery |
| `DD` | drawdown guard (Protections.mqh) | 10 % pause trigger, timer, restart, re-based reference |
| `CONSEC` | consecutive-loss guard (Protections.mqh) | loss streaks, cooldowns |
| `NEWS` `SESS` `ROLL` | filters (Filters.mqh) | news source/load/blocks, session open/close, rollover window |
| `MD` | market data (MarketData.mqh) | ticks, bars, spread / ATR, data readiness |
| `TBUF` | tick buffer (TickBuffer.mqh) | ring capacity, velocity history coverage |
| `H1` | H1 context (H1Context.mqh) | H1 state changes, STRICT blocks |
| `STR` | structure (Structure.mqh) | swing scans (TRACE) |
| `CLK` | clock (Clock.mqh) | broker GMT offset (AUTO / MANUAL / DST) |
| `STAT` | statistics (Stats.mqh) | per-trade stats, daily recap, OnTester value |
| `JRNL` | CSV journals (Journal.mqh) | file open / write problems |
| `STOR` | state store (StateStore.mqh) | state file load / save |
| `UI` | chart panel and drawings (ChartUI.mqh) | object limits, panel problems |
| `PF` | platform layer (Platform.mqh, MT4/MT5) | broker calls, retcodes, calendar / web requests |
| `LOG` | logger (Logger.mqh) | logger start / stop, file problems |
| `EVT` | events (Context.mqh) | copy of every events.csv row (`CATEGORY/CODE detail`) |

Levels (**Log level**): ERROR < WARN < INFO (default: decisions, entries, exits, protections) < DEBUG (every
rejected setup with numbers, indicator snapshots on every new M1 bar) < TRACE (per-tick internals).
Repeated messages are summarised: `(+37 similar suppressed)` (**Throttle repeated messages (ms)**).
At start the full effective configuration is written (`[GROUP] parameter = value`), so every log file
documents the settings that produced it.

## 3. signals.csv - one row per setup decision
| Column | Meaning |
|---|---|
| time, msc | server time of the decision |
| platform, symbol, instance, mode | identity |
| engine_id, engine, tf | StrategyID / StrategyName / timeframe (`TICK/M1`, `M5`, `M1`) |
| signal_id, setup_id | unique signal number; setup fingerprint (duplicate protection) |
| dir, signal_price, bid, ask, spread_pts | direction, price at signal time, quotes, spread |
| sl, tp, sl_pts, tp_pts | proposed stop / target (absolute and in points) |
| quality, h1, struct_ok | engine internal quality, H1 context, BOS/CHoCH present (FVG) |
| lots | computed lot (0 when refused before sizing) |
| decision | `ACCEPTED`, `REJECTED`, or `PENDING` (parked for the mode confirmation delay, re-checked later) |
| reason_code, reason, detail | rejection reason (see section 6) with the numbers that triggered it |
| entry_reason | the engine's explanation of the setup |

## 4. trades.csv - one row per closed trade (the 20 fields of spec section 12)
`ticket; position_id; platform; symbol; instance; mode; engine_id; engine; tf; setup_id; dir; lots;
signal_time; open_time; close_time; duration_s; signal_price; requested_price; open_price; close_price;
slippage_pts (positive = adverse); decision_ms (tick -> order); latency_ms (order round trip); spread_pts;
initial_sl; initial_tp; final_sl; risk_money; gross_pnl; commission; swap; net_pnl; stress_commission;
net_after_stress; r_multiple; mae_pts; mfe_pts; equity_at_entry; dd_pct_at_entry; h1; retries; recovered;
entry_reason; exit_code; exit_reason; exit_detail`

## 5. events.csv
`time; msc; platform; symbol; instance; category; code; detail` - categories: `INIT DEINIT CONFIG STATE RECOVERY
PROTECTION DD NEWS SESSION ROLLOVER CONSEC EXECQ ORDER RETRY ERROR CONFLICT EXPOSURE INSTANCE SAFETY_CHECK STATS`.
Examples: `DD;TRIGGER`, `SAFETY_CHECK;PASS`, `DD;RESUME`, `NEWS;BLOCK_START`, `RETRY;QUEUED`, `ERROR;FATAL`,
`RECOVERY;POSITION`, `INSTANCE;DUPLICATE`, `CONFLICT;OPPOSITE`.

## 6. Reason codes (why a setup was refused)
| Code | Meaning | Typical fix / note |
|---|---|---|
| WARMUP | data not ready or restart grace | wait |
| TRADING_OFF | master switch OFF | **Enable new entries** |
| TERMINAL | AutoTrading / permissions / connection | enable Algo Trading |
| SYMBOL | unsupported symbol (BLOCK mode) or trading disabled for the symbol | check symbol |
| STALE_TICK | no recent tick (market closed) | normal off-hours |
| DD_PAUSE | 10 % drawdown pause (seconds) | automatic restart |
| CONSEC_LOSS | consecutive-loss cooldown | automatic after Y minutes |
| NEWS / SESSION / ROLLOVER | time filters | normal |
| SPREAD | spread above the mode limit | broker conditions |
| VOLATILITY | abnormal ATR / tick burst / spread spike | normal protection |
| EXEC_QUALITY | poor fills recently | check VPS/broker |
| ERROR_COOLDOWN | pause after a permanent broker error | read the ERROR event |
| CONFLICT | opposite signals within the conflict window | normal (spec Table 12) |
| H1_STRICT | blocked by the H1 filter in STRICT | normal |
| ENGINE_COOLDOWN | mode delay since the engine's last entry | normal |
| ENTRY_SPACING | global spacing between entries | optional setting |
| MAX_POS_ENGINE / MAX_POS_SYMBOL | limits reached | normal |
| HEDGE_OFF | opposite position open, hedging disabled | normal |
| SAME_DIR_IGNORE | same-direction position open (IGNORE mode) | setting |
| DUPLICATE | setup already traded, or too close to the engine's last entry | normal |
| MULTI_INSTANCE | duplicate Instance ID / another instance just took the same trade | fix Instance IDs |
| SIGNAL_EXPIRED / SIGNAL_INVALID / PRICE_DRIFT | signal too old / no longer valid / price moved before a retry | normal |
| SLTP_INVALID / SLTP_RATIO / STOPS_LEVEL | stop/target geometry problems | normal filter |
| RISK / LOT / MARGIN | sizing impossible within limits | capital / caps |
| EXPOSURE / AGGREGATE_EXPOSURE | instance or account exposure caps | normal |
| NETTING_ACCOUNT | netting account already has a position | use hedging |
| ORDER_FAILED | broker refused after retries | read the ORDER/RETRY events |

Exit codes: `TP SL BREAKEVEN_SL TRAILING_SL TIME_STOP HARD_MAX_TIME MOMENTUM_LOSS MOMENTUM_INVALIDATION
FVG_INVALIDATED RANGE_BREAKOUT MANUAL_OR_OTHER STOP_OUT CLOSED_WHILE_OFFLINE UNKNOWN`.

## 7. stats.csv
Per engine and TOTAL: setups, setups/day, entries, trades, trades/day, execution rate, wins, losses, win rate,
profit factor, expectancy, net, gross profit/loss, average win/loss, max DD (money and %), average duration,
slippage, latency (avg/max), MAE/MFE, rejects, rejection rate, top-3 rejection reasons.

## 8. How to debug with the logs (recipes)
1. **"Why no trade?"** Dashboard status line and engine lines show the current reason. In `signals.csv`
   filter `decision=REJECTED` and count `reason` per engine (Excel pivot or `tools/analyze_logs.py`).
2. **"Why this trade?"** Find the ticket in `trades.csv` -> `setup_id`, `entry_reason`; then search the
   `signal_id` in `signals.csv` and the time in `ftf.log` (DEBUG shows all measured values).
3. **"Why did it close early?"** `exit_reason` + `exit_detail` in `trades.csv`; `PMG` (exit decision) and `EXEC` (EXIT request / CLOSE OK) lines in `ftf.log`.
4. **Pause / protection timeline:** filter `events.csv` by category.
5. **Execution quality:** `slippage_pts`, `latency_ms`, `decision_ms` columns; panel row 5.
6. **Compare MT4 vs MT5:** run the same preset on both and compare `stats.csv` per engine (docs/08 lists the
   expected differences).
7. **Visual backtest:** enable **Draw rejected signals** to see refused setups as grey markers with tooltips.
8. **Report:** `python3 tools/analyze_logs.py <folders> --out report.md`.
