//+------------------------------------------------------------------+
//|                                                      ChartUI.mqh |
//|  CChartUI - dashboard panel + chart objects (entries, exits,     |
//|  FVG zones, ranges, micro-ranges, news, pauses, rejections).     |
//|  All object names start with "FTF<id>_" (docs/09 section 10).    |
//|  Disabled UI -> every method is a cheap no-op (optimization,     |
//|  non-visual tester).                                             |
//+------------------------------------------------------------------+
#ifndef FTF_CHART_UI_MQH
#define FTF_CHART_UI_MQH

#include <FranckyTriFlux\Core\Utils.mqh>
#include <FranckyTriFlux\Core\Config.mqh>
#include <FranckyTriFlux\Core\Logger.mqh>

#define FTF_UI_FONT          "Consolas"   // fixed-width font for the panel
#define FTF_UI_TEXT_FONT     "Arial"      // chart texts
#define FTF_UI_TEXT_SIZE     7            // TUNABLE (not an input yet) - chart text size
#define FTF_UI_REDRAW_US     100000       // min wall-clock interval between two ChartRedraw (us)
#define FTF_UI_MARKER_MAX    4096         // hard cap of the marker FIFO

class CChartUI
  {
private:
   CConfig          *m_cfg;
   CLogger          *m_log;
   bool              m_enabled;
   string            m_prefix;
   //--- panel
   string            m_rowText[FTF_PANEL_ROWS];
   color             m_rowColor[FTF_PANEL_ROWS];
   string            m_drawnText[FTF_PANEL_ROWS];
   color             m_drawnColor[FTF_PANEL_ROWS];
   bool              m_rowCreated[FTF_PANEL_ROWS];
   int               m_panelW;
   int               m_panelH;
   int               m_drawnRows;
   bool              m_bgCreated;
   //--- marker FIFO (entries, exits, rejected, micro-ranges...)
   string            m_markers[];
   int               m_mHead;
   int               m_mCount;
   int               m_rejSeq;
   ulong             m_lastRedrawUs;
   int               m_createErrors;

   string            Name(const string id) { return m_prefix+id; }

   bool              Exists(const string fullName) { return (ObjectFind(0,fullName)>=0); }

   void              CreateFailed(const string fullName)
     {
      m_createErrors++;
      if(CheckPointer(m_log)!=POINTER_INVALID)
         m_log.Throttled(FTF_LOG_WARN,"ui.create",10000,"UI","ObjectCreate failed for "+fullName+" (error "+
                         IntegerToString(GetLastError())+", "+IntegerToString(m_createErrors)+" failures)");
     }

   //--- common properties of every non-panel object
   void              Decorate(const string fullName,const color clr,const string tip)
     {
      ObjectSetInteger(0,fullName,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,fullName,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,fullName,OBJPROP_SELECTED,false);
      ObjectSetInteger(0,fullName,OBJPROP_HIDDEN,true);
      if(StringLen(tip)>0)
         ObjectSetString(0,fullName,OBJPROP_TOOLTIP,tip);
     }

   //--- remember a marker; delete the oldest when the budget is exceeded
   void              PushMarker(const string fullName)
     {
      int cap=ArraySize(m_markers);
      if(cap<=0)
         return;
      int pos=(m_mHead+m_mCount)%cap;
      if(m_mCount==cap)
        {
         //--- ring full: overwrite (and delete) the oldest
         ObjectDelete(0,m_markers[m_mHead]);
         m_markers[m_mHead]=fullName;
         m_mHead=(m_mHead+1)%cap;
         return;
        }
      m_markers[pos]=fullName;
      m_mCount++;
      int limit=(m_cfg.MaxChartObjects>0 ? m_cfg.MaxChartObjects : 600);
      while(m_mCount>limit)
        {
         ObjectDelete(0,m_markers[m_mHead]);
         m_markers[m_mHead]="";
         m_mHead=(m_mHead+1)%cap;
         m_mCount--;
        }
     }

   //--- panel geometry helpers
   int               LineHeight(void) { return m_cfg.PanelFontSize*2+3; }
   bool              IsRight(void) { return (m_cfg.PanelCorner==CORNER_RIGHT_UPPER || m_cfg.PanelCorner==CORNER_RIGHT_LOWER); }
   bool              IsLower(void) { return (m_cfg.PanelCorner==CORNER_LEFT_LOWER || m_cfg.PanelCorner==CORNER_RIGHT_LOWER); }
   color             PanelBg(void) { return (m_cfg.PanelDark ? C'20,24,32' : clrWhiteSmoke); }
   color             PanelBorder(void) { return (m_cfg.PanelDark ? C'70,80,100' : clrSilver); }

   int               RowX(void)
     {
      return (IsRight() ? m_cfg.PanelX+m_panelW-6 : m_cfg.PanelX+6);
     }
   int               RowY(const int row)
     {
      int lh=LineHeight();
      return (IsLower() ? m_cfg.PanelY+m_panelH-4-row*lh : m_cfg.PanelY+4+row*lh);
     }

   void              PlaceBackground(void)
     {
      string n=Name("P_BG");
      if(!m_bgCreated || !Exists(n))
        {
         if(!ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0))
           {
            CreateFailed(n);
            return;
           }
         m_bgCreated=true;
         ObjectSetInteger(0,n,OBJPROP_CORNER,m_cfg.PanelCorner);
         ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
         ObjectSetInteger(0,n,OBJPROP_BACK,false);
         ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
        }
      ObjectSetInteger(0,n,OBJPROP_BGCOLOR,PanelBg());
      ObjectSetInteger(0,n,OBJPROP_COLOR,PanelBorder());
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,(IsRight() ? m_cfg.PanelX+m_panelW : m_cfg.PanelX));
      ObjectSetInteger(0,n,OBJPROP_YDISTANCE,(IsLower() ? m_cfg.PanelY+m_panelH : m_cfg.PanelY));
      ObjectSetInteger(0,n,OBJPROP_XSIZE,m_panelW);
      ObjectSetInteger(0,n,OBJPROP_YSIZE,m_panelH);
     }

   void              PlaceRow(const int row)
     {
      string n=Name("P_"+IntegerToString(row));
      if(!m_rowCreated[row] || !Exists(n))
        {
         if(!ObjectCreate(0,n,OBJ_LABEL,0,0,0))
           {
            CreateFailed(n);
            return;
           }
         m_rowCreated[row]=true;
         ObjectSetInteger(0,n,OBJPROP_CORNER,m_cfg.PanelCorner);
         ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
         ObjectSetString(0,n,OBJPROP_FONT,FTF_UI_FONT);
         ObjectSetInteger(0,n,OBJPROP_FONTSIZE,m_cfg.PanelFontSize);
         ObjectSetInteger(0,n,OBJPROP_BACK,false);
         ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
         m_drawnText[row]="#init#";   // force the first text update
        }
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,RowX());
      ObjectSetInteger(0,n,OBJPROP_YDISTANCE,RowY(row));
     }

public:
                     CChartUI(void)
     {
      m_cfg=NULL;
      m_log=NULL;
      m_enabled=false;
      m_prefix="FTF1_";
      for(int i=0;i<FTF_PANEL_ROWS;i++)
        {
         m_rowText[i]="";
         m_rowColor[i]=clrWhite;
         m_drawnText[i]="";
         m_drawnColor[i]=clrNONE;
         m_rowCreated[i]=false;
        }
      m_panelW=0;
      m_panelH=0;
      m_drawnRows=0;
      m_bgCreated=false;
      m_mHead=0;
      m_mCount=0;
      m_rejSeq=0;
      m_lastRedrawUs=0;
      m_createErrors=0;
     }

   bool              Init(CConfig *cfg,CLogger *logger,const int instanceId,const bool enabled)
     {
      m_cfg=cfg;
      m_log=logger;
      m_prefix="FTF"+IntegerToString(instanceId)+"_";
      m_enabled=(enabled && CheckPointer(m_cfg)!=POINTER_INVALID);
      int cap=FTF_UI_MARKER_MAX;
      if(CheckPointer(m_cfg)!=POINTER_INVALID && m_cfg.MaxChartObjects+16<cap)
         cap=m_cfg.MaxChartObjects+16;
      if(cap<16)
         cap=16;
      ArrayResize(m_markers,cap);
      for(int i=0;i<cap;i++)
         m_markers[i]="";
      m_mHead=0;
      m_mCount=0;
      if(CheckPointer(m_log)!=POINTER_INVALID)
         m_log.Info("UI","chart display "+(m_enabled ? "ON" : "OFF")+" | prefix "+m_prefix+
                    (m_enabled ? " | marker budget "+IntegerToString(m_cfg.MaxChartObjects) : ""));
      return true;
     }

   //--- delete every object of this instance (or only the panel when deleteObjects=false)
   void              Deinit(const bool deleteObjects)
     {
      if(!m_enabled)
         return;
      int total=ObjectsTotal(0,-1,-1);
      for(int i=total-1;i>=0;i--)
        {
         string n=ObjectName(0,i,-1,-1);
         if(StringFind(n,m_prefix)!=0)
            continue;
         bool isPanel=(StringFind(n,m_prefix+"P_")==0);
         if(deleteObjects || isPanel)
            ObjectDelete(0,n);
        }
      ChartRedraw(0);
     }

   bool              Enabled(void) { return m_enabled; }
   string            Prefix(void)  { return m_prefix; }

   //--- panel ----------------------------------------------------------
   void              PanelLine(const int row,const string text,const color clr)
     {
      if(!m_enabled || row<0 || row>=FTF_PANEL_ROWS)
         return;
      m_rowText[row]=text;
      m_rowColor[row]=clr;
     }

   void              PanelRender(void)
     {
      if(!m_enabled || !m_cfg.ShowPanel)
         return;
      //--- size: highest non-empty row, longest text (fixed-width font)
      int rows=0;
      int maxLen=20;
      for(int i=0;i<FTF_PANEL_ROWS;i++)
         if(StringLen(m_rowText[i])>0)
           {
            rows=i+1;
            if(StringLen(m_rowText[i])>maxLen)
               maxLen=StringLen(m_rowText[i]);
           }
      if(rows==0)
         return;
      int needW=(int)MathCeil(maxLen*m_cfg.PanelFontSize*0.80)+14;
      int needH=rows*LineHeight()+8;
      bool geometry=(needW>m_panelW || needH!=m_panelH || !m_bgCreated);
      if(needW>m_panelW)
         m_panelW=needW;   // grows only: avoids flicker
      m_panelH=needH;
      if(geometry)
         PlaceBackground();
      for(int i=0;i<FTF_PANEL_ROWS;i++)
        {
         if(i>=rows)
           {
            if(m_rowCreated[i])
              {
               ObjectDelete(0,Name("P_"+IntegerToString(i)));
               m_rowCreated[i]=false;
              }
            continue;
           }
         if(geometry || !m_rowCreated[i])
            PlaceRow(i);
         if(!m_rowCreated[i])
            continue;
         string n=Name("P_"+IntegerToString(i));
         string t=(StringLen(m_rowText[i])>0 ? m_rowText[i] : " ");
         if(t!=m_drawnText[i])
           {
            ObjectSetString(0,n,OBJPROP_TEXT,t);
            m_drawnText[i]=t;
           }
         if(m_rowColor[i]!=m_drawnColor[i])
           {
            ObjectSetInteger(0,n,OBJPROP_COLOR,m_rowColor[i]);
            m_drawnColor[i]=m_rowColor[i];
           }
        }
      m_drawnRows=rows;
      Redraw();
     }

   //--- trades ---------------------------------------------------------
   void              DrawEntry(const ulong ticket,const int engine,const int dir,const datetime t,const double price,const string text)
     {
      if(!m_enabled || !m_cfg.DrawTrades)
         return;
      string id=IntegerToString((long)ticket);
      string a=Name("E_"+id);
      if(!Exists(a))
        {
         if(!ObjectCreate(0,a,OBJ_ARROW,0,t,price))
           {
            CreateFailed(a);
            return;
           }
         PushMarker(a);
        }
      ObjectSetInteger(0,a,OBJPROP_ARROWCODE,(dir==FTF_DIR_BUY ? 233 : 234));
      ObjectSetInteger(0,a,OBJPROP_ANCHOR,(dir==FTF_DIR_BUY ? ANCHOR_TOP : ANCHOR_BOTTOM));
      ObjectSetInteger(0,a,OBJPROP_WIDTH,2);
      Decorate(a,(dir==FTF_DIR_BUY ? clrLime : clrRed),text);
      string tx=Name("ET_"+id);
      if(!Exists(tx))
        {
         if(!ObjectCreate(0,tx,OBJ_TEXT,0,t,price))
           {
            CreateFailed(tx);
            return;
           }
         PushMarker(tx);
        }
      ObjectSetString(0,tx,OBJPROP_TEXT,FTF_EngineCode(engine)+" "+FTF_DirStr(dir)+" #"+id);
      ObjectSetString(0,tx,OBJPROP_FONT,FTF_UI_TEXT_FONT);
      ObjectSetInteger(0,tx,OBJPROP_FONTSIZE,FTF_UI_TEXT_SIZE);
      ObjectSetInteger(0,tx,OBJPROP_ANCHOR,(dir==FTF_DIR_BUY ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER));
      Decorate(tx,EngineColor(engine),text);
      Redraw();
     }

   void              DrawExit(const ulong ticket,const int engine,const int dir,const datetime tOpen,const double pOpen,
                              const datetime tClose,const double pClose,const double net,const string text)
     {
      if(!m_enabled || !m_cfg.DrawTrades)
         return;
      string id=IntegerToString((long)ticket);
      string a=Name("X_"+id);
      if(!Exists(a))
        {
         if(!ObjectCreate(0,a,OBJ_ARROW,0,tClose,pClose))
           {
            CreateFailed(a);
            return;
           }
         PushMarker(a);
        }
      ObjectSetInteger(0,a,OBJPROP_ARROWCODE,251);
      ObjectSetInteger(0,a,OBJPROP_ANCHOR,ANCHOR_BOTTOM);
      ObjectSetInteger(0,a,OBJPROP_WIDTH,1);
      Decorate(a,clrGold,text);
      if(tOpen>0 && pOpen>0.0)
        {
         string l=Name("L_"+id);
         if(!Exists(l))
           {
            if(ObjectCreate(0,l,OBJ_TREND,0,tOpen,pOpen,tClose,pClose))
               PushMarker(l);
            else
               CreateFailed(l);
           }
         if(Exists(l))
           {
            ObjectSetInteger(0,l,OBJPROP_STYLE,STYLE_DOT);
            ObjectSetInteger(0,l,OBJPROP_WIDTH,1);
#ifdef __MQL5__
            ObjectSetInteger(0,l,OBJPROP_RAY_RIGHT,false);
#else
            ObjectSetInteger(0,l,OBJPROP_RAY,false);
#endif
            Decorate(l,(net>=0.0 ? clrLime : clrRed),text);
           }
        }
      string tx=Name("XT_"+id);
      if(!Exists(tx))
        {
         if(ObjectCreate(0,tx,OBJ_TEXT,0,tClose,pClose))
            PushMarker(tx);
         else
            CreateFailed(tx);
        }
      if(Exists(tx))
        {
         ObjectSetString(0,tx,OBJPROP_TEXT,FTF_EngineCode(engine)+" "+(net>=0.0 ? "+" : "")+DoubleToString(net,2));
         ObjectSetString(0,tx,OBJPROP_FONT,FTF_UI_TEXT_FONT);
         ObjectSetInteger(0,tx,OBJPROP_FONTSIZE,FTF_UI_TEXT_SIZE);
         ObjectSetInteger(0,tx,OBJPROP_ANCHOR,(dir==FTF_DIR_BUY ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER));
         Decorate(tx,(net>=0.0 ? clrLime : clrTomato),text);
        }
      Redraw();
     }

   //--- generic shapes (upsert by id) ---------------------------------
   void              DrawRect(const string id,const datetime t1,const double p1,const datetime t2,const double p2,
                              const color clr,const bool fill,const string tip)
     {
      if(!m_enabled)
         return;
      string n=Name(id);
      if(!Exists(n))
        {
         if(!ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,p1,t2,p2))
           {
            CreateFailed(n);
            return;
           }
        }
      else
        {
         ObjectMove(0,n,0,t1,p1);
         ObjectMove(0,n,1,t2,p2);
        }
      ObjectSetInteger(0,n,OBJPROP_BACK,true);
      ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
#ifdef __MQL5__
      ObjectSetInteger(0,n,OBJPROP_FILL,fill);
#endif
      Decorate(n,clr,tip);
     }

   void              DrawSegment(const string id,const datetime t1,const double p1,const datetime t2,const double p2,
                                 const color clr,const int style,const string tip)
     {
      if(!m_enabled)
         return;
      string n=Name(id);
      if(!Exists(n))
        {
         if(!ObjectCreate(0,n,OBJ_TREND,0,t1,p1,t2,p2))
           {
            CreateFailed(n);
            return;
           }
         //--- micro-range segments are markers (budgeted); zone lines are managed by their owner
         if(StringFind(id,"MR_")==0)
            PushMarker(n);
        }
      else
        {
         ObjectMove(0,n,0,t1,p1);
         ObjectMove(0,n,1,t2,p2);
        }
      ObjectSetInteger(0,n,OBJPROP_STYLE,style);
      ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
#ifdef __MQL5__
      ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
#else
      ObjectSetInteger(0,n,OBJPROP_RAY,false);
#endif
      ObjectSetInteger(0,n,OBJPROP_BACK,false);
      Decorate(n,clr,tip);
     }

   void              DrawVLine(const string id,const datetime t,const color clr,const string tip)
     {
      if(!m_enabled)
         return;
      string n=Name(id);
      if(!Exists(n))
        {
         if(!ObjectCreate(0,n,OBJ_VLINE,0,t,0.0))
           {
            CreateFailed(n);
            return;
           }
        }
      else
         ObjectMove(0,n,0,t,0.0);
      ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,n,OBJPROP_BACK,true);
      Decorate(n,clr,tip);
     }

   void              DrawText(const string id,const datetime t,const double price,const string text,const color clr)
     {
      if(!m_enabled)
         return;
      string n=Name(id);
      if(!Exists(n))
        {
         if(!ObjectCreate(0,n,OBJ_TEXT,0,t,price))
           {
            CreateFailed(n);
            return;
           }
        }
      else
         ObjectMove(0,n,0,t,price);
      ObjectSetString(0,n,OBJPROP_TEXT,text);
      ObjectSetString(0,n,OBJPROP_FONT,FTF_UI_TEXT_FONT);
      ObjectSetInteger(0,n,OBJPROP_FONTSIZE,FTF_UI_TEXT_SIZE);
      ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
      Decorate(n,clr,text);
     }

   void              DrawRejected(const int engine,const int dir,const datetime t,const double price,const string reason)
     {
      if(!m_enabled || !m_cfg.DrawRejected)
         return;
      m_rejSeq++;
      string n=Name("REJ_"+IntegerToString(m_rejSeq));
      if(!ObjectCreate(0,n,OBJ_ARROW,0,t,price))
        {
         CreateFailed(n);
         return;
        }
      PushMarker(n);
      ObjectSetInteger(0,n,OBJPROP_ARROWCODE,158);
      ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_CENTER);
      ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
      Decorate(n,clrGray,FTF_EngineCode(engine)+" "+FTF_DirStr(dir)+" REJECTED: "+reason);
     }

   void              Remove(const string id)
     {
      if(!m_enabled)
         return;
      string n=Name(id);
      if(Exists(n))
         ObjectDelete(0,n);
     }

   void              Redraw(void)
     {
      if(!m_enabled)
         return;
      ulong now=GetMicrosecondCount();
      if(m_lastRedrawUs>0 && now>=m_lastRedrawUs && now-m_lastRedrawUs<(ulong)FTF_UI_REDRAW_US)
         return;
      m_lastRedrawUs=now;
      ChartRedraw(0);
     }

   color             EngineColor(const int engine)
     {
      switch(engine)
        {
         case FTF_ENG_MOMENTUM: return clrDodgerBlue;
         case FTF_ENG_FVG:      return clrOrange;
         case FTF_ENG_RANGE:    return clrMediumOrchid;
         default:               break;
        }
      return clrSilver;
     }
  };

#endif // FTF_CHART_UI_MQH
