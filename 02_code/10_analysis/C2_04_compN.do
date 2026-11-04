/*******************************************************************************
 C2_04_compN.do -- rerun C2, revision round 1 item 3.2: why the composition model (A2.1e composition_sh)
 has 2 visitor / 4 tourist observations fewer than the bilateral baseline. Final data only.
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do C2_04_compN.do corrected2x
 Re-traces A2_1.do lines 74 and 352-360 step by step without changing them: the share s = rev/(rev+same) is
 undefined where both directions have zero trips (A2_1.do:74); the identical-observation set is the fixed
 point of the composition model and the bilateral model (a2_fix, A2_00_programs.do). Each fit records N,
 N_full, e(num_singletons), e(num_separated). Positive control: the final N equals the A2.csv rows
 A2.1e composition_sh (20,596 / 26,335).
 Help consulted: ppmlhdfe.sthlp 2.3.4 (e(N), e(N_full), e(num_singletons), e(num_separated), e(sample));
 [P] postfile; nflow.sthlp 1.0.1.
 Output: ${OUT}/tables/A2_A2.1e_composition_N.csv; log; nflow in ${OUT}/A2_nflow.csv.
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
version 18.0
do "00_config.do" `vintage'
version 18.0
do "A2_00_programs.do"
assert "${VINTAGE}" == "corrected2x"
capture log close _all
log using "${LOGS}/C2_04_compN_${VINTAGE}.log", text replace
use "${OUT}/A2_work.dta", clear
nflow start using "${OUT}/A2_nflow.csv", append
local FE "exporter_year importer_year pair_id"
tempname T
postfile `T' str5 mobility str60 step double(rows N N_full singletons separated) str160 note using "${OUT}/tables/A2_A2.1e_composition_N.dta", replace
foreach m in vis tour {
    local smp "s_base_`m'"
    quietly count if `smp'
    post `T' ("`m'") ("baseline estimation sample s_base") (r(N)) (.) (.) (.) (.) ("bilateral model N (Table 3 bilateral column)")
    gen double sh_`m' = rev_`m'_raw / (rev_`m'_raw + same_`m'_raw) if `smp' & (rev_`m'_raw + same_`m'_raw) > 0
    quietly count if `smp' & missing(sh_`m')
    post `T' ("`m'") ("pair-years with zero trips in both directions (share undefined)") (r(N)) (.) (.) (.) (.) ("A2_1.do:74")
    gen byte cand_`m' = `smp' & !missing(sh_`m')
    local it 0
    local done 0
    while !`done' {
        local ++it
        quietly count if cand_`m'
        local n0 = r(N)
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' sh_`m' if cand_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "C2_04 composition `m' iteration `it'"
        post `T' ("`m'") ("iteration `it': composition model (mob_bilat + share)") (`n0') (e(N)) (e(N_full)) (e(num_singletons)) (e(num_separated)) ("fit on the current candidate rows")
        quietly replace cand_`m' = cand_`m' & e(sample)
        quietly count if cand_`m'
        local n1 = r(N)
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if cand_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "C2_04 bilateral on composition rows `m' iteration `it'"
        post `T' ("`m'") ("iteration `it': bilateral model on the same rows") (`n1') (e(N)) (e(N_full)) (e(num_singletons)) (e(num_separated)) ("")
        quietly replace cand_`m' = cand_`m' & e(sample)
        quietly count if cand_`m'
        if r(N) == `n0' local done 1
    }
    quietly count if cand_`m'
    local nf = r(N)
    post `T' ("`m'") ("identical observations (fixed point)") (`nf') (.) (.) (.) (.) ("= N of A2.1e composition_sh")
    local exp = cond("`m'" == "vis", 20596, 26335)
    assert `nf' == `exp'
    display as result "C2_04 `m': final N `nf' (expected `exp') after `it' iteration(s)"
}
postclose `T'
use "${OUT}/tables/A2_A2.1e_composition_N.dta", clear
gen str11 vintage = "${VINTAGE}"
order vintage
export delimited using "${OUT}/tables/A2_A2.1e_composition_N.csv", replace
list, noobs clean
erase "${OUT}/tables/A2_A2.1e_composition_N.dta"
log close
