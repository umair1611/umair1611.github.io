//+------------------------------------------------------------------+
//|                                                        Types.mqh |
//|  Shared data structures (docs/09 section 5). Every struct has    |
//|  Reset() that zeroes all fields. Structs are passed by reference |
//|  and never returned from functions (MQL4/MQL5 portability).      |
//+------------------------------------------------------------------+
#ifndef FTF_TYPES_MQH
#define FTF_TYPES_MQH

#include <FranckyTriFlux\Core\Defines.mqh>

//--- one market tick (platform-neutral; MqlTick is not used in Core)
struct STick
  {
   long              msc;      // server time in milliseconds
   double            bid;
   double            ask;
   int               dir;      // +1 bid up, -1 bid down, 0 unchanged (vs previous tick)
   void              Reset(void) { msc=0; bid=0.0; ask=0.0; dir=0; }
  };

//--- trading signal produced by one engine
struct SSignal
  {
   long              id;            // unique id (CFtfContext::NextSignalId)
   int               engine;        // ENUM_FTF_ENGINE
   int               dir;           // ENUM_FTF_DIR
   string            setupId;       // fingerprint used for duplicate protection
   string            tfText;        // "TICK/M1", "M5", "M1" (logging)
   long              timeMsc;       // server ms when generated
   long              firstSeenMsc;  // confirmer: first time the signal was seen
   long              expiryMsc;     // discard after this server ms
   double            price;         // reference entry price (ask for BUY, bid for SELL)
   double            sl;            // absolute stop-loss price
   double            tp;            // absolute take-profit price
   double            invalidation;  // engine invalidation level (log / chart)
   double            quality;       // 0..100 engine-internal quality (ordering only)
   double            atr;           // ATR used by the engine
   double            spreadPts;     // spread at signal time (points)
   int               h1State;       // ENUM_FTF_H1_STATE at signal time
   bool              structOk;      // BOS/CHoCH present (FVG)
   string            reason;        // entry reason text with key numbers
   void              Reset(void)
     {
      id=0; engine=FTF_ENG_NONE; dir=FTF_DIR_NONE; setupId=""; tfText="";
      timeMsc=0; firstSeenMsc=0; expiryMsc=0; price=0.0; sl=0.0; tp=0.0; invalidation=0.0;
      quality=0.0; atr=0.0; spreadPts=0.0; h1State=FTF_H1S_NEUTRAL; structOk=false; reason="";
     }
  };

//--- a position opened by THIS instance, tracked in memory (+ state file)
struct STrackedPos
  {
   ulong             ticket;
   long              positionId;
   int               engine;
   int               dir;
   string            setupId;
   double            lots;
   double            openPrice;
   double            initialSL;
   double            initialTP;
   double            sl;
   double            tp;
   long              openMsc;
   long              signalMsc;
   double            signalPrice;
   double            requestedPrice;
   double            slippagePts;     // positive = adverse
   double            latencyMs;       // order send -> result
   double            decisionMs;      // tick arrival -> order send
   double            spreadPts;
   int               retries;
   double            riskMoney;
   double            equityAtEntry;
   double            ddPctAtEntry;
   int               h1State;
   int               mode;
   string            entryReason;
   string            tfText;
   double            maePts;          // max adverse excursion (points, >=0)
   double            mfePts;          // max favourable excursion (points, >=0)
   bool              beDone;
   bool              trailActive;
   long              lastModifyMsc;
   int               pendingExit;     // ENUM_FTF_EXIT requested by the EA (0 = none)
   string            pendingExitDetail;
   long              exitRequestMsc;
   int               exitAttempts;
   bool              recovered;       // rebuilt after restart
   long              invStartMsc;     // Momentum: start of current tick inversion (0 = none)
   double            refLevel;        // engine reference level (Momentum breakout level, FVG/Range bound)
   void              Reset(void)
     {
      ticket=0; positionId=0; engine=FTF_ENG_NONE; dir=FTF_DIR_NONE; setupId="";
      lots=0.0; openPrice=0.0; initialSL=0.0; initialTP=0.0; sl=0.0; tp=0.0;
      openMsc=0; signalMsc=0; signalPrice=0.0; requestedPrice=0.0; slippagePts=0.0;
      latencyMs=0.0; decisionMs=0.0; spreadPts=0.0; retries=0; riskMoney=0.0;
      equityAtEntry=0.0; ddPctAtEntry=0.0; h1State=FTF_H1S_NEUTRAL; mode=0;
      entryReason=""; tfText=""; maePts=0.0; mfePts=0.0; beDone=false; trailActive=false;
      lastModifyMsc=0; pendingExit=FTF_EXIT_NONE; pendingExitDetail=""; exitRequestMsc=0;
      exitAttempts=0; recovered=false; invStartMsc=0; refLevel=0.0;
     }
  };

//--- result of a history lookup for a closed position
struct SClosedTrade
  {
   bool              found;
   ulong             ticket;
   long              positionId;
   double            closePrice;
   long              closeMsc;
   double            profit;
   double            commission;
   double            swap;
   double            net;           // profit + commission + swap (+ fee)
   int               exitReason;    // ENUM_FTF_EXIT as seen by the platform
   string            exitDetail;
   void              Reset(void)
     {
      found=false; ticket=0; positionId=0; closePrice=0.0; closeMsc=0;
      profit=0.0; commission=0.0; swap=0.0; net=0.0; exitReason=FTF_EXIT_UNKNOWN; exitDetail="";
     }
  };

//--- snapshot of one open market position (any magic / symbol)
struct SPosInfo
  {
   ulong             ticket;
   long              positionId;
   string            symbol;
   long              magic;
   int               dir;
   double            lots;
   double            openPrice;
   double            sl;
   double            tp;
   long              openMsc;
   double            profit;
   double            swap;
   string            comment;
   void              Reset(void)
     {
      ticket=0; positionId=0; symbol=""; magic=0; dir=FTF_DIR_NONE; lots=0.0;
      openPrice=0.0; sl=0.0; tp=0.0; openMsc=0; profit=0.0; swap=0.0; comment="";
     }
  };

//--- result of an order operation
struct SExecResult
  {
   bool              ok;
   int               retcode;
   string            retcodeText;
   int               errClass;       // ENUM_FTF_ERRCLASS
   ulong             ticket;
   long              positionId;
   double            requestedPrice;
   double            fillPrice;
   double            lots;
   double            latencyMs;
   void              Reset(void)
     {
      ok=false; retcode=0; retcodeText=""; errClass=FTF_ERR_NONE; ticket=0; positionId=0;
      requestedPrice=0.0; fillPrice=0.0; lots=0.0; latencyMs=0.0;
     }
  };

//--- economic calendar event
struct SNewsEvent
  {
   datetime          timeServer;
   string            currency;
   int               impact;        // ENUM_FTF_IMPACT value 1..3
   string            title;
   string            source;
   void              Reset(void) { timeServer=0; currency=""; impact=0; title=""; source=""; }
  };

//--- chart symbol specification (refreshed by CMarketData)
struct SSymbolSpec
  {
   string            name;
   double            point;
   int               digits;
   double            tickSize;
   double            tickValue;
   double            contractSize;
   double            lotMin;
   double            lotMax;
   double            lotStep;
   int               stopsLevelPts;
   int               freezeLevelPts;
   string            baseCcy;
   string            profitCcy;
   string            marginCcy;
   bool              canBuy;
   bool              canSell;
   bool              tradeAllowed;
   bool              hedging;
   void              Reset(void)
     {
      name=""; point=0.0; digits=0; tickSize=0.0; tickValue=0.0; contractSize=0.0;
      lotMin=0.0; lotMax=0.0; lotStep=0.0; stopsLevelPts=0; freezeLevelPts=0;
      baseCcy=""; profitCcy=""; marginCcy=""; canBuy=false; canSell=false; tradeAllowed=false; hedging=true;
     }
  };

#endif // FTF_TYPES_MQH
