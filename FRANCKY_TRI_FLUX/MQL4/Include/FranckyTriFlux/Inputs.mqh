//+------------------------------------------------------------------+
//| FRANCKY TRI-FLUX HFT-style Ultra Scalping                          |
//| GENERATED FILE - DO NOT EDIT BY HAND.                              |
//| Source of truth: tools/ftf_spec.py  ->  python3 tools/generate.py |
//+------------------------------------------------------------------+

#ifndef FTF_INPUTS_MQH
#define FTF_INPUTS_MQH

#include <FranckyTriFlux\Core\InputEnums.mqh>

// MQL4 has no 'input group': groups are shown as read-only separator lines.


sinput string InpSep_GEN = "==== 01. GENERAL / INSTANCE ===="; // ==== 01. GENERAL / INSTANCE ====
input bool InpEnableTrading = true; // Enable new entries (master switch)
input ENUM_FTF_MODE InpTradingMode = FTF_MODE_AGGRESSIVE; // Trading mode (SPEED / AGGRESSIVE / ULTRA)
input int InpInstanceId = 1; // Instance ID (1-999, unique per chart on one account)
input int InpMagicBase = 4100000; // Magic number base (magic = base + ID x 10 + engine)
input string InpCommentPrefix = "FTF"; // Order comment prefix
input ENUM_FTF_SYMBOL_CHECK InpSymbolCheck = FTF_SYMCHK_WARN; // Supported-symbol check (EURUSD/XAUUSD/BTCUSD)
input int InpTimerMs = 250; // Internal timer period (ms)

sinput string InpSep_ENG = "==== 02. STRATEGY ENGINES ON/OFF ===="; // ==== 02. STRATEGY ENGINES ON/OFF ====
input bool InpMomEnabled = true; // Engine A - Momentum / Micro-breakout ON
input bool InpFvgEnabled = true; // Engine B - FVG (Fair Value Gap) ON
input bool InpRngEnabled = true; // Engine C - Range / Mean Reversion ON

sinput string InpSep_MODE = "==== 03. MODES - DELAYS AND SPREAD LIMITS ===="; // ==== 03. MODES - DELAYS AND SPREAD LIMITS ====
input int InpDelaySpeedMs = 1500; // SPEED mode entry delay (ms)
input int InpDelayAggressiveMs = 750; // AGGRESSIVE mode entry delay (ms)
input int InpDelayUltraMs = 300; // ULTRA mode entry delay (ms)
input ENUM_FTF_DELAY_USAGE InpDelayUsage = FTF_DELAY_COOLDOWN; // How the mode delay is applied
input int InpMaxSpreadPtsSpeed = 0; // Max spread SPEED (points, 0 = auto)
input int InpMaxSpreadPtsAggressive = 0; // Max spread AGGRESSIVE (points, 0 = auto)
input int InpMaxSpreadPtsUltra = 0; // Max spread ULTRA (points, 0 = auto)
input double InpAutoMaxSpreadAtr = 0.3; // Auto max spread (x ATR M1) when limit = 0

sinput string InpSep_MD = "==== 04. MARKET DATA / VOLATILITY ===="; // ==== 04. MARKET DATA / VOLATILITY ====
input int InpAtrPeriod = 14; // ATR period (M1 / M5)
input int InpAtrMedianBars = 50; // ATR median length (M1 bars)
input int InpTickHistorySec = 120; // Tick history kept in memory (s)
input int InpMaxTickAgeSec = 60; // Max tick age before market considered stale (s)
input double InpVolAnomalyAtrMult = 3.0; // Volatility anomaly: ATR > x median ATR
input double InpVolAnomalyVelMult = 6.0; // Volatility anomaly: tick velocity > x median
input double InpVolAnomalySpreadMult = 3.0; // Volatility anomaly: spread > x median spread

sinput string InpSep_H1 = "==== 05. H1 CONTEXT FILTER (OFF / SOFT / STRICT) ===="; // ==== 05. H1 CONTEXT FILTER (OFF / SOFT / STRICT) ====
input ENUM_FTF_H1_FILTER InpH1Filter = FTF_H1_SOFT; // H1_FILTER mode
input int InpH1EmaFast = 20; // H1 fast EMA period
input int InpH1EmaSlow = 50; // H1 slow EMA period
input int InpH1AdxPeriod = 14; // H1 ADX period
input double InpH1AdxThreshold = 18.0; // H1 ADX directional threshold
input double InpH1DiMinGap = 0.0; // H1 min +DI/-DI gap
input double InpH1StrongAdx = 25.0; // H1 'strong trend' ADX (Range STRICT)
input bool InpH1StrictMomentum = true; // STRICT applies to Momentum
input bool InpH1StrictFvg = true; // STRICT applies to FVG
input bool InpH1StrictRange = true; // STRICT applies to Range

sinput string InpSep_MOM = "==== 06. ENGINE A - MOMENTUM / MICRO-BREAKOUT ===="; // ==== 06. ENGINE A - MOMENTUM / MICRO-BREAKOUT ====
input int InpMomTickWindow = 50; // Tick window for imbalance (ticks)
input double InpMomBuyRatio = 0.62; // BUY: min bullish tick ratio
input bool InpMomSymmetric = true; // SELL ratio = 1 - BUY ratio (symmetric)
input double InpMomSellRatio = 0.38; // SELL: max bullish tick ratio
input bool InpMomCountFlatTicks = false; // Count unchanged ticks in the ratio
input ENUM_FTF_VEL_METRIC InpMomVelMetric = FTF_VEL_TICKS; // Velocity metric
input int InpMomVelWindowMs = 2000; // Velocity window (ms)
input int InpMomVelRefMs = 30000; // Velocity reference window for median (ms)
input double InpMomVelRatio = 1.25; // Min velocity / median velocity
input double InpMomAccelMin = 0.2; // Min acceleration (0.20 = +20%)
input int InpMomMicroRangeTicks = 20; // Micro-range length (ticks)
input double InpMomBufSpreadMult = 0.15; // Breakout buffer (x spread)
input double InpMomBufAtrMult = 0.02; // Breakout buffer (x ATR M1)
input bool InpMomUseRoc = true; // Confirm with ROC direction
input int InpMomRocPeriod = 5; // ROC period (M1 bars)
input double InpMomRocMin = 0.0; // Min |ROC| (%)
input bool InpMomUseEma = false; // Confirm with M1 EMA fast/slow
input int InpMomEmaFast = 9; // M1 fast EMA period
input int InpMomEmaSlow = 21; // M1 slow EMA period
input bool InpMomUseAdx = false; // Confirm with M1 ADX/DI
input double InpMomAdxMin = 18.0; // M1 ADX min
input ENUM_FTF_CTX_USE InpMomM5Context = FTF_CTX_SOFT; // M5 EMA20/50 context
input double InpMomTpSpreadMult = 1.2; // TP = max(x spread, ...)
input double InpMomTpAtrMult = 0.18; // TP = max(..., x ATR M1)
input double InpMomSlSpreadMult = 2.0; // SL = max(x spread, ...)
input double InpMomSlAtrMult = 0.35; // SL = max(..., x ATR M1)
input int InpMomSignalTtlMs = 500; // Signal validity (ms)
input bool InpMomExitEnabled = true; // Momentum-loss exit ON
input double InpMomExitScore = 60.0; // Exit when momentum score below
input int InpMomExitInversionMs = 500; // Tick inversion persistence (ms)
input int InpMomExitTicks = 10; // Inversion window (ticks)
input int InpMomTimeStopSec = 45; // Time-stop (s, 0 = off)
input int InpMomMaxPositions = 3; // Max simultaneous positions (Momentum)
input double InpMomBeTriggerPct = 70.0; // Break-even trigger (% of TP distance)
input double InpMomBeLockPct = 5.0; // Break-even lock (% of TP distance)
input double InpMomTrailTriggerPct = 85.0; // Trailing trigger (% of TP distance)
input double InpMomTrailDistPct = 25.0; // Trailing distance (% of TP distance)
input double InpMomTrailStepPct = 5.0; // Trailing min step (% of TP distance)

sinput string InpSep_FVG = "==== 07. ENGINE B - FVG (FAIR VALUE GAP) ===="; // ==== 07. ENGINE B - FVG (FAIR VALUE GAP) ====
input ENUM_TIMEFRAMES InpFvgTimeframe = PERIOD_M5; // FVG timeframe
input bool InpFvgUseM1Refine = false; // Use M1 for entry precision
input int InpFvgScanBars = 60; // Bars scanned for FVGs
input int InpFvgMaxZones = 20; // Max zones kept
input double InpFvgMinGapAtr = 0.25; // Min gap size (x ATR of FVG timeframe)
input double InpFvgMinGapSpreadMult = 2.0; // Min gap size (x spread)
input int InpFvgMaxAgeBars = 48; // Max zone age (bars)
input int InpFvgMaxMitigations = 2; // Max mitigations (returns into zone)
input double InpFvgMaxDistanceAtr = 1.5; // Max price distance to zone (x ATR)
input ENUM_FTF_FVG_ENTRY InpFvgEntryMode = FTF_FVG_TOUCH; // Entry mode (TOUCH / CE 50% / REJECTION)
input double InpFvgRejectWickPct = 30.0; // REJECTION: min wick (% of candle range)
input bool InpFvgBosRequired = false; // BOS_REQUIRED (structure confirmation)
input ENUM_FTF_STRUCT_MODE InpFvgStructMode = FTF_STRUCT_BOS; // Structure event accepted when required
input int InpStructSwingBars = 3; // Swing strength (bars each side)
input int InpStructLookbackBars = 120; // Structure lookback (bars)
input double InpFvgInvalidBufAtr = 0.1; // Invalidation buffer (x ATR)
input bool InpFvgInvalidOnClose = true; // Invalidate on candle close (else on tick)
input ENUM_FTF_FVG_SL InpFvgSlMode = FTF_FVGSL_ZONE; // SL anchor
input double InpFvgSlBufSpreadMult = 1.0; // SL buffer (x spread)
input double InpFvgSlBufAtr = 0.1; // SL buffer (x ATR)
input ENUM_FTF_TP_MODE InpFvgTpMode = FTF_TP_LIQUIDITY; // TP mode
input double InpFvgTpAtrMult = 1.0; // TP ATR multiple
input double InpFvgTpRR = 1.0; // TP R multiple
input double InpFvgTpMinRR = 0.5; // TP min R (liquidity mode)
input double InpFvgTpMaxRR = 2.0; // TP max R (liquidity mode)
input int InpFvgMaxTradesPerZone = 1; // Max trades per zone
input int InpFvgSignalTtlMs = 1000; // Signal validity (ms)
input bool InpFvgExitOnInvalidation = true; // Exit open trade if zone invalidated
input int InpFvgTimeStopSec = 120; // Time-stop (s, 0 = off)
input int InpFvgMaxPositions = 3; // Max simultaneous positions (FVG)
input double InpFvgBeTriggerPct = 70.0; // Break-even trigger (% of TP distance)
input double InpFvgBeLockPct = 5.0; // Break-even lock (% of TP distance)
input double InpFvgTrailTriggerPct = 85.0; // Trailing trigger (% of TP distance)
input double InpFvgTrailDistPct = 25.0; // Trailing distance (% of TP distance)
input double InpFvgTrailStepPct = 5.0; // Trailing min step (% of TP distance)

sinput string InpSep_RNG = "==== 08. ENGINE C - RANGE / MEAN REVERSION ===="; // ==== 08. ENGINE C - RANGE / MEAN REVERSION ====
input ENUM_TIMEFRAMES InpRngTimeframe = PERIOD_M1; // Range timeframe (M1 or M5)
input int InpRngLookbackBars = 30; // Range lookback (bars)
input int InpRngAdxPeriod = 14; // ADX period
input double InpRngAdxMax = 20.0; // Max ADX for a range
input bool InpRngRequireAdxFalling = false; // Require falling ADX
input int InpRngAdxSlopeBars = 3; // ADX slope bars
input int InpRngEmaFast = 20; // Fast EMA period
input int InpRngEmaSlow = 50; // Slow EMA period
input double InpRngEmaSepMaxAtr = 0.3; // Max |EMA20-EMA50| (x ATR)
input double InpRngMinWidthAtr = 1.0; // Min range width (x ATR)
input double InpRngMinWidthSpreadMult = 4.0; // Min range width (x spread)
input double InpRngMaxWidthAtr = 6.0; // Max range width (x ATR)
input double InpRngMaxDriftPct = 50.0; // Max net drift (% of width)
input int InpRngMinTouchesPerSide = 1; // Min touches per boundary
input double InpRngEdgeZonePct = 20.0; // Entry zone near boundary (% of width)
input ENUM_FTF_RANGE_CONFIRM InpRngConfirmMode = FTF_RCONF_EITHER; // Edge confirmation (slowdown / rejection)
input double InpRngRejectWickPct = 40.0; // Rejection: min wick (% of candle range)
input int InpRngTickWindow = 20; // Tick window for buyer/seller return (ticks)
input double InpRngTickRatioMin = 0.55; // Min returning tick ratio
input double InpRngMaxVelRatio = 2.0; // Max tick velocity ratio (impulse protection)
input double InpRngMaxAtrExpansion = 1.6; // Max ATR / median ATR
input double InpRngSlBufSpreadMult = 1.5; // SL buffer beyond boundary (x spread)
input double InpRngSlBufAtr = 0.15; // SL buffer beyond boundary (x ATR)
input ENUM_FTF_RANGE_TP InpRngTpTarget = FTF_RTP_MID; // TP target
input double InpRngTpOffsetPct = 5.0; // TP offset before target (% of width)
input double InpRngBreakBufAtr = 0.15; // Breakout confirmation buffer (x ATR)
input bool InpRngExitOnBreakout = true; // Exit quickly on confirmed breakout
input int InpRngMaxTradesPerTouch = 1; // Max trades per boundary touch
input int InpRngSignalTtlMs = 1000; // Signal validity (ms)
input int InpRngTimeStopSec = 120; // Time-stop (s, 0 = off)
input int InpRngMaxPositions = 3; // Max simultaneous positions (Range)
input double InpRngBeTriggerPct = 70.0; // Break-even trigger (% of TP distance)
input double InpRngBeLockPct = 5.0; // Break-even lock (% of TP distance)
input double InpRngTrailTriggerPct = 85.0; // Trailing trigger (% of TP distance)
input double InpRngTrailDistPct = 25.0; // Trailing distance (% of TP distance)
input double InpRngTrailStepPct = 5.0; // Trailing min step (% of TP distance)

sinput string InpSep_POS = "==== 09. POSITIONS / CONFLICTS / HEDGING ===="; // ==== 09. POSITIONS / CONFLICTS / HEDGING ====
input int InpMaxPositionsSymbol = 9; // Max total positions on this symbol (this instance)
input bool InpAllowOppositeHedge = false; // OPPOSITE_HEDGE (allow BUY and SELL together)
input ENUM_FTF_SAMEDIR InpSameDirMode = FTF_SAMEDIR_STACK; // Same-direction signals
input int InpConflictWindowMs = 300; // Opposite-signal conflict window (ms)
input int InpConflictHoldMs = 300; // Entry block after a conflict (ms)
input double InpDupMinDistAtr = 0.1; // Min distance between same-engine entries (x ATR M1)
input int InpMinEntrySpacingMs = 0; // Min time between any two entries (ms, 0 = off)
input int InpHardMaxHoldSec = 120; // Hard max holding time, all engines (s, 0 = off)
input int InpMinModifyIntervalMs = 300; // Min interval between SL modifications (ms)
input bool InpTwoStepStops = false; // Send SL/TP after the fill (ECN brokers)

sinput string InpSep_RISK = "==== 10. RISK MANAGEMENT ===="; // ==== 10. RISK MANAGEMENT ====
input ENUM_FTF_RISK_MODE InpRiskMode = FTF_RISK_PCT_EQUITY; // RISK_MODE
input double InpFixedLot = 0.01; // Fixed lot
input double InpRiskPercent = 0.25; // Risk per trade (%)
input double InpMaxRiskPercent = 1.0; // Max risk per trade - hard cap (%)
input double InpMaxLotPerTrade = 0.0; // Max lot per trade (0 = broker max)
input bool InpAllowMinLotOverRisk = false; // Allow broker min lot even if above max risk
input double InpMaxOpenRiskPct = 5.0; // Max total open risk, this instance (%)
input double InpMaxTotalLots = 0.0; // Max total open lots, this instance (0 = off)
input ENUM_FTF_STOPS_POLICY InpStopsPolicy = FTF_STOPS_ADJUST; // Broker stops-level policy
input double InpMaxSlTpRatio = 2.0; // SL/TP ratio guard (max SL / TP, 0 = off)
input bool InpMartingaleEnabled = false; // Martingale ON (optional)
input double InpMartingaleMult = 1.5; // Martingale multiplier
input int InpMartingaleMaxSteps = 3; // Martingale max steps

sinput string InpSep_DD = "==== 11. EQUITY DRAWDOWN PROTECTION (10% PAUSE) ===="; // ==== 11. EQUITY DRAWDOWN PROTECTION (10% PAUSE) ====
input bool InpDdEnabled = true; // Equity drawdown pause ON
input double InpDdPausePct = 10.0; // Drawdown threshold (%)
input int InpDdPauseSec = 10; // Pause length (s)
input ENUM_FTF_DD_REF InpDdReference = FTF_DDREF_PEAK_EQUITY; // Drawdown reference

sinput string InpSep_NEWS = "==== 12. NEWS FILTER (B.1) ===="; // ==== 12. NEWS FILTER (B.1) ====
input bool InpNewsEnabled = true; // NEWS_FILTER ON
input ENUM_FTF_NEWS_SOURCE InpNewsSource = FTF_NEWS_AUTO; // News source
input ENUM_FTF_IMPACT InpNewsMinImpact = FTF_IMPACT_HIGH; // Min impact
input string InpNewsCurrencies = "AUTO"; // Currencies (AUTO or list e.g. USD,EUR)
input string InpNewsKeywords = "Non-Farm,Nonfarm,NFP,CPI,FOMC,Federal Funds,Interest Rate,Rate Decision,Fed Chair"; // Keywords always blocked (any impact)
input int InpNewsMinsBefore = 10; // Block minutes BEFORE news
input int InpNewsMinsAfter = 10; // Block minutes AFTER news
input string InpNewsCsvFile = "FranckyTriFlux\\news.csv"; // News CSV file (in Files or Common\Files)
input bool InpNewsCsvCommon = true; // News CSV is in Common\Files
input bool InpNewsCsvUtc = true; // News CSV times are UTC
input string InpNewsWebUrl = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml"; // Web XML feed URL
input int InpNewsRefreshMin = 60; // News refresh interval (min)
input bool InpNewsDraw = true; // Draw news windows on chart

sinput string InpSep_SESS = "==== 13. SESSIONS / DAYS (B.2) ===="; // ==== 13. SESSIONS / DAYS (B.2) ====
input bool InpSessionEnabled = false; // SESSION_FILTER ON
input ENUM_FTF_SESSION_PRESET InpSessionPreset = FTF_SESS_LONDON_NY; // Session preset
input ENUM_FTF_TIME_BASIS InpSessionTimeBasis = FTF_TIME_SERVER; // CUSTOM hours time basis
input string InpTradingStart = "08:00"; // TradingStart (HH:MM)
input string InpTradingEnd = "22:00"; // TradingEnd (HH:MM)
input string InpTradingStart2 = ""; // TradingStart 2 (HH:MM, empty = none)
input string InpTradingEnd2 = ""; // TradingEnd 2 (HH:MM)
input bool InpTradeMonday = true; // Trade Monday
input bool InpTradeTuesday = true; // Trade Tuesday
input bool InpTradeWednesday = true; // Trade Wednesday
input bool InpTradeThursday = true; // Trade Thursday
input bool InpTradeFriday = true; // Trade Friday
input bool InpTradeSaturday = false; // Trade Saturday
input bool InpTradeSunday = false; // Trade Sunday

sinput string InpSep_ROLL = "==== 14. ROLLOVER / DAY CHANGE (B.3) ===="; // ==== 14. ROLLOVER / DAY CHANGE (B.3) ====
input bool InpRolloverEnabled = true; // ROLLOVER_FILTER ON
input string InpRolloverTime = "00:00"; // Rollover time (server, HH:MM)
input int InpRolloverMinsBefore = 10; // Block minutes BEFORE rollover
input int InpRolloverMinsAfter = 15; // Block minutes AFTER rollover

sinput string InpSep_TZ = "==== 15. TIME ZONE (SERVER / UTC) ===="; // ==== 15. TIME ZONE (SERVER / UTC) ====
input ENUM_FTF_GMT_MODE InpGmtMode = FTF_GMT_AUTO; // Broker GMT offset mode
input int InpGmtOffsetHours = 2; // Manual broker GMT offset (winter, hours)
input bool InpGmtUseUsDst = true; // Manual offset follows US DST (+1h)

sinput string InpSep_CONS = "==== 16. CONSECUTIVE LOSS PROTECTION (B.4) ===="; // ==== 16. CONSECUTIVE LOSS PROTECTION (B.4) ====
input bool InpConsecEnabled = true; // CONSECUTIVE_LOSS_PROTECTION ON
input int InpConsecMaxLosses = 3; // Consecutive losses X
input int InpConsecCooldownMin = 15; // Cooldown Y (minutes)
input ENUM_FTF_LOSS_SCOPE InpConsecScope = FTF_SCOPE_ENGINE; // Scope

sinput string InpSep_EXEC = "==== 17. EXECUTION / RETRIES / QUALITY (B.8) ===="; // ==== 17. EXECUTION / RETRIES / QUALITY (B.8) ====
input int InpMaxDeviationPts = 0; // Max slippage / deviation (points, 0 = auto)
input double InpAutoDeviationSpreadMult = 1.0; // Auto deviation (x spread)
input int InpMaxRetries = 3; // Max retries per order
input int InpRetryDelayMs = 150; // Delay between retries (ms)
input double InpRetryMaxDriftAtr = 0.15; // Max price drift before a retry (x ATR M1)
input int InpFatalErrorCooldownSec = 60; // Pause after a permanent broker error (s)
input ENUM_FTF_EXECQ_ACTION InpExecQualityAction = FTF_EXECQ_BLOCK; // Execution-quality action
input int InpExecQualityWindow = 20; // Execution-quality window (trades)
input double InpMaxAvgSlippageSpreadMult = 1.5; // Max avg adverse slippage (x avg spread, 0 = off)
input int InpMaxAvgLatencyMs = 0; // Max avg order latency (ms, 0 = off)
input int InpExecQualityCooldownSec = 120; // Execution-quality cooldown (s)
input double InpExecQualityLotFactor = 0.5; // Lot factor when quality is poor

sinput string InpSep_MI = "==== 18. MULTI-INSTANCE / AGGREGATE EXPOSURE (B.6) ===="; // ==== 18. MULTI-INSTANCE / AGGREGATE EXPOSURE (B.6) ====
input ENUM_FTF_MI_GUARD InpMiGuard = FTF_MI_ISOLATE; // MULTI_INSTANCE_GUARD
input int InpMiDupWindowSec = 10; // Cross-instance duplicate window (s)
input ENUM_FTF_EXPOSURE_MODE InpExposureMode = FTF_EXPO_CURRENCY; // Aggregate exposure mode
input bool InpExposureFamilyOnly = true; // Count only FRANCKY positions (same magic base)
input double InpMaxAccountRiskPct = 10.0; // Max open risk all symbols (% equity)
input double InpMaxCurrencyRiskPct = 6.0; // Max net risk per currency, e.g. USD (% equity)
input int InpCorrBars = 288; // Correlation lookback (M5 bars)
input double InpMaxCorrRiskPct = 6.0; // Max correlation-adjusted risk (% equity)

sinput string InpSep_STATE = "==== 19. RESTART RECOVERY (B.7) ===="; // ==== 19. RESTART RECOVERY (B.7) ====
input bool InpStateEnabled = true; // Save and restore state after restart
input int InpRestartGraceSec = 5; // No new entries after start (s)

sinput string InpSep_LOG = "==== 20. LOGGING / STATISTICS ===="; // ==== 20. LOGGING / STATISTICS ====
input ENUM_FTF_LOG_LEVEL InpLogLevel = FTF_LOG_INFO; // Log level
input bool InpLogToJournal = true; // Print to Experts journal
input bool InpLogToFile = true; // Write text log file
input bool InpLogCsv = true; // Write CSV journals (signals, trades, events, stats)
input bool InpLogCommon = true; // Log files in Common\Files
input bool InpLogSignals = true; // Log every signal decision
input int InpLogThrottleMs = 2000; // Throttle repeated messages (ms)
input bool InpLogInOptimization = false; // Write files during optimization
input int InpStatsEveryMin = 60; // Write stats summary every (min)

sinput string InpSep_UI = "==== 21. CHART DISPLAY ===="; // ==== 21. CHART DISPLAY ====
input bool InpShowPanel = true; // Show dashboard panel
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER; // Panel corner
input int InpPanelX = 10; // Panel X offset (px)
input int InpPanelY = 20; // Panel Y offset (px)
input int InpPanelFontSize = 8; // Panel font size
input bool InpPanelDark = true; // Dark panel theme
input int InpPanelRefreshMs = 250; // Panel refresh (ms)
input bool InpDrawTrades = true; // Draw entries / exits
input bool InpDrawZones = true; // Draw FVG zones, ranges, micro-ranges
input bool InpDrawRejected = false; // Draw rejected signals
input int InpMaxChartObjects = 600; // Max chart objects
input bool InpKeepObjectsOnExit = true; // Keep drawings when the EA stops (tester review)

sinput string InpSep_TEST = "==== 22. TESTER / OPTIMIZATION / STRESS ===="; // ==== 22. TESTER / OPTIMIZATION / STRESS ====
input ENUM_FTF_OPT_CRITERION InpOptCriterion = FTF_OPT_ROBUST; // Custom optimization criterion
input int InpOptMinTrades = 30; // Min trades for a valid pass
input int InpStressExtraSpreadPts = 0; // Stress: extra spread (points)
input double InpStressCommissionPerLot = 0.0; // Stress: extra commission per lot (money)

#endif // FTF_INPUTS_MQH
