//+------------------------------------------------------------------+
//|                                                        Utils.mqh |
//|  Platform-neutral helper functions (docs/09 section 6).          |
//|  No platform API here: only Math*, String*, Time* basics.        |
//+------------------------------------------------------------------+
#ifndef FTF_UTILS_MQH
#define FTF_UTILS_MQH

#include <FranckyTriFlux\Core\Types.mqh>

//+------------------------------------------------------------------+
//| numbers                                                          |
//+------------------------------------------------------------------+
double FTF_Clamp(const double v,const double lo,const double hi)
  {
   if(v<lo)
      return lo;
   if(v>hi)
      return hi;
   return v;
  }

//--- median of the first n values (src is not modified). n<=0 -> 0
double FTF_Median(const double &src[],const int n)
  {
   int cnt=n;
   if(cnt>ArraySize(src))
      cnt=ArraySize(src);
   if(cnt<=0)
      return 0.0;
   double tmp[];
   ArrayResize(tmp,cnt);
   for(int i=0;i<cnt;i++)
      tmp[i]=src[i];
   //--- insertion sort (n is small: <= a few hundred)
   for(int i=1;i<cnt;i++)
     {
      double key=tmp[i];
      int j=i-1;
      while(j>=0 && tmp[j]>key)
        {
         tmp[j+1]=tmp[j];
         j--;
        }
      tmp[j+1]=key;
     }
   if((cnt%2)==1)
      return tmp[cnt/2];
   return (tmp[cnt/2-1]+tmp[cnt/2])*0.5;
  }

string FTF_D(const double v,const int digits)
  {
   return DoubleToString(v,digits);
  }

//--- number of decimals of a step such as 0.01 -> 2
int FTF_StepDigits(const double step)
  {
   int d=0;
   double s=step;
   while(d<8 && MathAbs(s-MathRound(s))>1e-9)
     {
      s*=10.0;
      d++;
     }
   return d;
  }

double FTF_NormalizePrice(const double price,const double tickSize,const int digits)
  {
   double p=price;
   if(tickSize>0.0)
      p=MathRound(price/tickSize)*tickSize;
   return NormalizeDouble(p,digits);
  }

//--- floor to lot step, cap at lotMax, 0 if below lotMin
double FTF_NormalizeLotsDown(const double lots,const double step,const double lotMin,const double lotMax)
  {
   double st=(step>0.0 ? step : 0.01);
   double v=MathFloor(lots/st+1e-9)*st;
   if(lotMax>0.0 && v>lotMax)
      v=MathFloor(lotMax/st+1e-9)*st;
   if(v<lotMin-1e-12 || v<=0.0)
      return 0.0;
   return NormalizeDouble(v,FTF_StepDigits(st));
  }

//+------------------------------------------------------------------+
//| strings                                                          |
//+------------------------------------------------------------------+
string FTF_Upper(const string s)
  {
   string out="";
   int n=StringLen(s);
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(s,i);
      if(c>='a' && c<='z')
         c=(ushort)(c-32);
      out+=ShortToString(c);
     }
   return out;
  }

bool FTF_IsSpace(const ushort c)
  {
   return (c==' ' || c=='\t' || c=='\r' || c=='\n');
  }

string FTF_Trim(const string s)
  {
   int n=StringLen(s);
   int a=0;
   while(a<n && FTF_IsSpace(StringGetCharacter(s,a)))
      a++;
   int b=n-1;
   while(b>=a && FTF_IsSpace(StringGetCharacter(s,b)))
      b--;
   if(b<a)
      return "";
   return StringSubstr(s,a,b-a+1);
  }

//--- split a comma separated list, trimmed, empty items skipped
int FTF_SplitList(const string csv,string &out[])
  {
   ArrayResize(out,0);
   string parts[];
   int n=StringSplit(csv,StringGetCharacter(",",0),parts);
   int k=0;
   for(int i=0;i<n;i++)
     {
      string p=FTF_Trim(parts[i]);
      if(StringLen(p)==0)
         continue;
      ArrayResize(out,k+1);
      out[k]=p;
      k++;
     }
   return k;
  }

bool FTF_ListContains(const string csv,const string item)
  {
   string items[];
   int n=FTF_SplitList(csv,items);
   string u=FTF_Upper(FTF_Trim(item));
   for(int i=0;i<n;i++)
      if(FTF_Upper(items[i])==u)
         return true;
   return false;
  }

//--- keeps [A-Za-z0-9_-.] for file names
string FTF_SafeFilePart(const string s)
  {
   string out="";
   int n=StringLen(s);
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(s,i);
      bool ok=((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='_' || c=='-' || c=='.');
      out+=(ok ? ShortToString(c) : "_");
     }
   return out;
  }

//+------------------------------------------------------------------+
//| time                                                             |
//+------------------------------------------------------------------+
//--- "HH:MM" -> minutes since midnight, -1 if invalid or empty
int FTF_ParseHHMM(const string s)
  {
   string t=FTF_Trim(s);
   if(StringLen(t)==0)
      return -1;
   string parts[];
   int n=StringSplit(t,StringGetCharacter(":",0),parts);
   if(n<2)
      return -1;
   int hh=(int)StringToInteger(FTF_Trim(parts[0]));
   int mm=(int)StringToInteger(FTF_Trim(parts[1]));
   if(hh<0 || hh>24 || mm<0 || mm>59)
      return -1;
   if(hh==24)
      return 1440;
   return hh*60+mm;
  }

int FTF_MinuteOfDay(const datetime t)
  {
   long v=(long)t;
   return (int)((v%86400)/60);
  }

//--- 0 = Sunday ... 6 = Saturday (1970-01-01 was a Thursday)
int FTF_DayOfWeek(const datetime t)
  {
   long days=((long)t)/86400;
   return (int)((days+4)%7);
  }

datetime FTF_DayStart(const datetime t)
  {
   long v=(long)t;
   return (datetime)(v-(v%86400));
  }

//--- minute within [start,end) with wrap past midnight; start==end means the whole day
bool FTF_InMinuteWindow(const int minute,const int startMin,const int endMin)
  {
   if(startMin<0 || endMin<0)
      return false;
   if(startMin==endMin)
      return true;
   if(startMin<endMin)
      return (minute>=startMin && minute<endMin);
   return (minute>=startMin || minute<endMin);
  }

//--- n-th Sunday (n>=1) of a month, returns day of month
int FTF_NthSunday(const int year,const int month,const int n)
  {
   MqlDateTime dt;
   dt.year=year; dt.mon=month; dt.day=1; dt.hour=0; dt.min=0; dt.sec=0;
   dt.day_of_week=0; dt.day_of_year=0;
   datetime first=StructToTime(dt);
   int dow=FTF_DayOfWeek(first);
   int firstSunday=1+((7-dow)%7);
   return firstSunday+7*(n-1);
  }

//--- US daylight saving time (2nd Sunday of March 07:00 UTC .. 1st Sunday of November 06:00 UTC)
bool FTF_IsUsDst(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t,dt);
   MqlDateTime a;
   a.year=dt.year; a.mon=3; a.day=FTF_NthSunday(dt.year,3,2); a.hour=7; a.min=0; a.sec=0;
   a.day_of_week=0; a.day_of_year=0;
   MqlDateTime b;
   b.year=dt.year; b.mon=11; b.day=FTF_NthSunday(dt.year,11,1); b.hour=6; b.min=0; b.sec=0;
   b.day_of_week=0; b.day_of_year=0;
   datetime start=StructToTime(a);
   datetime end=StructToTime(b);
   return (t>=start && t<end);
  }

string FTF_TimeStr(const datetime t)
  {
   return TimeToString(t,TIME_DATE|TIME_SECONDS);
  }

string FTF_TimeMscStr(const long msc)
  {
   if(msc<=0)
      return "";
   datetime t=(datetime)(msc/1000);
   int ms=(int)(msc%1000);
   return TimeToString(t,TIME_DATE|TIME_SECONDS)+"."+StringFormat("%03d",ms);
  }

string FTF_TfStr(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default:         break;
     }
   return "TF"+IntegerToString((int)tf);
  }

//--- seconds of one bar of a timeframe
int FTF_TfSeconds(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return 60;
      case PERIOD_M5:  return 300;
      case PERIOD_M15: return 900;
      case PERIOD_M30: return 1800;
      case PERIOD_H1:  return 3600;
      case PERIOD_H4:  return 14400;
      case PERIOD_D1:  return 86400;
      default:         break;
     }
   return 60;
  }

//+------------------------------------------------------------------+
//| enum -> text                                                     |
//+------------------------------------------------------------------+
string FTF_DirStr(const int dir)
  {
   if(dir==FTF_DIR_BUY)
      return "BUY";
   if(dir==FTF_DIR_SELL)
      return "SELL";
   return "NONE";
  }

string FTF_EngineCode(const int e)
  {
   switch(e)
     {
      case FTF_ENG_MOMENTUM: return "MOM";
      case FTF_ENG_FVG:      return "FVG";
      case FTF_ENG_RANGE:    return "RNG";
      default:               break;
     }
   return "ALL";
  }

string FTF_EngineName(const int e)
  {
   switch(e)
     {
      case FTF_ENG_MOMENTUM: return "Momentum";
      case FTF_ENG_FVG:      return "FVG";
      case FTF_ENG_RANGE:    return "Range";
      default:               break;
     }
   return "TOTAL";
  }

string FTF_ModeStr(const int mode)
  {
   if(mode==FTF_MODE_SPEED)
      return "SPEED";
   if(mode==FTF_MODE_ULTRA)
      return "ULTRA";
   return "AGGRESSIVE";
  }

string FTF_H1StateStr(const int s)
  {
   if(s==FTF_H1S_BULLISH)
      return "BULLISH";
   if(s==FTF_H1S_BEARISH)
      return "BEARISH";
   return "NEUTRAL";
  }

string FTF_ImpactStr(const int impact)
  {
   if(impact>=3)
      return "HIGH";
   if(impact==2)
      return "MEDIUM";
   if(impact==1)
      return "LOW";
   return "NONE";
  }

//--- "HIGH"/"H"/"3" ... -> 3 ; unknown -> 0
int FTF_ParseImpact(const string s)
  {
   string u=FTF_Upper(FTF_Trim(s));
   if(u=="HIGH" || u=="H" || u=="3" || u=="RED")
      return 3;
   if(u=="MEDIUM" || u=="MED" || u=="M" || u=="2" || u=="ORANGE" || u=="MODERATE")
      return 2;
   if(u=="LOW" || u=="L" || u=="1" || u=="YELLOW")
      return 1;
   return 0;
  }

string FTF_ReasonStr(const int code)
  {
   switch(code)
     {
      case FTF_OK:                 return "OK";
      case FTF_REJ_WARMUP:         return "WARMUP";
      case FTF_REJ_TRADING_OFF:    return "TRADING_OFF";
      case FTF_REJ_TERMINAL:       return "TERMINAL";
      case FTF_REJ_SYMBOL:         return "SYMBOL";
      case FTF_REJ_STALE_TICK:     return "STALE_TICK";
      case FTF_REJ_DD_PAUSE:       return "DD_PAUSE";
      case FTF_REJ_CONSEC_LOSS:    return "CONSEC_LOSS";
      case FTF_REJ_NEWS:           return "NEWS";
      case FTF_REJ_SESSION:        return "SESSION";
      case FTF_REJ_ROLLOVER:       return "ROLLOVER";
      case FTF_REJ_SPREAD:         return "SPREAD";
      case FTF_REJ_VOLATILITY:     return "VOLATILITY";
      case FTF_REJ_EXEC_QUALITY:   return "EXEC_QUALITY";
      case FTF_REJ_ERROR_COOLDOWN: return "ERROR_COOLDOWN";
      case FTF_REJ_CONFLICT:       return "CONFLICT";
      case FTF_REJ_H1_STRICT:      return "H1_STRICT";
      case FTF_REJ_COOLDOWN:       return "ENGINE_COOLDOWN";
      case FTF_REJ_SPACING:        return "ENTRY_SPACING";
      case FTF_REJ_MAX_POS_ENGINE: return "MAX_POS_ENGINE";
      case FTF_REJ_MAX_POS_SYMBOL: return "MAX_POS_SYMBOL";
      case FTF_REJ_HEDGE:          return "HEDGE_OFF";
      case FTF_REJ_SAME_DIR:       return "SAME_DIR_IGNORE";
      case FTF_REJ_DUPLICATE:      return "DUPLICATE";
      case FTF_REJ_MULTI_INSTANCE: return "MULTI_INSTANCE";
      case FTF_REJ_SIGNAL_EXPIRED: return "SIGNAL_EXPIRED";
      case FTF_REJ_SIGNAL_INVALID: return "SIGNAL_INVALID";
      case FTF_REJ_PRICE_DRIFT:    return "PRICE_DRIFT";
      case FTF_REJ_SLTP_INVALID:   return "SLTP_INVALID";
      case FTF_REJ_SLTP_RATIO:     return "SLTP_RATIO";
      case FTF_REJ_STOPS_LEVEL:    return "STOPS_LEVEL";
      case FTF_REJ_RISK:           return "RISK";
      case FTF_REJ_LOT:            return "LOT";
      case FTF_REJ_MARGIN:         return "MARGIN";
      case FTF_REJ_EXPOSURE:       return "EXPOSURE";
      case FTF_REJ_AGGREGATE:      return "AGGREGATE_EXPOSURE";
      case FTF_REJ_NETTING:        return "NETTING_ACCOUNT";
      case FTF_REJ_ORDER_FAILED:   return "ORDER_FAILED";
      case FTF_REJ_CONFIRM_PENDING:return "CONFIRM_PENDING";
      default:                     break;
     }
   return "REASON_"+IntegerToString(code);
  }

string FTF_ExitStr(const int code)
  {
   switch(code)
     {
      case FTF_EXIT_NONE:         return "NONE";
      case FTF_EXIT_TP:           return "TP";
      case FTF_EXIT_SL:           return "SL";
      case FTF_EXIT_BE:           return "BREAKEVEN_SL";
      case FTF_EXIT_TRAIL:        return "TRAILING_SL";
      case FTF_EXIT_TIME_STOP:    return "TIME_STOP";
      case FTF_EXIT_HARD_MAX:     return "HARD_MAX_TIME";
      case FTF_EXIT_MOM_LOSS:     return "MOMENTUM_LOSS";
      case FTF_EXIT_MOM_INVALID:  return "MOMENTUM_INVALIDATION";
      case FTF_EXIT_FVG_INVALID:  return "FVG_INVALIDATED";
      case FTF_EXIT_RANGE_BREAK:  return "RANGE_BREAKOUT";
      case FTF_EXIT_MANUAL:       return "MANUAL_OR_OTHER";
      case FTF_EXIT_STOP_OUT:     return "STOP_OUT";
      case FTF_EXIT_OFFLINE:      return "CLOSED_WHILE_OFFLINE";
      case FTF_EXIT_UNKNOWN:      return "UNKNOWN";
      default:                    break;
     }
   return "EXIT_"+IntegerToString(code);
  }

//--- supported V1 market class from a broker symbol name ("" if unsupported)
string FTF_SymbolClass(const string symbol)
  {
   string u=FTF_Upper(symbol);
   if(StringFind(u,"EURUSD")>=0)
      return "EURUSD";
   if(StringFind(u,"XAUUSD")>=0 || StringFind(u,"GOLD")>=0)
      return "XAUUSD";
   if(StringFind(u,"BTCUSD")>=0 || StringFind(u,"XBTUSD")>=0 || StringFind(u,"BITCOIN")>=0)
      return "BTCUSD";
   return "";
  }

#endif // FTF_UTILS_MQH
