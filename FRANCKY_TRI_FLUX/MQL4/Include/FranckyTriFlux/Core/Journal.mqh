//+------------------------------------------------------------------+
//|                                                      Journal.mqh |
//|  CTradeJournal - exportable CSV journals (acceptance criterion): |
//|    signals.csv  every signal decision (accepted / rejected)      |
//|    trades.csv   every closed trade with full execution metrics   |
//|    events.csv   protection / state / error events                |
//|  Separator ';', header written when the file is new, files kept  |
//|  open (append) for speed. docs/09 section 7.2 (columns binding). |
//|  Shared Core: identical in the MQL5 and MQL4 trees.              |
//+------------------------------------------------------------------+
#ifndef FTF_JOURNAL_MQH
#define FTF_JOURNAL_MQH

#include <FranckyTriFlux\Core\Types.mqh>
#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>

#define FTF_JOURNAL_SIGNAL_FLUSH  25   // TUNABLE (not an input yet) - flush signals.csv every N rows

//--- binding column lists (docs/09 7.2) - change only together with the contract
#define FTF_CSV_SIGNALS_HEADER "time;msc;platform;symbol;instance;mode;engine_id;engine;tf;signal_id;setup_id;dir;signal_price;bid;ask;spread_pts;sl;tp;sl_pts;tp_pts;quality;h1;struct_ok;lots;decision;reason_code;reason;detail;entry_reason"
#define FTF_CSV_TRADES_HEADER  "ticket;position_id;platform;symbol;instance;mode;engine_id;engine;tf;setup_id;dir;lots;signal_time;open_time;close_time;duration_s;signal_price;requested_price;open_price;close_price;slippage_pts;decision_ms;latency_ms;spread_pts;initial_sl;initial_tp;final_sl;risk_money;gross_pnl;commission;swap;net_pnl;stress_commission;net_after_stress;r_multiple;mae_pts;mfe_pts;equity_at_entry;dd_pct_at_entry;h1;retries;recovered;entry_reason;exit_code;exit_reason;exit_detail"
#define FTF_CSV_EVENTS_HEADER  "time;msc;platform;symbol;instance;category;code;detail"

class CTradeJournal
  {
private:
   CLogger          *m_log;
   string            m_folder;
   bool              m_useCommon;
   bool              m_enabled;        // InpLogCsv (and not optimization unless allowed) - false: every method is a no-op
   bool              m_logSignals;     // InpLogSignals - false: LogSignal is a no-op
   string            m_platform;       // "MT5" / "MT4"
   string            m_symbol;
   int               m_instanceId;
   string            m_modeText;       // SPEED / AGGRESSIVE / ULTRA (signals.csv)
   int               m_digits;         // price decimals (SetDigits)
   double            m_point;          // 10^-digits, used for *_pts columns of signals.csv
   int               m_hSignals;
   int               m_hTrades;
   int               m_hEvents;
   int               m_sigUnflushed;
   long              m_rowsSignals;
   long              m_rowsTrades;
   long              m_rowsEvents;
   int               m_writeErrors;

   //--- logging helpers (src tag "JRNL")
   void              LogMsg(const int lvl,const string msg)
     {
      if(CheckPointer(m_log)==POINTER_INVALID)
         return;
      m_log.Log(lvl,"JRNL",msg);
     }

   //--- CSV text field: ';' would shift columns, CR/LF would break rows
   string            San(const string s)
     {
      string out=s;
      StringReplace(out,";",",");
      StringReplace(out,"\r"," ");
      StringReplace(out,"\n"," ");
      return out;
     }

   //--- number formats (docs: prices = symbol digits, money 2, ms 1, points 1, ratios 3)
   string            Px(const double v)     { return DoubleToString(v,m_digits); }
   string            Money(const double v)  { return DoubleToString(v,2); }
   string            Ms(const double v)     { return DoubleToString(v,1); }
   string            Pts(const double v)    { return DoubleToString(v,1); }
   string            Ratio(const double v)  { return DoubleToString(v,3); }
   string            Flag(const bool b)     { return (b ? "1" : "0"); }
   string            Lots(const double v)
     {
      int d=FTF_StepDigits(v);
      if(d<2)
         d=2;
      if(d>4)
         d=4;
      return DoubleToString(v,d);
     }
   //--- price distance in points (0 when the level is not set)
   string            DistPts(const double from,const double level)
     {
      if(level<=0.0 || from<=0.0 || m_point<=0.0)
         return Pts(0.0);
      return Pts(MathAbs(from-level)/m_point);
     }
   string            FilePath(const string name)
     {
      if(StringLen(m_folder)==0)
         return name;
      return m_folder+"\\"+name;
     }
   string            FileLabel(const string name)
     {
      return (m_useCommon ? "Common\\Files\\" : "Files\\")+FilePath(name);
     }

   //--- open one CSV in append mode; header only when the file is new (size 0)
   int               OpenCsv(const string name,const string header)
     {
      int flags=FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ;
      if(m_useCommon)
         flags|=FILE_COMMON;
      ResetLastError();
      int h=FileOpen(FilePath(name),flags);
      if(h==INVALID_HANDLE)
        {
         LogMsg(FTF_LOG_ERROR,"cannot open "+FileLabel(name)+" (error "+IntegerToString(GetLastError())+
                ") - this CSV journal is DISABLED (file open in another program?)");
         return INVALID_HANDLE;
        }
      if(!FileSeek(h,0,SEEK_END))
         LogMsg(FTF_LOG_WARN,"FileSeek to end of "+FileLabel(name)+" failed (error "+IntegerToString(GetLastError())+")");
      if(FileSize(h)==0)
        {
         if(FileWriteString(h,header+"\r\n")==0)
            LogMsg(FTF_LOG_WARN,"header write to "+FileLabel(name)+" failed (error "+IntegerToString(GetLastError())+")");
         FileFlush(h);
         LogMsg(FTF_LOG_DEBUG,"new journal "+FileLabel(name)+" created with header");
        }
      else
         LogMsg(FTF_LOG_DEBUG,"appending to existing journal "+FileLabel(name)+" ("+
                IntegerToString((long)FileSize(h))+" bytes)");
      return h;
     }

   void              CloseCsv(int &h)
     {
      if(h!=INVALID_HANDLE)
        {
         FileFlush(h);
         FileClose(h);
        }
      h=INVALID_HANDLE;
     }

   //--- write one row; false (and a throttled error) when nothing was written
   bool              WriteRow(const int h,const string row,const string name)
     {
      if(h==INVALID_HANDLE)
         return false;
      ResetLastError();
      uint written=FileWriteString(h,row+"\r\n");
      if(written>0)
         return true;
      m_writeErrors++;
      if(CheckPointer(m_log)!=POINTER_INVALID)
         m_log.Throttled(FTF_LOG_ERROR,"JRNL.write."+name,60000,"JRNL","write to "+name+" failed (error "+
                         IntegerToString(GetLastError())+", total "+IntegerToString(m_writeErrors)+" failures)");
      return false;
     }

   //--- common identity columns: platform;symbol;instance
   string            Identity(void)
     {
      return San(m_platform)+";"+San(m_symbol)+";"+IntegerToString(m_instanceId);
     }

   //--- event / signal timestamp, never empty (falls back to server time)
   long              SafeMsc(const long msc)
     {
      if(msc>0)
         return msc;
      return (long)TimeCurrent()*1000;
     }

   //--- decision text of signals.csv
   string            Decision(const bool accepted,const int reason)
     {
      if(accepted)
         return "ACCEPTED";
      if(reason==FTF_REJ_CONFIRM_PENDING)
         return "PENDING";
      return "REJECTED";
     }

   //--- trades.csv part 1: identity, timing and prices
   string            TradeRowA(const STrackedPos &p,const SClosedTrade &t)
     {
      double dur=0.0;
      if(t.closeMsc>0 && p.openMsc>0 && t.closeMsc>=p.openMsc)
         dur=(double)(t.closeMsc-p.openMsc)/1000.0;
      string r=IntegerToString((long)p.ticket)+";"+IntegerToString(p.positionId)+";"+Identity()+";"+
               FTF_ModeStr(p.mode)+";"+IntegerToString(p.engine)+";"+FTF_EngineName(p.engine)+";"+
               San(p.tfText)+";"+San(p.setupId)+";"+FTF_DirStr(p.dir)+";"+Lots(p.lots)+";";
      r+=FTF_TimeMscStr(p.signalMsc)+";"+FTF_TimeMscStr(p.openMsc)+";"+FTF_TimeMscStr(t.closeMsc)+";"+
         DoubleToString(dur,3)+";";
      r+=Px(p.signalPrice)+";"+Px(p.requestedPrice)+";"+Px(p.openPrice)+";"+Px(t.closePrice)+";"+
         Pts(p.slippagePts)+";"+Ms(p.decisionMs)+";"+Ms(p.latencyMs)+";"+Pts(p.spreadPts)+";"+
         Px(p.initialSL)+";"+Px(p.initialTP)+";"+Px(p.sl);
      return r;
     }

   //--- trades.csv part 2: money, excursions, context, exit
   string            TradeRowB(const STrackedPos &p,const SClosedTrade &t,const double stressMoney)
     {
      double rMult=(p.riskMoney>0.0 ? t.net/p.riskMoney : 0.0);
      string r=Money(p.riskMoney)+";"+Money(t.profit)+";"+Money(t.commission)+";"+Money(t.swap)+";"+
               Money(t.net)+";"+Money(stressMoney)+";"+Money(t.net-stressMoney)+";"+Ratio(rMult)+";";
      r+=Pts(p.maePts)+";"+Pts(p.mfePts)+";"+Money(p.equityAtEntry)+";"+DoubleToString(p.ddPctAtEntry,2)+";"+
         FTF_H1StateStr(p.h1State)+";"+IntegerToString(p.retries)+";"+Flag(p.recovered)+";"+San(p.entryReason)+";";
      r+=IntegerToString(t.exitReason)+";"+FTF_ExitStr(t.exitReason)+";"+San(t.exitDetail);
      return r;
     }

public:
                     CTradeJournal(void)
     {
      m_log=NULL;
      m_folder="";
      m_useCommon=false;
      m_enabled=false;
      m_logSignals=false;
      m_platform=FTF_PLATFORM;
      m_symbol="";
      m_instanceId=0;
      m_modeText="";
      m_digits=5;
      m_point=0.00001;
      m_hSignals=INVALID_HANDLE;
      m_hTrades=INVALID_HANDLE;
      m_hEvents=INVALID_HANDLE;
      m_sigUnflushed=0;
      m_rowsSignals=0;
      m_rowsTrades=0;
      m_rowsEvents=0;
      m_writeErrors=0;
     }
                    ~CTradeJournal(void)
     {
      CloseCsv(m_hSignals);
      CloseCsv(m_hTrades);
      CloseCsv(m_hEvents);
     }

   void              Deinit(void)
     {
      if(m_enabled && (m_hSignals!=INVALID_HANDLE || m_hTrades!=INVALID_HANDLE || m_hEvents!=INVALID_HANDLE))
         LogMsg(FTF_LOG_INFO,"CSV journals closed: "+IntegerToString(m_rowsSignals)+" signal rows, "+
                IntegerToString(m_rowsTrades)+" trade rows, "+IntegerToString(m_rowsEvents)+" event rows"+
                (m_writeErrors>0 ? ", "+IntegerToString(m_writeErrors)+" write errors" : ""));
      CloseCsv(m_hSignals);
      CloseCsv(m_hTrades);
      CloseCsv(m_hEvents);
      m_sigUnflushed=0;
     }

   //--- docs/09 7.2. Never fails the EA: a file that cannot be opened is disabled and logged (FilesOk()).
   bool              Init(CLogger *logger,const string folder,const bool useCommon,const bool enabled,const bool logSignals,
                          const string platform,const string symbol,const int instanceId,const string modeText)
     {
      Deinit();
      m_log=logger;
      m_folder=folder;
      m_useCommon=useCommon;
      m_enabled=enabled;
      m_logSignals=logSignals;
      m_platform=platform;
      m_symbol=symbol;
      m_instanceId=instanceId;
      m_modeText=modeText;
      m_rowsSignals=0;
      m_rowsTrades=0;
      m_rowsEvents=0;
      m_writeErrors=0;
      if(!m_enabled)
        {
         LogMsg(FTF_LOG_INFO,"CSV journals OFF (signals/trades/events not written)");
         return true;
        }
      if(StringLen(m_folder)>0)
        {
         if(CheckPointer(m_log)!=POINTER_INVALID)
            m_log.MakeFolder(m_folder,m_useCommon);
         else if(!FolderCreate(m_folder,(m_useCommon ? FILE_COMMON : 0)))
            ResetLastError();   // folder may already exist
        }
      if(m_logSignals)
         m_hSignals=OpenCsv("signals.csv",FTF_CSV_SIGNALS_HEADER);
      m_hTrades=OpenCsv("trades.csv",FTF_CSV_TRADES_HEADER);
      m_hEvents=OpenCsv("events.csv",FTF_CSV_EVENTS_HEADER);
      LogMsg(FTF_LOG_INFO,"CSV journals ON in "+(m_useCommon ? "Common\\Files\\" : "Files\\")+m_folder+
             " | signals "+(m_logSignals ? (m_hSignals!=INVALID_HANDLE ? "OK" : "FAILED") : "OFF")+
             " | trades "+(m_hTrades!=INVALID_HANDLE ? "OK" : "FAILED")+
             " | events "+(m_hEvents!=INVALID_HANDLE ? "OK" : "FAILED"));
      return true;
     }

   //--- price formatting after the symbol spec is known (controller)
   void              SetDigits(const int digits)
     {
      int d=digits;
      if(d<0)
         d=0;
      if(d>10)
         d=10;
      m_digits=d;
      m_point=MathPow(10.0,(double)(-d));
      LogMsg(FTF_LOG_DEBUG,"price digits set to "+IntegerToString(m_digits));
     }

   bool              Enabled(void)  { return m_enabled; }
   //--- true when every requested CSV is open (or the journal is disabled)
   bool              FilesOk(void)
     {
      if(!m_enabled)
         return true;
      if(m_logSignals && m_hSignals==INVALID_HANDLE)
         return false;
      return (m_hTrades!=INVALID_HANDLE && m_hEvents!=INVALID_HANDLE);
     }

   //--- signals.csv: one row per signal decision (step 11 of the pipeline, docs/09 section 8)
   void              LogSignal(const SSignal &s,const bool accepted,const int reason,const string detail,
                               const double bid,const double ask,const double lots)
     {
      if(!m_enabled || !m_logSignals || m_hSignals==INVALID_HANDLE)
         return;
      long msc=SafeMsc(s.timeMsc);
      string r=FTF_TimeMscStr(msc)+";"+IntegerToString(msc)+";"+Identity()+";"+San(m_modeText)+";"+
               IntegerToString(s.engine)+";"+FTF_EngineName(s.engine)+";"+San(s.tfText)+";"+
               IntegerToString(s.id)+";"+San(s.setupId)+";"+FTF_DirStr(s.dir)+";";
      r+=Px(s.price)+";"+Px(bid)+";"+Px(ask)+";"+Pts(s.spreadPts)+";"+Px(s.sl)+";"+Px(s.tp)+";"+
         DistPts(s.price,s.sl)+";"+DistPts(s.price,s.tp)+";"+DoubleToString(s.quality,1)+";"+
         FTF_H1StateStr(s.h1State)+";"+Flag(s.structOk)+";"+Lots(lots)+";";
      r+=Decision(accepted,reason)+";"+IntegerToString(reason)+";"+FTF_ReasonStr(reason)+";"+
         San(detail)+";"+San(s.reason);
      if(!WriteRow(m_hSignals,r,"signals.csv"))
         return;
      m_rowsSignals++;
      m_sigUnflushed++;
      if(m_sigUnflushed>=FTF_JOURNAL_SIGNAL_FLUSH)
        {
         FileFlush(m_hSignals);
         m_sigUnflushed=0;
        }
      LogMsg(FTF_LOG_TRACE,"signals.csv #"+IntegerToString(m_rowsSignals)+" sig "+IntegerToString(s.id)+" "+
             FTF_EngineCode(s.engine)+" "+FTF_DirStr(s.dir)+" -> "+Decision(accepted,reason)+" "+FTF_ReasonStr(reason));
     }

   //--- trades.csv: one row per closed position (step 5, tracker.Sync). stressCommission = total money (cost)
   void              LogTrade(const STrackedPos &p,const SClosedTrade &t,const double stressCommission)
     {
      if(!m_enabled || m_hTrades==INVALID_HANDLE)
         return;
      double stressMoney=MathAbs(stressCommission);   // a commission is always a cost
      string r=TradeRowA(p,t)+";"+TradeRowB(p,t,stressMoney);
      if(!WriteRow(m_hTrades,r,"trades.csv"))
         return;
      FileFlush(m_hTrades);   // closed trades are rare and precious: flush every row
      m_rowsTrades++;
      LogMsg(FTF_LOG_DEBUG,"trades.csv #"+IntegerToString(m_rowsTrades)+" ticket "+IntegerToString((long)p.ticket)+" "+
             FTF_EngineCode(p.engine)+" "+FTF_DirStr(p.dir)+" net "+Money(t.net)+" (after stress "+
             Money(t.net-stressMoney)+") exit "+FTF_ExitStr(t.exitReason));
     }

   //--- events.csv: categories of docs/09 section 4.3 (INIT DEINIT CONFIG STATE ... STATS)
   void              LogEvent(const long msc,const string category,const string code,const string detail)
     {
      if(!m_enabled || m_hEvents==INVALID_HANDLE)
         return;
      long t=SafeMsc(msc);
      string r=FTF_TimeMscStr(t)+";"+IntegerToString(t)+";"+Identity()+";"+San(category)+";"+San(code)+";"+San(detail);
      if(!WriteRow(m_hEvents,r,"events.csv"))
         return;
      FileFlush(m_hEvents);
      m_rowsEvents++;
      LogMsg(FTF_LOG_TRACE,"events.csv #"+IntegerToString(m_rowsEvents)+" "+category+"/"+code);
     }

   void              Flush(void)
     {
      if(!m_enabled)
         return;
      if(m_hSignals!=INVALID_HANDLE)
         FileFlush(m_hSignals);
      if(m_hTrades!=INVALID_HANDLE)
         FileFlush(m_hTrades);
      if(m_hEvents!=INVALID_HANDLE)
         FileFlush(m_hEvents);
      m_sigUnflushed=0;
     }

   long              SignalRows(void)  { return m_rowsSignals; }
   long              TradeRows(void)   { return m_rowsTrades; }
   long              EventRows(void)   { return m_rowsEvents; }
  };

#endif // FTF_JOURNAL_MQH
