# 11 - Requirements Traceability Matrix

Every requirement of the final specification (`docs/01_Specification_EN_Corrected.md`: V1 sections 0-17,
Tables 1-20, addendum A-F, priority update G, clarification H) is mapped to the code that implements it
and to the evidence that proves it. Parameters are named by their **display name** (the text shown in the
Inputs dialog); the code field behind each name is listed in `docs/05_Input_Parameters_Reference.md`.

**Status**
| Tag | Meaning |
|---|---|
| DONE | Implemented in both EAs (shared Core, or both platform layers). Check it with the evidence column. |
| TEST | Implemented; the *result* must come from Strategy Tester / demo runs on the client's broker data (cannot be produced without MetaTrader). Procedure in docs/07. |
| USER | A delivery step the client performs (compile EX5/EX4 in MetaEditor, run the test campaign). |
| DOC | Implemented with an interpretation or a documented MT4 limit (docs/12 decision D-n, docs/08 divergence). |

Paths are relative to `MQL5/Include/FranckyTriFlux/` (Core identical in `MQL4/Include/FranckyTriFlux/`).

---

## 1. Scope and architecture (sections 0-4, Tables 1-8, F, G.5)

| Req | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| T1 / F.1 / G.5 | Exactly 3 independent engines: Momentum / Micro-breakout, FVG, Range / Mean Reversion. No Pullback, no Order Block, no trend-following engine. | `Core/EngineMomentum.mqh`, `Core/EngineFVG.mqh`, `Core/EngineRange.mqh`, all derived from `Core/EngineBase.mqh`; `Core/EngineManager.mqh` creates exactly these 3 (`FTF_ENGINE_COUNT 3`). | Panel rows `[M]` `[F]` `[R]`; `MGR` log line at start lists 3 engines. | DONE |
| 0 / T1 | A valid strategy trades alone; alignment of engines is never required. | Each engine's `Evaluate()` returns its own signals; the controller processes each signal separately; no engine reads another (docs/09 1.1). | Isolation test (section 9 below); `signals.csv` engine column. | DONE |
| 0 / T20 | No global score blocks a valid strategy. | The only score (Momentum internal score) is used for the Momentum exit only (D8). Quality only orders signals inside a cycle. | `Core/ConflictResolver.mqh` sorts by quality, never rejects on it. | DONE |
| T7 / A.5 | BOS / CHoCH are confirmations / structure only. | `Core/Structure.mqh` (swings, BOS, CHoCH) used only inside FVG: **BOS_REQUIRED (structure confirmation)** default OFF, **Structure event accepted when required**. | FVG `reason` text shows `struct BOS ok/no`. | DONE |
| T4 | Each engine switchable ON/OFF, per symbol and per profile. | **Engine A - Momentum / Micro-breakout ON**, **Engine B - FVG (Fair Value Gap) ON**, **Engine C - Range / Mean Reversion ON**; per-symbol `.set` presets. | Panel shows `ON`/`OFF` per engine. | DONE |
| T5 | Modules: Market Data, Engine Manager, Signal Bus, Conflict Resolver, Risk & Safety Gate, Execution, Position Manager, Journal & Analytics, Tester/Optimizer. | `MarketData`, `EngineManager`, `SSignal` (Types.mqh), `ConflictResolver`, `SafetyGate` + `RiskManager` + `Protections` + `Filters`, `Execution`, `PositionManager` + `PositionTracker`, `Journal` + `Stats`, `OnTester` + `Tester/*.ini`. | docs/02 diagram, docs/09 section 2. | DONE |
| T6 / D.2 | Flow OnTick -> market update -> 3 engines -> signals -> conflicts -> safety -> execution -> management -> logging. | `CFranckyController::Cycle()` (docs/09 section 8, steps 1-12). Position management runs before new entries so exits are never delayed by entry work. | `CTRL` log, docs/02. | DONE |
| T5 Signal Bus | Signal carries StrategyID, symbol, direction, price, SL, TP, expiry, reason, quality, log data. | `struct SSignal` (`Core/Types.mqh`): `engine dir price sl tp expiryMsc reason quality setupId invalidation spreadPts atr h1State tfText`. | `signals.csv` columns. | DONE |

## 2. Platform, licence, installations (sections 1, 1.1, Tables 3, 4, 19, 20)

| Req | Requirement | Implementation | Evidence | Status |
|---|---|---|---|---|
| 1 | MT5 reference + faithful MT4 port, same engines / protections / management. | One Core source tree used by both EAs (`tools/check_core.py` proves byte identity); only `Platform/Platform.mqh` differs, same public API (checked). | `python3 tools/check_core.py` -> 0 errors. | DONE |
| 1 / T4 | Every MT4 divergence documented. | `docs/08_MT4_Divergences.md` (ticks, millisecond time, tester, calendar, order model, ...). | docs/08. | DOC |
| 1.1 / T3 / T19 | Perpetual use, no expiry, no subscription, no activation, no licence server, no PC/account/broker/hardware/VPS lock, no installation limit. | No licence code at all; no account/login checks for permission; no DLL; the only web call is the optional news feed (D22). | Search the sources: no `TimeCurrent() >` expiry, no `AccountInfoInteger(ACCOUNT_LOGIN)` gate. | DONE |
| 1.1 | Same PC / several PCs / one VPS with MT5 + MT4 / several VPSs; simultaneous or separate. | MT5 and MT4 EAs share nothing at run time (separate terminals, separate files, magic bases 5100000 / 4100000). | Installation test (section 9). | USER |
| 1.1 / T12 | Configurable Magic Numbers / Strategy IDs / Instance IDs. | **Magic number base** + **Instance ID**: magic = base + ID x 10 + engine (1 Momentum, 2 FVG, 3 Range); order comment `FTF|MOM|I1|<setup>` (**Order comment prefix**). | `trades.csv` engine_id; magic visible in the terminal. | DONE |
| 1.1 / T12 / B.7 | Multi-instance protection: an instance never manages or duplicates another's orders. | Isolation: the tracker only handles positions of the chart symbol AND one of its own 3 magics (`CPositionTracker::IsOwn`). `CMultiInstanceGuard` (RiskManager.mqh): duplicate Instance ID detection (terminal global variables heartbeat), cross-instance duplicate blocking (**MULTI_INSTANCE_GUARD**, **Cross-instance duplicate window**). | `INSTANCE/DUPLICATE` event; reason `MULTI_INSTANCE`. | DONE |
| 1.1 / T4 | A failure of one platform never stops the other. | No synchronisation, no shared file locks; each EA writes its own folder `MT5_<SYM>_I<id>` / `MT4_<SYM>_I<id>`. | docs/06 section 1. | DONE |
| T15 / T19 | MT5: MQ5 + EX5 + SET; MT4: MQ4 + EX4 + SET; complete sources. | Sources and `.set` files delivered (`MQL5/Presets`, `MQL4/Presets`). EX5/EX4 are produced by compiling in MetaEditor (no compiler in the delivery environment). | `docs/04` installation steps 1-4. | USER |
| T15 | No unjustified DLL or hidden dependency. | None (`#import` not used anywhere). | grep `#import` -> nothing. | DONE |

## 3. Engine A - Momentum / Micro-breakout (Table 9, Table 18, D.4)

| Req | Requirement | Implementation (display names) | Status |
|---|---|---|---|
| Tick window 50 | Bullish tick ratio over 50 ticks. | **Tick window for imbalance (ticks)** = 50; `CTickBuffer::UpRatio`; **Count unchanged ticks in the ratio** OFF. | DONE |
| BUY >= 62 % / SELL <= 38 % | Imbalance thresholds. | **BUY: min bullish tick ratio** 0.62, **SELL ratio = 1 - BUY ratio (symmetric)** ON, **SELL: max bullish tick ratio** 0.38. | DONE |
| Velocity 2 s >= 1.25 x median 30 s | Tick speed. | **Velocity metric** (ticks / price path, D6), **Velocity window (ms)** 2000, **Velocity reference window for median (ms)** 30000, **Min velocity / median velocity** 1.25. | DONE |
| Acceleration >= +20 % | | **Min acceleration (0.20 = +20%)** 0.20. | DONE |
| Micro-range 20 ticks + buffer max(0.15 x spread, 0.02 x ATR) | Breakout above / below the range of the 20 ticks before the current tick. | **Micro-range length (ticks)** 20, **Breakout buffer (x spread)** 0.15, **Breakout buffer (x ATR M1)** 0.02. | DONE |
| Compatible directional momentum; ROC(5), ATR(14), ADX/DI, EMA M1/M5 internal only | | **Confirm with ROC direction** ON, **ROC period (M1 bars)** 5, **Confirm with M1 EMA fast/slow** (9/21), **Confirm with M1 ADX/DI**, **M5 EMA20/50 context** SOFT (D7). These never affect FVG or Range. | DOC (D7) |
| TP max(1.2 x spread, 0.18 x ATR), SL max(2 x spread, 0.35 x ATR) (Table 14) | | **TP = max(x spread, ...)** 1.2, **TP = max(..., x ATR M1)** 0.18, **SL = max(x spread, ...)** 2.0, **SL = max(..., x ATR M1)** 0.35. | DONE |
| Invalidation: return into the micro-range + persistent tick reversal | | Exit `MOMENTUM_INVALIDATION` when the bid returns to the broken level after a persistent inversion. | DONE |
| Momentum-loss exit: score < 60 and reversal ~500 ms (Table 14) | | **Momentum-loss exit ON**, **Exit when momentum score below** 60, **Tick inversion persistence (ms)** 500, **Inversion window (ticks)** 10 (D8). | DONE |
| Exits: dynamic TP/SL, BE, short trailing, time-stop | | Position manager (section 6). **Time-stop (s, 0 = off)** 45 / 30 / 30 s in the EURUSD / XAUUSD / BTCUSD presets. | DONE |
| One setup = one trade | Setup id `MOM-B-<level>` / `MOM-S-<level>`; ring of traded setups persisted. | `DUPLICATE` reason. | DONE |

## 4. Engine B - FVG (Table 10)

| Req | Requirement | Implementation (display names) | Status |
|---|---|---|---|
| Main timeframe M5, optional M1 precision | | **FVG timeframe** M5, **Use M1 for entry precision** (REJECTION candle on M1). | DONE |
| Bullish: Low(C3) > High(C1), zone [High C1 ; Low C3]; bearish symmetric | | `CEngineFVG::DetectAt` on closed bars; zone id `FVG-B/S-<time of C2>`. | DONE |
| Own filters: min gap vs ATR, max age, max mitigations, spread, distance | | **Min gap size (x ATR of FVG timeframe)**, **Min gap size (x spread)**, **Max zone age (bars)**, **Max mitigations (returns into zone)**, **Max price distance to zone (x ATR)**; the common spread filter applies. | DONE |
| Entry modes Touch / CE 50 % / Rejection | | **Entry mode (TOUCH / CE 50% / REJECTION)**, **REJECTION: min wick (% of candle range)**. | DONE |
| BOS / CHoCH optional, BOS_REQUIRED = false | | **BOS_REQUIRED (structure confirmation)** OFF, **Structure event accepted when required**, **Swing strength (bars each side)**, **Structure lookback (bars)**. | DONE |
| Programmable invalidation: close / overshoot beyond the edge + buffer | | **Invalidation buffer (x ATR)**, **Invalidate on candle close (else on tick)**. | DONE |
| SL behind the real invalidation / swing + buffer; no microscopic SL | | **SL anchor** (zone edge / swing extreme of C1..C3), **SL buffer (x spread)**, **SL buffer (x ATR)**. | DONE |
| TP: next liquidity / ATR target / R multiple | | **TP mode** (LIQUIDITY = nearest swing, ATR, RR), **TP ATR multiple**, **TP R multiple**, **TP min R (liquidity mode)**, **TP max R (liquidity mode)**. | DONE |
| Stored state: direction, bounds, CE, time, age, returns, status intact / mitigated / invalidated | | `struct SFvgZone` (`id dir top bottom ce t1 t2 t3 ageBars mitigations trades state ...`), states INTACT / MITIGATED / INVALIDATED / EXPIRED / EXHAUSTED; logged on every change and drawn on the chart. | DONE |
| Exit if the zone is invalidated | | **Exit open trade if zone invalidated** (exit `FVG_INVALIDATED`, also after a restart from the saved reference level). | DONE |

## 5. Engine C - Range / Mean Reversion (Table 11)

| Req | Requirement | Implementation (display names) | Status |
|---|---|---|---|
| Timeframes M1 / M5; H1 only as context | | **Range timeframe (M1 or M5)**; H1 STRICT rule A.4 (section 7). | DONE |
| Detection: low / falling ADX, small EMA20/50 separation vs ATR, no significant swings | | **Max ADX for a range**, **Require falling ADX**, **ADX slope bars**, **Fast EMA period** / **Slow EMA period**, **Max \|EMA20-EMA50\| (x ATR)**, **Max net drift (% of width)**. | DONE |
| Construction: recent highs / lows; min width > spread and > x ATR | | **Range lookback (bars)**, **Min range width (x ATR)**, **Min range width (x spread)**, **Max range width (x ATR)**, **Min touches per boundary**. | DONE |
| BUY near the low bound + rejection / slow-down + return of buying ticks (SELL symmetric) | | **Entry zone near boundary (% of width)**, **Edge confirmation (slowdown / rejection)**, **Rejection: min wick (% of candle range)**, **Tick window for buyer/seller return (ticks)**, **Min returning tick ratio**. | DONE |
| SL beyond the bound + spread / ATR buffer | | **SL buffer beyond boundary (x spread)**, **SL buffer beyond boundary (x ATR)**. | DONE |
| TP = range centre, opposite bound optional | | **TP target** (MID / OPPOSITE), **TP offset before target (% of width)**. | DONE |
| Invalidation: volatility expansion + confirmed breakout -> cancel or exit quickly | | **Breakout confirmation buffer (x ATR)**, **Exit quickly on confirmed breakout** (exit `RANGE_BREAKOUT`), box re-built after a breakout. | DONE |
| Never mean-revert against an abnormal impulse: volatility / spread / tick-velocity filter mandatory | | **Max tick velocity ratio (impulse protection)**, **Max ATR / median ATR**, plus the common VOLATILITY and SPREAD gate checks. | DONE |

## 6. Positions, conflicts, SL/TP management (Tables 12, 14, G.2)

| Req | Requirement | Implementation (display names) | Status |
|---|---|---|---|
| G.2 | Up to 3 positions per engine, up to 9 per symbol, manually adjustable; never an obligation. | **Max simultaneous positions (Momentum)** / **(FVG)** / **(Range)** = 3, **Max total positions on this symbol (this instance)** = 9. Reasons `MAX_POS_ENGINE`, `MAX_POS_SYMBOL`. Positions are only opened by valid setups (one trade per setup). | DONE |
| G.2 | The 3 engines run in parallel; none waits for another. | All enabled engines are evaluated on every tick in the same cycle. | DONE |
| T12 | OPPOSITE_HEDGE false by default. | **OPPOSITE_HEDGE (allow BUY and SELL together)** OFF -> reason `HEDGE`. | DONE |
| T12 | Same direction: ignore or stack within the max. | **Same-direction signals** (STACK default / IGNORE), **Min distance between same-engine entries (x ATR M1)** (D15). | DOC (D15) |
| T12 | Simultaneous opposite signals: block a few hundred ms and re-evaluate; no arbitrary winner. | **Opposite-signal conflict window (ms)** 300, **Entry block after a conflict (ms)** 300 -> reason `CONFLICT` for both, event `CONFLICT/OPPOSITE` (D16). | DONE |
| T12 | Every order keeps its engine of origin. | Engine digit in the magic number + comment; tracker, stats and exits per engine. | DONE |
| T14 | SL/TP <= 2 guard, never manipulated to inflate the win rate. | **SL/TP ratio guard (max SL / TP, 0 = off)** 2.0 -> reason `SLTP_RATIO`; TP is never shrunk to fit (D11). | DOC (D11) |
| T14 | Break-even at 70 % of TP, per strategy. | **Break-even trigger (% of TP distance)** 70, **Break-even lock (% of TP distance)** 5, per engine. | DONE |
| T14 | Trailing at 85 % of TP, short, configurable. | **Trailing trigger (% of TP distance)** 85, **Trailing distance (% of TP distance)** 25, **Trailing min step (% of TP distance)** 5, per engine. | DONE |
| T14 / G.1 | Time-stops EURUSD 45 s, XAUUSD 30 s; BTCUSD own value from tests; hard max 120 s. | **Time-stop (s, 0 = off)** per engine and preset, **Hard max holding time, all engines (s, 0 = off)** 120 (D5, D9). BTCUSD starts at 30 s and is part of the optimisation `.ini`. | TEST |
| T14 | Each engine returns its own Entry, SL, TP, invalidation; no universal SL/TP. | Engine-specific `BuildSignal()`; `SSignal.invalidation`. | DONE |
| T5 Execution | Respect broker stops / freeze levels; measure slippage and latency. | **Broker stops-level policy** (adjust + re-size, or reject; D12), **Min interval between SL modifications (ms)**, freeze-level check before every modify; slippage and latency stored per trade. | DONE |
| ECN brokers | SL/TP after the fill. | **Send SL/TP after the fill (ECN brokers)**. | DONE |

## 7. Timeframes and H1 context (section 5, A.1-A.5)

| Req | Requirement | Implementation (display names) | Status |
|---|---|---|---|
| A.1 | H1 BULLISH / BEARISH / NEUTRAL from EMA20/50 + ADX/DI, thresholds as inputs. | `CH1Context` on closed H1 bars: **H1 fast EMA period** 20, **H1 slow EMA period** 50, **H1 ADX period** 14, **H1 ADX directional threshold** 18, **H1 min +DI/-DI gap**. | DONE |
| A.2 | OFF: ignored. | **H1_FILTER mode** OFF -> `CheckEntry` always OK. | DONE |
| A.3 | SOFT (default): context only, never blocks, never reduces the lot. | SOFT logs the context, returns OK; the lot calculation never reads the H1 state. | DONE |
| A.4 | STRICT: Momentum / FVG opposite to a clear trend blocked; Range blocked while a strong trend is established; never forces a direction. | **STRICT applies to Momentum / FVG / Range**, **H1 'strong trend' ADX (Range STRICT)** 25 (D10) -> reason `H1_STRICT`. NEUTRAL never blocks. | DOC (D10) |
| 5 | Momentum ticks/M1 + M5 context; FVG M5 (+M1); Range M1/M5; no mandatory multi-timeframe confirmation. | See sections 3-5; every multi-timeframe confirmation is optional. | DONE |

## 8. Common filters, execution and the eight protections (Table 13, B.1-B.8)

| Req | Requirement | Implementation (display names) | Status |
|---|---|---|---|
| T13 Spread | Refuse when spread > symbol / mode threshold; log the reason. | **Max spread SPEED / AGGRESSIVE / ULTRA (points, 0 = auto)**, **Auto max spread (x ATR M1) when limit = 0** -> reason `SPREAD` with the numbers (D4). | DONE |
| T13 Slippage / B.8 | Measure it; refuse / reduce when execution quality is out of tolerance. | `CExecQualityGuard`: **Execution-quality action** (LOG_ONLY / BLOCK / REDUCE_LOT), **Execution-quality window (trades)**, **Max avg adverse slippage (x avg spread, 0 = off)**, **Max avg order latency (ms, 0 = off)**, **Execution-quality cooldown (s)**, **Lot factor when quality is poor**; **Max slippage / deviation (points, 0 = auto)**. | DONE |
| T13 Volatility | Block on spread / ATR / tick-velocity anomaly. | **Volatility anomaly: ATR > x median ATR**, **... tick velocity > x median**, **... spread > x median spread** -> reason `VOLATILITY`. | DONE |
| T13 Availability | AutoTrading, market open, trading allowed, margin, stops / freeze levels. | Gate `TERMINAL`, `SYMBOL`, `STALE_TICK` (**Max tick age before market considered stale (s)**), `MARGIN`, `STOPS_LEVEL`. | DONE |
| T13 / D.3 | Latency <= 10 ms if possible, always measured. | Decision time (tick -> send) and order round trip measured per order: `decision_ms`, `latency_ms`, panel row "ticks/latency" (D21). | TEST |
| T13 | One VPS can host MT5 + MT4. | Light CPU use: indicator handles cached, no per-tick allocation in the tick buffer, throttled logs. | USER |
| B.1 | News filter: ON/OFF, NFP / CPI / FOMC / rates, window before / after, new entries blocked, positions managed, automatic resumption, impact and currencies configurable, MT5 calendar, MT4 equivalent, no paid dependency. | `CNewsFilter`: **NEWS_FILTER ON**, **News source** (AUTO / calendar / CSV / web), **Min impact**, **Currencies (AUTO or list e.g. USD,EUR)**, **Keywords always blocked (any impact)**, **Block minutes BEFORE news**, **Block minutes AFTER news**, **News CSV file ...**, **News CSV times are UTC**, **Web XML feed URL**, **News refresh interval (min)**, **Draw news windows on chart**. MT4 / testers: CSV exported by `Scripts/FranckyTriFlux/FranckyNewsExporter.mq5` or the free web feed (D17). | DOC (D17) |
| B.2 | Session filter: ON/OFF, days and ranges, London / NY / Asia or custom TradingStart / TradingEnd, server / UTC documented. | `CSessionFilter`: **SESSION_FILTER ON**, **Session preset** (UTC), **CUSTOM hours time basis**, **TradingStart (HH:MM)**, **TradingEnd (HH:MM)**, second window, **Trade Monday ... Trade Sunday**; broker offset **Broker GMT offset mode**, **Manual broker GMT offset (winter, hours)**, **Manual offset follows US DST (+1h)** (`CClock`). | DONE |
| B.3 | Rollover filter: ON/OFF, window before / after, positions managed, spread filter stays active. | `CRolloverFilter`: **ROLLOVER_FILTER ON**, **Rollover time (server, HH:MM)**, **Block minutes BEFORE rollover**, **Block minutes AFTER rollover**; the SPREAD check runs independently. | DONE |
| B.4 | Consecutive losses X -> cooldown Y min, scope engine / symbol / instance, new setup required, does not replace the 10 % pause. | `CConsecLossGuard`: **CONSECUTIVE_LOSS_PROTECTION ON**, **Consecutive losses X**, **Cooldown Y (minutes)**, **Scope**; setups refused during the cooldown are burned (D13). | DOC (D13) |
| B.5 | Risk mode Fixed / % balance / % equity, max risk, broker lot rules, margin, real SL distance, total exposure cap; martingale optional within hard limits and with a new setup. | `CRiskManager`: **RISK_MODE**, **Fixed lot**, **Risk per trade (%)**, **Max risk per trade - hard cap (%)**, **Max lot per trade (0 = broker max)**, **Allow broker min lot even if above max risk**, **Max total open risk, this instance (%)**, **Max total open lots, this instance (0 = off)**; lot from the real SL distance after stops-level adjustment; **Martingale ON (optional)** OFF, **Martingale multiplier**, **Martingale max steps** (still subject to every cap). | DONE |
| B.6 / G.1 | Aggregate exposure across EURUSD / XAUUSD / BTCUSD, USD exposure, no hard-coded correlation, no MT4/MT5 synchronisation. | `CExposureGuard`: **Aggregate exposure mode**, **Count only FRANCKY positions (same magic base)**, **Max open risk all symbols (% equity)**, **Max net risk per currency, e.g. USD (% equity)**, **Correlation lookback (M5 bars)**, **Max correlation-adjusted risk (% equity)**. Reads the account's open positions; nothing is shared between platforms (D14). | DOC (D14) |
| B.7 | Recovery after restart / reconnection: rebuild positions, identify engine / magic / instance, no duplicate entries, resume management, restore cooldowns and protections. | `CPositionTracker::RecoverOnStart` (positions + per-position metadata), `CStateStore` (drawdown pause, cooldowns, martingale steps, traded setup rings), **Save and restore state after restart**, **No new entries after start (s)**; positions closed while offline are journaled. | DONE |
| B.8 | Classify transient / permanent errors; max retries; delay; revalidate signal, spread, slippage, price, permissions, margin before each retry; never retry blindly; log code, reason, attempts, result. | `CExecutionEngine` (error classes from `CPlatform::ClassifyError`), **Max retries per order**, **Delay between retries (ms)**, **Max price drift before a retry (x ATR M1)**, **Pause after a permanent broker error (s)**; `CSafetyGate::Revalidate` before every retry; ambiguous results (timeout) reconciled before any resend. | DONE |

## 9. Modes, drawdown, martingale (Table 15, section 10, D.3, G.4, H)

| Req | Requirement | Implementation (display names) | Status |
|---|---|---|---|
| T15 / D.3 | SPEED 1500 ms, AGGRESSIVE 750 ms, ULTRA 300 ms; no NORMAL mode; a more aggressive mode never needs a higher score. | **Trading mode (SPEED / AGGRESSIVE / ULTRA)**, **SPEED / AGGRESSIVE / ULTRA mode entry delay (ms)**, **How the mode delay is applied** (cooldown / confirm / both, D3); modes change only delays and spread limits, never engine thresholds. | DOC (D3) |
| 10 / G.4 / H | At 10 %: STOP new entries -> re-activate safeties -> verify -> restart automatically after a few seconds (strict timer, never waits for another condition); open positions managed during the pause. | `CDrawdownGuard` (Protections.mqh): **Equity drawdown pause ON**, **Drawdown threshold (%)** 10, **Pause length (s)** 10, **Drawdown reference**. Controller `RunSafetyVerification()` writes `SAFETY_CHECK START / PASS / WARN / SUMMARY`; resume by server time or (live) wall clock even without ticks; reference re-based at restart (D1, D2). | DOC (D1, D2) |
| 10 | No automatic definitive daily stop. | None exists; every block is temporary. | DONE |
| 10 | Martingale optional, a loss never opens a position blindly, a new valid setup is mandatory. | Martingale only changes the lot of the next valid signal; no order is ever created by a loss. | DONE |

## 10. Logging and statistics (section 12, Table 17)

**Section 12 - the 20 mandatory fields** (`trades.csv` per closed trade, `signals.csv` per decision):

| # | Field | Column(s) |
|---|---|---|
| 1 | StrategyID / StrategyName | `engine_id`, `engine` |
| 2 | Symbol | `symbol` |
| 3 | Mode | `mode` |
| 4 | Timeframe | `tf` |
| 5 | Signal date/time | `signal_time` (trades), `time` + `msc` (signals) |
| 6 | Direction | `dir` |
| 7 | Signal / requested / executed price | `signal_price`, `requested_price`, `open_price` |
| 8 | Spread | `spread_pts` |
| 9 | Slippage | `slippage_pts` (positive = adverse) |
| 10 | Latency | `latency_ms` (+ `decision_ms`) |
| 11 | Lot | `lots` |
| 12 | SL | `initial_sl`, `final_sl` (trades), `sl`, `sl_pts` (signals) |
| 13 | TP | `initial_tp` (trades), `tp`, `tp_pts` (signals) |
| 14 | Entry reason | `entry_reason` |
| 15 | Rejection reason | `reason_code`, `reason`, `detail` (signals) |
| 16 | Exit reason | `exit_code`, `exit_reason`, `exit_detail` |
| 17 | Duration | `duration_s` |
| 18 | Gross / net PnL | `gross_pnl`, `commission`, `swap`, `net_pnl` (+ `stress_commission`, `net_after_stress`) |
| 19 | MAE / MFE | `mae_pts`, `mfe_pts` |
| 20 | Equity / DD at trade time | `equity_at_entry`, `dd_pct_at_entry` |

| Req | Requirement | Implementation | Status |
|---|---|---|---|
| T17 | Setups/day, trades/day, execution rate, win rate, PF, expectancy, max DD, average win/loss, average duration, average slippage, rejection rate - per engine and symbol. | `CStats` -> `stats.csv` (one row per engine + TOTAL, one folder per symbol/instance), also top-3 rejection reasons, latency, MAE/MFE; `tools/analyze_logs.py` merges folders into one report. | DONE |
| 0 | Statistics separated by StrategyID, symbol and mode. | Engine column, per-symbol folders, `mode` column. | DONE |
| T15 | Logs exportable as CSV or text. | `ftf.log` (text) + `signals.csv`, `trades.csv`, `events.csv`, `stats.csv` (docs/06). | DONE |
| User request | Extensive logs for backtest / demo debugging. | Levelled logger (**Log level**, **Throttle repeated messages (ms)**), configuration dump at start, every rejection with its numbers at DEBUG. | DONE |
| User request | Chart labels and dashboard. | `CChartUI`: dashboard (**Show dashboard panel**), entry/exit arrows and lines (**Draw entries / exits**), FVG zones, range boxes, micro-ranges (**Draw FVG zones, ranges, micro-ranges**), rejected signals (**Draw rejected signals**), news and drawdown markers. | DONE |

## 11. Tests, optimisation, performance target (sections 11, 13, C.1-C.4, Table 16)

| Req | Requirement | Implementation | Status |
|---|---|---|---|
| 13 / C.2 | Each engine alone on each symbol, then combined. | `Tester/MT5`, `Tester/MT4`: `.ini` + `.set` per symbol x stage (MOMENTUM_ONLY, FVG_ONLY, RANGE_ONLY, COMBINED). | TEST |
| 13 / C.3 | In-sample / out-of-sample, sensitivity, degraded execution. | `_IS`, `_OOS`, `_STRESS` files (**Stress: extra spread (points)**, **Stress: extra commission per lot (money)**, MT5 random execution delay), `_OPTIMIZE` files with forward period; protocol and sensitivity procedure in docs/07. | TEST |
| C.1 | MT5 Momentum on "Every tick based on real ticks", data quality documented. | MT5 `.ini` use `Model=4` (real ticks); docs/07 lists what to record (period, history quality, gaps). | TEST |
| 13 | Demo / forward test before freezing; then MT4 equivalence tests. | docs/07 sections on demo and MT4 equivalence; docs/08 expected differences. | USER |
| 11 / C.4 / T16 | ~90 % is a research target; no tiny TP, big SL, dangerous martingale or over-fitting; report the best robust rate otherwise. | **Custom optimization criterion** (robust: expectancy x sqrt(trades) x min(PF,3) / (1 + DD%/5)), **Min trades for a valid pass**; SL/TP ratio guard; martingale OFF by default (D20). | DOC (D20) |
| 11 | Report: win rate, PF, expectancy, max DD, trades, average win/loss, duration, spread/slippage per strategy and symbol. | `stats.csv` + `analyze_logs.py` report. | TEST |

## 12. Priority update G and clarification H

| Req | Requirement | Implementation | Status |
|---|---|---|---|
| G.1 | Markets EURUSD, XAUUSD, BTCUSD; GBPUSD removed; BTCUSD own settings; weekend trading possible. | Presets `FranckyTriFlux_MT5/MT4_<EURUSD/XAUUSD/BTCUSD>.set`; **Supported-symbol check (EURUSD/XAUUSD/BTCUSD)** (WARN by default, D18); BTCUSD preset: session filter OFF, **Trade Saturday** / **Trade Sunday** ON; BTCUSD values flagged for optimisation (D5). | DOC (D5, D18) |
| G.2 | 3 per engine / 9 per symbol, adjustable. | Section 6. Netting accounts: 1 position (D19). | DOC (D19) |
| G.3 | One instance trades only its chart symbol; several symbols = several instances. | The EA only ever sends orders for `_Symbol`; tracker and manager only touch chart-symbol positions with own magics. | DONE |
| G.4 / H | 10 % sequence STOP -> RE-ACTIVATE -> VERIFY -> AUTOMATIC RESTART a few seconds later. | Section 9; docs/09 section 9. | DONE |
| G.5 | No additional strategy without the client's validation. | None added. | DONE |
| G.6 | G.1-G.4 in MT5 and MT4. | Shared Core; MT4 platform layer implements the same API. | DONE |

## 13. Acceptance checklist (sections 15, E, G.6) - how to tick each box

| Criterion | How to verify |
|---|---|
| MT5 and MT4 compile without errors | Compile both EAs in MetaEditor (F7). Before that, `python3 tools/check_core.py`, `tools/check_api.py`, `tools/gen_api_doc.py --check`, `tools/generate.py --check` all pass (static checks only - they do not replace the compiler). |
| Only 3 engines; each switchable | Panel rows, input group "Engines". |
| Isolation test (only FVG ON -> only FVG trades, etc.) | Run `Tester/MT5/FTF_MT5_<SYM>_FVG_ONLY_IS.ini` (and the Momentum / Range ones); `trades.csv` must contain only that `engine`. |
| No global score blocks a strategy; BOS/CHoCH not standalone | Code review points in sections 1 and 4 above. |
| Every trade tagged with its StrategyID | `trades.csv` `engine_id`; magic last digit. |
| Conflict Resolver, hedging OFF, max positions, opposite signals documented and configurable | Section 6; docs/03; docs/05. |
| Spread, slippage, DD, pause/resume, position management work in the tester and on demo | Visual test + `events.csv` (`DD/TRIGGER`, `SAFETY_CHECK`, `DD/RESUME`); tip: set **Drawdown threshold (%)** to 1 on a demo to see the sequence quickly. |
| Logs exportable | docs/06. |
| Tester reports per engine/symbol + combination | Test campaign of docs/07 (client side). |
| MQ5 + EX5 + SET / MQ4 + EX4 + SET, perpetual use | Sources + presets delivered; EX files from step 1. |
| MT5 and MT4 simultaneously on one PC / one VPS; several PCs | Attach both EAs at the same time (different terminals); check both trade and both write their own folders. |
| Magic / Strategy / Instance IDs isolate instances; multi-instance protection on one account | Run two charts with Instance ID 1 and 2 on the same account; then the same ID twice -> `INSTANCE/DUPLICATE` event and no new entries from the second chart. |
| H1 OFF / SOFT / STRICT per addendum | Section 7; `H1` log lines; `signals.csv` reason `H1_STRICT` only in STRICT. |
| News / session / rollover / consecutive-loss / risk modes / exposure / restart / retries | Sections 8 and 9; each has its own `events.csv` category. |
| Momentum on real ticks, period and data quality documented | docs/07 step 3 (record the period and the MT5 "History quality" % of every run). |
| Reports show IS / OOS / sensitivity / degraded execution; no artificial 90 % | docs/07; `stats.csv` of the `_STRESS` runs. |
| Tick-by-tick event-driven architecture; latency measured; delays 1500 / 750 / 300 ms present | Sections 1, 8, 9. |
| No automatic definitive daily stop | Section 9. |
| G.1-G.4 in both platforms | Section 12. |
