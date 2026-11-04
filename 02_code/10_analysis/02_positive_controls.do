/*******************************************************************************
 02_positive_controls.do  --  re-estimate the published tables on prepared.dta and
 compare with the published numbers.  Fail closed.
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do 02_positive_controls.do <submitted|corrected>

 The ORIGINAL do-files are executed unmodified from the vintage's own code tree
 (${VROOT}/02_code/03_Mobility/02_empirical_analysis/01_core/04-09 and 02_sensitivity/01-02;
 STUDENT and COPY copies are byte-identical, cmp 2026-11-03), so the specifications are
 verbatim by construction. Their inputs are redirected to prepared.dta through symbolic
 links named analysis_prepared.dta; their outputs go to ${OUT}/pc/.  Full-precision
 coefficients are harvested from the stored estimates (eststo) and scalars they leave in
 memory; tables/diagnostics they write are parsed by 02a_parse_published.py exactly like
 the published files.
 Tolerance: b, SE within 2e-5 absolute after rounding of the published value
 (allowed = 2e-5 + half a unit of the published last digit), p within 2e-4 (+ rounding),
 N exact.  Help consulted: ppmlhdfe.sthlp (e(N_full), e(num_singletons), e(num_separated)),
 reghdfe.sthlp (e(r2_a), e(num_singletons)), [R] estimates store/restore, [P] postfile,
 [P] shell; pkg_fs.py sharow (sha256 for byte identity).
*******************************************************************************/

args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
global PC "${OUT}/pc"
global ORIG_CORE "${VROOT}/02_code/03_Mobility/02_empirical_analysis/01_core"
global ORIG_SENS "${VROOT}/02_code/03_Mobility/02_empirical_analysis/02_sensitivity"
global PCLOG "${LOGS}/02_positive_controls_${VINTAGE}.log"
confirm file "${PREPARED}"
pkg_py "${CODE}/pkg_fs.py" rmtree "${PC}"
pkg_py "${CODE}/pkg_fs.py" mkdirs "${PC}/cache" "${PC}/tables" "${PC}/diag" "${PC}/root/03_intermediate/03_Mobility/runtime/core/LB"
* directory tree the original sensitivity do-files expect under their PROJECT_ROOT (they mkdir only the leaves)
foreach st in 01_common_support 02_formal_equality {
    pkg_py "${CODE}/pkg_fs.py" mkdirs "${PC}/root/05_output/03_Mobility/02_empirical_analysis/02_sensitivity/`st'/tables" "${PC}/root/05_output/03_Mobility/01_diagnostics/sensitivity/`st'" "${PC}/root/05_output/03_Mobility/03_logs/sensitivity/`st'" "${PC}/root/03_intermediate/03_Mobility/sensitivity/`st'"
}
pkg_py "${CODE}/pkg_fs.py" link "${PREPARED}" "${PC}/cache/analysis_prepared.dta"
pkg_py "${CODE}/pkg_fs.py" link "${PREPARED}" "${PC}/root/03_intermediate/03_Mobility/runtime/core/LB/analysis_prepared.dta"
confirm file "${PC}/cache/analysis_prepared.dta"
confirm file "${PC}/root/03_intermediate/03_Mobility/runtime/core/LB/analysis_prepared.dta"
capture log close _all
log using "${PCLOG}", text replace name(pc)
display as result "PC_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
display as result "ORIG_CORE=${ORIG_CORE}"

*==============================================================================
* 1. Exact common support (original 01_common_support_visitors_tourists.do, unmodified).
*    It runs "clear all" and "capture log close _all" and resets several globals, so the
*    config is re-run and the log re-opened afterwards.
*==============================================================================
do "${ORIG_SENS}/01_common_support_visitors_tourists.do" "${PC}/root"
do "00_config.do" `vintage'
global PC "${OUT}/pc"
global ORIG_CORE "${VROOT}/02_code/03_Mobility/02_empirical_analysis/01_core"
global ORIG_SENS "${VROOT}/02_code/03_Mobility/02_empirical_analysis/02_sensitivity"
global PCLOG "${LOGS}/02_positive_controls_${VINTAGE}.log"
capture log close _all
log using "${PCLOG}", text append name(pc)
tempname H1
postfile `H1' str90 id double value str4 kind using "${PC}/rep_full_cs.dta", replace
local j 0
foreach est in ORIG_VIS ORIG_TOUR CS_VIS CS_TOUR {
    local ++j
    quietly estimates restore `est'
    local var = cond(inlist("`est'", "ORIG_VIS", "CS_VIS"), "mob_bilat_vis", "mob_bilat_tour")
    local lab = cond(inlist("`est'", "ORIG_VIS", "CS_VIS"), "Bilateral visitors", "Bilateral tourists")
    post `H1' ("CS.c`j'.`lab'.b") (_b[`var']) ("b")
    post `H1' ("CS.c`j'.`lab'.se") (_se[`var']) ("se")
    post `H1' ("CS.c`j'.N.N") (e(N)) ("N")
    post `H1' ("CSK.`=cond(strpos("`est'","VIS"),"visitors","tourists")'.`=cond(strpos("`est'","ORIG"),"own","exact")'.b") (_b[`var']) ("b")
    post `H1' ("CSK.`=cond(strpos("`est'","VIS"),"visitors","tourists")'.`=cond(strpos("`est'","ORIG"),"own","exact")'.se") (_se[`var']) ("se")
}
postclose `H1'
do "02b_pc_programs.do"
tempname C1
postfile `C1' ${PC_COUNTS_SPEC} using "${PC}/estimation_counts_cs.dta", replace
local j 0
foreach est in ORIG_VIS ORIG_TOUR CS_VIS CS_TOUR {
    local ++j
    quietly estimates restore `est'
    _hc `C1' "CS.c`j'" "`est'"
}
postclose `C1'

*==============================================================================
* 2. Formal equality (original 02_formal_equality_visitors_tourists.do, unmodified)
*==============================================================================
log close pc
do "${ORIG_SENS}/02_formal_equality_visitors_tourists.do" "${PC}/root"
do "00_config.do" `vintage'
global PC "${OUT}/pc"
global ORIG_CORE "${VROOT}/02_code/03_Mobility/02_empirical_analysis/01_core"
global ORIG_SENS "${VROOT}/02_code/03_Mobility/02_empirical_analysis/02_sensitivity"
global PCLOG "${LOGS}/02_positive_controls_${VINTAGE}.log"
capture log close _all
log using "${PCLOG}", text append name(pc)
tempname H2
postfile `H2' str90 id double value str4 kind using "${PC}/rep_full_fe.dta", replace
quietly estimates restore STACKED
post `H2' ("FE.c1.Bilateral visitors.b") (_b[x_vis]) ("b")
post `H2' ("FE.c1.Bilateral visitors.se") (_se[x_vis]) ("se")
post `H2' ("FE.c1.Bilateral tourists.b") (_b[x_tour]) ("b")
post `H2' ("FE.c1.Bilateral tourists.se") (_se[x_tour]) ("se")
post `H2' ("FE.c1.P-value: visitors = tourists.p") (e(p_equal)) ("p")
post `H2' ("FE.c1.Visitor - tourist slope.b") (e(diff_b)) ("b")
post `H2' ("FE.c1.Original exact-common observations.N") (e(common_N)) ("N")
post `H2' ("FE.c1.Stacked estimation rows.N") (e(N)) ("N")
postclose `H2'
do "02b_pc_programs.do"
tempname C2
postfile `C2' ${PC_COUNTS_SPEC} using "${PC}/estimation_counts_fe.dta", replace
foreach est in SEP_VIS SEP_TOUR STACKED {
    quietly estimates restore `est'
    _hc `C2' "FE.`est'" "`est'"
}
postclose `C2'

*==============================================================================
* 3. Core tables (original 04-09, unmodified) on ${CACHE_DIR}/analysis_prepared.dta
*==============================================================================
global CACHE_DIR "${PC}/cache"
global TABLE_DIR "${PC}/tables"
global DIAG_DIR  "${PC}/diag"

tempname H C
postfile `H' str90 id double value str4 kind using "${PC}/rep_full_core.dta", replace
postfile `C' ${PC_COUNTS_SPEC} using "${PC}/estimation_counts.dta", replace

* ---- Table 2
do "${ORIG_CORE}/04_table2_baseline.do"
local j 0
foreach est in V_bilat V_rev V_same V_horse T_bilat T_rev T_same T_horse {
    local ++j
    _hn `H' `C' T2 `j' `est'
}
_hb `H' T2 1 V_bilat mob_bilat_vis "Bilateral visitors"
_hb `H' T2 2 V_rev   mob_rev_vis   "Reverse visitors"
_hb `H' T2 3 V_same  mob_same_vis  "Same-direction visitors"
_hb `H' T2 4 V_horse mob_rev_vis   "Reverse visitors"
_hb `H' T2 4 V_horse mob_same_vis  "Same-direction visitors"
_hb `H' T2 5 T_bilat mob_bilat_tour "Bilateral tourists"
_hb `H' T2 6 T_rev   mob_rev_tour   "Reverse tourists"
_hb `H' T2 7 T_same  mob_same_tour  "Same-direction tourists"
_hb `H' T2 8 T_horse mob_rev_tour   "Reverse tourists"
_hb `H' T2 8 T_horse mob_same_tour  "Same-direction tourists"
post `H' ("BKR.visitor_b") (scalar(baseline_vis_b)) ("b")
post `H' ("BKR.visitor_se") (scalar(baseline_vis_se)) ("b")
post `H' ("BKR.visitor_n") (scalar(baseline_vis_n)) ("N")
post `H' ("BKR.tourist_b") (scalar(baseline_tour_b)) ("b")
post `H' ("BKR.tourist_se") (scalar(baseline_tour_se)) ("b")
post `H' ("BKR.tourist_n") (scalar(baseline_tour_n)) ("N")
post `H' ("BKR.visitor_direction_equality_p") (scalar(directional_vis_p)) ("p")
foreach x in vis_b vis_se vis_n tour_b tour_se tour_n {
    local s = subinstr(subinstr("`x'", "vis_", "baseline_vis_", 1), "tour_", "baseline_tour_", 1)
    post `H' ("CVS.validation_`x'") (scalar(`s')) ("`=cond(strpos("`x'","_n"),"N","b")'")
}
* ---- Table 3
do "${ORIG_CORE}/05_table3_dynamic.do"
_hn `H' `C' T3 1 D_vis
_hn `H' `C' T3 2 D_tour
_hb `H' T3 1 D_vis lag_bilat_vis  "Lag bilateral visitors"
_hb `H' T3 1 D_vis mob_bilat_vis  "Bilateral visitors"
_hb `H' T3 1 D_vis lead_bilat_vis "Future bilateral visitors"
_hb `H' T3 2 D_tour lag_bilat_tour  "Lag bilateral tourists"
_hb `H' T3 2 D_tour mob_bilat_tour  "Bilateral tourists"
_hb `H' T3 2 D_tour lead_bilat_tour "Future bilateral tourists"
quietly estimates restore D_vis
post `H' ("T3.c1.Future-mobility p-value.p") (e(p_future)) ("p")
quietly estimates restore D_tour
post `H' ("T3.c2.Future-mobility p-value.p") (e(p_future)) ("p")
post `H' ("LOG.FUTURE_VISITOR_P") (scalar(future_vis_p)) ("p")
post `H' ("LOG.FUTURE_TOURIST_P") (scalar(future_tour_p)) ("p")
* ---- Table 4 (category equality p and shares are parsed from this log / pc/diag)
do "${ORIG_CORE}/06_table4_categories.do"
local j 0
foreach spec in 3706 49 8523 97 {
    local ++j
    _hn `H' `C' T4 `j' C`spec'_v
    _hb `H' T4 `j' C`spec'_v mob_bilat_vis "Bilateral visitors"
    local ++j
    _hn `H' `C' T4 `j' C`spec'_t
    _hb `H' T4 `j' C`spec'_t mob_bilat_tour "Bilateral tourists"
}
* ---- Table 5
do "${ORIG_CORE}/07_table5_moderators.do"
local j 0
foreach est in M_lang_v M_lang_t M_cul_v M_cul_t {
    local ++j
    _hn `H' `C' T5 `j' `est'
}
_hb `H' T5 1 M_lang_v mob_bilat_vis  "Bilateral visitors"
_hb `H' T5 1 M_lang_v vis_x_comlang  "Visitors x common language"
_hb `H' T5 2 M_lang_t mob_bilat_tour "Bilateral tourists"
_hb `H' T5 2 M_lang_t tour_x_comlang "Tourists x common language"
_hb `H' T5 3 M_cul_v  mob_bilat_vis  "Bilateral visitors"
_hb `H' T5 3 M_cul_v  vis_x_culdist  "Visitors x cultural distance"
_hb `H' T5 4 M_cul_t  mob_bilat_tour "Bilateral tourists"
_hb `H' T5 4 M_cul_t  tour_x_culdist "Tourists x cultural distance"
foreach r in common_language_slope_vis common_language_slope_tour original_culdist_b original_culdist_p ///
    no_china_hk_b no_china_hk_p no_crisis_full_b no_crisis_full_p no_crisis_no_china_hk_b no_crisis_no_china_hk_p {
    post `H' ("MIR.`r'") (scalar(`r')) ("`=cond(substr("`r'",-2,2)=="_p","p","b")'")
}
* ---- Table 6
do "${ORIG_CORE}/08_table6_robustness.do"
local j 0
foreach est in R_tw_v R_tw_t R_top_v R_top_t R_crisis_v R_crisis_t R_fta_v R_fta_t {
    local ++j
    _hn `H' `C' T6 `j' `est'
    local var = cond(substr("`est'", -1, 1) == "v", "mob_bilat_vis", "mob_bilat_tour")
    local lab = cond(substr("`est'", -1, 1) == "v", "Bilateral visitors", "Bilateral tourists")
    _hb `H' T6 `j' `est' `var' "`lab'"
}
_hb `H' T6 7 R_fta_v fta_wto "RTA/FTA indicator"
_hb `H' T6 8 R_fta_t fta_wto "RTA/FTA indicator"
* ---- Table A1
do "${ORIG_CORE}/09_tableA1_positive_trade.do"
_hn `H' `C' TA1 1 A1_vis
_hn `H' `C' TA1 2 A1_tour
_hb `H' TA1 1 A1_vis  mob_bilat_vis  "Bilateral visitors"
_hb `H' TA1 2 A1_tour mob_bilat_tour "Bilateral tourists"
quietly estimates restore A1_vis
post `H' ("TA1.c1.Adjusted R2.r2") (e(r2_a)) ("r2")
quietly estimates restore A1_tour
post `H' ("TA1.c2.Adjusted R2.r2") (e(r2_a)) ("r2")

* ---- 3b. Fits that the original code runs but does not store: re-run verbatim to assert
*      e(converged)==1 and record counts (06_table4_categories.do:37,39,61-82;
*      07_table5_moderators.do:11-22,61-75). The CS iteration fits are asserted in 01_prep.do.
use "${CACHE_DIR}/analysis_prepared.dta", clear
local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"
quietly ppmlhdfe v_ttl_k mob_bilat_vis, absorb(`FE') vce(cluster `CLUSTER')          // 06:37
_hc `C' "T4.share_vis" "unstored"
quietly ppmlhdfe v_ttl_k mob_bilat_tour, absorb(`FE') vce(cluster `CLUSTER')         // 06:39
_hc `C' "T4.share_tour" "unstored"
gen double vis_x_comlang = mob_bilat_vis * comlang_off                                 // 07:11-22
gen double tour_x_comlang = mob_bilat_tour * comlang_off
quietly summarize cul_dist if !missing(v_ttl_k, mob_bilat_vis, cul_dist)
scalar culdist_mean_vis = r(mean)
gen double culdist_c_vis = cul_dist - scalar(culdist_mean_vis)
gen double vis_x_culdist = mob_bilat_vis * culdist_c_vis
quietly ppmlhdfe v_ttl_k mob_bilat_vis vis_x_culdist ///
    if !missing(culdist_c_vis) & !(iso3_o == "CHN" & iso3_d == "HKG"), ///
    absorb(`FE') vce(cluster `CLUSTER')                                                 // 07:61-63
_hc `C' "T5.infl_noCHNHKG" "unstored"
quietly ppmlhdfe v_ttl_k mob_bilat_vis if !inlist(year, 2008, 2020), ///
    absorb(`FE') vce(cluster `CLUSTER')                                                 // 07:67-68
_hc `C' "T5.infl_nocrisis" "unstored"
quietly ppmlhdfe v_ttl_k mob_bilat_vis ///
    if !inlist(year, 2008, 2020) & !(iso3_o == "CHN" & iso3_d == "HKG"), ///
    absorb(`FE') vce(cluster `CLUSTER')                                                 // 07:71-73
_hc `C' "T5.infl_nocrisis_noCHNHKG" "unstored"
tempfile base cat1 cat2 cat3 cat4                                                       // 06:61-79
save `"`base'"', replace
local outcomes "v_3706_k v_49_k v_8523_k v_97_k"
local k = 0
foreach outcome of local outcomes {
    local ++k
    use `"`base'"', clear
    gen byte category = `k'
    gen double stacked_trade = `outcome'
    keep stacked_trade mob_bilat_vis mob_bilat_tour exporter_year importer_year pair_id category
    save `"`cat`k''"', replace
}
use `"`cat1'"', clear
append using `"`cat2'"' `"`cat3'"' `"`cat4'"'
foreach mobility in mob_bilat_vis mob_bilat_tour {
    quietly ppmlhdfe stacked_trade ibn.category#c.`mobility', ///
        absorb(category#exporter_year category#importer_year category#pair_id) ///
        vce(cluster pair_id) noconstant
    _hc `C' "T4.stack_`=substr("`mobility'",11,.)'" "unstored"
    quietly test (1.category#c.`mobility' = 2.category#c.`mobility') ///
        (1.category#c.`mobility' = 3.category#c.`mobility') ///
        (1.category#c.`mobility' = 4.category#c.`mobility')
    post `H' ("LOG.CATEGORY_EQUALITY.`mobility'") (r(p)) ("p")
}

* ---- counts on prepared.dta: support ledger, validation rows, hierarchy count, sample flags
use "${PREPARED}", clear
post `H' ("CVS.validation_rows") (_N) ("N")
foreach item in rev_vis same_vis both_vis rev_tour same_tour both_tour {
    quietly count if has_`item'
    post `H' ("SUP.`item'") (r(N)) ("N")
}
quietly count if has_both_vis
post `H' ("CVS.validation_strict_vis") (r(N)) ("N")
quietly count if has_both_tour
post `H' ("CVS.validation_strict_tour") (r(N)) ("N")
quietly count if !missing(v_ttl_k)
post `H' ("SUP.trade_nonmissing") (r(N)) ("N")
quietly count if !missing(visitors, tourists) & visitors < tourists
post `H' ("LOG.VISITOR_TOURIST_HIERARCHY_VIOLATIONS") (r(N)) ("N")
foreach f in s_base_vis s_base_tour s_dyn_vis s_dyn_tour s_lang_vis s_lang_tour s_cd_vis s_cd_tour s_cs_exact {
    quietly count if `f' == 1
    post `H' ("FLAG.`f'") (r(N)) ("N")
}
* the flags must also BE the realized samples, not only have the right size
use "${PC}/root/03_intermediate/03_Mobility/sensitivity/01_common_support/common_support_vt_exact.dta", clear
keep year iso3_o iso3_d
gen byte __in_orig_cs = 1
tempfile csorig
save `"`csorig'"', replace
use year iso3_o iso3_d s_cs_exact using "${PREPARED}", clear
merge 1:1 year iso3_o iso3_d using `"`csorig'"', nogen
quietly count if (s_cs_exact == 1) != (__in_orig_cs == 1)
post `H' ("FLAGID.s_cs_exact_vs_original_common_support_file") (r(N)) ("N")
postclose `H'
postclose `C'
use "${PC}/estimation_counts.dta", clear
append using "${PC}/estimation_counts_cs.dta" "${PC}/estimation_counts_fe.dta"
assert converged == 1
export delimited using "${OUT}/pc_estimation_counts.csv", replace
quietly count
display as result "PC_FITS_RECORDED_ALL_CONVERGED=" r(N)

*==============================================================================
* 4. Byte identity of the reproduced esttab tables with the published ones (sha256 via shasum)
*==============================================================================
local SENS "${PC}/root/05_output/03_Mobility/02_empirical_analysis/02_sensitivity"
* published submitted files were written on Windows (CRLF line ends); identity is reported
* byte-for-byte and after removing carriage returns (tr -d '\r').
pkg_py "${CODE}/pkg_fs.py" shaheader "${PC}/table_sha.csv"
foreach t in table2_baseline_regression table3_dynamic_future_checks table4_category_heterogeneity ///
    table5_moderators table6_robustness tableA1_positive_trade_presence {
    pkg_py "${CODE}/pkg_fs.py" sharow "${PC}/table_sha.csv" "`t'" "${PUB_TAB}/`t'.csv" "${PC}/tables/`t'.csv"
}
pkg_py "${CODE}/pkg_fs.py" sharow "${PC}/table_sha.csv" "table_common_support_visitors_tourists" "${PUB_CS_TAB}" "`SENS'/01_common_support/tables/table_common_support_visitors_tourists.csv"
pkg_py "${CODE}/pkg_fs.py" sharow "${PC}/table_sha.csv" "table_formal_equality_visitors_tourists" "${PUB_FE_TAB}" "`SENS'/02_formal_equality/tables/table_formal_equality_visitors_tourists.csv"
import delimited using "${PC}/table_sha.csv", varnames(1) stringcols(_all) clear
assert _N == 8
assert strlen(pub_sha256) == 64 & strlen(rep_sha256) == 64 & strlen(pub_sha256_nocr) == 64
gen str8 identical_bytes = cond(pub_sha256 == rep_sha256, "yes", "no")
gen str8 identical = cond(pub_sha256_nocr == rep_sha256_nocr, "yes", "no")
label variable identical "Identical after removing carriage returns (CRLF vs LF)"
list, noobs clean
save "${PC}/table_identity.dta", replace
export delimited using "${OUT}/pc_table_identity.csv", replace

*==============================================================================
* 5. Published and reproduced registers (same parser), comparison, verdict
*==============================================================================
log close pc
local RR "${PC}/root/05_output/03_Mobility"
pkg_py "${CODE}/02a_parse_published.py" "${PC}/published_register.csv" "${PUB_TAB}" "${PUB_DIAG}" "${PUB_CS}" "${PUB_FE}" "${PUB_LOG}" "${PUB_CS_TAB}" "${PUB_FE_TAB}" > "${LOGS}/02a_parse_published_${VINTAGE}.log" 2>&1
pkg_py "${CODE}/02a_parse_published.py" "${PC}/reproduced_register.csv" "${PC}/tables" "${PC}/diag" "`RR'/01_diagnostics/sensitivity/01_common_support" "`RR'/01_diagnostics/sensitivity/02_formal_equality" "${PCLOG}" "`RR'/02_empirical_analysis/02_sensitivity/01_common_support/tables/table_common_support_visitors_tourists.csv" "`RR'/02_empirical_analysis/02_sensitivity/02_formal_equality/tables/table_formal_equality_visitors_tourists.csv" lenient >> "${LOGS}/02a_parse_published_${VINTAGE}.log" 2>&1
log using "${PCLOG}", text append name(pc)
confirm file "${PC}/published_register.csv"
confirm file "${PC}/reproduced_register.csv"

import delimited using "${PC}/reproduced_register.csv", varnames(1) stringcols(1 4 5) asdouble clear
rename value rep_disp
keep id rep_disp
tempfile rdisp
save `"`rdisp'"', replace
use "${PC}/rep_full_core.dta", clear
append using "${PC}/rep_full_cs.dta" "${PC}/rep_full_fe.dta"
rename value rep_full
drop kind
isid id
tempfile rfull
save `"`rfull'"', replace
import delimited using "${PC}/published_register.csv", varnames(1) stringcols(1 4 5) asdouble clear
rename value published
isid id
merge 1:1 id using `"`rfull'"', keep(master match) gen(_m_full)
merge 1:1 id using `"`rdisp'"', keep(master match) gen(_m_disp)
* reproduced-only identity checks (expected 0 mismatching rows)
preserve
    use `"`rfull'"', clear
    keep if substr(id, 1, 7) == "FLAGID."
    gen double published = 0
    gen byte decimals = 0
    gen str4 kind = "N"
    gen str60 source = "expected zero mismatches (identity check)"
    tempfile flagid
    save `"`flagid'"', replace
restore
append using `"`flagid'"'
gen double reproduced = cond(!missing(rep_full), rep_full, rep_disp)
gen str12 repro_source = cond(!missing(rep_full), "full", cond(!missing(rep_disp), "output_file", "MISSING"))
gen double diff = reproduced - published
gen double half_unit = cond(decimals < 6, 0.5 * 10^(-decimals), 0)
gen double tolerance = cond(kind == "N", 0, cond(kind == "p", 2e-4, 2e-5) + half_unit)
gen str4 result = cond(!missing(reproduced) & abs(diff) <= tolerance + 1e-12, "PASS", "FAIL")
* display identity of the rounded cell (informational): reproduced rounded like the published value
gen str8 display_match = ""
replace display_match = cond(real(string(reproduced, "%20." + string(decimals) + "f")) == published, "yes", "no") if decimals < 6 & !missing(reproduced)
rename id item
order item published reproduced diff result kind decimals tolerance repro_source display_match source
keep item published reproduced diff result kind decimals tolerance repro_source display_match source
sort item
format published reproduced %20.12g
format diff %12.3e
export delimited using "${OUT}/positive_controls.csv", replace
quietly count
local n_all = r(N)
quietly count if result == "FAIL"
local n_fail = r(N)
quietly count if display_match == "no"
local n_disp = r(N)
list item published reproduced diff result if result == "FAIL", noobs clean
list item published reproduced diff if display_match == "no", noobs clean
display as result "POSITIVE_CONTROLS vintage=${VINTAGE} items=`n_all' FAIL=`n_fail' display_mismatch=`n_disp'"
use "${PC}/table_identity.dta", clear
quietly count if identical == "no"
display as result "TABLE_IDENTITY_AFTER_CR_STRIP_NOT_IDENTICAL=" r(N)
local n_tab_diff = r(N)
quietly count if identical_bytes == "no"
display as result "TABLE_BYTE_IDENTITY_NOT_IDENTICAL=" r(N) " (CRLF line ends in Windows-written published files count here)"
if `n_tab_diff' > 0 {
    display as error "`n_tab_diff' reproduced table(s) differ in content from the published table(s)."
    local n_fail = `n_fail' + `n_tab_diff'
}
if `n_fail' > 0 & inlist("${VINTAGE}", "corrected2", "corrected2x") {
    * Replication package: corrected2 / corrected2x are compared with the corrected outputs, so differences
    * are expected by design (00_config.do). The run that produced the reported results stopped here with
    * r(459), which its launcher tolerated for these two vintages; the package reports and continues.
    display as result "POSITIVE_CONTROLS_REFERENCE vintage=${VINTAGE}: `n_fail' of `n_all' items differ from corrected (expected by design)"
    log close pc
    exit, clear
}
if `n_fail' > 0 {
    display as error "POSITIVE CONTROLS FAILED (`n_fail' of `n_all'). Do not use prepared.dta until resolved."
    log close pc
    exit 459
}
display as result "POSITIVE_CONTROLS=PASS vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close pc
exit, clear
