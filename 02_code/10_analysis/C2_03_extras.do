/*******************************************************************************
 C2_03_extras.do -- rerun C2, author additions (writing plan producers)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do C2_03_extras.do <corrected2|corrected2x>
 (a) Table A2 upper-bound basket. UB = LB basket + ambiguous pre-HS2007 recorded-media pool
     (TAB_02.do:22, v_ub_k = v_ttl_k + v_8523_amb_k where v_ttl_k is observed). corrected2x: the UB
     basket is computed on the 30-code outcome, so UB_ex4907 = v_ttl_k + v_8523_amb_k; identity
     controlled on every row: UB_ex4907 = UB_31 - v_4907_k, UB_31 = v_ttl31_k + v_8523_amb_k.
 (b) HS 490700 value share on the final samples (for the A2.6 outputs): 100 * sum(v_4907_k) /
     sum(31-code value) and / sum(30-code value) on s_base_*, s_cs_exact, s_dyn_*, s_cd_*.
 Help consulted: [R] summarize (r(sum)), [P] postfile, [D] export delimited.
 Output: ${OUT}/C2_ub_identity.csv, ${OUT}/tables/A2_A2.6_hs490700_share.csv (A2 table schema).
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
version 18.0
do "00_config.do" `vintage'
version 18.0
assert inlist("${VINTAGE}", "corrected2", "corrected2x")
capture log close _all
log using "${LOGS}/C2_03_extras_${VINTAGE}.log", text replace
local v31 = cond("${VINTAGE}" == "corrected2x", "v_ttl31_k", "v_ttl_k")
use year iso3_o iso3_d v_ttl_k v_ttl_ex4907 v_4907_k v_8523_amb_k s_base_vis s_base_tour s_cs_exact ///
    s_dyn_vis s_dyn_tour s_cd_vis s_cd_tour `=cond("${VINTAGE}" == "corrected2x", "v_ttl31_k", "")' using "${PREPARED}", clear
nflow start using "${OUT}/C2_nflow.csv", append expected(823446)
* ---------------------------------------------------------------- (a) UB identity
gen double ub31 = `v31' + v_8523_amb_k if !missing(`v31')
gen double ub30 = v_ttl_ex4907 + v_8523_amb_k if !missing(v_ttl_ex4907)
gen double __d = abs(ub30 - (ub31 - v_4907_k))
quietly summarize __d
local mx = r(max)
local nr = r(N)
quietly count if __d > 1e-6 + 1e-9 * abs(ub31) & !missing(__d)
local nf = r(N)
quietly count if missing(ub30) != missing(ub31)
local nm = r(N)
if "${VINTAGE}" == "corrected2x" {
    * the UB basket of the TAB_02.do fit on corrected2x is v_ttl_k + v_8523_amb_k = ub30
    gen double __ubtab = v_ttl_k + v_8523_amb_k if !missing(v_ttl_k)
    quietly count if !((__ubtab == ub30) | (missing(__ubtab) & missing(ub30)))
    local nt = r(N)
}
else local nt = 0
display as result "C2_UB_IDENTITY rows=`nr' max_abs=" %12.3e `mx' " fails=`nf' missingness_diff=`nm' tab02_basket_diff=`nt'"
clear
set obs 1
gen str11 vintage = "${VINTAGE}"
gen str80 control = "UB_ex4907 = UB_31 - v_4907_k on every row (UB = LB + v_8523_amb_k)"
gen double rows = `nr'
gen double max_abs_diff = `mx'
gen double n_fail = `nf' + `nm' + `nt'
gen str4 result = cond(n_fail == 0, "PASS", "FAIL")
export delimited using "${OUT}/C2_ub_identity.csv", replace
assert n_fail == 0
* ---------------------------------------------------------------- (b) HS 490700 value share
use year iso3_o iso3_d v_ttl_k v_ttl_ex4907 v_4907_k s_base_vis s_base_tour s_cs_exact ///
    s_dyn_vis s_dyn_tour s_cd_vis s_cd_tour `=cond("${VINTAGE}" == "corrected2x", "v_ttl31_k", "")' using "${PREPARED}", clear
tempname T
postfile `T' str11 vintage str8 item str40 table str48 sample str12 mobility str60 stat double(value N) str200 note ///
    using "${OUT}/tables/A2_A2.6_hs490700_share.dta", replace
foreach s in s_base_vis s_base_tour s_cs_exact s_dyn_vis s_dyn_tour s_cd_vis s_cd_tour {
    local mob = cond(strpos("`s'", "vis"), "visitors", cond(strpos("`s'", "tour"), "tourists", "both"))
    quietly summarize v_4907_k if `s', meanonly
    local s49 = r(sum)
    local n = r(N)
    quietly summarize `v31' if `s', meanonly
    local s31 = r(sum)
    quietly summarize v_ttl_ex4907 if `s', meanonly
    local s30 = r(sum)
    quietly count if `s' & v_4907_k > 0 & !missing(v_4907_k)
    local npos = r(N)
    post `T' ("${VINTAGE}") ("A2.6") ("value_share_hs490700") ("`s' (${VINTAGE})") ("`mob'") ("share_hs490700_of_31code_pct") (100 * `s49' / `s31') (`n') ///
        ("100 * sum(v_4907_k) / sum(31-code LB value) over the ${VINTAGE} sample `s'")
    post `T' ("${VINTAGE}") ("A2.6") ("value_share_hs490700") ("`s' (${VINTAGE})") ("`mob'") ("share_hs490700_of_30code_pct") (100 * `s49' / `s30') (`n') ///
        ("100 * sum(v_4907_k) / sum(30-code value v_ttl_ex4907) over the ${VINTAGE} sample `s'")
    post `T' ("${VINTAGE}") ("A2.6") ("value_share_hs490700") ("`s' (${VINTAGE})") ("`mob'") ("rows_with_hs490700_gt0") (`npos') (`n') ("rows of the sample with a positive HS 490700 value")
    display as result "C2_SHARE_490700 `s' share31=" %8.4f 100 * `s49' / `s31' " share30=" %8.4f 100 * `s49' / `s30' " rows_pos=`npos' N=`n'"
}
postclose `T'
use "${OUT}/tables/A2_A2.6_hs490700_share.dta", clear
format value %24.17g
export delimited using "${OUT}/tables/A2_A2.6_hs490700_share.csv", replace datafmt
erase "${OUT}/tables/A2_A2.6_hs490700_share.dta"
display as result "C2_03_EXTRAS_DONE vintage=${VINTAGE}"
log close
