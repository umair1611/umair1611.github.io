# FRANCKY TRI-FLUX HFT ULTRA SCALPING — Final Specification (corrected English translation)

> **Source:** `FRANCKY_TRI-FLUX_CAHIER_FINAL_CORRIGE_UMAIR_05-10-2026.txt` (French, final locked reference).
> **This translation** corrects and completes `FRANCKY_TRI_FLUX_Final_Reference_English_Translation.docx`.
> The issues found in that translation are listed in `docs/01a_Translation_Review.md`.
>
> **Translator's conventions**
> * The V1 text and the addendum are translated **as written**: they are not reworded, even where Section G
>   later replaces something. Where Section G (05/10/2026) or the clarification agreed afterwards changes a
>   V1 rule, a **[TN]** (translator's note) shows the current rule.
> * **[TN G.1]**: every V1 mention of **GBPUSD** must now be read as **BTCUSD**. The final markets are
>   **EURUSD, XAUUSD, BTCUSD**.
> * Original spelling of identifiers is kept (H1_FILTER, OPPOSITE_HEDGE, MAX_POSITIONS_PER_SYMBOL, ...).

---

# FRANCKY TRI-FLUX HFT ULTRA SCALPING
## FINAL ARCHITECTURE V1 - MT5 + MT4 - TOTAL FREEDOM OF USE
### EURUSD | GBPUSD | XAUUSD  **[TN G.1: EURUSD | XAUUSD | BTCUSD]**

## FINAL ARCHITECTURE V1 - 3 INDEPENDENT ENGINES
MetaTrader 5 / MQL5 + MetaTrader 4 / MQL4 - EURUSD • GBPUSD • XAUUSD **[TN G.1: BTCUSD]** - simultaneous or separate use

## 0. Executive summary
* Definitive V1 architecture: 3 independent engines only. Pullback and Order Block are not part of V1.
* A valid strategy can trigger a trade on its own after the common safety checks. Momentum + FVG + Range
  alignment is never required.
* BOS/CHoCH = structure or optional confirmation, never a standalone strategy.
* H1 = configurable context OFF / SOFT / STRICT. Default for the aggressive profile: SOFT.
* Opposite hedging disabled by default. Initial maximum: 3 positions per symbol, configurable.
  **[TN G.2: replaced by "up to 3 positions per engine, i.e. up to 9 per symbol, manually adjustable".]**
* Statistics must be separated by StrategyID, symbol and mode so that the frequency and robustness of each
  engine can be verified.
* "HFT" here means HFT-style / retail ultra-scalping on MT5/MT4, not institutional co-located HFT. MT5
  remains the technical reference version.

## 1. Objectives and non-negotiable constraints
**Dual-platform principle:** MT5/MQL5 remains the technical reference for development and initial
validation. This development priority creates no usage restriction after delivery.

An MT4/MQL4 version must be delivered with the same 3 engines, protections and management logic, as
faithfully as MT4's technical limits allow. Once both versions are delivered, MT5 and MT4 must be able to
run and trade simultaneously or separately, with no dependency between them. Any technical divergence
imposed by MT4 must be stated explicitly and documented.

### 1.1 Freedom of use / perpetual licence / multiple installations
* The MT5 and MT4 versions are two implementations of the same FRANCKY TRI-FLUX system. They must be able to
  run simultaneously or separately, each trading independently.
* The client must be able to install and use FRANCKY on the same computer, on several different computers,
  on one or more VPSs, or on any combination of these compatible environments.
* A single VPS of sufficient size must be able to host an MT5 terminal running FRANCKY MT5 and an MT4
  terminal running FRANCKY MT4 at the same time. Two separate VPSs must never be a technical requirement
  imposed by the robot.
* No artificial limit on the number of installations or instances may be built into the delivered versions.
  No periodic activation, mandatory subscription, external licence server, expiry, or lock to a PC, hardware,
  account, broker or VPS.
* The right to use the delivered versions is perpetual: the client must be able to keep using the delivered
  files for life. Delivery of the MQ5 and MQ4 source code must let the client keep technical control of the
  versions acquired.
* Each instance must have configurable Magic Numbers, Strategy IDs and instance identifiers to avoid
  conflicts when several terminals, accounts or installations run in parallel.
* If several FRANCKY instances run on the same trading account, a configurable protection against duplicate
  orders and management conflicts must prevent one instance from modifying or closing, by mistake, a
  position that belongs to another instance.
* A failure or shutdown of one platform must not stop the other: MT4 and MT5 must stay operationally
  independent after delivery.

## 2. General software architecture  *(content: Tables 5 and 6)*
## 3. Correct classification of elements  *(content: Table 7)*
## 4. The 3 independent engines of V1  *(content: Table 8)*
### 4.1 Engine A - Momentum / Micro-breakout  *(Table 9)*
### 4.2 Engine B - Standalone FVG (Fair Value Gap)  *(Table 10)*
### 4.3 Engine C - Fast Range / Mean Reversion  *(Table 11)*

## 5. Timeframes and H1 context
* H1_FILTER = OFF / SOFT / STRICT; recommended aggressive default: SOFT. H1 informs the context without
  systematically blocking a valid setup.
* Momentum: ticks/M1 with M5 context; FVG: M5 with optional M1 precision; Range: M1/M5.
* Avoid mandatory multi-timeframe confirmations: the entry logic must stay short, measurable and executable.

## 6. Conflict management, hedging and simultaneous positions  *(Table 12)*
## 7. Common filters and execution  *(Table 13)*
## 8. SL / TP and automatic position management  *(Table 14)*
## 9. SPEED / AGGRESSIVE / ULTRA modes  *(Table 15)*

## 10. Drawdown, pause/resume and martingale
* Equity drawdown >= 10 %: immediately suspend NEW entries.
* Keep managing the positions already open normally.
* Initial sleep = 10 seconds, configurable.
* After the pause, automatically resume analysis if the safety conditions have returned to normal.
  **[TN G.4 + clarification agreed on 07/10/2026: the pause is a strict timer of a few seconds (10 s by
  default). FRANCKY stops new entries, re-activates and verifies its safeties, keeps managing open positions,
  and restarts automatically when the timer ends, without waiting for any other condition. See Section H.]**
* No automatic definitive daily stop; the user keeps final control.
* Martingale optional and can be disabled. A loss never gives the right to open a new position blindly.
* Even with martingale active, a new valid setup from one of the 3 engines is mandatory.

## 11. Performance requirement: target around 90 %  *(Table 16)*
* Forbidden: an artificially tiny TP relative to the SL to inflate the win rate.
* Forbidden: excessive SL, dangerous martingale, disproportionate risk, or over-optimisation to produce a
  cosmetic figure.
* The final report must show at least: win rate, profit factor, expectancy, max drawdown, number of trades,
  average win/loss, duration, spread/slippage — per strategy and per symbol.
* If 90 % is not sustainable out-of-sample and under degraded conditions, the developer must report the best
  robust rate obtained instead of forcing the parameters.
* The final choice must favour robustness and positive net expectancy, not the win rate alone.

## 12. Mandatory logging and statistics  *(statistics list: Table 17)*
Each logged trade/signal must contain:
1. StrategyID / StrategyName
2. Symbol
3. Mode SPEED/AGGRESSIVE/ULTRA
4. Timeframe
5. Signal date/time
6. Direction
7. Signal / requested / executed price
8. Spread
9. Slippage
10. Latency
11. Lot
12. SL
13. TP
14. Entry reason
15. Rejection reason
16. Exit reason
17. Trade duration
18. Gross / net PnL
19. MAE/MFE if possible
20. Equity/DD at the time of the trade

## 13. Backtest protocol and V1 validation
* Test each engine ALONE: Momentum / Micro-breakout, FVG, Range / Mean Reversion.
* Test each engine on EURUSD, GBPUSD **[TN G.1: BTCUSD]** and XAUUSD with variable spread and realistic
  commission and slippage.
* Produce frequency statistics: setups/day and trades/day, in addition to win rate, PF, expectancy and max DD.
* Separate in-sample optimisation from out-of-sample validation.
* Run sensitivity tests: performance must not disappear as soon as a parameter changes slightly.
* Run degraded execution-cost tests (higher spread/slippage).
* Then test the 3 engines TOGETHER with the Conflict Resolver, exposure limits and hedging OFF by default.
* First validate the MT5 version with the Strategy Tester, then with a demo/forward test in conditions close
  to the target broker, before freezing the reference logic.
* After MT5 validation, port the logic to MT4 and run equivalence tests per engine/symbol. Any difference
  imposed by MT4 limits (ticks, tester, execution) must be documented. An engine may be disabled on a symbol
  if the data show that it degrades the results.

## 14. Initial technical parameters  *(Table 18)*
All relevant parameters must be exposed as MQL5 inputs and, after porting, as MQL4 inputs, with separate SET
files EURUSD / GBPUSD / XAUUSD **[TN G.1: EURUSD / XAUUSD / BTCUSD]** for each platform.

## 15. Developer acceptance criteria
- [ ] MT5 and MT4 compile with no errors and no critical warnings.
- [ ] Only the 3 engines are present in V1: Momentum / Micro-breakout, FVG, Range / Mean Reversion.
- [ ] Each engine can be enabled/disabled independently.
- [ ] Isolation test: when only FVG is ON, only FVG trades are allowed; same for Momentum and Range.
- [ ] No global score blocks a valid independent strategy.
- [ ] BOS/CHoCH are not standalone strategy engines.
- [ ] Every trade is tagged with its StrategyID.
- [ ] Conflict Resolver, hedging OFF by default, max positions and handling of opposite signals are documented and configurable.
- [ ] Spread, slippage, drawdown, pause/resume and position management work in the Strategy Tester and on demo.
- [ ] Logs exportable as CSV or text file.
- [ ] Strategy Tester reports supplied per engine/symbol + final combination.
- [ ] MT5: complete MQ5 + EX5 + SET; MT4: complete MQ4 + EX4 + SET; perpetual right of use, no expiry, no subscription, no periodic activation, no PC/account/broker/hardware/VPS lock.
- [ ] No unjustified external DLL or hidden dependency.
- [ ] MT5 and MT4 can be launched simultaneously and trade independently.
- [ ] Installation test passed on one computer with one MT5 terminal + one MT4 terminal open at the same time.
- [ ] Recommended test on a single VPS hosting MT5 + MT4 simultaneously, if the VPS resources are sufficient.
- [ ] The robot can be installed on several computers/VPSs without extra activation or artificial blocking.
- [ ] Magic Numbers / Strategy IDs / Instance IDs are configurable and correctly isolate the orders of each instance.
- [ ] On the same account, the multi-instance protection prevents one instance from managing or duplicating another's orders by mistake.
- [ ] No expiry: the delivered versions stay usable for life under the agreed perpetual right of use.

## 16. Deliverables and quotation request  *(Table 19)*

## 17. Mandatory questions before ordering
1. Have you already developed and ported multi-strategy EAs with independent strategies on MT5 and MT4?
2. Can you implement an objective, backtestable FVG as defined here?
3. Can you provide separate reports for Momentum, FVG and Range?
4. How do you handle ticks, latency, slippage and signal conflicts?
5. Do you confirm hedging OFF by default and max 3 positions/symbol? **[TN G.2: now up to 3 per engine / 9 per symbol.]**
6. Do you confirm MT5 (MQ5, EX5, SET) + MT4 (MQ4, EX4, SET), simultaneous or separate use, multiple installations, perpetual right of use, documentation, tests and no licence lock?
7. What is your fixed price, lead time, number of revisions and support period?

---

# SPECIFICATION TABLES

### Table 1 — FINAL V1 DECISION
This version replaces all previous versions. V1 contains only three independent trading engines:
(1) Momentum / Micro-breakout, (2) FVG, (3) Range / Mean Reversion. A valid strategy can trigger a trade
without waiting for the other two to align.

### Table 2 — MAIN OBJECTIVE
Retail HFT-style / aggressive ultra-scalping robot, highly reactive and modular. The 3 engines were selected
for a high potential frequency of opportunities, but their real frequency must be measured by backtests and
demo tests. Optimisation goal: aim for about 90 % winning trades or more ONLY if this level is robust and
sustainable, without risk tricks.

### Table 3
| Item | Specification |
|---|---|
| Platform | MetaTrader 5 / MQL5 + MetaTrader 4 / MQL4; two versions of the same system, usable simultaneously or separately. |
| Markets | EURUSD, GBPUSD, XAUUSD **[TN G.1: EURUSD, XAUUSD, BTCUSD]** |
| Modes | SPEED, AGGRESSIVE, ULTRA — no NORMAL mode |
| Deliverables | MT5: MQ5 + EX5 + SET / MT4: MQ4 + EX4 + SET / documentation + test reports / configurable Magic Numbers and Strategy IDs. |
| Licence | Perpetual right of use; no expiry, no subscription, no periodic activation, no PC / account / broker / hardware / VPS lock; no external licence server. |
| Installations | Same PC, several PCs, a single VPS for MT5+MT4, several VPSs: all these configurations must be allowed. |

### Table 4 — Objectives and constraints
| Item | Specification |
|---|---|
| Trading objective | Obtain regular, fast opportunities without manufacturing trades when no valid setup exists. |
| Performance objective | Aim for about 90 % winning trades or more during a robust optimisation IF this is sustainable. No guarantee of profitability or of a future win rate. |
| Prohibitions | No fake 90 % obtained with a tiny TP, a disproportionate SL, a dangerous martingale, excessive risk, retrospective filtering or over-fitted parameters. |
| Architecture | 3 independent engines only: Momentum / Micro-breakout, FVG, Range / Mean Reversion. |
| Activation | Each engine must be switchable ON/OFF independently, per symbol and per parameter profile. |
| Markets | EURUSD, GBPUSD, XAUUSD only for V1. **[TN G.1: EURUSD, XAUUSD, BTCUSD]** |
| Modes | SPEED, AGGRESSIVE, ULTRA only. |
| Code | MT5 source: complete MQ5 + EX5. MT4 port: complete MQ4 + EX4. No licence lock or hidden dependency. |
| Reference version | MT5/MQL5 remains the technical reference for development and initial validation. After both versions are delivered, no usage dependency is imposed between MT5 and MT4. |
| MT4 port | Reproduce the 3 engines and the risk/execution management in MQL4 as faithfully as technically possible. The port must not restrict simultaneous use with MT5. |
| Equivalence | Any MT4 difference caused by ticks, the Strategy Tester, orders or platform functions must be documented; no silent strategy change. |
| Simultaneous running | MT5 and MT4 must be able to run and trade at the same time on the same PC, on two different PCs, on one VPS or on several VPSs, with independent accounts/terminals/settings. |
| Perpetual licence | Lifetime use of the delivered versions; no expiry, subscription or periodic activation. |
| Multiple installations | No artificial installation or instance limit tied to the delivered robot. |
| Independence | Stopping or a failure of MT4 must not stop MT5, and vice versa. |

### Table 5 — General software architecture (modules)
| Item | Specification |
|---|---|
| Market Data Layer | Ticks, Bid/Ask, spread, OHLC M1/M5/H1, ATR, EMA, ADX/DI, ROC, tick speed and acceleration. |
| Strategy Engine Manager | Runs the 3 active engines in parallel. Each engine returns its own Signal object. |
| Signal Bus | Receives StrategyID, symbol, direction, price, SL, TP, expiry, reason, internal quality and data useful for the log. |
| Conflict Resolver | Handles only conflicts and duplicates; it never turns several strategies into a mandatory condition. |
| Risk & Safety Gate | Spread, slippage, margin, exposure, drawdown, number of positions, broker permissions and volatility anomaly. |
| Execution Engine | Sends/modifies orders; measures slippage and latency; respects the broker's stops/freeze levels. |
| Position Manager | Break-even, trailing, time-stop, strategy-specific exits, closing on invalidation. |
| Journal & Analytics | Full history per StrategyID/symbol/mode and performance measurements. |
| Tester / Optimizer | MT5: test each engine alone, then the 3 together. After validation, run MT4 equivalence tests without changing the functional logic. |

### Table 6 — Recommended flow
OnTick -> market update -> run the 3 active engines -> collect signals -> resolve conflicts -> safety
checks -> execution -> position management -> logging.

### Table 7 — Classification of elements
| Item | Specification |
|---|---|
| STRATEGY | Has its own detection, entry, invalidation, SL, TP and exit rules; can trigger a trade on its own. |
| CONFIRMATION | May reinforce a setup. Examples: BOS, CHoCH, rejection, momentum recovery. Must not become an artificial strategy. |
| FILTER | Allows/refuses an execution for quality or context reasons: spread, slippage, extreme volatility, H1 if enabled. |
| MANAGEMENT | Lot, break-even, trailing, time-stop, drawdown pause, optional martingale, position limits. |

### Table 8 — Frequency principle
These three engines are chosen as a starting selection for their potential for frequent opportunities in
different regimes: impulse, imbalance/retest, and sideways market. Their real frequency must be measured; it
is neither assumed nor guaranteed.

### Table 9 — Engine A: Momentum / Micro-breakout
| Item | Specification |
|---|---|
| Role | Most reactive engine: capture accelerations, micro-impulses and micro-range breakouts. |
| Timeframes | Ticks + M1; M5 available as SOFT context. |
| Tick window | 50 ticks by default. |
| Initial BUY | Bullish tick ratio >= 62 %, 2-s velocity >= 1.25x the 30-s median, acceleration >= +20 %, break above the micro-range + buffer, compatible directional momentum. |
| Initial SELL | Bullish tick ratio <= 38 %, symmetric velocity/acceleration conditions, break below the micro-range + buffer, compatible momentum. |
| Micro-range | 20 ticks by default. |
| Breakout buffer | max(0.15 x spread, 0.02 x ATR). |
| Internal confirmations | ROC(5), ATR(14), ADX/DI, EMA M1/M5 may be used inside this engine; they do not block FVG or Range. |
| Invalidation | Fast return into the micro-range + persistent tick reversal / loss of momentum. |
| Exits | Dynamic TP/SL, break-even, short trailing, momentum-loss exit, time-stop. |

### Table 10 — Engine B: FVG (Fair Value Gap)
| Item | Specification |
|---|---|
| Role | Trade an FVG scenario without requiring the agreement of Momentum or Range. |
| Main timeframe | M5. M1 may refine the entry only if the option is enabled. |
| Bullish FVG | 3-candle sequence: Low of candle 3 > High of candle 1. Zone = [High C1 ; Low C3]. |
| Bearish FVG | 3-candle sequence: High of candle 3 < Low of candle 1. Zone = [High C3 ; Low C1]. |
| Own filters | Minimum gap size relative to ATR, maximum age, maximum number of mitigations, spread, distance to price. All configurable and optimisable. |
| Entry modes | Touch, 50 % / CE, or Rejection. The mode is configurable and must be compared in backtests. |
| BOS / CHoCH | Optional confirmation only. BOS_REQUIRED = false by default. |
| Invalidation | Zone invalidated by a programmable rule: close/overshoot beyond the invalidation edge + buffer; exposed parameter. |
| SL | Behind the real invalidation of the FVG / associated swing + buffer. No arbitrary microscopic SL. |
| TP | Next liquidity/structure, dynamic ATR target or configurable R multiple. |
| Stored state | Direction, bounds, CE, time, age, number of returns, status intact/mitigated/invalidated. |

### Table 11 — Engine C: Range / Mean Reversion
| Item | Specification |
|---|---|
| Role | Exploit returns toward the mean when the market consolidates instead of trending. |
| Timeframes | M1/M5; H1 only as context if the filter is enabled. |
| Range detection | Low/falling ADX, small EMA20/50 separation relative to ATR, no significant directional swings. All thresholds configurable. |
| Range construction | Recent highs/lows; minimum width above the spread and above a configurable multiple of ATR. |
| BUY | Price near the lower bound + rejection/slow-down + return of buying ticks. |
| SELL | Price near the upper bound + rejection/slow-down + return of selling ticks. |
| SL | Beyond the range bound + spread/ATR buffer. |
| TP | Range centre as first target; opposite bound optional depending on the mode. |
| Invalidation | Volatility expansion + confirmed range breakout: cancel the setup or exit quickly. |
| Protection | Do not mean-revert against an abnormal impulse: volatility/spread/tick-velocity filter mandatory. |

### Table 12 — Conflicts, hedging, positions
| Item | Specification |
|---|---|
| MAX_POSITIONS_PER_SYMBOL | 3 by default, configurable. **[TN G.2: up to 3 per engine, up to 9 per symbol, manually adjustable.]** |
| OPPOSITE_HEDGE | false by default. Do not automatically open opposite BUY and SELL on the same symbol. |
| Same direction | If a position already exists, ignore or stack within the max limit, according to a parameter. |
| Simultaneous opposite signals | Block the entry for a few hundred milliseconds and re-evaluate. Do not arbitrarily pick a winning strategy without a measurable rule. |
| StrategyID | Every order keeps its engine of origin for separate management and statistics. |
| MAGIC_NUMBER / INSTANCE_ID | Configurable per platform, account, symbol and instance in order to clearly separate MT4/MT5 orders and multiple installations. |
| MULTI_INSTANCE_GUARD | If several instances run on the same account, block or coordinate duplicates according to a parameter; one instance must never manage another's orders by mistake. |
| MT4_MT5_INDEPENDENCE | No mandatory synchronisation: both versions can trade in parallel or separately. |

### Table 13 — Common filters and execution
| Item | Specification |
|---|---|
| Spread | Refuse a new entry if spread > threshold specific to the symbol/mode; log the reason. |
| Slippage | Measure it for real. Refuse/reduce entries if the execution quality is out of tolerance. |
| Extreme volatility | Block new entries if spread/ATR/tick velocity signal an anomaly not foreseen by the engine. |
| Availability | Check AutoTrading, market open, trading allowed, margin, stops level/freeze level. |
| Target latency | <= 10 ms if the broker/VPS allows it; always measure rather than assume. |
| Platform | MT5 remains the latency/tick reference for the design. MT4 must keep the same execution intent. After delivery both platforms can run simultaneously, including on a single sufficiently sized VPS. |
| VPS resources | The robot must not require two VPSs. One VPS can host MT5 + MT4 simultaneously if CPU/RAM/latency are sufficient; execution quality must be measured. |

### Table 14 — SL/TP and position management
| Item | Specification |
|---|---|
| Momentum base TP | max(1.2 x spread, 0.18 x ATR) — initial value to optimise per symbol. |
| Momentum base SL | max(2 x spread, 0.35 x ATR) — initial value to optimise per symbol. |
| SL/TP guard-rail | SL/TP <= 2 as a historical configurable constraint; never manipulate this ratio only to inflate the win rate. |
| Break-even | Triggered initially at 70 % of the TP; configurable per strategy. |
| Trailing | Triggered initially at 85 % of the TP; short and configurable. |
| Momentum-loss exit | For Momentum: exit possible if the internal score/momentum < 60 AND persistent tick reversal of about 500 ms. |
| Time-stop | EURUSD 45 s, GBPUSD 40 s, XAUUSD 30 s for ultra-scalping; configurable per strategy. **[TN G.1: GBPUSD removed; BTCUSD gets its own value determined by tests — the 40 s are not copied.]** |
| Hard max | 120 s initially; configurable if FVG/Range need a different ceiling during tests. |
| Structuring rule | Each engine returns its Entry, SL, TP and invalidation reason; no universal fixed SL/TP for the three engines. |

### Table 15 — Modes
| Item | Specification |
|---|---|
| SPEED | Reactive base; initial cooldown/delay 1500 ms. |
| AGGRESSIVE | More permissive and faster without removing the safeties; initial delay 750 ms. |
| ULTRA | Maximum reactivity allowed by the broker/VPS; initial delay 300 ms. |
| Rule | A more aggressive mode must not require a higher score to the point of producing fewer trades. Thresholds are specific to each engine and optimisable. |

### Table 16 — PRIORITY REQUIREMENT
The design and optimisation objective is to aim for about 90 % winning trades or more, IF this level is
obtained in a robust and sustainable way on realistic tests. This figure is a research target, not a
promise of future results.

### Table 17 — Statistics per engine and symbol
Setups/day, trades/day, execution rate, win rate, profit factor, expectancy, max drawdown, average win/loss,
average duration, average slippage, signal rejection rate.

### Table 18 — Initial technical parameters
| Item | Specification |
|---|---|
| M5 trend | EMA20 / EMA50 |
| M1 short structure | EMA9 / EMA21 when relevant |
| Volatility | ATR(14) M1 + median ATR of the last 50 M1 candles |
| Directional strength | ADX(14), initial threshold 18 + DI, used per engine |
| Momentum | ROC(5) |
| Tick window | 50 ticks |
| Tick imbalance BUY | >= 62 % bullish ticks |
| Tick imbalance SELL | <= 38 % bullish ticks |
| Velocity | current 2-s window >= 1.25x the 30-s reference median |
| Acceleration | +20 % initial |
| Micro-range | 20 ticks |
| Breakout buffer | max(0.15 x spread, 0.02 x ATR) |
| Entry delay SPEED | 1500 ms |
| Entry delay AGGRESSIVE | 750 ms |
| Entry delay ULTRA | 300 ms |
| Max positions | 3 / symbol **[TN G.2: 3 per engine, 9 per symbol, adjustable]** |
| Equity pause | 10 % |
| Sleep after pause | 10 s |
| Hard time max | 120 s initial, configurable |
| Inputs / SET MT5 | MQL5 inputs + separate SET files EURUSD / GBPUSD / XAUUSD. **[TN G.1: BTCUSD]** |
| Inputs / SET MT4 | Equivalent MQL4 inputs + separate SET files EURUSD / GBPUSD / XAUUSD after the port is validated. **[TN G.1: BTCUSD]** |
| Magic Number MT5 | Configurable per instance/strategy/symbol. |
| Magic Number MT4 | Configurable per instance/strategy/symbol. |
| Instance ID | Configurable identifier to distinguish several installations on the same account or the same VPS. |

### Table 19 — Deliverables
| Item | Specification |
|---|---|
| Code | MT5: complete .MQ5 EA + compiled .EX5. MT4: complete .MQ4 EA + compiled .EX4. Both versions must be usable simultaneously or separately after delivery. |
| Configurations | Optimised .set files for EURUSD, GBPUSD and XAUUSD **[TN G.1: BTCUSD]**, separated by platform if necessary. |
| Documentation | Installation, parameters, description of the 3 engines, ON/OFF rules, logs, troubleshooting. |
| Tests | MT5: Strategy Tester reports per engine/symbol + combined + out-of-sample. MT4: equivalence/validation tests after the port, with documented differences. |
| Support | Bug fixes during the period agreed in the offer. |
| Licence | Perpetual right of use. No PC / account / broker / hardware / VPS lock, no expiry, no subscription, no periodic activation, no external licence server, no artificial limit on the number of installations. |
| Price | Fixed-price quote preferred. |
| Lead time | Realistic lead time announced after reading this specification. |
| Development order | 1) MT5 development/reference validation -> 2) MT4 port -> 3) equivalence tests -> 4) delivery of both platforms. This order concerns development only; after delivery MT4 and MT5 are free and independent. |
| Multi-environment use | Same PC, several PCs, one shared MT5+MT4 VPS or several VPSs; simultaneous or separate use. |
| Multi-instance protection | Configurable Magic Numbers / Strategy IDs / Instance IDs + protection against duplicates/conflicts on the same account. |

### Table 20 — FINAL INSTRUCTION TO THE DEVELOPER
This V1 architecture contains exactly 3 engines. MT5 is the technical development reference; MT4 is its
faithful port. After delivery, both versions must be able to run simultaneously or separately, on the same
PC, several PCs, one VPS or several VPSs, with no dependency between them. The right of use is perpetual,
with no expiry, subscription, periodic activation, external licence server or PC/account/broker/hardware/VPS
lock, and no artificial limit on the number of installations. Provide configurable Magic Numbers / Strategy
IDs / Instance IDs and a protection against duplicates if several instances share an account. Do not
re-introduce Pullback, Order Block or any other strategy without written validation. Do not simplify the
robot into a single global score. Any MT4 limitation or divergence must be explained and validated before
coding.

---

# LOCKED FINAL ADDENDUM — VALIDATED ADDITIONS AND CLARIFICATIONS

**Document status**
* This document is the final technical reference to be sent to the developer together with the V1
  reproduced in full above.
* The V1 text above remains fully valid and must not be deleted, replaced, simplified or silently
  reworded.
* This addendum only adds the decisions and clarifications validated after V1. It creates no fourth engine
  and replaces no V1 logic.
* In case of a supposed contradiction, ambiguity, technical difficulty or MT4/MT5 limitation, the developer
  must report it BEFORE changing the logic and obtain written validation.
* Any future improvement not present in this document must be proposed separately and may be integrated
  into the code only after the client's written validation.

## A. Clarification of the H1 filter OFF / SOFT / STRICT
**A.1 H1 states.** The H1 context must be classifiable as BULLISH / BEARISH / NEUTRAL from objective,
backtestable elements, notably EMA20/EMA50 + ADX/DI. The exact thresholds must be exposed as inputs,
configurable and optimisable. Initial reference definition:
* BULLISH: EMA20 H1 > EMA50 H1, +DI dominating -DI and ADX above the configured directional threshold.
* BEARISH: EMA20 H1 < EMA50 H1, -DI dominating +DI and ADX above the configured directional threshold.
* NEUTRAL: insufficient or contradictory directional conditions.
The thresholds stay configurable/optimisable and must not be fixed arbitrarily.

**A.2 OFF mode.** H1 is completely ignored for the entry decision. A valid engine setup cannot be blocked by
the H1 context when H1_FILTER = OFF.

**A.3 SOFT mode.** H1 serves only as context/confirmation and cannot on its own block an otherwise valid
setup of one of the 3 engines. SOFT must not automatically reduce the lot just because the H1 context is
opposite or neutral. The engine keeps its own entry, invalidation, risk and exit rules.

**A.4 STRICT mode.**
* Momentum / Micro-breakout: a clearly BULLISH H1 trend may block a new opposite SELL entry; a clearly
  BEARISH H1 trend may block a new opposite BUY entry.
* FVG: same principle; an FVG opposite to a clearly established H1 trend may be blocked in STRICT.
* Range / Mean Reversion: when a strong directional H1 trend is clearly established, STRICT may block NEW
  Range entries to avoid mean-reverting against a strong directional impulse. STRICT never turns the Range
  engine into a trend-following engine and never forces an entry in the trend direction.
* H1 NEUTRAL must not artificially create a direction.

**A.5 Common principle.** H1 remains a filter/context, never a fourth engine. BOS/CHoCH remain optional
confirmations/structures and never standalone strategies. No independent trend-following strategy is added.

## B. Eight additional mandatory protections
**B.1 News filter / economic calendar / NFP**
* NEWS_FILTER = ON/OFF.
* Cover relevant high-impact announcements, notably NFP, CPI, FOMC, rate decisions and other configurable announcements.
* Configurable window in minutes BEFORE and AFTER the announcement.
* During the blocked window: no NEW entry; positions already open keep being managed normally.
* Automatic resumption after the window when the other safety conditions are valid.
* Impact and currencies concerned configurable.
* MT5: the native economic calendar may be used if appropriate.
* MT4: provide a faithful equivalent compatible with MT4 limits.
* No hidden paid dependency or mandatory external subscription.

**B.2 Session filter / trading hours**
* SESSION_FILTER = ON/OFF.
* Configurable days and time ranges.
* Possible London / New York / Asia profiles or custom TradingStart / TradingEnd hours.
* Server time / UTC handling clearly documented.
* Outside the allowed ranges: no NEW entry; existing positions remain managed normally.

**B.3 Rollover / day-change protection**
* ROLLOVER_FILTER = ON/OFF.
* Configurable window before and after the rollover/day change.
* During this window: no NEW entry; existing positions remain managed.
* The spread filter stays active; no entry may be forced during an abnormal degradation of spread/liquidity.

**B.4 Consecutive-loss protection + cooldown**
* CONSECUTIVE_LOSS_PROTECTION = ON/OFF.
* Configurable number X of consecutive losses.
* Configurable cooldown of Y minutes.
* Configurable scope: engine / symbol / instance, according to the documented implementation.
* After the cooldown, a new entry requires a NEW valid setup; no blind re-entry.
* This protection is in addition to the equity drawdown >= 10 % rule and does not replace it.

**B.5 Risk management per trade**
* Configurable RISK_MODE: Fixed Lot / %Balance / %Equity.
* Configurable maximum risk per trade.
* Mandatory compliance with broker constraints: minimum lot, maximum lot, lot step, margin, stops/freeze levels.
* The risk calculation must use the REAL SL distance of the setup concerned.
* Configurable total exposure ceiling.
* Martingale remains optional/can be disabled as in V1 and, even when active, must respect the hard
  risk/exposure limits and require a new valid setup.

**B.6 Aggregate exposure / correlation between EURUSD, GBPUSD and XAUUSD** **[TN G.1: EURUSD, XAUUSD, BTCUSD]**
* Add a configurable control of the total open exposure across the 3 symbols.
* Take common exposure into account, notably USD exposure, without a simplistic rule or an arbitrary
  hard-coded correlation.
* Configurable total open-risk limit/guard.
* This protection must NOT impose a mandatory synchronisation between FRANCKY MT5 and FRANCKY MT4. The
  platform and instance independence planned in V1 remains valid.

**B.7 Recovery after restart / reconnection**
* After a terminal restart, VPS restart, broker reconnection or technical interruption, FRANCKY must rebuild
  the necessary state of the open positions/orders as far as technically possible.
* Correctly identify StrategyID / Magic Number / Instance ID.
* Avoid any duplicate entry caused only by a restart/reconnection.
* Resume management of existing positions according to their engine of origin.
* Recover/restore, where possible, the important states, notably cooldowns and active protections.
* MT4 differences or limits must be documented explicitly.

**B.8 Detailed handling of order errors and retries**
* Classify transient and permanent errors as far as possible: rejection, requote, off quotes, timeout and
  other relevant platform/broker codes.
* Configurable maximum number of retries.
* Configurable delay between retries.
* BEFORE each retry, mandatorily revalidate: signal still valid, spread, slippage/tolerance, current price,
  trading allowed, margin and relevant execution conditions.
* Never blindly retry an obsolete order or an invalid signal.
* Log the error code, reason, number of attempts and final result.

## C. Clarification of tests, backtests and validation
**C.1 Momentum and MT5 tick data.** For the Momentum / Micro-breakout engine, use the MT5 Strategy Tester
mode "Every tick based on real ticks" when sufficient, usable real tick data are available for the
period/broker tested. The report must document the tested period, the data quality/availability and any
known significant gaps. A historical backtest, even on real ticks, does not perfectly reproduce latency,
spread, slippage, rejections and live microstructure; the demo/forward validation planned in V1 therefore
remains mandatory before freezing the reference logic.

**C.2 Separate then combined validation.** Strictly keep the V1 validation order:
1) test Momentum alone on EURUSD, GBPUSD and XAUUSD **[TN G.1: BTCUSD]**;
2) test FVG alone on the same symbols;
3) test Range alone on the same symbols;
4) only then test the 3 engines combined with the Conflict Resolver and the common protections.
For each engine/symbol and for the final combination: provide the relevant statistics planned in V1.

**C.3 Robustness**
* Separate in-sample optimisation and out-of-sample validation.
* Run parameter sensitivity tests.
* Run tests with degraded execution: higher spread/slippage/costs and realistic conditions.
* Complete with an MT5 demo/forward test in conditions close to the target broker.
* After MT5 validation, port to MT4 and run equivalence tests, documenting the MT4-specific
  data/tick/tester/execution limits.

**C.4 Transparency of results / 90 % target.** The ~90 % target remains a RESEARCH TARGET and never a
guarantee of profitability or of a future win rate. Do not over-optimise, manipulate TP/SL, dangerously
increase the risk or use a dangerous martingale to force this figure. The report must not present only an
isolated "best result" without context. It must allow the robustness to be assessed by showing the agreed
validation results: separate engines/symbols, final combination, out-of-sample, sensitivity and degraded
execution conditions where applicable. If 90 % is not robust/sustainable, clearly state the best robust
result obtained and its test conditions, in accordance with V1.

## D. Clarification of the HFT-style / retail ultra-scalping already agreed
**D.1 HFT nature of the project.** FRANCKY remains a RETAIL HFT-style / ultra-scalping robot on MT5/MT4, not
institutional co-located HFT. The HFT-style character is an architectural requirement: tick-by-tick
processing, event-driven OnTick logic, microstructure exploitation, tick speed and acceleration,
micro-breakouts, minimal internal decision time, measured low-latency execution and a frequent search for
valid opportunities. SPEED / AGGRESSIVE / ULTRA are settings and reactivity profiles; they do not replace
the HFT-style architecture and are not, on their own, what makes the robot HFT-style. This section makes the
already agreed architecture explicit; it adds no engine, no standalone signal and no new strategy.

**D.2 Data and architecture already planned.** The Market Data Layer and the engines concerned keep the
already planned use of ticks, Bid/Ask, spread, tick speed/acceleration, micro-ranges/micro-breakouts, as well
as M1/M5/H1 data, ATR, EMA, ADX/DI and ROC according to each engine's own rules. The main flow remains the
V1 flow: OnTick -> market update -> run the 3 active engines -> collect signals -> resolve conflicts ->
safety checks -> execution -> position management -> logging. No mandatory multi-engine confirmation is added.

**D.3 Latency and reactivity.** The latency target remains <= 10 ms IF the broker/VPS/connection/platform
allow it; it must be measured rather than assumed. Minimal internal decision time concerns the reactivity
of the software processing and does NOT remove the strategic delays/cooldowns already validated. The initial
delays remain exactly: SPEED 1500 ms, AGGRESSIVE 750 ms, ULTRA 300 ms, configurable as planned in V1.

**D.4 Momentum / Micro-breakout.** The Momentum engine remains the engine most directly tied to tick
microstructure. Its initial V1 parameters remain unchanged: 50-tick window; BUY >= 62 % bullish ticks;
SELL <= 38 %; current 2-s velocity >= 1.25x the 30-s median; initial acceleration +20 %; 20-tick micro-range;
breakout buffer max(0.15 x spread, 0.02 x ATR); internal confirmations ROC(5), ATR(14), ADX/DI and EMA
M1/M5. The V1 TP/SL, break-even, trailing, momentum-loss exit and time-stops remain unchanged and
configurable as planned.

## E. Additional acceptance criteria
- [ ] H1 OFF/SOFT/STRICT follows exactly the addendum definitions and adds no trend-following engine.
- [ ] In SOFT, H1 alone does not block an otherwise valid setup and does not automatically reduce the lot only because of the H1 context.
- [ ] In STRICT, the Momentum/FVG/Range behaviour matches the rules above and H1 NEUTRAL forces no direction.
- [ ] The news filter is configurable ON/OFF, blocks only new entries during the configured window, manages existing positions and resumes automatically after the window.
- [ ] The session filter is configurable ON/OFF, respects the documented days/ranges and server/UTC handling, without abandoning the management of existing positions.
- [ ] The rollover protection is configurable ON/OFF with before/after windows and keeps managing existing positions and controlling the spread.
- [ ] The consecutive-loss/cooldown protection is configurable, requires a new setup after the cooldown and does not replace the equity DD >= 10 % pause.
- [ ] The Fixed Lot / %Balance / %Equity risk modes work, use the real SL distance and respect the broker constraints and exposure limits.
- [ ] The aggregate exposure/correlation protection controls the global EURUSD/GBPUSD/XAUUSD **[TN G.1: BTCUSD]** risk without imposing a mandatory MT4/MT5 synchronisation.
- [ ] After restart/reconnection the robot correctly finds the relevant positions/orders, StrategyID/Magic/Instance, avoids duplicates and resumes management as far as technically possible.
- [ ] Error/retry handling revalidates the signal and the execution conditions before each new attempt, limits the retries and logs the result.
- [ ] MT5 Momentum is tested in "Every tick based on real ticks" when enough data are available, with the period/data quality documented.
- [ ] The reports allow checking separate engines/symbols, the final combination, in-sample/out-of-sample, sensitivity and degraded execution according to the protocol.
- [ ] No artificial 90 % guarantee is imposed; robustness, expectancy, PF, drawdown and test conditions remain visible.
- [ ] The HFT-style architecture is truly tick-by-tick / event-driven OnTick with microstructure, tick velocity/acceleration and micro-breakouts for the engines that use them; SPEED/AGGRESSIVE/ULTRA remain profiles.
- [ ] The <= 10 ms latency target is measured and conditional on the environment; it is not turned into an impossible promise.
- [ ] The SPEED 1500 ms / AGGRESSIVE 750 ms / ULTRA 300 ms delays remain present and are not removed by the HFT clarification.
- [ ] MT5 remains the validation reference before the faithful MT4 port; any technically imposed MT4 divergence is documented and validated before a logic change.
- [ ] Both final versions are delivered: MT5 MQ5 + EX5 + SET and MT4 MQ4 + EX4 + SET, with complete sources, documentation and the agreed reports.
- [ ] The perpetual right of use, the absence of expiry/subscription/periodic activation/licence server/PC-account-broker-hardware-VPS lock and the absence of an artificial installation limit are respected.
- [ ] MT4 and MT5 remain independent after delivery and can run simultaneously or separately, including on the same PC or the same sufficiently sized VPS.
- [ ] Exactly 3 engines only: Momentum / Micro-breakout, FVG, Range / Mean Reversion. Pullback and Order Block stay excluded; trend following is not added; BOS/CHoCH remain optional confirmations/structures.
- [ ] The V1 rule "no automatic definitive daily stop" remains intact; no protection of this addendum silently replaces it.

## F. Final scope lock
1. EXACTLY 3 independent engines: Momentum / Micro-breakout, FVG, Range / Mean Reversion.
2. HFT-style / retail ultra-scalping remains a fundamental and measurable requirement; it is not institutional HFT.
3. H1 remains only OFF / SOFT / STRICT according to the definitions of section A.
4. The 8 protections B.1 to B.8 are mandatory and are added to the V1 protections without removing any.
5. Test protocol C completes V1: MT5 real ticks when available, separate then combined engine/symbol, in-sample/out-of-sample, sensitivity, degraded execution, demo/forward, then MT4 equivalence.
6. The V1 parameters for Momentum/FVG/Range, risk, drawdown, martingale, hedging, positions, logs, Magic/Strategy/Instance IDs, SL/TP, BE, trailing and time-stops remain valid.
7. MT5 is the technical development/validation reference; MT4 is the faithful port. After delivery both are independent and free to use.
8. Perpetual use, multi-PC/VPS/accounts/brokers/instances according to V1; no hidden lock or licence server.
9. No new strategy, protection, limitation, filter or behaviour change may be added without the client's written validation.
10. If a requirement seems technically impossible or contradictory, the developer must report it and propose a solution; never delete or change it silently.

**END - FINAL LOCKED TECHNICAL REFERENCE FOR DEVELOPMENT**

---

# G. PRIORITY FINAL UPDATE — 05/10/2026

**Priority rule.** This section G completes the already validated final specification. It removes no
previous requirement, except where an earlier wording is explicitly replaced below. In case of a
contradiction on any of points G.1 to G.5, this section G takes precedence. All other requirements of the
previous specification remain fully applicable: HFT-style / retail ultra-scalping architecture, separate and
independent MT5 and MT4 versions, trading engines, H1 context OFF/SOFT/STRICT, protections, tests,
deliverables, source code, perpetual use, multi-PC/VPS/accounts/brokers/instances, no lock, and every other
validated requirement not explicitly changed by this section.

**G.1 Final markets — GBPUSD replaced by BTCUSD.** The three supported markets become EURUSD, XAUUSD and
BTCUSD. GBPUSD is removed from the final scope and replaced by BTCUSD. Every earlier reference to EURUSD /
GBPUSD / XAUUSD concerning the market scope, SET files, per-symbol tests, per-symbol statistics, validation
and exposure/correlation must now be read as EURUSD / XAUUSD / BTCUSD. BTCUSD must receive its own settings,
tests and per-symbol optimisation. The values previously planned for GBPUSD, notably its initial time-stop,
must not be copied automatically to BTCUSD: the BTCUSD values must be determined and optimised by tests.
BTCUSD must be usable independently, notably at weekends when the broker and the BTCUSD symbol concerned
actually allow trading. Day/session filters must stay configurable to allow this use.

**G.2 Simultaneous positions — up to 3 per engine / 9 per symbol — manually adjustable.** The 3 main engines
are Momentum / Micro-breakout, FVG and Range / Mean Reversion. When enabled, the three engines work
independently and in parallel on the selected symbol. No engine may wait for another to finish before
analysing the market or exploiting its own valid opportunity. Each engine may take several positions when
ITS OWN CONDITIONS ARE ALIGNED and when the common protections allow entries. The final limit is up to 3
simultaneous positions per engine, i.e. potentially up to 9 simultaneous positions in total on one symbol.
THIS MAXIMUM IS MANUALLY ADJUSTABLE BY THE CLIENT. This rule replaces the former initial limit of 3 positions
maximum per symbol. The maximum allowed is never an obligation to open 9 positions. No trade may be created
only to reach 3 or 9 positions. The Conflict Resolver, duplicate control, hedging, Risk & Safety Gate, risk
per trade and exposure limits still apply. The engines must not create unwanted overlaps, duplicates or
conflicts between strategies.

**G.3 One instance = only the chart symbol.** A FRANCKY instance must trade only the symbol of the chart it is
attached to. FRANCKY on EURUSD = EURUSD only. FRANCKY on XAUUSD = XAUUSD only. FRANCKY on BTCUSD = BTCUSD only.
An instance must never spontaneously start trading the two other supported assets. If the client wants to
trade several assets simultaneously, they will deliberately launch several FRANCKY instances on the
corresponding charts. The multi-instance protections, Magic Numbers, Strategy IDs and Instance IDs already
required remain applicable to isolate the orders correctly. This requirement must be respected in FRANCKY
MT5 and FRANCKY MT4.

**G.4 10 % protection — final requested behaviour.** When the capital is hit by 10 %, FRANCKY must:
1. STOP;
2. RE-ACTIVATE ITS SAFETIES;
3. VERIFY THEM;
4. then RESTART AUTOMATICALLY A FEW SECONDS LATER.

This is the requested behaviour for this protection. This wording takes precedence over any earlier
contradictory wording about the pause/resume behaviour at the 10 % threshold. No other behaviour may be
substituted for this sequence without the client's written validation. This requirement must be respected in
FRANCKY MT5 and FRANCKY MT4.

**G.5 Final rule on additional strategies.** FRANCKY must first be developed, tested and optimised with its
3 main strategies: Momentum / Micro-breakout, FVG and Range / Mean Reversion. If these 3 strategies are enough
to reach the desired level of activity, aggressiveness, opportunities and operation, they will be kept alone
and no additional strategy will be added. If, however, the tests or use show that these 3 strategies are not
enough to reach the desired operation, adding one or more strategies may then be considered. In that case the
first strategies to consider will be Pullback and/or Order Block, as already recommended by the developer.
No additional strategy may be integrated automatically. Pullback, Order Block or any other additional
strategy must first be proposed/identified and validated by the client before being integrated. Adding a
strategy must never silently remove or replace the 3 main engines already validated.

**G.6 Final acceptance criteria added**
- [ ] Final markets: EURUSD, XAUUSD and BTCUSD; GBPUSD removed.
- [ ] SET files, tests, statistics and validations adapted to the three final markets.
- [ ] BTCUSD has its own settings and values determined/optimised by tests.
- [ ] The 3 engines work independently and in parallel on the selected symbol.
- [ ] Up to 3 simultaneous positions per engine, i.e. up to 9 in total on one symbol, with the maximum manually adjustable by the client.
- [ ] No trade is forced to fill the limit; risks, exposure, conflicts and duplicates remain controlled.
- [ ] An instance trades only the symbol of the chart it is attached to.
- [ ] Several simultaneous symbols require several instances deliberately launched by the client.
- [ ] At the 10 % threshold: STOP -> RE-ACTIVATION OF THE SAFETIES -> VERIFICATION -> AUTOMATIC RESTART A FEW SECONDS LATER.
- [ ] G.1 to G.4 must be implemented in the MT5 and MT4 versions.
- [ ] The 3 main strategies are developed, tested and optimised first.
- [ ] If they are enough for the desired operation, no additional strategy is added.
- [ ] If they are not enough, Pullback and/or Order Block are the first additional strategies to consider, without automatic integration and after client validation.
- [ ] All other requirements of the previous specification remain applicable when they are not explicitly replaced by this section G.

**END — CORRECTED FINAL FRANCKY TRI-FLUX SPECIFICATION — SINGLE REFERENCE FOR UMAIR AFTER ACCEPTANCE OF POINTS G.3 AND G.4**

---

# H. Clarification agreed after Section G (client <-> developer messages, 06-07/10/2026)

*Not part of the client's document; recorded here so the implementation is traceable.*

1. **G.3 confirmed:** one instance trades only the chart symbol, on MT5 and MT4. Several symbols = several
   instances, isolated by Magic Number / Instance ID.
2. **G.4 final interpretation (client message):** the 10 % protection is a **very short trading pause of a few
   seconds** during which FRANCKY stays fully active, checks its safeties and technical environment and keeps
   managing the open positions; **after those seconds it resumes normal operation automatically, without
   waiting indefinitely for any additional condition.** The client explicitly does NOT want "restart once the
   safeties clear" if that can hold FRANCKY for an indefinite time.
3. **Developer confirmation:** implemented as a strict time-based cooldown (default 10 s, configurable). New
   entry signals are ignored during the pause; trailing stops, break-even, time-stops and exits of open
   positions keep working; when the timer expires FRANCKY resumes scanning for setups immediately. Safety
   checks run during the pause are recorded in the log; they never extend the pause.
4. **Engines:** V1 = Momentum, FVG, Range; Pullback / Order Block only as a possible "Version 2" after tests and
   written validation (G.5).
