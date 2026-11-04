/*******************************************************************************
 A1_01_flow_coverage.do  --  A1.1 sample flow, A1.2 coverage (analysis block A1)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do A1_01_flow_coverage.do <vintage>
 Input : ${OUT}/prepared.dta (read only). Output: ${OUT}/tables/A1_A1.1_*.csv,
         ${OUT}/tables/A1_A1.2_*.csv, ${OUT}/results/A1_parts/A1_01.csv, logs.
 Sample definitions = PREP flags (01_prep.do section F), reproduced here by the same
 original specifications and asserted equal (positive control).
 Help: ppmlhdfe.sthlp (e(N_full), e(num_singletons), e(num_separated), e(sample));
 [D] collapse; [D] egen (tag, group); [D] export delimited; nflow.sthlp.
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
log using "${LOGS}/A1_01_flow_coverage_${VINTAGE}.log", text replace
display as result "A1_01_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)

use year iso3_o iso3_d v_ttl_k has_rev_vis has_same_vis has_both_vis has_rev_tour has_same_tour has_both_tour ///
    mob_bilat_vis mob_bilat_tour lag_bilat_vis lead_bilat_vis lag_bilat_tour lead_bilat_tour cul_dist ///
    exporter_year importer_year pair_id unordered_pair_id ///
    s_base_vis s_base_tour s_dyn_vis s_dyn_tour s_cd_vis s_cd_tour s_cs_candidate s_cs_exact ///
    wb_region_o wb_region_d wb_income_cur_o wb_income_cur_d wb_inc_hist_o wb_inc_hist_d ///
    using "${PREPARED}", clear
nflow start using "${OUT}/A1_nflow.csv", append expected(823446)
assert _N == 823446
A1_open A1_01

tempname FL
postfile `FL' str12 sample str5 mobility str16 order int step str70 condition double(rows_remaining rows_removed) ///
    str120 note using "${OUT}/tables/A1_A1.1_flow.dta", replace
tempname OC
postfile `OC' str12 sample str5 mobility str40 condition double(rows_failing_alone rows_failing_only_this master) ///
    using "${OUT}/tables/A1_A1.1_condition_counts.dta", replace

gen byte c_trade = !missing(v_ttl_k)

*==============================================================================
* A1.1 (a) baseline samples
*==============================================================================
foreach m in vis tour {
    local mob = cond("`m'" == "vis", "visitors", "tourists")
    quietly count
    local n0 = r(N)
    * order A: trade first
    post `FL' ("base") ("`m'") ("trade_first") (0) ("master panel (directed dyad-years 2007-2021)") (`n0') (.) ("")
    quietly count if c_trade
    local n1 = r(N)
    post `FL' ("base") ("`m'") ("trade_first") (1) ("trade observed (importer-year reports, incl. zeros)") (`n1') (`n0' - `n1') ("")
    quietly count if c_trade & has_rev_`m'
    local n2 = r(N)
    post `FL' ("base") ("`m'") ("trade_first") (2) ("+ stored-direction (reverse) mobility observed") (`n2') (`n1' - `n2') ("")
    quietly count if c_trade & has_both_`m'
    local n3 = r(N)
    post `FL' ("base") ("`m'") ("trade_first") (3) ("+ opposite-direction mobility observed (has_both)") (`n3') (`n2' - `n3') ("= both directions and trade observed")
    * PPML
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m', absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.1) spec(baseline) sample(has_both_`m') mobility(`m') terms(mob_bilat_`m') gen(__es)
    assert e(N_full) == `n3'
    assert __es == s_base_`m'
    local nsing = e(num_singletons)
    local nsep = e(num_separated)
    local nn = e(N)
    drop __es
    post `FL' ("base") ("`m'") ("trade_first") (4) ("PPML: singleton observations dropped (e(num_singletons))") (`n3' - `nsing') (`nsing') ("")
    post `FL' ("base") ("`m'") ("trade_first") (5) ("PPML: separated observations dropped (e(num_separated))") (`nn') (`nsep') ("final e(N)")
    * order B: mobility first
    post `FL' ("base") ("`m'") ("mobility_first") (0) ("master panel (directed dyad-years 2007-2021)") (`n0') (.) ("")
    quietly count if has_rev_`m'
    local b1 = r(N)
    post `FL' ("base") ("`m'") ("mobility_first") (1) ("stored-direction (reverse) mobility observed") (`b1') (`n0' - `b1') ("")
    quietly count if has_both_`m'
    local b2 = r(N)
    post `FL' ("base") ("`m'") ("mobility_first") (2) ("+ opposite-direction mobility observed (has_both)") (`b2') (`b1' - `b2') ("")
    post `FL' ("base") ("`m'") ("mobility_first") (3) ("+ trade observed") (`n3') (`b2' - `n3') ("")
    post `FL' ("base") ("`m'") ("mobility_first") (4) ("PPML: singleton observations dropped (e(num_singletons))") (`n3' - `nsing') (`nsing') ("")
    post `FL' ("base") ("`m'") ("mobility_first") (5) ("PPML: separated observations dropped (e(num_separated))") (`nn') (`nsep') ("final e(N)")
    * order-independent counts
    foreach c in c_trade has_rev_`m' has_same_`m' {
        local others = subinstr("c_trade has_rev_`m' has_same_`m'", "`c'", "", 1)
        local oc "1"
        foreach o of local others {
            local oc "`oc' & `o'"
        }
        quietly count if !`c'
        local fa = r(N)
        quietly count if !`c' & `oc'
        local fo = r(N)
        post `OC' ("base") ("`m'") ("`c'") (`fa') (`fo') (`n0')
    }
}

*==============================================================================
* A1.1 (b) exact visitor-tourist common support (01_common_support:116-170 logic, as 01_prep F)
*==============================================================================
quietly count
local n0 = r(N)
post `FL' ("cs_exact") ("both") ("trade_first") (0) ("master panel") (`n0') (.) ("")
quietly count if c_trade
local n1 = r(N)
post `FL' ("cs_exact") ("both") ("trade_first") (1) ("trade observed") (`n1') (`n0' - `n1') ("")
quietly count if c_trade & has_both_vis
local n2 = r(N)
post `FL' ("cs_exact") ("both") ("trade_first") (2) ("+ visitors observed in both directions") (`n2') (`n1' - `n2') ("")
quietly count if c_trade & has_both_vis & has_both_tour
local n3 = r(N)
post `FL' ("cs_exact") ("both") ("trade_first") (3) ("+ tourists observed in both directions (raw candidate)") (`n3') (`n2' - `n3') ("")
gen byte __cs = c_trade & has_both_vis & has_both_tour
assert __cs == s_cs_candidate
local step 3
forvalues it = 1/10 {
    capture drop __ev __et
    capture noisily ppmlhdfe v_ttl_k mob_bilat_vis if __cs, absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.1) spec(cs_iter`it') sample(cs_candidate_iter`it') mobility(vis) terms(mob_bilat_vis) gen(__ev)
    local sv = e(num_singletons)
    local pv = e(num_separated)
    capture noisily ppmlhdfe v_ttl_k mob_bilat_tour if __cs, absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.1) spec(cs_iter`it') sample(cs_candidate_iter`it') mobility(tour) terms(mob_bilat_tour) gen(__et)
    local st = e(num_singletons)
    local pt = e(num_separated)
    quietly count if __cs
    local before = r(N)
    quietly count if __cs & (!__ev | !__et)
    local rm = r(N)
    local ++step
    post `FL' ("cs_exact") ("both") ("trade_first") (`step') ("PPML iteration `it': rows dropped by the visitor or the tourist fit") ///
        (`before' - `rm') (`rm') ("visitor fit: singletons `sv', separated `pv'; tourist fit: singletons `st', separated `pt'")
    if `rm' == 0 continue, break
    replace __cs = __cs & __ev & __et
}
assert __cs == s_cs_exact
drop __cs __ev __et
foreach c in c_trade has_both_vis has_both_tour {
    local others = subinstr("c_trade has_both_vis has_both_tour", "`c'", "", 1)
    local oc "1"
    foreach o of local others {
        local oc "`oc' & `o'"
    }
    quietly count if !`c'
    local fa = r(N)
    quietly count if !`c' & `oc'
    local fo = r(N)
    post `OC' ("cs_exact") ("both") ("`c'") (`fa') (`fo') (`n0')
}

*==============================================================================
* A1.1 (c) dynamic samples (Table 3; 05_table3_dynamic.do:14,20)
*==============================================================================
foreach m in vis tour {
    gen byte c_lag = !missing(lag_bilat_`m')
    gen byte c_lead = !missing(lead_bilat_`m')
    quietly count
    local n0 = r(N)
    post `FL' ("dyn") ("`m'") ("trade_first") (0) ("master panel") (`n0') (.) ("")
    quietly count if c_trade
    local n1 = r(N)
    post `FL' ("dyn") ("`m'") ("trade_first") (1) ("trade observed") (`n1') (`n0' - `n1') ("")
    quietly count if c_trade & has_both_`m'
    local n2 = r(N)
    post `FL' ("dyn") ("`m'") ("trade_first") (2) ("+ current bilateral mobility (has_both)") (`n2') (`n1' - `n2') ("")
    quietly count if c_trade & has_both_`m' & c_lag
    local n3 = r(N)
    quietly count if c_trade & has_both_`m' & !c_lag & year == 2007
    local y07 = r(N)
    post `FL' ("dyn") ("`m'") ("trade_first") (3) ("+ lagged bilateral mobility observed (t-1 both directions)") (`n3') (`n2' - `n3') ("of which year 2007 (no t-1 in window): `y07'")
    quietly count if c_trade & has_both_`m' & c_lag & c_lead
    local n4 = r(N)
    quietly count if c_trade & has_both_`m' & c_lag & !c_lead & year == 2021
    local y21 = r(N)
    post `FL' ("dyn") ("`m'") ("trade_first") (4) ("+ lead bilateral mobility observed (t+1 both directions)") (`n4') (`n3' - `n4') ("of which year 2021 (no t+1 in window): `y21'")
    capture noisily ppmlhdfe v_ttl_k lag_bilat_`m' mob_bilat_`m' lead_bilat_`m', absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.1) spec(dynamic_T3) sample(all_rows) mobility(`m') terms(lag_bilat_`m' mob_bilat_`m' lead_bilat_`m') gen(__es)
    assert e(N_full) == `n4'
    assert __es == s_dyn_`m'
    local nsing = e(num_singletons)
    local nsep = e(num_separated)
    local nn = e(N)
    drop __es
    post `FL' ("dyn") ("`m'") ("trade_first") (5) ("PPML: singleton observations dropped") (`n4' - `nsing') (`nsing') ("")
    post `FL' ("dyn") ("`m'") ("trade_first") (6) ("PPML: separated observations dropped") (`nn') (`nsep') ("final e(N)")
    foreach c in c_trade has_both_`m' c_lag c_lead {
        local others = subinstr("c_trade has_both_`m' c_lag c_lead", "`c'", "", 1)
        local oc "1"
        foreach o of local others {
            local oc "`oc' & `o'"
        }
        quietly count if !`c'
        local fa = r(N)
        quietly count if !`c' & `oc'
        local fo = r(N)
        local cl = cond("`c'" == "c_lag", "lag_bilat_`m' observed", cond("`c'" == "c_lead", "lead_bilat_`m' observed", "`c'"))
        post `OC' ("dyn") ("`m'") ("`cl'") (`fa') (`fo') (`n0')
    }
    drop c_lag c_lead
}

*==============================================================================
* A1.1 (d) cultural-distance interaction samples (07_table5_moderators.do:11-43, as 01_prep F)
*==============================================================================
gen byte c_cd = !missing(cul_dist)
foreach m in vis tour {
    quietly summarize cul_dist if !missing(v_ttl_k, mob_bilat_`m', cul_dist)
    gen double __cdc = cul_dist - r(mean)
    gen double __x = mob_bilat_`m' * __cdc
    quietly count
    local n0 = r(N)
    post `FL' ("cd") ("`m'") ("trade_first") (0) ("master panel") (`n0') (.) ("")
    quietly count if c_trade
    local n1 = r(N)
    post `FL' ("cd") ("`m'") ("trade_first") (1) ("trade observed") (`n1') (`n0' - `n1') ("")
    quietly count if c_trade & has_both_`m'
    local n2 = r(N)
    post `FL' ("cd") ("`m'") ("trade_first") (2) ("+ bilateral mobility (has_both)") (`n2') (`n1' - `n2') ("")
    quietly count if c_trade & has_both_`m' & c_cd
    local n3 = r(N)
    post `FL' ("cd") ("`m'") ("trade_first") (3) ("+ Hofstede cultural distance observed (cul_dist, cd6_ge4)") (`n3') (`n2' - `n3') ("")
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' __x if !missing(__cdc), absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.1) spec(cd_T5) sample(cul_dist_observed) mobility(`m') terms(mob_bilat_`m' __x) gen(__es) note("__x = mobility x centred cul_dist")
    assert e(N_full) == `n3'
    assert __es == s_cd_`m'
    local nsing = e(num_singletons)
    local nsep = e(num_separated)
    local nn = e(N)
    drop __es __cdc __x
    post `FL' ("cd") ("`m'") ("trade_first") (4) ("PPML: singleton observations dropped") (`n3' - `nsing') (`nsing') ("")
    post `FL' ("cd") ("`m'") ("trade_first") (5) ("PPML: separated observations dropped") (`nn') (`nsep') ("final e(N)")
    foreach c in c_trade has_both_`m' c_cd {
        local others = subinstr("c_trade has_both_`m' c_cd", "`c'", "", 1)
        local oc "1"
        foreach o of local others {
            local oc "`oc' & `o'"
        }
        quietly count if !`c'
        local fa = r(N)
        quietly count if !`c' & `oc'
        local fo = r(N)
        post `OC' ("cd") ("`m'") ("`c'") (`fa') (`fo') (`n0')
    }
}
postclose `FL'
postclose `OC'
foreach f in flow condition_counts {
    preserve
        use "${OUT}/tables/A1_A1.1_`f'.dta", clear
        gen str10 vintage = "${VINTAGE}"
        order vintage
        export delimited using "${OUT}/tables/A1_A1.1_`f'.csv", replace
    restore
    erase "${OUT}/tables/A1_A1.1_`f'.dta"
}
display as result "A1.1_DONE"

*==============================================================================
* A1.2 coverage (samples: baseline, exact common support, dynamic) vs trade-reporting panel
*==============================================================================
keep if c_trade
nflow step "A1.2: keep trade-reporting panel rows (v_ttl_k observed) as the reference universe"
gen byte s_panel = 1
local SAMPLES s_panel s_base_vis s_base_tour s_cs_exact s_dyn_vis s_dyn_tour
quietly summarize v_ttl_k, meanonly
scalar TOTV = r(sum)

* --- summary
tempname SM
postfile `SM' str12 sample double(obs exporters importers economies directed_pairs unordered_pairs years ///
    zero_share value_k share_of_panel_value) using "${OUT}/tables/A1_A1.2_summary.dta", replace
foreach s of local SAMPLES {
    preserve
        keep if `s' == 1
        quietly count
        local o = r(N)
        egen byte __t1 = tag(iso3_o)
        quietly count if __t1
        local ne = r(N)
        egen byte __t2 = tag(iso3_d)
        quietly count if __t2
        local ni = r(N)
        egen byte __t3 = tag(pair_id)
        quietly count if __t3
        local np = r(N)
        egen byte __t4 = tag(unordered_pair_id)
        quietly count if __t4
        local nu = r(N)
        egen byte __t5 = tag(year)
        quietly count if __t5
        local ny = r(N)
        quietly count if v_ttl_k == 0
        local zs = r(N) / `o'
        quietly summarize v_ttl_k, meanonly
        local vv = r(sum)
        keep iso3_o iso3_d
        gen long __k = _n
        rename (iso3_o iso3_d) (iso1 iso2)
        reshape long iso, i(__k) j(__side)
        egen byte __t6 = tag(iso)
        quietly count if __t6
        local nec = r(N)
        post `SM' ("`s'") (`o') (`ne') (`ni') (`nec') (`np') (`nu') (`ny') (`zs') (`vv') (`vv' / scalar(TOTV))
    restore
}
postclose `SM'

* --- by year
tempname BY
postfile `BY' str12 sample int year double(obs zero_share value_k panel_value_k share_of_panel_value) ///
    using "${OUT}/tables/A1_A1.2_by_year.dta", replace
forvalues y = 2007/2021 {
    quietly summarize v_ttl_k if year == `y', meanonly
    local pv = r(sum)
    foreach s of local SAMPLES {
        quietly count if `s' == 1 & year == `y'
        local o = r(N)
        quietly count if `s' == 1 & year == `y' & v_ttl_k == 0
        local z = cond(`o' > 0, r(N) / `o', .)
        quietly summarize v_ttl_k if `s' == 1 & year == `y', meanonly
        local vv = cond(`o' > 0, r(sum), 0)
        post `BY' ("`s'") (`y') (`o') (`z') (`vv') (`pv') (`vv' / `pv')
    }
}
postclose `BY'

* --- composition by World Bank region / income group (exporter and importer side)
tempfile comp
local first 1
foreach s of local SAMPLES {
    foreach dim in wb_region_o wb_region_d wb_income_cur_o wb_income_cur_d wb_inc_hist_o wb_inc_hist_d {
        preserve
            keep if `s' == 1
            gen str60 category = `dim'
            replace category = "Not classified by the World Bank" if strtrim(category) == ""
            gen double one = 1
            collapse (sum) obs = one value_k = v_ttl_k, by(category)
            quietly summarize obs, meanonly
            gen double share_obs = obs / r(sum)
            quietly summarize value_k, meanonly
            gen double share_value = value_k / r(sum)
            gen str12 sample = "`s'"
            gen str20 dimension = "`dim'"
            if `first' == 0 append using `comp'
            save `comp', replace
            local first 0
        restore
    }
}
preserve
    use `comp', clear
    gen str10 vintage = "${VINTAGE}"
    order vintage sample dimension category obs share_obs value_k share_value
    sort sample dimension category
    format share_obs share_value %12.6f
    format value_k %18.3f
    export delimited using "${OUT}/tables/A1_A1.2_composition.csv", replace
restore

* --- economy lists (iso3, UN designation, role) and years per sample
preserve
    import delimited using "${OUTROOT}/A1_un_names.csv", clear varnames(1) stringcols(_all)
    rename iso3 iso
    isid iso
    tempfile names
    save `names'
restore
tempfile econ
local first 1
foreach s in s_base_vis s_base_tour s_cs_exact s_dyn_vis s_dyn_tour {
    preserve
        keep if `s' == 1
        keep iso3_o iso3_d year
        gen long __k = _n
        rename (iso3_o iso3_d) (iso1 iso2)
        reshape long iso, i(__k) j(side)
        gen byte as_exporter = side == 1
        gen byte as_importer = side == 2
        collapse (sum) obs_as_exporter = as_exporter obs_as_importer = as_importer (min) first_year = year (max) last_year = year, by(iso)
        gen str24 role = cond(obs_as_exporter > 0 & obs_as_importer > 0, "exporter and importer", ///
            cond(obs_as_exporter > 0, "exporter only", "importer only"))
        gen str12 sample = "`s'"
        merge 1:1 iso using `names', keep(master match) gen(_mname)
        replace name_un = "(no UN Comtrade reference name)" if _mname == 1
        drop _mname
        if `first' == 0 append using `econ'
        save `econ', replace
        local first 0
    restore
}
preserve
    use `econ', clear
    rename iso iso3
    gen str10 vintage = "${VINTAGE}"
    order vintage sample iso3 name_un role obs_as_exporter obs_as_importer first_year last_year name_source
    sort sample iso3
    export delimited using "${OUT}/tables/A1_A1.2_economy_lists.csv", replace
restore

foreach f in summary by_year {
    preserve
        use "${OUT}/tables/A1_A1.2_`f'.dta", clear
        gen str10 vintage = "${VINTAGE}"
        order vintage
        export delimited using "${OUT}/tables/A1_A1.2_`f'.csv", replace
    restore
    erase "${OUT}/tables/A1_A1.2_`f'.dta"
}
display as result "A1.2_DONE"

A1_close
nflow report
display as result "A1_01_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
exit, clear
