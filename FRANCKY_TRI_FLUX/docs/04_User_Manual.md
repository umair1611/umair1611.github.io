# FRANCKY TRI-FLUX — User Manual (MT5 and MT4)

Version 1.00 · HFT-style retail ultra-scalping Expert Advisor · Markets: **EURUSD, XAUUSD, BTCUSD**

> Every setting in this manual is written with the name you see in the EA **Inputs** tab
> (for example **Trading mode (SPEED / AGGRESSIVE / ULTRA)**). The complete list with default values,
> per-symbol values and optimisation ranges is in **05 - Input Parameters Reference**.

---

## 1. What FRANCKY does — in one page

FRANCKY is a very fast scalping robot. It reads **every tick** and runs **three independent strategies
("engines")** at the same time on the chart symbol:

| Engine | Idea in plain words | Typical holding time |
|---|---|---|
| **A - Momentum / Micro-breakout** | Price suddenly speeds up and breaks a tiny range of the last 20 ticks, with most ticks going the same way. FRANCKY jumps in with the move. | seconds |
| **B - FVG (Fair Value Gap)** | A fast M5 move leaves a "gap" between candle 1 and candle 3. When price comes back into that gap, FRANCKY trades the expected reaction. | seconds to minutes |
| **C - Range / Mean Reversion** | When the market goes sideways, FRANCKY buys near the bottom of the range and sells near the top, aiming at the middle. | seconds to minutes |

* Each engine can open a trade **on its own**. No engine waits for another one, and no "global score" exists.
* Up to **3 positions per engine** and **9 per symbol** (adjustable). These are limits, not targets.
* Before any order, a **safety gate** checks spread, news, session, rollover, drawdown, volatility,
  exposure, broker rules, and so on. If a check fails, the trade is refused and the reason is written in
  the log and shown on the chart.
* Open trades are managed automatically: **break-even**, **short trailing stop**, **time-stop** and
  strategy-specific emergency exits.
* **One FRANCKY = one chart symbol.** FRANCKY on EURUSD trades only EURUSD. To trade XAUUSD and BTCUSD
  too, open two more charts and attach FRANCKY to each (with a different **Instance ID**).

> **Important:** no robot can guarantee profits or a win rate. The ~90 % win rate in the specification is a
> research target. Always test on a demo account first.

---

## 2. What you receive

| Folder / file | What it is |
|---|---|
| `MQL5/Experts/FranckyTriFlux/FranckyTriFlux.mq5` | MT5 Expert Advisor (source). Compile once to get the `.ex5`. |
| `MQL5/Include/FranckyTriFlux/...` | MT5 program modules (required to compile). |
| `MQL5/Presets/FranckyTriFlux/*.set` | Ready settings for EURUSD, XAUUSD, BTCUSD (MT5). |
| `MQL5/Scripts/FranckyTriFlux/FranckyNewsExporter.mq5` | MT5 script that exports the economic calendar to a news file (for MT4 and backtests). |
| `MQL4/...` | The same for MT4 (`FranckyTriFlux.mq4`, modules, presets). |
| `Tester/MT5`, `Tester/MT4` | Strategy Tester configuration files (.ini + .set) for every engine and symbol. |
| `docs/` | This manual and the technical documents. |
| `tools/` | Report and configuration tools (Python, optional). |

There is **no licence key, no expiry, no account lock and no DLL**. You can install FRANCKY on as many
computers, VPSs, accounts and terminals as you want, forever.

---

## 3. Requirements

* MetaTrader 5 (recommended: latest build) and/or MetaTrader 4 (build 1400 or later).
* A **hedging** account for MT5 (several positions per symbol). On a netting account FRANCKY works but
  limits itself to 1 position per symbol.
* Low latency matters: a VPS close to your broker server is recommended (FRANCKY measures and shows the
  real order latency). One VPS can run MT5 and MT4 at the same time.
* AutoTrading enabled (MT5 "Algo Trading" button / MT4 "AutoTrading" button).

---

## 4. Installation

### 4.1 MT5
1. In MetaTrader 5 click **File > Open Data Folder**.
2. Copy the delivered `MQL5` folder into the data folder (merge with the existing `MQL5` folder).
3. Open **MetaEditor** (F4), open `MQL5\Experts\FranckyTriFlux\FranckyTriFlux.mq5`, press **F7 (Compile)**.
   The result must show **0 errors**. (Delivered packages already contain the compiled `.ex5`.)
4. Also compile `MQL5\Scripts\FranckyTriFlux\FranckyNewsExporter.mq5` (optional, for news files).
5. Back in MT5, right-click **Expert Advisors** in the Navigator > **Refresh**.

### 4.2 MT4
Same steps with the `MQL4` folder and `FranckyTriFlux.mq4` (MetaEditor 4).

### 4.3 Optional: news feed on MT4 (live)
MT4 has no built-in calendar. Two free options:
* **CSV file (recommended):** run `FranckyNewsExporter` on any MT5 terminal of the same PC (once a week).
  It writes `Common\Files\FranckyTriFlux\news.csv`, which MT4, MT5 and the strategy testers can read.
* **Web feed:** set **News source** = *Web XML feed* and add
  `https://nfs.faireconomy.media` in **Tools > Options > Expert Advisors > Allow WebRequest for listed URL**.

---

## 5. Quick start (5 minutes)

1. Open a chart of **EURUSD** (any timeframe; M1 is convenient to watch the trades).
2. Drag **FranckyTriFlux** onto the chart.
3. In the **Inputs** tab click **Load** and choose `FranckyTriFlux_MT5_EURUSD.set` (or `_MT4_` on MT4).
4. Check **Instance ID** (1 for the first chart, 2 for the second ...).
5. Check **Risk per trade (%)** (default 0.25 %).
6. Tick **Allow Algo Trading** (MT5) / **Allow live trading** (MT4), click **OK**.
7. The dashboard appears in the top-left corner. After a short warm-up (~30-60 s) the status line shows
   **RUNNING**.

Repeat on XAUUSD and BTCUSD charts with their own presets and **Instance ID** 2 and 3.

> Brokers often add a suffix (EURUSD.m, XAUUSDm, GOLD, BTCUSD.r). FRANCKY recognises them. Use the
> preset of the matching market.

---

## 6. Running several instances, MT4 + MT5, several PCs

* **Several symbols:** one chart per symbol, each with its own **Instance ID**. Magic numbers are built
  automatically: `Magic number base + Instance ID x 10 + engine` (1 Momentum, 2 FVG, 3 Range).
* **Same Instance ID twice on the same account and symbol** is detected: the second chart refuses new
  trades and shows **MULTI_INSTANCE** (setting **MULTI_INSTANCE_GUARD**).
* An instance **never** modifies or closes a trade of another instance or of another EA.
* **MT4 and MT5 together:** fully independent (different default magic base: MT5 5 100 000, MT4 4 100 000).
  Closing one platform never stops the other.
* **Several PCs / VPSs:** just install and run. Use different **Instance ID**s if two installations trade the
  same account and symbol.

---

## 7. The three engines — what to know

### 7.1 Engine A — Momentum / Micro-breakout
Looks at the last **Tick window for imbalance (ticks)** ticks (50) and buys when:
* at least **BUY: min bullish tick ratio** of them went up (62 %),
* the tick speed of the last 2 s is at least **Min velocity / median velocity** (1.25x) the usual speed of the
  last 30 s, and it is accelerating (**Min acceleration** +20 %),
* price breaks above the high of the last **Micro-range length (ticks)** ticks (20) plus a small buffer,
* the short-term momentum agrees (**Confirm with ROC direction**).
Sells in the mirror situation. TP and SL follow the market volatility (ATR) and the spread:
TP = max(1.2 x spread, 0.18 x ATR), SL = max(2 x spread, 0.35 x ATR).
It exits early when momentum fades and ticks turn against the trade for about 0.5 s
(**Momentum-loss exit ON**). Time-stop: **Time-stop (s, 0 = off)** (EURUSD 45 s, XAUUSD/BTCUSD 30 s).

### 7.2 Engine B — FVG
On M5 (**FVG timeframe**) FRANCKY finds gaps where candle 3 does not overlap candle 1. It keeps up to
**Max zones kept** zones, drops old ones (**Max zone age (bars)**) and zones touched too often
(**Max mitigations**). It enters when price returns to a zone:
* **TOUCH** - at the first touch of the zone edge (default, most active),
* **CE 50 %** - at the middle of the gap,
* **REJECTION** - after a candle rejects the zone.
SL goes behind the zone; TP goes to the next swing (liquidity), limited between **TP min R** and **TP max R**.
Optional BOS/CHoCH confirmation: **BOS_REQUIRED** (OFF by default). If a zone breaks while a trade is open,
the trade is closed (**Exit open trade if zone invalidated**).

### 7.3 Engine C — Range / Mean Reversion
On M1 (**Range timeframe**) FRANCKY recognises a sideways market (low ADX, flat EMAs, limited width).
It buys in the lowest **Entry zone near boundary (% of width)** (20 %) of the range when price slows down or
rejects the bottom and buyers come back; sells near the top in the opposite case. TP = middle of the range
(or opposite side). It never fights a strong impulse (**Max tick velocity ratio**, **Max ATR / median ATR**)
and exits quickly when the range breaks (**Exit quickly on confirmed breakout**).

### 7.4 Turning engines on/off
**Engine A - Momentum / Micro-breakout ON**, **Engine B - FVG (Fair Value Gap) ON**,
**Engine C - Range / Mean Reversion ON**. With only one engine ON, only that engine trades (isolation test).

---

## 8. Modes: SPEED / AGGRESSIVE / ULTRA
**Trading mode** selects how often each engine may enter and the spread limit:

| Mode | Delay (default) | Max spread setting used |
|---|---|---|
| SPEED | **SPEED mode entry delay (ms)** 1500 | **Max spread SPEED** |
| AGGRESSIVE | **AGGRESSIVE mode entry delay (ms)** 750 | **Max spread AGGRESSIVE** |
| ULTRA | **ULTRA mode entry delay (ms)** 300 | **Max spread ULTRA** |

**How the mode delay is applied**: *Cooldown* (default) = minimum time between two entries of the same
engine; *Confirm* = the signal must stay valid during the whole delay before the order is sent; *Both*.

---

## 9. H1 filter (OFF / SOFT / STRICT)
**H1_FILTER mode** decides how the H1 trend (EMA20/50 + ADX/DI) is used:
* **OFF** - ignored.
* **SOFT** (default) - shown on the dashboard and written in the logs, **never blocks** a trade, never
  reduces the lot.
* **STRICT** - Momentum and FVG: no SELL when H1 is clearly BULLISH, no BUY when H1 is clearly BEARISH.
  Range: no new range trade while H1 shows a strong trend (**H1 'strong trend' ADX**). A NEUTRAL H1 never
  blocks anything.

---

## 10. Risk management
* **RISK_MODE**: *Fixed lot* (uses **Fixed lot**), *% of balance* or *% of equity* (uses **Risk per trade
  (%)**). The lot is always computed from the **real stop-loss distance** of the trade.
* **Max risk per trade - hard cap (%)** and **Max lot per trade** are never exceeded (also with martingale).
* **Max total open risk, this instance (%)** and **Max total open lots** limit the total exposure.
* **Aggregate exposure mode** checks the risk of all FRANCKY trades on the account together
  (EURUSD + XAUUSD + BTCUSD), especially the USD exposure: **Max open risk all symbols**, **Max net risk per
  currency**.
* **SL/TP ratio guard** (max SL / TP = 2) refuses trades whose stop is too large versus the target.
* **Martingale ON (optional)** is OFF by default. Even when ON, a new valid setup is always required and all
  caps apply.
* Broker limits (minimum/maximum lot, lot step, margin, stop level) are always respected.

---

## 11. Protections (what can stop new trades)
Open positions are **always** managed, whatever protection is active. Protections only stop NEW entries.

| Protection | Setting(s) | Behaviour |
|---|---|---|
| **10 % equity drawdown pause** | **Equity drawdown pause ON**, **Drawdown threshold (%)**, **Pause length (s)** | At -10 % FRANCKY stops new entries, re-activates and checks all its safeties (written in the log), keeps managing open trades and **restarts automatically after 10 seconds** (strict timer). The next pause needs a further 10 % drop. There is no automatic daily stop. |
| **News** | **NEWS_FILTER ON**, **Min impact**, **Currencies**, **Keywords always blocked**, **Block minutes BEFORE/AFTER news** | No new trades around important news (NFP, CPI, FOMC, rate decisions...). Restarts automatically after the window. |
| **Sessions / days** | **SESSION_FILTER ON**, **Session preset**, **TradingStart/End**, **Trade Monday ... Sunday** | Trade only during chosen hours/days. OFF by default (24 h; needed for BTCUSD weekends). |
| **Rollover** | **ROLLOVER_FILTER ON**, **Rollover time**, minutes before/after | No new trades around the daily rollover (spreads widen). |
| **Consecutive losses** | **CONSECUTIVE_LOSS_PROTECTION ON**, **Consecutive losses X**, **Cooldown Y (minutes)**, **Scope** | After X losses in a row, pause Y minutes; afterwards only a NEW setup can trade. |
| **Spread** | mode spread limits / **Auto max spread** | Refuses trades when the spread is too wide. |
| **Abnormal volatility** | **Volatility anomaly: ...** | Refuses trades during abnormal ATR, tick bursts or spread spikes. |
| **Execution quality** | **Execution-quality action**, **Max avg adverse slippage**, **Max avg order latency** | If fills become bad, block or reduce lots for a while. |
| **Broker errors** | **Max retries per order**, **Delay between retries**, **Pause after a permanent broker error** | Smart retries (signal re-checked before each retry); pause after errors such as "no money" or "market closed". |
| **Multi-instance** | **MULTI_INSTANCE_GUARD** | Prevents two charts with the same Instance ID and cross-instance duplicate trades. |
| **Restart recovery** | **Save and restore state after restart**, **No new entries after start (s)** | After a restart/reconnection FRANCKY finds its open trades, restores cooldowns/pauses and avoids duplicates. |

---

## 12. Trade management
For each engine (settings with the same names in the Momentum, FVG and Range groups):
* **Break-even trigger (% of TP distance)** (70 %) moves the stop to entry + **Break-even lock** (5 %).
* **Trailing trigger (% of TP distance)** (85 %) starts a short trailing stop at **Trailing distance** (25 %).
* **Time-stop (s, 0 = off)** closes a trade after that time; **Hard max holding time, all engines** (120 s)
  is an absolute limit.
* **Max simultaneous positions** per engine (3) and **Max total positions on this symbol** (9).
* **OPPOSITE_HEDGE** OFF: no BUY and SELL at the same time on the symbol.

---

## 13. Reading the chart

### 13.1 Dashboard (top-left)
| Row | Example | Meaning |
|---|---|---|
| 1 | `FRANCKY TRI-FLUX v1.00 | MT5 | EURUSD | AGGRESSIVE | I1 | magic 5100011-13` | Identity of this instance. |
| 2 | `STATUS: RUNNING - entries allowed` (green) / `BLOCKED: NEWS USD NFP 14:30 (-3m)` (orange) / `DD PAUSE 7s` (red) | Why trades are allowed or not, with the reason code. |
| 3 | `Equity 10 234.55 | DD 2.1% / 10% ARMED | pauses 0` | Drawdown protection. |
| 4 | `Spread 1.2 pts (max 15) | ATR M1 12.3 pts (median 10.1)` | Market conditions. |
| 5 | `Ticks vel 1.42x acc +31% | imbalance 66% up | latency avg 7.2 ms` | Tick micro-structure and execution speed. |
| 6 | `H1 BULLISH (ADX 24.5) | filter SOFT` | H1 context. |
| 7-9 | `[M] Momentum ON | pos 1/3 | ...` | One line per engine: positions, live measures, last decision or reason. |
| 10 | `Positions 2/9 | BUY 2 SELL 0 | open risk 0.4% | float +3.20` | Open trades of this instance. |
| 11 | `Today trades 12 | WR 83% | net +23.40 | top rejects SPREAD:40 NEWS:12` | Today's statistics. |
| 12-15 | News / session / rollover / consecutive losses / execution quality / exposure / instance lock / clock | State of every protection. |
| 16-17 | `Last signal ...` / `Last event ...` | The latest decisions. |

### 13.2 Chart drawings
| Drawing | Meaning |
|---|---|
| Green up arrow / red down arrow + small text (`MOM BUY 0.10 | reason`) | Entry, with engine and reason. Colour of the text: blue = Momentum, orange = FVG, purple = Range. |
| Gold cross + dotted line (green = profit, red = loss) | Exit, with exit reason (TP, SL, BREAKEVEN_SL, TRAILING_SL, TIME_STOP, MOMENTUM_LOSS, FVG_INVALIDATED, RANGE_BREAKOUT...). |
| Green / red rectangles | Bullish / bearish FVG zones (lighter = already touched, grey = invalidated or expired); dotted line = 50 % (CE). |
| Purple rectangle with dotted middle line | Active range (grey = broken). |
| Two short blue lines | The micro-range broken by a Momentum entry. |
| Vertical lines with a title | Upcoming news events (blocked window). |
| Small grey markers (optional) | Refused signals with their reason (**Draw rejected signals**). |

---

## 14. Logs and files (for checking and for support)
Files are written to `Terminal\Common\Files\FranckyTriFlux\` (setting **Log files in Common\Files**, ON by
default). Open it from MetaTrader with *File > Open Data Folder*, go up two levels, then `Common\Files`.

| File | Use |
|---|---|
| `ftf.log` | Readable diary: every decision, protection change, order, error and its reason. |
| `signals.csv` | One line per setup found: accepted or refused, with the reason (open in Excel; separator `;`). |
| `trades.csv` | One line per closed trade: engine, prices, spread, slippage, latency, lot, SL, TP, entry/exit reasons, duration, PnL, MAE/MFE, equity and drawdown. |
| `events.csv` | Protections (pauses, news windows...), safety checks, broker errors and retries, restart recovery. |
| `stats.csv` | Statistics per engine and total: setups/day, trades/day, win rate, profit factor, expectancy, drawdown... |

Live/demo runs use the folder `MT5_EURUSD_I1` (platform_symbol_instance); every backtest gets its own
`TEST_...` folder. For support, zip the folder of the run and send it.

**Log level**: INFO is enough for daily use. Use DEBUG to understand why setups are refused, TRACE only for
short bug hunts (very large files).

---

## 15. Backtesting in a few lines
1. MT5: use **Every tick based on real ticks** (Momentum needs real ticks).
2. Export news for the test period with `FranckyNewsExporter` (calendar functions do not work in the
   tester).
3. Set **Manual broker GMT offset (winter, hours)** and **Manual offset follows US DST** for your broker.
4. Test each engine alone first, then all three together (ready files in `Tester/`).
5. Read `docs/07_Testing_and_Optimization_Protocol.md` for the full protocol, optimisation and reports.

---

## 16. Troubleshooting

| What you see | Meaning | What to do |
|---|---|---|
| `BLOCKED: TERMINAL` | AutoTrading is off, EA trading not allowed, or not connected. | Turn on Algo Trading / Allow live trading; check connection. |
| `BLOCKED: WARMUP` | Collecting data after start (indicators, ticks) or restart grace period. | Wait 30-60 s (MT4: Momentum needs ~32 s of live ticks). |
| `BLOCKED: SPREAD` | Spread above the limit of the mode. | Normal at rollover/news; adjust **Max spread ...** to your broker's typical spread. |
| `BLOCKED: STALE_TICK` | No price for a long time (market closed). | Normal at weekends for EURUSD/XAUUSD. |
| `BLOCKED: NEWS ...` | Inside a news window. | Normal. |
| `BLOCKED: DD_PAUSE` | 10 % drawdown pause (10 s). | Restarts by itself. |
| `MULTI_INSTANCE` | Another chart uses the same Instance ID on this account/symbol. | Give each chart its own **Instance ID**. |
| Engine line says `warming ticks` | Momentum needs 30 s of tick history. | Wait. |
| Many `HEDGE_OFF` rejections | A trade in the opposite direction is open (hedging disabled). | Normal; or enable **OPPOSITE_HEDGE** (not recommended). |
| Many `MAX_POS_ENGINE` | The engine already has its maximum positions. | Normal; adjust **Max simultaneous positions**. |
| `RISK` rejections | The broker's minimum lot would risk more than **Max risk per trade - hard cap**. | Increase the capital/hard cap or allow **Allow broker min lot even if above max risk**. |
| `STOPS NOT ATTACHED` in log | The broker refused the SL/TP after the fill. | Enable **Send SL/TP after the fill (ECN brokers)**; contact the broker. |
| News filter never blocks (MT4/tester) | No news file. | Run `FranckyNewsExporter` or use the web feed (live). |
| No trades at all | Check the dashboard status line and engine lines: they always say why. | Look at `signals.csv` reasons. |

---

## 17. FAQ
**Does FRANCKY close my manual trades?** No. It only touches its own magic numbers on its own chart symbol.

**Can I change settings while trades are open?** Yes. FRANCKY restarts with the new settings and resumes the
management of its open trades.

**What happens after a VPS restart?** FRANCKY reloads its state, finds its open trades, logs any trade closed
while it was offline, waits a few seconds and continues. It does not open duplicate trades.

**Can I trade BTCUSD at weekends?** Yes if your broker allows it: the BTCUSD preset enables Saturday and
Sunday and keeps the session filter OFF.

**Is the 90 % win rate guaranteed?** No. It is a research objective; robustness, expectancy and drawdown come
first.
