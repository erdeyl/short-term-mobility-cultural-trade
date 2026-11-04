/*******************************************************************************
 A2_2.do -- item A2.2 alternatives to the IHS of bilateral trips (R2.10).
 On s_base_vis / s_base_tour: ln(x) on x>0; ln(max(x,1)) + 1[x==0]; ln(1+x);
 asinh(x/1000) (thousand trips, the UN Tourism source unit); asinh(x/1e6); each next to the
 baseline asinh(x) on IDENTICAL observations (fixed point of both models' e(sample)).
 x = bilat_*_raw (trips; STUDENT 02_prepare_data.do:49-50, 54, 56). Help: ppmlhdfe.sthlp,
 [FN] asinh(), ln(), max().
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
log using "${LOGS}/A2_2_${VINTAGE}.log", text replace
display as result "A2_2_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
use "${OUT}/A2_work.dta", clear
nflow start using "${OUT}/A2_nflow.csv", append
a2_open "${OUT}/results/A2_2.dta"
a2_topen "${OUT}/tables/A2_A2.2.dta"
local FE "exporter_year importer_year pair_id"

foreach m in vis tour {
    local smp "s_base_`m'"
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    local x "bilat_`m'_raw"
    quietly count if `smp'
    local N0 = r(N)
    quietly count if `smp' & `x' == 0
    a2_tpost, item(A2.2) table(zeros) sample(`smp') mobility(`mlab') stat(n_bilat_zero) value(`r(N)') n(`N0')
    quietly count if `smp' & `x' > 0 & `x' < 1
    a2_tpost, item(A2.2) table(zeros) sample(`smp') mobility(`mlab') stat(n_bilat_between_0_1) value(`r(N)') n(`N0') note("ln(max(x,1)) also sets these to 0")
    foreach k in 10 1000 10000 1000000 10000000 {
        quietly count if `smp' & `x' < `k'
        a2_tpost, item(A2.2) table(scale) sample(`smp') mobility(`mlab') stat(share_bilat_lt_`k') value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'; asinh(x/k) is close to ln(2x/k) only where x/k is large")
    }
    quietly summarize `x' if `smp', detail
    a2_tpost, item(A2.2) table(scale) sample(`smp') mobility(`mlab') stat(median_bilat_trips) value(`r(p50)') n(`N0')
    gen double t_ln_`m'   = ln(`x') if `smp' & `x' > 0
    gen double t_lnm_`m'  = ln(max(`x', 1)) if `smp' & !missing(`x')
    gen byte   t_z_`m'    = (`x' == 0) if `smp' & !missing(`x')
    gen double t_ln1_`m'  = ln(1 + `x') if `smp' & !missing(`x')
    gen double t_ak_`m'   = asinh(`x' / 1000) if `smp' & !missing(`x')
    gen double t_am_`m'   = asinh(`x' / 1e6) if `smp' & !missing(`x')
    label variable t_ln_`m' "ln(bilateral trips), x>0"
    label variable t_lnm_`m' "ln(max(bilateral trips,1))"
    label variable t_z_`m' "1[bilateral trips==0]"
    label variable t_ln1_`m' "ln(1+bilateral trips)"
    label variable t_ak_`m' "asinh(bilateral trips/1000)"
    label variable t_am_`m' "asinh(bilateral trips/1e6)"
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' if `smp', absorb(`FE') vce(cluster pair_id)
    a2_chk "A2.2 `mlab' baseline asinh"
    a2_post, item(A2.2) spec(baseline_asinh) sample(`smp') mobility(`mlab') term(mob_bilat_`m') label(asinh(x))
    foreach t in ln lnm ln1 ak am {
        local reg "t_`t'_`m'"
        if "`t'" == "lnm" local reg "t_lnm_`m' t_z_`m'"
        gen byte cs_`t'_`m' = `smp' & !missing(t_`t'_`m')
        quietly count if cs_`t'_`m'
        local nc = r(N)
        a2_fix, touse(cs_`t'_`m') models("v_ttl_k `reg' ; v_ttl_k mob_bilat_`m'")
        local it = ${A2_FIX_IT}
        quietly ppmlhdfe v_ttl_k `reg' if cs_`t'_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.2 `mlab' transform `t'"
        local tl : variable label t_`t'_`m'
        a2_post, item(A2.2) spec(`t') sample(`smp' & common) mobility(`mlab') term(t_`t'_`m') label(`tl') note("candidate rows=`nc'; fixed-point iterations=`it'")
        if "`t'" == "lnm" {
            quietly count if e(sample) & t_z_`m' == 1
            local nz = r(N)
            if `nz' > 0 & _se[t_z_`m'] > 0 {
                a2_post, item(A2.2) spec(`t') sample(`smp' & common) mobility(`mlab') term(t_z_`m') label(1[x==0]) note("zero indicator")
            }
            else {
                a2_postval, item(A2.2) spec(`t') sample(`smp' & common) mobility(`mlab') label(1[x==0] not identified) value(.) n(`=e(N)') note("x==0 rows left in the common sample: `nz'; the indicator gives each zero-mobility row its own parameter, so ppmlhdfe drops those rows in the first fit and the model equals ln(x) on x>0")
            }
        }
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if cs_`t'_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.2 `mlab' baseline asinh on rows of transform `t'"
        a2_post, item(A2.2) spec(`t'_baseline_same_rows) sample(`smp' & common) mobility(`mlab') term(mob_bilat_`m') label(asinh(x) on identical rows)
        display as result "A2_2 `m' `t' N=" e(N) " (candidate `nc')"
    }
}
a2_close "${OUT}/results/A2_2.dta" "${OUT}/results/A2_2.csv"
a2_tclose "${OUT}/tables/A2_A2.2.dta" "${OUT}/tables/A2_A2.2.csv"
display as result "A2_2_DONE vintage=${VINTAGE} " c(current_time)
log close
