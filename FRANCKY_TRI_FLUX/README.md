# FRANCKY TRI-FLUX — HFT-style retail ultra-scalping EA (MT5 + MT4)

Three independent engines — **Momentum / Micro-breakout**, **FVG**, **Range / Mean Reversion** — running tick by
tick on **EURUSD, XAUUSD, BTCUSD** (one instance per chart symbol), with a full Risk & Safety Gate, the 10 %
equity pause with automatic restart, news/session/rollover filters, consecutive-loss cooldown, aggregate USD
exposure control, restart recovery, smart order retries, CSV journals and an on-chart dashboard.

MT5 (`MQL5/`) is the reference implementation; MT4 (`MQL4/`) is a faithful port built from the **same Core
source files** — only the platform layer differs.

## Start here
| You are... | Read |
|---|---|
| End user / trader | [`docs/04_User_Manual.md`](docs/04_User_Manual.md), then [`docs/05_Input_Parameters_Reference.md`](docs/05_Input_Parameters_Reference.md) |
| Tester / optimizer | [`docs/07_Testing_and_Optimization_Protocol.md`](docs/07_Testing_and_Optimization_Protocol.md), [`docs/06_Logs_and_Diagnostics.md`](docs/06_Logs_and_Diagnostics.md) |
| Developer / AI agent | [`docs/09_SSOT_Developer_Contract.md`](docs/09_SSOT_Developer_Contract.md), [`docs/10_Agent_Implementation_Brief.md`](docs/10_Agent_Implementation_Brief.md), [`docs/02_Architecture_and_Workflow.md`](docs/02_Architecture_and_Workflow.md), [`docs/03_Strategy_Logic.md`](docs/03_Strategy_Logic.md) |
| Project owner | [`docs/01_Specification_EN_Corrected.md`](docs/01_Specification_EN_Corrected.md), [`docs/01a_Translation_Review.md`](docs/01a_Translation_Review.md), [`docs/11_Requirements_Traceability.md`](docs/11_Requirements_Traceability.md), [`docs/12_Design_Decisions_and_Open_Questions.md`](docs/12_Design_Decisions_and_Open_Questions.md), [`docs/08_MT4_Divergences.md`](docs/08_MT4_Divergences.md) |

## Layout
```
MQL5/Experts/FranckyTriFlux/FranckyTriFlux.mq5      MT5 EA (event forwarding only)
MQL5/Include/FranckyTriFlux/Core/*.mqh              shared Core (identical in MQL4/)
MQL5/Include/FranckyTriFlux/Platform/Platform.mqh   MT5 platform layer (CTrade, CopyTicks, calendar)
MQL5/Include/FranckyTriFlux/Inputs.mqh              generated inputs (input groups)
MQL5/Scripts/FranckyTriFlux/FranckyNewsExporter.mq5 calendar -> news.csv for MT4 and the testers
MQL5/Presets/FranckyTriFlux/*.set                   EURUSD / XAUUSD / BTCUSD presets (generated)
MQL4/...                                            same for MT4 (OrderSend, iATR, ...)
Tester/MT5, Tester/MT4                              tester .ini + .set per engine/symbol/stage (generated)
tools/ftf_spec.py                                   single source of truth for all inputs
tools/generate.py                                   regenerates inputs, config, presets, ini, docs/05
tools/check_core.py                                 Core identity MT5/MT4 + portability static checks
tools/analyze_logs.py                               per engine/symbol report from the CSV journals
docs/                                               all documentation
```

## Build
1. Copy `MQL5/` into the MT5 data folder and `MQL4/` into the MT4 data folder.
2. Compile `FranckyTriFlux.mq5` in MetaEditor 5 and `FranckyTriFlux.mq4` in MetaEditor 4 (F7).
3. After any change to inputs: edit `tools/ftf_spec.py`, run `python3 tools/generate.py`.
4. After any Core change (edit the MQL5 copy): `python3 tools/check_core.py --sync`.

No DLL, no licence server, no expiry, no account/PC lock — perpetual, unlimited installations.
