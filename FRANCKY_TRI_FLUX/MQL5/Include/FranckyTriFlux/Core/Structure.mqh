//+------------------------------------------------------------------+
//|                                                    Structure.mqh |
//|  CStructure - fractal swing highs / lows on ONE timeframe, used  |
//|  by the FVG engine for BOS / CHoCH confirmation (docs/03 2.3)    |
//|  and liquidity targets (docs/03 2.4 TP LIQUIDITY).               |
//|  Swing high at closed bar i (1+swingBars .. lookback):           |
//|    High(i) >  High(i+k)  (older bars)  for k = 1..swingBars      |
//|    High(i) >= High(i-k)  (newer bars)  for k = 1..swingBars      |
//|  Swing low symmetric. Arrays are stored most recent first.       |
//|  docs/09 section 7.10. Shared Core: identical in MQL5 and MQL4.  |
//+------------------------------------------------------------------+
#ifndef FTF_STRUCTURE_MQH
#define FTF_STRUCTURE_MQH

#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>
#include <FranckyTriFlux\Platform\Platform.mqh>

#define FTF_STRUCT_MAX_LOOKBACK   300   // docs/09 7.10: lookback <= 300 bars (speed)
#define FTF_STRUCT_MAX_SWING      20    // TUNABLE (not an input yet) - max fractal strength (bars each side)

class CStructure
  {
private:
   CPlatform        *m_pf;
   CLogger          *m_log;          // optional (SetLogger) - TRACE only
   ENUM_TIMEFRAMES   m_tf;
   int               m_swingBars;
   int               m_lookback;
   //--- swings, index 0 = most recent
   double            m_hiPrice[];
   datetime          m_hiTime[];
   int               m_hiCount;
   double            m_loPrice[];
   datetime          m_loTime[];
   int               m_loCount;
   //--- closed bars cached at the last scan, index = shift (0 unused)
   double            m_h[];
   double            m_l[];
   double            m_c[];
   datetime          m_t[];
   int               m_maxShift;     // highest cached shift
   datetime          m_scanBar;      // time of bar 1 at the last scan

   bool              Valid(const double v) { return (v>0.0 && v!=EMPTY_VALUE && MathIsValidNumber(v)); }

   void              Trace(const string msg)
     {
      if(CheckPointer(m_log)!=POINTER_INVALID && m_log.IsEnabled(FTF_LOG_TRACE))
         m_log.Trace("STR",msg);
     }

   //--- caches High/Low/Close/Time of shifts 1..m_maxShift (bars that cannot change any more)
   void              LoadBars(void)
     {
      int avail=m_pf.BarsCount(m_tf);
      int need=m_lookback+m_swingBars+1;
      m_maxShift=need;
      if(m_maxShift>avail-1)
         m_maxShift=avail-1;
      if(m_maxShift<1)
        {
         m_maxShift=0;
         return;
        }
      ArrayResize(m_h,m_maxShift+1);
      ArrayResize(m_l,m_maxShift+1);
      ArrayResize(m_c,m_maxShift+1);
      ArrayResize(m_t,m_maxShift+1);
      m_h[0]=0.0; m_l[0]=0.0; m_c[0]=0.0; m_t[0]=0;
      for(int s=1;s<=m_maxShift;s++)
        {
         m_h[s]=m_pf.BarHigh(m_tf,s);
         m_l[s]=m_pf.BarLow(m_tf,s);
         m_c[s]=m_pf.BarClose(m_tf,s);
         m_t[s]=m_pf.BarTime(m_tf,s);
        }
     }

   //--- fractal tests (caller guarantees 1 <= i-swingBars and i+swingBars <= m_maxShift)
   bool              IsSwingHigh(const int i)
     {
      double v=m_h[i];
      if(!Valid(v))
         return false;
      for(int k=1;k<=m_swingBars;k++)
        {
         if(!(v>m_h[i+k]))      // strictly above the older bars
            return false;
         if(!(v>=m_h[i-k]))     // at least equal to the newer bars
            return false;
        }
      return true;
     }

   bool              IsSwingLow(const int i)
     {
      double v=m_l[i];
      if(!Valid(v))
         return false;
      for(int k=1;k<=m_swingBars;k++)
        {
         if(!(v<m_l[i+k]))
            return false;
         if(!(v<=m_l[i-k]))
            return false;
        }
      return true;
     }

   void              PushHigh(const double price,const datetime t)
     {
      if(m_hiCount>=ArraySize(m_hiPrice))
        {
         ArrayResize(m_hiPrice,m_hiCount+16);
         ArrayResize(m_hiTime,m_hiCount+16);
        }
      m_hiPrice[m_hiCount]=price;
      m_hiTime[m_hiCount]=t;
      m_hiCount++;
     }

   void              PushLow(const double price,const datetime t)
     {
      if(m_loCount>=ArraySize(m_loPrice))
        {
         ArrayResize(m_loPrice,m_loCount+16);
         ArrayResize(m_loTime,m_loCount+16);
        }
      m_loPrice[m_loCount]=price;
      m_loTime[m_loCount]=t;
      m_loCount++;
     }

   //--- nth (0 = most recent) swing high / low formed strictly before fromTime, -1 if none
   int               HighIndexBefore(const datetime fromTime,const int nth)
     {
      int cnt=0;
      for(int i=0;i<m_hiCount;i++)
        {
         if(m_hiTime[i]>=fromTime)
            continue;
         if(cnt==nth)
            return i;
         cnt++;
        }
      return -1;
     }

   int               LowIndexBefore(const datetime fromTime,const int nth)
     {
      int cnt=0;
      for(int i=0;i<m_loCount;i++)
        {
         if(m_loTime[i]>=fromTime)
            continue;
         if(cnt==nth)
            return i;
         cnt++;
        }
      return -1;
     }

   //--- any closed bar with time >= fromTime closing beyond the level (BUY: above, SELL: below)
   bool              CloseBeyond(const int dir,const double level,const datetime fromTime)
     {
      for(int s=1;s<=m_maxShift;s++)
        {
         if(m_t[s]<=0 || m_t[s]<fromTime)
            break;
         if(!Valid(m_c[s]))
            continue;
         if(dir==FTF_DIR_BUY && m_c[s]>level)
            return true;
         if(dir==FTF_DIR_SELL && m_c[s]<level)
            return true;
        }
      return false;
     }

   //--- prior structure from the last two swing highs and lows before fromTime (+1 up, -1 down, 0 mixed)
   int               TrendBefore(const datetime fromTime)
     {
      int h1=HighIndexBefore(fromTime,0);
      int h2=HighIndexBefore(fromTime,1);
      int l1=LowIndexBefore(fromTime,0);
      int l2=LowIndexBefore(fromTime,1);
      if(h1<0 || h2<0 || l1<0 || l2<0)
         return 0;
      if(m_hiPrice[h1]>m_hiPrice[h2] && m_loPrice[l1]>m_loPrice[l2])
         return 1;
      if(m_hiPrice[h1]<m_hiPrice[h2] && m_loPrice[l1]<m_loPrice[l2])
         return -1;
      return 0;
     }

   //--- full rescan of the closed bars 1+swingBars .. lookback (most recent swing first)
   void              Scan(void)
     {
      m_hiCount=0;
      m_loCount=0;
      if(CheckPointer(m_pf)==POINTER_INVALID)
         return;
      LoadBars();
      m_scanBar=(m_maxShift>=1 ? m_t[1] : m_pf.BarTime(m_tf,1));
      int last=m_lookback;
      if(last>m_maxShift-m_swingBars)
         last=m_maxShift-m_swingBars;
      for(int i=1+m_swingBars;i<=last;i++)
        {
         if(IsSwingHigh(i))
            PushHigh(m_h[i],m_t[i]);
         if(IsSwingLow(i))
            PushLow(m_l[i],m_t[i]);
        }
      if(CheckPointer(m_log)!=POINTER_INVALID && m_log.IsEnabled(FTF_LOG_TRACE))
         Trace(FTF_TfStr(m_tf)+" structure scan @"+FTF_TimeStr(m_scanBar)+": "+IntegerToString(m_maxShift)+
               " bars, "+IntegerToString(m_hiCount)+" swing highs (last "+(m_hiCount>0 ? DoubleToString(m_hiPrice[0],8) : "-")+
               "), "+IntegerToString(m_loCount)+" swing lows (last "+(m_loCount>0 ? DoubleToString(m_loPrice[0],8) : "-")+
               "), structure "+IntegerToString(TrendBefore(m_scanBar+1)));
     }

   //--- lazy rescan when a new bar of the timeframe closed since the last scan
   void              EnsureFresh(void)
     {
      if(CheckPointer(m_pf)==POINTER_INVALID)
         return;
      datetime t=m_pf.BarTime(m_tf,1);
      if(t>0 && t!=m_scanBar)
         Scan();
     }

public:
                     CStructure(void)
     {
      m_pf=NULL; m_log=NULL; m_tf=PERIOD_M5; m_swingBars=3; m_lookback=120;
      m_hiCount=0; m_loCount=0; m_maxShift=0; m_scanBar=0;
     }

   //--- swingBars clamped to 1..FTF_STRUCT_MAX_SWING, lookback to (2*swingBars+3)..FTF_STRUCT_MAX_LOOKBACK
   void              Init(CPlatform *pf,const ENUM_TIMEFRAMES tf,const int swingBars,const int lookback)
     {
      m_pf=pf;
      m_tf=tf;
      m_swingBars=swingBars;
      if(m_swingBars<1)
         m_swingBars=1;
      if(m_swingBars>FTF_STRUCT_MAX_SWING)
         m_swingBars=FTF_STRUCT_MAX_SWING;
      m_lookback=lookback;
      if(m_lookback>FTF_STRUCT_MAX_LOOKBACK)
         m_lookback=FTF_STRUCT_MAX_LOOKBACK;
      if(m_lookback<2*m_swingBars+3)
         m_lookback=2*m_swingBars+3;
      ArrayResize(m_hiPrice,32);
      ArrayResize(m_hiTime,32);
      ArrayResize(m_loPrice,32);
      ArrayResize(m_loTime,32);
      m_hiCount=0; m_loCount=0; m_maxShift=0; m_scanBar=0;
      if(CheckPointer(m_pf)!=POINTER_INVALID)
         Scan();
     }

   //--- extra: optional logger (TRACE of each scan). Call before or after Init.
   void              SetLogger(CLogger *logger) { m_log=logger; }

   //--- rescans the closed bars (call on each new bar of tf; queries also rescan lazily)
   void              Update(void)
     {
      Scan();
     }

   //--- lowest swing high strictly above price (closest buy-side liquidity)
   bool              NearestSwingHighAbove(const double price,double &level)
     {
      EnsureFresh();
      level=0.0;
      bool found=false;
      for(int i=0;i<m_hiCount;i++)
        {
         double v=m_hiPrice[i];
         if(v>price && (!found || v<level))
           {
            level=v;
            found=true;
           }
        }
      return found;
     }

   //--- highest swing low strictly below price (closest sell-side liquidity)
   bool              NearestSwingLowBelow(const double price,double &level)
     {
      EnsureFresh();
      level=0.0;
      bool found=false;
      for(int i=0;i<m_loCount;i++)
        {
         double v=m_loPrice[i];
         if(v<price && (!found || v>level))
           {
            level=v;
            found=true;
           }
        }
      return found;
     }

   //--- BOS: a closed bar at/after fromTime closes beyond the most recent swing formed before fromTime
   //--- (BUY: close > swing high, SELL: close < swing low) - docs/03 2.3
   bool              HasBos(const int dir,const datetime fromTime)
     {
      EnsureFresh();
      int k=-1;
      double level=0.0;
      if(dir==FTF_DIR_BUY)
        {
         k=HighIndexBefore(fromTime,0);
         if(k<0)
            return false;
         level=m_hiPrice[k];
        }
      else if(dir==FTF_DIR_SELL)
        {
         k=LowIndexBefore(fromTime,0);
         if(k<0)
            return false;
         level=m_loPrice[k];
        }
      else
         return false;
      return CloseBeyond(dir,level,fromTime);
     }

   //--- extra: prior structure from the last two swing highs and lows before fromTime
   //--- +1 = higher highs + higher lows, -1 = lower highs + lower lows, 0 = undefined / mixed
   int               PriorTrend(const datetime fromTime)
     {
      EnsureFresh();
      return TrendBefore(fromTime);
     }

   //--- CHoCH: BOS against the prior structure direction (BUY after a down structure, SELL after up)
   bool              HasChoch(const int dir,const datetime fromTime)
     {
      EnsureFresh();
      int tr=TrendBefore(fromTime);
      if(dir==FTF_DIR_BUY)
         return (tr<0 && HasBos(FTF_DIR_BUY,fromTime));
      if(dir==FTF_DIR_SELL)
         return (tr>0 && HasBos(FTF_DIR_SELL,fromTime));
      return false;
     }

   int               SwingHighs(void) { return m_hiCount; }
   int               SwingLows(void)  { return m_loCount; }

   //--- extra: i-th swing (0 = most recent); false if out of range
   bool              SwingHighAt(const int i,double &price,datetime &t)
     {
      price=0.0;
      t=0;
      if(i<0 || i>=m_hiCount)
         return false;
      price=m_hiPrice[i];
      t=m_hiTime[i];
      return true;
     }

   bool              SwingLowAt(const int i,double &price,datetime &t)
     {
      price=0.0;
      t=0;
      if(i<0 || i>=m_loCount)
         return false;
      price=m_loPrice[i];
      t=m_loTime[i];
      return true;
     }

   //--- extra: timeframe of this structure
   ENUM_TIMEFRAMES   Timeframe(void)  { return m_tf; }
  };

#endif // FTF_STRUCTURE_MQH
