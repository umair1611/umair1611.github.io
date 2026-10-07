//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|  CLogger - levelled text logger (Experts journal + ftf.log file) |
//|  with key-based throttling of repeated messages.                 |
//|  docs/09 section 7.1 - Line format:                              |
//|  "2026.10.07 10:35:01.123 | INFO  | MOM  | message"              |
//|  This is the ONLY Core class allowed to call Print() (docs/10).  |
//|  Shared Core: identical in the MQL5 and MQL4 trees.              |
//+------------------------------------------------------------------+
#ifndef FTF_LOGGER_MQH
#define FTF_LOGGER_MQH

#include <FranckyTriFlux\Core\Defines.mqh>
#include <FranckyTriFlux\Core\Utils.mqh>

#define FTF_LOG_THROTTLE_KEYS   256        // TUNABLE (not an input yet) - distinct throttle keys remembered (oldest overwritten)
#define FTF_LOG_FLUSH_LINES     20         // TUNABLE (not an input yet) - flush ftf.log every N lines (WARN/ERROR flush at once)
#define FTF_LOG_FILE_NAME       "ftf.log"  // text log file name inside the log folder (docs/09 7.1)

class CLogger
  {
private:
   int               m_level;          // ENUM_FTF_LOG_LEVEL (0 = OFF)
   bool              m_toJournal;      // Print() to the Experts journal
   bool              m_toFile;         // write <folder>\ftf.log (false after an open failure)
   bool              m_useCommon;      // folder is under Terminal\Common\Files
   string            m_folder;         // log folder relative to (Common\)Files
   string            m_tag;            // instance tag printed in front of journal lines
   int               m_handle;         // ftf.log handle (INVALID_HANDLE when closed)
   long              m_nowMsc;         // server ms of the current cycle (SetTimeMsc)
   int               m_unflushed;      // lines written since the last FileFlush
   long              m_lines;          // lines emitted since Init
   int               m_writeErrors;    // failed FileWriteString calls
   //--- throttling (parallel arrays, docs/10: no struct array copies needed)
   string            m_thrKeys[FTF_LOG_THROTTLE_KEYS];
   long              m_thrLast[FTF_LOG_THROTTLE_KEYS];
   int               m_thrSupp[FTF_LOG_THROTTLE_KEYS];
   int               m_thrCount;

   //--- right-pad a text with spaces up to width (never truncates)
   string            Pad(const string s,const int width)
     {
      string out=s;
      int n=StringLen(out);
      while(n<width)
        {
         out+=" ";
         n++;
        }
      return out;
     }

   //--- 5-character level label used in every line
   string            LevelLabel(const int lvl)
     {
      switch(lvl)
        {
         case FTF_LOG_ERROR: return "ERROR";
         case FTF_LOG_WARN:  return "WARN ";
         case FTF_LOG_INFO:  return "INFO ";
         case FTF_LOG_DEBUG: return "DEBUG";
         case FTF_LOG_TRACE: return "TRACE";
         default:            break;
        }
      return "LOG  ";
     }

   //--- timestamp source: cycle server ms, else server time, else local time (before the first tick)
   long              StampMsc(void)
     {
      if(m_nowMsc>0)
         return m_nowMsc;
      long t=(long)TimeCurrent();
      if(t<=0)
         t=(long)TimeLocal();
      return t*1000;
     }

   string            FilePath(void)
     {
      if(StringLen(m_folder)==0)
         return FTF_LOG_FILE_NAME;
      return m_folder+"\\"+FTF_LOG_FILE_NAME;
     }

   //--- direct journal output used for logger self-diagnostics (independent of level/toJournal)
   void              SelfReport(const string msg)
     {
      string prefix=(StringLen(m_tag)>0 ? m_tag+" | " : "");
      Print(prefix+FTF_TimeMscStr(StampMsc())+" | ERROR | LOG  | "+msg);
     }

   //--- create every level of a folder path under (Common\)Files; failures ignored (folder may exist)
   bool              CreateFolderPath(const string path,const bool inCommon)
     {
      string p=path;
      StringReplace(p,"/","\\");
      string parts[];
      int n=StringSplit(p,StringGetCharacter("\\",0),parts);
      string cur="";
      bool ok=true;
      for(int i=0;i<n;i++)
        {
         if(StringLen(parts[i])==0)
            continue;
         cur=(StringLen(cur)>0 ? cur+"\\"+parts[i] : parts[i]);
         if(!FolderCreate(cur,(inCommon ? FILE_COMMON : 0)))
            ok=false;
        }
      ResetLastError();
      return ok;
     }

   //--- open <folder>\ftf.log once in append mode (docs/09 7.1); false -> file output disabled
   bool              OpenFile(void)
     {
      if(StringLen(m_folder)>0)
         CreateFolderPath(m_folder,m_useCommon);
      int flags=FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ;
      if(m_useCommon)
         flags|=FILE_COMMON;
      ResetLastError();
      m_handle=FileOpen(FilePath(),flags);
      if(m_handle==INVALID_HANDLE)
        {
         int err=GetLastError();
         SelfReport("cannot open log file "+(m_useCommon ? "Common\\Files\\" : "Files\\")+FilePath()+
                    " (error "+IntegerToString(err)+") - file logging DISABLED, journal only");
         return false;
        }
      if(!FileSeek(m_handle,0,SEEK_END))
         SelfReport("FileSeek to end of "+FilePath()+" failed (error "+IntegerToString(GetLastError())+")");
      return true;
     }

   void              CloseFile(void)
     {
      if(m_handle!=INVALID_HANDLE)
        {
         FileFlush(m_handle);
         FileClose(m_handle);
        }
      m_handle=INVALID_HANDLE;
      m_unflushed=0;
     }

   //--- format one line and send it to the enabled outputs
   void              Write(const int lvl,const string src,const string msg)
     {
      if(m_level<=FTF_LOG_OFF || lvl>m_level)
         return;
      string line=FTF_TimeMscStr(StampMsc())+" | "+LevelLabel(lvl)+" | "+Pad(src,4)+" | "+msg;
      m_lines++;
      if(m_toJournal)
         Print(StringLen(m_tag)>0 ? m_tag+" | "+line : line);
      if(!m_toFile || m_handle==INVALID_HANDLE)
         return;
      uint written=FileWriteString(m_handle,line+"\r\n");
      if(written==0)
        {
         m_writeErrors++;
         if(m_writeErrors==1 || (m_writeErrors%1000)==0)
            SelfReport("write to "+FilePath()+" failed (error "+IntegerToString(GetLastError())+", "+
                       IntegerToString(m_writeErrors)+" failures)");
        }
      m_unflushed++;
      //--- WARN/ERROR are flushed immediately so a crash never hides the reason (docs/10 behaviour rules)
      if(lvl<=FTF_LOG_WARN || m_unflushed>=FTF_LOG_FLUSH_LINES)
        {
         FileFlush(m_handle);
         m_unflushed=0;
        }
     }

   int               FindKey(const string key)
     {
      for(int i=0;i<m_thrCount;i++)
         if(m_thrKeys[i]==key)
            return i;
      return -1;
     }

   //--- free slot for a new throttle key; when full the least recently emitted key is overwritten
   int               NewSlot(void)
     {
      if(m_thrCount<FTF_LOG_THROTTLE_KEYS)
        {
         m_thrCount++;
         return m_thrCount-1;
        }
      int oldest=0;
      for(int i=1;i<FTF_LOG_THROTTLE_KEYS;i++)
         if(m_thrLast[i]<m_thrLast[oldest])
            oldest=i;
      return oldest;
     }

   void              ResetThrottle(void)
     {
      for(int i=0;i<FTF_LOG_THROTTLE_KEYS;i++)
        {
         m_thrKeys[i]="";
         m_thrLast[i]=0;
         m_thrSupp[i]=0;
        }
      m_thrCount=0;
     }

public:
                     CLogger(void)
     {
      m_level=FTF_LOG_INFO;
      m_toJournal=true;
      m_toFile=false;
      m_useCommon=false;
      m_folder="";
      m_tag="";
      m_handle=INVALID_HANDLE;
      m_nowMsc=0;
      m_unflushed=0;
      m_lines=0;
      m_writeErrors=0;
      ResetThrottle();
     }
                    ~CLogger(void)
     {
      CloseFile();
     }

   //--- create every level of a folder path under (Common\)Files (used by Journal / StateStore too)
   bool              MakeFolder(const string path,const bool useCommon) { return CreateFolderPath(path,useCommon); }

   void              SetTimeMsc(const long msc)          { m_nowMsc=msc; }
   bool              IsEnabled(const int level)          { return (m_level>FTF_LOG_OFF && level<=m_level); }
   void              SetLevel(const int level)           { m_level=level; }
   int               Level(void)                         { return m_level; }
   bool              FileOk(void)                        { return (m_toFile && m_handle!=INVALID_HANDLE); }
   string            Folder(void)                        { return m_folder; }
   string            Tag(void)                           { return m_tag; }

   void              Error(const string src,const string msg) { Write(FTF_LOG_ERROR,src,msg); }
   void              Warn(const string src,const string msg)  { Write(FTF_LOG_WARN,src,msg); }
   void              Info(const string src,const string msg)  { Write(FTF_LOG_INFO,src,msg); }
   void              Debug(const string src,const string msg) { Write(FTF_LOG_DEBUG,src,msg); }
   void              Trace(const string src,const string msg) { Write(FTF_LOG_TRACE,src,msg); }

   //--- generic levelled entry point (level = ENUM_FTF_LOG_LEVEL)
   void              Log(const int level,const string src,const string msg) { Write(level,src,msg); }

   //--- same key within intervalMs -> suppressed and counted; next emission appends the count.
   //--- Used for every per-tick message (docs/10 behaviour rules, InpLogThrottleMs).
   void              Throttled(const int level,const string key,const int intervalMs,const string src,const string msg)
     {
      if(!IsEnabled(level))
         return;
      if(intervalMs<=0)
        {
         Write(level,src,msg);
         return;
        }
      long now=StampMsc();
      int idx=FindKey(key);
      if(idx<0)
        {
         idx=NewSlot();
         m_thrKeys[idx]=key;
         m_thrLast[idx]=now;
         m_thrSupp[idx]=0;
         Write(level,src,msg);
         return;
        }
      //--- time going backwards (new tester pass, clock reset) counts as elapsed
      if(now>=m_thrLast[idx] && now-m_thrLast[idx]<(long)intervalMs)
        {
         m_thrSupp[idx]++;
         return;
        }
      int suppressed=m_thrSupp[idx];
      m_thrLast[idx]=now;
      m_thrSupp[idx]=0;
      if(suppressed>0)
         Write(level,src,msg+" (+"+IntegerToString(suppressed)+" similar suppressed)");
      else
         Write(level,src,msg);
     }

   void              Flush(void)
     {
      if(m_handle!=INVALID_HANDLE)
         FileFlush(m_handle);
      m_unflushed=0;
     }

   //--- docs/09 7.1. Never fails the EA: a file problem only disables file output (see FileOk()).
   bool              Init(const int level,const bool toJournal,const bool toFile,const string folder,const bool useCommon,const string tag)
     {
      CloseFile();
      m_level=level;
      m_toJournal=toJournal;
      m_toFile=toFile;
      m_folder=folder;
      m_useCommon=useCommon;
      m_tag=tag;
      m_lines=0;
      m_writeErrors=0;
      ResetThrottle();
      if(m_toFile && !OpenFile())
         m_toFile=false;
      Info("LOG",FTF_NAME+" v"+FTF_VERSION+" logger ready | level "+FTF_Trim(LevelLabel(m_level))+
           " | journal "+(m_toJournal ? "ON" : "OFF")+" | file "+
           (m_toFile ? (m_useCommon ? "Common\\Files\\" : "Files\\")+FilePath() : "OFF")+
           (StringLen(m_tag)>0 ? " | tag "+m_tag : ""));
      return true;
     }

   void              Deinit(void)
     {
      Debug("LOG","logger closing after "+IntegerToString(m_lines)+" lines"+
            (m_writeErrors>0 ? " ("+IntegerToString(m_writeErrors)+" write errors)" : ""));
      CloseFile();
     }
  };

#endif // FTF_LOGGER_MQH
