//+------------------------------------------------------------------+
//|                                                    EngineFVG.mqh |
//|  CEngineFVG - Engine B: Fair Value Gap (docs/03 section 2).      |
//|  Zones are detected on CLOSED bars of the FVG timeframe, their   |
//|  life cycle is tracked per bar and per tick, entries are         |
//|  evaluated on every tick. Never reads another engine.            |
//|  docs/09 section 7.13                                            |
//|                                                                  |
//|  Price conventions (documented choices):                         |
//|  * "inside" / mitigation uses the MID price: a bullish zone is   |
//|    entered when mid <= top, a bearish zone when mid >= bottom    |
//|    (near edge penetrated; the far side is the invalidation rule).|
//|    A new return counts only after price left the zone by         |
//|    max(1 spread, FTF_FVG_REENTRY_GAP_FRAC x gap) (tick noise).   |
//|    During the start-up replay the same rule is applied per bar   |
//|    (bull: bar low <= top, outside again when bar low > top).     |
//|  * invalidation uses BID (chart bars are bid based): bullish     |
//|    close/bid < bottom - buf, bearish close/bid > top + buf,      |
//|    buf = Invalidation buffer x ATR(FVG tf, shift 1).             |
//|  * entries: BUY trigger on ASK, SELL trigger on BID (docs/03).   |
//+------------------------------------------------------------------+
#ifndef FTF_ENGINE_FVG_MQH
#define FTF_ENGINE_FVG_MQH

#include <FranckyTriFlux\Core\EngineBase.mqh>
#include <FranckyTriFlux\Core\Structure.mqh>

#define FTF_FVG_REENTRY_GAP_FRAC  0.25   // TUNABLE (not an input yet): price must leave a zone by max(1 spread, this x gap) before a new return counts as a mitigation

//--- one fair value gap zone
struct SFvgZone
  {
   string            id;            // FVG-<B|S>-<time of B2>
   int               dir;           // +1 bullish (demand below price), -1 bearish (supply above price)
   double            top;
   double            bottom;
   double            ce;            // consequent encroachment = (top + bottom) / 2
   datetime          t1;            // open time of B1 (oldest candle)
   datetime          t2;            // open time of B2 (displacement candle, used in the id)
   datetime          t3;            // open time of B3 (newest candle)
   int               ageBars;       // closed bars of the FVG timeframe since B3
   int               mitigations;   // returns into the zone after being outside
   int               trades;        // setups consumed (entries, or ids already traded / burned)
   int               state;         // ENUM_FTF_ZONE_STATE
   bool              inside;        // price currently inside the zone (near edge penetrated)
   long              lastTouchMsc;  // last tick (server ms) seen inside the zone
   double            swingExtreme;  // lowest low (bull) / highest high (bear) of B1..B3 (SWING SL)
   bool              structOk;      // BOS / CHoCH present according to FvgStructMode
   datetime          endTime;       // time of the terminal state change (0 while alive) - drawing end
   int               drawnState;    // state last drawn on the chart (-1 = never drawn)
   void              Reset(void)
     {
      id=""; dir=0; top=0.0; bottom=0.0; ce=0.0; t1=0; t2=0; t3=0; ageBars=0; mitigations=0;
      trades=0; state=FTF_ZS_INTACT; inside=false; lastTouchMsc=0; swingExtreme=0.0; structOk=false;
      endTime=0; drawnState=-1;
     }
  };

class CEngineFVG : public CEngineBase
  {
private:
   CStructure        m_struct;        // swings / BOS / CHoCH on the FVG timeframe
   SFvgZone          m_zones[];       // creation order: oldest first
   int               m_count;         // == ArraySize(m_zones)
   int               m_atrId;         // platform ATR id on the FVG timeframe (-1 = none)
   double            m_atr;           // ATR(FVG tf) of the last closed bar (shift 1)
   bool              m_scanned;       // start-up history scan done
   bool              m_dirty;         // chart objects must be redrawn
   datetime          m_lastBar1;      // open time of the last closed FVG bar already processed
   datetime          m_lastRefBar;    // REJECTION: last refine candle already evaluated
   datetime          m_lastDrawBar;   // FVG bar used by the last Draw()
   long              m_infoMsc;       // last refresh of the panel "waiting" text
   double            m_atrCache[];    // ATR per shift, only while the start-up scan runs
   int               m_atrCacheN;     // 0 = cache off

   //+---------------------------------------------------------------+
   //| small helpers                                                 |
   //+---------------------------------------------------------------+
   string            FmtPx(const double v)
     {
      int d=m_ctx.md.DigitsCount();
      return DoubleToString(v,(d>0 ? d : 5));
     }
   string            FmtPts(const double dist)
     {
      double pt=m_ctx.md.PointSize();
      return DoubleToString((pt>0.0 ? dist/pt : 0.0),1);
     }
   string            StateStr(const int st)
     {
      switch(st)
        {
         case FTF_ZS_INTACT:      return "INTACT";
         case FTF_ZS_MITIGATED:   return "MITIGATED";
         case FTF_ZS_INVALIDATED: return "INVALIDATED";
         case FTF_ZS_EXPIRED:     return "EXPIRED";
         case FTF_ZS_EXHAUSTED:   return "EXHAUSTED";
         default:                 break;
        }
      return "?";
     }
   bool              IsAlive(const int st)
     {
      return (st==FTF_ZS_INTACT || st==FTF_ZS_MITIGATED);
     }
   //--- REJECTION candle timeframe: M1 when "Use M1 for entry precision", else the FVG timeframe
   ENUM_TIMEFRAMES   RefTf(void)
     {
      return (m_ctx.cfg.FvgUseM1Refine ? PERIOD_M1 : m_ctx.cfg.FvgTimeframe);
     }
   string            TfText(void)
     {
      string s=FTF_TfStr(m_ctx.cfg.FvgTimeframe);
      if(m_ctx.cfg.FvgEntryMode==FTF_FVG_REJECTION && m_ctx.cfg.FvgUseM1Refine && m_ctx.cfg.FvgTimeframe!=PERIOD_M1)
         s+="/M1";
      return s;
     }
   string            EntryModeStr(void)
     {
      if(m_ctx.cfg.FvgEntryMode==FTF_FVG_CE)
         return "CE";
      if(m_ctx.cfg.FvgEntryMode==FTF_FVG_REJECTION)
         return "REJECTION";
      return "TOUCH";
     }
   string            StructModeStr(void)
     {
      if(m_ctx.cfg.FvgStructMode==FTF_STRUCT_CHOCH)
         return "CHoCH";
      if(m_ctx.cfg.FvgStructMode==FTF_STRUCT_ANY)
         return "BOS|CHoCH";
      return "BOS";
     }
   string            TpModeStr(void)
     {
      if(m_ctx.cfg.FvgTpMode==FTF_TP_ATR)
         return "ATR";
      if(m_ctx.cfg.FvgTpMode==FTF_TP_RR)
         return "RR";
      return "LIQUIDITY";
     }
   string            ShortId(const int k)
     {
      return (m_zones[k].dir>0 ? "B " : "S ")+TimeToString(m_zones[k].t2,TIME_MINUTES);
     }

   //--- ATR(FVG tf) at a shift: platform indicator, else a local SMA of the true range (same
   //--- definition) so that the start-up scan works before the indicator buffer is ready
   double            AtrAt(const int shift)
     {
      if(shift>=0 && shift<m_atrCacheN)
        {
         if(m_atrCache[shift]<=0.0)
            m_atrCache[shift]=AtrRaw(shift);
         return m_atrCache[shift];
        }
      return AtrRaw(shift);
     }
   double            AtrRaw(const int shift)
     {
      double v=EMPTY_VALUE;
      if(m_atrId>=0)
         v=m_ctx.pf.IndValue(m_atrId,0,shift);
      if(v!=EMPTY_VALUE && v>0.0)
         return v;
      return LocalAtr(shift);
     }
   double            LocalAtr(const int shift)
     {
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      int period=m_ctx.cfg.AtrPeriod;
      if(period<1 || shift<0 || shift+period+1>m_ctx.pf.BarsCount(tf))
         return 0.0;
      double sum=0.0;
      for(int j=shift;j<shift+period;j++)
        {
         double prevClose=m_ctx.pf.BarClose(tf,j+1);
         double hi=MathMax(m_ctx.pf.BarHigh(tf,j),prevClose);
         double lo=MathMin(m_ctx.pf.BarLow(tf,j),prevClose);
         sum+=(hi-lo);
        }
      return sum/(double)period;
     }

   //+---------------------------------------------------------------+
   //| zone helpers                                                  |
   //+---------------------------------------------------------------+
   //--- invalidation level: bullish bottom - buf, bearish top + buf (docs/03 2.2)
   double            InvalidLevel(const int k,const double atr)
     {
      double buf=m_ctx.cfg.FvgInvalidBufAtr*atr;
      return (m_zones[k].dir>0 ? m_zones[k].bottom-buf : m_zones[k].top+buf);
     }
   //--- entry-side distance: bullish = ask above top, bearish = bid below bottom (0 when touching)
   double            EntryDistance(const int k,const double bid,const double ask)
     {
      if(m_zones[k].dir>0)
         return MathMax(0.0,ask-m_zones[k].top);
      return MathMax(0.0,m_zones[k].bottom-bid);
     }
   //--- distance of a price to the zone band (0 inside) - panel only
   double            BandDistance(const int k,const double px)
     {
      if(px>m_zones[k].top)
         return px-m_zones[k].top;
      if(px<m_zones[k].bottom)
         return m_zones[k].bottom-px;
      return 0.0;
     }
   int               FindZone(const string zid)
     {
      for(int k=0;k<m_count;k++)
         if(m_zones[k].id==zid)
            return k;
      return -1;
     }
   //--- setup ids are "<zoneId>-T<n>" (docs/09 7.13 signal field conventions)
   int               ZoneOfSetup(const string setupId)
     {
      for(int k=0;k<m_count;k++)
         if(StringFind(setupId,m_zones[k].id+"-T")==0)
            return k;
      return -1;
     }
   //--- structure event per "Structure event accepted" (BOS / CHoCH / either) since B1
   bool              StructFor(const int dir,const datetime fromTime)
     {
      if(m_ctx.cfg.FvgStructMode==FTF_STRUCT_CHOCH)
         return m_struct.HasChoch(dir,fromTime);
      if(m_ctx.cfg.FvgStructMode==FTF_STRUCT_ANY)
         return (m_struct.HasBos(dir,fromTime) || m_struct.HasChoch(dir,fromTime));
      return m_struct.HasBos(dir,fromTime);
     }
   //--- quality 0..100 (ordering only): 50 + 25 if BOS/CHoCH present + 25 x min(1, gap / ATR)
   double            Quality(const int k,const double atr)
     {
      double gap=m_zones[k].top-m_zones[k].bottom;
      double q=50.0+(m_zones[k].structOk ? 25.0 : 0.0);
      if(atr>0.0)
         q+=MathMin(25.0,25.0*gap/atr);
      return FTF_Clamp(q,0.0,100.0);
     }

   void              SetState(const int k,const int st,const datetime t,const string why,const bool quiet)
     {
      int old=m_zones[k].state;
      if(old==st)
         return;
      m_zones[k].state=st;
      if(!IsAlive(st))
         m_zones[k].endTime=t;
      m_dirty=true;
      Log((quiet ? (int)FTF_LOG_DEBUG : (int)FTF_LOG_INFO),"zone "+m_zones[k].id+" "+StateStr(old)+" -> "+StateStr(st)+" | "+why);
     }
   //--- one more return into the zone: MITIGATED, or EXHAUSTED above FvgMaxMitigations (docs/03 2.2)
   void              CountMitigation(const int k,const datetime t,const string where,const bool quiet)
     {
      m_zones[k].mitigations++;
      int mit=m_zones[k].mitigations;
      string txt="return #"+IntegerToString(mit)+" ("+where+")";
      if(mit>m_ctx.cfg.FvgMaxMitigations)
         SetState(k,FTF_ZS_EXHAUSTED,t,txt+" > max "+IntegerToString(m_ctx.cfg.FvgMaxMitigations),quiet);
      else if(m_zones[k].state==FTF_ZS_INTACT)
         SetState(k,FTF_ZS_MITIGATED,t,txt,quiet);
      else
         Log((quiet ? (int)FTF_LOG_DEBUG : (int)FTF_LOG_INFO),"zone "+m_zones[k].id+" "+txt);
     }
   void              RemoveObjects(const int k)
     {
      if(CheckPointer(m_ctx.ui)==POINTER_INVALID)
         return;
      m_ctx.ui.Remove("FVG_"+m_zones[k].id);
      m_ctx.ui.Remove("FVGCE_"+m_zones[k].id);
     }
   void              RemoveAt(const int k)
     {
      if(k<0 || k>=m_count)
         return;
      for(int j=k;j<m_count-1;j++)
         m_zones[j]=m_zones[j+1];
      m_count--;
      ArrayResize(m_zones,m_count);
      m_dirty=true;
     }
   //--- keep at most "Max zones kept": dead zones (oldest first) go before live ones (oldest first)
   void              EnforceMaxZones(void)
     {
      int maxZ=(m_ctx.cfg.FvgMaxZones>0 ? m_ctx.cfg.FvgMaxZones : 1);
      while(m_count>maxZ)
        {
         int victim=0;
         for(int k=0;k<m_count;k++)
            if(!IsAlive(m_zones[k].state))
              {
               victim=k;
               break;
              }
         if(IsAlive(m_zones[victim].state))
           {
            Log(FTF_LOG_INFO,"zone "+m_zones[victim].id+" dropped while "+StateStr(m_zones[victim].state)+
                " (max "+IntegerToString(maxZ)+" zones kept, oldest first)");
            RemoveObjects(victim);
           }
         else
            Log(FTF_LOG_DEBUG,"zone "+m_zones[victim].id+" ("+StateStr(m_zones[victim].state)+") forgotten (max zones)");
         RemoveAt(victim);
        }
     }

   //+---------------------------------------------------------------+
   //| detection (docs/03 2.1)                                       |
   //+---------------------------------------------------------------+
   bool              GapPasses(const string zid,const double gap,const double atr)
     {
      double minAtr=m_ctx.cfg.FvgMinGapAtr*atr;
      double minSpr=m_ctx.cfg.FvgMinGapSpreadMult*m_ctx.md.Spread();
      if(atr>0.0 && gap>=minAtr && gap>=minSpr)
         return true;
      Log(FTF_LOG_DEBUG,zid+" gap filtered: "+FmtPts(gap)+" pts < min "+FmtPts(minAtr)+" pts ("+
          DoubleToString(m_ctx.cfg.FvgMinGapAtr,2)+" ATR) or "+FmtPts(minSpr)+" pts ("+
          DoubleToString(m_ctx.cfg.FvgMinGapSpreadMult,2)+" x spread)"+(atr>0.0 ? "" : " | ATR not ready"));
      return false;
     }
   //--- FVG with B3 = shift i, B2 = i+1, B1 = i+2 (all closed). Returns the new zone index or -1
   int               DetectAt(const int i,const bool replay)
     {
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      if(i<1 || i+2>=m_ctx.pf.BarsCount(tf))
         return -1;
      double hiB1=m_ctx.pf.BarHigh(tf,i+2);
      double loB1=m_ctx.pf.BarLow(tf,i+2);
      double hiB3=m_ctx.pf.BarHigh(tf,i);
      double loB3=m_ctx.pf.BarLow(tf,i);
      int dir=FTF_DIR_NONE;
      double top=0.0;
      double bottom=0.0;
      if(loB3>hiB1)
        {
         dir=FTF_DIR_BUY;  bottom=hiB1; top=loB3;     // bullish: Low(B3) > High(B1)
        }
      else if(hiB3<loB1)
        {
         dir=FTF_DIR_SELL; bottom=hiB3; top=loB1;     // bearish: High(B3) < Low(B1)
        }
      if(dir==FTF_DIR_NONE)
         return -1;
      string zid=(dir>0 ? "FVG-B-" : "FVG-S-")+TimeToString(m_ctx.pf.BarTime(tf,i+1),TIME_DATE|TIME_MINUTES);
      if(FindZone(zid)>=0)
         return -1;
      double atr=AtrAt(i);
      if(!GapPasses(zid,top-bottom,atr))
         return -1;
      return AddZone(zid,dir,top,bottom,i,atr,replay);
     }
   int               AddZone(const string zid,const int dir,const double top,const double bottom,const int i,
                             const double atr,const bool replay)
     {
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      SFvgZone z;
      z.Reset();
      z.id=zid;
      z.dir=dir;
      z.top=top;
      z.bottom=bottom;
      z.ce=(top+bottom)*0.5;
      z.t1=m_ctx.pf.BarTime(tf,i+2);
      z.t2=m_ctx.pf.BarTime(tf,i+1);
      z.t3=m_ctx.pf.BarTime(tf,i);
      double lo=MathMin(m_ctx.pf.BarLow(tf,i),MathMin(m_ctx.pf.BarLow(tf,i+1),m_ctx.pf.BarLow(tf,i+2)));
      double hi=MathMax(m_ctx.pf.BarHigh(tf,i),MathMax(m_ctx.pf.BarHigh(tf,i+1),m_ctx.pf.BarHigh(tf,i+2)));
      z.swingExtreme=(dir>0 ? lo : hi);
      z.structOk=StructFor(dir,z.t1);
      int k=m_count;
      if(ArrayResize(m_zones,k+1)<k+1)
         return -1;
      m_zones[k]=z;
      m_count=k+1;
      m_dirty=true;
      Log((replay ? (int)FTF_LOG_DEBUG : (int)FTF_LOG_INFO),"new "+(dir>0 ? "BULL" : "BEAR")+" zone "+zid+" ["+FmtPx(bottom)+
          " .. "+FmtPx(top)+"] gap "+FmtPts(top-bottom)+" pts = "+DoubleToString((atr>0.0 ? (top-bottom)/atr : 0.0),2)+
          " ATR | CE "+FmtPx(z.ce)+" | struct "+StructModeStr()+" "+(z.structOk ? "ok" : "no"));
      return k;
     }
   //--- start-up replay of the closed bars after B3 (shifts i-1 .. 1): bar-level mitigation,
   //--- invalidation and expiry, in the same order as live processing (docs/03 2.1)
   void              ReplayZone(const int k,const int i)
     {
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      long tfSec=(long)FTF_TfSeconds(tf);
      bool onClose=m_ctx.cfg.FvgInvalidOnClose;
      bool bull=(m_zones[k].dir>0);
      for(int j=i-1;j>=1;j--)
        {
         datetime tEnd=(datetime)((long)m_ctx.pf.BarTime(tf,j)+tfSec);
         double hi=m_ctx.pf.BarHigh(tf,j);
         double lo=m_ctx.pf.BarLow(tf,j);
         bool touch=(bull ? (lo<=m_zones[k].top) : (hi>=m_zones[k].bottom));
         if(touch && !m_zones[k].inside)
           {
            m_zones[k].inside=true;
            CountMitigation(k,tEnd,"replay bar "+TimeToString(m_ctx.pf.BarTime(tf,j),TIME_DATE|TIME_MINUTES),true);
           }
         else if(!touch)
            m_zones[k].inside=false;
         if(!IsAlive(m_zones[k].state))
            break;
         double inv=InvalidLevel(k,AtrAt(j));
         double px=(onClose ? m_ctx.pf.BarClose(tf,j) : (bull ? lo : hi));
         if(bull ? (px<inv) : (px>inv))
           {
            SetState(k,FTF_ZS_INVALIDATED,tEnd,"replay "+(onClose ? "close " : "extreme ")+FmtPx(px)+(bull ? " < " : " > ")+FmtPx(inv),true);
            break;
           }
         if(i-j>m_ctx.cfg.FvgMaxAgeBars)
           {
            SetState(k,FTF_ZS_EXPIRED,tEnd,"replay age "+IntegerToString(i-j)+" > "+IntegerToString(m_ctx.cfg.FvgMaxAgeBars)+" bars",true);
            break;
           }
        }
      m_zones[k].ageBars=i-1;
     }
   void              LogScanSummary(const int nBars)
     {
      int nb=0, ns=0, intact=0, mitig=0, dead=0;
      for(int k=0;k<m_count;k++)
        {
         if(m_zones[k].dir>0)
            nb++;
         else
            ns++;
         if(m_zones[k].state==FTF_ZS_INTACT)
            intact++;
         else if(m_zones[k].state==FTF_ZS_MITIGATED)
            mitig++;
         else
            dead++;
        }
      Log(FTF_LOG_INFO,"scan: "+IntegerToString(m_count)+" zones (bull "+IntegerToString(nb)+" / bear "+IntegerToString(ns)+
          ") | live "+IntegerToString(intact+mitig)+" (intact "+IntegerToString(intact)+", mitigated "+IntegerToString(mitig)+
          "), dead "+IntegerToString(dead)+" | "+IntegerToString(nBars)+" "+FTF_TfStr(m_ctx.cfg.FvgTimeframe)+
          " bars scanned | ATR "+FmtPts(m_atr)+" pts | swings H/L "+IntegerToString(m_struct.SwingHighs())+"/"+
          IntegerToString(m_struct.SwingLows()));
     }
   //--- start-up scan: zones created oldest first, each replayed over the bars after its B3
   bool              Scan(void)
     {
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      int nBars=m_ctx.pf.BarsCount(tf);
      int maxI=m_ctx.cfg.FvgScanBars;
      if(maxI>nBars-3)
         maxI=nBars-3;                   // B1 = i+2 must exist
      if(maxI<1 || AtrAt(1)<=0.0)
        {
         LogThrottled(FTF_LOG_DEBUG,"scan","scan deferred: "+FTF_TfStr(tf)+" bars "+IntegerToString(nBars)+", ATR not ready");
         return false;
        }
      m_struct.Update();
      m_count=0;
      ArrayResize(m_zones,0);
      if(ArrayResize(m_atrCache,maxI+1)==maxI+1)
        {
         for(int j=0;j<=maxI;j++)
            m_atrCache[j]=0.0;
         m_atrCacheN=maxI+1;
        }
      for(int i=maxI;i>=1;i--)
        {
         int k=DetectAt(i,true);
         if(k>=0)
            ReplayZone(k,i);
        }
      m_atrCacheN=0;
      ArrayResize(m_atrCache,0);
      EnforceMaxZones();
      m_scanned=true;
      m_dirty=true;
      m_atr=AtrAt(1);
      m_lastBar1=m_ctx.pf.BarTime(tf,1);
      LogScanSummary(maxI);
      return true;
     }

   //+---------------------------------------------------------------+
   //| life cycle (docs/03 2.2)                                      |
   //+---------------------------------------------------------------+
   //--- new closed bar of the FVG tf: age, invalidation on close (bar extreme in tick mode, as a
   //--- safety net for missed ticks), expiry, structure refresh
   void              BarUpdateZones(void)
     {
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      datetime tNow=m_ctx.pf.BarTime(tf,0);
      double cl=m_ctx.pf.BarClose(tf,1);
      double hi=m_ctx.pf.BarHigh(tf,1);
      double lo=m_ctx.pf.BarLow(tf,1);
      bool onClose=m_ctx.cfg.FvgInvalidOnClose;
      for(int k=0;k<m_count;k++)
        {
         if(!IsAlive(m_zones[k].state))
            continue;
         bool bull=(m_zones[k].dir>0);
         m_zones[k].ageBars++;
         double inv=InvalidLevel(k,m_atr);
         double px=(onClose ? cl : (bull ? lo : hi));
         if(bull ? (px<inv) : (px>inv))
           {
            SetState(k,FTF_ZS_INVALIDATED,tNow,(onClose ? "close " : "bar extreme ")+FmtPx(px)+(bull ? " < " : " > ")+
                     "far edge +/- buffer "+FmtPx(inv),false);
            continue;
           }
         if(m_zones[k].ageBars>m_ctx.cfg.FvgMaxAgeBars)
           {
            SetState(k,FTF_ZS_EXPIRED,tNow,"age "+IntegerToString(m_zones[k].ageBars)+" > "+
                     IntegerToString(m_ctx.cfg.FvgMaxAgeBars)+" bars",false);
            continue;
           }
         if(!m_zones[k].structOk && StructFor(m_zones[k].dir,m_zones[k].t1))
           {
            m_zones[k].structOk=true;
            m_dirty=true;
            Log(FTF_LOG_INFO,"zone "+m_zones[k].id+" structure confirmed ("+StructModeStr()+" since B1)");
           }
        }
     }
   //--- every tick: returns into the zone (mid price) and tick invalidation (bid) when
   //--- "Invalidate on candle close" is OFF
   void              UpdateTicks(const double bid,const double mid,const double atr)
     {
      bool tickInv=!m_ctx.cfg.FvgInvalidOnClose;
      long nowMsc=m_ctx.md.NowMsc();
      datetime tNow=m_ctx.md.ServerTime();
      double spread=m_ctx.md.Spread();
      for(int k=0;k<m_count;k++)
        {
         if(!IsAlive(m_zones[k].state))
            continue;
         bool bull=(m_zones[k].dir>0);
         if(tickInv)
           {
            double inv=InvalidLevel(k,atr);
            if(bull ? (bid<inv) : (bid>inv))
              {
               SetState(k,FTF_ZS_INVALIDATED,tNow,"tick bid "+FmtPx(bid)+(bull ? " < " : " > ")+FmtPx(inv),false);
               continue;
              }
           }
         double hyst=MathMax(spread,FTF_FVG_REENTRY_GAP_FRAC*(m_zones[k].top-m_zones[k].bottom));
         bool isIn=(bull ? (mid<=m_zones[k].top) : (mid>=m_zones[k].bottom));
         bool isOut=(bull ? (mid>m_zones[k].top+hyst) : (mid<m_zones[k].bottom-hyst));
         if(isIn)
           {
            m_zones[k].lastTouchMsc=nowMsc;
            if(!m_zones[k].inside)
              {
               m_zones[k].inside=true;
               CountMitigation(k,tNow,"mid "+FmtPx(mid),false);
              }
           }
         else if(isOut)
            m_zones[k].inside=false;
        }
     }

   //+---------------------------------------------------------------+
   //| entry rules (docs/03 2.3)                                     |
   //+---------------------------------------------------------------+
   //--- REJECTION: last closed candle of the refine tf wicks into the zone, closes beyond CE in
   //--- the zone direction, has the zone-direction body and a wick >= "REJECTION: min wick" %
   bool              RejectionOk(const int k,string &txt)
     {
      ENUM_TIMEFRAMES rtf=RefTf();
      double o=m_ctx.pf.BarOpen(rtf,1);
      double hi=m_ctx.pf.BarHigh(rtf,1);
      double lo=m_ctx.pf.BarLow(rtf,1);
      double c=m_ctx.pf.BarClose(rtf,1);
      double rng=hi-lo;
      string tfs=FTF_TfStr(rtf);
      if(rng<=0.0)
        {
         txt="REJECTION: flat "+tfs+" candle";
         return false;
        }
      bool bull=(m_zones[k].dir>0);
      double wick=(bull ? MathMin(o,c)-lo : hi-MathMax(o,c));
      string w="wick "+DoubleToString(wick/rng*100.0,0)+"% (min "+DoubleToString(m_ctx.cfg.FvgRejectWickPct,0)+"%)";
      if(bull ? (lo>m_zones[k].top) : (hi<m_zones[k].bottom))
         txt="REJECTION: "+tfs+" candle did not reach the zone";
      else if(bull ? (c<=m_zones[k].ce) : (c>=m_zones[k].ce))
         txt="REJECTION: close "+FmtPx(c)+(bull ? " <= " : " >= ")+"CE "+FmtPx(m_zones[k].ce);
      else if(bull ? (c<=o) : (c>=o))
         txt="REJECTION: "+tfs+" candle not "+(bull ? "bullish" : "bearish");
      else if(wick<m_ctx.cfg.FvgRejectWickPct/100.0*rng)
         txt="REJECTION: "+w;
      else
        {
         txt="REJECTION "+tfs+" candle "+(bull ? "low " : "high ")+FmtPx(bull ? lo : hi)+" in zone, close "+
             FmtPx(c)+" beyond CE, "+w;
         return true;
        }
      return false;
     }
   //--- TOUCH: bull ask <= top / bear bid >= bottom ; CE: bull ask <= CE / bear bid >= CE
   bool              PriceTrigger(const int k,const double bid,const double ask,const bool rejBar,const bool verbose,string &txt)
     {
      if(m_ctx.cfg.FvgEntryMode==FTF_FVG_REJECTION)
        {
         if(rejBar)
            return RejectionOk(k,txt);
         if(verbose)
            txt="REJECTION: waiting for the next "+FTF_TfStr(RefTf())+" candle close";
         return false;
        }
      bool bull=(m_zones[k].dir>0);
      bool useCe=(m_ctx.cfg.FvgEntryMode==FTF_FVG_CE);
      double lvl=(useCe ? m_zones[k].ce : (bull ? m_zones[k].top : m_zones[k].bottom));
      double px=(bull ? ask : bid);
      bool hit=(bull ? (px<=lvl) : (px>=lvl));
      if(verbose)
        {
         txt=(bull ? "ask " : "bid ")+FmtPx(px)+(hit ? (bull ? " <= " : " >= ") : (bull ? " > " : " < "))+
             (useCe ? "CE " : (bull ? "top " : "bottom "))+FmtPx(lvl);
         if(!hit)
            txt+=" ("+FmtPts(MathAbs(px-lvl))+" pts away)";
        }
      return hit;
     }
   //--- 2 = enter now, 1 = price triggered but an engine filter refused (candidate rejection), 0 = waiting.
   //--- Strings are only built when verbose (per-tick cost).
   int               CheckEntry(const int k,const double bid,const double ask,const double atr,const bool rejBar,
                                const bool verbose,string &txt)
     {
      txt="";
      int maxT=m_ctx.cfg.FvgMaxTradesPerZone;
      if(!IsAlive(m_zones[k].state) || m_zones[k].trades>=maxT)
        {
         if(verbose)
            txt=StateStr(m_zones[k].state)+", trades "+IntegerToString(m_zones[k].trades)+"/"+IntegerToString(maxT);
         return 0;
        }
      double dist=EntryDistance(k,bid,ask);
      double maxDist=m_ctx.cfg.FvgMaxDistanceAtr*atr;
      if(dist>maxDist)
        {
         if(verbose)
            txt="distance "+FmtPts(dist)+" > "+FmtPts(maxDist)+" pts ("+DoubleToString(m_ctx.cfg.FvgMaxDistanceAtr,2)+" ATR)";
         return 0;
        }
      bool bull=(m_zones[k].dir>0);
      double inv=InvalidLevel(k,atr);
      if(bull ? (bid<=inv) : (bid>=inv))
        {
         if(verbose)
            txt="bid "+FmtPx(bid)+" beyond invalidation "+FmtPx(inv)+" (candle close pending)";
         return 0;
        }
      if(!PriceTrigger(k,bid,ask,rejBar,verbose,txt))
         return 0;
      if(m_ctx.cfg.FvgBosRequired && !m_zones[k].structOk)
        {
         if(verbose)
            txt="BOS_REQUIRED: no "+StructModeStr()+" since B1 | "+txt;
         return 1;
        }
      return 2;
     }
   //--- REJECTION: true on the first evaluated tick after a refine-tf candle closed
   bool              RefineBarClosed(void)
     {
      datetime b1=m_ctx.pf.BarTime(RefTf(),1);
      if(b1<=0 || b1==m_lastRefBar)
         return false;
      m_lastRefBar=b1;
      return true;
     }

   //+---------------------------------------------------------------+
   //| SL / TP / signal (docs/03 2.4)                                |
   //+---------------------------------------------------------------+
   //--- next setup id of a zone. Ids already traded / burned (persisted ring) are skipped so the
   //--- trade counter survives restarts and consecutive-loss burns. "" when the zone is used up.
   string            SetupIdFor(const int k)
     {
      int maxT=m_ctx.cfg.FvgMaxTradesPerZone;
      while(m_zones[k].trades<maxT && WasTraded(m_zones[k].id+"-T"+IntegerToString(m_zones[k].trades+1)))
        {
         m_zones[k].trades++;
         Log(FTF_LOG_DEBUG,"zone "+m_zones[k].id+" setup T"+IntegerToString(m_zones[k].trades)+" already traded/burned (ring)");
        }
      if(m_zones[k].trades>=maxT)
         return "";
      return m_zones[k].id+"-T"+IntegerToString(m_zones[k].trades+1);
     }
   //--- LIQUIDITY: nearest swing beyond min R (closer swings skipped), capped at max R, else RR fallback
   double            CalcTp(const int dir,const double entry,const double slDist,const double atr,string &txt)
     {
      txt="";
      double sgn=(double)dir;
      if(m_ctx.cfg.FvgTpMode==FTF_TP_ATR)
        {
         double d=m_ctx.cfg.FvgTpAtrMult*atr;
         if(d>0.0)
           {
            txt="TP ATR x"+DoubleToString(m_ctx.cfg.FvgTpAtrMult,2);
            return entry+sgn*d;
           }
         txt="TP ATR x0 -> ";
        }
      else if(m_ctx.cfg.FvgTpMode==FTF_TP_LIQUIDITY)
        {
         double minR=m_ctx.cfg.FvgTpMinRR;
         double maxR=m_ctx.cfg.FvgTpMaxRR;
         double lvl=0.0;
         double fromPx=entry+sgn*minR*slDist;
         bool found=false;
         if(dir>0)
            found=m_struct.NearestSwingHighAbove(fromPx,lvl);
         else
            found=m_struct.NearestSwingLowBelow(fromPx,lvl);
         if(found && slDist>0.0)
           {
            double r=sgn*(lvl-entry)/slDist;
            if(r>maxR)
              {
               txt="TP LIQ swing "+FmtPx(lvl)+" "+DoubleToString(r,2)+"R capped at "+DoubleToString(maxR,2)+"R";
               return entry+sgn*maxR*slDist;
              }
            if(r>0.0 && r>=minR)
              {
               txt="TP LIQ swing "+FmtPx(lvl)+" ("+DoubleToString(r,2)+"R)";
               return lvl;
              }
           }
         txt="TP LIQ no swing in "+DoubleToString(minR,2)+".."+DoubleToString(maxR,2)+"R -> ";
        }
      txt+="TP RR "+DoubleToString(m_ctx.cfg.FvgTpRR,2)+"R";
      return entry+sgn*m_ctx.cfg.FvgTpRR*slDist;
     }
   string            SignalReason(const int k,const double atr,const string trigger,const string slMode,const double sl,
                                  const double slDist,const string tpTxt,const double tp,const double tpDist)
     {
      double gap=m_zones[k].top-m_zones[k].bottom;
      return "FVG "+EntryModeStr()+" "+(m_zones[k].dir>0 ? "BULL" : "BEAR")+" zone "+m_zones[k].id+" ["+
             FmtPx(m_zones[k].bottom)+".."+FmtPx(m_zones[k].top)+"] gap "+FmtPts(gap)+" pts ("+
             DoubleToString((atr>0.0 ? gap/atr : 0.0),2)+" ATR) | "+trigger+" | "+StateStr(m_zones[k].state)+" mit "+
             IntegerToString(m_zones[k].mitigations)+"/"+IntegerToString(m_ctx.cfg.FvgMaxMitigations)+" age "+
             IntegerToString(m_zones[k].ageBars)+" bars | struct "+StructModeStr()+" "+(m_zones[k].structOk ? "ok" : "no")+
             " | SL "+slMode+" "+FmtPx(sl)+" ("+FmtPts(slDist)+" pts) | "+tpTxt+" = "+FmtPx(tp)+" ("+FmtPts(tpDist)+
             " pts, "+DoubleToString((slDist>0.0 ? tpDist/slDist : 0.0),2)+"R) | ATR "+FmtPts(atr)+" pts";
     }
   bool              BuildSignal(const int k,const double atr,const string trigger,SSignal &s,string &why)
     {
      string setupId=SetupIdFor(k);
      if(StringLen(setupId)==0)
        {
         why="all "+IntegerToString(m_ctx.cfg.FvgMaxTradesPerZone)+" setup(s) of the zone already traded/burned";
         return false;
        }
      int dir=m_zones[k].dir;
      bool bull=(dir>0);
      double entry=(bull ? m_ctx.md.AskPrice() : m_ctx.md.BidPrice());
      double buf=MathMax(m_ctx.cfg.FvgSlBufSpreadMult*m_ctx.md.Spread(),m_ctx.cfg.FvgSlBufAtr*atr);
      bool swingSl=(m_ctx.cfg.FvgSlMode==FTF_FVGSL_SWING);
      double anchor=(swingSl ? m_zones[k].swingExtreme : (bull ? m_zones[k].bottom : m_zones[k].top));
      double sl=Norm(bull ? anchor-buf : anchor+buf);
      double slDist=(bull ? entry-sl : sl-entry);
      if(slDist<=0.0)
        {
         why="SL "+FmtPx(sl)+" on the wrong side of entry "+FmtPx(entry);
         return false;
        }
      string tpTxt="";
      double tp=Norm(CalcTp(dir,entry,slDist,atr,tpTxt));
      double tpDist=(bull ? tp-entry : entry-tp);
      if(tpDist<=0.0)
        {
         why="TP "+FmtPx(tp)+" on the wrong side of entry "+FmtPx(entry)+" ("+tpTxt+")";
         return false;
        }
      PrepareSignal(s,dir,setupId,TfText());
      s.sl=sl;
      s.tp=tp;
      s.invalidation=Norm(bull ? m_zones[k].bottom : m_zones[k].top);   // zone far edge (docs/09 7.13)
      s.atr=atr;
      s.structOk=m_zones[k].structOk;
      s.quality=Quality(k,atr);
      s.reason=SignalReason(k,atr,trigger,(swingSl ? "SWING" : "ZONE"),sl,slDist,tpTxt,tp,tpDist);
      return true;
     }

   //+---------------------------------------------------------------+
   //| evaluation plumbing                                           |
   //+---------------------------------------------------------------+
   bool              EnsureReady(void)
     {
      if(!m_scanned && !Scan())
        {
         m_status="waiting history";
         SetInfo("waiting: "+FTF_TfStr(m_ctx.cfg.FvgTimeframe)+" history / ATR not ready");
         return false;
        }
      if(m_atr<=0.0)
         m_atr=AtrAt(1);
      if(m_atr<=0.0)
        {
         SetInfo("waiting: ATR "+FTF_TfStr(m_ctx.cfg.FvgTimeframe)+" not ready");
         return false;
        }
      return true;
     }
   void              SortCandidates(int &cand[],double &candQ[],const int nc)
     {
      for(int a=1;a<nc;a++)
        {
         int ci=cand[a];
         double cq=candQ[a];
         int b=a-1;
         while(b>=0 && candQ[b]<cq)
           {
            cand[b+1]=cand[b];
            candQ[b+1]=candQ[b];
            b--;
           }
         cand[b+1]=ci;
         candQ[b+1]=cq;
        }
     }
   //--- candidate refused by an engine filter while price triggered: DEBUG, throttled by the logger
   void              LogRejected(const int k,const double bid,const double ask,const bool rejBar,const bool showInfo)
     {
      string txt="";
      CheckEntry(k,bid,ask,m_atr,rejBar,true,txt);
      LogThrottled(FTF_LOG_DEBUG,"rej."+m_zones[k].id,"candidate "+m_zones[k].id+" rejected: "+txt);
      if(showInfo)
         SetInfo("rejected: "+ShortId(k)+" "+txt);
     }
   //--- panel explanation of why nothing trades (refreshed at the panel cadence, not every tick)
   void              WaitInfo(const int nearest,const double bid,const double ask,const bool rejBar)
     {
      long now=m_ctx.md.NowMsc();
      if(now>=m_infoMsc && now-m_infoMsc<(long)m_ctx.cfg.PanelRefreshMs)
         return;
      m_infoMsc=now;
      if(nearest<0)
        {
         SetInfo("waiting: no tradable zone ("+IntegerToString(m_count)+" tracked)");
         return;
        }
      string txt="";
      CheckEntry(nearest,bid,ask,m_atr,rejBar,true,txt);
      SetInfo("waiting: "+ShortId(nearest)+" "+txt);
      LogThrottled(FTF_LOG_TRACE,"wait","waiting: "+m_zones[nearest].id+" "+txt);
     }
   //--- evaluates every live zone; returns the candidates sorted by quality (desc)
   int               CollectCandidates(const double bid,const double ask,const bool rejBar,int &cand[])
     {
      double candQ[];
      ArrayResize(cand,m_count);
      ArrayResize(candQ,m_count);
      int nc=0, nb=0, ns=0, nearest=-1, rejected=-1;
      double nearestD=DBL_MAX;
      string txt="";
      for(int k=0;k<m_count;k++)
        {
         if(!IsAlive(m_zones[k].state))
            continue;
         if(m_zones[k].dir>0)
            nb++;
         else
            ns++;
         int res=CheckEntry(k,bid,ask,m_atr,rejBar,false,txt);
         if(res==2)
           {
            cand[nc]=k;
            candQ[nc]=Quality(k,m_atr);
            nc++;
            continue;
           }
         if(res==1)
            rejected=k;
         double d=EntryDistance(k,bid,ask);
         if(m_zones[k].trades<m_ctx.cfg.FvgMaxTradesPerZone && d<nearestD)
           {
            nearestD=d;
            nearest=k;
           }
        }
      m_status="zones B/S "+IntegerToString(nb)+"/"+IntegerToString(ns);
      SortCandidates(cand,candQ,nc);
      if(rejected>=0)
         LogRejected(rejected,bid,ask,rejBar,(nc==0));
      else if(nc==0)
         WaitInfo(nearest,bid,ask,rejBar);
      return nc;
     }
   //--- one signal per zone (setup), all in the direction of the best candidate (never against itself)
   int               EmitSignals(SSignal &out[],const int startIndex,const int maxOut,const int &cand[],const int nc,
                                 const double bid,const double ask,const bool rejBar)
     {
      int n=0;
      int bestDir=m_zones[cand[0]].dir;
      for(int c=0;c<nc && n<maxOut && startIndex+n<ArraySize(out);c++)
        {
         int k=cand[c];
         if(m_zones[k].dir!=bestDir)
           {
            LogThrottled(FTF_LOG_DEBUG,"opp."+m_zones[k].id,"candidate "+m_zones[k].id+" skipped this tick: opposite to the better "+
                         FTF_DirStr(bestDir)+" candidate");
            continue;
           }
         string trig="";
         string why="";
         CheckEntry(k,bid,ask,m_atr,rejBar,true,trig);
         if(!BuildSignal(k,m_atr,trig,out[startIndex+n],why))
           {
            LogThrottled(FTF_LOG_DEBUG,"rej."+m_zones[k].id,"candidate "+m_zones[k].id+" rejected: "+why);
            SetInfo("rejected: "+ShortId(k)+" "+why);
            continue;
           }
         LogThrottled(FTF_LOG_INFO,"sig."+out[startIndex+n].setupId,"SIGNAL "+FTF_DirStr(out[startIndex+n].dir)+" "+
                      out[startIndex+n].setupId+" @ "+FmtPx(out[startIndex+n].price)+" SL "+FmtPx(out[startIndex+n].sl)+
                      " TP "+FmtPx(out[startIndex+n].tp)+" q "+DoubleToString(out[startIndex+n].quality,0)+" | "+
                      out[startIndex+n].reason);
         SetInfo("signal "+FTF_DirStr(out[startIndex+n].dir)+" "+out[startIndex+n].setupId);
         n++;
        }
      return n;
     }
   //--- exit rule rebuilt from pos.refLevel (= zone far edge at entry) when the zone is unknown
   //--- (restart, or dropped from memory)
   int               FallbackExit(STrackedPos &pos,string &detail)
     {
      if(pos.refLevel<=0.0 || CheckPointer(m_ctx.pf)==POINTER_INVALID || CheckPointer(m_ctx.md)==POINTER_INVALID)
         return FTF_EXIT_NONE;
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      double atr=(m_atr>0.0 ? m_atr : AtrAt(1));
      double buf=m_ctx.cfg.FvgInvalidBufAtr*atr;
      bool bull=(pos.dir==FTF_DIR_BUY);
      double lvl=(bull ? pos.refLevel-buf : pos.refLevel+buf);
      double px=m_ctx.md.BidPrice();
      string src="bid";
      if(m_ctx.cfg.FvgInvalidOnClose)
        {
         long closeMsc=((long)m_ctx.pf.BarTime(tf,1)+(long)FTF_TfSeconds(tf))*1000;
         if(closeMsc<pos.openMsc)
            return FTF_EXIT_NONE;        // that candle closed before the trade was opened
         px=m_ctx.pf.BarClose(tf,1);
         src=FTF_TfStr(tf)+" close";
        }
      if(bull ? (px>=lvl) : (px<=lvl))
         return FTF_EXIT_NONE;
      detail="zone of "+pos.setupId+" not tracked: "+src+" "+FmtPx(px)+(bull ? " < " : " > ")+"far edge "+
             FmtPx(pos.refLevel)+(bull ? " - " : " + ")+"buffer = "+FmtPx(lvl);
      return FTF_EXIT_FVG_INVALID;
     }
   void              DrawZone(const int k,const datetime tEnd)
     {
      bool alive=IsAlive(m_zones[k].state);
      bool bull=(m_zones[k].dir>0);
      color clr=clrDimGray;
      if(m_zones[k].state==FTF_ZS_INTACT)
         clr=(bull ? clrSeaGreen : clrIndianRed);
      else if(m_zones[k].state==FTF_ZS_MITIGATED)
         clr=(bull ? clrDarkSeaGreen : clrRosyBrown);
      datetime tTo=tEnd;
      if(tTo<=m_zones[k].t1)
         tTo=(datetime)((long)m_zones[k].t3+(long)FTF_TfSeconds(m_ctx.cfg.FvgTimeframe));
      string tip="FVG "+(bull ? "BULL " : "BEAR ")+StateStr(m_zones[k].state)+" "+m_zones[k].id+" | "+
                 FmtPx(m_zones[k].bottom)+" - "+FmtPx(m_zones[k].top)+" | CE "+FmtPx(m_zones[k].ce)+" | mit "+
                 IntegerToString(m_zones[k].mitigations)+" | trades "+IntegerToString(m_zones[k].trades)+" | age "+
                 IntegerToString(m_zones[k].ageBars)+" | struct "+(m_zones[k].structOk ? "ok" : "no");
      m_ctx.ui.DrawRect("FVG_"+m_zones[k].id,m_zones[k].t1,m_zones[k].top,tTo,m_zones[k].bottom,clr,alive,tip);
      m_ctx.ui.DrawSegment("FVGCE_"+m_zones[k].id,m_zones[k].t1,m_zones[k].ce,tTo,m_zones[k].ce,clr,STYLE_DOT,
                           "FVG CE "+FmtPx(m_zones[k].ce));
      m_zones[k].drawnState=m_zones[k].state;
     }
   void              LogConfig(void)
     {
      Log(FTF_LOG_INFO,"config: tf "+FTF_TfStr(m_ctx.cfg.FvgTimeframe)+" | scan "+IntegerToString(m_ctx.cfg.FvgScanBars)+
          " bars, max "+IntegerToString(m_ctx.cfg.FvgMaxZones)+" zones, age "+IntegerToString(m_ctx.cfg.FvgMaxAgeBars)+
          " bars, mitigations "+IntegerToString(m_ctx.cfg.FvgMaxMitigations)+" | gap >= "+DoubleToString(m_ctx.cfg.FvgMinGapAtr,2)+
          " ATR & "+DoubleToString(m_ctx.cfg.FvgMinGapSpreadMult,2)+" x spread | entry "+EntryModeStr()+" ("+TfText()+
          "), dist <= "+DoubleToString(m_ctx.cfg.FvgMaxDistanceAtr,2)+" ATR | BOS_REQUIRED "+
          (m_ctx.cfg.FvgBosRequired ? "yes" : "no")+" ("+StructModeStr()+") | invalidation buf "+
          DoubleToString(m_ctx.cfg.FvgInvalidBufAtr,2)+" ATR on "+(m_ctx.cfg.FvgInvalidOnClose ? "close" : "tick")+
          " | SL "+(m_ctx.cfg.FvgSlMode==FTF_FVGSL_SWING ? "SWING" : "ZONE")+" buf max("+
          DoubleToString(m_ctx.cfg.FvgSlBufSpreadMult,2)+" spread, "+DoubleToString(m_ctx.cfg.FvgSlBufAtr,2)+
          " ATR) | TP "+TpModeStr()+" (RR "+DoubleToString(m_ctx.cfg.FvgTpRR,2)+", "+DoubleToString(m_ctx.cfg.FvgTpMinRR,2)+".."+
          DoubleToString(m_ctx.cfg.FvgTpMaxRR,2)+"R) | trades/zone "+IntegerToString(m_ctx.cfg.FvgMaxTradesPerZone)+
          " | exit on invalidation "+(m_ctx.cfg.FvgExitOnInvalidation ? "yes" : "no"));
     }

public:
                     CEngineFVG(void)
     {
      m_id=FTF_ENG_FVG;
      m_code="FVG";
      m_name="FVG";
      m_count=0;
      m_atrId=-1;
      m_atr=0.0;
      m_scanned=false;
      m_dirty=true;
      m_lastBar1=0;
      m_lastRefBar=0;
      m_lastDrawBar=0;
      m_infoMsc=0;
      m_atrCacheN=0;
     }

   virtual bool      Init(CFtfContext *ctx)
     {
      if(!CEngineBase::Init(ctx))
         return false;
      m_count=0;
      ArrayResize(m_zones,0);
      m_atrId=-1;
      m_atr=0.0;
      m_scanned=false;
      m_dirty=true;
      m_lastBar1=0;
      m_lastRefBar=0;
      m_lastDrawBar=0;
      m_infoMsc=0;
      m_atrCacheN=0;
      if(!m_enabled || CheckPointer(m_ctx.pf)==POINTER_INVALID)
         return true;
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      m_atrId=m_ctx.pf.RegisterATR(tf,m_ctx.cfg.AtrPeriod);
      m_struct.Init(m_ctx.pf,tf,m_ctx.cfg.StructSwingBars,m_ctx.cfg.StructLookbackBars);
      m_lastRefBar=m_ctx.pf.BarTime(RefTf(),1);   // REJECTION never fires on a candle closed before start
      LogConfig();
      if(!Scan())
         Log(FTF_LOG_INFO,"initial scan deferred until "+FTF_TfStr(tf)+" history and ATR are available");
      return true;
     }

   //--- bar-based work only on the FVG timeframe (docs/03 section 0)
   virtual void      OnNewBar(const ENUM_TIMEFRAMES tf)
     {
      if(!m_enabled || CheckPointer(m_ctx)==POINTER_INVALID || tf!=m_ctx.cfg.FvgTimeframe)
         return;
      m_dirty=true;                       // live rectangles extend to the new bar
      if(!m_scanned)
        {
         Scan();
         return;
        }
      datetime bar1=m_ctx.pf.BarTime(tf,1);
      if(bar1==m_lastBar1)                // already processed (start-up scan or duplicate event)
         return;
      m_lastBar1=bar1;
      m_struct.Update();
      m_atr=AtrAt(1);
      BarUpdateZones();                   // existing zones first: the new zone starts at age 0
      DetectAt(1,false);
      EnforceMaxZones();
     }

   virtual int       Evaluate(SSignal &out[],const int startIndex,const int maxOut)
     {
      if(!m_enabled || CheckPointer(m_ctx)==POINTER_INVALID || !EnsureReady())
         return 0;
      double bid=m_ctx.md.BidPrice();
      double ask=m_ctx.md.AskPrice();
      if(bid<=0.0 || ask<=0.0)
         return 0;
      UpdateTicks(bid,m_ctx.md.MidPrice(),m_atr);
      bool rejBar=false;
      if(m_ctx.cfg.FvgEntryMode==FTF_FVG_REJECTION)
         rejBar=RefineBarClosed();
      int cand[];
      int nc=CollectCandidates(bid,ask,rejBar,cand);
      if(nc<=0 || maxOut<=0)
         return 0;
      return EmitSignals(out,startIndex,maxOut,cand,nc,bid,ask,rejBar);
     }

   //--- confirmation / retry: zone still INTACT/MITIGATED and price still satisfies the entry rule
   virtual bool      IsStillValid(const SSignal &sig,string &why)
     {
      why="";
      if(!m_enabled || !m_scanned || m_atr<=0.0)
        {
         why="FVG engine not ready";
         return false;
        }
      int k=ZoneOfSetup(sig.setupId);
      if(k<0)
        {
         why="zone of "+sig.setupId+" no longer tracked";
         return false;
        }
      if(WasTraded(sig.setupId))
        {
         why="setup "+sig.setupId+" already traded";
         return false;
        }
      string txt="";
      int res=CheckEntry(k,m_ctx.md.BidPrice(),m_ctx.md.AskPrice(),m_atr,true,true,txt);
      if(res!=2)
        {
         why="zone "+m_zones[k].id+": "+txt;
         return false;
        }
      return true;
     }

   //--- FVG_INVALIDATED when the zone of an open FVG trade is invalidated (docs/03 2.4)
   virtual int       CheckExit(STrackedPos &pos,string &detail)
     {
      detail="";
      if(pos.engine!=FTF_ENG_FVG || CheckPointer(m_ctx)==POINTER_INVALID || !m_ctx.cfg.FvgExitOnInvalidation)
         return FTF_EXIT_NONE;
      int k=ZoneOfSetup(pos.setupId);
      if(k<0)
         return FallbackExit(pos,detail);
      if(m_zones[k].state!=FTF_ZS_INVALIDATED)
         return FTF_EXIT_NONE;
      detail="zone "+m_zones[k].id+" invalidated at "+TimeToString(m_zones[k].endTime,TIME_DATE|TIME_MINUTES)+
             " (far edge "+FmtPx(m_zones[k].dir>0 ? m_zones[k].bottom : m_zones[k].top)+")";
      return FTF_EXIT_FVG_INVALID;
     }

   virtual void      OnEntry(const SSignal &sig,const STrackedPos &pos)
     {
      int k=ZoneOfSetup(sig.setupId);
      if(k>=0)
        {
         int tn=(int)StringToInteger(StringSubstr(sig.setupId,StringLen(m_zones[k].id)+2));
         int nt=m_zones[k].trades+1;
         if(tn>nt)
            nt=tn;
         m_zones[k].trades=nt;
         m_dirty=true;
         Log(FTF_LOG_INFO,"zone "+m_zones[k].id+" trade #"+IntegerToString(nt)+"/"+
             IntegerToString(m_ctx.cfg.FvgMaxTradesPerZone)+" opened, ticket "+IntegerToString((long)pos.ticket)+" | "+
             StateStr(m_zones[k].state)+", mit "+IntegerToString(m_zones[k].mitigations));
        }
      CEngineBase::OnEntry(sig,pos);
     }

   //--- redraw only on a new FVG bar or a zone change (dirty flag); frozen zones drawn once
   virtual void      Draw(void)
     {
      if(!m_enabled || CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_ctx.ui)==POINTER_INVALID)
         return;
      if(!m_ctx.ui.Enabled() || !m_ctx.cfg.DrawZones || !m_scanned)
         return;
      ENUM_TIMEFRAMES tf=m_ctx.cfg.FvgTimeframe;
      datetime bar0=m_ctx.pf.BarTime(tf,0);
      if(bar0!=m_lastDrawBar)
        {
         m_lastDrawBar=bar0;
         m_dirty=true;
        }
      if(!m_dirty)
         return;
      m_dirty=false;
      datetime tLive=(datetime)((long)bar0+(long)FTF_TfSeconds(tf));   // current bar + 1 bar
      for(int k=0;k<m_count;k++)
        {
         bool alive=IsAlive(m_zones[k].state);
         if(!alive && m_zones[k].drawnState==m_zones[k].state)
            continue;                     // frozen drawing already up to date
         DrawZone(k,(alive ? tLive : m_zones[k].endTime));
        }
      m_ctx.ui.Redraw();
     }

   virtual string    StatusLine(void)
     {
      string head="["+StringSubstr(m_code,0,1)+"] "+m_name+" "+(m_enabled ? "ON " : "OFF");
      if(!m_enabled || CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_ctx.md)==POINTER_INVALID)
         return head;
      int nb=0, ns=0, best=-1;
      double bestD=DBL_MAX;
      double mid=m_ctx.md.MidPrice();
      for(int k=0;k<m_count;k++)
        {
         if(!IsAlive(m_zones[k].state))
            continue;
         if(m_zones[k].dir>0)
            nb++;
         else
            ns++;
         double d=BandDistance(k,mid);
         if(d<bestD)
           {
            bestD=d;
            best=k;
           }
        }
      string s=head+" | zones B/S "+IntegerToString(nb)+"/"+IntegerToString(ns);
      if(best>=0)
         s+=" | nearest "+ShortId(best)+" "+FmtPts(bestD)+" pts "+StateStr(m_zones[best].state)+" mit "+
            IntegerToString(m_zones[best].mitigations)+" T"+IntegerToString(m_zones[best].trades);
      if(StringLen(m_lastInfo)>0)
         s+=" | "+m_lastInfo;
      return s;
     }
  };

#endif // FTF_ENGINE_FVG_MQH
