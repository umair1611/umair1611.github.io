//+------------------------------------------------------------------+
//|                                                  Protections.mqh |
//|  Account / execution protections (docs/09 sections 7.15 and 9):  |
//|   CDrawdownGuard    - 10 % equity drawdown pause (spec G.4)      |
//|   CConsecLossGuard  - consecutive-loss cooldown (spec B.4)       |
//|   CExecQualityGuard - rolling slippage / latency check (Tab. 13) |
//|  Protections never touch strategy logic: they only say "blocked" |
//|  (the safety gate turns that into a reason code).                |
//+------------------------------------------------------------------+
#ifndef FTF_PROTECTIONS_MQH
#define FTF_PROTECTIONS_MQH

#include <FranckyTriFlux\Core\Context.mqh>

#define FTF_PROT_EXECQ_MIN_SAMPLES   5     // TUNABLE (not an input yet) fills needed before EXEC_QUALITY may act
#define FTF_PROT_EXECQ_MAX_WINDOW    500   // TUNABLE (not an input yet) hard cap of the rolling fill window
#define FTF_PROT_EXECQ_SPREAD_FLOOR  1.0   // TUNABLE (not an input yet) avg-spread floor (points) of the slippage test
#define FTF_PROT_DD_NEAR_RATIO       0.8   // TUNABLE (not an input yet) throttled INFO when dd >= 80 % of the threshold

//+------------------------------------------------------------------+
//| small formatting helpers (file-local prefix FTF_Prot)            |
//+------------------------------------------------------------------+
//--- 10450 -> "10 450.00"
string FTF_ProtMoney(const double v)
  {
   string s=DoubleToString(MathAbs(v),2);
   int dot=StringFind(s,".");
   string ip=s;
   string dp="";
   if(dot>0)
     {
      ip=StringSubstr(s,0,dot);
      dp=StringSubstr(s,dot);
     }
   string out="";
   int len=StringLen(ip);
   for(int i=0;i<len;i++)
     {
      if(i>0 && ((len-i)%3)==0)
         out+=" ";
      out+=StringSubstr(ip,i,1);
     }
   return (v<0.0 ? "-" : "")+out+dp;
  }

//--- 10.0 -> "10", 2.34 -> "2.3"
string FTF_ProtPct(const double v)
  {
   string s=DoubleToString(v,1);
   int n=StringLen(s);
   if(n>2 && StringSubstr(s,n-2)==".0")
      return StringSubstr(s,0,n-2);
   return s;
  }

//--- remaining time: "45s", "12m", "1h05m" (rounded up)
string FTF_ProtDur(const long ms)
  {
   long s=(ms+999)/1000;
   if(s<0)
      s=0;
   if(s<60)
      return IntegerToString(s)+"s";
   long m=(s+59)/60;
   if(m<60)
      return IntegerToString(m)+"m";
   return IntegerToString(m/60)+"h"+StringFormat("%02d",(int)(m%60))+"m";
  }

//+------------------------------------------------------------------+
//| CDrawdownGuard - 10 % pause: STOP -> REACTIVATE -> VERIFY ->     |
//| RESTART (docs/03 section 7, docs/09 section 9).                  |
//| The pause is a strict timer: it ends when the server-time OR     |
//| (live only) the wall-clock elapsed time reaches the pause length,|
//| so a quiet market (no tick) can never keep the EA waiting.       |
//+------------------------------------------------------------------+
class CDrawdownGuard
  {
private:
   CFtfContext      *m_ctx;
   int               m_state;          // ENUM_FTF_DD_STATE
   bool              m_isTester;
   double            m_startRef;       // START_BALANCE reference (state key dd.ref)
   double            m_peak;           // PEAK_EQUITY high-water mark (dd.peak)
   double            m_dayRef;         // DAY_START_EQUITY reference (dd.dayRef)
   datetime          m_dayStart;       // server day of m_dayRef (dd.dayStart)
   double            m_lastEquity;
   double            m_ddPct;
   long              m_pauseStartMsc;
   long              m_pauseEndMsc;    // server ms (dd.pauseEnd)
   ulong             m_wallEndUs;      // wall-clock deadline (GetMicrosecondCount, live only, 0 = none)
   int               m_triggers;       // dd.triggers
   bool              m_verifyReq;      // one-shot request for the safety verification sequence
   bool              m_rebasePending;  // resumed while equity was unavailable -> rebase on next valid equity

   bool              Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.cfg)!=POINTER_INVALID &&
              CheckPointer(m_ctx.pf)!=POINTER_INVALID);
     }
   bool              StoreOk(void)
     {
      return (Ready() && CheckPointer(m_ctx.state)!=POINTER_INVALID && m_ctx.state.Enabled());
     }
   long              NowMs(void)
     {
      long ms=m_ctx.NowMsc();
      if(ms<=0)
         ms=(long)m_ctx.pf.ServerTime()*1000;
      return ms;
     }
   long              PauseLenMs(void)
     {
      return (long)m_ctx.cfg.DdPauseSec*1000;
     }
   string            RefName(void)
     {
      if(m_ctx.cfg.DdReference==FTF_DDREF_START_BALANCE)
         return "START_BALANCE";
      if(m_ctx.cfg.DdReference==FTF_DDREF_DAY_START_EQUITY)
         return "DAY_START_EQUITY";
      return "PEAK_EQUITY";
     }
   string            StateName(void)
     {
      return (m_state==FTF_DDS_PAUSED ? "PAUSED" : "ARMED");
     }
   double            CalcPct(const double eq,const double ref)
     {
      if(ref<=0.0 || eq<=0.0)
         return 0.0;
      double v=(ref-eq)/ref*100.0;
      return (v>0.0 ? v : 0.0);
     }
   void              LogInfo(const string msg)
     {
      if(CheckPointer(m_ctx.log)!=POINTER_INVALID)
         m_ctx.log.Info("DD",msg);
     }
   void              LogThrottled(const int level,const string key,const string msg)
     {
      if(CheckPointer(m_ctx.log)!=POINTER_INVALID)
         m_ctx.log.Throttled(level,"DD."+key,m_ctx.cfg.LogThrottleMs,"DD",msg);
     }

   //--- strict timer: server time, or (live) wall clock
   bool              PauseElapsed(void)
     {
      if(NowMs()>=m_pauseEndMsc)
         return true;
      if(!m_isTester && m_wallEndUs>0 && GetMicrosecondCount()>=m_wallEndUs)
         return true;
      return false;
     }

   //--- DAY_START_EQUITY: equity at the first Update of each server day
   void              UpdateDay(const double eq)
     {
      datetime srv=(datetime)(NowMs()/1000);
      if(srv<=0)
         return;
      datetime day=FTF_DayStart(srv);
      if(day==m_dayStart && m_dayRef>0.0)
         return;
      bool newDay=(m_dayStart>0 && day!=m_dayStart);
      m_dayStart=day;
      m_dayRef=eq;
      if(newDay)
         LogInfo("new server day "+TimeToString(day,TIME_DATE)+": day-start equity "+FTF_D(eq,2)+
                 (m_ctx.cfg.DdReference==FTF_DDREF_DAY_START_EQUITY ? " = drawdown reference" : ""));
     }

   //--- 1 STOP (+ 2 REACTIVATE / 3 VERIFY requested from the controller)
   void              Trigger(const double eq,const double ref)
     {
      long now=NowMs();
      long lenMs=PauseLenMs();
      m_state=FTF_DDS_PAUSED;
      m_pauseStartMsc=now;
      m_pauseEndMsc=now+lenMs;
      m_wallEndUs=GetMicrosecondCount()+(ulong)(lenMs*1000);
      m_triggers++;
      m_verifyReq=true;
      m_ctx.Event("DD","TRIGGER","dd "+FTF_D(m_ddPct,2)+"% >= "+FTF_ProtPct(m_ctx.cfg.DdPausePct)+"% ref "+FTF_D(ref,2)+
                  " ("+RefName()+") equity "+FTF_D(eq,2)+" - STOP new entries, safeties re-activated, auto restart in "+
                  IntegerToString(m_ctx.cfg.DdPauseSec)+" s (until "+FTF_TimeMscStr(m_pauseEndMsc)+", trigger #"+
                  IntegerToString(m_triggers)+")");
      if(CheckPointer(m_ctx.ui)!=POINTER_INVALID && m_ctx.ui.Enabled())
         m_ctx.ui.DrawVLine("DD_"+IntegerToString(m_triggers),(datetime)(now/1000),clrRed,
                            "DD pause #"+IntegerToString(m_triggers)+" dd "+FTF_D(m_ddPct,2)+"%");
      Save();
     }

   //--- 4 RESTART: ARMED, reference re-based to the current equity (prevents a pause loop)
   void              Resume(const double eq,const string why)
     {
      double oldRef=RefEquity();
      m_state=FTF_DDS_ARMED;
      m_wallEndUs=0;
      m_ddPct=0.0;
      string rebase="";
      if(eq>0.0)
        {
         m_peak=eq;
         m_startRef=eq;
         m_dayRef=eq;
         m_lastEquity=eq;
         m_rebasePending=false;
         double nextAt=eq*(1.0-m_ctx.cfg.DdPausePct/100.0);
         rebase="reference re-based to equity "+FTF_D(eq,2)+" (was "+FTF_D(oldRef,2)+" "+RefName()+"), next pause at equity <= "+FTF_D(nextAt,2);
        }
      else
        {
         m_rebasePending=true;
         rebase="equity unavailable - reference will be re-based on the next valid equity";
        }
      m_ctx.Event("DD","RESUME",why+" - new entries allowed again, "+rebase);
      Save();
     }

   void              CheckResume(const double eq)
     {
      if(m_state!=FTF_DDS_PAUSED || !PauseElapsed())
         return;
      long now=NowMs();
      string how=(now>=m_pauseEndMsc ? "server time" : "wall clock, no tick");
      double secs=(double)(now-m_pauseStartMsc)/1000.0;
      Resume(eq,"pause of "+IntegerToString(m_ctx.cfg.DdPauseSec)+" s elapsed ("+how+", server "+FTF_D(secs,1)+" s)");
     }

public:
                     CDrawdownGuard(void)
     {
      m_ctx=NULL; m_state=FTF_DDS_ARMED; m_isTester=false; m_startRef=0.0; m_peak=0.0; m_dayRef=0.0;
      m_dayStart=0; m_lastEquity=0.0; m_ddPct=0.0; m_pauseStartMsc=0; m_pauseEndMsc=0; m_wallEndUs=0;
      m_triggers=0; m_verifyReq=false; m_rebasePending=false;
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(!Ready())
         return false;
      m_isTester=m_ctx.pf.IsTester();
      double eq=m_ctx.pf.Equity();
      double bal=m_ctx.pf.Balance();
      m_state=FTF_DDS_ARMED;
      m_peak=eq;
      m_startRef=(bal>0.0 ? bal : eq);
      m_dayRef=eq;
      m_lastEquity=eq;
      m_ddPct=0.0;
      m_pauseStartMsc=0; m_pauseEndMsc=0; m_wallEndUs=0;
      m_triggers=0; m_verifyReq=false; m_rebasePending=false;
      datetime srv=(datetime)(NowMs()/1000);
      m_dayStart=(srv>0 ? FTF_DayStart(srv) : (datetime)0);
      LogInfo("drawdown guard "+(m_ctx.cfg.DdEnabled ? "ON" : "OFF")+": threshold "+FTF_ProtPct(m_ctx.cfg.DdPausePct)+
              "%, pause "+IntegerToString(m_ctx.cfg.DdPauseSec)+" s (strict timer"+(m_isTester ? ", tester: server time" : ", server time + wall clock")+
              "), reference "+RefName()+" | equity "+FTF_D(eq,2)+" balance "+FTF_D(bal,2));
      return true;
     }

   //--- once per cycle (pipeline step 4)
   void              Update(void)
     {
      if(!Ready())
         return;
      if(!m_ctx.cfg.DdEnabled)
        {
         m_state=FTF_DDS_ARMED;
         m_ddPct=0.0;
         return;
        }
      double eq=m_ctx.pf.Equity();
      if(m_state==FTF_DDS_PAUSED)
         CheckResume(eq);                                // the timer is checked even without equity
      if(eq<=0.0)
        {
         LogThrottled(FTF_LOG_WARN,"noeq","equity not available - drawdown not measured this cycle");
         return;
        }
      m_lastEquity=eq;
      if(m_rebasePending)
        {
         m_peak=eq; m_startRef=eq; m_dayRef=eq; m_rebasePending=false;
         LogInfo("reference re-based to equity "+FTF_D(eq,2)+" (deferred rebase after resume)");
        }
      if(m_startRef<=0.0)
        {
         double bal=m_ctx.pf.Balance();
         m_startRef=(bal>0.0 ? bal : eq);
        }
      UpdateDay(eq);
      if(m_state==FTF_DDS_PAUSED)
        {
         m_ddPct=CalcPct(eq,RefEquity());
         return;
        }
      if(eq>m_peak)
         m_peak=eq;                                      // high-water mark, tracked while ARMED
      double ref=RefEquity();
      m_ddPct=CalcPct(eq,ref);
      if(m_ddPct>=m_ctx.cfg.DdPausePct)
         Trigger(eq,ref);
      else if(m_ddPct>=m_ctx.cfg.DdPausePct*FTF_PROT_DD_NEAR_RATIO)
         LogThrottled(FTF_LOG_INFO,"near","dd "+FTF_D(m_ddPct,2)+"% approaching the "+FTF_ProtPct(m_ctx.cfg.DdPausePct)+
                      "% pause (ref "+FTF_D(ref,2)+" "+RefName()+", equity "+FTF_D(eq,2)+")");
     }

   //--- also enforces the strict timer when Update() has not run yet this cycle
   bool              IsPaused(void)
     {
      if(!Ready() || !m_ctx.cfg.DdEnabled || m_state!=FTF_DDS_PAUSED)
         return false;
      CheckResume(m_ctx.pf.Equity());
      return (m_state==FTF_DDS_PAUSED);
     }

   int               State(void)        { return m_state; }

   long              PauseRemainingMs(void)
     {
      if(!Ready() || m_state!=FTF_DDS_PAUSED)
         return 0;
      long rem=m_pauseEndMsc-NowMs();
      if(!m_isTester && m_wallEndUs>0)
        {
         ulong nowUs=GetMicrosecondCount();
         long wallRem=0;
         if(nowUs<m_wallEndUs)
            wallRem=(long)((m_wallEndUs-nowUs)/1000);
         if(wallRem<rem)
            rem=wallRem;
        }
      return (rem>0 ? rem : (long)0);
     }

   double            DdPct(void)        { return m_ddPct; }

   double            RefEquity(void)
     {
      if(!Ready())
         return 0.0;
      if(m_ctx.cfg.DdReference==FTF_DDREF_START_BALANCE)
         return m_startRef;
      if(m_ctx.cfg.DdReference==FTF_DDREF_DAY_START_EQUITY)
         return m_dayRef;
      return m_peak;
     }

   double            PeakEquity(void)   { return m_peak; }
   int               Triggers(void)     { return m_triggers; }

   //--- true once after each trigger (controller runs the safety verification)
   bool              TakeVerifyRequest(void)
     {
      if(!m_verifyReq)
         return false;
      m_verifyReq=false;
      return true;
     }

   void              Save(void)
     {
      if(!StoreOk())
         return;
      m_ctx.state.SetLong("dd.state",(long)m_state);
      m_ctx.state.SetDouble("dd.ref",m_startRef);
      m_ctx.state.SetDouble("dd.peak",m_peak);
      m_ctx.state.SetLong("dd.pauseEnd",(m_state==FTF_DDS_PAUSED ? m_pauseEndMsc : (long)0));
      m_ctx.state.SetLong("dd.triggers",(long)m_triggers);
      m_ctx.state.SetLong("dd.dayStart",(long)m_dayStart);
      m_ctx.state.SetDouble("dd.dayRef",m_dayRef);
     }

   //--- after Init. A saved pause is never extended beyond its original end.
   void              Load(void)
     {
      if(!StoreOk() || !m_ctx.state.Has("dd.state"))
         return;
      double sRef=m_ctx.state.GetDouble("dd.ref",0.0);
      double sPeak=m_ctx.state.GetDouble("dd.peak",0.0);
      datetime sDay=(datetime)m_ctx.state.GetLong("dd.dayStart",0);
      double sDayRef=m_ctx.state.GetDouble("dd.dayRef",0.0);
      int sState=(int)m_ctx.state.GetLong("dd.state",(long)FTF_DDS_ARMED);
      long sEnd=m_ctx.state.GetLong("dd.pauseEnd",0);
      m_triggers=(int)m_ctx.state.GetLong("dd.triggers",0);
      if(sRef>0.0)
         m_startRef=sRef;
      if(sPeak>m_peak)
         m_peak=sPeak;
      if(sDay>0 && sDay==m_dayStart && sDayRef>0.0)
         m_dayRef=sDayRef;
      LogInfo("state restored: ref(start) "+FTF_D(m_startRef,2)+" peak "+FTF_D(m_peak,2)+" day-ref "+FTF_D(m_dayRef,2)+
              " triggers "+IntegerToString(m_triggers)+" saved state "+(sState==FTF_DDS_PAUSED ? "PAUSED" : "ARMED"));
      if(sState!=FTF_DDS_PAUSED || sEnd<=0)
         return;
      long now=NowMs();
      long rem=sEnd-now;
      if(rem<=0 || !m_ctx.cfg.DdEnabled)
        {
         m_state=FTF_DDS_PAUSED;
         m_pauseStartMsc=sEnd-PauseLenMs();
         m_pauseEndMsc=sEnd;
         Resume(m_ctx.pf.Equity(),"restart: the saved pause (end "+FTF_TimeMscStr(sEnd)+") already ended while the EA was offline");
         return;
        }
      if(rem>PauseLenMs())
         rem=PauseLenMs();                               // stale clock: never longer than one pause from now
      m_state=FTF_DDS_PAUSED;
      m_pauseEndMsc=now+rem;                             // <= original end
      m_pauseStartMsc=m_pauseEndMsc-PauseLenMs();
      m_wallEndUs=GetMicrosecondCount()+(ulong)(rem*1000);
      m_ctx.Event("DD","RESTORE","pause restored after restart: "+FTF_D((double)rem/1000.0,1)+" s left (original end "+
                  FTF_TimeMscStr(sEnd)+") - no new entries until then");
     }

   //--- "DD 2.3% / 10% (ref 10 450.00) ARMED" or "... PAUSED 7s"
   string            Describe(void)
     {
      if(!Ready())
         return "DD n/a";
      if(!m_ctx.cfg.DdEnabled)
         return "DD OFF";
      string s="DD "+FTF_D(m_ddPct,1)+"% / "+FTF_ProtPct(m_ctx.cfg.DdPausePct)+"% (ref "+FTF_ProtMoney(RefEquity())+") ";
      if(m_state==FTF_DDS_PAUSED)
         return s+"PAUSED "+IntegerToString((PauseRemainingMs()+999)/1000)+"s";
      return s+"ARMED";
     }

   //--- verification step 3: true = PASS, false = WARN (never extends the pause)
   bool              SelfCheck(string &d)
     {
      d="";
      if(!Ready())
        {
         d="drawdown guard not initialised";
         return false;
        }
      if(!m_ctx.cfg.DdEnabled)
        {
         d="drawdown guard OFF (input) - no 10% pause";
         return true;
        }
      bool ok=true;
      string issues="";
      double eq=m_ctx.pf.Equity();
      double ref=RefEquity();
      if(eq<=0.0)
        {
         ok=false;
         issues+=" | equity unavailable";
        }
      if(ref<=0.0)
        {
         ok=false;
         issues+=" | reference not set";
        }
      string pause="";
      if(m_state==FTF_DDS_PAUSED)
        {
         long rem=PauseRemainingMs();
         if(rem>PauseLenMs())
           {
            ok=false;
            m_pauseEndMsc=NowMs()+PauseLenMs();          // clamp: the timer can only get shorter
            issues+=" | remaining pause above the configured length (clamped)";
           }
         if(!m_isTester && m_wallEndUs==0)
           {
            ok=false;
            m_wallEndUs=GetMicrosecondCount()+(ulong)(PauseRemainingMs()*1000);
            issues+=" | wall-clock backup timer was missing (re-armed)";
           }
         pause=", auto restart in "+FTF_D((double)PauseRemainingMs()/1000.0,1)+" s";
        }
      d="state "+StateName()+", dd "+FTF_D(m_ddPct,2)+"% / "+FTF_ProtPct(m_ctx.cfg.DdPausePct)+"%, ref "+FTF_D(ref,2)+
        " ("+RefName()+"), peak "+FTF_D(m_peak,2)+", equity "+FTF_D(eq,2)+", pause "+IntegerToString(m_ctx.cfg.DdPauseSec)+
        " s strict timer ("+(m_isTester ? "server time" : "server time + wall clock")+")"+pause+", triggers "+
        IntegerToString(m_triggers)+issues;
      return ok;
     }
  };

//+------------------------------------------------------------------+
//| CConsecLossGuard - X losses in a row -> cooldown Y minutes (B.4) |
//| Index 0 = instance scope, 1..3 = engines (InpConsecScope).        |
//| Cooldown expiry is checked lazily (IsBlocked / Describe / Update) |
//| and emits CONSEC/RESUME exactly once.                             |
//+------------------------------------------------------------------+
class CConsecLossGuard
  {
private:
   CFtfContext      *m_ctx;
   int               m_count[FTF_ENGINE_COUNT+1];
   long              m_until[FTF_ENGINE_COUNT+1];    // server ms end of cooldown (0 = none)
   bool              m_active[FTF_ENGINE_COUNT+1];   // cooldown running (RESUME pending)

   bool              Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.cfg)!=POINTER_INVALID &&
              CheckPointer(m_ctx.pf)!=POINTER_INVALID);
     }
   bool              StoreOk(void)
     {
      return (Ready() && CheckPointer(m_ctx.state)!=POINTER_INVALID && m_ctx.state.Enabled());
     }
   long              NowMs(void)
     {
      long ms=m_ctx.NowMsc();
      if(ms<=0)
         ms=(long)m_ctx.pf.ServerTime()*1000;
      return ms;
     }
   bool              InstanceScope(void)
     {
      return (m_ctx.cfg.ConsecScope==FTF_SCOPE_INSTANCE);
     }
   //--- counter index for an engine (-1 = invalid)
   int               Idx(const int engine)
     {
      if(InstanceScope())
         return 0;
      if(engine>=1 && engine<=FTF_ENGINE_COUNT)
         return engine;
      return -1;
     }
   string            Who(const int idx)
     {
      return (idx==0 ? "ALL" : FTF_EngineCode(idx));
     }
   string            Letter(const int idx)
     {
      if(idx==FTF_ENG_MOMENTUM)
         return "M";
      if(idx==FTF_ENG_FVG)
         return "F";
      if(idx==FTF_ENG_RANGE)
         return "R";
      return "ALL";
     }
   long              CooldownMs(void)
     {
      return (long)m_ctx.cfg.ConsecCooldownMin*60000;
     }
   void              CheckExpiry(const int idx)
     {
      if(idx<0 || idx>FTF_ENGINE_COUNT || !m_active[idx])
         return;
      if(NowMs()<m_until[idx])
         return;
      m_active[idx]=false;
      m_until[idx]=0;
      m_ctx.Event("CONSEC","RESUME",Who(idx)+": consecutive-loss cooldown of "+IntegerToString(m_ctx.cfg.ConsecCooldownMin)+
                  " min ended - a NEW setup may trade (setups refused during the cooldown stay burned)");
      Save();
     }
   string            Counts(void)
     {
      if(InstanceScope())
         return "ALL:"+IntegerToString(m_count[0]);
      return "M:"+IntegerToString(m_count[1])+" F:"+IntegerToString(m_count[2])+" R:"+IntegerToString(m_count[3]);
     }

public:
                     CConsecLossGuard(void)
     {
      m_ctx=NULL;
      for(int i=0;i<=FTF_ENGINE_COUNT;i++)
        {
         m_count[i]=0;
         m_until[i]=0;
         m_active[i]=false;
        }
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(!Ready())
         return false;
      for(int i=0;i<=FTF_ENGINE_COUNT;i++)
        {
         m_count[i]=0;
         m_until[i]=0;
         m_active[i]=false;
        }
      if(CheckPointer(m_ctx.log)!=POINTER_INVALID)
         m_ctx.log.Info("CONSEC","consecutive-loss protection "+(m_ctx.cfg.ConsecEnabled ? "ON" : "OFF")+": "+
                        IntegerToString(m_ctx.cfg.ConsecMaxLosses)+" losses in a row -> cooldown "+
                        IntegerToString(m_ctx.cfg.ConsecCooldownMin)+" min, scope "+(InstanceScope() ? "INSTANCE" : "ENGINE"));
      return true;
     }

   //--- every closed trade of this instance (net = profit + commission + swap)
   void              OnClosed(const int engine,const double net)
     {
      if(!Ready() || !m_ctx.cfg.ConsecEnabled)
         return;
      int i=Idx(engine);
      if(i<0)
         return;
      if(net>=0.0)
        {
         if(m_count[i]>0 && CheckPointer(m_ctx.log)!=POINTER_INVALID)
            m_ctx.log.Info("CONSEC",Who(i)+": loss streak of "+IntegerToString(m_count[i])+" reset by a non-losing trade (net "+FTF_D(net,2)+")");
         m_count[i]=0;
         Save();
         return;
        }
      m_count[i]++;
      if(CheckPointer(m_ctx.log)!=POINTER_INVALID)
         m_ctx.log.Info("CONSEC",Who(i)+": loss "+IntegerToString(m_count[i])+"/"+IntegerToString(m_ctx.cfg.ConsecMaxLosses)+
                        " in a row (net "+FTF_D(net,2)+", engine "+FTF_EngineCode(engine)+")");
      if(m_count[i]>=m_ctx.cfg.ConsecMaxLosses)
        {
         int streak=m_count[i];
         m_count[i]=0;
         m_until[i]=NowMs()+CooldownMs();
         m_active[i]=true;
         m_ctx.Event("CONSEC","COOLDOWN",Who(i)+": "+IntegerToString(streak)+" consecutive losses (last net "+FTF_D(net,2)+
                     ") - no new "+Who(i)+" entries for "+IntegerToString(m_ctx.cfg.ConsecCooldownMin)+" min until "+
                     FTF_TimeMscStr(m_until[i])+"; setups refused meanwhile are burned");
        }
      Save();
     }

   bool              IsBlocked(const int engine,string &detail)
     {
      detail="";
      if(!Ready() || !m_ctx.cfg.ConsecEnabled)
         return false;
      int i=Idx(engine);
      if(i<0)
         return false;
      CheckExpiry(i);
      if(!m_active[i])
         return false;
      detail="consecutive-loss cooldown "+Who(i)+" ("+IntegerToString(m_ctx.cfg.ConsecMaxLosses)+" losses in a row) "+
             FTF_ProtDur(m_until[i]-NowMs())+" left, until "+FTF_TimeMscStr(m_until[i]);
      return true;
     }

   //--- extra: emits RESUME events for expired cooldowns without waiting for a signal
   void              Update(void)
     {
      if(!Ready())
         return;
      for(int i=0;i<=FTF_ENGINE_COUNT;i++)
         CheckExpiry(i);
     }

   long              RemainingMs(const int engine)
     {
      if(!Ready() || !m_ctx.cfg.ConsecEnabled)
         return 0;
      int i=Idx(engine);
      if(i<0 || !m_active[i])
         return 0;
      long rem=m_until[i]-NowMs();
      return (rem>0 ? rem : (long)0);
     }

   int               Count(const int engine)
     {
      if(!Ready())
         return 0;
      int i=Idx(engine);
      if(i<0)
         return 0;
      return m_count[i];
     }

   void              Save(void)
     {
      if(!StoreOk())
         return;
      for(int i=0;i<=FTF_ENGINE_COUNT;i++)
        {
         string k="cl."+IntegerToString(i)+".";
         m_ctx.state.SetLong(k+"count",(long)m_count[i]);
         m_ctx.state.SetLong(k+"until",(m_active[i] ? m_until[i] : (long)0));
        }
     }

   //--- after Init. A restored cooldown never lasts longer than one cooldown from now.
   void              Load(void)
     {
      if(!StoreOk())
         return;
      long now=NowMs();
      for(int i=0;i<=FTF_ENGINE_COUNT;i++)
        {
         string k="cl."+IntegerToString(i)+".";
         if(!m_ctx.state.Has(k+"count") && !m_ctx.state.Has(k+"until"))
            continue;
         bool relevant=(InstanceScope() ? (i==0) : (i>=1));
         if(!relevant)
            continue;                                    // scope changed since the save
         m_count[i]=(int)m_ctx.state.GetLong(k+"count",0);
         if(m_count[i]<0)
            m_count[i]=0;
         long u=m_ctx.state.GetLong(k+"until",0);
         if(u>0 && now>0 && u<=now)
           {
            if(CheckPointer(m_ctx.log)!=POINTER_INVALID)
               m_ctx.log.Info("CONSEC",Who(i)+": cooldown (end "+FTF_TimeMscStr(u)+") expired while the EA was offline");
            u=0;
           }
         if(u>0 && now>0 && u-now>CooldownMs())
            u=now+CooldownMs();
         m_until[i]=u;
         m_active[i]=(u>0);
         if(m_active[i])
            m_ctx.Event("CONSEC","RESTORE",Who(i)+": cooldown restored after restart, until "+FTF_TimeMscStr(u));
        }
     }

   //--- "CL M:1 F:0 R:2 (3 max) | R cooldown 12m"
   string            Describe(void)
     {
      if(!Ready())
         return "CL n/a";
      if(!m_ctx.cfg.ConsecEnabled)
         return "CL OFF";
      string s="CL "+Counts()+" ("+IntegerToString(m_ctx.cfg.ConsecMaxLosses)+" max)";
      for(int i=0;i<=FTF_ENGINE_COUNT;i++)
        {
         CheckExpiry(i);
         if(m_active[i])
            s+=" | "+Letter(i)+" cooldown "+FTF_ProtDur(m_until[i]-NowMs());
        }
      return s;
     }

   bool              SelfCheck(string &d)
     {
      d="";
      if(!Ready())
        {
         d="consecutive-loss guard not initialised";
         return false;
        }
      if(!m_ctx.cfg.ConsecEnabled)
        {
         d="consecutive-loss protection OFF (input)";
         return true;
        }
      bool ok=true;
      string act="";
      long now=NowMs();
      for(int i=0;i<=FTF_ENGINE_COUNT;i++)
        {
         CheckExpiry(i);
         if(!m_active[i])
            continue;
         if(m_until[i]-now>CooldownMs())
           {
            ok=false;
            m_until[i]=now+CooldownMs();                 // clamp corrupted value
            act+=Who(i)+" (clamped) ";
           }
         act+=Who(i)+" "+FTF_ProtDur(m_until[i]-now)+" ";
        }
      d="max "+IntegerToString(m_ctx.cfg.ConsecMaxLosses)+" losses, cooldown "+IntegerToString(m_ctx.cfg.ConsecCooldownMin)+
        " min, scope "+(InstanceScope() ? "INSTANCE" : "ENGINE")+", counts "+Counts()+", active cooldowns: "+
        (StringLen(act)>0 ? act : "none");
      return ok;
     }
  };

//+------------------------------------------------------------------+
//| CExecQualityGuard - rolling window of the last N fills           |
//| (adverse slippage pts, latency ms, spread pts). Table 13 / B.8.  |
//| LOG_ONLY never blocks, BLOCK blocks for a cooldown (window then  |
//| cleared), REDUCE_LOT returns a lot factor while out of tolerance.|
//+------------------------------------------------------------------+
class CExecQualityGuard
  {
private:
   CFtfContext      *m_ctx;
   double            m_slip[];
   double            m_lat[];
   double            m_spr[];
   int               m_cap;
   int               m_n;
   int               m_pos;
   long              m_fills;          // total fills seen
   bool              m_bad;            // out of tolerance (last assessment)
   string            m_badWhy;
   bool              m_blocked;        // BLOCK action running
   long              m_blockUntil;     // server ms

   bool              Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.cfg)!=POINTER_INVALID &&
              CheckPointer(m_ctx.pf)!=POINTER_INVALID);
     }
   long              NowMs(void)
     {
      long ms=m_ctx.NowMsc();
      if(ms<=0)
         ms=(long)m_ctx.pf.ServerTime()*1000;
      return ms;
     }
   int               Action(void)
     {
      return (int)m_ctx.cfg.ExecQualityAction;
     }
   string            ActionName(void)
     {
      if(Action()==FTF_EXECQ_BLOCK)
         return "BLOCK";
      if(Action()==FTF_EXECQ_REDUCE_LOT)
         return "REDUCE_LOT";
      return "LOG_ONLY";
     }
   double            AvgOf(const double &a[])
     {
      if(m_n<=0)
         return 0.0;
      double s=0.0;
      for(int i=0;i<m_n && i<ArraySize(a);i++)
         s+=a[i];
      return s/(double)m_n;
     }
   void              ClearWindow(void)
     {
      m_n=0;
      m_pos=0;
      m_bad=false;
      m_badWhy="";
     }
   string            Summary(void)
     {
      return "avg adverse slip "+FTF_D(AvgSlipPts(),2)+"pt, avg spread "+FTF_D(AvgSpreadPts(),2)+"pt, avg latency "+
             FTF_D(AvgLatencyMs(),1)+"ms (max "+FTF_D(MaxLatencyMs(),0)+"ms) over "+IntegerToString(m_n)+" fills";
     }

   //--- true when out of tolerance (needs >= FTF_PROT_EXECQ_MIN_SAMPLES fills)
   bool              Assess(string &why)
     {
      why="";
      if(m_n<FTF_PROT_EXECQ_MIN_SAMPLES)
         return false;
      bool bad=false;
      double mult=m_ctx.cfg.MaxAvgSlippageSpreadMult;
      if(mult>0.0)
        {
         double avgSpr=AvgSpreadPts();
         double base=(avgSpr>FTF_PROT_EXECQ_SPREAD_FLOOR ? avgSpr : FTF_PROT_EXECQ_SPREAD_FLOOR);
         double lim=mult*base;
         double avgSlip=AvgSlipPts();
         if(avgSlip>lim)
           {
            bad=true;
            why="avg adverse slippage "+FTF_D(avgSlip,2)+"pt > "+FTF_D(mult,2)+" x avg spread "+FTF_D(avgSpr,2)+"pt = "+FTF_D(lim,2)+"pt";
           }
        }
      if(m_ctx.cfg.MaxAvgLatencyMs>0)
        {
         double avgLat=AvgLatencyMs();
         if(avgLat>(double)m_ctx.cfg.MaxAvgLatencyMs)
           {
            if(bad)
               why+=", ";
            bad=true;
            why+="avg latency "+FTF_D(avgLat,1)+"ms > "+IntegerToString(m_ctx.cfg.MaxAvgLatencyMs)+"ms";
           }
        }
      if(bad)
         why+=" over "+IntegerToString(m_n)+" fills (max latency "+FTF_D(MaxLatencyMs(),0)+"ms)";
      return bad;
     }

   void              StartBlock(const string why)
     {
      m_blocked=true;
      m_blockUntil=NowMs()+(long)m_ctx.cfg.ExecQualityCooldownSec*1000;
      m_ctx.Event("EXECQ","BLOCK",why+" - no new entries for "+IntegerToString(m_ctx.cfg.ExecQualityCooldownSec)+
                  " s (until "+FTF_TimeMscStr(m_blockUntil)+")");
     }

   void              EndBlock(void)
     {
      m_blocked=false;
      m_blockUntil=0;
      ClearWindow();
      m_ctx.Event("EXECQ","RESUME","execution-quality cooldown of "+IntegerToString(m_ctx.cfg.ExecQualityCooldownSec)+
                  " s ended - fill window cleared, new entries allowed");
     }

   //--- called after every fill (the window only changes on fills)
   void              Reassess(void)
     {
      string why="";
      bool bad=Assess(why);
      if(bad && !m_bad)
        {
         m_bad=true;
         m_badWhy=why;
         if(Action()==FTF_EXECQ_BLOCK)
           {
            if(!m_blocked)
               StartBlock(why);
           }
         else if(Action()==FTF_EXECQ_REDUCE_LOT)
            m_ctx.Event("EXECQ","REDUCE_LOT",why+" - lot factor x"+FTF_D(m_ctx.cfg.ExecQualityLotFactor,2)+" until quality recovers");
         else
            m_ctx.Event("EXECQ","DEGRADED",why+" - LOG_ONLY: entries not affected");
         return;
        }
      if(!bad && m_bad)
        {
         m_bad=false;
         m_badWhy="";
         if(Action()!=FTF_EXECQ_BLOCK)
            m_ctx.Event("EXECQ","RECOVERED","execution quality back in tolerance: "+Summary()+
                        (Action()==FTF_EXECQ_REDUCE_LOT ? " - lot factor 1.00" : ""));
         return;
        }
      if(bad)
         m_badWhy=why;
     }

public:
                     CExecQualityGuard(void)
     {
      m_ctx=NULL; m_cap=0; m_n=0; m_pos=0; m_fills=0; m_bad=false; m_badWhy="";
      m_blocked=false; m_blockUntil=0;
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(!Ready())
         return false;
      m_cap=m_ctx.cfg.ExecQualityWindow;
      if(m_cap<FTF_PROT_EXECQ_MIN_SAMPLES)
         m_cap=FTF_PROT_EXECQ_MIN_SAMPLES;
      if(m_cap>FTF_PROT_EXECQ_MAX_WINDOW)
         m_cap=FTF_PROT_EXECQ_MAX_WINDOW;
      ArrayResize(m_slip,m_cap);
      ArrayResize(m_lat,m_cap);
      ArrayResize(m_spr,m_cap);
      for(int i=0;i<m_cap;i++)
        {
         m_slip[i]=0.0;
         m_lat[i]=0.0;
         m_spr[i]=0.0;
        }
      m_fills=0;
      m_blocked=false;
      m_blockUntil=0;
      ClearWindow();
      string lim=(m_ctx.cfg.MaxAvgSlippageSpreadMult>0.0 ? "slip <= "+FTF_D(m_ctx.cfg.MaxAvgSlippageSpreadMult,2)+" x avg spread" : "slip check off");
      lim+=(m_ctx.cfg.MaxAvgLatencyMs>0 ? ", avg latency <= "+IntegerToString(m_ctx.cfg.MaxAvgLatencyMs)+"ms" : ", latency check off");
      if(CheckPointer(m_ctx.log)!=POINTER_INVALID)
         m_ctx.log.Info("EXECQ","execution-quality guard: action "+ActionName()+", window "+IntegerToString(m_cap)+" fills (min "+
                        IntegerToString(FTF_PROT_EXECQ_MIN_SAMPLES)+"), "+lim+", cooldown "+IntegerToString(m_ctx.cfg.ExecQualityCooldownSec)+
                        " s, lot factor "+FTF_D(m_ctx.cfg.ExecQualityLotFactor,2));
      return true;
     }

   //--- adverseSlipPts > 0 = adverse. Price improvement is counted as 0 so it never masks adverse fills.
   void              OnFill(const double adverseSlipPts,const double latencyMs,const double spreadPts)
     {
      if(!Ready() || m_cap<=0)
         return;
      m_slip[m_pos]=(adverseSlipPts>0.0 ? adverseSlipPts : 0.0);
      m_lat[m_pos]=(latencyMs>0.0 ? latencyMs : 0.0);
      m_spr[m_pos]=(spreadPts>0.0 ? spreadPts : 0.0);
      m_pos=(m_pos+1)%m_cap;
      if(m_n<m_cap)
         m_n++;
      m_fills++;
      if(CheckPointer(m_ctx.log)!=POINTER_INVALID)
         m_ctx.log.Debug("EXECQ","fill #"+IntegerToString(m_fills)+": adverse slip "+FTF_D(adverseSlipPts,2)+"pt latency "+
                         FTF_D(latencyMs,1)+"ms spread "+FTF_D(spreadPts,1)+"pt | "+Summary());
      Reassess();
     }

   bool              IsBlocked(string &detail)
     {
      detail="";
      if(!Ready())
         return false;
      if(Action()==FTF_EXECQ_BLOCK)
        {
         if(!m_blocked)
            return false;
         long now=NowMs();
         if(now<m_blockUntil)
           {
            detail="execution quality poor ("+m_badWhy+") - blocked "+FTF_ProtDur(m_blockUntil-now)+" more";
            return true;
           }
         EndBlock();
         return false;
        }
      if(m_bad && CheckPointer(m_ctx.log)!=POINTER_INVALID)
         m_ctx.log.Throttled(FTF_LOG_WARN,"EXECQ.bad",m_ctx.cfg.LogThrottleMs,"EXECQ","execution quality out of tolerance: "+m_badWhy+
                             (Action()==FTF_EXECQ_REDUCE_LOT ? " - lots x"+FTF_D(m_ctx.cfg.ExecQualityLotFactor,2) : " - LOG_ONLY"));
      return false;
     }

   double            LotFactor(void)
     {
      if(!Ready())
         return 1.0;
      if(Action()==FTF_EXECQ_REDUCE_LOT && m_bad)
         return m_ctx.cfg.ExecQualityLotFactor;
      return 1.0;
     }

   double            AvgSlipPts(void)   { return AvgOf(m_slip); }
   double            AvgLatencyMs(void) { return AvgOf(m_lat); }
   double            AvgSpreadPts(void) { return AvgOf(m_spr); }   // extra
   int               Samples(void)      { return m_n; }            // extra
   bool              IsOutOfTolerance(void) { return m_bad; }      // extra

   double            MaxLatencyMs(void)
     {
      double mx=0.0;
      for(int i=0;i<m_n && i<ArraySize(m_lat);i++)
         if(m_lat[i]>mx)
            mx=m_lat[i];
      return mx;
     }

   //--- "exec slip 0.3pt lat 7.2ms (max 21) OK"
   string            Describe(void)
     {
      if(!Ready())
         return "exec n/a";
      if(m_n==0 && !m_blocked)
         return "exec no fills yet ("+ActionName()+")";
      string s="exec slip "+FTF_D(AvgSlipPts(),1)+"pt lat "+FTF_D(AvgLatencyMs(),1)+"ms (max "+FTF_D(MaxLatencyMs(),0)+") ";
      if(m_blocked)
         return s+"BLOCKED "+FTF_ProtDur(m_blockUntil-NowMs());
      if(m_bad)
         return s+(Action()==FTF_EXECQ_REDUCE_LOT ? "LOT x"+FTF_D(m_ctx.cfg.ExecQualityLotFactor,2) : "POOR");
      if(m_n<FTF_PROT_EXECQ_MIN_SAMPLES)
         return s+"OK (n="+IntegerToString(m_n)+")";
      return s+"OK";
     }

   bool              SelfCheck(string &d)
     {
      d="";
      if(!Ready() || m_cap<=0)
        {
         d="execution-quality guard not initialised";
         return false;
        }
      string lim=(m_ctx.cfg.MaxAvgSlippageSpreadMult>0.0 ? "slip <= "+FTF_D(m_ctx.cfg.MaxAvgSlippageSpreadMult,2)+" x spread" : "slip off");
      lim+=(m_ctx.cfg.MaxAvgLatencyMs>0 ? ", latency <= "+IntegerToString(m_ctx.cfg.MaxAvgLatencyMs)+"ms" : ", latency off");
      d="action "+ActionName()+", "+Summary()+" (window "+IntegerToString(m_cap)+"), limits: "+lim;
      if(m_blocked)
        {
         d+=" - BLOCKED "+FTF_ProtDur(m_blockUntil-NowMs())+" ("+m_badWhy+")";
         return false;
        }
      if(m_bad)
        {
         d+=" - OUT OF TOLERANCE: "+m_badWhy;
         return false;
        }
      if(m_n<FTF_PROT_EXECQ_MIN_SAMPLES)
         d+=" - fewer than "+IntegerToString(FTF_PROT_EXECQ_MIN_SAMPLES)+" fills, not evaluated yet";
      return true;
     }
  };

#endif // FTF_PROTECTIONS_MQH
