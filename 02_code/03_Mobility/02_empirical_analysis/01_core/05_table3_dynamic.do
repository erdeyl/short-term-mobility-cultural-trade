/*******************************************************************************
 Table 3: lagged, contemporaneous, and future-mobility timing diagnostics.
*******************************************************************************/

version 18.0
use "${CACHE_DIR}/analysis_prepared.dta", clear
local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"

xtset pair_id year, yearly
sort pair_id year

eststo clear
quietly ppmlhdfe v_ttl_k lag_bilat_vis mob_bilat_vis lead_bilat_vis, absorb(`FE') vce(cluster `CLUSTER')
eststo D_vis
quietly test lead_bilat_vis
estadd scalar p_future = r(p)
scalar future_vis_p = r(p)

quietly ppmlhdfe v_ttl_k lag_bilat_tour mob_bilat_tour lead_bilat_tour, absorb(`FE') vce(cluster `CLUSTER')
eststo D_tour
quietly test lead_bilat_tour
estadd scalar p_future = r(p)
scalar future_tour_p = r(p)

local coeflabels ///
    lag_bilat_vis "Lag bilateral visitors" ///
    mob_bilat_vis "Bilateral visitors" ///
    lead_bilat_vis "Future bilateral visitors" ///
    lag_bilat_tour "Lag bilateral tourists" ///
    mob_bilat_tour "Bilateral tourists" ///
    lead_bilat_tour "Future bilateral tourists"

foreach format in csv rtf {
    local extra ""
    if "`format'" == "csv" local extra "csv"
    esttab D_vis D_tour using "${TABLE_DIR}/table3_dynamic_future_checks.`format'", replace `extra' ///
        mtitles("Visitors" "Tourists") b(%9.3f) se(%9.3f) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        keep(lag_bilat_vis mob_bilat_vis lead_bilat_vis lag_bilat_tour mob_bilat_tour lead_bilat_tour) ///
        order(lag_bilat_vis mob_bilat_vis lead_bilat_vis lag_bilat_tour mob_bilat_tour lead_bilat_tour) ///
        coeflabels(`coeflabels') ///
        stats(p_future N, labels("Future-mobility p-value" "N") fmt(%9.3f %12.0fc)) ///
        label compress nogaps ///
        addnotes("Leads are timing diagnostics, not causal tests. Visitor and tourist columns use different realized supports.")
}

display as result "FUTURE_VISITOR_P=" %12.9f scalar(future_vis_p)
display as result "FUTURE_TOURIST_P=" %12.9f scalar(future_tour_p)
display as result "TABLE3_COMPLETE=yes"

