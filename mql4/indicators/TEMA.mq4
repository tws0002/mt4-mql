/**
 * Triple Exponential Moving Average (TEMA) by Patrick G. Mulloy
 *
 *
 * The TEMA is not a three times applied EMA = EMA(EMA(EMA(n))). For calculation the value of a double-smoothed EMA is
 * subtracted 3 times from a tripled regular EMA. Finally a aingle triple-smoothed EMA is added.
 *
 *   TEMA(n) = 3*EMA(n) - 3*EMA(EMA(n)) + EMA(EMA(EMA(n)))
 *
 * Indicator buffers for iCustom():
 *  � MovingAverage.MODE_MA: MA values
 */
#include <stddefines.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////// Configuration ////////////////////////////////////////////////////////

extern int    MA.Periods      = 38;
extern string MA.AppliedPrice = "Open | High | Low | Close* | Median | Typical | Weighted";

extern color  MA.Color        = OrangeRed;               // indicator style management in MQL
extern string Draw.Type       = "Line* | Dot";
extern int    Draw.LineWidth  = 2;

extern int    Max.Values      = 5000;                    // max. number of values to calculate: -1 = all

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <rsfLibs.mqh>
#include <functions/@Trend.mqh>

#define MODE_TEMA             MovingAverage.MODE_MA
#define MODE_EMA_1            1
#define MODE_EMA_2            2

#property indicator_chart_window
#property indicator_buffers   1                          // configurable buffers (via input dialog)
int       allocated_buffers = 3;                         // used buffers
#property indicator_width1    2

double tema     [];                                      // MA values:       visible, displayed in "Data" window
double firstEma [];                                      // first EMA:       invisible
double secondEma[];                                      // second EMA(EMA): invisible

int    ma.appliedPrice;
string ma.name;                                          // name for chart legend, "Data" window and context menues

int    draw.type      = DRAW_LINE;                       // DRAW_LINE | DRAW_ARROW
int    draw.arrowSize = 1;                               // default symbol size for Draw.Type="dot"
string legendLabel;


/**
 * Initialization
 *
 * @return int - error status
 */
int onInit() {
   if (ProgramInitReason() == IR_RECOMPILE) {
      if (!RestoreInputParameters()) return(last_error);
   }

   // (1) validate inputs
   // MA.Periods
   if (MA.Periods < 1)     return(catch("onInit(1)  Invalid input parameter MA.Periods = "+ MA.Periods, ERR_INVALID_INPUT_PARAMETER));

   // MA.AppliedPrice
   string values[], sValue = StrToLower(MA.AppliedPrice);
   if (Explode(sValue, "*", values, 2) > 1) {
      int size = Explode(values[0], "|", values, NULL);
      sValue = values[size-1];
   }
   sValue = StrTrim(sValue);
   if (sValue == "") sValue = "close";                      // default price type
   ma.appliedPrice = StrToPriceType(sValue, F_ERR_INVALID_PARAMETER);
   if (IsEmpty(ma.appliedPrice)) {
      if      (StrStartsWith("open",     sValue)) ma.appliedPrice = PRICE_OPEN;
      else if (StrStartsWith("high",     sValue)) ma.appliedPrice = PRICE_HIGH;
      else if (StrStartsWith("low",      sValue)) ma.appliedPrice = PRICE_LOW;
      else if (StrStartsWith("close",    sValue)) ma.appliedPrice = PRICE_CLOSE;
      else if (StrStartsWith("median",   sValue)) ma.appliedPrice = PRICE_MEDIAN;
      else if (StrStartsWith("typical",  sValue)) ma.appliedPrice = PRICE_TYPICAL;
      else if (StrStartsWith("weighted", sValue)) ma.appliedPrice = PRICE_WEIGHTED;
      else                 return(catch("onInit(2)  Invalid input parameter MA.AppliedPrice = "+ DoubleQuoteStr(MA.AppliedPrice), ERR_INVALID_INPUT_PARAMETER));
   }
   MA.AppliedPrice = PriceTypeDescription(ma.appliedPrice);

   // Colors: after deserialization the terminal might turn CLR_NONE (0xFFFFFFFF) into Black (0xFF000000)
   if (MA.Color == 0xFF000000) MA.Color = CLR_NONE;

   // Draw.Type
   sValue = StrToLower(Draw.Type);
   if (Explode(sValue, "*", values, 2) > 1) {
      size = Explode(values[0], "|", values, NULL);
      sValue = values[size-1];
   }
   sValue = StrTrim(sValue);
   if      (StrStartsWith("line", sValue)) { draw.type = DRAW_LINE;  Draw.Type = "Line"; }
   else if (StrStartsWith("dot",  sValue)) { draw.type = DRAW_ARROW; Draw.Type = "Dot";  }
   else                    return(catch("onInit(3)  Invalid input parameter Draw.Type = "+ DoubleQuoteStr(Draw.Type), ERR_INVALID_INPUT_PARAMETER));

   // Draw.LineWidth
   if (Draw.LineWidth < 0) return(catch("onInit(4)  Invalid input parameter Draw.LineWidth = "+ Draw.LineWidth, ERR_INVALID_INPUT_PARAMETER));
   if (Draw.LineWidth > 5) return(catch("onInit(5)  Invalid input parameter Draw.LineWidth = "+ Draw.LineWidth, ERR_INVALID_INPUT_PARAMETER));

   // Max.Values
   if (Max.Values < -1)    return(catch("onInit(6)  Invalid input parameter Max.Values = "+ Max.Values, ERR_INVALID_INPUT_PARAMETER));


   // (2) setup buffer management
   SetIndexBuffer(MODE_TEMA,  tema     );
   SetIndexBuffer(MODE_EMA_1, firstEma );
   SetIndexBuffer(MODE_EMA_2, secondEma);


   // (3) data display configuration, names and labels
   string shortName="TEMA("+ MA.Periods +")", strAppliedPrice="";
   if (ma.appliedPrice != PRICE_CLOSE) strAppliedPrice = ", "+ PriceTypeDescription(ma.appliedPrice);
   ma.name = "TEMA("+ MA.Periods + strAppliedPrice +")";
   if (!IsSuperContext()) {                                    // no chart legend if called by iCustom()
       legendLabel = CreateLegendLabel(ma.name);
       ObjectRegister(legendLabel);
   }
   IndicatorShortName(shortName);                              // context menu
   SetIndexLabel(MODE_TEMA,  shortName);                       // "Data" window and tooltips
   SetIndexLabel(MODE_EMA_1, NULL);
   SetIndexLabel(MODE_EMA_2, NULL);
   IndicatorDigits(SubPipDigits);


   // (4) drawing options and styles
   int startDraw = 0;
   if (Max.Values >= 0) startDraw = Bars - Max.Values;
   if (startDraw  <  0) startDraw = 0;
   SetIndexDrawBegin(MODE_TEMA, startDraw);
   SetIndicatorOptions();

   return(catch("onInit(7)"));
}


/**
 * Deinitialization
 *
 * @return int - error status
 */
int onDeinit() {
   DeleteRegisteredObjects(NULL);
   RepositionLegend();
   return(catch("onDeinit(1)"));
}


/**
 * Called before recompilation.
 *
 * @return int - error status
 */
int onDeinitRecompile() {
   StoreInputParameters();
   return(last_error);
}


/**
 * Main function
 *
 * @return int - error status
 */
int onTick() {
   // check for finished buffer initialization (needed on terminal start)
   if (!ArraySize(tema))
      return(log("onTick(1)  size(tema) = 0", SetLastError(ERS_TERMINAL_NOT_YET_READY)));

   // reset all buffers and delete garbage behind Max.Values before doing a full recalculation
   if (!UnchangedBars) {
      ArrayInitialize(tema,      EMPTY_VALUE);
      ArrayInitialize(firstEma,  EMPTY_VALUE);
      ArrayInitialize(secondEma, EMPTY_VALUE);
      SetIndicatorOptions();
   }

   // synchronize buffers with a shifted offline chart
   if (ShiftedBars > 0) {
      ShiftIndicatorBuffer(tema,      Bars, ShiftedBars, EMPTY_VALUE);
      ShiftIndicatorBuffer(firstEma,  Bars, ShiftedBars, EMPTY_VALUE);
      ShiftIndicatorBuffer(secondEma, Bars, ShiftedBars, EMPTY_VALUE);
   }


   // (1) calculate start bar
   int changedBars = ChangedBars;
   if (Max.Values >= 0) /*&&*/ if (Max.Values < ChangedBars)
      changedBars = Max.Values;                                      // Because EMA(EMA(EMA)) is used in the calculation, TEMA needs 3*<period>-2 samples
   int bar, startBar = Min(changedBars-1, Bars - (3*MA.Periods-2));  // to start producing values in contrast to <period> samples needed by a regular EMA.
   if (startBar < 0) return(catch("onTick(2)", ERR_HISTORY_INSUFFICIENT));


   // (2) recalculate changed bars
   double thirdEma;
   for (bar=ChangedBars-1; bar >= 0; bar--)   firstEma [bar] =        iMA(NULL,      NULL,        MA.Periods, 0, MODE_EMA, ma.appliedPrice, bar);
   for (bar=ChangedBars-1; bar >= 0; bar--)   secondEma[bar] = iMAOnArray(firstEma,  WHOLE_ARRAY, MA.Periods, 0, MODE_EMA,                  bar);
   for (bar=startBar;      bar >= 0; bar--) { thirdEma       = iMAOnArray(secondEma, WHOLE_ARRAY, MA.Periods, 0, MODE_EMA,                  bar);
      tema[bar] = 3*firstEma[bar] - 3*secondEma[bar] + thirdEma;
   }


   // (3) update chart legend
   if (!IsSuperContext()) {
       @Trend.UpdateLegend(legendLabel, ma.name, "", MA.Color, MA.Color, tema[0], NULL, Time[0]);
   }
   return(last_error);
}


/**
 * Workaround for various terminal bugs when setting indicator options. Usually options are set in init(). However after
 * recompilation options must be set in start() to not get ignored.
 */
void SetIndicatorOptions() {
   IndicatorBuffers(allocated_buffers);

   int drawWidth = ifInt(draw.type==DRAW_ARROW, draw.arrowSize, Draw.LineWidth);
   int drawType  = ifInt(draw.type==DRAW_ARROW, DRAW_ARROW, ifInt(Draw.LineWidth, DRAW_LINE, DRAW_NONE));

   SetIndexStyle(MODE_TEMA, drawType, EMPTY, drawWidth, MA.Color); SetIndexArrow(MODE_TEMA, 159);
}


/**
 * Store input parameters in the chart before recompilation.
 *
 * @return bool - success status
 */
bool StoreInputParameters() {
   string name = __NAME();
   Chart.StoreInt   (name +".input.MA.Periods",      MA.Periods     );
   Chart.StoreString(name +".input.MA.AppliedPrice", MA.AppliedPrice);
   Chart.StoreColor (name +".input.MA.Color",        MA.Color       );
   Chart.StoreString(name +".input.Draw.Type",       Draw.Type      );
   Chart.StoreInt   (name +".input.Draw.LineWidth",  Draw.LineWidth );
   Chart.StoreInt   (name +".input.Max.Values",      Max.Values     );
   return(!catch("StoreInputParameters(1)"));
}


/**
 * Restore input parameters found in the chart after recompilation.
 *
 * @return bool - success status
 */
bool RestoreInputParameters() {
   string name = __NAME();
   Chart.RestoreInt   (name +".input.MA.Periods",      MA.Periods     );
   Chart.RestoreString(name +".input.MA.AppliedPrice", MA.AppliedPrice);
   Chart.RestoreColor (name +".input.MA.Color",        MA.Color       );
   Chart.RestoreString(name +".input.Draw.Type",       Draw.Type      );
   Chart.RestoreInt   (name +".input.Draw.LineWidth",  Draw.LineWidth );
   Chart.RestoreInt   (name +".input.Max.Values",      Max.Values     );
   return(!catch("RestoreInputParameters(1)"));
}


/**
 * Return a string representation of the input parameters (for logging purposes).
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("MA.Periods=",      MA.Periods,                      ";", NL,
                            "MA.AppliedPrice=", DoubleQuoteStr(MA.AppliedPrice), ";", NL,
                            "MA.Color=",        ColorToStr(MA.Color),            ";", NL,

                            "Draw.Type=",       DoubleQuoteStr(Draw.Type),       ";", NL,
                            "Draw.LineWidth=",  Draw.LineWidth,                  ";", NL,

                            "Max.Values=",      Max.Values,                      ";")
   );
}
