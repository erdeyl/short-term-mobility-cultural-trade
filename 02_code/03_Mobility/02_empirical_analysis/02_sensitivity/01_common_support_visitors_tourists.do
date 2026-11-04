/*******************************************************************************
 01_common_support_visitors_tourists.do

 STEP 1: Exact common-support comparison of bilateral visitors and tourists.

 Research question:
   Do the visitor and tourist baseline associations remain similar when BOTH
   mobility measures are estimated on exactly the same realized PPML observations?

 This file intentionally does NOT test whether the two coefficients are statistically
 equal. That is Step 2 (formal equality). Its job is to remove sample-composition
 differences first.

 Input:
   03_intermediate/03_Mobility/runtime/core/LB/analysis_prepared.dta

 Outputs:
   05_output/03_Mobility/02_empirical_analysis/02_sensitivity/01_common_support/
*******************************************************************************/

clear all
set more off
set linesize 255
version 18.0
set varabbrev off

args PROJECT_ROOT
if `"`PROJECT_ROOT'"' == "" {
    di as error "Supply the replication-package root as argument 1."
    exit 198
}
local PROJECT_ROOT = subinstr(`"`PROJECT_ROOT'"', "\", "/", .)

global ROOT     `"`PROJECT_ROOT'"'
global INDATA   "${ROOT}/03_intermediate/03_Mobility/runtime/core/LB/analysis_prepared.dta"
global OUTROOT  "${ROOT}/05_output/03_Mobility/02_empirical_analysis/02_sensitivity/01_common_support"
global TABLES   "${OUTROOT}/tables"
global DIAG     "${ROOT}/05_output/03_Mobility/01_diagnostics/sensitivity/01_common_support"
global DATAOUT  "${ROOT}/03_intermediate/03_Mobility/sensitivity/01_common_support"
global LOGS     "${ROOT}/05_output/03_Mobility/03_logs/sensitivity/01_common_support"

capture mkdir "${ROOT}/05_output/03_Mobility/02_empirical_analysis"
capture mkdir "${ROOT}/05_output/03_Mobility/02_empirical_analysis/02_sensitivity"
capture mkdir "${OUTROOT}"
capture mkdir "${TABLES}"
capture mkdir "${DIAG}"
capture mkdir "${DATAOUT}"
capture mkdir "${LOGS}"

capture log close _all
log using "${LOGS}/01_common_support_visitors_tourists.log", replace text

capture confirm file "${INDATA}"
if _rc {
    di as error "Prepared LB analysis data not found:"
    di as error "${INDATA}"
    di as error "Run the Phase-2 core LB analysis successfully first."
    exit 601
}

capture which ppmlhdfe
if _rc {
    di as error "Required command missing: ppmlhdfe"
    exit 199
}
capture which esttab
if _rc {
    di as error "Required command missing: esttab (estout package)"
    exit 199
}
capture which eststo
if _rc {
    di as error "Required command missing: eststo (estout package)"
    exit 199
}

use "${INDATA}", clear
isid year iso3_o iso3_d

foreach v in ///
    v_ttl_k mob_bilat_vis mob_bilat_tour ///
    has_both_vis has_both_tour ///
    exporter_year importer_year pair_id {
    capture confirm variable `v'
    if _rc {
        di as error "Required prepared-data variable missing: `v'"
        exit 111
    }
}

local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"

* ----------------------------------------------------------------------
* A. Reproduce the two original-support baseline models.
* ----------------------------------------------------------------------
eststo clear

quietly ppmlhdfe v_ttl_k mob_bilat_vis if has_both_vis, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo ORIG_VIS
scalar orig_vis_b  = _b[mob_bilat_vis]
scalar orig_vis_se = _se[mob_bilat_vis]
scalar orig_vis_n  = e(N)

quietly ppmlhdfe v_ttl_k mob_bilat_tour if has_both_tour, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo ORIG_TOUR
scalar orig_tour_b  = _b[mob_bilat_tour]
scalar orig_tour_se = _se[mob_bilat_tour]
scalar orig_tour_n  = e(N)

* ----------------------------------------------------------------------
* B. Define raw common support before PPML separation.
* ----------------------------------------------------------------------
gen byte common_vt_candidate = ///
    has_both_vis == 1 & has_both_tour == 1 & ///
    !missing(v_ttl_k, mob_bilat_vis, mob_bilat_tour)

quietly count
scalar prepared_rows = r(N)

quietly count if has_both_vis
scalar strict_vis_rows = r(N)

quietly count if has_both_tour
scalar strict_tour_rows = r(N)

quietly count if common_vt_candidate
scalar common_candidate_rows = r(N)

* ----------------------------------------------------------------------
* C. Obtain EXACT REALIZED common support.
*
* ppmlhdfe can drop separated/singleton observations. Because separation can
* in principle differ across the visitor and tourist regressors, iteratively
* intersect the two realized e(sample) sets until both models retain exactly
* the same observations.
* ----------------------------------------------------------------------
gen byte common_vt_exact = common_vt_candidate
local converged = 0
local iterations = 0

forvalues iter = 1/10 {
    local iterations = `iter'
    capture drop __es_vis __es_tour

    quietly ppmlhdfe v_ttl_k mob_bilat_vis if common_vt_exact, ///
        absorb(`FE') vce(cluster `CLUSTER')
    gen byte __es_vis = e(sample)

    quietly ppmlhdfe v_ttl_k mob_bilat_tour if common_vt_exact, ///
        absorb(`FE') vce(cluster `CLUSTER')
    gen byte __es_tour = e(sample)

    quietly count if common_vt_exact & (!__es_vis | !__es_tour)
    local n_to_remove = r(N)

    if `n_to_remove' == 0 {
        local converged = 1
        continue, break
    }

    replace common_vt_exact = common_vt_exact & __es_vis & __es_tour
}

if `converged' == 0 {
    di as error "Exact common-support intersection did not converge within 10 iterations."
    exit 430
}

drop __es_vis __es_tour

quietly count if common_vt_exact
scalar common_exact_rows = r(N)

* ----------------------------------------------------------------------
* D. Re-estimate BOTH measures on exactly that same realized sample.
* ----------------------------------------------------------------------
quietly ppmlhdfe v_ttl_k mob_bilat_vis if common_vt_exact, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo CS_VIS
gen byte __final_vis = e(sample)
scalar cs_vis_b  = _b[mob_bilat_vis]
scalar cs_vis_se = _se[mob_bilat_vis]
scalar cs_vis_n  = e(N)

quietly ppmlhdfe v_ttl_k mob_bilat_tour if common_vt_exact, ///
    absorb(`FE') vce(cluster `CLUSTER')
eststo CS_TOUR
gen byte __final_tour = e(sample)
scalar cs_tour_b  = _b[mob_bilat_tour]
scalar cs_tour_se = _se[mob_bilat_tour]
scalar cs_tour_n  = e(N)

* The defining validation of this step: same realized observations, not just
* the same pre-estimation eligibility rule.
quietly count if __final_vis != __final_tour
if r(N) != 0 {
    di as error "Visitor and tourist realized PPML samples are not identical."
    exit 459
}

quietly count if common_vt_exact != __final_vis
if r(N) != 0 {
    di as error "Exact common-support flag does not equal final realized PPML sample."
    exit 459
}

assert scalar(cs_vis_n) == scalar(cs_tour_n)
assert scalar(cs_vis_n) == scalar(common_exact_rows)

* ----------------------------------------------------------------------
* E. Save exact common-support data for Step 2 formal equality.
* ----------------------------------------------------------------------
preserve
    keep if common_vt_exact
    keep year iso3_o iso3_d pair_id exporter_year importer_year ///
         v_ttl_k mob_bilat_vis mob_bilat_tour
    isid year iso3_o iso3_d
    save "${DATAOUT}/common_support_vt_exact.dta", replace
restore

* ----------------------------------------------------------------------
* F. Human-readable comparison table.
* ----------------------------------------------------------------------
local coeflabels ///
    mob_bilat_vis  "Bilateral visitors" ///
    mob_bilat_tour "Bilateral tourists"

foreach format in csv rtf {
    local extra ""
    if "`format'" == "csv" local extra "csv"

    esttab ORIG_VIS ORIG_TOUR CS_VIS CS_TOUR ///
        using "${TABLES}/table_common_support_visitors_tourists.`format'", ///
        replace `extra' ///
        mtitles("Visitor: own support" "Tourist: own support" ///
                "Visitor: exact common" "Tourist: exact common") ///
        b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(mob_bilat_vis mob_bilat_tour) ///
        order(mob_bilat_vis mob_bilat_tour) ///
        coeflabels(`coeflabels') ///
        stats(N, labels("N") fmt(%12.0fc)) ///
        label compress nogaps ///
        addnotes( ///
            "Columns 1-2 reproduce each mobility measure on its own strict bilateral support.", ///
            "Columns 3-4 use exactly the same realized PPML observations after separation handling.", ///
            "This table removes sample-composition differences; it is not a formal coefficient-equality test." ///
        )
}

* ----------------------------------------------------------------------
* G. Machine-readable ledgers.
* ----------------------------------------------------------------------
tempname p1
postfile `p1' str36 stage double N using "${DIAG}/common_support_ledger.dta", replace
post `p1' ("prepared_rows")              (scalar(prepared_rows))
post `p1' ("strict_visitor_rows")        (scalar(strict_vis_rows))
post `p1' ("strict_tourist_rows")        (scalar(strict_tour_rows))
post `p1' ("raw_common_candidate_rows")  (scalar(common_candidate_rows))
post `p1' ("exact_realized_common_rows") (scalar(common_exact_rows))
postclose `p1'

preserve
    use "${DIAG}/common_support_ledger.dta", clear
    export delimited using "${DIAG}/common_support_ledger.csv", replace
restore

tempname p2
postfile `p2' str32 model str16 support double b se N ///
    using "${DIAG}/common_support_key_results.dta", replace

post `p2' ("visitors") ("own")   (scalar(orig_vis_b))  (scalar(orig_vis_se))  (scalar(orig_vis_n))
post `p2' ("tourists") ("own")   (scalar(orig_tour_b)) (scalar(orig_tour_se)) (scalar(orig_tour_n))
post `p2' ("visitors") ("exact") (scalar(cs_vis_b))    (scalar(cs_vis_se))    (scalar(cs_vis_n))
post `p2' ("tourists") ("exact") (scalar(cs_tour_b))   (scalar(cs_tour_se))   (scalar(cs_tour_n))
postclose `p2'

preserve
    use "${DIAG}/common_support_key_results.dta", clear
    gen double change_from_own_pct = .
    quietly summarize b if model=="visitors" & support=="own", meanonly
    local vb = r(mean)
    quietly summarize b if model=="tourists" & support=="own", meanonly
    local tb = r(mean)
    replace change_from_own_pct = 100*(b/`vb' - 1) if model=="visitors" & support=="exact"
    replace change_from_own_pct = 100*(b/`tb' - 1) if model=="tourists" & support=="exact"
    export delimited using "${DIAG}/common_support_key_results.csv", replace
restore

file open done using "${DIAG}/01_COMMON_SUPPORT_COMPLETE.txt", write replace text
file write done "COMMON_SUPPORT_STEP1=PASS" _n
file write done "iterations=`iterations'" _n
local n_exact : display %18.0f scalar(common_exact_rows)
file write done "exact_realized_common_N=`n_exact'" _n
local bv : display %12.9f scalar(cs_vis_b)
local bt : display %12.9f scalar(cs_tour_b)
file write done "visitor_common_b=`bv'" _n
file write done "tourist_common_b=`bt'" _n
file write done "formal_equality_test=NOT_RUN_STEP2" _n
file close done

di as result "COMMON_SUPPORT_STEP1=PASS"
di as result "EXACT_REALIZED_COMMON_N=" scalar(common_exact_rows)
di as result "VISITOR_COMMON_B=" %12.9f scalar(cs_vis_b) ///
    " SE=" %12.9f scalar(cs_vis_se)
di as result "TOURIST_COMMON_B=" %12.9f scalar(cs_tour_b) ///
    " SE=" %12.9f scalar(cs_tour_se)
di as text "Formal equality is intentionally reserved for Step 2."

log close
