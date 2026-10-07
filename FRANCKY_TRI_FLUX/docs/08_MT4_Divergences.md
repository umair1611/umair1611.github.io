# 08 - MT4 Divergences (documented as required by spec section 1, Table 4 "Equivalence", B.7, C.3)

The MT4 version uses **the same Core source files** as MT5 (identical engines, filters, protections, risk,
logging and chart display). Only `Platform\Platform.mqh` differs. The differences below come from MetaTrader 4
itself, not from a change of strategy. None of them is silent: each one is listed here and, where relevant,
shown in the log at start-up.

| # | Area | MT5 (reference) | MT4 | Effect / what to do |
|---|---|---|---|---|
| 1 | Tick timestamps | Each tick has a millisecond time (`time_msc`). | No millisecond time. FRANCKY builds a monotonic millisecond clock: live = server second + sub-second part from the PC clock; tester = server second + tick counter. | Live: velocity/acceleration windows (2 s / 30 s) work with ~ms accuracy. Tester: many ticks share one second, so tick-velocity numbers are approximations. |
| 2 | Tick capture | `CopyTicks` returns every tick since the last call (none lost while the EA is busy) and pre-loads 120 s of history at start. | Only the current tick is visible in `OnTick`; ticks arriving while the EA is busy are skipped; no history pre-load. | Momentum needs ~32 s of live ticks before its first signal after start (panel shows "warming ticks"). |
| 3 | Strategy Tester ticks | "Every tick based on real ticks" with real variable spread (spec C.1). | Ticks are interpolated from M1 bars ("Every tick"); spread is FIXED for the whole test (TestSpread). | MT4 backtests of the Momentum engine (tick microstructure) are NOT representative. Validate Momentum on MT5 real ticks and on MT4 demo/forward. FVG and Range (bar based) are comparable. |
| 4 | Tester timer | `OnTimer` runs in the tester. | `OnTimer` never runs in the MT4 tester. | All time logic (10 % pause expiry, retries, cooldowns) also runs from `OnTick`, so it works in both testers. |
| 5 | Economic calendar (B.1) | Native MT5 calendar (live). Tester: CSV file. | No calendar API. News come from the CSV file (`Common\Files\FranckyTriFlux\news.csv`, produced by the MT5 script `FranckyNewsExporter` or edited by hand) or from the free ForexFactory weekly XML feed (live only, URL must be allowed in Options > Expert Advisors). | Keep the CSV up to date for MT4 and for every backtest. |
| 6 | Indicators | Handles + `CopyBuffer`. | Direct `iATR`, `iMA`, `iADX` calls. | Same formulas (ATR, EMA on close, ADX/DI with Wilder smoothing); values can differ in the last decimals between platforms/brokers. |
| 7 | Trade execution | `CTrade`, filling mode by symbol, request/fill price, position identifier. | `OrderSend` / `OrderModify` / `OrderClose`; a single trade thread (error 146 "trade context busy" handled as transient). | Same retry/revalidation logic (B.8). ECN brokers: enable **Send SL/TP after the fill**. |
| 8 | Position identity | Positions have `POSITION_IDENTIFIER`; history by position. | The order ticket is the identifier; history lookup by ticket. | Same journal fields. |
| 9 | Close reason | Deal reason (SL, TP, stop-out, client, expert). | Inferred from the order comment (`[sl]`, `[tp]`, `so:`) or from the close price vs SL/TP. | Rarely "UNKNOWN" if the broker rewrites comments. |
| 10 | Hedging accounts | Netting accounts allow only 1 position per symbol (FRANCKY then limits itself to 1 and logs NETTING_ACCOUNT). | MT4 always allows several tickets; US FIFO accounts reject hedging (errors 149/150 = fatal, entries paused). | Use hedging accounts for the 3-per-engine / 9-per-symbol design. |
| 11 | Inputs dialog | Groups (`input group`). | MQL4 has no groups: separator lines `==== 01. GENERAL ... ====` are shown instead. | Same parameter names and defaults. Default magic base differs (MT5 5 100 000, MT4 4 100 000) so MT4 and MT5 orders never collide. |
| 12 | `.set` files | UTF-16 format `name=value||start||step||stop||Y/N`. | ANSI format `name=value` + `name,F/1/2/3` lines. | Separate preset folders per platform (generated from the same spec). |
| 13 | Tester INI | `terminal64.exe /config:file.ini` with a `[Tester]` section. | `terminal.exe /portable file.ini` with `Test*` keys; deposit/currency come from the tester GUI. | See `docs/07_Testing_and_Optimization_Protocol.md`. |
| 14 | Aggregate exposure (B.6) correlation mode | Reads other symbols' M5 closes (also in the tester). | Live: same. Tester: other symbols are not modelled -> correlation falls back to the currency decomposition (logged once). | Currency mode (default) works identically on both. |
| 15 | GMT offset | Live: `TimeTradeServer() - TimeGMT()`. | Live: `TimeCurrent() - TimeGMT()` when the last tick is fresh. Both testers: manual offset inputs. | Set **Manual broker GMT offset** + **US DST** for backtests (session/news windows). |
| 16 | Global variables in the tester | Tester agents have their own global variables. | The MT4 tester shares global variables with the live terminal. | FRANCKY uses a separate `FTFT.` prefix in the tester and skips duplicate-instance detection there. |
| 17 | Files in the tester | Agent sandbox `Tester\Agent-*\MQL5\Files`. | `tester\files`. | Default **Log files in Common\Files** = ON writes every log to `Terminal\Common\Files\FranckyTriFlux` for both platforms and both testers. |
| 18 | Latency measurement | Round trip of `OrderSend` measured in microseconds. | Same measurement around `OrderSend`. | Reported per trade (`latency_ms`) and averaged on the panel. |

**Independence (spec 1.1, Table 4).** The MT4 and MT5 versions share no files, no global variables and no
licence check at run time. They can run on the same PC/VPS or separately; stopping one never affects the other.
The only optional shared item is the news CSV in the Common folder (read-only for the EAs).
