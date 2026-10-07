//+------------------------------------------------------------------+
//|                                               FranckyTriFlux.mq5 |
//|        FRANCKY TRI-FLUX - HFT-style retail ultra scalping (MT5)  |
//|  3 independent engines: Momentum/Micro-breakout, FVG, Range/MR   |
//|  One instance = the chart symbol only (spec G.3).                |
//|  Architecture: docs/02_Architecture_and_Workflow.md              |
//|  Contract:     docs/09_SSOT_Developer_Contract.md                |
//+------------------------------------------------------------------+
#property copyright   "FRANCKY TRI-FLUX - perpetual licence, no lock (spec 1.1)"
#property link        ""
#property version     "1.00"
#property description "FRANCKY TRI-FLUX HFT-style ultra scalping - MT5 reference version"
#property description "Engines: Momentum / Micro-breakout, FVG, Range / Mean Reversion (independent)"
#property description "Markets: EURUSD, XAUUSD, BTCUSD - attach one instance per chart symbol"

//--- this file only forwards terminal events to the controller (all logic lives in Include\FranckyTriFlux)
#include <FranckyTriFlux\Core\Defines.mqh>
#include <FranckyTriFlux\Inputs.mqh>
#include <FranckyTriFlux\Core\Controller.mqh>

CFranckyController g_ftf;

//+------------------------------------------------------------------+
int OnInit(void)
  {
   return g_ftf.OnInitHandler();
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_ftf.OnDeinitHandler(reason);
  }
//+------------------------------------------------------------------+
void OnTick(void)
  {
   g_ftf.OnTickHandler();
  }
//+------------------------------------------------------------------+
void OnTimer(void)
  {
   g_ftf.OnTimerHandler();
  }
//+------------------------------------------------------------------+
//| a deal was added (fill / SL / TP / manual close): reconcile now   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
      g_ftf.OnTradeHandler();
  }
//+------------------------------------------------------------------+
//| custom optimization criterion (tester: 'Custom max')             |
//+------------------------------------------------------------------+
double OnTester(void)
  {
   return g_ftf.OnTesterHandler();
  }
//+------------------------------------------------------------------+
