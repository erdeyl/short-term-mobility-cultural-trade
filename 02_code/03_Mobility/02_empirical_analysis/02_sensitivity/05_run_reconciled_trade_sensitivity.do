/*******************************************************************************
 06_run_reconciled_trade_sensitivity.do

 STEP 4D: Simple reporting-side reconciled trade sensitivity.

 Purpose
 -------
 Step 4C showed:
   - tourists are robust to importer- vs exporter-reported trade;
   - visitors are materially reporting-side sensitive.

 This final measurement sensitivity asks what happens when neither reporting side
 alone determines the bilateral trade value.

 Reconciled outcome
 ------------------
 On dyad-years where BOTH importer- and exporter-reported LB cultural-trade
 outcomes are observed:

   v_ttl_reconciled_lb_k
      = (v_ttl_k + v_ttl_exporter_lb_k) / 2

 This is deliberately called a "simple reporting-side average", NOT "true trade".
 No attempt is made to correct CIF/FOB, timing, re-exports, or partner attribution.

 Estimation
 ----------
 For visitors and tourists separately:
   1. require strict bilateral mobility support;
   2. require both importer- and exporter-reported LB trade outcomes;
   3. iteratively intersect realized ppmlhdfe e(sample) across
      importer, exporter, and reconciled outcomes;
   4. estimate all three outcomes on the exact same realized observations;
   5. use a stacked PPML to obtain formal covariance-aware tests:
        importer = reconciled
        exporter = reconciled
        importer = exporter
        all three equal

 All models:
   absorb(exporter_year importer_year pair_id)
   vce(cluster pair_id)

 Input
 -----
 08_sensitivity/04_mirror_trade/data/mirror_analysis_ready.dta

 Outputs
 -------
 08_sensitivity/04_mirror_trade/reconciled/
*******************************************************************************/

clear all
set more off
set linesize 255
version 18.0
set varabbrev off

args PROJECT_ROOT
if `"`PROJECT_ROOT'"'=="" {
    di as error "Supply replication_build root as argument 1."
    exit 198
}
local PROJECT_ROOT=subinstr(`"`PROJECT_ROOT'"',"\\","/",.)

global ROOT `"`PROJECT_ROOT'"'
global INDATA "${ROOT}/03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta"
global OUTROOT "${ROOT}/05_output/03_Mobility/02_empirical_analysis/02_sensitivity/04_mirror_trade/reconciled"
global TABLES "${OUTROOT}/tables"
global DIAG "${ROOT}/05_output/03_Mobility/01_diagnostics/sensitivity/04_mirror_trade/reconciled"
global LOGS "${ROOT}/05_output/03_Mobility/03_logs/sensitivity/04_mirror_trade/reconciled"

capture mkdir "${OUTROOT}"
capture mkdir "${TABLES}"
capture mkdir "${DIAG}"
capture mkdir "${LOGS}"

capture log close _all
log using "${LOGS}/06_run_reconciled_trade_sensitivity.log", replace text

capture confirm file "${INDATA}"
if _rc {
    di as error "Missing Step 4B mirror analysis input:"
    di as error "${INDATA}"
    exit 601
}

capture which ppmlhdfe
if _rc {
    di as error "Required command missing: ppmlhdfe"
    exit 199
}
capture which esttab
if _rc {
    di as error "Required command missing: esttab"
    exit 199
}
capture which eststo
if _rc {
    di as error "Required command missing: eststo"
    exit 199
}

use "${INDATA}", clear
isid year iso3_o iso3_d

foreach v in ///
    v_ttl_k v_ttl_exporter_lb_k ///
    mob_bilat_vis mob_bilat_tour ///
    has_both_vis has_both_tour ///
    exporter_year importer_year pair_id {
    capture confirm variable `v'
    if _rc {
        di as error "Required variable missing: `v'"
        exit 111
    }
}

* Simple reporting-side average, defined only when BOTH reports are observed.
gen double v_ttl_reconciled_lb_k = ///
    (v_ttl_k + v_ttl_exporter_lb_k) / 2 ///
    if !missing(v_ttl_k, v_ttl_exporter_lb_k)

label var v_ttl_reconciled_lb_k ///
    "Simple average of importer- and exporter-reported LB cultural trade (thousand current USD)"

assert missing(v_ttl_reconciled_lb_k) ///
    if missing(v_ttl_k) | missing(v_ttl_exporter_lb_k)

assert abs(v_ttl_reconciled_lb_k - ///
    (v_ttl_k + v_ttl_exporter_lb_k)/2) < 1e-10 ///
    if !missing(v_ttl_reconciled_lb_k)

local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"

eststo clear

* ======================================================================
* A. VISITORS: exact 3-outcome realized support
* ======================================================================
gen byte recon_vis = ///
    has_both_vis==1 & ///
    !missing(v_ttl_k, v_ttl_exporter_lb_k, ///
             v_ttl_reconciled_lb_k, mob_bilat_vis)

quietly count if recon_vis
scalar vis_candidate_n = r(N)

local vis_converged=0
local vis_iterations=0

forvalues iter=1/10 {
    local vis_iterations=`iter'
    capture drop __v_imp __v_exp __v_rec

    quietly ppmlhdfe v_ttl_k mob_bilat_vis if recon_vis, ///
        absorb(`FE') vce(cluster `CLUSTER')
    gen byte __v_imp=e(sample)

    quietly ppmlhdfe v_ttl_exporter_lb_k mob_bilat_vis if recon_vis, ///
        absorb(`FE') vce(cluster `CLUSTER')
    gen byte __v_exp=e(sample)

    quietly ppmlhdfe v_ttl_reconciled_lb_k mob_bilat_vis if recon_vis, ///
        absorb(`FE') vce(cluster `CLUSTER')
    gen byte __v_rec=e(sample)

    quietly count if recon_vis & (!__v_imp | !__v_exp | !__v_rec)
    local removed=r(N)

    if `removed'==0 {
        local vis_converged=1
        continue, break
    }

    replace recon_vis = recon_vis & __v_imp & __v_exp & __v_rec
}

if `vis_converged'==0 {
    di as error "Visitor exact three-outcome sample failed to converge."
    exit 430
}
drop __v_imp __v_exp __v_rec

quietly ppmlhdfe v_ttl_k mob_bilat_vis if recon_vis, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo V_IMP
gen byte __v_imp_final=e(sample)
scalar v_imp_b=_b[mob_bilat_vis]
scalar v_imp_se=_se[mob_bilat_vis]
scalar v_n=e(N)

quietly ppmlhdfe v_ttl_exporter_lb_k mob_bilat_vis if recon_vis, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo V_EXP
gen byte __v_exp_final=e(sample)
scalar v_exp_b=_b[mob_bilat_vis]
scalar v_exp_se=_se[mob_bilat_vis]

quietly ppmlhdfe v_ttl_reconciled_lb_k mob_bilat_vis if recon_vis, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo V_REC
gen byte __v_rec_final=e(sample)
scalar v_rec_b=_b[mob_bilat_vis]
scalar v_rec_se=_se[mob_bilat_vis]

quietly count if ///
    __v_imp_final!=__v_exp_final | ///
    __v_imp_final!=__v_rec_final
if r(N)!=0 {
    di as error "Visitor final realized samples are not identical."
    exit 459
}

quietly count if __v_imp_final
assert r(N)==scalar(v_n)
drop __v_imp_final __v_exp_final __v_rec_final

* Stacked visitor model for formal three-outcome covariance-aware tests.
preserve
    keep if recon_vis
    keep year iso3_o iso3_d pair_id exporter_year importer_year ///
         v_ttl_k v_ttl_exporter_lb_k v_ttl_reconciled_lb_k mob_bilat_vis

    expand 3
    bysort year iso3_o iso3_d: gen byte side=_n
    label define side3 1 "Importer" 2 "Exporter" 3 "Reconciled"
    label values side side3

    gen double stacked_trade = .
    replace stacked_trade=v_ttl_k if side==1
    replace stacked_trade=v_ttl_exporter_lb_k if side==2
    replace stacked_trade=v_ttl_reconciled_lb_k if side==3

    gen double x_imp=cond(side==1,mob_bilat_vis,0)
    gen double x_exp=cond(side==2,mob_bilat_vis,0)
    gen double x_rec=cond(side==3,mob_bilat_vis,0)

    egen long exporter_year_s=group(exporter_year side)
    egen long importer_year_s=group(importer_year side)
    egen long pair_s=group(pair_id side)

    quietly ppmlhdfe stacked_trade x_imp x_exp x_rec, ///
        absorb(exporter_year_s importer_year_s pair_s) ///
        vce(cluster pair_id)

    scalar v_stack_imp=_b[x_imp]
    scalar v_stack_exp=_b[x_exp]
    scalar v_stack_rec=_b[x_rec]

    if abs(scalar(v_stack_imp)-scalar(v_imp_b))>1e-6 | ///
       abs(scalar(v_stack_exp)-scalar(v_exp_b))>1e-6 | ///
       abs(scalar(v_stack_rec)-scalar(v_rec_b))>1e-6 {
        di as error "Visitor stacked model failed coefficient reproduction check."
        exit 459
    }

    test x_imp=x_rec
    scalar v_p_imp_rec=r(p)

    test x_exp=x_rec
    scalar v_p_exp_rec=r(p)

    test x_imp=x_exp
    scalar v_p_imp_exp=r(p)

    test x_imp=x_exp=x_rec
    scalar v_p_all_equal=r(p)

    lincom x_imp-x_rec
    scalar v_diff_imp_rec=r(estimate)
    scalar v_diff_imp_rec_se=r(se)

    lincom x_exp-x_rec
    scalar v_diff_exp_rec=r(estimate)
    scalar v_diff_exp_rec_se=r(se)
restore

* ======================================================================
* B. TOURISTS: exact 3-outcome realized support
* ======================================================================
gen byte recon_tour = ///
    has_both_tour==1 & ///
    !missing(v_ttl_k, v_ttl_exporter_lb_k, ///
             v_ttl_reconciled_lb_k, mob_bilat_tour)

quietly count if recon_tour
scalar tour_candidate_n = r(N)

local tour_converged=0
local tour_iterations=0

forvalues iter=1/10 {
    local tour_iterations=`iter'
    capture drop __t_imp __t_exp __t_rec

    quietly ppmlhdfe v_ttl_k mob_bilat_tour if recon_tour, ///
        absorb(`FE') vce(cluster `CLUSTER')
    gen byte __t_imp=e(sample)

    quietly ppmlhdfe v_ttl_exporter_lb_k mob_bilat_tour if recon_tour, ///
        absorb(`FE') vce(cluster `CLUSTER')
    gen byte __t_exp=e(sample)

    quietly ppmlhdfe v_ttl_reconciled_lb_k mob_bilat_tour if recon_tour, ///
        absorb(`FE') vce(cluster `CLUSTER')
    gen byte __t_rec=e(sample)

    quietly count if recon_tour & (!__t_imp | !__t_exp | !__t_rec)
    local removed=r(N)

    if `removed'==0 {
        local tour_converged=1
        continue, break
    }

    replace recon_tour = recon_tour & __t_imp & __t_exp & __t_rec
}

if `tour_converged'==0 {
    di as error "Tourist exact three-outcome sample failed to converge."
    exit 430
}
drop __t_imp __t_exp __t_rec

quietly ppmlhdfe v_ttl_k mob_bilat_tour if recon_tour, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo T_IMP
gen byte __t_imp_final=e(sample)
scalar t_imp_b=_b[mob_bilat_tour]
scalar t_imp_se=_se[mob_bilat_tour]
scalar t_n=e(N)

quietly ppmlhdfe v_ttl_exporter_lb_k mob_bilat_tour if recon_tour, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo T_EXP
gen byte __t_exp_final=e(sample)
scalar t_exp_b=_b[mob_bilat_tour]
scalar t_exp_se=_se[mob_bilat_tour]

quietly ppmlhdfe v_ttl_reconciled_lb_k mob_bilat_tour if recon_tour, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo T_REC
gen byte __t_rec_final=e(sample)
scalar t_rec_b=_b[mob_bilat_tour]
scalar t_rec_se=_se[mob_bilat_tour]

quietly count if ///
    __t_imp_final!=__t_exp_final | ///
    __t_imp_final!=__t_rec_final
if r(N)!=0 {
    di as error "Tourist final realized samples are not identical."
    exit 459
}

quietly count if __t_imp_final
assert r(N)==scalar(t_n)
drop __t_imp_final __t_exp_final __t_rec_final

* Stacked tourist model for formal three-outcome covariance-aware tests.
preserve
    keep if recon_tour
    keep year iso3_o iso3_d pair_id exporter_year importer_year ///
         v_ttl_k v_ttl_exporter_lb_k v_ttl_reconciled_lb_k mob_bilat_tour

    expand 3
    bysort year iso3_o iso3_d: gen byte side=_n
    label define side3t 1 "Importer" 2 "Exporter" 3 "Reconciled"
    label values side side3t

    gen double stacked_trade = .
    replace stacked_trade=v_ttl_k if side==1
    replace stacked_trade=v_ttl_exporter_lb_k if side==2
    replace stacked_trade=v_ttl_reconciled_lb_k if side==3

    gen double x_imp=cond(side==1,mob_bilat_tour,0)
    gen double x_exp=cond(side==2,mob_bilat_tour,0)
    gen double x_rec=cond(side==3,mob_bilat_tour,0)

    egen long exporter_year_s=group(exporter_year side)
    egen long importer_year_s=group(importer_year side)
    egen long pair_s=group(pair_id side)

    quietly ppmlhdfe stacked_trade x_imp x_exp x_rec, ///
        absorb(exporter_year_s importer_year_s pair_s) ///
        vce(cluster pair_id)

    scalar t_stack_imp=_b[x_imp]
    scalar t_stack_exp=_b[x_exp]
    scalar t_stack_rec=_b[x_rec]

    if abs(scalar(t_stack_imp)-scalar(t_imp_b))>1e-6 | ///
       abs(scalar(t_stack_exp)-scalar(t_exp_b))>1e-6 | ///
       abs(scalar(t_stack_rec)-scalar(t_rec_b))>1e-6 {
        di as error "Tourist stacked model failed coefficient reproduction check."
        exit 459
    }

    test x_imp=x_rec
    scalar t_p_imp_rec=r(p)

    test x_exp=x_rec
    scalar t_p_exp_rec=r(p)

    test x_imp=x_exp
    scalar t_p_imp_exp=r(p)

    test x_imp=x_exp=x_rec
    scalar t_p_all_equal=r(p)

    lincom x_imp-x_rec
    scalar t_diff_imp_rec=r(estimate)
    scalar t_diff_imp_rec_se=r(se)

    lincom x_exp-x_rec
    scalar t_diff_exp_rec=r(estimate)
    scalar t_diff_exp_rec_se=r(se)
restore

* ======================================================================
* C. Publication-facing table
* ======================================================================
foreach format in csv rtf {
    local extra ""
    if "`format'"=="csv" local extra "csv"

    esttab V_IMP V_EXP V_REC T_IMP T_EXP T_REC ///
        using "${TABLES}/table_reconciled_trade_sensitivity.`format'", ///
        replace `extra' ///
        mtitles( ///
            "Vis: importer" "Vis: exporter" "Vis: reconciled" ///
            "Tour: importer" "Tour: exporter" "Tour: reconciled" ///
        ) ///
        b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(mob_bilat_vis mob_bilat_tour) ///
        order(mob_bilat_vis mob_bilat_tour) ///
        coeflabels(mob_bilat_vis "Bilateral visitors" ///
                   mob_bilat_tour "Bilateral tourists") ///
        stats(N,labels("Exact three-outcome N") fmt(%12.0fc)) ///
        label compress nogaps ///
        addnotes( ///
            "Reconciled trade is the simple arithmetic mean of importer- and exporter-reported LB cultural trade.", ///
            "All three columns within each mobility measure use exactly the same realized PPML observations.", ///
            "All models absorb exporter-year, importer-year, and directed-pair fixed effects; SEs are clustered by pair.", ///
            "The reporting-side average is a measurement sensitivity and is not interpreted as true bilateral trade." ///
        )
}

* ======================================================================
* D. Machine-readable ledgers
* ======================================================================
preserve
    clear
    input str10 mobility str12 outcome double b se N
    "visitors" "importer" . . .
    "visitors" "exporter" . . .
    "visitors" "reconciled" . . .
    "tourists" "importer" . . .
    "tourists" "exporter" . . .
    "tourists" "reconciled" . . .
    end

    replace b=scalar(v_imp_b) in 1
    replace se=scalar(v_imp_se) in 1
    replace N=scalar(v_n) in 1

    replace b=scalar(v_exp_b) in 2
    replace se=scalar(v_exp_se) in 2
    replace N=scalar(v_n) in 2

    replace b=scalar(v_rec_b) in 3
    replace se=scalar(v_rec_se) in 3
    replace N=scalar(v_n) in 3

    replace b=scalar(t_imp_b) in 4
    replace se=scalar(t_imp_se) in 4
    replace N=scalar(t_n) in 4

    replace b=scalar(t_exp_b) in 5
    replace se=scalar(t_exp_se) in 5
    replace N=scalar(t_n) in 5

    replace b=scalar(t_rec_b) in 6
    replace se=scalar(t_rec_se) in 6
    replace N=scalar(t_n) in 6

    export delimited using ///
        "${DIAG}/reconciled_trade_key_results.csv", replace
restore

preserve
    clear
    set obs 2

    gen str10 mobility=""
    replace mobility="visitors" in 1
    replace mobility="tourists" in 2

    gen double candidate_N=.
    gen double exact_three_outcome_N=.
    gen double importer_b=.
    gen double exporter_b=.
    gen double reconciled_b=.
    gen double p_importer_eq_reconciled=.
    gen double p_exporter_eq_reconciled=.
    gen double p_importer_eq_exporter=.
    gen double p_all_three_equal=.
    gen double importer_minus_reconciled=.
    gen double importer_minus_reconciled_se=.
    gen double exporter_minus_reconciled=.
    gen double exporter_minus_reconciled_se=.

    replace candidate_N=scalar(vis_candidate_n) in 1
    replace exact_three_outcome_N=scalar(v_n) in 1
    replace importer_b=scalar(v_imp_b) in 1
    replace exporter_b=scalar(v_exp_b) in 1
    replace reconciled_b=scalar(v_rec_b) in 1
    replace p_importer_eq_reconciled=scalar(v_p_imp_rec) in 1
    replace p_exporter_eq_reconciled=scalar(v_p_exp_rec) in 1
    replace p_importer_eq_exporter=scalar(v_p_imp_exp) in 1
    replace p_all_three_equal=scalar(v_p_all_equal) in 1
    replace importer_minus_reconciled=scalar(v_diff_imp_rec) in 1
    replace importer_minus_reconciled_se=scalar(v_diff_imp_rec_se) in 1
    replace exporter_minus_reconciled=scalar(v_diff_exp_rec) in 1
    replace exporter_minus_reconciled_se=scalar(v_diff_exp_rec_se) in 1

    replace candidate_N=scalar(tour_candidate_n) in 2
    replace exact_three_outcome_N=scalar(t_n) in 2
    replace importer_b=scalar(t_imp_b) in 2
    replace exporter_b=scalar(t_exp_b) in 2
    replace reconciled_b=scalar(t_rec_b) in 2
    replace p_importer_eq_reconciled=scalar(t_p_imp_rec) in 2
    replace p_exporter_eq_reconciled=scalar(t_p_exp_rec) in 2
    replace p_importer_eq_exporter=scalar(t_p_imp_exp) in 2
    replace p_all_three_equal=scalar(t_p_all_equal) in 2
    replace importer_minus_reconciled=scalar(t_diff_imp_rec) in 2
    replace importer_minus_reconciled_se=scalar(t_diff_imp_rec_se) in 2
    replace exporter_minus_reconciled=scalar(t_diff_exp_rec) in 2
    replace exporter_minus_reconciled_se=scalar(t_diff_exp_rec_se) in 2

    export delimited using ///
        "${DIAG}/reconciled_trade_formal_tests.csv", replace
restore

* Compact status marker.
file open done using ///
    "${DIAG}/06_RECONCILED_TRADE_SENSITIVITY_COMPLETE.txt", ///
    write replace text

file write done "RECONCILED_TRADE_STEP4D=PASS" _n

local vn : display %18.0f scalar(v_n)
local vb : display %12.9f scalar(v_rec_b)
local vp1 : display %12.9f scalar(v_p_imp_rec)
local vp2 : display %12.9f scalar(v_p_exp_rec)
local vpall : display %12.9f scalar(v_p_all_equal)

local tn : display %18.0f scalar(t_n)
local tb : display %12.9f scalar(t_rec_b)
local tp1 : display %12.9f scalar(t_p_imp_rec)
local tp2 : display %12.9f scalar(t_p_exp_rec)
local tpall : display %12.9f scalar(t_p_all_equal)

file write done "visitor_exact_three_outcome_N=`vn'" _n
file write done "visitor_reconciled_b=`vb'" _n
file write done "visitor_p_importer_eq_reconciled=`vp1'" _n
file write done "visitor_p_exporter_eq_reconciled=`vp2'" _n
file write done "visitor_p_all_three_equal=`vpall'" _n

file write done "tourist_exact_three_outcome_N=`tn'" _n
file write done "tourist_reconciled_b=`tb'" _n
file write done "tourist_p_importer_eq_reconciled=`tp1'" _n
file write done "tourist_p_exporter_eq_reconciled=`tp2'" _n
file write done "tourist_p_all_three_equal=`tpall'" _n

file close done

di as result "RECONCILED_TRADE_STEP4D=PASS"

di as result ///
    "VISITORS: importer=" %12.9f scalar(v_imp_b) ///
    " exporter=" %12.9f scalar(v_exp_b) ///
    " reconciled=" %12.9f scalar(v_rec_b) ///
    " N=" %12.0f scalar(v_n)

di as result ///
    "VISITOR p(importer=reconciled)=" %12.9f scalar(v_p_imp_rec) ///
    " p(exporter=reconciled)=" %12.9f scalar(v_p_exp_rec) ///
    " p(all three equal)=" %12.9f scalar(v_p_all_equal)

di as result ///
    "TOURISTS: importer=" %12.9f scalar(t_imp_b) ///
    " exporter=" %12.9f scalar(t_exp_b) ///
    " reconciled=" %12.9f scalar(t_rec_b) ///
    " N=" %12.0f scalar(t_n)

di as result ///
    "TOURIST p(importer=reconciled)=" %12.9f scalar(t_p_imp_rec) ///
    " p(exporter=reconciled)=" %12.9f scalar(t_p_exp_rec) ///
    " p(all three equal)=" %12.9f scalar(t_p_all_equal)

log close
