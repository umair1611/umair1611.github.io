//+------------------------------------------------------------------+
//|                                                   SafetyGate.mqh |
//|  CSafetyGate - the Risk & Safety Gate (spec Table 5, Table 13).  |
//|  GlobalCheck(): conditions shared by every signal, computed once |
//|  per cycle. CheckSignal(): per-signal checks + lot sizing.       |
//|  The gate only accepts/refuses with a reason code; it never      |
//|  changes strategy logic (only SL/TP widening for broker stops).  |
//|  Check orders: docs/09 section 8.                                |
//+------------------------------------------------------------------+
#ifndef FTF_SAFETY_GATE_MQH
#define FTF_SAFETY_GATE_MQH

#include <FranckyTriFlux\Core\EngineManager.mqh>
#include <FranckyTriFlux\Core\PositionTracker.mqh>
#include <FranckyTriFlux\Core\Protections.mqh>
#include <FranckyTriFlux\Core\Filters.mqh>
#include <FranckyTriFlux\Core\RiskManager.mqh>
#include <FranckyTriFlux\Core\Execution.mqh>
#include <FranckyTriFlux\Core\ConflictResolver.mqh>

class CSafetyGate
  {
private:
   CFtfContext         *m_ctx;
   CEngineManager      *m_eng;
   CPositionTracker    *m_tracker;
   CDrawdownGuard      *m_dd;
   CConsecLossGuard    *m_cl;
   CExecQualityGuard   *m_eq;
   CNewsFilter         *m_news;
   CSessionFilter      *m_sess;
   CRolloverFilter     *m_roll;
   CRiskManager        *m_risk;
   CExposureGuard      *m_expo;
   CMultiInstanceGuard *m_mi;
   CExecutionEngine    *m_exec;
   CConflictResolver   *m_cr;
   long              m_cycle;
   long              m_cachedCycle;
   int               m_lastGlobal;
   string            m_lastGlobalDetail;

   string            P(const double v) { return FTF_D(v,m_ctx.md.DigitsCount()); }

   double            EntryPrice(const int dir)
     {
      return (dir==FTF_DIR_BUY ? m_ctx.md.AskPrice() : m_ctx.md.BidPrice());
     }

   int               ComputeGlobal(string &detail)
     {
      CConfig *cf=m_ctx.cfg;
      string why="";
      detail="";
      //--- master switch
      if(!cf.EnableTrading)
        {
         detail="'Enable new entries' is OFF";
         return FTF_REJ_TRADING_OFF;
        }
      //--- symbol
      if(cf.SymbolCheck==FTF_SYMCHK_BLOCK && FTF_SymbolClass(m_ctx.symbol)=="")
        {
         detail=m_ctx.symbol+" is not a V1 market (EURUSD/XAUUSD/BTCUSD)";
         return FTF_REJ_SYMBOL;
        }
      if(!m_ctx.md.spec.tradeAllowed)
        {
         detail="trading disabled for "+m_ctx.symbol;
         return FTF_REJ_SYMBOL;
        }
      if(!m_ctx.pf.SymbolTradable(why))
        {
         detail=why;
         return FTF_REJ_SYMBOL;
        }
      //--- terminal / permissions / connection
      if(!m_ctx.pf.TradeAllowed(why))
        {
         detail=why;
         return FTF_REJ_TERMINAL;
        }
      if(!m_ctx.pf.IsTester() && !m_ctx.pf.IsConnected())
        {
         detail="terminal not connected";
         return FTF_REJ_TERMINAL;
        }
      //--- market alive
      if(!m_ctx.md.TickFresh())
        {
         detail="last tick "+IntegerToString(m_ctx.md.TickAgeMs()/1000)+" s old (max "+IntegerToString(cf.MaxTickAgeSec)+" s)";
         return FTF_REJ_STALE_TICK;
        }
      //--- warm-up / restart grace
      if(!m_ctx.md.IsWarm(why))
        {
         detail=why;
         return FTF_REJ_WARMUP;
        }
      long now=m_ctx.NowMsc();
      if(cf.RestartGraceSec>0 && m_ctx.startMsc>0 && now-m_ctx.startMsc<(long)cf.RestartGraceSec*1000)
        {
         detail="start grace "+IntegerToString(((long)cf.RestartGraceSec*1000-(now-m_ctx.startMsc))/1000+1)+" s";
         return FTF_REJ_WARMUP;
        }
      //--- duplicate Instance ID
      if(m_mi.IsDuplicateInstance())
        {
         detail="duplicate Instance ID "+IntegerToString(m_ctx.instanceId);
         return FTF_REJ_MULTI_INSTANCE;
        }
      //--- 10 % equity pause (G.4)
      if(m_dd.IsPaused())
        {
         detail=m_dd.Describe();
         return FTF_REJ_DD_PAUSE;
        }
      //--- pause after a permanent broker error
      if(m_exec.InErrorCooldown(why))
        {
         detail=why;
         return FTF_REJ_ERROR_COOLDOWN;
        }
      //--- time filters (B.1, B.2, B.3)
      if(m_news.IsBlocked(why))
        {
         detail=why;
         return FTF_REJ_NEWS;
        }
      if(!m_sess.IsAllowed(why))
        {
         detail=why;
         return FTF_REJ_SESSION;
        }
      if(m_roll.IsBlocked(why))
        {
         detail=why;
         return FTF_REJ_ROLLOVER;
        }
      //--- spread (Table 13: threshold per symbol/mode)
      int limit=cf.ModeMaxSpreadPts();
      double sp=m_ctx.md.SpreadPts();
      if(limit>0)
        {
         if(sp>(double)limit)
           {
            detail="spread "+FTF_D(sp,1)+" pts > "+IntegerToString(limit)+" ("+FTF_ModeStr(cf.TradingMode)+")";
            return FTF_REJ_SPREAD;
           }
        }
      else
         if(cf.AutoMaxSpreadAtr>0.0 && m_ctx.md.AtrM1()>0.0 && m_ctx.md.Spread()>cf.AutoMaxSpreadAtr*m_ctx.md.AtrM1())
           {
            detail="spread "+FTF_D(sp,1)+" pts > auto "+FTF_D(cf.AutoMaxSpreadAtr,2)+" x ATR M1 ("+
                   FTF_D(cf.AutoMaxSpreadAtr*m_ctx.md.AtrM1()/m_ctx.md.PointSize(),1)+" pts)";
            return FTF_REJ_SPREAD;
           }
      //--- volatility anomaly (Table 13)
      double atr=m_ctx.md.AtrM1();
      double med=m_ctx.md.AtrM1Median();
      if(cf.VolAnomalyAtrMult>0.0 && med>0.0 && atr>cf.VolAnomalyAtrMult*med)
        {
         detail="ATR M1 "+FTF_D(atr/med,2)+"x median > "+FTF_D(cf.VolAnomalyAtrMult,2);
         return FTF_REJ_VOLATILITY;
        }
      if(cf.VolAnomalyVelMult>0.0 && m_ctx.md.VelOk() && m_ctx.md.VelRatio()>cf.VolAnomalyVelMult)
        {
         detail="tick velocity "+FTF_D(m_ctx.md.VelRatio(),2)+"x median > "+FTF_D(cf.VolAnomalyVelMult,2);
         return FTF_REJ_VOLATILITY;
        }
      double ms=m_ctx.md.MedianSpread();
      if(cf.VolAnomalySpreadMult>0.0 && ms>0.0 && m_ctx.md.Spread()>cf.VolAnomalySpreadMult*ms)
        {
         detail="spread "+FTF_D(m_ctx.md.Spread()/ms,2)+"x its median > "+FTF_D(cf.VolAnomalySpreadMult,2);
         return FTF_REJ_VOLATILITY;
        }
      //--- execution quality
      if(m_eq.IsBlocked(why))
        {
         detail=why;
         return FTF_REJ_EXEC_QUALITY;
        }
      //--- opposite-signal hold (Table 12)
      if(m_cr.IsHolding())
        {
         detail="conflict hold "+IntegerToString(m_cr.HoldRemainingMs())+" ms";
         return FTF_REJ_CONFLICT;
        }
      return FTF_OK;
     }

   //--- broker stops level: widen (ADJUST) or refuse (REJECT)
   int               CheckStops(SSignal &sig,const double entry,string &detail)
     {
      double pt=m_ctx.md.PointSize();
      double minDist=(double)m_ctx.md.spec.stopsLevelPts*pt;
      if(minDist<=0.0)
         return FTF_OK;
      double slDist=MathAbs(entry-sig.sl);
      double tpDist=MathAbs(sig.tp-entry);
      if(slDist>=minDist && tpDist>=minDist)
         return FTF_OK;
      if(m_ctx.cfg.StopsPolicy==FTF_STOPS_REJECT)
        {
         detail="SL "+FTF_D(slDist/pt,1)+" / TP "+FTF_D(tpDist/pt,1)+" pts < broker stops level "+
                IntegerToString(m_ctx.md.spec.stopsLevelPts)+" pts";
         return FTF_REJ_STOPS_LEVEL;
        }
      double need=minDist+pt;
      string before="SL "+P(sig.sl)+" TP "+P(sig.tp);
      if(slDist<minDist)
         sig.sl=FTF_NormalizePrice(entry-sig.dir*need,m_ctx.md.TickSize(),m_ctx.md.DigitsCount());
      if(tpDist<minDist)
         sig.tp=FTF_NormalizePrice(entry+sig.dir*need,m_ctx.md.TickSize(),m_ctx.md.DigitsCount());
      m_ctx.logger.Debug("GATE","stops level "+IntegerToString(m_ctx.md.spec.stopsLevelPts)+" pts: "+before+" -> SL "+
                      P(sig.sl)+" TP "+P(sig.tp)+" ("+sig.setupId+")");
      return FTF_OK;
     }

public:
                     CSafetyGate(void)
     {
      m_ctx=NULL; m_eng=NULL; m_tracker=NULL; m_dd=NULL; m_cl=NULL; m_eq=NULL; m_news=NULL; m_sess=NULL;
      m_roll=NULL; m_risk=NULL; m_expo=NULL; m_mi=NULL; m_exec=NULL; m_cr=NULL;
      m_cycle=0;
      m_cachedCycle=-1;
      m_lastGlobal=FTF_REJ_WARMUP;
      m_lastGlobalDetail="not evaluated yet";
     }

   bool              Init(CFtfContext *ctx,CEngineManager *eng,CPositionTracker *tracker,CDrawdownGuard *dd,
                          CConsecLossGuard *cl,CExecQualityGuard *eq,CNewsFilter *news,CSessionFilter *sess,
                          CRolloverFilter *roll,CRiskManager *risk,CExposureGuard *expo,CMultiInstanceGuard *mi,
                          CExecutionEngine *exec,CConflictResolver *cr)
     {
      m_ctx=ctx; m_eng=eng; m_tracker=tracker; m_dd=dd; m_cl=cl; m_eq=eq; m_news=news; m_sess=sess;
      m_roll=roll; m_risk=risk; m_expo=expo; m_mi=mi; m_exec=exec; m_cr=cr;
      if(CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_eng)==POINTER_INVALID ||
         CheckPointer(m_tracker)==POINTER_INVALID || CheckPointer(m_dd)==POINTER_INVALID ||
         CheckPointer(m_cl)==POINTER_INVALID || CheckPointer(m_eq)==POINTER_INVALID ||
         CheckPointer(m_news)==POINTER_INVALID || CheckPointer(m_sess)==POINTER_INVALID ||
         CheckPointer(m_roll)==POINTER_INVALID || CheckPointer(m_risk)==POINTER_INVALID ||
         CheckPointer(m_expo)==POINTER_INVALID || CheckPointer(m_mi)==POINTER_INVALID ||
         CheckPointer(m_exec)==POINTER_INVALID || CheckPointer(m_cr)==POINTER_INVALID)
         return false;
      return true;
     }

   void              BeginCycle(void) { m_cycle++; }

   int               GlobalCheck(string &detail)
     {
      if(m_cachedCycle!=m_cycle)
        {
         m_lastGlobal=ComputeGlobal(m_lastGlobalDetail);
         m_cachedCycle=m_cycle;
        }
      detail=m_lastGlobalDetail;
      return m_lastGlobal;
     }

   int               LastGlobal(void)       { return m_lastGlobal; }
   string            LastGlobalDetail(void) { return m_lastGlobalDetail; }

   //--- per-signal checks (docs/09 section 8) + lot sizing; may adjust sig.sl/tp for broker stops level
   int               CheckSignal(SSignal &sig,double &lots,double &riskMoney,string &detail)
     {
      lots=0.0;
      riskMoney=0.0;
      detail="";
      CConfig *cf=m_ctx.cfg;
      long now=m_ctx.NowMsc();
      int e=sig.engine;
      CEngineBase *eng=m_eng.Get(e);
      if(CheckPointer(eng)==POINTER_INVALID)
        {
         detail="unknown engine "+IntegerToString(e);
         return FTF_REJ_SIGNAL_INVALID;
        }
      //--- expiry
      if(now>sig.expiryMsc)
        {
         detail="signal age "+IntegerToString(now-sig.timeMsc)+" ms";
         return FTF_REJ_SIGNAL_EXPIRED;
        }
      //--- geometry
      double entry=EntryPrice(sig.dir);
      if(entry<=0.0 || sig.sl<=0.0 || sig.tp<=0.0 ||
         (sig.dir==FTF_DIR_BUY && !(sig.sl<entry && entry<sig.tp)) ||
         (sig.dir==FTF_DIR_SELL && !(sig.tp<entry && entry<sig.sl)) ||
         (sig.dir!=FTF_DIR_BUY && sig.dir!=FTF_DIR_SELL))
        {
         detail="entry "+P(entry)+" SL "+P(sig.sl)+" TP "+P(sig.tp)+" "+FTF_DirStr(sig.dir);
         return FTF_REJ_SLTP_INVALID;
        }
      //--- consecutive losses (B.4): the setup is burned so only a NEW setup trades after the cooldown
      string why="";
      if(m_cl.IsBlocked(e,why))
        {
         eng.MarkTraded(sig.setupId);
         detail=why+" (setup burned)";
         return FTF_REJ_CONSEC_LOSS;
        }
      //--- H1 STRICT (A.4)
      int r=m_ctx.h1.CheckEntry(e,sig.dir,why);
      if(r!=FTF_OK)
        {
         detail=why;
         return r;
        }
      //--- mode delay used as cooldown (Table 15)
      int delay=cf.ModeDelayMs();
      if(cf.UseCooldownDelay() && delay>0 && eng.LastEntryMsc()>0 && now-eng.LastEntryMsc()<(long)delay)
        {
         detail=FTF_ModeStr(cf.TradingMode)+" delay "+IntegerToString(delay)+" ms, last entry "+
                IntegerToString(now-eng.LastEntryMsc())+" ms ago";
         return FTF_REJ_COOLDOWN;
        }
      //--- global spacing between entries
      long lastAny=m_eng.LastAnyEntryMsc();
      if(cf.MinEntrySpacingMs>0 && lastAny>0 && now-lastAny<(long)cf.MinEntrySpacingMs)
        {
         detail="last entry "+IntegerToString(now-lastAny)+" ms ago < "+IntegerToString(cf.MinEntrySpacingMs);
         return FTF_REJ_SPACING;
        }
      //--- netting accounts allow one position per symbol
      if(!m_ctx.pf.IsHedging() && m_tracker.total>=1)
        {
         detail="netting account: one position per symbol";
         return FTF_REJ_NETTING;
        }
      //--- limits (G.2)
      int cntE=m_tracker.CountEngine(e);
      if(cntE>=cf.EngineMaxPositions(e))
        {
         detail=FTF_EngineCode(e)+" "+IntegerToString(cntE)+"/"+IntegerToString(cf.EngineMaxPositions(e));
         return FTF_REJ_MAX_POS_ENGINE;
        }
      if(m_tracker.total>=cf.MaxPositionsSymbol)
        {
         detail="symbol "+IntegerToString(m_tracker.total)+"/"+IntegerToString(cf.MaxPositionsSymbol);
         return FTF_REJ_MAX_POS_SYMBOL;
        }
      //--- hedging (Table 12 OPPOSITE_HEDGE)
      if(!cf.AllowOppositeHedge && m_tracker.HasDir(-sig.dir))
        {
         detail=IntegerToString(m_tracker.CountDir(-sig.dir))+" "+FTF_DirStr(-sig.dir)+" open, hedging OFF";
         return FTF_REJ_HEDGE;
        }
      if(cf.SameDirMode==FTF_SAMEDIR_IGNORE && m_tracker.HasDir(sig.dir))
        {
         detail=FTF_DirStr(sig.dir)+" already open (IGNORE mode)";
         return FTF_REJ_SAME_DIR;
        }
      //--- duplicates (G.2: no overlaps / duplicates)
      if(eng.WasTraded(sig.setupId))
        {
         detail="setup "+sig.setupId+" already traded";
         return FTF_REJ_DUPLICATE;
        }
      if(cf.DupMinDistAtr>0.0)
        {
         long lastMsc=0;
         double lastPx=m_tracker.LastEntryPrice(e,sig.dir,lastMsc);
         double minD=cf.DupMinDistAtr*m_ctx.md.AtrM1();
         if(lastPx>0.0 && minD>0.0 && MathAbs(entry-lastPx)<minD)
           {
            detail="last "+FTF_EngineCode(e)+" "+FTF_DirStr(sig.dir)+" entry "+P(lastPx)+" closer than "+
                   FTF_D(cf.DupMinDistAtr,2)+" x ATR";
            return FTF_REJ_DUPLICATE;
           }
        }
      r=m_mi.CheckSignal(sig,why);
      if(r!=FTF_OK)
        {
         detail=why;
         return r;
        }
      //--- broker stops level, then the SL/TP ratio guard (Table 14 - never shrink TP)
      r=CheckStops(sig,entry,why);
      if(r!=FTF_OK)
        {
         detail=why;
         return r;
        }
      double slDist=MathAbs(entry-sig.sl);
      double tpDist=MathAbs(sig.tp-entry);
      if(cf.MaxSlTpRatio>0.0 && tpDist>0.0 && slDist/tpDist>cf.MaxSlTpRatio)
        {
         detail="SL/TP "+FTF_D(slDist/tpDist,2)+" > "+FTF_D(cf.MaxSlTpRatio,2)+" (SL "+FTF_D(slDist/m_ctx.md.PointSize(),1)+
                " TP "+FTF_D(tpDist/m_ctx.md.PointSize(),1)+" pts)";
         return FTF_REJ_SLTP_RATIO;
        }
      //--- lot sizing, margin, exposure (B.5, B.6)
      double lotFactor=(cf.ExecQualityAction==FTF_EXECQ_REDUCE_LOT ? m_eq.LotFactor() : 1.0);
      r=m_risk.CalcLots(sig,entry,lotFactor,lots,riskMoney,why);
      if(r!=FTF_OK)
        {
         detail=why;
         return r;
        }
      string riskTxt=why;
      r=m_risk.CheckInstanceExposure(riskMoney,lots,why);
      if(r!=FTF_OK)
        {
         detail=why;
         return r;
        }
      r=m_expo.Check(sig,lots,riskMoney,why);
      if(r!=FTF_OK)
        {
         detail=why;
         return r;
        }
      detail=riskTxt+" | "+why;
      return FTF_OK;
     }

   //--- before a retry or a confirmed (parked) signal: B.8 "revalidate before each retry"
   int               Revalidate(SSignal &sig,string &detail)
     {
      detail="";
      long now=m_ctx.NowMsc();
      if(now>sig.expiryMsc)
        {
         detail="expired "+IntegerToString(now-sig.expiryMsc)+" ms ago";
         return FTF_REJ_SIGNAL_EXPIRED;
        }
      CEngineBase *eng=m_eng.Get(sig.engine);
      if(CheckPointer(eng)==POINTER_INVALID)
        {
         detail="unknown engine";
         return FTF_REJ_SIGNAL_INVALID;
        }
      string why="";
      if(!eng.IsStillValid(sig,why))
        {
         detail=why;
         return FTF_REJ_SIGNAL_INVALID;
        }
      double entry=EntryPrice(sig.dir);
      double atr=(sig.atr>0.0 ? sig.atr : m_ctx.md.AtrM1());
      double drift=MathAbs(entry-sig.price);
      if(m_ctx.cfg.RetryMaxDriftAtr>0.0 && atr>0.0 && drift>m_ctx.cfg.RetryMaxDriftAtr*atr)
        {
         detail="price moved "+FTF_D(drift/m_ctx.md.PointSize(),1)+" pts > "+FTF_D(m_ctx.cfg.RetryMaxDriftAtr,2)+" x ATR";
         return FTF_REJ_PRICE_DRIFT;
        }
      int g=GlobalCheck(why);
      if(g!=FTF_OK)
        {
         detail=why;
         return g;
        }
      //--- refresh the reference price; Momentum stops are distances -> shift them with the price
      if(sig.engine==FTF_ENG_MOMENTUM && entry>0.0)
        {
         double delta=entry-sig.price;
         sig.sl=FTF_NormalizePrice(sig.sl+delta,m_ctx.md.TickSize(),m_ctx.md.DigitsCount());
         sig.tp=FTF_NormalizePrice(sig.tp+delta,m_ctx.md.TickSize(),m_ctx.md.DigitsCount());
        }
      if(entry>0.0)
         sig.price=entry;
      detail="revalidated (drift "+FTF_D(drift/m_ctx.md.PointSize(),1)+" pts)";
      return FTF_OK;
     }

   //--- panel helper
   string            SpreadLimitText(void)
     {
      int limit=m_ctx.cfg.ModeMaxSpreadPts();
      if(limit>0)
         return IntegerToString(limit);
      double pt=m_ctx.md.PointSize();
      if(pt<=0.0)
         return "auto";
      return "auto "+FTF_D(m_ctx.cfg.AutoMaxSpreadAtr*m_ctx.md.AtrM1()/pt,1);
     }
  };

#endif // FTF_SAFETY_GATE_MQH
