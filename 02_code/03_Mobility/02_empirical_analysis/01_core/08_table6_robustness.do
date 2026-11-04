/*******************************************************************************
 Table 6: inference, influence, crisis-window, and RTA/FTA sensitivities.
*******************************************************************************/

version 18.0
use "${CACHE_DIR}/analysis_prepared.dta", clear
local FE "exporter_year importer_year pair_id"

tempfile top5
preserve
    collapse (sum) total_cultural_exports = v_ttl_k, by(iso3_o)
    gsort -total_cultural_exports
    gen exporter_rank = _n
    keep if exporter_rank <= 5
    gen byte top5_exporter = 1
    export delimited using "${DIAG_DIR}/top5-exporters.csv", replace
    keep iso3_o top5_exporter
    save `"`top5'"', replace
restore

merge m:1 iso3_o using `"`top5'"', keep(master match) nogen
replace top5_exporter = 0 if missing(top5_exporter)

eststo clear
quietly ppmlhdfe v_ttl_k mob_bilat_vis, absorb(`FE') vce(cluster exporter_id importer_id)
eststo R_tw_v
quietly ppmlhdfe v_ttl_k mob_bilat_tour, absorb(`FE') vce(cluster exporter_id importer_id)
eststo R_tw_t
quietly ppmlhdfe v_ttl_k mob_bilat_vis if top5_exporter == 0, absorb(`FE') vce(cluster pair_id)
eststo R_top_v
quietly ppmlhdfe v_ttl_k mob_bilat_tour if top5_exporter == 0, absorb(`FE') vce(cluster pair_id)
eststo R_top_t
quietly ppmlhdfe v_ttl_k mob_bilat_vis if !inlist(year, 2008, 2020), absorb(`FE') vce(cluster pair_id)
eststo R_crisis_v
quietly ppmlhdfe v_ttl_k mob_bilat_tour if !inlist(year, 2008, 2020), absorb(`FE') vce(cluster pair_id)
eststo R_crisis_t
quietly ppmlhdfe v_ttl_k mob_bilat_vis fta_wto, absorb(`FE') vce(cluster pair_id)
eststo R_fta_v
quietly ppmlhdfe v_ttl_k mob_bilat_tour fta_wto, absorb(`FE') vce(cluster pair_id)
eststo R_fta_t

foreach format in csv rtf {
    local extra ""
    if "`format'" == "csv" local extra "csv"
    esttab R_tw_v R_tw_t R_top_v R_top_t R_crisis_v R_crisis_t R_fta_v R_fta_t ///
        using "${TABLE_DIR}/table6_robustness.`format'", replace `extra' ///
        mtitles("Two-way V" "Two-way T" "Exclude major V" "Exclude major T" ///
                "Exclude year V" "Exclude year T" "RTA/FTA V" "RTA/FTA T") ///
        b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(mob_bilat_vis mob_bilat_tour fta_wto) ///
        coeflabels(mob_bilat_vis "Bilateral visitors" mob_bilat_tour "Bilateral tourists" fta_wto "RTA/FTA indicator") ///
        stats(N, labels("N") fmt(%12.0fc)) label compress nogaps ///
        addnotes("Columns 1-2 use exporter/importer two-way clustering; columns 3-8 cluster by directed pair.", ///
                 "Top-five checks exclude the five largest cultural-goods exporters; crisis checks exclude 2008 and 2020.", ///
                 "RTA/FTA coefficients are imprecise and rely on sparse within-pair switches; they are not policy-effect estimates.")
}

display as result "TABLE6_COMPLETE=yes"

