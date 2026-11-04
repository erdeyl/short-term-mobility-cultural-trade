/*******************************************************************************
 C2_A1_07_sweep2.do -- rerun C2: SWEEP2 sensitivities (A1.5 rows)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do C2_A1_07_sweep2.do <vintage>
 Output: ${OUT}/results/A1_parts/A1_07.csv (rows item A1.5, specs below; A1_combine.py picks it up),
         ${OUT}/tables/A1_A1.5_sw2_exclusion_counts.csv, log, nflow records in A1_nflow.csv.
 Definitions (authors' working notes; cell rule = SW2_09_classify.py:17-28:
 a row is flagged if its reverse cell (reporter iso3_o, basis_rev_*) or its same-direction cell
 (reporter iso3_d, basis_same_*) is a flagged reporter-year-series):
   visitors: MDA nationality 2007-2015; KAZ residence 2020-2021; SAU residence, ZAF residence,
             BOL nationality, NOR residence 2020-2021 (tourists-only visitor values)
   tourists: BLR nationality 2007-2020 (organised tourism only); KAZ residence 2020-2021
   trade:    six unexplained single lots PAN->RUS 2013, NZL->SGP 2017, RUS->HKG 2019, RUS->EGY 2018,
             KOR->VEN 2012, CAN->GTM 2021, and NOR->SAU 2019 (record absent from current Comtrade);
             exporter -> importer = iso3_o -> iso3_d
 Specs: x_sw2defn (definitional mobility flags, joint), x_clean_sw2 (A1.5 (vi) "clean measurement"
 x_clean of A1_02_measurement.do lines 351-381, recomputed here verbatim, plus x_sw2defn), x_sw2lots.
 Positive controls: (1) the x_clean fit reproduces A1_02's row A1.5.x_clean.<m>.mob_bilat_<m> of the
 same vintage (|db| < 1e-9, same N); (2) corrected vintage: flagged baseline rows per finding =
 05_output/11_data_screens/NEW_FINDINGS_COUNTS.csv (507, 90 / 318, 146, 136, 242, 84, 80; lots 6 / 0).
 Help consulted: ppmlhdfe.sthlp 2.3.4 (absorb(), vce(cluster), e(N_full), e(num_singletons),
 e(num_separated), e(converged)); [D] merge; [D] import delimited; nflow.sthlp 1.0.1.
 No data value is altered: every restriction is an if-condition.
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
do "A1_00_programs.do"
capture log close _all
log using "${LOGS}/C2_A1_07_sweep2_${VINTAGE}.log", text replace
display as result "C2_A1_07_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)

use year iso3_o iso3_d v_ttl_k has_both_vis has_both_tour mob_bilat_vis mob_bilat_tour ///
    exporter_year importer_year pair_id basis_rev_vis basis_same_vis basis_rev_tour basis_same_tour ///
    s_base_vis s_base_tour using "${PREPARED}", clear
nflow start using "${OUT}/A1_nflow.csv", append expected(823446)
A1_open A1_07
gen byte c_trade = !missing(v_ttl_k)

* ---------------------------------------------------------------- SWEEP2 cell flags (rev | same)
capture program drop _sw2
program define _sw2
    args name fam iso basis y0 y1
    local B = cond("`basis'" == "RES", "residence", "nationality")
    gen byte `name' = (iso3_o == "`iso'" & basis_rev_`fam' == "`B'" & inrange(year, `y0', `y1')) | ///
                      (iso3_d == "`iso'" & basis_same_`fam' == "`B'" & inrange(year, `y0', `y1'))
end
_sw2 f_mda_vis  vis  MDA NAT 2007 2015
_sw2 f_kaz_vis  vis  KAZ RES 2020 2021
_sw2 f_sau_vis  vis  SAU RES 2020 2021
_sw2 f_zaf_vis  vis  ZAF RES 2020 2021
_sw2 f_bol_vis  vis  BOL NAT 2020 2021
_sw2 f_nor_vis  vis  NOR RES 2020 2021
_sw2 f_blr_tour tour BLR NAT 2007 2020
_sw2 f_kaz_tour tour KAZ RES 2020 2021
gen byte x_sw2defn_vis  = f_mda_vis | f_kaz_vis | f_sau_vis | f_zaf_vis | f_bol_vis | f_nor_vis
gen byte x_sw2defn_tour = f_blr_tour | f_kaz_tour
gen byte x_sw2lots = (iso3_o == "PAN" & iso3_d == "RUS" & year == 2013) | (iso3_o == "NZL" & iso3_d == "SGP" & year == 2017) | ///
    (iso3_o == "RUS" & iso3_d == "HKG" & year == 2019) | (iso3_o == "RUS" & iso3_d == "EGY" & year == 2018) | ///
    (iso3_o == "KOR" & iso3_d == "VEN" & year == 2012) | (iso3_o == "CAN" & iso3_d == "GTM" & year == 2021) | ///
    (iso3_o == "NOR" & iso3_d == "SAU" & year == 2019)
quietly count if x_sw2lots
assert r(N) == 7

* ---------------------------------------------------------------- x_clean, verbatim from A1_02_measurement.do:351-381
gen byte x_svksvn = inlist(iso3_o, "SVK", "SVN") | inlist(iso3_d, "SVK", "SVN")
gen byte x_pry_rep = iso3_o == "PRY" | iso3_d == "PRY"
preserve
    import delimited using "${C09_FILE}", clear varnames(1) stringcols(3)
    keep year iso3_d zero_fill_no_rows
    assert zero_fill_no_rows == 1
    quietly count
    assert r(N) == 36
    isid year iso3_d
    drop zero_fill_no_rows
    gen byte x_c09 = 1
    tempfile c09
    save `c09'
restore
merge m:1 year iso3_d using `c09', keep(master match) nogen
nflow step "C2_A1_07 merge C09 importer-year list (m:1 keep master match; no row change)"
replace x_c09 = 0 if missing(x_c09)
gen byte x_cz = ((iso3_o == "SSD" | iso3_d == "SSD") & inrange(year, 2011, 2012)) | ///
    ((inlist(iso3_o, "CUW", "BES", "SXM") | inlist(iso3_d, "CUW", "BES", "SXM")) & inrange(year, 2007, 2010))
gen byte x_rev15 = (iso3_d == "AGO" & inlist(year, 2011, 2012)) | (iso3_d == "GHA" & inlist(year, 2016, 2017, 2018, 2021)) | ///
    (iso3_d == "OMN" & year == 2021) | (iso3_d == "QAT" & inlist(year, 2012, 2013)) | ///
    (iso3_d == "GEO" & inlist(year, 2018, 2020, 2021)) | (inlist(iso3_d, "COD", "CRI", "CIV") & year == 2021)
gen byte x_clean = x_svksvn | x_pry_rep | x_c09 | x_cz | x_rev15

* ---------------------------------------------------------------- counts (+ corrected-vintage positive control)
tempname XS
postfile `XS' str5 measure str16 flag double(cand_rows base_rows base_rows_expected_corrected base_value base_value_share) str6 control ///
    using "${OUT}/tables/A1_A1.5_sw2_exclusion_counts.dta", replace
local nfail 0
foreach m in vis tour {
    quietly summarize v_ttl_k if s_base_`m', meanonly
    local vb = r(sum)
    if "`m'" == "vis" local fl "f_mda_vis:318 f_kaz_vis:146 f_sau_vis:136 f_zaf_vis:242 f_bol_vis:84 f_nor_vis:80 x_sw2defn_vis:. x_sw2lots:6 x_clean:. "
    else local fl "f_blr_tour:507 f_kaz_tour:90 x_sw2defn_tour:. x_sw2lots:0 x_clean:. "
    foreach item of local fl {
        gettoken f e : item, parse(":")
        local e = substr("`e'", 2, .)
        quietly count if has_both_`m' & c_trade & `f'
        local ec = r(N)
        quietly count if s_base_`m' & `f'
        local eb = r(N)
        quietly summarize v_ttl_k if s_base_`m' & `f', meanonly
        local ev = cond(r(N) > 0, r(sum), 0)
        local ctl ""
        if "${VINTAGE}" == "corrected" & "`e'" != "." {
            local ctl = cond(`eb' == `e', "PASS", "FAIL")
            if "`ctl'" == "FAIL" local ++nfail
        }
        post `XS' ("`m'") ("`f'") (`ec') (`eb') (`e') (`ev') (`ev' / `vb') ("`ctl'")
        display as result "SW2_COUNT `m' `f' cand=`ec' base=`eb' expected_corrected=`e' `ctl'"
    }
}
postclose `XS'
preserve
    use "${OUT}/tables/A1_A1.5_sw2_exclusion_counts.dta", clear
    gen str11 vintage = "${VINTAGE}"
    order vintage
    export delimited using "${OUT}/tables/A1_A1.5_sw2_exclusion_counts.csv", replace
restore
erase "${OUT}/tables/A1_A1.5_sw2_exclusion_counts.dta"
if `nfail' > 0 {
    display as error "SWEEP2 count positive control failed (`nfail')"
    exit 459
}

* ---------------------------------------------------------------- estimates
preserve
    import delimited using "${OUT}/results/A1_parts/A1_02.csv", clear varnames(1) stringcols(_all) case(lower)
    foreach m in vis tour {
        quietly levelsof b if row_id == "A1.5.x_clean.`m'.mob_bilat_`m'", local(v) clean
        assert "`v'" != ""
        local ref_b_`m' `v'
        quietly levelsof n if row_id == "A1.5.x_clean.`m'.mob_bilat_`m'", local(v) clean
        local ref_n_`m' `v'
    }
restore
foreach m in vis tour {
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & !x_clean, absorb(${FE}) vce(cluster pair_id)
    assert _rc == 0 & e(converged) == 1
    nflow est "C2_A1_07 positive control x_clean `m'"
    display as result "C2_PC_XCLEAN `m' b=" %18.15f _b[mob_bilat_`m'] " ref=`ref_b_`m'' N=" e(N) " ref=`ref_n_`m''"
    assert abs(_b[mob_bilat_`m'] - real("`ref_b_`m''")) < 1e-9 & e(N) == real("`ref_n_`m''")
    foreach x in x_sw2defn_`m' x_sw2lots {
        quietly count if s_base_`m' & `x'
        local eb = r(N)
        local sp = cond("`x'" == "x_sw2lots", "x_sw2lots", "x_sw2defn")
        capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & !`x', absorb(${FE}) vce(cluster pair_id)
        A1_after, rc(`=_rc') item(A1.5) spec(`sp') sample(has_both_`m' & !`x') mobility(`m') terms(mob_bilat_`m') ///
            note("SWEEP2 exclusion (authors' working notes); baseline e(sample) rows excluded `eb'")
    }
    quietly count if s_base_`m' & (x_clean | x_sw2defn_`m')
    local eb = r(N)
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & !x_clean & !x_sw2defn_`m', absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.5) spec(x_clean_sw2) sample(has_both_`m' & !x_clean & !x_sw2defn_`m') mobility(`m') terms(mob_bilat_`m') ///
        note("clean measurement (A1.5 vi) plus SWEEP2 definitional mobility flags; baseline e(sample) rows excluded `eb'")
}
A1_close
nflow report
display as result "C2_A1_07_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
