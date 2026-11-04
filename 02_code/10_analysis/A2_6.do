/*******************************************************************************
 A2_6.do -- item A2.6 product basket (R1.6b,c; R2.7).
 Outcomes (thousand USD, importer-reported, LB = ambiguous pre-HS2007 recorded-media pool
 excluded; definitions in PREP 01_prep.do part C and prepared_variables.csv labels):
   v_unesco_a  UNESCO FCS2009-consistent narrow basket A (22 HS2007 codes, no 8523)
   v_unesco_b  basket B = A + 852329 + 852380 (24 codes)
   v_nomedia   v_ttl_k - v_8523_k (no recorded media at all; generated here, = v_3706+v_49+v_97)
 For each outcome: baseline model on s_base_* (N changes from new always-zero/separated pairs);
 identical observations with v_ttl_k (fixed point) and stacked test baseline basket = narrow
 basket (block-specific FE, a2_stack). Value shares of v_8523_k and of each narrow basket.
 Recorded media "exact" row of Table A5: File S1 run_T6.do:44-48 on v_8523_exact==1
 (build_products.py:230). Help: ppmlhdfe.sthlp, [R] test, [R] summarize.
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
do "A2_00_programs.do"
capture log close _all
log using "${LOGS}/A2_6_${VINTAGE}.log", text replace
display as result "A2_6_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
use "${OUT}/A2_work.dta", clear
nflow start using "${OUT}/A2_nflow.csv", append
a2_open "${OUT}/results/A2_6.dta"
a2_topen "${OUT}/tables/A2_A2.6.dta"
local FE "exporter_year importer_year pair_id"

gen double v_nomedia = v_ttl_k - v_8523_k if !missing(v_ttl_k, v_8523_k)
label variable v_nomedia "Cultural trade without recorded media: v_ttl_k - v_8523_k (1000 USD)"
gen double __chk = abs(v_nomedia - (v_3706_k + v_49_k + v_97_k))
quietly summarize __chk
display as result "A2_6_NOMEDIA_IDENTITY max|v_ttl-v_8523-(v_3706+v_49+v_97)| = " r(max)
assert r(max) < 1e-6
drop __chk
quietly count if v_nomedia < 0
assert r(N) == 0

preserve
    import delimited using "${OUT}/positive_controls.csv", clear asdouble varnames(1) stringcols(1)
    quietly summarize reproduced if item == "SHR.v_8523_k.visitor"
    local pc_sh_vis = r(mean)
    quietly summarize reproduced if item == "SHR.v_8523_k.tourist"
    local pc_sh_tour = r(mean)
restore

foreach m in vis tour {
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    local smp "s_base_`m'"
    quietly summarize v_ttl_k if `smp', meanonly
    local tot = r(sum)
    foreach y in v_8523_k v_unesco_a v_unesco_b v_nomedia v_3706_k v_49_k v_97_k {
        quietly summarize `y' if `smp', meanonly
        a2_tpost, item(A2.6) table(value_share) sample(`smp') mobility(`mlab') stat(share_`y'_pct) value(`=100*r(sum)/`tot'') n(`r(N)') note("100 * sum(`y') / sum(v_ttl_k) over the baseline sample")
    }
    quietly summarize v_8523_k if `smp', meanonly
    local sh8523 = 100 * r(sum) / `tot'
    display as result "A2_6_SHARE_8523 `m' = " %10.6f `sh8523' " ref " %10.6f `pc_sh_`m''
    assert abs(`sh8523' - `pc_sh_`m'') < 1e-5

    quietly ppmlhdfe v_ttl_k mob_bilat_`m' if `smp', absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.6 baseline v_ttl_k `mlab'"
    a2_post, item(A2.6) spec(baseline_v_ttl_k) sample(`smp') mobility(`mlab') term(mob_bilat_`m') label(all cultural goods (baseline))
    local k = 0
    foreach y in v_unesco_a v_unesco_b v_nomedia {
        local ++k
        local yl : variable label `y'
        * (1) baseline model on the baseline sample with the new outcome
        quietly count if `smp' & !missing(`y')
        local nc = r(N)
        quietly ppmlhdfe `y' mob_bilat_`m' if `smp', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.6 `y' on baseline sample `mlab'"
        a2_post, item(A2.6) spec(`y'_on_baseline_sample) sample(`smp') mobility(`mlab') term(mob_bilat_`m') label(`y') note("candidate rows `nc' of the baseline sample; drops = singletons `e(num_singletons)' (incl. pairs whose new outcome is always zero) + separated `e(num_separated)'")
        * (2) identical observations and stacked test
        gen byte id_`k'_`m' = `smp' & !missing(`y')
        a2_fix, touse(id_`k'_`m') models("v_ttl_k mob_bilat_`m' ; `y' mob_bilat_`m'")
        local it = ${A2_FIX_IT}
        preserve
        a2_stack, touse(id_`k'_`m') ys(v_ttl_k `y') xs("mob_bilat_`m' ; mob_bilat_`m'") cluster(pair_id)
        local nu = ${A2_NUNIQ}
        a2_post, item(A2.6) spec(`y'_identical_rows) sample(`smp' & common) mobility(`mlab') term(s1_1) label(all cultural goods) nuniq(`nu') note("fixed-point iterations `it'")
        a2_post, item(A2.6) spec(`y'_identical_rows) sample(`smp' & common) mobility(`mlab') term(s2_1) label(`y') nuniq(`nu')
        a2_post, item(A2.6) spec(`y'_identical_rows) sample(`smp' & common) mobility(`mlab') term(s1_1 - s2_1) label(all - narrow) nuniq(`nu')
        quietly test s1_1 = s2_1
        a2_posttest, item(A2.6) spec(`y'_identical_rows) sample(`smp' & common) mobility(`mlab') label(test all = narrow) chi2(`r(chi2)') df(`r(df)') p(`r(p)') nuniq(`nu')
        display as result "A2_6 `m' `y' N=`nu' all=" %9.6f _b[s1_1] " narrow=" %9.6f _b[s2_1]
        restore
        nflow step "restore: after A2.6 `y' `mlab' stacked test"
    }

    * ---------------- recorded media: Table 4 row vs Table A5 "exact" row
    quietly ppmlhdfe v_8523_k mob_bilat_`m', absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.6 Table 4 recorded media `mlab'"
    gen byte t4_`m' = e(sample)
    a2_post, item(A2.6) spec(recmedia_table4) sample(all rows (Table 4)) mobility(`mlab') term(mob_bilat_`m') label(v_8523_k, Table 4) note("06_table4_categories.do:15,17")
    local n4 = e(N)
    quietly ppmlhdfe v_8523_k mob_bilat_`m' if has_both_`m' & v_8523_exact == 1, absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.6 Table A5 exact recorded media `mlab'"
    gen byte t5_`m' = e(sample)
    a2_post, item(A2.6) spec(recmedia_exact_tableA5) sample(has_both & v_8523_exact==1) mobility(`mlab') term(mob_bilat_`m') label(v_8523_k on v_8523_exact==1) note("File S1 run_T6.do:45-46")
    local n5 = e(N)
    quietly count if t4_`m' & v_8523_exact == 0
    local nx = r(N)
    a2_tpost, item(A2.6) table(recmedia_exact) sample(Table 4 recorded-media sample) mobility(`mlab') stat(rows_v8523_exact_0) value(`nx') n(`n4') note("pair-years whose importer reported part of 8523 in ambiguous pre-HS2007 codes (ambiguous pool > 0)")
    quietly count if t4_`m' & v_8523_exact == 1 & !t5_`m'
    a2_tpost, item(A2.6) table(recmedia_exact) sample(Table 4 recorded-media sample) mobility(`mlab') stat(rows_exact_but_dropped_by_refit) value(`r(N)') n(`n4') note("exact rows lost as new singletons/separated after the restriction")
    quietly count if t5_`m' & !t4_`m'
    a2_tpost, item(A2.6) table(recmedia_exact) sample(Table A5 exact sample) mobility(`mlab') stat(rows_in_exact_not_in_table4) value(`r(N)') n(`n5')
    quietly summarize v_8523_amb_k if t4_`m' & v_8523_exact == 0
    a2_tpost, item(A2.6) table(recmedia_exact) sample(Table 4 recorded-media sample) mobility(`mlab') stat(sum_ambiguous_pool_k_on_inexact_rows) value(`=r(sum)') n(`r(N)') note("sum of the excluded ambiguous pool (1000 USD) on those rows; not part of v_8523_k (LB)")
    display as result "A2_6_RECMEDIA `m' table4 N=`n4' exact N=`n5' inexact rows=`nx'"
}
a2_close "${OUT}/results/A2_6.dta" "${OUT}/results/A2_6.csv"
a2_tclose "${OUT}/tables/A2_A2.6.dta" "${OUT}/tables/A2_A2.6.csv"
display as result "A2_6_DONE vintage=${VINTAGE} " c(current_time)
log close
