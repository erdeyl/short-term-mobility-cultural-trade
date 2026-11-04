/*******************************************************************************
 A1_04_directional.do  --  A1.9 directional result and the mobility reporting side (analysis block A1)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do A1_04_directional.do <vintage>
 Input : ${OUT}/prepared.dta (read only); exporter-reported mirror input built by the
         authors' 04_build_mirror_analysis_input.py (submitted: STUDENT, corrected: COPY)
         03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta.
 Output: results part A1_04; tables A1_A1.9_*.csv.
 Direction (FLAGS_CODEBOOK.md section 1; STUDENT 02_prepare_data.do:4-7): in stored row
 i->j, the reverse flow (j->i arrivals) is reported by i (exporter) and the same-direction
 flow (i->j arrivals) by j (importer). Importer-reported trade is reported by j; the mirror
 (exporter-reported) trade by i (04_run_mirror_sensitivity.do:6-8).
 A4 reporting-side common support: 04_run_mirror_sensitivity.do:118-166 (bilateral models,
 iterated intersection of importer- and exporter-side e(sample)).
 Help: ppmlhdfe.sthlp; [R] test; [R] lincom; [D] merge.
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
log using "${LOGS}/A1_04_directional_${VINTAGE}.log", text replace
display as result "A1_04_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
* rerun C2: 00_config.do sets MIRROR for corrected2/corrected2x (corrected2x: 30-code mirror file);
* submitted/corrected leave it empty, so the original line applies to them unchanged
if "${MIRROR}" == "" global MIRROR "${VROOT}/03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta"
confirm file "${MIRROR}"

* positive-control values (PREP positive_controls.csv; Table 2 cols 4 and 8)
preserve
    import delimited using "${OUT}/positive_controls.csv", clear varnames(1) stringcols(_all)
    foreach pair in "T2c4rev|T2.c4.Reverse visitors.b" "T2c4same|T2.c4.Same-direction visitors.b" ///
        "T2c8rev|T2.c8.Reverse tourists.b" "T2c8same|T2.c8.Same-direction tourists.b" {
        gettoken key it : pair, parse("|")
        local it = substr("`it'", 2, .)
        quietly levelsof reproduced if item == "`it'", local(v) clean
        assert "`v'" != ""
        global PC_`key' `v'
    }
restore
* published A4 values of the same vintage (PKG for submitted, COPY run outputs for corrected)
if "${VINTAGE}" == "submitted" global A4KEY "${PKG}/07_results/02_sensitivity/04_mirror_trade/diagnostics/mirror_trade_key_results.csv"
if "${VINTAGE}" == "corrected" global A4KEY "${COPY}/05_output/03_Mobility/01_diagnostics/sensitivity/04_mirror_trade/mirror_trade_key_results.csv"
* rerun C2 input-safety switch: corrected reads the same file from the pre-C14 snapshot (00_config.do PUB_A4KEY)
if "${VINTAGE}" == "corrected" & "${PUB_A4KEY}" != "" global A4KEY "${PUB_A4KEY}"
* rerun C2: corrected2/corrected2x have no published A4 file; the A4 support is rebuilt by the
* same iteration below and the published-value asserts are skipped for them (their controls:
* C2_00_controls.do; A1.9 rows are compared with corrected in 06_results/reconciliation/DELTA_corrected2.md)
global A4PC = inlist("${VINTAGE}", "submitted", "corrected")
if ${A4PC} {
preserve
    import delimited using "${A4KEY}", clear varnames(1) asdouble case(lower)
    foreach mm in visitors tourists {
        foreach sd in importer exporter {
            quietly summarize b if mobility == "`mm'" & reporting_side == "`sd'" & support == "common"
            global A4_`mm'_`sd'_b = r(mean)
            quietly summarize n if mobility == "`mm'" & reporting_side == "`sd'" & support == "common"
            global A4_`mm'_`sd'_N = r(mean)
        }
    }
restore
}

use year iso3_o iso3_d v_ttl_k has_both_vis has_both_tour mob_bilat_vis mob_bilat_tour ///
    mob_rev_vis mob_same_vis mob_rev_tour mob_same_tour exporter_year importer_year pair_id unordered_pair_id ///
    basis_rev_vis basis_same_vis basis_rev_tour basis_same_tour ///
    basis_switch_rev_vis basis_switch_same_vis basis_switch_rev_tour basis_switch_same_tour s_base_vis s_base_tour ///
    using "${PREPARED}", clear
nflow start using "${OUT}/A1_nflow.csv", append expected(823446)
A1_open A1_04
preserve
    use year iso3_o iso3_d v_ttl_k v_ttl_exporter_lb_k export_trade_reporting_available using "${MIRROR}", clear
    isid year iso3_o iso3_d
    rename v_ttl_k v_ttl_k_mirrorfile
    tempfile mir
    save `mir'
restore
merge 1:1 year iso3_o iso3_d using `mir', assert(match) nogen
nflow step "A1.9 merge exporter-reported mirror trade by year iso3_o iso3_d (assert all match)"
* positive control: the mirror input carries the same importer-reported outcome
quietly count if !((v_ttl_k == v_ttl_k_mirrorfile) | (missing(v_ttl_k) & missing(v_ttl_k_mirrorfile)))
display as result "A1.9_MIRRORFILE_VTTL_DIFF_ROWS=" r(N)
assert r(N) == 0
drop v_ttl_k_mirrorfile

foreach m in vis tour {
    gen byte r1_`m' = basis_rev_`m' == basis_same_`m' & inlist(basis_rev_`m', "residence", "nationality")
    gen byte r4_`m' = basis_switch_rev_`m' == 0 & basis_switch_same_`m' == 0
}

* --- helper: joint directional fit, posts rev, same, test rev = same and lincom rev - same
capture program drop A1_dirfit
program define A1_dirfit
    syntax , y(varname) m(string) cond(string) item(string) spec(string) cl(name) [note(string) gen(name)]
    capture noisily ppmlhdfe `y' mob_rev_`m' mob_same_`m' if `cond', absorb(${FE}) vce(cluster `cl')
    local rc = _rc
    local genopt ""
    if "`gen'" != "" local genopt "gen(`gen')"
    A1_after, rc(`rc') item(`item') spec(`spec'_`cl') sample(`cond') mobility(`m') terms(mob_rev_`m' mob_same_`m') `genopt' note("`note'")
    if `rc' == 0 & e(converged) == 1 {
        quietly test mob_rev_`m' = mob_same_`m'
        A1_posttest, item(`item') spec(`spec'_`cl'_test) sample(`cond') mobility(`m') term(rev_eq_same) ///
            stat(`r(chi2)') df(`r(df)') p(`r(p)') nobs(`=e(N)') nfull(`=e(N_full)') ncl(`=e(N_clust)') clv(`e(clustvar)') ///
            note("Wald chi2 H0 b_rev = b_same; `note'")
        quietly lincom mob_rev_`m' - mob_same_`m'
        A1_postlincom, item(`item') spec(`spec'_`cl'_diff) sample(`cond') mobility(`m') term(rev_minus_same) note("`note'")
    }
end

*==============================================================================
* A1.9 (i) joint directional models: full baseline and same basis + no series switch
*==============================================================================
foreach m in vis tour {
    foreach cl in pair_id unordered_pair_id {
        A1_dirfit, y(v_ttl_k) m(`m') cond(has_both_`m') item(A1.9) spec(dir_full) cl(`cl') note("Table 2 joint directional model")
        if "`cl'" == "pair_id" {
            local c = cond("`m'" == "vis", 4, 8)
            assert abs(_b[mob_rev_`m'] - ${PC_T2c`c'rev}) < 1e-6 & abs(_b[mob_same_`m'] - ${PC_T2c`c'same}) < 1e-6
            display as result "A1.9_PC_TABLE2_COL`c' PASS"
        }
        A1_dirfit, y(v_ttl_k) m(`m') cond(has_both_`m' & r1_`m' & r4_`m') item(A1.9) spec(dir_samebasis_noswitch) cl(`cl') ///
            note("same basis in both directions and no basis switch in either series")
    }
}

*==============================================================================
* A1.9 (ii) exporter-reported (mirror) vs importer-reported trade, A4 reporting-side support
*==============================================================================
tempname SUP
postfile `SUP' str5 mobility str40 step double(rows) using "${OUT}/tables/A1_A1.9_support.dta", replace
foreach m in vis tour {
    local mm = cond("`m'" == "vis", "visitors", "tourists")
    * A4 support exactly as 04_run_mirror_sensitivity.do:118-166
    gen byte __ct = has_both_`m' == 1 & !missing(v_ttl_k, v_ttl_exporter_lb_k, mob_bilat_`m')
    quietly count if __ct
    post `SUP' ("`m'") ("A4 raw candidate (both trade sides observed)") (r(N))
    local conv 0
    forvalues it = 1/10 {
        capture drop __i __e
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if __ct, absorb(${FE}) vce(cluster pair_id)
        gen byte __i = e(sample)
        nflow est "A1.9 A4 support iteration `it' importer `m' (immediate record, audit R1-10)"
        quietly ppmlhdfe v_ttl_exporter_lb_k mob_bilat_`m' if __ct, absorb(${FE}) vce(cluster pair_id)
        gen byte __e = e(sample)
        nflow est "A1.9 A4 support iteration `it' exporter `m' (immediate record, audit R1-10)"
        quietly count if __ct & (!__i | !__e)
        if r(N) == 0 {
            local conv 1
            continue, break
        }
        replace __ct = __ct & __i & __e
    }
    assert `conv' == 1
    drop __i __e
    quietly count if __ct
    post `SUP' ("`m'") ("A4 bilateral common support (iterated)") (r(N))
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if __ct, absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.9) spec(A4_bilat_importer) sample(A4 common support) mobility(`m') terms(mob_bilat_`m')
    if ${A4PC} assert abs(_b[mob_bilat_`m'] - ${A4_`mm'_importer_b}) < 1e-6 & e(N) == ${A4_`mm'_importer_N}
    capture noisily ppmlhdfe v_ttl_exporter_lb_k mob_bilat_`m' if __ct, absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.9) spec(A4_bilat_exporter) sample(A4 common support) mobility(`m') terms(mob_bilat_`m')
    if ${A4PC} assert abs(_b[mob_bilat_`m'] - ${A4_`mm'_exporter_b}) < 1e-6 & e(N) == ${A4_`mm'_exporter_N}
    if ${A4PC} display as result "A1.9_PC_TABLE_A4_`m' PASS"
    else display as result "A1.9_PC_TABLE_A4_`m' NOT APPLICABLE (no published A4 for ${VINTAGE})"
    * joint directional models on the A4 support; iterate to identical observations for both sides
    gen byte __cd = __ct
    local conv 0
    forvalues it = 1/10 {
        capture drop __i __e
        quietly ppmlhdfe v_ttl_k mob_rev_`m' mob_same_`m' if __cd, absorb(${FE}) vce(cluster pair_id)
        gen byte __i = e(sample)
        nflow est "A1.9 directional support iteration `it' importer `m' (immediate record, audit R1-10)"
        quietly ppmlhdfe v_ttl_exporter_lb_k mob_rev_`m' mob_same_`m' if __cd, absorb(${FE}) vce(cluster pair_id)
        gen byte __e = e(sample)
        nflow est "A1.9 directional support iteration `it' exporter `m' (immediate record, audit R1-10)"
        quietly count if __cd & (!__i | !__e)
        if r(N) == 0 {
            local conv 1
            continue, break
        }
        replace __cd = __cd & __i & __e
    }
    assert `conv' == 1
    drop __i __e
    quietly count if __cd
    post `SUP' ("`m'") ("directional common support (identical rows both sides)") (r(N))
    foreach cl in pair_id unordered_pair_id {
        A1_dirfit, y(v_ttl_k) m(`m') cond(__cd) item(A1.9) spec(dirA4_importer) cl(`cl') note("importer-reported trade (reported by j); A4 support")
        A1_dirfit, y(v_ttl_exporter_lb_k) m(`m') cond(__cd) item(A1.9) spec(dirA4_exporter) cl(`cl') note("exporter-reported trade (reported by i); A4 support")
    }
    * supplementary stacked test: is the reverse-minus-same gap equal across reporting sides?
    foreach cl in pair_id unordered_pair_id {
        preserve
            keep if __cd
            nflow step "A1.9 stacked side test `m' `cl': keep directional common support"
            keep year iso3_o iso3_d exporter_year importer_year pair_id unordered_pair_id v_ttl_k v_ttl_exporter_lb_k mob_rev_`m' mob_same_`m'
            expand 2
            nflow step "A1.9 stacked side test `m' `cl': expand 2 (side 1 importer, side 2 exporter)"
            bysort year iso3_o iso3_d: gen byte __side = _n
            gen double __y = cond(__side == 1, v_ttl_k, v_ttl_exporter_lb_k)
            gen double rev_imp = cond(__side == 1, mob_rev_`m', 0)
            gen double same_imp = cond(__side == 1, mob_same_`m', 0)
            gen double rev_exp = cond(__side == 2, mob_rev_`m', 0)
            gen double same_exp = cond(__side == 2, mob_same_`m', 0)
            egen long __ey = group(exporter_year __side)
            egen long __iy = group(importer_year __side)
            egen long __pp = group(pair_id __side)
            capture noisily ppmlhdfe __y rev_imp same_imp rev_exp same_exp, absorb(__ey __iy __pp) vce(cluster `cl')
            local rc = _rc
            if `rc' == 0 & e(converged) == 1 {
                assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
                nflow est "A1.9 stacked side test `m' `cl'"
                foreach t in rev_imp same_imp rev_exp same_exp {
                    A1_post1, item(A1.9) spec(dirA4_stacked_`cl') sample(directional common support x2) mobility(`m') term(`t') note("stacked, side-specific FE")
                }
                quietly test (rev_imp - same_imp) = (rev_exp - same_exp)
                A1_posttest, item(A1.9) spec(dirA4_stacked_`cl'_test) sample(directional common support x2) mobility(`m') term(gap_imp_eq_gap_exp) ///
                    stat(`r(chi2)') df(`r(df)') p(`r(p)') nobs(`=e(N)') nfull(`=e(N_full)') ncl(`=e(N_clust)') clv(`e(clustvar)') ///
                    note("H0 (rev-same) importer side = (rev-same) exporter side; supplementary")
                quietly lincom (rev_imp - same_imp) - (rev_exp - same_exp)
                A1_postlincom, item(A1.9) spec(dirA4_stacked_`cl'_diff) sample(directional common support x2) mobility(`m') term(gap_imp_minus_gap_exp) note("supplementary")
            }
            else {
                A1_posttest, item(A1.9) spec(dirA4_stacked_`cl'_test) sample(directional common support x2) mobility(`m') term(gap_imp_eq_gap_exp) ///
                    stat(.) df(.) p(.) note("FAILED stacked fit rc=`rc'")
            }
        restore
        nflow step "A1.9 stacked side test `m' `cl': restore"
    }
    drop __ct __cd
}
postclose `SUP'
preserve
    use "${OUT}/tables/A1_A1.9_support.dta", clear
    gen str10 vintage = "${VINTAGE}"
    order vintage
    export delimited using "${OUT}/tables/A1_A1.9_support.csv", replace
restore
erase "${OUT}/tables/A1_A1.9_support.dta"

A1_close
nflow report
display as result "A1_04_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
exit, clear
