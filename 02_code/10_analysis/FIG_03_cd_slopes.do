/*******************************************************************************
 FIG_03_cd_slopes.do -- data for manuscript Figure 1 (mobility slopes over cultural distance)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do FIG_03_cd_slopes.do <corrected2|corrected2x>
 Caption: (a) visitors, own estimation sample; (b) tourists,
 own estimation sample; (c) visitors and tourists on identical observations. Line = mobility slope
 b + g*(CD - c) on a fine grid between the sample minimum and maximum with a 95% interval from the
 full covariance of (b, g); bars = pair-year counts in 20 equal-width CD bins (clamped to [1, 20],
 counts asserted to sum to the estimation N).
 Fits: identical to A2_5.do for mod = cd (moderator cul_dist = package cd6_ge4): own samples with
 realized-sample centring (A2_5.do lines 212-238, cd_own_real), identical observations = fixed point of
 the two eligible-centred models then common-sample centring (A2_5.do lines 296-334, cd_common_real).
 Help consulted (installed): ppmlhdfe.sthlp 2.3.4 (absorb(), vce(cluster), e(sample), e(b), e(V),
 e(N), e(N_full), e(num_singletons), e(num_separated), e(converged)); [R] lincom (r(estimate), r(se);
 standard normal reference when the model posts no residual df); [R] pctile (_pctile, r(r#));
 [P] matrix (e(V) elements); [P] postfile; nflow.sthlp 1.0.1.
 Grid interval: se(v) = sqrt(V_bb + 2(v-c)V_bg + (v-c)^2 V_gg), 95% CI = slope -/+ invnormal(0.975) se,
 i.e. exactly what lincom reports for b + (v-c) g after ppmlhdfe (checked at 11 grid points to 1e-10).
 Positive control: at the 7 percentiles of A2_5.do a2_slopes, lincom slope and SE equal the A2.csv rows
 A2.5 cd_own_slopes (own) and cd_common_slopes (identical observations) of the same vintage to 1e-6.
 Output: ${OUT}/FIG_cd_slopes_grid.csv, FIG_cd_slopes_bins.csv, FIG_cd_slopes_controls.csv; nflow (every fit via a2_chk) in
 ${OUT}/FIG_nflow.csv. No data value is altered.
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
assert inlist("${VINTAGE}", "corrected2", "corrected2x")
capture log close _all
log using "${LOGS}/FIG_03_cd_slopes_${VINTAGE}.log", text replace
display as result "FIG_03_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
local FE "exporter_year importer_year pair_id"
local NG 201
use "${OUT}/A2_work.dta", clear
nflow start using "${OUT}/FIG_nflow.csv", append
tempname G B K
postfile `G' str12 panel str9 mobility int gridpoint double(cd slope se ci_lo ci_hi c N) using "${OUT}/FIG_cd_slopes_grid.dta", replace
postfile `B' str12 panel int bin double(bin_lo bin_hi pairyears N) using "${OUT}/FIG_cd_slopes_bins.dta", replace
postfile `K' str12 panel str9 mobility str40 check double(value reference absdiff) str6 result using "${OUT}/FIG_cd_slopes_controls.dta", replace

* reference rows of A2.csv (same vintage): slopes at the 7 percentiles
preserve
    import delimited using "${OUT}/results/A2.csv", clear varnames(1) asdouble stringcols(1 2 3 4 5 6 7 18 19) case(lower)
    keep if item == "A2.5" & inlist(spec, "cd_own_slopes", "cd_common_slopes")
    gen int q = real(regexs(1)) if regexm(term, "^slope at p([0-9]+) of cul_dist")
    keep spec mobility q b se n
    tempfile refs
    save `refs'
restore

capture program drop _grid
program define _grid
    * slope b + (v - c) g on NG points between min and max of the moderator over touse; e(V) block
    args G panel mob ix c touse ng mlab
    tempname V
    matrix `V' = e(V)
    local bb = _b[`mob']
    local gg = _b[`ix']
    local vbb = `V'[rownumb(`V', "`mob'"), colnumb(`V', "`mob'")]
    local vgg = `V'[rownumb(`V', "`ix'"), colnumb(`V', "`ix'")]
    local vbg = `V'[rownumb(`V', "`mob'"), colnumb(`V', "`ix'")]
    quietly summarize cul_dist if `touse'
    local lo = r(min)
    local hi = r(max)
    local nn = e(N)
    local z = invnormal(0.975)
    forvalues k = 1/`ng' {
        local v = `lo' + (`k' - 1) * (`hi' - `lo') / (`ng' - 1)
        local s = `bb' + (`v' - `c') * `gg'
        local se = sqrt(`vbb' + 2 * (`v' - `c') * `vbg' + (`v' - `c')^2 * `vgg')
        post `G' ("`panel'") ("`mlab'") (`k') (`v') (`s') (`se') (`s' - `z' * `se') (`s' + `z' * `se') (`c') (`nn')
        if mod(`k' - 1, 20) == 0 {
            quietly lincom `mob' + (`v' - `c') * `ix'
            assert abs(r(estimate) - `s') < 1e-10 & abs(r(se) - `se') < 1e-10
        }
    }
end

capture program drop _bins
program define _bins
    * 20 equal-width bins between min and max over touse; full-precision endpoints; clamped to [1, 20]
    args B panel touse nexp
    tempname slo sw
    quietly summarize cul_dist if `touse'
    scalar `slo' = r(min)
    scalar `sw' = (r(max) - r(min)) / 20
    local ntot = r(N)
    tempvar bin
    quietly gen int `bin' = max(1, min(20, 1 + floor((cul_dist - scalar(`slo')) / scalar(`sw')))) if `touse'
    local nsum 0
    forvalues b = 1/20 {
        quietly count if `touse' & `bin' == `b'
        local nsum = `nsum' + r(N)
        post `B' ("`panel'") (`b') (scalar(`slo') + (`b' - 1) * scalar(`sw')) (scalar(`slo') + `b' * scalar(`sw')) (r(N)) (`ntot')
    }
    assert `nsum' == `ntot'
    assert `ntot' == `nexp'
    drop `bin'
end

capture program drop _pcheck
program define _pcheck
    * lincom at the 7 percentiles (same _pctile call as A2_5.do a2_slopes) vs the A2.csv rows
    args K refs panel spec mobility mob ix c touse
    preserve
        use `refs', clear
        foreach q in 5 10 25 50 75 90 95 {
            quietly count if spec == "`spec'" & mobility == "`mobility'" & q == `q'
            assert r(N) == 1
            quietly summarize b if spec == "`spec'" & mobility == "`mobility'" & q == `q', meanonly
            local rb_`q' = r(mean)
            quietly summarize se if spec == "`spec'" & mobility == "`mobility'" & q == `q', meanonly
            local rs_`q' = r(mean)
        }
    restore
    quietly _pctile cul_dist if `touse', percentiles(5 10 25 50 75 90 95)
    local k 0
    foreach q in 5 10 25 50 75 90 95 {
        local ++k
        local v_`q' = r(r`k')
    }
    foreach q in 5 10 25 50 75 90 95 {
        quietly lincom `mob' + (`v_`q'' - `c') * `ix'
        local est = r(estimate)
        local se = r(se)
        local rb = `rb_`q''
        local rs = `rs_`q''
        local d1 = abs(`est' - `rb')
        local d2 = abs(`se' - `rs')
        post `K' ("`panel'") ("`mobility'") ("slope p`q'") (`est') (`rb') (`d1') (cond(`d1' < 1e-6, "PASS", "FAIL"))
        post `K' ("`panel'") ("`mobility'") ("SE p`q'") (`se') (`rs') (`d2') (cond(`d2' < 1e-6, "PASS", "FAIL"))
        assert `d1' < 1e-6 & `d2' < 1e-6
        display as result "FIG_03_PC `panel' `mobility' p`q' slope=" %10.6f `est' " ref=" %10.6f `rb' " se=" %10.6f `se' " ref=" %10.6f `rs'
    }
end

*------------------------------------------------------------------------------ panels a, b: own samples
foreach m in vis tour {
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    local panel = cond("`m'" == "vis", "a_own_vis", "b_own_tour")
    gen byte cand_`m' = has_both_`m' & !missing(v_ttl_k, mob_bilat_`m', cul_dist)
    quietly summarize cul_dist if cand_`m'
    local c0 = r(mean)
    gen double ix0_`m' = mob_bilat_`m' * (cul_dist - `c0') if cand_`m'
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' ix0_`m' if cand_`m', absorb(`FE') vce(cluster pair_id)
    a2_chk "FIG_03 own `mlab' eligible centring"
    gen byte own_`m' = e(sample)
    assert own_`m' == s_cd_`m'
    * realized-sample centring (A2_5.do: re-centre until e(sample) is unchanged)
    quietly summarize cul_dist if own_`m'
    local c1 = r(mean)
    gen byte es_`m' = own_`m'
    local stable 0
    local it 0
    while `stable' == 0 {
        local ++it
        if `it' > 10 error 430
        capture drop ix1_`m'
        gen double ix1_`m' = mob_bilat_`m' * (cul_dist - `c1') if cand_`m'
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' ix1_`m' if cand_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "FIG_03 own `mlab' realized centring iteration `it'"
        tempvar e1
        gen byte `e1' = e(sample)
        quietly count if `e1' != es_`m'
        if r(N) == 0 local stable 1
        else {
            quietly replace es_`m' = `e1'
            quietly summarize cul_dist if es_`m'
            local c1 = r(mean)
        }
        drop `e1'
    }
    quietly count if es_`m'
    local nreal = r(N)
    display as result "FIG_03 `panel' c=" %12.9f `c1' " N=`nreal' b=" %12.9f _b[mob_bilat_`m'] " g=" %12.9f _b[ix1_`m']
    _grid `G' `panel' mob_bilat_`m' ix1_`m' `c1' es_`m' `NG' `mlab'
    _pcheck `K' `refs' `panel' cd_own_slopes `mlab' mob_bilat_`m' ix1_`m' `c1' es_`m'
    _bins `B' `panel' es_`m' `nreal'
}
*------------------------------------------------------------------------------ panel c: identical observations
gen byte cm = own_vis & own_tour
a2_fix, touse(cm) models("v_ttl_k mob_bilat_vis ix0_vis ; v_ttl_k mob_bilat_tour ix0_tour")
nflow step "FIG_03 identical-observation fixed point (A2_5 cd common; no row change, flag only)"
quietly count if cm
local ncm = r(N)
quietly summarize cul_dist if cm
local cc = r(mean)
foreach m in vis tour {
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    gen double ixc_`m' = mob_bilat_`m' * (cul_dist - `cc') if cm
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' ixc_`m' if cm, absorb(`FE') vce(cluster pair_id)
    a2_chk "FIG_03 identical observations `mlab'"
    tempvar e1
    gen byte `e1' = e(sample)
    assert `e1' == cm
    drop `e1'
    assert e(N) == `ncm'
    _grid `G' c_identical mob_bilat_`m' ixc_`m' `cc' cm `NG' `mlab'
    _pcheck `K' `refs' c_identical cd_common_slopes `mlab' mob_bilat_`m' ixc_`m' `cc' cm
}
_bins `B' c_identical cm `ncm'
display as result "FIG_03 c_identical c=" %12.9f `cc' " N=`ncm'"
postclose `G'
postclose `B'
postclose `K'
foreach f in grid bins controls {
    preserve
        use "${OUT}/FIG_cd_slopes_`f'.dta", clear
        gen str11 vintage = "${VINTAGE}"
        order vintage
        quietly ds, has(type numeric)
        format `r(varlist)' %24.17g
        export delimited using "${OUT}/FIG_cd_slopes_`f'.csv", replace datafmt
    restore
    erase "${OUT}/FIG_cd_slopes_`f'.dta"
}
nflow report
display as result "FIG_03_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
