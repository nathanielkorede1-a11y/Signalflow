// SignalFlow MQL5 webhook helper.
// Add your deployed HTTPS domain to MT5:
// Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL.
// Never distribute an EA containing a shared production secret.

#ifndef SIGNALFLOW_WEBHOOK_MQH
#define SIGNALFLOW_WEBHOOK_MQH

bool SignalFlowSend(const string base_url,
                    const string webhook_secret,
                    const string external_id,
                    const string symbol,
                    const string direction,
                    const double entry,
                    const double stop_loss,
                    const double take_profit,
                    const double rr,
                    const string status="active")
{
   if(base_url=="" || webhook_secret=="" || external_id=="" || symbol=="")
   {
      Print("SignalFlow: missing required webhook parameter");
      return false;
   }

   string url=base_url;
   if(StringSubstr(url,StringLen(url)-1,1)=="/")
      url=StringSubstr(url,0,StringLen(url)-1);
   url += "/api/mt5/signals";

   string json="{";
   json += "\"external_id\":\""+external_id+"\",";
   json += "\"symbol\":\""+symbol+"\",";
   json += "\"direction\":\""+direction+"\",";
   json += "\"entry\":"+DoubleToString(entry,_Digits)+",";
   json += "\"stop_loss\":"+DoubleToString(stop_loss,_Digits)+",";
   json += "\"take_profit\":"+DoubleToString(take_profit,_Digits)+",";
   json += "\"rr\":"+DoubleToString(rr,2)+",";
   json += "\"status\":\""+status+"\"}";

   char payload[];
   int copied=StringToCharArray(json,payload,0,WHOLE_ARRAY,CP_UTF8);
   if(copied>0) ArrayResize(payload,copied-1); // remove terminating NUL

   char response[];
   string response_headers;
   string headers="Content-Type: application/json\r\n";
   headers += "x-signalflow-secret: "+webhook_secret+"\r\n";

   ResetLastError();
   int http_code=WebRequest("POST",url,headers,10000,payload,response,response_headers);
   if(http_code<200 || http_code>=300)
   {
      Print("SignalFlow webhook failed. HTTP=",http_code,
            " MT5 error=",GetLastError(),
            " response=",CharArrayToString(response));
      return false;
   }

   Print("SignalFlow signal delivered. HTTP=",http_code,
         " response=",CharArrayToString(response));
   return true;
}

#endif
