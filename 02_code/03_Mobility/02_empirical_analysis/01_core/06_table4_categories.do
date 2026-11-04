/*******************************************************************************
 Table 4: category-specific PPML associations, direct coefficient-equality
 tests, and category shares. Significance patterns are not treated as tests of
 coefficient differences.
*******************************************************************************/

version 18.0
use "${CACHE_DIR}/analysis_prepared.dta", clear
local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"

eststo clear
local catmodels ""
foreach spec in 3706 49 8523 97 {
    quietly ppmlhdfe v_`spec'_k mob_bilat_vis, absorb(`FE') vce(cluster `CLUSTER')
    eststo C`spec'_v
    quietly ppmlhdfe v_`spec'_k mob_bilat_tour, absorb(`FE') vce(cluster `CLUSTER')
    eststo C`spec'_t
    local catmodels `catmodels' C`spec'_v C`spec'_t
}

foreach format in csv rtf {
    local extra ""
    if "`format'" == "csv" local extra "csv"
    esttab `catmodels' using "${TABLE_DIR}/table4_category_heterogeneity.`format'", replace `extra' ///
        mtitles("Audiovisual V" "Audiovisual T" "Publications V" "Publications T" ///
                "Recorded media V" "Recorded media T" "Artworks V" "Artworks T") ///
        b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(mob_bilat_vis mob_bilat_tour) ///
        coeflabels(mob_bilat_vis "Bilateral visitors" mob_bilat_tour "Bilateral tourists") ///
        stats(N, labels("N") fmt(%12.0fc)) label compress nogaps ///
        addnotes("All models include exporter-year, importer-year, and directed-pair fixed effects and cluster by directed pair.", ///
                 "Category samples and value shares differ; coefficients should not be ranked by significance alone.")
}

* Baseline realized supports for value-share accounting.
quietly ppmlhdfe v_ttl_k mob_bilat_vis, absorb(`FE') vce(cluster `CLUSTER')
gen byte baseline_vis_sample = e(sample)
quietly ppmlhdfe v_ttl_k mob_bilat_tour, absorb(`FE') vce(cluster `CLUSTER')
gen byte baseline_tour_sample = e(sample)

file open shares using "${DIAG_DIR}/category-value-shares.csv", write replace
file write shares "category,support,share_percent" _n
foreach category in v_3706_k v_49_k v_8523_k v_97_k {
    foreach support in full visitor tourist {
        local condition "!missing(v_ttl_k)"
        if "`support'" == "visitor" local condition "baseline_vis_sample"
        if "`support'" == "tourist" local condition "baseline_tour_sample"
        quietly summarize `category' if `condition', meanonly
        scalar category_sum = r(sum)
        quietly summarize v_ttl_k if `condition', meanonly
        scalar category_share = 100 * scalar(category_sum) / r(sum)
        local category_share_text : display %12.6f scalar(category_share)
        file write shares "`category',`support',`category_share_text'" _n
        display as result "CATEGORY_SHARE category=`category' support=`support' percent=" %12.6f scalar(category_share)
    }
}
file close shares

* Direct four-category equality tests from a stacked PPML model.
tempfile base cat1 cat2 cat3 cat4
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
    quietly test (1.category#c.`mobility' = 2.category#c.`mobility') ///
        (1.category#c.`mobility' = 3.category#c.`mobility') ///
        (1.category#c.`mobility' = 4.category#c.`mobility')
    display as result "CATEGORY_EQUALITY mobility=`mobility' P=" %12.9f r(p)
}

display as result "TABLE4_COMPLETE=yes"
