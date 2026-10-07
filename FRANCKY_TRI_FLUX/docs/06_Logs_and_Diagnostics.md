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
2026.10.07 10:35:01.123 | INFO  | MOM  | SIGNAL BUY imb 0.66 vel 1.42x acc +31% brk 1.08523+0.6pt roc +0.012% q=96
2026.10.07 10:35:01.124 | INFO  | EXEC | OPEN BUY 0.10 EURUSD @1.08525 req 1.08525 slip 0.0pt lat 6.8ms sl 1.08491 tp 1.08545 magic 5100011 [FTF|MOM|I1|MOM-B-1.08523]
2026.10.07 10:35:19.870 | INFO  | PM   | BE ticket 123456 SL 1.08491 -> 1.08526 (fav 14.1pt >= 70% of 20.0pt)
2026.10.07 10:35:31.002 | INFO  | CTRL | EXIT ticket 123456 MOM TP net +2.00 dur 29.9s MAE 3.1pt MFE 20.4pt
2026.10.07 10:40:00.000 | INFO  | EVT  | NEWS/BLOCK_START NEWS USD HIGH Non-Farm Payrolls 12:30 (-10m)
```
Columns: server time with milliseconds | level | module | message. Modules: `CTRL` controller, `MOM` `FVG`
`RNG` engines, `MGR` engine manager, `GATE` safety gate, `EXEC` execution, `PM` position manager, `TRK`
tracker, `RISK`, `EXPO`, `MI` multi-instance, `DD` drawdown, `CL` consecutive losses, `EQ` execution quality,
`NEWS`, `SESS`, `ROLL`, `MD` market data, `H1`, `PF` platform, `UI`, `LOG`, `EVT` events.

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
| decision | `ACCEPTED` or `REJECTED` |
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
3. **"Why did it close early?"** `exit_reason` + `exit_detail` in `trades.csv`; `PM` lines in `ftf.log`.
4. **Pause / protection timeline:** filter `events.csv` by category.
5. **Execution quality:** `slippage_pts`, `latency_ms`, `decision_ms` columns; panel row 5.
6. **Compare MT4 vs MT5:** run the same preset on both and compare `stats.csv` per engine (docs/08 lists the
   expected differences).
7. **Visual backtest:** enable **Draw rejected signals** to see refused setups as grey markers with tooltips.
8. **Report:** `python3 tools/analyze_logs.py <folders> --out report.md`.
