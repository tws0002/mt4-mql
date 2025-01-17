/**
 * SuperBars Down
 *
 * Send the SuperBars indicator a command to switch to the next lower SuperBars timeframe.
 */
#include <stddefines.mqh>
int   __INIT_FLAGS__[] = {INIT_NO_BARS_REQUIRED};
int __DEINIT_FLAGS__[];
#include <core/script.mqh>
#include <stdfunctions.mqh>


/**
 * Main function
 *
 * @return int - error status
 */
int onStart() {
   SendChartCommand("SuperBars.command", "Timeframe=Down");
   return(catch("onStart(1)"));
}
