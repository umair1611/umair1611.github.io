//+------------------------------------------------------------------+
//|                                                  EngineRange.mqh |
//|  CEngineRange - Engine C: Range / Mean Reversion (docs/03 s.3).  |
//|  Range detection on CLOSED bars of the Range timeframe (M1/M5),  |
//|  entries on every tick near the boundaries, mandatory impulse    |
//|  protection, exit on confirmed breakout. Never reads another     |
//|  engine.                                                         |
//|                                                                  |
//|  Price conventions: boundaries / touches / breakouts use BID     |
//|  (chart bars are bid based); BUY enters at ASK, SELL at BID.     |
//+------------------------------------------------------------------+
#ifndef FTF_ENGINE_RANGE_MQH
#define FTF_ENGINE_RANGE_MQH

#include <FranckyTriFlux\Core\EngineBase.mqh>

#define FTF_RNG_REBOX_FRAC   0.10   // TUNABLE (not an input yet) - bounds moving more than 10% of width = new range id
#define FTF_RNG_DRAW_KEEP    20     // TUNABLE (not an input yet) - range boxes kept on the chart
#define FTF_RNG_MEDIAN_MAX   200    // max ATR values used for the median (non-M1 timeframe)

//--- the current range box
struct SRangeBox
  {
   string            id;        // RNG-<yyyymmdd>-<lo>-<hi>
   int               state;     // ENUM_FTF_RANGE_STATE
   double            hi;
   double            lo;
   double            mid;
   double            width;
   datetime          tStart;    // open time of the oldest bar of the lookback at detection
   datetime          tDetect;   // bar time of the detection
   datetime          tEnd;      // time the box ended (broken / dissolved), 0 while active
   int               touchB;    // touches of the bottom edge zone (tick level)
   int               touchS;    // touches of the top edge zone
   bool              insideB;
   bool              insideS;
   double            atr;       // ATR at detection
   void              Reset(void)
     {
      id=""; state=FTF_RS_NONE; hi=0.0; lo=0.0; mid=0.0; width=0.0; tStart=0; tDetect=0; tEnd=0;
      touchB=0; touchS=0; insideB=false; insideS=false; atr=0.0;
     }
  };

class CEngineRange : public CEngineBase
  {
private:
   SRangeBox         m_box;
   ENUM_TIMEFRAMES   m_tf;
   int               m_adxId;
   int               m_emaFId;
   int               m_emaSId;
   int               m_atrId;
   double            m_atr;       // ATR(range tf) shift 1
   double            m_atrMed;    // median ATR(range tf)
   double            m_adx;
   double            m_adxPrev;
   double            m_emaF;
   double            m_emaS;
   datetime          m_lastBar1;
   string            m_noRangeWhy;
   bool              m_dirty;
   string            m_drawn[];   // ring of drawn box ids
   int               m_drawPos;
   long              m_infoMsc;

   //--- helpers -----------------------------------------------------
   bool              Valid(const double v) { return (v!=EMPTY_VALUE && MathIsValidNumber(v)); }
   string            Px(const double v)   { return FTF_D(v,m_ctx.md.DigitsCount()); }
   double            AtrPts(const double dist)
     {
      return (m_atr>0.0 ? dist/m_atr : 0.0);
     }
   string            Pct(const double v) { return DoubleToString(v,0)+"%"; }

   //--- indicator cache of the last closed bar
   bool              RefreshIndicators(void)
     {
      CPlatform *pf=m_ctx.pf;
      m_atr=pf.IndValue(m_atrId,0,1);
      m_adx=pf.IndValue(m_adxId,0,1);
      m_adxPrev=pf.IndValue(m_adxId,0,1+(int)MathMax(1,m_ctx.cfg.RngAdxSlopeBars));
      m_emaF=pf.IndValue(m_emaFId,0,1);
      m_emaS=pf.IndValue(m_emaSId,0,1);
      if(!Valid(m_atr) || m_atr<=0.0 || !Valid(m_adx) || !Valid(m_emaF) || !Valid(m_emaS))
         return false;
      if(!Valid(m_adxPrev))
         m_adxPrev=m_adx;
      //--- median ATR for the volatility-expansion protection
      if(m_tf==PERIOD_M1 && m_ctx.md.AtrM1Median()>0.0)
         m_atrMed=m_ctx.md.AtrM1Median();
      else
        {
         int n=(int)MathMin(m_ctx.cfg.AtrMedianBars,FTF_RNG_MEDIAN_MAX);
         double vals[];
         ArrayResize(vals,n);
         int k=0;
         for(int i=1;i<=n;i++)
           {
            double v=pf.IndValue(m_atrId,0,i);
            if(Valid(v) && v>0.0)
              {
               vals[k]=v;
               k++;
              }
           }
         m_atrMed=(k>0 ? FTF_Median(vals,k) : m_atr);
        }
      return true;
     }

   //--- docs/03 3.1 - the 5 detection conditions on closed bars; fills hi/lo/tStart
   bool              Detect(double &hi,double &lo,datetime &tStart,string &why)
     {
      CConfig *cf=m_ctx.cfg;
      CPlatform *pf=m_ctx.pf;
      int n=cf.RngLookbackBars;
      hi=0.0;
      lo=0.0;
      tStart=0;
      if(pf.BarsCount(m_tf)<n+5)
        {
         why="not enough bars";
         return false;
        }
      //--- 1. weak / falling ADX
      if(m_adx>=cf.RngAdxMax)
        {
         why="ADX "+FTF_D(m_adx,1)+">="+FTF_D(cf.RngAdxMax,1);
         return false;
        }
      if(cf.RngRequireAdxFalling && m_adx>m_adxPrev)
        {
         why="ADX rising "+FTF_D(m_adxPrev,1)+"->"+FTF_D(m_adx,1);
         return false;
        }
      //--- 2. small EMA separation
      double sep=MathAbs(m_emaF-m_emaS);
      if(sep>cf.RngEmaSepMaxAtr*m_atr)
        {
         why="EMA sep "+FTF_D(AtrPts(sep),2)+"xATR>"+FTF_D(cf.RngEmaSepMaxAtr,2);
         return false;
        }
      //--- 3. bounds + width
      hi=pf.BarHigh(m_tf,1);
      lo=pf.BarLow(m_tf,1);
      for(int i=2;i<=n;i++)
        {
         double h=pf.BarHigh(m_tf,i);
         double l=pf.BarLow(m_tf,i);
         if(h>hi)
            hi=h;
         if(l<lo || lo<=0.0)
            lo=l;
        }
      tStart=pf.BarTime(m_tf,n);
      double width=hi-lo;
      double spread=m_ctx.md.Spread();
      double minW=MathMax(cf.RngMinWidthAtr*m_atr,cf.RngMinWidthSpreadMult*spread);
      if(width<=0.0 || width<minW)
        {
         why="width "+FTF_D(AtrPts(width),2)+"xATR < min";
         return false;
        }
      if(cf.RngMaxWidthAtr>0.0 && width>cf.RngMaxWidthAtr*m_atr)
        {
         why="width "+FTF_D(AtrPts(width),2)+"xATR > "+FTF_D(cf.RngMaxWidthAtr,1);
         return false;
        }
      //--- 4. no significant directional swing
      double drift=MathAbs(pf.BarClose(m_tf,1)-pf.BarClose(m_tf,n));
      if(drift>cf.RngMaxDriftPct/100.0*width)
        {
         why="drift "+Pct(drift/width*100.0)+" of width > "+Pct(cf.RngMaxDriftPct);
         return false;
        }
      //--- 5. touches of both boundaries
      double edge=cf.RngEdgeZonePct/100.0*width;
      int tTop=0;
      int tBot=0;
      for(int i=1;i<=n;i++)
        {
         if(pf.BarHigh(m_tf,i)>=hi-edge)
            tTop++;
         if(pf.BarLow(m_tf,i)<=lo+edge)
            tBot++;
        }
      if(tTop<cf.RngMinTouchesPerSide || tBot<cf.RngMinTouchesPerSide)
        {
         why="touches top "+IntegerToString(tTop)+" bottom "+IntegerToString(tBot)+" < "+IntegerToString(cf.RngMinTouchesPerSide);
         return false;
        }
      why="ADX "+FTF_D(m_adx,1)+" sep "+FTF_D(AtrPts(sep),2)+"xATR width "+FTF_D(AtrPts(width),2)+"xATR drift "+
          Pct(drift/width*100.0)+" touches "+IntegerToString(tTop)+"/"+IntegerToString(tBot);
      return true;
     }

   string            MakeId(const double lo,const double hi,const datetime t)
     {
      MqlDateTime dt;
      TimeToStruct(t,dt);
      string day=IntegerToString(dt.year)+StringFormat("%02d%02d",dt.mon,dt.day);
      return "RNG-"+day+"-"+Px(lo)+"-"+Px(hi);
     }

   void              EndBox(const int newState,const datetime t,const string why)
     {
      if(m_box.state!=FTF_RS_ACTIVE)
         return;
      m_box.state=newState;
      m_box.tEnd=t;
      m_dirty=true;
      Log(FTF_LOG_INFO,"range "+m_box.id+(newState==FTF_RS_BROKEN ? " BROKEN: " : " dissolved: ")+why);
     }

   void              NewBox(const double lo,const double hi,const datetime tStart,const string why)
     {
      string prevId=m_box.id;
      m_box.Reset();
      m_box.lo=lo;
      m_box.hi=hi;
      m_box.width=hi-lo;
      m_box.mid=(hi+lo)*0.5;
      m_box.tStart=tStart;
      m_box.tDetect=m_ctx.pf.BarTime(m_tf,0);
      m_box.atr=m_atr;
      m_box.id=MakeId(lo,hi,m_box.tDetect);
      m_box.state=FTF_RS_ACTIVE;
      m_dirty=true;
      Log(FTF_LOG_INFO,"range ACTIVE "+m_box.id+" "+Px(lo)+"-"+Px(hi)+" | "+why+
          (StringLen(prevId)>0 ? " (previous "+prevId+")" : ""));
     }

   //--- last closed candle wick toward a boundary, % of its range
   double            WickPct(const int dir)
     {
      CPlatform *pf=m_ctx.pf;
      double o=pf.BarOpen(m_tf,1);
      double h=pf.BarHigh(m_tf,1);
      double l=pf.BarLow(m_tf,1);
      double c=pf.BarClose(m_tf,1);
      double rng=h-l;
      if(rng<=0.0)
         return 0.0;
      double wick=(dir==FTF_DIR_BUY ? MathMin(o,c)-l : h-MathMax(o,c));
      return wick/rng*100.0;
     }

   //--- docs/03 3.2 confirmation; text explains the result
   bool              Confirmed(const int dir,string &txt)
     {
      int mode=m_ctx.cfg.RngConfirmMode;
      double vr=m_ctx.md.VelRatio();
      bool slow=(vr<=1.0);
      double wp=WickPct(dir);
      double edge=m_ctx.cfg.RngEdgeZonePct/100.0*m_box.width;
      bool nearEdge=(dir==FTF_DIR_BUY ? m_ctx.pf.BarLow(m_tf,1)<=m_box.lo+edge : m_ctx.pf.BarHigh(m_tf,1)>=m_box.hi-edge);
      bool rej=(nearEdge && wp>=m_ctx.cfg.RngRejectWickPct);
      txt="vel "+FTF_D(vr,2)+"x"+(slow ? " slowdown" : "")+" wick "+Pct(wp)+(rej ? " rejection" : "");
      switch(mode)
        {
         case FTF_RCONF_NONE:      return true;
         case FTF_RCONF_SLOWDOWN:  return slow;
         case FTF_RCONF_REJECTION: return rej;
         case FTF_RCONF_BOTH:      return (slow && rej);
         default:                  break;
        }
      return (slow || rej);
     }

   //--- docs/03 3.2 returning ticks: BUY bullish ratio >= min, SELL bearish ratio >= min
   bool              TicksReturn(const int dir,double &ratioOut)
     {
      int up=0;
      int down=0;
      double r=m_ctx.ticks.UpRatio(m_ctx.cfg.RngTickWindow,false,up,down);
      ratioOut=r;
      if(r<0.0)
         return false;
      double side=(dir==FTF_DIR_BUY ? r : 1.0-r);
      return (side>=m_ctx.cfg.RngTickRatioMin);
     }

   //--- first setup id of this touch not traded yet ("" when the touch is exhausted)
   string            FreeSetupId(const int dir)
     {
      int touch=(dir==FTF_DIR_BUY ? m_box.touchB : m_box.touchS);
      string base=m_box.id+(dir==FTF_DIR_BUY ? "-B-T" : "-S-T")+IntegerToString(touch);
      int maxK=(int)MathMax(1,m_ctx.cfg.RngMaxTradesPerTouch);
      for(int k=1;k<=maxK;k++)
        {
         string sid=(k==1 ? base : base+"-"+IntegerToString(k));
         if(!WasTraded(sid))
            return sid;
        }
      return "";
     }

   //--- build one signal (docs/03 3.3)
   bool              Build(const int dir,const string setupId,const double ratio,const string confTxt,SSignal &s)
     {
      CConfig *cf=m_ctx.cfg;
      double spread=m_ctx.md.Spread();
      double buf=MathMax(cf.RngSlBufSpreadMult*spread,cf.RngSlBufAtr*m_atr);
      double offset=cf.RngTpOffsetPct/100.0*m_box.width;
      double edge=cf.RngEdgeZonePct/100.0*m_box.width;
      double bid=m_ctx.md.BidPrice();
      PrepareSignal(s,dir,setupId,FTF_TfStr(m_tf));
      if(dir==FTF_DIR_BUY)
        {
         s.sl=Norm(m_box.lo-buf);
         s.tp=Norm(cf.RngTpTarget==FTF_RTP_OPPOSITE ? m_box.hi-offset : m_box.mid-offset);
         s.invalidation=m_box.lo;
        }
      else
        {
         s.sl=Norm(m_box.hi+buf);
         s.tp=Norm(cf.RngTpTarget==FTF_RTP_OPPOSITE ? m_box.lo+offset : m_box.mid+offset);
         s.invalidation=m_box.hi;
        }
      if((dir==FTF_DIR_BUY && s.tp<=s.price) || (dir==FTF_DIR_SELL && s.tp>=s.price))
         return false;   // target already reached / too close
      //--- quality: depth in the edge zone (0..1) and strength of the returning ticks (0..1)
      double depth=(dir==FTF_DIR_BUY ? (m_box.lo+edge-bid)/MathMax(edge,1e-12) : (bid-(m_box.hi-edge))/MathMax(edge,1e-12));
      double side=(dir==FTF_DIR_BUY ? ratio : 1.0-ratio);
      double strength=(cf.RngTickRatioMin<1.0 ? (side-cf.RngTickRatioMin)/(1.0-cf.RngTickRatioMin) : 0.0);
      s.quality=50.0+30.0*FTF_Clamp(depth,0.0,1.0)+20.0*FTF_Clamp(strength,0.0,1.0);
      s.atr=m_atr;
      s.structOk=true;
      double posPct=(m_box.width>0.0 ? (bid-m_box.lo)/m_box.width*100.0 : 0.0);
      s.reason="range "+Px(m_box.lo)+"-"+Px(m_box.hi)+" w "+FTF_D(AtrPts(m_box.width),2)+"xATR | "+
               (dir==FTF_DIR_BUY ? "T"+IntegerToString(m_box.touchB)+" bottom" : "T"+IntegerToString(m_box.touchS)+" top")+
               " bid at "+Pct(posPct)+" of width | "+confTxt+" | ticks "+FTF_D(side,2)+" "+
               (dir==FTF_DIR_BUY ? "up" : "down")+" | ADX "+FTF_D(m_adx,1)+" | TP "+
               (cf.RngTpTarget==FTF_RTP_OPPOSITE ? "opposite" : "mid");
      return true;
     }

   //--- remember drawn boxes, delete beyond the budget
   void              RememberDrawn(const string id)
     {
      for(int i=0;i<FTF_RNG_DRAW_KEEP;i++)
         if(m_drawn[i]==id)
            return;
      if(StringLen(m_drawn[m_drawPos])>0)
        {
         m_ctx.ui.Remove("RNG_"+m_drawn[m_drawPos]);
         m_ctx.ui.Remove("RNGMID_"+m_drawn[m_drawPos]);
        }
      m_drawn[m_drawPos]=id;
      m_drawPos=(m_drawPos+1)%FTF_RNG_DRAW_KEEP;
     }

public:
                     CEngineRange(void)
     {
      m_id=FTF_ENG_RANGE;
      m_code="RNG";
      m_name="Range";
      m_box.Reset();
      m_tf=PERIOD_M1;
      m_adxId=-1;
      m_emaFId=-1;
      m_emaSId=-1;
      m_atrId=-1;
      m_atr=0.0;
      m_atrMed=0.0;
      m_adx=0.0;
      m_adxPrev=0.0;
      m_emaF=0.0;
      m_emaS=0.0;
      m_lastBar1=0;
      m_noRangeWhy="waiting for data";
      m_dirty=false;
      m_drawPos=0;
      m_infoMsc=0;
      ArrayResize(m_drawn,FTF_RNG_DRAW_KEEP);
      for(int i=0;i<FTF_RNG_DRAW_KEEP;i++)
         m_drawn[i]="";
     }

   virtual bool      Init(CFtfContext *ctx)
     {
      if(!CEngineBase::Init(ctx))
         return false;
      CConfig *cf=m_ctx.cfg;
      m_tf=cf.RngTimeframe;
      m_adxId=m_ctx.pf.RegisterADX(m_tf,cf.RngAdxPeriod);
      m_emaFId=m_ctx.pf.RegisterEMA(m_tf,cf.RngEmaFast);
      m_emaSId=m_ctx.pf.RegisterEMA(m_tf,cf.RngEmaSlow);
      m_atrId=m_ctx.pf.RegisterATR(m_tf,cf.AtrPeriod);
      Log(FTF_LOG_INFO,"rules: tf "+FTF_TfStr(m_tf)+" lookback "+IntegerToString(cf.RngLookbackBars)+" | ADX<"+
          FTF_D(cf.RngAdxMax,1)+(cf.RngRequireAdxFalling ? " falling" : "")+" | EMA"+IntegerToString(cf.RngEmaFast)+"/"+
          IntegerToString(cf.RngEmaSlow)+" sep<="+FTF_D(cf.RngEmaSepMaxAtr,2)+"xATR | width "+FTF_D(cf.RngMinWidthAtr,2)+"-"+
          FTF_D(cf.RngMaxWidthAtr,2)+"xATR | drift<="+Pct(cf.RngMaxDriftPct)+" | edge "+Pct(cf.RngEdgeZonePct)+
          " | confirm "+EnumToString(cf.RngConfirmMode)+" | ticks>="+FTF_D(cf.RngTickRatioMin,2)+" over "+
          IntegerToString(cf.RngTickWindow)+" | impulse vel<="+FTF_D(cf.RngMaxVelRatio,2)+"x ATR/med<="+
          FTF_D(cf.RngMaxAtrExpansion,2)+" | TP "+(cf.RngTpTarget==FTF_RTP_OPPOSITE ? "opposite" : "mid")+
          " | exit on breakout "+(cf.RngExitOnBreakout ? "ON" : "OFF"));
      if(m_adxId<0 || m_emaFId<0 || m_emaSId<0 || m_atrId<0)
         Log(FTF_LOG_ERROR,"indicator registration failed - engine waits for data");
      return true;
     }

   //--- detection on each new bar of the range timeframe
   virtual void      OnNewBar(const ENUM_TIMEFRAMES tf)
     {
      if(tf!=m_tf || CheckPointer(m_ctx)==POINTER_INVALID)
         return;
      datetime bar1=m_ctx.pf.BarTime(m_tf,1);
      if(bar1<=0 || bar1==m_lastBar1)
         return;
      m_lastBar1=bar1;
      if(!RefreshIndicators())
        {
         m_noRangeWhy="indicators not ready";
         return;
        }
      CConfig *cf=m_ctx.cfg;
      //--- (a) confirmed breakout on the close of the last bar
      if(m_box.state==FTF_RS_ACTIVE)
        {
         double breakBuf=cf.RngBreakBufAtr*m_atr;
         double c1=m_ctx.pf.BarClose(m_tf,1);
         if(c1>m_box.hi+breakBuf || c1<m_box.lo-breakBuf)
            EndBox(FTF_RS_BROKEN,bar1,"close "+Px(c1)+(c1>m_box.hi ? " above " : " below ")+"boundary + "+
                   FTF_D(cf.RngBreakBufAtr,2)+"xATR");
        }
      //--- (b) detection
      double hi=0.0;
      double lo=0.0;
      datetime tStart=0;
      string why="";
      bool ok=Detect(hi,lo,tStart,why);
      Log(FTF_LOG_DEBUG,"detect "+(ok ? "OK " : "NO ")+why+" | ATR "+Px(m_atr)+" med "+Px(m_atrMed));
      if(ok)
        {
         m_noRangeWhy="";
         bool same=(m_box.state==FTF_RS_ACTIVE && m_box.width>0.0 &&
                    MathAbs(hi-m_box.hi)<=FTF_RNG_REBOX_FRAC*m_box.width &&
                    MathAbs(lo-m_box.lo)<=FTF_RNG_REBOX_FRAC*m_box.width);
         if(!same)
           {
            if(m_box.state==FTF_RS_ACTIVE)
               EndBox(FTF_RS_NONE,bar1,"bounds moved to "+Px(lo)+"-"+Px(hi));
            NewBox(lo,hi,tStart,why);
           }
        }
      else
        {
         m_noRangeWhy=why;
         if(m_box.state==FTF_RS_ACTIVE)
            EndBox(FTF_RS_NONE,bar1,why);
        }
      m_dirty=true;
     }

   //--- entries on every tick (docs/03 3.2)
   virtual int       Evaluate(SSignal &out[],const int startIndex,const int maxOut)
     {
      if(!m_enabled || maxOut<=0 || CheckPointer(m_ctx)==POINTER_INVALID)
         return 0;
      if(m_box.state!=FTF_RS_ACTIVE)
        {
         m_status=(m_box.state==FTF_RS_BROKEN ? "range broken - waiting new range" : "no range: "+m_noRangeWhy);
         return 0;
        }
      if(m_atr<=0.0)
         return 0;
      CConfig *cf=m_ctx.cfg;
      double bid=m_ctx.md.BidPrice();
      if(bid<=0.0)
         return 0;
      double vr=m_ctx.md.VelRatio();
      double breakBuf=cf.RngBreakBufAtr*m_atr;
      double edge=cf.RngEdgeZonePct/100.0*m_box.width;
      //--- fast invalidation: beyond a boundary + buffer with an impulse
      if((bid>m_box.hi+breakBuf || bid<m_box.lo-breakBuf) && vr>cf.RngMaxVelRatio)
        {
         EndBox(FTF_RS_BROKEN,m_ctx.md.ServerTime(),"tick breakout bid "+Px(bid)+" vel "+FTF_D(vr,2)+"x");
         m_status="range broken (tick impulse)";
         return 0;
        }
      //--- touch counting
      bool inB=(bid<=m_box.lo+edge && bid>=m_box.lo-breakBuf);
      bool inS=(bid>=m_box.hi-edge && bid<=m_box.hi+breakBuf);
      if(inB && !m_box.insideB)
         m_box.touchB++;
      if(inS && !m_box.insideS)
         m_box.touchS++;
      m_box.insideB=inB;
      m_box.insideS=inS;
      double posPct=(m_box.width>0.0 ? (bid-m_box.lo)/m_box.width*100.0 : 0.0);
      m_status="ACTIVE "+Px(m_box.lo)+"-"+Px(m_box.hi)+" w "+FTF_D(AtrPts(m_box.width),1)+"xATR pos "+Pct(posPct)+
               " T B"+IntegerToString(m_box.touchB)+"/S"+IntegerToString(m_box.touchS);
      if(!inB && !inS)
         return 0;
      int dir=(inB ? FTF_DIR_BUY : FTF_DIR_SELL);
      //--- mandatory impulse protection
      double atrRatio=(m_atrMed>0.0 ? m_atr/m_atrMed : 1.0);
      if((cf.RngMaxVelRatio>0.0 && vr>cf.RngMaxVelRatio) || (cf.RngMaxAtrExpansion>0.0 && atrRatio>cf.RngMaxAtrExpansion))
        {
         SetInfo("impulse protection vel "+FTF_D(vr,2)+"x ATR/med "+FTF_D(atrRatio,2));
         LogThrottled(FTF_LOG_DEBUG,"impulse","impulse protection "+FTF_DirStr(dir)+": vel "+FTF_D(vr,2)+"x (max "+
                      FTF_D(cf.RngMaxVelRatio,2)+") ATR/med "+FTF_D(atrRatio,2)+" (max "+FTF_D(cf.RngMaxAtrExpansion,2)+")");
         return 0;
        }
      string sid=FreeSetupId(dir);
      if(StringLen(sid)==0)
        {
         SetInfo("touch already traded");
         return 0;
        }
      string confTxt="";
      if(!Confirmed(dir,confTxt))
        {
         SetInfo("waiting confirmation: "+confTxt);
         LogThrottled(FTF_LOG_DEBUG,"conf"+IntegerToString(dir),FTF_DirStr(dir)+" edge reached, no confirmation: "+confTxt);
         return 0;
        }
      double ratio=0.0;
      if(!TicksReturn(dir,ratio))
        {
         SetInfo("waiting "+(dir==FTF_DIR_BUY ? "buyers" : "sellers")+" ticks "+FTF_D(ratio,2));
         LogThrottled(FTF_LOG_DEBUG,"ticks"+IntegerToString(dir),FTF_DirStr(dir)+" edge+confirm OK, ticks ratio "+
                      FTF_D(ratio,2)+" < "+FTF_D(cf.RngTickRatioMin,2));
         return 0;
        }
      if(!Build(dir,sid,ratio,confTxt,out[startIndex]))
        {
         SetInfo("target too close");
         return 0;
        }
      LogThrottled(FTF_LOG_INFO,"sig."+sid,"SIGNAL "+FTF_DirStr(dir)+" "+sid+" @ "+Px(out[startIndex].price)+" SL "+
                   Px(out[startIndex].sl)+" TP "+Px(out[startIndex].tp)+" q "+FTF_D(out[startIndex].quality,0)+" | "+
                   out[startIndex].reason);
      SetInfo("signal "+FTF_DirStr(dir)+" "+sid);
      return 1;
     }

   virtual bool      IsStillValid(const SSignal &sig,string &why)
     {
      why="";
      if(m_ctx.md.NowMsc()>sig.expiryMsc)
        {
         why="expired";
         return false;
        }
      if(m_box.state!=FTF_RS_ACTIVE || StringFind(sig.setupId,m_box.id)!=0)
        {
         why="range no longer active";
         return false;
        }
      double bid=m_ctx.md.BidPrice();
      double edge=m_ctx.cfg.RngEdgeZonePct/100.0*m_box.width;
      double breakBuf=m_ctx.cfg.RngBreakBufAtr*m_atr;
      bool inZone=(sig.dir==FTF_DIR_BUY ? (bid<=m_box.lo+edge && bid>=m_box.lo-breakBuf) :
                   (bid>=m_box.hi-edge && bid<=m_box.hi+breakBuf));
      if(!inZone)
        {
         why="price left the edge zone";
         return false;
        }
      double ratio=0.0;
      if(!TicksReturn(sig.dir,ratio))
        {
         why="returning ticks lost ("+FTF_D(ratio,2)+")";
         return false;
        }
      return true;
     }

   //--- RANGE_BREAKOUT exit (docs/03 3.4)
   virtual int       CheckExit(STrackedPos &pos,string &detail)
     {
      detail="";
      if(pos.engine!=FTF_ENG_RANGE || !m_ctx.cfg.RngExitOnBreakout)
         return FTF_EXIT_NONE;
      if(m_box.state==FTF_RS_BROKEN && StringLen(m_box.id)>0 && StringFind(pos.setupId,m_box.id)==0)
        {
         detail="range "+m_box.id+" broken";
         return FTF_EXIT_RANGE_BREAK;
        }
      if(pos.refLevel>0.0 && m_atr>0.0)
        {
         double bid=m_ctx.md.BidPrice();
         double vr=m_ctx.md.VelRatio();
         double breakBuf=m_ctx.cfg.RngBreakBufAtr*m_atr;
         bool beyond=(pos.dir==FTF_DIR_BUY ? bid<pos.refLevel-breakBuf : bid>pos.refLevel+breakBuf);
         if(beyond && vr>m_ctx.cfg.RngMaxVelRatio)
           {
            detail="bid "+Px(bid)+" beyond boundary "+Px(pos.refLevel)+" with vel "+FTF_D(vr,2)+"x";
            return FTF_EXIT_RANGE_BREAK;
           }
        }
      return FTF_EXIT_NONE;
     }

   virtual void      Draw(void)
     {
      if(CheckPointer(m_ctx.ui)==POINTER_INVALID || !m_ctx.ui.Enabled() || !m_ctx.cfg.DrawZones)
         return;
      if(StringLen(m_box.id)==0)
         return;
      datetime now=m_ctx.md.ServerTime();
      if(!m_dirty && m_box.state!=FTF_RS_ACTIVE)
         return;
      datetime tTo=(m_box.tEnd>0 ? m_box.tEnd : now);
      color clr=(m_box.state==FTF_RS_ACTIVE ? clrMediumOrchid : clrDimGray);
      string tip="Range "+m_box.id+" "+Px(m_box.lo)+"-"+Px(m_box.hi)+" "+
                 (m_box.state==FTF_RS_ACTIVE ? "ACTIVE" : (m_box.state==FTF_RS_BROKEN ? "BROKEN" : "ENDED"));
      RememberDrawn(m_box.id);
      m_ctx.ui.DrawRect("RNG_"+m_box.id,m_box.tStart,m_box.hi,tTo,m_box.lo,clr,false,tip);
      m_ctx.ui.DrawSegment("RNGMID_"+m_box.id,m_box.tStart,m_box.mid,tTo,m_box.mid,clr,STYLE_DOT,tip+" mid");
      m_dirty=false;
     }

   virtual string    StatusLine(void)
     {
      return "[R] Range "+(m_enabled ? "ON " : "OFF")+" | "+m_status+(StringLen(m_lastInfo)>0 ? " | "+m_lastInfo : "");
     }

   //--- accessors (panel / tests)
   int               BoxState(void) { return m_box.state; }
   string            BoxId(void)    { return m_box.id; }
  };

#endif // FTF_ENGINE_RANGE_MQH
