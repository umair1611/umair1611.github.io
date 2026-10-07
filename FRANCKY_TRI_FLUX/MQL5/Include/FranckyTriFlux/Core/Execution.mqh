//+------------------------------------------------------------------+
//|                                                    Execution.mqh |
//|  CExecutionEngine - market orders, closes and SL modifications   |
//|  of THIS instance (chart symbol, own magics) through CPlatform.  |
//|  Non-blocking retries (FIFO queue), fatal-error cooldown, close  |
//|  retry throttle, stops/freeze/min-interval checks on modify.     |
//|  docs/09 section 7.19, docs/03 sections 5-6, spec B.8            |
//+------------------------------------------------------------------+
#ifndef FTF_EXECUTION_MQH
#define FTF_EXECUTION_MQH

#include <FranckyTriFlux\Core\Context.mqh>
#include <FranckyTriFlux\Core\PositionTracker.mqh>
#include <FranckyTriFlux\Core\Protections.mqh>

#define FTF_EXEC_MAX_RETRY_QUEUE     16     // TUNABLE (not an input yet): max queued order retries
#define FTF_EXEC_CLOSE_RETRY_MS      250    // TUNABLE (not an input yet): min gap between 2 close attempts of a position
#define FTF_EXEC_CLOSE_SLOW_MS       2000   // TUNABLE (not an input yet): gap after FTF_EXEC_CLOSE_FAST_TRIES failures
#define FTF_EXEC_CLOSE_FAST_TRIES    20     // TUNABLE (not an input yet)
#define FTF_EXEC_COMMENT_MAX         31     // broker order comment limit (MT4 and MT5)

class CExecutionEngine
  {
private:
   CFtfContext       *m_ctx;
   CPositionTracker  *m_tracker;
   CExecQualityGuard *m_execQ;
   bool               m_isTester;
   //--- retry queue (FIFO, parallel arrays)
   SSignal            m_rSig[];
   double             m_rLots[];
   double             m_rRisk[];
   int                m_rAttempt[];
   long               m_rQueuedMsc[];
   ulong              m_rQueuedUs[];
   int                m_rCount;
   //--- fatal broker error cooldown
   bool               m_errActive;
   long               m_errStartMsc;
   ulong              m_errStartUs;
   string             m_errText;
   //--- close attempt throttle per ticket
   ulong              m_cTicket[];
   long               m_cLastMsc[];
   ulong              m_cLastUs[];
   int                m_cCount;
   //--- counters (panel / self-check)
   int                m_nOpenOk;
   int                m_nOpenFail;
   int                m_nCloseOk;
   int                m_nCloseFail;
   int                m_nModOk;
   int                m_nModFail;
   string             m_lastError;

   //--- helpers --------------------------------------------------------
   bool               Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_tracker)!=POINTER_INVALID &&
              CheckPointer(m_ctx.pf)!=POINTER_INVALID && CheckPointer(m_ctx.md)!=POINTER_INVALID &&
              CheckPointer(m_ctx.cfg)!=POINTER_INVALID && CheckPointer(m_ctx.log)!=POINTER_INVALID);
     }
   int                PriceDigits(void)
     {
      int d=m_ctx.md.DigitsCount();
      return (d>0 ? d : 5);
     }
   string             Px(const double price)         { return DoubleToString(price,PriceDigits()); }
   string             TicketStr(const ulong ticket)  { return IntegerToString((long)ticket); }
   double             NormPrice(const double price)
     {
      if(price<=0.0)
         return 0.0;
      return FTF_NormalizePrice(price,m_ctx.md.TickSize(),m_ctx.md.DigitsCount());
     }
   //--- elapsed ms: server clock, plus the local clock when live (server ms stalls without ticks)
   long               ElapsedMs(const long startMsc,const ulong startUs)
     {
      long el=0;
      long now=m_ctx.NowMsc();
      if(startMsc>0 && now>startMsc)
         el=now-startMsc;
      if(!m_isTester && startUs>0)
        {
         ulong us=m_ctx.pf.Micros();
         if(us>startUs)
           {
            long wall=(long)((us-startUs)/1000);
            if(wall>el)
               el=wall;
           }
        }
      return el;
     }
   int                MaxRetries(void)
     {
      return (m_ctx.cfg.MaxRetries>0 ? m_ctx.cfg.MaxRetries : 0);
     }
   bool               ValidIndex(const int idx)
     {
      return (idx>=0 && idx<m_tracker.total && idx<ArraySize(m_tracker.pos));
     }
   string             SigText(const SSignal &sig,const double lots)
     {
      return FTF_EngineCode(sig.engine)+" "+FTF_DirStr(sig.dir)+" "+DoubleToString(lots,2)+" lots setup "+sig.setupId;
     }

   //--- "FTF|MOM|I1|<setup suffix>" truncated to 31 chars (the magic number is the real id)
   string             BuildComment(const SSignal &sig)
     {
      string head=m_ctx.cfg.CommentPrefix+"|"+FTF_EngineCode(sig.engine)+"|I"+IntegerToString(m_ctx.instanceId)+"|";
      string sid=sig.setupId;
      StringReplace(sid," ","");
      StringReplace(sid,":","");
      int room=FTF_EXEC_COMMENT_MAX-StringLen(head);
      string tail="";
      int len=StringLen(sid);
      if(room>0 && len>0)
         tail=(len<=room ? sid : StringSubstr(sid,len-room,room));
      string c=head+tail;
      if(StringLen(c)>FTF_EXEC_COMMENT_MAX)
         c=StringSubstr(c,0,FTF_EXEC_COMMENT_MAX);
      return c;
     }

   //--- retry queue -----------------------------------------------------
   void               RemoveRetryAt(const int i)
     {
      if(i<0 || i>=m_rCount)
         return;
      for(int k=i;k<m_rCount-1;k++)
        {
         m_rSig[k]=m_rSig[k+1];
         m_rLots[k]=m_rLots[k+1];
         m_rRisk[k]=m_rRisk[k+1];
         m_rAttempt[k]=m_rAttempt[k+1];
         m_rQueuedMsc[k]=m_rQueuedMsc[k+1];
         m_rQueuedUs[k]=m_rQueuedUs[k+1];
        }
      m_rCount--;
      if(m_rCount<0)
         m_rCount=0;
      ArrayResize(m_rSig,m_rCount);
      ArrayResize(m_rLots,m_rCount);
      ArrayResize(m_rRisk,m_rCount);
      ArrayResize(m_rAttempt,m_rCount);
      ArrayResize(m_rQueuedMsc,m_rCount);
      ArrayResize(m_rQueuedUs,m_rCount);
     }

   void               QueueRetry(const SSignal &sig,const double lots,const double riskMoney,const int attempt)
     {
      //--- one queued retry per setup (a newer failure replaces the older item)
      for(int i=m_rCount-1;i>=0;i--)
         if(m_rSig[i].engine==sig.engine && m_rSig[i].setupId==sig.setupId)
            RemoveRetryAt(i);
      if(m_rCount>=FTF_EXEC_MAX_RETRY_QUEUE)
        {
         m_ctx.log.Warn("EXEC","retry queue full - oldest retry dropped: "+SigText(m_rSig[0],m_rLots[0]));
         RemoveRetryAt(0);
        }
      int n=m_rCount+1;
      ArrayResize(m_rSig,n);
      ArrayResize(m_rLots,n);
      ArrayResize(m_rRisk,n);
      ArrayResize(m_rAttempt,n);
      ArrayResize(m_rQueuedMsc,n);
      ArrayResize(m_rQueuedUs,n);
      m_rSig[m_rCount]=sig;
      m_rLots[m_rCount]=lots;
      m_rRisk[m_rCount]=riskMoney;
      m_rAttempt[m_rCount]=attempt;
      m_rQueuedMsc[m_rCount]=m_ctx.NowMsc();
      m_rQueuedUs[m_rCount]=m_ctx.pf.Micros();
      m_rCount=n;
     }

   //--- close throttle slot of a ticket (created on demand, pruned when the ticket is gone)
   int                CloseSlot(const ulong ticket)
     {
      for(int i=0;i<m_cCount;i++)
         if(m_cTicket[i]==ticket)
            return i;
      if(m_cCount>=32)
         PruneCloseSlots();
      int n=m_cCount+1;
      ArrayResize(m_cTicket,n);
      ArrayResize(m_cLastMsc,n);
      ArrayResize(m_cLastUs,n);
      m_cTicket[m_cCount]=ticket;
      m_cLastMsc[m_cCount]=0;
      m_cLastUs[m_cCount]=0;
      m_cCount=n;
      return m_cCount-1;
     }

   void               PruneCloseSlots(void)
     {
      int w=0;
      for(int i=0;i<m_cCount;i++)
        {
         if(m_tracker.IndexOf(m_cTicket[i])<0)
            continue;
         m_cTicket[w]=m_cTicket[i];
         m_cLastMsc[w]=m_cLastMsc[i];
         m_cLastUs[w]=m_cLastUs[i];
         w++;
        }
      m_cCount=w;
      ArrayResize(m_cTicket,w);
      ArrayResize(m_cLastMsc,w);
      ArrayResize(m_cLastUs,w);
     }

   //--- open: success / failure handling ---------------------------------
   void               FillPosition(const SSignal &sig,const double lots,const double riskMoney,const int attempt,
                                   const double decisionMs,const double refPx,const double sl,const double tp,
                                   const SExecResult &res,STrackedPos &outPos)
     {
      double pt=m_ctx.md.PointSize();
      double req=(res.requestedPrice>0.0 ? res.requestedPrice : refPx);
      double fill=(res.fillPrice>0.0 ? res.fillPrice : req);
      outPos.Reset();
      outPos.ticket=res.ticket;
      outPos.positionId=(res.positionId>0 ? res.positionId : (long)res.ticket);
      outPos.engine=sig.engine;
      outPos.dir=sig.dir;
      outPos.setupId=sig.setupId;
      outPos.lots=(res.lots>0.0 ? res.lots : lots);
      outPos.openPrice=fill;
      outPos.initialSL=sl;
      outPos.initialTP=tp;
      outPos.sl=sl;
      outPos.tp=tp;
      outPos.openMsc=m_ctx.NowMsc();
      outPos.signalMsc=sig.timeMsc;
      outPos.signalPrice=sig.price;
      outPos.requestedPrice=req;
      outPos.slippagePts=(pt>0.0 ? (fill-req)*(double)sig.dir/pt : 0.0);   // positive = adverse
      outPos.latencyMs=res.latencyMs;
      outPos.decisionMs=decisionMs;
      outPos.spreadPts=sig.spreadPts;
      outPos.retries=attempt;
      outPos.riskMoney=riskMoney;
      outPos.equityAtEntry=m_ctx.pf.Equity();
      outPos.ddPctAtEntry=0.0;                                           // set by the controller (drawdown guard)
      outPos.h1State=sig.h1State;
      outPos.mode=m_ctx.mode;
      outPos.entryReason=sig.reason;
      outPos.tfText=sig.tfText;
      outPos.refLevel=sig.invalidation;
      outPos.recovered=false;
     }

   int                OnOpenFailure(const SSignal &sig,const double lots,const double riskMoney,const int attempt,
                                    const SExecResult &res,string &detail)
     {
      int code=res.retcode;
      string txt=res.retcodeText;
      if(StringLen(txt)==0)
         txt=m_ctx.pf.ErrorText(code);
      int cls=res.errClass;
      if(cls==FTF_ERR_NONE)
         cls=m_ctx.pf.ClassifyError(code);
      if(cls==FTF_ERR_NONE)
         cls=FTF_ERR_PERMANENT;           // failed without a class: never retry blindly
      int maxR=MaxRetries();
      detail=IntegerToString(code)+" "+txt+" attempt "+IntegerToString(attempt+1)+"/"+IntegerToString(maxR+1);
      string what=SigText(sig,lots)+" | "+detail;
      m_nOpenFail++;
      m_lastError=detail;
      switch(cls)
        {
         case FTF_ERR_TRANSIENT:
            if(attempt<maxR)
              {
               QueueRetry(sig,lots,riskMoney,attempt+1);
               detail+=" - retry queued in "+IntegerToString(m_ctx.cfg.RetryDelayMs)+" ms";
               m_ctx.log.Warn("EXEC","OPEN FAILED (transient) "+what+" - retry queued in "+
                              IntegerToString(m_ctx.cfg.RetryDelayMs)+" ms");
               m_ctx.Event("RETRY","QUEUED",what);
              }
            else
              {
               detail+=" - retries exhausted";
               m_ctx.log.Warn("EXEC","OPEN FAILED (transient, retries exhausted) "+what);
               m_ctx.Event("ORDER","REJECTED",what+" - retries exhausted");
              }
            break;
         case FTF_ERR_FATAL:
            StartErrorCooldown(detail);
            m_ctx.log.Error("EXEC","OPEN FAILED (fatal) "+what+" - new entries paused "+
                            IntegerToString(m_ctx.cfg.FatalErrorCooldownSec)+" s");
            m_ctx.Event("ERROR","FATAL",what+" - entries paused "+IntegerToString(m_ctx.cfg.FatalErrorCooldownSec)+" s");
            break;
         default:
            m_ctx.log.Warn("EXEC","OPEN FAILED (permanent) "+what);
            m_ctx.Event("ORDER","REJECTED",what);
            break;
        }
      return FTF_REJ_ORDER_FAILED;
     }

   void               StartErrorCooldown(const string why)
     {
      if(m_ctx.cfg.FatalErrorCooldownSec<=0)
         return;
      m_errActive=true;
      m_errStartMsc=m_ctx.NowMsc();
      m_errStartUs=m_ctx.pf.Micros();
      m_errText=why;
     }

   //--- close: one broker attempt -----------------------------------------
   bool               SendClose(const int idx)
     {
      ulong tk=m_tracker.pos[idx].ticket;
      int dir=m_tracker.pos[idx].dir;
      double lots=m_tracker.pos[idx].lots;
      double openPx=m_tracker.pos[idx].openPrice;
      double pt=m_ctx.md.PointSize();
      double px=(dir==FTF_DIR_BUY ? m_ctx.md.BidPrice() : m_ctx.md.AskPrice());
      double favPts=(pt>0.0 && openPx>0.0 ? (double)dir*(px-openPx)/pt : 0.0);
      int dev=DeviationPts();
      int tries=m_tracker.pos[idx].exitAttempts+1;
      string head="#"+TicketStr(tk)+" "+FTF_EngineCode(m_tracker.pos[idx].engine)+" "+FTF_DirStr(dir)+" "+
                  DoubleToString(lots,2)+" exit "+FTF_ExitStr(m_tracker.pos[idx].pendingExit);
      string msg="CLOSE send "+head+" @"+Px(px)+" (open "+Px(openPx)+", "+DoubleToString(favPts,1)+" pts) dev "+
                 IntegerToString(dev)+" pts attempt "+IntegerToString(tries)+" | "+m_tracker.pos[idx].pendingExitDetail;
      if(tries<=3 || (tries%10)==0)
         m_ctx.log.Info("EXEC",msg);
      else
         m_ctx.log.Throttled(FTF_LOG_INFO,"exec.close."+TicketStr(tk),m_ctx.cfg.LogThrottleMs,"EXEC",msg);
      SExecResult res;
      res.Reset();
      bool ok=m_ctx.pf.ClosePosition(tk,lots,dev,res);
      m_tracker.pos[idx].exitAttempts=tries;
      if(ok && res.ok)
        {
         m_nCloseOk++;
         string done=head+" fill "+Px(res.fillPrice)+" (req "+Px(res.requestedPrice)+") latency "+
                     DoubleToString(res.latencyMs,1)+" ms attempt "+IntegerToString(tries);
         m_ctx.log.Info("EXEC","CLOSE OK "+done);
         m_ctx.Event("ORDER","CLOSE",done+" | "+m_tracker.pos[idx].pendingExitDetail);
         return true;
        }
      m_nCloseFail++;
      string txt=(StringLen(res.retcodeText)>0 ? res.retcodeText : m_ctx.pf.ErrorText(res.retcode));
      string fail=head+" retcode "+IntegerToString(res.retcode)+" "+txt+" attempt "+IntegerToString(tries)+
                  " - retried in "+IntegerToString(tries>=FTF_EXEC_CLOSE_FAST_TRIES ? FTF_EXEC_CLOSE_SLOW_MS : FTF_EXEC_CLOSE_RETRY_MS)+" ms";
      m_lastError=fail;
      if(tries==1)
         m_ctx.Event("ORDER","CLOSE_FAILED",fail);
      if(tries<=3 || (tries%10)==0)
         m_ctx.log.Warn("EXEC","CLOSE FAILED "+fail);
      else
         m_ctx.log.Throttled(FTF_LOG_WARN,"exec.closefail."+TicketStr(tk),m_ctx.cfg.LogThrottleMs,"EXEC","CLOSE FAILED "+fail);
      return false;
     }

   //--- modify: broker distance rules (true = allowed now); why explains a refusal
   bool               ModifyAllowed(const int idx,const double nsl,string &why)
     {
      why="";
      int dir=m_tracker.pos[idx].dir;
      double cur=m_tracker.pos[idx].sl;
      double tpx=m_tracker.pos[idx].tp;
      double pt=m_ctx.md.PointSize();
      double bid=m_ctx.md.BidPrice();
      double ask=m_ctx.md.AskPrice();
      //--- 1. must improve the SL (BUY higher, SELL lower or no SL yet)
      bool improves=(dir==FTF_DIR_BUY ? (nsl-cur>pt*0.5) : (cur<=0.0 || cur-nsl>pt*0.5));
      if(!improves)
        {
         why="not an improvement (SL "+Px(cur)+" -> "+Px(nsl)+")";
         return false;
        }
      //--- 2. stops level: distance between the close price and the new SL
      int stopsPts=(m_ctx.md.spec.stopsLevelPts>0 ? m_ctx.md.spec.stopsLevelPts : 0);
      double dist=(dir==FTF_DIR_BUY ? bid-nsl : nsl-ask);
      if(dist<=0.0 || dist<(double)stopsPts*pt-pt*0.01)
        {
         why="stops level: distance "+DoubleToString(pt>0.0 ? dist/pt : 0.0,1)+" pts < "+IntegerToString(stopsPts)+" pts";
         return false;
        }
      //--- 3. freeze level: no modification while price is within freeze distance of SL or TP
      int frz=m_ctx.md.spec.freezeLevelPts;
      if(frz>0)
        {
         double fz=(double)frz*pt;
         double px=(dir==FTF_DIR_BUY ? bid : ask);
         if((cur>0.0 && MathAbs(px-cur)<=fz) || (tpx>0.0 && MathAbs(px-tpx)<=fz))
           {
            why="freeze level "+IntegerToString(frz)+" pts (price "+Px(px)+" SL "+Px(cur)+" TP "+Px(tpx)+")";
            return false;
           }
        }
      //--- 4. min interval between two modifications of the same position
      long last=m_tracker.pos[idx].lastModifyMsc;
      long gap=(long)m_ctx.cfg.MinModifyIntervalMs;
      if(gap>0 && last>0)
        {
         long since=m_ctx.NowMsc()-last;
         if(since>=0 && since<gap)
           {
            why="min modify interval ("+IntegerToString(since)+" < "+IntegerToString(gap)+" ms)";
            return false;
           }
        }
      return true;
     }

public:
                      CExecutionEngine(void)
     {
      m_ctx=NULL;
      m_tracker=NULL;
      m_execQ=NULL;
      m_isTester=false;
      m_rCount=0;
      m_errActive=false;
      m_errStartMsc=0;
      m_errStartUs=0;
      m_errText="";
      m_cCount=0;
      m_nOpenOk=0;
      m_nOpenFail=0;
      m_nCloseOk=0;
      m_nCloseFail=0;
      m_nModOk=0;
      m_nModFail=0;
      m_lastError="";
     }

   bool               Init(CFtfContext *ctx,CPositionTracker *tracker,CExecQualityGuard *execQ)
     {
      m_ctx=ctx;
      m_tracker=tracker;
      m_execQ=execQ;
      if(!Ready())
         return false;
      m_isTester=m_ctx.pf.IsTester();
      m_rCount=0;
      ArrayResize(m_rSig,0);
      ArrayResize(m_rLots,0);
      ArrayResize(m_rRisk,0);
      ArrayResize(m_rAttempt,0);
      ArrayResize(m_rQueuedMsc,0);
      ArrayResize(m_rQueuedUs,0);
      m_cCount=0;
      ArrayResize(m_cTicket,0);
      ArrayResize(m_cLastMsc,0);
      ArrayResize(m_cLastUs,0);
      m_errActive=false;
      m_ctx.log.Info("EXEC","execution ready: deviation "+(m_ctx.cfg.MaxDeviationPts>0 ? IntegerToString(m_ctx.cfg.MaxDeviationPts)+" pts" :
                     "auto "+DoubleToString(m_ctx.cfg.AutoDeviationSpreadMult,2)+" x spread")+
                     " | retries "+IntegerToString(MaxRetries())+" x "+IntegerToString(m_ctx.cfg.RetryDelayMs)+" ms"+
                     " | fatal-error pause "+IntegerToString(m_ctx.cfg.FatalErrorCooldownSec)+" s"+
                     " | min modify interval "+IntegerToString(m_ctx.cfg.MinModifyIntervalMs)+" ms"+
                     " | exec-quality guard "+(CheckPointer(m_execQ)!=POINTER_INVALID ? "linked" : "MISSING"));
      return true;
     }

   //--- market entry. attempt = 0 for the first send, n for the n-th retry
   int                Open(const SSignal &sig,const double lots,const double riskMoney,const int attempt,const ulong cycleStartUs,
                           STrackedPos &outPos,string &detail)
     {
      outPos.Reset();
      detail="";
      if(!Ready())
        {
         detail="execution engine not initialised";
         return FTF_REJ_ORDER_FAILED;
        }
      if((sig.dir!=FTF_DIR_BUY && sig.dir!=FTF_DIR_SELL) || sig.engine<1 || sig.engine>FTF_ENGINE_COUNT || lots<=0.0)
        {
         detail="invalid order (engine "+IntegerToString(sig.engine)+" dir "+IntegerToString(sig.dir)+" lots "+DoubleToString(lots,2)+")";
         m_ctx.log.Error("EXEC","OPEN refused: "+detail);
         return FTF_REJ_ORDER_FAILED;
        }
      int dev=DeviationPts();
      string comment=BuildComment(sig);
      long magic=m_ctx.MagicFor(sig.engine);
      double sl=NormPrice(sig.sl);
      double tp=NormPrice(sig.tp);
      double bid=m_ctx.md.BidPrice();
      double ask=m_ctx.md.AskPrice();
      double refPx=(sig.dir==FTF_DIR_BUY ? ask : bid);
      double pt=m_ctx.md.PointSize();
      ulong sendUs=m_ctx.pf.Micros();
      double decisionMs=0.0;
      if(cycleStartUs>0 && sendUs>=cycleStartUs)
         decisionMs=(double)(sendUs-cycleStartUs)/1000.0;
      m_ctx.log.Info("EXEC","OPEN send "+SigText(sig,lots)+" @"+(sig.dir==FTF_DIR_BUY ? "ask " : "bid ")+Px(refPx)+
                     " (signal "+Px(sig.price)+", bid "+Px(bid)+" ask "+Px(ask)+")"+
                     " SL "+Px(sl)+" ("+DoubleToString(pt>0.0 ? MathAbs(refPx-sl)/pt : 0.0,1)+" pts)"+
                     " TP "+Px(tp)+" ("+DoubleToString(pt>0.0 ? MathAbs(tp-refPx)/pt : 0.0,1)+" pts)"+
                     " spread "+DoubleToString(sig.spreadPts,1)+" pts dev "+IntegerToString(dev)+" pts"+
                     " risk "+DoubleToString(riskMoney,2)+" magic "+IntegerToString(magic)+" '"+comment+"'"+
                     " attempt "+IntegerToString(attempt+1)+"/"+IntegerToString(MaxRetries()+1)+
                     " decision "+DoubleToString(decisionMs,2)+" ms");
      SExecResult res;
      res.Reset();
      bool ok=m_ctx.pf.OpenMarket(sig.dir,lots,sl,tp,magic,comment,dev,res);
      if(ok && res.ok && res.ticket>0)
        {
         FillPosition(sig,lots,riskMoney,attempt,decisionMs,refPx,sl,tp,res,outPos);
         m_nOpenOk++;
         if(CheckPointer(m_execQ)!=POINTER_INVALID)
            m_execQ.OnFill(outPos.slippagePts,outPos.latencyMs,outPos.spreadPts);
         detail="#"+TicketStr(outPos.ticket)+" "+FTF_EngineCode(sig.engine)+" "+FTF_DirStr(sig.dir)+" "+
                DoubleToString(outPos.lots,2)+" @"+Px(outPos.openPrice)+" req "+Px(outPos.requestedPrice)+
                " slip "+DoubleToString(outPos.slippagePts,1)+" pts latency "+DoubleToString(outPos.latencyMs,1)+
                " ms decision "+DoubleToString(decisionMs,2)+" ms retries "+IntegerToString(attempt);
         m_ctx.log.Info("EXEC","OPEN OK "+detail+" SL "+Px(sl)+" TP "+Px(tp)+" equity "+DoubleToString(outPos.equityAtEntry,2)+
                        " setup "+sig.setupId+" | "+sig.reason);
         m_ctx.Event("ORDER","OPEN",detail+" setup "+sig.setupId);
         return FTF_OK;
        }
      if(ok && res.ok)
        {
         //--- accepted without a ticket: never resend (duplicate risk); the tracker recovers it from the broker
         detail="order accepted but no ticket returned - position will be recovered by the tracker";
         m_nOpenFail++;
         m_lastError=detail;
         m_ctx.log.Warn("EXEC","OPEN "+SigText(sig,lots)+": "+detail);
         m_ctx.Event("ORDER","NO_TICKET",SigText(sig,lots));
         return FTF_REJ_ORDER_FAILED;
        }
      return OnOpenFailure(sig,lots,riskMoney,attempt,res,detail);
     }

   //--- first due retry (FIFO). The caller revalidates the signal before Open(...,attempt,...)
   bool               PopDueRetry(SSignal &sig,double &lots,double &riskMoney,int &attempt)
     {
      if(!Ready() || m_rCount<=0)
         return false;
      long delay=(long)(m_ctx.cfg.RetryDelayMs>0 ? m_ctx.cfg.RetryDelayMs : 0);
      for(int i=0;i<m_rCount;i++)
        {
         if(ElapsedMs(m_rQueuedMsc[i],m_rQueuedUs[i])<delay)
            continue;
         sig=m_rSig[i];
         lots=m_rLots[i];
         riskMoney=m_rRisk[i];
         attempt=m_rAttempt[i];
         RemoveRetryAt(i);
         m_ctx.log.Debug("EXEC","retry due: "+SigText(sig,lots)+" attempt "+IntegerToString(attempt+1)+"/"+
                         IntegerToString(MaxRetries()+1)+" ("+IntegerToString(m_rCount)+" still queued)");
         return true;
        }
      return false;
     }

   int                PendingRetries(void)
     {
      return m_rCount;
     }

   bool               InErrorCooldown(string &detail)
     {
      detail="";
      if(!m_errActive || !Ready())
         return false;
      long cdMs=(long)m_ctx.cfg.FatalErrorCooldownSec*1000;
      long el=ElapsedMs(m_errStartMsc,m_errStartUs);
      if(el>=cdMs)
        {
         m_errActive=false;
         m_ctx.Event("ERROR","COOLDOWN_END","fatal-error pause over after "+IntegerToString(el/1000)+" s ("+m_errText+")");
         return false;
        }
      detail="fatal broker error ("+m_errText+") - "+IntegerToString((cdMs-el+999)/1000)+" s left";
      return true;
     }

   //--- close a tracked position (index into tracker.pos). Retried by the position manager until gone
   bool               Close(const int idx,const int exitCode,const string detail)
     {
      if(!Ready() || !ValidIndex(idx))
         return false;
      long now=m_ctx.NowMsc();
      if(m_tracker.pos[idx].pendingExit==FTF_EXIT_NONE)
        {
         m_tracker.pos[idx].pendingExit=(exitCode!=FTF_EXIT_NONE ? exitCode : FTF_EXIT_UNKNOWN);
         m_tracker.pos[idx].pendingExitDetail=detail;
         m_tracker.pos[idx].exitRequestMsc=now;
         m_tracker.pos[idx].exitAttempts=0;
         m_ctx.log.Info("EXEC","EXIT request #"+TicketStr(m_tracker.pos[idx].ticket)+" "+
                        FTF_EngineCode(m_tracker.pos[idx].engine)+" "+FTF_DirStr(m_tracker.pos[idx].dir)+" "+
                        FTF_ExitStr(m_tracker.pos[idx].pendingExit)+" | "+detail);
         m_tracker.SaveMeta(idx);
        }
      else if(m_tracker.pos[idx].exitRequestMsc<=0)
         m_tracker.pos[idx].exitRequestMsc=now;
      //--- at most one attempt every 250 ms (2 s after 20 failures)
      int slot=CloseSlot(m_tracker.pos[idx].ticket);
      if(slot<0 || slot>=m_cCount)
         return false;
      long gap=(m_tracker.pos[idx].exitAttempts>=FTF_EXEC_CLOSE_FAST_TRIES ? FTF_EXEC_CLOSE_SLOW_MS : FTF_EXEC_CLOSE_RETRY_MS);
      if((m_cLastMsc[slot]>0 || m_cLastUs[slot]>0) && ElapsedMs(m_cLastMsc[slot],m_cLastUs[slot])<gap)
         return false;
      m_cLastMsc[slot]=now;
      m_cLastUs[slot]=m_ctx.pf.Micros();
      return SendClose(idx);
     }

   //--- move the SL of a tracked position (break-even / trailing). true = modified at the broker
   bool               ModifySL(const int idx,const double newSL,const string why)
     {
      if(!Ready() || !ValidIndex(idx))
         return false;
      if(m_tracker.pos[idx].pendingExit!=FTF_EXIT_NONE)
         return false;                                   // closing: never touch the SL
      double pt=m_ctx.md.PointSize();
      double nsl=NormPrice(newSL);
      if(pt<=0.0 || nsl<=0.0)
         return false;
      ulong tk=m_tracker.pos[idx].ticket;
      string refusal="";
      if(!ModifyAllowed(idx,nsl,refusal))
        {
         m_ctx.log.Throttled(FTF_LOG_DEBUG,"exec.mod."+TicketStr(tk),m_ctx.cfg.LogThrottleMs,"EXEC",
                             "SL modify #"+TicketStr(tk)+" skipped: "+refusal+" | "+why);
         return false;
        }
      int dir=m_tracker.pos[idx].dir;
      double old=m_tracker.pos[idx].sl;
      double tpx=m_tracker.pos[idx].tp;
      double bid=m_ctx.md.BidPrice();
      double ask=m_ctx.md.AskPrice();
      long now=m_ctx.NowMsc();
      string head="#"+TicketStr(tk)+" "+FTF_EngineCode(m_tracker.pos[idx].engine)+" "+FTF_DirStr(dir)+" SL "+
                  Px(old)+" -> "+Px(nsl)+(old>0.0 ? " ("+DoubleToString((double)dir*(nsl-old)/pt,1)+" pts)" : "")+
                  " TP "+Px(tpx)+" bid "+Px(bid)+" ask "+Px(ask);
      SExecResult res;
      res.Reset();
      bool ok=m_ctx.pf.ModifyPosition(tk,nsl,tpx,res);
      m_tracker.pos[idx].lastModifyMsc=now;               // also after a failure: respects the min interval
      if(ok && res.ok)
        {
         m_nModOk++;
         m_tracker.pos[idx].sl=nsl;
         m_tracker.SaveMeta(idx);
         m_ctx.log.Info("EXEC","SL MODIFY OK "+head+" latency "+DoubleToString(res.latencyMs,1)+" ms | "+why);
         return true;
        }
      m_nModFail++;
      string txt=(StringLen(res.retcodeText)>0 ? res.retcodeText : m_ctx.pf.ErrorText(res.retcode));
      m_lastError="modify "+head+" retcode "+IntegerToString(res.retcode)+" "+txt;
      m_ctx.log.Throttled(FTF_LOG_WARN,"exec.modfail."+TicketStr(tk),m_ctx.cfg.LogThrottleMs,"EXEC",
                          "SL MODIFY FAILED "+head+" retcode "+IntegerToString(res.retcode)+" "+txt+" | "+why);
      return false;
     }

   //--- deviation in points: input, or auto = spread x multiplier (>= 1)
   int                DeviationPts(void)
     {
      if(CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_ctx.cfg)==POINTER_INVALID)
         return 1;
      if(m_ctx.cfg.MaxDeviationPts>0)
         return m_ctx.cfg.MaxDeviationPts;
      if(CheckPointer(m_ctx.md)==POINTER_INVALID)
         return 1;
      int d=(int)MathRound(m_ctx.md.SpreadPts()*m_ctx.cfg.AutoDeviationSpreadMult);
      return (d<1 ? 1 : d);
     }

   //--- extra: panel line
   string             Describe(void)
     {
      if(!Ready())
         return "Execution: not initialised";
      string cd="";
      string s="Exec dev "+IntegerToString(DeviationPts())+" pts | open "+IntegerToString(m_nOpenOk)+"/"+
               IntegerToString(m_nOpenOk+m_nOpenFail)+" | close fail "+IntegerToString(m_nCloseFail)+
               " | SL mod "+IntegerToString(m_nModOk)+"/"+IntegerToString(m_nModOk+m_nModFail)+
               " | retries "+IntegerToString(m_rCount);
      if(InErrorCooldown(cd))
         s+=" | PAUSED: "+cd;
      return s;
     }

   //--- extra: 10 % verification (true = PASS)
   bool               SelfCheck(string &d)
     {
      d="";
      if(!Ready())
        {
         d="execution engine not initialised";
         return false;
        }
      bool pass=true;
      string why="";
      bool allowed=m_ctx.pf.TradeAllowed(why);
      if(!allowed)
         pass=false;
      if(m_ctx.md.PointSize()<=0.0 || m_ctx.md.TickSize()<=0.0)
         pass=false;
      string cd="";
      bool cooling=InErrorCooldown(cd);
      if(cooling)
         pass=false;
      if(CheckPointer(m_execQ)==POINTER_INVALID)
         pass=false;
      d="trade allowed "+(allowed ? "yes" : "NO ("+why+")")+", deviation "+IntegerToString(DeviationPts())+" pts"+
        ", point "+DoubleToString(m_ctx.md.PointSize(),8)+", stops "+IntegerToString(m_ctx.md.spec.stopsLevelPts)+
        " / freeze "+IntegerToString(m_ctx.md.spec.freezeLevelPts)+" pts, retries queued "+IntegerToString(m_rCount)+
        ", error cooldown "+(cooling ? cd : "none")+", exec-quality guard "+
        (CheckPointer(m_execQ)!=POINTER_INVALID ? "linked" : "MISSING");
      return pass;
     }

   //--- extra: last broker error text (panel / report)
   string             LastError(void)
     {
      return m_lastError;
     }
  };

#endif // FTF_EXECUTION_MQH
