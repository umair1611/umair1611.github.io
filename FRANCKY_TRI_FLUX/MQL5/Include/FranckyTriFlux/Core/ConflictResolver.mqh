//+------------------------------------------------------------------+
//|                                             ConflictResolver.mqh |
//|  CConflictResolver - handles ONLY conflicts and duplicates        |
//|  (spec Table 5): opposite signals within a window -> all refused |
//|  and entries held a few hundred ms, then fresh re-evaluation     |
//|  (Table 12). It never turns several engines into a mandatory     |
//|  condition. Ordering by engine-internal quality (measurable rule).|
//|  CSignalConfirmer - parked signals for the "Confirm" mode delay. |
//|  docs/09 section 7.18                                            |
//+------------------------------------------------------------------+
#ifndef FTF_CONFLICT_RESOLVER_MQH
#define FTF_CONFLICT_RESOLVER_MQH

#include <FranckyTriFlux\Core\Context.mqh>

#define FTF_CONFIRM_MAX   16

class CConflictResolver
  {
private:
   CFtfContext      *m_ctx;
   int               m_lastDir[FTF_ENGINE_COUNT+1];   // last non-expired signal direction per engine
   long              m_lastMsc[FTF_ENGINE_COUNT+1];
   long              m_holdUntil;
   int               m_conflicts;
   string            m_lastConflict;

   void              Swap(SSignal &sigs[],int &reasons[],string &details[],const int a,const int b)
     {
      SSignal ts=sigs[a];
      sigs[a]=sigs[b];
      sigs[b]=ts;
      int tr=reasons[a];
      reasons[a]=reasons[b];
      reasons[b]=tr;
      string td=details[a];
      details[a]=details[b];
      details[b]=td;
     }

   bool              Before(const SSignal &x,const SSignal &y)
     {
      if(x.quality>y.quality+1e-9)
         return true;
      if(MathAbs(x.quality-y.quality)<=1e-9 && x.engine<y.engine)
         return true;
      return false;
     }

public:
                     CConflictResolver(void)
     {
      m_ctx=NULL;
      for(int e=0;e<=FTF_ENGINE_COUNT;e++)
        {
         m_lastDir[e]=FTF_DIR_NONE;
         m_lastMsc[e]=0;
        }
      m_holdUntil=0;
      m_conflicts=0;
      m_lastConflict="";
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(CheckPointer(m_ctx)==POINTER_INVALID)
         return false;
      m_ctx.logger.Info("CR","conflict window "+IntegerToString(m_ctx.cfg.ConflictWindowMs)+" ms, hold "+
                     IntegerToString(m_ctx.cfg.ConflictHoldMs)+" ms, hedging "+(m_ctx.cfg.AllowOppositeHedge ? "ON" : "OFF"));
      return true;
     }

   //--- reasons[i] = FTF_OK / FTF_REJ_SIGNAL_EXPIRED / FTF_REJ_CONFLICT; signals re-ordered (quality desc, engine asc)
   int               Resolve(SSignal &sigs[],const int n,int &reasons[],string &details[])
     {
      ArrayResize(reasons,n);
      ArrayResize(details,n);
      long now=m_ctx.NowMsc();
      int buys=0;
      int sells=0;
      for(int i=0;i<n;i++)
        {
         reasons[i]=FTF_OK;
         details[i]="";
         if(now>sigs[i].expiryMsc)
           {
            reasons[i]=FTF_REJ_SIGNAL_EXPIRED;
            details[i]="age "+IntegerToString(now-sigs[i].timeMsc)+" ms";
            continue;
           }
         if(sigs[i].dir==FTF_DIR_BUY)
            buys++;
         else
            if(sigs[i].dir==FTF_DIR_SELL)
               sells++;
        }
      //--- conflict: both directions in this cycle, or against another engine's recent opposite signal
      bool conflict=(buys>0 && sells>0);
      string why=(conflict ? "BUY and SELL in the same cycle" : "");
      int window=m_ctx.cfg.ConflictWindowMs;
      if(!conflict && window>0)
         for(int i=0;i<n && !conflict;i++)
           {
            if(reasons[i]!=FTF_OK)
               continue;
            for(int e=1;e<=FTF_ENGINE_COUNT;e++)
              {
               if(e==sigs[i].engine || m_lastDir[e]==FTF_DIR_NONE)
                  continue;
               if(m_lastDir[e]==-sigs[i].dir && now-m_lastMsc[e]>=0 && now-m_lastMsc[e]<=window)
                 {
                  conflict=true;
                  why=FTF_EngineCode(sigs[i].engine)+" "+FTF_DirStr(sigs[i].dir)+" vs "+FTF_EngineCode(e)+" "+
                      FTF_DirStr(m_lastDir[e])+" "+IntegerToString(now-m_lastMsc[e])+" ms ago";
                  break;
                 }
              }
           }
      //--- remember this cycle's signals AFTER the check
      for(int i=0;i<n;i++)
        {
         if(reasons[i]!=FTF_OK)
            continue;
         int e=sigs[i].engine;
         if(e>=1 && e<=FTF_ENGINE_COUNT)
           {
            m_lastDir[e]=sigs[i].dir;
            m_lastMsc[e]=now;
           }
        }
      if(conflict)
        {
         m_holdUntil=now+(long)m_ctx.cfg.ConflictHoldMs;
         m_conflicts++;
         m_lastConflict=why;
         for(int i=0;i<n;i++)
            if(reasons[i]==FTF_OK)
              {
               reasons[i]=FTF_REJ_CONFLICT;
               details[i]=why+" - hold "+IntegerToString(m_ctx.cfg.ConflictHoldMs)+" ms";
              }
         m_ctx.Event("CONFLICT","OPPOSITE",why+" - entries held "+IntegerToString(m_ctx.cfg.ConflictHoldMs)+" ms");
        }
      //--- stable insertion sort by quality desc, engine asc
      for(int i=1;i<n;i++)
        {
         int j=i;
         while(j>0 && Before(sigs[j],sigs[j-1]))
           {
            Swap(sigs,reasons,details,j,j-1);
            j--;
           }
        }
      return n;
     }

   bool              IsHolding(void)
     {
      long now=m_ctx.NowMsc();
      return (m_holdUntil>0 && now<m_holdUntil);
     }

   long              HoldRemainingMs(void)
     {
      long r=m_holdUntil-m_ctx.NowMsc();
      return (r>0 ? r : 0);
     }

   int               Conflicts(void) { return m_conflicts; }

   string            Describe(void)
     {
      string s="conflicts "+IntegerToString(m_conflicts);
      if(IsHolding())
         s+=" | HOLD "+IntegerToString(HoldRemainingMs())+" ms";
      if(StringLen(m_lastConflict)>0)
         s+=" | last: "+m_lastConflict;
      return s;
     }
  };

//+------------------------------------------------------------------+
//| CSignalConfirmer - signals parked during the mode delay          |
//+------------------------------------------------------------------+
class CSignalConfirmer
  {
private:
   CFtfContext      *m_ctx;
   SSignal           m_items[FTF_CONFIRM_MAX];
   int               m_count;

public:
                     CSignalConfirmer(void)
     {
      m_ctx=NULL;
      m_count=0;
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      m_count=0;
      return (CheckPointer(m_ctx)!=POINTER_INVALID);
     }

   bool              HasSetup(const string setupId)
     {
      for(int i=0;i<m_count;i++)
         if(m_items[i].setupId==setupId)
            return true;
      return false;
     }

   //--- park a signal; its expiry is extended by the delay (docs/03 section 5)
   bool              Add(const SSignal &s)
     {
      if(HasSetup(s.setupId) || m_count>=FTF_CONFIRM_MAX)
         return false;
      m_items[m_count]=s;
      m_items[m_count].firstSeenMsc=m_ctx.NowMsc();
      m_items[m_count].expiryMsc=s.expiryMsc+(long)m_ctx.cfg.ModeDelayMs();
      m_count++;
      return true;
     }

   int               Count(void) { return m_count; }

   bool              Get(const int i,SSignal &s)
     {
      if(i<0 || i>=m_count)
         return false;
      s=m_items[i];
      return true;
     }

   void              RemoveAt(const int i)
     {
      if(i<0 || i>=m_count)
         return;
      for(int k=i;k<m_count-1;k++)
         m_items[k]=m_items[k+1];
      m_count--;
     }

   void              Clear(void) { m_count=0; }
  };

#endif // FTF_CONFLICT_RESOLVER_MQH
