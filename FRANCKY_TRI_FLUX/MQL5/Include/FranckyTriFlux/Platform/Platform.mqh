//+------------------------------------------------------------------+
//|                                                     Platform.mqh |
//|  CPlatform - MetaTrader 5 implementation (docs/09 section 7.5).  |
//|  The ONLY MT5 file that calls trading / market / account /       |
//|  history / indicator / calendar / web APIs. Its MQL4 twin        |
//|  (MQL4/Include/FranckyTriFlux/Platform/Platform.mqh) exposes the |
//|  same public methods so the shared Core compiles unchanged.      |
//|                                                                  |
//|  Key MT5 facts used here (research notes "mql5-trade"):          |
//|  * CTrade Buy/Sell/PositionModify/PositionClose returning true   |
//|    is NOT success: ResultRetcode() must be DONE/PLACED/PARTIAL.  |
//|  * ResultPrice()/ResultDeal() may be 0 -> DEAL_PRICE fallback.   |
//|  * TIMEOUT/ERROR/REJECT are ambiguous: the order may be filled.  |
//|  * CopyTicks 'from' is inclusive -> remember how many ticks of   |
//|    the last millisecond were already consumed.                   |
//|  * Calendar API: server time, not in the tester, <=30 day calls. |
//+------------------------------------------------------------------+
#ifndef FTF_PLATFORM_MQH
#define FTF_PLATFORM_MQH

#include <FranckyTriFlux\Core\Types.mqh>
#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>
#include <Trade\Trade.mqh>

#define FTF_PF_SRC               "PF"       // log source tag of the platform layer
#define FTF_PF_MAX_IND           32         // TUNABLE (not an input yet) - distinct indicator registrations (type,tf,period)
#define FTF_PF_TICK_BATCH        4096       // TUNABLE (not an input yet) - ticks per FetchNewTicks call when maxCount<=0
#define FTF_PF_TICK_GAP_MS       60000      // TUNABLE (not an input yet) - unread tick backlog older than this is skipped (reconnect/weekend)
#define FTF_PF_AMBIG_BACK_MS     2000       // ambiguous result: own position opened at/after request time - 2 s = our fill
#define FTF_PF_AMBIG_RECHECK_MS  250        // TUNABLE (not an input yet) - live: wait before the second ambiguous scan
#define FTF_PF_AMBIG_MEMORY_MS   30000      // TUNABLE (not an input yet) - a retry with the same magic+comment re-scans first
#define FTF_PF_CAL_CHUNK_SEC     2592000    // 30 days: longer CalendarValueHistory windows time out (build 5327+)
#define FTF_PF_DEF_DEVIATION     10         // TUNABLE (not an input yet) - deviation (points) used when the caller passes <=0
#define FTF_PF_WEB_ERR_MS        21600000   // the WebRequest permission error is repeated at most every 6 h
#define FTF_PF_MAX_SESSIONS      16         // trade sessions scanned per weekday
#define FTF_PF_IND_ATR           1
#define FTF_PF_IND_EMA           2
#define FTF_PF_IND_ADX           3
#define FTF_PF_ERR_POS_NOT_FOUND 4753       // ERR_TRADE_POSITION_NOT_FOUND
#define FTF_PF_ERR_SEND_FAILED   4756       // ERR_TRADE_SEND_FAILED
#define FTF_PF_ERR_CAL_NO_DATA   5402       // ERR_CALENDAR_NO_DATA

class CPlatform
  {
private:
   CLogger          *m_log;
   string            m_symbol;          // chart symbol captured at OnInit (docs/09 principle 5)
   bool              m_twoStep;         // open without SL/TP, attach them right after the fill
   CTrade            m_trade;
   double            m_point;
   int               m_digits;
   int               m_lotDigits;
   //--- clock and tick stream
   long              m_nowMsc;          // last value returned by NowMsc() (monotonic)
   long              m_lastMsc;         // time_msc of the newest tick handed out
   int               m_seenAtLast;      // ticks already handed out at m_lastMsc (CopyTicks 'from' is inclusive)
   bool              m_skipAllAtLast;   // m_lastMsc came from a SymbolInfoTick snapshot: skip every tick of that ms
   double            m_lastBid;
   double            m_lastAsk;
   //--- indicator registry (parallel fixed arrays, index = public id)
   int               m_indCount;
   int               m_indType[FTF_PF_MAX_IND];
   ENUM_TIMEFRAMES   m_indTf[FTF_PF_MAX_IND];
   int               m_indPeriod[FTF_PF_MAX_IND];
   int               m_indHandle[FTF_PF_MAX_IND];
   //--- calendar event-type cache (CalendarEventById results)
   int               m_evCount;
   ulong             m_evId[];
   int               m_evImp[];
   int               m_evMode[];
   string            m_evName[];
   //--- last open request with an ambiguous result (duplicate protection on retry)
   bool              m_ambActive;
   long              m_ambMagic;
   int               m_ambDir;
   string            m_ambComment;
   long              m_ambSinceMsc;
   ulong             m_ambExpireUs;

   //+---------------------------------------------------------------+
   //| logging (m_log may still be NULL before Init)                 |
   //+---------------------------------------------------------------+
   void              Log(const int level,const string msg)
     {
      if(CheckPointer(m_log)==POINTER_INVALID)
         return;
      switch(level)
        {
         case FTF_LOG_ERROR: m_log.Error(FTF_PF_SRC,msg); break;
         case FTF_LOG_WARN:  m_log.Warn(FTF_PF_SRC,msg);  break;
         case FTF_LOG_INFO:  m_log.Info(FTF_PF_SRC,msg);  break;
         case FTF_LOG_DEBUG: m_log.Debug(FTF_PF_SRC,msg); break;
         default:            m_log.Trace(FTF_PF_SRC,msg); break;
        }
     }

   void              LogThr(const int level,const string key,const int intervalMs,const string msg)
     {
      if(CheckPointer(m_log)==POINTER_INVALID)
         return;
      m_log.Throttled(level,"PF."+key,intervalMs,FTF_PF_SRC,msg);
     }

   string            Px(const double p)       { return FTF_D(p,m_digits); }
   string            LotStr(const double v)   { return FTF_D(v,m_lotDigits); }
   string            MsStr(const double ms)   { return FTF_D(ms,1)+" ms"; }

   string            ErrClassStr(const int c)
     {
      if(c==FTF_ERR_NONE)
         return "OK";
      if(c==FTF_ERR_TRANSIENT)
         return "TRANSIENT";
      if(c==FTF_ERR_FATAL)
         return "FATAL";
      return "PERMANENT";
     }

   //--- MT5 success retcodes of a trade request
   bool              RcSuccess(const int rc)
     {
      return (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_DONE_PARTIAL);
     }

   //--- results that do not prove the order was NOT executed (research: reconcile before any resend)
   bool              IsAmbiguous(const int rc)
     {
      return (rc==TRADE_RETCODE_TIMEOUT || rc==TRADE_RETCODE_ERROR || rc==TRADE_RETCODE_REJECT);
     }

   //--- direction of the currently selected position
   int               PosDir(void)
     {
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
         return FTF_DIR_BUY;
      return FTF_DIR_SELL;
     }

   string            SecStr(const long s)
     {
      return StringFormat("%02d:%02d",(int)(s/3600),(int)((s%3600)/60));
     }

   //--- local refusal (nothing sent to the server)
   bool              Reject(SExecResult &res,const int code,const string msg)
     {
      res.ok=false;
      res.retcode=code;
      res.retcodeText=ErrorText(code)+" - "+msg;
      res.errClass=FTF_ERR_PERMANENT;
      Log(FTF_LOG_ERROR,msg);
      return false;
     }

   void              ResetState(void)
     {
      m_nowMsc=0;
      m_lastMsc=0;
      m_seenAtLast=0;
      m_skipAllAtLast=false;
      m_lastBid=0.0;
      m_lastAsk=0.0;
      m_evCount=0;
      ArrayResize(m_evId,0);
      ArrayResize(m_evImp,0);
      ArrayResize(m_evMode,0);
      ArrayResize(m_evName,0);
      m_ambActive=false;
      m_ambMagic=0;
      m_ambDir=FTF_DIR_NONE;
      m_ambComment="";
      m_ambSinceMsc=0;
      m_ambExpireUs=0;
     }

   //+---------------------------------------------------------------+
   //| ticks                                                         |
   //+---------------------------------------------------------------+
   //--- one tick from SymbolInfoTick, only if time/bid/ask changed (first call, tester, CopyTicks failure)
   int               FetchSnapshotTick(STick &out[])
     {
      ArrayResize(out,0);
      MqlTick q;
      ZeroMemory(q);
      if(!SymbolInfoTick(m_symbol,q))
         return 0;
      if(q.bid<=0.0 || q.time_msc<=0 || q.time_msc<m_lastMsc)
         return 0;
      if(q.time_msc==m_lastMsc && q.bid==m_lastBid && q.ask==m_lastAsk)
         return 0;
      ArrayResize(out,1);
      out[0].msc=q.time_msc;
      out[0].bid=q.bid;
      out[0].ask=q.ask;
      out[0].dir=0;
      if(m_lastBid>0.0)
         out[0].dir=(q.bid>m_lastBid ? 1 : (q.bid<m_lastBid ? -1 : 0));
      if(q.time_msc==m_lastMsc)
        {
         if(!m_skipAllAtLast)
            m_seenAtLast++;
        }
      else
        {
         //--- how many CopyTicks ticks share this ms is unknown: skip them all next time (no duplicates)
         m_lastMsc=q.time_msc;
         m_seenAtLast=0;
         m_skipAllAtLast=true;
        }
      m_lastBid=q.bid;
      m_lastAsk=q.ask;
      return 1;
     }

   //--- hands out arr[] minus the ticks already consumed at m_lastMsc, updates the dedupe state
   int               ConsumeTicks(const MqlTick &arr[],const int n,const int cap,STick &out[])
     {
      ArrayResize(out,0);
      int i=0;
      while(i<n && arr[i].time_msc<m_lastMsc)
         i++;
      int skipped=0;
      while(i<n && arr[i].time_msc==m_lastMsc && (m_skipAllAtLast || skipped<m_seenAtLast))
        {
         i++;
         skipped++;
        }
      int first=i;
      int room=n-first;
      if(room>cap)
         room=cap;
      if(room<=0)
         return 0;
      ArrayResize(out,room);
      int k=0;
      int lastIdx=-1;
      for(int j=first;j<n && j<first+room;j++)
        {
         lastIdx=j;
         if(arr[j].bid<=0.0)
            continue;
         out[k].msc=arr[j].time_msc;
         out[k].bid=arr[j].bid;
         out[k].ask=arr[j].ask;
         out[k].dir=0;
         if(m_lastBid>0.0)
            out[k].dir=(arr[j].bid>m_lastBid ? 1 : (arr[j].bid<m_lastBid ? -1 : 0));
         m_lastBid=arr[j].bid;
         m_lastAsk=arr[j].ask;
         k++;
        }
      ArrayResize(out,k);
      if(lastIdx<first)
         return k;
      long newLast=arr[lastIdx].time_msc;
      if(newLast==m_lastMsc)
        {
         if(!m_skipAllAtLast)
            m_seenAtLast+=(lastIdx-first+1);
        }
      else
        {
         int cnt=0;
         for(int b=lastIdx;b>=first && arr[b].time_msc==newLast;b--)
            cnt++;
         m_lastMsc=newLast;
         m_seenAtLast=cnt;
         m_skipAllAtLast=false;
        }
      return k;
     }

   //+---------------------------------------------------------------+
   //| positions                                                     |
   //+---------------------------------------------------------------+
   //--- ticket of the open position with this POSITION_IDENTIFIER (0 if none); leaves it selected
   ulong             FindPositionTicket(const long positionId)
     {
      if(positionId<=0)
         return 0;
      if(PositionSelectByTicket((ulong)positionId) && PositionGetInteger(POSITION_IDENTIFIER)==positionId)
         return (ulong)PositionGetInteger(POSITION_TICKET);
      int total=PositionsTotal();
      for(int i=total-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0)
            continue;
         if(PositionGetInteger(POSITION_IDENTIFIER)==positionId)
            return tk;
        }
      return 0;
     }

   //--- the server may truncate comments: a stored prefix of the requested comment matches too
   bool              CommentMatches(const string posComment,const string reqComment)
     {
      if(posComment==reqComment)
         return true;
      int n=StringLen(posComment);
      return (n>0 && StringLen(reqComment)>n && StringSubstr(reqComment,0,n)==posComment);
     }

   //--- own chart-symbol position with this magic/comment/side opened at or after sinceMsc (0 if none)
   ulong             FindRecentOwnPosition(const int dir,const long magic,const string comment,const long sinceMsc)
     {
      int total=PositionsTotal();
      for(int i=total-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0)
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC)!=magic || PosDir()!=dir)
            continue;
         if(PositionGetInteger(POSITION_TIME_MSC)<sinceMsc)
            continue;
         if(!CommentMatches(PositionGetString(POSITION_COMMENT),comment))
            continue;
         return tk;
        }
      return 0;
     }

   //--- fill the execution result from an open position
   void              FillFromPosition(const ulong ticket,SExecResult &res)
     {
      if(!PositionSelectByTicket(ticket))
         return;
      res.ticket=ticket;
      res.positionId=PositionGetInteger(POSITION_IDENTIFIER);
      res.fillPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      res.lots=PositionGetDouble(POSITION_VOLUME);
      if(res.requestedPrice<=0.0)
         res.requestedPrice=res.fillPrice;
     }

   //--- reference server ms of a request: the older of NowMsc() and the last tick (wider, safer window)
   long              RequestRefMsc(void)
     {
      long now=NowMsc();
      MqlTick q;
      ZeroMemory(q);
      if(SymbolInfoTick(m_symbol,q) && q.time_msc>0 && q.time_msc<now)
         return q.time_msc;
      return now;
     }

   //+---------------------------------------------------------------+
   //| order helpers                                                 |
   //+---------------------------------------------------------------+
   //--- PositionModify with result validation; rc = retcode or runtime error
   bool              ModifyRaw(const ulong ticket,const double sl,const double tp,int &rc,double &ms)
     {
      rc=0;
      ms=0.0;
      if(!PositionSelectByTicket(ticket))
        {
         rc=FTF_PF_ERR_POS_NOT_FOUND;
         return false;
        }
      m_trade.SetExpertMagicNumber((ulong)PositionGetInteger(POSITION_MAGIC));
      ResetLastError();
      ulong t0=GetMicrosecondCount();
      bool sent=m_trade.PositionModify(ticket,sl,tp);
      ms=(double)(GetMicrosecondCount()-t0)/1000.0;
      int err=GetLastError();
      rc=(int)m_trade.ResultRetcode();
      if(!sent && RcSuccess(rc))
        {
         //--- CTrade returned before sending and kept the previous result: verify on the position itself
         if(!PositionSelectByTicket(ticket))
           {
            rc=FTF_PF_ERR_POS_NOT_FOUND;
            return false;
           }
         if(MathAbs(PositionGetDouble(POSITION_SL)-sl)<m_point*0.5 && MathAbs(PositionGetDouble(POSITION_TP)-tp)<m_point*0.5)
            return true;
         rc=(err!=0 ? err : FTF_PF_ERR_SEND_FAILED);
         return false;
        }
      if(rc==0)
        {
         rc=(err!=0 ? err : FTF_PF_ERR_SEND_FAILED);
         return false;
        }
      return (RcSuccess(rc) || rc==TRADE_RETCODE_NO_CHANGES);
     }

   //--- sends the market order and fills res (ok, retcode, prices, ids, latency)
   void              SendOpen(const int dir,const double lots,const double sl,const double tp,const long magic,
                              const string comment,const int deviationPts,SExecResult &res)
     {
      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints((ulong)(deviationPts>0 ? deviationPts : FTF_PF_DEF_DEVIATION));
      MqlTick q;
      ZeroMemory(q);
      double price=0.0;
      if(SymbolInfoTick(m_symbol,q))
         price=(dir==FTF_DIR_BUY ? q.ask : q.bid);
      ResetLastError();
      ulong t0=GetMicrosecondCount();
      bool sent=false;
      if(dir==FTF_DIR_BUY)
         sent=m_trade.Buy(lots,m_symbol,price,sl,tp,comment);
      else
         sent=m_trade.Sell(lots,m_symbol,price,sl,tp,comment);
      ulong t1=GetMicrosecondCount();
      int err=GetLastError();
      res.latencyMs=(double)(t1-t0)/1000.0;
      int rc=(int)m_trade.ResultRetcode();
      if(rc==0 && !sent)
         rc=(err!=0 ? err : FTF_PF_ERR_SEND_FAILED);
      res.retcode=rc;
      res.requestedPrice=(m_trade.RequestPrice()>0.0 ? m_trade.RequestPrice() : price);
      res.retcodeText=ErrorText(rc);
      res.ok=RcSuccess(rc);
      if(!res.ok)
        {
         res.errClass=ClassifyError(rc);
         string brk=m_trade.ResultComment();
         if(StringLen(brk)>0)
            res.retcodeText+=" ["+brk+"]";
         return;
        }
      res.errClass=FTF_ERR_NONE;
      //--- fill price: ResultPrice, else DEAL_PRICE of the deal, else the requested price
      ulong deal=m_trade.ResultDeal();
      double fill=m_trade.ResultPrice();
      double vol=m_trade.ResultVolume();
      long posId=0;
      if(deal>0 && HistoryDealSelect(deal))
        {
         if(fill<=0.0)
            fill=HistoryDealGetDouble(deal,DEAL_PRICE);
         if(vol<=0.0)
            vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
         posId=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
        }
      if(posId<=0)
         posId=(long)m_trade.ResultOrder();     // POSITION_IDENTIFIER = ticket of the opening order
      res.fillPrice=(fill>0.0 ? fill : res.requestedPrice);
      res.lots=(vol>0.0 ? vol : lots);
      res.positionId=posId;
      ulong tk=FindPositionTicket(posId);
      res.ticket=(tk>0 ? tk : (ulong)posId);
      if(tk==0)
         Log(FTF_LOG_WARN,"OPEN filled (deal #"+IntegerToString((long)deal)+") but position id #"+IntegerToString(posId)+
             " is not in the open list yet - ticket assumed = position id");
     }

   //--- ambiguous result: look for the fill before reporting a failure (prevents duplicate entries)
   bool              ReconcileAmbiguous(const int dir,const long magic,const string comment,const long sinceMsc,SExecResult &res)
     {
      ulong tk=FindRecentOwnPosition(dir,magic,comment,sinceMsc);
      if(tk==0 && !IsTester())
        {
         Sleep(FTF_PF_AMBIG_RECHECK_MS);
         tk=FindRecentOwnPosition(dir,magic,comment,sinceMsc);
        }
      if(tk==0)
        {
         //--- remember it: a retry of the same request re-scans first (late fill)
         m_ambActive=true;
         m_ambMagic=magic;
         m_ambDir=dir;
         m_ambComment=comment;
         m_ambSinceMsc=sinceMsc;
         m_ambExpireUs=GetMicrosecondCount()+(ulong)FTF_PF_AMBIG_MEMORY_MS*1000;
         Log(FTF_LOG_WARN,"ambiguous result "+ErrorText(res.retcode)+": no matching position found (magic "+
             IntegerToString(magic)+" '"+comment+"') - reported as failure, a retry re-checks for a late fill first");
         return false;
        }
      FillFromPosition(tk,res);
      res.ok=true;
      res.errClass=FTF_ERR_NONE;
      res.retcodeText=ErrorText(res.retcode)+" - ambiguous result reconciled";
      m_ambActive=false;
      Log(FTF_LOG_WARN,"ambiguous result reconciled: "+ErrorText(res.retcode)+" but position #"+IntegerToString((long)tk)+
          " (magic "+IntegerToString(magic)+" '"+comment+"') exists - treated as filled, no duplicate entry");
      return true;
     }

   //--- retry of a request whose previous result was ambiguous: was it filled late?
   bool              AmbiguousRetryFilled(const int dir,const long magic,const string comment,SExecResult &res)
     {
      if(!m_ambActive)
         return false;
      if(GetMicrosecondCount()>m_ambExpireUs)
        {
         m_ambActive=false;
         return false;
        }
      if(m_ambMagic!=magic || m_ambDir!=dir || m_ambComment!=comment)
         return false;
      ulong tk=FindRecentOwnPosition(dir,magic,comment,m_ambSinceMsc);
      if(tk==0)
         return false;
      m_ambActive=false;
      FillFromPosition(tk,res);
      res.ok=true;
      res.retcode=TRADE_RETCODE_DONE;
      res.errClass=FTF_ERR_NONE;
      res.retcodeText=ErrorText(TRADE_RETCODE_DONE)+" - ambiguous result reconciled on retry (late fill, no new order sent)";
      return true;
     }

   //--- two-step stops, or SL/TP silently dropped by the broker: attach them now
   void              EnsureStops(const double sl,const double tp,SExecResult &res)
     {
      if((sl<=0.0 && tp<=0.0) || res.ticket==0)
         return;
      bool visible=PositionSelectByTicket(res.ticket);
      double curSl=(visible ? PositionGetDouble(POSITION_SL) : 0.0);
      double curTp=(visible ? PositionGetDouble(POSITION_TP) : 0.0);
      bool missing=((sl>0.0 && curSl<=0.0) || (tp>0.0 && curTp<=0.0));
      if(!missing)
         return;
      if(!m_twoStep && !visible)
         return;                                  // cannot verify; the position manager sees the real SL/TP
      string why=(m_twoStep ? "two-step stops" : "broker dropped SL/TP");
      double newSl=(sl>0.0 ? sl : curSl);
      double newTp=(tp>0.0 ? tp : curTp);
      int rc=0;
      double ms=0.0;
      if(ModifyRaw(res.ticket,newSl,newTp,rc,ms))
        {
         Log(FTF_LOG_INFO,"STOPS attached #"+IntegerToString((long)res.ticket)+" ("+why+") sl "+Px(newSl)+" tp "+Px(newTp)+
             " | "+ErrorText(rc)+" | "+MsStr(ms));
         return;
        }
      res.retcodeText="STOPS NOT ATTACHED: "+ErrorText(rc);
      Log(FTF_LOG_ERROR,"STOPS NOT ATTACHED to #"+IntegerToString((long)res.ticket)+" ("+why+") sl "+Px(newSl)+" tp "+Px(newTp)+
          " | "+ErrorText(rc)+" | "+MsStr(ms)+" - position is UNPROTECTED, the position manager must handle it");
     }

   //+---------------------------------------------------------------+
   //| indicators                                                    |
   //+---------------------------------------------------------------+
   string            IndDesc(const int i)
     {
      string t=(m_indType[i]==FTF_PF_IND_ATR ? "ATR" : (m_indType[i]==FTF_PF_IND_EMA ? "EMA" : "ADX"));
      return t+"("+IntegerToString(m_indPeriod[i])+") "+FTF_TfStr(m_indTf[i]);
     }

   //--- creates the handle lazily (retried later if the terminal refused it)
   bool              EnsureHandle(const int i)
     {
      if(m_indHandle[i]!=INVALID_HANDLE)
         return true;
      ResetLastError();
      int h=INVALID_HANDLE;
      if(m_indType[i]==FTF_PF_IND_ATR)
         h=iATR(m_symbol,m_indTf[i],m_indPeriod[i]);
      else
         if(m_indType[i]==FTF_PF_IND_EMA)
            h=iMA(m_symbol,m_indTf[i],m_indPeriod[i],0,MODE_EMA,PRICE_CLOSE);
         else
            h=iADX(m_symbol,m_indTf[i],m_indPeriod[i]);
      if(h==INVALID_HANDLE)
        {
         int err=GetLastError();
         LogThr(FTF_LOG_ERROR,"ind."+IntegerToString(i),60000,"cannot create "+IndDesc(i)+" handle on "+m_symbol+": "+ErrorText(err));
         return false;
        }
      m_indHandle[i]=h;
      return true;
     }

   int               RegisterInd(const int type,const ENUM_TIMEFRAMES tf,const int period)
     {
      for(int i=0;i<m_indCount;i++)
         if(m_indType[i]==type && m_indTf[i]==tf && m_indPeriod[i]==period)
            return i;
      if(period<=0)
        {
         Log(FTF_LOG_ERROR,"indicator registration refused: period "+IntegerToString(period));
         return -1;
        }
      if(m_indCount>=FTF_PF_MAX_IND)
        {
         Log(FTF_LOG_ERROR,"indicator registration refused: more than "+IntegerToString(FTF_PF_MAX_IND)+" indicators");
         return -1;
        }
      int id=m_indCount;
      m_indType[id]=type;
      m_indTf[id]=tf;
      m_indPeriod[id]=period;
      m_indHandle[id]=INVALID_HANDLE;
      m_indCount++;
      EnsureHandle(id);
      Log(FTF_LOG_DEBUG,"indicator #"+IntegerToString(id)+" "+IndDesc(id)+" registered (handle "+IntegerToString(m_indHandle[id])+")");
      return id;
     }

   void              ReleaseIndicators(void)
     {
      for(int i=0;i<m_indCount;i++)
        {
         if(m_indHandle[i]!=INVALID_HANDLE && !IndicatorRelease(m_indHandle[i]))
            Log(FTF_LOG_DEBUG,"IndicatorRelease("+IndDesc(i)+") failed");
         m_indHandle[i]=INVALID_HANDLE;
        }
      m_indCount=0;
     }

   //+---------------------------------------------------------------+
   //| calendar / history helpers                                    |
   //+---------------------------------------------------------------+
   //--- cached CalendarEventById (importance and time mode live on the event TYPE)
   int               EventIndex(const ulong eventId)
     {
      for(int i=0;i<m_evCount;i++)
         if(m_evId[i]==eventId)
            return i;
      MqlCalendarEvent ev;
      ResetLastError();
      if(!CalendarEventById(eventId,ev))
        {
         int err=GetLastError();
         LogThr(FTF_LOG_DEBUG,"calev",60000,"CalendarEventById("+IntegerToString((long)eventId)+") failed: "+ErrorText(err));
         return -1;
        }
      int k=m_evCount;
      ArrayResize(m_evId,k+1,64);
      ArrayResize(m_evImp,k+1,64);
      ArrayResize(m_evMode,k+1,64);
      ArrayResize(m_evName,k+1,64);
      m_evId[k]=eventId;
      m_evImp[k]=(int)ev.importance;
      m_evMode[k]=(int)ev.time_mode;
      m_evName[k]=ev.name;
      m_evCount=k+1;
      return k;
     }

   //--- one <=30-day CalendarValueHistory call [from,to) appended to dst
   bool              LoadCalendarChunk(const string ccy,const datetime from,const datetime to,SNewsEvent &dst[],int &k)
     {
      MqlCalendarValue vals[];
      ResetLastError();
      int nv=CalendarValueHistory(vals,from,to,NULL,ccy);
      int err=GetLastError();
      if(nv<0 || (nv==0 && err!=0 && err!=FTF_PF_ERR_CAL_NO_DATA))
        {
         LogThr(FTF_LOG_WARN,"cal."+ccy,60000,"CalendarValueHistory("+ccy+" "+TimeToString(from)+" .. "+TimeToString(to)+
                ") failed: n="+IntegerToString(nv)+" "+ErrorText(err));
         return false;
        }
      for(int i=0;i<nv;i++)
        {
         int ei=EventIndex(vals[i].event_id);
         if(ei<0)
            continue;
         if(m_evMode[ei]!=(int)CALENDAR_TIMEMODE_DATETIME)
            continue;                              // all-day / tentative events have no reliable time
         if(m_evImp[ei]<=0)
            continue;                              // CALENDAR_IMPORTANCE_NONE
         ArrayResize(dst,k+1,256);
         dst[k].Reset();
         dst[k].timeServer=vals[i].time;          // calendar times are trade-server time (no conversion)
         dst[k].currency=ccy;
         dst[k].impact=m_evImp[ei];
         dst[k].title=m_evName[ei];
         dst[k].source="MT5CAL";
         k++;
        }
      return true;
     }

   //--- stable bottom-up merge sort by timeServer (index array; structs copied once)
   void              SortNews(const SNewsEvent &src[],const int n,SNewsEvent &dst[])
     {
      ArrayResize(dst,(n>0 ? n : 0));
      if(n<=0)
         return;
      int idx[];
      int tmp[];
      ArrayResize(idx,n);
      ArrayResize(tmp,n);
      for(int i=0;i<n;i++)
         idx[i]=i;
      for(int width=1;width<n;width*=2)
        {
         for(int lo=0;lo<n;lo+=2*width)
           {
            int mid=(lo+width<n ? lo+width : n);
            int hi=(lo+2*width<n ? lo+2*width : n);
            int a=lo;
            int b=mid;
            int w=lo;
            while(a<mid && b<hi)
              {
               if(src[idx[b]].timeServer<src[idx[a]].timeServer)
                 {
                  tmp[w]=idx[b];
                  b++;
                 }
               else
                 {
                  tmp[w]=idx[a];
                  a++;
                 }
               w++;
              }
            while(a<mid)
              {
               tmp[w]=idx[a];
               a++;
               w++;
              }
            while(b<hi)
              {
               tmp[w]=idx[b];
               b++;
               w++;
              }
           }
         for(int i=0;i<n;i++)
            idx[i]=tmp[i];
        }
      for(int i=0;i<n;i++)
         dst[i]=src[idx[i]];
     }

   //--- docs/09 7.5 exit mapping (EXPERT -> UNKNOWN: the tracker substitutes its own pending exit code)
   int               ExitFromDealReason(const long reason)
     {
      ENUM_DEAL_REASON r=(ENUM_DEAL_REASON)reason;
      switch(r)
        {
         case DEAL_REASON_SL:     return FTF_EXIT_SL;
         case DEAL_REASON_TP:     return FTF_EXIT_TP;
         case DEAL_REASON_SO:     return FTF_EXIT_STOP_OUT;
         case DEAL_REASON_CLIENT:
         case DEAL_REASON_MOBILE:
         case DEAL_REASON_WEB:    return FTF_EXIT_MANUAL;
         case DEAL_REASON_EXPERT: return FTF_EXIT_UNKNOWN;
         default:                 break;
        }
      return FTF_EXIT_MANUAL;                       // rollover, variation margin, split, corporate action ...
     }

   //--- symbol defines at least one trade session on any weekday
   bool              AnySessionDefined(void)
     {
      for(int d=0;d<7;d++)
        {
         datetime f=0;
         datetime t=0;
         if(SymbolInfoSessionTrade(m_symbol,(ENUM_DAY_OF_WEEK)d,0,f,t))
            return true;
        }
      return false;
     }

   //--- full or partial close request; returns 'sent'
   bool              SendClose(const ulong ticket,const int dir,const bool partial,const double closeLots,const ulong dev)
     {
      if(!partial)
         return m_trade.PositionClose(ticket,dev);
      if(IsHedging())
         return m_trade.PositionClosePartial(ticket,closeLots,dev);
      //--- netting: an opposite deal of closeLots reduces the single position
      MqlTick q;
      ZeroMemory(q);
      double price=0.0;
      if(SymbolInfoTick(m_symbol,q))
         price=(dir==FTF_DIR_BUY ? q.bid : q.ask);
      if(dir==FTF_DIR_BUY)
         return m_trade.Sell(closeLots,m_symbol,price,0.0,0.0,"");
      return m_trade.Buy(closeLots,m_symbol,price,0.0,0.0,"");
     }

   //--- fill price of the last close: ResultPrice, else DEAL_PRICE, else requested price
   double            LastDealPrice(const double fallback)
     {
      double p=m_trade.ResultPrice();
      if(p>0.0)
         return p;
      ulong deal=m_trade.ResultDeal();
      if(deal>0 && HistoryDealSelect(deal))
        {
         p=HistoryDealGetDouble(deal,DEAL_PRICE);
         if(p>0.0)
            return p;
        }
      return fallback;
     }

   //--- symbol name of a trade/runtime code ("" if unknown)
   string            CodeName(const int code)
     {
      switch(code)
        {
         case 0:     return "ERR_SUCCESS";
         case 10004: return "TRADE_RETCODE_REQUOTE";
         case 10006: return "TRADE_RETCODE_REJECT";
         case 10007: return "TRADE_RETCODE_CANCEL";
         case 10008: return "TRADE_RETCODE_PLACED";
         case 10009: return "TRADE_RETCODE_DONE";
         case 10010: return "TRADE_RETCODE_DONE_PARTIAL";
         case 10011: return "TRADE_RETCODE_ERROR";
         case 10012: return "TRADE_RETCODE_TIMEOUT";
         case 10013: return "TRADE_RETCODE_INVALID";
         case 10014: return "TRADE_RETCODE_INVALID_VOLUME";
         case 10015: return "TRADE_RETCODE_INVALID_PRICE";
         case 10016: return "TRADE_RETCODE_INVALID_STOPS";
         case 10017: return "TRADE_RETCODE_TRADE_DISABLED";
         case 10018: return "TRADE_RETCODE_MARKET_CLOSED";
         case 10019: return "TRADE_RETCODE_NO_MONEY";
         case 10020: return "TRADE_RETCODE_PRICE_CHANGED";
         case 10021: return "TRADE_RETCODE_PRICE_OFF";
         case 10022: return "TRADE_RETCODE_INVALID_EXPIRATION";
         case 10023: return "TRADE_RETCODE_ORDER_CHANGED";
         case 10024: return "TRADE_RETCODE_TOO_MANY_REQUESTS";
         case 10025: return "TRADE_RETCODE_NO_CHANGES";
         case 10026: return "TRADE_RETCODE_SERVER_DISABLES_AT";
         case 10027: return "TRADE_RETCODE_CLIENT_DISABLES_AT";
         case 10028: return "TRADE_RETCODE_LOCKED";
         case 10029: return "TRADE_RETCODE_FROZEN";
         case 10030: return "TRADE_RETCODE_INVALID_FILL";
         case 10031: return "TRADE_RETCODE_CONNECTION";
         case 10032: return "TRADE_RETCODE_ONLY_REAL";
         case 10033: return "TRADE_RETCODE_LIMIT_ORDERS";
         case 10034: return "TRADE_RETCODE_LIMIT_VOLUME";
         case 10035: return "TRADE_RETCODE_INVALID_ORDER";
         case 10036: return "TRADE_RETCODE_POSITION_CLOSED";
         case 10038: return "TRADE_RETCODE_INVALID_CLOSE_VOLUME";
         case 10039: return "TRADE_RETCODE_CLOSE_ORDER_EXIST";
         case 10040: return "TRADE_RETCODE_LIMIT_POSITIONS";
         case 10041: return "TRADE_RETCODE_REJECT_CANCEL";
         case 10042: return "TRADE_RETCODE_LONG_ONLY";
         case 10043: return "TRADE_RETCODE_SHORT_ONLY";
         case 10044: return "TRADE_RETCODE_CLOSE_ONLY";
         case 10045: return "TRADE_RETCODE_FIFO_CLOSE";
         case 10046: return "TRADE_RETCODE_HEDGE_PROHIBITED";
         case 4001:  return "ERR_INTERNAL_ERROR";
         case 4004:  return "ERR_NOT_ENOUGH_MEMORY";
         case 4014:  return "ERR_FUNCTION_NOT_ALLOWED";
         case 4301:  return "ERR_MARKET_UNKNOWN_SYMBOL";
         case 4302:  return "ERR_MARKET_NOT_SELECTED";
         case 4401:  return "ERR_HISTORY_NOT_FOUND";
         case 4403:  return "ERR_HISTORY_TIMEOUT";
         case 4752:  return "ERR_TRADE_DISABLED";
         case 4753:  return "ERR_TRADE_POSITION_NOT_FOUND";
         case 4754:  return "ERR_TRADE_ORDER_NOT_FOUND";
         case 4755:  return "ERR_TRADE_DEAL_NOT_FOUND";
         case 4756:  return "ERR_TRADE_SEND_FAILED";
         case 4758:  return "ERR_TRADE_CALC_FAILED";
         case 4806:  return "ERR_INDICATOR_DATA_NOT_FOUND";
         case 5200:  return "ERR_WEBREQUEST_INVALID_ADDRESS";
         case 5201:  return "ERR_WEBREQUEST_CONNECT_FAILED";
         case 5202:  return "ERR_WEBREQUEST_TIMEOUT";
         case 5203:  return "ERR_WEBREQUEST_REQUEST_FAILED";
         case 5400:  return "ERR_CALENDAR_MORE_DATA";
         case 5401:  return "ERR_CALENDAR_TIMEOUT";
         case 5402:  return "ERR_CALENDAR_NO_DATA";
         default:    break;
        }
      return "";
     }

public:
   //--- trivial: the global controller (and this member) is constructed before OnInit
                     CPlatform(void)
     {
      m_log=NULL;
      m_symbol="";
      m_twoStep=false;
      m_point=0.0;
      m_digits=0;
      m_lotDigits=2;
      m_nowMsc=0;
      m_lastMsc=0;
      m_seenAtLast=0;
      m_skipAllAtLast=false;
      m_lastBid=0.0;
      m_lastAsk=0.0;
      m_indCount=0;
      m_evCount=0;
      m_ambActive=false;
      m_ambMagic=0;
      m_ambDir=0;
      m_ambComment="";
      m_ambSinceMsc=0;
      m_ambExpireUs=0;
     }

   //+---------------------------------------------------------------+
   //| lifecycle / environment                                       |
   //+---------------------------------------------------------------+
   bool              Init(CLogger *logger,const string symbol,const bool twoStepStops)
     {
      m_log=logger;
      m_symbol=symbol;
      m_twoStep=twoStepStops;
      ReleaseIndicators();                         // global object survives a parameter/chart change re-init
      ResetState();
      ResetLastError();
      if(!SymbolSelect(m_symbol,true))
         Log(FTF_LOG_WARN,"SymbolSelect("+m_symbol+",true) failed: "+ErrorText(GetLastError()));
      m_point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      m_digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      m_lotDigits=FTF_StepDigits(SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP));
      if(m_point<=0.0)
        {
         Log(FTF_LOG_ERROR,"symbol "+m_symbol+" is unknown to the terminal (point 0) - platform init failed");
         return false;
        }
      //--- CTrade: refresh margin mode (cached at construction, maybe before the account connected)
      m_trade.SetMarginMode();
      if(!m_trade.SetTypeFillingBySymbol(m_symbol))
         Log(FTF_LOG_WARN,"SetTypeFillingBySymbol("+m_symbol+") failed: the symbol allows neither FOK nor IOC (filling flags "+
             IntegerToString(SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE))+") - CTrade default filling kept");
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      Log(FTF_LOG_INFO,"MT5 platform ready | "+m_symbol+" digits "+IntegerToString(m_digits)+" point "+FTF_D(m_point,m_digits)+
          " | account "+(IsHedging() ? "HEDGING" : "NETTING")+" | execution "+
          EnumToString((ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_EXEMODE))+
          " | two-step stops "+(m_twoStep ? "ON" : "OFF")+(IsTester() ? " | TESTER" : ""));
      return true;
     }

   void              Deinit(void)
     {
      ReleaseIndicators();
      m_evCount=0;
      ArrayResize(m_evId,0);
      ArrayResize(m_evImp,0);
      ArrayResize(m_evMode,0);
      ArrayResize(m_evName,0);
      m_ambActive=false;
      Log(FTF_LOG_DEBUG,"MT5 platform released (indicator handles freed)");
     }

   string            Name(void)            { return "MT5"; }
   bool              IsTester(void)        { return (MQLInfoInteger(MQL_TESTER)!=0); }
   bool              IsOptimization(void)  { return (MQLInfoInteger(MQL_OPTIMIZATION)!=0); }
   bool              IsVisual(void)        { return (MQLInfoInteger(MQL_VISUAL_MODE)!=0); }

   bool              IsConnected(void)
     {
      if(IsTester())
         return true;
      return (TerminalInfoInteger(TERMINAL_CONNECTED)!=0);
     }

   //--- terminal AutoTrading + EA permission + expert trading + account trading (checked every cycle)
   bool              TradeAllowed(string &why)
     {
      why="";
      if(IsTester())
         return true;
      if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)==0)
        {
         why="Algo Trading is disabled in the terminal (toolbar button)";
         return false;
        }
      if(MQLInfoInteger(MQL_TRADE_ALLOWED)==0)
        {
         why="'Allow Algo Trading' is unchecked in the EA properties";
         return false;
        }
      if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)==0)
        {
         why="expert trading is disabled for this account by the broker";
         return false;
        }
      if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)==0)
        {
         why="trading is not allowed for this account (investor password or account disabled)";
         return false;
        }
      return true;
     }

   bool              IsHedging(void)
     {
      return ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
     }

   long              Login(void)           { return AccountInfoInteger(ACCOUNT_LOGIN); }
   string            AccountCurrency(void) { return AccountInfoString(ACCOUNT_CURRENCY); }
   string            Company(void)         { return AccountInfoString(ACCOUNT_COMPANY); }
   string            Server(void)          { return AccountInfoString(ACCOUNT_SERVER); }
   double            Balance(void)         { return AccountInfoDouble(ACCOUNT_BALANCE); }
   double            Equity(void)          { return AccountInfoDouble(ACCOUNT_EQUITY); }
   double            FreeMargin(void)      { return AccountInfoDouble(ACCOUNT_MARGIN_FREE); }
   double            MarginLevel(void)     { return AccountInfoDouble(ACCOUNT_MARGIN_LEVEL); }

   //--- chart symbol specification
   bool              RefreshSpec(SSymbolSpec &spec)
     {
      spec.Reset();
      spec.name=m_symbol;
      spec.point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      spec.digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      spec.tickSize=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      spec.tickValue=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      spec.contractSize=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      spec.lotMin=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      spec.lotMax=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      spec.lotStep=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      spec.stopsLevelPts=(int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
      spec.freezeLevelPts=(int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      spec.baseCcy=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_BASE);
      spec.profitCcy=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_PROFIT);
      spec.marginCcy=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_MARGIN);
      ENUM_SYMBOL_TRADE_MODE mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_MODE);
      spec.tradeAllowed=(mode!=SYMBOL_TRADE_MODE_DISABLED && mode!=SYMBOL_TRADE_MODE_CLOSEONLY);
      spec.canBuy=(mode==SYMBOL_TRADE_MODE_FULL || mode==SYMBOL_TRADE_MODE_LONGONLY);
      spec.canSell=(mode==SYMBOL_TRADE_MODE_FULL || mode==SYMBOL_TRADE_MODE_SHORTONLY);
      spec.hedging=IsHedging();
      if(spec.tickSize<=0.0)
         spec.tickSize=spec.point;
      if(spec.point>0.0)
        {
         m_point=spec.point;
         m_digits=spec.digits;
        }
      if(spec.lotStep>0.0)
         m_lotDigits=FTF_StepDigits(spec.lotStep);
      bool ok=(spec.point>0.0 && spec.lotStep>0.0 && spec.lotMin>0.0 && spec.tickValue>0.0);
      if(!ok)
         LogThr(FTF_LOG_WARN,"spec",60000,"symbol spec of "+m_symbol+" incomplete: point "+FTF_D(spec.point,8)+" step "+
                FTF_D(spec.lotStep,4)+" min "+FTF_D(spec.lotMin,4)+" tick value "+FTF_D(spec.tickValue,6));
      return ok;
     }

   //--- trade mode allows opening and the current server time is inside today's trade session
   bool              SymbolTradable(string &why)
     {
      why="";
      ENUM_SYMBOL_TRADE_MODE mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_MODE);
      if(mode==SYMBOL_TRADE_MODE_DISABLED)
        {
         why="trade mode DISABLED for "+m_symbol;
         return false;
        }
      if(mode==SYMBOL_TRADE_MODE_CLOSEONLY)
        {
         why="trade mode CLOSE ONLY for "+m_symbol;
         return false;
        }
      datetime now=(IsTester() ? TimeCurrent() : TimeTradeServer());
      MqlDateTime dt;
      TimeToStruct(now,dt);
      long sec=(long)dt.hour*3600+(long)dt.min*60+(long)dt.sec;
      string today="";
      bool anyToday=false;
      for(uint i=0;i<FTF_PF_MAX_SESSIONS;i++)
        {
         datetime f=0;
         datetime t=0;
         if(!SymbolInfoSessionTrade(m_symbol,(ENUM_DAY_OF_WEEK)dt.day_of_week,i,f,t))
            break;
         anyToday=true;
         long fs=((long)f)%86400;
         long ts=((long)t)%86400;
         if(ts==0 && (long)t>0)
            ts=86400;                              // 24:00
         today+=(StringLen(today)>0 ? "," : "")+SecStr(fs)+"-"+SecStr(ts);
         bool inside=false;
         if(fs<ts)
            inside=(sec>=fs && sec<ts);
         else
            if(fs>ts)
               inside=(sec>=fs || sec<ts);
            else
               inside=true;
         if(inside)
            return true;
        }
      if(!anyToday && !AnySessionDefined())
         return true;                              // the symbol defines no session at all: tradable
      why="outside trading session (server "+TimeToString(now,TIME_MINUTES)+" "+EnumToString((ENUM_DAY_OF_WEEK)dt.day_of_week)+
          ", sessions "+(anyToday ? today : "none today")+")";
      return false;
     }

   datetime          ServerTime(void)      { return TimeCurrent(); }

   //--- monotonic server ms = max(previous, last tick time_msc, trade server time)
   long              NowMsc(void)
     {
      long cand=m_nowMsc;
      MqlTick q;
      ZeroMemory(q);
      if(SymbolInfoTick(m_symbol,q) && q.time_msc>cand)
         cand=q.time_msc;
      long srv=(IsTester() ? (long)TimeCurrent() : (long)TimeTradeServer())*1000;
      if(srv>cand)
         cand=srv;
      m_nowMsc=cand;
      return m_nowMsc;
     }

   //--- server - GMT in seconds, rounded to 15 min (false in the tester: no real clock there)
   bool              AutoGmtOffset(long &secs)
     {
      secs=0;
      if(IsTester())
         return false;
      datetime srv=TimeTradeServer();
      datetime gmt=TimeGMT();
      if(srv<=0 || gmt<=0)
         return false;
      long diff=(long)srv-(long)gmt;
      secs=(long)MathRound((double)diff/900.0)*900;
      return true;
     }

   ulong             Micros(void)          { return GetMicrosecondCount(); }

   //+---------------------------------------------------------------+
   //| ticks                                                         |
   //+---------------------------------------------------------------+
   //--- chronological ticks (bid>0) that arrived since the previous call
   int               FetchNewTicks(STick &out[],const int maxCount)
     {
      ArrayResize(out,0);
      int cap=(maxCount>0 ? maxCount : FTF_PF_TICK_BATCH);
      //--- tester: OnTick runs for every tick, the snapshot is complete and much cheaper than CopyTicks
      if(IsTester() || m_lastMsc<=0)
         return FetchSnapshotTick(out);
      MqlTick last;
      ZeroMemory(last);
      if(SymbolInfoTick(m_symbol,last) && last.time_msc>m_lastMsc+FTF_PF_TICK_GAP_MS)
        {
         //--- reconnect / weekend: do not replay a stale backlog, restart FTF_PF_TICK_GAP_MS before the newest tick
         LogThr(FTF_LOG_INFO,"tickgap",60000,"tick gap of "+FTF_D((double)(last.time_msc-m_lastMsc)/1000.0,1)+
                " s since the last processed tick - resync on the last "+IntegerToString(FTF_PF_TICK_GAP_MS/1000)+" s");
         m_lastMsc=last.time_msc-FTF_PF_TICK_GAP_MS;
         m_seenAtLast=0;
         m_skipAllAtLast=false;
        }
      int want=cap+(m_skipAllAtLast ? 64 : m_seenAtLast);
      MqlTick arr[];
      ResetLastError();
      int n=CopyTicks(m_symbol,arr,COPY_TICKS_INFO,(ulong)m_lastMsc,(uint)want);
      if(n<=0)
        {
         int err=GetLastError();
         LogThr(FTF_LOG_DEBUG,"copyticks",10000,"CopyTicks("+m_symbol+") returned "+IntegerToString(n)+" "+ErrorText(err)+
                " - SymbolInfoTick fallback");
         return FetchSnapshotTick(out);
        }
      return ConsumeTicks(arr,n,cap,out);
     }

   //--- history warm-up: the last 'seconds' of ticks; initialises the dedupe state
   int               PreloadTicks(STick &out[],const int seconds)
     {
      ArrayResize(out,0);
      if(seconds<=0)
         return 0;
      MqlTick q;
      ZeroMemory(q);
      long toMsc=0;
      if(SymbolInfoTick(m_symbol,q) && q.time_msc>0)
         toMsc=q.time_msc;
      else
         toMsc=(long)TimeCurrent()*1000;
      if(toMsc<=0)
         return 0;
      long fromMsc=toMsc-(long)seconds*1000;
      MqlTick arr[];
      ulong t0=GetMicrosecondCount();
      ResetLastError();
      int n=CopyTicksRange(m_symbol,arr,COPY_TICKS_INFO,(ulong)fromMsc,(ulong)toMsc);
      int err=GetLastError();
      double ms=(double)(GetMicrosecondCount()-t0)/1000.0;
      if(n<=0)
        {
         Log(FTF_LOG_WARN,"tick preload: CopyTicksRange("+m_symbol+", "+IntegerToString(seconds)+" s) returned "+IntegerToString(n)+
             " "+ErrorText(err)+" after "+MsStr(ms)+" - engines warm up on live ticks");
         return 0;
        }
      m_lastMsc=0;
      m_seenAtLast=0;
      m_skipAllAtLast=false;
      m_lastBid=0.0;
      m_lastAsk=0.0;
      int k=ConsumeTicks(arr,n,n,out);
      Log(FTF_LOG_INFO,"tick preload: "+IntegerToString(k)+" ticks over the last "+IntegerToString(seconds)+" s ("+
          FTF_TimeMscStr(fromMsc)+" .. "+FTF_TimeMscStr(toMsc)+") in "+MsStr(ms)+(err!=0 ? " ("+ErrorText(err)+")" : ""));
      return k;
     }

   bool              CurrentTick(STick &t)
     {
      t.Reset();
      MqlTick q;
      ZeroMemory(q);
      if(!SymbolInfoTick(m_symbol,q) || q.bid<=0.0)
         return false;
      t.msc=q.time_msc;
      t.bid=q.bid;
      t.ask=q.ask;
      t.dir=0;
      return true;
     }

   //+---------------------------------------------------------------+
   //| bars (chart symbol)                                           |
   //+---------------------------------------------------------------+
   datetime          BarTime(const ENUM_TIMEFRAMES tf,const int shift)  { return iTime(m_symbol,tf,shift); }
   double            BarOpen(const ENUM_TIMEFRAMES tf,const int shift)  { return iOpen(m_symbol,tf,shift); }
   double            BarHigh(const ENUM_TIMEFRAMES tf,const int shift)  { return iHigh(m_symbol,tf,shift); }
   double            BarLow(const ENUM_TIMEFRAMES tf,const int shift)   { return iLow(m_symbol,tf,shift); }
   double            BarClose(const ENUM_TIMEFRAMES tf,const int shift) { return iClose(m_symbol,tf,shift); }
   int               BarsCount(const ENUM_TIMEFRAMES tf)                { return iBars(m_symbol,tf); }

   //+---------------------------------------------------------------+
   //| indicators (identical (type,tf,period) -> same id)            |
   //+---------------------------------------------------------------+
   int               RegisterATR(const ENUM_TIMEFRAMES tf,const int period) { return RegisterInd(FTF_PF_IND_ATR,tf,period); }
   int               RegisterEMA(const ENUM_TIMEFRAMES tf,const int period) { return RegisterInd(FTF_PF_IND_EMA,tf,period); }
   int               RegisterADX(const ENUM_TIMEFRAMES tf,const int period) { return RegisterInd(FTF_PF_IND_ADX,tf,period); }

   //--- ADX buffers: 0 main, 1 +DI, 2 -DI ; EMPTY_VALUE if not available
   double            IndValue(const int id,const int buffer,const int shift)
     {
      if(id<0 || id>=m_indCount || shift<0)
         return EMPTY_VALUE;
      int maxBuf=(m_indType[id]==FTF_PF_IND_ADX ? 2 : 0);
      if(buffer<0 || buffer>maxBuf)
         return EMPTY_VALUE;
      if(!EnsureHandle(id))
         return EMPTY_VALUE;
      double v[];
      ResetLastError();
      int n=CopyBuffer(m_indHandle[id],buffer,shift,1,v);
      if(n!=1 || ArraySize(v)<1)
         return EMPTY_VALUE;
      double x=v[0];
      if(x==EMPTY_VALUE || !MathIsValidNumber(x))
         return EMPTY_VALUE;
      return x;
     }

   bool              IndReady(const int id)
     {
      if(id<0 || id>=m_indCount)
         return false;
      if(!EnsureHandle(id))
         return false;
      return (BarsCalculated(m_indHandle[id])>0);
     }

   //+---------------------------------------------------------------+
   //| other symbols (read only - exposure guard)                    |
   //+---------------------------------------------------------------+
   //--- closes[0] = newest CLOSED bar; true only if 'count' values were available
   bool              OtherSymbolCloses(const string sym,const ENUM_TIMEFRAMES tf,const int count,double &closes[])
     {
      ArrayResize(closes,0);
      if(count<=0 || StringLen(sym)==0)
         return false;
      ResetLastError();
      if(!SymbolSelect(sym,true))
        {
         int err=GetLastError();
         LogThr(FTF_LOG_WARN,"sym."+sym,300000,"SymbolSelect("+sym+") failed: "+ErrorText(err)+" - symbol not available");
         return false;
        }
      double tmp[];
      ResetLastError();
      int n=CopyClose(sym,tf,1,count,tmp);
      if(n<=0)
        {
         int err=GetLastError();
         LogThr(FTF_LOG_DEBUG,"cc."+sym,60000,"CopyClose("+sym+" "+FTF_TfStr(tf)+") returned "+IntegerToString(n)+" "+
                ErrorText(err)+" (history still loading?)");
         return false;
        }
      ArrayResize(closes,n);
      for(int i=0;i<n;i++)
         closes[i]=tmp[n-1-i];
      return (n>=count);
     }

   bool              OtherSymbolCurrencies(const string sym,string &baseCcy,string &profitCcy)
     {
      baseCcy="";
      profitCcy="";
      if(StringLen(sym)==0 || !SymbolSelect(sym,true))
         return false;
      baseCcy=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
      profitCcy=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
      return (StringLen(baseCcy)>0 && StringLen(profitCcy)>0);
     }

   //--- money (>0, account currency) lost by 1.0 lot from entry to sl; 0 if it cannot be computed
   double            LossPerLot(const string sym,const int dir,const double entry,const double sl)
     {
      if(entry<=0.0 || sl<=0.0 || (dir!=FTF_DIR_BUY && dir!=FTF_DIR_SELL))
         return 0.0;
      double dist=MathAbs(entry-sl);
      if(dist<=0.0)
         return 0.0;
      string s=(StringLen(sym)>0 ? sym : m_symbol);
      if(s!=m_symbol && !SymbolSelect(s,true))
         return 0.0;
      ENUM_ORDER_TYPE type=(dir==FTF_DIR_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double pnl=0.0;
      ResetLastError();
      if(OrderCalcProfit(type,s,1.0,entry,sl,pnl) && pnl!=0.0)
         return MathAbs(pnl);
      int err=GetLastError();
      double tickSize=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE);
      double tickVal=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_VALUE);
      if(tickSize<=0.0 || tickVal<=0.0)
        {
         LogThr(FTF_LOG_WARN,"lpl."+s,60000,"loss per lot of "+s+" unavailable: OrderCalcProfit "+ErrorText(err)+
                ", tick size "+FTF_D(tickSize,8)+", tick value "+FTF_D(tickVal,6));
         return 0.0;
        }
      LogThr(FTF_LOG_DEBUG,"lplfb."+s,60000,"OrderCalcProfit("+s+") failed ("+ErrorText(err)+") - tick value fallback");
      return dist/tickSize*tickVal;
     }

   //--- margin for 'lots' of the chart symbol at 'price' (current price if <=0); 0 if unknown
   double            MarginRequired(const int dir,const double lots,const double price)
     {
      if(lots<=0.0 || (dir!=FTF_DIR_BUY && dir!=FTF_DIR_SELL))
         return 0.0;
      double px=price;
      if(px<=0.0)
        {
         MqlTick q;
         ZeroMemory(q);
         if(SymbolInfoTick(m_symbol,q))
            px=(dir==FTF_DIR_BUY ? q.ask : q.bid);
        }
      if(px<=0.0)
         return 0.0;
      ENUM_ORDER_TYPE type=(dir==FTF_DIR_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double m=0.0;
      ResetLastError();
      if(!OrderCalcMargin(type,m_symbol,lots,px,m))
        {
         int err=GetLastError();
         LogThr(FTF_LOG_WARN,"margin",60000,"OrderCalcMargin("+m_symbol+" "+LotStr(lots)+") failed: "+ErrorText(err)+" - 0 returned");
         return 0.0;
        }
      return m;
     }

   //+---------------------------------------------------------------+
   //| positions and history                                         |
   //+---------------------------------------------------------------+
   //--- open market positions (all magics); allSymbols=false -> chart symbol only
   int               GetPositions(SPosInfo &out[],const bool allSymbols)
     {
      ArrayResize(out,0);
      int total=PositionsTotal();
      int k=0;
      for(int i=0;i<total;i++)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0)
            continue;
         string sym=PositionGetString(POSITION_SYMBOL);
         if(!allSymbols && sym!=m_symbol)
            continue;
         ArrayResize(out,k+1,16);
         out[k].Reset();
         out[k].ticket=tk;
         out[k].positionId=PositionGetInteger(POSITION_IDENTIFIER);
         out[k].symbol=sym;
         out[k].magic=PositionGetInteger(POSITION_MAGIC);
         out[k].dir=PosDir();
         out[k].lots=PositionGetDouble(POSITION_VOLUME);
         out[k].openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
         out[k].sl=PositionGetDouble(POSITION_SL);
         out[k].tp=PositionGetDouble(POSITION_TP);
         out[k].openMsc=PositionGetInteger(POSITION_TIME_MSC);
         out[k].profit=PositionGetDouble(POSITION_PROFIT);
         out[k].swap=PositionGetDouble(POSITION_SWAP);
         out[k].comment=PositionGetString(POSITION_COMMENT);
         k++;
        }
      return k;
     }

   //--- history of a closed position; found=true only when the closing deal exists
   bool              GetClosedTrade(const ulong ticket,const long positionId,SClosedTrade &out)
     {
      out.Reset();
      out.ticket=ticket;
      long id=(positionId>0 ? positionId : (long)ticket);
      out.positionId=id;
      if(id<=0)
         return false;
      if(FindPositionTicket(id)>0)
         return false;                             // still (partially) open
      ResetLastError();
      if(!HistorySelectByPosition((ulong)id))
        {
         int err=GetLastError();
         LogThr(FTF_LOG_DEBUG,"hist."+IntegerToString(id),5000,"HistorySelectByPosition(#"+IntegerToString(id)+") failed: "+ErrorText(err));
         return false;
        }
      int nd=HistoryDealsTotal();
      double profit=0.0;
      double comm=0.0;
      double swp=0.0;
      double fee=0.0;
      ulong outDeal=0;
      long outMsc=-1;
      for(int i=0;i<nd;i++)
        {
         ulong d=HistoryDealGetTicket(i);
         if(d==0)
            continue;
         //--- commission may sit on the entry deal: sum every deal of the position
         profit+=HistoryDealGetDouble(d,DEAL_PROFIT);
         comm+=HistoryDealGetDouble(d,DEAL_COMMISSION);
         swp+=HistoryDealGetDouble(d,DEAL_SWAP);
         fee+=HistoryDealGetDouble(d,DEAL_FEE);
         ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
         if(e!=DEAL_ENTRY_OUT && e!=DEAL_ENTRY_OUT_BY && e!=DEAL_ENTRY_INOUT)
            continue;
         long msc=HistoryDealGetInteger(d,DEAL_TIME_MSC);
         if(msc>=outMsc)
           {
            outMsc=msc;
            outDeal=d;
           }
        }
      if(outDeal==0)
         return false;                             // closing deal not in history yet: the tracker retries
      long reason=HistoryDealGetInteger(outDeal,DEAL_REASON);
      out.found=true;
      out.closePrice=HistoryDealGetDouble(outDeal,DEAL_PRICE);
      out.closeMsc=outMsc;
      out.profit=profit;
      out.commission=comm+fee;                     // DEAL_FEE folded into commission so net = profit+commission+swap
      out.swap=swp;
      out.net=profit+comm+fee+swp;
      out.exitReason=ExitFromDealReason(reason);
      out.exitDetail="deal #"+IntegerToString((long)outDeal)+" "+EnumToString((ENUM_DEAL_REASON)reason)+" @"+
                     Px(out.closePrice)+" '"+HistoryDealGetString(outDeal,DEAL_COMMENT)+"' ("+IntegerToString(nd)+" deals"+
                     (fee!=0.0 ? ", fee "+FTF_D(fee,2) : "")+")";
      Log(FTF_LOG_DEBUG,"closed trade #"+IntegerToString(id)+" net "+FTF_D(out.net,2)+" exit "+FTF_ExitStr(out.exitReason)+" | "+out.exitDetail);
      return true;
     }

   //+---------------------------------------------------------------+
   //| orders                                                        |
   //+---------------------------------------------------------------+
   bool              OpenMarket(const int dir,const double lots,const double sl,const double tp,const long magic,
                                const string comment,const int deviationPts,SExecResult &res)
     {
      res.Reset();
      res.lots=lots;
      if(dir!=FTF_DIR_BUY && dir!=FTF_DIR_SELL)
         return Reject(res,TRADE_RETCODE_INVALID,"OPEN refused: invalid direction "+IntegerToString(dir));
      if(lots<=0.0)
         return Reject(res,TRADE_RETCODE_INVALID_VOLUME,"OPEN refused: lots "+LotStr(lots));
      double slN=(sl>0.0 ? NormalizeDouble(sl,m_digits) : 0.0);
      double tpN=(tp>0.0 ? NormalizeDouble(tp,m_digits) : 0.0);
      string what=FTF_DirStr(dir)+" "+LotStr(lots)+" "+m_symbol+" sl "+Px(slN)+" tp "+Px(tpN)+" magic "+
                  IntegerToString(magic)+" '"+comment+"'";
      //--- retry after an ambiguous result: a late fill must not be doubled
      if(AmbiguousRetryFilled(dir,magic,comment,res))
        {
         EnsureStops(slN,tpN,res);
         Log(FTF_LOG_WARN,"OPEN "+what+" | ambiguous result reconciled on retry: position #"+IntegerToString((long)res.ticket)+
             " already exists @"+Px(res.fillPrice)+" - no new order sent");
         return true;
        }
      long sinceMsc=RequestRefMsc()-FTF_PF_AMBIG_BACK_MS;
      SendOpen(dir,lots,(m_twoStep ? 0.0 : slN),(m_twoStep ? 0.0 : tpN),magic,comment,deviationPts,res);
      if(!res.ok && IsAmbiguous(res.retcode))
         ReconcileAmbiguous(dir,magic,comment,sinceMsc,res);
      if(res.ok)
        {
         if(m_ambActive && m_ambMagic==magic && m_ambComment==comment)
            m_ambActive=false;
         EnsureStops(slN,tpN,res);
         double slipPts=0.0;
         if(m_point>0.0)
            slipPts=(dir==FTF_DIR_BUY ? res.fillPrice-res.requestedPrice : res.requestedPrice-res.fillPrice)/m_point;
         Log(FTF_LOG_INFO,"OPEN "+what+" | filled "+LotStr(res.lots)+" @"+Px(res.fillPrice)+" req "+Px(res.requestedPrice)+
             " slip "+FTF_D(slipPts,1)+" pts | "+res.retcodeText+" | ticket #"+IntegerToString((long)res.ticket)+
             " pos #"+IntegerToString(res.positionId)+" | "+MsStr(res.latencyMs));
         return true;
        }
      Log((res.errClass==FTF_ERR_TRANSIENT ? FTF_LOG_WARN : FTF_LOG_ERROR),
          "OPEN "+what+" req "+Px(res.requestedPrice)+" FAILED | "+res.retcodeText+" | class "+ErrClassStr(res.errClass)+
          " | "+MsStr(res.latencyMs));
      return false;
     }

   bool              ModifyPosition(const ulong ticket,const double sl,const double tp,SExecResult &res)
     {
      res.Reset();
      res.ticket=ticket;
      if(!PositionSelectByTicket(ticket))
        {
         res.retcode=FTF_PF_ERR_POS_NOT_FOUND;
         res.retcodeText=ErrorText(res.retcode)+" - position not open";
         res.errClass=FTF_ERR_PERMANENT;
         Log(FTF_LOG_WARN,"MODIFY #"+IntegerToString((long)ticket)+" FAILED | position not open (closed meanwhile?)");
         return false;
        }
      string sym=PositionGetString(POSITION_SYMBOL);
      if(sym!=m_symbol)
         return Reject(res,TRADE_RETCODE_INVALID,"MODIFY #"+IntegerToString((long)ticket)+" refused: symbol "+sym+
                       " is not the chart symbol "+m_symbol);
      int dir=PosDir();
      long magic=PositionGetInteger(POSITION_MAGIC);
      string cmt=PositionGetString(POSITION_COMMENT);
      double curSl=PositionGetDouble(POSITION_SL);
      double curTp=PositionGetDouble(POSITION_TP);
      res.positionId=PositionGetInteger(POSITION_IDENTIFIER);
      res.lots=PositionGetDouble(POSITION_VOLUME);
      res.fillPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double slN=(sl>0.0 ? NormalizeDouble(sl,m_digits) : 0.0);
      double tpN=(tp>0.0 ? NormalizeDouble(tp,m_digits) : 0.0);
      string what="#"+IntegerToString((long)ticket)+" "+FTF_DirStr(dir)+" "+LotStr(res.lots)+" "+m_symbol+" sl "+Px(curSl)+
                  "->"+Px(slN)+" tp "+Px(curTp)+"->"+Px(tpN)+" magic "+IntegerToString(magic)+" '"+cmt+"'";
      if(MathAbs(slN-curSl)<m_point*0.5 && MathAbs(tpN-curTp)<m_point*0.5)
        {
         res.ok=true;
         res.retcode=TRADE_RETCODE_NO_CHANGES;
         res.retcodeText=ErrorText(TRADE_RETCODE_NO_CHANGES)+" - unchanged, not sent";
         res.errClass=FTF_ERR_NONE;
         Log(FTF_LOG_DEBUG,"MODIFY "+what+" | unchanged - skipped");
         return true;
        }
      int rc=0;
      double ms=0.0;
      bool ok=ModifyRaw(ticket,slN,tpN,rc,ms);
      res.retcode=rc;
      res.latencyMs=ms;
      res.retcodeText=ErrorText(rc);
      if(ok)
        {
         res.ok=true;
         res.errClass=FTF_ERR_NONE;
         Log(FTF_LOG_INFO,"MODIFY "+what+" | "+res.retcodeText+" | "+MsStr(ms));
         return true;
        }
      res.errClass=ClassifyError(rc);
      string brk=m_trade.ResultComment();
      if(StringLen(brk)>0 && rc>=10000)
         res.retcodeText+=" ["+brk+"]";
      Log((res.errClass==FTF_ERR_TRANSIENT ? FTF_LOG_WARN : FTF_LOG_ERROR),
          "MODIFY "+what+" FAILED | "+res.retcodeText+" | class "+ErrClassStr(res.errClass)+" | "+MsStr(ms));
      return false;
     }

   //--- lots<=0 or >= volume -> full close; a position that no longer exists counts as ok
   bool              ClosePosition(const ulong ticket,const double lots,const int deviationPts,SExecResult &res)
     {
      res.Reset();
      res.ticket=ticket;
      if(!PositionSelectByTicket(ticket))
        {
         res.ok=true;
         res.retcode=TRADE_RETCODE_POSITION_CLOSED;
         res.retcodeText="already closed";
         res.errClass=FTF_ERR_NONE;
         Log(FTF_LOG_INFO,"CLOSE #"+IntegerToString((long)ticket)+" | already closed (not in the open list)");
         return true;
        }
      string sym=PositionGetString(POSITION_SYMBOL);
      if(sym!=m_symbol)
         return Reject(res,TRADE_RETCODE_INVALID,"CLOSE #"+IntegerToString((long)ticket)+" refused: symbol "+sym+
                       " is not the chart symbol "+m_symbol);
      int dir=PosDir();
      long magic=PositionGetInteger(POSITION_MAGIC);
      string cmt=PositionGetString(POSITION_COMMENT);
      double vol=PositionGetDouble(POSITION_VOLUME);
      double openPx=PositionGetDouble(POSITION_PRICE_OPEN);
      res.positionId=PositionGetInteger(POSITION_IDENTIFIER);
      bool partial=(lots>0.0 && lots<vol-1e-8);
      double closeLots=vol;
      if(partial)
        {
         closeLots=FTF_NormalizeLotsDown(lots,SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP),
                                         SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN),vol);
         if(closeLots<=0.0)
            return Reject(res,TRADE_RETCODE_INVALID_VOLUME,"CLOSE #"+IntegerToString((long)ticket)+" refused: partial lots "+
                          LotStr(lots)+" below the symbol minimum");
        }
      res.lots=closeLots;
      string what="#"+IntegerToString((long)ticket)+" "+FTF_DirStr(dir)+" "+LotStr(closeLots)+(partial ? " (partial of "+LotStr(vol)+")" : "")+
                  " "+m_symbol+" open "+Px(openPx)+" magic "+IntegerToString(magic)+" '"+cmt+"'";
      ulong dev=(ulong)(deviationPts>0 ? deviationPts : FTF_PF_DEF_DEVIATION);
      m_trade.SetExpertMagicNumber((ulong)magic);  // the closing deal carries the position magic
      m_trade.SetDeviationInPoints(dev);
      ResetLastError();
      ulong t0=GetMicrosecondCount();
      bool sent=SendClose(ticket,dir,partial,closeLots,dev);
      res.latencyMs=(double)(GetMicrosecondCount()-t0)/1000.0;
      int err=GetLastError();
      int rc=(int)m_trade.ResultRetcode();
      res.requestedPrice=m_trade.RequestPrice();
      bool exists=PositionSelectByTicket(ticket);
      double remain=(exists ? PositionGetDouble(POSITION_VOLUME) : 0.0);
      bool shrunk=(!exists || remain<vol-1e-8);
      if(RcSuccess(rc) && !sent && !shrunk)
         rc=(err!=0 ? err : FTF_PF_ERR_SEND_FAILED);  // stale CTrade result, nothing was sent
      if(rc==0)
         rc=(err!=0 ? err : FTF_PF_ERR_SEND_FAILED);
      res.retcode=rc;
      res.retcodeText=ErrorText(rc);
      if(RcSuccess(rc) || rc==TRADE_RETCODE_POSITION_CLOSED || shrunk)
        {
         res.ok=true;
         res.errClass=FTF_ERR_NONE;
         if(!RcSuccess(rc))
            res.retcodeText+=(IsAmbiguous(rc) ? " - ambiguous result reconciled (position closed)" : " - already closed");
         res.fillPrice=LastDealPrice(res.requestedPrice);
         Log(FTF_LOG_INFO,"CLOSE "+what+" @"+Px(res.fillPrice)+" req "+Px(res.requestedPrice)+" | "+res.retcodeText+" | "+MsStr(res.latencyMs));
         return true;
        }
      res.errClass=ClassifyError(rc);
      string brk=m_trade.ResultComment();
      if(StringLen(brk)>0 && rc>=10000)
         res.retcodeText+=" ["+brk+"]";
      Log((res.errClass==FTF_ERR_TRANSIENT ? FTF_LOG_WARN : FTF_LOG_ERROR),
          "CLOSE "+what+" req "+Px(res.requestedPrice)+" FAILED | "+res.retcodeText+" | class "+ErrClassStr(res.errClass)+
          " | "+MsStr(res.latencyMs));
      return false;
     }

   //+---------------------------------------------------------------+
   //| error classification (ENUM_FTF_ERRCLASS, spec B.8)            |
   //+---------------------------------------------------------------+
   int               ClassifyError(const int code)
     {
      switch(code)
        {
         case 0:
         case 10008:   // PLACED
         case 10009:   // DONE
         case 10010:   // DONE_PARTIAL
         case 10025:   // NO_CHANGES (modify: nothing to do)
            return FTF_ERR_NONE;
         case 10004:   // REQUOTE
         case 10020:   // PRICE_CHANGED
         case 10021:   // PRICE_OFF
         case 10024:   // TOO_MANY_REQUESTS
         case 10031:   // CONNECTION
         case 10028:   // LOCKED
         case 10029:   // FROZEN
         case 10023:   // ORDER_CHANGED
         case 10012:   // TIMEOUT
         case 10015:   // INVALID_PRICE (stale quote)
         case 10039:   // CLOSE_ORDER_EXIST (a close is already pending)
            return FTF_ERR_TRANSIENT;
         case 10017:   // TRADE_DISABLED
         case 10018:   // MARKET_CLOSED
         case 10019:   // NO_MONEY
         case 10026:   // SERVER_DISABLES_AT (autotrading disabled by server)
         case 10027:   // CLIENT_DISABLES_AT (autotrading disabled by client)
         case 10032:   // ONLY_REAL (account type not allowed)
         case 10033:   // LIMIT_ORDERS
         case 10034:   // LIMIT_VOLUME
         case 10040:   // LIMIT_POSITIONS
         case 10042:   // LONG_ONLY
         case 10043:   // SHORT_ONLY
         case 10044:   // CLOSE_ONLY
         case 10045:   // FIFO_CLOSE
         case 10046:   // HEDGE_PROHIBITED
         case 4752:    // ERR_TRADE_DISABLED (EA trading prohibited)
            return FTF_ERR_FATAL;
         default:
            break;
        }
      return FTF_ERR_PERMANENT;                    // invalid stops/volume/fill/request ...
     }

   //--- "CODE_NAME (number)" for known codes, "error <n>" otherwise
   string            ErrorText(const int code)
     {
      string nm=CodeName(code);
      if(StringLen(nm)==0)
         return "error "+IntegerToString(code);
      return nm+" ("+IntegerToString(code)+")";
     }

   //+---------------------------------------------------------------+
   //| economic calendar / web                                       |
   //+---------------------------------------------------------------+
   //--- MT5 calendar events of [fromSrv,toSrv) (server time), sorted by time; 0 in the tester
   int               LoadCalendar(const datetime fromSrv,const datetime toSrv,const string &currencies[],const int nCcy,SNewsEvent &out[])
     {
      ArrayResize(out,0);
      if(IsTester() || IsOptimization())
         return 0;                                 // Calendar* fails with 4014 in the tester: CSV is used there
      if(toSrv<=fromSrv)
         return 0;
      int nc=(nCcy<ArraySize(currencies) ? nCcy : ArraySize(currencies));
      SNewsEvent tmp[];
      int k=0;
      int failures=0;
      string done="";
      ulong t0=GetMicrosecondCount();
      for(int c=0;c<nc;c++)
        {
         string ccy=FTF_Upper(FTF_Trim(currencies[c]));
         if(StringLen(ccy)==0 || FTF_ListContains(done,ccy))
            continue;
         done=(StringLen(done)>0 ? done+","+ccy : ccy);
         datetime from=fromSrv;
         while(from<toSrv)
           {
            datetime to=(datetime)((long)from+FTF_PF_CAL_CHUNK_SEC);
            if(to>toSrv)
               to=toSrv;
            if(!LoadCalendarChunk(ccy,from,to,tmp,k))
               failures++;
            from=to;
           }
        }
      SortNews(tmp,k,out);
      double ms=(double)(GetMicrosecondCount()-t0)/1000.0;
      Log((failures>0 ? FTF_LOG_WARN : FTF_LOG_INFO),"MT5 calendar: "+IntegerToString(k)+" events ["+done+"] "+
          TimeToString(fromSrv)+" .. "+TimeToString(toSrv)+" (server time) in "+MsStr(ms)+
          (failures>0 ? " - "+IntegerToString(failures)+" request(s) FAILED" : ""));
      return k;
     }

   //--- WebRequest GET (URL must be allowed in Tools > Options > Expert Advisors); false in the tester
   bool              HttpGet(const string url,const int timeoutMs,string &body,int &httpCode)
     {
      body="";
      httpCode=0;
      if(IsTester() || IsOptimization())
         return false;
      char data[];
      char result[];
      string respHeaders="";
      ArrayResize(data,0);
      ResetLastError();
      int code=WebRequest("GET",url,"",timeoutMs,data,result,respHeaders);
      if(code==-1)
        {
         int err=GetLastError();
         LogThr(FTF_LOG_ERROR,"web",FTF_PF_WEB_ERR_MS,"WebRequest GET "+url+" failed: "+ErrorText(err)+
                " - add the URL in Tools > Options > Expert Advisors > 'Allow WebRequest for listed URL'");
         return false;
        }
      httpCode=code;
      body=CharArrayToString(result,0,WHOLE_ARRAY,CP_UTF8);
      if(code<200 || code>=300)
        {
         LogThr(FTF_LOG_WARN,"webhttp",600000,"WebRequest GET "+url+" -> HTTP "+IntegerToString(code));
         return false;
        }
      Log(FTF_LOG_DEBUG,"WebRequest GET "+url+" -> HTTP "+IntegerToString(code)+", "+IntegerToString(ArraySize(result))+" bytes");
      return true;
     }
  };

#endif // FTF_PLATFORM_MQH
