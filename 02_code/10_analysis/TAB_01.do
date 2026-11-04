/*******************************************************************************
 TAB_01.do -- TAB step: table cells with no corrected-vintage estimate yet (one vintage per run).
 Usage (cwd = 02_code/10_analysis):  "$STATA" -b -q do TAB_01.do <vintage>     (vintage = submitted | corrected)
 Specification = File S1 code (run_tests.do T5/T10/T11/T12, run_T6.do) and PKG 03_table1_descriptives.do:
   ppmlhdfe y x [if], absorb(exporter_year importer_year pair_id) vce(cluster pair_id); same FE/cluster as the paper.
 Items (all on out/<vintage>/prepared.dta; no data value is altered, restrictions are if-conditions):
   T1.*   Table 1 descriptive statistics (summarize on the full prepared file)
   T11.*  Table 7 Panel B: exclude pair-years above the 99.9th percentile of each directional flow
          (run_tests.do:289-309; reverse and same-direction cutoffs separately for "directional")
   T10.*  Table 7 Panel C: same_basis==1 (stored direction) and same_basis in both directions
          (run_tests.do:264-275; same_basis, cd6_strict from the vintage's own master, as construct_metadata.do)
   T6.*   Table A5 artworks HS 9701-9703 (v_art3) and publications excl. 4907/4908/4911 (v_pub_core)
          (run_T6.do:42-61; PREP rebuilt the HS6 outcomes from the raw API files)
   T12.*  Table A5 visitor-minus-tourist difference, alone and controlling for tourists (run_tests.do:312-324)
   T5.*   Table A5 cultural distance requiring all six Hofstede dimensions (run_tests.do:176-206, strict part)
 Help files consulted (installed): ppmlhdfe.sthlp 2.3.4 (e(converged) l.287, e(N_full) l.261,
 e(num_singletons) l.259, e(num_separated) l.260; absorb(), vce(cluster)), [R] lincom (level(), r(estimate)
 r(se) r(p) r(lb) r(ub), lincom.sthlp l.191-196), [R] pctile/_pctile (percentile in r(r1), pctile.sthlp l.195),
 [R] summarize (r(N) r(mean) r(sd) r(min) r(max)), [D] merge (1:1, keep(), assert), nflow.sthlp (start/step/est).
 Every ppmlhdfe fit: assert e(converged)==1 and e(N_full)==e(N)+e(num_singletons)+e(num_separated).
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
capture log close _all
log using "${OUT}/TAB_01_${VINTAGE}.log", text replace
display as result "TAB_01_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)

local FE "exporter_year importer_year pair_id"

* ---------------------------------------------------------------- programs
capture program drop tab_open
program define tab_open
    args file
    capture postclose TABH
    postfile TABH str10 vintage str8 item str64 spec str80 sample str40 term double(b se p ci95_lo ci95_hi ci90_lo ci90_hi N N_full n_singletons n_separated n_clusters) ///
        str20 cluster_var str244 note using "`file'", replace
end

capture program drop tab_post
program define tab_post
    * tab_post, item() spec() sample() term() [note()]  -- records the current ppmlhdfe/lincom of `term'
    syntax, item(string) spec(string) sample(string) term(string) [note(string)]
    assert "`e(cmd)'" == "ppmlhdfe"
    assert e(converged) == 1
    assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
    local N = e(N)
    local nf = e(N_full)
    local ns = e(num_singletons)
    local nsep = e(num_separated)
    local ncl = e(N_clust)
    local cv "`e(clustvar)'"
    quietly lincom `term', level(95)
    local b = r(estimate)
    local se = r(se)
    local p = r(p)
    local lo95 = r(lb)
    local hi95 = r(ub)
    quietly lincom `term', level(90)
    local lo90 = r(lb)
    local hi90 = r(ub)
    post TABH ("${VINTAGE}") ("`item'") ("`spec'") ("`sample'") ("`term'") (`b') (`se') (`p') (`lo95') (`hi95') (`lo90') (`hi90') ///
        (`N') (`nf') (`ns') (`nsep') (`ncl') ("`cv'") (`"`note'"')
    display as result "TAB_FIT `item' `spec' `term' b=" %12.9f `b' " se=" %12.9f `se' " p=" %9.6f `p' " N=" `N' " N_full=" `nf' " singletons=" `ns' " separated=" `nsep'
end

capture program drop tab_close
program define tab_close
    args dtafile csvfile
    postclose TABH
    preserve
        use "`dtafile'", clear
        format b se p ci95_lo ci95_hi ci90_lo ci90_hi N N_full n_singletons n_separated n_clusters %24.17g
        export delimited using "`csvfile'", datafmt replace
    restore
end

* ---------------------------------------------------------------- T1: Table 1 on the full prepared file
use "${PREPARED}", clear
nflow start using "${OUT}/TAB_nflow.csv", append
quietly count
assert r(N) == 823446
tempname T1
postfile `T1' str10 vintage str40 variable double(N mean sd min max) using "${OUT}/TAB_table1.dta", replace
foreach v in v_ttl_k bilat_vis_raw rev_vis_raw same_vis_raw bilat_tour_raw rev_tour_raw same_tour_raw ///
             ln_dist contig comlang_off comcol col45 comrelig cul_dist {
    quietly summarize `v'
    post `T1' ("${VINTAGE}") ("`v'") (r(N)) (r(mean)) (r(sd)) (r(min)) (r(max))
    display as result "TAB_T1 `v' N=" r(N) " mean=" %20.9f r(mean) " sd=" %20.9f r(sd) " min=" %14.3f r(min) " max=" %20.3f r(max)
}
postclose `T1'
preserve
    use "${OUT}/TAB_table1.dta", clear
    format N mean sd min max %24.17g
    export delimited using "${OUT}/TAB_table1.csv", datafmt replace
restore

* ---------------------------------------------------------------- estimation file: rows with strict bilateral visitors or tourists
keep if has_both_vis == 1 | has_both_tour == 1
nflow step "TAB: keep rows with strict bilateral visitors or tourists (every model below needs mob_bilat_vis or mob_bilat_tour)"

* master merge: same_basis, cd6_strict (vintage's own master; construct_metadata.do:5-11 takes them from the master)
preserve
    use year iso3_o iso3_d same_basis cd6_strict common_dim_count6 using "${MASTER_FILE}", clear
    isid year iso3_o iso3_d
    tempfile mst
    save `"`mst'"'
    * opposite-direction row (construct_metadata.do:22-31)
    rename same_basis same_basis_opposite
    keep year iso3_o iso3_d same_basis_opposite
    rename iso3_o __sw
    rename iso3_d iso3_o
    rename __sw iso3_d
    tempfile opp
    save `"`opp'"'
restore
merge 1:1 year iso3_o iso3_d using `"`mst'"', keep(master match) gen(_m_mst)
assert _m_mst == 3
drop _m_mst
nflow step "TAB: merge master same_basis, cd6_strict (1:1, all matched)"
merge 1:1 year iso3_o iso3_d using `"`opp'"', keep(master match) gen(_m_opp)
quietly count if _m_opp == 1
display as result "TAB_OPPOSITE_UNMATCHED=" r(N)
assert r(N) == 0
drop _m_opp
nflow step "TAB: merge opposite-direction same_basis (1:1, all matched)"

* control: cd6_strict is cul_dist where all six dimensions exist (cul_dist = cd6_ge4)
quietly count if !missing(cd6_strict) & common_dim_count6 != 6
assert r(N) == 0
gen double __d = abs(cd6_strict - cul_dist) if !missing(cd6_strict)
quietly summarize __d
display as result "TAB_CD6_STRICT_VS_CULDIST maxabsdiff=" r(max) " N=" r(N)
assert r(max) < 1e-9
drop __d
* same_basis vs prepared basis variables (diagnostic only; reported in log)
gen byte __sb = (basis_rev_vis == basis_rev_tour) & basis_rev_vis != "" & basis_rev_tour != ""
quietly count if __sb != same_basis & !missing(same_basis)
display as result "TAB_SAME_BASIS_VS_PREPARED_BASIS rows_differing=" r(N)
quietly count if __sb != same_basis & !missing(same_basis) & pry_res_quarantine_rev != 1
display as result "TAB_SAME_BASIS_VS_PREPARED_BASIS rows_differing_outside_PRY_quarantine=" r(N)
drop __sb

tab_open "${OUT}/TAB_results.dta"

* ---------------------------------------------------------------- T11: Table 7 Panel B, top 0.1% of directional flows
foreach m in vis tour {
    foreach mode in directional bilateral {
        local raw "rev_`m'_raw"
        if "`mode'" == "bilateral" local raw "bilat_`m'_raw"
        quietly _pctile `raw' if has_both_`m' & !missing(v_ttl_k), p(99.9)
        local cutoff = r(r1)
        gen byte __trim = has_both_`m' & !missing(v_ttl_k) & `raw' > `cutoff'
        local cnote "cutoff=`cutoff'"
        if "`mode'" == "directional" {
            quietly _pctile same_`m'_raw if has_both_`m' & !missing(v_ttl_k), p(99.9)
            local scut = r(r1)
            quietly replace __trim = 1 if has_both_`m' & !missing(v_ttl_k) & same_`m'_raw > `scut'
            local cnote "reverse cutoff=`cutoff'; same cutoff=`scut'"
        }
        quietly count if __trim
        local dn = r(N)
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & !__trim, absorb(`FE') vce(cluster pair_id)
        nflow est "TAB T11 trim_`mode'_`m'"
        tab_post, item(T11) spec(trim_`mode') sample(has_both_`m' & !trim) term(mob_bilat_`m') note("Above 99.9th percentile of `mode' flow; `cnote'; candidate exclusions=`dn'")
        drop __trim
    }
}

* ---------------------------------------------------------------- T10: Table 7 Panel C, compatible origin bases
foreach m in vis tour {
    foreach mode in source bilateral {
        local cond "same_basis == 1"
        if "`mode'" == "bilateral" local cond "same_basis == 1 & same_basis_opposite == 1"
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & `cond', absorb(`FE') vce(cluster pair_id)
        nflow est "TAB T10 same_basis_`mode'_`m'"
        tab_post, item(T10) spec(same_basis_`mode') sample(has_both_`m' & `cond') term(mob_bilat_`m') note("source: same_basis==1 in the stored source row; bilateral: also opposite source row same_basis==1")
    }
}

* ---------------------------------------------------------------- T6: Table A5 artworks 9701-9703, publications excl. 4907/4908/4911
foreach m in vis tour {
    quietly ppmlhdfe v_art3 mob_bilat_`m' if has_both_`m', absorb(`FE') vce(cluster pair_id)
    nflow est "TAB T6 art3_`m'"
    tab_post, item(T6) spec(artworks_9701_9703) sample(has_both_`m') term(mob_bilat_`m') note("v_art3: HS 970110 970190 970200 970300 (PREP rebuild from raw API files)")
    quietly ppmlhdfe v_pub_core mob_bilat_`m' if has_both_`m', absorb(`FE') vce(cluster pair_id)
    nflow est "TAB T6 pub_core_`m'"
    tab_post, item(T6) spec(publications_excl_4907_4908_4911) sample(has_both_`m') term(mob_bilat_`m') note("v_pub_core: chapter 49 excluding 4907, 4908, 4911 (13 codes)")
}

* ---------------------------------------------------------------- T12: Table A5 visitor-minus-tourist difference
gen byte __common = has_both_vis & has_both_tour
quietly count if __common & !missing(v_ttl_k) & bilat_vis_raw - bilat_tour_raw < 0
local negative_n = r(N)
gen double __day = bilat_vis_raw - bilat_tour_raw if __common & bilat_vis_raw - bilat_tour_raw >= 0
gen double mob_day = asinh(__day) if !missing(__day)
quietly ppmlhdfe v_ttl_k mob_day if __common & !missing(mob_day), absorb(`FE') vce(cluster pair_id)
nflow est "TAB T12 same_day_only"
tab_post, item(T12) spec(same_day_only) sample(common & day>=0) term(mob_day) note("IHS of bilateral visitors minus bilateral tourists; negative differences excluded (trade-observed negative cases=`negative_n')")
quietly ppmlhdfe v_ttl_k mob_day mob_bilat_tour if __common & !missing(mob_day), absorb(`FE') vce(cluster pair_id)
nflow est "TAB T12 same_day_with_overnight"
tab_post, item(T12) spec(same_day_with_overnight) sample(common & day>=0) term(mob_day) note("controlling for IHS bilateral tourists")
tab_post, item(T12) spec(overnight_with_same_day) sample(common & day>=0) term(mob_bilat_tour) note("IHS bilateral tourists, controlling for same-day IHS")

* ---------------------------------------------------------------- T5 (strict part): cultural distance with all six dimensions
foreach m in vis tour {
    quietly summarize cd6_strict if has_both_`m' & !missing(v_ttl_k, cd6_strict), meanonly
    gen double strict_center = cd6_strict - r(mean)
    gen double strict_x = mob_bilat_`m' * strict_center
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' strict_x if has_both_`m' & !missing(cd6_strict), absorb(`FE') vce(cluster pair_id)
    nflow est "TAB T5 strict6 first fit `m'"
    gen byte strict_sample = e(sample)
    quietly summarize cd6_strict if strict_sample, meanonly
    local cmean = r(mean)
    quietly replace strict_center = cd6_strict - r(mean)
    quietly replace strict_x = mob_bilat_`m' * strict_center
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' strict_x if strict_sample, absorb(`FE') vce(cluster pair_id)
    nflow est "TAB T5 strict6 refit `m'"
    tab_post, item(T5) spec(strict6_mobility) sample(strict_sample) term(mob_bilat_`m') note("mobility slope at the retained-sample mean of cd6_strict (`cmean')")
    tab_post, item(T5) spec(strict6_interaction) sample(strict_sample) term(strict_x) note("interaction with centred cd6_strict; all six Hofstede dimensions observed")
    drop strict_center strict_x strict_sample
}

tab_close "${OUT}/TAB_results.dta" "${OUT}/TAB_results.csv"
display as result "TAB_01_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
exit, clear
