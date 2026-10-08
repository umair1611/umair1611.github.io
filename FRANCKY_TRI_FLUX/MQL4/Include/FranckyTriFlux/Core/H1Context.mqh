//+------------------------------------------------------------------+
//|                                                    H1Context.mqh |
//|  CH1Context - H1 context filter (spec Addendum A, docs/03 sec 4) |
//|  On each new H1 bar (closed bar = shift 1): EMA fast/slow and    |
//|  ADX with +DI/-DI ->  BULLISH / BEARISH / NEUTRAL.               |
//|   OFF    : ignored, never blocks                                 |
//|   SOFT   : context logged only, never blocks, never changes lot  |
//|   STRICT : BULLISH blocks SELL, BEARISH blocks BUY (Momentum,    |
//|            FVG); Range blocked while H1 trend is strong.         |
//|  NEUTRAL never creates a direction and never blocks.             |
//|  docs/09 section 7.9. Shared Core: identical in MQL5 and MQL4.   |
//+------------------------------------------------------------------+
#ifndef FTF_H1_CONTEXT_MQH
#define FTF_H1_CONTEXT_MQH

#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Config.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>
#include <FranckyTriFlux\Platform\Platform.mqh>

#define FTF_H1_RETRY_SEC   1    // TUNABLE (not an input yet) - retry period (server s) while H1 indicators are not ready

class CH1Context
  {
private:
   CConfig          *m_cfg;
   CLogger          *m_log;
   CPlatform        *m_pf;
   bool              m_ready;       // Init succeeded
   int               m_idEmaF;      // platform indicator ids
   int               m_idEmaS;
   int               m_idAdx;
   int               m_state;       // ENUM_FTF_H1_STATE
   double            m_adx;
   double            m_pdi;
   double            m_mdi;
   double            m_emaF;
   double            m_emaS;
   bool              m_computed;    // values of a closed H1 bar are available
   bool              m_pending;     // a new H1 bar was signalled but its values were not available yet
   datetime          m_barTime;     // open time of the closed H1 bar used (shift 1)
   datetime          m_lastTry;     // server time of the last compute attempt
   int               m_digits;      // price digits for the log
   int               m_changes;     // state changes since Init

   bool              IsNum(const double v) { return (v!=EMPTY_VALUE && MathIsValidNumber(v)); }

   string            ModeText(void)
     {
      if(m_cfg.H1Filter==FTF_H1_STRICT)
         return "STRICT";
      if(m_cfg.H1Filter==FTF_H1_SOFT)
         return "SOFT";
      return "OFF";
     }

   //--- spec A.1 / docs/03 section 4
   int               Classify(void)
     {
      if(m_emaF>m_emaS && m_pdi>m_mdi+m_cfg.H1DiMinGap && m_adx>m_cfg.H1AdxThreshold)
         return FTF_H1S_BULLISH;
      if(m_emaF<m_emaS && m_mdi>m_pdi+m_cfg.H1DiMinGap && m_adx>m_cfg.H1AdxThreshold)
         return FTF_H1S_BEARISH;
      return FTF_H1S_NEUTRAL;
     }

   //--- EMA / ADX / DI values with the rule that produced the state
   string            ValuesText(void)
     {
      string rel=(m_emaF>m_emaS ? " > " : (m_emaF<m_emaS ? " < " : " = "));
      return "EMA"+IntegerToString(m_cfg.H1EmaFast)+" "+FTF_D(m_emaF,m_digits)+rel+"EMA"+
             IntegerToString(m_cfg.H1EmaSlow)+" "+FTF_D(m_emaS,m_digits)+" | ADX("+IntegerToString(m_cfg.H1AdxPeriod)+") "+
             FTF_D(m_adx,1)+" (threshold "+FTF_D(m_cfg.H1AdxThreshold,1)+", strong "+FTF_D(m_cfg.H1StrongAdx,1)+
             ") | +DI "+FTF_D(m_pdi,1)+" / -DI "+FTF_D(m_mdi,1)+" (min gap "+FTF_D(m_cfg.H1DiMinGap,1)+")";
     }

   //--- reads the closed H1 bar; false while the indicators are not ready (state stays NEUTRAL)
   bool              Compute(void)
     {
      m_lastTry=m_pf.ServerTime();
      double ef=m_pf.IndValue(m_idEmaF,0,1);
      double es=m_pf.IndValue(m_idEmaS,0,1);
      double ax=m_pf.IndValue(m_idAdx,0,1);
      double pd=m_pf.IndValue(m_idAdx,1,1);
      double nd=m_pf.IndValue(m_idAdx,2,1);
      if(!IsNum(ef) || !IsNum(es) || !IsNum(ax) || !IsNum(pd) || !IsNum(nd) || ef<=0.0 || es<=0.0)
        {
         m_log.Throttled(FTF_LOG_DEBUG,"h1.notready",m_cfg.LogThrottleMs,"H1",
                         "H1 indicators not ready yet - keeping "+FTF_H1StateStr(m_state)+
                         (m_computed ? " of the previous bar" : " (NEUTRAL never blocks)")+", retrying");
         return false;
        }
      m_emaF=ef; m_emaS=es; m_adx=ax; m_pdi=pd; m_mdi=nd;
      m_barTime=m_pf.BarTime(PERIOD_H1,1);
      int prev=m_state;
      bool first=!m_computed;
      m_state=Classify();
      m_computed=true;
      if(first)
         m_log.Info("H1","H1 context initialised: "+FTF_H1StateStr(m_state)+" | "+ValuesText()+" | mode "+ModeText()+
                    " | bar "+FTF_TimeStr(m_barTime));
      else if(prev!=m_state)
        {
         m_changes++;
         m_log.Info("H1","H1 context changed "+FTF_H1StateStr(prev)+" -> "+FTF_H1StateStr(m_state)+" | "+ValuesText()+
                    " | mode "+ModeText()+(m_adx>=m_cfg.H1StrongAdx && m_state!=FTF_H1S_NEUTRAL ? " | STRONG trend" : "")+" | bar "+FTF_TimeStr(m_barTime));
        }
      else
         m_log.Debug("H1","H1 bar "+FTF_TimeStr(m_barTime)+" -> "+FTF_H1StateStr(m_state)+" (unchanged) | "+ValuesText());
      return true;
     }

public:
                     CH1Context(void)
     {
      m_cfg=NULL; m_log=NULL; m_pf=NULL; m_ready=false;
      m_idEmaF=-1; m_idEmaS=-1; m_idAdx=-1;
      m_state=FTF_H1S_NEUTRAL;
      m_adx=0.0; m_pdi=0.0; m_mdi=0.0; m_emaF=0.0; m_emaS=0.0;
      m_computed=false; m_pending=false; m_barTime=0; m_lastTry=0; m_digits=5; m_changes=0;
     }

   //--- registers EMA(H1,fast), EMA(H1,slow), ADX(H1,period) and computes once (spec A.1)
   bool              Init(CConfig *cfg,CLogger *logger,CPlatform *pf)
     {
      m_cfg=cfg; m_log=logger; m_pf=pf;
      m_ready=false;
      if(CheckPointer(m_cfg)==POINTER_INVALID || CheckPointer(m_log)==POINTER_INVALID || CheckPointer(m_pf)==POINTER_INVALID)
         return false;
      SSymbolSpec sp;
      sp.Reset();
      if(m_pf.RefreshSpec(sp) && sp.digits>0)
         m_digits=sp.digits;
      m_idEmaF=m_pf.RegisterEMA(PERIOD_H1,m_cfg.H1EmaFast);
      m_idEmaS=m_pf.RegisterEMA(PERIOD_H1,m_cfg.H1EmaSlow);
      m_idAdx=m_pf.RegisterADX(PERIOD_H1,m_cfg.H1AdxPeriod);
      if(m_idEmaF<0 || m_idEmaS<0 || m_idAdx<0)
        {
         m_log.Error("H1","H1 indicator registration FAILED (EMA #"+IntegerToString(m_idEmaF)+"/#"+
                     IntegerToString(m_idEmaS)+", ADX #"+IntegerToString(m_idAdx)+")");
         return false;
        }
      m_ready=true;
      m_log.Info("H1","H1 context filter "+ModeText()+" | EMA "+IntegerToString(m_cfg.H1EmaFast)+"/"+
                 IntegerToString(m_cfg.H1EmaSlow)+" | ADX("+IntegerToString(m_cfg.H1AdxPeriod)+") > "+
                 FTF_D(m_cfg.H1AdxThreshold,1)+" with DI gap "+FTF_D(m_cfg.H1DiMinGap,1)+" | strong ADX "+
                 FTF_D(m_cfg.H1StrongAdx,1)+" | STRICT applies to: Momentum "+(m_cfg.H1StrictMomentum ? "yes" : "no")+
                 ", FVG "+(m_cfg.H1StrictFvg ? "yes" : "no")+", Range "+(m_cfg.H1StrictRange ? "yes" : "no"));
      Compute();   // at init (retried by Update while the indicators are not ready)
      return true;
     }

   //--- recompute on a new H1 bar (closed bar 1). When the values are not available yet (never computed,
   //--- or live indicator lag on the new bar) the compute is retried every FTF_H1_RETRY_SEC server seconds.
   void              Update(const bool newH1Bar)
     {
      if(!m_ready)
         return;
      if(newH1Bar)
        {
         m_pending=!Compute();
         return;
        }
      if((m_pending || !m_computed) && m_pf.ServerTime()>=m_lastTry+FTF_H1_RETRY_SEC)
         m_pending=!Compute();
     }

   int               State(void)     { return m_state; }
   //--- State()!=NEUTRAL && ADX >= InpH1StrongAdx (Range STRICT rule)
   bool              IsStrong(void)  { return (m_state!=FTF_H1S_NEUTRAL && m_adx>=m_cfg.H1StrongAdx); }
   double            Adx(void)       { return m_adx; }
   double            PlusDi(void)    { return m_pdi; }
   double            MinusDi(void)   { return m_mdi; }
   double            EmaFast(void)   { return m_emaF; }
   double            EmaSlow(void)   { return m_emaS; }
   //--- extra: values of a closed H1 bar are available (false = NEUTRAL by default)
   bool              Computed(void)  { return m_computed; }
   //--- extra: open time of the closed H1 bar the state was computed on
   datetime          ComputedBarTime(void) { return m_barTime; }
   //--- extra: number of state changes since Init
   int               StateChanges(void) { return m_changes; }

   //--- FTF_OK or FTF_REJ_H1_STRICT. OFF / SOFT never block (docs/03 section 4 table)
   int               CheckEntry(const int engine,const int dir,string &detail)
     {
      string st=FTF_H1StateStr(m_state);
      string vs=st+" vs "+FTF_DirStr(dir)+" "+FTF_EngineName(engine)+" (ADX "+FTF_D(m_adx,1)+
                ", +DI "+FTF_D(m_pdi,1)+" / -DI "+FTF_D(m_mdi,1)+")";
      bool against=((m_state==FTF_H1S_BULLISH && dir==FTF_DIR_SELL) || (m_state==FTF_H1S_BEARISH && dir==FTF_DIR_BUY));
      if(!m_ready)
        {
         detail="H1 context not initialised - not blocking";
         return FTF_OK;
        }
      if(m_cfg.H1Filter==FTF_H1_OFF)
        {
         detail="H1 OFF - ignored";
         return FTF_OK;
        }
      if(m_cfg.H1Filter==FTF_H1_SOFT)
        {
         detail="H1 SOFT context "+vs+(against ? " - against H1 trend, not blocking" : " - not blocking");
         return FTF_OK;
        }
      //--- STRICT
      if(!m_cfg.H1StrictAppliesTo(engine))
        {
         detail="H1 STRICT not applied to "+FTF_EngineName(engine)+" - context "+vs;
         return FTF_OK;
        }
      if(m_state==FTF_H1S_NEUTRAL)
        {
         detail="H1 STRICT context NEUTRAL - never blocks"+(m_computed ? "" : " (H1 not computed yet)");
         return FTF_OK;
        }
      if(engine==FTF_ENG_RANGE)
        {
         if(IsStrong())
           {
            detail="H1 STRICT: strong "+st+" trend (ADX "+FTF_D(m_adx,1)+" >= "+FTF_D(m_cfg.H1StrongAdx,1)+
                   ") blocks all new Range entries";
            m_log.Debug("H1",detail);
            return FTF_REJ_H1_STRICT;
           }
         detail="H1 STRICT: "+st+" not strong (ADX "+FTF_D(m_adx,1)+" < "+FTF_D(m_cfg.H1StrongAdx,1)+") - Range allowed";
         return FTF_OK;
        }
      if(against)
        {
         detail="H1 STRICT: "+vs+" - entry against the H1 trend blocked";
         m_log.Debug("H1",detail);
         return FTF_REJ_H1_STRICT;
        }
      detail="H1 STRICT: "+vs+" - with the H1 trend, allowed";
      return FTF_OK;
     }

   //--- panel / log text
   string            Describe(void)
     {
      if(!m_ready)
         return "H1 context not initialised";
      if(!m_computed)
         return "H1 "+ModeText()+" | NEUTRAL (not computed yet)";
      return "H1 "+ModeText()+" | "+FTF_H1StateStr(m_state)+(IsStrong() ? " STRONG" : "")+" | ADX "+FTF_D(m_adx,1)+
             " +DI "+FTF_D(m_pdi,1)+" -DI "+FTF_D(m_mdi,1)+" | EMA "+FTF_D(m_emaF,m_digits)+
             (m_emaF>m_emaS ? " > " : " <= ")+FTF_D(m_emaS,m_digits);
     }
  };

#endif // FTF_H1_CONTEXT_MQH
