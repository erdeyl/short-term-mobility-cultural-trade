/*******************************************************************************
 A2_3.do -- item A2.3 cross-equation tests under directed- and unordered-pair clustering,
 with Holm-adjusted p values per test family (R1.5a, R2.11).
  T1 exact visitor-tourist common support (PKG 02_sensitivity/02_formal_equality:112-196)
  T2 four-category equality on separate category supports (CORE 06_table4_categories.do:60-84;
     reproduction assert added here)
  T3 four-category equality on the common category support (File S1 run_tests.do:87-131,
     Table 7 Panel D)
  T4 reporting-side equality importer / exporter / simple average (PKG 02_sensitivity/
     05_run_reconciled_trade_sensitivity.do:119-280, Table A4)
  T5 visitor-tourist contrasts by category on identical rows (File S1 run_tests.do:134-173,
     Table 7 Panel E; extended to all four categories)
 Every stacked fit: block-specific exporter-year, importer-year and pair FE, cluster on the
 original-row cluster id, stacked slopes reproduce the separate fits to 1e-6 (a2_stack).
 Help: ppmlhdfe.sthlp, [R] test (r(chi2) r(df) r(p)), [R] lincom; Holm (1979) step-down
 adjusted p = max_{j<=i} min(1, (m-j+1) p_(j)).
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
capture log close _all
log using "${LOGS}/A2_3_${VINTAGE}.log", text replace
display as result "A2_3_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
use "${OUT}/A2_work.dta", clear
nflow start using "${OUT}/A2_nflow.csv", append
a2_open "${OUT}/results/A2_3.dta"
local FE "exporter_year importer_year pair_id"
local cat1 "3706"
local cat2 "49"
local cat3 "8523"
local cat4 "97"
local cn1 "film"
local cn2 "publications"
local cn3 "recorded_media"
local cn4 "artworks"
gen double v_rec_k = (v_ttl_k + v_ttl_exporter_lb_k) / 2 if !missing(v_ttl_k, v_ttl_exporter_lb_k)
label variable v_rec_k "Simple average of importer- and exporter-reported LB trade (05_run_reconciled:120-122)"
local tol_pub = 6e-4

*==============================================================================
* T1 exact visitor-tourist common support
*==============================================================================
foreach cl in pair_id unordered_pair_id {
    preserve
    a2_stack, touse(s_cs_exact) ys(v_ttl_k v_ttl_k) xs("mob_bilat_vis ; mob_bilat_tour") cluster(`cl')
    local nu = ${A2_NUNIQ}
    a2_post, item(A2.3) spec(T1_cs_exact_`cl') sample(s_cs_exact) mobility(both) term(s1_1) label(visitors) nuniq(`nu')
    a2_post, item(A2.3) spec(T1_cs_exact_`cl') sample(s_cs_exact) mobility(both) term(s2_1) label(tourists) nuniq(`nu')
    a2_post, item(A2.3) spec(T1_cs_exact_`cl') sample(s_cs_exact) mobility(both) term(s1_1 - s2_1) label(visitors - tourists) nuniq(`nu')
    quietly test s1_1 = s2_1
    local p = r(p)
    a2_posttest, item(A2.3) spec(T1_cs_exact_`cl') sample(s_cs_exact) mobility(both) label(test visitors = tourists) chi2(`r(chi2)') df(`r(df)') p(`r(p)') nuniq(`nu') note("max reproduction gap ${A2_STACK_GAP}")
    display as result "A2_3_T1 `cl' p=" %12.10f `p' " N=`nu' clusters=" e(N_clust)
    restore
    nflow step "restore: after T1 `cl'"
    if "`cl'" == "pair_id" {
        preserve
            import delimited using "${OUT}/positive_controls.csv", clear asdouble varnames(1) stringcols(1)
            quietly summarize reproduced if item == "FER.equality_p"
            local pcp = r(mean)
        restore
        display as result "A2_3_PC_T1 p=" %12.10f `p' " ref=" %12.10f `pcp'
        assert abs(`p' - `pcp') < 1e-8
    }
}

*==============================================================================
* T2 four-category equality on separate category supports (Table 4)
*==============================================================================
global A2_STACK_NOTE ""
preserve
    import delimited using "${OUT}/positive_controls.csv", clear asdouble varnames(1) stringcols(1)
    quietly summarize reproduced if item == "LOG.CATEGORY_EQUALITY.mob_bilat_vis"
    local pc_t2_vis = r(mean)
    quietly summarize reproduced if item == "LOG.CATEGORY_EQUALITY.mob_bilat_tour"
    local pc_t2_tour = r(mean)
restore
foreach m in vis tour {
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    * separate category fits (06_table4_categories.do:14-20)
    local nsum = 0
    forvalues k = 1/4 {
        quietly ppmlhdfe v_`cat`k''_k mob_bilat_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.3 T2 separate category `cat`k'' `mlab'"
        tempname sep`k'
        scalar `sep`k'' = _b[mob_bilat_`m']
        local n`k' = e(N)
        local nsum = `nsum' + e(N)
        gen byte es`k'_`m' = e(sample)
    }
    egen byte esany_`m' = rowmax(es1_`m' es2_`m' es3_`m' es4_`m')
    quietly count if esany_`m'
    local nunion = r(N)
    foreach cl in pair_id unordered_pair_id {
        preserve
            keep if has_both_`m' == 1
            keep year iso3_o iso3_d exporter_year importer_year pair_id unordered_pair_id v_3706_k v_49_k v_8523_k v_97_k mob_bilat_`m'
            nflow step "T2: keep rows with strict bilateral `mlab' (stacking input)"
            quietly expand 4
            nflow step "T2: expand to 4 category blocks"
            bysort year iso3_o iso3_d: gen byte __blk = _n
            quietly gen double __y = .
            forvalues k = 1/4 {
                quietly replace __y = v_`cat`k''_k if __blk == `k'
                quietly gen double s`k'_1 = cond(__blk == `k', mob_bilat_`m', 0)
            }
            egen long __ey = group(exporter_year __blk)
            egen long __iy = group(importer_year __blk)
            egen long __pr = group(pair_id __blk)
            quietly ppmlhdfe __y s1_1 s2_1 s3_1 s4_1, absorb(__ey __iy __pr) vce(cluster `cl')
            a2_chk "A2.3 T2 stacked 4 categories `mlab' cluster `cl'"
            assert e(N) == `nsum'
            local gap = 0
            forvalues k = 1/4 {
                local g = abs(_b[s`k'_1] - `sep`k'')
                if `g' > `gap' local gap = `g'
            }
            display as result "A2_3_T2 `m' `cl' reproduction gap=" `gap'
            assert `gap' < 1e-6
            forvalues k = 1/4 {
                a2_post, item(A2.3) spec(T2_sepsupport_`cl') sample(own category supports) mobility(`mlab') term(s`k'_1) label(`cn`k'') nuniq(`n`k'') note("separate-support N of this category; stacked e(N)=`e(N)' = sum of the four category N; union of rows `nunion'")
            }
            quietly test (s1_1 = s2_1) (s1_1 = s3_1) (s1_1 = s4_1)
            local pj = r(p)
            a2_posttest, item(A2.3) spec(T2_sepsupport_`cl') sample(own category supports) mobility(`mlab') label(joint equality of 4 category slopes) chi2(`r(chi2)') df(`r(df)') p(`r(p)') nuniq(`nunion') note("N = union of the four category supports")
            display as result "A2_3_T2 `m' `cl' joint p=" %12.10f `pj'
            if "`cl'" == "pair_id" assert abs(`pj' - `pc_t2_`m'') < 1e-8
            local plist ""
            local clist ""
            forvalues a = 1/3 {
                local s = `a' + 1
                forvalues b = `s'/4 {
                    a2_post, item(A2.3) spec(T2_sepsupport_`cl') sample(own category supports) mobility(`mlab') term(s`a'_1 - s`b'_1) label(`cn`a'' - `cn`b'') nuniq(`nunion')
                    quietly test s`a'_1 = s`b'_1
                    local plist "`plist' `r(p)'"
                    local clist "`clist' `a'`b'"
                    quietly lincom s`a'_1 - s`b'_1
                    local est`a'`b' = r(estimate)
                    local se`a'`b' = r(se)
                    local raw`a'`b' = r(p)
                }
            }
            a2_holm `plist'
            local i = 0
            foreach ab of local clist {
                local ++i
                local a = substr("`ab'", 1, 1)
                local b = substr("`ab'", 2, 1)
                a2_postval, item(A2.3) spec(T2_sepsupport_`cl'_holm) sample(own category supports) mobility(`mlab') label(holm: `cn`a'' - `cn`b'') value(`est`ab'') se(`se`ab'') p(`=r(h`i')') n(`nunion') note("Holm family = six pairwise category differences, `mlab', clustering `cl', m=6; raw p=`raw`ab''")
            }
        restore
        nflow step "restore: after T2 `m' `cl'"
    }
    drop es1_`m' es2_`m' es3_`m' es4_`m' esany_`m'
}

*==============================================================================
* T3 four-category equality on the common category support (Table 7 Panel D)
*==============================================================================
foreach m in vis tour {
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    gen byte cc_`m' = has_both_`m' & !missing(v_3706_k, v_49_k, v_8523_k, v_97_k)
    a2_fix, touse(cc_`m') models("v_3706_k mob_bilat_`m' ; v_49_k mob_bilat_`m' ; v_8523_k mob_bilat_`m' ; v_97_k mob_bilat_`m'")
    local it = ${A2_FIX_IT}
    foreach cl in pair_id unordered_pair_id {
        preserve
        a2_stack, touse(cc_`m') ys(v_3706_k v_49_k v_8523_k v_97_k) xs("mob_bilat_`m' ; mob_bilat_`m' ; mob_bilat_`m' ; mob_bilat_`m'") cluster(`cl')
        local nu = ${A2_NUNIQ}
        forvalues k = 1/4 {
            a2_post, item(A2.3) spec(T3_commonsupport_`cl') sample(common category support) mobility(`mlab') term(s`k'_1) label(`cn`k'') nuniq(`nu') note("fixed-point iterations=`it'")
        }
        quietly test (s1_1 = s2_1) (s1_1 = s3_1) (s1_1 = s4_1)
        local pj = r(p)
        local cj = r(chi2)
        a2_posttest, item(A2.3) spec(T3_commonsupport_`cl') sample(common category support) mobility(`mlab') label(joint equality of 4 category slopes) chi2(`r(chi2)') df(`r(df)') p(`r(p)') nuniq(`nu')
        display as result "A2_3_T3 `m' `cl' chi2=" %12.6f `cj' " p=" %12.9f `pj' " N=`nu'"
        if "${VINTAGE}" == "submitted" & "`cl'" == "pair_id" {
            local ref = cond("`m'" == "vis", 3.990108, 1.953561)
            local refn = cond("`m'" == "vis", 3666, 4403)
            * published chi2 (File S1 README T3b, default tolerance) to 1e-3: a2_stack may refit
            * with tolerance(1e-11), which moves chi2 in the 4th decimal (log line A2_3_T3)
            assert abs(`cj' - `ref') < 1e-3 & `nu' == `refn'
        }
        local plist ""
        local clist ""
        forvalues a = 1/3 {
            local s = `a' + 1
            forvalues b = `s'/4 {
                a2_post, item(A2.3) spec(T3_commonsupport_`cl') sample(common category support) mobility(`mlab') term(s`a'_1 - s`b'_1) label(`cn`a'' - `cn`b'') nuniq(`nu')
                quietly test s`a'_1 = s`b'_1
                local plist "`plist' `r(p)'"
                local clist "`clist' `a'`b'"
                quietly lincom s`a'_1 - s`b'_1
                local est`a'`b' = r(estimate)
                local se`a'`b' = r(se)
                local raw`a'`b' = r(p)
            }
        }
        a2_holm `plist'
        local i = 0
        foreach ab of local clist {
            local ++i
            local a = substr("`ab'", 1, 1)
            local b = substr("`ab'", 2, 1)
            a2_postval, item(A2.3) spec(T3_commonsupport_`cl'_holm) sample(common category support) mobility(`mlab') label(holm: `cn`a'' - `cn`b'') value(`est`ab'') se(`se`ab'') p(`=r(h`i')') n(`nu') note("Holm family = six pairwise category differences, `mlab', clustering `cl', m=6; raw p=`raw`ab''")
        }
        restore
        nflow step "restore: after T3 `m' `cl'"
    }
}

*==============================================================================
* T4 reporting-side equality (Table A4)
*==============================================================================
local sn1 "importer"
local sn2 "exporter"
local sn3 "average"
foreach m in vis tour {
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    gen byte rc_`m' = has_both_`m' & !missing(v_ttl_k, v_ttl_exporter_lb_k, v_rec_k, mob_bilat_`m')
    quietly count if rc_`m'
    local ncand = r(N)
    a2_fix, touse(rc_`m') models("v_ttl_k mob_bilat_`m' ; v_ttl_exporter_lb_k mob_bilat_`m' ; v_rec_k mob_bilat_`m'")
    local it = ${A2_FIX_IT}
    foreach cl in pair_id unordered_pair_id {
        preserve
        a2_stack, touse(rc_`m') ys(v_ttl_k v_ttl_exporter_lb_k v_rec_k) xs("mob_bilat_`m' ; mob_bilat_`m' ; mob_bilat_`m'") cluster(`cl')
        local nu = ${A2_NUNIQ}
        forvalues k = 1/3 {
            a2_post, item(A2.3) spec(T4_reporting_`cl') sample(reporting-side common support) mobility(`mlab') term(s`k'_1) label(`sn`k'') nuniq(`nu') note("candidate rows=`ncand'; fixed-point iterations=`it'")
        }
        quietly test (s1_1 = s2_1) (s1_1 = s3_1)
        local pall = r(p)
        a2_posttest, item(A2.3) spec(T4_reporting_`cl') sample(reporting-side common support) mobility(`mlab') label(all three equal) chi2(`r(chi2)') df(`r(df)') p(`r(p)') nuniq(`nu')
        local plist ""
        local clist ""
        foreach ab in 12 13 23 {
            local a = substr("`ab'", 1, 1)
            local b = substr("`ab'", 2, 1)
            a2_post, item(A2.3) spec(T4_reporting_`cl') sample(reporting-side common support) mobility(`mlab') term(s`a'_1 - s`b'_1) label(`sn`a'' - `sn`b'') nuniq(`nu')
            quietly test s`a'_1 = s`b'_1
            local plist "`plist' `r(p)'"
            local clist "`clist' `ab'"
            local pr`ab' = r(p)
            quietly lincom s`a'_1 - s`b'_1
            local est`ab' = r(estimate)
            local se`ab' = r(se)
        }
        display as result "A2_3_T4 `m' `cl' N=`nu' imp=" %9.6f _b[s1_1] " exp=" %9.6f _b[s2_1] " avg=" %9.6f _b[s3_1] " p(imp=exp)=" %9.6f `pr12' " p(all)=" %9.6f `pall'
        if "${VINTAGE}" == "submitted" & "`cl'" == "pair_id" {
            local refn = cond("`m'" == "vis", 17612, 21992)
            local refp = cond("`m'" == "vis", 0.003, 0.489)
            local refa = cond("`m'" == "vis", 0.012, 0.332)
            assert `nu' == `refn' & abs(`pr12' - `refp') < `tol_pub' & abs(`pall' - `refa') < `tol_pub'
        }
        a2_holm `plist'
        local i = 0
        foreach ab of local clist {
            local ++i
            local a = substr("`ab'", 1, 1)
            local b = substr("`ab'", 2, 1)
            a2_postval, item(A2.3) spec(T4_reporting_`cl'_holm) sample(reporting-side common support) mobility(`mlab') label(holm: `sn`a'' - `sn`b'') value(`est`ab'') se(`se`ab'') p(`=r(h`i')') n(`nu') note("Holm family = three reporting-side contrasts, `mlab', clustering `cl', m=3; raw p=`pr`ab''")
        }
        restore
        nflow step "restore: after T4 `m' `cl'"
    }
}

*==============================================================================
* T5 visitor-tourist contrasts by category on identical rows (Table 7 Panel E, all categories)
*==============================================================================
forvalues k = 1/4 {
    gen byte vt`k' = has_both_vis & has_both_tour & !missing(v_`cat`k''_k)
    a2_fix, touse(vt`k') models("v_`cat`k''_k mob_bilat_vis ; v_`cat`k''_k mob_bilat_tour")
    local it`k' = ${A2_FIX_IT}
}
foreach cl in pair_id unordered_pair_id {
    local plist ""
    forvalues k = 1/4 {
        preserve
        a2_stack, touse(vt`k') ys(v_`cat`k''_k v_`cat`k''_k) xs("mob_bilat_vis ; mob_bilat_tour") cluster(`cl')
        local nu`k' = ${A2_NUNIQ}
        a2_post, item(A2.3) spec(T5_vt_`cn`k''_`cl') sample(visitor-tourist identical rows) mobility(both) term(s1_1) label(visitors) nuniq(`nu`k'') note("fixed-point iterations=`it`k''")
        a2_post, item(A2.3) spec(T5_vt_`cn`k''_`cl') sample(visitor-tourist identical rows) mobility(both) term(s2_1) label(tourists) nuniq(`nu`k'')
        a2_post, item(A2.3) spec(T5_vt_`cn`k''_`cl') sample(visitor-tourist identical rows) mobility(both) term(s1_1 - s2_1) label(visitors - tourists) nuniq(`nu`k'')
        quietly test s1_1 = s2_1
        local plist "`plist' `r(p)'"
        local raw`k' = r(p)
        quietly lincom s1_1 - s2_1
        local est`k' = r(estimate)
        local se`k' = r(se)
        display as result "A2_3_T5 `cn`k'' `cl' N=`nu`k'' diff=" %9.6f `est`k'' " se=" %9.6f `se`k'' " p=" %9.6f `raw`k''
        if "${VINTAGE}" == "submitted" & "`cl'" == "pair_id" & inlist(`k', 3, 4) {
            local refn = cond(`k' == 4, 1816, 1913)
            local refd = cond(`k' == 4, -0.011, 0.048)
            local refp = cond(`k' == 4, 0.792, 0.538)
            assert `nu`k'' == `refn' & abs(`est`k'' - `refd') < `tol_pub' & abs(`raw`k'' - `refp') < `tol_pub'
        }
        restore
        nflow step "restore: after T5 `cn`k'' `cl'"
    }
    a2_holm `plist'
    forvalues k = 1/4 {
        a2_postval, item(A2.3) spec(T5_vt_`cl'_holm) sample(visitor-tourist identical rows) mobility(both) label(holm: `cn`k'' visitors - tourists) value(`est`k'') se(`se`k'') p(`=r(h`k')') n(`nu`k'') note("Holm family = visitor-tourist contrasts across the four categories, clustering `cl', m=4; raw p=`raw`k''")
    }
}

a2_close "${OUT}/results/A2_3.dta" "${OUT}/results/A2_3.csv"
display as result "A2_3_DONE vintage=${VINTAGE} " c(current_time)
log close
