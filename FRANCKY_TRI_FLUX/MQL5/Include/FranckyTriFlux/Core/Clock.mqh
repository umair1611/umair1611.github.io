//+------------------------------------------------------------------+
//|                                                        Clock.mqh |
//|  CClock - broker server time <-> UTC conversion (docs/09 7.6).   |
//|  offset = server time - UTC (seconds).                           |
//|   * AUTO  (live only): CPlatform::AutoGmtOffset(), cached and    |
//|     re-queried at most every FTF_CLOCK_REQUERY_SEC server secs.  |
//|   * MANUAL (and always in the Strategy Tester, where TimeGMT()   |
//|     == TimeCurrent()): GmtOffsetHours x 3600 (+3600 during US    |
//|     DST when GmtUseUsDst = true, New-York-close brokers).        |
//|  Used by the session / news / rollover filters (spec B.1-B.3).   |
//|  Shared Core: identical in the MQL5 and MQL4 trees.              |
//+------------------------------------------------------------------+
#ifndef FTF_CLOCK_MQH
#define FTF_CLOCK_MQH

#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Config.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>
#include <FranckyTriFlux\Platform\Platform.mqh>

#define FTF_CLOCK_REQUERY_SEC   600       // TUNABLE (not an input yet) - AUTO offset re-query interval (server seconds)
#define FTF_CLOCK_ROUND_SEC     1800      // TUNABLE (not an input yet) - AUTO offset rounded to 30 min (absorbs the last-tick lag of TimeCurrent on MT4)
#define FTF_CLOCK_NOW_TOL_SEC   120       // TUNABLE (not an input yet) - conversions within +/- this of "server now" update the current offset (change log)
#define FTF_CLOCK_MIN_OFFSET    (-43200)  // -12 h : AUTO values outside [-12 h, +14 h] are rejected (stale server time, weekend)
#define FTF_CLOCK_MAX_OFFSET    50400     // +14 h
#define FTF_CLOCK_SRC           "CLK"     // log source tag

class CClock
  {
private:
   CConfig          *m_cfg;
   CPlatform        *m_pf;
   CLogger          *m_log;
   bool              m_ready;          // configuration pointer valid
   bool              m_isTester;       // cached pf.IsTester(): AUTO is impossible in the tester (docs/05 TZ)
   bool              m_wantAuto;       // GmtMode==AUTO and live and platform available
   //--- AUTO cache
   bool              m_autoQueried;    // at least one platform query done
   bool              m_autoValid;      // m_autoOffset holds a usable value
   long              m_autoOffset;     // last accepted AUTO offset (s, rounded)
   long              m_autoRaw;        // last raw platform value (s)
   datetime          m_autoQueryTime;  // server time of the last query
   int               m_autoFails;      // consecutive failed / rejected queries
   //--- US DST cache (DST status is constant inside one UTC hour: switches at 07:00 / 06:00 UTC)
   long              m_dstHourKey;
   bool              m_dstVal;
   //--- current offset tracking (INFO log when it changes)
   bool              m_haveCur;
   long              m_curOffset;
   bool              m_curAuto;

   //--- logging helpers (no-op without a logger)
   bool              HasLog(void) { return (CheckPointer(m_log)!=POINTER_INVALID); }
   bool              HasPf(void)  { return (CheckPointer(m_pf)!=POINTER_INVALID); }
   void              LogError(const string msg) { if(HasLog()) m_log.Error(FTF_CLOCK_SRC,msg); }
   void              LogWarn(const string msg)  { if(HasLog()) m_log.Warn(FTF_CLOCK_SRC,msg); }
   void              LogInfo(const string msg)  { if(HasLog()) m_log.Info(FTF_CLOCK_SRC,msg); }
   void              LogDebug(const string msg) { if(HasLog()) m_log.Debug(FTF_CLOCK_SRC,msg); }

   void              ResetCache(void)
     {
      m_autoQueried=false;
      m_autoValid=false;
      m_autoOffset=0;
      m_autoRaw=0;
      m_autoQueryTime=0;
      m_autoFails=0;
      m_dstHourKey=-1;
      m_dstVal=false;
      m_haveCur=false;
      m_curOffset=0;
      m_curAuto=false;
     }

public:
                     CClock(void)
     {
      m_cfg=NULL;
      m_pf=NULL;
      m_log=NULL;
      m_ready=false;
      m_isTester=false;
      m_wantAuto=false;
      ResetCache();
     }

   //--- extra: "+3", "-5", "+5:30" for an offset in seconds
   string            OffsetText(const long secs)
     {
      long a=(secs<0 ? -secs : secs);
      long h=a/3600;
      long m=(a%3600)/60;
      string s=(secs<0 ? "-" : "+");
      s+=IntegerToString(h);
      if(m!=0)
         s+=":"+(m<10 ? "0" : "")+IntegerToString(m);
      return s;
     }

private:
   //--- manual winter base (s): GmtOffsetHours x 3600
   long              ManualBaseSec(void)
     {
      if(!m_ready)
         return 0;
      return (long)m_cfg.GmtOffsetHours*3600;
     }

   //--- "GMT+2+DST" / "GMT+2"
   string            ManualText(void)
     {
      bool dst=(m_ready && m_cfg.GmtUseUsDst);
      return "GMT"+OffsetText(ManualBaseSec())+(dst ? "+DST" : "");
     }

   //--- US DST test with a one-hour cache (FTF_IsUsDst is constant inside one UTC hour)
   bool              IsUsDstCached(const datetime utc)
     {
      long hourKey=((long)utc)/3600;
      if(hourKey!=m_dstHourKey)
        {
         m_dstHourKey=hourKey;
         m_dstVal=FTF_IsUsDst(utc);
        }
      return m_dstVal;
     }

   //--- nearest multiple of FTF_CLOCK_ROUND_SEC: on MT4 TimeCurrent() is the time of the LAST tick,
   //--- so server - GMT is slightly short when the market is quiet; broker offsets are whole/half hours
   long              RoundOffset(const long raw)
     {
      double q=MathRound((double)raw/(double)FTF_CLOCK_ROUND_SEC);
      return (long)q*(long)FTF_CLOCK_ROUND_SEC;
     }

   //--- one platform query; the last good AUTO value is kept when a later query fails
   void              QueryAuto(const datetime nowSrv)
     {
      m_autoQueried=true;
      m_autoQueryTime=nowSrv;
      long raw=0;
      if(!m_pf.AutoGmtOffset(raw))
        {
         m_autoFails++;
         string fb=(m_autoValid ? "keeping last AUTO value GMT"+OffsetText(m_autoOffset) : "MANUAL fallback "+ManualText());
         if(m_autoFails==1)
            LogWarn("AUTO GMT offset unavailable from "+m_pf.Name()+" -> "+fb+", retry in "+
                    IntegerToString(FTF_CLOCK_REQUERY_SEC)+" s");
         else
            LogDebug("AUTO GMT offset still unavailable ("+IntegerToString(m_autoFails)+" queries) -> "+fb);
         return;
        }
      long rounded=RoundOffset(raw);
      if(rounded<FTF_CLOCK_MIN_OFFSET || rounded>FTF_CLOCK_MAX_OFFSET)
        {
         m_autoFails++;
         string msg="AUTO GMT offset "+IntegerToString(raw)+" s out of range [-12 h,+14 h] (stale server time / market closed?) -> ignored, "+
                    (m_autoValid ? "keeping GMT"+OffsetText(m_autoOffset) : "MANUAL fallback "+ManualText());
         if(m_autoFails==1)
            LogWarn(msg);
         else
            LogDebug(msg);
         return;
        }
      if(m_autoFails>0)
         LogInfo("AUTO GMT offset available again after "+IntegerToString(m_autoFails)+" failed queries");
      m_autoFails=0;
      long diff=raw-rounded;
      if(diff<0)
         diff=-diff;
      if(diff>300)
         LogDebug("AUTO raw offset "+IntegerToString(raw)+" s rounded to "+IntegerToString(rounded)+
                  " s (server time lags the clock by the last-tick age)");
      if(!m_autoValid || rounded!=m_autoOffset)
         LogDebug("AUTO GMT offset accepted: GMT"+OffsetText(rounded)+" (raw "+IntegerToString(raw)+" s)");
      m_autoRaw=raw;
      m_autoOffset=rounded;
      m_autoValid=true;
     }

   //--- AUTO offset if usable (live, AUTO mode, platform answered at least once)
   bool              AutoOffset(long &secs)
     {
      secs=0;
      if(!m_wantAuto || !HasPf())
         return false;
      datetime nowSrv=m_pf.ServerTime();
      long age=(long)nowSrv-(long)m_autoQueryTime;
      if(age<0)
         age=-age;
      //--- re-query at most every FTF_CLOCK_REQUERY_SEC of server time (cheap per-tick calls, DST switch caught)
      if(!m_autoQueried || age>=FTF_CLOCK_REQUERY_SEC)
         QueryAuto(nowSrv);
      if(!m_autoValid)
         return false;
      secs=m_autoOffset;
      return true;
     }

   //--- records the offset valid "now" and logs every change (INFO). Conversions of other times
   //--- (news events, history) are ignored so a DST boundary cannot make the log flip-flop.
   void              TrackCurrent(const datetime serverTime,const long off,const bool isAuto)
     {
      if(!HasPf())
         return;
      long d=(long)serverTime-(long)m_pf.ServerTime();
      if(d<0)
         d=-d;
      if(d>FTF_CLOCK_NOW_TOL_SEC)
         return;
      if(m_haveCur && off==m_curOffset && isAuto==m_curAuto)
         return;
      string was="";
      if(m_haveCur)
         was=" (was GMT"+OffsetText(m_curOffset)+(m_curAuto ? " AUTO" : " MANUAL")+")";
      string src=(isAuto ? " [AUTO, raw "+IntegerToString(m_autoRaw)+" s]" : " [MANUAL "+ManualText()+"]");
      m_haveCur=true;
      m_curOffset=off;
      m_curAuto=isAuto;
      LogInfo("broker time offset now GMT"+OffsetText(off)+src+was+
              " | server "+FTF_TimeStr(serverTime)+" = UTC "+FTF_TimeStr((datetime)((long)serverTime-off)));
     }

public:
   //--- MANUAL rule: base + 1 h during US DST. DST is tested on (server - winter base), i.e. on UTC
   //--- (exact except inside the switch hour itself; the switches happen on Sunday morning).
   long              ManualOffsetSec(const datetime serverTime)
     {
      long base=ManualBaseSec();
      if(!m_ready || !m_cfg.GmtUseUsDst)
         return base;
      long approxUtc=(long)serverTime-base;
      if(approxUtc<=86400)
         return base;          // no valid time yet (before the first tick)
      return base+(IsUsDstCached((datetime)approxUtc) ? 3600 : 0);
     }

   //--- server - UTC in seconds for the given server time (docs/09 7.6)
   long              OffsetSec(const datetime serverTime)
     {
      long off=0;
      bool isAuto=AutoOffset(off);
      if(!isAuto)
         off=ManualOffsetSec(serverTime);
      TrackCurrent(serverTime,off,isAuto);
      return off;
     }

   datetime          ServerToUtc(const datetime s)
     {
      return (datetime)((long)s-OffsetSec(s));
     }

   //--- approximation (docs/09 7.6): the offset is evaluated at u + manual winter base.
   //--- Exact in MANUAL mode (the DST test then runs on u itself) and in AUTO mode (time independent).
   datetime          UtcToServer(const datetime u)
     {
      datetime probe=(datetime)((long)u+ManualBaseSec());
      return (datetime)((long)u+OffsetSec(probe));
     }

   //--- "GMT+3 (AUTO)" / "GMT+2+DST (MANUAL)" / "GMT+2 (MANUAL)" / "GMT+2+DST (MANUAL, tester)"
   string            Describe(void)
     {
      long off=0;
      if(AutoOffset(off))
         return "GMT"+OffsetText(off)+" (AUTO)";
      string s=ManualText()+" (MANUAL";
      if(m_ready && m_cfg.GmtMode==FTF_GMT_AUTO)
         s+=(m_isTester ? ", tester" : ", AUTO n/a");
      return s+")";
     }

   //--- extra: true when the offset currently comes from the platform (AUTO)
   bool              AutoActive(void)
     {
      long off=0;
      return AutoOffset(off);
     }

   //--- extra: current UTC time
   datetime          UtcNow(void)
     {
      datetime nowSrv=(HasPf() ? m_pf.ServerTime() : TimeCurrent());
      return ServerToUtc(nowSrv);
     }

   //--- docs/09 7.6
   void              Init(CConfig *cfg,CPlatform *pf,CLogger *logger)
     {
      m_cfg=cfg;
      m_pf=pf;
      m_log=logger;
      m_ready=(CheckPointer(m_cfg)!=POINTER_INVALID);
      m_isTester=(HasPf() ? m_pf.IsTester() : false);
      m_wantAuto=(m_ready && HasPf() && m_cfg.GmtMode==FTF_GMT_AUTO && !m_isTester);
      ResetCache();
      if(!m_ready)
        {
         LogError("no configuration: GMT offset forced to 0 (UTC = server time) - session/news/rollover times may be wrong");
         return;
        }
      if(!HasPf())
         LogWarn("no platform layer: AUTO GMT offset impossible, MANUAL values used");
      LogInfo("clock: mode "+(m_cfg.GmtMode==FTF_GMT_AUTO ? "AUTO" : "MANUAL")+
              " | manual base GMT"+OffsetText(ManualBaseSec())+" | US DST "+(m_cfg.GmtUseUsDst ? "ON" : "OFF")+
              " | tester "+(m_isTester ? "yes" : "no"));
      if(m_cfg.GmtMode==FTF_GMT_AUTO && m_isTester)
         LogInfo("Strategy Tester: TimeGMT()==TimeCurrent(), AUTO offset impossible -> MANUAL "+ManualText()+" used (docs/05 TZ)");
      //--- first evaluation: logs the current offset through TrackCurrent()
      datetime nowSrv=(HasPf() ? m_pf.ServerTime() : TimeCurrent());
      long off=OffsetSec(nowSrv);
      LogInfo("clock ready: "+Describe()+" | server "+FTF_TimeStr(nowSrv)+" -> UTC "+
              FTF_TimeStr((datetime)((long)nowSrv-off))+" (offset "+IntegerToString(off)+" s)");
     }
  };

#endif // FTF_CLOCK_MQH
