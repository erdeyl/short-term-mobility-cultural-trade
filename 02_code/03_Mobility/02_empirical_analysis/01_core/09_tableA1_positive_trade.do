/*******************************************************************************
 Appendix Table A1: positive-trade presence diagnostic (linear probability).
*******************************************************************************/

version 18.0
use "${CACHE_DIR}/analysis_prepared.dta", clear
local FE "exporter_year importer_year pair_id"

eststo clear
quietly reghdfe positive_trade mob_bilat_vis, absorb(`FE') vce(cluster pair_id)
eststo A1_vis
quietly reghdfe positive_trade mob_bilat_tour, absorb(`FE') vce(cluster pair_id)
eststo A1_tour

foreach format in csv rtf {
    local extra ""
    if "`format'" == "csv" local extra "csv"
    esttab A1_vis A1_tour using "${TABLE_DIR}/tableA1_positive_trade_presence.`format'", replace `extra' ///
        mtitles("Bilateral visitors" "Bilateral tourists") ///
        b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(mob_bilat_vis mob_bilat_tour) ///
        coeflabels(mob_bilat_vis "Bilateral visitors" mob_bilat_tour "Bilateral tourists") ///
        stats(N r2_a, labels("N" "Adjusted R2") fmt(%12.0fc %9.3f)) ///
        label compress nogaps ///
        addnotes("The dependent variable equals one if positive cultural-goods trade is observed and zero otherwise.", ///
                 "This is a positive-trade presence diagnostic, not a first-entry or re-entry model.", ///
                 "All models include exporter-year, importer-year, and directed-pair fixed effects and cluster by directed pair.")
}

display as result "TABLEA1_COMPLETE=yes"

