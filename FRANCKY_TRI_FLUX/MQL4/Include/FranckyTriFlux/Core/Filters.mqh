//+------------------------------------------------------------------+
//|                                                      Filters.mqh |
//|  Time-based entry filters (docs/09 section 7.16, docs/03 sec. 5):|
//|   CNewsFilter     - news windows (spec B.1)                      |
//|   CSessionFilter  - allowed days / hours (spec B.2)              |
//|   CRolloverFilter - daily rollover window (spec B.3)             |
//|  Filters only block NEW entries; open positions keep being       |
//|  managed by the position manager.                                |
//+------------------------------------------------------------------+
#ifndef FTF_FILTERS_MQH
#define FTF_FILTERS_MQH

#include <FranckyTriFlux\Core\Context.mqh>

#define FTF_FILT_NEWS_BACK_SEC        86400    // load window starts 1 day back (events still inside their after-window)
#define FTF_FILT_NEWS_AHEAD_SEC       691200   // ... and ends 8 days ahead
#define FTF_FILT_NEWS_HTTP_TIMEOUT    5000     // web feed timeout (ms)
#define FTF_FILT_NEWS_MAX_EVENTS      5000     // TUNABLE (not an input yet) max events kept in the 9-day window
#define FTF_FILT_NEWS_MAX_CACHE       200000   // TUNABLE (not an input yet) max CSV events cached in the tester
#define FTF_FILT_NEWS_MAX_LINES       500000   // TUNABLE (not an input yet) max CSV lines read
#define FTF_FILT_NEWS_WEB_MIN_REFRESH 15       // TUNABLE (not an input yet) min minutes between two web downloads (feed rate limit)
#define FTF_FILT_NEWS_DRAW_AHEAD_SEC  86400    // draw blocking events of the next 24 h
#define FTF_FILT_NEWS_MAX_DRAWN       40       // TUNABLE (not an input yet) max news events drawn

//+------------------------------------------------------------------+
//| helpers (file-local prefix FTF_Filt)                             |
//| NOTE: StringSubstr(s,a,0) returns the TAIL in MQL4 but "" in     |
//| MQL5 - every computed substring goes through FTF_FiltSub.        |
//+------------------------------------------------------------------+
string FTF_FiltSub(const string s,const int start,const int len)
  {
   int n=StringLen(s);
   if(len<=0 || start<0 || start>=n)
      return "";
   return StringSubstr(s,start,len);
  }

string FTF_FiltTail(const string s,const int start)
  {
   int n=StringLen(s);
   if(start<0 || start>=n)
      return "";
   return StringSubstr(s,start,n-start);
  }

//--- minute of day -> "07:00"
string FTF_FiltHHMM(const int minuteOfDay)
  {
   if(minuteOfDay<0)
      return "--:--";
   int m=minuteOfDay%1440;
   if(minuteOfDay==1440)
      return "24:00";
   return StringFormat("%02d:%02d",m/60,m%60);
  }

string FTF_FiltDayName(const int dow)
  {
   switch(dow)
     {
      case 0:  return "Sun";
      case 1:  return "Mon";
      case 2:  return "Tue";
      case 3:  return "Wed";
      case 4:  return "Thu";
      case 5:  return "Fri";
      case 6:  return "Sat";
      default: break;
     }
   return "?";
  }

//--- seconds -> "35m", "2h10m", "3d4h"
string FTF_FiltIn(const long secs)
  {
   long s=(secs>0 ? secs : (long)0);
   long m=s/60;
   if(m<60)
      return IntegerToString(m)+"m";
   long h=m/60;
   if(h<24)
      return IntegerToString(h)+"h"+StringFormat("%02d",(int)(m%60))+"m";
   return IntegerToString(h/24)+"d"+IntegerToString(h%24)+"h";
  }

string FTF_FiltShort(const string s,const int maxLen)
  {
   if(StringLen(s)<=maxLen || maxLen<4)
      return s;
   return FTF_FiltSub(s,0,maxLen-2)+"..";
  }

//+------------------------------------------------------------------+
//| CNewsFilter - B.1                                                |
//| Sources: MT5 calendar (via CPlatform), CSV file, ForexFactory    |
//| weekly XML feed (via CPlatform.HttpGet). Window [t-before,       |
//| t+after] blocks NEW entries for events of the watched currencies |
//| with impact >= min impact OR a title containing a keyword.       |
//+------------------------------------------------------------------+
class CNewsFilter
  {
private:
   CFtfContext      *m_ctx;
   bool              m_isTester;
   SNewsEvent        m_ev[];           // loaded events, sorted by time
   bool              m_blk[];          // event blocks entries
   int               m_n;
   SNewsEvent        m_tmp[];          // load buffer
   int               m_tmpN;
   SNewsEvent        m_cache[];        // tester only: CSV parsed once (watched currencies), sorted
   int               m_cacheN;
   bool              m_cacheReady;
   string            m_cacheKey;
   int               m_cacheCur;
   string            m_ccy[];          // watched currencies (upper case)
   int               m_nCcy;
   string            m_kw[];           // keywords (upper case)
   int               m_nKw;
   datetime          m_lastRefresh;
   datetime          m_lastWeb;
   string            m_used;           // sources used by the last successful load
   int               m_srcState;       // -1 unknown, 0 no source, 1 ok
   bool              m_emptyWarned;
   bool              m_blocking;
   string            m_blockDetail;
   int               m_scan;           // events before this index have their window over
   int               m_version;
   int               m_drawnVersion;
   datetime          m_lastDraw;
   int               m_drawn;

   bool              Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.cfg)!=POINTER_INVALID &&
              CheckPointer(m_ctx.pf)!=POINTER_INVALID);
     }
   datetime          NowSrv(void)
     {
      long ms=m_ctx.NowMsc();
      if(ms>0)
         return (datetime)(ms/1000);
      return m_ctx.pf.ServerTime();
     }
   void              LogI(const string msg) { if(CheckPointer(m_ctx.logger)!=POINTER_INVALID) m_ctx.logger.Info("NEWS",msg); }
   void              LogW(const string msg) { if(CheckPointer(m_ctx.logger)!=POINTER_INVALID) m_ctx.logger.Warn("NEWS",msg); }
   void              LogE(const string msg) { if(CheckPointer(m_ctx.logger)!=POINTER_INVALID) m_ctx.logger.Error("NEWS",msg); }
   void              LogD(const string msg) { if(CheckPointer(m_ctx.logger)!=POINTER_INVALID) m_ctx.logger.Debug("NEWS",msg); }
   long              BeforeSec(void) { return (long)m_ctx.cfg.NewsMinsBefore*60; }
   long              AfterSec(void)  { return (long)m_ctx.cfg.NewsMinsAfter*60; }

   //--- currencies ---------------------------------------------------
   bool              IsNonFiat(const string u)
     {
      return (u=="XAU" || u=="XAG" || u=="XPT" || u=="XPD" || u=="BTC" || u=="XBT" || u=="ETH" || u=="LTC" || u=="XRP");
     }
   void              AddCcy(const string c,const bool skipNonFiat)
     {
      string u=FTF_Upper(FTF_Trim(c));
      if(StringLen(u)==0 || (skipNonFiat && IsNonFiat(u)))
         return;
      for(int i=0;i<m_nCcy;i++)
         if(m_ccy[i]==u)
            return;
      ArrayResize(m_ccy,m_nCcy+1);
      m_ccy[m_nCcy]=u;
      m_nCcy++;
     }
   //--- AUTO: base + profit currency of the chart symbol, metals/crypto skipped (EURUSD -> EUR,USD; XAUUSD/BTCUSD -> USD)
   void              BuildCurrencies(void)
     {
      ArrayResize(m_ccy,0);
      m_nCcy=0;
      string setting=FTF_Upper(FTF_Trim(m_ctx.cfg.NewsCurrencies));
      if(StringLen(setting)>0 && setting!="AUTO")
        {
         string parts[];
         int np=FTF_SplitList(setting,parts);
         for(int i=0;i<np;i++)
            AddCcy(parts[i],false);
         return;
        }
      string base="";
      string prof="";
      if(CheckPointer(m_ctx.md)!=POINTER_INVALID)
        {
         base=m_ctx.md.spec.baseCcy;
         prof=m_ctx.md.spec.profitCcy;
        }
      if(StringLen(base)==0 && StringLen(prof)==0)
        {
         //--- symbol spec not loaded yet: derive from the name (handles suffixes, GOLD, XBTUSD)
         string cls=FTF_SymbolClass(m_ctx.symbol);
         string nm=(StringLen(cls)==6 ? cls : FTF_Upper(m_ctx.symbol));
         base=FTF_FiltSub(nm,0,3);
         prof=FTF_FiltSub(nm,3,3);
        }
      AddCcy(base,true);
      AddCcy(prof,true);
     }
   bool              CcyWanted(const string c)
     {
      for(int i=0;i<m_nCcy;i++)
         if(m_ccy[i]==c)
            return true;
      return false;
     }
   string            CcyText(void)
     {
      string s="";
      for(int i=0;i<m_nCcy;i++)
         s+=(i>0 ? "," : "")+m_ccy[i];
      return (StringLen(s)>0 ? s : "none");
     }

   //--- blocking rule: impact >= min impact OR keyword in the title (case-insensitive)
   bool              IsBlockingEvent(const SNewsEvent &e)
     {
      if(e.impact>=(int)m_ctx.cfg.NewsMinImpact)
         return true;
      string ut=FTF_Upper(e.title);
      for(int i=0;i<m_nKw;i++)
         if(StringLen(m_kw[i])>0 && StringFind(ut,m_kw[i])>=0)
            return true;
      return false;
     }
   int               BlockingCount(void)
     {
      int c=0;
      for(int i=0;i<m_n;i++)
         if(m_blk[i])
            c++;
      return c;
     }

   //--- sources ------------------------------------------------------
   //--- AUTO: tester or MT4 -> CSV, MT5 live -> calendar. WEB is impossible in the tester -> CSV.
   void              ResolveSource(bool &useCal,bool &useCsv,bool &useWeb)
     {
      useCal=false;
      useCsv=false;
      useWeb=false;
      int src=(int)m_ctx.cfg.NewsSource;
      bool mt4=(m_ctx.pf.Name()=="MT4");
      if(src==FTF_NEWS_AUTO)
        {
         if(m_isTester || mt4)
            useCsv=true;
         else
            useCal=true;
        }
      else if(src==FTF_NEWS_CALENDAR)
         useCal=true;
      else if(src==FTF_NEWS_CSV)
         useCsv=true;
      else if(src==FTF_NEWS_WEB)
        {
         if(m_isTester)
            useCsv=true;
         else
            useWeb=true;
        }
      else
        {
         useCal=true;
         useCsv=true;
        }
     }
   string            SourceName(void)
     {
      bool useCal=false,useCsv=false,useWeb=false;
      ResolveSource(useCal,useCsv,useWeb);
      string s="";
      if(useCal)
         s+="CALENDAR";
      if(useWeb)
         s+=(StringLen(s)>0 ? "+" : "")+"WEB";
      if(useCsv)
         s+=(StringLen(s)>0 ? "+" : "")+"CSV '"+m_ctx.cfg.NewsCsvFile+"'"+(m_ctx.cfg.NewsCsvCommon ? " (Common)" : "");
      return s;
     }
   bool              CsvExists(void)
     {
      return FileIsExist(m_ctx.cfg.NewsCsvFile,(m_ctx.cfg.NewsCsvCommon ? FILE_COMMON : 0));
     }

   //--- append to the load buffer (window + currency filter, de-duplicated when sources are merged)
   bool              AddTmp(const SNewsEvent &e,const datetime from,const datetime to)
     {
      if(e.timeServer<from || e.timeServer>to || m_tmpN>=FTF_FILT_NEWS_MAX_EVENTS)
         return false;
      if(!CcyWanted(e.currency))
         return false;
      for(int i=0;i<m_tmpN;i++)
         if(m_tmp[i].timeServer==e.timeServer && m_tmp[i].currency==e.currency && FTF_Upper(m_tmp[i].title)==FTF_Upper(e.title))
            return false;
      ArrayResize(m_tmp,m_tmpN+1,64);
      m_tmp[m_tmpN]=e;
      m_tmpN++;
      return true;
     }
   void              AddCache(const SNewsEvent &e)
     {
      if(m_cacheN>=FTF_FILT_NEWS_MAX_CACHE || !CcyWanted(e.currency))
         return;
      ArrayResize(m_cache,m_cacheN+1,1024);
      m_cache[m_cacheN]=e;
      m_cacheN++;
     }
   //--- insertion sort by time (fast path for already sorted files)
   void              SortEvents(SNewsEvent &arr[],const int n)
     {
      int cnt=(n<ArraySize(arr) ? n : ArraySize(arr));
      SNewsEvent key;
      for(int i=1;i<cnt;i++)
        {
         if(arr[i].timeServer>=arr[i-1].timeServer)
            continue;
         key=arr[i];
         int j=i-1;
         while(j>=0 && arr[j].timeServer>key.timeServer)
           {
            arr[j+1]=arr[j];
            j--;
           }
         arr[j+1]=key;
        }
     }

   int               LoadCalendarSrc(const datetime from,const datetime to)
     {
      if(m_nCcy<=0)
         return 0;
      SNewsEvent cal[];
      int k=m_ctx.pf.LoadCalendar(from,to,m_ccy,m_nCcy,cal);
      if(k>ArraySize(cal))
         k=ArraySize(cal);
      for(int i=0;i<k;i++)
        {
         cal[i].currency=FTF_Upper(FTF_Trim(cal[i].currency));
         string tt=cal[i].title;
         StringReplace(tt,";",",");                     // keep events.csv columns intact
         cal[i].title=tt;
         if(StringLen(cal[i].source)==0)
            cal[i].source="CALENDAR";
         AddTmp(cal[i],from,to);
        }
      return k;
     }

   //--- CSV line 'yyyy.mm.dd hh:mi;CCY;IMPACT;Title' -> 1 event, 0 skip (empty/comment/header), -1 bad
   int               ParseCsvLine(const string raw,SNewsEvent &e)
     {
      e.Reset();
      string line=FTF_Trim(raw);
      while(StringLen(line)>0 && StringGetCharacter(line,0)>127)
         line=FTF_Trim(FTF_FiltTail(line,1));            // UTF-8 / UTF-16 BOM remnants
      if(StringLen(line)==0 || StringGetCharacter(line,0)=='#')
         return 0;
      string u=FTF_Upper(line);
      if(StringFind(u,"DATE")==0 || StringFind(u,"TIME")==0)
         return 0;
      ushort sep=(StringFind(line,";")>=0 ? (ushort)';' : (ushort)',');
      string f[];
      int nf=StringSplit(line,sep,f);
      if(nf<3)
         return -1;
      string ts=FTF_Trim(f[0]);
      StringReplace(ts,"-",".");
      StringReplace(ts,"/",".");
      StringReplace(ts,"T"," ");
      ushort c0=StringGetCharacter(ts,0);
      if(c0<'0' || c0>'9')
         return -1;
      datetime t=StringToTime(ts);
      if(t<(datetime)946684800)                          // before 2000.01.01 = unreadable
         return -1;
      if(m_ctx.cfg.NewsCsvUtc && CheckPointer(m_ctx.clock)!=POINTER_INVALID)
         t=m_ctx.clock.UtcToServer(t);
      e.timeServer=t;
      e.currency=FTF_Upper(FTF_Trim(f[1]));
      e.impact=FTF_ParseImpact(f[2]);
      string title="";
      for(int i=3;i<nf;i++)
         title+=(i>3 ? "," : "")+f[i];
      e.title=FTF_Trim(title);
      e.source="CSV";
      return (StringLen(e.currency)>0 ? 1 : -1);
     }

   bool              ReadCsvFile(const bool toCache,const datetime from,const datetime to,string &why)
     {
      why="";
      string fname=m_ctx.cfg.NewsCsvFile;
      int flags=FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ;
      if(m_ctx.cfg.NewsCsvCommon)
         flags|=FILE_COMMON;
      ResetLastError();
      int h=FileOpen(fname,flags);
      if(h==INVALID_HANDLE)
        {
         why="news CSV '"+fname+"' not found in "+(m_ctx.cfg.NewsCsvCommon ? "Common\\Files" : "the terminal Files folder")+
             " (error "+IntegerToString(GetLastError())+")";
         return false;
        }
      if(toCache)
        {
         m_cacheN=0;
         ArrayResize(m_cache,0);
        }
      int lines=0,bad=0,good=0;
      SNewsEvent e;
      while(!FileIsEnding(h) && lines<FTF_FILT_NEWS_MAX_LINES)
        {
         string line=FileReadString(h);
         lines++;
         int r=ParseCsvLine(line,e);
         if(r<0)
            bad++;
         if(r<=0)
            continue;
         good++;
         if(toCache)
            AddCache(e);
         else
            AddTmp(e,from,to);
        }
      FileClose(h);
      if(toCache)
         SortEvents(m_cache,m_cacheN);
      LogD("news CSV '"+fname+"': "+IntegerToString(lines)+" lines, "+IntegerToString(good)+" events"+
           (toCache ? ", "+IntegerToString(m_cacheN)+" cached for "+CcyText() : ""));
      if(bad>0)
         LogW("news CSV '"+fname+"': "+IntegerToString(bad)+" unreadable line(s) skipped (expected 'yyyy.mm.dd hh:mi;CCY;HIGH|MEDIUM|LOW;Title')");
      return true;
     }

   //--- tester: the file is parsed once, every refresh copies its window from the sorted cache
   bool              LoadCsv(const datetime from,const datetime to,string &why)
     {
      why="";
      if(!m_isTester)
         return ReadCsvFile(false,from,to,why);
      string key=CcyText();
      if(!m_cacheReady || m_cacheKey!=key)
        {
         if(!ReadCsvFile(true,from,to,why))
            return false;
         m_cacheReady=true;
         m_cacheKey=key;
         m_cacheCur=0;
        }
      if(m_cacheCur>m_cacheN || (m_cacheCur>0 && m_cache[m_cacheCur-1].timeServer>=from))
         m_cacheCur=0;
      while(m_cacheCur<m_cacheN && m_cache[m_cacheCur].timeServer<from)
         m_cacheCur++;
      for(int i=m_cacheCur;i<m_cacheN;i++)
        {
         if(m_cache[i].timeServer>to)
            break;
         AddTmp(m_cache[i],from,to);
        }
      return true;
     }

   //--- inner text of <tag>..</tag>, CDATA wrapper removed, basic entities decoded
   string            XmlTag(const string blk,const string tag)
     {
      string otag="<"+tag+">";
      string ctag="</"+tag+">";
      int a=StringFind(blk,otag);
      if(a<0)
         return "";
      a+=StringLen(otag);
      int b=StringFind(blk,ctag,a);
      if(b<=a)
         return "";
      string v=FTF_Trim(FTF_FiltSub(blk,a,b-a));
      if(StringFind(v,"<![CDATA[")==0)
        {
         v=FTF_FiltTail(v,9);
         int c=StringFind(v,"]]>");
         if(c>=0)
            v=FTF_FiltSub(v,0,c);
         v=FTF_Trim(v);
        }
      StringReplace(v,"&amp;","&");
      StringReplace(v,"&lt;","<");
      StringReplace(v,"&gt;",">");
      StringReplace(v,"&quot;","\"");
      StringReplace(v,"&apos;","'");
      StringReplace(v,"&#39;","'");
      StringReplace(v,";",",");                          // keep events.csv columns intact
      return v;
     }

   //--- ForexFactory weekly XML event. ASSUMPTION: the feed's <date>/<time> are UTC (GMT);
   //--- converted with CClock.UtcToServer. Events without a clock time (All Day, Tentative, empty) are skipped.
   bool              ParseFfEvent(const string blk,SNewsEvent &e)
     {
      e.Reset();
      string dt=XmlTag(blk,"date");
      string tm=FTF_Upper(XmlTag(blk,"time"));
      string dp[];
      if(StringSplit(dt,(ushort)'-',dp)!=3)
         return false;
      int mo=(int)StringToInteger(dp[0]);
      int dd=(int)StringToInteger(dp[1]);
      int yy=(int)StringToInteger(dp[2]);
      if(yy<2000 || mo<1 || mo>12 || dd<1 || dd>31)
         return false;
      int len=StringLen(tm);
      if(len<6)
         return false;
      string ap=FTF_FiltTail(tm,len-2);
      if(ap!="AM" && ap!="PM")
         return false;
      string hm[];
      if(StringSplit(FTF_FiltSub(tm,0,len-2),(ushort)':',hm)!=2)
         return false;
      int hh=(int)StringToInteger(FTF_Trim(hm[0]));
      int mi=(int)StringToInteger(FTF_Trim(hm[1]));
      if(hh<1 || hh>12 || mi<0 || mi>59)
         return false;
      if(ap=="AM" && hh==12)
         hh=0;
      if(ap=="PM" && hh<12)
         hh+=12;
      MqlDateTime st;
      st.year=yy; st.mon=mo; st.day=dd; st.hour=hh; st.min=mi; st.sec=0; st.day_of_week=0; st.day_of_year=0;
      datetime utc=StructToTime(st);
      e.timeServer=(CheckPointer(m_ctx.clock)!=POINTER_INVALID ? m_ctx.clock.UtcToServer(utc) : utc);
      e.currency=FTF_Upper(XmlTag(blk,"country"));
      e.impact=FTF_ParseImpact(XmlTag(blk,"impact"));     // High/Medium/Low; Holiday -> 0
      e.title=XmlTag(blk,"title");
      e.source="WEB";
      return (StringLen(e.currency)>0);
     }

   int               ParseFfXml(const string body,const datetime from,const datetime to)
     {
      int found=0;
      int pos=0;
      int len=StringLen(body);
      SNewsEvent e;
      while(pos<len)
        {
         int a=StringFind(body,"<event>",pos);
         if(a<0)
            break;
         int b=StringFind(body,"</event>",a);
         if(b<0)
            break;
         string blk=FTF_FiltSub(body,a+7,b-a-7);
         pos=b+8;
         found++;
         if(ParseFfEvent(blk,e))
            AddTmp(e,from,to);
        }
      return found;
     }

   bool              LoadWeb(const datetime from,const datetime to,string &why)
     {
      why="";
      string url=FTF_Trim(m_ctx.cfg.NewsWebUrl);
      if(StringLen(url)==0)
        {
         why="web feed URL is empty";
         return false;
        }
      string body="";
      int code=0;
      m_lastWeb=NowSrv();
      bool ok=m_ctx.pf.HttpGet(url,FTF_FILT_NEWS_HTTP_TIMEOUT,body,code);
      if(!ok || code!=200 || StringLen(body)==0)
        {
         why="web feed failed (HTTP "+IntegerToString(code)+", "+IntegerToString(StringLen(body))+
             " bytes) - add the URL in Tools > Options > Expert Advisors > Allow WebRequest";
         return false;
        }
      int found=ParseFfXml(body,from,to);
      if(found<=0)
        {
         why="web feed: no <event> element in "+IntegerToString(StringLen(body))+" bytes";
         return false;
        }
      LogD("web feed: "+IntegerToString(found)+" <event> elements parsed");
      return true;
     }

   //--- load buffer -> active list
   void              Commit(void)
     {
      SortEvents(m_tmp,m_tmpN);
      ArrayResize(m_ev,m_tmpN);
      ArrayResize(m_blk,m_tmpN);
      for(int i=0;i<m_tmpN;i++)
        {
         m_ev[i]=m_tmp[i];
         m_blk[i]=IsBlockingEvent(m_ev[i]);
        }
      m_n=m_tmpN;
      m_scan=0;
      m_version++;
     }

   //--- "NEWS USD HIGH Non-Farm Payrolls 12:30 (+3m)"
   string            EventText(const int i,const datetime now)
     {
      long diff=(long)now-(long)m_ev[i].timeServer;
      long mins=(diff>=0 ? diff : -diff)/60;
      string rel=(diff>=0 ? "+" : "-")+IntegerToString(mins)+"m";
      string imp=FTF_ImpactStr(m_ev[i].impact);
      if(m_ev[i].impact<(int)m_ctx.cfg.NewsMinImpact)
         imp+="/KEYWORD";
      return "NEWS "+m_ev[i].currency+" "+imp+" "+m_ev[i].title+" "+TimeToString(m_ev[i].timeServer,TIME_MINUTES)+" ("+rel+")";
     }

   string            NextText(const datetime now)
     {
      SNewsEvent ev;
      if(!NextEvent(ev))
         return "none";
      long secs=(long)ev.timeServer-(long)now;
      return ev.currency+" "+FTF_ImpactStr(ev.impact)+" "+ev.title+" "+TimeToString(ev.timeServer,TIME_DATE|TIME_MINUTES)+
             (secs>0 ? " (in "+FTF_FiltIn(secs)+")" : " (now)");
     }

   void              SetSourceState(const int st,const string info)
     {
      if(st==m_srcState)
         return;
      int prev=m_srcState;
      m_srcState=st;
      if(st==0)
         m_ctx.Event("NEWS","SOURCE_MISSING",info+" - the news filter cannot block entries");
      else if(prev==0)
         m_ctx.Event("NEWS","SOURCE_OK","news source available again: "+info);
     }

   void              ReportLoad(const bool anyOk,const bool force,const string used,const string problems,const datetime now)
     {
      int prevN=m_n;
      if(anyOk)
        {
         Commit();
         m_used=used;
         bool loud=(force || m_srcState!=1 || (prevN==0 && m_n>0));   // routine reloads go to DEBUG
         string msg="news: "+IntegerToString(m_n)+" events loaded ("+IntegerToString(BlockingCount())+" blocking, source "+used+
                    ", currencies "+CcyText()+"), next: "+NextText(now);
         if(StringLen(problems)>0)
            msg+=" | "+problems;
         if(loud)
            LogI(msg);
         else
            LogD(msg);
         if(m_n==0 && !m_emptyWarned)
           {
            LogW("news: no event for "+CcyText()+" between "+FTF_TimeStr((datetime)((long)now-FTF_FILT_NEWS_BACK_SEC))+" and "+
                 FTF_TimeStr((datetime)((long)now+FTF_FILT_NEWS_AHEAD_SEC))+" - check that the source covers this period");
            m_emptyWarned=true;
           }
         if(m_n>0)
            m_emptyWarned=false;
         SetSourceState(1,"source "+used+", "+IntegerToString(m_n)+" events");
         return;
        }
      LogE("news source unavailable: "+problems+"- the news filter CANNOT block entries"+
           (m_n>0 ? " (keeping "+IntegerToString(m_n)+" previously loaded events)" : ""));
      SetSourceState(0,problems);
     }

public:
                     CNewsFilter(void)
     {
      m_ctx=NULL; m_isTester=false; m_n=0; m_tmpN=0; m_cacheN=0; m_cacheReady=false; m_cacheKey=""; m_cacheCur=0;
      m_nCcy=0; m_nKw=0; m_lastRefresh=0; m_lastWeb=0; m_used=""; m_srcState=-1; m_emptyWarned=false;
      m_blocking=false; m_blockDetail=""; m_scan=0; m_version=0; m_drawnVersion=-1; m_lastDraw=0; m_drawn=0;
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(!Ready())
         return false;
      m_isTester=m_ctx.pf.IsTester();
      m_n=0; m_tmpN=0; m_cacheN=0; m_cacheReady=false; m_scan=0; m_lastRefresh=0; m_lastWeb=0;
      m_srcState=-1; m_blocking=false; m_blockDetail="";
      ArrayResize(m_ev,0);
      ArrayResize(m_blk,0);
      BuildCurrencies();
      m_nKw=FTF_SplitList(m_ctx.cfg.NewsKeywords,m_kw);
      for(int i=0;i<m_nKw;i++)
         m_kw[i]=FTF_Upper(m_kw[i]);
      LogI("news filter "+(m_ctx.cfg.NewsEnabled ? "ON" : "OFF")+": source "+SourceName()+", currencies "+CcyText()+
           ", min impact "+FTF_ImpactStr((int)m_ctx.cfg.NewsMinImpact)+", "+IntegerToString(m_nKw)+" keywords, window -"+
           IntegerToString(m_ctx.cfg.NewsMinsBefore)+"/+"+IntegerToString(m_ctx.cfg.NewsMinsAfter)+" min, refresh "+
           IntegerToString(m_ctx.cfg.NewsRefreshMin)+" min"+(m_ctx.cfg.NewsCsvUtc ? ", CSV times UTC" : ", CSV times server"));
      return true;
     }

   //--- reload every InpNewsRefreshMin minutes of server time (force = now, e.g. 10 % pause re-activation)
   void              Refresh(const bool force)
     {
      if(!Ready() || !m_ctx.cfg.NewsEnabled)
         return;
      datetime now=NowSrv();
      if(now<=0)
         return;
      long age=(long)now-(long)m_lastRefresh;
      if(!force && m_lastRefresh>0 && age>=0 && age<(long)m_ctx.cfg.NewsRefreshMin*60)
         return;
      bool useCal=false,useCsv=false,useWeb=false;
      ResolveSource(useCal,useCsv,useWeb);
      if(useWeb && !useCal && m_n>0 && m_lastWeb>0)
        {
         long webAge=(long)now-(long)m_lastWeb;
         if(webAge>=0 && webAge<(long)FTF_FILT_NEWS_WEB_MIN_REFRESH*60)
           {
            m_lastRefresh=now;                           // feed rate limit: keep the current list
            LogD("news: web feed downloaded "+IntegerToString(webAge)+" s ago - list kept");
            return;
           }
        }
      m_lastRefresh=now;
      BuildCurrencies();
      datetime from=(datetime)((long)now-FTF_FILT_NEWS_BACK_SEC);
      datetime to=(datetime)((long)now+FTF_FILT_NEWS_AHEAD_SEC);
      m_tmpN=0;
      ArrayResize(m_tmp,0);
      string used="";
      string problems="";
      bool anyOk=false;
      if(m_nCcy<=0)
         problems+="no currency to watch (check 'Currencies'); ";
      if(useCal)
        {
         if(LoadCalendarSrc(from,to)>0)
           {
            anyOk=true;
            used+="CALENDAR ";
           }
         else
           {
            problems+="MT5 calendar returned no event; ";
            useCsv=true;                                 // fallback keeps the filter able to block
           }
        }
      if(useWeb)
        {
         string whyWeb="";
         if(LoadWeb(from,to,whyWeb))
           {
            anyOk=true;
            used+="WEB ";
           }
         else
           {
            problems+=whyWeb+"; ";
            useCsv=true;                                 // fallback to the CSV file
           }
        }
      if(useCsv)
        {
         string whyCsv="";
         if(LoadCsv(from,to,whyCsv))
           {
            anyOk=true;
            used+="CSV ";
           }
         else
            problems+=whyCsv+"; ";
        }
      ReportLoad(anyOk,force,FTF_Trim(used),problems,now);
     }

   bool              IsBlocked(string &detail)
     {
      detail="";
      if(!Ready())
         return false;
      if(!m_ctx.cfg.NewsEnabled)
        {
         m_blocking=false;
         return false;
        }
      Refresh(false);
      datetime now=NowSrv();
      long nowL=(long)now;
      long before=BeforeSec();
      long after=AfterSec();
      while(m_scan<m_n && (long)m_ev[m_scan].timeServer+after<nowL)
         m_scan++;                                       // sorted list: those windows are over
      int hit=-1;
      for(int i=m_scan;i<m_n;i++)
        {
         long t=(long)m_ev[i].timeServer;
         if(t-before>nowL)
            break;                                       // later events start later
         if(m_blk[i] && nowL>=t-before && nowL<=t+after)
           {
            hit=i;
            break;
           }
        }
      if(hit<0)
        {
         if(m_blocking)
           {
            m_blocking=false;
            m_ctx.Event("NEWS","BLOCK_END","news window over ("+m_blockDetail+") - new entries allowed by the news filter");
           }
         return false;
        }
      detail=EventText(hit,now);
      if(!m_blocking)
        {
         long t0=(long)m_ev[hit].timeServer;
         m_blocking=true;
         m_ctx.Event("NEWS","BLOCK_START",detail+" window "+TimeToString((datetime)(t0-before),TIME_MINUTES)+"-"+
                     TimeToString((datetime)(t0+after),TIME_MINUTES)+" server - no new entries");
        }
      m_blockDetail=detail;
      return true;
     }

   //--- next blocking event whose window is not over (current one included)
   bool              NextEvent(SNewsEvent &ev)
     {
      ev.Reset();
      if(!Ready() || m_n<=0)
         return false;
      long nowL=(long)NowSrv();
      long after=AfterSec();
      int from=(m_scan<m_n ? m_scan : 0);
      for(int i=from;i<m_n;i++)
        {
         if(!m_blk[i] || (long)m_ev[i].timeServer+after<nowL)
            continue;
         ev=m_ev[i];
         return true;
        }
      return false;
     }

   int               Count(void)         { return m_n; }
   int               BlockingEvents(void) { return BlockingCount(); }   // extra

   //--- blocking events of the next 24 h: vertical line at the event + title (objects NEWS_<n>, NEWS_<n>_T)
   void              Draw(void)
     {
      if(!Ready() || !m_ctx.cfg.NewsEnabled || !m_ctx.cfg.NewsDraw)
         return;
      if(CheckPointer(m_ctx.ui)==POINTER_INVALID || !m_ctx.ui.Enabled())
         return;
      datetime now=NowSrv();
      long nowL=(long)now;
      long since=nowL-(long)m_lastDraw;
      if(m_drawnVersion==m_version && m_lastDraw>0 && since>=0 && since<60)
         return;
      m_drawnVersion=m_version;
      m_lastDraw=now;
      double price=(CheckPointer(m_ctx.md)!=POINTER_INVALID ? m_ctx.md.BidPrice() : 0.0);
      long before=BeforeSec();
      long after=AfterSec();
      int k=0;
      for(int i=0;i<m_n && k<FTF_FILT_NEWS_MAX_DRAWN;i++)
        {
         long t=(long)m_ev[i].timeServer;
         if(!m_blk[i] || t+after<nowL)
            continue;
         if(t>nowL+FTF_FILT_NEWS_DRAW_AHEAD_SEC)
            break;
         color clr=clrGold;
         if(m_ev[i].impact>=3)
            clr=clrRed;
         else if(m_ev[i].impact==2)
            clr=clrOrange;
         string id="NEWS_"+IntegerToString(k);
         string tip=m_ev[i].currency+" "+FTF_ImpactStr(m_ev[i].impact)+" "+m_ev[i].title+" "+TimeToString(m_ev[i].timeServer,TIME_MINUTES)+
                    " | no entries "+TimeToString((datetime)(t-before),TIME_MINUTES)+"-"+TimeToString((datetime)(t+after),TIME_MINUTES);
         m_ctx.ui.DrawVLine(id,m_ev[i].timeServer,clr,tip);
         if(price>0.0)
            m_ctx.ui.DrawText(id+"_T",m_ev[i].timeServer,price,m_ev[i].currency+" "+FTF_FiltShort(m_ev[i].title,28),clr);
         k++;
        }
      for(int j=k;j<m_drawn;j++)
        {
         m_ctx.ui.Remove("NEWS_"+IntegerToString(j));
         m_ctx.ui.Remove("NEWS_"+IntegerToString(j)+"_T");
        }
      m_drawn=k;
     }

   //--- 'news ON next USD Non-Farm Payrolls in 2h10m' / 'news OFF'
   string            Describe(void)
     {
      if(!Ready())
         return "news n/a";
      if(!m_ctx.cfg.NewsEnabled)
         return "news OFF";
      if(m_blocking)
         return "news BLOCK "+FTF_FiltShort(FTF_FiltTail(m_blockDetail,5),48);
      SNewsEvent ev;
      if(NextEvent(ev))
        {
         long secs=(long)ev.timeServer-(long)NowSrv();
         return "news ON next "+ev.currency+" "+FTF_FiltShort(ev.title,24)+(secs>0 ? " in "+FTF_FiltIn(secs) : " now");
        }
      if(m_srcState==0 && m_n==0)
         return "news ON - NO DATA ("+SourceName()+")";
      if(m_srcState<0)
         return "news ON (not loaded yet)";
      return "news ON no event ahead";
     }

   //--- PASS if disabled, events loaded, or the CSV source exists
   bool              SelfCheck(string &d)
     {
      d="";
      if(!Ready())
        {
         d="news filter not initialised";
         return false;
        }
      if(!m_ctx.cfg.NewsEnabled)
        {
         d="news filter OFF (input)";
         return true;
        }
      string base="source "+SourceName()+(StringLen(m_used)>0 ? " (last used "+m_used+")" : "")+", currencies "+CcyText()+", "+
                  IntegerToString(m_n)+" events ("+IntegerToString(BlockingCount())+" blocking)";
      if(m_nCcy<=0)
        {
         d=base+" - no currency to watch";
         return false;
        }
      if(m_n>0)
        {
         d=base+", next: "+NextText(NowSrv());
         return true;
        }
      if(CsvExists())                                   // every source falls back to the CSV
        {
         d=base+" - CSV present, no event in the current window";
         return true;
        }
      d=base+" - NO news data: the filter cannot block entries";
      return false;
     }
  };

//+------------------------------------------------------------------+
//| CSessionFilter - B.2. Presets are UTC; CUSTOM uses the inputs in |
//| SERVER or UTC time. The day-of-week check uses the same basis.   |
//| Unparseable CUSTOM window 1 => no entries (fail-safe, WARN).     |
//+------------------------------------------------------------------+
class CSessionFilter
  {
private:
   CFtfContext      *m_ctx;
   string            m_name;
   bool              m_utc;
   int               m_s1;
   int               m_e1;
   int               m_s2;
   int               m_e2;
   bool              m_has2;
   bool              m_bad1;   // CUSTOM window 1 unparseable
   bool              m_bad2;   // CUSTOM window 2 given but unparseable
   int               m_last;   // -1 unknown, 0 closed, 1 open

   bool              Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.cfg)!=POINTER_INVALID &&
              CheckPointer(m_ctx.pf)!=POINTER_INVALID);
     }
   datetime          NowSrv(void)
     {
      long ms=m_ctx.NowMsc();
      if(ms>0)
         return (datetime)(ms/1000);
      return m_ctx.pf.ServerTime();
     }
   string            BasisName(void) { return (m_utc ? "UTC" : "server"); }
   bool              DayAllowed(const int dow)
     {
      switch(dow)
        {
         case 0:  return m_ctx.cfg.TradeSunday;
         case 1:  return m_ctx.cfg.TradeMonday;
         case 2:  return m_ctx.cfg.TradeTuesday;
         case 3:  return m_ctx.cfg.TradeWednesday;
         case 4:  return m_ctx.cfg.TradeThursday;
         case 5:  return m_ctx.cfg.TradeFriday;
         case 6:  return m_ctx.cfg.TradeSaturday;
         default: break;
        }
      return false;
     }
   string            DaysText(void)
     {
      string s="";
      if(m_ctx.cfg.TradeMonday)    s+="Mo";
      if(m_ctx.cfg.TradeTuesday)   s+="Tu";
      if(m_ctx.cfg.TradeWednesday) s+="We";
      if(m_ctx.cfg.TradeThursday)  s+="Th";
      if(m_ctx.cfg.TradeFriday)    s+="Fr";
      if(m_ctx.cfg.TradeSaturday)  s+="Sa";
      if(m_ctx.cfg.TradeSunday)    s+="Su";
      return (StringLen(s)>0 ? s : "no day");
     }
   //--- "LONDON_NY 07:00-21:00 UTC"
   string            WindowText(void)
     {
      string s=m_name+" ";
      if(m_bad1)
         s+="??:??-??:??";
      else
         s+=FTF_FiltHHMM(m_s1)+"-"+FTF_FiltHHMM(m_e1);
      if(m_has2)
         s+=" + "+FTF_FiltHHMM(m_s2)+"-"+FTF_FiltHHMM(m_e2);
      return s+" "+BasisName();
     }
   //--- server time -> basis time (UTC through CClock)
   datetime          BasisTime(const datetime srv)
     {
      if(!m_utc)
         return srv;
      if(CheckPointer(m_ctx.clock)==POINTER_INVALID)
        {
         if(CheckPointer(m_ctx.logger)!=POINTER_INVALID)
            m_ctx.logger.Throttled(FTF_LOG_WARN,"SESS.noclock",m_ctx.cfg.LogThrottleMs,"SESS","clock not available - UTC session evaluated on server time");
         return srv;
        }
      return m_ctx.clock.ServerToUtc(srv);
     }
   //--- pure evaluation (no event)
   bool              Evaluate(string &detail)
     {
      detail="";
      datetime t=BasisTime(NowSrv());
      int minute=FTF_MinuteOfDay(t);
      int dow=FTF_DayOfWeek(t);
      bool dayOk=DayAllowed(dow);
      bool inWin=false;
      if(!m_bad1 && FTF_InMinuteWindow(minute,m_s1,m_e1))
         inWin=true;
      if(m_has2 && FTF_InMinuteWindow(minute,m_s2,m_e2))
         inWin=true;
      string nowTxt="now "+FTF_FiltHHMM(minute)+" "+BasisName()+" "+FTF_FiltDayName(dow);
      if(!dayOk)
         detail="day not traded ("+FTF_FiltDayName(dow)+" disabled, days "+DaysText()+", "+WindowText()+", "+nowTxt+")";
      else if(!inWin && m_bad1 && !m_has2)
         detail="CUSTOM session hours unparseable ('"+m_ctx.cfg.TradingStart+"'-'"+m_ctx.cfg.TradingEnd+"') - no new entries until fixed";
      else if(!inWin)
         detail="outside session ("+WindowText()+", "+nowTxt+")";
      else
         detail="inside session ("+WindowText()+", "+nowTxt+")";
      return (dayOk && inWin);
     }

public:
                     CSessionFilter(void)
     {
      m_ctx=NULL; m_name=""; m_utc=true; m_s1=-1; m_e1=-1; m_s2=-1; m_e2=-1;
      m_has2=false; m_bad1=false; m_bad2=false; m_last=-1;
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(!Ready())
         return false;
      m_s2=-1; m_e2=-1; m_has2=false; m_bad1=false; m_bad2=false; m_last=-1; m_utc=true;
      int p=(int)m_ctx.cfg.SessionPreset;
      if(p==FTF_SESS_LONDON)                { m_name="LONDON";         m_s1=420;  m_e1=960;  }
      else if(p==FTF_SESS_NEWYORK)          { m_name="NEW_YORK";       m_s1=720;  m_e1=1260; }
      else if(p==FTF_SESS_LONDON_NY)        { m_name="LONDON_NY";      m_s1=420;  m_e1=1260; }
      else if(p==FTF_SESS_ASIA)             { m_name="ASIA";           m_s1=1380; m_e1=480;  }
      else if(p==FTF_SESS_ASIA_LONDON_NY)   { m_name="ASIA_LONDON_NY"; m_s1=1380; m_e1=1260; }
      else
        {
         m_name="CUSTOM";
         m_utc=(m_ctx.cfg.SessionTimeBasis==FTF_TIME_UTC);
         m_s1=FTF_ParseHHMM(m_ctx.cfg.TradingStart);
         m_e1=FTF_ParseHHMM(m_ctx.cfg.TradingEnd);
         if(m_s1==1440)
            m_s1=0;                                      // "24:00" as a start = midnight
         m_bad1=(m_s1<0 || m_e1<0);
         string st2=FTF_Trim(m_ctx.cfg.TradingStart2);
         string en2=FTF_Trim(m_ctx.cfg.TradingEnd2);
         if(StringLen(st2)>0 || StringLen(en2)>0)
           {
            m_s2=FTF_ParseHHMM(st2);
            m_e2=FTF_ParseHHMM(en2);
            if(m_s2==1440)
               m_s2=0;
            m_has2=(m_s2>=0 && m_e2>=0);
            m_bad2=!m_has2;
           }
        }
      if(CheckPointer(m_ctx.logger)!=POINTER_INVALID)
        {
         m_ctx.logger.Info("SESS","session filter "+(m_ctx.cfg.SessionEnabled ? "ON" : "OFF (24h)")+": "+WindowText()+", days "+DaysText()+
                        (m_utc && CheckPointer(m_ctx.clock)!=POINTER_INVALID ? ", clock "+m_ctx.clock.Describe() : ""));
         if(m_ctx.cfg.SessionEnabled && m_bad1)
            m_ctx.logger.Error("SESS","CUSTOM TradingStart/TradingEnd unparseable ('"+m_ctx.cfg.TradingStart+"'-'"+m_ctx.cfg.TradingEnd+
                            "', expected HH:MM) - window 1 never open");
         if(m_ctx.cfg.SessionEnabled && m_bad2)
            m_ctx.logger.Warn("SESS","CUSTOM window 2 unparseable ('"+m_ctx.cfg.TradingStart2+"'-'"+m_ctx.cfg.TradingEnd2+"') - ignored");
        }
      return true;
     }

   bool              IsAllowed(string &detail)
     {
      detail="";
      if(!Ready() || !m_ctx.cfg.SessionEnabled)
         return true;
      string txt="";
      bool allowed=Evaluate(txt);
      int st=(allowed ? 1 : 0);
      if(st!=m_last)
        {
         m_last=st;
         m_ctx.Event("SESSION",(allowed ? "OPEN" : "CLOSE"),txt);
        }
      if(!allowed)
         detail=txt;
      return allowed;
     }

   //--- "session LONDON_NY 07:00-21:00 UTC MoTuWeThFr OPEN"
   string            Describe(void)
     {
      if(!Ready())
         return "session n/a";
      if(!m_ctx.cfg.SessionEnabled)
         return "session OFF (24h)";
      string txt="";
      bool allowed=Evaluate(txt);
      return "session "+WindowText()+" "+DaysText()+(allowed ? " OPEN" : " CLOSED");
     }

   bool              SelfCheck(string &d)
     {
      d="";
      if(!Ready())
        {
         d="session filter not initialised";
         return false;
        }
      if(!m_ctx.cfg.SessionEnabled)
        {
         d="session filter OFF (input) - 24h trading on every quoted day";
         return true;
        }
      bool ok=true;
      string issues="";
      if(m_bad1)
        {
         ok=false;
         issues+=" | CUSTOM window 1 unparseable ('"+m_ctx.cfg.TradingStart+"'-'"+m_ctx.cfg.TradingEnd+"')";
        }
      if(m_bad2)
        {
         ok=false;
         issues+=" | CUSTOM window 2 unparseable ('"+m_ctx.cfg.TradingStart2+"'-'"+m_ctx.cfg.TradingEnd2+"')";
        }
      if(DaysText()=="no day")
        {
         ok=false;
         issues+=" | no trading day enabled";
        }
      if(m_utc && CheckPointer(m_ctx.clock)==POINTER_INVALID)
        {
         ok=false;
         issues+=" | clock unavailable (UTC basis)";
        }
      string txt="";
      Evaluate(txt);
      d=WindowText()+", days "+DaysText()+(m_utc && CheckPointer(m_ctx.clock)!=POINTER_INVALID ? ", clock "+m_ctx.clock.Describe() : "")+
        ", "+txt+issues;
      return ok;
     }
  };

//+------------------------------------------------------------------+
//| CRolloverFilter - B.3. Server time, window                        |
//| [rollover - before, rollover + after) with wrap past midnight.    |
//+------------------------------------------------------------------+
class CRolloverFilter
  {
private:
   CFtfContext      *m_ctx;
   int               m_roll;   // minute of day (server), -1 = unparseable
   int               m_last;   // -1 unknown, 0 clear, 1 blocked
   string            m_lastDetail;

   bool              Ready(void)
     {
      return (CheckPointer(m_ctx)!=POINTER_INVALID && CheckPointer(m_ctx.cfg)!=POINTER_INVALID &&
              CheckPointer(m_ctx.pf)!=POINTER_INVALID);
     }
   datetime          NowSrv(void)
     {
      long ms=m_ctx.NowMsc();
      if(ms>0)
         return (datetime)(ms/1000);
      return m_ctx.pf.ServerTime();
     }
   int               StartMin(void)
     {
      int before=(m_ctx.cfg.RolloverMinsBefore>0 ? m_ctx.cfg.RolloverMinsBefore : 0);
      return ((m_roll-before)%1440+1440)%1440;
     }
   int               EndMin(void)
     {
      int after=(m_ctx.cfg.RolloverMinsAfter>0 ? m_ctx.cfg.RolloverMinsAfter : 0);
      return (m_roll+after)%1440;
     }
   string            WindowText(void)
     {
      return "rollover "+FTF_FiltHHMM(m_roll)+" server, window "+FTF_FiltHHMM(StartMin())+"-"+FTF_FiltHHMM(EndMin());
     }
   //--- pure evaluation (no event)
   bool              Evaluate(string &detail)
     {
      detail="";
      if(m_roll<0)
        {
         if(CheckPointer(m_ctx.logger)!=POINTER_INVALID)
            m_ctx.logger.Throttled(FTF_LOG_WARN,"ROLL.bad",m_ctx.cfg.LogThrottleMs,"ROLL","rollover time '"+m_ctx.cfg.RolloverTime+
                                "' unparseable (HH:MM) - rollover filter inactive");
         return false;
        }
      int before=(m_ctx.cfg.RolloverMinsBefore>0 ? m_ctx.cfg.RolloverMinsBefore : 0);
      int after=(m_ctx.cfg.RolloverMinsAfter>0 ? m_ctx.cfg.RolloverMinsAfter : 0);
      if(before+after<=0)
         return false;
      int minute=FTF_MinuteOfDay(NowSrv());
      bool blocked=(before+after>=1440 ? true : FTF_InMinuteWindow(minute,StartMin(),EndMin()));
      if(blocked)
         detail=WindowText()+" (now "+FTF_FiltHHMM(minute)+" server)";
      return blocked;
     }

public:
                     CRolloverFilter(void)
     {
      m_ctx=NULL; m_roll=-1; m_last=-1; m_lastDetail="";
     }

   bool              Init(CFtfContext *ctx)
     {
      m_ctx=ctx;
      if(!Ready())
         return false;
      m_roll=FTF_ParseHHMM(m_ctx.cfg.RolloverTime);
      if(m_roll==1440)
         m_roll=0;
      m_last=-1;
      m_lastDetail="";
      if(CheckPointer(m_ctx.logger)!=POINTER_INVALID)
        {
         if(m_roll<0)
            m_ctx.logger.Error("ROLL","rollover time '"+m_ctx.cfg.RolloverTime+"' unparseable (expected HH:MM) - rollover filter inactive");
         else
            m_ctx.logger.Info("ROLL","rollover filter "+(m_ctx.cfg.RolloverEnabled ? "ON" : "OFF")+": "+WindowText()+
                           " (-"+IntegerToString(m_ctx.cfg.RolloverMinsBefore)+"/+"+IntegerToString(m_ctx.cfg.RolloverMinsAfter)+" min)");
        }
      return true;
     }

   bool              IsBlocked(string &detail)
     {
      detail="";
      if(!Ready() || !m_ctx.cfg.RolloverEnabled)
         return false;
      bool blocked=Evaluate(detail);
      if(blocked && m_last!=1)
        {
         m_ctx.Event("ROLLOVER","BLOCK_START",detail+" - no new entries");
         m_lastDetail=detail;
        }
      else if(!blocked && m_last==1)
         m_ctx.Event("ROLLOVER","BLOCK_END",WindowText()+" over - new entries allowed by the rollover filter");
      m_last=(blocked ? 1 : 0);
      return blocked;
     }

   //--- "rollover 00:00 (-10/+15m) clear" / "rollover BLOCK until 00:15"
   string            Describe(void)
     {
      if(!Ready())
         return "rollover n/a";
      if(!m_ctx.cfg.RolloverEnabled)
         return "rollover OFF";
      if(m_roll<0)
         return "rollover BAD TIME '"+m_ctx.cfg.RolloverTime+"'";
      string txt="";
      if(Evaluate(txt))
         return "rollover BLOCK until "+FTF_FiltHHMM(EndMin());
      return "rollover "+FTF_FiltHHMM(m_roll)+" (-"+IntegerToString(m_ctx.cfg.RolloverMinsBefore)+"/+"+
             IntegerToString(m_ctx.cfg.RolloverMinsAfter)+"m) clear";
     }

   bool              SelfCheck(string &d)
     {
      d="";
      if(!Ready())
        {
         d="rollover filter not initialised";
         return false;
        }
      if(!m_ctx.cfg.RolloverEnabled)
        {
         d="rollover filter OFF (input)";
         return true;
        }
      if(m_roll<0)
        {
         d="rollover time '"+m_ctx.cfg.RolloverTime+"' unparseable (HH:MM) - filter inactive";
         return false;
        }
      string txt="";
      bool blocked=Evaluate(txt);
      d=WindowText()+(blocked ? " - blocking now ("+txt+")" : " - not blocking now");
      return true;
     }
  };

#endif // FTF_FILTERS_MQH
