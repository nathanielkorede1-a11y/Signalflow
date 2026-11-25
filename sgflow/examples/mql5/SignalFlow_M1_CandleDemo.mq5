//+------------------------------------------------------------------+
//| SignalFlow M1 Candle Demo EA                                     |
//| Demonstration only: bullish closed M1 candle BUY, bearish SELL.  |
//| Smart Algo Trader                                                |
//+------------------------------------------------------------------+
#property copyright "Smart Algo Trader"
#property version   "1.00"
#property strict
#include <Trade\Trade.mqh>
#include "SignalFlowWebhook.mqh"

CTrade trade;
input double FixedLot=0.01;
input double StopLossPips=20.0;
input double TakeProfitPips=60.0;
input double PipSizeOverride=0.0; // 0=standard FX pip; set explicitly for metals/indices/broker symbols
input ulong MagicNumber=881122;
input bool OneOpenPositionOnly=true;
input bool PublishToSignalFlow=true;
input string SignalFlowBaseUrl="https://signalflow-xevn.vercel.app";
input string SignalFlowWebhookSecret="CHANGE_ME";

datetime last_bar_time=0;

int OnInit(){
 if(FixedLot<=0 || StopLossPips<=0 || TakeProfitPips<=0){Print("Invalid lot/SL/TP inputs");return INIT_PARAMETERS_INCORRECT;}
 trade.SetExpertMagicNumber(MagicNumber);
 trade.SetTypeFillingBySymbol(_Symbol);
 last_bar_time=iTime(_Symbol,PERIOD_M1,0);
 Print("SignalFlow M1 Candle Demo started on ",_Symbol,". DEMO ACCOUNT ONLY.");
 return INIT_SUCCEEDED;
}
void OnTick(){
 datetime current=iTime(_Symbol,PERIOD_M1,0);
 if(current<=0 || current==last_bar_time)return;
 last_bar_time=current; // one evaluation per newly opened M1 bar, using the candle that just closed
 if(Bars(_Symbol,PERIOD_M1)<3)return;
 if(OneOpenPositionOnly && HasOurPosition())return;
 double o=iOpen(_Symbol,PERIOD_M1,1), c=iClose(_Symbol,PERIOD_M1,1);
 if(o<=0 || c<=0 || c==o)return; // ignore doji
 MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;
 double pip=PipSize();if(pip<=0)return;
 double entry=(c>o)?tick.ask:tick.bid;
 double sl,tp;
 if(c>o){sl=entry-StopLossPips*pip;tp=entry+TakeProfitPips*pip;}
 else{sl=entry+StopLossPips*pip;tp=entry-TakeProfitPips*pip;}
 int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
 sl=NormalizeDouble(sl,digits);tp=NormalizeDouble(tp,digits);
 double lot=NormalizeVolume(FixedLot);
 if(lot<=0){Print("Lot size is outside broker volume constraints");return;}
 bool sent=(c>o)?trade.Buy(lot,_Symbol,0.0,sl,tp,"SignalFlow M1 bullish"):trade.Sell(lot,_Symbol,0.0,sl,tp,"SignalFlow M1 bearish");
 uint rc=trade.ResultRetcode();
 bool executed=sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL);
 if(!executed){Print("Order not confirmed. Retcode=",rc," ",trade.ResultRetcodeDescription());return;}
 double actual=trade.ResultPrice();if(actual<=0)actual=entry;
 string side=(c>o)?"BUY":"SELL";
 Print("Demo trade executed: ",side," ",_Symbol," entry=",actual," SL=",sl," TP=",tp);
 if(PublishToSignalFlow){
  string external_id="M1DEMO_"+_Symbol+"_"+IntegerToString((long)current)+"_"+side;
  double rr=TakeProfitPips/StopLossPips;
  if(!SignalFlowSend(SignalFlowBaseUrl,SignalFlowWebhookSecret,external_id,_Symbol,side,actual,sl,tp,rr,"active"))
   Print("Trade executed but SignalFlow publishing failed. Check WebRequest permission, URL and secret.");
 }
}
double PipSize(){
 if(PipSizeOverride>0)return PipSizeOverride;
 int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
 double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
 return (digits==3 || digits==5)?point*10.0:point;
}
double NormalizeVolume(double requested){
 double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
 if(step<=0 || requested<minv || requested>maxv)return 0;
 double v=MathFloor(requested/step+1e-8)*step;
 int precision=2;if(step<0.01)precision=3;if(step<0.001)precision=4;
 return NormalizeDouble(v,precision);
}
bool HasOurPosition(){
 for(int i=PositionsTotal()-1;i>=0;i--){ulong ticket=PositionGetTicket(i);if(ticket==0)continue;if(PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber)return true;}
 return false;
}
