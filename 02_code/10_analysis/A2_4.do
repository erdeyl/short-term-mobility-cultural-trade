/*******************************************************************************
 A2_4.do -- item A2.4 scales of the baseline coefficients; LPM effects; File S1 rows
 (R1.5d, R2.15, R1.5c).
 PPML: 100*b (local semi-elasticity per IHS unit), 100*(exp(b)-1) (finite change for a
 one-unit IHS increase), 100*(1.1^b-1) (10% more trips at large values, where
 asinh(1.1x) - asinh(x) ~ ln 1.1). SEs by the delta method ([R] nlcom); CIs = transformed
 endpoints of b's 95% CI (monotone transforms); p = p of H0: b = 0.
 LPM: Table A1 (CORE 09_tableA1_positive_trade.do:10-12, reghdfe) and the File S1 T2
 identical-sample fixed point (File S1 run_tests.do:56-84): pp = 100*b, relative = pp / share
 of positive trade on the estimation sample (share treated as fixed, as File S1).
 File S1 rows: T1 positive trade / positive in every year (run_tests.do:35-49),
 T9 fully reported (run_tests.do:250-261). Help: ppmlhdfe.sthlp, reghdfe.sthlp, [R] nlcom.
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
log using "${LOGS}/A2_4_${VINTAGE}.log", text replace
display as result "A2_4_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
use "${OUT}/A2_work.dta", clear
nflow start using "${OUT}/A2_nflow.csv", append
a2_open "${OUT}/results/A2_4.dta"
local FE "exporter_year importer_year pair_id"

capture program drop a2_scales
program define a2_scales
    * after a fit: post 100b, 100(exp(b)-1), 100(1.1^b-1) for coefficient `x'
    syntax, x(name) spec(string) sample(string) mobility(string)
    local N = e(N)
    local b = _b[`x']
    local se = _se[`x']
    local z = invnormal(0.975)
    local lo = `b' - `z' * `se'
    local hi = `b' + `z' * `se'
    local p = 2 * normal(-abs(`b' / `se'))
    a2_postval, item(A2.4) spec(`spec') sample(`sample') mobility(`mobility') label(100*b: % per IHS unit, local) value(`=100*`b'') se(`=100*`se'') p(`p') lo(`=100*`lo'') hi(`=100*`hi'') n(`N') note("local semi-elasticity per IHS unit")
    tempname V
    quietly nlcom 100 * (exp(_b[`x']) - 1)
    matrix `V' = r(V)
    local sef = sqrt(`V'[1,1])
    a2_postval, item(A2.4) spec(`spec') sample(`sample') mobility(`mobility') label(100*(exp(b)-1): % for +1 IHS unit) value(`=100*(exp(`b')-1)') se(`sef') p(`p') lo(`=100*(exp(`lo')-1)') hi(`=100*(exp(`hi')-1)') n(`N') note("finite change for a one-unit IHS increase (about a 172% increase in trips at large values, exp(1)-1); SE delta method; CI = transformed endpoints")
    quietly nlcom 100 * (1.1^_b[`x'] - 1)
    matrix `V' = r(V)
    local se10 = sqrt(`V'[1,1])
    a2_postval, item(A2.4) spec(`spec') sample(`sample') mobility(`mobility') label(100*(1.1^b-1): % for +10% trips) value(`=100*(1.1^`b'-1)') se(`se10') p(`p') lo(`=100*(1.1^`lo'-1)') hi(`=100*(1.1^`hi'-1)') n(`N') note("change in expected trade for a 10% increase in trips at large values (asinh(1.1x)-asinh(x) ~ ln 1.1); SE delta method")
end

foreach m in vis tour {
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    * ---------------- baseline PPML scales (Table 2 cols 1, 5)
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m', absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.4 baseline PPML `mlab'"
    a2_post, item(A2.4) spec(baseline_ppml) sample(has_both_`m') mobility(`mlab') term(mob_bilat_`m') label(b)
    a2_scales, x(mob_bilat_`m') spec(baseline_ppml) sample(has_both_`m') mobility(`mlab')

    * ---------------- Table A1 LPM (09_tableA1_positive_trade.do:10-12)
    quietly reghdfe positive_trade mob_bilat_`m', absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.4 Table A1 LPM `mlab'"
    gen byte eA1_`m' = e(sample)
    quietly summarize positive_trade if eA1_`m'
    local sh = r(mean)
    local nA1 = r(N)
    a2_post, item(A2.4) spec(tableA1_lpm) sample(Table A1 sample) mobility(`mlab') term(100*mob_bilat_`m') label(pp per IHS unit) note("LPM, reghdfe; positive-trade share on sample = `sh'")
    a2_post, item(A2.4) spec(tableA1_lpm) sample(Table A1 sample) mobility(`mlab') term((100/`sh')*mob_bilat_`m') label(relative % per IHS unit) note("pp / positive-trade share `sh' (share treated as fixed)")
    a2_postval, item(A2.4) spec(tableA1_lpm) sample(Table A1 sample) mobility(`mlab') label(positive-trade share) value(`sh') n(`nA1')
    display as result "A2_4_A1 `m' b=" %10.7f _b[mob_bilat_`m'] " N=" e(N) " r2_a=" %8.5f e(r2_a)
    local bA1 = _b[mob_bilat_`m']
    local nA1e = e(N)
    preserve
        import delimited using "${OUT}/positive_controls.csv", clear asdouble varnames(1) stringcols(1)
        local c = cond("`m'" == "vis", "c1.Bilateral visitors", "c2.Bilateral tourists")
        quietly summarize reproduced if item == "TA1.`c'.b"
        local refb = r(mean)
        local c = cond("`m'" == "vis", "c1", "c2")
        quietly summarize reproduced if item == "TA1.`c'.N.N"
        local refn = r(mean)
    restore
    display as result "A2_4_PC_A1 `m' b=" %12.10f `bA1' " ref=" %12.10f `refb' " N=`nA1e' ref=`refn'"
    assert abs(`bA1' - `refb') < 1e-9 & `nA1e' == `refn'

    * ---------------- File S1 T2 identical-sample fixed point (run_tests.do:56-84)
    gen byte mt_`m' = has_both_`m' & !missing(v_ttl_k)
    local it = 0
    local done = 0
    while `done' == 0 {
        local ++it
        if `it' > 10 error 430
        quietly count if mt_`m'
        local n0 = r(N)
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if mt_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.4 T2 fixed point PPML `mlab' iteration `it'"
        quietly replace mt_`m' = mt_`m' & e(sample)
        quietly reghdfe positive_trade mob_bilat_`m' if mt_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.4 T2 fixed point LPM `mlab' iteration `it'"
        quietly replace mt_`m' = mt_`m' & e(sample)
        quietly count if mt_`m'
        if r(N) == `n0' local done = 1
    }
    quietly summarize positive_trade if mt_`m'
    local pbar = r(mean)
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' if mt_`m', absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.4 T2 PPML on identical sample `mlab'"
    gen byte __e = e(sample)
    assert __e == mt_`m'
    drop __e
    a2_post, item(A2.4) spec(T2_same_sample_ppml) sample(T2 identical sample) mobility(`mlab') term(100*mob_bilat_`m') label(100*b: % per IHS unit) note("File S1 T2 row 'expected trade, % per IHS unit'; fixed-point iterations=`it'")
    a2_scales, x(mob_bilat_`m') spec(T2_same_sample_ppml) sample(T2 identical sample) mobility(`mlab')
    quietly reghdfe positive_trade mob_bilat_`m' if mt_`m', absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.4 T2 LPM on identical sample `mlab'"
    gen byte __e = e(sample)
    assert __e == mt_`m'
    drop __e
    a2_post, item(A2.4) spec(T2_same_sample_lpm) sample(T2 identical sample) mobility(`mlab') term(100*mob_bilat_`m') label(pp per IHS unit) note("Table A5 row 'probability of positive trade, percentage points'")
    a2_post, item(A2.4) spec(T2_same_sample_lpm) sample(T2 identical sample) mobility(`mlab') term((100/`pbar')*mob_bilat_`m') label(relative % per IHS unit) note("pp / positive-trade share `pbar' (File S1 T2 'LPM_relative_percent'; the text's 1.5% / 0.4%)")
    a2_postval, item(A2.4) spec(T2_same_sample_lpm) sample(T2 identical sample) mobility(`mlab') label(positive-trade share) value(`pbar') n(`=e(N)')
    display as result "A2_4_T2 `m' N=" e(N) " pp=" %10.7f 100*_b[mob_bilat_`m'] " rel=" %10.7f 100*_b[mob_bilat_`m']/`pbar' " pbar=" %10.8f `pbar'

    * ---------------- File S1 T1 and T9 rows
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & v_ttl_k > 0 & !missing(v_ttl_k), absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.4 File S1 T1 positive trade only `mlab'"
    a2_post, item(A2.4) spec(S1_T1_positive_only) sample(has_both & trade>0) mobility(`mlab') term(mob_bilat_`m') note("run_tests.do:40,44: pos = v_ttl_k>0 & !missing(v_ttl_k)")
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & pos_every_year == 1, absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.4 File S1 T1 positive in every year `mlab'"
    a2_post, item(A2.4) spec(S1_T1_positive_every_year) sample(has_both & pos_every_year) mobility(`mlab') term(mob_bilat_`m') note("run_tests.do:40-45: pair has 15 rows and observed positive trade in all of them")
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & fully_reported == 1, absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.4 File S1 T9 fully reported `mlab'"
    a2_post, item(A2.4) spec(S1_T9_fully_reported) sample(has_both & fully_reported) mobility(`mlab') term(mob_bilat_`m') note("run_tests.do:253-259: every any_unreported* = 0, missing flag = not clean")
    quietly count if has_both_`m' & !missing(v_ttl_k) & fully_reported == 0
    a2_postval, item(A2.4) spec(S1_T9_fully_reported) sample(has_both & trade observed) mobility(`mlab') label(rows with any_unreported != 0 or missing) value(`r(N)')
}
a2_close "${OUT}/results/A2_4.dta" "${OUT}/results/A2_4.csv"
display as result "A2_4_DONE vintage=${VINTAGE} " c(current_time)
log close
