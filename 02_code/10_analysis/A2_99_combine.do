/*******************************************************************************
 A2_99_combine.do -- block-level results file out/<vintage>/results/A2.csv
 (the shared analysis conventions: one CSV per block) = the item files A2_1 ... A2_7 appended.
*******************************************************************************/
args vintage
clear all
set more off
version 18.0
do "00_config.do" `vintage'
version 18.0
capture log close _all
log using "${LOGS}/A2_99_combine_${VINTAGE}.log", text replace
use "${OUT}/results/A2_1.dta", clear
forvalues k = 2/7 {
    append using "${OUT}/results/A2_`k'.dta"
}
* rerun C2: item A2.7b (A2_7b.do) is appended when it has been run for this vintage
capture confirm file "${OUT}/results/A2_7b.dta"
if _rc == 0 append using "${OUT}/results/A2_7b.dta"
format b se p ci_lo ci_hi N N_full n_singletons n_separated n_clusters %24.17g
export delimited using "${OUT}/results/A2.csv", datafmt replace
count
display as result "A2_COMBINE_DONE vintage=${VINTAGE} rows=" _N
log close
