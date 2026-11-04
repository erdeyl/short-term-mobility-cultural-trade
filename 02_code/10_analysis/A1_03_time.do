/*******************************************************************************
 A1_03_time.do  --  A1.6 time windows and directed-pair trends, A1.7 static baseline on
                    the dynamic sample and lead-test power, A1.8 Table 7 Panel F (analysis block A1)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do A1_03_time.do <vintage>
 Input : ${OUT}/prepared.dta (read only); ${OUT}/positive_controls.csv (PREP) for controls.
 Output: ${OUT}/tables/A1_A1.6_*.csv, A1_A1.7_*.csv, A1_A1.8_*.csv; results part A1_03.
 Help: ppmlhdfe.sthlp, Syntax for absorbed variables: "i.var1##c.var2  absorb fixed effects
 and individual slopes (e.g. i.country##c.time includes country FEs and different time trend
 per country)"; "advice: never run i.id i.id#c.z, as it is slower and less accurate than
 running i.id##c.z". Directed-pair trends are absorbed as pair_id##c.time_c with
 time_c = year - 2007, exactly as File S1 run_tests.do:216 and construct_metadata.do:38.
 Original models: 05_table3_dynamic.do:14,20; 08_table6_robustness.do:33-36;
 File S1 run_tests.do:209-240 (T7). Power formula (Roth 2022 logic):
 power = Phi(d/se - z) + Phi(-d/se - z), z = invnormal(1 - alpha/2).
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
log using "${LOGS}/A1_03_time_${VINTAGE}.log", text replace
display as result "A1_03_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)

* --- positive-control values (PREP positive_controls.csv, column reproduced = full precision)
preserve
    import delimited using "${OUT}/positive_controls.csv", clear varnames(1) stringcols(_all)
    foreach pair in "T6c5b|T6.c5.Bilateral visitors.b" "T6c5N|T6.c5.N.N" "T6c6b|T6.c6.Bilateral tourists.b" "T6c6N|T6.c6.N.N" ///
        "T3c1b|T3.c1.Bilateral visitors.b" "T3c1lead|T3.c1.Future bilateral visitors.b" "T3c1N|T3.c1.N.N" ///
        "T3c2b|T3.c2.Bilateral tourists.b" "T3c2lead|T3.c2.Future bilateral tourists.b" "T3c2N|T3.c2.N.N" {
        gettoken key it : pair, parse("|")
        local it = substr("`it'", 2, .)
        quietly levelsof reproduced if item == "`it'", local(v) clean
        assert "`v'" != ""
        global PC_`key' `v'
        display "PC `key' (`it') = `v'"
    }
restore

use year iso3_o iso3_d v_ttl_k has_both_vis has_both_tour mob_bilat_vis mob_bilat_tour ///
    mob_rev_vis mob_same_vis mob_rev_tour mob_same_tour lag_bilat_vis lead_bilat_vis lag_bilat_tour lead_bilat_tour ///
    exporter_year importer_year pair_id unordered_pair_id s_base_vis s_base_tour s_dyn_vis s_dyn_tour ///
    using "${PREPARED}", clear
nflow start using "${OUT}/A1_nflow.csv", append expected(823446)
A1_open A1_03
gen double time_c = year - 2007
local FET "exporter_year importer_year pair_id##c.time_c"

* --- diagnostics of rows dropped when trends are added: pair classification on the
*     no-trend sample (pairs with one positive observation at the first or last sample year,
*     with zeros elsewhere, are separated by a pair-specific linear trend in the log mean)
tempname DD
postfile `DD' str6 item str40 model str5 mobility double(n_notrend n_trend rows_dropped pairs_dropped ///
    dp_2obs dp_endpt_1pos dp_other nt_pairs_endpt_1pos ///
    nt_pairs_2obs_1zero sing_trend sep_trend) using "${OUT}/tables/A1_A1.6_8_trend_drop_diag.dta", replace
capture program drop A1_trenddiag
program define A1_trenddiag
    args handle item model mob s0 s1 nsing nsep
    tempvar n np tmin tmax tpos one drop dp tg ep
    quietly {
        bysort pair_id: egen `n' = total(`s0')
        bysort pair_id: egen `np' = total(`s0' & v_ttl_k > 0)
        bysort pair_id: egen `tmin' = min(cond(`s0', year, .))
        bysort pair_id: egen `tmax' = max(cond(`s0', year, .))
        bysort pair_id: egen `tpos' = max(cond(`s0' & v_ttl_k > 0, year, .))
        gen byte `ep' = `np' == 1 & (`tpos' == `tmin' | `tpos' == `tmax')
        gen byte `drop' = `s0' & !`s1'
        bysort pair_id: egen byte `dp' = max(`drop')
        egen byte `tg' = tag(pair_id) if `s0'
        count if `s0'
        local a = r(N)
        count if `s1'
        local b = r(N)
        count if `drop'
        local c = r(N)
        count if `tg' == 1 & `dp' == 1
        local d = r(N)
        count if `tg' == 1 & `dp' == 1 & `n' == 2
        local e = r(N)
        count if `tg' == 1 & `dp' == 1 & `ep' & `n' != 2
        local f = r(N)
        count if `tg' == 1 & `dp' == 1 & !`ep' & `n' != 2
        local g = r(N)
        count if `tg' == 1 & `ep'
        local h = r(N)
        count if `tg' == 1 & `n' == 2 & `np' == 1
        local i = r(N)
    }
    post `handle' ("`item'") ("`model'") ("`mob'") (`a') (`b') (`c') (`d') (`e') (`f') (`g') (`h') (`i') (`nsing') (`nsep')
    display as result "A1_TRENDDIAG `item' `model' `mob': notrend=`a' trend=`b' rows_dropped=`c' pairs_dropped=`d' (2obs `e', endpoint-single-positive `f', other `g'); notrend pairs endpoint-single-positive `h'; 2obs-one-zero `i'"
end

* --- separation check for trend fits: ppmlhdfe's default separation(fe simplex ir) may leave
*     separated rows in a model with absorbed slopes; such rows show as zero-trade rows whose fitted
*     eta keeps falling (mu -> 0). Untrended fits here converge with min(eta) about -22 to -26, so
*     eta < -30 (mu < 1e-13 thousand USD) marks numerically separated rows. Two refits:
*     (a) excluding those rows; (b) adding ppmlhdfe's "mu" separation method (help ppmlhdfe:
*     separation(string) "Valid options are fe, ir, simplex, and mu (or any combination of those)").
tempname SPX
postfile `SPX' str6 item str40 model str5 mobility double(N_default zero_rows eta_lt20 eta_lt30 eta_lt50 min_eta) ///
    using "${OUT}/tables/A1_A1.6_8_trend_separation.dta", replace
capture program drop A1_trendsep
program define A1_trendsep
    args handle item spec m cond X
    tempvar dsum eta nsep
    capture noisily ppmlhdfe v_ttl_k `X' if `cond', absorb(exporter_year importer_year pair_id##c.time_c) vce(cluster pair_id) d(`dsum')
    if _rc != 0 | e(converged) != 1 {
        display as error "A1_TRENDSEP refit with d() failed `item' `spec' `m'"
        exit
    }
    local N0 = e(N)
    quietly predict double `eta' if e(sample), eta
    quietly count if e(sample) & v_ttl_k == 0
    local z0 = r(N)
    foreach t in 20 30 50 {
        quietly count if e(sample) & v_ttl_k == 0 & `eta' < -`t'
        local c`t' = r(N)
    }
    quietly summarize `eta' if e(sample), meanonly
    local mn = r(min)
    post `handle' ("`item'") ("`spec'") ("`m'") (`N0') (`z0') (`c20') (`c30') (`c50') (`mn')
    gen byte `nsep' = e(sample) & v_ttl_k == 0 & `eta' < -30
    capture noisily ppmlhdfe v_ttl_k `X' if `cond' & !`nsep', absorb(exporter_year importer_year pair_id##c.time_c) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(`item') spec(`spec'_exnumsep) sample(`cond' & eta>=-30) mobility(`m') terms(`X') ///
        note("pair trends; excluding `c30' zero-trade rows with fitted eta < -30 in the default fit")
    capture noisily ppmlhdfe v_ttl_k `X' if `cond', absorb(exporter_year importer_year pair_id##c.time_c) vce(cluster pair_id) separation(fe simplex ir mu)
    A1_after, rc(`=_rc') item(`item') spec(`spec'_sepmu) sample(`cond') mobility(`m') terms(`X') ///
        note("pair trends; separation(fe simplex ir mu)")
    display as result "A1_TRENDSEP `item' `spec' `m': N_default=`N0' zero_rows=`z0' eta<-20:`c20' eta<-30:`c30' eta<-50:`c50' min_eta=`mn'"
end

*==============================================================================
* A1.6 time windows
*==============================================================================
tempname TW
postfile `TW' str5 mobility str24 window double(base_rows base_rows_excluded share_excluded) using "${OUT}/tables/A1_A1.6_window_shares.dta", replace
local w_2007_2019  "year <= 2019"
local w_ex2009     "year != 2009"
local w_ex2020_21  "!inrange(year, 2020, 2021)"
local w_ex0809_2021 "!inlist(year, 2008, 2009, 2020, 2021)"
local w_ex2008_2020 "!inlist(year, 2008, 2020)"
foreach m in vis tour {
    quietly count if s_base_`m'
    local nb = r(N)
    foreach w in 2007_2019 ex2009 ex2020_21 ex0809_2021 ex2008_2020 {
        quietly count if s_base_`m' & !(`w_`w'')
        post `TW' ("`m'") ("`w'") (`nb') (r(N)) (r(N) / `nb')
        capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & `w_`w'', absorb(${FE}) vce(cluster pair_id)
        A1_after, rc(`=_rc') item(A1.6) spec(win_`w') sample(has_both_`m' & `w_`w'') mobility(`m') terms(mob_bilat_`m')
        if "`w'" == "ex2008_2020" {
            * positive control: submitted/corrected Table 6 cols 5-6 (08_table6_robustness.do:33-36)
            local c = cond("`m'" == "vis", 5, 6)
            assert abs(_b[mob_bilat_`m'] - ${PC_T6c`c'b}) < 1e-6
            assert e(N) == ${PC_T6c`c'N}
            display as result "A1.6_PC_TABLE6_COL`c' PASS b=" _b[mob_bilat_`m'] " N=" e(N)
        }
    }
}
postclose `TW'

* --- directed-pair linear trends: bilateral and joint directional baselines
foreach m in vis tour {
    foreach mod in bilat dir {
        local X = cond("`mod'" == "bilat", "mob_bilat_`m'", "mob_rev_`m' mob_same_`m'")
        capture noisily ppmlhdfe v_ttl_k `X' if has_both_`m', absorb(${FE}) vce(cluster pair_id)
        A1_after, rc(`=_rc') item(A1.6) spec(`mod'_notrend) sample(has_both_`m') mobility(`m') terms(`X') gen(__s0)
        capture noisily ppmlhdfe v_ttl_k `X' if has_both_`m', absorb(`FET') vce(cluster pair_id)
        A1_after, rc(`=_rc') item(A1.6) spec(`mod'_pairtrend) sample(has_both_`m') mobility(`m') terms(`X') gen(__s1) ///
            note("absorb(exporter_year importer_year pair_id##c.time_c)")
        display as result "A1.6_TREND_ABSVARS `m' `mod': `e(extended_absvars)' N_hdfe_extended=" e(N_hdfe_extended)
        A1_trenddiag `DD' A1.6 `mod'_pairtrend `m' __s0 __s1 `=e(num_singletons)' `=e(num_separated)'
        if "`mod'" == "dir" {
            quietly test mob_rev_`m' = mob_same_`m'
            A1_posttest, item(A1.6) spec(dir_pairtrend_test) sample(has_both_`m') mobility(`m') term(rev_eq_same) ///
                stat(`r(chi2)') df(`r(df)') p(`r(p)') nobs(`=e(N)') nfull(`=e(N_full)') ncl(`=e(N_clust)') clv(pair_id) ///
                note("Wald chi2 H0 b_rev=b_same within the pair-trend model")
        }
        A1_trendsep `SPX' A1.6 `mod'_pairtrend `m' has_both_`m' "`X'"
        drop __s0 __s1
    }
    * syntax-equivalence check against the alternative form pair_id pair_id#c.year (bilateral only)
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m', absorb(exporter_year importer_year pair_id pair_id#c.year) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.6) spec(bilat_pairtrend_altsyntax) sample(has_both_`m') mobility(`m') terms(mob_bilat_`m') ///
        note("absorb(exporter_year importer_year pair_id pair_id#c.year): alternative form; equivalence check only")
}

*==============================================================================
* A1.7 static baseline on the dynamic (Table 3) sample, nested dynamic models
*==============================================================================
tempname LP
postfile `LP' str5 mobility str10 trend str20 reference double(b_lead se_lead b_ref d_share d alpha z power ci90_lo ci90_hi ///
    ci90_lo_share ci90_hi_share N) using "${OUT}/tables/A1_A1.7_lead_power.dta", replace
foreach m in vis tour {
    quietly count if s_dyn_`m'
    local nd = r(N)
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if s_dyn_`m', absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.7) spec(static_on_dyn) sample(s_dyn_`m') mobility(`m') terms(mob_bilat_`m')
    assert e(N) == `nd'
    local bstat = _b[mob_bilat_`m']
    capture noisily ppmlhdfe v_ttl_k lag_bilat_`m' mob_bilat_`m' lead_bilat_`m' if s_dyn_`m', absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.7) spec(T3_lag_cur_lead) sample(s_dyn_`m') mobility(`m') terms(lag_bilat_`m' mob_bilat_`m' lead_bilat_`m')
    assert e(N) == `nd'
    local c = cond("`m'" == "vis", 1, 2)
    assert abs(_b[mob_bilat_`m'] - ${PC_T3c`c'b}) < 1e-6
    assert abs(_b[lead_bilat_`m'] - ${PC_T3c`c'lead}) < 1e-6
    assert e(N) == ${PC_T3c`c'N}
    display as result "A1.7_PC_TABLE3_COL`c' PASS"
    local blead = _b[lead_bilat_`m']
    local slead = _se[lead_bilat_`m']
    local bcur = _b[mob_bilat_`m']
    capture noisily ppmlhdfe v_ttl_k lag_bilat_`m' mob_bilat_`m' if s_dyn_`m', absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.7) spec(lag_cur) sample(s_dyn_`m') mobility(`m') terms(lag_bilat_`m' mob_bilat_`m')
    assert e(N) == `nd'
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' lead_bilat_`m' if s_dyn_`m', absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.7) spec(cur_lead) sample(s_dyn_`m') mobility(`m') terms(mob_bilat_`m' lead_bilat_`m')
    assert e(N) == `nd'
    * lead-test power, no trends
    foreach ref in static_same_sample current_in_T3 {
        local br = cond("`ref'" == "static_same_sample", `bstat', `bcur')
        foreach sh in 0.5 1 {
            foreach a in 0.05 0.10 {
                local z = invnormal(1 - `a' / 2)
                local d = abs(`sh' * `br')
                local pw = normal(`d' / `slead' - `z') + normal(-`d' / `slead' - `z')
                local lo = `blead' - invnormal(0.95) * `slead'
                local hi = `blead' + invnormal(0.95) * `slead'
                post `LP' ("`m'") ("none") ("`ref'") (`blead') (`slead') (`br') (`sh') (`d') (`a') (`z') (`pw') (`lo') (`hi') (`lo' / `br') (`hi' / `br') (`nd')
            }
        }
    }
}

*==============================================================================
* A1.8 Table 7 Panel F: File S1 T7 reproduced (no if-condition; run_tests.do:213-217)
*      + A1.7 lead power with pair trends (same-sample static contemporaneous coefficient)
*==============================================================================
foreach m in vis tour {
    capture noisily ppmlhdfe v_ttl_k lag_bilat_`m' mob_bilat_`m' lead_bilat_`m', absorb(${FE}) vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.8) spec(T7_none) sample(all_rows) mobility(`m') terms(lag_bilat_`m' mob_bilat_`m' lead_bilat_`m') gen(__s0)
    display as result "A1.8_T7_NONE `m' N=" e(N) " N_full=" e(N_full) " singletons=" e(num_singletons) " separated=" e(num_separated) " absvars=`e(extended_absvars)'"
    capture noisily ppmlhdfe v_ttl_k lag_bilat_`m' mob_bilat_`m' lead_bilat_`m', absorb(`FET') vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.8) spec(T7_pair) sample(all_rows) mobility(`m') terms(lag_bilat_`m' mob_bilat_`m' lead_bilat_`m') gen(__s1) ///
        note("absorb(exporter_year importer_year pair_id##c.time_c), File S1 run_tests.do:216")
    display as result "A1.8_T7_PAIR `m' N=" e(N) " N_full=" e(N_full) " singletons=" e(num_singletons) " separated=" e(num_separated) ///
        " N_hdfe=" e(N_hdfe) " N_hdfe_extended=" e(N_hdfe_extended) " absvars=`e(extended_absvars)'"
    local blead = _b[lead_bilat_`m']
    local slead = _se[lead_bilat_`m']
    local bcur = _b[mob_bilat_`m']
    local nt = e(N)
    if "${VINTAGE}" == "submitted" {
        * positive control: File S1 estimates.csv rows T7 lead_pair_* / current_pair_* (8 significant digits)
        local pl = cond("`m'" == "vis", -0.01661386, 0.10155301)
        local pc = cond("`m'" == "vis", 0.33408231, 0.11122672)
        local pn = cond("`m'" == "vis", 13320, 19122)
        assert abs(`blead' - `pl') < 1e-7 & abs(`bcur' - `pc') < 1e-7 & `nt' == `pn'
        display as result "A1.8_PC_FILE_S1_T7_PAIR_`m' PASS"
    }
    A1_trenddiag `DD' A1.8 T7_pair `m' __s0 __s1 `=e(num_singletons)' `=e(num_separated)'
    A1_trendsep `SPX' A1.8 T7_pair `m' 1 "lag_bilat_`m' mob_bilat_`m' lead_bilat_`m'"
    * same-sample static contemporaneous coefficient with pair trends
    capture noisily ppmlhdfe v_ttl_k mob_bilat_`m' if __s1, absorb(`FET') vce(cluster pair_id)
    A1_after, rc(`=_rc') item(A1.7) spec(static_on_dyn_pairtrend) sample(T7_pair e(sample)) mobility(`m') terms(mob_bilat_`m')
    local bstat = _b[mob_bilat_`m']
    local nst = e(N)
    foreach ref in static_same_sample current_in_T3 {
        local br = cond("`ref'" == "static_same_sample", `bstat', `bcur')
        foreach sh in 0.5 1 {
            foreach a in 0.05 0.10 {
                local z = invnormal(1 - `a' / 2)
                local d = abs(`sh' * `br')
                local pw = normal(`d' / `slead' - `z') + normal(-`d' / `slead' - `z')
                local lo = `blead' - invnormal(0.95) * `slead'
                local hi = `blead' + invnormal(0.95) * `slead'
                post `LP' ("`m'") ("pair") ("`ref'") (`blead') (`slead') (`br') (`sh') (`d') (`a') (`z') (`pw') (`lo') (`hi') (`lo' / `br') (`hi' / `br') (`nt')
            }
        }
    }
    drop __s0 __s1
}
postclose `LP'
postclose `DD'
postclose `SPX'
foreach f in A1.6_window_shares A1.7_lead_power A1.6_8_trend_drop_diag A1.6_8_trend_separation {
    preserve
        use "${OUT}/tables/A1_`f'.dta", clear
        gen str10 vintage = "${VINTAGE}"
        order vintage
        export delimited using "${OUT}/tables/A1_`f'.csv", replace
    restore
    erase "${OUT}/tables/A1_`f'.dta"
}

A1_close
nflow report
display as result "A1_03_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
exit, clear
