//+------------------------------------------------------------------+
//| FRANCKY TRI-FLUX HFT-style Ultra Scalping                          |
//| GENERATED FILE - DO NOT EDIT BY HAND.                              |
//| Source of truth: tools/ftf_spec.py  ->  python3 tools/generate.py |
//+------------------------------------------------------------------+

#ifndef FTF_CONFIG_MQH
#define FTF_CONFIG_MQH

#include <FranckyTriFlux\Core\InputEnums.mqh>

// CConfig holds a validated copy of every input. Core modules ONLY read CConfig, never Inp* globals.
// The only place where Inp* globals are read is LoadFromInputs() below.
class CConfig
  {
public:
   //--- 01. GENERAL / INSTANCE
   bool                   EnableTrading;  // Enable new entries (master switch)
   ENUM_FTF_MODE          TradingMode;  // Trading mode (SPEED / AGGRESSIVE / ULTRA)
   int                    InstanceId;  // Instance ID (1-999, unique per chart on one account)
   int                    MagicBase;  // Magic number base (magic = base + ID x 10 + engine)
   string                 CommentPrefix;  // Order comment prefix
   ENUM_FTF_SYMBOL_CHECK  SymbolCheck;  // Supported-symbol check (EURUSD/XAUUSD/BTCUSD)
   int                    TimerMs;  // Internal timer period (ms)
   //--- 02. STRATEGY ENGINES ON/OFF
   bool                   MomEnabled;  // Engine A - Momentum / Micro-breakout ON
   bool                   FvgEnabled;  // Engine B - FVG (Fair Value Gap) ON
   bool                   RngEnabled;  // Engine C - Range / Mean Reversion ON
   //--- 03. MODES - DELAYS AND SPREAD LIMITS
   int                    DelaySpeedMs;  // SPEED mode entry delay (ms)
   int                    DelayAggressiveMs;  // AGGRESSIVE mode entry delay (ms)
   int                    DelayUltraMs;  // ULTRA mode entry delay (ms)
   ENUM_FTF_DELAY_USAGE   DelayUsage;  // How the mode delay is applied
   int                    MaxSpreadPtsSpeed;  // Max spread SPEED (points, 0 = auto)
   int                    MaxSpreadPtsAggressive;  // Max spread AGGRESSIVE (points, 0 = auto)
   int                    MaxSpreadPtsUltra;  // Max spread ULTRA (points, 0 = auto)
   double                 AutoMaxSpreadAtr;  // Auto max spread (x ATR M1) when limit = 0
   //--- 04. MARKET DATA / VOLATILITY
   int                    AtrPeriod;  // ATR period (M1 / M5)
   int                    AtrMedianBars;  // ATR median length (M1 bars)
   int                    TickHistorySec;  // Tick history kept in memory (s)
   int                    MaxTickAgeSec;  // Max tick age before market considered stale (s)
   double                 VolAnomalyAtrMult;  // Volatility anomaly: ATR > x median ATR
   double                 VolAnomalyVelMult;  // Volatility anomaly: tick velocity > x median
   double                 VolAnomalySpreadMult;  // Volatility anomaly: spread > x median spread
   //--- 05. H1 CONTEXT FILTER (OFF / SOFT / STRICT)
   ENUM_FTF_H1_FILTER     H1Filter;  // H1_FILTER mode
   int                    H1EmaFast;  // H1 fast EMA period
   int                    H1EmaSlow;  // H1 slow EMA period
   int                    H1AdxPeriod;  // H1 ADX period
   double                 H1AdxThreshold;  // H1 ADX directional threshold
   double                 H1DiMinGap;  // H1 min +DI/-DI gap
   double                 H1StrongAdx;  // H1 'strong trend' ADX (Range STRICT)
   bool                   H1StrictMomentum;  // STRICT applies to Momentum
   bool                   H1StrictFvg;  // STRICT applies to FVG
   bool                   H1StrictRange;  // STRICT applies to Range
   //--- 06. ENGINE A - MOMENTUM / MICRO-BREAKOUT
   int                    MomTickWindow;  // Tick window for imbalance (ticks)
   double                 MomBuyRatio;  // BUY: min bullish tick ratio
   bool                   MomSymmetric;  // SELL ratio = 1 - BUY ratio (symmetric)
   double                 MomSellRatio;  // SELL: max bullish tick ratio
   bool                   MomCountFlatTicks;  // Count unchanged ticks in the ratio
   ENUM_FTF_VEL_METRIC    MomVelMetric;  // Velocity metric
   int                    MomVelWindowMs;  // Velocity window (ms)
   int                    MomVelRefMs;  // Velocity reference window for median (ms)
   double                 MomVelRatio;  // Min velocity / median velocity
   double                 MomAccelMin;  // Min acceleration (0.20 = +20%)
   int                    MomMicroRangeTicks;  // Micro-range length (ticks)
   double                 MomBufSpreadMult;  // Breakout buffer (x spread)
   double                 MomBufAtrMult;  // Breakout buffer (x ATR M1)
   bool                   MomUseRoc;  // Confirm with ROC direction
   int                    MomRocPeriod;  // ROC period (M1 bars)
   double                 MomRocMin;  // Min |ROC| (%)
   bool                   MomUseEma;  // Confirm with M1 EMA fast/slow
   int                    MomEmaFast;  // M1 fast EMA period
   int                    MomEmaSlow;  // M1 slow EMA period
   bool                   MomUseAdx;  // Confirm with M1 ADX/DI
   double                 MomAdxMin;  // M1 ADX min
   ENUM_FTF_CTX_USE       MomM5Context;  // M5 EMA20/50 context
   double                 MomTpSpreadMult;  // TP = max(x spread, ...)
   double                 MomTpAtrMult;  // TP = max(..., x ATR M1)
   double                 MomSlSpreadMult;  // SL = max(x spread, ...)
   double                 MomSlAtrMult;  // SL = max(..., x ATR M1)
   int                    MomSignalTtlMs;  // Signal validity (ms)
   bool                   MomExitEnabled;  // Momentum-loss exit ON
   double                 MomExitScore;  // Exit when momentum score below
   int                    MomExitInversionMs;  // Tick inversion persistence (ms)
   int                    MomExitTicks;  // Inversion window (ticks)
   int                    MomTimeStopSec;  // Time-stop (s, 0 = off)
   int                    MomMaxPositions;  // Max simultaneous positions (Momentum)
   double                 MomBeTriggerPct;  // Break-even trigger (% of TP distance)
   double                 MomBeLockPct;  // Break-even lock (% of TP distance)
   double                 MomTrailTriggerPct;  // Trailing trigger (% of TP distance)
   double                 MomTrailDistPct;  // Trailing distance (% of TP distance)
   double                 MomTrailStepPct;  // Trailing min step (% of TP distance)
   //--- 07. ENGINE B - FVG (FAIR VALUE GAP)
   ENUM_TIMEFRAMES        FvgTimeframe;  // FVG timeframe
   bool                   FvgUseM1Refine;  // Use M1 for entry precision
   int                    FvgScanBars;  // Bars scanned for FVGs
   int                    FvgMaxZones;  // Max zones kept
   double                 FvgMinGapAtr;  // Min gap size (x ATR of FVG timeframe)
   double                 FvgMinGapSpreadMult;  // Min gap size (x spread)
   int                    FvgMaxAgeBars;  // Max zone age (bars)
   int                    FvgMaxMitigations;  // Max mitigations (returns into zone)
   double                 FvgMaxDistanceAtr;  // Max price distance to zone (x ATR)
   ENUM_FTF_FVG_ENTRY     FvgEntryMode;  // Entry mode (TOUCH / CE 50% / REJECTION)
   double                 FvgRejectWickPct;  // REJECTION: min wick (% of candle range)
   bool                   FvgBosRequired;  // BOS_REQUIRED (structure confirmation)
   ENUM_FTF_STRUCT_MODE   FvgStructMode;  // Structure event accepted when required
   int                    StructSwingBars;  // Swing strength (bars each side)
   int                    StructLookbackBars;  // Structure lookback (bars)
   double                 FvgInvalidBufAtr;  // Invalidation buffer (x ATR)
   bool                   FvgInvalidOnClose;  // Invalidate on candle close (else on tick)
   ENUM_FTF_FVG_SL        FvgSlMode;  // SL anchor
   double                 FvgSlBufSpreadMult;  // SL buffer (x spread)
   double                 FvgSlBufAtr;  // SL buffer (x ATR)
   ENUM_FTF_TP_MODE       FvgTpMode;  // TP mode
   double                 FvgTpAtrMult;  // TP ATR multiple
   double                 FvgTpRR;  // TP R multiple
   double                 FvgTpMinRR;  // TP min R (liquidity mode)
   double                 FvgTpMaxRR;  // TP max R (liquidity mode)
   int                    FvgMaxTradesPerZone;  // Max trades per zone
   int                    FvgSignalTtlMs;  // Signal validity (ms)
   bool                   FvgExitOnInvalidation;  // Exit open trade if zone invalidated
   int                    FvgTimeStopSec;  // Time-stop (s, 0 = off)
   int                    FvgMaxPositions;  // Max simultaneous positions (FVG)
   double                 FvgBeTriggerPct;  // Break-even trigger (% of TP distance)
   double                 FvgBeLockPct;  // Break-even lock (% of TP distance)
   double                 FvgTrailTriggerPct;  // Trailing trigger (% of TP distance)
   double                 FvgTrailDistPct;  // Trailing distance (% of TP distance)
   double                 FvgTrailStepPct;  // Trailing min step (% of TP distance)
   //--- 08. ENGINE C - RANGE / MEAN REVERSION
   ENUM_TIMEFRAMES        RngTimeframe;  // Range timeframe (M1 or M5)
   int                    RngLookbackBars;  // Range lookback (bars)
   int                    RngAdxPeriod;  // ADX period
   double                 RngAdxMax;  // Max ADX for a range
   bool                   RngRequireAdxFalling;  // Require falling ADX
   int                    RngAdxSlopeBars;  // ADX slope bars
   int                    RngEmaFast;  // Fast EMA period
   int                    RngEmaSlow;  // Slow EMA period
   double                 RngEmaSepMaxAtr;  // Max |EMA20-EMA50| (x ATR)
   double                 RngMinWidthAtr;  // Min range width (x ATR)
   double                 RngMinWidthSpreadMult;  // Min range width (x spread)
   double                 RngMaxWidthAtr;  // Max range width (x ATR)
   double                 RngMaxDriftPct;  // Max net drift (% of width)
   int                    RngMinTouchesPerSide;  // Min touches per boundary
   double                 RngEdgeZonePct;  // Entry zone near boundary (% of width)
   ENUM_FTF_RANGE_CONFIRM RngConfirmMode;  // Edge confirmation (slowdown / rejection)
   double                 RngRejectWickPct;  // Rejection: min wick (% of candle range)
   int                    RngTickWindow;  // Tick window for buyer/seller return (ticks)
   double                 RngTickRatioMin;  // Min returning tick ratio
   double                 RngMaxVelRatio;  // Max tick velocity ratio (impulse protection)
   double                 RngMaxAtrExpansion;  // Max ATR / median ATR
   double                 RngSlBufSpreadMult;  // SL buffer beyond boundary (x spread)
   double                 RngSlBufAtr;  // SL buffer beyond boundary (x ATR)
   ENUM_FTF_RANGE_TP      RngTpTarget;  // TP target
   double                 RngTpOffsetPct;  // TP offset before target (% of width)
   double                 RngBreakBufAtr;  // Breakout confirmation buffer (x ATR)
   bool                   RngExitOnBreakout;  // Exit quickly on confirmed breakout
   int                    RngMaxTradesPerTouch;  // Max trades per boundary touch
   int                    RngSignalTtlMs;  // Signal validity (ms)
   int                    RngTimeStopSec;  // Time-stop (s, 0 = off)
   int                    RngMaxPositions;  // Max simultaneous positions (Range)
   double                 RngBeTriggerPct;  // Break-even trigger (% of TP distance)
   double                 RngBeLockPct;  // Break-even lock (% of TP distance)
   double                 RngTrailTriggerPct;  // Trailing trigger (% of TP distance)
   double                 RngTrailDistPct;  // Trailing distance (% of TP distance)
   double                 RngTrailStepPct;  // Trailing min step (% of TP distance)
   //--- 09. POSITIONS / CONFLICTS / HEDGING
   int                    MaxPositionsSymbol;  // Max total positions on this symbol (this instance)
   bool                   AllowOppositeHedge;  // OPPOSITE_HEDGE (allow BUY and SELL together)
   ENUM_FTF_SAMEDIR       SameDirMode;  // Same-direction signals
   int                    ConflictWindowMs;  // Opposite-signal conflict window (ms)
   int                    ConflictHoldMs;  // Entry block after a conflict (ms)
   double                 DupMinDistAtr;  // Min distance between same-engine entries (x ATR M1)
   int                    MinEntrySpacingMs;  // Min time between any two entries (ms, 0 = off)
   int                    HardMaxHoldSec;  // Hard max holding time, all engines (s, 0 = off)
   int                    MinModifyIntervalMs;  // Min interval between SL modifications (ms)
   bool                   TwoStepStops;  // Send SL/TP after the fill (ECN brokers)
   //--- 10. RISK MANAGEMENT
   ENUM_FTF_RISK_MODE     RiskMode;  // RISK_MODE
   double                 FixedLot;  // Fixed lot
   double                 RiskPercent;  // Risk per trade (%)
   double                 MaxRiskPercent;  // Max risk per trade - hard cap (%)
   double                 MaxLotPerTrade;  // Max lot per trade (0 = broker max)
   bool                   AllowMinLotOverRisk;  // Allow broker min lot even if above max risk
   double                 MaxOpenRiskPct;  // Max total open risk, this instance (%)
   double                 MaxTotalLots;  // Max total open lots, this instance (0 = off)
   ENUM_FTF_STOPS_POLICY  StopsPolicy;  // Broker stops-level policy
   double                 MaxSlTpRatio;  // SL/TP ratio guard (max SL / TP, 0 = off)
   bool                   MartingaleEnabled;  // Martingale ON (optional)
   double                 MartingaleMult;  // Martingale multiplier
   int                    MartingaleMaxSteps;  // Martingale max steps
   //--- 11. EQUITY DRAWDOWN PROTECTION (10% PAUSE)
   bool                   DdEnabled;  // Equity drawdown pause ON
   double                 DdPausePct;  // Drawdown threshold (%)
   int                    DdPauseSec;  // Pause length (s)
   ENUM_FTF_DD_REF        DdReference;  // Drawdown reference
   //--- 12. NEWS FILTER (B.1)
   bool                   NewsEnabled;  // NEWS_FILTER ON
   ENUM_FTF_NEWS_SOURCE   NewsSource;  // News source
   ENUM_FTF_IMPACT        NewsMinImpact;  // Min impact
   string                 NewsCurrencies;  // Currencies (AUTO or list e.g. USD,EUR)
   string                 NewsKeywords;  // Keywords always blocked (any impact)
   int                    NewsMinsBefore;  // Block minutes BEFORE news
   int                    NewsMinsAfter;  // Block minutes AFTER news
   string                 NewsCsvFile;  // News CSV file (in Files or Common\Files)
   bool                   NewsCsvCommon;  // News CSV is in Common\Files
   bool                   NewsCsvUtc;  // News CSV times are UTC
   string                 NewsWebUrl;  // Web XML feed URL
   int                    NewsRefreshMin;  // News refresh interval (min)
   bool                   NewsDraw;  // Draw news windows on chart
   //--- 13. SESSIONS / DAYS (B.2)
   bool                   SessionEnabled;  // SESSION_FILTER ON
   ENUM_FTF_SESSION_PRESET SessionPreset;  // Session preset
   ENUM_FTF_TIME_BASIS    SessionTimeBasis;  // CUSTOM hours time basis
   string                 TradingStart;  // TradingStart (HH:MM)
   string                 TradingEnd;  // TradingEnd (HH:MM)
   string                 TradingStart2;  // TradingStart 2 (HH:MM, empty = none)
   string                 TradingEnd2;  // TradingEnd 2 (HH:MM)
   bool                   TradeMonday;  // Trade Monday
   bool                   TradeTuesday;  // Trade Tuesday
   bool                   TradeWednesday;  // Trade Wednesday
   bool                   TradeThursday;  // Trade Thursday
   bool                   TradeFriday;  // Trade Friday
   bool                   TradeSaturday;  // Trade Saturday
   bool                   TradeSunday;  // Trade Sunday
   //--- 14. ROLLOVER / DAY CHANGE (B.3)
   bool                   RolloverEnabled;  // ROLLOVER_FILTER ON
   string                 RolloverTime;  // Rollover time (server, HH:MM)
   int                    RolloverMinsBefore;  // Block minutes BEFORE rollover
   int                    RolloverMinsAfter;  // Block minutes AFTER rollover
   //--- 15. TIME ZONE (SERVER / UTC)
   ENUM_FTF_GMT_MODE      GmtMode;  // Broker GMT offset mode
   int                    GmtOffsetHours;  // Manual broker GMT offset (winter, hours)
   bool                   GmtUseUsDst;  // Manual offset follows US DST (+1h)
   //--- 16. CONSECUTIVE LOSS PROTECTION (B.4)
   bool                   ConsecEnabled;  // CONSECUTIVE_LOSS_PROTECTION ON
   int                    ConsecMaxLosses;  // Consecutive losses X
   int                    ConsecCooldownMin;  // Cooldown Y (minutes)
   ENUM_FTF_LOSS_SCOPE    ConsecScope;  // Scope
   //--- 17. EXECUTION / RETRIES / QUALITY (B.8)
   int                    MaxDeviationPts;  // Max slippage / deviation (points, 0 = auto)
   double                 AutoDeviationSpreadMult;  // Auto deviation (x spread)
   int                    MaxRetries;  // Max retries per order
   int                    RetryDelayMs;  // Delay between retries (ms)
   double                 RetryMaxDriftAtr;  // Max price drift before a retry (x ATR M1)
   int                    FatalErrorCooldownSec;  // Pause after a permanent broker error (s)
   ENUM_FTF_EXECQ_ACTION  ExecQualityAction;  // Execution-quality action
   int                    ExecQualityWindow;  // Execution-quality window (trades)
   double                 MaxAvgSlippageSpreadMult;  // Max avg adverse slippage (x avg spread, 0 = off)
   int                    MaxAvgLatencyMs;  // Max avg order latency (ms, 0 = off)
   int                    ExecQualityCooldownSec;  // Execution-quality cooldown (s)
   double                 ExecQualityLotFactor;  // Lot factor when quality is poor
   //--- 18. MULTI-INSTANCE / AGGREGATE EXPOSURE (B.6)
   ENUM_FTF_MI_GUARD      MiGuard;  // MULTI_INSTANCE_GUARD
   int                    MiDupWindowSec;  // Cross-instance duplicate window (s)
   ENUM_FTF_EXPOSURE_MODE ExposureMode;  // Aggregate exposure mode
   bool                   ExposureFamilyOnly;  // Count only FRANCKY positions (same magic base)
   double                 MaxAccountRiskPct;  // Max open risk all symbols (% equity)
   double                 MaxCurrencyRiskPct;  // Max net risk per currency, e.g. USD (% equity)
   int                    CorrBars;  // Correlation lookback (M5 bars)
   double                 MaxCorrRiskPct;  // Max correlation-adjusted risk (% equity)
   //--- 19. RESTART RECOVERY (B.7)
   bool                   StateEnabled;  // Save and restore state after restart
   int                    RestartGraceSec;  // No new entries after start (s)
   //--- 20. LOGGING / STATISTICS
   ENUM_FTF_LOG_LEVEL     LogLevel;  // Log level
   bool                   LogToJournal;  // Print to Experts journal
   bool                   LogToFile;  // Write text log file
   bool                   LogCsv;  // Write CSV journals (signals, trades, events, stats)
   bool                   LogCommon;  // Log files in Common\Files
   bool                   LogSignals;  // Log every signal decision
   int                    LogThrottleMs;  // Throttle repeated messages (ms)
   bool                   LogInOptimization;  // Write files during optimization
   int                    StatsEveryMin;  // Write stats summary every (min)
   //--- 21. CHART DISPLAY
   bool                   ShowPanel;  // Show dashboard panel
   ENUM_BASE_CORNER       PanelCorner;  // Panel corner
   int                    PanelX;  // Panel X offset (px)
   int                    PanelY;  // Panel Y offset (px)
   int                    PanelFontSize;  // Panel font size
   bool                   PanelDark;  // Dark panel theme
   int                    PanelRefreshMs;  // Panel refresh (ms)
   bool                   DrawTrades;  // Draw entries / exits
   bool                   DrawZones;  // Draw FVG zones, ranges, micro-ranges
   bool                   DrawRejected;  // Draw rejected signals
   int                    MaxChartObjects;  // Max chart objects
   bool                   KeepObjectsOnExit;  // Keep drawings when the EA stops (tester review)
   //--- 22. TESTER / OPTIMIZATION / STRESS
   ENUM_FTF_OPT_CRITERION OptCriterion;  // Custom optimization criterion
   int                    OptMinTrades;  // Min trades for a valid pass
   int                    StressExtraSpreadPts;  // Stress: extra spread (points)
   double                 StressCommissionPerLot;  // Stress: extra commission per lot (money)

   CConfig(void) {}

   //--- copy every input into the config
   void LoadFromInputs(void)
     {
      EnableTrading = InpEnableTrading;
      TradingMode = InpTradingMode;
      InstanceId = InpInstanceId;
      MagicBase = InpMagicBase;
      CommentPrefix = InpCommentPrefix;
      SymbolCheck = InpSymbolCheck;
      TimerMs = InpTimerMs;
      MomEnabled = InpMomEnabled;
      FvgEnabled = InpFvgEnabled;
      RngEnabled = InpRngEnabled;
      DelaySpeedMs = InpDelaySpeedMs;
      DelayAggressiveMs = InpDelayAggressiveMs;
      DelayUltraMs = InpDelayUltraMs;
      DelayUsage = InpDelayUsage;
      MaxSpreadPtsSpeed = InpMaxSpreadPtsSpeed;
      MaxSpreadPtsAggressive = InpMaxSpreadPtsAggressive;
      MaxSpreadPtsUltra = InpMaxSpreadPtsUltra;
      AutoMaxSpreadAtr = InpAutoMaxSpreadAtr;
      AtrPeriod = InpAtrPeriod;
      AtrMedianBars = InpAtrMedianBars;
      TickHistorySec = InpTickHistorySec;
      MaxTickAgeSec = InpMaxTickAgeSec;
      VolAnomalyAtrMult = InpVolAnomalyAtrMult;
      VolAnomalyVelMult = InpVolAnomalyVelMult;
      VolAnomalySpreadMult = InpVolAnomalySpreadMult;
      H1Filter = InpH1Filter;
      H1EmaFast = InpH1EmaFast;
      H1EmaSlow = InpH1EmaSlow;
      H1AdxPeriod = InpH1AdxPeriod;
      H1AdxThreshold = InpH1AdxThreshold;
      H1DiMinGap = InpH1DiMinGap;
      H1StrongAdx = InpH1StrongAdx;
      H1StrictMomentum = InpH1StrictMomentum;
      H1StrictFvg = InpH1StrictFvg;
      H1StrictRange = InpH1StrictRange;
      MomTickWindow = InpMomTickWindow;
      MomBuyRatio = InpMomBuyRatio;
      MomSymmetric = InpMomSymmetric;
      MomSellRatio = InpMomSellRatio;
      MomCountFlatTicks = InpMomCountFlatTicks;
      MomVelMetric = InpMomVelMetric;
      MomVelWindowMs = InpMomVelWindowMs;
      MomVelRefMs = InpMomVelRefMs;
      MomVelRatio = InpMomVelRatio;
      MomAccelMin = InpMomAccelMin;
      MomMicroRangeTicks = InpMomMicroRangeTicks;
      MomBufSpreadMult = InpMomBufSpreadMult;
      MomBufAtrMult = InpMomBufAtrMult;
      MomUseRoc = InpMomUseRoc;
      MomRocPeriod = InpMomRocPeriod;
      MomRocMin = InpMomRocMin;
      MomUseEma = InpMomUseEma;
      MomEmaFast = InpMomEmaFast;
      MomEmaSlow = InpMomEmaSlow;
      MomUseAdx = InpMomUseAdx;
      MomAdxMin = InpMomAdxMin;
      MomM5Context = InpMomM5Context;
      MomTpSpreadMult = InpMomTpSpreadMult;
      MomTpAtrMult = InpMomTpAtrMult;
      MomSlSpreadMult = InpMomSlSpreadMult;
      MomSlAtrMult = InpMomSlAtrMult;
      MomSignalTtlMs = InpMomSignalTtlMs;
      MomExitEnabled = InpMomExitEnabled;
      MomExitScore = InpMomExitScore;
      MomExitInversionMs = InpMomExitInversionMs;
      MomExitTicks = InpMomExitTicks;
      MomTimeStopSec = InpMomTimeStopSec;
      MomMaxPositions = InpMomMaxPositions;
      MomBeTriggerPct = InpMomBeTriggerPct;
      MomBeLockPct = InpMomBeLockPct;
      MomTrailTriggerPct = InpMomTrailTriggerPct;
      MomTrailDistPct = InpMomTrailDistPct;
      MomTrailStepPct = InpMomTrailStepPct;
      FvgTimeframe = InpFvgTimeframe;
      FvgUseM1Refine = InpFvgUseM1Refine;
      FvgScanBars = InpFvgScanBars;
      FvgMaxZones = InpFvgMaxZones;
      FvgMinGapAtr = InpFvgMinGapAtr;
      FvgMinGapSpreadMult = InpFvgMinGapSpreadMult;
      FvgMaxAgeBars = InpFvgMaxAgeBars;
      FvgMaxMitigations = InpFvgMaxMitigations;
      FvgMaxDistanceAtr = InpFvgMaxDistanceAtr;
      FvgEntryMode = InpFvgEntryMode;
      FvgRejectWickPct = InpFvgRejectWickPct;
      FvgBosRequired = InpFvgBosRequired;
      FvgStructMode = InpFvgStructMode;
      StructSwingBars = InpStructSwingBars;
      StructLookbackBars = InpStructLookbackBars;
      FvgInvalidBufAtr = InpFvgInvalidBufAtr;
      FvgInvalidOnClose = InpFvgInvalidOnClose;
      FvgSlMode = InpFvgSlMode;
      FvgSlBufSpreadMult = InpFvgSlBufSpreadMult;
      FvgSlBufAtr = InpFvgSlBufAtr;
      FvgTpMode = InpFvgTpMode;
      FvgTpAtrMult = InpFvgTpAtrMult;
      FvgTpRR = InpFvgTpRR;
      FvgTpMinRR = InpFvgTpMinRR;
      FvgTpMaxRR = InpFvgTpMaxRR;
      FvgMaxTradesPerZone = InpFvgMaxTradesPerZone;
      FvgSignalTtlMs = InpFvgSignalTtlMs;
      FvgExitOnInvalidation = InpFvgExitOnInvalidation;
      FvgTimeStopSec = InpFvgTimeStopSec;
      FvgMaxPositions = InpFvgMaxPositions;
      FvgBeTriggerPct = InpFvgBeTriggerPct;
      FvgBeLockPct = InpFvgBeLockPct;
      FvgTrailTriggerPct = InpFvgTrailTriggerPct;
      FvgTrailDistPct = InpFvgTrailDistPct;
      FvgTrailStepPct = InpFvgTrailStepPct;
      RngTimeframe = InpRngTimeframe;
      RngLookbackBars = InpRngLookbackBars;
      RngAdxPeriod = InpRngAdxPeriod;
      RngAdxMax = InpRngAdxMax;
      RngRequireAdxFalling = InpRngRequireAdxFalling;
      RngAdxSlopeBars = InpRngAdxSlopeBars;
      RngEmaFast = InpRngEmaFast;
      RngEmaSlow = InpRngEmaSlow;
      RngEmaSepMaxAtr = InpRngEmaSepMaxAtr;
      RngMinWidthAtr = InpRngMinWidthAtr;
      RngMinWidthSpreadMult = InpRngMinWidthSpreadMult;
      RngMaxWidthAtr = InpRngMaxWidthAtr;
      RngMaxDriftPct = InpRngMaxDriftPct;
      RngMinTouchesPerSide = InpRngMinTouchesPerSide;
      RngEdgeZonePct = InpRngEdgeZonePct;
      RngConfirmMode = InpRngConfirmMode;
      RngRejectWickPct = InpRngRejectWickPct;
      RngTickWindow = InpRngTickWindow;
      RngTickRatioMin = InpRngTickRatioMin;
      RngMaxVelRatio = InpRngMaxVelRatio;
      RngMaxAtrExpansion = InpRngMaxAtrExpansion;
      RngSlBufSpreadMult = InpRngSlBufSpreadMult;
      RngSlBufAtr = InpRngSlBufAtr;
      RngTpTarget = InpRngTpTarget;
      RngTpOffsetPct = InpRngTpOffsetPct;
      RngBreakBufAtr = InpRngBreakBufAtr;
      RngExitOnBreakout = InpRngExitOnBreakout;
      RngMaxTradesPerTouch = InpRngMaxTradesPerTouch;
      RngSignalTtlMs = InpRngSignalTtlMs;
      RngTimeStopSec = InpRngTimeStopSec;
      RngMaxPositions = InpRngMaxPositions;
      RngBeTriggerPct = InpRngBeTriggerPct;
      RngBeLockPct = InpRngBeLockPct;
      RngTrailTriggerPct = InpRngTrailTriggerPct;
      RngTrailDistPct = InpRngTrailDistPct;
      RngTrailStepPct = InpRngTrailStepPct;
      MaxPositionsSymbol = InpMaxPositionsSymbol;
      AllowOppositeHedge = InpAllowOppositeHedge;
      SameDirMode = InpSameDirMode;
      ConflictWindowMs = InpConflictWindowMs;
      ConflictHoldMs = InpConflictHoldMs;
      DupMinDistAtr = InpDupMinDistAtr;
      MinEntrySpacingMs = InpMinEntrySpacingMs;
      HardMaxHoldSec = InpHardMaxHoldSec;
      MinModifyIntervalMs = InpMinModifyIntervalMs;
      TwoStepStops = InpTwoStepStops;
      RiskMode = InpRiskMode;
      FixedLot = InpFixedLot;
      RiskPercent = InpRiskPercent;
      MaxRiskPercent = InpMaxRiskPercent;
      MaxLotPerTrade = InpMaxLotPerTrade;
      AllowMinLotOverRisk = InpAllowMinLotOverRisk;
      MaxOpenRiskPct = InpMaxOpenRiskPct;
      MaxTotalLots = InpMaxTotalLots;
      StopsPolicy = InpStopsPolicy;
      MaxSlTpRatio = InpMaxSlTpRatio;
      MartingaleEnabled = InpMartingaleEnabled;
      MartingaleMult = InpMartingaleMult;
      MartingaleMaxSteps = InpMartingaleMaxSteps;
      DdEnabled = InpDdEnabled;
      DdPausePct = InpDdPausePct;
      DdPauseSec = InpDdPauseSec;
      DdReference = InpDdReference;
      NewsEnabled = InpNewsEnabled;
      NewsSource = InpNewsSource;
      NewsMinImpact = InpNewsMinImpact;
      NewsCurrencies = InpNewsCurrencies;
      NewsKeywords = InpNewsKeywords;
      NewsMinsBefore = InpNewsMinsBefore;
      NewsMinsAfter = InpNewsMinsAfter;
      NewsCsvFile = InpNewsCsvFile;
      NewsCsvCommon = InpNewsCsvCommon;
      NewsCsvUtc = InpNewsCsvUtc;
      NewsWebUrl = InpNewsWebUrl;
      NewsRefreshMin = InpNewsRefreshMin;
      NewsDraw = InpNewsDraw;
      SessionEnabled = InpSessionEnabled;
      SessionPreset = InpSessionPreset;
      SessionTimeBasis = InpSessionTimeBasis;
      TradingStart = InpTradingStart;
      TradingEnd = InpTradingEnd;
      TradingStart2 = InpTradingStart2;
      TradingEnd2 = InpTradingEnd2;
      TradeMonday = InpTradeMonday;
      TradeTuesday = InpTradeTuesday;
      TradeWednesday = InpTradeWednesday;
      TradeThursday = InpTradeThursday;
      TradeFriday = InpTradeFriday;
      TradeSaturday = InpTradeSaturday;
      TradeSunday = InpTradeSunday;
      RolloverEnabled = InpRolloverEnabled;
      RolloverTime = InpRolloverTime;
      RolloverMinsBefore = InpRolloverMinsBefore;
      RolloverMinsAfter = InpRolloverMinsAfter;
      GmtMode = InpGmtMode;
      GmtOffsetHours = InpGmtOffsetHours;
      GmtUseUsDst = InpGmtUseUsDst;
      ConsecEnabled = InpConsecEnabled;
      ConsecMaxLosses = InpConsecMaxLosses;
      ConsecCooldownMin = InpConsecCooldownMin;
      ConsecScope = InpConsecScope;
      MaxDeviationPts = InpMaxDeviationPts;
      AutoDeviationSpreadMult = InpAutoDeviationSpreadMult;
      MaxRetries = InpMaxRetries;
      RetryDelayMs = InpRetryDelayMs;
      RetryMaxDriftAtr = InpRetryMaxDriftAtr;
      FatalErrorCooldownSec = InpFatalErrorCooldownSec;
      ExecQualityAction = InpExecQualityAction;
      ExecQualityWindow = InpExecQualityWindow;
      MaxAvgSlippageSpreadMult = InpMaxAvgSlippageSpreadMult;
      MaxAvgLatencyMs = InpMaxAvgLatencyMs;
      ExecQualityCooldownSec = InpExecQualityCooldownSec;
      ExecQualityLotFactor = InpExecQualityLotFactor;
      MiGuard = InpMiGuard;
      MiDupWindowSec = InpMiDupWindowSec;
      ExposureMode = InpExposureMode;
      ExposureFamilyOnly = InpExposureFamilyOnly;
      MaxAccountRiskPct = InpMaxAccountRiskPct;
      MaxCurrencyRiskPct = InpMaxCurrencyRiskPct;
      CorrBars = InpCorrBars;
      MaxCorrRiskPct = InpMaxCorrRiskPct;
      StateEnabled = InpStateEnabled;
      RestartGraceSec = InpRestartGraceSec;
      LogLevel = InpLogLevel;
      LogToJournal = InpLogToJournal;
      LogToFile = InpLogToFile;
      LogCsv = InpLogCsv;
      LogCommon = InpLogCommon;
      LogSignals = InpLogSignals;
      LogThrottleMs = InpLogThrottleMs;
      LogInOptimization = InpLogInOptimization;
      StatsEveryMin = InpStatsEveryMin;
      ShowPanel = InpShowPanel;
      PanelCorner = InpPanelCorner;
      PanelX = InpPanelX;
      PanelY = InpPanelY;
      PanelFontSize = InpPanelFontSize;
      PanelDark = InpPanelDark;
      PanelRefreshMs = InpPanelRefreshMs;
      DrawTrades = InpDrawTrades;
      DrawZones = InpDrawZones;
      DrawRejected = InpDrawRejected;
      MaxChartObjects = InpMaxChartObjects;
      KeepObjectsOnExit = InpKeepObjectsOnExit;
      OptCriterion = InpOptCriterion;
      OptMinTrades = InpOptMinTrades;
      StressExtraSpreadPts = InpStressExtraSpreadPts;
      StressCommissionPerLot = InpStressCommissionPerLot;
     }

   //--- range checks generated from the spec + cross checks. Returns false on blocking errors.
   bool Validate(string &errors)
     {
      errors="";
      bool ok=true;
      if(InstanceId<1) { errors+="InstanceId ('Instance ID (1-999, unique per chart on one account)') below 1; "; ok=false; }
      if(InstanceId>999) { errors+="InstanceId ('Instance ID (1-999, unique per chart on one account)') above 999; "; ok=false; }
      if(MagicBase<0) { errors+="MagicBase ('Magic number base (magic = base + ID x 10 + engine)') below 0; "; ok=false; }
      if(TimerMs<50) { errors+="TimerMs ('Internal timer period (ms)') below 50; "; ok=false; }
      if(TimerMs>5000) { errors+="TimerMs ('Internal timer period (ms)') above 5000; "; ok=false; }
      if(DelaySpeedMs<0) { errors+="DelaySpeedMs ('SPEED mode entry delay (ms)') below 0; "; ok=false; }
      if(DelayAggressiveMs<0) { errors+="DelayAggressiveMs ('AGGRESSIVE mode entry delay (ms)') below 0; "; ok=false; }
      if(DelayUltraMs<0) { errors+="DelayUltraMs ('ULTRA mode entry delay (ms)') below 0; "; ok=false; }
      if(MaxSpreadPtsSpeed<0) { errors+="MaxSpreadPtsSpeed ('Max spread SPEED (points, 0 = auto)') below 0; "; ok=false; }
      if(MaxSpreadPtsAggressive<0) { errors+="MaxSpreadPtsAggressive ('Max spread AGGRESSIVE (points, 0 = auto)') below 0; "; ok=false; }
      if(MaxSpreadPtsUltra<0) { errors+="MaxSpreadPtsUltra ('Max spread ULTRA (points, 0 = auto)') below 0; "; ok=false; }
      if(AutoMaxSpreadAtr<0.0) { errors+="AutoMaxSpreadAtr ('Auto max spread (x ATR M1) when limit = 0') below 0.0; "; ok=false; }
      if(AtrPeriod<2) { errors+="AtrPeriod ('ATR period (M1 / M5)') below 2; "; ok=false; }
      if(AtrMedianBars<5) { errors+="AtrMedianBars ('ATR median length (M1 bars)') below 5; "; ok=false; }
      if(TickHistorySec<40) { errors+="TickHistorySec ('Tick history kept in memory (s)') below 40; "; ok=false; }
      if(MaxTickAgeSec<5) { errors+="MaxTickAgeSec ('Max tick age before market considered stale (s)') below 5; "; ok=false; }
      if(VolAnomalyAtrMult<0.0) { errors+="VolAnomalyAtrMult ('Volatility anomaly: ATR > x median ATR') below 0.0; "; ok=false; }
      if(VolAnomalyVelMult<0.0) { errors+="VolAnomalyVelMult ('Volatility anomaly: tick velocity > x median') below 0.0; "; ok=false; }
      if(VolAnomalySpreadMult<0.0) { errors+="VolAnomalySpreadMult ('Volatility anomaly: spread > x median spread') below 0.0; "; ok=false; }
      if(H1EmaFast<1) { errors+="H1EmaFast ('H1 fast EMA period') below 1; "; ok=false; }
      if(H1EmaSlow<2) { errors+="H1EmaSlow ('H1 slow EMA period') below 2; "; ok=false; }
      if(H1AdxPeriod<2) { errors+="H1AdxPeriod ('H1 ADX period') below 2; "; ok=false; }
      if(H1AdxThreshold<0.0) { errors+="H1AdxThreshold ('H1 ADX directional threshold') below 0.0; "; ok=false; }
      if(H1DiMinGap<0.0) { errors+="H1DiMinGap ('H1 min +DI/-DI gap') below 0.0; "; ok=false; }
      if(H1StrongAdx<0.0) { errors+="H1StrongAdx ('H1 'strong trend' ADX (Range STRICT)') below 0.0; "; ok=false; }
      if(MomTickWindow<5) { errors+="MomTickWindow ('Tick window for imbalance (ticks)') below 5; "; ok=false; }
      if(MomBuyRatio<0.5) { errors+="MomBuyRatio ('BUY: min bullish tick ratio') below 0.5; "; ok=false; }
      if(MomBuyRatio>1.0) { errors+="MomBuyRatio ('BUY: min bullish tick ratio') above 1.0; "; ok=false; }
      if(MomSellRatio<0.0) { errors+="MomSellRatio ('SELL: max bullish tick ratio') below 0.0; "; ok=false; }
      if(MomSellRatio>0.5) { errors+="MomSellRatio ('SELL: max bullish tick ratio') above 0.5; "; ok=false; }
      if(MomVelWindowMs<200) { errors+="MomVelWindowMs ('Velocity window (ms)') below 200; "; ok=false; }
      if(MomVelRefMs<2000) { errors+="MomVelRefMs ('Velocity reference window for median (ms)') below 2000; "; ok=false; }
      if(MomVelRatio<0.0) { errors+="MomVelRatio ('Min velocity / median velocity') below 0.0; "; ok=false; }
      if(MomAccelMin<-1.0) { errors+="MomAccelMin ('Min acceleration (0.20 = +20%)') below -1.0; "; ok=false; }
      if(MomMicroRangeTicks<3) { errors+="MomMicroRangeTicks ('Micro-range length (ticks)') below 3; "; ok=false; }
      if(MomBufSpreadMult<0.0) { errors+="MomBufSpreadMult ('Breakout buffer (x spread)') below 0.0; "; ok=false; }
      if(MomBufAtrMult<0.0) { errors+="MomBufAtrMult ('Breakout buffer (x ATR M1)') below 0.0; "; ok=false; }
      if(MomRocPeriod<1) { errors+="MomRocPeriod ('ROC period (M1 bars)') below 1; "; ok=false; }
      if(MomRocMin<0.0) { errors+="MomRocMin ('Min |ROC| (%)') below 0.0; "; ok=false; }
      if(MomEmaFast<1) { errors+="MomEmaFast ('M1 fast EMA period') below 1; "; ok=false; }
      if(MomEmaSlow<2) { errors+="MomEmaSlow ('M1 slow EMA period') below 2; "; ok=false; }
      if(MomAdxMin<0.0) { errors+="MomAdxMin ('M1 ADX min') below 0.0; "; ok=false; }
      if(MomTpSpreadMult<0.0) { errors+="MomTpSpreadMult ('TP = max(x spread, ...)') below 0.0; "; ok=false; }
      if(MomTpAtrMult<0.0) { errors+="MomTpAtrMult ('TP = max(..., x ATR M1)') below 0.0; "; ok=false; }
      if(MomSlSpreadMult<0.0) { errors+="MomSlSpreadMult ('SL = max(x spread, ...)') below 0.0; "; ok=false; }
      if(MomSlAtrMult<0.0) { errors+="MomSlAtrMult ('SL = max(..., x ATR M1)') below 0.0; "; ok=false; }
      if(MomSignalTtlMs<50) { errors+="MomSignalTtlMs ('Signal validity (ms)') below 50; "; ok=false; }
      if(MomExitScore<0.0) { errors+="MomExitScore ('Exit when momentum score below') below 0.0; "; ok=false; }
      if(MomExitScore>100.0) { errors+="MomExitScore ('Exit when momentum score below') above 100.0; "; ok=false; }
      if(MomExitInversionMs<0) { errors+="MomExitInversionMs ('Tick inversion persistence (ms)') below 0; "; ok=false; }
      if(MomExitTicks<3) { errors+="MomExitTicks ('Inversion window (ticks)') below 3; "; ok=false; }
      if(MomTimeStopSec<0) { errors+="MomTimeStopSec ('Time-stop (s, 0 = off)') below 0; "; ok=false; }
      if(MomMaxPositions<0) { errors+="MomMaxPositions ('Max simultaneous positions (Momentum)') below 0; "; ok=false; }
      if(MomMaxPositions>50) { errors+="MomMaxPositions ('Max simultaneous positions (Momentum)') above 50; "; ok=false; }
      if(MomBeTriggerPct<0.0) { errors+="MomBeTriggerPct ('Break-even trigger (% of TP distance)') below 0.0; "; ok=false; }
      if(MomBeLockPct<0.0) { errors+="MomBeLockPct ('Break-even lock (% of TP distance)') below 0.0; "; ok=false; }
      if(MomTrailTriggerPct<0.0) { errors+="MomTrailTriggerPct ('Trailing trigger (% of TP distance)') below 0.0; "; ok=false; }
      if(MomTrailDistPct<1.0) { errors+="MomTrailDistPct ('Trailing distance (% of TP distance)') below 1.0; "; ok=false; }
      if(MomTrailStepPct<0.0) { errors+="MomTrailStepPct ('Trailing min step (% of TP distance)') below 0.0; "; ok=false; }
      if(FvgScanBars<5) { errors+="FvgScanBars ('Bars scanned for FVGs') below 5; "; ok=false; }
      if(FvgMaxZones<1) { errors+="FvgMaxZones ('Max zones kept') below 1; "; ok=false; }
      if(FvgMaxZones>100) { errors+="FvgMaxZones ('Max zones kept') above 100; "; ok=false; }
      if(FvgMinGapAtr<0.0) { errors+="FvgMinGapAtr ('Min gap size (x ATR of FVG timeframe)') below 0.0; "; ok=false; }
      if(FvgMinGapSpreadMult<0.0) { errors+="FvgMinGapSpreadMult ('Min gap size (x spread)') below 0.0; "; ok=false; }
      if(FvgMaxAgeBars<1) { errors+="FvgMaxAgeBars ('Max zone age (bars)') below 1; "; ok=false; }
      if(FvgMaxMitigations<1) { errors+="FvgMaxMitigations ('Max mitigations (returns into zone)') below 1; "; ok=false; }
      if(FvgMaxDistanceAtr<0.0) { errors+="FvgMaxDistanceAtr ('Max price distance to zone (x ATR)') below 0.0; "; ok=false; }
      if(FvgRejectWickPct<0.0) { errors+="FvgRejectWickPct ('REJECTION: min wick (% of candle range)') below 0.0; "; ok=false; }
      if(FvgRejectWickPct>100.0) { errors+="FvgRejectWickPct ('REJECTION: min wick (% of candle range)') above 100.0; "; ok=false; }
      if(StructSwingBars<1) { errors+="StructSwingBars ('Swing strength (bars each side)') below 1; "; ok=false; }
      if(StructLookbackBars<10) { errors+="StructLookbackBars ('Structure lookback (bars)') below 10; "; ok=false; }
      if(FvgInvalidBufAtr<0.0) { errors+="FvgInvalidBufAtr ('Invalidation buffer (x ATR)') below 0.0; "; ok=false; }
      if(FvgSlBufSpreadMult<0.0) { errors+="FvgSlBufSpreadMult ('SL buffer (x spread)') below 0.0; "; ok=false; }
      if(FvgSlBufAtr<0.0) { errors+="FvgSlBufAtr ('SL buffer (x ATR)') below 0.0; "; ok=false; }
      if(FvgTpAtrMult<0.0) { errors+="FvgTpAtrMult ('TP ATR multiple') below 0.0; "; ok=false; }
      if(FvgTpRR<0.1) { errors+="FvgTpRR ('TP R multiple') below 0.1; "; ok=false; }
      if(FvgTpMinRR<0.0) { errors+="FvgTpMinRR ('TP min R (liquidity mode)') below 0.0; "; ok=false; }
      if(FvgTpMaxRR<0.1) { errors+="FvgTpMaxRR ('TP max R (liquidity mode)') below 0.1; "; ok=false; }
      if(FvgMaxTradesPerZone<1) { errors+="FvgMaxTradesPerZone ('Max trades per zone') below 1; "; ok=false; }
      if(FvgMaxTradesPerZone>3) { errors+="FvgMaxTradesPerZone ('Max trades per zone') above 3; "; ok=false; }
      if(FvgSignalTtlMs<50) { errors+="FvgSignalTtlMs ('Signal validity (ms)') below 50; "; ok=false; }
      if(FvgTimeStopSec<0) { errors+="FvgTimeStopSec ('Time-stop (s, 0 = off)') below 0; "; ok=false; }
      if(FvgMaxPositions<0) { errors+="FvgMaxPositions ('Max simultaneous positions (FVG)') below 0; "; ok=false; }
      if(FvgMaxPositions>50) { errors+="FvgMaxPositions ('Max simultaneous positions (FVG)') above 50; "; ok=false; }
      if(FvgBeTriggerPct<0.0) { errors+="FvgBeTriggerPct ('Break-even trigger (% of TP distance)') below 0.0; "; ok=false; }
      if(FvgBeLockPct<0.0) { errors+="FvgBeLockPct ('Break-even lock (% of TP distance)') below 0.0; "; ok=false; }
      if(FvgTrailTriggerPct<0.0) { errors+="FvgTrailTriggerPct ('Trailing trigger (% of TP distance)') below 0.0; "; ok=false; }
      if(FvgTrailDistPct<1.0) { errors+="FvgTrailDistPct ('Trailing distance (% of TP distance)') below 1.0; "; ok=false; }
      if(FvgTrailStepPct<0.0) { errors+="FvgTrailStepPct ('Trailing min step (% of TP distance)') below 0.0; "; ok=false; }
      if(RngLookbackBars<5) { errors+="RngLookbackBars ('Range lookback (bars)') below 5; "; ok=false; }
      if(RngAdxPeriod<2) { errors+="RngAdxPeriod ('ADX period') below 2; "; ok=false; }
      if(RngAdxMax<0.0) { errors+="RngAdxMax ('Max ADX for a range') below 0.0; "; ok=false; }
      if(RngAdxSlopeBars<1) { errors+="RngAdxSlopeBars ('ADX slope bars') below 1; "; ok=false; }
      if(RngEmaFast<1) { errors+="RngEmaFast ('Fast EMA period') below 1; "; ok=false; }
      if(RngEmaSlow<2) { errors+="RngEmaSlow ('Slow EMA period') below 2; "; ok=false; }
      if(RngEmaSepMaxAtr<0.0) { errors+="RngEmaSepMaxAtr ('Max |EMA20-EMA50| (x ATR)') below 0.0; "; ok=false; }
      if(RngMinWidthAtr<0.0) { errors+="RngMinWidthAtr ('Min range width (x ATR)') below 0.0; "; ok=false; }
      if(RngMinWidthSpreadMult<0.0) { errors+="RngMinWidthSpreadMult ('Min range width (x spread)') below 0.0; "; ok=false; }
      if(RngMaxWidthAtr<0.0) { errors+="RngMaxWidthAtr ('Max range width (x ATR)') below 0.0; "; ok=false; }
      if(RngMaxDriftPct<0.0) { errors+="RngMaxDriftPct ('Max net drift (% of width)') below 0.0; "; ok=false; }
      if(RngMaxDriftPct>100.0) { errors+="RngMaxDriftPct ('Max net drift (% of width)') above 100.0; "; ok=false; }
      if(RngMinTouchesPerSide<1) { errors+="RngMinTouchesPerSide ('Min touches per boundary') below 1; "; ok=false; }
      if(RngEdgeZonePct<1.0) { errors+="RngEdgeZonePct ('Entry zone near boundary (% of width)') below 1.0; "; ok=false; }
      if(RngEdgeZonePct>49.0) { errors+="RngEdgeZonePct ('Entry zone near boundary (% of width)') above 49.0; "; ok=false; }
      if(RngRejectWickPct<0.0) { errors+="RngRejectWickPct ('Rejection: min wick (% of candle range)') below 0.0; "; ok=false; }
      if(RngRejectWickPct>100.0) { errors+="RngRejectWickPct ('Rejection: min wick (% of candle range)') above 100.0; "; ok=false; }
      if(RngTickWindow<5) { errors+="RngTickWindow ('Tick window for buyer/seller return (ticks)') below 5; "; ok=false; }
      if(RngTickRatioMin<0.5) { errors+="RngTickRatioMin ('Min returning tick ratio') below 0.5; "; ok=false; }
      if(RngTickRatioMin>1.0) { errors+="RngTickRatioMin ('Min returning tick ratio') above 1.0; "; ok=false; }
      if(RngMaxVelRatio<0.0) { errors+="RngMaxVelRatio ('Max tick velocity ratio (impulse protection)') below 0.0; "; ok=false; }
      if(RngMaxAtrExpansion<0.0) { errors+="RngMaxAtrExpansion ('Max ATR / median ATR') below 0.0; "; ok=false; }
      if(RngSlBufSpreadMult<0.0) { errors+="RngSlBufSpreadMult ('SL buffer beyond boundary (x spread)') below 0.0; "; ok=false; }
      if(RngSlBufAtr<0.0) { errors+="RngSlBufAtr ('SL buffer beyond boundary (x ATR)') below 0.0; "; ok=false; }
      if(RngTpOffsetPct<0.0) { errors+="RngTpOffsetPct ('TP offset before target (% of width)') below 0.0; "; ok=false; }
      if(RngTpOffsetPct>40.0) { errors+="RngTpOffsetPct ('TP offset before target (% of width)') above 40.0; "; ok=false; }
      if(RngBreakBufAtr<0.0) { errors+="RngBreakBufAtr ('Breakout confirmation buffer (x ATR)') below 0.0; "; ok=false; }
      if(RngMaxTradesPerTouch<1) { errors+="RngMaxTradesPerTouch ('Max trades per boundary touch') below 1; "; ok=false; }
      if(RngMaxTradesPerTouch>3) { errors+="RngMaxTradesPerTouch ('Max trades per boundary touch') above 3; "; ok=false; }
      if(RngSignalTtlMs<50) { errors+="RngSignalTtlMs ('Signal validity (ms)') below 50; "; ok=false; }
      if(RngTimeStopSec<0) { errors+="RngTimeStopSec ('Time-stop (s, 0 = off)') below 0; "; ok=false; }
      if(RngMaxPositions<0) { errors+="RngMaxPositions ('Max simultaneous positions (Range)') below 0; "; ok=false; }
      if(RngMaxPositions>50) { errors+="RngMaxPositions ('Max simultaneous positions (Range)') above 50; "; ok=false; }
      if(RngBeTriggerPct<0.0) { errors+="RngBeTriggerPct ('Break-even trigger (% of TP distance)') below 0.0; "; ok=false; }
      if(RngBeLockPct<0.0) { errors+="RngBeLockPct ('Break-even lock (% of TP distance)') below 0.0; "; ok=false; }
      if(RngTrailTriggerPct<0.0) { errors+="RngTrailTriggerPct ('Trailing trigger (% of TP distance)') below 0.0; "; ok=false; }
      if(RngTrailDistPct<1.0) { errors+="RngTrailDistPct ('Trailing distance (% of TP distance)') below 1.0; "; ok=false; }
      if(RngTrailStepPct<0.0) { errors+="RngTrailStepPct ('Trailing min step (% of TP distance)') below 0.0; "; ok=false; }
      if(MaxPositionsSymbol<1) { errors+="MaxPositionsSymbol ('Max total positions on this symbol (this instance)') below 1; "; ok=false; }
      if(MaxPositionsSymbol>150) { errors+="MaxPositionsSymbol ('Max total positions on this symbol (this instance)') above 150; "; ok=false; }
      if(ConflictWindowMs<0) { errors+="ConflictWindowMs ('Opposite-signal conflict window (ms)') below 0; "; ok=false; }
      if(ConflictHoldMs<0) { errors+="ConflictHoldMs ('Entry block after a conflict (ms)') below 0; "; ok=false; }
      if(DupMinDistAtr<0.0) { errors+="DupMinDistAtr ('Min distance between same-engine entries (x ATR M1)') below 0.0; "; ok=false; }
      if(MinEntrySpacingMs<0) { errors+="MinEntrySpacingMs ('Min time between any two entries (ms, 0 = off)') below 0; "; ok=false; }
      if(HardMaxHoldSec<0) { errors+="HardMaxHoldSec ('Hard max holding time, all engines (s, 0 = off)') below 0; "; ok=false; }
      if(MinModifyIntervalMs<0) { errors+="MinModifyIntervalMs ('Min interval between SL modifications (ms)') below 0; "; ok=false; }
      if(FixedLot<0.0) { errors+="FixedLot ('Fixed lot') below 0.0; "; ok=false; }
      if(RiskPercent<0.0) { errors+="RiskPercent ('Risk per trade (%)') below 0.0; "; ok=false; }
      if(MaxRiskPercent<0.0) { errors+="MaxRiskPercent ('Max risk per trade - hard cap (%)') below 0.0; "; ok=false; }
      if(MaxLotPerTrade<0.0) { errors+="MaxLotPerTrade ('Max lot per trade (0 = broker max)') below 0.0; "; ok=false; }
      if(MaxOpenRiskPct<0.0) { errors+="MaxOpenRiskPct ('Max total open risk, this instance (%)') below 0.0; "; ok=false; }
      if(MaxTotalLots<0.0) { errors+="MaxTotalLots ('Max total open lots, this instance (0 = off)') below 0.0; "; ok=false; }
      if(MaxSlTpRatio<0.0) { errors+="MaxSlTpRatio ('SL/TP ratio guard (max SL / TP, 0 = off)') below 0.0; "; ok=false; }
      if(MartingaleMult<1.0) { errors+="MartingaleMult ('Martingale multiplier') below 1.0; "; ok=false; }
      if(MartingaleMaxSteps<0) { errors+="MartingaleMaxSteps ('Martingale max steps') below 0; "; ok=false; }
      if(DdPausePct<0.1) { errors+="DdPausePct ('Drawdown threshold (%)') below 0.1; "; ok=false; }
      if(DdPauseSec<1) { errors+="DdPauseSec ('Pause length (s)') below 1; "; ok=false; }
      if(NewsMinsBefore<0) { errors+="NewsMinsBefore ('Block minutes BEFORE news') below 0; "; ok=false; }
      if(NewsMinsAfter<0) { errors+="NewsMinsAfter ('Block minutes AFTER news') below 0; "; ok=false; }
      if(NewsRefreshMin<1) { errors+="NewsRefreshMin ('News refresh interval (min)') below 1; "; ok=false; }
      if(RolloverMinsBefore<0) { errors+="RolloverMinsBefore ('Block minutes BEFORE rollover') below 0; "; ok=false; }
      if(RolloverMinsAfter<0) { errors+="RolloverMinsAfter ('Block minutes AFTER rollover') below 0; "; ok=false; }
      if(GmtOffsetHours<-12) { errors+="GmtOffsetHours ('Manual broker GMT offset (winter, hours)') below -12; "; ok=false; }
      if(GmtOffsetHours>14) { errors+="GmtOffsetHours ('Manual broker GMT offset (winter, hours)') above 14; "; ok=false; }
      if(ConsecMaxLosses<1) { errors+="ConsecMaxLosses ('Consecutive losses X') below 1; "; ok=false; }
      if(ConsecCooldownMin<1) { errors+="ConsecCooldownMin ('Cooldown Y (minutes)') below 1; "; ok=false; }
      if(MaxDeviationPts<0) { errors+="MaxDeviationPts ('Max slippage / deviation (points, 0 = auto)') below 0; "; ok=false; }
      if(AutoDeviationSpreadMult<0.1) { errors+="AutoDeviationSpreadMult ('Auto deviation (x spread)') below 0.1; "; ok=false; }
      if(MaxRetries<0) { errors+="MaxRetries ('Max retries per order') below 0; "; ok=false; }
      if(MaxRetries>10) { errors+="MaxRetries ('Max retries per order') above 10; "; ok=false; }
      if(RetryDelayMs<0) { errors+="RetryDelayMs ('Delay between retries (ms)') below 0; "; ok=false; }
      if(RetryMaxDriftAtr<0.0) { errors+="RetryMaxDriftAtr ('Max price drift before a retry (x ATR M1)') below 0.0; "; ok=false; }
      if(FatalErrorCooldownSec<0) { errors+="FatalErrorCooldownSec ('Pause after a permanent broker error (s)') below 0; "; ok=false; }
      if(ExecQualityWindow<3) { errors+="ExecQualityWindow ('Execution-quality window (trades)') below 3; "; ok=false; }
      if(MaxAvgSlippageSpreadMult<0.0) { errors+="MaxAvgSlippageSpreadMult ('Max avg adverse slippage (x avg spread, 0 = off)') below 0.0; "; ok=false; }
      if(MaxAvgLatencyMs<0) { errors+="MaxAvgLatencyMs ('Max avg order latency (ms, 0 = off)') below 0; "; ok=false; }
      if(ExecQualityCooldownSec<0) { errors+="ExecQualityCooldownSec ('Execution-quality cooldown (s)') below 0; "; ok=false; }
      if(ExecQualityLotFactor<0.01) { errors+="ExecQualityLotFactor ('Lot factor when quality is poor') below 0.01; "; ok=false; }
      if(ExecQualityLotFactor>1.0) { errors+="ExecQualityLotFactor ('Lot factor when quality is poor') above 1.0; "; ok=false; }
      if(MiDupWindowSec<1) { errors+="MiDupWindowSec ('Cross-instance duplicate window (s)') below 1; "; ok=false; }
      if(MaxAccountRiskPct<0.0) { errors+="MaxAccountRiskPct ('Max open risk all symbols (% equity)') below 0.0; "; ok=false; }
      if(MaxCurrencyRiskPct<0.0) { errors+="MaxCurrencyRiskPct ('Max net risk per currency, e.g. USD (% equity)') below 0.0; "; ok=false; }
      if(CorrBars<20) { errors+="CorrBars ('Correlation lookback (M5 bars)') below 20; "; ok=false; }
      if(MaxCorrRiskPct<0.0) { errors+="MaxCorrRiskPct ('Max correlation-adjusted risk (% equity)') below 0.0; "; ok=false; }
      if(RestartGraceSec<0) { errors+="RestartGraceSec ('No new entries after start (s)') below 0; "; ok=false; }
      if(LogThrottleMs<0) { errors+="LogThrottleMs ('Throttle repeated messages (ms)') below 0; "; ok=false; }
      if(StatsEveryMin<1) { errors+="StatsEveryMin ('Write stats summary every (min)') below 1; "; ok=false; }
      if(PanelX<0) { errors+="PanelX ('Panel X offset (px)') below 0; "; ok=false; }
      if(PanelY<0) { errors+="PanelY ('Panel Y offset (px)') below 0; "; ok=false; }
      if(PanelFontSize<6) { errors+="PanelFontSize ('Panel font size') below 6; "; ok=false; }
      if(PanelFontSize>20) { errors+="PanelFontSize ('Panel font size') above 20; "; ok=false; }
      if(PanelRefreshMs<50) { errors+="PanelRefreshMs ('Panel refresh (ms)') below 50; "; ok=false; }
      if(MaxChartObjects<50) { errors+="MaxChartObjects ('Max chart objects') below 50; "; ok=false; }
      if(OptMinTrades<0) { errors+="OptMinTrades ('Min trades for a valid pass') below 0; "; ok=false; }
      if(StressExtraSpreadPts<0) { errors+="StressExtraSpreadPts ('Stress: extra spread (points)') below 0; "; ok=false; }
      if(StressCommissionPerLot<0.0) { errors+="StressCommissionPerLot ('Stress: extra commission per lot (money)') below 0.0; "; ok=false; }
      if(H1EmaFast>=H1EmaSlow)    { errors+="H1 fast EMA must be < slow EMA; "; ok=false; }
      if(MomEmaFast>=MomEmaSlow)  { errors+="M1 fast EMA must be < slow EMA; "; ok=false; }
      if(RngEmaFast>=RngEmaSlow)  { errors+="Range fast EMA must be < slow EMA; "; ok=false; }
      if(MomVelRefMs<2*MomVelWindowMs) { errors+="Velocity reference window must be >= 2 x velocity window; "; ok=false; }
      if((long)TickHistorySec*1000<(long)MomVelRefMs+2*(long)MomVelWindowMs) { errors+="Tick history too short for the velocity reference window; "; ok=false; }
      if(FvgTpMinRR>FvgTpMaxRR)   { errors+="FVG TP min R must be <= max R; "; ok=false; }
      if(MomMicroRangeTicks>=MomTickWindow*4) { errors+="Micro-range ticks unusually large versus tick window; "; }
      if(RiskMode!=FTF_RISK_FIXED_LOT && RiskPercent>MaxRiskPercent && MaxRiskPercent>0.0) { errors+="Risk per trade above hard cap - hard cap will apply; "; }
      if(MaxPositionsSymbol<MomMaxPositions || MaxPositionsSymbol<FvgMaxPositions || MaxPositionsSymbol<RngMaxPositions) { errors+="Symbol max positions lower than an engine max - symbol limit wins; "; }
      return ok;
     }

   //--- human readable dump of the effective configuration (written to the log at start)
   int DumpLines(string &lines[])
     {
      ArrayResize(lines,256);
      int n=0;
      lines[n++]="[GEN] Enable new entries (master switch) = "+(EnableTrading ? "true" : "false");
      lines[n++]="[GEN] Trading mode (SPEED / AGGRESSIVE / ULTRA) = "+EnumToString(TradingMode);
      lines[n++]="[GEN] Instance ID (1-999, unique per chart on one account) = "+IntegerToString(InstanceId);
      lines[n++]="[GEN] Magic number base (magic = base + ID x 10 + engine) = "+IntegerToString(MagicBase);
      lines[n++]="[GEN] Order comment prefix = "+CommentPrefix;
      lines[n++]="[GEN] Supported-symbol check (EURUSD/XAUUSD/BTCUSD) = "+EnumToString(SymbolCheck);
      lines[n++]="[GEN] Internal timer period (ms) = "+IntegerToString(TimerMs);
      lines[n++]="[ENG] Engine A - Momentum / Micro-breakout ON = "+(MomEnabled ? "true" : "false");
      lines[n++]="[ENG] Engine B - FVG (Fair Value Gap) ON = "+(FvgEnabled ? "true" : "false");
      lines[n++]="[ENG] Engine C - Range / Mean Reversion ON = "+(RngEnabled ? "true" : "false");
      lines[n++]="[MODE] SPEED mode entry delay (ms) = "+IntegerToString(DelaySpeedMs);
      lines[n++]="[MODE] AGGRESSIVE mode entry delay (ms) = "+IntegerToString(DelayAggressiveMs);
      lines[n++]="[MODE] ULTRA mode entry delay (ms) = "+IntegerToString(DelayUltraMs);
      lines[n++]="[MODE] How the mode delay is applied = "+EnumToString(DelayUsage);
      lines[n++]="[MODE] Max spread SPEED (points, 0 = auto) = "+IntegerToString(MaxSpreadPtsSpeed);
      lines[n++]="[MODE] Max spread AGGRESSIVE (points, 0 = auto) = "+IntegerToString(MaxSpreadPtsAggressive);
      lines[n++]="[MODE] Max spread ULTRA (points, 0 = auto) = "+IntegerToString(MaxSpreadPtsUltra);
      lines[n++]="[MODE] Auto max spread (x ATR M1) when limit = 0 = "+DoubleToString(AutoMaxSpreadAtr,4);
      lines[n++]="[MD] ATR period (M1 / M5) = "+IntegerToString(AtrPeriod);
      lines[n++]="[MD] ATR median length (M1 bars) = "+IntegerToString(AtrMedianBars);
      lines[n++]="[MD] Tick history kept in memory (s) = "+IntegerToString(TickHistorySec);
      lines[n++]="[MD] Max tick age before market considered stale (s) = "+IntegerToString(MaxTickAgeSec);
      lines[n++]="[MD] Volatility anomaly: ATR > x median ATR = "+DoubleToString(VolAnomalyAtrMult,4);
      lines[n++]="[MD] Volatility anomaly: tick velocity > x median = "+DoubleToString(VolAnomalyVelMult,4);
      lines[n++]="[MD] Volatility anomaly: spread > x median spread = "+DoubleToString(VolAnomalySpreadMult,4);
      lines[n++]="[H1] H1_FILTER mode = "+EnumToString(H1Filter);
      lines[n++]="[H1] H1 fast EMA period = "+IntegerToString(H1EmaFast);
      lines[n++]="[H1] H1 slow EMA period = "+IntegerToString(H1EmaSlow);
      lines[n++]="[H1] H1 ADX period = "+IntegerToString(H1AdxPeriod);
      lines[n++]="[H1] H1 ADX directional threshold = "+DoubleToString(H1AdxThreshold,4);
      lines[n++]="[H1] H1 min +DI/-DI gap = "+DoubleToString(H1DiMinGap,4);
      lines[n++]="[H1] H1 'strong trend' ADX (Range STRICT) = "+DoubleToString(H1StrongAdx,4);
      lines[n++]="[H1] STRICT applies to Momentum = "+(H1StrictMomentum ? "true" : "false");
      lines[n++]="[H1] STRICT applies to FVG = "+(H1StrictFvg ? "true" : "false");
      lines[n++]="[H1] STRICT applies to Range = "+(H1StrictRange ? "true" : "false");
      lines[n++]="[MOM] Tick window for imbalance (ticks) = "+IntegerToString(MomTickWindow);
      lines[n++]="[MOM] BUY: min bullish tick ratio = "+DoubleToString(MomBuyRatio,4);
      lines[n++]="[MOM] SELL ratio = 1 - BUY ratio (symmetric) = "+(MomSymmetric ? "true" : "false");
      lines[n++]="[MOM] SELL: max bullish tick ratio = "+DoubleToString(MomSellRatio,4);
      lines[n++]="[MOM] Count unchanged ticks in the ratio = "+(MomCountFlatTicks ? "true" : "false");
      lines[n++]="[MOM] Velocity metric = "+EnumToString(MomVelMetric);
      lines[n++]="[MOM] Velocity window (ms) = "+IntegerToString(MomVelWindowMs);
      lines[n++]="[MOM] Velocity reference window for median (ms) = "+IntegerToString(MomVelRefMs);
      lines[n++]="[MOM] Min velocity / median velocity = "+DoubleToString(MomVelRatio,4);
      lines[n++]="[MOM] Min acceleration (0.20 = +20%) = "+DoubleToString(MomAccelMin,4);
      lines[n++]="[MOM] Micro-range length (ticks) = "+IntegerToString(MomMicroRangeTicks);
      lines[n++]="[MOM] Breakout buffer (x spread) = "+DoubleToString(MomBufSpreadMult,4);
      lines[n++]="[MOM] Breakout buffer (x ATR M1) = "+DoubleToString(MomBufAtrMult,4);
      lines[n++]="[MOM] Confirm with ROC direction = "+(MomUseRoc ? "true" : "false");
      lines[n++]="[MOM] ROC period (M1 bars) = "+IntegerToString(MomRocPeriod);
      lines[n++]="[MOM] Min |ROC| (%) = "+DoubleToString(MomRocMin,4);
      lines[n++]="[MOM] Confirm with M1 EMA fast/slow = "+(MomUseEma ? "true" : "false");
      lines[n++]="[MOM] M1 fast EMA period = "+IntegerToString(MomEmaFast);
      lines[n++]="[MOM] M1 slow EMA period = "+IntegerToString(MomEmaSlow);
      lines[n++]="[MOM] Confirm with M1 ADX/DI = "+(MomUseAdx ? "true" : "false");
      lines[n++]="[MOM] M1 ADX min = "+DoubleToString(MomAdxMin,4);
      lines[n++]="[MOM] M5 EMA20/50 context = "+EnumToString(MomM5Context);
      lines[n++]="[MOM] TP = max(x spread, ...) = "+DoubleToString(MomTpSpreadMult,4);
      lines[n++]="[MOM] TP = max(..., x ATR M1) = "+DoubleToString(MomTpAtrMult,4);
      lines[n++]="[MOM] SL = max(x spread, ...) = "+DoubleToString(MomSlSpreadMult,4);
      lines[n++]="[MOM] SL = max(..., x ATR M1) = "+DoubleToString(MomSlAtrMult,4);
      lines[n++]="[MOM] Signal validity (ms) = "+IntegerToString(MomSignalTtlMs);
      lines[n++]="[MOM] Momentum-loss exit ON = "+(MomExitEnabled ? "true" : "false");
      lines[n++]="[MOM] Exit when momentum score below = "+DoubleToString(MomExitScore,4);
      lines[n++]="[MOM] Tick inversion persistence (ms) = "+IntegerToString(MomExitInversionMs);
      lines[n++]="[MOM] Inversion window (ticks) = "+IntegerToString(MomExitTicks);
      lines[n++]="[MOM] Time-stop (s, 0 = off) = "+IntegerToString(MomTimeStopSec);
      lines[n++]="[MOM] Max simultaneous positions (Momentum) = "+IntegerToString(MomMaxPositions);
      lines[n++]="[MOM] Break-even trigger (% of TP distance) = "+DoubleToString(MomBeTriggerPct,4);
      lines[n++]="[MOM] Break-even lock (% of TP distance) = "+DoubleToString(MomBeLockPct,4);
      lines[n++]="[MOM] Trailing trigger (% of TP distance) = "+DoubleToString(MomTrailTriggerPct,4);
      lines[n++]="[MOM] Trailing distance (% of TP distance) = "+DoubleToString(MomTrailDistPct,4);
      lines[n++]="[MOM] Trailing min step (% of TP distance) = "+DoubleToString(MomTrailStepPct,4);
      lines[n++]="[FVG] FVG timeframe = "+EnumToString(FvgTimeframe);
      lines[n++]="[FVG] Use M1 for entry precision = "+(FvgUseM1Refine ? "true" : "false");
      lines[n++]="[FVG] Bars scanned for FVGs = "+IntegerToString(FvgScanBars);
      lines[n++]="[FVG] Max zones kept = "+IntegerToString(FvgMaxZones);
      lines[n++]="[FVG] Min gap size (x ATR of FVG timeframe) = "+DoubleToString(FvgMinGapAtr,4);
      lines[n++]="[FVG] Min gap size (x spread) = "+DoubleToString(FvgMinGapSpreadMult,4);
      lines[n++]="[FVG] Max zone age (bars) = "+IntegerToString(FvgMaxAgeBars);
      lines[n++]="[FVG] Max mitigations (returns into zone) = "+IntegerToString(FvgMaxMitigations);
      lines[n++]="[FVG] Max price distance to zone (x ATR) = "+DoubleToString(FvgMaxDistanceAtr,4);
      lines[n++]="[FVG] Entry mode (TOUCH / CE 50% / REJECTION) = "+EnumToString(FvgEntryMode);
      lines[n++]="[FVG] REJECTION: min wick (% of candle range) = "+DoubleToString(FvgRejectWickPct,4);
      lines[n++]="[FVG] BOS_REQUIRED (structure confirmation) = "+(FvgBosRequired ? "true" : "false");
      lines[n++]="[FVG] Structure event accepted when required = "+EnumToString(FvgStructMode);
      lines[n++]="[FVG] Swing strength (bars each side) = "+IntegerToString(StructSwingBars);
      lines[n++]="[FVG] Structure lookback (bars) = "+IntegerToString(StructLookbackBars);
      lines[n++]="[FVG] Invalidation buffer (x ATR) = "+DoubleToString(FvgInvalidBufAtr,4);
      lines[n++]="[FVG] Invalidate on candle close (else on tick) = "+(FvgInvalidOnClose ? "true" : "false");
      lines[n++]="[FVG] SL anchor = "+EnumToString(FvgSlMode);
      lines[n++]="[FVG] SL buffer (x spread) = "+DoubleToString(FvgSlBufSpreadMult,4);
      lines[n++]="[FVG] SL buffer (x ATR) = "+DoubleToString(FvgSlBufAtr,4);
      lines[n++]="[FVG] TP mode = "+EnumToString(FvgTpMode);
      lines[n++]="[FVG] TP ATR multiple = "+DoubleToString(FvgTpAtrMult,4);
      lines[n++]="[FVG] TP R multiple = "+DoubleToString(FvgTpRR,4);
      lines[n++]="[FVG] TP min R (liquidity mode) = "+DoubleToString(FvgTpMinRR,4);
      lines[n++]="[FVG] TP max R (liquidity mode) = "+DoubleToString(FvgTpMaxRR,4);
      lines[n++]="[FVG] Max trades per zone = "+IntegerToString(FvgMaxTradesPerZone);
      lines[n++]="[FVG] Signal validity (ms) = "+IntegerToString(FvgSignalTtlMs);
      lines[n++]="[FVG] Exit open trade if zone invalidated = "+(FvgExitOnInvalidation ? "true" : "false");
      lines[n++]="[FVG] Time-stop (s, 0 = off) = "+IntegerToString(FvgTimeStopSec);
      lines[n++]="[FVG] Max simultaneous positions (FVG) = "+IntegerToString(FvgMaxPositions);
      lines[n++]="[FVG] Break-even trigger (% of TP distance) = "+DoubleToString(FvgBeTriggerPct,4);
      lines[n++]="[FVG] Break-even lock (% of TP distance) = "+DoubleToString(FvgBeLockPct,4);
      lines[n++]="[FVG] Trailing trigger (% of TP distance) = "+DoubleToString(FvgTrailTriggerPct,4);
      lines[n++]="[FVG] Trailing distance (% of TP distance) = "+DoubleToString(FvgTrailDistPct,4);
      lines[n++]="[FVG] Trailing min step (% of TP distance) = "+DoubleToString(FvgTrailStepPct,4);
      lines[n++]="[RNG] Range timeframe (M1 or M5) = "+EnumToString(RngTimeframe);
      lines[n++]="[RNG] Range lookback (bars) = "+IntegerToString(RngLookbackBars);
      lines[n++]="[RNG] ADX period = "+IntegerToString(RngAdxPeriod);
      lines[n++]="[RNG] Max ADX for a range = "+DoubleToString(RngAdxMax,4);
      lines[n++]="[RNG] Require falling ADX = "+(RngRequireAdxFalling ? "true" : "false");
      lines[n++]="[RNG] ADX slope bars = "+IntegerToString(RngAdxSlopeBars);
      lines[n++]="[RNG] Fast EMA period = "+IntegerToString(RngEmaFast);
      lines[n++]="[RNG] Slow EMA period = "+IntegerToString(RngEmaSlow);
      lines[n++]="[RNG] Max |EMA20-EMA50| (x ATR) = "+DoubleToString(RngEmaSepMaxAtr,4);
      lines[n++]="[RNG] Min range width (x ATR) = "+DoubleToString(RngMinWidthAtr,4);
      lines[n++]="[RNG] Min range width (x spread) = "+DoubleToString(RngMinWidthSpreadMult,4);
      lines[n++]="[RNG] Max range width (x ATR) = "+DoubleToString(RngMaxWidthAtr,4);
      lines[n++]="[RNG] Max net drift (% of width) = "+DoubleToString(RngMaxDriftPct,4);
      lines[n++]="[RNG] Min touches per boundary = "+IntegerToString(RngMinTouchesPerSide);
      lines[n++]="[RNG] Entry zone near boundary (% of width) = "+DoubleToString(RngEdgeZonePct,4);
      lines[n++]="[RNG] Edge confirmation (slowdown / rejection) = "+EnumToString(RngConfirmMode);
      lines[n++]="[RNG] Rejection: min wick (% of candle range) = "+DoubleToString(RngRejectWickPct,4);
      lines[n++]="[RNG] Tick window for buyer/seller return (ticks) = "+IntegerToString(RngTickWindow);
      lines[n++]="[RNG] Min returning tick ratio = "+DoubleToString(RngTickRatioMin,4);
      lines[n++]="[RNG] Max tick velocity ratio (impulse protection) = "+DoubleToString(RngMaxVelRatio,4);
      lines[n++]="[RNG] Max ATR / median ATR = "+DoubleToString(RngMaxAtrExpansion,4);
      lines[n++]="[RNG] SL buffer beyond boundary (x spread) = "+DoubleToString(RngSlBufSpreadMult,4);
      lines[n++]="[RNG] SL buffer beyond boundary (x ATR) = "+DoubleToString(RngSlBufAtr,4);
      lines[n++]="[RNG] TP target = "+EnumToString(RngTpTarget);
      lines[n++]="[RNG] TP offset before target (% of width) = "+DoubleToString(RngTpOffsetPct,4);
      lines[n++]="[RNG] Breakout confirmation buffer (x ATR) = "+DoubleToString(RngBreakBufAtr,4);
      lines[n++]="[RNG] Exit quickly on confirmed breakout = "+(RngExitOnBreakout ? "true" : "false");
      lines[n++]="[RNG] Max trades per boundary touch = "+IntegerToString(RngMaxTradesPerTouch);
      lines[n++]="[RNG] Signal validity (ms) = "+IntegerToString(RngSignalTtlMs);
      lines[n++]="[RNG] Time-stop (s, 0 = off) = "+IntegerToString(RngTimeStopSec);
      lines[n++]="[RNG] Max simultaneous positions (Range) = "+IntegerToString(RngMaxPositions);
      lines[n++]="[RNG] Break-even trigger (% of TP distance) = "+DoubleToString(RngBeTriggerPct,4);
      lines[n++]="[RNG] Break-even lock (% of TP distance) = "+DoubleToString(RngBeLockPct,4);
      lines[n++]="[RNG] Trailing trigger (% of TP distance) = "+DoubleToString(RngTrailTriggerPct,4);
      lines[n++]="[RNG] Trailing distance (% of TP distance) = "+DoubleToString(RngTrailDistPct,4);
      lines[n++]="[RNG] Trailing min step (% of TP distance) = "+DoubleToString(RngTrailStepPct,4);
      lines[n++]="[POS] Max total positions on this symbol (this instance) = "+IntegerToString(MaxPositionsSymbol);
      lines[n++]="[POS] OPPOSITE_HEDGE (allow BUY and SELL together) = "+(AllowOppositeHedge ? "true" : "false");
      lines[n++]="[POS] Same-direction signals = "+EnumToString(SameDirMode);
      lines[n++]="[POS] Opposite-signal conflict window (ms) = "+IntegerToString(ConflictWindowMs);
      lines[n++]="[POS] Entry block after a conflict (ms) = "+IntegerToString(ConflictHoldMs);
      lines[n++]="[POS] Min distance between same-engine entries (x ATR M1) = "+DoubleToString(DupMinDistAtr,4);
      lines[n++]="[POS] Min time between any two entries (ms, 0 = off) = "+IntegerToString(MinEntrySpacingMs);
      lines[n++]="[POS] Hard max holding time, all engines (s, 0 = off) = "+IntegerToString(HardMaxHoldSec);
      lines[n++]="[POS] Min interval between SL modifications (ms) = "+IntegerToString(MinModifyIntervalMs);
      lines[n++]="[POS] Send SL/TP after the fill (ECN brokers) = "+(TwoStepStops ? "true" : "false");
      lines[n++]="[RISK] RISK_MODE = "+EnumToString(RiskMode);
      lines[n++]="[RISK] Fixed lot = "+DoubleToString(FixedLot,4);
      lines[n++]="[RISK] Risk per trade (%) = "+DoubleToString(RiskPercent,4);
      lines[n++]="[RISK] Max risk per trade - hard cap (%) = "+DoubleToString(MaxRiskPercent,4);
      lines[n++]="[RISK] Max lot per trade (0 = broker max) = "+DoubleToString(MaxLotPerTrade,4);
      lines[n++]="[RISK] Allow broker min lot even if above max risk = "+(AllowMinLotOverRisk ? "true" : "false");
      lines[n++]="[RISK] Max total open risk, this instance (%) = "+DoubleToString(MaxOpenRiskPct,4);
      lines[n++]="[RISK] Max total open lots, this instance (0 = off) = "+DoubleToString(MaxTotalLots,4);
      lines[n++]="[RISK] Broker stops-level policy = "+EnumToString(StopsPolicy);
      lines[n++]="[RISK] SL/TP ratio guard (max SL / TP, 0 = off) = "+DoubleToString(MaxSlTpRatio,4);
      lines[n++]="[RISK] Martingale ON (optional) = "+(MartingaleEnabled ? "true" : "false");
      lines[n++]="[RISK] Martingale multiplier = "+DoubleToString(MartingaleMult,4);
      lines[n++]="[RISK] Martingale max steps = "+IntegerToString(MartingaleMaxSteps);
      lines[n++]="[DD] Equity drawdown pause ON = "+(DdEnabled ? "true" : "false");
      lines[n++]="[DD] Drawdown threshold (%) = "+DoubleToString(DdPausePct,4);
      lines[n++]="[DD] Pause length (s) = "+IntegerToString(DdPauseSec);
      lines[n++]="[DD] Drawdown reference = "+EnumToString(DdReference);
      lines[n++]="[NEWS] NEWS_FILTER ON = "+(NewsEnabled ? "true" : "false");
      lines[n++]="[NEWS] News source = "+EnumToString(NewsSource);
      lines[n++]="[NEWS] Min impact = "+EnumToString(NewsMinImpact);
      lines[n++]="[NEWS] Currencies (AUTO or list e.g. USD,EUR) = "+NewsCurrencies;
      lines[n++]="[NEWS] Keywords always blocked (any impact) = "+NewsKeywords;
      lines[n++]="[NEWS] Block minutes BEFORE news = "+IntegerToString(NewsMinsBefore);
      lines[n++]="[NEWS] Block minutes AFTER news = "+IntegerToString(NewsMinsAfter);
      lines[n++]="[NEWS] News CSV file (in Files or Common\Files) = "+NewsCsvFile;
      lines[n++]="[NEWS] News CSV is in Common\Files = "+(NewsCsvCommon ? "true" : "false");
      lines[n++]="[NEWS] News CSV times are UTC = "+(NewsCsvUtc ? "true" : "false");
      lines[n++]="[NEWS] Web XML feed URL = "+NewsWebUrl;
      lines[n++]="[NEWS] News refresh interval (min) = "+IntegerToString(NewsRefreshMin);
      lines[n++]="[NEWS] Draw news windows on chart = "+(NewsDraw ? "true" : "false");
      lines[n++]="[SESS] SESSION_FILTER ON = "+(SessionEnabled ? "true" : "false");
      lines[n++]="[SESS] Session preset = "+EnumToString(SessionPreset);
      lines[n++]="[SESS] CUSTOM hours time basis = "+EnumToString(SessionTimeBasis);
      lines[n++]="[SESS] TradingStart (HH:MM) = "+TradingStart;
      lines[n++]="[SESS] TradingEnd (HH:MM) = "+TradingEnd;
      lines[n++]="[SESS] TradingStart 2 (HH:MM, empty = none) = "+TradingStart2;
      lines[n++]="[SESS] TradingEnd 2 (HH:MM) = "+TradingEnd2;
      lines[n++]="[SESS] Trade Monday = "+(TradeMonday ? "true" : "false");
      lines[n++]="[SESS] Trade Tuesday = "+(TradeTuesday ? "true" : "false");
      lines[n++]="[SESS] Trade Wednesday = "+(TradeWednesday ? "true" : "false");
      lines[n++]="[SESS] Trade Thursday = "+(TradeThursday ? "true" : "false");
      lines[n++]="[SESS] Trade Friday = "+(TradeFriday ? "true" : "false");
      lines[n++]="[SESS] Trade Saturday = "+(TradeSaturday ? "true" : "false");
      lines[n++]="[SESS] Trade Sunday = "+(TradeSunday ? "true" : "false");
      lines[n++]="[ROLL] ROLLOVER_FILTER ON = "+(RolloverEnabled ? "true" : "false");
      lines[n++]="[ROLL] Rollover time (server, HH:MM) = "+RolloverTime;
      lines[n++]="[ROLL] Block minutes BEFORE rollover = "+IntegerToString(RolloverMinsBefore);
      lines[n++]="[ROLL] Block minutes AFTER rollover = "+IntegerToString(RolloverMinsAfter);
      lines[n++]="[TZ] Broker GMT offset mode = "+EnumToString(GmtMode);
      lines[n++]="[TZ] Manual broker GMT offset (winter, hours) = "+IntegerToString(GmtOffsetHours);
      lines[n++]="[TZ] Manual offset follows US DST (+1h) = "+(GmtUseUsDst ? "true" : "false");
      lines[n++]="[CONS] CONSECUTIVE_LOSS_PROTECTION ON = "+(ConsecEnabled ? "true" : "false");
      lines[n++]="[CONS] Consecutive losses X = "+IntegerToString(ConsecMaxLosses);
      lines[n++]="[CONS] Cooldown Y (minutes) = "+IntegerToString(ConsecCooldownMin);
      lines[n++]="[CONS] Scope = "+EnumToString(ConsecScope);
      lines[n++]="[EXEC] Max slippage / deviation (points, 0 = auto) = "+IntegerToString(MaxDeviationPts);
      lines[n++]="[EXEC] Auto deviation (x spread) = "+DoubleToString(AutoDeviationSpreadMult,4);
      lines[n++]="[EXEC] Max retries per order = "+IntegerToString(MaxRetries);
      lines[n++]="[EXEC] Delay between retries (ms) = "+IntegerToString(RetryDelayMs);
      lines[n++]="[EXEC] Max price drift before a retry (x ATR M1) = "+DoubleToString(RetryMaxDriftAtr,4);
      lines[n++]="[EXEC] Pause after a permanent broker error (s) = "+IntegerToString(FatalErrorCooldownSec);
      lines[n++]="[EXEC] Execution-quality action = "+EnumToString(ExecQualityAction);
      lines[n++]="[EXEC] Execution-quality window (trades) = "+IntegerToString(ExecQualityWindow);
      lines[n++]="[EXEC] Max avg adverse slippage (x avg spread, 0 = off) = "+DoubleToString(MaxAvgSlippageSpreadMult,4);
      lines[n++]="[EXEC] Max avg order latency (ms, 0 = off) = "+IntegerToString(MaxAvgLatencyMs);
      lines[n++]="[EXEC] Execution-quality cooldown (s) = "+IntegerToString(ExecQualityCooldownSec);
      lines[n++]="[EXEC] Lot factor when quality is poor = "+DoubleToString(ExecQualityLotFactor,4);
      lines[n++]="[MI] MULTI_INSTANCE_GUARD = "+EnumToString(MiGuard);
      lines[n++]="[MI] Cross-instance duplicate window (s) = "+IntegerToString(MiDupWindowSec);
      lines[n++]="[MI] Aggregate exposure mode = "+EnumToString(ExposureMode);
      lines[n++]="[MI] Count only FRANCKY positions (same magic base) = "+(ExposureFamilyOnly ? "true" : "false");
      lines[n++]="[MI] Max open risk all symbols (% equity) = "+DoubleToString(MaxAccountRiskPct,4);
      lines[n++]="[MI] Max net risk per currency, e.g. USD (% equity) = "+DoubleToString(MaxCurrencyRiskPct,4);
      lines[n++]="[MI] Correlation lookback (M5 bars) = "+IntegerToString(CorrBars);
      lines[n++]="[MI] Max correlation-adjusted risk (% equity) = "+DoubleToString(MaxCorrRiskPct,4);
      lines[n++]="[STATE] Save and restore state after restart = "+(StateEnabled ? "true" : "false");
      lines[n++]="[STATE] No new entries after start (s) = "+IntegerToString(RestartGraceSec);
      lines[n++]="[LOG] Log level = "+EnumToString(LogLevel);
      lines[n++]="[LOG] Print to Experts journal = "+(LogToJournal ? "true" : "false");
      lines[n++]="[LOG] Write text log file = "+(LogToFile ? "true" : "false");
      lines[n++]="[LOG] Write CSV journals (signals, trades, events, stats) = "+(LogCsv ? "true" : "false");
      lines[n++]="[LOG] Log files in Common\Files = "+(LogCommon ? "true" : "false");
      lines[n++]="[LOG] Log every signal decision = "+(LogSignals ? "true" : "false");
      lines[n++]="[LOG] Throttle repeated messages (ms) = "+IntegerToString(LogThrottleMs);
      lines[n++]="[LOG] Write files during optimization = "+(LogInOptimization ? "true" : "false");
      lines[n++]="[LOG] Write stats summary every (min) = "+IntegerToString(StatsEveryMin);
      lines[n++]="[UI] Show dashboard panel = "+(ShowPanel ? "true" : "false");
      lines[n++]="[UI] Panel corner = "+EnumToString(PanelCorner);
      lines[n++]="[UI] Panel X offset (px) = "+IntegerToString(PanelX);
      lines[n++]="[UI] Panel Y offset (px) = "+IntegerToString(PanelY);
      lines[n++]="[UI] Panel font size = "+IntegerToString(PanelFontSize);
      lines[n++]="[UI] Dark panel theme = "+(PanelDark ? "true" : "false");
      lines[n++]="[UI] Panel refresh (ms) = "+IntegerToString(PanelRefreshMs);
      lines[n++]="[UI] Draw entries / exits = "+(DrawTrades ? "true" : "false");
      lines[n++]="[UI] Draw FVG zones, ranges, micro-ranges = "+(DrawZones ? "true" : "false");
      lines[n++]="[UI] Draw rejected signals = "+(DrawRejected ? "true" : "false");
      lines[n++]="[UI] Max chart objects = "+IntegerToString(MaxChartObjects);
      lines[n++]="[UI] Keep drawings when the EA stops (tester review) = "+(KeepObjectsOnExit ? "true" : "false");
      lines[n++]="[TEST] Custom optimization criterion = "+EnumToString(OptCriterion);
      lines[n++]="[TEST] Min trades for a valid pass = "+IntegerToString(OptMinTrades);
      lines[n++]="[TEST] Stress: extra spread (points) = "+IntegerToString(StressExtraSpreadPts);
      lines[n++]="[TEST] Stress: extra commission per lot (money) = "+DoubleToString(StressCommissionPerLot,4);
      return n;
     }

   //--- derived helpers (hand-written part of the template in tools/generate.py)
   int ModeDelayMs(void) const
     {
      if(TradingMode==FTF_MODE_SPEED)      return DelaySpeedMs;
      if(TradingMode==FTF_MODE_ULTRA)      return DelayUltraMs;
      return DelayAggressiveMs;
     }
   int ModeMaxSpreadPts(void) const
     {
      if(TradingMode==FTF_MODE_SPEED)      return MaxSpreadPtsSpeed;
      if(TradingMode==FTF_MODE_ULTRA)      return MaxSpreadPtsUltra;
      return MaxSpreadPtsAggressive;
     }
   bool UseCooldownDelay(void) const { return (DelayUsage==FTF_DELAY_COOLDOWN || DelayUsage==FTF_DELAY_BOTH); }
   bool UseConfirmDelay(void)  const { return (DelayUsage==FTF_DELAY_CONFIRM  || DelayUsage==FTF_DELAY_BOTH); }
   double MomSellRatioEff(void) const { return (MomSymmetric ? 1.0-MomBuyRatio : MomSellRatio); }
   //--- per-engine accessors (engine id: 1=Momentum 2=FVG 3=Range)
   bool   EngineEnabled(const int e) const    { if(e==1) return MomEnabled;        if(e==2) return FvgEnabled;        if(e==3) return RngEnabled;        return false; }
   int    EngineMaxPositions(const int e) const{ if(e==1) return MomMaxPositions;   if(e==2) return FvgMaxPositions;   if(e==3) return RngMaxPositions;   return 0; }
   int    EngineTimeStopSec(const int e) const { if(e==1) return MomTimeStopSec;    if(e==2) return FvgTimeStopSec;    if(e==3) return RngTimeStopSec;    return 0; }
   int    EngineSignalTtlMs(const int e) const { if(e==1) return MomSignalTtlMs;    if(e==2) return FvgSignalTtlMs;    if(e==3) return RngSignalTtlMs;    return 500; }
   double EngineBeTriggerPct(const int e) const{ if(e==1) return MomBeTriggerPct;   if(e==2) return FvgBeTriggerPct;   if(e==3) return RngBeTriggerPct;   return 0.0; }
   double EngineBeLockPct(const int e) const   { if(e==1) return MomBeLockPct;      if(e==2) return FvgBeLockPct;      if(e==3) return RngBeLockPct;      return 0.0; }
   double EngineTrailTriggerPct(const int e) const{ if(e==1) return MomTrailTriggerPct; if(e==2) return FvgTrailTriggerPct; if(e==3) return RngTrailTriggerPct; return 0.0; }
   double EngineTrailDistPct(const int e) const{ if(e==1) return MomTrailDistPct;   if(e==2) return FvgTrailDistPct;   if(e==3) return RngTrailDistPct;   return 25.0; }
   double EngineTrailStepPct(const int e) const{ if(e==1) return MomTrailStepPct;   if(e==2) return FvgTrailStepPct;   if(e==3) return RngTrailStepPct;   return 5.0; }
   bool   H1StrictAppliesTo(const int e) const { if(e==1) return H1StrictMomentum;  if(e==2) return H1StrictFvg;       if(e==3) return H1StrictRange;     return false; }

  };

#endif // FTF_CONFIG_MQH
