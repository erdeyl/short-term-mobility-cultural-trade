/*******************************************************************************
 01_prep.do  --  audited analysis base for the response to the reviewers
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do 01_prep.do <submitted|corrected>
 Output: ${OUT}/prepared.dta (+ logs, nflow.csv, sample_counts.csv, control CSVs)

 Help files consulted before writing this code (installed versions):
   [D] merge (merge.sthlp: 1:1, m:1, keep(), assert(), gen()), [D] egen (group(), max(), rowmax),
   [TS] xtset (xtset.sthlp: yearly), [D] import excel (sheet(), allstring, firstrow),
   [D] reshape, [P] postfile, [P] file, [D] use (varlist, if, using),
   ppmlhdfe.sthlp 2.3.4 (absorb(), vce(cluster), e(sample), e(N_full), e(num_singletons),
   e(num_separated); singletons dropped iteratively; separation fe simplex ir by default),
   nflow.sthlp 1.0.1 (start/step/est/report; a record, not a gate).
 Rules: no data value is altered; restrictions are flags. Read-only on STUDENT/COPY/PKG.
*******************************************************************************/

args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
capture mkdir "${OUT}"
capture mkdir "${LOGS}"
capture log close _all
log using "${LOGS}/01_prep_${VINTAGE}.log", text replace
display as result "PREP_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time) " stata=" c(stata_version)

foreach f in DATA_FILE MASTER_FILE COPY_DATA_FILE CT_MANIFEST CT_CROSSWALK CEPII_FILE WB_CLASS WB_OGHIST {
    confirm file "${`f'}"
}
global DIAG_DIR "${OUT}"    // used by the verbatim support-ledger block (STUDENT 02_prepare_data.do:77-87)

*==============================================================================
* C0. HS6-level importer-reported values from the raw API files (Python, pandas)
*     01a_hs6_products.py documents its source lines; status JSON must say PASS.
*==============================================================================
capture erase "${HS6_FILE}"
capture erase "${HS6_STATUS}"
pkg_py "${CODE}/01a_hs6_products.py" ${VINTAGE} "${CT_RAW_DIR}" "${CT_MANIFEST}" "${CT_INT}" "${CT_CROSSWALK}" "${HS6_FILE}" "${HS6_STATUS}" > "${LOGS}/01a_hs6_products_${VINTAGE}.log" 2>&1
confirm file "${HS6_STATUS}"
local hs6_ok 0
tempname fh
file open `fh' using "${HS6_STATUS}", read text
file read `fh' line
while r(eof) == 0 {
    if strpos(`"`macval(line)'"', `""status": "PASS""') local hs6_ok 1
    file read `fh' line
}
file close `fh'
if `hs6_ok' != 1 {
    display as error "HS6 build did not report PASS; see ${LOGS}/01a_hs6_products_${VINTAGE}.log"
    exit 459
}
confirm file "${HS6_FILE}"
display as result "HS6_BUILD=PASS"

*==============================================================================
* A. STUDENT 02_code/03_Mobility/02_empirical_analysis/01_core/02_prepare_data.do
*    lines 12-90, verbatim (only ${DIAG_DIR}/${CACHE_DIR} targets differ; the
*    save at line 92 is replaced by the save at the end of this file).
*==============================================================================
version 18.0
use "${DATA_FILE}", clear                                   // :13
nflow start using "${NFLOW}", replace expected(823446)
compress                                                    // :14
isid year iso3_o iso3_d                                     // :15

*------------------------------------------------------------------------------
* A0. corrected2 / corrected2x only (rerun C2, author decisions 2026-11-03).
*     Inserted before the mirror step; the submitted and corrected vintages skip it.
*     Rule = C12 (README section 6; COPY 01_build_UN_Tourism.do lines
*     366-372: the residence cell value is set missing, no rescaling; the residence-first /
*     nationality-fallback rule of lines 620-629 then applies; trips = thousand trips x 1000,
*     lines 667-669). Stored row iso3_o -> iso3_d carries arrivals in iso3_o (UN Tourism
*     reporter = destination) from iso3_d (FLAGS_CODEBOOK.md section 1; COPY
*     01_build_master_panel.py lines 31-39).
*     (q1) PAK residence workbooks 2020-2024 hold single trips under a "thousand trips"
*          label (authors' working notes): reporter PAK, 2020-2021, tourists
*          workbook 0586011220202024202512.xlsx, visitors workbook 0586012220202024202512.xlsx.
*     (q2) BLR visitors by residence 2020-2022 book Lithuania under partner code 438
*          Liechtenstein (authors' working notes): stored rows BLR-LIE,
*          workbook 0112012220202024202512.xlsx.
*     Nationality fallback values: COPY master tourists_nat_k / visitors_nat_k (thousand trips).
*     Originals kept in tourists_pre_pak, visitors_pre_pak, visitors_pre_blr (quarantined cells).
*------------------------------------------------------------------------------
if inlist("${VINTAGE}", "corrected2", "corrected2x") {
    preserve
        use year iso3_o iso3_d tourists_res_k tourists_nat_k visitors_res_k visitors_nat_k using "${MASTER_FILE}", clear
        isid year iso3_o iso3_d
        tempfile c2resnat
        save `"`c2resnat'"', replace
    restore
    merge 1:1 year iso3_o iso3_d using `"`c2resnat'"', assert(match) nogen
    nflow step "corrected2: merge COPY master residence/nationality series by key (assert all match; no row change)"
    gen byte __q_tour_pak = iso3_o == "PAK" & inrange(year, 2020, 2022) & tourists_basis == "residence" & tourists_source_file == "0586011220202024202512.xlsx"
    gen byte __q_vis_pak  = iso3_o == "PAK" & inrange(year, 2020, 2022) & visitors_basis == "residence" & visitors_source_file == "0586012220202024202512.xlsx"
    gen byte __q_vis_blr  = iso3_o == "BLR" & iso3_d == "LIE" & inrange(year, 2020, 2022) & visitors_basis == "residence" & visitors_source_file == "0112012220202024202512.xlsx"
    * controls of the selection: every PAK 2020-2021 stored value is on the two workbooks;
    * every BLR-LIE 2020-2021 visitor value on the residence workbook is selected
    quietly count if iso3_o == "PAK" & inrange(year, 2020, 2021) & !missing(tourists) & !__q_tour_pak
    assert r(N) == 0
    quietly count if iso3_o == "PAK" & inrange(year, 2020, 2021) & !missing(visitors) & !__q_vis_pak
    assert r(N) == 0
    quietly count if iso3_o == "BLR" & iso3_d == "LIE" & visitors_source_file == "0112012220202024202512.xlsx" & !__q_vis_blr
    assert r(N) == 0
    foreach q in tour_pak vis_pak vis_blr {
        quietly count if __q_`q'
        display as result "C2_QUARANTINE_CELLS_`q'=" r(N)
        local n_q_`q' = r(N)
    }
    assert `n_q_tour_pak' == 468 & `n_q_vis_pak' == 468 & `n_q_vis_blr' == 2
    * the stored values are the residence values (thousand trips x 1000) and PRY C12 is not involved
    assert !missing(tourists_res_k) & tourists == tourists_res_k * 1000 if __q_tour_pak
    assert !missing(visitors_res_k) & visitors == visitors_res_k * 1000 if __q_vis_pak | __q_vis_blr
    assert pry_res_quarantine == 0 if __q_tour_pak | __q_vis_pak | __q_vis_blr
    * affected pairs; validation (as section B3): before the quarantine, the master-row
    * recomputation of the pair-level basis switch reproduces COPY's source-table flag
    * (COPY 02_code/99_rescue/I-M/source_flags.do lines 24-27) on every row of these pairs
    bysort iso3_o iso3_d: egen byte __q_pair_tour = max(__q_tour_pak)
    bysort iso3_o iso3_d: egen byte __q_pair_vis = max(__q_vis_pak | __q_vis_blr)
    foreach m in tour vis {
        local s = cond("`m'" == "tour", "tourists", "visitors")
        tempvar hn hr chk
        egen byte `hn' = max(cond(!missing(`s'), `s'_basis == "nationality", .)), by(iso3_o iso3_d)
        egen byte `hr' = max(cond(!missing(`s'), `s'_basis == "residence", .)), by(iso3_o iso3_d)
        gen byte `chk' = (`hn' == 1 & `hr' == 1) if !missing(`s')
        quietly count if __q_pair_`m' & !missing(`s') & `chk' != `m'_study_switch
        display as result "C2_STUDY_SWITCH_VALIDATION_DIFF_`m'=" r(N)
        assert r(N) == 0
        quietly count if __q_pair_`m' & missing(`s') & !missing(`m'_study_switch)
        display as result "C2_STUDY_SWITCH_NONMISSING_WITHOUT_VALUE_`m'=" r(N)
        drop `hn' `hr' `chk'
    }
    gen double tourists_pre_pak = tourists if __q_tour_pak
    gen double visitors_pre_pak = visitors if __q_vis_pak
    gen double visitors_pre_blr = visitors if __q_vis_blr
    label variable tourists_pre_pak "corrected2: original tourists value of a PAK-residence quarantined cell (trips)"
    label variable visitors_pre_pak "corrected2: original visitors value of a PAK-residence quarantined cell (trips)"
    label variable visitors_pre_blr "corrected2: original visitors value of a BLR-LIE residence quarantined cell (trips)"
    * C12 rule: residence value missing, nationality fallback (missing if no nationality value)
    replace tourists = tourists_nat_k * 1000 if __q_tour_pak
    replace tourists_basis = cond(!missing(tourists_nat_k), "nationality", "") if __q_tour_pak
    replace visitors = visitors_nat_k * 1000 if __q_vis_pak | __q_vis_blr
    replace visitors_basis = cond(!missing(visitors_nat_k), "nationality", "") if __q_vis_pak | __q_vis_blr
    gen byte __fb_tour = __q_tour_pak & !missing(tourists)
    gen byte __fb_vis = (__q_vis_pak | __q_vis_blr) & !missing(visitors)
    foreach q in tour_pak vis_pak vis_blr {
        local s = cond("`q'" == "tour_pak", "tourists", "visitors")
        quietly count if __q_`q' & !missing(`s')
        display as result "C2_QUARANTINE_NATIONALITY_FALLBACK_`q'=" r(N)
    }
    list year iso3_o iso3_d visitors_pre_blr visitors visitors_basis visitors_nat_k if __q_vis_blr, noobs clean
    * series metadata (COPY convention on its C12 cells, probe of COPY pry_res_quarantine==1 rows:
    * without a fallback value the quarantined workbook's file/flag/notes/release stay, basis is
    * empty, start/end/span2020, conf_sub and the basis switch are missing, basis_mismatch and
    * hierarchy_violation are 0). With a fallback value (BLR-LIE 2020, nationality) the
    * nationality cell's metadata are not in the analysis file: they are set empty/missing.
    foreach v in tour_start tour_end tour_span2020 {
        replace `v' = . if __q_tour_pak
    }
    foreach v in vis_start vis_end vis_span2020 conf_sub {
        replace `v' = . if __q_vis_pak | __q_vis_blr
    }
    foreach v in tourists_source_file tourists_flag tourists_flag_label tourists_notes tourists_release {
        replace `v' = "" if __fb_tour
    }
    foreach v in visitors_source_file visitors_flag visitors_flag_label visitors_notes visitors_release {
        replace `v' = "" if __fb_vis
    }
    replace visitors_definition_diff = . if __fb_vis
    assert missing(tourists) | missing(visitors) if __q_tour_pak | __q_vis_pak | __q_vis_blr
    replace hierarchy_violation = 0 if __q_tour_pak | __q_vis_pak | __q_vis_blr
    replace basis_mismatch = 0 if __q_tour_pak | __q_vis_pak | __q_vis_blr
    * pair-level basis switch recomputed on the master rows of the affected pairs (valid: see validation above)
    foreach m in tour vis {
        local s = cond("`m'" == "tour", "tourists", "visitors")
        tempvar hn hr old
        egen byte `hn' = max(cond(!missing(`s'), `s'_basis == "nationality", .)), by(iso3_o iso3_d)
        egen byte `hr' = max(cond(!missing(`s'), `s'_basis == "residence", .)), by(iso3_o iso3_d)
        gen byte `old' = `m'_study_switch
        replace `m'_study_switch = (`hn' == 1 & `hr' == 1) if __q_pair_`m' & !missing(`s')
        replace `m'_study_switch = . if __q_pair_`m' & missing(`s')
        quietly count if !((`old' == `m'_study_switch) | (missing(`old') & missing(`m'_study_switch)))
        display as result "C2_STUDY_SWITCH_CHANGED_`m'=" r(N)
        drop `hn' `hr' `old'
    }
    * cell-level flags (missing where the row has no tourism record, as pry_res_quarantine)
    gen byte pak_res_quarantine = cond(__q_tour_pak | __q_vis_pak, 1, cond(!missing(pry_res_quarantine), 0, .))
    gen byte blr_lie_quarantine = cond(__q_vis_blr, 1, cond(!missing(pry_res_quarantine), 0, .))
    label variable pak_res_quarantine "corrected2: PAK residence 2020-2021 cell quarantined (C12 rule); stored row"
    label variable blr_lie_quarantine "corrected2: BLR visitors residence partner LIE 2020-2022 quarantined; stored row"
    foreach s in tourists visitors {
        quietly count if !((`s' == `s'_pre_pak) | missing(`s'_pre_pak)) | (missing(`s') & !missing(`s'_pre_pak))
        display as result "C2_CHANGED_`s'_PAK=" r(N)
    }
    drop tourists_res_k tourists_nat_k visitors_res_k visitors_nat_k __q_tour_pak __q_vis_pak __q_vis_blr ///
        __fb_tour __fb_vis __q_pair_tour __q_pair_vis
    sort year iso3_o iso3_d
}

egen long exporter_id = group(iso3_o), label                // :17
egen long importer_id = group(iso3_d), label                // :18
egen long exporter_year = group(iso3_o year), label         // :19
egen long importer_year = group(iso3_d year), label         // :20
egen long pair_id = group(iso3_o iso3_d), label             // :21
gen str3 iso_low = cond(iso3_o < iso3_d, iso3_o, iso3_d)    // :22
gen str3 iso_high = cond(iso3_o < iso3_d, iso3_d, iso3_o)   // :23
egen long unordered_pair_id = group(iso_low iso_high), label // :24

gen double rev_tour_raw = tourists                          // :26
gen double rev_vis_raw = visitors                           // :27

preserve                                                    // :29-38
    keep year iso3_o iso3_d tourists visitors
    rename tourists same_tour_raw
    rename visitors same_vis_raw
    rename iso3_o old_iso3_o
    rename iso3_d iso3_o
    rename old_iso3_o iso3_d
    tempfile opposite_flows
    save `"`opposite_flows'"', replace
restore

merge 1:1 year iso3_o iso3_d using `"`opposite_flows'"', keep(master match) nogen   // :40
nflow step "STUDENT 02_prepare_data.do:40 mirror merge of opposite-direction flows (keep master match)"

gen byte has_rev_tour = !missing(rev_tour_raw)              // :42-47
gen byte has_same_tour = !missing(same_tour_raw)
gen byte has_both_tour = has_rev_tour & has_same_tour
gen byte has_rev_vis = !missing(rev_vis_raw)
gen byte has_same_vis = !missing(same_vis_raw)
gen byte has_both_vis = has_rev_vis & has_same_vis

gen double bilat_tour_raw = rev_tour_raw + same_tour_raw if has_both_tour   // :49-56
gen double bilat_vis_raw = rev_vis_raw + same_vis_raw if has_both_vis
gen double mob_rev_tour = asinh(rev_tour_raw) if has_rev_tour
gen double mob_same_tour = asinh(same_tour_raw) if has_same_tour
gen double mob_bilat_tour = asinh(bilat_tour_raw) if has_both_tour
gen double mob_rev_vis = asinh(rev_vis_raw) if has_rev_vis
gen double mob_same_vis = asinh(same_vis_raw) if has_same_vis
gen double mob_bilat_vis = asinh(bilat_vis_raw) if has_both_vis

gen byte positive_trade = (v_ttl_k > 0) if !missing(v_ttl_k)   // :58

label variable v_ttl_k "Trade (thousand USD)"               // :60-68
label variable bilat_vis_raw "Bilateral visitors"
label variable rev_vis_raw "Reverse visitors: importer to exporter"
label variable same_vis_raw "Same-direction visitors: exporter to importer"
label variable bilat_tour_raw "Bilateral tourists"
label variable rev_tour_raw "Reverse tourists: importer to exporter"
label variable same_tour_raw "Same-direction tourists: exporter to importer"
label variable mob_bilat_vis "IHS bilateral visitors"
label variable mob_bilat_tour "IHS bilateral tourists"

xtset pair_id year, yearly                                  // :70-75
sort pair_id year
gen double lag_bilat_vis = L.mob_bilat_vis
gen double lead_bilat_vis = F.mob_bilat_vis
gen double lag_bilat_tour = L.mob_bilat_tour
gen double lead_bilat_tour = F.mob_bilat_tour

file open support using "${DIAG_DIR}/support-ledger.csv", write replace   // :77-87
file write support "measure,N" _n
foreach item in rev_vis same_vis both_vis rev_tour same_tour both_tour {
    quietly count if has_`item'
    local support_n = r(N)
    file write support "`item',`support_n'" _n
}
quietly count if !missing(v_ttl_k)
local trade_n = r(N)
file write support "trade_nonmissing,`trade_n'" _n
file close support

quietly count if !missing(visitors, tourists) & visitors < tourists   // :89-90
display as result "VISITOR_TOURIST_HIERARCHY_VIOLATIONS=" r(N)

*==============================================================================
* B. Mobility-source flags for both travel directions.
*    Mirror logic = COPY 02_code/03_Mobility/02_empirical_analysis/01_core/02_prepare_data.do
*    lines 29-129 with all switches on (C11b, C11c, C12). rescue_on is not installed here,
*    so the switch tests are replaced by the "on" branch; names follow COPY exactly.
*    Flag meanings: out/FLAGS_CODEBOOK.md.
*==============================================================================
local copyflags conf_sub visitors_source_file visitors_flag visitors_flag_label visitors_notes ///
    visitors_release tourists_basis visitors_basis tourists_source_file tourists_flag ///
    tourists_flag_label tourists_notes tourists_release basis_mismatch hierarchy_violation ///
    visitors_definition_diff tour_start tour_end tour_span2020 tour_study_switch vis_start ///
    vis_end vis_span2020 vis_study_switch regional_proxy_flag_o regional_proxy_flag_d ///
    any_regional_proxy common_dim_count6 france251_component_o france251_component_d ///
    france251_component_any pry_res_quarantine

if "${VINTAGE}" == "submitted" {
    * B1. Bring the COPY flag variables by key (COPY rows = same 823,446 keys).
    preserve
        use year iso3_o iso3_d tourists visitors `copyflags' using "${COPY_DATA_FILE}", clear
        isid year iso3_o iso3_d
        rename tourists tourists_copy
        rename visitors visitors_copy
        tempfile copyflagfile
        save `"`copyflagfile'"', replace
    restore
    merge 1:1 year iso3_o iso3_d using `"`copyflagfile'"', assert(match) nogen
    nflow step "merge COPY flag variables by year iso3_o iso3_d (assert all match)"

    * B2. Where do submitted tourism values differ from COPY's? (expected: PRY quarantine only)
    gen byte tour_val_diff = !((tourists == tourists_copy) | (missing(tourists) & missing(tourists_copy)))
    gen byte vis_val_diff  = !((visitors == visitors_copy) | (missing(visitors) & missing(visitors_copy)))
    label variable tour_val_diff "Submitted tourists value differs from COPY (stored row)"
    label variable vis_val_diff  "Submitted visitors value differs from COPY (stored row)"
    foreach m in tour vis {
        quietly count if `m'_val_diff
        display as result "VALDIFF_`m'_ALL=" r(N)
        quietly count if `m'_val_diff & pry_res_quarantine != 1
        display as result "VALDIFF_`m'_OUTSIDE_PRY_QUARANTINE=" r(N)
        local vd_out_`m' = r(N)
    }
    quietly count if pry_res_quarantine == 1
    display as result "PRY_QUARANTINE_CELLS=" r(N)
    quietly count if pry_res_quarantine == 1 & !tour_val_diff & !vis_val_diff
    display as result "PRY_QUARANTINE_CELLS_SAME_VALUES_BOTH_SERIES=" r(N)

    * B3. Validate the study_switch recomputation on COPY's own basis and values
    *     (definition: COPY 02_code/99_rescue/I-M/source_flags.do:24-27, computed on the
    *     tourism SOURCE table by reporter x partner area code). On master rows a few pairs
    *     differ because some source rows never enter the master (e.g. TTO-SDN, Sudan area
    *     codes). The recomputation is used only for PRY-quarantine pairs, so it is valid
    *     iff none of the differing pairs is a PRY-quarantine pair (asserted).
    bysort iso3_o iso3_d: egen byte __pry_pair = max(pry_res_quarantine == 1)
    foreach m in tour vis {
        local s = cond("`m'" == "tour", "tourists", "visitors")
        tempvar hn hr chk bad badpair
        egen byte `hn' = max(cond(!missing(`s'_copy), `s'_basis == "nationality", .)), by(iso3_o iso3_d)
        egen byte `hr' = max(cond(!missing(`s'_copy), `s'_basis == "residence", .)), by(iso3_o iso3_d)
        gen byte `chk' = (`hn' == 1 & `hr' == 1) if !missing(`s'_copy)
        gen byte `bad' = !missing(`s'_copy) & `chk' != `m'_study_switch
        quietly count if `bad'
        display as result "STUDY_SWITCH_RECOMPUTE_MASTER_ROWS_DIFF_`m'=" r(N) " (source-table rows outside master)"
        bysort iso3_o iso3_d: egen byte `badpair' = max(`bad')
        list year iso3_o iso3_d `s'_copy `s'_basis `m'_study_switch `chk' if `bad', noobs clean
        quietly count if `badpair' & __pry_pair
        if r(N) != 0 {
            display as error "A PRY-quarantine pair has a study_switch the master rows cannot reproduce."
            exit 459
        }
        drop `hn' `hr' `chk' `bad' `badpair'
    }

    * B4. Submitted-vintage treatment (author decision): every PRY-quarantine cell gets basis
    *     "PRY_unknown" (the submitted data used the residence value there). Series metadata
    *     that describe COPY's selected workbook are set to missing where the submitted value
    *     differs from COPY's (the selected series differs); value comparisons that depend on
    *     an unknown basis are set to missing. No mobility or trade value is changed.
    replace tourists_basis = cond(missing(tourists), "", "PRY_unknown") if pry_res_quarantine == 1
    replace visitors_basis = cond(missing(visitors), "", "PRY_unknown") if pry_res_quarantine == 1
    foreach v in tourists_source_file tourists_flag tourists_flag_label tourists_notes tourists_release {
        replace `v' = "" if tour_val_diff
    }
    foreach v in tour_start tour_end tour_span2020 {
        replace `v' = . if tour_val_diff
    }
    foreach v in visitors_source_file visitors_flag visitors_flag_label visitors_notes visitors_release {
        replace `v' = "" if vis_val_diff
    }
    foreach v in vis_start vis_end vis_span2020 conf_sub visitors_definition_diff {
        replace `v' = . if vis_val_diff
    }
    replace hierarchy_violation = . if tour_val_diff | vis_val_diff
    replace basis_mismatch = . if inlist("PRY_unknown", tourists_basis, visitors_basis) | tour_val_diff | vis_val_diff
    * study_switch for PRY-quarantine pairs recomputed on the submitted basis (1 if the
    * known cells already show both bases; missing if only PRY_unknown cells could decide);
    * all other pairs keep COPY's source-table value (same source rows in both vintages).
    foreach m in tour vis {
        local s = cond("`m'" == "tour", "tourists", "visitors")
        tempvar hn hr hu
        egen byte `hn' = max(cond(!missing(`s'), `s'_basis == "nationality", .)), by(iso3_o iso3_d)
        egen byte `hr' = max(cond(!missing(`s'), `s'_basis == "residence", .)), by(iso3_o iso3_d)
        egen byte `hu' = max(cond(!missing(`s'), `s'_basis == "PRY_unknown", .)), by(iso3_o iso3_d)
        gen byte __sw_old = `m'_study_switch
        replace `m'_study_switch = (`hn' == 1 & `hr' == 1) if !missing(`s') & __pry_pair
        replace `m'_study_switch = . if !missing(`s') & !(`hn' == 1 & `hr' == 1) & `hu' == 1 & __pry_pair
        quietly count if !((__sw_old == `m'_study_switch) | (missing(__sw_old) & missing(`m'_study_switch)))
        display as result "STUDY_SWITCH_SUBMITTED_CHANGED_`m'=" r(N)
        drop __sw_old `hn' `hr' `hu'
    }
    drop tourists_copy visitors_copy __pry_pair
}
if inlist("${VINTAGE}", "corrected", "corrected2", "corrected2x") {
    foreach v of local copyflags {
        confirm variable `v', exact
    }
}

* B5. Direction mirror (COPY 02_prepare_data.do:35-104; names as COPY).
local rescue_rev ""
local rescue_same ""
rename pry_res_quarantine pry_res_quarantine_rev                                   // COPY :35
local rescue_rev "pry_res_quarantine_rev"
local rescue_same "pry_res_quarantine_same"
if inlist("${VINTAGE}", "corrected2", "corrected2x") {
    * corrected2 quarantine flags carried to both directions like pry_res_quarantine (section A0)
    rename pak_res_quarantine pak_res_quarantine_rev
    rename blr_lie_quarantine blr_lie_quarantine_rev
    local rescue_rev "`rescue_rev' pak_res_quarantine_rev blr_lie_quarantine_rev"
    local rescue_same "`rescue_same' pak_res_quarantine_same blr_lie_quarantine_same"
}
rename conf_sub conf_sub_rev                                                     // COPY :42
local rescue_rev "`rescue_rev' conf_sub_rev"
local rescue_same "`rescue_same' conf_sub_same"
gen byte hier_rev = hierarchy_violation if !missing(tourists,visitors)             // COPY :49-53
gen byte basis_mismatch_rev = basis_mismatch if !missing(tourists,visitors)
gen byte visitors_definition_diff_rev = visitors_definition_diff if !missing(visitors)
rename visitors_basis basis_rev_vis
rename tourists_basis basis_rev_tour
local rescue_rev "`rescue_rev' hier_rev basis_mismatch_rev visitors_definition_diff_rev basis_rev_vis basis_rev_tour"
local rescue_same "`rescue_same' hier_same basis_mismatch_same visitors_definition_diff_same basis_same_vis basis_same_tour"
foreach measure in vis tour {                                                      // COPY :63-85
    local source = cond("`measure'"=="vis","visitors","tourists")
    foreach pair in "source_file file" "flag flag" "flag_label flaglabel" "notes notes" "release release" {
        gettoken old new : pair
        local new = strtrim("`new'")
        rename `source'_`old' `measure'_`new'_rev
        local rescue_rev "`rescue_rev' `measure'_`new'_rev"
        local rescue_same "`rescue_same' `measure'_`new'_same"
    }
    foreach prop in start end span2020 study_switch {
        local target "`measure'_`prop'"
        if "`prop'"=="study_switch" local target "basis_switch_rev_`measure'"
        else local target "`measure'_`prop'_rev"
        rename `measure'_`prop' `target'
        local rescue_rev "`rescue_rev' `target'"
        local mate = subinstr("`target'","_rev","_same",.)
        local rescue_same "`rescue_same' `mate'"
    }
}
* Additions beyond COPY's list: pair-level Hofstede flags, and for the submitted
* vintage the value-difference flags. Originals stay in the data.
gen byte any_regional_proxy_rev = any_regional_proxy
gen byte common_dim_count6_rev = common_dim_count6
local rescue_rev "`rescue_rev' any_regional_proxy_rev common_dim_count6_rev"
local rescue_same "`rescue_same' any_regional_proxy_same common_dim_count6_same"
if "${VINTAGE}" == "submitted" {
    rename tour_val_diff tour_val_diff_rev
    rename vis_val_diff vis_val_diff_rev
    local rescue_rev "`rescue_rev' tour_val_diff_rev vis_val_diff_rev"
    local rescue_same "`rescue_same' tour_val_diff_same vis_val_diff_same"
}

preserve                                                                           // COPY :87-102
    keep year iso3_o iso3_d `rescue_rev'
    local meta_i 0
    foreach field of local rescue_rev {
        local ++meta_i
        local mate : word `meta_i' of `rescue_same'
        rename `field' `mate'
    }
    rename iso3_o old_iso3_o
    rename iso3_d iso3_o
    rename old_iso3_o iso3_d
    tempfile opposite_flags
    save `"`opposite_flags'"', replace
restore
merge 1:1 year iso3_o iso3_d using `"`opposite_flags'"', keep(master match) nogen  // COPY :104
nflow step "COPY 02_prepare_data.do:104-style mirror merge of source flags (keep master match)"

gen byte vis_defok = !missing(rev_vis_raw,same_vis_raw) & conf_sub_rev==0 & conf_sub_same==0   // COPY :109
label variable visitors "Visitor-series arrivals, mixed coverage, trips"                        // COPY :110
label variable pry_res_quarantine_rev "PRY source residence quarantined; reverse flow"          // COPY :114-127
label variable pry_res_quarantine_same "PRY source residence quarantined; same flow"
if inlist("${VINTAGE}", "corrected2", "corrected2x") {
    label variable pak_res_quarantine_rev "PAK residence 2020-2021 quarantined (corrected2); reverse flow"
    label variable pak_res_quarantine_same "PAK residence 2020-2021 quarantined (corrected2); same flow"
    label variable blr_lie_quarantine_rev "BLR visitors residence partner LIE quarantined (corrected2); reverse flow"
    label variable blr_lie_quarantine_same "BLR visitors residence partner LIE quarantined (corrected2); same flow"
    foreach v in pak_res_quarantine_rev pak_res_quarantine_same blr_lie_quarantine_rev blr_lie_quarantine_same {
        tab `v', missing
    }
}
label variable conf_sub_rev "Guarded confirmed tourists-only substitute; reverse visitors"
label variable conf_sub_same "Guarded confirmed tourists-only substitute; same visitors"
label variable vis_defok "Strict bilateral visitors without either confirmed substitute"
foreach direction in rev same {
    label variable hier_`direction' "Guarded tourists>visitors comparison; `direction' flow"
    label variable basis_mismatch_`direction' "Guarded visitor/tourist basis mismatch; `direction' flow"
    label variable visitors_definition_diff_`direction' "Guarded generic visitor definition flag; `direction' flow"
    label variable basis_`direction'_vis "Selected visitor-series basis; `direction' flow"
    label variable basis_`direction'_tour "Selected tourist-series basis; `direction' flow"
    label variable any_regional_proxy_`direction' "Hofstede regional proxy used for o or d; `direction' row"
    label variable common_dim_count6_`direction' "Hofstede dimensions with both scores; `direction' row"
}
* Symmetry of the pair-level Hofstede flags (should hold by construction).
quietly count if !missing(any_regional_proxy_rev, any_regional_proxy_same) & any_regional_proxy_rev != any_regional_proxy_same
display as result "ASYM_any_regional_proxy=" r(N)
quietly count if !missing(common_dim_count6_rev, common_dim_count6_same) & common_dim_count6_rev != common_dim_count6_same
display as result "ASYM_common_dim_count6=" r(N)
* Flag tabulations (for FLAGS_CODEBOOK.md)
foreach v in basis_rev_vis basis_rev_tour {
    tab `v' if has_rev_`=substr("`v'",11,.)', missing
}
foreach v in conf_sub_rev hier_rev basis_mismatch_rev visitors_definition_diff_rev pry_res_quarantine_rev ///
    basis_switch_rev_vis basis_switch_rev_tour vis_span2020_rev tour_span2020_rev vis_defok {
    tab `v', missing
}
tab basis_rev_vis basis_same_vis if has_both_vis, missing
tab basis_rev_tour basis_same_tour if has_both_tour, missing

*==============================================================================
* C. Product subsets (importer-reported, LB, thousand USD) and File S1 indicators
*==============================================================================
* C1. Master metadata of the same vintage (base_core.py:119-133 builds these fields).
preserve
    use year iso3_o iso3_d comtrade_reporting_available any_unreported n_unreported_rows ///
        v_8523_exact v_8523_amb_k v_ttl_lb_k using "${MASTER_FILE}", clear
    isid year iso3_o iso3_d
    tempfile mastermeta
    save `"`mastermeta'"', replace
restore
merge 1:1 year iso3_o iso3_d using `"`mastermeta'"', assert(match) nogen
nflow step "merge master metadata (comtrade_reporting_available, any_unreported, v_8523_exact) assert all match"
assert v_ttl_k == v_ttl_lb_k if !missing(v_ttl_lb_k)
assert missing(v_ttl_k) == missing(v_ttl_lb_k)
assert (comtrade_reporting_available == 1) == !missing(v_ttl_k)
drop v_ttl_lb_k

* C2. HS6 wide values from 01a_hs6_products.py
merge 1:1 year iso3_o iso3_d using "${HS6_FILE}", gen(_m_hs6)
quietly count if _m_hs6 == 2
local hs6_outside = r(N)
display as result "HS6_ROWS_OUTSIDE_MASTER_UNIVERSE=`hs6_outside'"
drop if _m_hs6 == 2
nflow step "merge HS6 dyad-year values; drop using-only rows (outside CEPII existing-country universe)"
quietly count if _m_hs6 == 3 & missing(v_ttl_k)
if r(N) != 0 {
    display as error "HS6 rows exist for importer-years without reporting availability: " r(N)
    exit 459
}
quietly count if _m_hs6 == 1 & !missing(v_ttl_k) & v_ttl_k != 0
if r(N) != 0 {
    display as error "Positive v_ttl_k without an HS6 row: " r(N)
    exit 459
}
unab hcodes : h??????_k
local nh : word count `hcodes'
assert `nh' == 31

* Basket definitions (authors' working notes)
local B_ttl     `hcodes'
local B_3706    h370610_k h370690_k
local B_49      h490110_k h490191_k h490199_k h490210_k h490290_k h490300_k h490400_k h490510_k h490591_k ///
                h490599_k h490600_k h490700_k h490810_k h490890_k h490900_k h491000_k h491110_k h491191_k h491199_k
local B_8523    h852329_k h852340_k h852380_k
local B_97      h970110_k h970190_k h970200_k h970300_k h970400_k h970500_k h970600_k
local B_unesco_a h370610_k h370690_k h490110_k h490191_k h490199_k h490210_k h490290_k h490300_k h490400_k ///
                 h490510_k h490591_k h490599_k h490600_k h490900_k h491000_k h491191_k ///
                 h970110_k h970190_k h970200_k h970300_k h970500_k h970600_k
local B_unesco_b `B_unesco_a' h852329_k h852380_k
local B_art3    h970110_k h970190_k h970200_k h970300_k
local B_pub_core h490110_k h490191_k h490199_k h490210_k h490290_k h490300_k h490400_k h490510_k h490591_k ///
                 h490599_k h490600_k h490900_k h491000_k
foreach b in unesco_a unesco_b art3 pub_core {
    local nb : word count `B_`b''
    display as result "BASKET_`b'_CODES=`nb'"
}
assert `: word count `B_unesco_a'' == 22
assert `: word count `B_unesco_b'' == 24
assert `: word count `B_art3'' == 4
assert `: word count `B_pub_core'' == 13

* zero/missing rule of v_ttl_k (base_core.py:119-133): row present -> sum of codes;
* importer-year reporting and no row -> 0; importer-year not reporting -> missing.
foreach b in ttl 3706 49 8523 97 unesco_a unesco_b art3 pub_core {
    gen double __b_`b' = 0 if !missing(v_ttl_k)
    foreach h of local B_`b' {
        quietly replace __b_`b' = __b_`b' + `h' if _m_hs6 == 3
    }
}
rename __b_unesco_a v_unesco_a
rename __b_unesco_b v_unesco_b
rename __b_art3     v_art3
rename __b_pub_core v_pub_core
label variable v_unesco_a "UNESCO FCS2009-consistent narrow basket A (22 HS2007 codes, no 8523), LB, 1000 USD"
label variable v_unesco_b "Narrow basket B = A + 852329 + 852380 (24 codes), LB (ambiguous pool excluded), 1000 USD"
label variable v_art3     "Artworks HS 9701-9703 only (970110 970190 970200 970300), 1000 USD"
label variable v_pub_core "Publications ch.49 excl. 4907 4908 4911 (13 codes), 1000 USD"

* Positive controls: 31-code sum = v_ttl_k; category sums = v_3706_k v_49_k v_8523_k v_97_k
local pc_fail 0
tempname PC
postfile `PC' str32 item double rows max_abs_diff max_rel_diff n_fail str8 result using "${OUT}/product_controls.dta", replace
foreach pair in "ttl v_ttl_k" "3706 v_3706_k" "49 v_49_k" "8523 v_8523_k" "97 v_97_k" {
    gettoken b orig : pair
    local orig = strtrim("`orig'")
    tempvar d r
    gen double `d' = abs(__b_`b' - `orig') if !missing(v_ttl_k)
    gen double `r' = `d' / max(abs(`orig'), 1e-300) if !missing(v_ttl_k) & `orig' != 0
    quietly summarize `d', meanonly
    local mx = r(max)
    local nrows = r(N)
    quietly summarize `r', meanonly
    local mr = cond(r(N) > 0, r(max), 0)
    quietly count if `d' > 1e-6 + 1e-9 * abs(`orig') & !missing(`d')
    local nf = r(N)
    quietly count if missing(__b_`b') != missing(`orig')
    local nf = `nf' + r(N)
    post `PC' ("sum_codes_vs_`orig'") (`nrows') (`mx') (`mr') (`nf') (cond(`nf' == 0, "PASS", "FAIL"))
    display as result "PRODUCT_CONTROL `orig' rows=`nrows' max_abs=" %12.3e `mx' " max_rel=" %12.3e `mr' " n_fail=`nf'"
    local pc_fail = `pc_fail' + `nf'
    drop `d' `r'
}
* Original-grouping category sums from Python (grouped exactly like 05_build_cultural_trade.py:302-321)
foreach pair in "cat3706_k v_3706_k" "cat49_k v_49_k" "cat8523_k v_8523_k" "cat97_k v_97_k" "catamb_k v_8523_amb_k" "amb8523_k v_8523_amb_k" {
    gettoken a orig : pair
    local orig = strtrim("`orig'")
    tempvar d
    gen double `d' = abs(`a' - `orig') if _m_hs6 == 3
    quietly summarize `d', meanonly
    local mx = r(max)
    local nrows = r(N)
    quietly count if `d' > 1e-6 + 1e-9 * abs(`orig') & !missing(`d')
    local nf = r(N)
    post `PC' ("py_`a'_vs_`orig'") (`nrows') (`mx') (.) (`nf') (cond(`nf' == 0, "PASS", "FAIL"))
    display as result "PRODUCT_CONTROL py `a' vs `orig' rows=`nrows' max_abs=" %12.3e `mx' " n_fail=`nf'"
    local pc_fail = `pc_fail' + `nf'
    drop `d'
}
quietly count if _m_hs6 == 3 & any_unreported_py != any_unreported
local nf = r(N)
post `PC' ("py_any_unreported_vs_master") (.) (.) (.) (`nf') (cond(`nf' == 0, "PASS", "FAIL"))
local pc_fail = `pc_fail' + `nf'
quietly count if _m_hs6 == 3 & v_8523_exact_py != v_8523_exact
local nf = r(N)
post `PC' ("py_v_8523_exact_vs_master") (.) (.) (.) (`nf') (cond(`nf' == 0, "PASS", "FAIL"))
local pc_fail = `pc_fail' + `nf'
quietly count if _m_hs6 == 1 & !missing(v_ttl_k) & !(any_unreported == 0 & v_8523_exact == 1)
local nf = r(N)
post `PC' ("zero_fill_rows_provenance") (.) (.) (.) (`nf') (cond(`nf' == 0, "PASS", "FAIL"))
local pc_fail = `pc_fail' + `nf'
postclose `PC'
preserve
    use "${OUT}/product_controls.dta", clear
    export delimited using "${OUT}/product_controls.csv", replace
restore
if `pc_fail' != 0 {
    display as error "PRODUCT POSITIVE CONTROL FAILED (n_fail total `pc_fail'); see ${OUT}/product_controls.csv"
    exit 459
}
display as result "PRODUCT_CONTROLS=PASS"
if inlist("${VINTAGE}", "corrected2", "corrected2x") {
    * C2x. 30-code basket = 31-code LB basket minus HS 490700 (banknotes, stamps, cheques,
    *      securities; IMTS 2010 paras 1.46 and 4.15(a)); same
    *      zero/missing rule as v_ttl_k (base_core.py:119-133): raw row present -> sum of the
    *      30 codes; importer-year reporting and no row -> 0; not reporting -> missing.
    local drop4907 h490700_k
    local B_ex4907 : list B_ttl - drop4907
    local B_49ex : list B_49 - drop4907
    assert `: word count `B_ex4907'' == 30
    assert `: word count `B_49ex'' == 18
    gen double v_ttl_ex4907 = 0 if !missing(v_ttl_k)
    foreach h of local B_ex4907 {
        quietly replace v_ttl_ex4907 = v_ttl_ex4907 + `h' if _m_hs6 == 3
    }
    gen double v_49_ex4907 = 0 if !missing(v_ttl_k)
    foreach h of local B_49ex {
        quietly replace v_49_ex4907 = v_49_ex4907 + `h' if _m_hs6 == 3
    }
    gen double v_4907_k = 0 if !missing(v_ttl_k)
    quietly replace v_4907_k = h490700_k if _m_hs6 == 3
    * Where the dyad-year has no HS 490700 value, the 30-code value IS the stored 31-code value
    * (bit-identical, so corrected2x differs from corrected2 only where 490700 > 0); where it has,
    * the 30-code sum above is kept (exact zeros when 490700 is the only code). Controls below.
    gen double __s30 = v_ttl_ex4907
    gen double __s18 = v_49_ex4907
    quietly replace v_ttl_ex4907 = v_ttl_k if v_4907_k == 0
    quietly replace v_49_ex4907 = v_49_k if v_4907_k == 0
    gen double __dd = abs(v_ttl_ex4907 - __s30)
    quietly summarize __dd, meanonly
    display as result "EX4907_STORED_VS_30CODE_SUM_WHERE_NO_490700 max_abs=" %12.3e r(max)
    assert __dd <= 1e-6 + 1e-9 * abs(v_ttl_k) if !missing(__dd)
    replace __dd = abs(v_49_ex4907 - __s18)
    assert __dd <= 1e-6 + 1e-9 * abs(v_49_k) if !missing(__dd)
    drop __s30 __s18 __dd
    label variable v_ttl_ex4907 "30-code LB basket: 31-code LB basket minus HS 490700, importer-reported, 1000 USD"
    label variable v_49_ex4907 "Publications ch.49 minus HS 490700 (18 codes), importer-reported, 1000 USD"
    label variable v_4907_k "HS 490700 component of the LB basket, importer-reported, 1000 USD"
    * positive controls: v_ttl_k - v_ttl_ex4907 = the HS 490700 component on every row
    tempname EX
    postfile `EX' str48 item double rows max_abs_diff n_fail str8 result using "${OUT}/ex4907_controls.dta", replace
    local ex_fail 0
    foreach pair in "v_ttl_k v_ttl_ex4907" "v_49_k v_49_ex4907" "__b_ttl v_ttl_ex4907" "__b_49 v_49_ex4907" {
        gettoken a bb : pair
        local bb = strtrim("`bb'")
        tempvar d
        gen double `d' = abs((`a' - `bb') - v_4907_k) if !missing(v_ttl_k)
        quietly summarize `d', meanonly
        local mx = r(max)
        local nr = r(N)
        quietly count if `d' > 1e-6 + 1e-9 * abs(`a') & !missing(`d')
        local nf = r(N)
        quietly count if missing(`a') != missing(`bb') | missing(`bb') != missing(v_4907_k)
        local nf = `nf' + r(N)
        post `EX' ("(`a' - `bb') - v_4907_k") (`nr') (`mx') (`nf') (cond(`nf' == 0, "PASS", "FAIL"))
        display as result "EX4907_CONTROL (`a' - `bb') - v_4907_k rows=`nr' max_abs=" %12.3e `mx' " n_fail=`nf'"
        local ex_fail = `ex_fail' + `nf'
        drop `d'
    }
    quietly count if v_ttl_ex4907 < 0 | v_49_ex4907 < 0 | v_4907_k < 0
    post `EX' ("negative values") (.) (.) (r(N)) (cond(r(N) == 0, "PASS", "FAIL"))
    local ex_fail = `ex_fail' + r(N)
    quietly count if v_4907_k > 0 & !missing(v_4907_k)
    display as result "EX4907_ROWS_WITH_POSITIVE_490700=" r(N)
    quietly summarize v_4907_k, meanonly
    display as result "EX4907_TOTAL_490700_K=" %18.3f r(sum)
    postclose `EX'
    preserve
        use "${OUT}/ex4907_controls.dta", clear
        export delimited using "${OUT}/ex4907_controls.csv", replace
    restore
    if `ex_fail' != 0 {
        display as error "EX4907 POSITIVE CONTROL FAILED; see ${OUT}/ex4907_controls.csv"
        exit 459
    }
    display as result "EX4907_CONTROLS=PASS"
    * "fully reported" for the 30-code basket: no isReported==false source row outside HS 490700
    gen byte any_unreported_ex4907 = cond(_m_hs6 == 3, (n_unreported_py - n_unreported4907_py) > 0, any_unreported) if !missing(any_unreported)
    label variable any_unreported_ex4907 "Any unreported source row among the 30 codes (31-code LB minus HS 490700)"
    drop n_unreported4907_py
}
if "${VINTAGE}" == "corrected2x" {
    * Outcome switch (author decision: exclude HS 490700): every analysis
    * script reads v_ttl_k, so in corrected2x v_ttl_k IS the 30-code basket and the publications
    * category v_49_k is chapter 49 minus HS 490700. The 31-code values are kept under *_31*.
    * The other baskets do not contain 490700 and are unchanged. Sample flags (section F),
    * positive_trade, pos_every_year and fully_reported follow the switched outcome.
    rename v_ttl_k v_ttl31_k
    gen double v_ttl_k = v_ttl_ex4907
    label variable v_ttl_k "Trade (thousand USD): 30-code LB basket = 31 codes minus HS 490700 (corrected2x)"
    label variable v_ttl31_k "31-code LB basket (= v_ttl_k of corrected/corrected2), 1000 USD"
    rename v_49_k v_49_31_k
    gen double v_49_k = v_49_ex4907
    label variable v_49_k "Publications category: ch.49 minus HS 490700 (corrected2x), 1000 USD"
    label variable v_49_31_k "Publications category incl. HS 490700 (= v_49_k of corrected), 1000 USD"
    rename positive_trade positive_trade31
    gen byte positive_trade = (v_ttl_k > 0) if !missing(v_ttl_k)
    label variable positive_trade "v_ttl_k > 0 (30-code basket, corrected2x)"
    rename any_unreported any_unreported31
    gen byte any_unreported = any_unreported_ex4907
    label variable any_unreported "Any unreported source row of the 30-code basket (corrected2x)"
    assert missing(v_ttl_k) == missing(v_ttl31_k)
    quietly count if v_ttl_k != v_ttl31_k & !missing(v_ttl_k)
    display as result "C2X_OUTCOME_ROWS_DIFFERENT_FROM_31CODE=" r(N)
    local ndiff = r(N)
    quietly count if v_4907_k > 0 & !missing(v_4907_k)
    assert `ndiff' == r(N)
}
drop __b_ttl __b_3706 __b_49 __b_8523 __b_97 cat3706_k cat49_k cat8523_k cat97_k catamb_k
drop any_unreported_py v_8523_exact_py n_source_rows_py n_unreported_py
* The 31 code columns stay in ${HS6_FILE}; drop them here to keep prepared.dta lean.
drop h??????_k amb8523_k
rename _m_hs6 hs6_merge
label variable hs6_merge "Merge with HS6 rows: 1 no raw cultural row for the dyad-year, 3 raw row present"
drop hs6_row_present

* C3. File S1 indicators
* v_8523_exact (indicator): File S1 build_products.py:230 / base_core 05_build_cultural_trade.py:355
*   = 1 if the ambiguous pre-H3 recorded-media pool is zero (zero-filled rows = 1,
*   base_core.py:133); missing for non-reporting importer-years. Estimation in File S1
*   uses v_8523_k on v_8523_exact==1 (run_T6.do:45-46).
label variable v_8523_exact "File S1: recorded-media value exact (ambiguous pre-H3 pool = 0)"
gen double v_8523_exact_k = v_8523_k if v_8523_exact == 1
label variable v_8523_exact_k "Recorded media (852329+852340+852380) on v_8523_exact==1, 1000 USD"
* fully reported: File S1 run_tests.do:250-260 (all any_unreported* == 0; missing excluded)
gen byte fully_reported = (any_unreported == 0)
label variable fully_reported "File S1 T9: no source row with isReported==false (any_unreported==0)"
* positive trade in every year: File S1 run_tests.do:36-47 (T1 'always')
gen byte __pos = v_ttl_k > 0 & !missing(v_ttl_k)
bysort pair_id: egen byte __allpos = min(__pos)
bysort pair_id: gen byte __fullwin = _N == 15
gen byte pos_every_year = __allpos == 1 & __fullwin == 1
label variable pos_every_year "File S1 T1: positive observed trade in all 15 years 2007-2021"
drop __pos __allpos __fullwin
sort pair_id year

*==============================================================================
* D. CEPII Gravity V202211 (PKG/01_raw/03_CEPII). Conte, Cotterlaz & Mayer (2023),
*    "The CEPII Gravity Database", sect. 3 (key = country_id_o country_id_d year;
*    country_exists dummies), sect. 5.1 (comlang_off, comlang_ethno), sect. 8.1
*    (tradeflow_comtrade_o: reported by origin; tradeflow_comtrade_d: reported by
*    destination; tradeflow_baci; all 1000 current USD). The common base used the
*    existing-country rows (base_core.py:79-81), keyed year iso3_o iso3_d.
*==============================================================================
preserve
    use year iso3_o iso3_d country_exists_o country_exists_d tradeflow_comtrade_o tradeflow_comtrade_d ///
        tradeflow_baci comlang_ethno comlang_off gdpcap_o gdpcap_d if inrange(year, 2007, 2021) ///
        using "${CEPII_FILE}", clear
    keep if country_exists_o == 1 & country_exists_d == 1 & iso3_o != iso3_d
    isid year iso3_o iso3_d
    rename comlang_off comlang_off_cepii
    rename comlang_ethno cepii_comlang_ethno
    rename gdpcap_o cepii_gdpcap_o
    rename gdpcap_d cepii_gdpcap_d
    drop country_exists_o country_exists_d
    tempfile cepii
    save `"`cepii'"', replace
restore
merge 1:1 year iso3_o iso3_d using `"`cepii'"', keep(master match) gen(_m_cepii)
nflow step "merge CEPII Gravity V202211 trade flows and language/GDP fields (keep master match)"
quietly count if _m_cepii == 3
display as result "CEPII_MATCHED=" r(N) " OF " _N
assert comlang_off == comlang_off_cepii if !missing(comlang_off, comlang_off_cepii)
quietly count if missing(comlang_off) != missing(comlang_off_cepii)
display as result "COMLANG_OFF_MISSINGNESS_DIFF=" r(N)
drop comlang_off_cepii
rename cepii_comlang_ethno comlang_ethno
rename cepii_gdpcap_o gdpcap_o
rename cepii_gdpcap_d gdpcap_d
label variable tradeflow_comtrade_o "CEPII Gravity: total trade reported by origin (exporter), 1000 current USD"
label variable tradeflow_comtrade_d "CEPII Gravity: total trade reported by destination (importer), 1000 current USD"
label variable tradeflow_baci "CEPII Gravity: BACI harmonized total trade, 1000 current USD"
label variable comlang_ethno "CEPII Gravity: common language spoken by >=9% of population"
label variable gdpcap_o "CEPII Gravity: origin GDP per capita, current thousand USD"
label variable gdpcap_d "CEPII Gravity: destination GDP per capita, current thousand USD"
rename _m_cepii cepii_merge

*==============================================================================
* E. World Bank country classification (01_raw/06_WorldBank/README.md)
*    Current: CLASS.xlsx (FY27). Historical: OGHIST.xlsx 'Country Analytical History'.
*    FY-to-year rule (CLASS.xlsx sheet notes row 3): "For FY27 (July 1, 2026-June 30,
*    2027), income groups are defined using 2025 GNI per capita ... Income classifications
*    set on July 1 remain in effect until the next July 1."  Hence FY(t+1) is in effect
*    1 July t - 30 June t+1 and FY(t) on 1 January - 30 June t.
*    Primary: wb_inc_hist_* = FY(t+1) (set on 1 July of calendar year t; based on GNI of t-1).
*    Alternative: wb_inc_hist_fyt_* = FY(t) (in effect in the first half of year t).
*==============================================================================
preserve
    import excel using "${WB_CLASS}", sheet("List of economies") firstrow allstring clear
    * economy names are NOT carried (terminology rule: author-facing lists use
    * UN designations; ISO3 codes only here)
    keep Code Region Incomegroup
    keep if regexm(Code, "^[A-Z]{3}$") & Region != ""
    isid Code
    rename Code iso3
    rename Region wb_region
    rename Incomegroup wb_income_cur
    tempfile wbcur
    save `"`wbcur'"', replace
    count
    display as result "WB_CURRENT_ECONOMIES=" r(N)

    import excel using "${WB_OGHIST}", sheet("Country Analytical History") allstring clear
    * row 5 = "Bank's fiscal year:" FY labels; row 6 = "Data for calendar year :"
    assert strpos(B[5], "fiscal year") > 0 & strpos(B[6], "calendar year") > 0
    ds A B, not
    foreach v in `r(varlist)' {
        local fy = strtrim(`v'[5])
        if regexm("`fy'", "^FY([0-9][0-9])$") {
            local yy = real(regexs(1))
            local fyyear = cond(`yy' >= 80, 1900 + `yy', 2000 + `yy')
            rename `v' inc`fyyear'
        }
        else drop `v'
    }
    keep if regexm(A, "^[A-Z]{3}$")
    rename A iso3
    drop B
    isid iso3
    reshape long inc, i(iso3) j(fy)
    replace inc = strtrim(inc)
    tab inc, missing
    gen str20 wb_inc = ""
    replace wb_inc = "Low income" if inc == "L"
    replace wb_inc = "Lower middle income" if inc == "LM"
    replace wb_inc = "Upper middle income" if inc == "UM"
    replace wb_inc = "High income" if inc == "H"
    quietly count if wb_inc == "" & !inlist(inc, "", "..")
    display as result "WB_HIST_UNRECOGNISED_CODES=" r(N)
    tab inc if wb_inc == "" & !inlist(inc, "", ".."), missing
    tempfile wbfy
    save `"`wbfy'"', replace
    * calendar-year panel 2007-2021
    clear
    use iso3 using `"`wbfy'"', clear
    duplicates drop
    expand 15
    bysort iso3: gen int year = 2006 + _n
    gen int fy = year + 1
    merge 1:1 iso3 fy using `"`wbfy'"', keep(master match) keepusing(wb_inc inc) nogen
    rename (wb_inc inc) (wb_inc_hist wb_inc_hist_code)
    replace fy = year
    merge 1:1 iso3 fy using `"`wbfy'"', keep(master match) keepusing(wb_inc inc) nogen
    rename (wb_inc inc) (wb_inc_hist_fyt wb_inc_hist_fyt_code)
    drop fy
    tempfile wbhist
    save `"`wbhist'"', replace
restore
foreach side in o d {
    preserve
        use `"`wbcur'"', clear
        rename (iso3 wb_region wb_income_cur) (iso3_`side' wb_region_`side' wb_income_cur_`side')
        tempfile c_`side'
        save `"`c_`side''"', replace
        use `"`wbhist'"', clear
        rename (iso3 wb_inc_hist wb_inc_hist_code wb_inc_hist_fyt wb_inc_hist_fyt_code) ///
               (iso3_`side' wb_inc_hist_`side' wb_inc_hist_code_`side' wb_inc_hist_fyt_`side' wb_inc_hist_fyt_code_`side')
        tempfile h_`side'
        save `"`h_`side''"', replace
    restore
    merge m:1 iso3_`side' using `"`c_`side''"', keep(master match) gen(_wbc_`side')
    nflow step "merge World Bank current classification for iso3_`side' (m:1, keep master match)"
    merge m:1 iso3_`side' year using `"`h_`side''"', keep(master match) gen(_wbh_`side')
    nflow step "merge World Bank historical income (FY t+1 and FY t) for iso3_`side' (m:1, keep master match)"
    label variable wb_region_`side' "World Bank region, current CLASS.xlsx (FY27), iso3_`side'"
    label variable wb_income_cur_`side' "World Bank income group, current CLASS.xlsx (FY27), iso3_`side'"
    label variable wb_inc_hist_`side' "World Bank income group FY(t+1), set 1 July of year t, iso3_`side'"
    label variable wb_inc_hist_fyt_`side' "World Bank income group FY(t), in effect Jan-Jun of year t, iso3_`side'"
    label variable wb_inc_hist_code_`side' "OGHIST raw code FY(t+1), iso3_`side'"
    label variable wb_inc_hist_fyt_code_`side' "OGHIST raw code FY(t), iso3_`side'"
}

*==============================================================================
* F. Sample flags from the original specifications (STUDENT 01_core/04,05,07 and
*    02_sensitivity/01) and ppmlhdfe drop counts per estimation.
*==============================================================================
local FE "exporter_year importer_year pair_id"
local CLUSTER "pair_id"
tempname SC
postfile `SC' str40 estimation str80 spec double N N_full num_singletons num_separated N_clustervars N_clust ///
    N_clust1 N_clust2 converged ic str24 separation using "${OUT}/sample_counts.dta", replace
capture program drop _postcounts
program define _postcounts
    * the authors' ppmlhdfe reporting notes, reporting checklist: N_full and N, singleton and separated
    * counts, e(converged), e(ic), methods, cluster counts. Installed accounting
    * N_full = N + num_singletons + num_separated (ppmlhdfe.ado results posting) is asserted.
    args handle label spec
    assert e(converged) == 1
    assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
    post `handle' ("`label'") ("`spec'") (e(N)) (e(N_full)) (e(num_singletons)) (e(num_separated)) ///
        (e(N_clustervars)) (e(N_clust)) (e(N_clust1)) (e(N_clust2)) (e(converged)) (e(ic)) ("`e(separation)'")
end

* Table 2 col 1 and col 5 (04_table2_baseline.do:15,30)
quietly ppmlhdfe v_ttl_k mob_bilat_vis if has_both_vis, absorb(`FE') vce(cluster `CLUSTER')
gen byte s_base_vis = e(sample)
_postcounts `SC' "T2c1_base_vis" "v_ttl_k mob_bilat_vis if has_both_vis"
nflow est "Table 2 col 1 baseline visitors"
quietly ppmlhdfe v_ttl_k mob_bilat_tour if has_both_tour, absorb(`FE') vce(cluster `CLUSTER')
gen byte s_base_tour = e(sample)
_postcounts `SC' "T2c5_base_tour" "v_ttl_k mob_bilat_tour if has_both_tour"
nflow est "Table 2 col 5 baseline tourists"

* Table 3 (05_table3_dynamic.do:14,20)
quietly ppmlhdfe v_ttl_k lag_bilat_vis mob_bilat_vis lead_bilat_vis, absorb(`FE') vce(cluster `CLUSTER')
gen byte s_dyn_vis = e(sample)
_postcounts `SC' "T3c1_dyn_vis" "v_ttl_k lag mob lead (visitors)"
nflow est "Table 3 col 1 dynamic visitors"
quietly ppmlhdfe v_ttl_k lag_bilat_tour mob_bilat_tour lead_bilat_tour, absorb(`FE') vce(cluster `CLUSTER')
gen byte s_dyn_tour = e(sample)
_postcounts `SC' "T3c2_dyn_tour" "v_ttl_k lag mob lead (tourists)"
nflow est "Table 3 col 2 dynamic tourists"

* Table 5 (07_table5_moderators.do:11-43), variables generated verbatim then dropped
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
quietly ppmlhdfe v_ttl_k mob_bilat_vis vis_x_comlang, absorb(`FE') vce(cluster `CLUSTER')
gen byte s_lang_vis = e(sample)
_postcounts `SC' "T5c1_lang_vis" "v_ttl_k mob_bilat_vis vis_x_comlang"
nflow est "Table 5 col 1 language visitors"
quietly ppmlhdfe v_ttl_k mob_bilat_tour tour_x_comlang, absorb(`FE') vce(cluster `CLUSTER')
gen byte s_lang_tour = e(sample)
_postcounts `SC' "T5c2_lang_tour" "v_ttl_k mob_bilat_tour tour_x_comlang"
nflow est "Table 5 col 2 language tourists"
quietly ppmlhdfe v_ttl_k mob_bilat_vis vis_x_culdist if !missing(culdist_c_vis), absorb(`FE') vce(cluster `CLUSTER')
gen byte s_cd_vis = e(sample)
_postcounts `SC' "T5c3_cd_vis" "v_ttl_k mob_bilat_vis vis_x_culdist if !missing(culdist_c_vis)"
nflow est "Table 5 col 3 cultural distance visitors"
quietly ppmlhdfe v_ttl_k mob_bilat_tour tour_x_culdist if !missing(culdist_c_tour), absorb(`FE') vce(cluster `CLUSTER')
gen byte s_cd_tour = e(sample)
_postcounts `SC' "T5c4_cd_tour" "v_ttl_k mob_bilat_tour tour_x_culdist if !missing(culdist_c_tour)"
nflow est "Table 5 col 4 cultural distance tourists"
drop vis_x_comlang tour_x_comlang culdist_c_vis vis_x_culdist culdist_c_tour tour_x_culdist

* Exact visitor-tourist common support (02_sensitivity/01_common_support_visitors_tourists.do:116-170)
gen byte common_vt_candidate = ///
    has_both_vis == 1 & has_both_tour == 1 & ///
    !missing(v_ttl_k, mob_bilat_vis, mob_bilat_tour)
gen byte s_cs_exact = common_vt_candidate
local converged = 0
local iterations = 0
forvalues iter = 1/10 {
    local iterations = `iter'
    capture drop __es_vis __es_tour
    quietly ppmlhdfe v_ttl_k mob_bilat_vis if s_cs_exact, absorb(`FE') vce(cluster `CLUSTER')
    gen byte __es_vis = e(sample)
    _postcounts `SC' "CS_iter`iter'_vis" "v_ttl_k mob_bilat_vis if s_cs_exact (iteration)"
    quietly ppmlhdfe v_ttl_k mob_bilat_tour if s_cs_exact, absorb(`FE') vce(cluster `CLUSTER')
    gen byte __es_tour = e(sample)
    _postcounts `SC' "CS_iter`iter'_tour" "v_ttl_k mob_bilat_tour if s_cs_exact (iteration)"
    quietly count if s_cs_exact & (!__es_vis | !__es_tour)
    local n_to_remove = r(N)
    if `n_to_remove' == 0 {
        local converged = 1
        continue, break
    }
    replace s_cs_exact = s_cs_exact & __es_vis & __es_tour
}
if `converged' == 0 {
    display as error "Exact common-support intersection did not converge within 10 iterations."
    exit 430
}
drop __es_vis __es_tour
quietly count if common_vt_candidate
display as result "CS_RAW_CANDIDATE_ROWS=" r(N)
quietly count if s_cs_exact
display as result "CS_EXACT_ROWS=" r(N) " ITERATIONS=`iterations'"
rename common_vt_candidate s_cs_candidate
label variable s_cs_candidate "Raw visitor-tourist common-support candidate (01_common_support:116-118)"

postclose `SC'
preserve
    use "${OUT}/sample_counts.dta", clear
    export delimited using "${OUT}/sample_counts.csv", replace
restore

label variable s_base_vis  "e(sample) Table 2 col 1 (bilateral visitors)"
label variable s_base_tour "e(sample) Table 2 col 5 (bilateral tourists)"
label variable s_dyn_vis   "e(sample) Table 3 visitors (lag, current, lead)"
label variable s_dyn_tour  "e(sample) Table 3 tourists (lag, current, lead)"
label variable s_lang_vis  "e(sample) Table 5 col 1 (visitors x common language)"
label variable s_lang_tour "e(sample) Table 5 col 2 (tourists x common language)"
label variable s_cd_vis    "e(sample) Table 5 col 3 (visitors x cultural distance)"
label variable s_cd_tour   "e(sample) Table 5 col 4 (tourists x cultural distance)"
label variable s_cs_exact  "Exact realized visitor-tourist common support (01_common_support:140-165)"

*==============================================================================
* G. Match-rate and unmatched-code reports
*==============================================================================
tempname MR
postfile `MR' str24 source str16 sample double rows matched rate using "${OUT}/match_rates.dta", replace
foreach smp in all s_base_vis s_base_tour s_cs_exact {
    local cond = cond("`smp'" == "all", "1", "`smp' == 1")
    quietly count if `cond'
    local n = r(N)
    quietly count if `cond' & cepii_merge == 3
    post `MR' ("CEPII_row") ("`smp'") (`n') (r(N)) (r(N) / `n')
    quietly count if `cond' & !missing(tradeflow_comtrade_d)
    post `MR' ("tradeflow_comtrade_d_nm") ("`smp'") (`n') (r(N)) (r(N) / `n')
    quietly count if `cond' & !missing(tradeflow_comtrade_o)
    post `MR' ("tradeflow_comtrade_o_nm") ("`smp'") (`n') (r(N)) (r(N) / `n')
    quietly count if `cond' & !missing(tradeflow_baci)
    post `MR' ("tradeflow_baci_nm") ("`smp'") (`n') (r(N)) (r(N) / `n')
    foreach side in o d {
        quietly count if `cond' & _wbc_`side' == 3
        post `MR' ("WB_current_`side'") ("`smp'") (`n') (r(N)) (r(N) / `n')
        quietly count if `cond' & !missing(wb_inc_hist_code_`side') & !inlist(wb_inc_hist_code_`side', "", "..")
        post `MR' ("WB_hist_FYt1_`side'_nonmiss") ("`smp'") (`n') (r(N)) (r(N) / `n')
    }
}
postclose `MR'
preserve
    use "${OUT}/match_rates.dta", clear
    export delimited using "${OUT}/match_rates.csv", replace
    list, noobs clean
restore

* unmatched ISO3 codes (as exporter or importer), with row counts in the samples
tempfile uo_o uo_d
foreach side in o d {
    preserve
        gen byte miss_cur = _wbc_`side' != 3
        gen byte miss_hist = missing(wb_inc_hist_code_`side') | inlist(wb_inc_hist_code_`side', "", "..")
        collapse (count) rows = year (sum) rows_base_vis = s_base_vis rows_base_tour = s_base_tour ///
            (max) miss_cur (sum) rowyears_hist_missing = miss_hist, by(iso3_`side')
        rename iso3_`side' iso3
        format rows rows_base_vis rows_base_tour rowyears_hist_missing %12.0f
        gen str1 side = "`side'"
        save `"`uo_`side''"', replace
    restore
}
preserve
    use `"`uo_o'"', clear
    append using `"`uo_d'"'
    keep if miss_cur == 1 | rowyears_hist_missing > 0
    sort iso3 side
    export delimited using "${OUT}/wb_unmatched.csv", replace
    list, noobs clean
restore
drop _wbc_o _wbc_d _wbh_o _wbh_d

*==============================================================================
* H. Save
*==============================================================================
compress
label data "PREP analysis base, vintage ${VINTAGE}, built `c(current_date)' `c(current_time)' by 01_prep.do"
isid year iso3_o iso3_d
sort pair_id year    // same row order as the original analysis_prepared.dta (02_prepare_data.do:71)
quietly count
assert r(N) == 823446
nflow step "final check before save (no row change expected)"
save "${PREPARED}", replace
nflow report
display as result "PREPARED_SAVED=${PREPARED} ROWS=" _N " VARS=" c(k)
display as result "PREP_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
exit, clear
