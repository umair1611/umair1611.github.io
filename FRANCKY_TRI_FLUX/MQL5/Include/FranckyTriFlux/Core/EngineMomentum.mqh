//+------------------------------------------------------------------+
//|                                               EngineMomentum.mqh |
//|  CEngineMomentum - Engine A: tick momentum / micro-breakout      |
//|  (Ticks + M1, M5 as SOFT context).                               |
//|  Exact rules: docs/03 section 1 - contract: docs/09 7.13.        |
//|  The engine works alone: it never reads another engine's state. |
//+------------------------------------------------------------------+
#ifndef FTF_ENGINE_MOMENTUM_MQH
#define FTF_ENGINE_MOMENTUM_MQH

#include <FranckyTriFlux\Core\EngineBase.mqh>

#define FTF_MOM_W_RATIO      0.40  // TUNABLE (not an input yet) - docs/03 1.4 score weight: tick imbalance
#define FTF_MOM_W_VEL        0.25  // TUNABLE (not an input yet) - docs/03 1.4 score weight: velocity ratio
#define FTF_MOM_W_ACC        0.15  // TUNABLE (not an input yet) - docs/03 1.4 score weight: acceleration
#define FTF_MOM_W_ROC        0.20  // TUNABLE (not an input yet) - docs/03 1.4 score weight: ROC direction
#define FTF_MOM_INV_RATIO    0.5   // TUNABLE (not an input yet) - docs/03 1.5 inversion: bullish ratio vs 0.5
#define FTF_MOM_DRAW_KEEP    50    // TUNABLE (not an input yet) - micro-ranges kept on the chart (oldest removed)
#define FTF_MOM_DRAW_MIN_SEC 60    // TUNABLE (not an input yet) - min drawn width of a micro-range (s), cosmetic

class CEngineMomentum : public CEngineBase
  {
private:
   bool              m_warm;        // tick buffer covers velocity reference + windows (docs/03 1.1)
   double            m_ratio;       // bullish tick ratio over MomTickWindow (-1 = no directional tick)
   int               m_up;          // up ticks in the window
   int               m_down;        // down ticks in the window
   double            m_vel;         // velocity ratio (CMarketData, Momentum config)
   double            m_acc;         // acceleration (CMarketData)
   double            m_roc;         // M1 ROC in % (CMarketData, raw: may be EMPTY_VALUE)
   bool              m_rangeOk;     // micro-range available
   double            m_hi;          // micro-range high (ticks BEFORE the current tick)
   double            m_lo;          // micro-range low
   long              m_fromMsc;     // time of the oldest tick of the micro-range
   double            m_buf;         // breakout buffer (price units)
   string            m_drawn[];     // ring of drawn micro-range object ids
   int               m_drawPos;

   //--- small helpers ----------------------------------------------
   bool              Valid(const double v)
     {
      return (v!=EMPTY_VALUE && MathIsValidNumber(v));
     }
   string            SignedNum(const double v,const int nDigits)
     {
      return (v>=0.0 ? "+" : "")+DoubleToString(v,nDigits);
     }
   string            Pct(const double v)
     {
      return SignedNum(v*100.0,0)+"%";
     }
   string            Num(const double v,const int nDigits)
     {
      if(!Valid(v))
         return "n/a";
      return FTF_D(v,nDigits);
     }
   string            Px(const double price)
     {
      if(!Valid(price))
         return "n/a";
      return FTF_D(price,m_ctx.md.DigitsCount());
     }
   string            Pts(const double dist)
     {
      if(!Valid(dist))
         return "n/a";
      double pt=m_ctx.md.PointSize();
      if(pt<=0.0)
         return FTF_D(dist,m_ctx.md.DigitsCount());
      return FTF_D(dist/pt,1)+"pt";
     }
   string            RocText(void)
     {
      if(!Valid(m_roc))
         return "n/a";
      return SignedNum(m_roc,3)+"%";
     }
   //--- "imb 0.58 vel 1.10x acc +5%"
   string            LiveText(void)
     {
      string r=(m_ratio>=0.0 ? "imb "+FTF_D(m_ratio,2) : "imb n/a");
      return r+" vel "+FTF_D(m_vel,2)+"x acc "+Pct(m_acc);
     }
   string            RangeText(void)
     {
      if(!m_rangeOk)
         return " mr n/a bid "+Px(m_ctx.md.BidPrice());
      return " mr "+Px(m_lo)+"-"+Px(m_hi)+" buf "+Pts(m_buf)+" bid "+Px(m_ctx.md.BidPrice());
     }
   //--- M5 EMA20/50 trend (docs/03 1.2 item 5)
   string            M5Trend(void)
     {
      double f=m_ctx.md.EmaM5Fast();
      double s=m_ctx.md.EmaM5Slow();
      if(!Valid(f) || !Valid(s) || f<=0.0 || s<=0.0)
         return "n/a";
      if(f>s)
         return "up";
      if(f<s)
         return "down";
      return "flat";
     }
   //--- optional confirmations / context, for reason texts
   string            CtxText(void)
     {
      CConfig *cf=m_ctx.cfg;
      string t="";
      if(cf.MomUseEma)
         t+=" ema"+IntegerToString(cf.MomEmaFast)+"/"+IntegerToString(cf.MomEmaSlow)+" "+
            Px(m_ctx.md.EmaM1Fast())+"/"+Px(m_ctx.md.EmaM1Slow());
      if(cf.MomUseAdx)
         t+=" adx "+Num(m_ctx.md.AdxM1(),1)+" di+ "+Num(m_ctx.md.PlusDiM1(),1)+" di- "+Num(m_ctx.md.MinusDiM1(),1);
      if(cf.MomM5Context!=FTF_CTX_OFF)
         t+=" m5 "+M5Trend()+(cf.MomM5Context==FTF_CTX_STRICT ? "(strict)" : "(soft)");
      return t;
     }
   //--- one-line summary of the active rules (logged at init)
   string            RulesText(void)
     {
      CConfig *cf=m_ctx.cfg;
      string t="imb>="+FTF_D(cf.MomBuyRatio,2)+" / <="+FTF_D(cf.MomSellRatioEff(),2)+" over "+
               IntegerToString(cf.MomTickWindow)+" ticks (flat "+(cf.MomCountFlatTicks ? "ON" : "OFF")+")";
      t+=", vel>="+FTF_D(cf.MomVelRatio,2)+"x ("+(cf.MomVelMetric==FTF_VEL_TICKS ? "TICKS" : "PRICE_PATH")+" "+
         IntegerToString(cf.MomVelWindowMs)+"/"+IntegerToString(cf.MomVelRefMs)+" ms)";
      t+=", acc>="+Pct(cf.MomAccelMin)+", micro-range "+IntegerToString(cf.MomMicroRangeTicks)+" ticks, buf max("+
         FTF_D(cf.MomBufSpreadMult,2)+"xspr,"+FTF_D(cf.MomBufAtrMult,3)+"xATR)";
      t+=", ROC "+(cf.MomUseRoc ? "ON("+IntegerToString(cf.MomRocPeriod)+",|ROC|>="+FTF_D(cf.MomRocMin,3)+"%)" : "OFF");
      t+=", EMA "+(cf.MomUseEma ? "ON("+IntegerToString(cf.MomEmaFast)+"/"+IntegerToString(cf.MomEmaSlow)+")" : "OFF");
      t+=", ADX "+(cf.MomUseAdx ? "ON(>="+FTF_D(cf.MomAdxMin,1)+")" : "OFF");
      t+=", M5 "+(cf.MomM5Context==FTF_CTX_STRICT ? "STRICT" : (cf.MomM5Context==FTF_CTX_SOFT ? "SOFT" : "OFF"));
      t+=", TP max("+FTF_D(cf.MomTpSpreadMult,2)+"xspr,"+FTF_D(cf.MomTpAtrMult,2)+"xATR) SL max("+
         FTF_D(cf.MomSlSpreadMult,2)+"xspr,"+FTF_D(cf.MomSlAtrMult,2)+"xATR), ttl "+IntegerToString(cf.MomSignalTtlMs)+" ms";
      t+=", exit "+(cf.MomExitEnabled ? "ON(score<"+FTF_D(cf.MomExitScore,0)+", inversion "+
         IntegerToString(cf.MomExitInversionMs)+" ms over "+IntegerToString(cf.MomExitTicks)+" ticks)" : "OFF");
      return t;
     }

   //--- measurements (docs/03 1.1) -----------------------------------
   void              ResetMeasures(void)
     {
      m_ratio=-1.0; m_up=0; m_down=0; m_vel=0.0; m_acc=0.0; m_roc=EMPTY_VALUE;
      m_rangeOk=false; m_hi=0.0; m_lo=0.0; m_fromMsc=0; m_buf=0.0;
     }
   //--- tick imbalance + velocity + acceleration + ROC (cheap: called on demand)
   void              MeasureFlow(void)
     {
      int up=0;
      int down=0;
      m_ratio=m_ctx.ticks.UpRatio(m_ctx.cfg.MomTickWindow,m_ctx.cfg.MomCountFlatTicks,up,down);
      m_up=up;
      m_down=down;
      m_vel=m_ctx.md.VelRatio();
      m_acc=m_ctx.md.VelAccel();
      m_roc=m_ctx.md.RocM1();
      if(!Valid(m_vel))
         m_vel=0.0;
      if(!Valid(m_acc))
         m_acc=0.0;
     }
   //--- micro-range of the MomMicroRangeTicks ticks before the current one + breakout buffer
   void              MeasureRange(void)
     {
      double hi=0.0;
      double lo=0.0;
      long fromMsc=0;
      m_rangeOk=m_ctx.ticks.MicroRange(m_ctx.cfg.MomMicroRangeTicks,1,hi,lo,fromMsc);
      if(m_rangeOk && (hi<=0.0 || lo<=0.0 || hi<lo))
         m_rangeOk=false;
      m_hi=0.0;
      m_lo=0.0;
      m_fromMsc=0;
      if(m_rangeOk)
        {
         m_hi=hi;
         m_lo=lo;
         m_fromMsc=fromMsc;
        }
      double atr=m_ctx.md.AtrM1();
      if(!Valid(atr) || atr<0.0)
         atr=0.0;
      //--- buffer = max(x spread, x ATR M1)  (docs/03 1.1)
      m_buf=MathMax(m_ctx.cfg.MomBufSpreadMult*m_ctx.md.Spread(),m_ctx.cfg.MomBufAtrMult*atr);
     }
   //--- internal score from the cached measurements (docs/03 1.4)
   double            ScoreFrom(const int dir)
     {
      if(dir!=FTF_DIR_BUY && dir!=FTF_DIR_SELL)
         return 0.0;
      bool buy=(dir==FTF_DIR_BUY);
      CConfig *cf=m_ctx.cfg;
      double c1=0.0;
      if(m_ratio>=0.0)
        {
         double rd=(buy ? m_ratio : 1.0-m_ratio);
         //--- SELL threshold mirrored (= BUY ratio when symmetric) so the score is ~100 at entry
         double thr=(buy ? cf.MomBuyRatio : 1.0-cf.MomSellRatioEff());
         double den=thr-0.5;
         if(den>1e-9)
            c1=FTF_Clamp((rd-0.5)/den,0.0,1.0);
         else
            c1=(rd>=thr ? 1.0 : 0.0);
        }
      double velThr=cf.MomVelRatio;
      double c2=0.0;
      if(velThr-1.0>1e-9)
         c2=FTF_Clamp((m_vel-1.0)/(velThr-1.0),0.0,1.0);
      else
         c2=(m_vel>=velThr ? 1.0 : 0.0);
      double accThr=cf.MomAccelMin;
      double c3=1.0;                                   // accel threshold <= 0 -> component = 1
      if(accThr>0.0)
         c3=FTF_Clamp(m_acc/accThr,0.0,1.0);
      double c4=0.0;
      if(Valid(m_roc) && ((buy && m_roc>0.0) || (!buy && m_roc<0.0)))
         c4=1.0;
      return 100.0*(FTF_MOM_W_RATIO*c1+FTF_MOM_W_VEL*c2+FTF_MOM_W_ACC*c3+FTF_MOM_W_ROC*c4);
     }

   //--- readiness -----------------------------------------------------
   //--- the tick buffer must span the velocity reference + 2 windows and hold enough ticks
   bool              CheckWarm(void)
     {
      CConfig *cf=m_ctx.cfg;
      int needMs=cf.MomVelRefMs+2*cf.MomVelWindowMs;
      int needTicks=(cf.MomTickWindow>cf.MomMicroRangeTicks ? cf.MomTickWindow : cf.MomMicroRangeTicks)+2;
      string needTxt=FTF_D((double)needMs/1000.0,0)+" s / "+IntegerToString(needTicks)+" ticks";
      if(m_ctx.md.TicksWarm(needMs,needTicks))
        {
         if(!m_warm)
           {
            m_warm=true;
            m_status="ready";
            SetInfo("ticks warm - evaluating every tick");
            //--- throttled: a quiet market may flip warm/not warm around the tick-count limit
            LogThrottled(FTF_LOG_INFO,"warmstate","tick history warm ("+IntegerToString(m_ctx.ticks.Count())+
                         " ticks, need "+needTxt+") - evaluating every tick");
           }
         return true;
        }
      if(m_warm)
         LogThrottled(FTF_LOG_INFO,"warmstate","tick history below "+needTxt+" - evaluation paused");
      m_warm=false;
      m_status="warming";
      int n=m_ctx.ticks.Count();
      long span=0;
      if(n>1)
         span=m_ctx.ticks.MscAt(0)-m_ctx.ticks.MscAt(n-1);
      string txt="warming ticks ("+FTF_D((double)span/1000.0,0)+"/"+FTF_D((double)needMs/1000.0,0)+" s, "+
                 IntegerToString(n)+"/"+IntegerToString(needTicks)+" ticks)";
      SetInfo(txt);
      LogThrottled(FTF_LOG_DEBUG,"warm",txt);
      return false;
     }
   bool              DataReady(void)
     {
      double atr=m_ctx.md.AtrM1();
      if(Valid(atr) && atr>0.0 && m_ctx.md.PointSize()>0.0 && m_ctx.md.BidPrice()>0.0 && m_ctx.md.AskPrice()>0.0)
         return true;
      m_status="waiting";
      SetInfo("waiting: ATR M1 / quotes not ready");
      LogThrottled(FTF_LOG_DEBUG,"nodata","no evaluation: ATR M1 "+Px(atr)+", bid "+Px(m_ctx.md.BidPrice())+
                   ", ask "+Px(m_ctx.md.AskPrice()));
      return false;
     }

   //--- entry rules (docs/03 1.2) ---------------------------------------
   //--- item 5: optional ROC / EMA / ADX / M5 STRICT confirmations (SOFT = logged only)
   bool              ConfirmOk(const int dir,string &why)
     {
      bool buy=(dir==FTF_DIR_BUY);
      string side=(buy ? "BUY " : "SELL ");
      CConfig *cf=m_ctx.cfg;
      if(cf.MomUseRoc)
        {
         bool rocDir=(Valid(m_roc) && (buy ? (m_roc>0.0) : (m_roc<0.0)));
         if(!rocDir || MathAbs(m_roc)<cf.MomRocMin)
           {
            why=side+"ROC "+RocText()+" (need "+(buy ? ">0" : "<0")+", |ROC|>="+FTF_D(cf.MomRocMin,3)+"%)";
            return false;
           }
        }
      if(cf.MomUseEma)
        {
         double f=m_ctx.md.EmaM1Fast();
         double s=m_ctx.md.EmaM1Slow();
         bool emaOk=(Valid(f) && Valid(s) && f>0.0 && s>0.0 && (buy ? (f>s) : (f<s)));
         if(!emaOk)
           {
            why=side+"EMA"+IntegerToString(cf.MomEmaFast)+" "+Px(f)+(buy ? " <= " : " >= ")+"EMA"+
                IntegerToString(cf.MomEmaSlow)+" "+Px(s);
            return false;
           }
        }
      if(cf.MomUseAdx)
        {
         double adx=m_ctx.md.AdxM1();
         double pdi=m_ctx.md.PlusDiM1();
         double mdi=m_ctx.md.MinusDiM1();
         bool adxOk=(Valid(adx) && Valid(pdi) && Valid(mdi) && adx>=cf.MomAdxMin && (buy ? (pdi>mdi) : (mdi>pdi)));
         if(!adxOk)
           {
            why=side+"ADX "+Num(adx,1)+" (min "+FTF_D(cf.MomAdxMin,1)+") +DI "+Num(pdi,1)+" -DI "+Num(mdi,1);
            return false;
           }
        }
      if(cf.MomM5Context==FTF_CTX_STRICT)
        {
         string m5=M5Trend();
         if(m5!=(buy ? "up" : "down"))
           {
            why=side+"M5 EMA20/50 "+m5+" (STRICT)";
            return false;
           }
        }
      why="";
      return true;
     }
   //--- items 1..5 for one direction. why = first failing rule, cand = imbalance or breakout present
   bool              CheckDir(const int dir,string &why,bool &cand)
     {
      bool buy=(dir==FTF_DIR_BUY);
      string side=(buy ? "BUY " : "SELL ");
      CConfig *cf=m_ctx.cfg;
      double bid=m_ctx.md.BidPrice();
      double thr=(buy ? cf.MomBuyRatio : cf.MomSellRatioEff());
      bool ratioOk=(m_ratio>=0.0 && (buy ? (m_ratio>=thr) : (m_ratio<=thr)));
      bool brkOk=(m_rangeOk && (buy ? (bid>m_hi+m_buf) : (bid<m_lo-m_buf)));
      cand=(ratioOk || brkOk);
      if(m_ratio<0.0)
        {
         why=side+"no directional tick in last "+IntegerToString(cf.MomTickWindow)+" ticks";
         return false;
        }
      if(!ratioOk)
        {
         why=side+"imb "+FTF_D(m_ratio,2)+(buy ? "<" : ">")+FTF_D(thr,2);
         return false;
        }
      if(m_vel<cf.MomVelRatio)
        {
         why=side+"vel "+FTF_D(m_vel,2)+"x<"+FTF_D(cf.MomVelRatio,2)+"x";
         return false;
        }
      if(m_acc<cf.MomAccelMin)
        {
         why=side+"acc "+Pct(m_acc)+"<"+Pct(cf.MomAccelMin);
         return false;
        }
      if(!m_rangeOk)
        {
         why=side+"micro-range n/a";
         return false;
        }
      if(!brkOk)
        {
         double edge=(buy ? m_hi+m_buf : m_lo-m_buf);
         why=side+"no breakout: bid "+Px(bid)+(buy ? "<=" : ">=")+Px(edge)+" (buf "+Pts(m_buf)+")";
         return false;
        }
      return ConfirmOk(dir,why);
     }
   //--- panel text + DEBUG log of rejected candidates (throttled)
   void              ReportWaiting(const string whyB,const string whyS,const bool candB,const bool candS)
     {
      bool showBuy=(m_ratio>=0.5);
      if(candB && !candS)
         showBuy=true;
      if(candS && !candB)
         showBuy=false;
      m_status="waiting";
      SetInfo("waiting: "+(showBuy ? whyB : whyS));
      if(candB)
         LogThrottled(FTF_LOG_DEBUG,"rejB","BUY candidate rejected: "+whyB+" | "+LiveText()+RangeText());
      if(candS)
         LogThrottled(FTF_LOG_DEBUG,"rejS","SELL candidate rejected: "+whyS+" | "+LiveText()+RangeText());
     }

   //--- signal ----------------------------------------------------------
   string            ReasonText(const int dir,const double bid,const double level,const double slDist,
                                const double tpDist,const double atr)
     {
      bool buy=(dir==FTF_DIR_BUY);
      double excess=(buy ? bid-level : level-bid);
      string t=LiveText()+" brk "+Px(level)+(buy ? "+" : "-")+Pts(excess)+" buf "+Pts(m_buf)+" roc "+RocText();
      t+=CtxText();
      t+=" | up/dn "+IntegerToString(m_up)+"/"+IntegerToString(m_down)+" mr "+Px(m_lo)+"-"+Px(m_hi)+
         " spr "+Pts(m_ctx.md.Spread())+" atr "+Pts(atr)+" sl "+Pts(slDist)+" tp "+Pts(tpDist);
      return t;
     }
   //--- SL/TP per docs/03 1.3: BUY from ask, SELL from bid
   bool              BuildSignal(SSignal &s,const int dir,const string setupId,const double level)
     {
      bool buy=(dir==FTF_DIR_BUY);
      CConfig *cf=m_ctx.cfg;
      double spread=m_ctx.md.Spread();
      double atr=m_ctx.md.AtrM1();
      double tpDist=MathMax(cf.MomTpSpreadMult*spread,cf.MomTpAtrMult*atr);
      double slDist=MathMax(cf.MomSlSpreadMult*spread,cf.MomSlAtrMult*atr);
      if(tpDist<=0.0 || slDist<=0.0)
        {
         m_status="waiting";
         SetInfo("waiting: SL/TP distance is 0");
         LogThrottled(FTF_LOG_WARN,"sltp0",FTF_DirStr(dir)+" "+setupId+" skipped: SL/TP distance 0 (spread "+
                      Pts(spread)+", ATR "+Pts(atr)+")");
         return false;
        }
      double bid=m_ctx.md.BidPrice();
      MeasureFlow();
      double q=ScoreFrom(dir);                       // == ScoreFor(dir) at signal time
      PrepareSignal(s,dir,setupId,"TICK/M1");
      double entry=s.price;                          // ask for BUY, bid for SELL (PrepareSignal)
      s.sl=Norm(buy ? entry-slDist : entry+slDist);
      s.tp=Norm(buy ? entry+tpDist : entry-tpDist);
      s.invalidation=level;                          // broken micro-range edge (docs/09 7.13)
      s.quality=q;
      s.atr=atr;
      s.structOk=true;                               // the micro-range breakout is this engine's structure
      s.reason=ReasonText(dir,bid,level,slDist,tpDist,atr);
      return true;
     }
   //--- micro-range drawn as two segments (docs/09 section 10: MR_<signalId>)
   void              DrawMicroRange(const SSignal &s)
     {
      if(!m_ctx.cfg.DrawZones || CheckPointer(m_ctx.ui)==POINTER_INVALID || !m_ctx.ui.Enabled())
         return;
      if(!m_rangeOk || m_fromMsc<=0)
         return;
      string oid="MR_"+IntegerToString(s.id);
      datetime t1=(datetime)(m_fromMsc/1000);
      datetime t2=(datetime)(s.timeMsc/1000);
      if((long)t2-(long)t1<FTF_MOM_DRAW_MIN_SEC)
         t2=(datetime)((long)t1+FTF_MOM_DRAW_MIN_SEC);
      color clr=m_ctx.ui.EngineColor(m_id);
      string tip=s.setupId+" micro-range "+IntegerToString(m_ctx.cfg.MomMicroRangeTicks)+" ticks";
      m_ctx.ui.DrawSegment(oid+"_H",t1,m_hi,t2,m_hi,clr,(int)STYLE_DOT,tip+" high "+Px(m_hi));
      m_ctx.ui.DrawSegment(oid+"_L",t1,m_lo,t2,m_lo,clr,(int)STYLE_DOT,tip+" low "+Px(m_lo));
      //--- keep only the last FTF_MOM_DRAW_KEEP micro-ranges on the chart
      int k=m_drawPos;
      if(k>=0 && k<ArraySize(m_drawn))
        {
         if(StringLen(m_drawn[k])>0)
           {
            m_ctx.ui.Remove(m_drawn[k]+"_H");
            m_ctx.ui.Remove(m_drawn[k]+"_L");
           }
         m_drawn[k]=oid;
        }
      m_drawPos=(m_drawPos+1)%FTF_MOM_DRAW_KEEP;
     }
   void              AnnounceSignal(const SSignal &s)
     {
      m_status="signal";
      SetInfo("SIGNAL "+FTF_DirStr(s.dir)+" "+s.setupId+" q "+FTF_D(s.quality,0));
      Log(FTF_LOG_INFO,"SIGNAL #"+IntegerToString(s.id)+" "+FTF_DirStr(s.dir)+" "+s.setupId+" @"+Px(s.price)+
          " sl "+Px(s.sl)+" tp "+Px(s.tp)+" inval "+Px(s.invalidation)+" q "+FTF_D(s.quality,0)+
          " ttl "+IntegerToString(s.expiryMsc-s.timeMsc)+"ms | "+s.reason);
      DrawMicroRange(s);
     }

   //--- exits (docs/03 1.5) -----------------------------------------------
   //--- maintains pos.invStartMsc; returns true when the inversion persisted long enough
   bool              UpdateInversion(STrackedPos &pos,const bool inv,const double r,const long now)
     {
      string tk=IntegerToString((long)pos.ticket);
      if(!inv)
        {
         if(pos.invStartMsc>0)
            Log(FTF_LOG_DEBUG,"#"+tk+" tick inversion ended after "+IntegerToString(now-pos.invStartMsc)+
                " ms (bull "+FTF_D(r,2)+")");
         pos.invStartMsc=0;
         return false;
        }
      if(pos.invStartMsc<=0)
        {
         pos.invStartMsc=now;
         Log(FTF_LOG_DEBUG,"#"+tk+" "+FTF_DirStr(pos.dir)+" tick inversion started (bull "+FTF_D(r,2)+" over "+
             IntegerToString(m_ctx.cfg.MomExitTicks)+" ticks)");
        }
      return (pos.invStartMsc>0 && now-pos.invStartMsc>=(long)m_ctx.cfg.MomExitInversionMs);
     }
   //--- breakout level of a position: refLevel, or parsed from "MOM-B-1.08523" (refLevel is not
   //--- persisted in the state file, docs/09 7.14, so recovered positions rely on the setup id)
   double            BreakoutLevel(const STrackedPos &pos)
     {
      if(pos.refLevel>0.0)
         return pos.refLevel;
      if(StringFind(pos.setupId,"MOM-")!=0 || StringLen(pos.setupId)<=6)
         return 0.0;
      double v=StringToDouble(StringSubstr(pos.setupId,6));
      return (v>0.0 ? v : 0.0);
     }
   void              LogExit(const STrackedPos &pos,const int code,const string detail)
     {
      string msg="#"+IntegerToString((long)pos.ticket)+" "+FTF_DirStr(pos.dir)+" "+pos.setupId+" exit "+
                 FTF_ExitStr(code)+": "+detail;
      if(pos.pendingExit==FTF_EXIT_NONE)
         Log(FTF_LOG_INFO,msg);
      else
         LogThrottled(FTF_LOG_DEBUG,"exit",msg);
     }

public:
                     CEngineMomentum(void)
     {
      m_id=FTF_ENG_MOMENTUM;
      m_code="MOM";
      m_name="Momentum";
      m_warm=false;
      ResetMeasures();
      m_drawPos=0;
      ArrayResize(m_drawn,FTF_MOM_DRAW_KEEP);
      for(int i=0;i<FTF_MOM_DRAW_KEEP;i++)
         m_drawn[i]="";
     }
   virtual          ~CEngineMomentum(void) {}

   virtual bool      Init(CFtfContext *ctx)
     {
      if(!CEngineBase::Init(ctx))
         return false;
      m_warm=false;
      ResetMeasures();
      if(CheckPointer(m_ctx.md)==POINTER_INVALID || CheckPointer(m_ctx.ticks)==POINTER_INVALID)
        {
         m_enabled=false;
         m_status="OFF (no market data)";
         Log(FTF_LOG_ERROR,"market data / tick buffer not available - engine disabled");
         return false;
        }
      if(m_enabled)
        {
         m_status="warming";
         Log(FTF_LOG_INFO,"rules: "+RulesText());
        }
      return true;
     }

   //--- internal momentum score 0..100 for direction dir with the CURRENT measurements (docs/03 1.4)
   double            ScoreFor(const int dir)
     {
      if(CheckPointer(m_ctx)==POINTER_INVALID)
         return 0.0;
      MeasureFlow();
      return ScoreFrom(dir);
     }

   //--- every new tick: at most one signal (BUY and SELL rules are mutually exclusive)
   virtual int       Evaluate(SSignal &out[],const int startIndex,const int maxOut)
     {
      if(!m_enabled || CheckPointer(m_ctx)==POINTER_INVALID)
         return 0;
      if(!CheckWarm() || !DataReady())
         return 0;
      MeasureFlow();
      MeasureRange();
      if(CheckPointer(m_ctx.logger)!=POINTER_INVALID && m_ctx.logger.IsEnabled(FTF_LOG_TRACE))
         Log(FTF_LOG_TRACE,"tick "+LiveText()+RangeText()+" roc "+RocText());
      string whyB="";
      string whyS="";
      bool candB=false;
      bool candS=false;
      bool okB=CheckDir(FTF_DIR_BUY,whyB,candB);
      bool okS=CheckDir(FTF_DIR_SELL,whyS,candS);
      if(!okB && !okS)
        {
         ReportWaiting(whyB,whyS,candB,candS);
         return 0;
        }
      int dir=(okB ? FTF_DIR_BUY : FTF_DIR_SELL);
      //--- setup id = broken micro-range edge rounded to the symbol digits (docs/03 1.2)
      double level=Norm(dir==FTF_DIR_BUY ? m_hi : m_lo);
      string setupId="MOM-"+(dir==FTF_DIR_BUY ? "B" : "S")+"-"+DoubleToString(level,m_ctx.md.DigitsCount());
      if(WasTraded(setupId))
        {
         m_status="waiting";
         SetInfo("waiting: "+setupId+" already traded");
         LogThrottled(FTF_LOG_DEBUG,"dup",FTF_DirStr(dir)+" "+setupId+" already traded/burned - not emitted");
         return 0;
        }
      if(maxOut<1 || startIndex<0 || startIndex>=ArraySize(out))
        {
         LogThrottled(FTF_LOG_WARN,"full",FTF_DirStr(dir)+" "+setupId+" dropped: signal buffer full");
         return 0;
        }
      if(!BuildSignal(out[startIndex],dir,setupId,level))
         return 0;
      AnnounceSignal(out[startIndex]);
      return 1;
     }

   //--- confirm / retry revalidation: not expired, imbalance still beyond threshold, price beyond the level
   virtual bool      IsStillValid(const SSignal &sig,string &why)
     {
      why="";
      if(CheckPointer(m_ctx)==POINTER_INVALID || !m_enabled)
        {
         why="Momentum engine disabled";
         return false;
        }
      if(sig.dir!=FTF_DIR_BUY && sig.dir!=FTF_DIR_SELL)
        {
         why="no direction";
         return false;
        }
      long now=m_ctx.md.NowMsc();
      if(sig.expiryMsc>0 && now>sig.expiryMsc)
        {
         why="expired "+IntegerToString(now-sig.expiryMsc)+" ms ago";
         return false;
        }
      if(WasTraded(sig.setupId))
        {
         why="setup "+sig.setupId+" already traded";
         return false;
        }
      MeasureFlow();
      bool buy=(sig.dir==FTF_DIR_BUY);
      double thr=(buy ? m_ctx.cfg.MomBuyRatio : m_ctx.cfg.MomSellRatioEff());
      if(m_ratio<0.0 || (buy ? (m_ratio<thr) : (m_ratio>thr)))
        {
         why="imb "+(m_ratio>=0.0 ? FTF_D(m_ratio,2) : "n/a")+(buy ? "<" : ">")+FTF_D(thr,2);
         return false;
        }
      double bid=m_ctx.md.BidPrice();
      if(buy ? !(bid>sig.invalidation) : !(bid<sig.invalidation))
        {
         why="bid "+Px(bid)+(buy ? "<=" : ">=")+"breakout level "+Px(sig.invalidation)+" (back in micro-range)";
         return false;
        }
      why="valid: imb "+FTF_D(m_ratio,2)+" bid "+Px(bid)+" level "+Px(sig.invalidation);
      return true;
     }

   //--- Momentum-specific exits (docs/03 1.5). Runs even when the engine is disabled (open positions).
   virtual int       CheckExit(STrackedPos &pos,string &detail)
     {
      detail="";
      if(CheckPointer(m_ctx)==POINTER_INVALID || pos.engine!=FTF_ENG_MOMENTUM || !m_ctx.cfg.MomExitEnabled)
         return FTF_EXIT_NONE;
      if(pos.dir!=FTF_DIR_BUY && pos.dir!=FTF_DIR_SELL)
         return FTF_EXIT_NONE;
      CConfig *cf=m_ctx.cfg;
      if(m_ctx.ticks.Count()<cf.MomExitTicks)
         return FTF_EXIT_NONE;
      int up=0;
      int down=0;
      double r=m_ctx.ticks.UpRatio(cf.MomExitTicks,cf.MomCountFlatTicks,up,down);
      if(r<0.0)
         return FTF_EXIT_NONE;   // no directional tick: no information, inversion state kept as is
      bool buy=(pos.dir==FTF_DIR_BUY);
      long now=m_ctx.md.NowMsc();
      bool inv=(buy ? (r<FTF_MOM_INV_RATIO) : (r>FTF_MOM_INV_RATIO));
      if(!UpdateInversion(pos,inv,r,now))
         return FTF_EXIT_NONE;
      double score=ScoreFor(pos.dir);
      string invTxt="inversion "+IntegerToString(now-pos.invStartMsc)+"ms>="+IntegerToString(cf.MomExitInversionMs)+
                    "ms (bull "+FTF_D(r,2)+" up/dn "+IntegerToString(up)+"/"+IntegerToString(down)+" over "+
                    IntegerToString(cf.MomExitTicks)+" ticks)";
      if(score<cf.MomExitScore)
        {
         detail="score "+FTF_D(score,0)+"<"+FTF_D(cf.MomExitScore,0)+" | "+invTxt+" | "+LiveText()+" roc "+RocText();
         LogExit(pos,FTF_EXIT_MOM_LOSS,detail);
         return FTF_EXIT_MOM_LOSS;
        }
      double bid=m_ctx.md.BidPrice();
      double brkLevel=BreakoutLevel(pos);
      if(brkLevel>0.0 && bid>0.0 && (buy ? (bid<=brkLevel) : (bid>=brkLevel)))
        {
         detail="bid "+Px(bid)+(buy ? "<=" : ">=")+"breakout "+Px(brkLevel)+" (back inside micro-range) | "+
                invTxt+" | score "+FTF_D(score,0);
         LogExit(pos,FTF_EXIT_MOM_INVALID,detail);
         return FTF_EXIT_MOM_INVALID;
        }
      return FTF_EXIT_NONE;
     }

   //--- bar data is cached by CMarketData; only a DEBUG context line per M1 bar here
   virtual void      OnNewBar(const ENUM_TIMEFRAMES tf)
     {
      if(!m_enabled || tf!=PERIOD_M1 || CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_ctx.logger)==POINTER_INVALID)
         return;
      if(!m_ctx.logger.IsEnabled(FTF_LOG_DEBUG))
         return;
      m_roc=m_ctx.md.RocM1();
      Log(FTF_LOG_DEBUG,"new M1 bar: roc "+RocText()+" atr "+Pts(m_ctx.md.AtrM1())+CtxText()+" | "+
          (m_warm ? "ticks warm" : m_lastInfo));
     }

   //--- micro-ranges are drawn once at signal time (AnnounceSignal): nothing to refresh per panel cycle
   virtual void      Draw(void)
     {
     }

   //--- panel: "[M] Momentum ON | imb 0.58 vel 1.10x acc +5% | waiting: BUY vel 1.10x<1.25x"
   virtual string    StatusLine(void)
     {
      string head="["+StringSubstr(m_code,0,1)+"] "+m_name+" "+(m_enabled ? "ON " : "OFF");
      if(!m_enabled || CheckPointer(m_ctx)==POINTER_INVALID)
         return head+" | "+m_status;
      if(!m_warm)
         return head+" | "+m_lastInfo;
      MeasureFlow();
      return head+" | "+LiveText()+(StringLen(m_lastInfo)>0 ? " | "+m_lastInfo : "");
     }
  };

#endif // FTF_ENGINE_MOMENTUM_MQH
