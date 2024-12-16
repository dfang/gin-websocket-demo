//+------------------------------------------------------------------+
//|                                               AutoTakeProfit.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, fang duan"
#property link      "https://www.mql5.com"
#property version   "0.10"

#include <AutoTrader/EA/TradeTransaction.mqh>
#include <AutoTrader/EA/AutoTrader.mqh>
#include <WebSocket/client.mqh>
#include <JAson.mqh>
#include <Trade/AccountInfo.mqh>

const string pairIdentifier = "95f6e028-78db-479f-b86c-850c088a7de4";
const string WS_URL = "ws://159.75.227.214:2222/ws";
const bool isDebug = true;


// Variables for backoff algorithm
int retryCount = 0;
int maxRetries = 5;
int initialDelay = 1000; // milliseconds
int maxDelay = 60000; // milliseconds

class CExtTradeTransaction : public CTradeTransaction
{
protected:
   //--- trade transactions
   virtual void      TradeTransactionOrderPlaced(ulong order)                      { PrintFormat("Pending order is placed. (order %I64u)", order); }
   virtual void      TradeTransactionOrderModified(ulong order)                    { PrintFormat("Pending order is modified. (order %I64u)", order); }
   virtual void      TradeTransactionOrderDeleted(ulong order)                     { PrintFormat("Pending order is deleted. (order %I64u)", order); }
   virtual void      TradeTransactionOrderExpired(ulong order)                     { PrintFormat("Pending order is expired. (order %I64u)", order); }
   virtual void      TradeTransactionOrderTriggered(ulong order)                   { PrintFormat("Pending order is triggered. (order %I64u)", order); }

   virtual void      TradeTransactionPositionOpened(ulong position, ulong deal)    { PrintFormat("Position is opened. (position %I64u, deal %I64u)", position, deal); OnTradeTransactionPositionOpened(position, deal); }
   virtual void      TradeTransactionPositionStopTake(ulong position, ulong deal)  { PrintFormat("Position is closed on sl or tp. (position %I64u, deal %I64u)", position, deal); }
   virtual void      TradeTransactionPositionClosed(ulong position, ulong deal)    { PrintFormat("Position is closed. (position %I64u, deal %I64u)", position, deal); OnTradeTransactionPositionClosed(position, deal); }
   virtual void      TradeTransactionPositionCloseBy(ulong position, ulong deal)   { PrintFormat("Position is closed by opposite position. (position %I64u, deal %I64u)", position, deal); }
   virtual void      TradeTransactionPositionModified(ulong position)              { PrintFormat("Position is modified. (position %I64u)", position); }
};

CExtTradeTransaction CTT;


// Create an instance of AutoTrader
AutoTrader trader;
CAccountInfo  m_account;

class WS : public WebSocketClient<Hybi>
{
public:
   WS(const string address, const bool debug = false, const bool useCompression = false)
        : WebSocketClient(address, debug, useCompression) {}

      void onConnected() override
      {
          if(isDebug)
              Print(" > Connected ", url);

//          // Send PAIR_IDENTIFIER and self info to server
//          CJAVal data;
//          data["event_type"] = "pair";
//          // Create nested object for data
//          CJAVal dataObj;
//          dataObj["pair_identifier"] = pairIdentifier;
//          dataObj["login"] = m_account.Login();
//          dataObj["name"] = m_account.Company();
//          dataObj["balance"] = m_account.Balance();
//          dataObj["credit"] = m_account.Credit();
//          dataObj["equity"] = m_account.Equity();
//
//          data["data"] = dataObj;
//
//          string json_str;
//          json_str = data.Serialize();
//          Print(json_str);  // {"a":3.14000000,"b":"foo","c":["bar",2,"baz"]}
//
//          if (!WebSocket.send(json_str))
//          {
//              if (isDebug)
//                  Print("Cannot send data via WebSocket. Error: ", GetLastError());
//              close();
//          }
          
          OnConnected();
      }

      void onDisconnect() override
      {
          if(isDebug)
              Print(" > Disconnected ", url);
          
          OnDisconnected();
      }

      
       // Received message from server
      void onMessage(IWebSocketMessage *msg) override
      {
           // Implement your logic
           if (isDebug)
               Print(" <- Message from custom WS: ", msg.getString());
           
           OnMessage(msg);
      
           delete msg;
      }
      
      // Function to connect with backoff
      bool ConnectWithBackoff()
      {
         bool connected = false;
         
         while (!connected && retryCount < maxRetries)
         {
            // Calculate delay based on retry count
            int delay = initialDelay * MathPow(2, retryCount);
            if (delay > maxDelay)
               delay = maxDelay;
            
            Print("Retrying connection in ", delay, " milliseconds");
            Sleep(delay);
            
            connected = WebSocket.open();
            retryCount++;
         }
         
         if (connected)
         {
            Print("Connected successfully!");
            retryCount = 0; // Reset retry count on successful connection
         }
         else
         {
            Print("Failed to connect after ", maxRetries, " attempts.");
         }
         
         return connected;
      }
};

WS WebSocket(WS_URL, isDebug, false);


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
         trader = new AutoTrader();
         
         //--- create timer
         //EventSetTimer(60);
         EventSetMillisecondTimer(50);
         
         if (!WebSocket.open())
         {
              Alert(StringFormat(
                  "[FAIL] Cannot initialize WebSocket connection.\n"
                  "Please, check if [ %s ] had been added to allowed URLs and check Internet connection",
                  WS_URL));
              // return INIT_FAILED;
         }
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
    EventKillTimer();
   
    ExpertRemove();
    delete &WebSocket;
    delete &trader;
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
          //if (!WebSocket.isConnected())
          //{
          //     Print("WS is not connected, try to reconnect with backoff algorithm");
          //     WebSocket.ConnectWithBackoff();
          //     return;
          //}else{
          //     // Use a non-blocking check
          //     WebSocket.checkMessages(false);
          //}
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
       // trader.CloseAllPositionsByProfitAsync();
             
       if (!WebSocket.isConnected())
       {
            Print("WS is not connected, try to reconnect with backoff algorithm");
            WebSocket.ConnectWithBackoff();
            return;
       }else{
            // Use a non-blocking check
            WebSocket.checkMessages(false);
       }
  }
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
//---
     
  }
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
//---
      Print("OnTradeTransaction: ", EnumToString(trans.type));
      CTT.OnTradeTransaction(trans, request, result);
  }
//+------------------------------------------------------------------+


void OnTradeTransactionPositionOpened(ulong position, ulong deal)
{
      Print("Position Opened");
      //string data = StringFormat(
      //    "{\"event_type\": \"position_closed\", \"account_info\": {" +
      //    "\"login\": %d, " +
      //    "\"balance\": %.2f, " +
      //    "\"equity\": %.2f, " +
      //    "\"profit\": %.2f, " +
      //    "\"margin\": %.2f" +
      //    "}}",
      //    m_account.Login(),
      //    m_account.Balance(),
      //    m_account.Equity(),
      //    m_account.Profit(),
      //    m_account.Margin()
      //  );
      CJAVal body;
      body["action"] = "publish";
      body["topic"] = pairIdentifier;
      CJAVal msgObj; // Create nested object for data
      msgObj["event"] = "position_open";
      body["message"] = msgObj;
      string data;
      data = body.Serialize();
      //Print("DATA:", data);
      if (!WebSocket.send(data))
      {
       if (isDebug)
            Print("Failed to send 'position_opened' message. Error: ", GetLastError());
      }
      else if (isDebug)
      {
            Print("Sent position_opened message: ", data);
      }
      
      //delete &body;
      //delete data;
}

void OnTradeTransactionPositionClosed(ulong position, ulong deal)
{
      Print("Position Closed");
      //string data = StringFormat(
      //    "{\"event_type\": \"position_closed\", \"account_info\": {" +
      //    "\"login\": %d, " +
      //    "\"balance\": %.2f, " +
      //    "\"equity\": %.2f, " +
      //    "\"profit\": %.2f, " +
      //    "\"margin\": %.2f" +
      //    "}}",
      //    m_account.Login(),
      //    m_account.Balance(),
      //    m_account.Equity(),
      //    m_account.Profit(),
      //    m_account.Margin()
      //  );
      //string message = "{\"event\": \"position_closed\"}";
      if(HistoryDealSelect(deal)){
         int reason = HistoryDealGetInteger(deal, DEAL_REASON);
         PrintFormat("DEAL_REASON: %s", EnumToString(ENUM_DEAL_REASON(reason)));
      }
      
      if(HistoryDealSelect(deal)){
         long reason=HistoryDealGetInteger(deal,DEAL_REASON);
         if(reason == DEAL_REASON_SO){  // 被强平
               string data = StringFormat("{ \"action\": \"publish\", \"topic\": \"%s\", \"message\":" + "{\"event\": \"position_closed\"} }", pairIdentifier);
               // Send WebSocket message
               if (!WebSocket.send(data))
               {
                if (isDebug)
                     Print("Failed to send 'position_closed' message. Error: ", GetLastError());
               }
               else if (isDebug)
               {
                     Print("Sent position_closed message: ", data);
               }
         }
      }
      
     
      
      //delete data;
}

void OnConnected()
{
      PrintFormat("OnConnected");
      // {"action": "subscribe","topic": "95f6e028-78db-479f-b86c-850c088a7de4"}
      string data = StringFormat("{ \"action\": \"subscribe\", \"topic\": \"%s\" }", pairIdentifier);
      PrintFormat("data to send for subscribe: %s", data);
      // Send WebSocket message
      if (!WebSocket.send(data))
      {
         if (isDebug)
            Print("Failed to send message. Error: ", GetLastError());
      }
      
      //string data2 = StringFormat("{ \"action\": \"publish\", \"topic\": \"%s\", \"message\": \"%s\" }", pairIdentifier, "TEST");
      //PrintFormat("data to send for publish: %s", data);
      //// Send WebSocket message
      //if (!WebSocket.send(data2))
      //{
      //   if (isDebug)
      //      Print("Failed to send message. Error: ", GetLastError());
      //}
      
      //delete data;
}

void OnDisconnected()
{
      PrintFormat("OnDisconnected");
}

void OnMessage(IWebSocketMessage *msg)
{
      PrintFormat("OnMessage: %s", msg.getString());
      CJAVal obj;
      if(obj.Deserialize(msg.getString())){
         Print("Deserialized");
         if(obj["event"] == "position_closed"){
             trader.CloseMostProfitablePositionAsync();
         }
         delete &obj;
      }
}
