# Supply & Demand Trading Bot (MQL4)

A MetaTrader 4 expert advisor (EA) that automates entries and exits based on supply and demand zoning, candlestick patterns, and risk management.

---

## ⚙️ Features

- **Multi-bar Supply & Demand Zones**  
  Automatically scans past H1 bars for strong bullish/bearish candles to define up to 10 supply and 10 demand zones.

- **Zone Pullback Entries**  
  Buys when price returns into a demand zone + bullish engulfing confirmation; sells on supply-zone pullbacks + bearish engulfing.

- **Risk Management**  
  • Configurable risk percentage per trade  
  • Automatic lot-size calculation  
  • Stop Loss and Take Profit in pips  
  • Minimum “fake-out” threshold to avoid whipsaws  

- **Trade Guards**  
  • Single-position-per-symbol enforcement  
  • Cool-down timer (default: 5 min)  
  • Tradability check  
  • Duplicate-trade prevention via global variables  

- **Logging & Notifications**  
  • Appends every trade to `Logs.csv`  
  • Push notifications on trade execution  

- **Optional Visuals**  
  Draws colored rectangles on the chart for active supply/demand zones.

---

## 📥 Installation

1. **Clone or Download** this repository.  
2. Open **MetaEditor 4** (part of your MT4 installation).  
3. Copy `SND.mq4` into your `...\MQL4\Experts\` folder.  
4. In MetaEditor, open `SND.mq4` and compile (F7).  
5. Restart MetaTrader 4.

---

## ⚙️ Inputs & Configuration

| Parameter            | Type    | Default | Description                                         |
|----------------------|---------|---------|-----------------------------------------------------|
| **RiskPercentage**   | double  | 1.0     | % of account balance to risk per trade              |
| **StopLossPips**     | int     | 30      | Stop Loss distance in pips                          |
| **TakeProfitPips**   | int     | 400     | Take Profit distance in pips                        |
| **FakeoutThreshold** | int     | 10      | Minimum extra pips beyond zone to avoid fake‐outs   |
| **MaxZoneAgeHours**  | int     | 48      | How long to keep detected zones (in hours)          |
| **MaxZones**         | int     | 10      | Maximum number of supply & demand zones to store    |

_You can tweak these values in the EA’s Properties window before attaching to a chart._

---

## 🚀 Usage

1. Attach the EA to any **H1** chart.  
2. Ensure “AutoTrading” is enabled in MT4.  
3. The EA will:
   - Scan back **50** bars for new zones each tick.
   - Purge zones older than **MaxZoneAgeHours**.
   - Draw active zones (if visualization is ON).
   - Enter trades on valid pullbacks with candlestick confirmation.
   - Respect all trade-guard and risk parameters.

---

## 🛠 Backtesting & Optimization

1. In the MT4 Strategy Tester, select **SND.ex4** (or **.mq4**).  
2. Choose your symbol and **H1** timeframe.  
3. Set your date range and modeling quality.  
4. Optimize inputs like `RiskPercentage`, `FakeoutThreshold`, `MaxZoneAgeHours`, and the body/range ratio threshold inside the code if you’ve customized it.

---

## ✏️ Customization

- **Zone Detection Logic**  
  Tweak the `body/range > 0.5` ratio or change the lookback window (default 50 bars) in `ScanForSupplyDemandZones()`.

- **Visual Style**  
  Modify colors, line widths, or object types in `DrawZones()`.

- **Additional Filters**  
  Integrate news filters, volume confirmation, or time-of-day restrictions.

---

## 📂 Log File

All executed trades are appended to **Logs.csv** in your `MQL4\Files` folder (you can change the path in `LogToFile()`). Columns:

