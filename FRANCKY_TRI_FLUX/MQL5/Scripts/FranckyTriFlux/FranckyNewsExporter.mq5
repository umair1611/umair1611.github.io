//+------------------------------------------------------------------+
//|                                          FranckyNewsExporter.mq5 |
//|  FRANCKY TRI-FLUX - exports the MT5 economic calendar to a CSV   |
//|  news file used by:                                              |
//|   * the MT5 Strategy Tester (calendar functions do not work in   |
//|     the tester),                                                 |
//|   * FRANCKY MT4 (MT4 has no calendar API) - live and tester.     |
//|  Run it on any MT5 chart (live/demo account, calendar enabled).  |
//|  Output line: yyyy.mm.dd hh:mi;CCY;HIGH|MEDIUM|LOW;Title         |
//|  Default file: Terminal\Common\Files\FranckyTriFlux\news.csv     |
//|  (the Common folder is shared by MT4, MT5 and local testers).    |
//+------------------------------------------------------------------+
#property copyright   "FRANCKY TRI-FLUX"
#property version     "1.00"
#property description "Exports MT5 economic calendar events to FranckyTriFlux\\news.csv (Common\\Files)"
#property script_show_inputs

input int    InpDaysBack      = 400;                        // Days back (cover the whole backtest period)
input int    InpDaysForward   = 14;                         // Days forward
input string InpCurrencies    = "USD,EUR";                  // Currencies (comma list)
input ENUM_CALENDAR_EVENT_IMPORTANCE InpMinImportance = CALENDAR_IMPORTANCE_LOW; // Minimum importance exported
input string InpFileName      = "FranckyTriFlux\\news.csv"; // Output file
input bool   InpCommon        = true;                       // Write to Common\Files
input bool   InpWriteUtc      = true;                       // Write times in UTC (FRANCKY default: CSV times are UTC)

#define FTF_NEWS_CHUNK_SEC 2592000   // 30 days per CalendarValueHistory call (longer windows can time out)

//--- one exported row
struct SNewsRow
  {
   datetime          t;
   string            ccy;
   int               imp;
   string            title;
  };

string ImpText(const int imp)
  {
   if(imp>=3)
      return "HIGH";
   if(imp==2)
      return "MEDIUM";
   return "LOW";
  }

string Clean(const string s)
  {
   string r=s;
   StringReplace(r,";",",");
   StringReplace(r,"\r"," ");
   StringReplace(r,"\n"," ");
   return r;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   if(MQLInfoInteger(MQL_TESTER)!=0)
     {
      Print("FranckyNewsExporter: calendar functions are not available in the Strategy Tester - run it on a live chart");
      return;
     }
   datetime now=TimeTradeServer();
   long offset=(long)MathRound((double)((long)TimeTradeServer()-(long)TimeGMT())/900.0)*900;
   datetime from=now-(datetime)((long)InpDaysBack*86400);
   datetime to=now+(datetime)((long)InpDaysForward*86400);
   string ccys[];
   int nc=StringSplit(InpCurrencies,StringGetCharacter(",",0),ccys);
   SNewsRow rows[];
   int n=0;
   //--- event type cache
   ulong evId[];
   int evImp[];
   int evMode[];
   string evName[];
   int nev=0;
   for(int c=0;c<nc;c++)
     {
      string ccy=ccys[c];
      StringTrimLeft(ccy);
      StringTrimRight(ccy);
      if(StringLen(ccy)==0)
         continue;
      for(datetime a=from;a<to;a+=(datetime)FTF_NEWS_CHUNK_SEC)
        {
         datetime b=a+(datetime)FTF_NEWS_CHUNK_SEC;
         if(b>to)
            b=to;
         MqlCalendarValue vals[];
         ResetLastError();
         int nv=CalendarValueHistory(vals,a,b,NULL,ccy);
         if(nv<0 || (nv==0 && GetLastError()!=0))
           {
            PrintFormat("FranckyNewsExporter: CalendarValueHistory(%s %s..%s) failed, error %d",ccy,
                        TimeToString(a,TIME_DATE),TimeToString(b,TIME_DATE),GetLastError());
            continue;
           }
         for(int i=0;i<nv;i++)
           {
            //--- event type (importance, time mode, name)
            int k=-1;
            for(int e=0;e<nev;e++)
               if(evId[e]==vals[i].event_id)
                 {
                  k=e;
                  break;
                 }
            if(k<0)
              {
               MqlCalendarEvent ev;
               if(!CalendarEventById(vals[i].event_id,ev))
                  continue;
               ArrayResize(evId,nev+1);
               ArrayResize(evImp,nev+1);
               ArrayResize(evMode,nev+1);
               ArrayResize(evName,nev+1);
               evId[nev]=ev.id;
               evImp[nev]=(int)ev.importance;
               evMode[nev]=(int)ev.time_mode;
               evName[nev]=ev.name;
               k=nev;
               nev++;
              }
            if(evMode[k]!=(int)CALENDAR_TIMEMODE_DATETIME)
               continue;          // holidays / tentative events have no reliable time
            if(evImp[k]<(int)InpMinImportance || evImp[k]<=0)
               continue;
            ArrayResize(rows,n+1);
            rows[n].t=vals[i].time;
            rows[n].ccy=ccy;
            rows[n].imp=evImp[k];
            rows[n].title=Clean(evName[k]);
            n++;
           }
        }
     }
   //--- sort by time (insertion sort)
   for(int i=1;i<n;i++)
     {
      SNewsRow key=rows[i];
      int j=i-1;
      while(j>=0 && rows[j].t>key.t)
        {
         rows[j+1]=rows[j];
         j--;
        }
      rows[j+1]=key;
     }
   //--- write
   int flags=FILE_WRITE|FILE_TXT|FILE_ANSI;
   if(InpCommon)
      flags|=FILE_COMMON;
   FolderCreate("FranckyTriFlux",(InpCommon ? FILE_COMMON : 0));
   int h=FileOpen(InpFileName,flags);
   if(h==INVALID_HANDLE)
     {
      PrintFormat("FranckyNewsExporter: cannot open %s (error %d)",InpFileName,GetLastError());
      return;
     }
   FileWriteString(h,"# FRANCKY TRI-FLUX news export "+TimeToString(TimeLocal(),TIME_DATE|TIME_MINUTES)+" | server GMT offset "+
                   IntegerToString(offset/3600)+"h | times in "+(InpWriteUtc ? "UTC" : "SERVER time")+
                   " | note: historical DST may differ by 1 h from the current offset\r\n");
   FileWriteString(h,"# date time;currency;impact;title\r\n");
   for(int i=0;i<n;i++)
     {
      datetime t=(InpWriteUtc ? rows[i].t-(datetime)offset : rows[i].t);
      FileWriteString(h,TimeToString(t,TIME_DATE|TIME_MINUTES)+";"+rows[i].ccy+";"+ImpText(rows[i].imp)+";"+rows[i].title+"\r\n");
     }
   FileClose(h);
   PrintFormat("FranckyNewsExporter: %d events written to %s%s (%s .. %s)",n,(InpCommon ? "Common\\Files\\" : "MQL5\\Files\\"),
               InpFileName,TimeToString(from,TIME_DATE),TimeToString(to,TIME_DATE));
  }
//+------------------------------------------------------------------+
