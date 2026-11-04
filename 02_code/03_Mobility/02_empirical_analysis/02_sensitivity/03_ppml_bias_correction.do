/*******************************************************************************
 03_ppml_bias_correction.do

 STEP 3: Weidner-Zylkin analytical bias correction for the main three-way
 PPML baseline estimates.

 Research question:
   Are the main LB visitor and tourist coefficients/inferences materially
   sensitive to the finite-sample incidental-parameter problem in three-way
   PPML gravity models with exporter-year, importer-year, and pair fixed effects?

 Method:
   1. Reproduce each main baseline on its own strict bilateral support.
   2. Estimate with ppmlhdfe using option -d- and predict the conditional mean.
   3. Pass the realized estimation sample, conditional mean, and original beta
      to ppml_fe_bias.
   4. Report original vs analytically bias-corrected coefficients and adjusted SEs.

 Notes:
   - This is a sensitivity of the MAIN baseline estimates, not a visitor-vs-tourist
     comparison. Step 1/2 already handle common support and equality.
   - The -approx- option is explicitly used for the adjusted variance because this
     is a high-dimensional application. It affects the variance correction, not the
     definition of the baseline specification.
   - No observations are manually deleted beyond each baseline's own realized
     ppmlhdfe estimation sample.

 Input:
   03_intermediate/03_Mobility/runtime/core/LB/analysis_prepared.dta

 Outputs:
   08_sensitivity/03_ppml_bias_correction/
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
global OUTROOT  "${ROOT}/05_output/03_Mobility/02_empirical_analysis/02_sensitivity/03_ppml_bias_correction"
global TABLES   "${OUTROOT}/tables"
global DIAG     "${ROOT}/05_output/03_Mobility/01_diagnostics/sensitivity/03_ppml_bias_correction"
global LOGS     "${ROOT}/05_output/03_Mobility/03_logs/sensitivity/03_ppml_bias_correction"

capture mkdir "${ROOT}/05_output/03_Mobility/02_empirical_analysis"
capture mkdir "${ROOT}/05_output/03_Mobility/02_empirical_analysis/02_sensitivity"
capture mkdir "${OUTROOT}"
capture mkdir "${TABLES}"
capture mkdir "${DIAG}"
capture mkdir "${LOGS}"

capture log close _all
log using "${LOGS}/03_ppml_bias_correction.log", replace text

* ----------------------------------------------------------------------
* A. Package preflight.
* ----------------------------------------------------------------------
capture which ppmlhdfe
if _rc {
    di as error "Required command missing: ppmlhdfe"
    exit 199
}

capture which ppml_fe_bias
if _rc {
    di as error "Required command missing: ppml_fe_bias"
    di as error "Run INSTALL_STATA_PACKAGES.bat, then rerun Step 3."
    exit 199
}

capture which hdfe
if _rc {
    di as error "Required dependency missing: hdfe"
    di as error "Run INSTALL_STATA_PACKAGES.bat."
    exit 199
}

capture which gtools
if _rc {
    di as error "Required dependency missing: gtools"
    di as error "Run INSTALL_STATA_PACKAGES.bat."
    exit 199
}

capture findfile lrowmat_utils.mlib
if _rc {
    di as error "Required dependency missing: rowmat_utils"
    di as error "Run INSTALL_STATA_PACKAGES.bat."
    exit 199
}

capture which frmttable
if _rc {
    di as error "Required dependency missing: frmttable/outreg"
    di as error "Run INSTALL_STATA_PACKAGES.bat."
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
capture which estadd
if _rc {
    di as error "Required command missing: estadd (estout package)"
    exit 199
}

which ppml_fe_bias

* ----------------------------------------------------------------------
* B. Load the successful LB prepared data.
* ----------------------------------------------------------------------
capture confirm file "${INDATA}"
if _rc {
    di as error "Prepared LB analysis data not found:"
    di as error "${INDATA}"
    di as error "Run the Phase-2 core LB analysis successfully first."
    exit 601
}

use "${INDATA}", clear
isid year iso3_o iso3_d

foreach v in ///
    year iso3_o iso3_d ///
    v_ttl_k mob_bilat_vis mob_bilat_tour ///
    has_both_vis has_both_tour ///
    exporter_year importer_year pair_id {
    capture confirm variable `v'
    if _rc {
        di as error "Required prepared-data variable missing: `v'"
        exit 111
    }
}

* ppml_fe_bias requires numeric origin/destination identifiers.
* The advisor-prepared LB data may already contain exporter_id/importer_id.
* Reuse them when present; create them only if absent.
capture confirm variable exporter_id
if _rc {
    egen long exporter_id = group(iso3_o)
}

capture confirm variable importer_id
if _rc {
    egen long importer_id = group(iso3_d)
}

* Validate that any pre-existing IDs are valid one-to-one code mappings.
assert !missing(exporter_id, importer_id)
bysort iso3_o (exporter_id): assert exporter_id[1] == exporter_id[_N]
bysort iso3_d (importer_id): assert importer_id[1] == importer_id[_N]

local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"

eststo clear

* ======================================================================
* C. VISITOR baseline and analytical bias correction.
* ======================================================================
quietly ppmlhdfe v_ttl_k mob_bilat_vis if has_both_vis, ///
    absorb(`FE') vce(cluster `CLUSTER') d

scalar orig_vis_b  = _b[mob_bilat_vis]
scalar orig_vis_se = _se[mob_bilat_vis]
scalar orig_vis_n  = e(N)

gen byte sample_vis_bias = e(sample)
predict double lambda_vis if sample_vis_bias
matrix beta_vis = e(b)

estadd scalar source_N = scalar(orig_vis_n)
eststo ORIG_VIS

* Restrict exactly to the realized baseline e(sample).
ppml_fe_bias v_ttl_k mob_bilat_vis if sample_vis_bias, ///
    i(exporter_id) j(importer_id) t(year) ///
    lambda(lambda_vis) beta(beta_vis) approx

matrix BCV_b = e(b)
matrix BCV_V = e(V)

scalar bc_vis_b  = BCV_b[1,1]
scalar bc_vis_se = sqrt(BCV_V[1,1])
scalar bc_vis_z  = scalar(bc_vis_b) / scalar(bc_vis_se)
scalar bc_vis_p  = 2 * normal(-abs(scalar(bc_vis_z)))
scalar bc_vis_ll = scalar(bc_vis_b) - invnormal(.975) * scalar(bc_vis_se)
scalar bc_vis_ul = scalar(bc_vis_b) + invnormal(.975) * scalar(bc_vis_se)

scalar bias_vis_abs = scalar(orig_vis_b) - scalar(bc_vis_b)
scalar bias_vis_pct_of_orig = 100 * scalar(bias_vis_abs) / scalar(orig_vis_b)
scalar bc_vis_change_pct = 100 * (scalar(bc_vis_b) / scalar(orig_vis_b) - 1)
scalar vis_se_change_pct = 100 * (scalar(bc_vis_se) / scalar(orig_vis_se) - 1)

estadd scalar source_N = scalar(orig_vis_n)
eststo BC_VIS

* ======================================================================
* D. TOURIST baseline and analytical bias correction.
* ======================================================================
quietly ppmlhdfe v_ttl_k mob_bilat_tour if has_both_tour, ///
    absorb(`FE') vce(cluster `CLUSTER') d

scalar orig_tour_b  = _b[mob_bilat_tour]
scalar orig_tour_se = _se[mob_bilat_tour]
scalar orig_tour_n  = e(N)

gen byte sample_tour_bias = e(sample)
predict double lambda_tour if sample_tour_bias
matrix beta_tour = e(b)

estadd scalar source_N = scalar(orig_tour_n)
eststo ORIG_TOUR

ppml_fe_bias v_ttl_k mob_bilat_tour if sample_tour_bias, ///
    i(exporter_id) j(importer_id) t(year) ///
    lambda(lambda_tour) beta(beta_tour) approx

matrix BCT_b = e(b)
matrix BCT_V = e(V)

scalar bc_tour_b  = BCT_b[1,1]
scalar bc_tour_se = sqrt(BCT_V[1,1])
scalar bc_tour_z  = scalar(bc_tour_b) / scalar(bc_tour_se)
scalar bc_tour_p  = 2 * normal(-abs(scalar(bc_tour_z)))
scalar bc_tour_ll = scalar(bc_tour_b) - invnormal(.975) * scalar(bc_tour_se)
scalar bc_tour_ul = scalar(bc_tour_b) + invnormal(.975) * scalar(bc_tour_se)

scalar bias_tour_abs = scalar(orig_tour_b) - scalar(bc_tour_b)
scalar bias_tour_pct_of_orig = 100 * scalar(bias_tour_abs) / scalar(orig_tour_b)
scalar bc_tour_change_pct = 100 * (scalar(bc_tour_b) / scalar(orig_tour_b) - 1)
scalar tour_se_change_pct = 100 * (scalar(bc_tour_se) / scalar(orig_tour_se) - 1)

estadd scalar source_N = scalar(orig_tour_n)
eststo BC_TOUR

* ----------------------------------------------------------------------
* E. Publication-facing original-vs-corrected table.
* ----------------------------------------------------------------------
foreach format in csv rtf {
    local extra ""
    if "`format'" == "csv" local extra "csv"

    esttab ORIG_VIS BC_VIS ORIG_TOUR BC_TOUR ///
        using "${TABLES}/table_ppml_bias_correction.`format'", ///
        replace `extra' ///
        mtitles("Visitor: original" "Visitor: bias-corrected" ///
                "Tourist: original" "Tourist: bias-corrected") ///
        b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(mob_bilat_vis mob_bilat_tour) ///
        order(mob_bilat_vis mob_bilat_tour) ///
        coeflabels(mob_bilat_vis "Bilateral visitors" ///
                   mob_bilat_tour "Bilateral tourists") ///
        stats(source_N, labels("Original realized N") fmt(%12.0fc)) ///
        label compress nogaps ///
        addnotes( ///
            "Original models use exporter-year, importer-year, and directed-pair fixed effects with pair-clustered SEs.", ///
            "Bias-corrected estimates use ppml_fe_bias following Weidner and Zylkin (2021).", ///
            "The adjusted variance uses the package's approximation option for this high-dimensional application.", ///
            "This is a finite-sample bias sensitivity, not a causal-identification correction." ///
        )
}

* ----------------------------------------------------------------------
* F. Machine-readable results.
* ----------------------------------------------------------------------
preserve
    clear
    set obs 2

    gen str16 measure = ""
    replace measure = "visitors" in 1
    replace measure = "tourists" in 2

    gen double original_b = .
    gen double original_se = .
    gen double corrected_b = .
    gen double corrected_se = .
    gen double corrected_z = .
    gen double corrected_p = .
    gen double corrected_ci_l = .
    gen double corrected_ci_u = .
    gen double analytical_bias = .
    gen double bias_pct_of_original = .
    gen double corrected_change_pct = .
    gen double se_change_pct = .
    gen double N = .

    replace original_b  = scalar(orig_vis_b) in 1
    replace original_se = scalar(orig_vis_se) in 1
    replace corrected_b = scalar(bc_vis_b) in 1
    replace corrected_se = scalar(bc_vis_se) in 1
    replace corrected_z = scalar(bc_vis_z) in 1
    replace corrected_p = scalar(bc_vis_p) in 1
    replace corrected_ci_l = scalar(bc_vis_ll) in 1
    replace corrected_ci_u = scalar(bc_vis_ul) in 1
    replace analytical_bias = scalar(bias_vis_abs) in 1
    replace bias_pct_of_original = scalar(bias_vis_pct_of_orig) in 1
    replace corrected_change_pct = scalar(bc_vis_change_pct) in 1
    replace se_change_pct = scalar(vis_se_change_pct) in 1
    replace N = scalar(orig_vis_n) in 1

    replace original_b  = scalar(orig_tour_b) in 2
    replace original_se = scalar(orig_tour_se) in 2
    replace corrected_b = scalar(bc_tour_b) in 2
    replace corrected_se = scalar(bc_tour_se) in 2
    replace corrected_z = scalar(bc_tour_z) in 2
    replace corrected_p = scalar(bc_tour_p) in 2
    replace corrected_ci_l = scalar(bc_tour_ll) in 2
    replace corrected_ci_u = scalar(bc_tour_ul) in 2
    replace analytical_bias = scalar(bias_tour_abs) in 2
    replace bias_pct_of_original = scalar(bias_tour_pct_of_orig) in 2
    replace corrected_change_pct = scalar(bc_tour_change_pct) in 2
    replace se_change_pct = scalar(tour_se_change_pct) in 2
    replace N = scalar(orig_tour_n) in 2

    gen str12 variance_mode = "approx"
    gen str24 estimator = "ppml_fe_bias"
    gen str40 correction = "Weidner-Zylkin analytical correction"

    export delimited using "${DIAG}/ppml_bias_correction_results.csv", replace
restore

* Baseline sample counts for audit.
preserve
    keep if sample_vis_bias | sample_tour_bias
    keep year iso3_o iso3_d pair_id sample_vis_bias sample_tour_bias
    export delimited using "${DIAG}/bias_correction_sample_flags.csv", replace
restore

file open done using "${DIAG}/03_PPML_BIAS_CORRECTION_COMPLETE.txt", write replace text
file write done "PPML_BIAS_CORRECTION_STEP3=PASS" _n

local ovb : display %12.9f scalar(orig_vis_b)
local cvb : display %12.9f scalar(bc_vis_b)
local ovs : display %12.9f scalar(orig_vis_se)
local cvs : display %12.9f scalar(bc_vis_se)
local cvp : display %12.9f scalar(bc_vis_p)

local otb : display %12.9f scalar(orig_tour_b)
local ctb : display %12.9f scalar(bc_tour_b)
local ots : display %12.9f scalar(orig_tour_se)
local cts : display %12.9f scalar(bc_tour_se)
local ctp : display %12.9f scalar(bc_tour_p)

file write done "visitor_original_b=`ovb'" _n
file write done "visitor_corrected_b=`cvb'" _n
file write done "visitor_original_se=`ovs'" _n
file write done "visitor_corrected_se=`cvs'" _n
file write done "visitor_corrected_p=`cvp'" _n
file write done "tourist_original_b=`otb'" _n
file write done "tourist_corrected_b=`ctb'" _n
file write done "tourist_original_se=`ots'" _n
file write done "tourist_corrected_se=`cts'" _n
file write done "tourist_corrected_p=`ctp'" _n
file write done "variance_correction_mode=approx" _n
file close done

di as result "PPML_BIAS_CORRECTION_STEP3=PASS"
di as result "VISITOR original=" %12.9f scalar(orig_vis_b) ///
    " corrected=" %12.9f scalar(bc_vis_b) ///
    " | SE original=" %12.9f scalar(orig_vis_se) ///
    " corrected=" %12.9f scalar(bc_vis_se) ///
    " | corrected p=" %12.9f scalar(bc_vis_p)

di as result "TOURIST original=" %12.9f scalar(orig_tour_b) ///
    " corrected=" %12.9f scalar(bc_tour_b) ///
    " | SE original=" %12.9f scalar(orig_tour_se) ///
    " corrected=" %12.9f scalar(bc_tour_se) ///
    " | corrected p=" %12.9f scalar(bc_tour_p)

log close
