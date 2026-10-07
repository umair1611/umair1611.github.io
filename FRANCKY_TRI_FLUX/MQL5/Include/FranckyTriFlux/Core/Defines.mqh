//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|              FRANCKY TRI-FLUX - HFT-style retail ultra scalping  |
//|  Shared Core (identical in MQL5 and MQL4 trees) - see docs/09    |
//+------------------------------------------------------------------+
#ifndef FTF_DEFINES_MQH
#define FTF_DEFINES_MQH

#include <FranckyTriFlux\Core\InputEnums.mqh>

#define FTF_NAME            "FRANCKY TRI-FLUX"
#define FTF_VERSION         "1.00"
#define FTF_SHORT           "FTF"
#define FTF_ENGINE_COUNT    3      // engine ids 1..3 ; index 0 = TOTAL in statistics
#define FTF_MAX_SIGNALS     16     // max signals handled per cycle
#define FTF_TRADED_RING     64     // traded / burned setup ids remembered per engine
#define FTF_PANEL_ROWS      24     // dashboard rows
#define FTF_TICK_CAPACITY   16384  // tick ring buffer capacity (power of two)
#define FTF_FILES_ROOT      "FranckyTriFlux"

#ifdef __MQL5__
   #define FTF_PLATFORM     "MT5"
#else
   #define FTF_PLATFORM     "MT4"
#endif

//--- engines
enum ENUM_FTF_ENGINE
  {
   FTF_ENG_NONE=0,
   FTF_ENG_MOMENTUM=1,
   FTF_ENG_FVG=2,
   FTF_ENG_RANGE=3
  };

//--- trade direction
enum ENUM_FTF_DIR
  {
   FTF_DIR_SELL=-1,
   FTF_DIR_NONE=0,
   FTF_DIR_BUY=1
  };

//--- H1 context state (spec A.1)
enum ENUM_FTF_H1_STATE
  {
   FTF_H1S_BEARISH=-1,
   FTF_H1S_NEUTRAL=0,
   FTF_H1S_BULLISH=1
  };

//--- order error classes (spec B.8)
enum ENUM_FTF_ERRCLASS
  {
   FTF_ERR_NONE=0,        // success
   FTF_ERR_TRANSIENT=1,   // requote, off quotes, price changed, timeout, busy -> retry after revalidation
   FTF_ERR_PERMANENT=2,   // invalid stops/volume/request -> no retry for this signal
   FTF_ERR_FATAL=3        // no money, trading disabled, market closed -> pause entries (error cooldown)
  };

//--- drawdown guard state (spec G.4)
enum ENUM_FTF_DD_STATE
  {
   FTF_DDS_ARMED=0,
   FTF_DDS_PAUSED=1
  };

//--- FVG zone state
enum ENUM_FTF_ZONE_STATE
  {
   FTF_ZS_INTACT=0,
   FTF_ZS_MITIGATED=1,
   FTF_ZS_INVALIDATED=2,
   FTF_ZS_EXPIRED=3,
   FTF_ZS_EXHAUSTED=4
  };

//--- range state
enum ENUM_FTF_RANGE_STATE
  {
   FTF_RS_NONE=0,
   FTF_RS_ACTIVE=1,
   FTF_RS_BROKEN=2
  };

//--- rejection / decision reasons (docs/09 section 4.1). Text: FTF_ReasonStr()
enum ENUM_FTF_REASON
  {
   FTF_OK=0,
   FTF_REJ_WARMUP,
   FTF_REJ_TRADING_OFF,
   FTF_REJ_TERMINAL,
   FTF_REJ_SYMBOL,
   FTF_REJ_STALE_TICK,
   FTF_REJ_DD_PAUSE,
   FTF_REJ_CONSEC_LOSS,
   FTF_REJ_NEWS,
   FTF_REJ_SESSION,
   FTF_REJ_ROLLOVER,
   FTF_REJ_SPREAD,
   FTF_REJ_VOLATILITY,
   FTF_REJ_EXEC_QUALITY,
   FTF_REJ_ERROR_COOLDOWN,
   FTF_REJ_CONFLICT,
   FTF_REJ_H1_STRICT,
   FTF_REJ_COOLDOWN,
   FTF_REJ_SPACING,
   FTF_REJ_MAX_POS_ENGINE,
   FTF_REJ_MAX_POS_SYMBOL,
   FTF_REJ_HEDGE,
   FTF_REJ_SAME_DIR,
   FTF_REJ_DUPLICATE,
   FTF_REJ_MULTI_INSTANCE,
   FTF_REJ_SIGNAL_EXPIRED,
   FTF_REJ_SIGNAL_INVALID,
   FTF_REJ_PRICE_DRIFT,
   FTF_REJ_SLTP_INVALID,
   FTF_REJ_SLTP_RATIO,
   FTF_REJ_STOPS_LEVEL,
   FTF_REJ_RISK,
   FTF_REJ_LOT,
   FTF_REJ_MARGIN,
   FTF_REJ_EXPOSURE,
   FTF_REJ_AGGREGATE,
   FTF_REJ_NETTING,
   FTF_REJ_ORDER_FAILED,
   FTF_REJ_CONFIRM_PENDING,
   FTF_REJ_COUNT
  };

//--- exit reasons (docs/09 section 4.2). Text: FTF_ExitStr()
enum ENUM_FTF_EXIT
  {
   FTF_EXIT_NONE=0,
   FTF_EXIT_TP,
   FTF_EXIT_SL,
   FTF_EXIT_BE,
   FTF_EXIT_TRAIL,
   FTF_EXIT_TIME_STOP,
   FTF_EXIT_HARD_MAX,
   FTF_EXIT_MOM_LOSS,
   FTF_EXIT_MOM_INVALID,
   FTF_EXIT_FVG_INVALID,
   FTF_EXIT_RANGE_BREAK,
   FTF_EXIT_MANUAL,
   FTF_EXIT_STOP_OUT,
   FTF_EXIT_OFFLINE,
   FTF_EXIT_UNKNOWN,
   FTF_EXIT_COUNT
  };

#endif // FTF_DEFINES_MQH
