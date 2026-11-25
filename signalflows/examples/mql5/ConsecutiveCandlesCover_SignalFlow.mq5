//+------------------------------------------------------------------+
//| Consecutive Candles Cover Strategy + SignalFlow publishing       |
//| Smart Algo Trader                                                |
//+------------------------------------------------------------------+
#property copyright "Smart Algo Trader"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include "SignalFlowWebhook.mqh"

CTrade trade;

input ENUM_TIMEFRAMES InpTF              = PERIOD_M1;
input int      ConsecutiveCandles        = 4;
input double   SLPipBuffer               = 300.0;
input double   RiskReward                = 4.0;
input double   FixedRiskUSD              = 100.0;
input bool     OnlyFirstOfDay            = true;
input int      SignalNumberOfDay         = 1;
input int      GMTOffset                 = 0;
input double   RiskPercent               = 0.0;

// SignalFlow settings. Use your own private webhook secret.
input bool     PublishToSignalFlow       = true;
input string   SignalFlowBaseUrl          = "https://YOUR-DOMAIN.com";
input string   SignalFlowWebhookSecret    = "CHANGE_ME";

int last_trade_day = -1;
int signals_today = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(123456);
   trade.SetTypeFillingBySymbol(_Symbol);
   Print("=== Consecutive Cover Strategy + SignalFlow Loaded ===");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(now, tm);

   tm.hour -= GMTOffset;
   if(tm.hour < 0) { tm.hour += 24; tm.day--; }

   int today = tm.year * 10000 + tm.mon * 100 + tm.day;

   static int last_day = -1;
   if(last_day != today)
   {
      signals_today = 0;
      last_day = today;
   }

   if(OnlyFirstOfDay && last_trade_day == today) return;
   if(GetOpenPositionType() != -1) return;

   CheckForCoverSignal(today);
}

//+------------------------------------------------------------------+
void CheckForCoverSignal(int today)
{
   int needed = ConsecutiveCandles;
   if(needed < 1 || Bars(_Symbol, InpTF) < needed + 5) return;

   bool all_bearish = true;
   bool all_bullish = true;
   double first_open = 0.0;

   // Closed candles before the covering candle.
   for(int i = 2; i <= needed + 1; i++)
   {
      double o = iOpen(_Symbol, InpTF, i);
      double c = iClose(_Symbol, InpTF, i);
      if(c >= o) all_bearish = false;
      if(c <= o) all_bullish = false;
      if(i == needed + 1) first_open = o;
   }

   double cover_close = iClose(_Symbol, InpTF, 1);
   double cover_high  = iHigh(_Symbol, InpTF, 1);
   double cover_low   = iLow(_Symbol, InpTF, 1);

   int direction = 0;
   if(all_bearish && cover_close > first_open) direction = 1;
   if(all_bullish && cover_close < first_open) direction = -1;
   if(direction == 0) return;

   signals_today++;
   if(signals_today != SignalNumberOfDay) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;

   double pip = GetPipSize();
   double entry, sl, tp, risk;

   if(direction == 1)
   {
      entry = tick.ask;
      sl = NormalizeDouble(cover_low - SLPipBuffer * pip, _Digits);
      risk = entry - sl;
      tp = NormalizeDouble(entry + risk * RiskReward, _Digits);
   }
   else
   {
      entry = tick.bid;
      sl = NormalizeDouble(cover_high + SLPipBuffer * pip, _Digits);
      risk = sl - entry;
      tp = NormalizeDouble(entry - risk * RiskReward, _Digits);
   }

   if(risk <= 0.0) return;

   double lot = CalculateLotSize(risk);
   if(lot <= 0.0) return;

   bool request_ok = false;
   if(direction == 1)
      request_ok = trade.Buy(lot, _Symbol, 0.0, sl, tp);
   else
      request_ok = trade.Sell(lot, _Symbol, 0.0, sl, tp);

   uint retcode = trade.ResultRetcode();
   bool executed = request_ok &&
      (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL);

   if(executed)
   {
      last_trade_day = today;
      double actual_entry = trade.ResultPrice();
      if(actual_entry <= 0.0) actual_entry = entry;

      Print("Cover trade executed: ", (direction == 1 ? "BUY" : "SELL"),
            " | Entry=", actual_entry, " | SL=", sl, " | TP=", tp);

      // Publishing failure must never affect the already-executed trade.
      if(PublishToSignalFlow)
      {
         string side = (direction == 1 ? "BUY" : "SELL");
         string external_id = _Symbol + "_" + IntegerToString((int)InpTF) + "_" +
                              IntegerToString((long)TimeCurrent()) + "_" + side;

         bool sent = SignalFlowSend(SignalFlowBaseUrl,
                                    SignalFlowWebhookSecret,
                                    external_id,
                                    _Symbol,
                                    side,
                                    actual_entry,
                                    sl,
                                    tp,
                                    RiskReward,
                                    "active");
         if(!sent)
            Print("SignalFlow publishing failed; the MT5 trade remains open and managed normally.");
      }
   }
   else
   {
      Print("Trade was not confirmed as executed. Retcode=", retcode,
            " Description=", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
double GetPipSize()
{
   if(StringFind(_Symbol, "XAU") >= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

//+------------------------------------------------------------------+
double CalculateLotSize(double stopSize)
{
   double riskUSD = (RiskPercent > 0.0)
      ? AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0
      : FixedRiskUSD;
   if(riskUSD <= 0.0 || stopSize <= 0.0) return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

   double lot = riskUSD * tickSize / (stopSize * tickValue);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) return 0.0;

   lot = MathFloor(lot / step) * step;
   // Do not force the broker minimum if it would exceed the requested risk.
   if(lot < minLot) return 0.0;
   lot = MathMin(maxLot, lot);
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
int GetOpenPositionType()
{
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == 123456)
      return (int)PositionGetInteger(POSITION_TYPE);
   return -1;
}
//+------------------------------------------------------------------+
