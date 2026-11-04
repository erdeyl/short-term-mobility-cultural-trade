/*******************************************************************************
 Table 2: baseline PPML and directional decomposition.

 Column labels follow the verified trade-row direction mapping. The visitor and
 tourist samples remain distinct. Pseudo-R2 is intentionally not exported.
*******************************************************************************/

version 18.0
use "${CACHE_DIR}/analysis_prepared.dta", clear
local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"

eststo clear

quietly ppmlhdfe v_ttl_k mob_bilat_vis if has_both_vis, absorb(`FE') vce(cluster `CLUSTER')
eststo V_bilat
scalar baseline_vis_b = _b[mob_bilat_vis]
scalar baseline_vis_se = _se[mob_bilat_vis]
scalar baseline_vis_n = e(N)

quietly ppmlhdfe v_ttl_k mob_rev_vis if has_both_vis, absorb(`FE') vce(cluster `CLUSTER')
eststo V_rev
quietly ppmlhdfe v_ttl_k mob_same_vis if has_both_vis, absorb(`FE') vce(cluster `CLUSTER')
eststo V_same
quietly ppmlhdfe v_ttl_k mob_rev_vis mob_same_vis if has_both_vis, absorb(`FE') vce(cluster `CLUSTER')
eststo V_horse
quietly test mob_rev_vis = mob_same_vis
scalar directional_vis_p = r(p)

quietly ppmlhdfe v_ttl_k mob_bilat_tour if has_both_tour, absorb(`FE') vce(cluster `CLUSTER')
eststo T_bilat
scalar baseline_tour_b = _b[mob_bilat_tour]
scalar baseline_tour_se = _se[mob_bilat_tour]
scalar baseline_tour_n = e(N)

quietly ppmlhdfe v_ttl_k mob_rev_tour if has_both_tour, absorb(`FE') vce(cluster `CLUSTER')
eststo T_rev
quietly ppmlhdfe v_ttl_k mob_same_tour if has_both_tour, absorb(`FE') vce(cluster `CLUSTER')
eststo T_same
quietly ppmlhdfe v_ttl_k mob_rev_tour mob_same_tour if has_both_tour, absorb(`FE') vce(cluster `CLUSTER')
eststo T_horse

local coeflabels ///
    mob_bilat_vis "Bilateral visitors" ///
    mob_rev_vis "Reverse visitors" ///
    mob_same_vis "Same-direction visitors" ///
    mob_bilat_tour "Bilateral tourists" ///
    mob_rev_tour "Reverse tourists" ///
    mob_same_tour "Same-direction tourists"

foreach format in csv rtf {
    local extra ""
    if "`format'" == "csv" local extra "csv"
    esttab V_bilat V_rev V_same V_horse T_bilat T_rev T_same T_horse ///
        using "${TABLE_DIR}/table2_baseline_regression.`format'", replace `extra' ///
        mtitles("Bilat Vis" "Rev Vis" "Same Vis" "Horse Vis" "Bilat Tour" "Rev Tour" "Same Tour" "Horse Tour") ///
        b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(mob_bilat_vis mob_rev_vis mob_same_vis mob_bilat_tour mob_rev_tour mob_same_tour) ///
        order(mob_bilat_vis mob_rev_vis mob_same_vis mob_bilat_tour mob_rev_tour mob_same_tour) ///
        coeflabels(`coeflabels') stats(N, labels("N") fmt(%12.0fc)) label compress nogaps ///
        addnotes("All models include exporter-year, importer-year, and directed-pair fixed effects; standard errors are clustered by directed pair.", ///
                 "Bilateral mobility is the sum of two observed directions; missing directions are not zero. Cross-column rankings are descriptive.", ///
                 "Pseudo-R2 is omitted because it is not a comparable likelihood statistic across these specifications.")
}

file open key using "${DIAG_DIR}/baseline-key-results.csv", write replace
file write key "result,value" _n
local visitor_b : display %12.9f scalar(baseline_vis_b)
local visitor_se : display %12.9f scalar(baseline_vis_se)
local visitor_n : display %12.0f scalar(baseline_vis_n)
local tourist_b : display %12.9f scalar(baseline_tour_b)
local tourist_se : display %12.9f scalar(baseline_tour_se)
local tourist_n : display %12.0f scalar(baseline_tour_n)
local direction_p : display %12.9f scalar(directional_vis_p)
file write key "visitor_b,`visitor_b'" _n
file write key "visitor_se,`visitor_se'" _n
file write key "visitor_n,`visitor_n'" _n
file write key "tourist_b,`tourist_b'" _n
file write key "tourist_se,`tourist_se'" _n
file write key "tourist_n,`tourist_n'" _n
file write key "visitor_direction_equality_p,`direction_p'" _n
file close key

display as result "BASELINE_VISITOR_B=" %12.9f scalar(baseline_vis_b) " SE=" %12.9f scalar(baseline_vis_se) " N=" scalar(baseline_vis_n)
display as result "BASELINE_TOURIST_B=" %12.9f scalar(baseline_tour_b) " SE=" %12.9f scalar(baseline_tour_se) " N=" scalar(baseline_tour_n)
display as result "DIRECTIONAL_VISITOR_EQUALITY_P=" %12.9f scalar(directional_vis_p)
display as result "TABLE2_COMPLETE=yes"
