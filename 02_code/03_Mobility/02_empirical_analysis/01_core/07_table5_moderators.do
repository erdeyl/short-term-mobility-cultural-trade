/*******************************************************************************
 Table 5: between-pair slope heterogeneity by common language and cultural
 distance. Time-invariant moderator main effects are absorbed by pair FE.
*******************************************************************************/

version 18.0
use "${CACHE_DIR}/analysis_prepared.dta", clear
local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"

gen double vis_x_comlang = mob_bilat_vis * comlang_off
gen double tour_x_comlang = mob_bilat_tour * comlang_off

quietly summarize cul_dist if !missing(v_ttl_k, mob_bilat_vis, cul_dist)
scalar culdist_mean_vis = r(mean)
gen double culdist_c_vis = cul_dist - scalar(culdist_mean_vis)
gen double vis_x_culdist = mob_bilat_vis * culdist_c_vis

quietly summarize cul_dist if !missing(v_ttl_k, mob_bilat_tour, cul_dist)
scalar culdist_mean_tour = r(mean)
gen double culdist_c_tour = cul_dist - scalar(culdist_mean_tour)
gen double tour_x_culdist = mob_bilat_tour * culdist_c_tour

eststo clear
quietly ppmlhdfe v_ttl_k mob_bilat_vis vis_x_comlang, absorb(`FE') vce(cluster `CLUSTER')
eststo M_lang_v
quietly lincom mob_bilat_vis + vis_x_comlang
scalar common_language_slope_vis = r(estimate)
scalar common_language_slope_vis_se = r(se)

quietly ppmlhdfe v_ttl_k mob_bilat_tour tour_x_comlang, absorb(`FE') vce(cluster `CLUSTER')
eststo M_lang_t
quietly lincom mob_bilat_tour + tour_x_comlang
scalar common_language_slope_tour = r(estimate)
scalar common_language_slope_tour_se = r(se)

quietly ppmlhdfe v_ttl_k mob_bilat_vis vis_x_culdist if !missing(culdist_c_vis), absorb(`FE') vce(cluster `CLUSTER')
eststo M_cul_v
scalar original_culdist_b = _b[vis_x_culdist]
scalar original_culdist_p = 2 * normal(-abs(_b[vis_x_culdist] / _se[vis_x_culdist]))

quietly ppmlhdfe v_ttl_k mob_bilat_tour tour_x_culdist if !missing(culdist_c_tour), absorb(`FE') vce(cluster `CLUSTER')
eststo M_cul_t

foreach format in csv rtf {
    local extra ""
    if "`format'" == "csv" local extra "csv"
    esttab M_lang_v M_lang_t M_cul_v M_cul_t using "${TABLE_DIR}/table5_moderators.`format'", replace `extra' ///
        mtitles("Language visitors" "Language tourists" "CulDist visitors" "CulDist tourists") ///
        b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(mob_bilat_vis mob_bilat_tour vis_x_comlang tour_x_comlang vis_x_culdist tour_x_culdist) ///
        coeflabels(mob_bilat_vis "Bilateral visitors" mob_bilat_tour "Bilateral tourists" ///
                   vis_x_comlang "Visitors x common language" tour_x_comlang "Tourists x common language" ///
                   vis_x_culdist "Visitors x cultural distance" tour_x_culdist "Tourists x cultural distance") ///
        stats(N, labels("N") fmt(%12.0fc)) label compress nogaps ///
        addnotes("Main effects are absorbed by directed-pair FE. Common-language baseline slopes apply to pairs without a common official language.", ///
                 "Cultural distance is centered within each realized model sample. Interactions describe between-pair slope heterogeneity, not mechanisms.")
}

* Influence check documented in the corrected manuscript.
quietly ppmlhdfe v_ttl_k mob_bilat_vis vis_x_culdist ///
    if !missing(culdist_c_vis) & !(iso3_o == "CHN" & iso3_d == "HKG"), ///
    absorb(`FE') vce(cluster `CLUSTER')
scalar no_china_hk_b = _b[vis_x_culdist]
scalar no_china_hk_p = 2 * normal(-abs(_b[vis_x_culdist] / _se[vis_x_culdist]))

quietly ppmlhdfe v_ttl_k mob_bilat_vis if !inlist(year, 2008, 2020), ///
    absorb(`FE') vce(cluster `CLUSTER')
scalar no_crisis_full_b = _b[mob_bilat_vis]
scalar no_crisis_full_p = 2 * normal(-abs(_b[mob_bilat_vis] / _se[mob_bilat_vis]))
quietly ppmlhdfe v_ttl_k mob_bilat_vis ///
    if !inlist(year, 2008, 2020) & !(iso3_o == "CHN" & iso3_d == "HKG"), ///
    absorb(`FE') vce(cluster `CLUSTER')
scalar no_crisis_no_china_hk_b = _b[mob_bilat_vis]
scalar no_crisis_no_china_hk_p = 2 * normal(-abs(_b[mob_bilat_vis] / _se[mob_bilat_vis]))

file open influence using "${DIAG_DIR}/moderator-influence-results.csv", write replace
file write influence "result,value" _n
foreach result in common_language_slope_vis common_language_slope_tour ///
    original_culdist_b original_culdist_p no_china_hk_b no_china_hk_p ///
    no_crisis_full_b no_crisis_full_p no_crisis_no_china_hk_b no_crisis_no_china_hk_p {
    local result_text : display %12.9f scalar(`result')
    file write influence "`result',`result_text'" _n
}
file close influence

display as result "COMMON_LANGUAGE_SLOPE_VIS=" %12.9f scalar(common_language_slope_vis)
display as result "COMMON_LANGUAGE_SLOPE_TOUR=" %12.9f scalar(common_language_slope_tour)
display as result "CULDIST_NO_CHINA_HK_B=" %12.9f scalar(no_china_hk_b) " P=" %12.9f scalar(no_china_hk_p)
display as result "NO_CRISIS_VISITOR_FULL_B=" %12.9f scalar(no_crisis_full_b) " P=" %12.9f scalar(no_crisis_full_p)
display as result "NO_CRISIS_VISITOR_NO_CHINA_HK_B=" %12.9f scalar(no_crisis_no_china_hk_b) " P=" %12.9f scalar(no_crisis_no_china_hk_p)
display as result "TABLE5_COMPLETE=yes"
