/*******************************************************************************
 C2_02_bias.do -- rerun C2: Weidner-Zylkin analytical bias correction (Table A3, figure row)
 Usage (cwd = 02_code/10_analysis):  stata-mp -b -q do C2_02_bias.do <vintage>
 Runs the ORIGINAL 02_sensitivity/03_ppml_bias_correction.do unmodified from the vintage's code
 tree (${VROOT}/02_code; byte-identical to STUDENT, cmp 2026-11-03) on ${OUT}/prepared.dta via the
 PROJECT_ROOT tree that 02_positive_controls.do creates (${OUT}/pc/root, symbolic link
 03_intermediate/03_Mobility/runtime/core/LB/analysis_prepared.dta -> prepared.dta). The original uses
 ppmlhdfe (d option) + ppml_fe_bias (Weidner and Zylkin 2021; help ppml_fe_bias: i() j() t() lambda()
 beta() approx). Output: ${OUT}/pc/root/05_output/03_Mobility/01_diagnostics/sensitivity/
 03_ppml_bias_correction/ppml_bias_correction_results.csv, copied to ${OUT}/C2_bias_results.csv.
 Positive control (corrected vintage): every value equals the stored COPY result (snapshot) to 1e-9
 (relative), N exact. corrected2/corrected2x: no stored counterpart (new estimates).
*******************************************************************************/
args vintage
clear all
set more off
version 18.0
do "00_config.do" `vintage'
version 18.0
global C2_ROOT "${OUT}/pc/root"
confirm file "${C2_ROOT}/03_intermediate/03_Mobility/runtime/core/LB/analysis_prepared.dta"
global C2_ORIG "${VROOT}/02_code/03_Mobility/02_empirical_analysis/02_sensitivity/03_ppml_bias_correction.do"
confirm file "${C2_ORIG}"
* package: the comparison with the original submitted file uses its sha256 (README.md, code provenance)
pkg_py "${CODE}/pkg_fs.py" shacheck "${C2_ORIG}" "8ce66393e58a316b41b3654acf0c503af64f5fca06f456b1fe4d2d102486f2b6" "${OUT}/C2_bias_cmp.txt" CMP_IDENTICAL CMP_DIFFERENT
do "${C2_ORIG}" "${C2_ROOT}"
* the original runs clear all and closes logs: restore the configuration
do "00_config.do" `vintage'
global C2_ROOT "${OUT}/pc/root"
capture log close _all
log using "${LOGS}/C2_02_bias_${VINTAGE}.log", text replace
type "${OUT}/C2_bias_cmp.txt"
* nflow sidecar (audit check): the original do-file has no nflow records, and ppml_fe_bias posts only
* e(b), e(V), e(cmd), e(cmdline) (ppml_fe_bias.ado:298-300; no e(N)). The sidecar records, right after the
* original returns, the preceding ppmlhdfe e(N) that the original stores in scalar orig_<m>_n
* (original lines 184, 224) for both the PPML fit and the bias correction on that sample. Same layout as nflow.
local sc_ok = !missing(scalar(orig_vis_n)) & !missing(scalar(orig_tour_n))
assert `sc_ok'
tempname NF
file open `NF' using "${OUT}/C2_bias_nflow.csv", write replace
file write `NF' "date,time,kind,n_before,n_after,change,reason" _n
foreach m in vis tour {
    local nn = scalar(orig_`m'_n)
    file write `NF' "`=strtrim(c(current_date))',`c(current_time)',est,823446,`nn',`=`nn'-823446',""C2_02_bias `m' ppmlhdfe baseline (original 03_ppml_bias_correction.do) | ppmlhdfe e(N) stored as scalar orig_`m'_n""" _n
    file write `NF' "`=strtrim(c(current_date))',`c(current_time)',est,823446,`nn',`=`nn'-823446',""C2_02_bias `m' ppml_fe_bias on the same e(sample) | no e(N) posted by ppml_fe_bias; N = preceding ppmlhdfe e(N)""" _n
    display as result "C2_BIAS_NFLOW `m' N=`nn' (preceding ppmlhdfe e(N))"
}
file close `NF'
local res "${C2_ROOT}/05_output/03_Mobility/01_diagnostics/sensitivity/03_ppml_bias_correction/ppml_bias_correction_results.csv"
confirm file "`res'"
copy "`res'" "${OUT}/C2_bias_results.csv", replace
import delimited using "`res'", clear varnames(1) asdouble case(lower)
list measure original_b original_se corrected_b corrected_se corrected_p n, noobs clean
quietly summarize n if measure == "visitors", meanonly
assert r(mean) == scalar(orig_vis_n)
quietly summarize n if measure == "tourists", meanonly
assert r(mean) == scalar(orig_tour_n)
if "${VINTAGE}" == "corrected" {
    tempfile rep
    save `rep'
    import delimited using "${PUB_WZ}", clear varnames(1) asdouble case(lower)
    foreach v in original_b original_se corrected_b corrected_se corrected_p n {
        rename `v' pub_`v'
    }
    merge 1:1 measure using `rep', assert(match) nogen
    foreach v in original_b original_se corrected_b corrected_se corrected_p {
        assert abs(`v' - pub_`v') <= 1e-9 * max(1, abs(pub_`v'))
    }
    assert n == pub_n
    display as result "C2_BIAS_POSITIVE_CONTROL=PASS (corrected = stored COPY result, snapshot)"
}
display as result "C2_BIAS_DONE vintage=${VINTAGE}"
log close
