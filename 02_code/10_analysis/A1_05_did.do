/*******************************************************************************
 A1_05_did.do  --  A1.10 DiD design characterisation (analysis block A1)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do A1_05_did.do <vintage>
 Input : ${OUT}/prepared.dta (read only). Output: tables A1_A1.10_*.csv; results part A1_05.
 Estimator choice: authors' working notes.
 Help files read before coding (installed): whichdidshouldiuse.sthlp 1.0.0 ("whichdidshouldiuse
 Y G T D [if] [in] [, detail strict]"; classifies, fits nothing; r(design), r(estimator),
 r(had_case), r(sfsd_case), condition flags, sample-adjustment counts; "Gaps are fine, because
 the command normalizes time internally"); did_multiplegt_dyn.sthlp (SSC 20260629: "compare the
 outcome evolutions of switchers ... and of not-yet-switchers, namely units whose treatment has
 not changed yet"; continuous(#) "when groups' period-one treatment is continuous"; "assumes that
 the time variable is evenly spaced"; _no_updates stops self-updates; graph_off); did_had.sthlp.
 Design input: one row per directed pair-year of each baseline sample;
 G = pair_id, T = year, D = mob_bilat_<m>, Y = v_ttl_k.
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
log using "${LOGS}/A1_05_did_${VINTAGE}.log", text replace
display as result "A1_05_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
which whichdidshouldiuse
which did_multiplegt_dyn
* Audit R1-02: whichdidshouldiuse.ado:312-313 and :355-356 create the baseline with a plain
* `gen` (default storage type) from the double treatment and compare it with exact inequality
* (:375), so under the default float type every group "switches" at entry. All new variables
* created without an explicit type are therefore stored as double ([D] generate; help set_type).
set type double
display as result "A1.10_STORAGE c(type)=`c(type)'"
* did_multiplegt_dyn saves and reloads a tempfile without quotes (installed ado lines 3641, 4022);
* the batch launcher sets STATATMP to a directory without spaces. Recorded here:
display as result "A1.10_TMPDIR c(tmpdir)=`c(tmpdir)'"
assert strpos("`c(tmpdir)'", " ") == 0

use year iso3_o iso3_d v_ttl_k pair_id mob_bilat_vis mob_bilat_tour s_base_vis s_base_tour exporter_year importer_year unordered_pair_id ///
    using "${PREPARED}", clear
nflow start using "${OUT}/A1_nflow.csv", append expected(823446)
A1_open A1_05

tempname CL ST NY
postfile `CL' str5 mobility str16 mode str32 rname str80 rvalue using "${OUT}/tables/A1_A1.10_classifier.dta", replace
postfile `ST' str5 mobility int year double(transitions exact_stay abs_lt_001 abs_lt_005 sh_exact sh_lt_001 sh_lt_005) ///
    using "${OUT}/tables/A1_A1.10_stayers_by_year.dta", replace
postfile `NY' str5 mobility int year double(groups_observed not_yet_switchers never_switchers_observed) ///
    using "${OUT}/tables/A1_A1.10_not_yet_switchers.dta", replace
foreach m in vis tour {
    preserve
        keep if s_base_`m' == 1
        nflow step "A1.10 keep baseline e(sample) rows (`m')"
        isid pair_id year
        * --- classifier, default and strict
        foreach mode in default strict {
            local opt = cond("`mode'" == "strict", "strict", "")
            display as result "A1.10_WHICHDID `m' `mode' -----------------------------------------"
            whichdidshouldiuse v_ttl_k pair_id year mob_bilat_`m', detail `opt'
            if "`mode'" == "strict" {
                local strict_ng = r(n_groups)
                local strict_case "`r(sfsd_case)'"
                local strict_design "`r(design)'"
            }
            local scal : r(scalars)
            local macs : r(macros)
            foreach r of local macs {
                local v = substr(`"`r(`r')'"', 1, 80)
                post `CL' ("`m'") ("`mode'") ("`r'") (`"`v'"')
            }
            foreach r of local scal {
                local v : display %18.0g r(`r')
                post `CL' ("`m'") ("`mode'") ("`r'") (strtrim("`v'"))
            }
        }
        * --- stayers and quasi-stayers: transitions t-1 -> t inside the sample
        xtset pair_id year, yearly
        gen double dd = mob_bilat_`m' - L.mob_bilat_`m'
        forvalues y = 2008/2021 {
            quietly count if year == `y' & !missing(dd)
            local n = r(N)
            quietly count if year == `y' & dd == 0
            local a = r(N)
            quietly count if year == `y' & abs(dd) < 0.01 & !missing(dd)
            local b = r(N)
            quietly count if year == `y' & abs(dd) < 0.05 & !missing(dd)
            local c = r(N)
            post `ST' ("`m'") (`y') (`n') (`a') (`b') (`c') (`a' / `n') (`b' / `n') (`c' / `n')
        }
        quietly count if !missing(dd)
        local n = r(N)
        quietly count if dd == 0
        local a = r(N)
        quietly count if abs(dd) < 0.01 & !missing(dd)
        local b = r(N)
        quietly count if abs(dd) < 0.05 & !missing(dd)
        local c = r(N)
        post `ST' ("`m'") (0) (`n') (`a') (`b') (`c') (`a' / `n') (`b' / `n') (`c' / `n')
        * --- first switch dates (D different from the pair's first observed D) and not-yet-switchers
        bysort pair_id (year): gen double d0 = mob_bilat_`m'[1]
        by pair_id: egen int Fg = min(cond(mob_bilat_`m' != d0, year, .))
        by pair_id: gen int y0 = year[1]
        forvalues y = 2008/2021 {
            quietly count if year == `y'
            local g = r(N)
            quietly count if year == `y' & y0 < `y' & (missing(Fg) | Fg > `y')
            local nys = r(N)
            quietly count if year == `y' & missing(Fg)
            local nev = r(N)
            post `NY' ("`m'") (`y') (`g') (`nys') (`nev')
        }
        egen byte __tg = tag(pair_id)
        quietly count if __tg & missing(Fg)
        display as result "A1.10_NEVER_SWITCHERS `m' pairs=" r(N)
        quietly count if __tg
        display as result "A1.10_PAIRS `m' =" r(N)
        * --- the estimator that the design classification assigns (rerun after audit check under double storage). The
        *     classifier sub-cases are read from the log/CSV of this run; both SFSD variants are run:
        *     plain = shared-baseline; continuous(1) = continuous-baseline, with the help's recommended
        *     bootstrap comparison (bootstrap(100,20261103); "we recommend using the bootstrap for
        *     inference ... At least, one should perform a robustness check"). Earlier wording below:
        *     Classifier sub-case (default mode, float storage) = "shared-baseline"
        *     -> did_multiplegt_dyn comparing first-time switchers with not-yet-switchers that share the
        *     same period-one treatment (help did_multiplegt_dyn).
        *     Secondary: continuous(1) (polynomial in the period-one treatment; for the
        *     continuous-baseline sub-case). One effect and one placebo, cluster by pair, levels.
        *     If the command stops after estimation (as observed: "didmgt_Var_all_XX not found" when
        *     the placebo cannot be estimated), it is rerun without placebo() so that e() is stored.
        * rerun C2 (author decision 2026-11-03, authors' working notes): for corrected2/corrected2x
        * every bootstrap call runs in its own fresh Stata process without placebo() (C2_A1_10_boot.do);
        * submitted/corrected keep the original list
        local dm_variants "plain cont1 cont1boot"
        if inlist("${VINTAGE}", "corrected2", "corrected2x") local dm_variants "plain cont1"
        foreach variant of local dm_variants {
            local vopt ""
            if "`variant'" == "cont1" local vopt "continuous(1)"
            if "`variant'" == "cont1boot" local vopt "continuous(1) bootstrap(100,20261103)"
            display as result "A1.10_DMDYN `m' `variant' -----------------------------------------"
            * rerun C2 (author decision 2026-11-04): variable abbreviation on only around the call
            set varabbrev on
            display as result "A1.10_VARABBREV on for did_multiplegt_dyn: package requires variable abbreviation, ado lines 2010-2014 (getmata scalars_XX* creates scalars_XX1, read as scalars_XX)"
            capture noisily did_multiplegt_dyn v_ttl_k pair_id year mob_bilat_`m', effects(1) placebo(1) `vopt' ///
                cluster(pair_id) graph_off _no_updates
            local rc = _rc
            set varabbrev off
            local plnote "effects(1) placebo(1)"
            display as result "A1.10_DMDYN_RC `m' `variant' placebo rc=`rc'"
            if `rc' != 0 {
                * rerun C2 (author decision 2026-11-04): variable abbreviation on only around the call
                set varabbrev on
                display as result "A1.10_VARABBREV on for did_multiplegt_dyn: package requires variable abbreviation, ado lines 2010-2014 (getmata scalars_XX* creates scalars_XX1, read as scalars_XX)"
                capture noisily did_multiplegt_dyn v_ttl_k pair_id year mob_bilat_`m', effects(1) `vopt' ///
                    cluster(pair_id) graph_off _no_updates
                local rc = _rc
                set varabbrev off
                local plnote "effects(1) only: the run with placebo(1) stopped with an error"
                display as result "A1.10_DMDYN_RC `m' `variant' noplacebo rc=`rc'"
            }
            if `rc' == 0 {
                foreach s in Effect_1 se_effect_1 N_effect_1 N_switchers_effect_1 Placebo_1 se_placebo_1 N_placebo_1 N_switchers_placebo_1 {
                    capture local v = e(`s')
                    if _rc local v = .
                    post `CL' ("`m'") ("dm2_`variant'") ("e(`s')") ("`v'")
                }
                foreach k in effect placebo {
                    local K = cond("`k'" == "effect", "Effect_1", "Placebo_1")
                    local bb = e(`K')
                    local ss = e(se_`k'_1)
                    local nn = e(N_`k'_1)
                    local ns = e(N_switchers_`k'_1)
                    if missing(`bb') & "`k'" == "placebo" {
                        post A1post ("A1.10.dmdyn2_`variant'.`m'.`K'") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("s_base_`m'") ("`m'") ("`K'") ///
                            (.) (.) (.) (.) (.) (`nn') (.) (.) (.) (.) ("pair_id") ("NOT ESTIMABLE: no switcher or no control for this placebo (command output); did_multiplegt_dyn `vopt' `plnote'; double storage")
                        continue
                    }
                    post A1post ("A1.10.dmdyn2_`variant'.`m'.`K'") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("s_base_`m'") ("`m'") ("`K'") ///
                        (`bb') (`ss') (2 * normal(-abs(`bb' / `ss'))) (`bb' - invnormal(.975) * `ss') (`bb' + invnormal(.975) * `ss') ///
                        (`nn') (.) (.) (.) (.) ("pair_id") ("did_multiplegt_dyn `vopt' `plnote'; level outcome (1000 USD); switchers=`ns'; N-switchers=`=`nn'-`ns''; double storage")
                }
            }
            else {
                post `CL' ("`m'") ("dm2_`variant'") ("rc") ("`rc'")
                post A1post ("A1.10.dmdyn2_`variant'.`m'.Effect_1") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("s_base_`m'") ("`m'") ("Effect_1") ///
                    (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) ("pair_id") ("FAILED rc=`rc': did_multiplegt_dyn `vopt' produced no stored estimate; double storage")
            }
        }
        * --- strict-mode classification: continuous-baseline SFSD -> did_multiplegt_dyn continuous(1)
        *     on the strict classifier's sample (groups with D observed at the first period, 2007, and
        *     no missing D before their first switch; whichdidshouldiuse help, "strict drops groups ...
        *     whose treatment is missing at baseline, or at any period before its first switch").
        *     Positive control: reconstructed group count = strict r(n_groups).
        display as result "A1.10_STRICT `m' design=`strict_design' case=`strict_case' n_groups=`strict_ng'"
        bysort pair_id: egen byte __o07 = max(year == 2007)
        gen double __d07x = mob_bilat_`m' if year == 2007
        bysort pair_id: egen double __d07 = max(__d07x)
        bysort pair_id: egen int __Fg = min(cond(!missing(__d07) & mob_bilat_`m' != __d07, year, .))
        bysort pair_id: egen int __nbefore = total(year < __Fg)
        gen byte __strict = __o07 == 1 & !missing(__Fg) & __nbefore == __Fg - 2007
        egen byte __tgs = tag(pair_id) if __strict
        quietly count if __tgs == 1
        local ngs = r(N)
        display as result "A1.10_STRICT_SAMPLE `m' reconstructed groups=`ngs' classifier n_groups=`strict_ng'"
        if "`strict_case'" == "continuous-baseline" & `ngs' != `strict_ng' {
            post A1post ("A1.10.dmdyn2_cont1strict.`m'.Effect_1") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_cont1strict") ("strict sample") ("`m'") ("Effect_1") ///
                (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) ("pair_id") ("NOT RUN: reconstructed strict sample has `ngs' groups, classifier `strict_ng'")
        }
        if "`strict_case'" == "continuous-baseline" & `ngs' == `strict_ng' {
                local dms_variants "cont1strict cont1strictboot"
                if inlist("${VINTAGE}", "corrected2", "corrected2x") local dms_variants "cont1strict"
                foreach variant of local dms_variants {
                    local vopt "continuous(1)"
                    if "`variant'" == "cont1strictboot" local vopt "continuous(1) bootstrap(100,20261103)"
                    display as result "A1.10_DMDYN `m' `variant' -----------------------------------------"
                    * rerun C2 (author decision 2026-11-04): variable abbreviation on only around the call
                    set varabbrev on
                    display as result "A1.10_VARABBREV on for did_multiplegt_dyn: package requires variable abbreviation, ado lines 2010-2014 (getmata scalars_XX* creates scalars_XX1, read as scalars_XX)"
                    capture noisily did_multiplegt_dyn v_ttl_k pair_id year mob_bilat_`m' if __strict, effects(1) placebo(1) `vopt' ///
                        cluster(pair_id) graph_off _no_updates
                    local rc = _rc
                    set varabbrev off
                    local plnote "effects(1) placebo(1); strict-classifier sample (`ngs' groups)"
                    display as result "A1.10_DMDYN_RC `m' `variant' placebo rc=`rc'"
                    if `rc' != 0 {
                        * rerun C2 (author decision 2026-11-04): variable abbreviation on only around the call
                        set varabbrev on
                        display as result "A1.10_VARABBREV on for did_multiplegt_dyn: package requires variable abbreviation, ado lines 2010-2014 (getmata scalars_XX* creates scalars_XX1, read as scalars_XX)"
                        capture noisily did_multiplegt_dyn v_ttl_k pair_id year mob_bilat_`m' if __strict, effects(1) `vopt' ///
                            cluster(pair_id) graph_off _no_updates
                        local rc = _rc
                        set varabbrev off
                        local plnote "effects(1) only (placebo run stopped with an error); strict-classifier sample (`ngs' groups)"
                        display as result "A1.10_DMDYN_RC `m' `variant' noplacebo rc=`rc'"
                    }
                    if `rc' == 0 {
                        foreach s in Effect_1 se_effect_1 N_effect_1 N_switchers_effect_1 Placebo_1 se_placebo_1 N_placebo_1 N_switchers_placebo_1 {
                            capture local v = e(`s')
                            if _rc local v = .
                            post `CL' ("`m'") ("dm2_`variant'") ("e(`s')") ("`v'")
                        }
                        foreach k in effect placebo {
                            local K = cond("`k'" == "effect", "Effect_1", "Placebo_1")
                            local bb = e(`K')
                            local ss = e(se_`k'_1)
                            local nn = e(N_`k'_1)
                            local ns = e(N_switchers_`k'_1)
                            if missing(`bb') {
                                post A1post ("A1.10.dmdyn2_`variant'.`m'.`K'") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("strict sample") ("`m'") ("`K'") ///
                                    (.) (.) (.) (.) (.) (`nn') (.) (.) (.) (.) ("pair_id") ("NOT ESTIMABLE: no switcher or no control for this placebo (command output); did_multiplegt_dyn `vopt' `plnote'; double storage")
                                continue
                            }
                            post A1post ("A1.10.dmdyn2_`variant'.`m'.`K'") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("strict sample") ("`m'") ("`K'") ///
                                (`bb') (`ss') (2 * normal(-abs(`bb' / `ss'))) (`bb' - invnormal(.975) * `ss') (`bb' + invnormal(.975) * `ss') ///
                                (`nn') (.) (.) (.) (.) ("pair_id") ("did_multiplegt_dyn `vopt' `plnote'; level outcome; switchers=`ns'; N-switchers=`=`nn'-`ns''; double storage")
                        }
                    }
                    else {
                        post `CL' ("`m'") ("dm2_`variant'") ("rc") ("`rc'")
                        post A1post ("A1.10.dmdyn2_`variant'.`m'.Effect_1") ("${VINTAGE}") ("A1") ("A1.10") ("dmdyn2_`variant'") ("strict sample") ("`m'") ("Effect_1") ///
                            (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) ("pair_id") ("FAILED rc=`rc': did_multiplegt_dyn `vopt' produced no stored estimate; `plnote'")
                    }
                }
        }
        drop __o07 __d07x __d07 __Fg __nbefore __strict __tgs
    restore
    nflow step "A1.10 restore full data (`m')"
}
postclose `CL'
postclose `ST'
postclose `NY'
foreach f in classifier stayers_by_year not_yet_switchers {
    preserve
        use "${OUT}/tables/A1_A1.10_`f'.dta", clear
        gen str10 vintage = "${VINTAGE}"
        order vintage
        export delimited using "${OUT}/tables/A1_A1.10_`f'.csv", replace
    restore
    erase "${OUT}/tables/A1_A1.10_`f'.dta"
}
A1_close
nflow report
display as result "A1_05_COMPLETE vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
exit, clear
