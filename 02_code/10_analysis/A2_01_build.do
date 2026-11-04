/*******************************************************************************
 A2_01_build.do -- block A2 working file for one vintage (no data value is altered).
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do A2_launch_<vintage>.do 01   (or do A2_01_build.do <vintage>)
 Output: ${OUT}/A2_work.dta = prepared.dta rows with strict bilateral visitors OR tourists
         (has_both_vis | has_both_tour; every A2 estimation sample lies inside these rows,
         because every A2 model uses mob_bilat_* / mob_rev_* / mob_same_*, which are missing
         elsewhere: STUDENT 02_prepare_data.do:49-56) plus three merged inputs:
   (1) exporter-reported mirror trade v_ttl_exporter_lb_k from the vintage's own
       03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta
       (input of PKG 02_sensitivity/05_run_reconciled_trade_sensitivity.do:67,104);
   (2) CEPII Language (Melitz-Toubal) csl, cnl, col from 01_raw/07_CEPII_Language/ling_web.dta;
   (3) Hofstede distance rebuilt by A2_00_hofstede.py (package rebuild = positive control; official-only).
 Positive controls (fail closed): baseline visitor/tourist fits and the Table 2 directional
 p reproduce PREP's out/<vintage>/positive_controls.csv `reproduced` values.
 Help consulted: [D] merge (1:1, m:1, keep(), assert()), [D] use (varlist using),
 [D] import delimited (asdouble), ppmlhdfe.sthlp, nflow.sthlp (start/append/step/est).
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
do "A2_00_programs.do"
capture mkdir "${OUT}/results"
capture mkdir "${OUT}/tables"
capture log close _all
log using "${LOGS}/A2_01_build_${VINTAGE}.log", text replace
display as result "A2_BUILD_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)

* rerun C2: 00_config.do sets MIRROR for corrected/corrected2/corrected2x (corrected, corrected2: the
* unchanged pre-C14 snapshot of COPY's file; corrected2x: the 30-code mirror file); submitted unchanged
if "${VINTAGE}" == "submitted" global MIRROR "${STUDENT}/03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta"
if "${VINTAGE}" == "corrected" & "${MIRROR}" == "" global MIRROR "${COPY}/03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta"
global LING "${LING_FILE}"
global HOFCD "${OUTROOT}/A2_hofstede/A2_hofstede_cd.csv"
foreach f in PREPARED MIRROR LING HOFCD {
    confirm file "${`f'}"
}

local keepvars year iso3_o iso3_d exporter_id importer_id exporter_year importer_year pair_id unordered_pair_id ///
    rev_vis_raw same_vis_raw bilat_vis_raw rev_tour_raw same_tour_raw bilat_tour_raw ///
    mob_rev_vis mob_same_vis mob_bilat_vis mob_rev_tour mob_same_tour mob_bilat_tour has_both_vis has_both_tour ///
    v_ttl_k v_3706_k v_49_k v_8523_k v_97_k v_unesco_a v_unesco_b v_8523_exact v_8523_exact_k v_8523_amb_k ///
    positive_trade fully_reported pos_every_year any_unreported comtrade_reporting_available ///
    comlang_off comlang_ethno cul_dist any_regional_proxy common_dim_count6 regional_proxy_flag_o regional_proxy_flag_d ///
    tradeflow_comtrade_d s_base_vis s_base_tour s_lang_vis s_lang_tour s_cd_vis s_cd_tour s_cs_exact s_cs_candidate
use `keepvars' using "${PREPARED}", clear
nflow start using "${OUT}/A2_nflow.csv", replace expected(823446)
isid year iso3_o iso3_d
keep if has_both_vis == 1 | has_both_tour == 1
nflow step "A2: keep rows with strict bilateral visitors or tourists (has_both_vis | has_both_tour)"
foreach s in s_base_vis s_base_tour s_lang_vis s_lang_tour s_cd_vis s_cd_tour s_cs_exact {
    quietly count if `s'
    display as result "A2_FLAG_`s'=" r(N)
}

* ---------------------------------------------------------------- (1) mirror trade
preserve
    use year iso3_o iso3_d v_ttl_k v_ttl_exporter_lb_k export_trade_reporting_available using "${MIRROR}", clear
    isid year iso3_o iso3_d
    rename v_ttl_k mir_v_ttl_k
    tempfile mir
    save `"`mir'"'
restore
merge 1:1 year iso3_o iso3_d using `"`mir'"', keep(master match) gen(_m_mirror)
tab _m_mirror
assert _m_mirror == 3
drop _m_mirror
nflow step "A2: merge exporter-reported mirror trade 1:1 (all master rows matched)"
quietly count if !((v_ttl_k == mir_v_ttl_k) | (missing(v_ttl_k) & missing(mir_v_ttl_k)))
local mir_mismatch = r(N)
display as result "A2_MIRROR_VTTLK_MISMATCH_ROWS=" `mir_mismatch'
quietly count if !missing(v_ttl_exporter_lb_k)
display as result "A2_MIRROR_EXPORTER_NONMISSING=" r(N)
label variable v_ttl_exporter_lb_k "Exporter-reported cultural trade LB, 1000 USD (vintage mirror_analysis_ready.dta)"

* ---------------------------------------------------------------- (2) CEPII Language
preserve
    use iso_o iso_d col csl cnl using "${LING}", clear
    isid iso_o iso_d
    rename (iso_o iso_d col csl cnl) (iso3_o iso3_d mt_col mt_csl mt_cnl)
    tempfile ling
    save `"`ling'"'
restore
merge m:1 iso3_o iso3_d using `"`ling'"', keep(master match) gen(_m_ling)
tab _m_ling
nflow step "A2: merge CEPII Language (m:1 by iso3_o iso3_d; unmatched kept with missing csl/cnl)"
gen byte ling_match = _m_ling == 3
drop _m_ling
label variable mt_csl "CEPII Language: common spoken language (Melitz-Toubal), 0-1"
label variable mt_cnl "CEPII Language: common native language (Melitz-Toubal), 0-1"
label variable mt_col "CEPII Language: common official language (Melitz-Toubal), 0/1"

* ---------------------------------------------------------------- (3) Hofstede rebuilds
preserve
    import delimited using "${HOFCD}", clear asdouble varnames(1) stringcols(1 2)
    isid iso3_o iso3_d
    tempfile hof
    save `"`hof'"'
restore
merge m:1 iso3_o iso3_d using `"`hof'"', keep(master match) gen(_m_hof)
tab _m_hof
nflow step "A2: merge Hofstede rebuilds (m:1; economies without Hofstede rows unmatched, missing)"
drop _m_hof
* positive control: the package rebuild reproduces prepared cul_dist exactly (missingness and values)
quietly count if missing(cul_dist) != missing(cd_pkg_rebuilt)
local hof_missdiff = r(N)
gen double __d = abs(cul_dist - cd_pkg_rebuilt)
quietly summarize __d
local hof_maxdiff = r(max)
drop __d
display as result "A2_HOFSTEDE_PKG_REBUILD_MISSINGNESS_DIFF=" `hof_missdiff' " MAXABSDIFF=" `hof_maxdiff'
assert `hof_missdiff' == 0
assert `hof_maxdiff' < 1e-9
quietly count if missing(common_dim_count6) != missing(cdim_pkg_rebuilt) & !missing(cul_dist)
assert r(N) == 0
label variable cd_off "Hofstede cd6_ge4 rebuilt from the OFFICIAL 2015-08-16 workbook only (A2_00_hofstede.py)"
label variable cdim_off "Official-only: number of the six dimensions with both scores"

compress
sort pair_id year
save "${OUT}/A2_work.dta", replace

* ---------------------------------------------------------------- positive controls vs PREP
preserve
    import delimited using "${OUT}/positive_controls.csv", clear asdouble varnames(1) stringcols(1)
    keep item reproduced
    local k = 0
    foreach it in visitor_b tourist_b visitor_n tourist_n visitor_direction_equality_p {
        quietly summarize reproduced if item == "BKR.`it'"
        assert r(N) == 1
        local pc_`it' = r(mean)
    }
restore
quietly ppmlhdfe v_ttl_k mob_bilat_vis if has_both_vis, absorb(exporter_year importer_year pair_id) vce(cluster pair_id)
a2_chk
nflow est "A2 PC baseline visitors (Table 2 col 1)"
display as result "A2_PC_VIS b=" %18.15f _b[mob_bilat_vis] " ref=" %18.15f `pc_visitor_b' " N=" e(N)
assert abs(_b[mob_bilat_vis] - `pc_visitor_b') < 1e-9 & e(N) == `pc_visitor_n'
gen byte __es = e(sample)
assert __es == s_base_vis
drop __es
quietly ppmlhdfe v_ttl_k mob_bilat_tour if has_both_tour, absorb(exporter_year importer_year pair_id) vce(cluster pair_id)
a2_chk
nflow est "A2 PC baseline tourists (Table 2 col 5)"
display as result "A2_PC_TOUR b=" %18.15f _b[mob_bilat_tour] " ref=" %18.15f `pc_tourist_b' " N=" e(N)
assert abs(_b[mob_bilat_tour] - `pc_tourist_b') < 1e-9 & e(N) == `pc_tourist_n'
quietly ppmlhdfe v_ttl_k mob_rev_vis mob_same_vis if has_both_vis, absorb(exporter_year importer_year pair_id) vce(cluster pair_id)
a2_chk
quietly test mob_rev_vis = mob_same_vis
display as result "A2_PC_DIRP p=" %18.15f r(p) " ref=" %18.15f `pc_visitor_direction_equality_p'
assert abs(r(p) - `pc_visitor_direction_equality_p') < 1e-8
display as result "A2_BUILD_PASS vintage=${VINTAGE} mirror_vttlk_mismatch=`mir_mismatch'"
log close
