//+------------------------------------------------------------------+
//|                                                     Platform.mqh |
//|  CPlatform - MetaTrader 4 implementation (MQL4, #property strict)|
//|  Same public API as the MT5 file (docs/09 section 7.5). This is  |
//|  the ONLY MT4-specific file: orders (OrderSend/OrderModify/      |
//|  OrderClose), indicators (iATR/iMA/iADX), MarketInfo, ticks.     |
//|  MT4 limits are documented in docs/08_MT4_Divergences.md:        |
//|  * no tick time_msc -> synthetic monotonic millisecond clock     |
//|  * no CopyTicks     -> one tick per OnTick, no history pre-load  |
//|  * no calendar      -> LoadCalendar returns 0 (CSV / web feed)   |
//|  * no position id   -> the order ticket is the identifier        |
//+------------------------------------------------------------------+
#ifndef FTF_PLATFORM_MQH
#define FTF_PLATFORM_MQH

#include <FranckyTriFlux\Core\Types.mqh>
#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>

#define FTF_PF_SRC               "PF"
#define FTF_PF_MAX_IND           32        // distinct indicator registrations
#define FTF_PF_AMBIG_BACK_SEC    2         // ambiguous result: own order opened at/after request time - 2 s
#define FTF_PF_CLOCK_CAP_MS      60000     // live clock extrapolation cap between two quotes
#define FTF_PF_WEB_ERR_MS        21600000  // WebRequest permission error repeated at most every 6 h
#define FTF_PF_MAX_SESSIONS      16
#define FTF_PF_IND_ATR           1
#define FTF_PF_IND_EMA           2
#define FTF_PF_IND_ADX           3
//--- MT4 trade error codes (own constants: stderror.mqh is not required)
#define FTF_E4_NO_ERROR          0
#define FTF_E4_NO_RESULT         1
#define FTF_E4_COMMON            2
#define FTF_E4_INVALID_PARAMS    3
#define FTF_E4_SERVER_BUSY       4
#define FTF_E4_OLD_VERSION       5
#define FTF_E4_NO_CONNECTION     6
#define FTF_E4_NOT_ENOUGH_RIGHTS 7
#define FTF_E4_TOO_FREQUENT      8
#define FTF_E4_MALFUNCTIONAL     9
#define FTF_E4_ACCOUNT_DISABLED  64
#define FTF_E4_INVALID_ACCOUNT   65
#define FTF_E4_TRADE_TIMEOUT     128
#define FTF_E4_INVALID_PRICE     129
#define FTF_E4_INVALID_STOPS     130
#define FTF_E4_INVALID_VOLUME    131
#define FTF_E4_MARKET_CLOSED     132
#define FTF_E4_TRADE_DISABLED    133
#define FTF_E4_NOT_ENOUGH_MONEY  134
#define FTF_E4_PRICE_CHANGED     135
#define FTF_E4_OFF_QUOTES        136
#define FTF_E4_BROKER_BUSY       137
#define FTF_E4_REQUOTE           138
#define FTF_E4_ORDER_LOCKED      139
#define FTF_E4_LONG_ONLY         140
#define FTF_E4_TOO_MANY_REQUESTS 141
#define FTF_E4_MODIFY_DENIED     145
#define FTF_E4_CONTEXT_BUSY      146
#define FTF_E4_EXPIRATION_DENIED 147
#define FTF_E4_TOO_MANY_ORDERS   148
#define FTF_E4_HEDGE_PROHIBITED  149
#define FTF_E4_FIFO              150
#define FTF_E4_TRADE_NOT_ALLOWED 4109
#define FTF_E4_LONGS_NOT_ALLOWED 4110
#define FTF_E4_SHORTS_NOT_ALLOWED 4111

class CPlatform
  {
private:
   CLogger          *m_log;
   string            m_symbol;
   bool              m_twoStep;
   double            m_point;
   int               m_digits;
   //--- synthetic clock
   long              m_nowMsc;
   datetime          m_clkSec;
   uint              m_clkTick;
   int               m_clkK;
   //--- tick de-duplication
   double            m_lastBid;
   double            m_lastAsk;
   datetime          m_lastTickTime;
   long              m_lastMsc;
   datetime          m_lastTickLocal;
   //--- indicator registry
   int               m_indType[FTF_PF_MAX_IND];
   int               m_indTf[FTF_PF_MAX_IND];
   int               m_indPeriod[FTF_PF_MAX_IND];
   int               m_indCount;
   long              m_lastWebErrMsc;

   void              Log(const int level,const string msg)
     {
      if(CheckPointer(m_log)==POINTER_INVALID)
        {
         if(level<=FTF_LOG_WARN)
            Print("FTF PF | "+msg);
         return;
        }
      if(level<=FTF_LOG_ERROR)      m_log.Error(FTF_PF_SRC,msg);
      else if(level==FTF_LOG_WARN)  m_log.Warn(FTF_PF_SRC,msg);
      else if(level==FTF_LOG_INFO)  m_log.Info(FTF_PF_SRC,msg);
      else if(level==FTF_LOG_DEBUG) m_log.Debug(FTF_PF_SRC,msg);
      else                          m_log.Trace(FTF_PF_SRC,msg);
     }

   string            P(const double v) { return DoubleToString(v,m_digits); }

   double            Nz(const double price)
     {
      if(price<=0.0)
         return 0.0;
      return NormalizeDouble(price,m_digits);
     }

   int               RegisterInd(const int type,const ENUM_TIMEFRAMES tf,const int period)
     {
      for(int i=0;i<m_indCount;i++)
         if(m_indType[i]==type && m_indTf[i]==(int)tf && m_indPeriod[i]==period)
            return i;
      if(m_indCount>=FTF_PF_MAX_IND || period<=0)
        {
         Log(FTF_LOG_ERROR,"indicator registry full or invalid period "+IntegerToString(period));
         return -1;
        }
      m_indType[m_indCount]=type;
      m_indTf[m_indCount]=(int)tf;
      m_indPeriod[m_indCount]=period;
      m_indCount++;
      return m_indCount-1;
     }

   //--- ambiguous result: find our own order (same magic + comment) opened at/after the request
   int               FindRecentOwnOrder(const long magic,const string comment,const int dir,const datetime since)
     {
      int total=OrdersTotal();
      for(int i=total-1;i>=0;i--)
        {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
            continue;
         if(OrderSymbol()!=m_symbol || OrderMagicNumber()!=(int)magic)
            continue;
         if((dir==FTF_DIR_BUY && OrderType()!=OP_BUY) || (dir==FTF_DIR_SELL && OrderType()!=OP_SELL))
            continue;
         if(OrderOpenTime()<since-FTF_PF_AMBIG_BACK_SEC)
            continue;
         if(StringLen(comment)>0 && StringFind(OrderComment(),StringSubstr(comment,0,MathMin(StringLen(comment),20)))<0)
            continue;
         return OrderTicket();
        }
      return -1;
     }

public:
                     CPlatform(void)
     {
      m_log=NULL;
      m_symbol="";
      m_twoStep=false;
      m_point=0.0;
      m_digits=5;
      m_nowMsc=0;
      m_clkSec=0;
      m_clkTick=0;
      m_clkK=0;
      m_lastBid=0.0;
      m_lastAsk=0.0;
      m_lastTickTime=0;
      m_lastMsc=0;
      m_lastTickLocal=0;
      m_indCount=0;
      m_lastWebErrMsc=0;
     }

   //+---------------------------------------------------------------+
   //| lifecycle / environment                                       |
   //+---------------------------------------------------------------+
   bool              Init(CLogger *logger,const string symbol,const bool twoStepStops)
     {
      m_log=logger;
      m_symbol=symbol;
      m_twoStep=twoStepStops;
      m_indCount=0;
      m_nowMsc=0;
      m_lastMsc=0;
      m_lastBid=0.0;
      m_lastAsk=0.0;
      m_lastTickTime=0;
      ResetLastError();
      if(!SymbolSelect(m_symbol,true))
         Log(FTF_LOG_WARN,"SymbolSelect("+m_symbol+",true) failed: "+ErrorText(GetLastError()));
      m_point=MarketInfo(m_symbol,MODE_POINT);
      m_digits=(int)MarketInfo(m_symbol,MODE_DIGITS);
      if(m_point<=0.0)
        {
         Log(FTF_LOG_ERROR,"symbol "+m_symbol+" is unknown to the terminal (point 0) - platform init failed");
         return false;
        }
      Log(FTF_LOG_INFO,"MT4 platform ready | "+m_symbol+" digits "+IntegerToString(m_digits)+" point "+P(m_point)+
          " | two-step stops "+(m_twoStep ? "ON" : "OFF")+(IsTester() ? " | TESTER (synthetic ms clock, fixed spread)" : ""));
      return true;
     }

   void              Deinit(void)
     {
      m_indCount=0;
     }

   string            Name(void)           { return "MT4"; }
   bool              IsTester(void)       { return IsTesting(); }
   bool              IsOptimization(void) { return ::IsOptimization(); }
   bool              IsVisual(void)       { return IsVisualMode(); }
   bool              IsConnected(void)    { return ::IsConnected(); }

   bool              TradeAllowed(string &why)
     {
      why="";
      if(IsTesting())
         return true;
      if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)==0)
        {
         why="AutoTrading button is OFF";
         return false;
        }
      if(!IsExpertEnabled())
        {
         why="Expert Advisors are disabled";
         return false;
        }
      if(MQLInfoInteger(MQL_TRADE_ALLOWED)==0)
        {
         why="'Allow live trading' is not ticked for this EA";
         return false;
        }
      if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)==0)
        {
         why="trading not allowed on this account (investor password?)";
         return false;
        }
      if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)==0)
        {
         why="expert trading disabled by the broker for this account";
         return false;
        }
      return true;
     }

   bool              IsHedging(void)       { return true; }
   long              Login(void)           { return (long)AccountNumber(); }
   string            AccountCurrency(void) { return ::AccountCurrency(); }
   string            Company(void)         { return AccountCompany(); }
   string            Server(void)          { return AccountServer(); }
   double            Balance(void)         { return AccountBalance(); }
   double            Equity(void)          { return AccountEquity(); }
   double            FreeMargin(void)      { return AccountFreeMargin(); }
   double            MarginLevel(void)     { return AccountInfoDouble(ACCOUNT_MARGIN_LEVEL); }

   bool              RefreshSpec(SSymbolSpec &spec)
     {
      spec.name=m_symbol;
      spec.point=MarketInfo(m_symbol,MODE_POINT);
      spec.digits=(int)MarketInfo(m_symbol,MODE_DIGITS);
      spec.tickSize=MarketInfo(m_symbol,MODE_TICKSIZE);
      if(spec.tickSize<=0.0)
         spec.tickSize=spec.point;
      spec.tickValue=MarketInfo(m_symbol,MODE_TICKVALUE);
      spec.contractSize=MarketInfo(m_symbol,MODE_LOTSIZE);
      spec.lotMin=MarketInfo(m_symbol,MODE_MINLOT);
      spec.lotMax=MarketInfo(m_symbol,MODE_MAXLOT);
      spec.lotStep=MarketInfo(m_symbol,MODE_LOTSTEP);
      spec.stopsLevelPts=(int)MarketInfo(m_symbol,MODE_STOPLEVEL);
      spec.freezeLevelPts=(int)MarketInfo(m_symbol,MODE_FREEZELEVEL);
      spec.baseCcy=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_BASE);
      spec.profitCcy=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_PROFIT);
      spec.marginCcy=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_MARGIN);
      long mode=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_MODE);
      spec.canBuy=(mode==SYMBOL_TRADE_MODE_FULL || mode==SYMBOL_TRADE_MODE_LONGONLY);
      spec.canSell=(mode==SYMBOL_TRADE_MODE_FULL || mode==SYMBOL_TRADE_MODE_SHORTONLY);
      spec.tradeAllowed=((spec.canBuy || spec.canSell) && MarketInfo(m_symbol,MODE_TRADEALLOWED)!=0.0);
      if(IsTesting())
         spec.tradeAllowed=true;
      spec.hedging=true;
      if(spec.point>0.0)
        {
         m_point=spec.point;
         m_digits=spec.digits;
        }
      return (spec.point>0.0);
     }

   bool              SymbolTradable(string &why)
     {
      why="";
      long mode=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_MODE);
      if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY)
        {
         why="symbol trade mode "+(mode==SYMBOL_TRADE_MODE_DISABLED ? "DISABLED" : "CLOSE ONLY");
         return false;
        }
      if(IsTesting())
         return true;
      if(MarketInfo(m_symbol,MODE_TRADEALLOWED)==0.0)
        {
         why="trading not allowed for "+m_symbol+" now";
         return false;
        }
      //--- trade sessions of the current weekday (no session defined = always open)
      datetime srv=TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(srv,dt);
      int secOfDay=dt.hour*3600+dt.min*60+dt.sec;
      bool any=false;
      for(int i=0;i<FTF_PF_MAX_SESSIONS;i++)
        {
         datetime from=0;
         datetime to=0;
         if(!SymbolInfoSessionTrade(m_symbol,(ENUM_DAY_OF_WEEK)dt.day_of_week,(uint)i,from,to))
            break;
         any=true;
         int f=(int)((long)from%86400);
         int t=(int)((long)to%86400);
         if((long)to>=86400)
            t=86400;
         if(secOfDay>=f && secOfDay<t)
            return true;
        }
      if(!any)
         return true;
      why="outside the broker trade session";
      return false;
     }

   //+---------------------------------------------------------------+
   //| time                                                          |
   //+---------------------------------------------------------------+
   datetime          ServerTime(void) { return TimeCurrent(); }

   //--- MT4 has no tick milliseconds: monotonic synthetic clock (docs/08 item 1)
   long              NowMsc(void)
     {
      datetime tc=TimeCurrent();
      long base=(long)tc*1000;
      long v=base;
      if(IsTesting())
        {
         if(tc!=m_clkSec)
           {
            m_clkSec=tc;
            m_clkK=0;
           }
         v=base+(long)MathMin(999,m_clkK);
        }
      else
        {
         uint tk=GetTickCount();
         if(tc!=m_clkSec)
           {
            m_clkSec=tc;
            m_clkTick=tk;
           }
         long sub=(long)(uint)(tk-m_clkTick);
         if(sub>FTF_PF_CLOCK_CAP_MS)
            sub=FTF_PF_CLOCK_CAP_MS;
         v=base+sub;
        }
      if(v<m_nowMsc)
         v=m_nowMsc;
      m_nowMsc=v;
      return v;
     }

   bool              AutoGmtOffset(long &secs)
     {
      secs=0;
      if(IsTesting())
         return false;
      if(m_lastTickLocal<=0 || (long)TimeLocal()-(long)m_lastTickLocal>300)
         return false;
      datetime g=TimeGMT();
      if(g<=0)
         return false;
      long d=(long)TimeCurrent()-(long)g;
      secs=(long)MathRound((double)d/900.0)*900;
      return true;
     }

   ulong             Micros(void) { return GetMicrosecondCount(); }

   //+---------------------------------------------------------------+
   //| ticks                                                         |
   //+---------------------------------------------------------------+
   int               FetchNewTicks(STick &out[],const int maxCount)
     {
      ArrayResize(out,0);
      if(maxCount<=0)
         return 0;
      RefreshRates();
      MqlTick t;
      if(!SymbolInfoTick(m_symbol,t) || t.bid<=0.0)
         return 0;
      bool changed=(t.bid!=m_lastBid || t.ask!=m_lastAsk || t.time!=m_lastTickTime);
      if(!changed)
         return 0;
      if(IsTesting())
        {
         if(t.time==m_clkSec)
            m_clkK++;
         else
           {
            m_clkSec=t.time;
            m_clkK=0;
           }
        }
      long msc=NowMsc();
      if(msc<=m_lastMsc)
         msc=m_lastMsc+1;
      if(msc>m_nowMsc)
         m_nowMsc=msc;
      ArrayResize(out,1);
      out[0].Reset();
      out[0].msc=msc;
      out[0].bid=t.bid;
      out[0].ask=t.ask;
      m_lastBid=t.bid;
      m_lastAsk=t.ask;
      m_lastTickTime=t.time;
      m_lastMsc=msc;
      m_lastTickLocal=TimeLocal();
      return 1;
     }

   //--- MT4 has no tick history: Momentum warms up on live ticks (docs/08 item 2)
   int               PreloadTicks(STick &out[],const int seconds)
     {
      ArrayResize(out,0);
      return 0;
     }

   bool              CurrentTick(STick &t)
     {
      t.Reset();
      MqlTick q;
      if(!SymbolInfoTick(m_symbol,q) || q.bid<=0.0)
         return false;
      t.msc=NowMsc();
      t.bid=q.bid;
      t.ask=q.ask;
      return true;
     }

   //+---------------------------------------------------------------+
   //| bars and indicators                                           |
   //+---------------------------------------------------------------+
   datetime          BarTime(const ENUM_TIMEFRAMES tf,const int shift)  { return iTime(m_symbol,tf,shift); }
   double            BarOpen(const ENUM_TIMEFRAMES tf,const int shift)  { return iOpen(m_symbol,tf,shift); }
   double            BarHigh(const ENUM_TIMEFRAMES tf,const int shift)  { return iHigh(m_symbol,tf,shift); }
   double            BarLow(const ENUM_TIMEFRAMES tf,const int shift)   { return iLow(m_symbol,tf,shift); }
   double            BarClose(const ENUM_TIMEFRAMES tf,const int shift) { return iClose(m_symbol,tf,shift); }
   int               BarsCount(const ENUM_TIMEFRAMES tf)                { return iBars(m_symbol,tf); }

   int               RegisterATR(const ENUM_TIMEFRAMES tf,const int period) { return RegisterInd(FTF_PF_IND_ATR,tf,period); }
   int               RegisterEMA(const ENUM_TIMEFRAMES tf,const int period) { return RegisterInd(FTF_PF_IND_EMA,tf,period); }
   int               RegisterADX(const ENUM_TIMEFRAMES tf,const int period) { return RegisterInd(FTF_PF_IND_ADX,tf,period); }

   double            IndValue(const int id,const int buffer,const int shift)
     {
      if(id<0 || id>=m_indCount || shift<0)
         return EMPTY_VALUE;
      int tf=m_indTf[id];
      int period=m_indPeriod[id];
      if(iBars(m_symbol,tf)<period+shift+2)
         return EMPTY_VALUE;
      double v=0.0;
      switch(m_indType[id])
        {
         case FTF_PF_IND_ATR:
            v=iATR(m_symbol,tf,period,shift);
            break;
         case FTF_PF_IND_EMA:
            v=iMA(m_symbol,tf,period,0,MODE_EMA,PRICE_CLOSE,shift);
            break;
         case FTF_PF_IND_ADX:
           {
            int mode=MODE_MAIN;
            if(buffer==1)
               mode=MODE_PLUSDI;
            else
               if(buffer==2)
                  mode=MODE_MINUSDI;
            v=iADX(m_symbol,tf,period,PRICE_CLOSE,mode,shift);
            break;
           }
         default:
            return EMPTY_VALUE;
        }
      if(!MathIsValidNumber(v))
         return EMPTY_VALUE;
      return v;
     }

   bool              IndReady(const int id)
     {
      if(id<0 || id>=m_indCount)
         return false;
      return (iBars(m_symbol,m_indTf[id])>m_indPeriod[id]+2);
     }

   //--- other symbols are not modelled by the MT4 tester (docs/08 item 14)
   bool              OtherSymbolCloses(const string sym,const ENUM_TIMEFRAMES tf,const int count,double &closes[])
     {
      ArrayResize(closes,0);
      if(IsTesting() || count<=0)
         return false;
      if(iBars(sym,tf)<count+1)
         return false;
      ArrayResize(closes,count);
      for(int i=0;i<count;i++)
        {
         closes[i]=iClose(sym,tf,i+1);
         if(closes[i]<=0.0)
           {
            ArrayResize(closes,0);
            return false;
           }
        }
      return true;
     }

   bool              OtherSymbolCurrencies(const string sym,string &baseCcy,string &profitCcy)
     {
      baseCcy=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
      profitCcy=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
      return (StringLen(baseCcy)>0 && StringLen(profitCcy)>0);
     }

   //--- money lost by 1 lot from entry to sl (account currency, > 0)
   double            LossPerLot(const string sym,const int dir,const double entry,const double sl)
     {
      double ts=MarketInfo(sym,MODE_TICKSIZE);
      if(ts<=0.0)
         ts=MarketInfo(sym,MODE_POINT);
      double tv=MarketInfo(sym,MODE_TICKVALUE);
      if(ts<=0.0 || tv<=0.0 || entry<=0.0 || sl<=0.0)
         return 0.0;
      return MathAbs(entry-sl)/ts*tv;
     }

   double            MarginRequired(const int dir,const double lots,const double price)
     {
      double m=MarketInfo(m_symbol,MODE_MARGINREQUIRED);
      return (m>0.0 ? m*lots : 0.0);
     }

   //+---------------------------------------------------------------+
   //| positions / history                                           |
   //+---------------------------------------------------------------+
   int               GetPositions(SPosInfo &out[],const bool allSymbols)
     {
      ArrayResize(out,0);
      int n=0;
      int total=OrdersTotal();
      for(int i=0;i<total;i++)
        {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
            continue;
         int type=OrderType();
         if(type!=OP_BUY && type!=OP_SELL)
            continue;
         if(!allSymbols && OrderSymbol()!=m_symbol)
            continue;
         ArrayResize(out,n+1);
         out[n].Reset();
         out[n].ticket=(ulong)OrderTicket();
         out[n].positionId=(long)OrderTicket();
         out[n].symbol=OrderSymbol();
         out[n].magic=(long)OrderMagicNumber();
         out[n].dir=(type==OP_BUY ? FTF_DIR_BUY : FTF_DIR_SELL);
         out[n].lots=OrderLots();
         out[n].openPrice=OrderOpenPrice();
         out[n].sl=OrderStopLoss();
         out[n].tp=OrderTakeProfit();
         out[n].openMsc=(long)OrderOpenTime()*1000;
         out[n].profit=OrderProfit();
         out[n].swap=OrderSwap();
         out[n].comment=OrderComment();
         n++;
        }
      return n;
     }

   bool              GetClosedTrade(const ulong ticket,const long positionId,SClosedTrade &out)
     {
      out.Reset();
      out.ticket=ticket;
      out.positionId=positionId;
      if(!OrderSelect((int)ticket,SELECT_BY_TICKET))
         return false;
      if(OrderCloseTime()<=0)
         return false;   // still open
      out.found=true;
      out.closePrice=OrderClosePrice();
      out.closeMsc=(long)OrderCloseTime()*1000;
      out.profit=OrderProfit();
      out.commission=OrderCommission();
      out.swap=OrderSwap();
      out.net=out.profit+out.commission+out.swap;
      string c=OrderComment();
      double sl=OrderStopLoss();
      double tp=OrderTakeProfit();
      double ts=MarketInfo(OrderSymbol(),MODE_TICKSIZE);
      if(ts<=0.0)
         ts=m_point;
      if(StringFind(c,"[sl]")>=0)
         out.exitReason=FTF_EXIT_SL;
      else
         if(StringFind(c,"[tp]")>=0)
            out.exitReason=FTF_EXIT_TP;
         else
            if(StringFind(c,"so:")==0)
               out.exitReason=FTF_EXIT_STOP_OUT;
            else
               if(sl>0.0 && MathAbs(out.closePrice-sl)<=ts*1.5)
                  out.exitReason=FTF_EXIT_SL;
               else
                  if(tp>0.0 && MathAbs(out.closePrice-tp)<=ts*1.5)
                     out.exitReason=FTF_EXIT_TP;
                  else
                     out.exitReason=FTF_EXIT_UNKNOWN;
      out.exitDetail="MT4 close comment '"+c+"'";
      return true;
     }

   //+---------------------------------------------------------------+
   //| trading                                                       |
   //+---------------------------------------------------------------+
   bool              OpenMarket(const int dir,const double lots,const double sl,const double tp,const long magic,
                                const string comment,const int deviationPts,SExecResult &res)
     {
      res.Reset();
      res.lots=lots;
      if(dir!=FTF_DIR_BUY && dir!=FTF_DIR_SELL)
        {
         res.retcode=FTF_E4_INVALID_PARAMS;
         res.retcodeText=ErrorText(res.retcode);
         res.errClass=FTF_ERR_PERMANENT;
         return false;
        }
      if(IsTradeContextBusy())
        {
         res.retcode=FTF_E4_CONTEXT_BUSY;
         res.retcodeText=ErrorText(res.retcode);
         res.errClass=FTF_ERR_TRANSIENT;
         Log(FTF_LOG_WARN,"trade context busy - order not sent");
         return false;
        }
      RefreshRates();
      double price=Nz(MarketInfo(m_symbol,(dir==FTF_DIR_BUY ? MODE_ASK : MODE_BID)));
      double sl2=(m_twoStep ? 0.0 : Nz(sl));
      double tp2=(m_twoStep ? 0.0 : Nz(tp));
      int dev=(deviationPts>0 ? deviationPts : 10);
      datetime reqTime=TimeCurrent();
      res.requestedPrice=price;
      ulong t0=GetMicrosecondCount();
      ResetLastError();
      int ticket=OrderSend(m_symbol,(dir==FTF_DIR_BUY ? OP_BUY : OP_SELL),lots,price,dev,sl2,tp2,comment,(int)magic,0,clrNONE);
      int err=GetLastError();
      res.latencyMs=(double)(GetMicrosecondCount()-t0)/1000.0;
      if(ticket<=0 && (err==FTF_E4_TRADE_TIMEOUT || err==FTF_E4_NO_RESULT || err==FTF_E4_COMMON))
        {
         int found=FindRecentOwnOrder(magic,comment,dir,reqTime);
         if(found>0)
           {
            Log(FTF_LOG_WARN,"ambiguous result "+ErrorText(err)+" reconciled: order #"+IntegerToString(found)+" exists");
            ticket=found;
           }
        }
      if(ticket<=0)
        {
         res.retcode=err;
         res.retcodeText=ErrorText(err);
         res.errClass=ClassifyError(err);
         Log(FTF_LOG_WARN,"OPEN "+FTF_DirStr(dir)+" "+m_symbol+" "+DoubleToString(lots,2)+" @"+P(price)+" sl "+P(sl)+" tp "+P(tp)+
             " magic "+IntegerToString(magic)+" FAILED: "+res.retcodeText+" ("+DoubleToString(res.latencyMs,1)+" ms)");
         return false;
        }
      res.ok=true;
      res.retcode=FTF_E4_NO_ERROR;
      res.ticket=(ulong)ticket;
      res.positionId=(long)ticket;
      res.fillPrice=price;
      if(OrderSelect(ticket,SELECT_BY_TICKET))
        {
         res.fillPrice=OrderOpenPrice();
         res.lots=OrderLots();
        }
      res.retcodeText="done";
      //--- two-step stops (ECN): attach SL/TP right after the fill
      if(m_twoStep && (sl>0.0 || tp>0.0))
        {
         ResetLastError();
         bool mod=false;
         if(OrderSelect(ticket,SELECT_BY_TICKET))
            mod=OrderModify(ticket,OrderOpenPrice(),Nz(sl),Nz(tp),0,clrNONE);
         if(!mod)
           {
            int e2=GetLastError();
            res.retcodeText="done | STOPS NOT ATTACHED: "+ErrorText(e2);
            Log(FTF_LOG_ERROR,"order #"+IntegerToString(ticket)+" opened but SL/TP not attached: "+ErrorText(e2));
           }
        }
      Log(FTF_LOG_INFO,"OPEN "+FTF_DirStr(dir)+" "+m_symbol+" #"+IntegerToString(ticket)+" "+DoubleToString(res.lots,2)+
          " req "+P(price)+" fill "+P(res.fillPrice)+" sl "+P(sl)+" tp "+P(tp)+" magic "+IntegerToString(magic)+
          " ["+comment+"] "+DoubleToString(res.latencyMs,1)+" ms");
      return true;
     }

   bool              ModifyPosition(const ulong ticket,const double sl,const double tp,SExecResult &res)
     {
      res.Reset();
      res.ticket=ticket;
      if(!OrderSelect((int)ticket,SELECT_BY_TICKET,MODE_TRADES) || OrderCloseTime()>0)
        {
         res.retcode=4108;
         res.retcodeText="position not found / closed";
         res.errClass=FTF_ERR_PERMANENT;
         return false;
        }
      double nsl=Nz(sl);
      double ntp=Nz(tp);
      if(MathAbs(OrderStopLoss()-nsl)<m_point*0.5 && MathAbs(OrderTakeProfit()-ntp)<m_point*0.5)
        {
         res.ok=true;
         res.retcodeText="no changes";
         return true;
        }
      ulong t0=GetMicrosecondCount();
      ResetLastError();
      bool ok=OrderModify((int)ticket,OrderOpenPrice(),nsl,ntp,0,clrNONE);
      int err=GetLastError();
      res.latencyMs=(double)(GetMicrosecondCount()-t0)/1000.0;
      if(!ok && err!=FTF_E4_NO_RESULT)
        {
         res.retcode=err;
         res.retcodeText=ErrorText(err);
         res.errClass=ClassifyError(err);
         Log(FTF_LOG_WARN,"MODIFY #"+IntegerToString((long)ticket)+" sl "+P(nsl)+" tp "+P(ntp)+" FAILED: "+res.retcodeText);
         return false;
        }
      res.ok=true;
      res.retcodeText="done";
      Log(FTF_LOG_DEBUG,"MODIFY #"+IntegerToString((long)ticket)+" sl "+P(nsl)+" tp "+P(ntp)+" "+
          DoubleToString(res.latencyMs,1)+" ms");
      return true;
     }

   bool              ClosePosition(const ulong ticket,const double lots,const int deviationPts,SExecResult &res)
     {
      res.Reset();
      res.ticket=ticket;
      if(!OrderSelect((int)ticket,SELECT_BY_TICKET) || OrderCloseTime()>0)
        {
         res.ok=true;
         res.retcodeText="already closed";
         return true;
        }
      if(IsTradeContextBusy())
        {
         res.retcode=FTF_E4_CONTEXT_BUSY;
         res.retcodeText=ErrorText(res.retcode);
         res.errClass=FTF_ERR_TRANSIENT;
         return false;
        }
      RefreshRates();
      if(!OrderSelect((int)ticket,SELECT_BY_TICKET))
        {
         res.ok=true;
         res.retcodeText="already closed";
         return true;
        }
      bool isBuy=(OrderType()==OP_BUY);
      double price=Nz(MarketInfo(m_symbol,(isBuy ? MODE_BID : MODE_ASK)));
      double vol=OrderLots();
      if(lots>0.0 && lots<vol)
         vol=lots;
      int dev=(deviationPts>0 ? deviationPts : 10);
      res.requestedPrice=price;
      ulong t0=GetMicrosecondCount();
      ResetLastError();
      bool ok=OrderClose((int)ticket,vol,price,dev,clrNONE);
      int err=GetLastError();
      res.latencyMs=(double)(GetMicrosecondCount()-t0)/1000.0;
      if(!ok)
        {
         if(OrderSelect((int)ticket,SELECT_BY_TICKET) && OrderCloseTime()>0)
           {
            res.ok=true;
            res.retcodeText="closed (late confirmation)";
            return true;
           }
         res.retcode=err;
         res.retcodeText=ErrorText(err);
         res.errClass=ClassifyError(err);
         Log(FTF_LOG_WARN,"CLOSE #"+IntegerToString((long)ticket)+" "+DoubleToString(vol,2)+" @"+P(price)+" FAILED: "+res.retcodeText);
         return false;
        }
      res.ok=true;
      res.lots=vol;
      res.fillPrice=price;
      res.retcodeText="done";
      Log(FTF_LOG_INFO,"CLOSE #"+IntegerToString((long)ticket)+" "+DoubleToString(vol,2)+" @"+P(price)+" "+
          DoubleToString(res.latencyMs,1)+" ms");
      return true;
     }

   int               ClassifyError(const int code)
     {
      switch(code)
        {
         case FTF_E4_NO_ERROR:
            return FTF_ERR_NONE;
         case FTF_E4_NO_RESULT:
         case FTF_E4_SERVER_BUSY:
         case FTF_E4_NO_CONNECTION:
         case FTF_E4_TOO_FREQUENT:
         case FTF_E4_TRADE_TIMEOUT:
         case FTF_E4_INVALID_PRICE:
         case FTF_E4_PRICE_CHANGED:
         case FTF_E4_OFF_QUOTES:
         case FTF_E4_BROKER_BUSY:
         case FTF_E4_REQUOTE:
         case FTF_E4_ORDER_LOCKED:
         case FTF_E4_TOO_MANY_REQUESTS:
         case FTF_E4_CONTEXT_BUSY:
            return FTF_ERR_TRANSIENT;
         case FTF_E4_ACCOUNT_DISABLED:
         case FTF_E4_INVALID_ACCOUNT:
         case FTF_E4_MARKET_CLOSED:
         case FTF_E4_TRADE_DISABLED:
         case FTF_E4_NOT_ENOUGH_MONEY:
         case FTF_E4_LONG_ONLY:
         case FTF_E4_TOO_MANY_ORDERS:
         case FTF_E4_HEDGE_PROHIBITED:
         case FTF_E4_FIFO:
         case FTF_E4_TRADE_NOT_ALLOWED:
         case FTF_E4_LONGS_NOT_ALLOWED:
         case FTF_E4_SHORTS_NOT_ALLOWED:
            return FTF_ERR_FATAL;
         default:
            break;
        }
      return FTF_ERR_PERMANENT;
     }

   string            ErrorText(const int code)
     {
      string n="";
      switch(code)
        {
         case FTF_E4_NO_ERROR:          n="NO_ERROR"; break;
         case FTF_E4_NO_RESULT:         n="NO_RESULT"; break;
         case FTF_E4_COMMON:            n="COMMON_ERROR"; break;
         case FTF_E4_INVALID_PARAMS:    n="INVALID_TRADE_PARAMETERS"; break;
         case FTF_E4_SERVER_BUSY:       n="SERVER_BUSY"; break;
         case FTF_E4_OLD_VERSION:       n="OLD_VERSION"; break;
         case FTF_E4_NO_CONNECTION:     n="NO_CONNECTION"; break;
         case FTF_E4_NOT_ENOUGH_RIGHTS: n="NOT_ENOUGH_RIGHTS"; break;
         case FTF_E4_TOO_FREQUENT:      n="TOO_FREQUENT_REQUESTS"; break;
         case FTF_E4_MALFUNCTIONAL:     n="MALFUNCTIONAL_TRADE"; break;
         case FTF_E4_ACCOUNT_DISABLED:  n="ACCOUNT_DISABLED"; break;
         case FTF_E4_INVALID_ACCOUNT:   n="INVALID_ACCOUNT"; break;
         case FTF_E4_TRADE_TIMEOUT:     n="TRADE_TIMEOUT"; break;
         case FTF_E4_INVALID_PRICE:     n="INVALID_PRICE"; break;
         case FTF_E4_INVALID_STOPS:     n="INVALID_STOPS"; break;
         case FTF_E4_INVALID_VOLUME:    n="INVALID_TRADE_VOLUME"; break;
         case FTF_E4_MARKET_CLOSED:     n="MARKET_CLOSED"; break;
         case FTF_E4_TRADE_DISABLED:    n="TRADE_DISABLED"; break;
         case FTF_E4_NOT_ENOUGH_MONEY:  n="NOT_ENOUGH_MONEY"; break;
         case FTF_E4_PRICE_CHANGED:     n="PRICE_CHANGED"; break;
         case FTF_E4_OFF_QUOTES:        n="OFF_QUOTES"; break;
         case FTF_E4_BROKER_BUSY:       n="BROKER_BUSY"; break;
         case FTF_E4_REQUOTE:           n="REQUOTE"; break;
         case FTF_E4_ORDER_LOCKED:      n="ORDER_LOCKED"; break;
         case FTF_E4_LONG_ONLY:         n="LONG_POSITIONS_ONLY_ALLOWED"; break;
         case FTF_E4_TOO_MANY_REQUESTS: n="TOO_MANY_REQUESTS"; break;
         case FTF_E4_MODIFY_DENIED:     n="TRADE_MODIFY_DENIED"; break;
         case FTF_E4_CONTEXT_BUSY:      n="TRADE_CONTEXT_BUSY"; break;
         case FTF_E4_EXPIRATION_DENIED: n="TRADE_EXPIRATION_DENIED"; break;
         case FTF_E4_TOO_MANY_ORDERS:   n="TRADE_TOO_MANY_ORDERS"; break;
         case FTF_E4_HEDGE_PROHIBITED:  n="TRADE_HEDGE_PROHIBITED"; break;
         case FTF_E4_FIFO:              n="TRADE_PROHIBITED_BY_FIFO"; break;
         case FTF_E4_TRADE_NOT_ALLOWED: n="TRADE_NOT_ALLOWED"; break;
         case FTF_E4_LONGS_NOT_ALLOWED: n="LONGS_NOT_ALLOWED"; break;
         case FTF_E4_SHORTS_NOT_ALLOWED:n="SHORTS_NOT_ALLOWED"; break;
         default:                       break;
        }
      if(StringLen(n)==0)
         return "error "+IntegerToString(code);
      return n+" ("+IntegerToString(code)+")";
     }

   //+---------------------------------------------------------------+
   //| news                                                          |
   //+---------------------------------------------------------------+
   //--- MT4 has no economic calendar: the Core uses the CSV file or the web feed (docs/08 item 5)
   int               LoadCalendar(const datetime fromSrv,const datetime toSrv,const string &currencies[],const int nCcy,SNewsEvent &out[])
     {
      ArrayResize(out,0);
      return 0;
     }

   bool              HttpGet(const string url,const int timeoutMs,string &body,int &httpCode)
     {
      body="";
      httpCode=0;
      if(IsTesting() || IsOptimization())
         return false;
      char data[];
      char result[];
      string headers="";
      ResetLastError();
      int r=WebRequest("GET",url,"",timeoutMs,data,result,headers);
      if(r==-1)
        {
         int err=GetLastError();
         httpCode=-1;
         long now=(long)TimeLocal()*1000;
         if(m_lastWebErrMsc==0 || now-m_lastWebErrMsc>FTF_PF_WEB_ERR_MS)
           {
            m_lastWebErrMsc=now;
            Log(FTF_LOG_ERROR,"WebRequest "+url+" failed (error "+IntegerToString(err)+
                ") - add the URL in Tools > Options > Expert Advisors > 'Allow WebRequest for listed URL'");
           }
         return false;
        }
      httpCode=r;
      body=CharArrayToString(result,0,WHOLE_ARRAY,CP_UTF8);
      return (r>=200 && r<300);
     }
  };

#endif // FTF_PLATFORM_MQH
