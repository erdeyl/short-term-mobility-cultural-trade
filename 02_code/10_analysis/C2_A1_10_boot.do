/*******************************************************************************
 C2_A1_10_boot.do -- rerun C2: A1.10 bootstrap inference for did_multiplegt_dyn continuous(1)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do C2_A1_10_boot.do <vintage> <vis|tour> <cont1boot|cont1strictboot>
 One call per fresh Stata process (author instruction 2026-11-03; authors' working notes:
 in a clean session the no-placebo bootstrap returns rc 0 for seeds 20261103, 1, 2, 3, 4; the only
 reproducible failure is placebo(1) combined with bootstrap() when the placebo is not estimable:
 rc 122 at the unguarded `foreach i of numlist `num_pl_XX'' (installed did_multiplegt_dyn.ado
 lines 1976-1989, SSC 20260629)). Hence: effects(1) continuous(1) bootstrap(100,20261103), no placebo(),
 cluster(pair_id), same sample and variables as A1_05_did.do (help did_multiplegt_dyn: bootstrap(reps, seed)
 "we recommend using the bootstrap for inference" with continuous(); the placebo status of the analytic
 runs is in rows A1.10.dmdyn2_cont1.* / dmdyn2_cont1strict.*).
 Sample: s_base_<m> (cont1boot) or the strict-classifier sample (cont1strictboot), reconstructed exactly
 as A1_05_did.do and checked against the strict n_groups in tables/A1_A1.10_classifier.csv.
 Output: ${OUT}/results/A1_parts/A1_05b_<m>_<variant>.csv (rows A1.10.dmdyn2_<variant>.<m>.Effect_1).
*******************************************************************************/
args vintage m variant
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
do "A1_00_programs.do"
assert inlist("`m'", "vis", "tour") & inlist("`variant'", "cont1boot", "cont1strictboot")
capture log close _all
log using "${LOGS}/C2_A1_10_boot_${VINTAGE}_`m'_`variant'.log", text replace
display as result "C2_A1_10_BOOT_BEGIN vintage=${VINTAGE} m=`m' variant=`variant' " c(current_date) " " c(current_time)
which did_multiplegt_dyn
set type double
display as result "A1.10_STORAGE c(type)=`c(type)' tmpdir=`c(tmpdir)'"
assert strpos("`c(tmpdir)'", " ") == 0
use year iso3_o iso3_d v_ttl_k pair_id mob_bilat_`m' s_base_`m' using "${PREPARED}", clear
nflow start using "${OUT}/A1_nflow_boot_`m'_`variant'.csv", replace expected(823446)
A1_open A1_05b_`m'_`variant'
keep if s_base_`m' == 1
nflow step "C2_A1_10_boot keep baseline e(sample) rows (`m')"
isid pair_id year
local ifc ""
local smp "s_base_`m'"
local snote ""
if "`variant'" == "cont1strictboot" {
    preserve
        import delimited using "${OUT}/tables/A1_A1.10_classifier.csv", clear varnames(1) stringcols(_all) case(lower)
        quietly levelsof rvalue if mobility == "`m'" & mode == "strict" & rname == "n_groups", local(ng) clean
        quietly levelsof rvalue if mobility == "`m'" & mode == "strict" & rname == "sfsd_case", local(sc) clean
    restore
    assert "`ng'" != ""
    * reconstruction verbatim from A1_05_did.do (strict-mode sample)
    bysort pair_id: egen byte __o07 = max(year == 2007)
    gen double __d07x = mob_bilat_`m' if year == 2007
    bysort pair_id: egen double __d07 = max(__d07x)
    bysort pair_id: egen int __Fg = min(cond(!missing(__d07) & mob_bilat_`m' != __d07, year, .))
    bysort pair_id: egen int __nbefore = total(year < __Fg)
    gen byte __strict = __o07 == 1 & !missing(__Fg) & __nbefore == __Fg - 2007
    egen byte __tgs = tag(pair_id) if __strict
    quietly count if __tgs == 1
    local ngs = r(N)
    display as result "A1.10_STRICT_SAMPLE `m' reconstructed groups=`ngs' classifier n_groups=`ng' case=`sc'"
    if `ngs' != real("`ng'") | "`sc'" != "continuous-baseline" {
        post A1post ("A1.10.dmdyn2_`variant'.`m'.Effect_1") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("strict sample") ("`m'") ("Effect_1") ///
            (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) ("pair_id") ("NOT RUN: strict sample `ngs' groups vs classifier `ng' (case `sc')")
        A1_close
        log close
        exit
    }
    local ifc "if __strict"
    local smp "strict sample"
    local snote "; strict-classifier sample (`ngs' groups)"
}
local vopt "continuous(1) bootstrap(100,20261103)"
timer clear 1
timer on 1
set varabbrev on
display as result "A1.10_VARABBREV on for did_multiplegt_dyn: package requires variable abbreviation, ado lines 2010-2014 (getmata scalars_XX* creates scalars_XX1, read as scalars_XX)"
capture noisily did_multiplegt_dyn v_ttl_k pair_id year mob_bilat_`m' `ifc', effects(1) `vopt' cluster(pair_id) graph_off _no_updates
local rc = _rc
set varabbrev off
timer off 1
quietly timer list 1
display as result "C2_A1_10_BOOT_RC `m' `variant' rc=`rc' seconds=" r(t1)
if `rc' == 0 {
    local bb = e(Effect_1)
    local ss = e(se_effect_1)
    local nn = e(N_effect_1)
    local ns = e(N_switchers_effect_1)
    post A1post ("A1.10.dmdyn2_`variant'.`m'.Effect_1") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("`smp'") ("`m'") ("Effect_1") ///
        (`bb') (`ss') (2 * normal(-abs(`bb' / `ss'))) (`bb' - invnormal(.975) * `ss') (`bb' + invnormal(.975) * `ss') ///
        (`nn') (.) (.) (.) (.) ("pair_id") ("did_multiplegt_dyn effects(1) `vopt', no placebo() (placebo() with bootstrap() stops with rc 122 when the placebo is not estimable: did_multiplegt_dyn.ado SSC 20260629 lines 1976-1989); se = bootstrap SE; fresh Stata process`snote'; level outcome; switchers=`ns'; N-switchers=`=`nn'-`ns''; double storage")
}
else {
    post A1post ("A1.10.dmdyn2_`variant'.`m'.Effect_1") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("`smp'") ("`m'") ("Effect_1") ///
        (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) ("pair_id") ("`=cond(`rc'==301, "FAILED rc=301: bootstrap(100,20261103) stops when a bootstrap sample draws too few of the 3 control (non-switching) observations: the command reports insufficient observations and that no effect can be estimated (replay: authors' working notes); no seed search", "FAILED rc=`rc': did_multiplegt_dyn effects(1) `vopt' (no placebo), fresh Stata process`snote'")'")
}
A1_close
nflow report
display as result "C2_A1_10_BOOT_COMPLETE vintage=${VINTAGE} m=`m' variant=`variant' " c(current_date) " " c(current_time)
log close
