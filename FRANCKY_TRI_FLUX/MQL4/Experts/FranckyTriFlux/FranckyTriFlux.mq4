//+------------------------------------------------------------------+
//|                                               FranckyTriFlux.mq4 |
//|        FRANCKY TRI-FLUX - HFT-style retail ultra scalping (MT4)  |
//|  Faithful port of the MT5 reference (same shared Core).          |
//|  Divergences: docs/08_MT4_Divergences.md                          |
//|  One instance = the chart symbol only (spec G.3).                |
//+------------------------------------------------------------------+
#property copyright   "FRANCKY TRI-FLUX - perpetual licence, no lock (spec 1.1)"
#property link        ""
#property version     "1.00"
#property description "FRANCKY TRI-FLUX HFT-style ultra scalping - MT4 port"
#property description "Engines: Momentum / Micro-breakout, FVG, Range / Mean Reversion (independent)"
#property description "Markets: EURUSD, XAUUSD, BTCUSD - attach one instance per chart symbol"
#property strict

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
//| MT4 has no OnTradeTransaction: positions are reconciled each tick |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   g_ftf.OnTickHandler();
  }
//+------------------------------------------------------------------+
//| OnTimer is not called by the MT4 Strategy Tester - nothing        |
//| critical depends on it (docs/08).                                 |
//+------------------------------------------------------------------+
void OnTimer(void)
  {
   g_ftf.OnTimerHandler();
  }
//+------------------------------------------------------------------+
double OnTester(void)
  {
   return g_ftf.OnTesterHandler();
  }
//+------------------------------------------------------------------+
