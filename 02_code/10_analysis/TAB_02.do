/*******************************************************************************
 TAB_02.do -- TAB step: independent re-estimation of Table A2 "UB own support" (upper-bound basket).
 UB trade = LB trade + ambiguous pre-HS2007 recorded-media pool (v_ttl_k + v_8523_amb_k, defined where
 v_ttl_k is observed). Purpose: positive control that the stored UB outputs (PKG/COPY UB baseline-key-results.csv)
 are reproduced on prepared.dta in both vintages; the table uses the stored values.
 Help: ppmlhdfe.sthlp (e(converged), e(N_full), e(num_singletons), e(num_separated)), [R] lincom.
 Usage (cwd = 02_code/10_analysis):  "$STATA" -b -q do TAB_02.do <vintage>
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
capture log close _all
log using "${OUT}/TAB_02_${VINTAGE}.log", text replace
use "${PREPARED}" if has_both_vis == 1 | has_both_tour == 1, clear
nflow start using "${OUT}/TAB_nflow.csv", append
nflow step "TAB_02: keep rows with strict bilateral visitors or tourists"
gen double v_ub_k = v_ttl_k + v_8523_amb_k if !missing(v_ttl_k)
quietly count if missing(v_8523_amb_k) & !missing(v_ttl_k)
display as result "TAB_UB_AMB_MISSING_WHERE_TRADE_OBSERVED=" r(N)
foreach m in vis tour {
    quietly ppmlhdfe v_ub_k mob_bilat_`m' if has_both_`m', absorb(exporter_year importer_year pair_id) vce(cluster pair_id)
    assert e(converged) == 1
    assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
    nflow est "TAB_02 UB own support `m'"
    display as result "TAB_UB `m' b=" %14.9f _b[mob_bilat_`m'] " se=" %14.9f _se[mob_bilat_`m'] " N=" e(N) " N_full=" e(N_full) " singletons=" e(num_singletons) " separated=" e(num_separated)
}
log close
exit, clear
