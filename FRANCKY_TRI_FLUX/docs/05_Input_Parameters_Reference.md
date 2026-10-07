# 05 - Input Parameters Reference

> Generated from `tools/ftf_spec.py` by `tools/generate.py`. Parameter names below are the names shown in the
> MetaTrader **Inputs** tab (the text after `//` in the source). MT5 and MT4 use the same names and defaults
> unless stated. Per-symbol values are those of the delivered `.set` presets.

Legend: **Opt range** = start / step / stop written in the optimization `.set` files.


## 01. GENERAL / INSTANCE

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Enable new entries (master switch)** | true | same |  | OFF = the EA keeps managing open positions (BE, trailing, time-stops, exits) but opens nothing new. |
| **Trading mode (SPEED / AGGRESSIVE / ULTRA)** | AGGRESSIVE (delay 750 ms) | same |  | Reactivity profile. Selects the entry delay and the maximum spread used by all three engines. Choices: SPEED (delay 1500 ms); AGGRESSIVE (delay 750 ms); ULTRA (delay 300 ms). |
| **Instance ID (1-999, unique per chart on one account)** | 1 | same |  | Identifies this chart/instance. Two charts on the same account and symbol must use different IDs. |
| **Magic number base (magic = base + ID x 10 + engine)** | 5100000 (MT4: 4100000) | same |  | Momentum = base+ID*10+1, FVG = +2, Range = +3. MT5 and MT4 use different default bases. |
| **Order comment prefix** | "FTF" | same |  | Short text written in every order comment (brokers may truncate comments; the magic number is the real ID). |
| **Supported-symbol check (EURUSD/XAUUSD/BTCUSD)** | WARN on unsupported symbol | same |  | The V1 markets are EURUSD, XAUUSD and BTCUSD (broker suffixes such as EURUSD.m are recognised). WARN only warns; BLOCK refuses new entries on any other symbol. Choices: OFF; WARN on unsupported symbol; BLOCK entries on unsupported symbol. |
| **Internal timer period (ms)** | 250 | same |  | Background heartbeat for pauses, retries, dashboard and state saving when no tick arrives. |

## 02. STRATEGY ENGINES ON/OFF

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Engine A - Momentum / Micro-breakout ON** | true | same |  | Turns the Momentum engine on or off. Each engine is independent; no engine waits for another. |
| **Engine B - FVG (Fair Value Gap) ON** | true | same |  | Turns the FVG engine on or off. |
| **Engine C - Range / Mean Reversion ON** | true | same |  | Turns the Range engine on or off. |

## 03. MODES - DELAYS AND SPREAD LIMITS

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **SPEED mode entry delay (ms)** | 1500 | same | 500 / 250 / 2500 | Initial value 1500 ms (spec Table 15). |
| **AGGRESSIVE mode entry delay (ms)** | 750 | same | 250 / 125 / 1500 | Initial value 750 ms. |
| **ULTRA mode entry delay (ms)** | 300 | same | 0 / 50 / 600 | Initial value 300 ms. |
| **How the mode delay is applied** | Cooldown between entries of the same engine | same |  | Cooldown = minimum time between two entries of the same engine. Confirm = the signal must stay valid for the whole delay before the order is sent. Both = both rules. Choices: Cooldown between entries of the same engine; Signal must stay valid during the delay; Both cooldown and confirmation. |
| **Max spread SPEED (points, 0 = auto)** | 0 | 12 / 35 / 0 (auto) |  | Entry refused when spread is above this value. 0 = automatic limit (see 'Auto max spread'). |
| **Max spread AGGRESSIVE (points, 0 = auto)** | 0 | 15 / 40 / 0 (auto) |  | As above, for AGGRESSIVE. |
| **Max spread ULTRA (points, 0 = auto)** | 0 | 18 / 45 / 0 (auto) |  | As above, for ULTRA. |
| **Auto max spread (x ATR M1) when limit = 0** | 0.3 | same |  | Used only when the mode limit is 0: spread must be <= this fraction of ATR(14) M1. |

## 04. MARKET DATA / VOLATILITY

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **ATR period (M1 / M5)** | 14 | same |  | ATR(14) is the spec value. |
| **ATR median length (M1 bars)** | 50 | same |  | Median of the last 50 M1 ATR values (spec Table 18). |
| **Tick history kept in memory (s)** | 120 | same |  | Must exceed the velocity reference window. MT5 pre-loads this history at start. |
| **Max tick age before market considered stale (s)** | 60 | 60 / 60 / 120 |  | No new entries when the last tick is older than this (market closed / feed problem). |
| **Volatility anomaly: ATR > x median ATR** | 3.0 | same |  | Blocks new entries when ATR(M1) is abnormally high versus its median. 0 = off. |
| **Volatility anomaly: tick velocity > x median** | 6.0 | same |  | Blocks new entries during abnormal tick bursts. 0 = off. |
| **Volatility anomaly: spread > x median spread** | 3.0 | same |  | Blocks new entries when spread widens abnormally versus its recent median. 0 = off. |

## 05. H1 CONTEXT FILTER (OFF / SOFT / STRICT)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **H1_FILTER mode** | SOFT - context only, never blocks | same |  | OFF: H1 ignored. SOFT (default): shown and logged, never blocks, never reduces the lot. STRICT: can block entries against a clear H1 trend (rules per engine below). Choices: OFF - H1 ignored; SOFT - context only, never blocks; STRICT - may block entries against clear H1 trend. |
| **H1 fast EMA period** | 20 | same |  | EMA20 (spec A.1). |
| **H1 slow EMA period** | 50 | same |  | EMA50 (spec A.1). |
| **H1 ADX period** | 14 | same |  | ADX(14). |
| **H1 ADX directional threshold** | 18.0 | same | 14.0 / 2.0 / 30.0 | BULLISH/BEARISH requires ADX above this value. Initial 18. |
| **H1 min +DI/-DI gap** | 0.0 | same |  | Dominant DI must exceed the other by at least this value. |
| **H1 'strong trend' ADX (Range STRICT)** | 25.0 | same |  | In STRICT, Range entries are blocked only when H1 is BULLISH/BEARISH and ADX >= this value. Set equal to the directional threshold to use the plain A.1 definition. |
| **STRICT applies to Momentum** | true | same |  | In STRICT, block Momentum entries opposite to a clear H1 trend. |
| **STRICT applies to FVG** | true | same |  | In STRICT, block FVG entries opposite to a clear H1 trend. |
| **STRICT applies to Range** | true | same |  | In STRICT, block NEW Range entries while a strong H1 trend is established. |

## 06. ENGINE A - MOMENTUM / MICRO-BREAKOUT

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Tick window for imbalance (ticks)** | 50 | same | 30 / 10 / 80 | Spec: 50 ticks. |
| **BUY: min bullish tick ratio** | 0.62 | same | 0.56 / 0.02 / 0.7 | Spec: >= 62% bullish ticks. |
| **SELL ratio = 1 - BUY ratio (symmetric)** | true | same |  | When ON, the SELL threshold is 1 - BUY ratio (0.38 for 0.62) and the next input is ignored. |
| **SELL: max bullish tick ratio** | 0.38 | same |  | Spec: <= 38% bullish ticks. Used only when symmetric is OFF. |
| **Count unchanged ticks in the ratio** | false | same |  | OFF: ratio = up / (up + down). ON: ratio = up / all ticks. |
| **Velocity metric** | Tick count per window | same |  | Tick count (default) or price path per window. Choices: Tick count per window; Price path (sum of /price changes/). |
| **Velocity window (ms)** | 2000 | same | 1000 / 500 / 3000 | Spec: 2 s. |
| **Velocity reference window for median (ms)** | 30000 | same |  | Spec: median over 30 s. |
| **Min velocity / median velocity** | 1.25 | same | 1.0 / 0.05 / 1.6 | Spec: >= 1.25x. |
| **Min acceleration (0.20 = +20%)** | 0.2 | same | 0.0 / 0.05 / 0.4 | Velocity growth versus the previous window. Spec: +20%. |
| **Micro-range length (ticks)** | 20 | same | 10 / 5 / 40 | Spec: 20 ticks. |
| **Breakout buffer (x spread)** | 0.15 | same |  | Buffer = max(0.15 x spread, 0.02 x ATR). |
| **Breakout buffer (x ATR M1)** | 0.02 | same |  | See above. |
| **Confirm with ROC direction** | true | same |  | Directional momentum must agree: ROC > 0 for BUY, < 0 for SELL. |
| **ROC period (M1 bars)** | 5 | same |  | Spec: ROC(5). |
| **Min /ROC/ (%)** | 0.0 | same |  | Minimum absolute ROC value in percent. |
| **Confirm with M1 EMA fast/slow** | false | same |  | Optional internal confirmation (EMA9 > EMA21 for BUY). |
| **M1 fast EMA period** | 9 | same |  | Spec Table 18: EMA9. |
| **M1 slow EMA period** | 21 | same |  | Spec Table 18: EMA21. |
| **Confirm with M1 ADX/DI** | false | same |  | Optional: ADX >= threshold and DI in trade direction. |
| **M1 ADX min** | 18.0 | same |  | Spec Table 18: initial ADX threshold 18. |
| **M5 EMA20/50 context** | SOFT (log only) | same |  | SOFT = informational only (spec). STRICT = M5 trend must agree. Choices: OFF; SOFT (log only); STRICT (must agree). |
| **TP = max(x spread, ...)** | 1.2 | same |  | Spec: TP = max(1.2 x spread, 0.18 x ATR). |
| **TP = max(..., x ATR M1)** | 0.18 | same | 0.12 / 0.02 / 0.3 | See above. |
| **SL = max(x spread, ...)** | 2.0 | same |  | Spec: SL = max(2 x spread, 0.35 x ATR). |
| **SL = max(..., x ATR M1)** | 0.35 | same | 0.25 / 0.05 / 0.5 | See above. |
| **Signal validity (ms)** | 500 | same |  | A Momentum signal older than this is discarded. |
| **Momentum-loss exit ON** | true | same |  | Exit when the internal score drops and ticks invert persistently. |
| **Exit when momentum score below** | 60.0 | same |  | Spec: score < 60. |
| **Tick inversion persistence (ms)** | 500 | same |  | Spec: about 500 ms. |
| **Inversion window (ticks)** | 10 | same |  | Ticks used to detect an inversion against the trade. |
| **Time-stop (s, 0 = off)** | 45 | 45 / 30 / 30 | 20 / 5 / 90 | Spec: EURUSD 45 s, XAUUSD 30 s. BTCUSD starts at 30 s and MUST be optimized (GBPUSD value not copied). |
| **Max simultaneous positions (Momentum)** | 3 | same |  | Spec G.2: up to 3 per engine, adjustable. |
| **Break-even trigger (% of TP distance)** | 70.0 | same | 50.0 / 5.0 / 90.0 | Spec: 70%. |
| **Break-even lock (% of TP distance)** | 5.0 | same |  | Profit locked when SL moves to break-even. |
| **Trailing trigger (% of TP distance)** | 85.0 | same | 70.0 / 5.0 / 95.0 | Spec: 85%. |
| **Trailing distance (% of TP distance)** | 25.0 | same |  | Short trailing distance. |
| **Trailing min step (% of TP distance)** | 5.0 | same |  | Minimum SL improvement before a modification is sent. |

## 07. ENGINE B - FVG (FAIR VALUE GAP)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **FVG timeframe** | M5 | same |  | Spec: M5. |
| **Use M1 for entry precision** | false | same |  | Spec: optional M1 refinement (used by REJECTION mode). |
| **Bars scanned for FVGs** | 60 | same |  | History scanned on start and kept in memory. |
| **Max zones kept** | 20 | same |  | Oldest zones are dropped beyond this number. |
| **Min gap size (x ATR of FVG timeframe)** | 0.25 | same | 0.1 / 0.05 / 0.6 | Gap filter relative to ATR. |
| **Min gap size (x spread)** | 2.0 | same |  | Gap must also exceed this multiple of the spread. |
| **Max zone age (bars)** | 48 | same | 12 / 12 / 96 | Older zones expire. |
| **Max mitigations (returns into zone)** | 2 | same | 1 / 1 / 3 | Zone stops trading after this number of returns. |
| **Max price distance to zone (x ATR)** | 1.5 | same |  | Zones farther than this are ignored for entries. |
| **Entry mode (TOUCH / CE 50% / REJECTION)** | TOUCH - first touch of the zone edge | same |  | To be compared in backtests (spec). Choices: TOUCH - first touch of the zone edge; CE - 50% of the gap; REJECTION - candle rejects the zone. |
| **REJECTION: min wick (% of candle range)** | 30.0 | same |  | Wick into the zone required for REJECTION mode. |
| **BOS_REQUIRED (structure confirmation)** | false | same |  | Spec default false. When true, the displacement must create a BOS/CHoCH (next input). |
| **Structure event accepted when required** | BOS | same |  | BOS, CHoCH or either. Choices: BOS; CHoCH; BOS or CHoCH. |
| **Swing strength (bars each side)** | 3 | same |  | Fractal swing definition for BOS/CHoCH and liquidity targets. |
| **Structure lookback (bars)** | 120 | same |  | Bars scanned for swings. |
| **Invalidation buffer (x ATR)** | 0.1 | same |  | Zone invalidated by a close beyond its far edge + buffer. |
| **Invalidate on candle close (else on tick)** | true | same |  | ON: needs a closed candle beyond the edge. OFF: first tick beyond the edge + buffer. |
| **SL anchor** | Beyond the FVG invalidation edge | same |  | Beyond zone invalidation edge or beyond the 3-candle swing. Choices: Beyond the FVG invalidation edge; Beyond the 3-candle swing extreme. |
| **SL buffer (x spread)** | 1.0 | same |  | SL buffer = max(x spread, x ATR). |
| **SL buffer (x ATR)** | 0.1 | same |  | See above. |
| **TP mode** | Next liquidity / swing (fallback R multiple) | same |  | Next liquidity/swing, ATR multiple or R multiple. Choices: Next liquidity / swing (fallback R multiple); ATR multiple; R multiple of SL distance. |
| **TP ATR multiple** | 1.0 | same |  | Used by TP mode ATR. |
| **TP R multiple** | 1.0 | same | 0.5 / 0.25 / 2.0 | Used by TP mode RR and as liquidity fallback. |
| **TP min R (liquidity mode)** | 0.5 | same |  | Liquidity targets closer than this R are skipped. |
| **TP max R (liquidity mode)** | 2.0 | same |  | Liquidity targets are capped at this R. |
| **Max trades per zone** | 1 | same |  | Duplicate protection: one zone = this many trades max. |
| **Signal validity (ms)** | 1000 | same |  | An FVG signal older than this is discarded. |
| **Exit open trade if zone invalidated** | true | same |  | Close FVG positions when their zone is invalidated. |
| **Time-stop (s, 0 = off)** | 120 | same | 60 / 60 / 600 | Initial ceiling 120 s; may need a higher value for M5 setups (test). |
| **Max simultaneous positions (FVG)** | 3 | same |  | Spec G.2: up to 3 per engine. |
| **Break-even trigger (% of TP distance)** | 70.0 | same |  | Spec: 70%. |
| **Break-even lock (% of TP distance)** | 5.0 | same |  | Profit locked at break-even. |
| **Trailing trigger (% of TP distance)** | 85.0 | same |  | Spec: 85%. |
| **Trailing distance (% of TP distance)** | 25.0 | same |  | Short trailing. |
| **Trailing min step (% of TP distance)** | 5.0 | same |  | Minimum SL improvement per modification. |

## 08. ENGINE C - RANGE / MEAN REVERSION

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Range timeframe (M1 or M5)** | M1 | same |  | Spec: M1/M5. |
| **Range lookback (bars)** | 30 | same | 20 / 10 / 60 | Range = highest high / lowest low of these closed bars. |
| **ADX period** | 14 | same |  | Range needs weak/falling ADX. |
| **Max ADX for a range** | 20.0 | same | 15.0 / 2.5 / 30.0 | ADX must be below this value. |
| **Require falling ADX** | false | same |  | ADX now <= ADX n bars ago. |
| **ADX slope bars** | 3 | same |  | Look-back for 'falling ADX'. |
| **Fast EMA period** | 20 | same |  | EMA20 (spec). |
| **Slow EMA period** | 50 | same |  | EMA50 (spec). |
| **Max /EMA20-EMA50/ (x ATR)** | 0.3 | same | 0.1 / 0.05 / 0.6 | Low EMA separation relative to ATR. |
| **Min range width (x ATR)** | 1.0 | same | 0.5 / 0.25 / 2.0 | Width must exceed this ATR multiple. |
| **Min range width (x spread)** | 4.0 | same |  | Width must exceed this multiple of the spread. |
| **Max range width (x ATR)** | 6.0 | same |  | Wider 'ranges' are treated as trends. |
| **Max net drift (% of width)** | 50.0 | same |  | No significant directional swing: /close now - close at lookback start/ <= this % of width. |
| **Min touches per boundary** | 1 | same |  | Bars touching each boundary zone (1 = disabled). |
| **Entry zone near boundary (% of width)** | 20.0 | same | 10.0 / 5.0 / 30.0 | BUY in the lowest x%, SELL in the highest x%. |
| **Edge confirmation (slowdown / rejection)** | Slowdown OR rejection | same |  | Spec: rejection/slowdown at the boundary. Choices: None; Tick slowdown; Candle rejection wick; Slowdown OR rejection; Slowdown AND rejection. |
| **Rejection: min wick (% of candle range)** | 40.0 | same |  | Wick towards the boundary on the last closed candle. |
| **Tick window for buyer/seller return (ticks)** | 20 | same |  | Ticks used to detect the return of buyers (BUY) or sellers (SELL). |
| **Min returning tick ratio** | 0.55 | same | 0.5 / 0.05 / 0.7 | BUY: bullish ratio >= x. SELL: bearish ratio >= x. |
| **Max tick velocity ratio (impulse protection)** | 2.0 | same |  | No mean reversion against an abnormal impulse (spec: mandatory). |
| **Max ATR / median ATR** | 1.6 | same |  | Volatility expansion protection. |
| **SL buffer beyond boundary (x spread)** | 1.5 | same |  | SL buffer = max(x spread, x ATR). |
| **SL buffer beyond boundary (x ATR)** | 0.15 | same |  | See above. |
| **TP target** | Range middle | same |  | Range middle (spec first target) or opposite boundary. Choices: Range middle; Opposite boundary. |
| **TP offset before target (% of width)** | 5.0 | same |  | TP placed slightly before the target. |
| **Breakout confirmation buffer (x ATR)** | 0.15 | same |  | Close beyond the boundary + buffer = confirmed breakout. |
| **Exit quickly on confirmed breakout** | true | same |  | Close Range positions on breakout + volatility expansion. |
| **Max trades per boundary touch** | 1 | same |  | Duplicate protection. |
| **Signal validity (ms)** | 1000 | same |  | A Range signal older than this is discarded. |
| **Time-stop (s, 0 = off)** | 120 | same | 60 / 30 / 300 | Initial ceiling 120 s. |
| **Max simultaneous positions (Range)** | 3 | same |  | Spec G.2: up to 3 per engine. |
| **Break-even trigger (% of TP distance)** | 70.0 | same |  | Spec: 70%. |
| **Break-even lock (% of TP distance)** | 5.0 | same |  | Profit locked at break-even. |
| **Trailing trigger (% of TP distance)** | 85.0 | same |  | Spec: 85%. |
| **Trailing distance (% of TP distance)** | 25.0 | same |  | Short trailing. |
| **Trailing min step (% of TP distance)** | 5.0 | same |  | Minimum SL improvement per modification. |

## 09. POSITIONS / CONFLICTS / HEDGING

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Max total positions on this symbol (this instance)** | 9 | same |  | Spec G.2: up to 9 (3 per engine). Never an obligation to open them. |
| **OPPOSITE_HEDGE (allow BUY and SELL together)** | false | same |  | Spec default: false. |
| **Same-direction signals** | Stack within the limits | same |  | Stack within limits, or ignore when a same-direction position exists. Choices: Stack within the limits; Ignore if a same-direction position exists. |
| **Opposite-signal conflict window (ms)** | 300 | same |  | BUY and SELL from different engines within this window = conflict. |
| **Entry block after a conflict (ms)** | 300 | same |  | Spec: block a few hundred ms, then re-evaluate. |
| **Min distance between same-engine entries (x ATR M1)** | 0.1 | same |  | Anti-duplicate distance for stacked entries of one engine. |
| **Min time between any two entries (ms, 0 = off)** | 0 | same |  | Global spacing between entries of this instance. |
| **Hard max holding time, all engines (s, 0 = off)** | 120 | same |  | Spec: 120 s initially, adjustable. |
| **Min interval between SL modifications (ms)** | 300 | same |  | Avoids flooding the server with modifications. |
| **Send SL/TP after the fill (ECN brokers)** | false | same |  | Open without SL/TP, then attach them immediately. |

## 10. RISK MANAGEMENT

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **RISK_MODE** | % of equity at real SL distance | same |  | Fixed lot, % of balance or % of equity, always computed on the REAL SL distance. Choices: Fixed lot; % of balance at real SL distance; % of equity at real SL distance. |
| **Fixed lot** | 0.01 | same |  | Used in Fixed-lot mode. |
| **Risk per trade (%)** | 0.25 | same | 0.1 / 0.1 / 1.0 | Money lost if the SL is hit, in % of balance or equity. |
| **Max risk per trade - hard cap (%)** | 1.0 | same |  | Applies in every mode, including martingale. |
| **Max lot per trade (0 = broker max)** | 0.0 | same |  | Hard lot cap. |
| **Allow broker min lot even if above max risk** | false | same |  | OFF = refuse the trade when the minimum lot already exceeds the hard cap. |
| **Max total open risk, this instance (%)** | 5.0 | same |  | Sum of risk at SL of all open positions of this instance. |
| **Max total open lots, this instance (0 = off)** | 0.0 | same |  | Total exposure ceiling in lots. |
| **Broker stops-level policy** | Widen SL/TP to broker minimum and re-size | same |  | Widen to broker minimum (and re-size), or reject. Choices: Widen SL/TP to broker minimum and re-size; Reject the signal. |
| **SL/TP ratio guard (max SL / TP, 0 = off)** | 2.0 | same |  | Spec: SL/TP <= 2. Signals above are refused, never 'fixed' by shrinking TP. |
| **Martingale ON (optional)** | false | same |  | OFF by default. Even when ON a NEW valid setup is required and hard caps apply. |
| **Martingale multiplier** | 1.5 | same |  | Risk x multiplier ^ step after each loss (per engine). |
| **Martingale max steps** | 3 | same |  | Step resets after a win or after this many steps. |

## 11. EQUITY DRAWDOWN PROTECTION (10% PAUSE)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Equity drawdown pause ON** | true | same |  | At the threshold: STOP new entries, re-activate and verify safeties, restart automatically after the pause. |
| **Drawdown threshold (%)** | 10.0 | same |  | Spec: 10%. |
| **Pause length (s)** | 10 | same |  | Spec: 10 s. Strict timer - never waits indefinitely. |
| **Drawdown reference** | Peak equity (high-water mark) | same |  | After each pause the reference is re-based to the current equity, so the next pause needs a further drop. Choices: Peak equity (high-water mark); Balance when EA started; Equity at start of the server day. |

## 12. NEWS FILTER (B.1)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **NEWS_FILTER ON** | true | same |  | No NEW entries inside the news window; open positions are still managed. |
| **News source** | AUTO (MT5 live: calendar, else CSV) | same |  | MT5 calendar (live), CSV file (tester/MT4/MT5), or web XML feed (live). Choices: AUTO (MT5 live: calendar, else CSV); MT5 built-in economic calendar; CSV file (works in tester, MT4 and MT5); Web XML feed (live only, URL must be allowed); MT5 calendar + CSV file. |
| **Min impact** | High only | same |  | Events at or above this impact block entries. Choices: Low and above; Medium and above; High only. |
| **Currencies (AUTO or list e.g. USD,EUR)** | "AUTO" | same |  | AUTO = currencies of the chart symbol (EURUSD: EUR,USD; XAUUSD and BTCUSD: USD). |
| **Keywords always blocked (any impact)** | "Non-Farm,Nonfarm,NFP,CPI,FOMC,Federal Funds,Interest Rate,Rate Decision,Fed Chair" | same |  | Comma list. Events whose title contains a keyword block entries even below the min impact. |
| **Block minutes BEFORE news** | 10 | same |  | Window start. |
| **Block minutes AFTER news** | 10 | same |  | Window end. |
| **News CSV file (in Files or Common\Files)** | "FranckyTriFlux\news.csv" | same |  | Format: yyyy.mm.dd hh:mi;CCY;HIGH/MEDIUM/LOW;Title (times in UTC by default). |
| **News CSV is in Common\Files** | true | same |  | Common folder is shared by MT4, MT5 and the tester agents. |
| **News CSV times are UTC** | true | same |  | OFF = times are broker server time. |
| **Web XML feed URL** | "https://nfs.faireconomy.media/ff_calendar_thisweek.xml" | same |  | Must be added in Tools > Options > Expert Advisors > Allow WebRequest. |
| **News refresh interval (min)** | 60 | same |  | Reload period for the news list. |
| **Draw news windows on chart** | true | same |  | Shows blocked windows as shaded areas. |

## 13. SESSIONS / DAYS (B.2)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **SESSION_FILTER ON** | false | same |  | OFF = trade 24h on every day the broker quotes (needed for BTCUSD weekends). |
| **Session preset** | LONDON + NEW YORK 07:00-21:00 UTC | same |  | Presets are in UTC. CUSTOM uses the hours below. Choices: CUSTOM (Trading start/end below); LONDON 07:00-16:00 UTC; NEW YORK 12:00-21:00 UTC; LONDON + NEW YORK 07:00-21:00 UTC; ASIA 23:00-08:00 UTC; ASIA + LONDON + NEW YORK 23:00-21:00 UTC. |
| **CUSTOM hours time basis** | Broker server time | same |  | Server time or UTC. Choices: Broker server time; UTC / GMT. |
| **TradingStart (HH:MM)** | "08:00" | same |  | CUSTOM window 1 start. |
| **TradingEnd (HH:MM)** | "22:00" | same |  | CUSTOM window 1 end (may wrap past midnight). |
| **TradingStart 2 (HH:MM, empty = none)** | (empty) | same |  | Optional CUSTOM window 2. |
| **TradingEnd 2 (HH:MM)** | (empty) | same |  | Optional CUSTOM window 2 end. |
| **Trade Monday** | true | same |  | Day filter (used when the session filter is ON). |
| **Trade Tuesday** | true | same |  |  |
| **Trade Wednesday** | true | same |  |  |
| **Trade Thursday** | true | same |  |  |
| **Trade Friday** | true | same |  |  |
| **Trade Saturday** | false | false / false / true |  | BTCUSD preset sets ON. |
| **Trade Sunday** | false | false / false / true |  | BTCUSD preset sets ON. |

## 14. ROLLOVER / DAY CHANGE (B.3)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **ROLLOVER_FILTER ON** | true | same |  | No NEW entries around the daily rollover; spread filter stays active. |
| **Rollover time (server, HH:MM)** | "00:00" | same |  | Most brokers roll over at 00:00 server time. |
| **Block minutes BEFORE rollover** | 10 | same |  |  |
| **Block minutes AFTER rollover** | 15 | same |  |  |

## 15. TIME ZONE (SERVER / UTC)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Broker GMT offset mode** | AUTO (live: server-GMT; tester: manual) | same |  | AUTO live = server time - GMT. Strategy Tester always uses the MANUAL values. Choices: AUTO (live: server-GMT; tester: manual); MANUAL (offset below). |
| **Manual broker GMT offset (winter, hours)** | 2 | same |  | Typical: 2 (GMT+2 winter / GMT+3 summer). |
| **Manual offset follows US DST (+1h)** | true | same |  | Adds 1 h between 2nd Sunday of March and 1st Sunday of November (New-York-close brokers). |

## 16. CONSECUTIVE LOSS PROTECTION (B.4)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **CONSECUTIVE_LOSS_PROTECTION ON** | true | same |  | After X losses in a row: cooldown Y minutes; then a NEW setup is required. |
| **Consecutive losses X** | 3 | same | 2 / 1 / 6 |  |
| **Cooldown Y (minutes)** | 15 | same | 5 / 5 / 60 |  |
| **Scope** | Per engine | same |  | Per engine or whole instance (one instance = one symbol). Choices: Per engine; Whole instance (symbol). |

## 17. EXECUTION / RETRIES / QUALITY (B.8)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Max slippage / deviation (points, 0 = auto)** | 0 | same |  | Auto = spread x multiplier below. |
| **Auto deviation (x spread)** | 1.0 | same |  |  |
| **Max retries per order** | 3 | same |  | Only for transient errors (requote, off quotes, timeout...). |
| **Delay between retries (ms)** | 150 | same |  | Non-blocking: other positions keep being managed. |
| **Max price drift before a retry (x ATR M1)** | 0.15 | same |  | Retry refused if price moved more than this since the signal. |
| **Pause after a permanent broker error (s)** | 60 | same |  | E.g. no money, trading disabled, market closed. |
| **Execution-quality action** | Block new entries for a cooldown | same |  | What to do when average slippage/latency is out of tolerance. Choices: Log only; Block new entries for a cooldown; Reduce lot size. |
| **Execution-quality window (trades)** | 20 | same |  | Rolling number of fills averaged. |
| **Max avg adverse slippage (x avg spread, 0 = off)** | 1.5 | same |  |  |
| **Max avg order latency (ms, 0 = off)** | 0 | same |  | Latency target <= 10 ms is MEASURED and reported, not assumed. |
| **Execution-quality cooldown (s)** | 120 | same |  |  |
| **Lot factor when quality is poor** | 0.5 | same |  | Used by REDUCE_LOT action. |

## 18. MULTI-INSTANCE / AGGREGATE EXPOSURE (B.6)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **MULTI_INSTANCE_GUARD** | ISOLATE + block duplicate Instance ID | same |  | An instance NEVER manages another instance's orders. ISOLATE also blocks a second chart using the same Instance ID. Choices: OFF (own-magic isolation only); ISOLATE + block duplicate Instance ID; ISOLATE + block cross-instance duplicate entries. |
| **Cross-instance duplicate window (s)** | 10 | same |  | Used by BLOCK_DUPLICATES. |
| **Aggregate exposure mode** | Currency decomposition (net USD/EUR/XAU/BTC risk) | same |  | Controls total open risk across EURUSD / XAUUSD / BTCUSD on the same account. Choices: OFF; Currency decomposition (net USD/EUR/XAU/BTC risk); Currency + measured correlation. |
| **Count only FRANCKY positions (same magic base)** | true | same |  | OFF = count every position on the account. |
| **Max open risk all symbols (% equity)** | 10.0 | same |  | Gross risk at SL of all counted positions. |
| **Max net risk per currency, e.g. USD (% equity)** | 6.0 | same |  | Net long/short risk per currency leg. |
| **Correlation lookback (M5 bars)** | 288 | same |  | Used by correlation mode (288 = 1 day). |
| **Max correlation-adjusted risk (% equity)** | 6.0 | same |  | sqrt(r' C r) using measured correlations. |

## 19. RESTART RECOVERY (B.7)

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Save and restore state after restart** | true | same |  | Cooldowns, pauses, martingale steps, traded setups, position metadata. |
| **No new entries after start (s)** | 5 | same |  | Lets data and positions resynchronise after a restart/reconnection. |

## 20. LOGGING / STATISTICS

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Log level** | INFO | same |  | DEBUG/TRACE for bug hunting (large files in tester). Choices: OFF; ERROR; WARN; INFO; DEBUG; TRACE (very verbose). |
| **Print to Experts journal** | true | same |  |  |
| **Write text log file** | true | same |  |  |
| **Write CSV journals (signals, trades, events, stats)** | true | same |  | Exportable logs (acceptance criterion). |
| **Log files in Common\Files** | true | same |  | Easy to find after backtests: %APPDATA%\MetaQuotes\Terminal\Common\Files\FranckyTriFlux. |
| **Log every signal decision** | true | same |  | One CSV row per accepted/rejected setup. |
| **Throttle repeated messages (ms)** | 2000 | same |  | Identical rejections are summarised instead of repeated. |
| **Write files during optimization** | false | same |  | Keep OFF: optimization runs thousands of passes. |
| **Write stats summary every (min)** | 60 | same |  | Also written when the EA stops. |

## 21. CHART DISPLAY

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Show dashboard panel** | true | same |  |  |
| **Panel corner** | Left Upper | same |  |  |
| **Panel X offset (px)** | 10 | same |  |  |
| **Panel Y offset (px)** | 20 | same |  |  |
| **Panel font size** | 8 | same |  |  |
| **Dark panel theme** | true | same |  |  |
| **Panel refresh (ms)** | 250 | same |  |  |
| **Draw entries / exits** | true | same |  | Arrows, labels (engine, reason) and entry-exit lines. |
| **Draw FVG zones, ranges, micro-ranges** | true | same |  |  |
| **Draw rejected signals** | false | same |  | Small grey markers with the rejection reason (busy charts). |
| **Max chart objects** | 600 | same |  | Oldest markers are deleted beyond this number. |
| **Keep drawings when the EA stops (tester review)** | true | same |  | Live charts are always cleaned on removal unless this is ON. |

## 22. TESTER / OPTIMIZATION / STRESS

| Parameter (Inputs tab) | Default | EURUSD / XAUUSD / BTCUSD | Opt range | What it does |
|---|---|---|---|---|
| **Custom optimization criterion** | Robust score (expectancy, PF, DD, trades) | same |  | Returned by OnTester (choose 'Custom max' in the tester). Choices: Net profit; Profit factor; Expectancy per trade; Win rate (with min trades); Robust score (expectancy, PF, DD, trades). |
| **Min trades for a valid pass** | 30 | same |  | Passes with fewer trades score 0. |
| **Stress: extra spread (points)** | 0 | same |  | Degraded-execution test: added to the spread in every decision. |
| **Stress: extra commission per lot (money)** | 0.0 | same |  | Subtracted in the EA statistics (net after stress). |

## Developer cross-reference (label -> MQL variable)

| Parameter (Inputs tab) | MQL variable | CConfig field | Type |
|---|---|---|---|
| Enable new entries (master switch) | `InpEnableTrading` | `cfg.EnableTrading` | bool |
| Trading mode (SPEED / AGGRESSIVE / ULTRA) | `InpTradingMode` | `cfg.TradingMode` | ENUM_FTF_MODE |
| Instance ID (1-999, unique per chart on one account) | `InpInstanceId` | `cfg.InstanceId` | int |
| Magic number base (magic = base + ID x 10 + engine) | `InpMagicBase` | `cfg.MagicBase` | int |
| Order comment prefix | `InpCommentPrefix` | `cfg.CommentPrefix` | string |
| Supported-symbol check (EURUSD/XAUUSD/BTCUSD) | `InpSymbolCheck` | `cfg.SymbolCheck` | ENUM_FTF_SYMBOL_CHECK |
| Internal timer period (ms) | `InpTimerMs` | `cfg.TimerMs` | int |
| Engine A - Momentum / Micro-breakout ON | `InpMomEnabled` | `cfg.MomEnabled` | bool |
| Engine B - FVG (Fair Value Gap) ON | `InpFvgEnabled` | `cfg.FvgEnabled` | bool |
| Engine C - Range / Mean Reversion ON | `InpRngEnabled` | `cfg.RngEnabled` | bool |
| SPEED mode entry delay (ms) | `InpDelaySpeedMs` | `cfg.DelaySpeedMs` | int |
| AGGRESSIVE mode entry delay (ms) | `InpDelayAggressiveMs` | `cfg.DelayAggressiveMs` | int |
| ULTRA mode entry delay (ms) | `InpDelayUltraMs` | `cfg.DelayUltraMs` | int |
| How the mode delay is applied | `InpDelayUsage` | `cfg.DelayUsage` | ENUM_FTF_DELAY_USAGE |
| Max spread SPEED (points, 0 = auto) | `InpMaxSpreadPtsSpeed` | `cfg.MaxSpreadPtsSpeed` | int |
| Max spread AGGRESSIVE (points, 0 = auto) | `InpMaxSpreadPtsAggressive` | `cfg.MaxSpreadPtsAggressive` | int |
| Max spread ULTRA (points, 0 = auto) | `InpMaxSpreadPtsUltra` | `cfg.MaxSpreadPtsUltra` | int |
| Auto max spread (x ATR M1) when limit = 0 | `InpAutoMaxSpreadAtr` | `cfg.AutoMaxSpreadAtr` | double |
| ATR period (M1 / M5) | `InpAtrPeriod` | `cfg.AtrPeriod` | int |
| ATR median length (M1 bars) | `InpAtrMedianBars` | `cfg.AtrMedianBars` | int |
| Tick history kept in memory (s) | `InpTickHistorySec` | `cfg.TickHistorySec` | int |
| Max tick age before market considered stale (s) | `InpMaxTickAgeSec` | `cfg.MaxTickAgeSec` | int |
| Volatility anomaly: ATR > x median ATR | `InpVolAnomalyAtrMult` | `cfg.VolAnomalyAtrMult` | double |
| Volatility anomaly: tick velocity > x median | `InpVolAnomalyVelMult` | `cfg.VolAnomalyVelMult` | double |
| Volatility anomaly: spread > x median spread | `InpVolAnomalySpreadMult` | `cfg.VolAnomalySpreadMult` | double |
| H1_FILTER mode | `InpH1Filter` | `cfg.H1Filter` | ENUM_FTF_H1_FILTER |
| H1 fast EMA period | `InpH1EmaFast` | `cfg.H1EmaFast` | int |
| H1 slow EMA period | `InpH1EmaSlow` | `cfg.H1EmaSlow` | int |
| H1 ADX period | `InpH1AdxPeriod` | `cfg.H1AdxPeriod` | int |
| H1 ADX directional threshold | `InpH1AdxThreshold` | `cfg.H1AdxThreshold` | double |
| H1 min +DI/-DI gap | `InpH1DiMinGap` | `cfg.H1DiMinGap` | double |
| H1 'strong trend' ADX (Range STRICT) | `InpH1StrongAdx` | `cfg.H1StrongAdx` | double |
| STRICT applies to Momentum | `InpH1StrictMomentum` | `cfg.H1StrictMomentum` | bool |
| STRICT applies to FVG | `InpH1StrictFvg` | `cfg.H1StrictFvg` | bool |
| STRICT applies to Range | `InpH1StrictRange` | `cfg.H1StrictRange` | bool |
| Tick window for imbalance (ticks) | `InpMomTickWindow` | `cfg.MomTickWindow` | int |
| BUY: min bullish tick ratio | `InpMomBuyRatio` | `cfg.MomBuyRatio` | double |
| SELL ratio = 1 - BUY ratio (symmetric) | `InpMomSymmetric` | `cfg.MomSymmetric` | bool |
| SELL: max bullish tick ratio | `InpMomSellRatio` | `cfg.MomSellRatio` | double |
| Count unchanged ticks in the ratio | `InpMomCountFlatTicks` | `cfg.MomCountFlatTicks` | bool |
| Velocity metric | `InpMomVelMetric` | `cfg.MomVelMetric` | ENUM_FTF_VEL_METRIC |
| Velocity window (ms) | `InpMomVelWindowMs` | `cfg.MomVelWindowMs` | int |
| Velocity reference window for median (ms) | `InpMomVelRefMs` | `cfg.MomVelRefMs` | int |
| Min velocity / median velocity | `InpMomVelRatio` | `cfg.MomVelRatio` | double |
| Min acceleration (0.20 = +20%) | `InpMomAccelMin` | `cfg.MomAccelMin` | double |
| Micro-range length (ticks) | `InpMomMicroRangeTicks` | `cfg.MomMicroRangeTicks` | int |
| Breakout buffer (x spread) | `InpMomBufSpreadMult` | `cfg.MomBufSpreadMult` | double |
| Breakout buffer (x ATR M1) | `InpMomBufAtrMult` | `cfg.MomBufAtrMult` | double |
| Confirm with ROC direction | `InpMomUseRoc` | `cfg.MomUseRoc` | bool |
| ROC period (M1 bars) | `InpMomRocPeriod` | `cfg.MomRocPeriod` | int |
| Min /ROC/ (%) | `InpMomRocMin` | `cfg.MomRocMin` | double |
| Confirm with M1 EMA fast/slow | `InpMomUseEma` | `cfg.MomUseEma` | bool |
| M1 fast EMA period | `InpMomEmaFast` | `cfg.MomEmaFast` | int |
| M1 slow EMA period | `InpMomEmaSlow` | `cfg.MomEmaSlow` | int |
| Confirm with M1 ADX/DI | `InpMomUseAdx` | `cfg.MomUseAdx` | bool |
| M1 ADX min | `InpMomAdxMin` | `cfg.MomAdxMin` | double |
| M5 EMA20/50 context | `InpMomM5Context` | `cfg.MomM5Context` | ENUM_FTF_CTX_USE |
| TP = max(x spread, ...) | `InpMomTpSpreadMult` | `cfg.MomTpSpreadMult` | double |
| TP = max(..., x ATR M1) | `InpMomTpAtrMult` | `cfg.MomTpAtrMult` | double |
| SL = max(x spread, ...) | `InpMomSlSpreadMult` | `cfg.MomSlSpreadMult` | double |
| SL = max(..., x ATR M1) | `InpMomSlAtrMult` | `cfg.MomSlAtrMult` | double |
| Signal validity (ms) | `InpMomSignalTtlMs` | `cfg.MomSignalTtlMs` | int |
| Momentum-loss exit ON | `InpMomExitEnabled` | `cfg.MomExitEnabled` | bool |
| Exit when momentum score below | `InpMomExitScore` | `cfg.MomExitScore` | double |
| Tick inversion persistence (ms) | `InpMomExitInversionMs` | `cfg.MomExitInversionMs` | int |
| Inversion window (ticks) | `InpMomExitTicks` | `cfg.MomExitTicks` | int |
| Time-stop (s, 0 = off) | `InpMomTimeStopSec` | `cfg.MomTimeStopSec` | int |
| Max simultaneous positions (Momentum) | `InpMomMaxPositions` | `cfg.MomMaxPositions` | int |
| Break-even trigger (% of TP distance) | `InpMomBeTriggerPct` | `cfg.MomBeTriggerPct` | double |
| Break-even lock (% of TP distance) | `InpMomBeLockPct` | `cfg.MomBeLockPct` | double |
| Trailing trigger (% of TP distance) | `InpMomTrailTriggerPct` | `cfg.MomTrailTriggerPct` | double |
| Trailing distance (% of TP distance) | `InpMomTrailDistPct` | `cfg.MomTrailDistPct` | double |
| Trailing min step (% of TP distance) | `InpMomTrailStepPct` | `cfg.MomTrailStepPct` | double |
| FVG timeframe | `InpFvgTimeframe` | `cfg.FvgTimeframe` | ENUM_TIMEFRAMES |
| Use M1 for entry precision | `InpFvgUseM1Refine` | `cfg.FvgUseM1Refine` | bool |
| Bars scanned for FVGs | `InpFvgScanBars` | `cfg.FvgScanBars` | int |
| Max zones kept | `InpFvgMaxZones` | `cfg.FvgMaxZones` | int |
| Min gap size (x ATR of FVG timeframe) | `InpFvgMinGapAtr` | `cfg.FvgMinGapAtr` | double |
| Min gap size (x spread) | `InpFvgMinGapSpreadMult` | `cfg.FvgMinGapSpreadMult` | double |
| Max zone age (bars) | `InpFvgMaxAgeBars` | `cfg.FvgMaxAgeBars` | int |
| Max mitigations (returns into zone) | `InpFvgMaxMitigations` | `cfg.FvgMaxMitigations` | int |
| Max price distance to zone (x ATR) | `InpFvgMaxDistanceAtr` | `cfg.FvgMaxDistanceAtr` | double |
| Entry mode (TOUCH / CE 50% / REJECTION) | `InpFvgEntryMode` | `cfg.FvgEntryMode` | ENUM_FTF_FVG_ENTRY |
| REJECTION: min wick (% of candle range) | `InpFvgRejectWickPct` | `cfg.FvgRejectWickPct` | double |
| BOS_REQUIRED (structure confirmation) | `InpFvgBosRequired` | `cfg.FvgBosRequired` | bool |
| Structure event accepted when required | `InpFvgStructMode` | `cfg.FvgStructMode` | ENUM_FTF_STRUCT_MODE |
| Swing strength (bars each side) | `InpStructSwingBars` | `cfg.StructSwingBars` | int |
| Structure lookback (bars) | `InpStructLookbackBars` | `cfg.StructLookbackBars` | int |
| Invalidation buffer (x ATR) | `InpFvgInvalidBufAtr` | `cfg.FvgInvalidBufAtr` | double |
| Invalidate on candle close (else on tick) | `InpFvgInvalidOnClose` | `cfg.FvgInvalidOnClose` | bool |
| SL anchor | `InpFvgSlMode` | `cfg.FvgSlMode` | ENUM_FTF_FVG_SL |
| SL buffer (x spread) | `InpFvgSlBufSpreadMult` | `cfg.FvgSlBufSpreadMult` | double |
| SL buffer (x ATR) | `InpFvgSlBufAtr` | `cfg.FvgSlBufAtr` | double |
| TP mode | `InpFvgTpMode` | `cfg.FvgTpMode` | ENUM_FTF_TP_MODE |
| TP ATR multiple | `InpFvgTpAtrMult` | `cfg.FvgTpAtrMult` | double |
| TP R multiple | `InpFvgTpRR` | `cfg.FvgTpRR` | double |
| TP min R (liquidity mode) | `InpFvgTpMinRR` | `cfg.FvgTpMinRR` | double |
| TP max R (liquidity mode) | `InpFvgTpMaxRR` | `cfg.FvgTpMaxRR` | double |
| Max trades per zone | `InpFvgMaxTradesPerZone` | `cfg.FvgMaxTradesPerZone` | int |
| Signal validity (ms) | `InpFvgSignalTtlMs` | `cfg.FvgSignalTtlMs` | int |
| Exit open trade if zone invalidated | `InpFvgExitOnInvalidation` | `cfg.FvgExitOnInvalidation` | bool |
| Time-stop (s, 0 = off) | `InpFvgTimeStopSec` | `cfg.FvgTimeStopSec` | int |
| Max simultaneous positions (FVG) | `InpFvgMaxPositions` | `cfg.FvgMaxPositions` | int |
| Break-even trigger (% of TP distance) | `InpFvgBeTriggerPct` | `cfg.FvgBeTriggerPct` | double |
| Break-even lock (% of TP distance) | `InpFvgBeLockPct` | `cfg.FvgBeLockPct` | double |
| Trailing trigger (% of TP distance) | `InpFvgTrailTriggerPct` | `cfg.FvgTrailTriggerPct` | double |
| Trailing distance (% of TP distance) | `InpFvgTrailDistPct` | `cfg.FvgTrailDistPct` | double |
| Trailing min step (% of TP distance) | `InpFvgTrailStepPct` | `cfg.FvgTrailStepPct` | double |
| Range timeframe (M1 or M5) | `InpRngTimeframe` | `cfg.RngTimeframe` | ENUM_TIMEFRAMES |
| Range lookback (bars) | `InpRngLookbackBars` | `cfg.RngLookbackBars` | int |
| ADX period | `InpRngAdxPeriod` | `cfg.RngAdxPeriod` | int |
| Max ADX for a range | `InpRngAdxMax` | `cfg.RngAdxMax` | double |
| Require falling ADX | `InpRngRequireAdxFalling` | `cfg.RngRequireAdxFalling` | bool |
| ADX slope bars | `InpRngAdxSlopeBars` | `cfg.RngAdxSlopeBars` | int |
| Fast EMA period | `InpRngEmaFast` | `cfg.RngEmaFast` | int |
| Slow EMA period | `InpRngEmaSlow` | `cfg.RngEmaSlow` | int |
| Max /EMA20-EMA50/ (x ATR) | `InpRngEmaSepMaxAtr` | `cfg.RngEmaSepMaxAtr` | double |
| Min range width (x ATR) | `InpRngMinWidthAtr` | `cfg.RngMinWidthAtr` | double |
| Min range width (x spread) | `InpRngMinWidthSpreadMult` | `cfg.RngMinWidthSpreadMult` | double |
| Max range width (x ATR) | `InpRngMaxWidthAtr` | `cfg.RngMaxWidthAtr` | double |
| Max net drift (% of width) | `InpRngMaxDriftPct` | `cfg.RngMaxDriftPct` | double |
| Min touches per boundary | `InpRngMinTouchesPerSide` | `cfg.RngMinTouchesPerSide` | int |
| Entry zone near boundary (% of width) | `InpRngEdgeZonePct` | `cfg.RngEdgeZonePct` | double |
| Edge confirmation (slowdown / rejection) | `InpRngConfirmMode` | `cfg.RngConfirmMode` | ENUM_FTF_RANGE_CONFIRM |
| Rejection: min wick (% of candle range) | `InpRngRejectWickPct` | `cfg.RngRejectWickPct` | double |
| Tick window for buyer/seller return (ticks) | `InpRngTickWindow` | `cfg.RngTickWindow` | int |
| Min returning tick ratio | `InpRngTickRatioMin` | `cfg.RngTickRatioMin` | double |
| Max tick velocity ratio (impulse protection) | `InpRngMaxVelRatio` | `cfg.RngMaxVelRatio` | double |
| Max ATR / median ATR | `InpRngMaxAtrExpansion` | `cfg.RngMaxAtrExpansion` | double |
| SL buffer beyond boundary (x spread) | `InpRngSlBufSpreadMult` | `cfg.RngSlBufSpreadMult` | double |
| SL buffer beyond boundary (x ATR) | `InpRngSlBufAtr` | `cfg.RngSlBufAtr` | double |
| TP target | `InpRngTpTarget` | `cfg.RngTpTarget` | ENUM_FTF_RANGE_TP |
| TP offset before target (% of width) | `InpRngTpOffsetPct` | `cfg.RngTpOffsetPct` | double |
| Breakout confirmation buffer (x ATR) | `InpRngBreakBufAtr` | `cfg.RngBreakBufAtr` | double |
| Exit quickly on confirmed breakout | `InpRngExitOnBreakout` | `cfg.RngExitOnBreakout` | bool |
| Max trades per boundary touch | `InpRngMaxTradesPerTouch` | `cfg.RngMaxTradesPerTouch` | int |
| Signal validity (ms) | `InpRngSignalTtlMs` | `cfg.RngSignalTtlMs` | int |
| Time-stop (s, 0 = off) | `InpRngTimeStopSec` | `cfg.RngTimeStopSec` | int |
| Max simultaneous positions (Range) | `InpRngMaxPositions` | `cfg.RngMaxPositions` | int |
| Break-even trigger (% of TP distance) | `InpRngBeTriggerPct` | `cfg.RngBeTriggerPct` | double |
| Break-even lock (% of TP distance) | `InpRngBeLockPct` | `cfg.RngBeLockPct` | double |
| Trailing trigger (% of TP distance) | `InpRngTrailTriggerPct` | `cfg.RngTrailTriggerPct` | double |
| Trailing distance (% of TP distance) | `InpRngTrailDistPct` | `cfg.RngTrailDistPct` | double |
| Trailing min step (% of TP distance) | `InpRngTrailStepPct` | `cfg.RngTrailStepPct` | double |
| Max total positions on this symbol (this instance) | `InpMaxPositionsSymbol` | `cfg.MaxPositionsSymbol` | int |
| OPPOSITE_HEDGE (allow BUY and SELL together) | `InpAllowOppositeHedge` | `cfg.AllowOppositeHedge` | bool |
| Same-direction signals | `InpSameDirMode` | `cfg.SameDirMode` | ENUM_FTF_SAMEDIR |
| Opposite-signal conflict window (ms) | `InpConflictWindowMs` | `cfg.ConflictWindowMs` | int |
| Entry block after a conflict (ms) | `InpConflictHoldMs` | `cfg.ConflictHoldMs` | int |
| Min distance between same-engine entries (x ATR M1) | `InpDupMinDistAtr` | `cfg.DupMinDistAtr` | double |
| Min time between any two entries (ms, 0 = off) | `InpMinEntrySpacingMs` | `cfg.MinEntrySpacingMs` | int |
| Hard max holding time, all engines (s, 0 = off) | `InpHardMaxHoldSec` | `cfg.HardMaxHoldSec` | int |
| Min interval between SL modifications (ms) | `InpMinModifyIntervalMs` | `cfg.MinModifyIntervalMs` | int |
| Send SL/TP after the fill (ECN brokers) | `InpTwoStepStops` | `cfg.TwoStepStops` | bool |
| RISK_MODE | `InpRiskMode` | `cfg.RiskMode` | ENUM_FTF_RISK_MODE |
| Fixed lot | `InpFixedLot` | `cfg.FixedLot` | double |
| Risk per trade (%) | `InpRiskPercent` | `cfg.RiskPercent` | double |
| Max risk per trade - hard cap (%) | `InpMaxRiskPercent` | `cfg.MaxRiskPercent` | double |
| Max lot per trade (0 = broker max) | `InpMaxLotPerTrade` | `cfg.MaxLotPerTrade` | double |
| Allow broker min lot even if above max risk | `InpAllowMinLotOverRisk` | `cfg.AllowMinLotOverRisk` | bool |
| Max total open risk, this instance (%) | `InpMaxOpenRiskPct` | `cfg.MaxOpenRiskPct` | double |
| Max total open lots, this instance (0 = off) | `InpMaxTotalLots` | `cfg.MaxTotalLots` | double |
| Broker stops-level policy | `InpStopsPolicy` | `cfg.StopsPolicy` | ENUM_FTF_STOPS_POLICY |
| SL/TP ratio guard (max SL / TP, 0 = off) | `InpMaxSlTpRatio` | `cfg.MaxSlTpRatio` | double |
| Martingale ON (optional) | `InpMartingaleEnabled` | `cfg.MartingaleEnabled` | bool |
| Martingale multiplier | `InpMartingaleMult` | `cfg.MartingaleMult` | double |
| Martingale max steps | `InpMartingaleMaxSteps` | `cfg.MartingaleMaxSteps` | int |
| Equity drawdown pause ON | `InpDdEnabled` | `cfg.DdEnabled` | bool |
| Drawdown threshold (%) | `InpDdPausePct` | `cfg.DdPausePct` | double |
| Pause length (s) | `InpDdPauseSec` | `cfg.DdPauseSec` | int |
| Drawdown reference | `InpDdReference` | `cfg.DdReference` | ENUM_FTF_DD_REF |
| NEWS_FILTER ON | `InpNewsEnabled` | `cfg.NewsEnabled` | bool |
| News source | `InpNewsSource` | `cfg.NewsSource` | ENUM_FTF_NEWS_SOURCE |
| Min impact | `InpNewsMinImpact` | `cfg.NewsMinImpact` | ENUM_FTF_IMPACT |
| Currencies (AUTO or list e.g. USD,EUR) | `InpNewsCurrencies` | `cfg.NewsCurrencies` | string |
| Keywords always blocked (any impact) | `InpNewsKeywords` | `cfg.NewsKeywords` | string |
| Block minutes BEFORE news | `InpNewsMinsBefore` | `cfg.NewsMinsBefore` | int |
| Block minutes AFTER news | `InpNewsMinsAfter` | `cfg.NewsMinsAfter` | int |
| News CSV file (in Files or Common\Files) | `InpNewsCsvFile` | `cfg.NewsCsvFile` | string |
| News CSV is in Common\Files | `InpNewsCsvCommon` | `cfg.NewsCsvCommon` | bool |
| News CSV times are UTC | `InpNewsCsvUtc` | `cfg.NewsCsvUtc` | bool |
| Web XML feed URL | `InpNewsWebUrl` | `cfg.NewsWebUrl` | string |
| News refresh interval (min) | `InpNewsRefreshMin` | `cfg.NewsRefreshMin` | int |
| Draw news windows on chart | `InpNewsDraw` | `cfg.NewsDraw` | bool |
| SESSION_FILTER ON | `InpSessionEnabled` | `cfg.SessionEnabled` | bool |
| Session preset | `InpSessionPreset` | `cfg.SessionPreset` | ENUM_FTF_SESSION_PRESET |
| CUSTOM hours time basis | `InpSessionTimeBasis` | `cfg.SessionTimeBasis` | ENUM_FTF_TIME_BASIS |
| TradingStart (HH:MM) | `InpTradingStart` | `cfg.TradingStart` | string |
| TradingEnd (HH:MM) | `InpTradingEnd` | `cfg.TradingEnd` | string |
| TradingStart 2 (HH:MM, empty = none) | `InpTradingStart2` | `cfg.TradingStart2` | string |
| TradingEnd 2 (HH:MM) | `InpTradingEnd2` | `cfg.TradingEnd2` | string |
| Trade Monday | `InpTradeMonday` | `cfg.TradeMonday` | bool |
| Trade Tuesday | `InpTradeTuesday` | `cfg.TradeTuesday` | bool |
| Trade Wednesday | `InpTradeWednesday` | `cfg.TradeWednesday` | bool |
| Trade Thursday | `InpTradeThursday` | `cfg.TradeThursday` | bool |
| Trade Friday | `InpTradeFriday` | `cfg.TradeFriday` | bool |
| Trade Saturday | `InpTradeSaturday` | `cfg.TradeSaturday` | bool |
| Trade Sunday | `InpTradeSunday` | `cfg.TradeSunday` | bool |
| ROLLOVER_FILTER ON | `InpRolloverEnabled` | `cfg.RolloverEnabled` | bool |
| Rollover time (server, HH:MM) | `InpRolloverTime` | `cfg.RolloverTime` | string |
| Block minutes BEFORE rollover | `InpRolloverMinsBefore` | `cfg.RolloverMinsBefore` | int |
| Block minutes AFTER rollover | `InpRolloverMinsAfter` | `cfg.RolloverMinsAfter` | int |
| Broker GMT offset mode | `InpGmtMode` | `cfg.GmtMode` | ENUM_FTF_GMT_MODE |
| Manual broker GMT offset (winter, hours) | `InpGmtOffsetHours` | `cfg.GmtOffsetHours` | int |
| Manual offset follows US DST (+1h) | `InpGmtUseUsDst` | `cfg.GmtUseUsDst` | bool |
| CONSECUTIVE_LOSS_PROTECTION ON | `InpConsecEnabled` | `cfg.ConsecEnabled` | bool |
| Consecutive losses X | `InpConsecMaxLosses` | `cfg.ConsecMaxLosses` | int |
| Cooldown Y (minutes) | `InpConsecCooldownMin` | `cfg.ConsecCooldownMin` | int |
| Scope | `InpConsecScope` | `cfg.ConsecScope` | ENUM_FTF_LOSS_SCOPE |
| Max slippage / deviation (points, 0 = auto) | `InpMaxDeviationPts` | `cfg.MaxDeviationPts` | int |
| Auto deviation (x spread) | `InpAutoDeviationSpreadMult` | `cfg.AutoDeviationSpreadMult` | double |
| Max retries per order | `InpMaxRetries` | `cfg.MaxRetries` | int |
| Delay between retries (ms) | `InpRetryDelayMs` | `cfg.RetryDelayMs` | int |
| Max price drift before a retry (x ATR M1) | `InpRetryMaxDriftAtr` | `cfg.RetryMaxDriftAtr` | double |
| Pause after a permanent broker error (s) | `InpFatalErrorCooldownSec` | `cfg.FatalErrorCooldownSec` | int |
| Execution-quality action | `InpExecQualityAction` | `cfg.ExecQualityAction` | ENUM_FTF_EXECQ_ACTION |
| Execution-quality window (trades) | `InpExecQualityWindow` | `cfg.ExecQualityWindow` | int |
| Max avg adverse slippage (x avg spread, 0 = off) | `InpMaxAvgSlippageSpreadMult` | `cfg.MaxAvgSlippageSpreadMult` | double |
| Max avg order latency (ms, 0 = off) | `InpMaxAvgLatencyMs` | `cfg.MaxAvgLatencyMs` | int |
| Execution-quality cooldown (s) | `InpExecQualityCooldownSec` | `cfg.ExecQualityCooldownSec` | int |
| Lot factor when quality is poor | `InpExecQualityLotFactor` | `cfg.ExecQualityLotFactor` | double |
| MULTI_INSTANCE_GUARD | `InpMiGuard` | `cfg.MiGuard` | ENUM_FTF_MI_GUARD |
| Cross-instance duplicate window (s) | `InpMiDupWindowSec` | `cfg.MiDupWindowSec` | int |
| Aggregate exposure mode | `InpExposureMode` | `cfg.ExposureMode` | ENUM_FTF_EXPOSURE_MODE |
| Count only FRANCKY positions (same magic base) | `InpExposureFamilyOnly` | `cfg.ExposureFamilyOnly` | bool |
| Max open risk all symbols (% equity) | `InpMaxAccountRiskPct` | `cfg.MaxAccountRiskPct` | double |
| Max net risk per currency, e.g. USD (% equity) | `InpMaxCurrencyRiskPct` | `cfg.MaxCurrencyRiskPct` | double |
| Correlation lookback (M5 bars) | `InpCorrBars` | `cfg.CorrBars` | int |
| Max correlation-adjusted risk (% equity) | `InpMaxCorrRiskPct` | `cfg.MaxCorrRiskPct` | double |
| Save and restore state after restart | `InpStateEnabled` | `cfg.StateEnabled` | bool |
| No new entries after start (s) | `InpRestartGraceSec` | `cfg.RestartGraceSec` | int |
| Log level | `InpLogLevel` | `cfg.LogLevel` | ENUM_FTF_LOG_LEVEL |
| Print to Experts journal | `InpLogToJournal` | `cfg.LogToJournal` | bool |
| Write text log file | `InpLogToFile` | `cfg.LogToFile` | bool |
| Write CSV journals (signals, trades, events, stats) | `InpLogCsv` | `cfg.LogCsv` | bool |
| Log files in Common\Files | `InpLogCommon` | `cfg.LogCommon` | bool |
| Log every signal decision | `InpLogSignals` | `cfg.LogSignals` | bool |
| Throttle repeated messages (ms) | `InpLogThrottleMs` | `cfg.LogThrottleMs` | int |
| Write files during optimization | `InpLogInOptimization` | `cfg.LogInOptimization` | bool |
| Write stats summary every (min) | `InpStatsEveryMin` | `cfg.StatsEveryMin` | int |
| Show dashboard panel | `InpShowPanel` | `cfg.ShowPanel` | bool |
| Panel corner | `InpPanelCorner` | `cfg.PanelCorner` | ENUM_BASE_CORNER |
| Panel X offset (px) | `InpPanelX` | `cfg.PanelX` | int |
| Panel Y offset (px) | `InpPanelY` | `cfg.PanelY` | int |
| Panel font size | `InpPanelFontSize` | `cfg.PanelFontSize` | int |
| Dark panel theme | `InpPanelDark` | `cfg.PanelDark` | bool |
| Panel refresh (ms) | `InpPanelRefreshMs` | `cfg.PanelRefreshMs` | int |
| Draw entries / exits | `InpDrawTrades` | `cfg.DrawTrades` | bool |
| Draw FVG zones, ranges, micro-ranges | `InpDrawZones` | `cfg.DrawZones` | bool |
| Draw rejected signals | `InpDrawRejected` | `cfg.DrawRejected` | bool |
| Max chart objects | `InpMaxChartObjects` | `cfg.MaxChartObjects` | int |
| Keep drawings when the EA stops (tester review) | `InpKeepObjectsOnExit` | `cfg.KeepObjectsOnExit` | bool |
| Custom optimization criterion | `InpOptCriterion` | `cfg.OptCriterion` | ENUM_FTF_OPT_CRITERION |
| Min trades for a valid pass | `InpOptMinTrades` | `cfg.OptMinTrades` | int |
| Stress: extra spread (points) | `InpStressExtraSpreadPts` | `cfg.StressExtraSpreadPts` | int |
| Stress: extra commission per lot (money) | `InpStressCommissionPerLot` | `cfg.StressCommissionPerLot` | double |
