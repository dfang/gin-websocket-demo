//+------------------------------------------------------------------+
//|                                                      ws_demo.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <WebSocket/client.mqh>
#include <Trade/AccountInfo.mqh>
#include <JAson.mqh>
#include <debug.mqh>

const string pairIdentifier = "de857c1f-7ea4-461d-bf15-636ee1d6a171";
const string WS_URL = "ws://159.75.227.214:2222/ws";
const bool isDebug = true;
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

          // Send PAIR_IDENTIFIER and self info to server
          CJAVal data;
          data["event_type"] = "pair";
          // Create nested object for data
          CJAVal dataObj;
          dataObj["pair_identifier"] = pairIdentifier;
          dataObj["login"] = m_account.Login();
          dataObj["name"] = m_account.Company();
          dataObj["balance"] = m_account.Balance();
          dataObj["credit"] = m_account.Credit();
          dataObj["equity"] = m_account.Equity();

          data["data"] = dataObj;

          string json_str;
          json_str = data.Serialize();
          Print(json_str);  // {"a":3.14000000,"b":"foo","c":["bar",2,"baz"]}

          if (!WebSocket.send(json_str))
          {
              if (isDebug)
                  Print("Cannot send data via WebSocket. Error: ", GetLastError());
              close();
          }
      }

      void onDisconnect() override
      {
          if(isDebug)
              Print(" > Disconnected ", url);
      }

      // Received message from server
      void onMessage(IWebSocketMessage *msg) override
      {
        // Implement your logic
        if (isDebug)
            Print(" > Message from custom WS: ", msg.getString());
      
        // Parse the received message
        string messageStr = msg.getString();

        // Create JAson object and parse message
        CJAVal data;
        if (data.Deserialize(messageStr))
        {
            // Debug print for all messages if in debug mode
            if (isDebug)
                Print(" > Message from custom WS: ", messageStr);
        
            delete msg;
        }
    }
};

WS WebSocket(WS_URL, isDebug, false);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   if (!WebSocket.open())
    {
        Alert(StringFormat(
            "[FAIL] Cannot initialize WebSocket connection.\n"
            "Please, check if [ %s ] had been added to allowed URLs and check Internet connection",
            WS_URL));
        return INIT_FAILED;
    }


    EventSetTimer(5);

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
    EventKillTimer();
    delete &WebSocket;
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
    // Print("onTick");
  }
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
int previousPositionCount = 0;
void OnTrade()
  {
//---
   // Current number of positions
   int currentPositions = PositionsTotal();

   // Check if positions have been reduced to zero from a non-zero state
   if (previousPositionCount > 0 && currentPositions == 0)
   {
        // Prepare JSON message with account details
        string accountInfo = StringFormat(
          "{\"event_type\": \"all_positions_closed\", \"account_info\": {" +
          "\"login\": %d, " +
          "\"balance\": %.2f, " +
          "\"equity\": %.2f, " +
          "\"profit\": %.2f, " +
          "\"margin\": %.2f" +
          "}}",
          m_account.Login(),
          m_account.Balance(),
          m_account.Equity(),
          m_account.Profit(),
          m_account.Margin()
        );
        
        // Send WebSocket message
        if (!WebSocket.send(accountInfo))
        {
          if (isDebug)
              Print("Failed to send 'all positions closed' message. Error: ", GetLastError());
        }
        else if (isDebug)
        {
          Print("Sent all positions closed message: ", accountInfo);
        }
    }

   // Update previous position count
   previousPositionCount = currentPositions;
  }
//+------------------------------------------------------------------+

void OnTimer()
{
    if (isDebug)
        // PrintDebugInfo();

    if (!WebSocket.isConnected())
    {
        Print("WS is not connected, attempting to reconnect");
        if (!WebSocket.open())
        {
            Print("Reconnection failed");
            return;
        }
        // EventKillTimer();
        return;
    }

    // Less frequent ping
    static int pingCounter = 0;
    pingCounter++;
    
    if (pingCounter >= 3)  // Send ping every 45 seconds (with 15-second timer)
    {
        string data = "{\"event_type\": \"ping\"}";
        if (!WebSocket.send(data))
        {
            if (isDebug)
                Print("Cannot send data via WebSocket. Error: ", GetLastError());
            WebSocket.close();
        }
        pingCounter = 0;
    }

    // Use a non-blocking check
    WebSocket.checkMessages(false);

    string data = "{\"event_type\": \"ping\"}";
    
    if (!WebSocket.send(data))
    {
        if (isDebug)
            Print("Cannot send data via WebSocket. Error: ", GetLastError());
        // WebSocket.close();
        // EventKillTimer();
    }
}

void PrintDebugInfo()
{
    Print(m_account.Login());
    Print(m_account.TradeModeDescription());
    Print(m_account.MarginModeDescription());
    Print(m_account.Balance());
    Print(m_account.Credit());
    Print(m_account.Profit());
    Print(m_account.Equity());
    Print(m_account.Margin());
    Print(m_account.FreeMargin());
    Print(m_account.MarginLevel());
    Print(m_account.MarginStopOut());
    Print(m_account.Name());
    Print(m_account.Server());
    Print(m_account.Currency());
    Print(m_account.Company());
}