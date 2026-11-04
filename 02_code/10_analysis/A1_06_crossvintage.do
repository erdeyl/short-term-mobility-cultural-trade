/*******************************************************************************
 A1_06_crossvintage.do  --  A1.5 (iii) and the measure-change comparison (analysis block A1)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do A1_06_crossvintage.do corrected
 Reads both prepared.dta files (read only). Rows are posted with vintage = "both" into
 out/corrected/results/A1_parts/A1_06.csv; table out/corrected/tables/A1_A1.5_vintage_diff.csv.
 The vintages differ in (a) the C12 Paraguay residence quarantine (221 stored cells, both
 series; PREP_NOTES.md, FLAGS_CODEBOOK.md section 4) and (b) the C02 code-490 crosswalk
 (trade rows of TWN). The measure comparison uses identical observations: rows whose trade
 value is the same in both vintages and that both mobility measures cover, intersected
 until both fits keep the same rows; stacked test as A1_stack (same rows, two measures).
 Help: ppmlhdfe.sthlp; [D] merge; [R] test.
*******************************************************************************/
args vintage
assert "`vintage'" == "corrected"
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" corrected
version 18.0
do "A1_00_programs.do"
global VINTAGE "both"
capture log close _all
log using "${LOGS}/A1_06_crossvintage.log", text replace
display as result "A1_06_BEGIN " c(current_date) " " c(current_time)

use year iso3_o iso3_d v_ttl_k has_both_vis has_both_tour mob_bilat_vis mob_bilat_tour ///
    rev_vis_raw same_vis_raw rev_tour_raw same_tour_raw exporter_year importer_year pair_id unordered_pair_id ///
    s_base_vis s_base_tour pry_res_quarantine_rev pry_res_quarantine_same using "${PREPARED}", clear
nflow start using "${OUT}/A1_nflow.csv", append expected(823446)
preserve
    use year iso3_o iso3_d v_ttl_k has_both_vis has_both_tour mob_bilat_vis mob_bilat_tour ///
        rev_vis_raw same_vis_raw rev_tour_raw same_tour_raw s_base_vis s_base_tour ///
        tour_val_diff_rev tour_val_diff_same vis_val_diff_rev vis_val_diff_same using "${OUTROOT}/submitted/prepared.dta", clear
    foreach v in v_ttl_k has_both_vis has_both_tour mob_bilat_vis mob_bilat_tour rev_vis_raw same_vis_raw rev_tour_raw same_tour_raw s_base_vis s_base_tour {
        rename `v' sub_`v'
    }
    tempfile sub
    save `sub'
restore
merge 1:1 year iso3_o iso3_d using `sub', assert(match) nogen
nflow step "A1_06 merge submitted-vintage values by key (assert all match)"
A1_open A1_06

gen byte trade_same = (v_ttl_k == sub_v_ttl_k) | (missing(v_ttl_k) & missing(sub_v_ttl_k))
gen byte inv_pry = iso3_o == "PRY" | iso3_d == "PRY"
gen byte inv_twn = iso3_o == "TWN" | iso3_d == "TWN"
tempname VD
postfile `VD' str5 mobility str80 statistic double(rows) using "${OUT}/tables/A1_A1.5_vintage_diff.dta", replace
quietly count if !trade_same
post `VD' ("all") ("panel rows whose trade value differs between vintages") (r(N))
quietly count if !trade_same & !inv_twn
post `VD' ("all") ("   of which not involving TWN") (r(N))
foreach m in vis tour {
    local mv = cond("`m'" == "vis", "vis", "tour")
    gen byte val_diff_`m' = `mv'_val_diff_rev == 1 | `mv'_val_diff_same == 1
    quietly count if s_base_`m'
    post `VD' ("`m'") ("corrected baseline e(sample) rows") (r(N))
    quietly count if sub_s_base_`m'
    post `VD' ("`m'") ("submitted baseline e(sample) rows") (r(N))
    quietly count if s_base_`m' & sub_s_base_`m'
    post `VD' ("`m'") ("rows in both baselines") (r(N))
    quietly count if s_base_`m' & sub_s_base_`m' & mob_bilat_`m' != sub_mob_bilat_`m'
    post `VD' ("`m'") ("   of which mobility value differs (PRY quarantine cells)") (r(N))
    quietly count if s_base_`m' & sub_s_base_`m' & !trade_same
    post `VD' ("`m'") ("   of which trade value differs") (r(N))
    quietly count if sub_s_base_`m' & !s_base_`m'
    post `VD' ("`m'") ("rows only in the submitted baseline") (r(N))
    quietly count if sub_s_base_`m' & !s_base_`m' & val_diff_`m'
    post `VD' ("`m'") ("   of which a direction is a PRY quarantine cell with a changed value") (r(N))
    quietly count if sub_s_base_`m' & !s_base_`m' & !has_both_`m'
    post `VD' ("`m'") ("   of which mobility not observed in the corrected vintage (quarantine, no fallback)") (r(N))
    quietly count if sub_s_base_`m' & !s_base_`m' & inv_pry
    post `VD' ("`m'") ("   of which involve PRY") (r(N))
    quietly count if sub_s_base_`m' & !s_base_`m' & !inv_pry
    post `VD' ("`m'") ("   of which do not involve PRY (fixed-effect support changes: singletons)") (r(N))
    quietly count if s_base_`m' & !sub_s_base_`m'
    post `VD' ("`m'") ("rows only in the corrected baseline") (r(N))
    quietly count if s_base_`m' & !sub_s_base_`m' & inv_twn
    post `VD' ("`m'") ("   of which involve TWN (C02 crosswalk)") (r(N))
    quietly count if s_base_`m' & !sub_s_base_`m' & inv_pry
    post `VD' ("`m'") ("   of which involve PRY") (r(N))
    quietly count if s_base_`m' & !sub_s_base_`m' & !inv_twn & !inv_pry
    post `VD' ("`m'") ("   of which involve neither (fixed-effect support changes)") (r(N))
    quietly count if (s_base_`m' | sub_s_base_`m') & val_diff_`m'
    post `VD' ("`m'") ("rows in either baseline using a PRY quarantine cell whose value differs") (r(N))

    * --- measure comparison on identical observations
    gen byte __c = has_both_`m' & sub_has_both_`m' & !missing(v_ttl_k) & trade_same
    quietly count if __c & mob_bilat_`m' != sub_mob_bilat_`m'
    local ndiff = r(N)
    post `VD' ("`m'") ("shared candidate rows (both measures observed, same trade value)") (.)
    quietly count if __c
    post `VD' ("`m'") ("   shared candidate rows: count") (r(N))
    post `VD' ("`m'") ("   shared candidate rows where the two measures differ") (`ndiff')
    local conv 0
    forvalues it = 1/10 {
        capture drop __a __b
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if __c, absorb(${FE}) vce(cluster pair_id)
        gen byte __a = e(sample)
        quietly ppmlhdfe v_ttl_k sub_mob_bilat_`m' if __c, absorb(${FE}) vce(cluster pair_id)
        gen byte __b = e(sample)
        quietly count if __c & (!__a | !__b)
        if r(N) == 0 {
            local conv 1
            continue, break
        }
        replace __c = __c & __a & __b
    }
    assert `conv' == 1
    quietly count if __c & mob_bilat_`m' != sub_mob_bilat_`m'
    local nd2 = r(N)
    post `VD' ("`m'") ("identical estimation rows where the two measures differ") (`nd2')
    gen byte __s = __c
    if `nd2' > 0 {
        A1_stack, y1(v_ttl_k) x1(mob_bilat_`m') s1(__s) y2(v_ttl_k) x2(sub_mob_bilat_`m') s2(__s) ///
            item(A1.5) spec(pry_measure) mobility(`m') lab1(corrected) lab2(submitted) sample(identical rows) ///
            note("PRY measure: corrected (quarantine) vs submitted values on identical rows; outcome = trade value equal in both vintages")
    }
    else {
        capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if __s, absorb(${FE}) vce(cluster pair_id)
        A1_after, rc(`=_rc') item(A1.5) spec(pry_measure_identical) sample(identical rows) mobility(`m') terms(mob_bilat_`m') ///
            note("the two vintages' measures are identical on every shared row: no measure difference to test")
    }
    drop __c __a __b __s
}
postclose `VD'
preserve
    use "${OUT}/tables/A1_A1.5_vintage_diff.dta", clear
    gen str10 vintage = "both"
    order vintage
    export delimited using "${OUT}/tables/A1_A1.5_vintage_diff.csv", replace
restore
erase "${OUT}/tables/A1_A1.5_vintage_diff.dta"
A1_close
nflow report
display as result "A1_06_COMPLETE " c(current_date) " " c(current_time)
log close
exit, clear
