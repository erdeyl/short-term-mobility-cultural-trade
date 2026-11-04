/*******************************************************************************
 C2_00_controls.do -- rerun C2 positive controls for the new vintages
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do C2_00_controls.do <vintage> <reference>
   corrected2  corrected   (a) only the quarantined mobility cells and what is computed from them
                               differ; trade identical; (b) baseline = the authors' reference numbers
   corrected2x corrected2  mobility identical; v_ttl31_k = corrected2 v_ttl_k; v_ttl_k = v_ttl_ex4907
 Variable-by-variable comparison of the two prepared.dta files on the key year iso3_o iso3_d.
 "Allowed" rows = rows whose own or mirrored cell is quarantined (pak_/blr_lie_quarantine_rev/_same)
 and, for lags/leads, the adjacent years of the same directed pair. Sample flags s_* are
 e(sample) of ppmlhdfe fits; they may change elsewhere (iterative singleton drop), so they are
 reported, not restricted.
 Help consulted: [D] merge (1:1, assert(match)), [D] egen (max(), by()), [P] postfile,
 [D] ds (has(type string)), ppmlhdfe.sthlp 2.3.4 (e(sample), e(N), e(N_full), e(num_singletons),
 e(num_separated), e(converged)), nflow.sthlp 1.0.1.
 Output: ${OUT}/C2_controls_vardiff.csv, ${OUT}/C2_controls.csv, log.
*******************************************************************************/
args vintage ref
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
assert inlist("`vintage'/`ref'", "corrected2/corrected", "corrected2x/corrected2")
capture log close _all
log using "${LOGS}/C2_00_controls_${VINTAGE}.log", text replace
display as result "C2_00_BEGIN vintage=${VINTAGE} ref=`ref' " c(current_date) " " c(current_time)
global REFPREP "${OUTROOT}/`ref'/prepared.dta"
confirm file "${REFPREP}"

tempname CT
postfile `CT' str60 control str80 expected str120 observed str6 result using "${OUT}/C2_controls.dta", replace

* ---------------------------------------------------------------- load both files
use "${PREPARED}", clear
nflow start using "${OUT}/C2_nflow.csv", replace expected(823446)
unab nv : _all
local keys year iso3_o iso3_d
local nv : list nv - keys
foreach v of local nv {
    rename `v' n__`v'
}
tempfile newf
save `"`newf'"', replace
use "${REFPREP}", clear
unab rv : _all
local rv : list rv - keys
merge 1:1 year iso3_o iso3_d using `"`newf'"', assert(match) nogen
nflow step "C2_00: merge `ref' and ${VINTAGE} prepared.dta 1:1 by key (assert all match)"

* ---------------------------------------------------------------- allowed rows
if "`vintage'" == "corrected2" {
    gen byte __q = n__pak_res_quarantine_rev == 1 | n__pak_res_quarantine_same == 1 | ///
        n__blr_lie_quarantine_rev == 1 | n__blr_lie_quarantine_same == 1
    sort pair_id year
    by pair_id: gen byte __qn = __q | (__q[_n-1] == 1 & year[_n-1] == year - 1) | (__q[_n+1] == 1 & year[_n+1] == year + 1)
}
else {
    gen byte __q = 0
    gen byte __qn = 0
}
quietly count if __q
local nq = r(N)
display as result "C2_ALLOWED_ROWS (quarantined cell in either direction)=`nq'"

* ---------------------------------------------------------------- variable-by-variable comparison
tempname VD
postfile `VD' str32 variable str8 class double(rows_differ rows_differ_outside_allowed) str60 allowed ///
    using "${OUT}/C2_controls_vardiff.dta", replace
local mobvars tourists visitors rev_tour_raw rev_vis_raw same_tour_raw same_vis_raw has_rev_tour has_same_tour ///
    has_both_tour has_rev_vis has_same_vis has_both_vis bilat_tour_raw bilat_vis_raw mob_rev_tour mob_same_tour ///
    mob_bilat_tour mob_rev_vis mob_same_vis mob_bilat_vis
local lagvars lag_bilat_vis lead_bilat_vis lag_bilat_tour lead_bilat_tour
local nbad_trade 0
local nbad_mob 0
local only_ref ""
foreach v of local rv {
    capture confirm variable n__`v'
    if _rc {
        local only_ref "`only_ref' `v'"
        continue
    }
    capture confirm string variable `v'
    local isstr = (_rc == 0)
    capture confirm string variable n__`v'
    local isstr2 = (_rc == 0)
    if `isstr' != `isstr2' {
        post `VD' ("`v'") ("TYPE") (.) (.) ("string in one file, numeric in the other")
        continue
    }
    tempvar d
    if `isstr' gen byte `d' = `v' != n__`v'
    else gen byte `d' = !((`v' == n__`v') | (missing(`v') & missing(n__`v')))
    quietly count if `d'
    local nd = r(N)
    local cls "other"
    local allow "none"
    local cond "1"
    if strpos(" `mobvars' ", " `v' ") {
        local cls "mobility"
        local allow "quarantined cell in either direction"
        local cond "!__q"
    }
    else if strpos(" `lagvars' ", " `v' ") {
        local cls "lagLead"
        local allow "quarantined cell or adjacent year of the pair"
        local cond "!__qn"
    }
    else if substr("`v'", 1, 2) == "s_" {
        local cls "sample"
        local allow "anywhere (e(sample) flag; reported only)"
        local cond "0"
    }
    else if substr("`v'", 1, 2) == "v_" | inlist("`v'", "positive_trade", "pos_every_year", "fully_reported", "any_unreported", "comtrade_reporting_available", "hs6_merge") | ///
        inlist("`v'", "tradeflow_comtrade_o", "tradeflow_comtrade_d", "tradeflow_baci", "n_unreported_rows") {
        local cls "trade"
    }
    else if "`vintage'" == "corrected2" {
        * tourism source metadata and flags: allowed on quarantined rows (and pair-level switch on the pair)
        local allow "quarantined cell in either direction, or (basis_switch) the same directed pair"
        local cond "!__q"
        if strpos("`v'", "basis_switch") {
            tempvar qp
            egen byte `qp' = max(__q), by(pair_id)
            local cond "!`qp'"
        }
    }
    quietly count if `d' & (`cond')
    local nout = r(N)
    if "`cls'" == "sample" local nout = .
    post `VD' ("`v'") ("`cls'") (`nd') (`nout') ("`allow'")
    if `nd' > 0 display as result "VARDIFF `v' class=`cls' rows=`nd' outside_allowed=`nout'"
    if "`cls'" == "trade" & `nout' > 0 local nbad_trade = `nbad_trade' + 1
    if "`cls'" != "trade" & "`cls'" != "sample" & `nout' > 0 & `nout' < . local nbad_mob = `nbad_mob' + 1
    drop `d'
    capture drop `qp'
}
local only_new ""
foreach v of local nv {
    capture confirm variable `v'
    if _rc local only_new "`only_new' `v'"
}
display as result "ONLY_IN_`ref':`only_ref'"
display as result "ONLY_IN_${VINTAGE}:`only_new'"
postclose `VD'

* ---------------------------------------------------------------- vintage-specific controls
if "`vintage'" == "corrected2" {
    post `CT' ("(a) trade variables identical to corrected") ("0 variables with any differing row") ("`nbad_trade'") (cond(`nbad_trade' == 0, "PASS", "FAIL"))
    post `CT' ("(a) mobility/flag differences only on allowed rows") ("0 variables with differences outside") ("`nbad_mob'") (cond(`nbad_mob' == 0, "PASS", "FAIL"))
    foreach s in tourists visitors {
        quietly count if !((`s' == n__`s') | (missing(`s') & missing(n__`s')))
        local nd = r(N)
        quietly count if !missing(n__`s'_pre_pak)
        local npak = r(N)
        local nblr 0
        if "`s'" == "visitors" {
            quietly count if !missing(n__visitors_pre_blr)
            local nblr = r(N)
        }
        post `CT' ("(a) stored `s' cells changed") ("= quarantined cells (`npak' PAK + `nblr' BLR-LIE)") ("`nd'") (cond(`nd' == `npak' + `nblr', "PASS", "FAIL"))
        quietly count if !((`s' == n__`s') | (missing(`s') & missing(n__`s'))) & missing(n__`s'_pre_pak) & ("`s'" == "tourists" | missing(n__visitors_pre_blr))
        post `CT' ("(a) stored `s' changed outside quarantined cells") ("0") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
    }
    quietly count if !missing(n__tourists_pre_pak) & n__tourists_pre_pak != tourists
    post `CT' ("(a) tourists_pre_pak = corrected value") ("0 differences") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
    quietly count if !missing(n__visitors_pre_pak) & n__visitors_pre_pak != visitors
    post `CT' ("(a) visitors_pre_pak = corrected value") ("0 differences") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
    quietly count if !missing(n__visitors_pre_blr) & n__visitors_pre_blr != visitors
    post `CT' ("(a) visitors_pre_blr = corrected value") ("0 differences") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
    foreach m in vis tour {
        quietly count if has_both_`m' & !n__has_both_`m'
        local lost = r(N)
        quietly count if !has_both_`m' & n__has_both_`m'
        local gain = r(N)
        quietly count if has_both_`m' & (iso3_o == "PAK" | iso3_d == "PAK") & inrange(year, 2020, 2021)
        local pakhb = r(N)
        post `CT' ("(a) has_both_`m': rows lost / gained") ("lost = corrected PAK 2020-21 has_both rows (`pakhb'); gained 0") ("lost `lost', gained `gain'") ///
            (cond(`lost' == `pakhb' & `gain' == 0, "PASS", "FAIL"))
        quietly count if s_base_`m' & (iso3_o == "PAK" | iso3_d == "PAK") & inrange(year, 2020, 2021)
        local pakb = r(N)
        local expb = cond("`m'" == "vis", 152, 193)
        post `CT' ("(a) corrected baseline rows with PAK 2020-21 (`m')") ("`expb' (authors' working notes)") ("`pakb'") (cond(`pakb' == `expb', "PASS", "FAIL"))
        quietly count if s_base_`m' & ((iso3_o == "BLR" & iso3_d == "LIE") | (iso3_o == "LIE" & iso3_d == "BLR")) & inrange(year, 2020, 2022)
        local blrb = r(N)
        quietly count if n__s_base_`m' & (n__blr_lie_quarantine_rev == 1 | n__blr_lie_quarantine_same == 1)
        post `CT' ("(a) BLR-LIE quarantine: baseline rows (`m')") ("0 in corrected and corrected2") ("corrected `blrb', corrected2 `r(N)'") (cond(`blrb' == 0 & r(N) == 0, "PASS", "FAIL"))
    }
    * (b) baseline = measured exclusion fit (separate diagnostic run):
    *     visitors 0.191778 (0.081398, N 20,711), tourists 0.233457 (0.065243, N 26,478)
    gen byte __pak = (iso3_o == "PAK" | iso3_d == "PAK") & inlist(year, 2020, 2021)
    foreach m in vis tour {
        local eb = cond("`m'" == "vis", 0.191778, 0.233457)
        local es = cond("`m'" == "vis", 0.081398, 0.065243)
        local en = cond("`m'" == "vis", 20711, 26478)
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if has_both_`m' & !__pak, absorb(exporter_year importer_year pair_id) vce(cluster pair_id)
        assert e(converged) == 1
        assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
        nflow est "C2_00 (b) corrected data excluding PAK 2020-21 pair-years (authors' specification) `m'"
        local b0 = _b[mob_bilat_`m']
        local s0 = _se[mob_bilat_`m']
        gen byte __e0 = e(sample)
        quietly ppmlhdfe n__v_ttl_k n__mob_bilat_`m' if n__has_both_`m', absorb(n__exporter_year n__importer_year n__pair_id) vce(cluster n__pair_id)
        assert e(converged) == 1
        assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
        nflow est "C2_00 (b) corrected2 baseline `m'"
        local b1 = _b[n__mob_bilat_`m']
        local s1 = _se[n__mob_bilat_`m']
        local n1 = e(N)
        gen byte __e1 = e(sample)
        display as result "C2_BASELINE_`m' b=" %18.15f `b1' " se=" %18.15f `s1' " N=" `n1' " N_full=" e(N_full) " singletons=" e(num_singletons) " separated=" e(num_separated) " clusters=" e(N_clust)
        display as result "C2_EXCLUSION_`m' b=" %18.15f `b0' " se=" %18.15f `s0'
        local ok = abs(`b1' - `eb') <= 5e-7 + 1e-12 & abs(`s1' - `es') <= 5e-7 + 1e-12 & `n1' == `en'
        post `CT' ("(b) corrected2 baseline `m' vs printed reference numbers") ("b `eb', se `es' (rounding 5e-7); N `en'") ///
            ("b `: display %10.7f `b1'', se `: display %10.7f `s1'', N `n1'") (cond(`ok', "PASS", "FAIL"))
        quietly count if __e0 != __e1
        local nds = r(N)
        local ok2 = abs(`b1' - `b0') < 1e-6 & abs(`s1' - `s0') < 1e-6 & `nds' == 0
        post `CT' ("(b) corrected2 baseline `m' = exclusion fit on corrected (full precision)") ("|db|,|dse| < 1e-6; identical e(sample)") ///
            ("|db| `: display %9.2e abs(`b1' - `b0')', |dse| `: display %9.2e abs(`s1' - `s0')', e(sample) rows differing `nds'") (cond(`ok2', "PASS", "FAIL"))
        quietly count if __e1 != n__s_base_`m'
        post `CT' ("(b) e(sample) = prepared s_base_`m' (corrected2)") ("0 differing rows") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
        drop __e0 __e1
    }
}
if "`vintage'" == "corrected2x" {
    foreach s in tourists visitors mob_bilat_vis mob_bilat_tour has_both_vis has_both_tour {
        quietly count if !((`s' == n__`s') | (missing(`s') & missing(n__`s')))
        post `CT' ("mobility `s' identical to corrected2") ("0 differing rows") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
    }
    quietly count if !((v_ttl_k == n__v_ttl31_k) | (missing(v_ttl_k) & missing(n__v_ttl31_k)))
    post `CT' ("v_ttl31_k (corrected2x) = v_ttl_k (corrected2)") ("0 differing rows") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
    quietly count if !((v_ttl_ex4907 == n__v_ttl_k) | (missing(v_ttl_ex4907) & missing(n__v_ttl_k)))
    post `CT' ("v_ttl_k (corrected2x) = v_ttl_ex4907 (corrected2)") ("0 differing rows") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
    quietly count if !((v_49_k == n__v_49_31_k) | (missing(v_49_k) & missing(n__v_49_31_k)))
    post `CT' ("v_49_31_k (corrected2x) = v_49_k (corrected2)") ("0 differing rows") ("`r(N)'") (cond(r(N) == 0, "PASS", "FAIL"))
    gen double __d = abs((v_ttl_k - n__v_ttl_k) - v_4907_k)
    quietly summarize __d
    local mx = r(max)
    quietly count if __d > 1e-6 & !missing(__d)
    post `CT' ("v_ttl_k(2) - v_ttl_k(2x) = HS 490700 component") ("0 rows beyond 1e-6") ("`r(N)' (max |diff| `: display %9.2e `mx'')") (cond(r(N) == 0, "PASS", "FAIL"))
    drop __d
    foreach m in vis tour {
        quietly count if s_base_`m'
        local a = r(N)
        quietly count if n__s_base_`m'
        local b = r(N)
        quietly count if s_base_`m' != n__s_base_`m'
        post `CT' ("baseline sample s_base_`m': corrected2 vs corrected2x") ("reported") ("`a' vs `b'; rows differing `r(N)'") ("INFO")
        quietly count if n__s_base_`m' & v_4907_k > 0 & !missing(v_4907_k)
        local r4 = r(N)
        quietly summarize v_4907_k if s_base_`m', meanonly
        local s4 = r(sum)
        quietly summarize v_ttl_k if s_base_`m', meanonly
        post `CT' ("corrected2 baseline `m': rows with HS 490700 > 0; 490700 value share") ("reported (SWEEP2 table 6 item 9: 4,998/4,771 rows, 3.6%/5.4% on corrected)") ///
            ("`r4' rows in corrected2x baseline; share `: display %6.4f `s4'/r(sum)' of corrected2 baseline value") ("INFO")
    }
}
postclose `CT'
preserve
    use "${OUT}/C2_controls.dta", clear
    export delimited using "${OUT}/C2_controls.csv", replace
    list, noobs clean
    quietly count if result == "FAIL"
    local nfail = r(N)
restore
preserve
    use "${OUT}/C2_controls_vardiff.dta", clear
    export delimited using "${OUT}/C2_controls_vardiff.csv", replace
    list if rows_differ > 0, noobs clean
restore
nflow report
if `nfail' > 0 {
    display as error "C2 CONTROLS FAILED (`nfail')"
    exit 459
}
display as result "C2_CONTROLS=PASS vintage=${VINTAGE} " c(current_date) " " c(current_time)
log close
