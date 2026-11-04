/*******************************************************************************
 FIG_01_new_checks.do  --  two checks of the coefficient plot (R2.14) that have no stored
 corrected-vintage estimate: (a) bilateral baseline clustered by unordered country pair,
 (b) baseline without pair-years above the 99.9th percentile of directional mobility.
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do FIG_01_new_checks.do <vintage>
 Input : ${PREPARED} (read only).  Output: ${OUT}/FIG_new_checks.csv, ${OUT}/FIG_nflow.csv.
 Original code: File S1 run_tests.do:243-247 (T8, vce(cluster unordered_pair_id)) and
 run_tests.do:285-307 (T11 directional: separate 99.9th-percentile cutoffs for the reverse
 and same-direction raw flows computed on has_both & !missing(v_ttl_k); drop if either
 exceeds its cutoff), estimator ppmlhdfe with absorb(exporter_year importer_year pair_id).
 Help files consulted (installed): ppmlhdfe.sthlp 2.3.4 (absorb(), vce(cluster), e(N_full),
 e(num_singletons), e(num_separated), e(converged)); [D] pctile (_pctile, p(99.9));
 [P] postfile; nflow.sthlp 1.0.1.
 Positive control (submitted vintage only): File S1 estimates.csv rows T8 and T11
 (= submitted manuscript Table 6 text and Table 7 Panel B): asserted to 1e-5 below.
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
log using "${LOGS}/FIG_01_new_checks_${VINTAGE}.log", text replace
display as result "FIG_01_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)

global FE "exporter_year importer_year pair_id"

use year iso3_o iso3_d v_ttl_k has_both_vis has_both_tour mob_bilat_vis mob_bilat_tour ///
    rev_vis_raw same_vis_raw rev_tour_raw same_tour_raw ///
    exporter_year importer_year pair_id unordered_pair_id using "${PREPARED}", clear
nflow start using "${OUT}/FIG_nflow.csv", replace expected(823446)

tempname H
postfile `H' str10 vintage str24 check str5 mobility double(b se ci_lo ci_hi N N_full n_singletons n_separated n_clusters) ///
    str20 cluster_var double(cutoff_rev cutoff_same n_candidate_excluded) str200 note using "${OUT}/FIG_new_checks.dta", replace

* positive-control targets (submitted vintage): File S1 estimates.csv
local pc_unord_vis_b  0.24287017
local pc_unord_vis_se 0.091529384
local pc_unord_vis_N  20543
local pc_unord_tour_b  0.24048044
local pc_unord_tour_se 0.065553479
local pc_unord_tour_N  26682
local pc_trim_vis_b  0.12063225
local pc_trim_vis_se 0.070991881
local pc_trim_vis_N  20509
local pc_trim_tour_b  0.22182305
local pc_trim_tour_se 0.073281154
local pc_trim_tour_N  26626

foreach m in vis tour {
    * ---------------- (a) unordered-pair clusters
    ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m', absorb($FE) vce(cluster unordered_pair_id)
    assert e(converged) == 1
    assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
    local b = _b[mob_bilat_`m']
    local se = _se[mob_bilat_`m']
    post `H' ("${VINTAGE}") ("unordered_pair_clusters") ("`m'") (`b') (`se') ///
        (`b' - invnormal(0.975) * `se') (`b' + invnormal(0.975) * `se') (e(N)) (e(N_full)) ///
        (e(num_singletons)) (e(num_separated)) (e(N_clust)) ("`e(clustvar)'") (.) (.) (.) ("")
    nflow est "FIG unordered-pair clusters `m'"
    display as result "FIG_FIT unordered `m' b=" %12.9f `b' " se=" %12.9f `se' " N=" e(N) " clusters=" e(N_clust)
    if "${VINTAGE}" == "submitted" {
        assert abs(`b' - `pc_unord_`m'_b') < 1e-5
        assert abs(`se' - `pc_unord_`m'_se') < 1e-5
        assert e(N) == `pc_unord_`m'_N'
        display as result "FIG_PC_PASS unordered `m'"
    }

    * ---------------- (b) top 0.1% directional mobility values (File S1 T11, directional)
    quietly _pctile rev_`m'_raw if has_both_`m' & !missing(v_ttl_k), p(99.9)
    local cut_rev = r(r1)
    quietly _pctile same_`m'_raw if has_both_`m' & !missing(v_ttl_k), p(99.9)
    local cut_same = r(r1)
    tempvar trimmed
    gen byte `trimmed' = has_both_`m' & !missing(v_ttl_k) & (rev_`m'_raw > `cut_rev' | same_`m'_raw > `cut_same')
    quietly count if `trimmed'
    local drop_n = r(N)
    ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & !`trimmed', absorb($FE) vce(cluster pair_id)
    assert e(converged) == 1
    assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
    local b = _b[mob_bilat_`m']
    local se = _se[mob_bilat_`m']
    post `H' ("${VINTAGE}") ("trim_top0.1pct_directional") ("`m'") (`b') (`se') ///
        (`b' - invnormal(0.975) * `se') (`b' + invnormal(0.975) * `se') (e(N)) (e(N_full)) ///
        (e(num_singletons)) (e(num_separated)) (e(N_clust)) ("`e(clustvar)'") (`cut_rev') (`cut_same') (`drop_n') ///
        ("candidate pair-years dropped (above 99.9th pct of reverse or same-direction raw flow)")
    nflow est "FIG trim top 0.1pct directional `m'"
    display as result "FIG_FIT trim `m' b=" %12.9f `b' " se=" %12.9f `se' " N=" e(N) " cutoffs=" `cut_rev' " " `cut_same' " candidate_excl=" `drop_n'
    if "${VINTAGE}" == "submitted" {
        assert abs(`b' - `pc_trim_`m'_b') < 1e-5
        assert abs(`se' - `pc_trim_`m'_se') < 1e-5
        assert e(N) == `pc_trim_`m'_N'
        display as result "FIG_PC_PASS trim `m'"
    }
    drop `trimmed'
}
postclose `H'
use "${OUT}/FIG_new_checks.dta", clear
format b se ci_lo ci_hi %24.17g
export delimited using "${OUT}/FIG_new_checks.csv", replace datafmt
display as result "FIG_01_DONE " c(current_date) " " c(current_time)
log close
