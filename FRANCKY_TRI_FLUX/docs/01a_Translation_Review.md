# 01a - Review of the English translation (`FRANCKY_TRI_FLUX_Final_Reference_English_Translation.docx`)

Compared line by line with the French reference `FRANCKY_TRI-FLUX_CAHIER_FINAL_CORRIGE_UMAIR_05-10-2026.txt`.
The corrected full translation is `docs/01_Specification_EN_Corrected.md` (also exported as
`docs/FRANCKY_TRI_FLUX_Specification_EN_Corrected.docx`).

## A. Critical omissions (content missing from the English .docx)

| # | Missing in the English .docx | Impact |
|---|---|---|
| 1 | **All 17 specification tables 4-20** (the .docx contains no tables at all): objectives (T4), software modules (T5), recommended flow (T6), element classification (T7), frequency principle (T8), **Momentum engine rules (T9)**, **FVG rules (T10)**, **Range rules (T11)**, **conflicts/hedging/magic/instance (T12)**, **common filters & execution (T13)**, **SL/TP, BE 70 %, trailing 85 %, momentum-loss exit, time-stops (T14)**, **modes 1500/750/300 ms (T15)**, 90 % priority (T16), statistics list (T17), **initial technical parameters (T18)**, deliverables (T19), final instruction (T20). | Sections 2, 3, 4.1-4.3, 6, 7, 8, 9, 16 of the English version are empty headings. A developer reading only the English text would not know the engine rules, the SL/TP formulas or the mode delays. |
| 2 | Section 17 "Mandatory questions before ordering" - the 7 questions are missing. | Minor (pre-order questions), but part of the reference. |
| 3 | Section 12 - the 20 logging fields were merged into one line ("StrategyID / StrategyName: Symbol / Mode ..."), which reads as if StrategyName were a heading for the others. | Ambiguity; corrected to a numbered list of 20 fields. |

## B. Silent changes to the V1 text (the reference itself forbids silent rewording of V1)

| # | English .docx | French original | Correction |
|---|---|---|---|
| 4 | Title "EURUSD: BTCUSD / XAUUSD" | "EURUSD / GBPUSD / XAUUSD" | Typo (colon) and silent replacement. Kept the original wording + translator's note "[TN G.1: EURUSD / XAUUSD / BTCUSD]". |
| 5 | Executive summary: "Initial maximum: Up to 9 positions per symbol (3 per engine), adjustable." | "Maximum initial : 3 positions par symbole, parametrable." | The V1 sentence was silently rewritten with the G.2 rule. Restored the V1 wording + note that G.2 replaces it. |
| 6 | Sections 13, 14, B.6, C.2, E use BTCUSD instead of GBPUSD | GBPUSD | Same issue: correct per G.1 but should be marked as an annotation, not as original V1 text. All occurrences now carry "[TN G.1]". |

## C. Points that need a translator's note because a later section overrides them

| # | Text | Note added |
|---|---|---|
| 7 | Section 10 "After the pause, automatically resume analysis if safety conditions have returned to normal." | Superseded by G.4 and by the client clarification of 07/10/2026: strict timer, never waits for conditions. |
| 8 | Table 12 / Table 18 "Max positions 3 / symbol" | Superseded by G.2 (3 per engine, 9 per symbol). |
| 9 | Table 14 time-stop "GBPUSD 40 s" | G.1: not copied to BTCUSD; BTCUSD value determined by tests. |
| 10 | Question 17.5 "max 3 positions/symbol" | Superseded by G.2. |

## D. Wording / formatting

| # | Issue | Correction |
|---|---|---|
| 11 | Section G paragraphs are broken mid-sentence (hard line breaks copied from the .txt) and the G.6 checklist items are run together in one paragraph. | Reflowed paragraphs; one checklist item per line. |
| 12 | "Sleep initial" rendered as "Initial sleep = 10 seconds" - correct; kept. | - |
| 13 | "paramétrable" sometimes rendered "adjustable", sometimes "configurable" - both acceptable; the corrected version uses "configurable" for parameters and "adjustable" where the client wrote "réglable manuellement". | Consistency only. |
| 14 | B.4 "Portée configurable : moteur / symbole / instance selon implémentation documentée" rendered "Configurable scope: engine / symbol / instance according to documented implementation" - correct. Implementation note: because one instance = one symbol (G.3), "symbol" and "instance" scope are the same; the EA offers ENGINE or INSTANCE. | Documented in the user manual. |

## E. Content added for traceability (not in the client document)

* Section H records the clarification exchanged after Section G (G.3 confirmation and the final G.4
  interpretation: a strict few-seconds pause, then automatic restart).
