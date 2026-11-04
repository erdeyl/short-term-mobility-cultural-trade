/*******************************************************************************
 A2_7b.do -- item A2.7b (rerun C2; author request): the A2.7 benchmark with the
 cultural outcome replaced by (i) v_unesco_b (Narrow-B, 24 HS2007 codes, PREP 01_prep.do section C)
 and (ii) v_nomedia = v_ttl_k - v_8523_k (no recorded media; in corrected2x v_ttl_k is the 30-code
 basket, so v_nomedia has 27 codes). Everything else exactly as A2_7.do (code copied, outcome
 switched): baseline rows s_base_* with year <= 2020 and the benchmark observed; benchmarks
 tradeflow_comtrade_d (CEPII total imports) and v_noncult_k = tradeflow_comtrade_d - v_ttl_k where
 >= 0 (unchanged definition of A2.7); identical observations = fixed point of the outcome model and
 the benchmark model (a2_fix); stacked test outcome = benchmark (a2_stack, block-specific FE,
 cluster pair_id). Rows: item A2.7b, spec A2.7b_<outcome>_<benchmark>_identical_rows.
 Help: ppmlhdfe.sthlp, [R] test.
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
log using "${LOGS}/A2_7b_${VINTAGE}.log", text replace
display as result "A2_7b_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
use "${OUT}/A2_work.dta", clear
nflow start using "${OUT}/A2_nflow.csv", append
a2_open "${OUT}/results/A2_7b.dta"
a2_topen "${OUT}/tables/A2_A2.7b.dta"
local FE "exporter_year importer_year pair_id"

gen double v_noncult_k = tradeflow_comtrade_d - v_ttl_k if !missing(tradeflow_comtrade_d, v_ttl_k) & tradeflow_comtrade_d - v_ttl_k >= 0
label variable v_noncult_k "Non-cultural imports: CEPII tradeflow_comtrade_d - v_ttl_k where >= 0 (1000 USD)"
gen double v_nomedia = v_ttl_k - v_8523_k if !missing(v_ttl_k, v_8523_k)
label variable v_nomedia "Cultural trade without recorded media: v_ttl_k - v_8523_k (1000 USD)"
quietly count if v_nomedia < 0
assert r(N) == 0
foreach Y in v_unesco_b v_nomedia {
    local ytag = cond("`Y'" == "v_unesco_b", "unesco_b", "nomedia")
    local ylab = cond("`Y'" == "v_unesco_b", "Narrow-B basket", "no recorded media")


    foreach m in vis tour {
        local mlab = cond("`m'" == "vis", "visitors", "tourists")
        local smp "s_base_`m'"
        * reference: the outcome on baseline rows with year <= 2020 (no benchmark restriction)
        quietly ppmlhdfe `Y' mob_bilat_`m' if `smp' & year <= 2020, absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.7b `ytag' `mlab' baseline rows year<=2020"
        a2_post, item(A2.7b) spec(A2.7b_`ytag'_year_le_2020) sample(`smp' & year<=2020) mobility(`mlab') term(mob_bilat_`m') label(`ylab')
        foreach bm in tradeflow_comtrade_d v_noncult_k {
            local bl = cond("`bm'" == "tradeflow_comtrade_d", "total imports (CEPII Comtrade)", "non-cultural imports")
            capture drop bm_`bm'_`m'
            gen byte bm_`bm'_`m' = `smp' & year <= 2020 & !missing(`bm', `Y')
            quietly count if bm_`bm'_`m'
            local nc = r(N)
            a2_fix, touse(bm_`bm'_`m') models("`Y' mob_bilat_`m' ; `bm' mob_bilat_`m'")
            local it = ${A2_FIX_IT}
            quietly summarize `Y' if bm_`bm'_`m', meanonly
            local sc = r(sum)
            quietly summarize tradeflow_comtrade_d if bm_`bm'_`m', meanonly
            local st = r(sum)
            a2_tpost, item(A2.7b) table(`ytag'_share) sample(identical rows `bm') mobility(`mlab') stat(outcome_share_of_total_pct) value(`=100*`sc'/`st'') n(`r(N)') note("100 * sum(`Y') / sum(tradeflow_comtrade_d)")
            tempvar r
            gen double `r' = `Y' / tradeflow_comtrade_d if bm_`bm'_`m'
            quietly summarize `r', detail
            a2_tpost, item(A2.7b) table(`ytag'_share) sample(identical rows `bm') mobility(`mlab') stat(median_rowwise_outcome_share) value(`r(p50)') n(`r(N)')
            a2_tpost, item(A2.7b) table(`ytag'_share) sample(identical rows `bm') mobility(`mlab') stat(p99_rowwise_outcome_share) value(`r(p99)') n(`r(N)')
            drop `r'
            preserve
            a2_stack, touse(bm_`bm'_`m') ys(`Y' `bm') xs("mob_bilat_`m' ; mob_bilat_`m'") cluster(pair_id)
            local nu = ${A2_NUNIQ}
            a2_post, item(A2.7b) spec(A2.7b_`ytag'_`bm'_identical_rows) sample(`smp' & year<=2020 & `bm' observed) mobility(`mlab') term(s1_1) label(`ylab') nuniq(`nu') note("outcome `Y'; candidate rows `nc'; fixed-point iterations `it'")
            a2_post, item(A2.7b) spec(A2.7b_`ytag'_`bm'_identical_rows) sample(`smp' & year<=2020 & `bm' observed) mobility(`mlab') term(s2_1) label(`bl') nuniq(`nu')
            a2_post, item(A2.7b) spec(A2.7b_`ytag'_`bm'_identical_rows) sample(`smp' & year<=2020 & `bm' observed) mobility(`mlab') term(s1_1 - s2_1) label(`ylab' - benchmark) nuniq(`nu')
            quietly test s1_1 = s2_1
            a2_posttest, item(A2.7b) spec(A2.7b_`ytag'_`bm'_identical_rows) sample(`smp' & year<=2020 & `bm' observed) mobility(`mlab') label(test `ytag' = benchmark) chi2(`r(chi2)') df(`r(df)') p(`r(p)') nuniq(`nu')
            display as result "A2_7b `ytag' `m' `bm' N=`nu' outcome=" %9.6f _b[s1_1] " benchmark=" %9.6f _b[s2_1] " gap=${A2_STACK_GAP}"
            restore
            nflow step "restore: after A2.7b `ytag' `bm' `mlab' stacked test"
        }
    }
}
a2_close "${OUT}/results/A2_7b.dta" "${OUT}/results/A2_7b.csv"
a2_tclose "${OUT}/tables/A2_A2.7b.dta" "${OUT}/tables/A2_A2.7b.csv"
display as result "A2_7b_DONE vintage=${VINTAGE} " c(current_time)
log close
