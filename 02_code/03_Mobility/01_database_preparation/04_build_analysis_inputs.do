/*******************************************************************************
 00_build_estimation_inputs.do

 Purpose:
   Create minimal direct-validation copies of the reconstructed master that expose
   exactly the variable interface required by the frozen core estimation workflow.

 IMPORTANT:
   - The frozen master is NEVER modified.
   - No observations are dropped.
   - Only variables are reduced in the direct-validation copies.
   - LB and UB inputs have identical variable names; only the two cultural-trade
     aliases differ by lower/upper concordance treatment.
*******************************************************************************/

clear all
set more off
version 18.0
set varabbrev off

args PROJECT_ROOT
if `"`PROJECT_ROOT'"' == "" {
    di as error "Supply the replication_build root as argument 1."
    exit 198
}
local PROJECT_ROOT = subinstr(`"`PROJECT_ROOT'"', "\", "/", .)

global ROOT      `"`PROJECT_ROOT'"'
global MASTER    "${ROOT}/03_intermediate/03_Mobility/master/mobility_merged_2007_2021.dta"
global OUTDATA   "${ROOT}/04_analysis data/03_Mobility"
global DIAG      "${ROOT}/05_output/03_Mobility/01_diagnostics/analysis_inputs"
global LOGS      "${ROOT}/05_output/03_Mobility/03_logs/analysis_inputs"

capture mkdir "${ROOT}/04_analysis data"
capture mkdir "${ROOT}/04_analysis data/03_Mobility"
capture mkdir "${OUTDATA}"
capture mkdir "${DIAG}"
capture mkdir "${LOGS}"

capture log close _all
log using "${LOGS}/00_build_estimation_inputs.log", replace text

capture confirm file "${MASTER}"
if _rc {
    di as error "Missing frozen master: ${MASTER}"
    exit 601
}

use "${MASTER}", clear
isid year iso3_o iso3_d
quietly count
local N_master = r(N)

* ----------------------------------------------------------------------
* Required source variables from reconstructed master.
* ----------------------------------------------------------------------
local need_master ///
    year iso3_o iso3_d ///
    tourists_trips visitors_trips ///
    v_ttl_lb_k v_ttl_ub_k ///
    v_3706_k v_49_k v_8523_lb_k v_8523_ub_k v_97_k ///
    dist contig comlang_off comcol col45 ///
    cd6_ge4 fta_wto

foreach v of local need_master {
    capture confirm variable `v'
    if _rc {
        di as error "Required reconstructed-master variable missing: `v'"
        exit 111
    }
}

* ----------------------------------------------------------------------
* The common base already retains comrelig. A missing field is an interface error.
capture confirm variable comrelig
if _rc {
    di as error "Common base must contain comrelig. Rebuild the common module."
    exit 111
}

* ----------------------------------------------------------------------
* estimation-interface aliases.
* These are interface translations, not changes to the reconstructed source data.
* ----------------------------------------------------------------------
* Drop aliases individually because the master may already contain ln_dist
* while other aliases do not yet exist. A combined drop would abort as a whole
* when one listed variable is absent and would leave ln_dist behind (r(110)).
foreach v in tourists visitors v_ttl_k v_8523_k cul_dist ln_dist {
    capture drop `v'
}

gen double tourists = tourists_trips
gen double visitors = visitors_trips

gen double cul_dist = cd6_ge4

* Preserve all observations. CEPII contains a tiny number of non-positive
* distance values; ln_dist is therefore defined only where dist > 0.
quietly count if !missing(dist) & dist <= 0
local N_nonpos_dist = r(N)

preserve
    keep if !missing(dist) & dist <= 0
    keep year iso3_o iso3_d dist
    export delimited using "${DIAG}/nonpositive_distance_rows.csv", replace
restore

gen double ln_dist = ln(dist) if dist > 0

label var tourists "Overnight tourists, trips"
label var visitors "Total visitors, trips"
label var cul_dist "Hofstede cultural distance, cd6_ge4"
label var ln_dist "Ln distance"

* ----------------------------------------------------------------------
* Exact minimal variable interface expected by core empirical workflow.
* ----------------------------------------------------------------------
local estimation_vars ///
    year iso3_o iso3_d ///
    tourists visitors ///
    v_ttl_k v_3706_k v_49_k v_8523_k v_97_k ///
    ln_dist contig comlang_off comcol col45 comrelig cul_dist fta_wto


local rescue_metadata "" // RESCUE C11b C11c C09-M
capture rescue_on C11b // RESCUE C11b I-M2
local rescue_on_C11b = (_rc==0 & r(on)==1) // RESCUE C11b I-M2
if `rescue_on_C11b' { // RESCUE C11b
    local rescue_metadata "conf_sub visitors_source_file visitors_flag visitors_flag_label visitors_notes visitors_release" // RESCUE C11b
    label variable visitors "Visitor-series arrivals, mixed coverage, trips" // RESCUE C11b
} // RESCUE C11b
capture rescue_on C11c // RESCUE C11c I-M2
local rescue_on_C11c = (_rc==0 & r(on)==1) // RESCUE C11c I-M2
if `rescue_on_C11c' { // RESCUE C11c
    local rescue_metadata "`rescue_metadata' tourists_basis visitors_basis tourists_source_file tourists_flag tourists_flag_label tourists_notes tourists_release visitors_source_file visitors_flag visitors_flag_label visitors_notes visitors_release basis_mismatch hierarchy_violation visitors_definition_diff tour_start tour_end tour_span2020 tour_study_switch vis_start vis_end vis_span2020 vis_study_switch regional_proxy_flag_o regional_proxy_flag_d any_regional_proxy common_dim_count6" // RESCUE C11c
} // RESCUE C11c
capture rescue_on C09-M // RESCUE C09-M I-M2
local rescue_on_C09_M = (_rc==0 & r(on)==1) // RESCUE C09-M I-M2
if `rescue_on_C09_M' { // RESCUE C09-M
    local rescue_metadata "`rescue_metadata' france251_component_o france251_component_d france251_component_any" // RESCUE C09-M
} // RESCUE C09-M
capture rescue_on C12 // RESCUE C12 I-M2
local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
if `rescue_on_C12' local rescue_metadata "`rescue_metadata' pry_res_quarantine" // RESCUE C12
local rescue_metadata : list uniq rescue_metadata // RESCUE C11b C11c C09-M
foreach field of local rescue_metadata { // RESCUE C11b C11c C09-M
    confirm variable `field', exact // RESCUE C11b C11c C09-M: installed [P] confirm
} // RESCUE C11b C11c C09-M
local estimation_vars "`estimation_vars' `rescue_metadata'" // RESCUE C11b C11c C09-M

* ----------------------------------------------------------------------
* Variable-level deletion audit.
* The audit is written BEFORE reduction, so every variable in the rebuilt master
* is explicitly accounted for.
* ----------------------------------------------------------------------
ds
local allvars `r(varlist)'

file open va using "${DIAG}/variable_reduction_audit.csv", write replace text
file write va "variable,action_in_minimal_input,reason" _n

foreach v of local allvars {
    local action "DROP_FROM_DIRECT_COPY"
    local reason "Not referenced by the core empirical modules; retained in frozen master."

    if strpos(" year iso3_o iso3_d v_3706_k v_49_k v_97_k contig comlang_off comcol col45 comrelig fta_wto ", " `v' ") {
        local action "KEEP"
        local reason "Directly required by core empirical modules."
    }

    if inlist("`v'","tourists_trips","visitors_trips","cd6_ge4","dist") {
        local action "DROP_AFTER_ALIAS"
        local reason "Used to create estimation-interface alias; original remains in frozen master."
    }

    if inlist("`v'","v_ttl_lb_k","v_ttl_ub_k","v_8523_lb_k","v_8523_ub_k") {
        local action "DROP_AFTER_ALIAS"
        local reason "Used to create LB/UB estimation-interface trade alias; original remains in frozen master."
    }

    if strpos(" `rescue_metadata' ", " `v' ") { // RESCUE C11b C11c C09-M
        local action "KEEP_RESCUE_METADATA" // RESCUE C11b C11c C09-M
        local reason "Enabled ledger metadata; values unchanged." // RESCUE C11b C11c C09-M
    } // RESCUE C11b C11c C09-M
    file write va "`v',`action',`reason'" _n
}

foreach v in tourists visitors v_ttl_k v_8523_k cul_dist ln_dist {
    file write va "`v',CREATE_AND_KEEP,estimation-interface interface variable created from reconstructed source variable." _n
}
file close va

* ----------------------------------------------------------------------
* LOWER-BOUND direct-validation input.
* ----------------------------------------------------------------------
preserve
    gen double v_ttl_k  = v_ttl_lb_k
    gen double v_8523_k = v_8523_lb_k

    label var v_ttl_k  "Cultural-goods trade, lower bound, thousand current USD"
    label var v_8523_k "Recorded media, lower bound, thousand current USD"

    assert v_ttl_k == v_ttl_lb_k if !missing(v_ttl_lb_k)
    assert v_8523_k == v_8523_lb_k if !missing(v_8523_lb_k)

    keep `estimation_vars'
    order `estimation_vars'
    isid year iso3_o iso3_d
    quietly count
    assert r(N) == `N_master'

    save "${OUTDATA}/mobility_analysis_2007_2021.dta", replace
restore

* ----------------------------------------------------------------------
* UPPER-BOUND sensitivity input.
* ----------------------------------------------------------------------
preserve
    gen double v_ttl_k  = v_ttl_ub_k
    gen double v_8523_k = v_8523_ub_k

    label var v_ttl_k  "Cultural-goods trade, upper bound, thousand current USD"
    label var v_8523_k "Recorded media, upper bound, thousand current USD"

    assert v_ttl_k == v_ttl_ub_k if !missing(v_ttl_ub_k)
    assert v_8523_k == v_8523_ub_k if !missing(v_8523_ub_k)

    keep `estimation_vars'
    order `estimation_vars'
    isid year iso3_o iso3_d
    quietly count
    assert r(N) == `N_master'

    save "${OUTDATA}/mobility_analysis_UB_2007_2021.dta", replace
restore

* Compact interface dictionary.
preserve
    clear
    input str20 variable str28 source_variable str90 definition
    "year"       "year"            "Calendar year"
    "iso3_o"     "iso3_o"          "Trade exporter/origin ISO3"
    "iso3_d"     "iso3_d"          "Trade importer/destination ISO3"
    "tourists"   "tourists_trips"  "Reverse-direction overnight tourists in trips"
    "visitors"   "visitors_trips"  "Reverse-direction total visitors in trips"
    "v_ttl_k"    "v_ttl_lb/ub_k"   "Aggregate cultural-goods trade in thousand current USD"
    "v_3706_k"   "v_3706_k"        "Audiovisual category trade"
    "v_49_k"     "v_49_k"          "Publications category trade"
    "v_8523_k"   "v_8523_lb/ub_k"  "Recorded-media category trade"
    "v_97_k"     "v_97_k"          "Artworks category trade"
    "ln_dist"    "ln(dist)"         "Natural log of CEPII bilateral distance"
    "contig"     "contig"           "CEPII contiguity indicator"
    "comlang_off" "comlang_off"     "CEPII common official/primary language"
    "comcol"     "comcol"           "CEPII common colonizer"
    "col45"      "col45"            "CEPII colonial relationship after 1945"
    "comrelig"   "CEPII comrelig"   "CEPII common-religion index retained from the common base"
    "cul_dist"   "cd6_ge4"          "Hofstede bilateral cultural distance; >=4 common dimensions"
    "fta_wto"    "fta_wto"          "CEPII RTA/FTA indicator"
    end
    capture rescue_on C11b // RESCUE C11b I-M2
    local rescue_on_C11b = (_rc==0 & r(on)==1) // RESCUE C11b I-M2
    if `rescue_on_C11b' replace definition = "Reverse-direction visitor-series arrivals; mixed coverage" if variable=="visitors" // RESCUE C11b
    export delimited using "${DIAG}/estimation_variable_interface.csv", replace
restore

file open done using "${DIAG}/00_DIRECT_INPUT_BUILD_COMPLETE.txt", write replace text
file write done "DIRECT_INPUT_BUILD=PASS" _n
file write done "master_rows=`N_master'" _n
file write done "nonpositive_distance_rows=`N_nonpos_dist'" _n
file write done "lb_input=mobility_analysis_2007_2021.dta" _n
file write done "ub_input=mobility_analysis_UB_2007_2021.dta" _n
file close done

di as result "DIRECT_INPUT_BUILD=PASS"
di as result "Rows preserved: `N_master'"
di as result "LB: ${OUTDATA}/mobility_analysis_2007_2021.dta"
di as result "UB: ${OUTDATA}/mobility_analysis_UB_2007_2021.dta"
log close
