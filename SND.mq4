//+------------------------------------------------------------------+
//| Supply and Demand Trading Bot (MQL5 Version)                    |
//| Author: Monte                                                   |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>  // Include trade functions

enum TradeType
{
   NONE = 0,
   BUY_TRADE = 1,
   SELL_TRADE = 2
};

//––– Supply/Demand Zone structure and storage
struct Zone {
   double high;
   double low;
   datetime time;
};

// Arrays to hold the last N zones
#define MAX_ZONES 10
Zone demandZones[MAX_ZONES];
Zone supplyZones[MAX_ZONES];
int demandZoneCount = 0;
int supplyZoneCount = 0;

//+------------------------------------------------------------------+
//| Returns true if there is already an open position on this symbol|
//+------------------------------------------------------------------+
bool HasOpenPositionForSymbol()
{
  for(int i = 0; i < PositionsTotal(); i++)
  {
    if(PositionGetSymbol(i) == _Symbol)
      return true;
  }
  return false;
}

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input double LotSize = 0.1;             // Default lot size
input int StopLossPips = 30;            // Stop Loss in pips
input int TakeProfitPips = 400;         // Take Profit in pips
input double RiskPercentage = 1.0;      // Risk per trade as % of balance
input int FakeoutThreshold = 10;        // Minimum price movement to avoid fakeouts

CTrade trade;                           // Trade object
datetime lastTradeTime = 0;             // Last trade execution time

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED); // Successful initialization
}

void OnDeinit(const int reason) {}      // No deinitialization logic needed

//+------------------------------------------------------------------+
//| Main trading loop                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1) History guard
   if (Bars(_Symbol, PERIOD_H1) < 3)
   {
      Print(__FUNCTION__, ": waiting for H1 history (", Bars(_Symbol, PERIOD_H1), " bars)");
      return;
   }
   ResetLastError();

   // 2) Cooldown guard
   if (!CanTrade())
   {
      Print(__FUNCTION__, ": cooldown in effect, next trade after ",
            TimeToString(lastTradeTime + 5*60, TIME_MINUTES));
      return;
   }

   // 3) Existing position guard
   if(HasOpenPositionForSymbol())
   {
      Print("🛑 A position is already open on ", _Symbol);
      return;
   }

   // 4) Tradability guard
   if (!IsSymbolTradable())
   {
      Print(__FUNCTION__, ": symbol not tradable");
      return;
   }

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double resistanceLevel = GetResistanceLevel();
   double supportLevel = GetSupportLevel();

   // Check for price breaking above resistance (fakeout logic)
   if (currentPrice > resistanceLevel + FakeoutThreshold * _Point)
   {
      EnterSellTrade(currentPrice);
      SetTradeTime();
   }
   // Check for price breaking below support (fakeout logic)
   else if (currentPrice < supportLevel - FakeoutThreshold * _Point)
   {
      EnterBuyTrade(currentPrice);
      SetTradeTime();
   }
   
   PurgeOldZones(48);
   
   ScanForSupplyDemandZones();   // identify fresh zones
   CheckZoneEntry();             // trigger entries when price returns
   
   ResetLastTradeIfNoOpenPositions();
}

//+------------------------------------------------------------------+
//| Global Symbol-Based Last Trade Tracker Trade Duplication Control |
//+------------------------------------------------------------------+
string GetLastTradeKey()
{
   return "LastTrade_" + _Symbol;
}

TradeType GetLastTrade()
{
   if (!GlobalVariableCheck(GetLastTradeKey()))
      return NONE;
   return (TradeType)(int)GlobalVariableGet(GetLastTradeKey());
}

void SetLastTrade(TradeType type)
{
   GlobalVariableSet(GetLastTradeKey(), type);
}

void ResetLastTradeIfNoOpenPositions()
{
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionGetSymbol(i) == _Symbol)
         return;
   }
   GlobalVariableDel(GetLastTradeKey());
}

//+------------------------------------------------------------------+
//| Enter sell trade                                                 |
//+------------------------------------------------------------------+
void EnterSellTrade(double entryPrice)
{
   if (GetLastTrade() == SELL_TRADE) {
      Print("🛑 Duplicate SELL trade avoided on ", _Symbol);
      return;
   }

   double sl = entryPrice + StopLossPips * _Point;
   double tp = entryPrice - TakeProfitPips * _Point;
   double lot = CalculateLotSize(StopLossPips);
   CorrectTradeParameters(lot, entryPrice, sl, tp);

   if (!trade.Sell(lot, _Symbol, entryPrice, sl, tp, "Sell Trade"))
   {
      Print("❌ Sell failed. Error: ", GetLastError());
      ResetLastError();
   }
   else
   {
      SendNotification("✅ Sell trade executed on " + _Symbol);
      SetLastTrade(SELL_TRADE);
   }
}

//+------------------------------------------------------------------+
//| Enter buy trade                                                  |
//+------------------------------------------------------------------+
void EnterBuyTrade(double entryPrice)
{
   if (GetLastTrade() == BUY_TRADE) {
   Print("🛑 Duplicate BUY trade avoided on ", _Symbol);
   return;
   }

   double sl = entryPrice - StopLossPips * _Point;
   double tp = entryPrice + TakeProfitPips * _Point;
   double lot = CalculateLotSize(StopLossPips);
   CorrectTradeParameters(lot, entryPrice, sl, tp);

   if (!trade.Buy(lot, _Symbol, entryPrice, sl, tp, "Buy Trade"))
   {
      Print("❌ Buy failed. Error: ", GetLastError());
      ResetLastError();
   }
   else
   {
      SendNotification("✅ Buy trade executed on " + _Symbol);
      SetLastTrade(BUY_TRADE);
   }
}

//+------------------------------------------------------------------+
//| Lot size calculator based on account balance and SL              |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercentage / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = NormalizeDouble(riskAmount / (slPips * tickValue), 2);

   // Ensure lot within broker min/max range
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(minLot, lot);
   lot = MathMin(maxLot, lot);
   lot = MathFloor(lot / lotStep) * lotStep;

   return lot;
}

//+------------------------------------------------------------------+
//| Adjust SL/TP to meet broker stop-level and price precision       |
//+------------------------------------------------------------------+
void CorrectTradeParameters(double &lot, double &price, double &sl, double &tp)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if (lot < minLot) lot = minLot;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   price = NormalizeDouble(price, _Digits);

   if (MathAbs(price - sl) < minStop)
      sl = (price > sl) ? price - minStop : price + minStop;

   if (MathAbs(price - tp) < minStop)
      tp = (price > tp) ? price - minStop : price + minStop;

   if (price <= 0)
      price = (lot > 0) ? (bid + ask) / 2 : ask;
}

//+------------------------------------------------------------------+
//| Utility Checks                                                   |
//+------------------------------------------------------------------+
bool IsSymbolTradable()  { return SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_DISABLED; }

bool CanTrade() { return (TimeCurrent() - lastTradeTime) > 5 * 60; }

void SetTradeTime() { lastTradeTime = TimeCurrent(); }

//+------------------------------------------------------------------+
//| Price Action Confirmations for Supply/Demand Zones               |
//+------------------------------------------------------------------+
void CheckSupplyDemandZones()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double high = iHigh(_Symbol, PERIOD_H1, 1);
   double low = iLow(_Symbol, PERIOD_H1, 1);

   if (IsBearishEngulfing() && price >= low && price <= high)
   {
      EnterSellTrade(price);
      SetTradeTime();
   }

   if (IsBullishEngulfing() && price >= low && price <= high)
   {
      EnterBuyTrade(price);
      SetTradeTime();
   }
}

//+------------------------------------------------------------------+
//| Candlestick pattern detection                                    |
//+------------------------------------------------------------------+
bool IsBearishEngulfing()
{
   double o1 = iOpen(_Symbol, PERIOD_H1, 1);
   double c1 = iClose(_Symbol, PERIOD_H1, 1);
   double o2 = iOpen(_Symbol, PERIOD_H1, 2);
   double c2 = iClose(_Symbol, PERIOD_H1, 2);
   return (c1 < o1 && c2 > o2 && c1 < o2 && o1 > c2);
}

bool IsBullishEngulfing()
{
   double o1 = iOpen(_Symbol, PERIOD_H1, 1);
   double c1 = iClose(_Symbol, PERIOD_H1, 1);
   double o2 = iOpen(_Symbol, PERIOD_H1, 2);
   double c2 = iClose(_Symbol, PERIOD_H1, 2);
   return (c1 > o1 && c2 < o2 && c1 > o2 && o1 < c2);
}

//+------------------------------------------------------------------+
//| Support and Resistance levels (simplified)                       |
//+------------------------------------------------------------------+
double GetResistanceLevel() { return iHigh(_Symbol, PERIOD_H1, 1); }
double GetSupportLevel()    { return iLow(_Symbol, PERIOD_H1, 1); }
//+------------------------------------------------------------------+

void LogToFile(string type, double lot, double price, double sl, double tp, string comment)
{
   string logFile = "Logs.csv";
   int fileHandle = FileOpen(logFile, FILE_CSV | FILE_READ | FILE_WRITE | FILE_ANSI);

   if (fileHandle != INVALID_HANDLE)
   {
      FileSeek(fileHandle, 0, SEEK_END); // Append to end
      string log = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + "," +
                   _Symbol + "," +
                   type + "," +
                   DoubleToString(lot, 2) + "," +
                   DoubleToString(price, _Digits) + "," +
                   DoubleToString(sl, _Digits) + "," +
                   DoubleToString(tp, _Digits) + "," +
                   comment;
      FileWrite(fileHandle, log);
      FileClose(fileHandle);
   }
   else
   {
      Print("❌ Failed to open local log file.");
   }
}

void ScanForSupplyDemandZones()
{
   const int lookback = 50;               // how many H1 bars to inspect
   for(int i = 3; i < lookback; i++)      // skip the 2 most recent bars
   {
      double high = iHigh(_Symbol, PERIOD_H1, i);
      double low  = iLow (_Symbol, PERIOD_H1, i);
      double body = MathAbs(iClose(_Symbol, PERIOD_H1, i) - iOpen(_Symbol, PERIOD_H1, i));
      double range = high - low;
      // **Supply**: strong bearish candle after bullish
      if(iClose(_Symbol, PERIOD_H1, i+1) > iOpen(_Symbol, PERIOD_H1, i+1) &&
         iClose(_Symbol, PERIOD_H1, i)   < iOpen(_Symbol, PERIOD_H1, i)   &&
         body / range > 0.5)
         AddSupplyZone(high, low, iTime(_Symbol, PERIOD_H1, i));
      // **Demand**: strong bullish candle after bearish
      if(iClose(_Symbol, PERIOD_H1, i+1) < iOpen(_Symbol, PERIOD_H1, i+1) &&
         iClose(_Symbol, PERIOD_H1, i)   > iOpen(_Symbol, PERIOD_H1, i)   &&
         body / range > 0.5)
         AddDemandZone(high, low, iTime(_Symbol, PERIOD_H1, i));
   }
}

void AddSupplyZone(double high, double low, datetime t)
{
   if(supplyZoneCount < MAX_ZONES)
   {
      // assign fields one by one
      supplyZones[supplyZoneCount].high = high;
      supplyZones[supplyZoneCount].low  = low;
      supplyZones[supplyZoneCount].time = t;
      supplyZoneCount++;
   }
}

void AddDemandZone(double high, double low, datetime t)
{
   if(demandZoneCount < MAX_ZONES)
   {
      demandZones[demandZoneCount].high = high;
      demandZones[demandZoneCount].low  = low;
      demandZones[demandZoneCount].time = t;
      demandZoneCount++;
   }
}


void CheckZoneEntry()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Demand zones → buy on bullish confirmation
   for(int i = 0; i < demandZoneCount; i++)
   {
      if(price >= demandZones[i].low && price <= demandZones[i].high 
         && IsBullishEngulfing())
      {
         EnterBuyTrade(price);
         SetTradeTime();
         return;
      }
   }

   // Supply zones → sell on bearish confirmation
   for(int i = 0; i < supplyZoneCount; i++)
   {
      if(price <= supplyZones[i].high && price >= supplyZones[i].low 
         && IsBearishEngulfing())
      {
         EnterSellTrade(price);
         SetTradeTime();
         return;
      }
   }
}

void PurgeOldZones(int maxAgeHours)
{
   datetime now = TimeCurrent();
   //––– Purge old demand zones
   int writeDemand = 0;
   for(int i = 0; i < demandZoneCount; i++)
   {
      if(now - demandZones[i].time <= (datetime)maxAgeHours * 3600)
      {
         demandZones[writeDemand++] = demandZones[i];
      }
   }
   demandZoneCount = writeDemand;

   //––– Purge old supply zones
   int writeSupply = 0;
   for(int j = 0; j < supplyZoneCount; j++)
   {
      if(now - supplyZones[j].time <= (datetime)maxAgeHours * 3600)
      {
         supplyZones[writeSupply++] = supplyZones[j];
      }
   }
   supplyZoneCount = writeSupply;
}
