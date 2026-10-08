//+------------------------------------------------------------------+
//|                                                   TickBuffer.mqh |
//|  CTickBuffer - fixed-capacity ring buffer of ticks (docs/09 7.7).|
//|  Index 0 = newest tick. Parallel arrays (no struct arrays):      |
//|  m_msc[] m_bid[] m_ask[] m_dir[]; capacity is a power of two.    |
//|  Feeds the Momentum engine measurements of docs/03 section 1.1:  |
//|  tick direction, bullish ratio, velocity (TICKS / PRICE_PATH),   |
//|  reference median, acceleration, micro-range, median spread.     |
//|  Called on every tick: no allocation per call (fixed scratch     |
//|  arrays, grow-only spread scratch, allocation-free median).      |
//|  Shared Core: identical in the MQL5 and MQL4 trees.              |
//+------------------------------------------------------------------+
#ifndef FTF_TICK_BUFFER_MQH
#define FTF_TICK_BUFFER_MQH

#include <FranckyTriFlux\Core\Types.mqh>
#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>

#define FTF_TB_MIN_CAPACITY   64        // TUNABLE (not an input yet) - smallest ring size (power of two)
#define FTF_TB_MAX_CAPACITY   1048576   // TUNABLE (not an input yet) - largest ring size (2^20 ticks, ~28 MB)
#define FTF_TB_MAX_BUCKETS    60        // velocity reference buckets cap (refMs / winMs), docs/09 7.7
#define FTF_TB_SCRATCH        64        // fixed scratch size, must be >= FTF_TB_MAX_BUCKETS + 1
#define FTF_TB_PRICE_EPS      1e-10     // TUNABLE (not an input yet) - bid change below this = unchanged tick (dir 0)
#define FTF_TB_TICK_FLOOR     1.0       // velocity floor for the TICKS metric (1 tick, docs/03 1.1)
#define FTF_TB_PATH_FLOOR     1e-12     // default velocity floor for PRICE_PATH (price units; SetPathFloor(point) = 1 point)
#define FTF_TB_SRC            "TBUF"    // log source tag

class CTickBuffer
  {
private:
   long              m_msc[];          // server ms (monotonic non-decreasing, see Add)
   double            m_bid[];
   double            m_ask[];
   int               m_dir[];          // +1 / -1 / 0 versus the previous bid
   int               m_cap;            // capacity (power of two), 0 before Init
   int               m_mask;           // m_cap - 1
   int               m_head;           // next write position
   int               m_count;          // stored ticks (<= m_cap)
   //--- continuity across trims / overwrites
   bool              m_hasPrev;        // a previous bid exists -> direction defined
   double            m_prevBid;        // bid of the newest tick ever added
   long              m_prevMsc;        // msc of the newest tick ever added
   bool              m_oldestUndef;    // the oldest stored tick is the very first tick (dir undefined)
   long              m_coverFromMsc;   // history is complete for msc > this (first tick or newest evicted tick)
   //--- diagnostics
   long              m_added;          // ticks stored since Init/Clear
   long              m_clamped;        // ticks whose msc went backwards (clamped to the previous msc)
   long              m_skipped;        // invalid ticks ignored (bid <= 0)
   long              m_evicted;        // ticks dropped (overwrite or trim)
   bool              m_velCovered;     // velocity reference history complete at the last Velocity() call
   bool              m_velLogged;      // first "history complete" INFO line already written
   //--- velocity / median scratch (fixed size, no allocation per tick)
   double            m_pathFloor;      // PRICE_PATH floor in price units
   double            m_tmp[FTF_TB_SCRATCH];   // velocity buckets 0..nb
   double            m_sel[FTF_TB_SCRATCH];   // reference buckets 1..nb copied for the median
   double            m_spr[];                 // MedianSpread scratch (grow-only)
   //--- optional logger (SetLogger)
   CLogger          *m_log;
   bool              m_hasLog;
   int               m_throttleMs;

   //--- ring position of logical index i (0 = newest). Valid for 0 <= i < m_cap.
   int               Pos(const int i)
     {
      int p=m_head-1-i;
      if(p<0)
         p+=m_cap;
      return p;
     }

   //--- k-th smallest (0-based) of a[0..n-1]: Wirth/Hoare selection, O(n), reorders a[] in place
   double            KthSmallest(double &a[],const int n,const int k)
     {
      int l=0;
      int r=n-1;
      while(l<r)
        {
         double x=a[k];
         int i=l;
         int j=r;
         do
           {
            while(a[i]<x)
               i++;
            while(x<a[j])
               j--;
            if(i<=j)
              {
               double w=a[i];
               a[i]=a[j];
               a[j]=w;
               i++;
               j--;
              }
           }
         while(i<=j);
         if(j<k)
            l=i;
         if(k<i)
            r=j;
        }
      return a[k];
     }

   //--- median of a[0..n-1] (same definition as FTF_Median: mean of the two middle values when n
   //--- is even) but allocation-free; a[] is reordered. n<=0 -> 0
   double            MedianInPlace(double &a[],const int n)
     {
      if(n<=0)
         return 0.0;
      int h=n/2;
      double upper=KthSmallest(a,n,h);
      if((n%2)==1)
         return upper;
      double lower=KthSmallest(a,n,h-1);
      return (lower+upper)*0.5;
     }

   void              LogThrottled(const int level,const string key,const string msg)
     {
      if(m_hasLog)
         m_log.Throttled(level,FTF_TB_SRC+"."+key,m_throttleMs,FTF_TB_SRC,msg);
     }

   //--- empties the buffer (capacity, logger and path floor kept)
   void              ResetState(void)
     {
      m_head=0;
      m_count=0;
      m_hasPrev=false;
      m_prevBid=0.0;
      m_prevMsc=0;
      m_oldestUndef=false;
      m_coverFromMsc=0;
      m_added=0;
      m_clamped=0;
      m_skipped=0;
      m_evicted=0;
      m_velCovered=false;
      m_velLogged=false;
      for(int k=0;k<FTF_TB_SCRATCH;k++)
        {
         m_tmp[k]=0.0;
         m_sel[k]=0.0;
        }
     }

public:
                     CTickBuffer(void)
     {
      m_cap=0;
      m_mask=0;
      m_log=NULL;
      m_hasLog=false;
      m_throttleMs=5000;
      m_pathFloor=FTF_TB_PATH_FLOOR;
      ResetState();
     }

   //--- extra: optional logger (call before Init to get the capacity line). throttleMs = cfg.LogThrottleMs
   void              SetLogger(CLogger *logger,const int throttleMs)
     {
      m_log=logger;
      m_hasLog=(CheckPointer(m_log)!=POINTER_INVALID);
      m_throttleMs=(throttleMs>0 ? throttleMs : 0);
     }

   //--- extra: PRICE_PATH velocity floor in price units (docs/03 1.1: 1 point). Default 1e-12.
   void              SetPathFloor(const double priceFloor)
     {
      m_pathFloor=(priceFloor>0.0 ? priceFloor : FTF_TB_PATH_FLOOR);
     }

   //--- extra: forget every tick (capacity kept)
   void              Clear(void)
     {
      ResetState();
      if(m_hasLog)
         m_log.Debug(FTF_TB_SRC,"tick buffer cleared (capacity "+IntegerToString(m_cap)+")");
     }

   //--- docs/09 7.7: capacity rounded up to a power of two in [FTF_TB_MIN_CAPACITY, FTF_TB_MAX_CAPACITY]
   bool              Init(const int capacityPow2)
     {
      int want=capacityPow2;
      if(want<FTF_TB_MIN_CAPACITY)
         want=FTF_TB_MIN_CAPACITY;
      if(want>FTF_TB_MAX_CAPACITY)
         want=FTF_TB_MAX_CAPACITY;
      int cap=FTF_TB_MIN_CAPACITY;
      while(cap<want)
         cap*=2;
      bool ok=(ArrayResize(m_msc,cap)==cap);
      ok=(ok && ArrayResize(m_bid,cap)==cap);
      ok=(ok && ArrayResize(m_ask,cap)==cap);
      ok=(ok && ArrayResize(m_dir,cap)==cap);
      if(!ok)
        {
         m_cap=0;
         m_mask=0;
         ResetState();
         if(m_hasLog)
            m_log.Error(FTF_TB_SRC,"tick buffer allocation failed for "+IntegerToString(cap)+" ticks - tick engines stay cold");
         return false;
        }
      m_cap=cap;
      m_mask=cap-1;
      ResetState();
      if(m_hasLog)
         m_log.Info(FTF_TB_SRC,"tick ring buffer ready: capacity "+IntegerToString(m_cap)+" ticks (requested "+
                    IntegerToString(capacityPow2)+", ~"+IntegerToString((long)m_cap*28/1024)+" KB)");
      return true;
     }

   //--- docs/09 7.7: stores a tick; its direction is computed vs the previous bid (docs/03 1.1:
   //--- +1 bid up, -1 bid down, 0 unchanged). The very first tick has dir 0 and is excluded by UpRatio.
   //--- msc is kept monotonic (backward stamps clamped) so every backward scan can stop early.
   void              Add(const STick &t)
     {
      if(m_cap<=0)
         return;
      if(t.bid<=0.0)
        {
         m_skipped++;
         LogThrottled(FTF_LOG_DEBUG,"skip","invalid tick ignored (bid "+DoubleToString(t.bid,8)+" at "+
                      FTF_TimeMscStr(t.msc)+"), "+IntegerToString(m_skipped)+" so far");
         return;
        }
      long msc=t.msc;
      if(m_added>0 && msc<m_prevMsc)
        {
         m_clamped++;
         LogThrottled(FTF_LOG_DEBUG,"clamp","tick time went backwards by "+IntegerToString(m_prevMsc-msc)+
                      " ms -> clamped to previous msc ("+IntegerToString(m_clamped)+" so far)");
         msc=m_prevMsc;
        }
      int d=0;
      if(m_hasPrev)
        {
         double delta=t.bid-m_prevBid;
         if(delta>FTF_TB_PRICE_EPS)
            d=1;
         else
            if(delta<(-FTF_TB_PRICE_EPS))
               d=-1;
        }
      if(m_count==m_cap)
        {
         //--- full: the slot at m_head holds the oldest tick, overwritten now
         m_coverFromMsc=m_msc[m_head];
         m_oldestUndef=false;
         m_evicted++;
        }
      else
         m_count++;
      if(m_added==0)
        {
         m_coverFromMsc=msc;
         m_oldestUndef=true;
        }
      m_msc[m_head]=msc;
      m_bid[m_head]=t.bid;
      m_ask[m_head]=(t.ask>0.0 ? t.ask : t.bid);
      m_dir[m_head]=d;
      m_head=(m_head+1)&m_mask;
      m_hasPrev=true;
      m_prevBid=t.bid;
      m_prevMsc=msc;
      m_added++;
     }

   int               Count(void)    { return m_count; }
   int               Capacity(void) { return m_cap; }          // extra
   long              Added(void)    { return m_added; }        // extra: ticks stored since Init/Clear

   long              LastMsc(void)
     {
      if(m_count<=0)
         return 0;
      return m_msc[Pos(0)];
     }

   //--- extra: newest msc - oldest msc of the stored ticks (0 when fewer than 2)
   long              SpanMs(void)
     {
      if(m_count<2)
         return 0;
      return m_msc[Pos(0)]-m_msc[Pos(m_count-1)];
     }

   bool              At(const int i,STick &t)
     {
      if(i<0 || i>=m_count)
        {
         t.Reset();
         return false;
        }
      int p=Pos(i);
      t.msc=m_msc[p];
      t.bid=m_bid[p];
      t.ask=m_ask[p];
      t.dir=m_dir[p];
      return true;
     }

   double            BidAt(const int i)
     {
      if(i<0 || i>=m_count)
         return 0.0;
      return m_bid[Pos(i)];
     }

   //--- extra
   double            AskAt(const int i)
     {
      if(i<0 || i>=m_count)
         return 0.0;
      return m_ask[Pos(i)];
     }

   long              MscAt(const int i)
     {
      if(i<0 || i>=m_count)
         return 0;
      return m_msc[Pos(i)];
     }

   int               DirAt(const int i)
     {
      if(i<0 || i>=m_count)
         return 0;
      return m_dir[Pos(i)];
     }

   //--- docs/03 1.1 bullish tick ratio over the newest min(nTicks,count) ticks:
   //--- up/(up+down), or up/N when countFlat (flat ticks dilute). The very first stored tick has no
   //--- defined direction and is excluded. Returns -1 when no directional tick exists (docs/09 7.7).
   double            UpRatio(const int nTicks,const bool countFlat,int &up,int &down)
     {
      up=0;
      down=0;
      int n=(nTicks<m_count ? nTicks : m_count);
      if(n>0 && n==m_count && m_oldestUndef)
         n--;
      if(n<=0)
         return -1.0;
      int p=Pos(0);
      for(int i=0;i<n;i++)
        {
         int d=m_dir[p];
         if(d>0)
            up++;
         else
            if(d<0)
               down++;
         p=(p>0 ? p-1 : m_mask);
        }
      int directional=up+down;
      if(directional<=0)
         return -1.0;
      if(countFlat)
         return (double)up/(double)n;
      return (double)up/(double)directional;
     }

   //--- number of ticks with fromMscExcl < msc <= toMscIncl (newest-first scan, stops at fromMscExcl)
   int               CountBetween(const long fromMscExcl,const long toMscIncl)
     {
      if(m_count<=0 || toMscIncl<=fromMscExcl)
         return 0;
      int c=0;
      int p=Pos(0);
      for(int i=0;i<m_count;i++)
        {
         long msc=m_msc[p];
         if(msc<=fromMscExcl)
            break;
         if(msc<=toMscIncl)
            c++;
         p=(p>0 ? p-1 : m_mask);
        }
      return c;
     }

   //--- sum of |bid change| of the ticks inside (fromMscExcl, toMscIncl], each change measured vs the
   //--- previous stored tick (docs/03 1.1 PRICE_PATH, price units). The oldest stored tick adds nothing.
   double            PathBetween(const long fromMscExcl,const long toMscIncl)
     {
      if(m_count<2 || toMscIncl<=fromMscExcl)
         return 0.0;
      double sum=0.0;
      int p=Pos(0);
      for(int i=0;i<m_count-1;i++)
        {
         long msc=m_msc[p];
         if(msc<=fromMscExcl)
            break;
         int q=(p>0 ? p-1 : m_mask);
         if(msc<=toMscIncl)
            sum+=MathAbs(m_bid[p]-m_bid[q]);
         p=q;
        }
      return sum;
     }

private:
   //--- velocity history coverage state change: first completion INFO, later toggles DEBUG (throttled)
   void              LogCoverChange(const bool covered,const int nb,const int winMs,const long needMsc)
     {
      if(covered && !m_velLogged)
        {
         m_velLogged=true;
         m_log.Info(FTF_TB_SRC,"velocity reference history complete: "+IntegerToString(nb)+" x "+IntegerToString(winMs)+
                    " ms buckets + current, "+IntegerToString(m_count)+" ticks stored, span "+
                    DoubleToString((double)SpanMs()/1000.0,1)+" s");
         return;
        }
      LogThrottled(FTF_LOG_DEBUG,"cover","velocity reference history "+(covered ? "complete again" : "INCOMPLETE")+
                   " (complete from "+FTF_TimeMscStr(m_coverFromMsc)+", needed from "+FTF_TimeMscStr(needMsc)+")");
     }

public:
   //--- docs/03 1.1 + docs/09 7.7 velocity. Buckets of winMs ending at nowMsc: bucket k covers
   //--- (now-(k+1)*win, now-k*win]; nb = refMs/winMs reference buckets (cap FTF_TB_MAX_BUCKETS).
   //--- cur = bucket 0, prev = bucket 1, median = median(buckets 1..nb),
   //--- ratio = cur/max(median,floor), accel = (cur-prev)/max(prev,floor);
   //--- floor = 1 tick (TICKS) or m_pathFloor price units (PRICE_PATH; values in PRICE units, the caller
   //--- converts to points). Returns false when the history does not reach now-(nb+1)*win (values still set).
   bool              Velocity(const long nowMsc,const int winMs,const int refMs,const int metric,
                              double &cur,double &prev,double &median,double &ratio,double &accel)
     {
      cur=0.0;
      prev=0.0;
      median=0.0;
      ratio=0.0;
      accel=0.0;
      if(winMs<=0)
         return false;
      int nb=refMs/winMs;                   // integer division intended (30000/2000 = 15 buckets)
      if(nb<1)
         nb=1;
      if(nb>FTF_TB_MAX_BUCKETS)
         nb=FTF_TB_MAX_BUCKETS;
      for(int k=0;k<=nb;k++)
         m_tmp[k]=0.0;
      bool isPath=(metric==FTF_VEL_PRICE_PATH);
      long win=(long)winMs;
      long span=(long)(nb+1)*win;
      //--- one backward pass (newest first) until the tick is older than the oldest bucket
      int p=(m_count>0 ? Pos(0) : 0);
      for(int i=0;i<m_count;i++)
        {
         long msc=m_msc[p];
         int q=(p>0 ? p-1 : m_mask);
         if(msc<=nowMsc)
           {
            long age=nowMsc-msc;
            if(age>=span)
               break;
            int bk=(int)(age/win);
            if(!isPath)
               m_tmp[bk]+=1.0;
            else
               if(i+1<m_count)
                  m_tmp[bk]+=MathAbs(m_bid[p]-m_bid[q]);
           }
         p=q;
        }
      cur=m_tmp[0];
      prev=m_tmp[1];
      for(int j=0;j<nb;j++)
         m_sel[j]=m_tmp[j+1];
      median=MedianInPlace(m_sel,nb);
      double velFloor=(isPath ? m_pathFloor : FTF_TB_TICK_FLOOR);
      ratio=cur/MathMax(median,velFloor);
      accel=(cur-prev)/MathMax(prev,velFloor);
      bool covered=(m_added>0 && m_coverFromMsc<=nowMsc-span);
      if(covered!=m_velCovered && m_hasLog)
         LogCoverChange(covered,nb,winMs,nowMsc-span);
      m_velCovered=covered;
      if(m_hasLog && m_log.IsEnabled(FTF_LOG_TRACE))
         LogThrottled(FTF_LOG_TRACE,"vel","velocity "+(isPath ? "PATH" : "TICKS")+" cur "+DoubleToString(cur,6)+
                      " prev "+DoubleToString(prev,6)+" median "+DoubleToString(median,6)+" ratio "+
                      DoubleToString(ratio,3)+" accel "+DoubleToString(accel,3)+(covered ? "" : " (history incomplete)"));
      return covered;
     }

   //--- docs/03 1.1 micro-range: highest / lowest bid of ticks skipNewest .. skipNewest+nTicks-1
   //--- (skipNewest=1 -> the ticks BEFORE the current one). fromMsc = msc of the oldest tick used.
   bool              MicroRange(const int nTicks,const int skipNewest,double &hi,double &lo,long &fromMsc)
     {
      hi=0.0;
      lo=0.0;
      fromMsc=0;
      if(nTicks<=0 || skipNewest<0 || m_count<skipNewest+nTicks)
         return false;
      int p=Pos(skipNewest);
      hi=m_bid[p];
      lo=m_bid[p];
      for(int i=0;i<nTicks;i++)
        {
         double b=m_bid[p];
         if(b>hi)
            hi=b;
         if(b<lo)
            lo=b;
         fromMsc=m_msc[p];
         p=(p>0 ? p-1 : m_mask);
        }
      return true;
     }

   //--- median (ask - bid) of the newest min(nTicks,count) ticks, price units (0 if empty)
   double            MedianSpread(const int nTicks)
     {
      int n=(nTicks<m_count ? nTicks : m_count);
      if(n<=0)
         return 0.0;
      if(ArraySize(m_spr)<n)
        {
         if(ArrayResize(m_spr,n)!=n)
            return 0.0;
        }
      int p=Pos(0);
      for(int i=0;i<n;i++)
        {
         m_spr[i]=m_ask[p]-m_bid[p];
         p=(p>0 ? p-1 : m_mask);
        }
      return MedianInPlace(m_spr,n);
     }

   //--- extra: the stored history is complete for msc > CoverFromMsc() (first tick or newest dropped tick)
   long              CoverFromMsc(void) { return m_coverFromMsc; }

   //--- docs/09 7.7: drop the oldest ticks until the oldest kept msc >= minMsc (may empty the buffer;
   //--- direction continuity is kept through m_prevBid)
   void              TrimOlderThan(const long minMsc)
     {
      int dropped=0;
      while(m_count>0)
        {
         int p=Pos(m_count-1);
         if(m_msc[p]>=minMsc)
            break;
         m_coverFromMsc=m_msc[p];
         m_count--;
         dropped++;
        }
      if(dropped<=0)
         return;
      m_oldestUndef=false;
      m_evicted+=dropped;
      if(m_hasLog && m_log.IsEnabled(FTF_LOG_TRACE))
         LogThrottled(FTF_LOG_TRACE,"trim","trimmed "+IntegerToString(dropped)+" ticks older than "+
                      FTF_TimeMscStr(minMsc)+", "+IntegerToString(m_count)+" kept");
     }

   //--- extra: one-line diagnostic for logs / panel
   string            Describe(void)
     {
      return "ticks "+IntegerToString(m_count)+"/"+IntegerToString(m_cap)+" | span "+
             DoubleToString((double)SpanMs()/1000.0,1)+" s | added "+IntegerToString(m_added)+
             " | evicted "+IntegerToString(m_evicted)+" | clamped "+IntegerToString(m_clamped)+
             " | skipped "+IntegerToString(m_skipped);
     }
  };

#endif // FTF_TICK_BUFFER_MQH
