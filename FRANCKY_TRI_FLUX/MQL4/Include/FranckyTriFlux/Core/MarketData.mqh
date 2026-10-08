//+------------------------------------------------------------------+
//|                                                   MarketData.mqh |
//|  CMarketData - market data layer of FRANCKY TRI-FLUX:            |
//|   * ingests every new tick into CTickBuffer (HFT-style, G.2)     |
//|   * bid/ask snapshot, spread incl. stress extra spread           |
//|   * new-bar flags for M1, M5, H1, FVG tf and Range tf            |
//|   * bar indicators cached on closed bars (shift 1) and refreshed |
//|     only on a new M1 bar (docs/03 section 0: speed + backtest    |
//|     reproducibility): ATR M1/M5, median ATR, EMA M1/M5, ADX M1,  |
//|     ROC M1                                                       |
//|   * tick velocity statistics and median spread                   |
//|  docs/09 section 7.8 - docs/03 sections 0, 1.1, 5                |
//|  Shared Core: identical in the MQL5 and MQL4 trees.              |
//+------------------------------------------------------------------+
#ifndef FTF_MARKET_DATA_MQH
#define FTF_MARKET_DATA_MQH

#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Config.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>
#include <FranckyTriFlux\Platform\Platform.mqh>
#include <FranckyTriFlux\Core\TickBuffer.mqh>

#define FTF_M5_EMA_FAST          20         // spec Table 18: M5 trend EMA20 / EMA50
#define FTF_M5_EMA_SLOW          50         // spec Table 18: M5 trend EMA20 / EMA50
#define FTF_M1_ADX_PERIOD        14         // spec Table 18: ADX(14) + DI (M1 Momentum confirmation)
#define FTF_MD_FETCH_MAX         4096       // TUNABLE (not an input yet) - max new ticks ingested per cycle
#define FTF_MD_SPEC_REFRESH_MS   60000      // TUNABLE (not an input yet) - symbol spec refresh period (server ms)
#define FTF_MD_SPREAD_EVERY      20         // TUNABLE (not an input yet) - median spread recomputed every N new ticks
#define FTF_MD_SPREAD_TICKS      200        // TUNABLE (not an input yet) - ticks used for the median spread
#define FTF_MD_CACHE_RETRY_MS    1000       // TUNABLE (not an input yet) - indicator cache retry period while not ready
#define FTF_MD_MIN_M5_BARS       60         // warm-up: M5 bars required (EMA50 + margin)
#define FTF_MD_MIN_H1_BARS       60         // warm-up: H1 bars required (H1 EMA50 + margin)
#define FTF_MD_MAX_TF            5          // watched timeframes: M1, M5, H1, FVG tf, Range tf
#define FTF_MD_NO_TICK_AGE       999999999  // TickAgeMs() before the first tick (always stale)

class CMarketData
  {
public:
   SSymbolSpec       spec;             // chart symbol spec - public, refreshed in Init and every 60 s (docs/09 7.8)

private:
   CConfig          *m_cfg;
   CLogger          *m_log;
   CPlatform        *m_pf;
   CTickBuffer      *m_ticks;
   bool              m_ready;          // Init succeeded
   //--- tick stream / snapshot
   STick             m_buf[];          // scratch array for PreloadTicks / FetchNewTicks
   STick             m_last;           // newest quote (snapshot used by every engine)
   bool              m_hasTick;        // at least one valid quote received
   long              m_nowMsc;         // server ms of the current cycle (never goes backwards)
   long              m_lastTickMsc;    // server ms of the newest received tick
   datetime          m_srvTime;        // pf.ServerTime() cached at the last Update
   int               m_ticksThisCycle; // ticks accepted by the last Update
   long              m_ticksTotal;     // ticks accepted since Init (incl. preload)
   long              m_specMsc;        // server ms of the last spec refresh
   //--- new-bar tracking (parallel arrays, docs/10)
   ENUM_TIMEFRAMES   m_tfs[FTF_MD_MAX_TF];
   datetime          m_tfLast[FTF_MD_MAX_TF];
   bool              m_tfNew[FTF_MD_MAX_TF];
   int               m_tfCount;
   //--- platform indicator ids
   int               m_idAtrM1;
   int               m_idAtrM5;
   int               m_idEmaM1F;
   int               m_idEmaM1S;
   int               m_idEmaM5F;
   int               m_idEmaM5S;
   int               m_idAdxM1;
   //--- indicator cache (closed bar = shift 1). A value that is not available keeps its previous
   //--- valid value (0.0 before the first one) and the refresh is retried every FTF_MD_CACHE_RETRY_MS
   bool              m_cacheDone;      // at least one refresh attempted
   bool              m_cacheOk;        // every cached value valid
   bool              m_cacheStale;     // the last refresh missed at least one value (retry pending)
   bool              m_adxOk;          // ADX/DI valid (0 is a legal DI value)
   long              m_cacheTryMsc;    // last refresh attempt
   double            m_atrM1;
   double            m_atrM1Med;
   double            m_atrM5;
   double            m_emaM1F;
   double            m_emaM1S;
   double            m_emaM5F;
   double            m_emaM5S;
   double            m_adxM1;
   double            m_pdiM1;
   double            m_mdiM1;
   double            m_rocM1;
   double            m_atrHist[];      // scratch for the ATR median
   //--- tick statistics (refreshed on every Update with new ticks)
   bool              m_velOk;
   double            m_velCur;
   double            m_velPrev;
   double            m_velMed;
   double            m_velRatio;
   double            m_velAccel;
   double            m_medSpreadRaw;   // median raw spread (price) of the last FTF_MD_SPREAD_TICKS ticks
   bool              m_spreadDone;     // median spread computed at least once
   int               m_spreadTicks;    // new ticks since the last median spread

   //+---------------------------------------------------------------+
   //| small helpers                                                 |
   //+---------------------------------------------------------------+
   bool              IsNum(const double v)  { return (v!=EMPTY_VALUE && MathIsValidNumber(v)); }
   bool              IsPos(const double v)  { return (IsNum(v) && v>0.0); }
   double            Clean(const double v)  { return (IsNum(v) ? v : 0.0); }
   //--- fresh value when valid (> 0), else the previous one and miss=true
   double            TakePos(const double fresh,const double prev,bool &miss)
     {
      if(IsPos(fresh))
         return fresh;
      miss=true;
      return prev;
     }
   int               Dg(void)               { return (spec.digits>0 ? spec.digits : 5); }
   double            Pt(void)               { return (spec.point>0.0 ? spec.point : 0.0); }
   void              AddWhy(string &why,const string s)
     {
      if(StringLen(why)>0)
         why+=", ";
      why+=s;
     }

   //--- index of a watched timeframe, -1 if not watched
   int               TfIndex(const ENUM_TIMEFRAMES tf)
     {
      for(int i=0;i<m_tfCount;i++)
         if(m_tfs[i]==tf)
            return i;
      return -1;
     }

   //--- watched timeframes are deduplicated (FVG tf / Range tf may equal M1 or M5)
   void              AddTf(const ENUM_TIMEFRAMES tf)
     {
      if(TfIndex(tf)>=0 || m_tfCount>=FTF_MD_MAX_TF)
         return;
      m_tfs[m_tfCount]=tf;
      m_tfLast[m_tfCount]=m_pf.BarTime(tf,0);   // the bar open at Init is not a "new" bar
      m_tfNew[m_tfCount]=false;
      m_tfCount++;
     }

   //+---------------------------------------------------------------+
   //| symbol specification (refreshed every 60 s)                   |
   //+---------------------------------------------------------------+
   void              LogSpecChanges(const SSymbolSpec &fresh)
     {
      if(fresh.stopsLevelPts!=spec.stopsLevelPts || fresh.freezeLevelPts!=spec.freezeLevelPts)
         m_log.Info("MD","broker levels changed: stops "+IntegerToString(spec.stopsLevelPts)+" -> "+
                    IntegerToString(fresh.stopsLevelPts)+" pts, freeze "+IntegerToString(spec.freezeLevelPts)+
                    " -> "+IntegerToString(fresh.freezeLevelPts)+" pts");
      if(fresh.tradeAllowed!=spec.tradeAllowed || fresh.canBuy!=spec.canBuy || fresh.canSell!=spec.canSell)
         m_log.Info("MD","symbol trade permissions changed: trade "+(fresh.tradeAllowed ? "ALLOWED" : "DISABLED")+
                    ", buy "+(fresh.canBuy ? "yes" : "no")+", sell "+(fresh.canSell ? "yes" : "no"));
      if(fresh.lotMin!=spec.lotMin || fresh.lotMax!=spec.lotMax || fresh.lotStep!=spec.lotStep)
         m_log.Info("MD","lot limits changed: min "+FTF_D(fresh.lotMin,3)+", max "+FTF_D(fresh.lotMax,2)+
                    ", step "+FTF_D(fresh.lotStep,3));
     }

   void              LogSpec(const SSymbolSpec &s)
     {
      m_log.Info("MD","symbol "+s.name+" | digits "+IntegerToString(s.digits)+" | point "+DoubleToString(s.point,8)+
                 " | tick size "+DoubleToString(s.tickSize,8)+" | tick value "+FTF_D(s.tickValue,5)+
                 " | contract "+FTF_D(s.contractSize,2)+" | lots "+FTF_D(s.lotMin,3)+".."+FTF_D(s.lotMax,2)+
                 " step "+FTF_D(s.lotStep,3)+" | stops "+IntegerToString(s.stopsLevelPts)+" / freeze "+
                 IntegerToString(s.freezeLevelPts)+" pts | "+s.baseCcy+"/"+s.profitCcy+" margin "+s.marginCcy+
                 " | trade "+(s.tradeAllowed ? "ALLOWED" : "DISABLED")+" | "+(s.hedging ? "hedging" : "netting"));
     }

   //+---------------------------------------------------------------+
   //| tick ingestion                                                |
   //+---------------------------------------------------------------+
   //--- pushes m_buf[0..n-1] (chronological) into the tick buffer; ticks without bid/ask are skipped.
   //--- A backward time stamp is clamped by CTickBuffer.Add (docs/09 7.7), so it is not skipped here.
   int               IngestTicks(const int n)
     {
      int cnt=n;
      if(cnt>ArraySize(m_buf))
         cnt=ArraySize(m_buf);
      int added=0;
      int skipped=0;
      int lastIdx=-1;
      for(int i=0;i<cnt;i++)
        {
         if(m_buf[i].bid<=0.0 || m_buf[i].ask<=0.0)
           {
            skipped++;
            continue;
           }
         m_ticks.Add(m_buf[i]);
         if(m_buf[i].msc>m_lastTickMsc)
            m_lastTickMsc=m_buf[i].msc;
         m_hasTick=true;
         lastIdx=i;
         added++;
        }
      if(lastIdx>=0)
        {
         m_last=m_buf[lastIdx];
         m_last.dir=m_ticks.DirAt(0);     // direction computed by the buffer vs the previous bid
        }
      m_ticksTotal+=added;
      if(skipped>0)
         m_log.Throttled(FTF_LOG_DEBUG,"md.skip",m_cfg.LogThrottleMs,"MD",
                         IntegerToString(skipped)+" tick(s) without bid/ask skipped");
      return added;
     }

   //--- no new tick this cycle (timer cycle): refresh the quote from the platform only
   void              SnapshotFromCurrent(void)
     {
      STick t;
      t.Reset();
      if(!m_pf.CurrentTick(t) || t.bid<=0.0 || t.ask<=0.0)
         return;
      if(m_hasTick && t.msc<m_lastTickMsc)
         return;
      t.dir=m_last.dir;
      m_last=t;
      if(t.msc>m_lastTickMsc)
         m_lastTickMsc=t.msc;
      m_hasTick=true;
     }

   //--- MT5: history warm-up so the tick engines can trade from the first live tick. MT4 returns 0.
   void              PreloadHistory(void)
     {
      int n=m_pf.PreloadTicks(m_buf,m_cfg.TickHistorySec);
      int added=(n>0 ? IngestTicks(n) : 0);
      if(added>0)
        {
         if(m_last.msc>m_nowMsc)
            m_nowMsc=m_last.msc;
         m_log.Info("MD","tick history pre-loaded: "+IntegerToString(added)+" ticks ("+
                    FTF_TimeMscStr(m_ticks.MscAt(m_ticks.Count()-1))+" .. "+FTF_TimeMscStr(m_last.msc)+")");
        }
      else
         m_log.Info("MD","no tick history pre-load ("+m_pf.Name()+") - tick engines warm up on live ticks ("+
                    IntegerToString(m_cfg.TickHistorySec)+" s history kept)");
     }

   //--- keeps TickHistorySec, never less than the velocity reference + 3 windows (Momentum needs ref + 2 windows)
   void              TrimTicks(void)
     {
      long keepMs=(long)m_cfg.TickHistorySec*1000;
      long needMs=(long)m_cfg.MomVelRefMs+3*(long)m_cfg.MomVelWindowMs;
      if(keepMs<needMs)
         keepMs=needMs;
      m_ticks.TrimOlderThan(m_nowMsc-keepMs);
     }

   //--- velocity (docs/03 1.1) on every Update with new ticks; median spread every FTF_MD_SPREAD_EVERY ticks
   void              UpdateTickStats(const int added)
     {
      double cur=0.0,prev=0.0,med=0.0,ratio=0.0,accel=0.0;
      //--- false = reference history not complete yet; the values are still computed (VelOk() tells)
      m_velOk=m_ticks.Velocity(m_nowMsc,m_cfg.MomVelWindowMs,m_cfg.MomVelRefMs,(int)m_cfg.MomVelMetric,
                               cur,prev,med,ratio,accel);
      //--- PRICE_PATH is returned in price units: docs/03 1.1 expresses it in points (ratio/accel unitless)
      double scale=1.0;
      double pt=Pt();
      if(m_cfg.MomVelMetric==FTF_VEL_PRICE_PATH && pt>0.0)
         scale=1.0/pt;
      m_velCur=Clean(cur)*scale;
      m_velPrev=Clean(prev)*scale;
      m_velMed=Clean(med)*scale;
      m_velRatio=Clean(ratio);
      m_velAccel=Clean(accel);
      m_spreadTicks+=added;
      if(m_spreadTicks>=FTF_MD_SPREAD_EVERY || !m_spreadDone)
        {
         double ms=m_ticks.MedianSpread(FTF_MD_SPREAD_TICKS);
         if(IsNum(ms) && ms>=0.0)
           {
            m_medSpreadRaw=ms;
            m_spreadDone=true;
           }
         m_spreadTicks=0;
        }
     }

   //+---------------------------------------------------------------+
   //| new bars                                                      |
   //+---------------------------------------------------------------+
   void              DetectNewBars(void)
     {
      for(int i=0;i<m_tfCount;i++)
        {
         datetime t=m_pf.BarTime(m_tfs[i],0);
         if(t<=0 || t==m_tfLast[i])
            continue;
         m_tfNew[i]=true;
         if(m_log.IsEnabled(FTF_LOG_TRACE))
            m_log.Trace("MD","new "+FTF_TfStr(m_tfs[i])+" bar "+FTF_TimeStr(t)+" (previous "+FTF_TimeStr(m_tfLast[i])+")");
         m_tfLast[i]=t;
        }
     }

   bool              NewBarAt(const ENUM_TIMEFRAMES tf)
     {
      int i=TfIndex(tf);
      return (i>=0 ? m_tfNew[i] : false);
     }

   //+---------------------------------------------------------------+
   //| indicator cache (closed bars only, docs/03 notation)          |
   //+---------------------------------------------------------------+
   //--- ROC = (close[1] - close[1+period]) / close[1+period] x 100 (docs/03 1.1); previous value kept if bars missing
   double            ComputeRoc(bool &miss)
     {
      int p=(m_cfg.MomRocPeriod>0 ? m_cfg.MomRocPeriod : 1);
      double c1=m_pf.BarClose(PERIOD_M1,1);
      double c0=m_pf.BarClose(PERIOD_M1,1+p);
      if(!IsPos(c1) || !IsPos(c0))
        {
         miss=true;
         return m_rocM1;
        }
      return (c1-c0)/c0*100.0;
     }

   //--- median of the last AtrMedianBars closed M1 ATR values (spec Table 18). 0 if < half available
   double            ComputeAtrMedian(void)
     {
      int n=(m_cfg.AtrMedianBars>0 ? m_cfg.AtrMedianBars : 1);
      if(ArraySize(m_atrHist)<n)
         ArrayResize(m_atrHist,n);
      int k=0;
      for(int i=1;i<=n;i++)
        {
         double v=m_pf.IndValue(m_idAtrM1,0,i);
         if(!IsPos(v) || k>=ArraySize(m_atrHist))
            continue;
         m_atrHist[k]=v;
         k++;
        }
      if(k<(n+1)/2)
         return 0.0;
      return FTF_Median(m_atrHist,k);
     }

   //--- reads every cached indicator of the closed bar (live MT5 may lag one tick on a new bar:
   //--- the previous valid value is kept and miss=true schedules a retry)
   void              ReadIndicators(bool &miss)
     {
      m_atrM1=TakePos(m_pf.IndValue(m_idAtrM1,0,1),m_atrM1,miss);
      m_atrM5=TakePos(m_pf.IndValue(m_idAtrM5,0,1),m_atrM5,miss);
      m_emaM1F=TakePos(m_pf.IndValue(m_idEmaM1F,0,1),m_emaM1F,miss);
      m_emaM1S=TakePos(m_pf.IndValue(m_idEmaM1S,0,1),m_emaM1S,miss);
      m_emaM5F=TakePos(m_pf.IndValue(m_idEmaM5F,0,1),m_emaM5F,miss);
      m_emaM5S=TakePos(m_pf.IndValue(m_idEmaM5S,0,1),m_emaM5S,miss);
      double adx=m_pf.IndValue(m_idAdxM1,0,1);
      double pdi=m_pf.IndValue(m_idAdxM1,1,1);
      double mdi=m_pf.IndValue(m_idAdxM1,2,1);
      if(IsNum(adx) && IsNum(pdi) && IsNum(mdi) && adx>=0.0 && pdi>=0.0 && mdi>=0.0)
        {
         m_adxM1=adx;
         m_pdiM1=pdi;
         m_mdiM1=mdi;
         m_adxOk=true;
        }
      else
         miss=true;
     }

   //--- one-line summary of the market state, logged on every new M1 bar (DEBUG)
   string            BarSummary(void)
     {
      int d=Dg();
      double pt=Pt();
      double atrX=(m_atrM1Med>0.0 ? m_atrM1/m_atrM1Med : 0.0);
      double sprPts=(pt>0.0 ? (MathMax(m_last.ask-m_last.bid,0.0)+(double)m_cfg.StressExtraSpreadPts*pt)/pt : 0.0);
      double medPts=(pt>0.0 ? (m_medSpreadRaw+(double)m_cfg.StressExtraSpreadPts*pt)/pt : 0.0);
      int i=TfIndex(PERIOD_M1);
      datetime bar=0;
      if(i>=0)
         bar=m_tfLast[i];
      return "M1 bar "+FTF_TimeStr(bar)+" | ATR "+FTF_D(m_atrM1,d+1)+" med "+FTF_D(m_atrM1Med,d+1)+
             " (x"+FTF_D(atrX,2)+") | ATR M5 "+FTF_D(m_atrM5,d+1)+
             " | ROC("+IntegerToString(m_cfg.MomRocPeriod)+") "+FTF_D(m_rocM1,4)+"%"+
             " | EMA"+IntegerToString(m_cfg.MomEmaFast)+"/"+IntegerToString(m_cfg.MomEmaSlow)+" "+
             FTF_D(m_emaM1F,d)+"/"+FTF_D(m_emaM1S,d)+(m_emaM1F>m_emaM1S ? " UP" : " DOWN")+
             " | M5 EMA"+IntegerToString(FTF_M5_EMA_FAST)+"/"+IntegerToString(FTF_M5_EMA_SLOW)+" "+
             FTF_D(m_emaM5F,d)+"/"+FTF_D(m_emaM5S,d)+(m_emaM5F>m_emaM5S ? " UP" : " DOWN")+
             " | ADX "+FTF_D(m_adxM1,1)+" +DI "+FTF_D(m_pdiM1,1)+" -DI "+FTF_D(m_mdiM1,1)+
             " | vel "+FTF_D(m_velCur,1)+" ratio "+FTF_D(m_velRatio,2)+" accel "+FTF_D(m_velAccel,2)+
             (m_velOk ? "" : " (vel history incomplete)")+
             " | spread "+FTF_D(sprPts,1)+" pts (median "+FTF_D(medPts,1)+")"+
             " | ticks "+IntegerToString(m_ticks.Count());
     }

   //--- refresh on the first Update, on every new M1 bar, and every second while a value is missing
   void              RefreshCache(void)
     {
      bool wasOk=m_cacheOk;
      bool miss=false;
      m_cacheTryMsc=m_nowMsc;
      ReadIndicators(miss);
      m_rocM1=ComputeRoc(miss);
      m_atrM1Med=TakePos(ComputeAtrMedian(),m_atrM1Med,miss);
      m_cacheStale=miss;
      m_cacheOk=(m_atrM1>0.0 && m_atrM5>0.0 && m_atrM1Med>0.0 && m_emaM1F>0.0 && m_emaM1S>0.0 &&
                 m_emaM5F>0.0 && m_emaM5S>0.0 && m_adxOk);
      m_cacheDone=true;
      if(m_cacheOk && !wasOk)
         m_log.Info("MD","indicator cache ready: "+BarSummary());
      else if(NewBarAt(PERIOD_M1) && m_log.IsEnabled(FTF_LOG_DEBUG))
         m_log.Debug("MD",BarSummary()+(miss ? " | some values not ready - previous kept, retrying" : ""));
      else if(miss && m_log.IsEnabled(FTF_LOG_DEBUG))
         m_log.Throttled(FTF_LOG_DEBUG,"md.cache",m_cfg.LogThrottleMs,"MD",
                         (m_cacheOk ? "indicator refresh incomplete - previous values kept: " : "indicators not ready yet: ")+BarSummary());
     }

   bool              CacheRetryDue(void)
     {
      return (m_cacheStale && m_nowMsc-m_cacheTryMsc>=FTF_MD_CACHE_RETRY_MS);
     }

   //--- registers every indicator used through md (ids owned by the platform layer)
   bool              RegisterIndicators(void)
     {
      m_idAtrM1=m_pf.RegisterATR(PERIOD_M1,m_cfg.AtrPeriod);
      m_idAtrM5=m_pf.RegisterATR(PERIOD_M5,m_cfg.AtrPeriod);
      m_idEmaM1F=m_pf.RegisterEMA(PERIOD_M1,m_cfg.MomEmaFast);
      m_idEmaM1S=m_pf.RegisterEMA(PERIOD_M1,m_cfg.MomEmaSlow);
      m_idEmaM5F=m_pf.RegisterEMA(PERIOD_M5,FTF_M5_EMA_FAST);
      m_idEmaM5S=m_pf.RegisterEMA(PERIOD_M5,FTF_M5_EMA_SLOW);
      m_idAdxM1=m_pf.RegisterADX(PERIOD_M1,FTF_M1_ADX_PERIOD);
      bool ok=(m_idAtrM1>=0 && m_idAtrM5>=0 && m_idEmaM1F>=0 && m_idEmaM1S>=0 &&
               m_idEmaM5F>=0 && m_idEmaM5S>=0 && m_idAdxM1>=0);
      string ids="ATR M1 #"+IntegerToString(m_idAtrM1)+", ATR M5 #"+IntegerToString(m_idAtrM5)+
                 ", EMA M1 "+IntegerToString(m_cfg.MomEmaFast)+"/"+IntegerToString(m_cfg.MomEmaSlow)+" #"+
                 IntegerToString(m_idEmaM1F)+"/#"+IntegerToString(m_idEmaM1S)+", EMA M5 "+
                 IntegerToString(FTF_M5_EMA_FAST)+"/"+IntegerToString(FTF_M5_EMA_SLOW)+" #"+
                 IntegerToString(m_idEmaM5F)+"/#"+IntegerToString(m_idEmaM5S)+", ADX M1("+
                 IntegerToString(FTF_M1_ADX_PERIOD)+") #"+IntegerToString(m_idAdxM1);
      if(ok)
         m_log.Info("MD","indicators registered (ATR period "+IntegerToString(m_cfg.AtrPeriod)+"): "+ids);
      else
         m_log.Error("MD","indicator registration FAILED: "+ids);
      return ok;
     }

public:
                     CMarketData(void)
     {
      m_cfg=NULL; m_log=NULL; m_pf=NULL; m_ticks=NULL; m_ready=false;
      spec.Reset();
      m_last.Reset();
      m_hasTick=false; m_nowMsc=0; m_lastTickMsc=0; m_srvTime=0;
      m_ticksThisCycle=0; m_ticksTotal=0; m_specMsc=0;
      m_tfCount=0;
      for(int i=0;i<FTF_MD_MAX_TF;i++)
        {
         m_tfs[i]=PERIOD_M1;
         m_tfLast[i]=0;
         m_tfNew[i]=false;
        }
      m_idAtrM1=-1; m_idAtrM5=-1; m_idEmaM1F=-1; m_idEmaM1S=-1; m_idEmaM5F=-1; m_idEmaM5S=-1; m_idAdxM1=-1;
      m_cacheDone=false; m_cacheOk=false; m_cacheStale=false; m_adxOk=false; m_cacheTryMsc=0;
      m_atrM1=0.0; m_atrM1Med=0.0; m_atrM5=0.0; m_emaM1F=0.0; m_emaM1S=0.0; m_emaM5F=0.0; m_emaM5S=0.0;
      m_adxM1=0.0; m_pdiM1=0.0; m_mdiM1=0.0; m_rocM1=0.0;
      m_velOk=false; m_velCur=0.0; m_velPrev=0.0; m_velMed=0.0; m_velRatio=0.0; m_velAccel=0.0;
      m_medSpreadRaw=0.0; m_spreadDone=false; m_spreadTicks=0;
     }

   //--- spec refresh (also used by the 10 % pause re-activation, docs/09 section 9). Logs INFO on changes
   bool              RefreshSpecNow(const bool initial)
     {
      m_specMsc=m_nowMsc;
      SSymbolSpec fresh;
      fresh.Reset();
      if(!m_pf.RefreshSpec(fresh) || fresh.point<=0.0)
        {
         m_log.Throttled(FTF_LOG_WARN,"md.spec",60000,"MD","symbol spec refresh failed - keeping previous values");
         return false;
        }
      if(initial)
         LogSpec(fresh);
      else
         LogSpecChanges(fresh);
      spec=fresh;
      //--- PRICE_PATH velocity floor = 1 point (docs/03 1.1)
      if(CheckPointer(m_ticks)!=POINTER_INVALID)
         m_ticks.SetPathFloor(spec.point);
      return true;
     }

   //+---------------------------------------------------------------+
   //| Init: spec, indicators, tick pre-load, watched timeframes     |
   //+---------------------------------------------------------------+
   bool              Init(CConfig *cfg,CLogger *logger,CPlatform *pf,CTickBuffer *ticks)
     {
      m_cfg=cfg; m_log=logger; m_pf=pf; m_ticks=ticks;
      m_ready=false;
      if(CheckPointer(m_cfg)==POINTER_INVALID || CheckPointer(m_log)==POINTER_INVALID ||
         CheckPointer(m_pf)==POINTER_INVALID || CheckPointer(m_ticks)==POINTER_INVALID)
         return false;
      m_nowMsc=m_pf.NowMsc();
      m_srvTime=m_pf.ServerTime();
      if(!RefreshSpecNow(true))
        {
         m_log.Error("MD","cannot read the chart symbol specification - market data not ready");
         return false;
        }
      if(!RegisterIndicators())
         return false;
      m_tfCount=0;
      AddTf(PERIOD_M1);
      AddTf(PERIOD_M5);
      AddTf(PERIOD_H1);
      AddTf(m_cfg.FvgTimeframe);
      AddTf(m_cfg.RngTimeframe);
      PreloadHistory();
      if(!m_hasTick)
         SnapshotFromCurrent();
      if((long)m_cfg.TickHistorySec*1000<(long)m_cfg.MomVelRefMs+3*(long)m_cfg.MomVelWindowMs)
         m_log.Warn("MD","tick history "+IntegerToString(m_cfg.TickHistorySec)+" s is shorter than the velocity "+
                    "reference + 3 windows - the buffer keeps "+FTF_D(((double)m_cfg.MomVelRefMs+3.0*(double)m_cfg.MomVelWindowMs)/1000.0,0)+" s");
      m_ready=true;
      string tfs="";
      for(int i=0;i<m_tfCount;i++)
         tfs+=(i>0 ? "," : "")+FTF_TfStr(m_tfs[i]);
      m_log.Info("MD","market data ready | watched timeframes "+tfs+" | stress extra spread "+
                 IntegerToString(m_cfg.StressExtraSpreadPts)+" pts | max tick age "+IntegerToString(m_cfg.MaxTickAgeSec)+
                 " s | velocity "+IntegerToString(m_cfg.MomVelWindowMs)+"/"+IntegerToString(m_cfg.MomVelRefMs)+" ms "+
                 EnumToString(m_cfg.MomVelMetric));
      return true;
     }

   //+---------------------------------------------------------------+
   //| Update - step 1 of every cycle (docs/09 section 8)            |
   //+---------------------------------------------------------------+
   bool              Update(void)
     {
      if(!m_ready)
         return false;
      for(int i=0;i<m_tfCount;i++)
         m_tfNew[i]=false;
      m_ticksThisCycle=0;
      int n=m_pf.FetchNewTicks(m_buf,FTF_MD_FETCH_MAX);
      if(n>0)
         m_ticksThisCycle=IngestTicks(n);
      if(m_ticksThisCycle>0)
        {
         if(m_last.msc>m_nowMsc)
            m_nowMsc=m_last.msc;           // server time = newest tick time
        }
      else
        {
         SnapshotFromCurrent();
         long p=m_pf.NowMsc();
         if(p>m_nowMsc)
            m_nowMsc=p;
        }
      m_srvTime=m_pf.ServerTime();
      if(m_ticksThisCycle>0)
        {
         UpdateTickStats(m_ticksThisCycle);
         TrimTicks();
        }
      DetectNewBars();
      if(!m_cacheDone || NewBarAt(PERIOD_M1) || CacheRetryDue())
         RefreshCache();
      if(m_nowMsc-m_specMsc>=FTF_MD_SPEC_REFRESH_MS)
         RefreshSpecNow(false);
      return (m_ticksThisCycle>0);
     }

   //+---------------------------------------------------------------+
   //| time / quotes                                                 |
   //+---------------------------------------------------------------+
   long              NowMsc(void)        { return m_nowMsc; }
   datetime          ServerTime(void)    { return (m_srvTime>0 ? m_srvTime : m_pf.ServerTime()); }
   double            BidPrice(void)      { return m_last.bid; }
   double            AskPrice(void)      { return m_last.ask; }
   double            MidPrice(void)      { return (m_last.bid+m_last.ask)*0.5; }
   //--- ask - bid + stress extra spread x point (docs/03 notation)
   double            Spread(void)
     {
      if(!m_hasTick)
         return 0.0;
      double raw=m_last.ask-m_last.bid;
      if(raw<0.0)
         raw=0.0;
      return raw+(double)m_cfg.StressExtraSpreadPts*Pt();
     }
   double            SpreadPts(void)
     {
      double pt=Pt();
      return (pt>0.0 ? Spread()/pt : 0.0);
     }
   double            PointSize(void)     { return spec.point; }
   int               DigitsCount(void)   { return spec.digits; }
   double            TickSize(void)      { return (spec.tickSize>0.0 ? spec.tickSize : spec.point); }
   int               TicksThisCycle(void){ return m_ticksThisCycle; }

   //+---------------------------------------------------------------+
   //| bars                                                          |
   //+---------------------------------------------------------------+
   //--- true during the cycle where tf opened a new bar (M1, M5, H1, FVG tf, Range tf only)
   bool              IsNewBar(const ENUM_TIMEFRAMES tf) { return NewBarAt(tf); }
   datetime          LastBarTime(const ENUM_TIMEFRAMES tf)
     {
      int i=TfIndex(tf);
      if(i>=0 && m_tfLast[i]>0)
         return m_tfLast[i];
      return m_pf.BarTime(tf,0);
     }

   //+---------------------------------------------------------------+
   //| cached indicators (closed bar, refreshed on new M1 bar)       |
   //+---------------------------------------------------------------+
   double            AtrM1(void)         { return m_atrM1; }
   double            AtrM1Median(void)   { return m_atrM1Med; }
   double            AtrM5(void)         { return m_atrM5; }
   double            EmaM1Fast(void)     { return m_emaM1F; }
   double            EmaM1Slow(void)     { return m_emaM1S; }
   double            EmaM5Fast(void)     { return m_emaM5F; }
   double            EmaM5Slow(void)     { return m_emaM5S; }
   double            AdxM1(void)         { return m_adxM1; }
   double            PlusDiM1(void)      { return m_pdiM1; }
   double            MinusDiM1(void)     { return m_mdiM1; }
   double            RocM1(void)         { return m_rocM1; }
   //--- extra: ATR M1 / median ATR (volatility anomaly + Range impulse protection), 0 if unknown
   double            AtrRatio(void)      { return (m_atrM1Med>0.0 ? m_atrM1/m_atrM1Med : 0.0); }

   //+---------------------------------------------------------------+
   //| tick statistics                                               |
   //+---------------------------------------------------------------+
   double            VelCur(void)        { return m_velCur; }
   double            VelPrev(void)       { return m_velPrev; }
   double            VelMedian(void)     { return m_velMed; }
   double            VelRatio(void)      { return m_velRatio; }
   double            VelAccel(void)      { return m_velAccel; }
   //--- extra: false while the velocity reference history is incomplete (values are computed anyway)
   bool              VelOk(void)         { return m_velOk; }
   //--- recent median spread (price) incl. the stress extra spread, comparable with Spread()
   double            MedianSpread(void)
     {
      if(!m_spreadDone)
         return 0.0;
      return m_medSpreadRaw+(double)m_cfg.StressExtraSpreadPts*Pt();
     }
   //--- extra: ticks accepted since Init (incl. pre-load)
   long              TicksTotal(void)    { return m_ticksTotal; }

   //+---------------------------------------------------------------+
   //| freshness / readiness                                         |
   //+---------------------------------------------------------------+
   //--- age of the newest tick vs the server clock (ms). Never negative.
   long              TickAgeMs(void)
     {
      if(!m_hasTick)
         return FTF_MD_NO_TICK_AGE;
      long age=(long)m_pf.ServerTime()*1000-m_lastTickMsc;
      return (age>0 ? age : 0);
     }
   //--- docs/03 section 5 STALE_TICK. The tester clock only moves with ticks: fresh once a tick arrived.
   bool              TickFresh(void)
     {
      if(!m_hasTick)
         return false;
      if(m_pf.IsTester() || m_cfg.MaxTickAgeSec<=0)
         return true;
      return (TickAgeMs()<=(long)m_cfg.MaxTickAgeSec*1000);
     }

   //--- bars + indicators ready (engines check their own tick coverage with TicksWarm)
   bool              IsWarm(string &why)
     {
      why="";
      if(!m_ready)
        {
         why="market data not initialised";
         return false;
        }
      if(!m_hasTick)
         AddWhy(why,"no tick received yet");
      int needM1=m_cfg.AtrMedianBars+m_cfg.AtrPeriod+5;
      int b1=m_pf.BarsCount(PERIOD_M1);
      int b5=m_pf.BarsCount(PERIOD_M5);
      int bh=m_pf.BarsCount(PERIOD_H1);
      if(b1<=needM1)
         AddWhy(why,"M1 bars "+IntegerToString(b1)+"/"+IntegerToString(needM1+1));
      if(b5<=FTF_MD_MIN_M5_BARS)
         AddWhy(why,"M5 bars "+IntegerToString(b5)+"/"+IntegerToString(FTF_MD_MIN_M5_BARS+1));
      if(bh<=FTF_MD_MIN_H1_BARS)
         AddWhy(why,"H1 bars "+IntegerToString(bh)+"/"+IntegerToString(FTF_MD_MIN_H1_BARS+1));
      if(!IsPos(m_atrM1))
         AddWhy(why,"ATR M1 not ready");
      if(!IsPos(m_atrM5))
         AddWhy(why,"ATR M5 not ready");
      if(!IsPos(m_atrM1Med))
         AddWhy(why,"median ATR not ready");
      if(m_emaM1F<=0.0 || m_emaM1S<=0.0 || m_emaM5F<=0.0 || m_emaM5S<=0.0)
         AddWhy(why,"EMA M1/M5 not ready");
      if(!m_adxOk)
         AddWhy(why,"ADX M1 not ready");
      return (StringLen(why)==0);
     }

   //--- tick buffer spans >= needMs (newest - oldest) and holds >= needTicks
   bool              TicksWarm(const int needMs,const int needTicks)
     {
      int cnt=m_ticks.Count();
      if(cnt<=0 || cnt<needTicks)
         return false;
      long span=m_ticks.MscAt(0)-m_ticks.MscAt(cnt-1);
      return (span>=(long)needMs);
     }

   //--- extra: short status for the panel / logs
   string            Describe(void)
     {
      int d=Dg();
      return "bid "+FTF_D(m_last.bid,d)+" ask "+FTF_D(m_last.ask,d)+" | spread "+FTF_D(SpreadPts(),1)+
             " pts | ATR "+FTF_D(m_atrM1,d+1)+" (x"+FTF_D(AtrRatio(),2)+" median) | vel x"+FTF_D(m_velRatio,2)+
             " | ticks "+IntegerToString(m_ticks.Count())+" | age "+
             (m_hasTick ? IntegerToString(TickAgeMs())+" ms" : "n/a");
     }
  };

#endif // FTF_MARKET_DATA_MQH
