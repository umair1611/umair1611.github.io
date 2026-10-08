//+------------------------------------------------------------------+
//|                                                   StateStore.mqh |
//|  CStateStore - persistent key=value store used to survive a      |
//|  restart (spec B.7): drawdown pause, consecutive-loss cooldowns, |
//|  martingale steps, traded setup rings, position metadata.        |
//|  One text file, one "key=value" per line, '#' = comment.         |
//|  Keys of docs/09 7.4: dd.* cl.<e>.* mg.<e>.step eng.<e>.*        |
//|  pos.<ticket>.<field> meta.saved                                 |
//|  Shared Core: identical in the MQL5 and MQL4 trees.              |
//+------------------------------------------------------------------+
#ifndef FTF_STATE_STORE_MQH
#define FTF_STATE_STORE_MQH

#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>

#define FTF_STATE_MAX_KEYS     2048     // TUNABLE (not an input yet) - hard cap of stored keys (linear search)
#define FTF_STATE_MAX_LINES    100000   // TUNABLE (not an input yet) - safety cap when reading a corrupted file
#define FTF_STATE_HEADER       "# FRANCKY TRI-FLUX state - do not edit while the EA runs"

class CStateStore
  {
private:
   CLogger          *m_log;
   string            m_fileName;       // relative to (Common\)Files, e.g. FranckyTriFlux\state\MT5_123_EURUSD_I1.state
   bool              m_useCommon;
   bool              m_enabled;        // InpStateEnabled and not in the tester (decided by the controller)
   string            m_keys[];         // parallel arrays, index 0..m_count-1
   string            m_vals[];
   int               m_count;
   bool              m_dirty;          // changed since the last successful Save
   long              m_nowMsc;         // last server ms seen by SaveIfDirty
   long              m_lastSaveMsc;    // server ms of the last save attempt
   long              m_saves;
   int               m_saveErrors;

   //--- logging helper (src tag "STOR")
   void              LogMsg(const int lvl,const string msg)
     {
      if(CheckPointer(m_log)==POINTER_INVALID)
         return;
      m_log.Log(lvl,"STOR",msg);
     }

   int               CommonFlag(void)  { return (m_useCommon ? FILE_COMMON : 0); }

   string            FileLabel(void)
     {
      return (m_useCommon ? "Common\\Files\\" : "Files\\")+m_fileName;
     }

   long              StampMsc(void)
     {
      if(m_nowMsc>0)
         return m_nowMsc;
      return (long)TimeCurrent()*1000;
     }

   //--- a key must not contain '=' or a line break (it would corrupt the file)
   string            CleanKey(const string key)
     {
      string out=key;
      StringReplace(out,"=","_");
      StringReplace(out,"\r","_");
      StringReplace(out,"\n","_");
      return out;
     }

   //--- a value must not contain a line break
   string            CleanValue(const string v)
     {
      string out=v;
      StringReplace(out,"\r"," ");
      StringReplace(out,"\n"," ");
      return out;
     }

   //--- remove trailing CR/LF that FileReadString may leave
   string            StripEol(const string s)
     {
      int n=StringLen(s);
      while(n>0)
        {
         ushort c=StringGetCharacter(s,n-1);
         if(c!='\r' && c!='\n')
            break;
         n--;
        }
      return StringSubstr(s,0,n);
     }

   int               IndexOf(const string key)
     {
      for(int i=0;i<m_count;i++)
         if(m_keys[i]==key)
            return i;
      return -1;
     }

   //--- create the folder that contains the state file (each level)
   void              MakeParentFolder(void)
     {
      string p=m_fileName;
      StringReplace(p,"/","\\");
      int cut=-1;
      int n=StringLen(p);
      for(int i=n-1;i>=0;i--)
         if(StringGetCharacter(p,i)=='\\')
           {
            cut=i;
            break;
           }
      if(cut<=0)
         return;
      string folder=StringSubstr(p,0,cut);
      if(CheckPointer(m_log)!=POINTER_INVALID)
         m_log.MakeFolder(folder,m_useCommon);
      else if(!FolderCreate(folder,CommonFlag()))
         ResetLastError();   // folder may already exist
     }

   //--- raw insert/update; true when something changed
   bool              Put(const string key,const string v)
     {
      string k=CleanKey(key);
      if(StringLen(k)==0)
         return false;
      string val=CleanValue(v);
      int i=IndexOf(k);
      if(i>=0)
        {
         if(m_vals[i]==val)
            return false;
         m_vals[i]=val;
         return true;
        }
      if(m_count>=FTF_STATE_MAX_KEYS)
        {
         if(CheckPointer(m_log)!=POINTER_INVALID)
            m_log.Throttled(FTF_LOG_ERROR,"STOR.full",60000,"STOR","state store full ("+IntegerToString(FTF_STATE_MAX_KEYS)+
                            " keys) - key '"+k+"' NOT stored");
         return false;
        }
      ArrayResize(m_keys,m_count+1,64);
      ArrayResize(m_vals,m_count+1,64);
      m_keys[m_count]=k;
      m_vals[m_count]=val;
      m_count++;
      return true;
     }

   //--- remove entry i keeping the order of the others (file stays readable)
   void              RemoveAt(const int idx)
     {
      if(idx<0 || idx>=m_count)
         return;
      for(int i=idx;i<m_count-1;i++)
        {
         m_keys[i]=m_keys[i+1];
         m_vals[i]=m_vals[i+1];
        }
      m_count--;
      ArrayResize(m_keys,m_count,64);
      ArrayResize(m_vals,m_count,64);
     }

   void              ClearAll(void)
     {
      ArrayResize(m_keys,0,64);
      ArrayResize(m_vals,0,64);
      m_count=0;
     }

   //--- one line of the file -> key/value (split at the FIRST '='); false for invalid lines
   bool              ParseLine(const string raw)
     {
      string line=StripEol(raw);
      string trimmed=FTF_Trim(line);
      if(StringLen(trimmed)==0 || StringGetCharacter(trimmed,0)=='#')
         return true;   // empty / comment: ignored, not an error
      int pos=StringFind(line,"=");
      if(pos<=0)
         return false;
      string key=FTF_Trim(StringSubstr(line,0,pos));
      if(StringLen(key)==0)
         return false;
      Put(key,StringSubstr(line,pos+1));
      return true;
     }

public:
                     CStateStore(void)
     {
      m_log=NULL;
      m_fileName="";
      m_useCommon=false;
      m_enabled=false;
      m_count=0;
      m_dirty=false;
      m_nowMsc=0;
      m_lastSaveMsc=0;
      m_saves=0;
      m_saveErrors=0;
     }

   //--- docs/09 7.4. A disabled store: getters return defaults, setters no-op, Load/Save return true.
   bool              Init(CLogger *logger,const string fileName,const bool useCommon,const bool enabled)
     {
      m_log=logger;
      m_fileName=fileName;
      m_useCommon=useCommon;
      m_enabled=(enabled && StringLen(fileName)>0);
      m_dirty=false;
      m_lastSaveMsc=0;
      m_saves=0;
      m_saveErrors=0;
      ClearAll();
      if(!m_enabled)
        {
         LogMsg(FTF_LOG_INFO,"state persistence OFF"+(enabled ? " (no file name)" : ""));
         return true;
        }
      MakeParentFolder();
      LogMsg(FTF_LOG_INFO,"state persistence ON: "+FileLabel());
      return true;
     }

   bool              Enabled(void)    { return m_enabled; }
   int               Count(void)      { return m_count; }
   bool              IsDirty(void)    { return m_dirty; }
   string            FileName(void)   { return m_fileName; }

   //--- read the whole file into memory (replaces current content). Missing file = fresh start (true).
   bool              Load(void)
     {
      if(!m_enabled)
         return true;
      if(!FileIsExist(m_fileName,CommonFlag()))
        {
         ResetLastError();
         LogMsg(FTF_LOG_INFO,"no state file "+FileLabel()+" - fresh start");
         return true;
        }
      ResetLastError();
      int h=FileOpen(m_fileName,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|CommonFlag());
      if(h==INVALID_HANDLE)
        {
         LogMsg(FTF_LOG_ERROR,"cannot open state file "+FileLabel()+" for reading (error "+
                IntegerToString(GetLastError())+") - starting WITHOUT restored state");
         return false;
        }
      ClearAll();
      int lines=0;
      int bad=0;
      while(!FileIsEnding(h) && lines<FTF_STATE_MAX_LINES)
        {
         string raw=FileReadString(h);
         lines++;
         if(!ParseLine(raw))
            bad++;
        }
      FileClose(h);
      m_dirty=false;
      int iSaved=IndexOf("meta.saved");
      long saved=0;
      if(iSaved>=0)
         saved=StringToInteger(m_vals[iSaved]);
      LogMsg(FTF_LOG_INFO,"state loaded from "+FileLabel()+": "+IntegerToString(m_count)+" keys"+
             (saved>0 ? ", saved "+FTF_TimeMscStr(saved) : "")+
             (bad>0 ? ", "+IntegerToString(bad)+" invalid line(s) ignored" : ""));
      if(bad>0)
         LogMsg(FTF_LOG_WARN,"state file "+FileLabel()+" contains "+IntegerToString(bad)+" line(s) without key=value");
      return true;
     }

   //--- rewrite the whole file (header + every key) and stamp meta.saved (server ms)
   bool              Save(void)
     {
      if(!m_enabled)
         return true;
      long now=StampMsc();
      Put("meta.saved",IntegerToString(now));
      m_lastSaveMsc=now;
      ResetLastError();
      int h=FileOpen(m_fileName,FILE_WRITE|FILE_TXT|FILE_ANSI|CommonFlag());
      if(h==INVALID_HANDLE)
        {
         m_saveErrors++;
         m_dirty=true;
         if(CheckPointer(m_log)!=POINTER_INVALID)
            m_log.Throttled(FTF_LOG_ERROR,"STOR.save",60000,"STOR","cannot write state file "+FileLabel()+
                            " (error "+IntegerToString(GetLastError())+", "+IntegerToString(m_saveErrors)+" failures)");
         return false;
        }
      bool ok=(FileWriteString(h,FTF_STATE_HEADER+"\r\n")>0);
      for(int i=0;i<m_count;i++)
         if(FileWriteString(h,m_keys[i]+"="+m_vals[i]+"\r\n")==0)
            ok=false;
      FileClose(h);
      m_saves++;
      m_dirty=!ok;
      if(!ok)
        {
         m_saveErrors++;
         LogMsg(FTF_LOG_ERROR,"state file "+FileLabel()+" written incompletely (error "+IntegerToString(GetLastError())+")");
         return false;
        }
      LogMsg(FTF_LOG_DEBUG,"state saved: "+IntegerToString(m_count)+" keys -> "+FileLabel()+
             " (save #"+IntegerToString(m_saves)+")");
      return true;
     }

   //--- periodic save (pipeline step 12, default every 2 s): only when dirty and the interval elapsed
   void              SaveIfDirty(const long nowMsc,const int minIntervalMs)
     {
      if(nowMsc>0)
         m_nowMsc=nowMsc;
      if(!m_enabled || !m_dirty)
         return;
      long elapsed=StampMsc()-m_lastSaveMsc;
      if(elapsed>=(long)minIntervalMs || elapsed<0)
         Save();
     }

   bool              Has(const string key)
     {
      if(!m_enabled)
         return false;
      return (IndexOf(CleanKey(key))>=0);
     }

   void              SetString(const string key,const string v)
     {
      if(!m_enabled)
         return;
      if(Put(key,v))
         m_dirty=true;
     }
   string            GetString(const string key,const string def)
     {
      if(!m_enabled)
         return def;
      int i=IndexOf(CleanKey(key));
      if(i<0)
         return def;
      return m_vals[i];
     }

   void              SetDouble(const string key,const double v)  { SetString(key,DoubleToString(v,8)); }
   double            GetDouble(const string key,const double def)
     {
      if(!m_enabled)
         return def;
      int i=IndexOf(CleanKey(key));
      if(i<0 || StringLen(m_vals[i])==0)
         return def;
      return StringToDouble(m_vals[i]);
     }

   void              SetLong(const string key,const long v)      { SetString(key,IntegerToString(v)); }
   long              GetLong(const string key,const long def)
     {
      if(!m_enabled)
         return def;
      int i=IndexOf(CleanKey(key));
      if(i<0 || StringLen(m_vals[i])==0)
         return def;
      return StringToInteger(m_vals[i]);
     }

   void              Remove(const string key)
     {
      if(!m_enabled)
         return;
      int i=IndexOf(CleanKey(key));
      if(i<0)
         return;
      RemoveAt(i);
      m_dirty=true;
     }

   //--- remove every key starting with prefix (e.g. "pos.123456." when a position is closed)
   void              RemovePrefix(const string prefix)
     {
      if(!m_enabled)
         return;
      if(StringLen(prefix)==0)
        {
         LogMsg(FTF_LOG_WARN,"RemovePrefix called with an empty prefix - ignored (would erase the whole state)");
         return;
        }
      int k=0;
      for(int i=0;i<m_count;i++)
        {
         if(StringFind(m_keys[i],prefix)==0)
            continue;
         if(k!=i)
           {
            m_keys[k]=m_keys[i];
            m_vals[k]=m_vals[i];
           }
         k++;
        }
      if(k==m_count)
         return;
      LogMsg(FTF_LOG_DEBUG,"removed "+IntegerToString(m_count-k)+" key(s) with prefix '"+prefix+"'");
      m_count=k;
      ArrayResize(m_keys,m_count,64);
      ArrayResize(m_vals,m_count,64);
      m_dirty=true;
     }

   //--- every key starting with prefix ("" = all keys); returns the count
   int               KeysWithPrefix(const string prefix,string &keys[])
     {
      ArrayResize(keys,0);
      if(!m_enabled)
         return 0;
      int n=0;
      bool all=(StringLen(prefix)==0);
      for(int i=0;i<m_count;i++)
        {
         if(!all && StringFind(m_keys[i],prefix)!=0)
            continue;
         ArrayResize(keys,n+1,64);
         keys[n]=m_keys[i];
         n++;
        }
      return n;
     }
  };

#endif // FTF_STATE_STORE_MQH
