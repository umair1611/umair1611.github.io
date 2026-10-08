//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|  CRiskManager        - lot sizing on the REAL SL distance, hard  |
//|                        caps, optional martingale (spec B.5)      |
//|  CExposureGuard      - aggregate exposure across EURUSD/XAUUSD/  |
//|                        BTCUSD, net risk per currency, optional   |
//|                        measured correlation (spec B.6)           |
//|  CMultiInstanceGuard - duplicate Instance ID lock + cross-       |
//|                        instance duplicate entries (Table 12)     |
//|  docs/09 section 7.17                                            |
//+------------------------------------------------------------------+
#ifndef FTF_RISK_MANAGER_MQH
#define FTF_RISK_MANAGER_MQH

#include <FranckyTriFlux\Core\Context.mqh>
#include <FranckyTriFlux\Core\PositionTracker.mqh>

#define FTF_EXPO_REFRESH_MS     2000     // TUNABLE (not an input yet) - account positions snapshot refresh
#define FTF_EXPO_CORR_MS        300000   // TUNABLE (not an input yet) - correlation matrix refresh
#define FTF_EXPO_NO_SL_MOVE     0.01     // positions without SL count as a 1% adverse move (documented in docs/12 D14)
#define FTF_EXPO_MAX_SYM        16
#define FTF_EXPO_MAX_CCY        24
#define FTF_MI_STALE_SEC        15       // heartbeat older than this = previous owner is gone
#define FTF_MARGIN_USE_MAX      0.95     // margin of a new trade must fit in 95% of the free margin

//+------------------------------------------------------------------+
//| CRiskManager                                                     |
//+------------------------------------------------------------------+
class CRiskManager
  {
private:
   CFtfContext      *m_ctx;
   CPositionTracker *m_tracker;
   int               m_step[FTF_ENGINE_COUNT+1];   // martingale step per engine

   string            Money(const double v) { return DoubleToString(v,2); }

public:
                     CRiskManager(void)
     {
      m_ctx=NULL;
      m_tracker=NULL;
      for(int e=0;e<=FTF_ENGINE_COUNT;e++)
         m_step[e]=0;
     }

   bool              Init(CFtfContext *ctx,CPositionTracker *tracker)
     {
      m_ctx=ctx;
      m_tracker=tracker;
      if(CheckPointer(m_ctx)==POINTER_INVALID || CheckPointer(m_tracker)==POINTER_INVALID)
         return false;
      CConfig *cf=m_ctx.cfg;
      m_ctx.logger.Info("RISK","mode "+EnumToString(cf.RiskMode)+" | fixed lot "+FTF_D(cf.FixedLot,2)+" | risk "+
                     FTF_D(cf.RiskPercent,2)+"% cap "+FTF_D(cf.MaxRiskPercent,2)+"% | max lot "+FTF_D(cf.MaxLotPerTrade,2)+
                     " | open risk cap "+FTF_D(cf.MaxOpenRiskPct,2)+"% | martingale "+
                     (cf.MartingaleEnabled ? "ON x"+FTF_D(cf.MartingaleMult,2)+" max "+IntegerToString(cf.MartingaleMaxSteps) : "OFF"));
      return true;
     }

   int               MartingaleStep(const int engine)
     {
      if(engine<1 || engine>FTF_ENGINE_COUNT)
         return 0;
      return m_step[engine];
     }

   //--- spec B.5: lots from the real SL distance; returns FTF_OK / FTF_REJ_RISK / FTF_REJ_LOT / FTF_REJ_MARGIN
   int               CalcLots(const SSignal &sig,const double entry,const double lotFactor,double &lots,double &riskMoney,string &detail)
     {
      lots=0.0;
      riskMoney=0.0;
      CConfig *cf=m_ctx.cfg;
      SSymbolSpec spec=m_ctx.md.spec;
      double lossPerLot=m_ctx.pf.LossPerLot(m_ctx.symbol,sig.dir,entry,sig.sl);
      if(lossPerLot<=0.0 || !MathIsValidNumber(lossPerLot))
        {
         detail="loss per lot unavailable (entry "+FTF_D(entry,spec.digits)+" sl "+FTF_D(sig.sl,spec.digits)+")";
         return FTF_REJ_RISK;
        }
      int step=MartingaleStep(sig.engine);
      double mart=(cf.MartingaleEnabled ? MathPow(cf.MartingaleMult,step) : 1.0);
      double base=(cf.RiskMode==FTF_RISK_PCT_BALANCE ? m_ctx.pf.Balance() : m_ctx.pf.Equity());
      double cap=(cf.MaxRiskPercent>0.0 ? base*cf.MaxRiskPercent/100.0 : 0.0);
      double raw=0.0;
      string how="";
      if(cf.RiskMode==FTF_RISK_FIXED_LOT)
        {
         raw=cf.FixedLot*mart;
         how="fixed "+FTF_D(cf.FixedLot,2)+(mart!=1.0 ? " x mart "+FTF_D(mart,2) : "");
         //--- the hard risk cap also applies to fixed lots
         if(cap>0.0 && raw*lossPerLot>cap)
           {
            raw=cap/lossPerLot;
            how+=" capped by "+FTF_D(cf.MaxRiskPercent,2)+"%";
           }
        }
      else
        {
         double target=base*cf.RiskPercent/100.0*mart;
         if(cap>0.0 && target>cap)
            target=cap;
         raw=target/lossPerLot;
         how=FTF_D(cf.RiskPercent,2)+"% of "+(cf.RiskMode==FTF_RISK_PCT_BALANCE ? "balance " : "equity ")+Money(base)+
             (mart!=1.0 ? " x mart "+FTF_D(mart,2) : "")+" = "+Money(target);
        }
      if(lotFactor>0.0 && lotFactor<1.0)
        {
         raw*=lotFactor;
         how+=" x quality factor "+FTF_D(lotFactor,2);
        }
      if(cf.MaxLotPerTrade>0.0 && raw>cf.MaxLotPerTrade)
         raw=cf.MaxLotPerTrade;
      lots=FTF_NormalizeLotsDown(raw,spec.lotStep,spec.lotMin,spec.lotMax);
      if(lots<=0.0)
        {
         if(!cf.AllowMinLotOverRisk)
           {
            detail="lot "+FTF_D(raw,4)+" < broker min "+FTF_D(spec.lotMin,2)+" (min lot risks "+Money(spec.lotMin*lossPerLot)+
                   (cap>0.0 ? " > cap "+Money(cap) : "")+") | "+how;
            return FTF_REJ_RISK;
           }
         lots=FTF_NormalizeLotsDown(spec.lotMin,spec.lotStep,spec.lotMin,spec.lotMax);
         if(lots<=0.0)
           {
            detail="invalid broker lot settings min "+FTF_D(spec.lotMin,2)+" step "+FTF_D(spec.lotStep,2);
            return FTF_REJ_LOT;
           }
        }
      riskMoney=lots*lossPerLot;
      if(cap>0.0 && riskMoney>cap*1.001 && !cf.AllowMinLotOverRisk)
        {
         detail="risk "+Money(riskMoney)+" > hard cap "+Money(cap)+" | "+how;
         return FTF_REJ_RISK;
        }
      //--- margin
      double margin=m_ctx.pf.MarginRequired(sig.dir,lots,entry);
      double free=m_ctx.pf.FreeMargin();
      if(margin>0.0 && margin>free*FTF_MARGIN_USE_MAX)
        {
         detail="margin "+Money(margin)+" > "+DoubleToString(FTF_MARGIN_USE_MAX*100.0,0)+"% of free margin "+Money(free)+
                " for "+FTF_D(lots,2)+" lots";
         return FTF_REJ_MARGIN;
        }
      detail=how+" | loss/lot "+Money(lossPerLot)+" | lots "+FTF_D(lots,2)+" | risk "+Money(riskMoney)+
             " ("+FTF_D(base>0.0 ? riskMoney/base*100.0 : 0.0,2)+"%) | margin "+Money(margin);
      return FTF_OK;
     }

   //--- instance exposure ceilings (spec B.5 "plafond d'exposition totale")
   int               CheckInstanceExposure(const double addRisk,const double addLots,string &detail)
     {
      CConfig *cf=m_ctx.cfg;
      double eq=m_ctx.pf.Equity();
      double open=m_tracker.OpenRiskMoney();
      if(cf.MaxOpenRiskPct>0.0 && eq>0.0 && open+addRisk>eq*cf.MaxOpenRiskPct/100.0)
        {
         detail="open risk "+Money(open)+" + "+Money(addRisk)+" > "+FTF_D(cf.MaxOpenRiskPct,2)+"% of equity "+Money(eq);
         return FTF_REJ_EXPOSURE;
        }
      double lotsOpen=m_tracker.OpenLots();
      if(cf.MaxTotalLots>0.0 && lotsOpen+addLots>cf.MaxTotalLots+1e-9)
        {
         detail="open lots "+FTF_D(lotsOpen,2)+" + "+FTF_D(addLots,2)+" > max "+FTF_D(cf.MaxTotalLots,2);
         return FTF_REJ_EXPOSURE;
        }
      detail="open risk "+Money(open+addRisk)+" lots "+FTF_D(lotsOpen+addLots,2);
      return FTF_OK;
     }

   //--- martingale bookkeeping (a NEW valid setup is still required: docs/03 section 9)
   void              OnClosed(const int engine,const double net)
     {
      if(engine<1 || engine>FTF_ENGINE_COUNT)
         return;
      int before=m_step[engine];
      if(net<0.0)
         m_step[engine]=(int)MathMin(m_step[engine]+1,MathMax(0,m_ctx.cfg.MartingaleMaxSteps));
      else
         m_step[engine]=0;
      if(m_ctx.cfg.MartingaleEnabled && before!=m_step[engine])
         m_ctx.logger.Info("RISK","martingale "+FTF_EngineCode(engine)+" step "+IntegerToString(before)+" -> "+
                        IntegerToString(m_step[engine])+" (net "+Money(net)+")");
      Save();
     }

   void              Save(void)
     {
      if(CheckPointer(m_ctx.state)==POINTER_INVALID || !m_ctx.state.Enabled())
         return;
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
         m_ctx.state.SetLong("mg."+IntegerToString(e)+".step",m_step[e]);
     }

   void              Load(void)
     {
      if(CheckPointer(m_ctx.state)==POINTER_INVALID || !m_ctx.state.Enabled())
         return;
      for(int e=1;e<=FTF_ENGINE_COUNT;e++)
        {
         long v=m_ctx.state.GetLong("mg."+IntegerToString(e)+".step",0);
         m_step[e]=(int)MathMax(0,MathMin((double)v,(double)m_ctx.cfg.MartingaleMaxSteps));
        }
     }

   string            Describe(void)
     {
      CConfig *cf=m_ctx.cfg;
      string s="risk "+(cf.RiskMode==FTF_RISK_FIXED_LOT ? "fixed "+FTF_D(cf.FixedLot,2) : FTF_D(cf.RiskPercent,2)+"%")+
               " cap "+FTF_D(cf.MaxRiskPercent,2)+"% | open "+Money(m_tracker.OpenRiskMoney());
      if(cf.MartingaleEnabled)
         s+=" | mart M"+IntegerToString(m_step[1])+" F"+IntegerToString(m_step[2])+" R"+IntegerToString(m_step[3]);
      return s;
     }
  };

//+------------------------------------------------------------------+
//| CExposureGuard (spec B.6)                                        |
//+------------------------------------------------------------------+
class CExposureGuard
  {
private:
   CFtfContext      *m_ctx;
   long              m_lastRefresh;
   long              m_lastCorr;
   bool              m_warnedCorr;
   //--- per symbol (positions counted + the chart symbol)
   string            m_sym[FTF_EXPO_MAX_SYM];
   string            m_symBase[FTF_EXPO_MAX_SYM];
   string            m_symProfit[FTF_EXPO_MAX_SYM];
   double            m_symRisk[FTF_EXPO_MAX_SYM];      // signed risk money (+ long, - short)
   int               m_nSym;
   //--- per currency
   string            m_ccy[FTF_EXPO_MAX_CCY];
   double            m_ccyNet[FTF_EXPO_MAX_CCY];
   int               m_nCcy;
   double            m_gross;
   int               m_positions;
   //--- correlation cache (symbols list at last computation)
   string            m_corrSym[FTF_EXPO_MAX_SYM];
   double            m_corr[FTF_EXPO_MAX_SYM*FTF_EXPO_MAX_SYM];
   bool              m_corrOk[FTF_EXPO_MAX_SYM*FTF_EXPO_MAX_SYM];
   int               m_nCorr;

   string            Money(const double v) { return DoubleToString(v,2); }

   int               SymIndex(const string sym,const bool create)
     {
      for(int i=0;i<m_nSym;i++)
         if(m_sym[i]==sym)
            return i;
      if(!create || m_nSym>=FTF_EXPO_MAX_SYM)
         return -1;
      string b="";
      string p="";
      if(!m_ctx.pf.OtherSymbolCurrencies(sym,b,p))
        {
         b=StringSubstr(sym,0,3);
         p=StringSubstr(sym,3,3);
        }
      m_sym[m_nSym]=sym;
      m_symBase[m_nSym]=b;
      m_symProfit[m_nSym]=p;
      m_symRisk[m_nSym]=0.0;
      m_nSym++;
      return m_nSym-1;
     }

   void              AddCcy(const string ccy,const double v)
     {
      if(StringLen(ccy)==0)
         return;
      for(int i=0;i<m_nCcy;i++)
         if(m_ccy[i]==ccy)
           {
            m_ccyNet[i]+=v;
            return;
           }
      if(m_nCcy>=FTF_EXPO_MAX_CCY)
         return;
      m_ccy[m_nCcy]=ccy;
      m_ccyNet[m_nCcy]=v;
      m_nCcy++;
     }

   //--- risk of one position at its SL (or a 1% adverse move without SL)
   double            PositionRisk(const SPosInfo &p)
     {
      double sl=p.sl;
      bool lossSide=(sl>0.0 && ((p.dir==FTF_DIR_BUY && sl<p.openPrice) || (p.dir==FTF_DIR_SELL && sl>p.openPrice)));
      if(sl>0.0 && !lossSide)
         return 0.0;    // stop already protects a profit
      if(sl<=0.0)
         sl=p.openPrice*(1.0-p.dir*FTF_EXPO_NO_SL_MOVE);
      double l=m_ctx.pf.LossPerLot(p.symbol,p.dir,p.openPrice,sl);
      return (l>0.0 ? l*p.lots : 0.0);
     }

   void              Snapshot(void)
     {
      m_nSym=0;
      m_nCcy=0;
      m_gross=0.0;
      m_positions=0;
      SPosInfo snap[];
      int n=m_ctx.pf.GetPositions(snap,true);
      for(int i=0;i<n;i++)
        {
         if(m_ctx.cfg.ExposureFamilyOnly && !m_ctx.IsFamilyMagic(snap[i].magic))
            continue;
         double r=PositionRisk(snap[i]);
         int k=SymIndex(snap[i].symbol,true);
         if(k<0)
            continue;
         m_positions++;
         m_gross+=r;
         m_symRisk[k]+=snap[i].dir*r;
         AddCcy(m_symBase[k],snap[i].dir*r);
         AddCcy(m_symProfit[k],-snap[i].dir*r);
        }
     }

   //--- Pearson correlation of M5 log returns (closes[0] = newest)
   bool              Correlation(const string a,const string b,double &rho)
     {
      int n=m_ctx.cfg.CorrBars;
      double ca[];
      double cb[];
      if(!m_ctx.pf.OtherSymbolCloses(a,PERIOD_M5,n+1,ca) || !m_ctx.pf.OtherSymbolCloses(b,PERIOD_M5,n+1,cb))
         return false;
      if(ArraySize(ca)<n+1 || ArraySize(cb)<n+1)
         return false;
      double sa=0.0,sb=0.0,saa=0.0,sbb=0.0,sab=0.0;
      int m=0;
      for(int i=0;i<n;i++)
        {
         if(ca[i]<=0.0 || ca[i+1]<=0.0 || cb[i]<=0.0 || cb[i+1]<=0.0)
            continue;
         double ra=MathLog(ca[i]/ca[i+1]);
         double rb=MathLog(cb[i]/cb[i+1]);
         sa+=ra; sb+=rb; saa+=ra*ra; sbb+=rb*rb; sab+=ra*rb;
         m++;
        }
      if(m<10)
         return false;
      double cov=sab-sa*sb/m;
      double va=saa-sa*sa/m;
      double vb=sbb-sb*sb/m;
      if(va<=0.0 || vb<=0.0)
         return false;
      rho=FTF_Clamp(cov/MathSqrt(va*vb),-1.0,1.0);
      return true;
     }

   //--- fallback when data is missing: +1 if both symbols share a currency leg on the same side, else 0
   double            FallbackRho(const int i,const int j)
     {
      if(m_symProfit[i]==m_symProfit[j] || m_symBase[i]==m_symBase[j])
         return 1.0;
      return 0.0;
     }

   void              ComputeCorrelations(void)
     {
      m_nCorr=m_nSym;
      for(int i=0;i<m_nSym;i++)
         m_corrSym[i]=m_sym[i];
      for(int i=0;i<m_nSym;i++)
         for(int j=0;j<m_nSym;j++)
           {
            int k=i*FTF_EXPO_MAX_SYM+j;
            if(i==j)
              {
               m_corr[k]=1.0;
               m_corrOk[k]=true;
               continue;
              }
            if(j<i)
              {
               m_corr[k]=m_corr[j*FTF_EXPO_MAX_SYM+i];
               m_corrOk[k]=m_corrOk[j*FTF_EXPO_MAX_SYM+i];
               continue;
              }
            double rho=0.0;
            bool ok=Correlation(m_sym[i],m_sym[j],rho);
            m_corr[k]=(ok ? rho : FallbackRho(i,j));
            m_corrOk[k]=ok;
            if(!ok && !m_warnedCorr)
              {
               m_warnedCorr=true;
               m_ctx.logger.Warn("EXPO","correlation data missing for "+m_sym[i]+"/"+m_sym[j]+
                              " - using currency-leg fallback (rho "+FTF_D(m_corr[k],0)+")");
              }
           }
      m_lastCorr=m_ctx.NowMsc();
     }

   double            Rho(const int i,const int j)
     {
      if(i>=m_nCorr || j>=m_nCorr || m_corrSym[i]!=m_sym[i] || m_corrSym[j]!=m_sym[j])
         return (i==j ? 1.0 : FallbackRho(i,j));
      return m_corr[i*FTF_EXPO_MAX_SYM+j];
     }

public:
                     CExposureGuard(void)
     {
      m_ctx=NULL;
      m_lastRefresh=0;
      m_lastCorr=0;
      m_warnedCorr=false;
      m_nSym=0;
      m_nCcy=0;
      m_gross=0.0;
      m_positions=0;
      m_nCorr=0;
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(CheckPointer(m_ctx)==POINTER_INVALID)
         return false;
      CConfig *cf=m_ctx.cfg;
      m_ctx.logger.Info("EXPO","aggregate exposure "+EnumToString(cf.ExposureMode)+" | family only "+
                     (cf.ExposureFamilyOnly ? "ON" : "OFF")+" | gross max "+FTF_D(cf.MaxAccountRiskPct,2)+
                     "% | per currency max "+FTF_D(cf.MaxCurrencyRiskPct,2)+"% | corr max "+FTF_D(cf.MaxCorrRiskPct,2)+
                     "% over "+IntegerToString(cf.CorrBars)+" M5 bars");
      return true;
     }

   void              Refresh(const bool force)
     {
      if(m_ctx.cfg.ExposureMode==FTF_EXPO_OFF)
         return;
      long now=m_ctx.NowMsc();
      if(!force && m_lastRefresh>0 && now-m_lastRefresh<FTF_EXPO_REFRESH_MS && now>=m_lastRefresh)
         return;
      m_lastRefresh=now;
      Snapshot();
      if(m_ctx.cfg.ExposureMode==FTF_EXPO_CORRELATION && (force || m_lastCorr==0 || now-m_lastCorr>=FTF_EXPO_CORR_MS || now<m_lastCorr))
        {
         SymIndex(m_ctx.symbol,true);
         ComputeCorrelations();
        }
     }

   int               Check(const SSignal &sig,const double lots,const double riskMoney,string &detail)
     {
      detail="";
      CConfig *cf=m_ctx.cfg;
      if(cf.ExposureMode==FTF_EXPO_OFF)
         return FTF_OK;
      Refresh(false);
      double eq=m_ctx.pf.Equity();
      if(eq<=0.0)
         return FTF_OK;
      //--- work on copies: current exposure + the candidate trade
      double gross=m_gross+riskMoney;
      if(cf.MaxAccountRiskPct>0.0 && gross>eq*cf.MaxAccountRiskPct/100.0)
        {
         detail="gross open risk "+Money(gross)+" ("+FTF_D(gross/eq*100.0,2)+"%) > "+FTF_D(cf.MaxAccountRiskPct,2)+
                "% on "+IntegerToString(m_positions)+" positions + candidate";
         return FTF_REJ_AGGREGATE;
        }
      int k=SymIndex(m_ctx.symbol,true);
      if(k<0)
         return FTF_OK;
      string base=m_symBase[k];
      string prof=m_symProfit[k];
      double add=sig.dir*riskMoney;
      if(cf.MaxCurrencyRiskPct>0.0)
        {
         double lim=eq*cf.MaxCurrencyRiskPct/100.0;
         for(int i=0;i<m_nCcy;i++)
           {
            double v=m_ccyNet[i];
            if(m_ccy[i]==base)
               v+=add;
            if(m_ccy[i]==prof)
               v-=add;
            if(MathAbs(v)>lim)
              {
               detail="net "+m_ccy[i]+" risk "+Money(v)+" ("+FTF_D(v/eq*100.0,2)+"%) > "+FTF_D(cf.MaxCurrencyRiskPct,2)+"%";
               return FTF_REJ_AGGREGATE;
              }
           }
         //--- currencies not yet in the book
         bool hasB=false;
         bool hasP=false;
         for(int i=0;i<m_nCcy;i++)
           {
            if(m_ccy[i]==base)
               hasB=true;
            if(m_ccy[i]==prof)
               hasP=true;
           }
         if((!hasB || !hasP) && MathAbs(add)>lim)
           {
            detail="single trade currency risk "+Money(MathAbs(add))+" > "+FTF_D(cf.MaxCurrencyRiskPct,2)+"%";
            return FTF_REJ_AGGREGATE;
           }
        }
      if(cf.ExposureMode==FTF_EXPO_CORRELATION && cf.MaxCorrRiskPct>0.0)
        {
         double sum=0.0;
         for(int i=0;i<m_nSym;i++)
           {
            double ri=m_symRisk[i]+(i==k ? add : 0.0);
            for(int j=0;j<m_nSym;j++)
              {
               double rj=m_symRisk[j]+(j==k ? add : 0.0);
               sum+=ri*rj*Rho(i,j);
              }
           }
         double port=MathSqrt(MathMax(0.0,sum));
         if(port>eq*cf.MaxCorrRiskPct/100.0)
           {
            detail="correlation-adjusted risk "+Money(port)+" ("+FTF_D(port/eq*100.0,2)+"%) > "+FTF_D(cf.MaxCorrRiskPct,2)+"%";
            return FTF_REJ_AGGREGATE;
           }
        }
      detail="gross "+FTF_D(gross/eq*100.0,2)+"%";
      return FTF_OK;
     }

   string            Describe(void)
     {
      if(m_ctx.cfg.ExposureMode==FTF_EXPO_OFF)
         return "expo OFF";
      double eq=m_ctx.pf.Equity();
      string s="expo gross "+FTF_D(eq>0.0 ? m_gross/eq*100.0 : 0.0,2)+"% ("+IntegerToString(m_positions)+" pos)";
      for(int i=0;i<m_nCcy && i<4;i++)
         s+=" "+m_ccy[i]+" "+FTF_D(eq>0.0 ? m_ccyNet[i]/eq*100.0 : 0.0,2)+"%";
      return s;
     }

   bool              SelfCheck(string &d)
     {
      Refresh(true);
      d=Describe();
      return true;
     }
  };

//+------------------------------------------------------------------+
//| CMultiInstanceGuard (Table 12 MULTI_INSTANCE_GUARD, 1.1)         |
//+------------------------------------------------------------------+
class CMultiInstanceGuard
  {
private:
   CFtfContext      *m_ctx;
   CPositionTracker *m_tracker;
   string            m_gvHb;
   string            m_gvTk;
   double            m_token;
   bool              m_duplicate;
   bool              m_owner;
   bool              m_tester;

   bool              GvSet(const string name,const double v)
     {
      ResetLastError();
      datetime r=GlobalVariableSet(name,v);
      if(r==0)
        {
         m_ctx.logger.Throttled(FTF_LOG_WARN,"mi.gv",60000,"MI","GlobalVariableSet("+name+") failed, error "+
                             IntegerToString(GetLastError()));
         return false;
        }
      return true;
     }

public:
                     CMultiInstanceGuard(void)
     {
      m_ctx=NULL;
      m_tracker=NULL;
      m_gvHb="";
      m_gvTk="";
      m_token=0.0;
      m_duplicate=false;
      m_owner=false;
      m_tester=false;
     }

   bool              Init(CFtfContext *ctx,CPositionTracker *tracker)
     {
      m_ctx=ctx;
      m_tracker=tracker;
      if(CheckPointer(m_ctx)==POINTER_INVALID)
         return false;
      m_tester=m_ctx.pf.IsTester();
      string base=(m_tester ? "FTFT." : "FTF.")+FTF_PLATFORM+"."+IntegerToString(m_ctx.pf.Login())+"."+m_ctx.symbol+
                  ".I"+IntegerToString(m_ctx.instanceId);
      m_gvHb=base+".HB";
      m_gvTk=base+".TK";
      MathSrand((int)(GetMicrosecondCount()%2147483647)+m_ctx.instanceId*7919);
      m_token=(double)MathRand()*32768.0+(double)MathRand()+1.0;
      return true;
     }

   //--- spec Table 12: a second chart with the same Instance ID/symbol/account refuses new entries
   bool              Acquire(string &why)
     {
      why="";
      m_duplicate=false;
      if(m_ctx.cfg.MiGuard==FTF_MI_OFF || m_tester)
        {
         m_owner=false;
         return true;
        }
      if(GlobalVariableCheck(m_gvHb) && GlobalVariableCheck(m_gvTk))
        {
         double hb=GlobalVariableGet(m_gvHb);
         double tk=GlobalVariableGet(m_gvTk);
         double age=(double)TimeLocal()-hb;
         if(age>=0.0 && age<FTF_MI_STALE_SEC && tk!=m_token)
           {
            m_duplicate=true;
            why="Instance ID "+IntegerToString(m_ctx.instanceId)+" already running on "+m_ctx.symbol+
                " (account "+IntegerToString(m_ctx.pf.Login())+") - new entries refused on this chart";
            m_ctx.logger.Error("MI",why);
            m_ctx.Event("INSTANCE","DUPLICATE",why);
            return false;
           }
        }
      GvSet(m_gvTk,m_token);
      GvSet(m_gvHb,(double)TimeLocal());
      m_owner=true;
      m_ctx.logger.Info("MI","instance lock acquired ("+m_gvTk+")");
      return true;
     }

   void              Heartbeat(void)
     {
      if(m_ctx.cfg.MiGuard==FTF_MI_OFF || m_tester)
         return;
      if(m_duplicate)
        {
         //--- retry: the other chart may have been closed
         string why="";
         if(Acquire(why))
           {
            m_ctx.logger.Info("MI","duplicate instance gone - this chart now owns Instance ID "+IntegerToString(m_ctx.instanceId));
            m_ctx.Event("INSTANCE","RESOLVED","lock acquired");
           }
         return;
        }
      //--- another chart took the token over (it saw a stale heartbeat)
      if(GlobalVariableCheck(m_gvTk) && GlobalVariableGet(m_gvTk)!=m_token)
        {
         m_duplicate=true;
         m_owner=false;
         m_ctx.logger.Error("MI","another chart took over Instance ID "+IntegerToString(m_ctx.instanceId)+" - new entries refused");
         m_ctx.Event("INSTANCE","DUPLICATE","token taken over by another chart");
         return;
        }
      GvSet(m_gvHb,(double)TimeLocal());
      if(!GlobalVariableCheck(m_gvTk))
         GvSet(m_gvTk,m_token);
     }

   void              Release(void)
     {
      if(!m_owner || m_tester)
         return;
      if(GlobalVariableCheck(m_gvTk) && GlobalVariableGet(m_gvTk)==m_token)
        {
         GlobalVariableDel(m_gvTk);
         GlobalVariableDel(m_gvHb);
        }
      m_owner=false;
     }

   bool              IsDuplicateInstance(void) { return m_duplicate; }

   //--- BLOCK_DUPLICATES: another instance just opened the same engine/direction near this price
   int               CheckSignal(const SSignal &sig,string &detail)
     {
      detail="";
      if(m_ctx.cfg.MiGuard!=FTF_MI_BLOCK_DUPLICATES)
         return FTF_OK;
      SPosInfo snap[];
      int n=m_ctx.pf.GetPositions(snap,false);
      long now=m_ctx.NowMsc();
      double dist=m_ctx.cfg.DupMinDistAtr*m_ctx.md.AtrM1();
      for(int i=0;i<n;i++)
        {
         if(snap[i].symbol!=m_ctx.symbol || !m_ctx.IsFamilyMagic(snap[i].magic))
            continue;
         if(m_ctx.InstanceFromMagic(snap[i].magic)==m_ctx.instanceId)
            continue;
         if(m_ctx.EngineOfFamilyMagic(snap[i].magic)!=sig.engine || snap[i].dir!=sig.dir)
            continue;
         long age=now-snap[i].openMsc;
         if(age<0 || age>(long)m_ctx.cfg.MiDupWindowSec*1000)
            continue;
         if(MathAbs(snap[i].openPrice-sig.price)<=dist)
           {
            detail="instance "+IntegerToString(m_ctx.InstanceFromMagic(snap[i].magic))+" opened "+FTF_EngineCode(sig.engine)+
                   " "+FTF_DirStr(sig.dir)+" "+DoubleToString((double)age/1000.0,1)+" s ago at "+
                   FTF_D(snap[i].openPrice,m_ctx.md.DigitsCount())+" (ticket "+IntegerToString((long)snap[i].ticket)+")";
            return FTF_REJ_MULTI_INSTANCE;
           }
        }
      return FTF_OK;
     }

   string            Describe(void)
     {
      if(m_ctx.cfg.MiGuard==FTF_MI_OFF)
         return "instance guard OFF";
      if(m_tester)
         return "instance guard (tester: lock skipped)";
      return (m_duplicate ? "DUPLICATE Instance ID - entries refused" : "instance lock OK");
     }

   bool              SelfCheck(string &d)
     {
      Heartbeat();
      d=Describe();
      return !m_duplicate;
     }
  };

#endif // FTF_RISK_MANAGER_MQH
