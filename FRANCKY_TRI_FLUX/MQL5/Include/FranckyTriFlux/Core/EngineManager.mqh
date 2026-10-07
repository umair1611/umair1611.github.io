//+------------------------------------------------------------------+
//|                                                EngineManager.mqh |
//|  CEngineManager - owns the 3 independent engines and runs them   |
//|  in parallel on every tick. No engine waits for another (G.2).   |
//|  docs/09 section 7.22                                            |
//+------------------------------------------------------------------+
#ifndef FTF_ENGINE_MANAGER_MQH
#define FTF_ENGINE_MANAGER_MQH

#include <FranckyTriFlux\Core\EngineMomentum.mqh>
#include <FranckyTriFlux\Core\EngineFVG.mqh>
#include <FranckyTriFlux\Core\EngineRange.mqh>

class CEngineManager
  {
private:
   CFtfContext      *m_ctx;
   CEngineMomentum   m_mom;
   CEngineFVG        m_fvg;
   CEngineRange      m_rng;
   CEngineBase      *m_eng[FTF_ENGINE_COUNT+1];   // index = engine id (0 unused)
   ENUM_TIMEFRAMES   m_tfs[5];
   int               m_tfCount;

   void              AddTf(const ENUM_TIMEFRAMES tf)
     {
      for(int i=0;i<m_tfCount;i++)
         if(m_tfs[i]==tf)
            return;
      if(m_tfCount<5)
        {
         m_tfs[m_tfCount]=tf;
         m_tfCount++;
        }
     }

public:
                     CEngineManager(void)
     {
      m_ctx=NULL;
      m_tfCount=0;
      m_eng[0]=NULL;
      m_eng[FTF_ENG_MOMENTUM]=GetPointer(m_mom);
      m_eng[FTF_ENG_FVG]=GetPointer(m_fvg);
      m_eng[FTF_ENG_RANGE]=GetPointer(m_rng);
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(CheckPointer(m_ctx)==POINTER_INVALID)
         return false;
      bool ok=true;
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         if(!m_eng[e].Init(ctx))
           {
            m_ctx.log.Error("MGR","engine "+FTF_EngineName(e)+" failed to initialise");
            ok=false;
           }
      m_tfCount=0;
      AddTf(PERIOD_M1);
      AddTf(PERIOD_M5);
      AddTf(PERIOD_H1);
      AddTf(m_ctx.cfg.FvgTimeframe);
      AddTf(m_ctx.cfg.RngTimeframe);
      m_ctx.log.Info("MGR","engines ready: "+IntegerToString(EnabledCount())+" enabled (Momentum "+
                     (m_mom.Enabled() ? "ON" : "OFF")+", FVG "+(m_fvg.Enabled() ? "ON" : "OFF")+", Range "+
                     (m_rng.Enabled() ? "ON" : "OFF")+")");
      return ok;
     }

   CEngineBase      *Get(const int engine)
     {
      if(engine<1 || engine>FTF_ENGINE_COUNT)
         return NULL;
      return m_eng[engine];
     }

   //--- forward new-bar events of every watched timeframe to every engine (each filters its own tf)
   void              OnNewBars(void)
     {
      for(int i=0;i<m_tfCount;i++)
        {
         if(!m_ctx.md.IsNewBar(m_tfs[i]))
            continue;
         for(int e=1;e<=FTF_ENGINE_COUNT;e++)
            m_eng[e].OnNewBar(m_tfs[i]);
        }
     }

   //--- run every enabled engine; signals appended to out[] (resized here)
   int               Evaluate(SSignal &out[])
     {
      ArrayResize(out,FTF_MAX_SIGNALS);
      int n=0;
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
        {
         if(!m_eng[e].Enabled())
            continue;
         if(n>=FTF_MAX_SIGNALS)
            break;
         int added=m_eng[e].Evaluate(out,n,FTF_MAX_SIGNALS-n);
         if(added>0)
            n+=added;
        }
      ArrayResize(out,n);
      return n;
     }

   void              DrawAll(void)
     {
      if(CheckPointer(m_ctx.ui)==POINTER_INVALID || !m_ctx.ui.Enabled())
         return;
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         if(m_eng[e].Enabled())
            m_eng[e].Draw();
     }

   void              SaveAll(void)
     {
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         m_eng[e].SaveState();
     }

   void              LoadAll(void)
     {
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         m_eng[e].LoadState();
     }

   int               EnabledCount(void)
     {
      int c=0;
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         if(m_eng[e].Enabled())
            c++;
      return c;
     }

   long              LastAnyEntryMsc(void)
     {
      long m=0;
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         if(m_eng[e].LastEntryMsc()>m)
            m=m_eng[e].LastEntryMsc();
      return m;
     }
  };

#endif // FTF_ENGINE_MANAGER_MQH
