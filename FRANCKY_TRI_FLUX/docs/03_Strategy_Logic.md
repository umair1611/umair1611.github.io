# 03 - Strategy Logic (exact, testable rules)

> Binding definition of the three V1 engines, the H1 filter, the common filters and the position
> management rules. Parameter names in **bold** are the names shown in the EA *Inputs* tab.
> Spec references: Tables 9-15 and 18, Addendum A-D, Section G of the final specification.

Notation: `spread` = ask - bid (price) + **Stress: extra spread** x point. `ATR` = ATR(**ATR period**) of the
last *closed* M1 bar unless another timeframe is named. "Closed bar" = shift 1. All prices are normalised to
the symbol tick size. BUY orders open at ask and close at bid; SELL orders open at bid and close at ask.

---

## 0. Common rules for all engines

* An engine evaluates **every new tick** (HFT-style, event-driven). Bar-based data (ATR, EMA, ADX, ROC, FVG
  detection, range detection) is refreshed only when a new bar opens on its timeframe (speed + backtest
  reproducibility).
* An engine produces a signal **alone**. It never reads another engine's state. Nothing requires Momentum +
  FVG + Range alignment and no global score exists.
* Each signal carries: engine id, direction, setup id (fingerprint), reference price, **absolute SL and TP**,
  invalidation level, expiry, internal quality 0-100, entry reason text with the key numbers.
* **Setup id** prevents duplicates: a setup id that was already traded (or burned by the consecutive-loss
  cooldown) is never traded again by that engine (ring of the last 64 ids, persisted across restarts).
* Up to **Max simultaneous positions** per engine (default 3) and **Max total positions on this symbol**
  (default 9). The limits are ceilings, never targets.
* Stacked entries of the same engine and direction must be at least **Min distance between same-engine
  entries** x ATR away from that engine's last entry price.

---

## 1. Engine A - Momentum / Micro-breakout (Ticks + M1, M5 as SOFT context)

### 1.1 Measurements (on every tick)

| Item | Definition |
|---|---|
| Tick direction | +1 if bid > previous bid, -1 if bid < previous bid, 0 otherwise |
| Bullish tick ratio | over the last **Tick window** ticks (50): `up / (up + down)`; if **Count unchanged ticks** ON: `up / N` |
| Velocity (TICKS metric) | number of ticks in the last **Velocity window** (2000 ms) ending at the current tick time |
| Velocity (PRICE_PATH) | sum of abs(bid changes) in the same window, in points |
| Reference velocity | **median** of the velocities of the 15 consecutive 2-s buckets before the current bucket (= **Velocity reference window** 30 000 ms / 2 000 ms) |
| Velocity ratio | `current / max(median, floor)`; floor = 1 tick (TICKS) or 1 point (PRICE_PATH) |
| Acceleration | `(current - previous bucket) / max(previous bucket, floor)` |
| Micro-range | highest and lowest bid of the **Micro-range length** (20) ticks *before* the current tick |
| Breakout buffer | `max(Breakout buffer (x spread) x spread, Breakout buffer (x ATR M1) x ATR)` = max(0.15 x spread, 0.02 x ATR) |
| ROC | `(close[1] - close[1+ROC period]) / close[1+ROC period] x 100` on M1 |

### 1.2 Entry

BUY when **all** are true:
1. bullish ratio >= **BUY: min bullish tick ratio** (0.62);
2. velocity ratio >= **Min velocity / median velocity** (1.25);
3. acceleration >= **Min acceleration** (0.20);
4. `bid > micro-range high + buffer` (breakout of the micro-range);
5. directional momentum compatible: if **Confirm with ROC direction** ON: ROC > 0 and |ROC| >= **Min |ROC|**;
   if **Confirm with M1 EMA** ON: EMA9 > EMA21; if **Confirm with M1 ADX/DI** ON: ADX >= **M1 ADX min** and +DI > -DI;
   if **M5 EMA20/50 context** = STRICT: EMA20(M5) > EMA50(M5) (SOFT = logged only).

SELL symmetric: bullish ratio <= SELL threshold (`1 - BUY ratio` when **symmetric** ON, else **SELL: max
bullish tick ratio** 0.38), same velocity/acceleration, `bid < micro-range low - buffer`, ROC < 0, etc.

Setup id: `MOM-<B|S>-<breakout level rounded to points>` (one entry per breakout level).
Validity: **Signal validity (ms)** (500).

### 1.3 SL / TP
* `TP distance = max(TP = max(x spread) x spread, TP = max(..., x ATR M1) x ATR)` = max(1.2 x spread, 0.18 x ATR)
* `SL distance = max(2.0 x spread, 0.35 x ATR)`
* BUY: `TP = ask + TPdist`, `SL = ask - SLdist`. SELL: `TP = bid - TPdist`, `SL = bid + SLdist`.

### 1.4 Internal momentum score (for exits only - never blocks another engine)
For direction d (BUY uses the bullish ratio r, SELL uses 1 - r; thr = BUY ratio):
```
c1 = clamp((r_d - 0.5) / (thr - 0.5), 0, 1)        weight 0.40
c2 = clamp((velRatio - 1) / (velThr - 1), 0, 1)    weight 0.25   (velThr = 1.25)
c3 = clamp(accel / accelThr, 0, 1)                 weight 0.15   (accelThr = 0.20; if thr<=0 -> 1)
c4 = 1 if ROC sign agrees with d else 0            weight 0.20
score = 100 x (0.40 c1 + 0.25 c2 + 0.15 c3 + 0.20 c4)
```
At entry the score is ~100 by construction.

### 1.5 Exits specific to Momentum (when **Momentum-loss exit ON**)
* *Inversion*: over the last **Inversion window** ticks (10) the ratio is against the trade (BUY: bullish
  ratio < 0.5; SELL: bullish ratio > 0.5). Its start time is remembered per position; it resets when the
  inversion disappears.
* **MOMENTUM_LOSS**: score < **Exit when momentum score below** (60) AND inversion persisted >=
  **Tick inversion persistence** (500 ms).
* **MOMENTUM_INVALIDATION**: price back inside the micro-range (BUY: bid <= breakout level; SELL: bid >=
  breakout level) AND inversion persisted >= 500 ms.
* Plus common: TP, SL, break-even, trailing, **Time-stop** (EURUSD 45 s, XAUUSD 30 s, BTCUSD 30 s initial -
  to be optimized), hard max.

---

## 2. Engine B - FVG (M5, optional M1 precision)

### 2.1 Detection (on each new bar of **FVG timeframe**, scanning **Bars scanned for FVGs**)
Candles B1 (oldest), B2, B3 (newest), all closed:
* Bullish FVG: `Low(B3) > High(B1)`; zone `[bottom = High(B1), top = Low(B3)]`.
* Bearish FVG: `High(B3) < Low(B1)`; zone `[bottom = High(B3), top = Low(B1)]`.
* CE (consequent encroachment) = (top + bottom) / 2.
* Filters: `gap >= Min gap size (x ATR) x ATR(FVG tf)` and `gap >= Min gap size (x spread) x spread`.
* Zone id: `FVG-<B|S>-<time of B2>`; state INTACT. Max **Max zones kept** (oldest dropped).
* On start, bars after B3 are replayed so that already-mitigated / invalidated zones get the correct state.

### 2.2 Zone life cycle
* **Age** = bars since B3. Expired when age > **Max zone age (bars)**.
* **Mitigation**: each time price enters the zone after being outside (tick-level; bar-level during the start
  replay) the counter increases; when it exceeds **Max mitigations** the zone is EXHAUSTED.
* **Invalidation**: bullish zone: close (of a candle of the FVG timeframe, or tick when **Invalidate on candle
  close** OFF) below `bottom - Invalidation buffer x ATR`; bearish: close above `top + buffer`.
* **Trades per zone** <= **Max trades per zone** (1).

### 2.3 Entry (each tick, INTACT/MITIGATED zones within **Max price distance to zone** x ATR)
* TOUCH: bullish -> ask <= top (and bid > invalidation). Bearish -> bid >= bottom.
* CE: bullish -> ask <= CE. Bearish -> bid >= CE.
* REJECTION: last closed candle of the refine timeframe (M1 if **Use M1 for entry precision**, else FVG tf):
  bullish -> low <= top, close > CE, close > open, lower wick >= **REJECTION: min wick** % of the candle
  range; bearish symmetric. Signal on the first tick after that candle closes.
* **BOS_REQUIRED** (default false): when true, the structure event chosen in **Structure event accepted** must
  be present: BOS in the zone direction (a close beyond the last swing formed before B1, at or after B1) or a
  CHoCH (BOS against the previous structure direction). Otherwise it is logged only (`struct_ok`).
* Setup id = zone id + `-T<trade #>`.

### 2.4 SL / TP
* SL (ZONE): bullish `bottom - buffer`, bearish `top + buffer`; (SWING): beyond the lowest low / highest high of
  B1..B3. `buffer = max(SL buffer (x spread) x spread, SL buffer (x ATR) x ATR)`.
* TP LIQUIDITY: nearest swing high above entry (bullish) / swing low below (bearish) on the FVG timeframe, kept
  only if its R (TP distance / SL distance) is within **TP min R** .. **TP max R**, else capped to max R, else
  fallback **TP R multiple**. TP ATR: entry +/- **TP ATR multiple** x ATR. TP RR: entry +/- R x SL distance.
* Exit **FVG_INVALIDATED** when the zone of an open trade is invalidated (if **Exit open trade if zone
  invalidated** ON). Common exits apply (time-stop default 120 s - may need increase for M5, see tests).

---

## 3. Engine C - Range / Mean Reversion (M1 or M5)

### 3.1 Range detection (on each new bar of **Range timeframe**)
All must hold (on closed bars):
1. ADX(**ADX period**) < **Max ADX for a range** (20); if **Require falling ADX**: ADX[1] <= ADX[1 + slope bars].
2. |EMA20 - EMA50| <= **Max |EMA20-EMA50| (x ATR)** x ATR(range tf).
3. `hi` = highest high, `lo` = lowest low of **Range lookback** bars; `width = hi - lo`;
   `width >= max(Min range width (x ATR) x ATR, Min range width (x spread) x spread)` and
   `width <= Max range width (x ATR) x ATR`.
4. No significant directional swing: `|close[1] - close[lookback]| <= Max net drift % x width`.
5. Each boundary touched by at least **Min touches per boundary** bars (bar high within the top edge zone /
   bar low within the bottom edge zone).
Range id: `RNG-<time of first bar>-<lo>-<hi>` (rounded). State ACTIVE.

### 3.2 Entry (each tick while ACTIVE)
Edge zone = **Entry zone near boundary** % of width.
* Impulse protection (mandatory): velocity ratio <= **Max tick velocity ratio** and ATR / median ATR <=
  **Max ATR / median ATR**.
* BUY: `lo - breakBuf <= bid <= lo + edge` AND confirmation AND bullish ratio of the last **Tick window for
  buyer/seller return** ticks >= **Min returning tick ratio**.
* SELL: `hi - edge <= bid <= hi + breakBuf` AND confirmation AND bearish ratio (1 - bullish ratio) >= min.
* Confirmation (**Edge confirmation**): *slowdown* = velocity ratio <= 1.0; *rejection* = last closed candle
  has a wick toward the boundary >= **Rejection: min wick** % of its range. NONE / SLOWDOWN / REJECTION /
  EITHER / BOTH.
* Touch counting: each new entry of price into the edge zone = new touch number; **Max trades per boundary
  touch** (1). Setup id = range id + `-B|S-T<touch>`.

### 3.3 SL / TP
* SL: BUY `lo - buffer`, SELL `hi + buffer`, `buffer = max(SL buffer (x spread) x spread, SL buffer (x ATR) x ATR)`.
* TP: **TP target** MID -> `mid -/+ offset`, OPPOSITE -> `hi - offset` (BUY) / `lo + offset` (SELL);
  `offset = TP offset % x width`.

### 3.4 Invalidation and exit
* Confirmed breakout: a closed candle beyond `hi + breakBuf` or `lo - breakBuf` (breakBuf = **Breakout
  confirmation buffer** x ATR) -> range BROKEN (no new entries until a new range forms).
* Fast invalidation on ticks: bid beyond the boundary + breakBuf while velocity ratio > **Max tick velocity
  ratio** -> range BROKEN.
* When BROKEN and **Exit quickly on confirmed breakout** ON -> open Range positions close with
  **RANGE_BREAKOUT**.

---

## 4. H1 context filter (spec section A)

On each new H1 bar (closed bar 1): EMA fast/slow (20/50), ADX(14) with +DI/-DI.
* BULLISH: EMA20 > EMA50 AND +DI > -DI + **H1 min +DI/-DI gap** AND ADX > **H1 ADX directional threshold** (18).
* BEARISH: EMA20 < EMA50 AND -DI > +DI + gap AND ADX > threshold.
* NEUTRAL: otherwise.

| Mode | Momentum | FVG | Range |
|---|---|---|---|
| OFF | never blocks | never blocks | never blocks |
| SOFT (default) | never blocks, never changes the lot - context shown + logged | same | same |
| STRICT | BULLISH blocks SELL, BEARISH blocks BUY | same | blocks ALL new Range entries while H1 is BULLISH/BEARISH with ADX >= **H1 'strong trend' ADX** |

NEUTRAL never creates a direction. STRICT never forces a trade in the trend direction.

---

## 5. Common entry filters (Risk & Safety Gate)

| Filter | Rule | Reason code |
|---|---|---|
| Master switch | **Enable new entries** OFF | TRADING_OFF |
| Terminal | AutoTrading off, EA trading not allowed, account trading disabled, disconnected | TERMINAL |
| Symbol | trade mode disabled / close-only; unsupported symbol with check = BLOCK | SYMBOL |
| Stale market | last tick older than **Max tick age** | STALE_TICK |
| Warm-up | data not ready, or < **No new entries after start** seconds since start | WARMUP |
| Duplicate instance | same Instance ID already alive on this terminal/account/symbol | MULTI_INSTANCE |
| 10 % pause | see section 7 | DD_PAUSE |
| Broker error pause | after a permanent error, **Pause after a permanent broker error** seconds | ERROR_COOLDOWN |
| News | inside [event - before, event + after] for matching currency/impact/keyword | NEWS |
| Session | outside allowed days/hours (only when the filter is ON) | SESSION |
| Rollover | inside [rollover - before, rollover + after] | ROLLOVER |
| Spread | `spread_pts > mode limit` (limit 0 -> `spread > Auto max spread x ATR`) | SPREAD |
| Volatility anomaly | ATR > k x median ATR, or velocity ratio > k, or spread > k x median spread | VOLATILITY |
| Execution quality | rolling average adverse slippage > k x average spread, or average latency > limit | EXEC_QUALITY |
| Conflict hold | opposite signals within the conflict window | CONFLICT |

Per-signal checks then apply in the order of `docs/09` section 8 (cooldown, limits, hedging, duplicates,
stops level, SL/TP ratio, risk, margin, exposure).

**Mode delay** (SPEED 1500 / AGGRESSIVE 750 / ULTRA 300 ms): with *Cooldown* usage an engine cannot open
two entries closer than the delay; with *Confirm* usage the signal is parked and re-validated on every tick
and sent only after it stayed valid for the whole delay (and before it expires - the expiry is extended to
`delay + TTL` for parked signals).

**Opposite signals**: BUY and SELL from different engines in the same cycle, or within
**Opposite-signal conflict window** -> both refused (CONFLICT) and all entries blocked for **Entry block after
a conflict**; engines re-evaluate afterwards on fresh ticks. **Hedging OFF** (default): no new BUY while a SELL
of this instance is open and vice versa.

---

## 6. Position management (all engines)

Distances are measured on the initial TP distance `D = |initial TP - open price|`.
1. **Break-even**: when favourable move >= **Break-even trigger** % of D (70 %) -> SL to
   `open +/- Break-even lock % x D` (only if it improves the SL).
2. **Trailing**: when favourable move >= **Trailing trigger** % of D (85 %) -> SL = price -/+ **Trailing
   distance** % x D, moved only by steps >= **Trailing min step** % of D.
3. **Time-stop** per engine (0 = off) and **Hard max holding time** (120 s) -> market close.
4. Engine-specific exits (Momentum loss / invalidation, FVG invalidation, Range breakout).
5. Modifications respect broker stops level and freeze level and **Min interval between SL modifications**.
6. Exits are retried on the following cycles until the position is gone.
7. MAE / MFE (points) are tracked on every tick for the trade journal.

---

## 7. Equity drawdown pause (spec section 10 + G.4, as agreed on 05-07/10/2026)

* `DD % = (reference - equity) / reference x 100`; reference = peak equity (default), start balance or the
  equity at the start of the server day.
* `DD % >= Drawdown threshold (10 %)`: **1) STOP** new entries immediately; **2) RE-ACTIVATE** safeties
  (news reload, session/rollover recompute, exposure refresh, symbol spec refresh, multi-instance heartbeat,
  position reconcile); **3) VERIFY** them (every module runs a self-check, each result logged as
  `SAFETY_CHECK` PASS/WARN); **4) RESTART automatically** when **Pause length** (10 s) has elapsed - a strict
  timer that never waits for any other condition. Open positions are managed normally during the pause.
* On restart the reference is re-based to the current equity, so the next pause happens only after a further
  10 % fall (prevents a pause loop). No automatic definitive daily stop exists.

---

## 8. Consecutive losses (B.4)
X losses in a row (net < 0; net >= 0 resets the counter) per engine or per instance -> cooldown Y minutes.
Signals generated during the cooldown are refused (CONSEC_LOSS) and their setup ids are **burned**: after the
cooldown only a NEW setup can trade. Independent from the 10 % pause.

## 9. Martingale (optional, OFF by default)
Per engine: after a loss `step = min(step + 1, max steps)`, after a win `step = 0`. Risk % (or fixed lot) x
`multiplier ^ step`, always capped by **Max risk per trade - hard cap**, **Max lot per trade**, exposure limits.
A new valid setup is always required.
