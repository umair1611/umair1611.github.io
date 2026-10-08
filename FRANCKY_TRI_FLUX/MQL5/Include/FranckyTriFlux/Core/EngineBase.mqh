//+------------------------------------------------------------------+
//|                                                   EngineBase.mqh |
//|  CEngineBase - common behaviour of the 3 independent engines.    |
//|  An engine NEVER reads another engine. docs/09 section 7.13      |
//+------------------------------------------------------------------+
#ifndef FTF_ENGINE_BASE_MQH
#define FTF_ENGINE_BASE_MQH

#include <FranckyTriFlux\Core\Context.mqh>

class CEngineBase
  {
protected:
   CFtfContext      *m_ctx;
   int               m_id;            // ENUM_FTF_ENGINE
   string            m_code;          // MOM / FVG / RNG
   string            m_name;          // Momentum / FVG / Range
   bool              m_enabled;
   long              m_lastEntryMsc;  // server ms of the last entry of this engine
   string            m_ring[];        // traded / burned setup ids
   int               m_ringPos;
   string            m_status;        // short status for the panel
   string            m_lastInfo;      // last decision text for the panel

   //--- helpers for derived engines
   void              Log(const int level,const string msg)
     {
      if(CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_ctx.logger)==POINTER_INVALID)
         return;
      if(level<=FTF_LOG_ERROR)      m_ctx.logger.Error(m_code,msg);
      else if(level==FTF_LOG_WARN)  m_ctx.logger.Warn(m_code,msg);
      else if(level==FTF_LOG_INFO)  m_ctx.logger.Info(m_code,msg);
      else if(level==FTF_LOG_DEBUG) m_ctx.logger.Debug(m_code,msg);
      else                          m_ctx.logger.Trace(m_code,msg);
     }
   void              LogThrottled(const int level,const string key,const string msg)
     {
      if(CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_ctx.logger)==POINTER_INVALID)
         return;
      m_ctx.logger.Throttled(level,m_code+"."+key,m_ctx.cfg.LogThrottleMs,m_code,msg);
     }
   //--- fills the common part of a signal
   void              PrepareSignal(SSignal &s,const int dir,const string setupId,const string tfText)
     {
      s.Reset();
      s.id=m_ctx.NextSignalId();
      s.engine=m_id;
      s.dir=dir;
      s.setupId=setupId;
      s.tfText=tfText;
      s.timeMsc=m_ctx.md.NowMsc();
      s.firstSeenMsc=s.timeMsc;
      s.expiryMsc=s.timeMsc+(long)m_ctx.cfg.EngineSignalTtlMs(m_id);
      s.price=(dir==FTF_DIR_BUY ? m_ctx.md.AskPrice() : m_ctx.md.BidPrice());
      s.spreadPts=m_ctx.md.SpreadPts();
      s.h1State=(CheckPointer(m_ctx.h1)!=POINTER_INVALID ? m_ctx.h1.State() : FTF_H1S_NEUTRAL);
     }
   double            Norm(const double price)
     {
      return FTF_NormalizePrice(price,m_ctx.md.TickSize(),m_ctx.md.DigitsCount());
     }

public:
                     CEngineBase(void)
     {
      m_ctx=NULL; m_id=FTF_ENG_NONE; m_code="---"; m_name="none"; m_enabled=false;
      m_lastEntryMsc=0; m_ringPos=0; m_status="init"; m_lastInfo="";
      ArrayResize(m_ring,FTF_TRADED_RING);
      for(int i=0;i<FTF_TRADED_RING;i++)
         m_ring[i]="";
     }
   virtual          ~CEngineBase(void) {}

   //--- derived classes set m_id/m_code/m_name in their constructor, then call CEngineBase::Init(ctx)
   virtual bool      Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(CheckPointer(m_ctx)==POINTER_INVALID)
         return false;
      m_enabled=m_ctx.cfg.EngineEnabled(m_id);
      m_status=(m_enabled ? "ON" : "OFF");
      Log(FTF_LOG_INFO,m_name+" engine "+(m_enabled ? "ENABLED" : "DISABLED")+
          " | max pos "+IntegerToString(m_ctx.cfg.EngineMaxPositions(m_id))+
          " | time-stop "+IntegerToString(m_ctx.cfg.EngineTimeStopSec(m_id))+"s");
      return true;
     }
   virtual void      OnNewBar(const ENUM_TIMEFRAMES tf) {}
   //--- append up to maxOut signals into out[startIndex..]; returns the number appended
   virtual int       Evaluate(SSignal &out[],const int startIndex,const int maxOut) { return 0; }
   virtual bool      IsStillValid(const SSignal &sig,string &why) { why=""; return true; }
   virtual int       CheckExit(STrackedPos &pos,string &detail) { detail=""; return FTF_EXIT_NONE; }
   virtual void      OnEntry(const SSignal &sig,const STrackedPos &pos)
     {
      m_lastEntryMsc=(pos.openMsc>0 ? pos.openMsc : sig.timeMsc);
      MarkTraded(sig.setupId);
      SaveState();
     }
   virtual void      OnClosed(const STrackedPos &pos,const SClosedTrade &tr) {}
   virtual void      Draw(void) {}
   virtual string    StatusLine(void)
     {
      return "["+StringSubstr(m_code,0,1)+"] "+m_name+" "+(m_enabled ? "ON " : "OFF")+" | "+m_status+
             (StringLen(m_lastInfo)>0 ? " | "+m_lastInfo : "");
     }

   //--- persistence of last entry + traded ring (B.7)
   virtual void      SaveState(void)
     {
      if(CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_ctx.state)==POINTER_INVALID || !m_ctx.state.Enabled())
         return;
      string k="eng."+IntegerToString(m_id)+".";
      m_ctx.state.SetLong(k+"lastEntry",m_lastEntryMsc);
      string joined="";
      for(int i=0;i<FTF_TRADED_RING;i++)
        {
         if(StringLen(m_ring[i])==0)
            continue;
         if(StringLen(joined)>0)
            joined+="|";
         joined+=m_ring[i];
        }
      m_ctx.state.SetString(k+"ring",joined);
     }
   virtual void      LoadState(void)
     {
      if(CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_ctx.state)==POINTER_INVALID || !m_ctx.state.Enabled())
         return;
      string k="eng."+IntegerToString(m_id)+".";
      m_lastEntryMsc=m_ctx.state.GetLong(k+"lastEntry",0);
      string joined=m_ctx.state.GetString(k+"ring","");
      string parts[];
      int n=StringSplit(joined,StringGetCharacter("|",0),parts);
      for(int i=0;i<n;i++)
         if(StringLen(parts[i])>0)
            MarkTraded(parts[i]);
      if(n>0)
         Log(FTF_LOG_INFO,"state restored: last entry "+FTF_TimeMscStr(m_lastEntryMsc)+", "+IntegerToString(n)+" traded setup ids");
     }

   int               Id(void)            { return m_id; }
   string            Code(void)          { return m_code; }
   string            Name(void)          { return m_name; }
   bool              Enabled(void)       { return m_enabled; }
   long              LastEntryMsc(void)  { return m_lastEntryMsc; }
   void              SetInfo(const string s) { m_lastInfo=s; }
   string            Info(void)          { return m_lastInfo; }

   void              MarkTraded(const string setupId)
     {
      if(StringLen(setupId)==0 || WasTraded(setupId))
         return;
      m_ring[m_ringPos]=setupId;
      m_ringPos=(m_ringPos+1)%FTF_TRADED_RING;
     }
   bool              WasTraded(const string setupId)
     {
      if(StringLen(setupId)==0)
         return false;
      for(int i=0;i<FTF_TRADED_RING;i++)
         if(m_ring[i]==setupId)
            return true;
      return false;
     }
  };

#endif // FTF_ENGINE_BASE_MQH
