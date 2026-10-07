# 02 - Architecture and Workflow

> How FRANCKY TRI-FLUX is built and how data moves from the market to the order. Diagrams use Mermaid
> (rendered by GitHub, VS Code, Obsidian...). Binding signatures are in `docs/09_SSOT_Developer_Contract.md`;
> exact trading rules in `docs/03_Strategy_Logic.md`.

## 1. Big picture

* **One EA, two platforms.** `FranckyTriFlux.mq5` (MT5, reference) and `FranckyTriFlux.mq4` (MT4 port) are
  20-line files that forward terminal events to `CFranckyController`. Everything else is in
  `Include\FranckyTriFlux\`.
* **Shared Core + Platform layer.** All logic (engines, risk, protections, logging, chart UI) is in `Core\` and
  is byte-identical in both trees. Only `Platform\Platform.mqh` (class `CPlatform`) differs: CTrade /
  CopyTicks / indicator handles / economic calendar on MT5, OrderSend / iATR / MarketInfo on MT4.
* **One instance = one chart symbol.** The symbol is captured at start; every order uses it. Several symbols
  = several charts (instances), each with its own Instance ID and magic numbers.
* **Three independent engines.** Momentum / Micro-breakout, FVG, Range / Mean Reversion run in parallel on
  every tick; each can trade alone (max 3 positions each, 9 per symbol).

```mermaid
flowchart LR
  subgraph Terminal["MetaTrader 5 / 4 terminal"]
    EV["OnInit / OnTick / OnTimer / OnTradeTransaction / OnTester / OnDeinit"]
  end
  EV --> CTRL["CFranckyController<br/>(Controller.mqh)"]
  subgraph Core["Shared Core (identical MT5/MT4)"]
    CTRL --> MD["Market Data Layer<br/>CMarketData + CTickBuffer"]
    CTRL --> H1["CH1Context<br/>OFF / SOFT / STRICT"]
    CTRL --> EM["CEngineManager"]
    EM --> E1["Engine A<br/>Momentum / Micro-breakout"]
    EM --> E2["Engine B<br/>FVG"]
    EM --> E3["Engine C<br/>Range / Mean Reversion"]
    CTRL --> CR["CConflictResolver<br/>+ CSignalConfirmer"]
    CTRL --> SG["CSafetyGate<br/>(Risk & Safety Gate)"]
    SG --> PROT["CDrawdownGuard / CConsecLossGuard / CExecQualityGuard"]
    SG --> FIL["CNewsFilter / CSessionFilter / CRolloverFilter"]
    SG --> RISK["CRiskManager / CExposureGuard / CMultiInstanceGuard"]
    CTRL --> EX["CExecutionEngine<br/>orders + retries"]
    CTRL --> PM["CPositionManager<br/>BE / trailing / time-stops / engine exits"]
    PM --> TR["CPositionTracker"]
    EX --> TR
    CTRL --> LOG["CLogger / CTradeJournal / CStats"]
    CTRL --> ST["CStateStore<br/>(restart recovery)"]
    CTRL --> UI["CChartUI<br/>panel + chart objects"]
  end
  MD --> PF["CPlatform<br/>(MT5 or MT4 implementation)"]
  EX --> PF
  TR --> PF
  RISK --> PF
  FIL --> PF
  PF --> BROKER[("Broker server")]
```

## 2. Module responsibilities (spec Table 5 mapping)

| Spec module (Table 5) | Class(es) | File |
|---|---|---|
| Market Data Layer | `CMarketData`, `CTickBuffer`, `CClock` | MarketData.mqh, TickBuffer.mqh, Clock.mqh |
| H1 context (Addendum A) | `CH1Context` | H1Context.mqh |
| Strategy Engine Manager | `CEngineManager` | EngineManager.mqh |
| Engines A/B/C | `CEngineMomentum`, `CEngineFVG` (+ `CStructure` for BOS/CHoCH/liquidity), `CEngineRange` | Engine*.mqh, Structure.mqh |
| Signal Bus | `SSignal` struct + signal array of the cycle | Types.mqh |
| Conflict Resolver | `CConflictResolver`, `CSignalConfirmer` | ConflictResolver.mqh |
| Risk & Safety Gate | `CSafetyGate` + protections, filters, risk | SafetyGate.mqh, Protections.mqh, Filters.mqh, RiskManager.mqh |
| Execution Engine | `CExecutionEngine` (+ `CPlatform` order calls) | Execution.mqh, Platform.mqh |
| Position Manager | `CPositionManager`, `CPositionTracker` | PositionManager.mqh, PositionTracker.mqh |
| Journal & Analytics | `CLogger`, `CTradeJournal`, `CStats` | Logger.mqh, Journal.mqh, Stats.mqh |
| Restart recovery (B.7) | `CStateStore`, `CPositionTracker::RecoverOnStart` | StateStore.mqh |
| Visual layer | `CChartUI` | ChartUI.mqh |
| Tester / Optimizer | `OnTester` -> `CStats::OptCriterion`, generated .set/.ini | Stats.mqh, tools/generate.py |

## 3. Data flow - market to order (one cycle)

```mermaid
sequenceDiagram
  autonumber
  participant T as Terminal (OnTick/OnTimer)
  participant C as Controller
  participant M as MarketData + TickBuffer
  participant E as Engines A/B/C
  participant R as ConflictResolver
  participant G as SafetyGate
  participant X as Execution
  participant P as PositionManager/Tracker
  participant L as Logger/Journal/Stats/UI
  T->>C: event (tick or 250 ms timer)
  C->>M: Update(): new ticks, spread, ATR/EMA/ADX on new bars, tick velocity
  C->>C: day change, new-bar dispatch, H1 context update
  C->>C: DrawdownGuard.Update() (10 % pause state machine)
  C->>P: Sync(): detect closed trades -> journal, stats, consecutive-loss, martingale
  C->>P: Manage(): engine exits, time-stops, BE, trailing (always, even during pauses)
  C->>G: GlobalCheck() once per cycle (cached reason)
  C->>X: due retries -> Gate.Revalidate -> Open
  C->>E: Evaluate() on new ticks (each engine independently)
  E-->>C: SSignal[] (engine, dir, SL, TP, invalidation, reason, quality)
  C->>R: Resolve(): expired / opposite-signal conflict / ordering by quality
  loop each signal
    C->>G: global reason? then CheckSignal(): limits, hedging, duplicates, stops, ratio, lots, margin, exposure
    alt confirmation delay mode
      C->>C: park in Confirmer until delay elapsed (re-validated every tick)
    else accepted
      C->>X: Open(signal, lots)
      X-->>C: filled position (fill price, slippage, latency) or retry queued
      C->>P: tracker.Add, engine.OnEntry (setup marked traded)
    end
    C->>L: signals.csv row (ACCEPTED/REJECTED + reason), stats, chart arrow
  end
  C->>L: periodic: state save, heartbeat, news refresh, stats.csv, panel
```

### 3.1 Why bar data is refreshed only on new bars
Engines react tick-by-tick, but indicator values (ATR, EMA, ADX, ROC) are read from the **last closed bar**
and cached once per bar. This keeps the per-tick work tiny (HFT-style reactivity), makes backtests
reproducible and avoids repainting.

## 4. Signal life cycle

```mermaid
stateDiagram-v2
  [*] --> Generated: engine Evaluate()
  Generated --> Expired: now > expiry (TTL per engine)
  Generated --> Conflict: opposite signal within window -> hold 300 ms
  Generated --> GateCheck
  GateCheck --> Rejected: reason code (SPREAD, NEWS, MAX_POS_ENGINE, HEDGE_OFF, ...)
  GateCheck --> Parked: mode delay = Confirm
  Parked --> Rejected: no longer valid (SIGNAL_INVALID / EXPIRED)
  Parked --> Sending: stayed valid for the whole delay
  GateCheck --> Sending: accepted (lots computed)
  Sending --> Filled: broker DONE
  Sending --> RetryQueued: transient error (requote, off quotes, timeout...)
  RetryQueued --> GateCheck: delay elapsed, revalidate (signal, spread, drift, permissions)
  Sending --> Failed: permanent/fatal error (fatal -> error cooldown)
  Filled --> [*]
  Rejected --> [*]
  Expired --> [*]
  Conflict --> [*]
  Failed --> [*]
```
Every terminal state writes one row in `signals.csv` with its reason.

## 5. Position life cycle

```mermaid
stateDiagram-v2
  [*] --> Open: fill (SL/TP attached)
  Open --> BreakEven: favourable move >= BE trigger % of TP distance
  BreakEven --> Trailing: favourable move >= trailing trigger %
  Open --> Trailing
  Open --> Closing: engine exit (momentum loss / FVG invalidated / range breakout)
  Open --> Closing: time-stop or hard max time
  BreakEven --> Closing
  Trailing --> Closing
  Open --> Closed: SL / TP hit at broker
  BreakEven --> Closed: break-even SL hit
  Trailing --> Closed: trailing SL hit
  Closing --> Closing: close failed -> retry next cycle (>= 250 ms)
  Closing --> Closed
  Closed --> [*]: trades.csv row, stats, consecutive-loss counter, martingale step, chart exit marker
```

## 6. Equity drawdown pause (spec G.4 as agreed)

```mermaid
stateDiagram-v2
  [*] --> ARMED
  ARMED --> PAUSED: DD% >= threshold (10 %)\n1 STOP new entries\n2 re-activate safeties\n3 verify (SAFETY_CHECK log rows)
  PAUSED --> PAUSED: open positions still managed\n(no new entries, reason DD_PAUSE)
  PAUSED --> ARMED: timer elapsed (10 s)\n4 automatic restart\nreference re-based to current equity
```
The pause is a strict timer; the verification never extends it.

## 7. Order retry flow (spec B.8)

```mermaid
flowchart TD
  A[Open order] --> B{Result}
  B -- DONE --> OK[Track position, log fill, slippage, latency]
  B -- ambiguous: timeout / error / reject --> R{Own position with same magic + comment opened just now?}
  R -- yes --> OK
  R -- no --> TRANS
  B -- transient: requote / price changed / off quotes / busy / connection --> TRANS{attempt < max retries?}
  TRANS -- no --> FAIL[ORDER_FAILED logged]
  TRANS -- yes --> Q[Queue retry after delay - non blocking]
  Q --> V{Revalidate: signal still valid? not expired? price drift <= limit? spread / news / session / DD / permissions OK?}
  V -- no --> DROP[Drop: SIGNAL_INVALID / PRICE_DRIFT / reason]
  V -- yes --> A
  B -- permanent: invalid stops / volume --> FAIL
  B -- fatal: no money / trading disabled / market closed --> CD[ERROR_COOLDOWN pause of new entries] --> FAIL
```

## 8. Restart / reconnection recovery (spec B.7)

```mermaid
flowchart TD
  S[OnInit] --> L[Load state file: DD state, cooldowns, martingale steps, last entries, traded setup ids, position metadata]
  L --> P[Scan open positions of chart symbol]
  P --> M{magic belongs to this instance?}
  M -- no --> IGN[ignore - never touched]
  M -- yes --> K{metadata in state?}
  K -- yes --> RES[restore engine, initial SL/TP, BE/trailing flags, MAE/MFE]
  K -- no --> REB[rebuild from position: engine from magic, initial SL/TP = current]
  RES --> G
  REB --> G
  G[Positions closed while offline -> journal with CLOSED_WHILE_OFFLINE] --> W[Restart grace period: no new entries for N s]
  W --> RUN[Normal cycle - engines re-detect zones/ranges; traded setup ids prevent duplicate re-entry]
```

## 9. Identification of orders

| Item | Rule |
|---|---|
| Magic number | `Magic number base + Instance ID x 10 + engine` (1 Momentum, 2 FVG, 3 Range). Default base MT5 5 100 000, MT4 4 100 000. |
| Order comment | `FTF|MOM|I1|<setup>` (max 31 chars; brokers may alter comments - the magic is authoritative). |
| StrategyID | Derived from the magic number, stored in every journal row. |
| Instance ownership | An instance only manages positions with its own 3 magics on its chart symbol. |
| Duplicate instance | A second chart with the same Instance ID/symbol/account is detected through terminal global variables and refuses new entries (MULTI_INSTANCE). |

## 10. Timing model

| Activity | Frequency |
|---|---|
| Tick ingestion, engines, gate, execution, position management | every tick |
| Indicator cache (ATR, EMA, ADX, ROC, ATR median) | new M1/M5/H1 bar |
| FVG detection / Range detection | new bar of their timeframe |
| H1 context | new H1 bar |
| Timer cycle (pause expiry, retries, UI when no ticks) | 250 ms (live and MT5 tester; MT4 tester has no timer) |
| Dashboard refresh | 250 ms |
| State save / multi-instance heartbeat | every 2 s when changed |
| News list refresh | 60 min |
| stats.csv | 60 min + at stop |

## 11. Files written at run time

| File | Content |
|---|---|
| `ftf.log` | Human-readable log (INFO/DEBUG/TRACE) of every decision |
| `signals.csv` | One row per setup decision (accepted/rejected + reason) |
| `trades.csv` | One row per closed trade with all 20 mandatory fields of spec section 12 |
| `events.csv` | Protections, pauses, safety checks, order errors, retries, recovery |
| `stats.csv` | Per-engine + total statistics (Table 17 / section 11 metrics) |
| `state\*.state` | Restart recovery state (live/demo only) |

See `docs/06_Logs_and_Diagnostics.md` for the columns and how to analyse them.
