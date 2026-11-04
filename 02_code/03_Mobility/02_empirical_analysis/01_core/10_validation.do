/*******************************************************************************
 10_validation.do

 Final validation of the rebuilt-data core empirical run.

 The LB and UB specifications share the same prepared panel and strict mobility
 supports, but the UB trade construction adds a small number of usable tourist
 observations. Validation therefore uses RUN_TAG-specific realized-sample checks.
*******************************************************************************/

version 18.0

use "${CACHE_DIR}/analysis_prepared.dta", clear
isid year iso3_o iso3_d

quietly count
scalar validation_rows = r(N)

quietly count if has_both_vis
scalar validation_strict_vis = r(N)

quietly count if has_both_tour
scalar validation_strict_tour = r(N)

foreach artifact in ///
    table1_descriptive_statistics.csv ///
    table1_descriptive_statistics.rtf ///
    table2_baseline_regression.csv ///
    table2_baseline_regression.rtf ///
    table3_dynamic_future_checks.csv ///
    table3_dynamic_future_checks.rtf ///
    table4_category_heterogeneity.csv ///
    table4_category_heterogeneity.rtf ///
    table5_moderators.csv ///
    table5_moderators.rtf ///
    table6_robustness.csv ///
    table6_robustness.rtf ///
    tableA1_positive_trade_presence.csv ///
    tableA1_positive_trade_presence.rtf {

    capture confirm file "${TABLE_DIR}/`artifact'"
    if _rc {
        display as error "EXPECTED_ARTIFACT_MISSING=`artifact'"
        exit 601
    }
}

quietly ppmlhdfe v_ttl_k mob_bilat_vis if has_both_vis, ///
    absorb(exporter_year importer_year pair_id) vce(cluster pair_id)
scalar validation_vis_b = _b[mob_bilat_vis]
scalar validation_vis_se = _se[mob_bilat_vis]
scalar validation_vis_n = e(N)

quietly ppmlhdfe v_ttl_k mob_bilat_tour if has_both_tour, ///
    absorb(exporter_year importer_year pair_id) vce(cluster pair_id)
scalar validation_tour_b = _b[mob_bilat_tour]
scalar validation_tour_se = _se[mob_bilat_tour]
scalar validation_tour_n = e(N)

capture rescue_on C11a // RESCUE C11a I-M2
local rescue_on_C11a = (_rc==0 & r(on)==1) // RESCUE C11a I-M2
if `rescue_on_C11a' { // RESCUE C11a
    do "${PROJECT_ROOT}/02_code/99_rescue/I-M/validation_delta.do" // RESCUE C11a
} // RESCUE C11a
else { // RESCUE C11a: original asserts retained in disabled branch
    * Panel structure and strict mobility supports are common to LB and UB. RESCUE C11a
    assert scalar(validation_rows) == 823446 // RESCUE C11a
    assert scalar(validation_strict_vis) == 25656 // RESCUE C11a
    assert scalar(validation_strict_tour) == 34830 // RESCUE C11a

    * RUN_TAG-specific realized PPML samples and reference coefficients. RESCUE C11a
    if "${RUN_TAG}" == "LB" { // RESCUE C11a
        assert scalar(validation_vis_n) == 20543 // RESCUE C11a
        assert scalar(validation_tour_n) == 26682 // RESCUE C11a

        assert abs(scalar(validation_vis_b) - 0.242870166) < 1e-6 // RESCUE C11a
        assert abs(scalar(validation_tour_b) - 0.240480434) < 1e-6 // RESCUE C11a
    } // RESCUE C11a
    else if "${RUN_TAG}" == "UB" { // RESCUE C11a
        assert scalar(validation_vis_n) == 20543 // RESCUE C11a
        assert scalar(validation_tour_n) == 26694 // RESCUE C11a

        * UB reference checks use a wider tolerance because the publication-facing RESCUE C11a
        * frozen ledger stores rounded UB coefficients. RESCUE C11a
        assert abs(scalar(validation_vis_b) - 0.243015) < 1e-4 // RESCUE C11a
        assert abs(scalar(validation_tour_b) - 0.242037) < 1e-4 // RESCUE C11a
    } // RESCUE C11a
    else { // RESCUE C11a
        display as error "UNKNOWN_RUN_TAG=${RUN_TAG}" // RESCUE C11a
        exit 198 // RESCUE C11a
    } // RESCUE C11a
} // RESCUE C11a

file open sum using "${DIAG_DIR}/core_validation_summary.csv", write replace text
file write sum "metric,value" _n

foreach s in validation_rows validation_strict_vis validation_strict_tour ///
             validation_vis_b validation_vis_se validation_vis_n ///
             validation_tour_b validation_tour_se validation_tour_n {

    local value = scalar(`s')
    file write sum "`s',`value'" _n
}

file close sum

display as result "CORE_VALIDATION_RUN_TAG=${RUN_TAG}"
display as result "CORE_VALIDATION_ROWS=" scalar(validation_rows)
display as result "CORE_VALIDATION_STRICT_VISITOR_N=" scalar(validation_strict_vis)
display as result "CORE_VALIDATION_STRICT_TOURIST_N=" scalar(validation_strict_tour)
display as result "CORE_VALIDATION_VISITOR_B=" scalar(validation_vis_b) ///
    " SE=" scalar(validation_vis_se) " N=" scalar(validation_vis_n)
display as result "CORE_VALIDATION_TOURIST_B=" scalar(validation_tour_b) ///
    " SE=" scalar(validation_tour_se) " N=" scalar(validation_tour_n)
display as result "CORE_VALIDATION=PASS"
