/**
 * Zeigt die Soll-StopLoss- und -TakeProfit-Level einer imagin�ren oder realen Position an.
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <core/script.mqh>
#include <stdfunctions.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onStart() {
   return(last_error);
}