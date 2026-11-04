/*******************************************************************************
 Table 1: delivered-unit descriptive statistics.
*******************************************************************************/

version 18.0
use "${CACHE_DIR}/analysis_prepared.dta", clear

local table1_vars v_ttl_k bilat_vis_raw rev_vis_raw same_vis_raw ///
    bilat_tour_raw rev_tour_raw same_tour_raw ln_dist contig comlang_off ///
    comcol col45 comrelig cul_dist

label variable ln_dist "Ln distance"
label variable contig "Contiguity"
label variable comlang_off "Common language"
label variable comcol "Common colonizer"
label variable col45 "Colonial relationship after 1945"
label variable comrelig "Common religion"
label variable cul_dist "Cultural distance"

estpost summarize `table1_vars'
esttab using "${TABLE_DIR}/table1_descriptive_statistics.csv", replace csv ///
    cells("count(fmt(0)) sd(fmt(3)) min(fmt(3)) mean(fmt(3)) max(fmt(3))") ///
    label nonumber nomtitle noobs
esttab using "${TABLE_DIR}/table1_descriptive_statistics.rtf", replace ///
    cells("count(fmt(0)) sd(fmt(3)) min(fmt(3)) mean(fmt(3)) max(fmt(3))") ///
    label nonumber nomtitle noobs ///
    title("Table 1. Descriptive statistics of variables") ///
    addnotes("Monetary values are in delivered data units; mobility is reported in delivered person-unit convention.", ///
             "N counts directed dyad-year observations, not unique pairs. Reverse and same-direction rows are reciprocal re-indexings of the same source series.")

quietly count if !missing(bilat_vis_raw)
display as result "TABLE1_BILATERAL_VISITOR_N=" r(N)
quietly count if !missing(bilat_tour_raw)
display as result "TABLE1_BILATERAL_TOURIST_N=" r(N)
display as result "TABLE1_COMPLETE=yes"

