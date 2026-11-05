/*******************************************************************************
 C2_A1_11b_common_sample.do -- common-sample check of the trend-model references of Table S9.3.
 Check of Table S9.3: the static reference fit with directed-pair trends (C2_A1_11_leadpower_mu.do:98)
 retains 13,564 visitor and 18,865 tourist observations of the 13,565 / 18,868 of the dynamic trend fit.
 This file refits the dynamic trend model on the static fit's own sample, so that both models use the
 same observations, and lists the removed observations by identifier only (pair_id, year, zero trade).
 Usage (cwd = the analysis code folder):  stata-mp -b -q do C2_A1_11b_common_sample.do corrected2x
 Output: ${OUT}/tables/A1_A1.7_common_sample_check.csv, nflow sidecar ${OUT}/C2_A1_11b_nflow.csv, log.
 No results/A1.csv row is written (results are frozen); no data value is altered or listed.
 Help consulted: ppmlhdfe.sthlp 2.3.4 (separation(string): "Valid options are fe, ir, simplex, and mu (or any
 combination of those)"; e(N), e(num_separated), e(num_singletons), e(converged), e(sample));
 [P] postfile; [D] list; nflow.sthlp.
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
assert "${VINTAGE}" == "corrected2x"
capture log close _all
log using "${LOGS}/C2_A1_11b_common_sample_${VINTAGE}.log", text replace
display as result "C2_A1_11b_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
use year v_ttl_k mob_bilat_vis mob_bilat_tour lag_bilat_vis lead_bilat_vis lag_bilat_tour lead_bilat_tour ///
    exporter_year importer_year pair_id using "${PREPARED}", clear
nflow start using "${OUT}/C2_A1_11b_nflow.csv", replace expected(823446)
gen double time_c = year - 2007
local FET "exporter_year importer_year pair_id##c.time_c"

tempname CS
postfile `CS' str5 mobility str40 model double(N n_separated n_singletons b_lag se_lag b_cur se_cur b_lead se_lead) ///
    using "${OUT}/tables/A1_A1.7_common_sample_check.dta", replace
foreach m in vis tour {
    local X "lag_bilat_`m' mob_bilat_`m' lead_bilat_`m'"
    * ---- (1) dynamic trend fit as in C2_A1_11_leadpower_mu.do:86 (= A1.8.T7_pair_sepmu)
    ppmlhdfe v_ttl_k `X', absorb(`FET') vce(cluster pair_id) separation(fe simplex ir mu)
    assert e(converged) == 1
    assert e(N) == cond("`m'" == "vis", 13565, 18868)
    nflow est "C2_A1_11b `m' dynamic pair-trend fit, separation(fe simplex ir mu) (= A1.8.T7_pair_sepmu)"
    gen byte __m1 = e(sample)
    post `CS' ("`m'") ("dynamic, own sample") (e(N)) (e(num_separated)) (e(num_singletons)) ///
        (_b[lag_bilat_`m']) (_se[lag_bilat_`m']) (_b[mob_bilat_`m']) (_se[mob_bilat_`m']) (_b[lead_bilat_`m']) (_se[lead_bilat_`m'])
    * ---- (2) static reference fit on the dynamic sample, as in C2_A1_11_leadpower_mu.do:98
    ppmlhdfe v_ttl_k mob_bilat_`m' if __m1, absorb(`FET') vce(cluster pair_id) separation(fe simplex ir mu)
    assert e(converged) == 1
    assert e(N) == cond("`m'" == "vis", 13564, 18865)
    nflow est "C2_A1_11b `m' static pair-trend fit on the dynamic sample (Table S9.3 reference)"
    gen byte __s1 = e(sample)
    post `CS' ("`m'") ("static, on dynamic sample") (e(N)) (e(num_separated)) (e(num_singletons)) ///
        (.) (.) (_b[mob_bilat_`m']) (_se[mob_bilat_`m']) (.) (.)
    * ---- (3) the observations the static fit removes: identifiers and zero-trade indicator only
    gen byte __zero = (v_ttl_k == 0) if __m1 & !__s1
    display as result "C2_A1_11b_REMOVED `m'"
    list pair_id year __zero if __m1 & !__s1, noobs clean
    * ---- (4) dynamic trend fit on the static fit's sample (common sample)
    ppmlhdfe v_ttl_k `X' if __s1, absorb(`FET') vce(cluster pair_id) separation(fe simplex ir mu)
    assert e(converged) == 1
    nflow est "C2_A1_11b `m' dynamic pair-trend fit on the static reference sample (common sample)"
    post `CS' ("`m'") ("dynamic, on static sample") (e(N)) (e(num_separated)) (e(num_singletons)) ///
        (_b[lag_bilat_`m']) (_se[lag_bilat_`m']) (_b[mob_bilat_`m']) (_se[mob_bilat_`m']) (_b[lead_bilat_`m']) (_se[lead_bilat_`m'])
    display as result "C2_A1_11b_COMMON `m' N=" e(N) " b_cur=" %12.9f _b[mob_bilat_`m'] " b_lead=" %12.9f _b[lead_bilat_`m'] ///
        " se_lead=" %12.9f _se[lead_bilat_`m']
    drop __m1 __s1 __zero
}
postclose `CS'
use "${OUT}/tables/A1_A1.7_common_sample_check.dta", clear
gen str12 vintage = "${VINTAGE}"
order vintage
export delimited using "${OUT}/tables/A1_A1.7_common_sample_check.csv", replace
erase "${OUT}/tables/A1_A1.7_common_sample_check.dta"
nflow report
display as result "C2_A1_11b_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
exit, clear
