//+------------------------------------------------------------------+
//|                                              PositionTracker.mqh |
//|  CPositionTracker - in-memory list of THIS instance's open       |
//|  positions (chart symbol + own magic numbers only), detection of |
//|  closed positions (exit reason), restart recovery and per-       |
//|  position metadata persistence (state keys pos.<ticket>.*).      |
//|  docs/09 section 7.14, docs/03 section 6, spec B.7               |
//+------------------------------------------------------------------+
#ifndef FTF_POSITION_TRACKER_MQH
#define FTF_POSITION_TRACKER_MQH

#include <FranckyTriFlux\Core\Context.mqh>

#define FTF_TRK_HISTORY_WAIT_MS  5000   // TUNABLE (not an input yet): wait for the history of a vanished position
#define FTF_TRK_MAX_OFFLINE      64     // TUNABLE (not an input yet): max closed-while-offline positions queued at start

class CPositionTracker
  {
public:
   STrackedPos       pos[];            // public array, index 0..total-1 (docs/09 7.14)
   int               total;

private:
   CFtfContext      *m_ctx;
   bool              m_isTester;
   long              m_missMsc[];      // parallel to pos[]: server ms when the ticket first vanished (0 = present)
   ulong             m_missUs[];       // parallel to pos[]: local micros at the same moment (live fallback clock)
   SPosInfo          m_snap[];         // reusable broker snapshot (chart symbol, all magics)
   STrackedPos       m_pendPos[];      // closed while the EA was offline, returned by the next Sync()
   SClosedTrade      m_pendInfo[];
   int               m_pendCount;
   int               m_recoveredCount; // positions rebuilt since Init (panel)
   int               m_closedCount;    // positions finalised since Init (panel)
   int               m_lastSnapOwn;    // own positions seen in the last broker snapshot
   bool              m_lastSnapOk;

   //--- helpers --------------------------------------------------------
   bool              Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.pf)!=POINTER_INVALID &&
              CheckPointer(m_ctx.logger)!=POINTER_INVALID && CheckPointer(m_ctx.cfg)!=POINTER_INVALID);
     }
   bool              StateOk(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.state)!=POINTER_INVALID && m_ctx.state.Enabled());
     }
   int               PriceDigits(void)
     {
      if(CheckPointer(m_ctx.md)!=POINTER_INVALID && m_ctx.md.DigitsCount()>0)
         return m_ctx.md.DigitsCount();
      return 5;
     }
   double            PointValue(void)
     {
      if(CheckPointer(m_ctx.md)!=POINTER_INVALID && m_ctx.md.PointSize()>0.0)
         return m_ctx.md.PointSize();
      return 0.0;
     }
   string            Px(const double price)          { return DoubleToString(price,PriceDigits()); }
   string            TicketStr(const ulong ticket)   { return IntegerToString((long)ticket); }
   string            MetaKey(const ulong ticket)     { return "pos."+TicketStr(ticket)+"."; }
   string            CleanText(const string s)
     {
      string r=s;
      StringReplace(r,"\r"," ");
      StringReplace(r,"\n"," ");
      return r;
     }
   bool              IsOwn(const SPosInfo &s)
     {
      //--- isolation (docs/09 1.6): chart symbol AND one of this instance's 3 magic numbers
      return (s.symbol==m_ctx.symbol && m_ctx.EngineFromMagic(s.magic)>0);
     }
   string            PosText(const STrackedPos &p)
     {
      return "#"+TicketStr(p.ticket)+" "+FTF_EngineCode(p.engine)+" "+FTF_DirStr(p.dir)+" "+DoubleToString(p.lots,2);
     }
   //--- elapsed ms since (startMsc,startUs): server clock, plus the local clock when live
   //--- (server ms stalls without ticks; the tester stays deterministic on server time only)
   long              ElapsedMs(const long startMsc,const ulong startUs)
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
   int               SnapIndex(const ulong ticket,const int n)
     {
      for(int s=0;s<n;s++)
         if(m_snap[s].ticket==ticket)
            return s;
      return -1;
     }
   //--- open risk of one position: loss from open price to the CURRENT SL (0 when the SL protects profit)
   double            RiskOf(const STrackedPos &p)
     {
      if(p.lots<=0.0 || p.openPrice<=0.0)
         return 0.0;
      if(p.sl<=0.0)
         return (p.riskMoney>0.0 ? p.riskMoney : 0.0);   // no SL yet (two-step stops): use the entry risk
      if(p.dir==FTF_DIR_BUY && p.sl>=p.openPrice)
         return 0.0;
      if(p.dir==FTF_DIR_SELL && p.sl<=p.openPrice)
         return 0.0;
      double lpl=m_ctx.pf.LossPerLot(m_ctx.symbol,p.dir,p.openPrice,p.sl);
      if(lpl<=0.0)
         return 0.0;
      return lpl*p.lots;
     }

   //--- platform exit reason -> FRANCKY exit code (SL refined by BE / trailing state)
   int               MapPlatformReason(const STrackedPos &p,const int reason,const bool offline)
     {
      switch(reason)
        {
         case FTF_EXIT_SL:
            if(p.trailActive)
               return FTF_EXIT_TRAIL;
            if(p.beDone)
               return FTF_EXIT_BE;
            return FTF_EXIT_SL;
         case FTF_EXIT_TP:
            return FTF_EXIT_TP;
         case FTF_EXIT_NONE:
         case FTF_EXIT_UNKNOWN:
            return (offline ? FTF_EXIT_OFFLINE : FTF_EXIT_UNKNOWN);
         default:
            break;
        }
      return reason;
     }

   //--- decides the final exit code/detail and completes the closed-trade record
   void              DecideExit(const STrackedPos &p,SClosedTrade &info,const bool offline)
     {
      int platformReason=(info.found ? info.exitReason : (int)FTF_EXIT_UNKNOWN);
      int code=FTF_EXIT_UNKNOWN;
      string detail="";
      if(p.pendingExit!=FTF_EXIT_NONE)
        {
         //--- the EA asked for this exit (time-stop, engine exit ...): keep its reason
         code=p.pendingExit;
         detail=p.pendingExitDetail;
         if(info.found && platformReason!=FTF_EXIT_UNKNOWN && platformReason!=FTF_EXIT_NONE && platformReason!=code)
            detail+=" (platform: "+FTF_ExitStr(platformReason)+")";
         if(!info.found)
            detail+=" (history not found)";
         if(offline)
            detail+=" (closed while EA offline)";
        }
      else if(!info.found)
        {
         code=(offline ? FTF_EXIT_OFFLINE : FTF_EXIT_UNKNOWN);
         detail=(offline ? "closed while EA offline - history not found" : "history not found");
        }
      else
        {
         code=MapPlatformReason(p,platformReason,offline);
         detail=info.exitDetail;
         if(offline)
            detail="closed while EA offline (platform: "+FTF_ExitStr(platformReason)+")"+
                   (StringLen(info.exitDetail)>0 ? " "+info.exitDetail : "");
        }
      info.ticket=p.ticket;
      if(info.positionId==0)
         info.positionId=p.positionId;
      if(!info.found && info.closeMsc<=0 && !offline)
         info.closeMsc=m_ctx.NowMsc();
      info.exitReason=code;
      info.exitDetail=CleanText(detail);
     }

   void              AppendClosed(STrackedPos &closedPos[],SClosedTrade &closedInfo[],const STrackedPos &p,const SClosedTrade &info)
     {
      int k=ArraySize(closedPos);
      if(ArraySize(closedInfo)!=k)
         ArrayResize(closedInfo,k);
      ArrayResize(closedPos,k+1);
      ArrayResize(closedInfo,k+1);
      closedPos[k]=p;
      closedInfo[k]=info;
     }

   void              LogClosed(const STrackedPos &p,const SClosedTrade &info)
     {
      string dur="?";
      if(info.closeMsc>0 && p.openMsc>0 && info.closeMsc>=p.openMsc)
         dur=DoubleToString((double)(info.closeMsc-p.openMsc)/1000.0,1);
      string msg="CLOSED "+PosText(p)+" open "+Px(p.openPrice)+" close "+Px(info.closePrice)+
                 " net "+DoubleToString(info.net,2)+" (gross "+DoubleToString(info.profit,2)+
                 " comm "+DoubleToString(info.commission,2)+" swap "+DoubleToString(info.swap,2)+")"+
                 " dur "+dur+" s MAE "+DoubleToString(p.maePts,1)+" MFE "+DoubleToString(p.mfePts,1)+" pts"+
                 " | exit "+FTF_ExitStr(info.exitReason)+" | "+info.exitDetail+" | setup "+p.setupId;
      if(info.found)
         m_ctx.logger.Info("TRK",msg);
      else
         m_ctx.logger.Warn("TRK",msg);
     }

   //--- remove pos[i] by shifting the tail down (no ArrayRemove on struct arrays)
   void              RemoveAt(const int i)
     {
      if(i<0 || i>=total)
         return;
      for(int k=i;k<total-1;k++)
        {
         pos[k]=pos[k+1];
         m_missMsc[k]=m_missMsc[k+1];
         m_missUs[k]=m_missUs[k+1];
        }
      total--;
      if(total<0)
         total=0;
      ArrayResize(pos,total);
      ArrayResize(m_missMsc,total);
      ArrayResize(m_missUs,total);
     }

   void              QueuePending(const STrackedPos &p,const SClosedTrade &info)
     {
      ArrayResize(m_pendPos,m_pendCount+1);
      ArrayResize(m_pendInfo,m_pendCount+1);
      m_pendPos[m_pendCount]=p;
      m_pendInfo[m_pendCount]=info;
      m_pendCount++;
     }

   //--- hand over the closed-while-offline queue (RecoverOnStart) to the caller of Sync()
   void              EmitPending(STrackedPos &closedPos[],SClosedTrade &closedInfo[])
     {
      for(int k=0;k<m_pendCount;k++)
        {
         AppendClosed(closedPos,closedInfo,m_pendPos[k],m_pendInfo[k]);
         LogClosed(m_pendPos[k],m_pendInfo[k]);
         RemoveMeta(m_pendPos[k].ticket);
         m_closedCount++;
        }
      m_pendCount=0;
      ArrayResize(m_pendPos,0);
      ArrayResize(m_pendInfo,0);
     }

   //--- keep pos[i] in line with the broker (SL/TP/lots may change: two-step stops, manual edits)
   void              RefreshFromSnap(const int i,const int s)
     {
      m_missMsc[i]=0;
      m_missUs[i]=0;
      double pt=PointValue();
      double tol=(pt>0.0 ? pt*0.5 : 0.0);
      bool slChanged=(MathAbs(m_snap[s].sl-pos[i].sl)>tol);
      bool tpChanged=(MathAbs(m_snap[s].tp-pos[i].tp)>tol);
      if(slChanged || tpChanged)
         m_ctx.logger.Throttled(FTF_LOG_INFO,"trk.sltp."+TicketStr(pos[i].ticket),m_ctx.cfg.LogThrottleMs,"TRK",
                             "broker SL/TP of "+PosText(pos[i])+" now SL "+Px(m_snap[s].sl)+" TP "+Px(m_snap[s].tp)+
                             " (was SL "+Px(pos[i].sl)+" TP "+Px(pos[i].tp)+")");
      pos[i].sl=m_snap[s].sl;
      pos[i].tp=m_snap[s].tp;
      if(m_snap[s].lots>0.0)
         pos[i].lots=m_snap[s].lots;
      if(pos[i].positionId==0)
         pos[i].positionId=(m_snap[s].positionId>0 ? m_snap[s].positionId : (long)m_snap[s].ticket);
      if(pos[i].openMsc<=0 && m_snap[s].openMsc>0)
         pos[i].openMsc=m_snap[s].openMsc;
      //--- the broker open price is authoritative (fill price may be unknown at send time)
      if(m_snap[s].openPrice>0.0 && MathAbs(m_snap[s].openPrice-pos[i].openPrice)>tol)
        {
         m_ctx.logger.Debug("TRK","open price of "+PosText(pos[i])+" corrected "+Px(pos[i].openPrice)+" -> "+Px(m_snap[s].openPrice));
         pos[i].openPrice=m_snap[s].openPrice;
         if(pt>0.0 && pos[i].requestedPrice>0.0)
            pos[i].slippagePts=(pos[i].openPrice-pos[i].requestedPrice)*(double)pos[i].dir/pt;
        }
     }

   //--- tracked ticket no longer open: look up the history (5 s grace), then finalise. true = removed
   bool              HandleMissing(const int i,STrackedPos &closedPos[],SClosedTrade &closedInfo[])
     {
      if(m_missMsc[i]==0 && m_missUs[i]==0)
        {
         m_missMsc[i]=m_ctx.NowMsc();
         m_missUs[i]=m_ctx.pf.Micros();
         m_ctx.logger.Debug("TRK",PosText(pos[i])+" no longer open - looking up the history");
        }
      SClosedTrade info;
      info.Reset();
      long pid=(pos[i].positionId>0 ? pos[i].positionId : (long)pos[i].ticket);
      bool got=m_ctx.pf.GetClosedTrade(pos[i].ticket,pid,info);
      if(!got || !info.found)
        {
         long waited=ElapsedMs(m_missMsc[i],m_missUs[i]);
         //--- never declare a position closed without history while the terminal is disconnected
         if(waited<FTF_TRK_HISTORY_WAIT_MS || !m_ctx.pf.IsConnected())
           {
            m_ctx.logger.Throttled(FTF_LOG_DEBUG,"trk.wait."+TicketStr(pos[i].ticket),m_ctx.cfg.LogThrottleMs,"TRK",
                                PosText(pos[i])+" closed, history not available yet (waited "+IntegerToString(waited)+" ms)");
            return false;
           }
         info.Reset();
         info.found=false;
        }
      STrackedPos p;
      p=pos[i];
      DecideExit(p,info,false);
      AppendClosed(closedPos,closedInfo,p,info);
      LogClosed(p,info);
      RemoveAt(i);
      RemoveMeta(p.ticket);
      m_closedCount++;
      return true;
     }

   //--- own position present at the broker but not tracked: rebuild it (state metadata when present)
   void              RecoverFromSnap(const int s)
     {
      STrackedPos p;
      p.Reset();
      bool meta=LoadMeta(m_snap[s].ticket,p);
      //--- live fields always come from the broker
      p.ticket=m_snap[s].ticket;
      p.positionId=(m_snap[s].positionId>0 ? m_snap[s].positionId : (long)m_snap[s].ticket);
      p.engine=m_ctx.EngineFromMagic(m_snap[s].magic);
      p.dir=m_snap[s].dir;
      p.lots=m_snap[s].lots;
      p.openPrice=m_snap[s].openPrice;
      p.sl=m_snap[s].sl;
      p.tp=m_snap[s].tp;
      if(m_snap[s].openMsc>0)
         p.openMsc=m_snap[s].openMsc;
      p.recovered=true;
      if(!meta)
        {
         p.initialSL=m_snap[s].sl;
         p.initialTP=m_snap[s].tp;
         p.setupId="REC-"+TicketStr(p.ticket);
         p.entryReason="recovered after restart";
         p.tfText="?";
         p.mode=m_ctx.mode;
         p.h1State=FTF_H1S_NEUTRAL;
         p.signalMsc=p.openMsc;
         p.signalPrice=p.openPrice;
         p.requestedPrice=p.openPrice;
         p.equityAtEntry=m_ctx.pf.Equity();
         p.riskMoney=RiskOf(p);   // initial risk: open -> SL (riskMoney is 0 after Reset)
        }
      Add(p);
      m_recoveredCount++;
      string what=PosText(p)+" open "+Px(p.openPrice)+" SL "+Px(p.sl)+" TP "+Px(p.tp)+
                  " opened "+FTF_TimeMscStr(p.openMsc)+" magic "+IntegerToString(m_snap[s].magic)+
                  " | metadata: "+(meta ? "state file" : "broker only")+
                  (meta ? " (BE "+(p.beDone ? "Y" : "N")+", trail "+(p.trailActive ? "Y" : "N")+", setup "+p.setupId+")" : "");
      m_ctx.logger.Warn("TRK","RECOVERED "+what);
      m_ctx.Event("RECOVERY","POSITION",what);
     }

   //--- read metadata of one ticket from the state store. false when absent
   bool              LoadMeta(const ulong ticket,STrackedPos &p)
     {
      if(!StateOk())
         return false;
      string k=MetaKey(ticket);
      if(!m_ctx.state.Has(k+"eng"))
         return false;
      CStateStore *st=m_ctx.state;
      p.ticket=ticket;
      p.engine=(int)st.GetLong(k+"eng",0);
      p.dir=(int)st.GetLong(k+"dir",0);
      p.setupId=st.GetString(k+"setup","");
      p.initialSL=st.GetDouble(k+"isl",0.0);
      p.initialTP=st.GetDouble(k+"itp",0.0);
      p.openMsc=st.GetLong(k+"omsc",0);
      p.signalMsc=st.GetLong(k+"smsc",0);
      p.signalPrice=st.GetDouble(k+"sp",0.0);
      p.requestedPrice=st.GetDouble(k+"rp",0.0);
      p.slippagePts=st.GetDouble(k+"slip",0.0);
      p.latencyMs=st.GetDouble(k+"lat",0.0);
      p.decisionMs=st.GetDouble(k+"dec",0.0);
      p.spreadPts=st.GetDouble(k+"spr",0.0);
      p.retries=(int)st.GetLong(k+"ret",0);
      p.riskMoney=st.GetDouble(k+"risk",0.0);
      p.equityAtEntry=st.GetDouble(k+"eq",0.0);
      p.ddPctAtEntry=st.GetDouble(k+"dd",0.0);
      p.h1State=(int)st.GetLong(k+"h1",0);
      p.mode=(int)st.GetLong(k+"mode",(long)m_ctx.mode);
      p.entryReason=st.GetString(k+"er","");
      p.tfText=st.GetString(k+"tf","");
      p.maePts=st.GetDouble(k+"mae",0.0);
      p.mfePts=st.GetDouble(k+"mfe",0.0);
      p.beDone=(st.GetLong(k+"be",0)!=0);
      p.trailActive=(st.GetLong(k+"tr",0)!=0);
      //--- extra keys (needed for closed-while-offline trades and engine exits)
      p.positionId=st.GetLong(k+"pid",(long)ticket);
      p.openPrice=st.GetDouble(k+"op",0.0);
      p.lots=st.GetDouble(k+"lots",0.0);
      p.sl=st.GetDouble(k+"sl",0.0);
      p.tp=st.GetDouble(k+"tp",0.0);
      p.refLevel=st.GetDouble(k+"ref",0.0);
      p.pendingExit=(int)st.GetLong(k+"pe",0);
      p.pendingExitDetail=st.GetString(k+"ped","");
      return true;
     }

   //--- state key "pos.<ticket>.<field>" -> "<ticket>" ("" if malformed)
   string            TicketFromKey(const string key)
     {
      if(StringFind(key,"pos.")!=0)
         return "";
      int dot=StringFind(key,".",4);
      if(dot<=4)
         return "";
      return StringSubstr(key,4,dot-4);
     }

   //--- ticket with metadata but no longer open: queue it as closed while offline. true = queued
   bool              QueueOffline(const ulong ticket)
     {
      STrackedPos p;
      p.Reset();
      if(!LoadMeta(ticket,p))
         return false;
      p.ticket=ticket;
      p.recovered=true;
      SClosedTrade info;
      info.Reset();
      long pid=(p.positionId>0 ? p.positionId : (long)ticket);
      bool got=m_ctx.pf.GetClosedTrade(ticket,pid,info);
      if(!got)
         info.found=false;
      DecideExit(p,info,true);
      QueuePending(p,info);
      string what=PosText(p)+" open "+Px(p.openPrice)+" close "+Px(info.closePrice)+" net "+DoubleToString(info.net,2)+
                  " exit "+FTF_ExitStr(info.exitReason)+" | "+info.exitDetail;
      m_ctx.logger.Warn("TRK","CLOSED WHILE OFFLINE "+what);
      m_ctx.Event("RECOVERY","CLOSED_OFFLINE",what);
      return true;
     }

   //--- every ticket that has "pos.<ticket>." keys in the state store (unique)
   int               StateTickets(string &tickets[])
     {
      ArrayResize(tickets,0);
      if(!StateOk())
         return 0;
      string keys[];
      int nk=m_ctx.state.KeysWithPrefix("pos.",keys);
      if(nk>ArraySize(keys))
         nk=ArraySize(keys);
      int ns=0;
      for(int k=0;k<nk;k++)
        {
         string t=TicketFromKey(keys[k]);
         if(StringLen(t)==0)
            continue;
         bool dup=false;
         for(int q=0;q<ns;q++)
            if(tickets[q]==t)
              {
               dup=true;
               break;
              }
         if(dup)
            continue;
         ArrayResize(tickets,ns+1);
         tickets[ns]=t;
         ns++;
        }
      return ns;
     }

public:
                     CPositionTracker(void)
     {
      m_ctx=NULL;
      m_isTester=false;
      m_pendCount=0;
      m_recoveredCount=0;
      m_closedCount=0;
      m_lastSnapOwn=0;
      m_lastSnapOk=false;
      total=0;
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(!Ready())
         return false;
      m_isTester=m_ctx.pf.IsTester();
      total=0;
      ArrayResize(pos,0);
      ArrayResize(m_missMsc,0);
      ArrayResize(m_missUs,0);
      ArrayResize(m_snap,0);
      m_pendCount=0;
      ArrayResize(m_pendPos,0);
      ArrayResize(m_pendInfo,0);
      m_recoveredCount=0;
      m_closedCount=0;
      m_ctx.logger.Info("TRK","position tracker ready: symbol "+m_ctx.symbol+" | magics "+
                     IntegerToString(m_ctx.MagicFor(FTF_ENG_MOMENTUM))+"/"+IntegerToString(m_ctx.MagicFor(FTF_ENG_FVG))+"/"+
                     IntegerToString(m_ctx.MagicFor(FTF_ENG_RANGE))+" | metadata persistence "+(StateOk() ? "ON" : "OFF"));
      return true;
     }

   //--- closed positions since the last call (exit reason decided here) + recovery of untracked own positions
   int               Sync(STrackedPos &closedPos[],SClosedTrade &closedInfo[])
     {
      ArrayResize(closedPos,0);
      ArrayResize(closedInfo,0);
      if(!Ready())
         return 0;
      //--- 1. positions found closed while the EA was offline (queued by RecoverOnStart)
      if(m_pendCount>0)
         EmitPending(closedPos,closedInfo);
      //--- 2. broker snapshot: chart symbol, all magics (filtered below)
      int n=m_ctx.pf.GetPositions(m_snap,false);
      if(n<0)
        {
         m_lastSnapOk=false;
         m_ctx.logger.Throttled(FTF_LOG_WARN,"trk.snap",m_ctx.cfg.LogThrottleMs,"TRK",
                             "position snapshot failed - closed-position detection skipped this cycle");
         return ArraySize(closedPos);
        }
      if(n>ArraySize(m_snap))
         n=ArraySize(m_snap);
      m_lastSnapOk=true;
      //--- 3. tracked tickets: refresh, or finalise when gone (backwards: RemoveAt shifts the tail)
      for(int i=total-1;i>=0;i--)
        {
         int si=SnapIndex(pos[i].ticket,n);
         if(si>=0)
            RefreshFromSnap(i,si);
         else
            HandleMissing(i,closedPos,closedInfo);
        }
      //--- 4. own positions that are not tracked -> recovered
      int own=0;
      for(int s=0;s<n;s++)
        {
         if(!IsOwn(m_snap[s]))
            continue;
         own++;
         if(IndexOf(m_snap[s].ticket)>=0)
            continue;
         RecoverFromSnap(s);
        }
      m_lastSnapOwn=own;
      return ArraySize(closedPos);
     }

   //--- add (or replace) a position opened by the execution engine, then persist its metadata
   void              Add(const STrackedPos &p)
     {
      if(p.ticket==0)
        {
         if(CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.logger)!=POINTER_INVALID)
            m_ctx.logger.Warn("TRK","Add refused: ticket 0 ("+FTF_EngineCode(p.engine)+" "+FTF_DirStr(p.dir)+")");
         return;
        }
      int idx=IndexOf(p.ticket);
      if(idx<0)
        {
         idx=total;
         total++;
         ArrayResize(pos,total);
         ArrayResize(m_missMsc,total);
         ArrayResize(m_missUs,total);
        }
      else if(CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.logger)!=POINTER_INVALID)
         m_ctx.logger.Debug("TRK","#"+TicketStr(p.ticket)+" already tracked - record replaced");
      pos[idx]=p;
      m_missMsc[idx]=0;
      m_missUs[idx]=0;
      SaveMeta(idx);
      if(CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.logger)!=POINTER_INVALID)
         m_ctx.logger.Debug("TRK","tracking "+PosText(p)+" open "+Px(p.openPrice)+" SL "+Px(p.sl)+" TP "+Px(p.tp)+
                         " ("+IntegerToString(total)+" open)");
     }

   int               IndexOf(const ulong ticket)
     {
      for(int i=0;i<total;i++)
         if(pos[i].ticket==ticket)
            return i;
      return -1;
     }

   int               CountEngine(const int engine)
     {
      int c=0;
      for(int i=0;i<total;i++)
         if(pos[i].engine==engine)
            c++;
      return c;
     }

   int               CountDir(const int dir)
     {
      int c=0;
      for(int i=0;i<total;i++)
         if(pos[i].dir==dir)
            c++;
      return c;
     }

   int               CountEngineDir(const int engine,const int dir)
     {
      int c=0;
      for(int i=0;i<total;i++)
         if(pos[i].engine==engine && pos[i].dir==dir)
            c++;
      return c;
     }

   bool              HasDir(const int dir)
     {
      for(int i=0;i<total;i++)
         if(pos[i].dir==dir)
            return true;
      return false;
     }

   //--- money lost if every open position hits its current SL (0 for SLs already protecting profit)
   double            OpenRiskMoney(void)
     {
      if(!Ready())
         return 0.0;
      double sum=0.0;
      for(int i=0;i<total;i++)
         sum+=RiskOf(pos[i]);
      return sum;
     }

   double            OpenLots(void)
     {
      double sum=0.0;
      for(int i=0;i<total;i++)
         sum+=pos[i].lots;
      return sum;
     }

   //--- open price of the latest entry of (engine,dir); msc = its open time. 0 / msc=0 when none
   double            LastEntryPrice(const int engine,const int dir,long &msc)
     {
      msc=0;
      double price=0.0;
      bool found=false;
      for(int i=0;i<total;i++)
        {
         if(pos[i].engine!=engine || pos[i].dir!=dir)
            continue;
         if(!found || pos[i].openMsc>msc)
           {
            msc=pos[i].openMsc;
            price=pos[i].openPrice;
            found=true;
           }
        }
      return price;
     }

   //--- persistence (docs/09 7.4 / 7.14): pos.<ticket>.<field>
   void              SaveMeta(const int i)
     {
      if(i<0 || i>=total || !StateOk())
         return;
      string k=MetaKey(pos[i].ticket);
      CStateStore *st=m_ctx.state;
      st.SetLong(k+"eng",(long)pos[i].engine);
      st.SetLong(k+"dir",(long)pos[i].dir);
      st.SetString(k+"setup",CleanText(pos[i].setupId));
      st.SetDouble(k+"isl",pos[i].initialSL);
      st.SetDouble(k+"itp",pos[i].initialTP);
      st.SetLong(k+"omsc",pos[i].openMsc);
      st.SetLong(k+"smsc",pos[i].signalMsc);
      st.SetDouble(k+"sp",pos[i].signalPrice);
      st.SetDouble(k+"rp",pos[i].requestedPrice);
      st.SetDouble(k+"slip",pos[i].slippagePts);
      st.SetDouble(k+"lat",pos[i].latencyMs);
      st.SetDouble(k+"dec",pos[i].decisionMs);
      st.SetDouble(k+"spr",pos[i].spreadPts);
      st.SetLong(k+"ret",(long)pos[i].retries);
      st.SetDouble(k+"risk",pos[i].riskMoney);
      st.SetDouble(k+"eq",pos[i].equityAtEntry);
      st.SetDouble(k+"dd",pos[i].ddPctAtEntry);
      st.SetLong(k+"h1",(long)pos[i].h1State);
      st.SetLong(k+"mode",(long)pos[i].mode);
      st.SetString(k+"er",CleanText(pos[i].entryReason));
      st.SetString(k+"tf",CleanText(pos[i].tfText));
      st.SetDouble(k+"mae",pos[i].maePts);
      st.SetDouble(k+"mfe",pos[i].mfePts);
      st.SetLong(k+"be",(pos[i].beDone ? 1 : 0));
      st.SetLong(k+"tr",(pos[i].trailActive ? 1 : 0));
      //--- extra keys (closed-while-offline journal + engine exits after restart)
      st.SetLong(k+"pid",pos[i].positionId);
      st.SetDouble(k+"op",pos[i].openPrice);
      st.SetDouble(k+"lots",pos[i].lots);
      st.SetDouble(k+"sl",pos[i].sl);
      st.SetDouble(k+"tp",pos[i].tp);
      st.SetDouble(k+"ref",pos[i].refLevel);
      st.SetLong(k+"pe",(long)pos[i].pendingExit);
      st.SetString(k+"ped",CleanText(pos[i].pendingExitDetail));
     }

   void              SaveAll(void)
     {
      for(int i=0;i<total;i++)
         SaveMeta(i);
     }

   void              RemoveMeta(const ulong ticket)
     {
      if(!StateOk())
         return;
      m_ctx.state.RemovePrefix("pos."+TicketStr(ticket)+".");
     }

   //--- B.7: rebuild open positions (broker + state) and queue positions closed while offline
   int               RecoverOnStart(void)
     {
      if(!Ready())
         return 0;
      int before=total;
      STrackedPos cp[];
      SClosedTrade ci[];
      int nc=Sync(cp,ci);
      //--- nothing should close here (fresh start) - keep anything returned for the controller's next Sync
      for(int j=0;j<nc && j<ArraySize(cp) && j<ArraySize(ci);j++)
         QueuePending(cp[j],ci[j]);
      int openRec=total-before;
      if(openRec<0)
         openRec=0;
      int offline=0;
      string tickets[];
      int nt=StateTickets(tickets);
      for(int q=0;q<nt;q++)
        {
         ulong tk=(ulong)StringToInteger(tickets[q]);
         if(tk==0)
           {
            m_ctx.state.RemovePrefix("pos."+tickets[q]+".");   // malformed key group
            continue;
           }
         if(IndexOf(tk)>=0)
            continue;
         if(m_pendCount>=FTF_TRK_MAX_OFFLINE)
           {
            m_ctx.logger.Warn("TRK","offline-closed queue full - metadata of #"+tickets[q]+" dropped");
            RemoveMeta(tk);
            continue;
           }
         if(QueueOffline(tk))
            offline++;
         else
            RemoveMeta(tk);
        }
      string msg=IntegerToString(openRec)+" open position(s) rebuilt, "+IntegerToString(offline)+
                 " closed while offline (state "+(StateOk() ? "ON" : "OFF")+", own open now "+IntegerToString(total)+")";
      m_ctx.logger.Info("TRK","restart recovery: "+msg);
      if(openRec>0 || offline>0)
         m_ctx.Event("RECOVERY","START",msg);
      return openRec+offline;
     }

   //--- extra: panel line
   string            Describe(void)
     {
      if(!Ready())
         return "Positions: not initialised";
      string s="Pos "+IntegerToString(total)+" (MOM "+IntegerToString(CountEngine(FTF_ENG_MOMENTUM))+
               " FVG "+IntegerToString(CountEngine(FTF_ENG_FVG))+" RNG "+IntegerToString(CountEngine(FTF_ENG_RANGE))+
               ") | B "+IntegerToString(CountDir(FTF_DIR_BUY))+" S "+IntegerToString(CountDir(FTF_DIR_SELL))+
               " | lots "+DoubleToString(OpenLots(),2)+" | risk "+DoubleToString(OpenRiskMoney(),2);
      s+=" | closed "+IntegerToString(m_closedCount);
      if(m_recoveredCount>0)
         s+=" | recovered "+IntegerToString(m_recoveredCount);
      if(!m_lastSnapOk)
         s+=" | SNAPSHOT FAILED";
      return s;
     }

   //--- extra: position reconcile for the 10 % verification (true = PASS)
   bool              SelfCheck(string &d)
     {
      d="";
      if(!Ready())
        {
         d="tracker not initialised";
         return false;
        }
      int n=m_ctx.pf.GetPositions(m_snap,false);
      if(n<0)
        {
         d="broker position snapshot failed";
         return false;
        }
      if(n>ArraySize(m_snap))
         n=ArraySize(m_snap);
      int own=0;
      int untracked=0;
      for(int s=0;s<n;s++)
        {
         if(!IsOwn(m_snap[s]))
            continue;
         own++;
         if(IndexOf(m_snap[s].ticket)<0)
            untracked++;
        }
      int vanished=0;
      int noSl=0;
      for(int i=0;i<total;i++)
        {
         if(SnapIndex(pos[i].ticket,n)<0)
            vanished++;
         if(pos[i].sl<=0.0)
            noSl++;
        }
      d="tracked "+IntegerToString(total)+" / broker own "+IntegerToString(own)+" (untracked "+IntegerToString(untracked)+
        ", awaiting close "+IntegerToString(vanished)+", without SL "+IntegerToString(noSl)+")";
      return (untracked==0 && noSl==0);
     }
  };

#endif // FTF_POSITION_TRACKER_MQH
