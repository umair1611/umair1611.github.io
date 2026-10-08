//+------------------------------------------------------------------+
//|                                                   Controller.mqh |
//|  CFranckyController - the application. Owns every module, wires  |
//|  them, and runs the pipeline of docs/09 section 8 on every tick  |
//|  (and on the timer when no tick arrives):                        |
//|  market update -> engines -> conflicts -> safety gate ->         |
//|  execution -> position management -> logging (spec Table 6).     |
//+------------------------------------------------------------------+
#ifndef FTF_CONTROLLER_MQH
#define FTF_CONTROLLER_MQH

#include <FranckyTriFlux\Core\SafetyGate.mqh>
#include <FranckyTriFlux\Core\PositionManager.mqh>

#define FTF_CTRL_STATE_MS        2000     // state save / heartbeat period (server ms)
#define FTF_CTRL_FLUSH_MS        5000     // journal flush period
#define FTF_CTRL_DRAW_MS         1000     // engine drawings refresh
#define FTF_CTRL_POSMETA_MS      30000    // full position metadata save
#define FTF_CTRL_NEWS_DRAW_MS    60000    // news lines refresh
#define FTF_CTRL_DEDUP_MS        60000    // same setup + same reason logged once per minute
#define FTF_CTRL_ROW_MAX         120      // panel row length cap

class CFranckyController
  {
private:
   //--- services
   CConfig             m_cfg;
   CLogger             m_log;
   CTradeJournal       m_journal;
   CStats              m_stats;
   CStateStore         m_state;
   CPlatform           m_pf;
   CClock              m_clock;
   CTickBuffer         m_ticks;
   CMarketData         m_md;
   CH1Context          m_h1;
   CChartUI            m_ui;
   CFtfContext         m_ctx;
   //--- trading layer
   CEngineManager      m_engines;
   CPositionTracker    m_tracker;
   CDrawdownGuard      m_dd;
   CConsecLossGuard    m_cl;
   CExecQualityGuard   m_eq;
   CNewsFilter         m_news;
   CSessionFilter      m_sess;
   CRolloverFilter     m_roll;
   CRiskManager        m_risk;
   CExposureGuard      m_expo;
   CMultiInstanceGuard m_mi;
   CConflictResolver   m_cr;
   CSignalConfirmer    m_conf;
   CExecutionEngine    m_exec;
   CSafetyGate         m_gate;
   CPositionManager    m_pm;
   //--- run-time state
   bool              m_ready;
   bool              m_quiet;          // optimization without files
   string            m_folder;
   long              m_lastState;
   long              m_lastFlush;
   long              m_lastDraw;
   long              m_lastPosMeta;
   long              m_lastNewsDraw;
   long              m_lastStatsCsv;
   long              m_lastPanelMsc;
   ulong             m_lastPanelUs;
   datetime          m_day;
   long              m_cycles;
   double            m_cycleUsAvg;
   double            m_cycleUsMax;
   string            m_lastSignalText;
   int               m_global;
   string            m_globalDetail;
   //--- per engine de-duplication of decision rows
   string            m_lastSetup[FTF_ENGINE_COUNT+1];
   string            m_lastDecisionKey[FTF_ENGINE_COUNT+1];
   long              m_lastDecisionMsc[FTF_ENGINE_COUNT+1];
   //--- work arrays
   SSignal           m_sigs[];
   int               m_reasons[];
   string            m_details[];
   STrackedPos       m_closedPos[];
   SClosedTrade      m_closedInfo[];

   //+---------------------------------------------------------------+
   //| helpers                                                        |
   //+---------------------------------------------------------------+
   string            Px(const double v) { return FTF_D(v,m_md.DigitsCount()); }

   string            Cut(const string s)
     {
      if(StringLen(s)<=FTF_CTRL_ROW_MAX)
         return s;
      return StringSubstr(s,0,FTF_CTRL_ROW_MAX-3)+"...";
     }

   string            ReasonText(const int reason)
     {
      switch(reason)
        {
         case REASON_PROGRAM:     return "EA stopped itself";
         case REASON_REMOVE:      return "EA removed from chart";
         case REASON_RECOMPILE:   return "EA recompiled";
         case REASON_CHARTCHANGE: return "symbol or timeframe changed";
         case REASON_CHARTCLOSE:  return "chart closed";
         case REASON_PARAMETERS:  return "inputs changed";
         case REASON_ACCOUNT:     return "account changed";
         case REASON_TEMPLATE:    return "template applied";
         case REASON_INITFAILED:  return "OnInit failed";
         case REASON_CLOSE:       return "terminal closed";
         default:                 break;
        }
      return "reason "+IntegerToString(reason);
     }

   string            BuildFolder(void)
     {
      string tag=FTF_PLATFORM+"_"+FTF_SafeFilePart(m_ctx.symbol)+"_I"+IntegerToString(m_cfg.InstanceId);
      if(!m_pf.IsTester())
         return FTF_FILES_ROOT+"\\"+tag;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      string day=IntegerToString(dt.year)+StringFormat("%02d%02d",dt.mon,dt.day);
      string run=IntegerToString((long)(GetMicrosecondCount()%1000000));
      return FTF_FILES_ROOT+"\\TEST_"+tag+"_"+day+"_"+run;
     }

   string            StateFileName(void)
     {
      return FTF_FILES_ROOT+"\\state\\"+FTF_PLATFORM+"_"+IntegerToString(m_pf.Login())+"_"+
             FTF_SafeFilePart(m_ctx.symbol)+"_I"+IntegerToString(m_cfg.InstanceId)+".state";
     }

   //+---------------------------------------------------------------+
   //| decisions (signals.csv + stats + panel), de-duplicated          |
   //+---------------------------------------------------------------+
   void              CountSetup(const SSignal &s)
     {
      int e=s.engine;
      if(e<1 || e>FTF_ENGINE_COUNT)
         return;
      if(m_lastSetup[e]!=s.setupId)
        {
         m_lastSetup[e]=s.setupId;
         m_stats.OnSetup(e);
        }
     }

   void              Decide(const SSignal &s,const bool accepted,const int reason,const string detail,const double lots)
     {
      int e=s.engine;
      if(e<1 || e>FTF_ENGINE_COUNT)
         return;
      long now=m_ctx.NowMsc();
      string key=s.setupId+"|"+IntegerToString(reason);
      bool repeat=(!accepted && key==m_lastDecisionKey[e] && now-m_lastDecisionMsc[e]>=0 &&
                   now-m_lastDecisionMsc[e]<FTF_CTRL_DEDUP_MS);
      if(repeat)
         return;   // same setup refused for the same reason: already logged
      m_lastDecisionKey[e]=key;
      m_lastDecisionMsc[e]=now;
      m_journal.LogSignal(s,accepted,reason,detail,m_md.BidPrice(),m_md.AskPrice(),lots);
      CEngineBase *eng=m_engines.Get(e);
      if(accepted)
        {
         m_lastSignalText=FTF_TimeMscStr(now)+" "+FTF_EngineCode(e)+" "+FTF_DirStr(s.dir)+" ACCEPTED "+FTF_D(lots,2)+" lots";
         return;
        }
      if(reason!=FTF_REJ_CONFIRM_PENDING)
         m_stats.OnReject(e,reason);
      if(CheckPointer(eng)!=POINTER_INVALID)
         eng.SetInfo("rej "+FTF_ReasonStr(reason));
      m_lastSignalText=FTF_TimeMscStr(now)+" "+FTF_EngineCode(e)+" "+FTF_DirStr(s.dir)+" "+
                       (reason==FTF_REJ_CONFIRM_PENDING ? "PENDING" : "REJECTED "+FTF_ReasonStr(reason));
      m_log.Debug("CTRL",FTF_EngineCode(e)+" "+FTF_DirStr(s.dir)+" "+s.setupId+" "+
                  (reason==FTF_REJ_CONFIRM_PENDING ? "PENDING" : "REJECTED "+FTF_ReasonStr(reason))+" | "+detail);
      if(reason!=FTF_REJ_CONFIRM_PENDING)
         m_ui.DrawRejected(e,s.dir,m_md.ServerTime(),s.price,FTF_ReasonStr(reason)+" "+detail);
     }

   //--- gate -> execution -> tracking. Returns true when a position was opened.
   bool              TryExecute(SSignal &s,const int attempt,const ulong cycleStartUs)
     {
      double lots=0.0;
      double risk=0.0;
      string d="";
      int r=m_gate.CheckSignal(s,lots,risk,d);
      if(r!=FTF_OK)
        {
         Decide(s,false,r,d,lots);
         return false;
        }
      STrackedPos pos;
      pos.Reset();
      string ed="";
      r=m_exec.OpenTrade(s,lots,risk,attempt,cycleStartUs,pos,ed);
      if(r!=FTF_OK)
        {
         Decide(s,false,r,ed,lots);
         return false;
        }
      pos.ddPctAtEntry=m_dd.DdPct();
      m_tracker.Add(pos);
      CEngineBase *eng=m_engines.Get(s.engine);
      if(CheckPointer(eng)!=POINTER_INVALID)
         eng.OnEntry(s,pos);
      m_stats.OnEntry(s.engine,pos.slippagePts,pos.latencyMs,pos.spreadPts);
      Decide(s,true,FTF_OK,d,lots);
      m_ui.DrawEntry(pos.ticket,s.engine,s.dir,(datetime)(pos.openMsc/1000),pos.openPrice,
                     FTF_EngineName(s.engine)+" "+FTF_DirStr(s.dir)+" "+FTF_D(pos.lots,2)+" @"+Px(pos.openPrice)+
                     " SL "+Px(pos.sl)+" TP "+Px(pos.tp)+" | "+s.reason);
      m_log.Info("CTRL","ENTRY "+FTF_EngineCode(s.engine)+" "+FTF_DirStr(s.dir)+" ticket "+IntegerToString((long)pos.ticket)+
                 " "+FTF_D(pos.lots,2)+" lots @"+Px(pos.openPrice)+" SL "+Px(pos.sl)+" TP "+Px(pos.tp)+
                 " slip "+FTF_D(pos.slippagePts,1)+"pt lat "+FTF_D(pos.latencyMs,1)+"ms dec "+FTF_D(pos.decisionMs,2)+
                 "ms risk "+FTF_D(risk,2)+" | "+s.setupId+" | "+s.reason);
      return true;
     }

   //+---------------------------------------------------------------+
   //| pipeline steps                                                 |
   //+---------------------------------------------------------------+
   void              ProcessClosures(void)
     {
      int n=m_tracker.Sync(m_closedPos,m_closedInfo);
      for(int k=0;k<n;k++)
        {
         STrackedPos p=m_closedPos[k];
         SClosedTrade t=m_closedInfo[k];
         double stress=m_cfg.StressCommissionPerLot*p.lots;
         m_journal.LogTrade(p,t,stress);
         double dur=(t.closeMsc>0 && p.openMsc>0 ? (double)(t.closeMsc-p.openMsc)/1000.0 : 0.0);
         if(t.found)
           {
            m_stats.OnClose(p.engine,t.net-stress,dur,p.maePts,p.mfePts);
            m_cl.OnClosed(p.engine,t.net);
            m_risk.OnClosed(p.engine,t.net);
           }
         CEngineBase *eng=m_engines.Get(p.engine);
         if(CheckPointer(eng)!=POINTER_INVALID)
            eng.OnClosed(p,t);
         if(t.found && t.closeMsc>0)
            m_ui.DrawExit(p.ticket,p.engine,p.dir,(datetime)(p.openMsc/1000),p.openPrice,(datetime)(t.closeMsc/1000),
                          t.closePrice,t.net,FTF_EngineName(p.engine)+" "+FTF_ExitStr(t.exitReason)+" net "+
                          FTF_D(t.net,2)+" "+t.exitDetail);
         m_log.Info("CTRL","EXIT "+FTF_EngineCode(p.engine)+" "+FTF_DirStr(p.dir)+" ticket "+IntegerToString((long)p.ticket)+" "+
                    FTF_ExitStr(t.exitReason)+(t.found ? "" : " (history not found)")+" @"+Px(t.closePrice)+" net "+
                    FTF_D(t.net,2)+" dur "+FTF_D(dur,1)+"s MAE "+FTF_D(p.maePts,1)+"pt MFE "+FTF_D(p.mfePts,1)+"pt"+
                    (StringLen(t.exitDetail)>0 ? " | "+t.exitDetail : ""));
        }
     }

   void              ProcessRetries(const ulong cycleStartUs)
     {
      SSignal s;
      double lots=0.0;
      double risk=0.0;
      int attempt=0;
      int guard=0;
      while(guard<8 && m_exec.PopDueRetry(s,lots,risk,attempt))
        {
         guard++;
         string d="";
         int r=m_gate.Revalidate(s,d);
         if(r!=FTF_OK)
           {
            m_ctx.Event("RETRY","DROPPED",FTF_EngineCode(s.engine)+" "+s.setupId+" attempt "+IntegerToString(attempt)+": "+
                        FTF_ReasonStr(r)+" "+d);
            Decide(s,false,r,"retry "+IntegerToString(attempt)+": "+d,lots);
            continue;
           }
         m_log.Info("CTRL","RETRY "+IntegerToString(attempt)+" "+FTF_EngineCode(s.engine)+" "+s.setupId+" | "+d);
         TryExecute(s,attempt,cycleStartUs);
        }
     }

   void              ProcessConfirmations(const ulong cycleStartUs)
     {
      long now=m_ctx.NowMsc();
      long delay=(long)m_cfg.ModeDelayMs();
      for(int i=m_conf.Count()-1;i>=0;i--)
        {
         SSignal s;
         if(!m_conf.Get(i,s))
            continue;
         CEngineBase *eng=m_engines.Get(s.engine);
         string why="";
         if(now-s.firstSeenMsc<delay)
           {
            if(CheckPointer(eng)==POINTER_INVALID || !eng.IsStillValid(s,why))
              {
               m_conf.RemoveAt(i);
               Decide(s,false,FTF_REJ_SIGNAL_INVALID,"during confirmation: "+why,0.0);
              }
            continue;
           }
         m_conf.RemoveAt(i);
         string d="";
         int r=m_gate.Revalidate(s,d);
         if(r!=FTF_OK)
           {
            Decide(s,false,r,"after "+IntegerToString(delay)+" ms confirmation: "+d,0.0);
            continue;
           }
         TryExecute(s,0,cycleStartUs);
        }
     }

   void              ProcessSignals(const ulong cycleStartUs)
     {
      int n=m_engines.Evaluate(m_sigs);
      if(n<=0)
         return;
      for(int i=0;i<n;i++)
         CountSetup(m_sigs[i]);
      m_cr.Resolve(m_sigs,n,m_reasons,m_details);
      bool confirm=(m_cfg.UseConfirmDelay() && m_cfg.ModeDelayMs()>0);
      for(int i=0;i<n;i++)
        {
         SSignal s=m_sigs[i];
         if(m_reasons[i]!=FTF_OK)
           {
            Decide(s,false,m_reasons[i],m_details[i],0.0);
            continue;
           }
         if(m_global!=FTF_OK)
           {
            Decide(s,false,m_global,m_globalDetail,0.0);
            continue;
           }
         if(confirm)
           {
            if(!m_conf.HasSetup(s.setupId) && m_conf.Add(s))
               Decide(s,false,FTF_REJ_CONFIRM_PENDING,"parked "+IntegerToString(m_cfg.ModeDelayMs())+" ms",0.0);
            continue;
           }
         TryExecute(s,0,cycleStartUs);
        }
     }

   //--- spec G.4 steps 2-3: re-activate and verify every safety (informational, never extends the pause)
   void              Verify(const string name,const bool ok,const string d,int &pass,int &warn)
     {
      if(ok)
         pass++;
      else
         warn++;
      m_ctx.Event("SAFETY_CHECK",(ok ? "PASS" : "WARN"),name+": "+d);
     }

   void              RunSafetyVerification(void)
     {
      m_ctx.Event("SAFETY_CHECK","START","equity drawdown pause - re-activating and verifying safeties, automatic restart in "+
                  IntegerToString(m_cfg.DdPauseSec)+" s");
      //--- re-activate
      m_md.RefreshSpecNow(false);
      m_news.Refresh(true);
      m_expo.Refresh(true);
      m_mi.Heartbeat();
      ProcessClosures();
      //--- verify
      int pass=0;
      int warn=0;
      string why="";
      bool ta=m_pf.TradeAllowed(why);
      Verify("terminal",ta && (m_pf.IsTester() || m_pf.IsConnected()),(ta ? "trading allowed" : why)+
             (m_pf.IsTester() || m_pf.IsConnected() ? ", connected" : ", NOT connected"),pass,warn);
      Verify("market",m_md.TickFresh(),"last tick "+IntegerToString(m_md.TickAgeMs())+" ms ago, spread "+
             FTF_D(m_md.SpreadPts(),1)+" pts (limit "+m_gate.SpreadLimitText()+")",pass,warn);
      double ml=m_pf.MarginLevel();
      Verify("margin",(ml==0.0 || ml>=150.0),"margin level "+(ml==0.0 ? "n/a (no position)" : FTF_D(ml,1)+"%")+
             ", free margin "+FTF_D(m_pf.FreeMargin(),2),pass,warn);
      bool okD=m_dd.SelfCheck(why);
      Verify("drawdown",okD,why,pass,warn);
      okD=m_cl.SelfCheck(why);
      Verify("consecutive losses",okD,why,pass,warn);
      okD=m_eq.SelfCheck(why);
      Verify("execution quality",okD,why,pass,warn);
      okD=m_news.SelfCheck(why);
      Verify("news filter",okD,why,pass,warn);
      okD=m_sess.SelfCheck(why);
      Verify("session filter",okD,why,pass,warn);
      okD=m_roll.SelfCheck(why);
      Verify("rollover filter",okD,why,pass,warn);
      okD=m_expo.SelfCheck(why);
      Verify("aggregate exposure",okD,why,pass,warn);
      okD=m_mi.SelfCheck(why);
      Verify("multi-instance",okD,why,pass,warn);
      okD=m_tracker.SelfCheck(why);
      Verify("positions",okD,why,pass,warn);
      okD=m_exec.SelfCheck(why);
      Verify("execution",okD,why,pass,warn);
      okD=m_pm.SelfCheck(why);
      Verify("position management",okD,why,pass,warn);
      m_ctx.Event("SAFETY_CHECK","SUMMARY",IntegerToString(pass)+" PASS / "+IntegerToString(warn)+
                  " WARN - open positions managed, automatic restart in "+IntegerToString(m_dd.PauseRemainingMs()/1000+1)+" s");
     }

   void              SaveStates(const bool all)
     {
      if(!m_state.Enabled())
         return;
      m_dd.Save();
      m_cl.Save();
      m_risk.Save();
      m_engines.SaveAll();
      if(all)
         m_tracker.SaveAll();
     }

   void              DayChange(void)
     {
      datetime srv=m_md.ServerTime();
      if(srv<=0)
         return;
      datetime day=FTF_DayStart(srv);
      if(m_day==0)
        {
         m_day=day;
         return;
        }
      if(day==m_day)
         return;
      m_log.Info("STAT","day closed: "+m_stats.SummaryLine(0,srv));
      m_stats.OnDayChange(srv);
      m_day=day;
     }

   void              Periodic(const long now)
     {
      //--- state + heartbeat
      if(m_lastState==0 || now-m_lastState>=FTF_CTRL_STATE_MS || now<m_lastState)
        {
         m_lastState=now;
         bool full=(m_lastPosMeta==0 || now-m_lastPosMeta>=FTF_CTRL_POSMETA_MS || now<m_lastPosMeta);
         if(full)
            m_lastPosMeta=now;
         SaveStates(full);
         m_state.SaveIfDirty(now,FTF_CTRL_STATE_MS);
         m_mi.Heartbeat();
        }
      //--- filters / exposure refresh (internally throttled)
      m_news.Refresh(false);
      m_expo.Refresh(false);
      //--- files
      if(m_lastFlush==0 || now-m_lastFlush>=FTF_CTRL_FLUSH_MS || now<m_lastFlush)
        {
         m_lastFlush=now;
         m_journal.Flush();
         m_log.Flush();
        }
      long statsMs=(long)m_cfg.StatsEveryMin*60000;
      if(m_lastStatsCsv==0)
         m_lastStatsCsv=now;
      if(now-m_lastStatsCsv>=statsMs || now<m_lastStatsCsv)
        {
         m_lastStatsCsv=now;
         WriteStats();
        }
      //--- drawings
      if(m_ui.Enabled())
        {
         if(m_lastDraw==0 || now-m_lastDraw>=FTF_CTRL_DRAW_MS || now<m_lastDraw || m_md.IsNewBar(PERIOD_M1))
           {
            m_lastDraw=now;
            m_engines.DrawAll();
           }
         if(m_lastNewsDraw==0 || now-m_lastNewsDraw>=FTF_CTRL_NEWS_DRAW_MS || now<m_lastNewsDraw)
           {
            m_lastNewsDraw=now;
            m_news.Draw();
           }
         UpdatePanel(now,false);
        }
     }

   void              WriteStats(void)
     {
      if(m_quiet || !m_cfg.LogCsv)
         return;
      datetime srv=m_md.ServerTime();
      string header=FTF_NAME+" v"+FTF_VERSION+" "+m_ctx.Tag()+" | "+FTF_TimeStr(srv)+" | start "+FTF_TimeStr(m_stats.StartTime());
      m_stats.WriteCsv(m_folder+"\\stats.csv",m_cfg.LogCommon,srv,header);
     }

   //+---------------------------------------------------------------+
   //| dashboard (docs/04 section 13.1)                               |
   //+---------------------------------------------------------------+
   void              UpdatePanel(const long now,const bool force)
     {
      if(!m_ui.Enabled() || !m_cfg.ShowPanel)
         return;
      if(!force)
        {
         if(m_pf.IsTester())
           {
            if(m_lastPanelMsc>0 && now-m_lastPanelMsc>=0 && now-m_lastPanelMsc<(long)m_cfg.PanelRefreshMs)
               return;
           }
         else
           {
            ulong us=m_pf.Micros();
            if(m_lastPanelUs>0 && us>=m_lastPanelUs && us-m_lastPanelUs<(ulong)m_cfg.PanelRefreshMs*1000)
               return;
            m_lastPanelUs=us;
           }
        }
      m_lastPanelMsc=now;
      color txt=(m_cfg.PanelDark ? clrWhite : clrBlack);
      color dim=(m_cfg.PanelDark ? clrDarkGray : clrDimGray);
      int row=0;
      m_ui.PanelLine(row++,FTF_NAME+" v"+FTF_VERSION+" | "+FTF_PLATFORM+" | "+m_ctx.symbol+" | "+FTF_ModeStr(m_cfg.TradingMode)+
                     " | I"+IntegerToString(m_cfg.InstanceId)+" | magic "+IntegerToString(m_ctx.MagicFor(1))+"-"+
                     IntegerToString(m_ctx.MagicFor(3)),clrGold);
      //--- status
      string st="";
      color sc=clrLime;
      if(m_global==FTF_OK)
         st="STATUS: RUNNING - entries allowed";
      else
        {
         st="BLOCKED: "+FTF_ReasonStr(m_global)+" "+m_globalDetail;
         sc=(m_global==FTF_REJ_DD_PAUSE || m_global==FTF_REJ_TERMINAL || m_global==FTF_REJ_ERROR_COOLDOWN ||
             m_global==FTF_REJ_MULTI_INSTANCE ? clrRed : clrOrange);
        }
      m_ui.PanelLine(row++,Cut(st),sc);
      m_ui.PanelLine(row++,Cut("Equity "+FTF_D(m_pf.Equity(),2)+" | Balance "+FTF_D(m_pf.Balance(),2)+" | "+m_dd.Describe()),txt);
      double pt=m_md.PointSize();
      m_ui.PanelLine(row++,Cut("Spread "+FTF_D(m_md.SpreadPts(),1)+" pts (max "+m_gate.SpreadLimitText()+") | ATR M1 "+
                     FTF_D(pt>0.0 ? m_md.AtrM1()/pt : 0.0,1)+" pts (median "+FTF_D(pt>0.0 ? m_md.AtrM1Median()/pt : 0.0,1)+
                     ") | bid "+Px(m_md.BidPrice())),txt);
      int up=0;
      int down=0;
      double ratio=m_ticks.UpRatio(m_cfg.MomTickWindow,m_cfg.MomCountFlatTicks,up,down);
      m_ui.PanelLine(row++,Cut("Ticks vel "+FTF_D(m_md.VelRatio(),2)+"x acc "+FTF_D(m_md.VelAccel()*100.0,0)+"% | imbalance "+
                     (ratio>=0.0 ? FTF_D(ratio*100.0,0)+"% up" : "n/a")+" | order latency avg "+FTF_D(m_eq.AvgLatencyMs(),1)+
                     " ms max "+FTF_D(m_eq.MaxLatencyMs(),1)+" | slip "+FTF_D(m_eq.AvgSlipPts(),2)+" pts"),txt);
      m_ui.PanelLine(row++,Cut("H1 "+m_h1.Describe()+" | filter "+EnumToString(m_cfg.H1Filter)),txt);
      m_ui.PanelLine(row++,"---- ENGINES ----",dim);
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
        {
         CEngineBase *eng=m_engines.Get(e);
         if(CheckPointer(eng)==POINTER_INVALID)
            continue;
         string line=eng.StatusLine()+" | pos "+IntegerToString(m_tracker.CountEngine(e))+"/"+
                     IntegerToString(m_cfg.EngineMaxPositions(e))+" | today "+IntegerToString(m_stats.TodayTrades(e))+
                     " tr "+FTF_D(m_stats.TodayNet(e),2);
         m_ui.PanelLine(row++,Cut(line),(eng.Enabled() ? m_ui.EngineColor(e) : dim));
        }
      m_ui.PanelLine(row++,Cut("Positions "+IntegerToString(m_tracker.total)+"/"+IntegerToString(m_cfg.MaxPositionsSymbol)+
                     " | BUY "+IntegerToString(m_tracker.CountDir(FTF_DIR_BUY))+" SELL "+IntegerToString(m_tracker.CountDir(FTF_DIR_SELL))+
                     " | open risk "+FTF_D(m_tracker.OpenRiskMoney(),2)+" | lots "+FTF_D(m_tracker.OpenLots(),2)+
                     " | retries "+IntegerToString(m_exec.PendingRetries())+" | parked "+IntegerToString(m_conf.Count())),txt);
      string rej="";
      for(int k=0;k<3;k++)
        {
         int rr=0;
         int rc=0;
         if(m_stats.GetRejectTop(0,k,rr,rc) && rc>0)
            rej+=" "+FTF_ReasonStr(rr)+":"+IntegerToString(rc);
        }
      m_ui.PanelLine(row++,Cut("Today trades "+IntegerToString(m_stats.TodayTrades(0))+" W "+IntegerToString(m_stats.TodayWins(0))+
                     " net "+FTF_D(m_stats.TodayNet(0),2)+" | total "+IntegerToString(m_stats.Trades(0))+" WR "+
                     FTF_D(m_stats.WinRatePct(0),1)+"% PF "+FTF_D(m_stats.ProfitFactor(0),2)+" | top rejects"+
                     (StringLen(rej)>0 ? rej : " none")),txt);
      m_ui.PanelLine(row++,"---- PROTECTIONS ----",dim);
      m_ui.PanelLine(row++,Cut(m_news.Describe()+" | "+m_sess.Describe()+" | "+m_roll.Describe()),txt);
      m_ui.PanelLine(row++,Cut(m_cl.Describe()+" | "+m_eq.Describe()),txt);
      m_ui.PanelLine(row++,Cut(m_expo.Describe()+" | "+m_mi.Describe()+" | "+m_risk.Describe()),txt);
      m_ui.PanelLine(row++,Cut("Clock "+m_clock.Describe()+" | state "+(m_state.Enabled() ? "ON" : "OFF")+" | "+
                     m_cr.Describe()+" | cycle avg "+FTF_D(m_cycleUsAvg,0)+" us max "+FTF_D(m_cycleUsMax,0)),dim);
      m_ui.PanelLine(row++,Cut("Last signal: "+(StringLen(m_lastSignalText)>0 ? m_lastSignalText : "-")),txt);
      m_ui.PanelLine(row++,Cut("Last event: "+(StringLen(m_ctx.lastEvent)>0 ? m_ctx.lastEvent : "-")),dim);
      for(int r2=row;r2<FTF_PANEL_ROWS;r2++)
         m_ui.PanelLine(r2,"",txt);
      m_ui.PanelRender();
     }

   //--- one pipeline cycle (docs/09 section 8)
   void              Cycle(const bool fromTick)
     {
      if(!m_ready)
         return;
      ulong t0=m_pf.Micros();
      bool newTicks=m_md.Update();
      long now=m_md.NowMsc();
      m_log.SetTimeMsc(now);
      if(m_ctx.startMsc<=0 && now>0)
         m_ctx.startMsc=now;
      m_gate.BeginCycle();
      DayChange();
      m_h1.Update(m_md.IsNewBar(PERIOD_H1));
      m_engines.OnNewBars();
      m_dd.Update();
      if(m_dd.TakeVerifyRequest())
         RunSafetyVerification();
      m_cl.Update();
      ProcessClosures();
      m_pm.Manage();
      m_global=m_gate.GlobalCheck(m_globalDetail);
      if(m_global!=FTF_OK)
         m_log.Throttled(FTF_LOG_DEBUG,"ctrl.global."+IntegerToString(m_global),10000,"CTRL",
                         "new entries blocked: "+FTF_ReasonStr(m_global)+" "+m_globalDetail);
      ProcessRetries(t0);
      ProcessConfirmations(t0);
      if(newTicks || fromTick)
         ProcessSignals(t0);
      Periodic(now);
      //--- internal decision time (spec D.3: measured, not assumed)
      double us=(double)(m_pf.Micros()-t0);
      m_cycles++;
      m_cycleUsAvg=(m_cycles==1 ? us : m_cycleUsAvg*0.99+us*0.01);
      if(us>m_cycleUsMax)
         m_cycleUsMax=us;
     }

public:
                     CFranckyController(void)
     {
      m_ready=false;
      m_quiet=false;
      m_folder="";
      m_lastState=0;
      m_lastFlush=0;
      m_lastDraw=0;
      m_lastPosMeta=0;
      m_lastNewsDraw=0;
      m_lastStatsCsv=0;
      m_lastPanelMsc=0;
      m_lastPanelUs=0;
      m_day=0;
      m_cycles=0;
      m_cycleUsAvg=0.0;
      m_cycleUsMax=0.0;
      m_lastSignalText="";
      m_global=FTF_REJ_WARMUP;
      m_globalDetail="starting";
      for(int e=0;e<=FTF_ENGINE_COUNT;e++)
        {
         m_lastSetup[e]="";
         m_lastDecisionKey[e]="";
         m_lastDecisionMsc[e]=0;
        }
     }

   int               OnInitHandler(void)
     {
      m_ready=false;
      //--- 1. configuration
      m_cfg.LoadFromInputs();
      string errs="";
      bool valid=m_cfg.Validate(errs);
      //--- 2. platform (the chart symbol is the ONLY traded symbol - spec G.3)
      m_ctx.symbol=_Symbol;
      if(!m_pf.Init(GetPointer(m_log),_Symbol,m_cfg.TwoStepStops))
        {
         Print(FTF_NAME+": platform layer initialisation failed for "+_Symbol);
         return INIT_FAILED;
        }
      m_quiet=(m_pf.IsOptimization() && !m_cfg.LogInOptimization);
      //--- 3. logging
      m_folder=BuildFolder();
      int level=(m_quiet ? FTF_LOG_ERROR : (int)m_cfg.LogLevel);
      m_log.Init(level,(m_cfg.LogToJournal && !m_quiet),(m_cfg.LogToFile && !m_quiet),m_folder,m_cfg.LogCommon,
                 FTF_PLATFORM+"|"+_Symbol+"|I"+IntegerToString(m_cfg.InstanceId));
      if(!valid)
        {
         m_log.Error("CTRL","invalid inputs: "+errs);
         Alert(FTF_NAME+" "+_Symbol+": invalid inputs - "+errs);
         return INIT_PARAMETERS_INCORRECT;
        }
      if(StringLen(errs)>0)
         m_log.Warn("CTRL","input warnings: "+errs);
      m_journal.Init(GetPointer(m_log),m_folder,m_cfg.LogCommon,(m_cfg.LogCsv && !m_quiet),m_cfg.LogSignals,FTF_PLATFORM,
                     _Symbol,m_cfg.InstanceId,FTF_ModeStr(m_cfg.TradingMode));
      //--- 4. state store (live/demo only: a backtest always starts fresh)
      m_state.Init(GetPointer(m_log),StateFileName(),m_cfg.LogCommon,(m_cfg.StateEnabled && !m_pf.IsTester()));
      //--- 5. market data
      m_clock.Init(GetPointer(m_cfg),GetPointer(m_pf),GetPointer(m_log));
      m_ticks.Init(FTF_TICK_CAPACITY);
      m_ticks.SetLogger(GetPointer(m_log),m_cfg.LogThrottleMs);
      if(!m_md.Init(GetPointer(m_cfg),GetPointer(m_log),GetPointer(m_pf),GetPointer(m_ticks)))
         m_log.Warn("CTRL","market data not ready yet - entries wait for WARMUP");
      m_journal.SetDigits(m_md.DigitsCount());
      m_h1.Init(GetPointer(m_cfg),GetPointer(m_log),GetPointer(m_pf));
      bool uiOn=(!m_pf.IsOptimization() && (!m_pf.IsTester() || m_pf.IsVisual()) &&
                 (m_cfg.ShowPanel || m_cfg.DrawTrades || m_cfg.DrawZones));
      m_ui.Init(GetPointer(m_cfg),GetPointer(m_log),m_cfg.InstanceId,uiOn);
      //--- 6. context
      m_ctx.cfg=GetPointer(m_cfg);
      m_ctx.logger=GetPointer(m_log);
      m_ctx.journal=GetPointer(m_journal);
      m_ctx.stats=GetPointer(m_stats);
      m_ctx.state=GetPointer(m_state);
      m_ctx.pf=GetPointer(m_pf);
      m_ctx.clock=GetPointer(m_clock);
      m_ctx.ticks=GetPointer(m_ticks);
      m_ctx.md=GetPointer(m_md);
      m_ctx.h1=GetPointer(m_h1);
      m_ctx.ui=GetPointer(m_ui);
      m_ctx.instanceId=m_cfg.InstanceId;
      m_ctx.magicBase=(long)m_cfg.MagicBase;
      m_ctx.mode=(int)m_cfg.TradingMode;
      m_ctx.startMsc=m_md.NowMsc();
      m_stats.SetLogger(GetPointer(m_log));
      m_stats.Init(TimeCurrent(),m_pf.Equity());
      m_state.Load();
      //--- 7. trading layer
      bool ok=true;
      ok=m_engines.Init(GetPointer(m_ctx)) && ok;
      ok=m_tracker.Init(GetPointer(m_ctx)) && ok;
      ok=m_dd.Init(GetPointer(m_ctx)) && ok;
      ok=m_cl.Init(GetPointer(m_ctx)) && ok;
      ok=m_eq.Init(GetPointer(m_ctx)) && ok;
      ok=m_news.Init(GetPointer(m_ctx)) && ok;
      ok=m_sess.Init(GetPointer(m_ctx)) && ok;
      ok=m_roll.Init(GetPointer(m_ctx)) && ok;
      ok=m_risk.Init(GetPointer(m_ctx),GetPointer(m_tracker)) && ok;
      ok=m_expo.Init(GetPointer(m_ctx)) && ok;
      ok=m_mi.Init(GetPointer(m_ctx),GetPointer(m_tracker)) && ok;
      ok=m_cr.Init(GetPointer(m_ctx)) && ok;
      ok=m_conf.Init(GetPointer(m_ctx)) && ok;
      ok=m_exec.Init(GetPointer(m_ctx),GetPointer(m_tracker),GetPointer(m_eq)) && ok;
      ok=m_gate.Init(GetPointer(m_ctx),GetPointer(m_engines),GetPointer(m_tracker),GetPointer(m_dd),GetPointer(m_cl),
                     GetPointer(m_eq),GetPointer(m_news),GetPointer(m_sess),GetPointer(m_roll),GetPointer(m_risk),
                     GetPointer(m_expo),GetPointer(m_mi),GetPointer(m_exec),GetPointer(m_cr)) && ok;
      ok=m_pm.Init(GetPointer(m_ctx),GetPointer(m_tracker),GetPointer(m_exec),GetPointer(m_engines)) && ok;
      if(!ok)
         m_log.Warn("CTRL","one or more modules reported an initialisation problem - see the lines above");
      //--- 8. restart recovery (B.7)
      m_dd.Load();
      m_cl.Load();
      m_risk.Load();
      m_engines.LoadAll();
      int rec=m_tracker.RecoverOnStart();
      string why="";
      if(!m_mi.Acquire(why))
         m_log.Error("CTRL",why);
      m_news.Refresh(true);
      m_expo.Refresh(true);
      //--- 9. configuration dump (file only) + environment checks
      string lines[];
      int nl=m_cfg.DumpLines(lines);
      m_log.FileOnly("CFG","effective configuration ("+IntegerToString(nl)+" inputs):");
      for(int i=0;i<nl;i++)
         m_log.FileOnly("CFG",lines[i]);
      if(FTF_SymbolClass(_Symbol)=="")
         m_log.Warn("CTRL",_Symbol+" is not one of the V1 markets EURUSD / XAUUSD / BTCUSD (supported-symbol check "+
                    EnumToString(m_cfg.SymbolCheck)+")");
      if(!m_pf.IsHedging())
         m_log.Warn("CTRL","NETTING account: only one position per symbol is possible - use a hedging account for 3 per engine");
      m_ctx.Event("INIT","START",FTF_NAME+" v"+FTF_VERSION+" "+m_ctx.Tag()+" | account "+IntegerToString(m_pf.Login())+" "+
                  m_pf.Company()+" | "+(m_pf.IsTester() ? "TESTER" : "LIVE")+" | engines "+IntegerToString(m_engines.EnabledCount())+
                  " | recovered "+IntegerToString(rec)+" | magic "+IntegerToString(m_ctx.MagicFor(1))+"-"+
                  IntegerToString(m_ctx.MagicFor(3))+" | logs "+(m_cfg.LogCommon ? "Common\\Files\\" : "Files\\")+m_folder);
      //--- 10. timer (live and visual tests; every critical rule also runs from OnTick)
      if(!m_pf.IsTester() || m_pf.IsVisual())
         EventSetMillisecondTimer(m_cfg.TimerMs);
      m_ready=true;
      UpdatePanel(m_md.NowMsc(),true);
      return INIT_SUCCEEDED;
     }

   void              OnDeinitHandler(const int reason)
     {
      EventKillTimer();
      if(m_ready)
        {
         SaveStates(true);
         m_state.Save();
         WriteStats();
         datetime srv=m_md.ServerTime();
         for(int e=1;e<=FTF_ENGINE_COUNT;e++)
            m_log.Info("STAT",m_stats.SummaryLine(e,srv));
         m_log.Info("STAT",m_stats.SummaryLine(0,srv));
         m_ctx.Event("DEINIT","STOP",ReasonText(reason)+" | trades "+IntegerToString(m_stats.Trades(0))+" | net "+
                     FTF_D(m_stats.NetProfit(0),2)+" | open positions left "+IntegerToString(m_tracker.total)+
                     " (managed again at the next start)");
         m_mi.Release();
        }
      m_journal.Flush();
      m_journal.Deinit();
      bool keep=(m_cfg.KeepObjectsOnExit || reason==REASON_CHARTCHANGE || reason==REASON_PARAMETERS ||
                 reason==REASON_RECOMPILE || reason==REASON_TEMPLATE);
      m_ui.Deinit(!keep);
      m_pf.Deinit();
      m_log.Deinit();
      m_ready=false;
     }

   void              OnTickHandler(void)  { Cycle(true); }
   void              OnTimerHandler(void) { Cycle(false); }

   //--- MT5 OnTradeTransaction(DEAL_ADD): reconcile closed positions immediately
   void              OnTradeHandler(void)
     {
      if(!m_ready)
         return;
      ProcessClosures();
     }

   double            OnTesterHandler(void)
     {
      WriteStats();
      double v=m_stats.OptCriterion((int)m_cfg.OptCriterion,m_cfg.OptMinTrades);
      m_log.Info("STAT","OnTester criterion "+EnumToString(m_cfg.OptCriterion)+" = "+FTF_D(v,4)+" | "+
                 m_stats.SummaryLine(0,m_md.ServerTime()));
      return v;
     }
  };

#endif // FTF_CONTROLLER_MQH
