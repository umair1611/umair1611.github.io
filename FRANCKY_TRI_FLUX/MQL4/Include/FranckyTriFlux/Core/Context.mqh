//+------------------------------------------------------------------+
//|                                                      Context.mqh |
//|  CFtfContext - shared services handed to engines and managers.   |
//|  The controller owns every object; the context only holds        |
//|  pointers (never delete them here).  docs/09 section 7.12        |
//+------------------------------------------------------------------+
#ifndef FTF_CONTEXT_MQH
#define FTF_CONTEXT_MQH

#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Config.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>
#include <FranckyTriFlux\Core\Journal.mqh>
#include <FranckyTriFlux\Core\Stats.mqh>
#include <FranckyTriFlux\Core\StateStore.mqh>
#include <FranckyTriFlux\Platform\Platform.mqh>
#include <FranckyTriFlux\Core\Clock.mqh>
#include <FranckyTriFlux\Core\TickBuffer.mqh>
#include <FranckyTriFlux\Core\MarketData.mqh>
#include <FranckyTriFlux\Core\H1Context.mqh>
#include <FranckyTriFlux\Core\Structure.mqh>
#include <FranckyTriFlux\Core\ChartUI.mqh>

class CFtfContext
  {
public:
   CConfig          *cfg;
   CLogger          *logger;
   CTradeJournal    *journal;
   CStats           *stats;
   CStateStore      *state;
   CPlatform        *pf;
   CClock           *clock;
   CTickBuffer      *ticks;
   CMarketData      *md;
   CH1Context       *h1;
   CChartUI         *ui;

   string            symbol;      // chart symbol (the ONLY traded symbol)
   int               instanceId;
   long              magicBase;
   int               mode;        // ENUM_FTF_MODE
   long              startMsc;    // server ms at init
   long              signalSeq;
   string            lastEvent;   // last protection/state event (dashboard)

                     CFtfContext(void)
     {
      cfg=NULL; logger=NULL; journal=NULL; stats=NULL; state=NULL; pf=NULL;
      clock=NULL; ticks=NULL; md=NULL; h1=NULL; ui=NULL;
      symbol=""; instanceId=1; magicBase=0; mode=FTF_MODE_AGGRESSIVE; startMsc=0; signalSeq=0; lastEvent="";
     }

   long              NextSignalId(void)
     {
      signalSeq++;
      return signalSeq;
     }

   //--- magic = base + instance*10 + engine (engine 1..3)
   long              MagicFor(const int engine)
     {
      return magicBase+(long)instanceId*10+(long)engine;
     }

   //--- 1..3 when the magic belongs to THIS instance, else 0
   int               EngineFromMagic(const long magic)
     {
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         if(magic==MagicFor(e))
            return e;
      return 0;
     }

   //--- any FRANCKY instance using the same magic base
   bool              IsFamilyMagic(const long magic)
     {
      long d=magic-magicBase;
      if(d<10 || d>9999)
         return false;
      long e=d%10;
      return (e>=1 && e<=FTF_ENGINE_COUNT);
     }

   int               InstanceFromMagic(const long magic)
     {
      if(!IsFamilyMagic(magic))
         return 0;
      return (int)((magic-magicBase)/10);
     }

   int               EngineOfFamilyMagic(const long magic)
     {
      if(!IsFamilyMagic(magic))
         return 0;
      return (int)((magic-magicBase)%10);
     }

   string            Tag(void)
     {
      return FTF_PLATFORM+"|"+symbol+"|I"+IntegerToString(instanceId)+"|"+FTF_ModeStr(mode);
     }

   long              NowMsc(void)
     {
      if(CheckPointer(md)!=POINTER_INVALID)
         return md.NowMsc();
      if(CheckPointer(pf)!=POINTER_INVALID)
         return pf.NowMsc();
      return 0;
     }

   //--- protection/state event: events.csv + log
   void              Event(const string category,const string code,const string detail)
     {
      lastEvent=FTF_TimeMscStr(NowMsc())+" "+category+"/"+code+" "+detail;
      if(CheckPointer(journal)!=POINTER_INVALID)
         journal.LogEvent(NowMsc(),category,code,detail);
      if(CheckPointer(logger)!=POINTER_INVALID)
         logger.Info("EVT",category+"/"+code+" "+detail);
     }
  };

#endif // FTF_CONTEXT_MQH
