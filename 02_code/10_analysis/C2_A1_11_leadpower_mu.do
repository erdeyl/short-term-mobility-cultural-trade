/*******************************************************************************
 C2_A1_11_leadpower_mu.do -- rerun C2, revision round 2 item 3.3.
 Lead-test power and lead-interval ratios of Table S9.3 with directed-pair trends, recomputed from the
 final separation(fe simplex ir mu) fits (A1.8.T7_pair_sepmu: N 13,565 visitors / 18,868 tourists)
 instead of the default-separation fits (A1.8.T7_pair: N 13,579 / 19,061) used by A1_03_time.do:236-280.
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do C2_A1_11_leadpower_mu.do corrected2x
 Output: ${OUT}/tables/A1_A1.7_lead_power_mu.csv (new rows, trend = pair_mu; sibling of A1_A1.7_lead_power.csv,
         which is not touched), ${OUT}/tables/A1_A1.7_lead_power_mu_check.csv (default-separation rows
         recomputed by this file, for the control against the existing pair rows), nflow sidecar
         ${OUT}/C2_A1_11_nflow.csv, log. No results/A1.csv row is written (results are frozen).
 Same formulas as A1_03_time.do:221-224 and 270-276: power = normal(d/se - z) + normal(-d/se - z),
 z = invnormal(1 - alpha/2), d = |share x reference|; 90% lead interval = b_lead -/+ invnormal(0.95) se_lead,
 divided by the reference. References as in A1_03_time.do:264-269: static_same_sample = static model
 (mob_bilat only) with pair trends on the e(sample) of the dynamic trend fit (the "same-sample static
 coefficient" of Table S9.3), current_in_T3 = current coefficient of the dynamic trend fit. Here both fits
 use separation(fe simplex ir mu), as the A1_trendsep refit (A1_03_time.do:130).
 Controls: (1) the dynamic mu fit reproduces A1.8.T7_pair_sepmu b/se/N (checked against results/A1.csv by
 C2_A1_11_check.py); (2) the default block recomputed here reproduces every trend = pair row of
 A1_A1.7_lead_power.csv (same check script).
 Help consulted: ppmlhdfe.sthlp 2.3.4 (separation(string): "Valid options are fe, ir, simplex, and mu (or any
 combination of those)"; e(N), e(num_separated), e(converged), e(sample)); [FN] normal(), invnormal();
 [P] postfile; nflow.sthlp. No data value is altered.
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
log using "${LOGS}/C2_A1_11_leadpower_mu_${VINTAGE}.log", text replace
display as result "C2_A1_11_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
use year v_ttl_k mob_bilat_vis mob_bilat_tour lag_bilat_vis lead_bilat_vis lag_bilat_tour lead_bilat_tour ///
    exporter_year importer_year pair_id using "${PREPARED}", clear
nflow start using "${OUT}/C2_A1_11_nflow.csv", replace expected(823446)
gen double time_c = year - 2007
local FET "exporter_year importer_year pair_id##c.time_c"

capture program drop c2_lp_post
program define c2_lp_post
    * posts the 8 rows of one reference (2 shares x 2 levels) with the formulas of A1_03_time.do:270-276
    args handle m trend ref blead slead br nt nref sep
    foreach sh in 0.5 1 {
        foreach a in 0.05 0.10 {
            local z = invnormal(1 - `a' / 2)
            local d = abs(`sh' * `br')
            local pw = normal(`d' / `slead' - `z') + normal(-`d' / `slead' - `z')
            local lo = `blead' - invnormal(0.95) * `slead'
            local hi = `blead' + invnormal(0.95) * `slead'
            local id = "A1.7.lead_power_`trend'.`m'.`ref'.d`sh'.a`a'"
            post `handle' ("`id'") ("`m'") ("`trend'") ("`ref'") (`blead') (`slead') (`br') (`sh') (`d') (`a') (`z') (`pw') ///
                (`lo') (`hi') (`lo' / `br') (`hi' / `br') (`nt') (`nref') ("`sep'")
        }
    }
end

tempname LP CK
postfile `LP' str60 row_id str5 mobility str10 trend str20 reference double(b_lead se_lead b_ref d_share d alpha z power ///
    ci90_lo ci90_hi ci90_lo_share ci90_hi_share N N_ref) str24 separation using "${OUT}/tables/A1_A1.7_lead_power_mu.dta", replace
postfile `CK' str60 row_id str5 mobility str10 trend str20 reference double(b_lead se_lead b_ref d_share d alpha z power ///
    ci90_lo ci90_hi ci90_lo_share ci90_hi_share N N_ref) str24 separation using "${OUT}/tables/A1_A1.7_lead_power_mu_check.dta", replace
foreach m in vis tour {
    local X "lag_bilat_`m' mob_bilat_`m' lead_bilat_`m'"
    * ---- (A) control: default-separation block exactly as A1_03_time.do:240-279
    ppmlhdfe v_ttl_k `X', absorb(`FET') vce(cluster pair_id)
    assert e(converged) == 1
    nflow est "C2_A1_11 `m' dynamic pair-trend fit, default separation (control = A1.8.T7_pair)"
    gen byte __d1 = e(sample)
    local blead = _b[lead_bilat_`m']
    local slead = _se[lead_bilat_`m']
    local bcur = _b[mob_bilat_`m']
    local nt = e(N)
    ppmlhdfe v_ttl_k mob_bilat_`m' if __d1, absorb(`FET') vce(cluster pair_id)
    assert e(converged) == 1
    nflow est "C2_A1_11 `m' static pair-trend fit on the default dynamic sample (control = A1.7.static_on_dyn_pairtrend)"
    local bstat = _b[mob_bilat_`m']
    local nst = e(N)
    display as result "C2_A1_11_DEFAULT `m' N_dyn=`nt' N_static=`nst' b_lead=" %12.9f `blead' " se_lead=" %12.9f `slead' " b_static=" %12.9f `bstat'
    c2_lp_post `CK' `m' pair static_same_sample `blead' `slead' `bstat' `nt' `nst' default
    c2_lp_post `CK' `m' pair current_in_T3 `blead' `slead' `bcur' `nt' `nt' default
    drop __d1
    * ---- (B) final: separation(fe simplex ir mu), as A1_trendsep (A1_03_time.do:130)
    ppmlhdfe v_ttl_k `X', absorb(`FET') vce(cluster pair_id) separation(fe simplex ir mu)
    assert e(converged) == 1
    assert e(N) == cond("`m'" == "vis", 13565, 18868)
    nflow est "C2_A1_11 `m' dynamic pair-trend fit, separation(fe simplex ir mu) (= A1.8.T7_pair_sepmu)"
    gen byte __m1 = e(sample)
    local blead = _b[lead_bilat_`m']
    local slead = _se[lead_bilat_`m']
    local bcur = _b[mob_bilat_`m']
    local nt = e(N)
    local nsep = e(num_separated)
    display as result "C2_A1_11_MU_DYN `m' N=`nt' separated=`nsep' b_lag=" %12.9f _b[lag_bilat_`m'] " b_cur=" %12.9f `bcur' ///
        " b_lead=" %12.9f `blead' " se_lead=" %12.9f `slead'
    ppmlhdfe v_ttl_k mob_bilat_`m' if __m1, absorb(`FET') vce(cluster pair_id) separation(fe simplex ir mu)
    assert e(converged) == 1
    nflow est "C2_A1_11 `m' static pair-trend fit on the mu dynamic sample (reference static_same_sample)"
    local bstat = _b[mob_bilat_`m']
    local sstat = _se[mob_bilat_`m']
    local nst = e(N)
    display as result "C2_A1_11_MU_STATIC `m' N=`nst' separated=" e(num_separated) " singletons=" e(num_singletons) ///
        " b_static=" %12.9f `bstat' " se=" %12.9f `sstat'
    c2_lp_post `LP' `m' pair_mu static_same_sample `blead' `slead' `bstat' `nt' `nst' "fe simplex ir mu"
    c2_lp_post `LP' `m' pair_mu current_in_T3 `blead' `slead' `bcur' `nt' `nt' "fe simplex ir mu"
    drop __m1
}
postclose `LP'
postclose `CK'
foreach f in A1_A1.7_lead_power_mu A1_A1.7_lead_power_mu_check {
    use "${OUT}/tables/`f'.dta", clear
    gen str10 vintage = "${VINTAGE}"
    order vintage
    export delimited using "${OUT}/tables/`f'.csv", replace
    erase "${OUT}/tables/`f'.dta"
}
nflow report
display as result "C2_A1_11_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
exit, clear
