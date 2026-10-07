//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|  CPositionManager - manages every open position of THIS instance |
//|  on every cycle: MAE/MFE, pending-exit retries, engine-specific  |
//|  exits, time-stop, hard max holding time, break-even, trailing.  |
//|  Runs always, also during pauses/filters (docs/03 sections 6-7). |
//|  docs/09 section 7.21                                            |
//+------------------------------------------------------------------+
#ifndef FTF_POSITION_MANAGER_MQH
#define FTF_POSITION_MANAGER_MQH

#include <FranckyTriFlux\Core\EngineManager.mqh>
#include <FranckyTriFlux\Core\PositionTracker.mqh>
#include <FranckyTriFlux\Core\Execution.mqh>

#define FTF_PMG_META_SAVE_MS     2000   // TUNABLE (not an input yet): min gap between MAE/MFE metadata saves
#define FTF_PMG_EXIT_STUCK_MS    10000  // TUNABLE (not an input yet): pending exit older than this = WARN in SelfCheck

class CPositionManager
  {
private:
   CFtfContext      *m_ctx;
   CPositionTracker *m_tracker;
   CExecutionEngine *m_exec;
   CEngineManager   *m_engMgr;
   bool              m_excDirty;      // MAE/MFE changed since the last metadata save
   long              m_lastSaveMsc;
   int               m_nBe;           // break-even moves since Init (panel)
   int               m_nTrail;        // trailing moves since Init (panel)
   int               m_nExitReq;      // exits requested since Init (panel)

   bool              Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_tracker)!=POINTER_INVALID &&
              CheckPointer(m_exec)!=POINTER_INVALID && CheckPointer(m_engMgr)!=POINTER_INVALID &&
              CheckPointer(m_ctx.md)!=POINTER_INVALID && CheckPointer(m_ctx.cfg)!=POINTER_INVALID &&
              CheckPointer(m_ctx.log)!=POINTER_INVALID);
     }
   int               PriceDigits(void)
     {
      int d=m_ctx.md.DigitsCount();
      return (d>0 ? d : 5);
     }
   string            Px(const double price) { return DoubleToString(price,PriceDigits()); }
   double            NormPrice(const double price)
     {
      return FTF_NormalizePrice(price,m_ctx.md.TickSize(),m_ctx.md.DigitsCount());
     }
   string            PosHead(const int i)
     {
      return "#"+IntegerToString((long)m_tracker.pos[i].ticket)+" "+FTF_EngineCode(m_tracker.pos[i].engine)+" "+
             FTF_DirStr(m_tracker.pos[i].dir);
     }

   //--- docs/03 6.7: MAE / MFE in points on every tick (both >= 0)
   void              UpdateExcursion(const int i,const double fav)
     {
      if(fav>m_tracker.pos[i].mfePts)
        {
         m_tracker.pos[i].mfePts=fav;
         m_excDirty=true;
        }
      if(-fav>m_tracker.pos[i].maePts)
        {
         m_tracker.pos[i].maePts=-fav;
         m_excDirty=true;
        }
     }

   //--- requests an exit through the execution engine (it keeps retrying on the next cycles)
   void              RequestExit(const int i,const int code,const string detail)
     {
      m_nExitReq++;
      m_ctx.log.Info("PMG","EXIT "+FTF_ExitStr(code)+" "+PosHead(i)+" "+DoubleToString(m_tracker.pos[i].lots,2)+
                     " | "+detail);
      m_exec.Close(i,code,detail);
     }

   //--- docs/03 6.4: engine-specific exit (Momentum loss / invalidation, FVG invalidated, Range breakout)
   bool              CheckEngineExit(const int i)
     {
      CEngineBase *eng=m_engMgr.Get(m_tracker.pos[i].engine);
      if(CheckPointer(eng)==POINTER_INVALID || !eng.Enabled())
         return false;
      STrackedPos cp;
      cp=m_tracker.pos[i];
      string detail="";
      int code=eng.CheckExit(cp,detail);
      m_tracker.pos[i]=cp;                     // engine-managed fields (e.g. invStartMsc)
      if(code==FTF_EXIT_NONE)
         return false;
      RequestExit(i,code,"engine "+FTF_EngineName(m_tracker.pos[i].engine)+": "+detail);
      return true;
     }

   //--- docs/03 6.3: engine time-stop, then hard max holding time (0 = off)
   bool              CheckTimeExits(const int i,const long now)
     {
      long om=m_tracker.pos[i].openMsc;
      if(om<=0)
         return false;                          // unknown open time: never close on age
      long age=now-om;
      if(age<0)
         age=0;
      int e=m_tracker.pos[i].engine;
      int ts=m_ctx.cfg.EngineTimeStopSec(e);
      if(ts>0 && age>=(long)ts*1000)
        {
         RequestExit(i,FTF_EXIT_TIME_STOP,"age "+DoubleToString((double)age/1000.0,1)+" s >= "+FTF_EngineName(e)+
                     " time-stop "+IntegerToString(ts)+" s");
         return true;
        }
      int hm=m_ctx.cfg.HardMaxHoldSec;
      if(hm>0 && age>=(long)hm*1000)
        {
         RequestExit(i,FTF_EXIT_HARD_MAX,"age "+DoubleToString((double)age/1000.0,1)+" s >= hard max "+
                     IntegerToString(hm)+" s");
         return true;
        }
      return false;
     }

   //--- D = |initial TP - open| (fallback |TP - open|), 0 = unknown
   double            TpDistance(const int i)
     {
      double openPx=m_tracker.pos[i].openPrice;
      if(openPx<=0.0)
         return 0.0;
      if(m_tracker.pos[i].initialTP>0.0)
        {
         double d0=MathAbs(m_tracker.pos[i].initialTP-openPx);
         if(d0>0.0)
            return d0;
        }
      if(m_tracker.pos[i].tp>0.0)
         return MathAbs(m_tracker.pos[i].tp-openPx);
      return 0.0;
     }

   //--- docs/03 6.1: break-even at trigger % of D -> SL = open +/- lock % of D (only if it improves)
   void              ManageBreakEven(const int i,const double fav,const double dist,const double pt)
     {
      if(m_tracker.pos[i].beDone)
         return;
      int e=m_tracker.pos[i].engine;
      double trig=m_ctx.cfg.EngineBeTriggerPct(e);
      if(trig<=0.0)
         return;                                // 0 = break-even disabled for this engine
      double dPts=dist/pt;
      if(fav<trig/100.0*dPts)
         return;
      int dir=m_tracker.pos[i].dir;
      double lockPct=m_ctx.cfg.EngineBeLockPct(e);
      double target=NormPrice(m_tracker.pos[i].openPrice+(double)dir*lockPct/100.0*dist);
      double cur=m_tracker.pos[i].sl;
      string why="BE: favourable "+DoubleToString(fav,1)+" pts >= "+DoubleToString(trig,1)+"% of D "+
                 DoubleToString(dPts,1)+" pts -> lock "+DoubleToString(lockPct,1)+"% at "+Px(target);
      bool already=(cur>0.0 && (dir==FTF_DIR_BUY ? cur>=target-pt*0.5 : cur<=target+pt*0.5));
      if(already)
        {
         m_tracker.pos[i].beDone=true;
         m_tracker.SaveMeta(i);
         m_ctx.log.Info("PMG","BE reached "+PosHead(i)+": SL "+Px(cur)+" already at/beyond lock "+Px(target)+" | "+why);
         return;
        }
      if(m_exec.ModifySL(i,target,why))
        {
         m_tracker.pos[i].beDone=true;
         m_tracker.SaveMeta(i);
         m_nBe++;
        }
     }

   //--- docs/03 6.2: trailing at trigger % of D -> SL = price -/+ dist % of D, steps >= step % of D
   void              ManageTrailing(const int i,const double price,const double fav,const double dist,const double pt)
     {
      int e=m_tracker.pos[i].engine;
      double trig=m_ctx.cfg.EngineTrailTriggerPct(e);
      if(trig<=0.0)
         return;                                // 0 = trailing disabled for this engine
      double dPts=dist/pt;
      if(fav<trig/100.0*dPts)
         return;
      if(!m_tracker.pos[i].trailActive)
        {
         m_tracker.pos[i].trailActive=true;
         m_tracker.SaveMeta(i);
         m_ctx.log.Info("PMG","TRAIL active "+PosHead(i)+": favourable "+DoubleToString(fav,1)+" pts >= "+
                        DoubleToString(trig,1)+"% of D "+DoubleToString(dPts,1)+" pts");
        }
      int dir=m_tracker.pos[i].dir;
      double distPct=m_ctx.cfg.EngineTrailDistPct(e);
      double stepPct=m_ctx.cfg.EngineTrailStepPct(e);
      double cand=NormPrice(price-(double)dir*distPct/100.0*dist);
      double step=stepPct/100.0*dist;
      if(step<pt)
         step=pt;                               // at least 1 point
      double cur=m_tracker.pos[i].sl;
      double impr=(cur>0.0 ? (double)dir*(cand-cur) : step);
      if(impr+pt*0.01<step)
        {
         if(m_ctx.log.IsEnabled(FTF_LOG_TRACE))
            m_ctx.log.Trace("PMG","trail "+PosHead(i)+" cand "+Px(cand)+" vs SL "+Px(cur)+" improvement "+
                            DoubleToString(impr/pt,1)+" < step "+DoubleToString(step/pt,1)+" pts");
         return;
        }
      string why="TRAIL: price "+Px(price)+" - "+DoubleToString(distPct,1)+"% of D ("+DoubleToString(distPct/100.0*dPts,1)+
                 " pts) -> "+Px(cand)+", step "+DoubleToString(impr/pt,1)+" >= "+DoubleToString(step/pt,1)+" pts";
      if(m_exec.ModifySL(i,cand,why))
         m_nTrail++;
     }

   //--- one position, docs/03 section 6 order
   void              ManageOne(const int i,const long now,const double bid,const double ask,const double pt)
     {
      int dir=m_tracker.pos[i].dir;
      if(dir!=FTF_DIR_BUY && dir!=FTF_DIR_SELL)
         return;
      double openPx=m_tracker.pos[i].openPrice;
      double price=(dir==FTF_DIR_BUY ? bid : ask);       // BUY closes at bid, SELL at ask
      double fav=(openPx>0.0 ? (double)dir*(price-openPx)/pt : 0.0);
      UpdateExcursion(i,fav);
      //--- (a) exit already requested: retry until the position is gone
      if(m_tracker.pos[i].pendingExit!=FTF_EXIT_NONE)
        {
         m_exec.Close(i,m_tracker.pos[i].pendingExit,m_tracker.pos[i].pendingExitDetail);
         return;
        }
      //--- (b) engine-specific exit
      if(CheckEngineExit(i))
         return;
      //--- (c) engine time-stop, (d) hard max holding time
      if(CheckTimeExits(i,now))
         return;
      //--- (e) break-even, (f) trailing: measured on the initial TP distance D
      double dist=TpDistance(i);
      if(dist<=0.0 || openPx<=0.0)
        {
         m_ctx.log.Throttled(FTF_LOG_DEBUG,"pmg.nod."+IntegerToString((long)m_tracker.pos[i].ticket),m_ctx.cfg.LogThrottleMs,
                             "PMG",PosHead(i)+": no TP distance - break-even/trailing skipped");
         return;
        }
      ManageBreakEven(i,fav,dist,pt);
      ManageTrailing(i,price,fav,dist,pt);
     }

public:
                     CPositionManager(void)
     {
      m_ctx=NULL;
      m_tracker=NULL;
      m_exec=NULL;
      m_engMgr=NULL;
      m_excDirty=false;
      m_lastSaveMsc=0;
      m_nBe=0;
      m_nTrail=0;
      m_nExitReq=0;
     }

   bool              Init(CFtfContext *ctx,CPositionTracker *tracker,CExecutionEngine *exec,CEngineManager *engineMgr)
     {
      m_ctx=ctx;
      m_tracker=tracker;
      m_exec=exec;
      m_engMgr=engineMgr;
      if(!Ready())
         return false;
      m_excDirty=false;
      m_lastSaveMsc=0;
      string s="position manager ready: hard max "+IntegerToString(m_ctx.cfg.HardMaxHoldSec)+" s";
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         s+=" | "+FTF_EngineCode(e)+" time-stop "+IntegerToString(m_ctx.cfg.EngineTimeStopSec(e))+" s BE "+
            DoubleToString(m_ctx.cfg.EngineBeTriggerPct(e),0)+"/"+DoubleToString(m_ctx.cfg.EngineBeLockPct(e),0)+
            "% trail "+DoubleToString(m_ctx.cfg.EngineTrailTriggerPct(e),0)+"/"+DoubleToString(m_ctx.cfg.EngineTrailDistPct(e),0)+
            "/"+DoubleToString(m_ctx.cfg.EngineTrailStepPct(e),0)+"%";
      m_ctx.log.Info("PMG",s);
      return true;
     }

   //--- every cycle (OnTick/OnTimer), also during pauses and filters. Never removes positions
   void              Manage(void)
     {
      if(!Ready() || m_tracker.total<=0)
         return;
      double bid=m_ctx.md.BidPrice();
      double ask=m_ctx.md.AskPrice();
      double pt=m_ctx.md.PointSize();
      if(bid<=0.0 || ask<=0.0 || pt<=0.0)
        {
         m_ctx.log.Throttled(FTF_LOG_WARN,"pmg.quote",m_ctx.cfg.LogThrottleMs,"PMG",
                             "no valid quote (bid "+Px(bid)+" ask "+Px(ask)+") - positions not managed this cycle");
         return;
        }
      long now=m_ctx.NowMsc();
      int n=m_tracker.total;
      for(int i=0;i<n && i<m_tracker.total && i<ArraySize(m_tracker.pos);i++)
         ManageOne(i,now,bid,ask,pt);
      //--- MAE/MFE persistence is throttled (BE/trailing/exit changes are saved immediately)
      if(m_excDirty && (m_lastSaveMsc<=0 || now-m_lastSaveMsc>=FTF_PMG_META_SAVE_MS || now<m_lastSaveMsc))
        {
         m_tracker.SaveAll();
         m_lastSaveMsc=now;
         m_excDirty=false;
        }
     }

   //--- extra: panel line
   string            Describe(void)
     {
      if(!Ready())
         return "Manager: not initialised";
      int be=0;
      int tr=0;
      int closing=0;
      for(int i=0;i<m_tracker.total && i<ArraySize(m_tracker.pos);i++)
        {
         if(m_tracker.pos[i].beDone)
            be++;
         if(m_tracker.pos[i].trailActive)
            tr++;
         if(m_tracker.pos[i].pendingExit!=FTF_EXIT_NONE)
            closing++;
        }
      return "Manage: open "+IntegerToString(m_tracker.total)+" | BE "+IntegerToString(be)+" | trail "+IntegerToString(tr)+
             " | closing "+IntegerToString(closing)+" | moves BE "+IntegerToString(m_nBe)+" trail "+IntegerToString(m_nTrail)+
             " | exits req "+IntegerToString(m_nExitReq);
     }

   //--- extra: 10 % verification (true = PASS): every position protected, no exit stuck
   bool              SelfCheck(string &d)
     {
      d="";
      if(!Ready())
        {
         d="position manager not initialised";
         return false;
        }
      long now=m_ctx.NowMsc();
      int noSl=0;
      int stuck=0;
      for(int i=0;i<m_tracker.total && i<ArraySize(m_tracker.pos);i++)
        {
         if(m_tracker.pos[i].sl<=0.0)
            noSl++;
         if(m_tracker.pos[i].pendingExit!=FTF_EXIT_NONE && m_tracker.pos[i].exitRequestMsc>0 &&
            now-m_tracker.pos[i].exitRequestMsc>FTF_PMG_EXIT_STUCK_MS)
            stuck++;
        }
      d="managed "+IntegerToString(m_tracker.total)+" position(s), without SL "+IntegerToString(noSl)+
        ", exits pending > "+IntegerToString(FTF_PMG_EXIT_STUCK_MS/1000)+" s: "+IntegerToString(stuck)+
        ", hard max "+IntegerToString(m_ctx.cfg.HardMaxHoldSec)+" s";
      return (noSl==0 && stuck==0);
     }
  };

#endif // FTF_POSITION_MANAGER_MQH
