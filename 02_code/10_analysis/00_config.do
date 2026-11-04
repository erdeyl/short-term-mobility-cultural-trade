/*******************************************************************************
 00_config.do  --  globals for one data vintage (analysis layer of the replication package)

 Usage (from another do-file, cwd = 02_code/10_analysis):  do 00_config.do <vintage>
   <vintage> = corrected2x (revised baseline, default run)
             | corrected | corrected2 (reconciliation switch, same data build)
             | submitted (reconciliation switch, needs a second build with corrections off)
 Every path is built from the package root ${PKGROOT}, which run_all.py passes as the first
 argument of the generated wrapper do-file (_run.do pattern); nothing here is machine-specific.
 Defines globals only and checks the Stata version.

 Vintages (see README.md, "Data-correction rules"):
   corrected   = build with the correction rules on (code 490 -> TWN, Paraguay residence quarantine, flags)
   corrected2  = corrected + quarantine of PAK residence 2020-2021 and BLR visitors-by-residence
                 partner LIE 2020-2022 (same rule as Paraguay); 31-code outcome
   corrected2x = corrected2 with the 30-code outcome (31-code basket minus HS 490700) = revised baseline
   submitted   = original data as submitted (build with corrections off), for the reconciliation only
*******************************************************************************/

args vintage
if !inlist("`vintage'", "submitted", "corrected", "corrected2", "corrected2x") {
    display as error "VINTAGE must be submitted, corrected, corrected2 or corrected2x; got [`vintage']"
    exit 198
}

version 18.0
if c(stata_version) < 18 {
    display as error "Stata 18 or newer required; running " c(stata_version)
    exit 9
}

global VINTAGE "`vintage'"

* ---------------------------------------------------------------- roots (all relative to the package root)
if `"${PKGROOT}"' == "" {
    display as error "PKGROOT is not set. Run the analysis through run_all.py (it passes the package root)."
    exit 198
}
global ROOT "${PKGROOT}"
confirm file "${ROOT}/run_all.py"
local _py : environment PKG_PYTHON
if `"`_py'"' == "" {
    display as error "PKG_PYTHON is not set. Run the analysis through run_all.py."
    exit 198
}
global PYTHON `"`_py'"'
global RAW     "${ROOT}/01_raw"
global DERIVED "${ROOT}/derived"
* Corrected chapter build of this package (02_code/00_common + 02_code/03_Mobility, run by run_all.py
* stage "build"): its 03_intermediate, 04_analysis data and 05_output folders live in the package root.
global COPY    "${ROOT}"
global SNAP    "${ROOT}"
* Submitted vintage (reconciliation only): a second copy of the package built with corrections off
* (run_all.py --corrections none --stages check,build) and the stored outputs of the first-submission
* replication package (its 07_results folder is read). Both are given as environment variables.
local _sub : environment PKG_SUBMITTED_ROOT
local _pub : environment PKG_SUBMITTED_PUBLISHED
global STUDENT `"`_sub'"'
global PKG     `"`_pub'"'
if "`vintage'" == "submitted" & (`"${STUDENT}"' == "" | `"${PKG}"' == "") {
    display as error "Vintage submitted needs PKG_SUBMITTED_ROOT and PKG_SUBMITTED_PUBLISHED (README.md, reconciliation switch)."
    exit 198
}

if "`vintage'" == "submitted" global VROOT "${STUDENT}"
if inlist("`vintage'", "corrected", "corrected2", "corrected2x") global VROOT "${ROOT}"

* ---------------------------------------------------------------- inputs
global DATA_FILE      "${VROOT}/04_analysis data/03_Mobility/mobility_analysis_2007_2021.dta"
global MASTER_FILE    "${VROOT}/03_intermediate/03_Mobility/master/mobility_merged_2007_2021.dta"
global COPY_DATA_FILE "${ROOT}/04_analysis data/03_Mobility/mobility_analysis_2007_2021.dta"
global CT_RAW_DIR     "${VROOT}/01_raw/02_UN_Comtrade/trade_api/reported_HS"
global CT_MANIFEST    "${VROOT}/01_raw/02_UN_Comtrade/acquisition_metadata/download_manifest.csv"
global CT_INT         "${VROOT}/03_intermediate/00_common/01_UN_Comtrade"
global CT_CROSSWALK   "${ROOT}/02_code/00_common/01_UN_Comtrade/config/special_area_crosswalk.csv"
global CEPII_FILE     "${RAW}/01_Gravity/Gravity_V202211.dta"
global WB_CLASS       "${RAW}/06_WorldBank/CLASS.xlsx"
global WB_OGHIST      "${RAW}/06_WorldBank/OGHIST.xlsx"
global LING_FILE      "${RAW}/07_CEPII_Language/ling_web.dta"
global C09_FILE       "${DERIVED}/flags/C09_zero_fill_no_rows.csv"
if inlist("`vintage'", "corrected", "corrected2", "corrected2x") {
    global MIRROR      "${SNAP}/03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta"
    global PUB_A4KEY   "${SNAP}/05_output/03_Mobility/01_diagnostics/sensitivity/04_mirror_trade/mirror_trade_key_results.csv"
    global PUB_UB      "${SNAP}/05_output/03_Mobility/01_diagnostics/core/UB/baseline-key-results.csv"
    global PUB_WZ      "${SNAP}/05_output/03_Mobility/01_diagnostics/sensitivity/03_ppml_bias_correction/ppml_bias_correction_results.csv"
}

* ---------------------------------------------------------------- published results (positive controls)
if "`vintage'" == "submitted" {
    global PUB_TAB   "${PKG}/07_results/01_core/LB/tables"
    global PUB_DIAG  "${PKG}/07_results/01_core/LB/diagnostics"
    global PUB_CS    "${PKG}/07_results/02_sensitivity/01_common_support/diagnostics"
    global PUB_FE    "${PKG}/07_results/02_sensitivity/02_formal_equality/diagnostics"
    global PUB_LOG   "${STUDENT}/05_output/03_Mobility/03_logs/core/LB/00_core_run.log"
    global PUB_CS_TAB "${PKG}/07_results/02_sensitivity/01_common_support/tables/table_common_support_visitors_tourists.csv"
    global PUB_FE_TAB "${PKG}/07_results/02_sensitivity/02_formal_equality/tables/table_formal_equality_visitors_tourists.csv"
}
* corrected, corrected2, corrected2x: the reference outputs are those of the corrected chapter build
* (original Mobility do-files run by run_all.py stage "build"). corrected2 / corrected2x have no published
* counterpart: 02_positive_controls.do compares them with the corrected outputs, so its "published" column
* = corrected and a difference there is expected by design (it is reported, not treated as an error);
* its "reproduced" column is the original code run on this vintage's prepared.dta.
if inlist("`vintage'", "corrected", "corrected2", "corrected2x") {
    global PUB_CS_TAB "${SNAP}/05_output/03_Mobility/02_empirical_analysis/02_sensitivity/01_common_support/tables/table_common_support_visitors_tourists.csv"
    global PUB_FE_TAB "${SNAP}/05_output/03_Mobility/02_empirical_analysis/02_sensitivity/02_formal_equality/tables/table_formal_equality_visitors_tourists.csv"
    global PUB_TAB   "${SNAP}/05_output/03_Mobility/02_empirical_analysis/01_core/LB/tables"
    global PUB_DIAG  "${SNAP}/05_output/03_Mobility/01_diagnostics/core/LB"
    global PUB_CS    "${SNAP}/05_output/03_Mobility/01_diagnostics/sensitivity/01_common_support"
    global PUB_FE    "${SNAP}/05_output/03_Mobility/01_diagnostics/sensitivity/02_formal_equality"
    global PUB_LOG   "${SNAP}/05_output/03_Mobility/03_logs/core/LB/00_core_run.log"
}

* ---------------------------------------------------------------- outputs
global CODE      "${ROOT}/02_code/10_analysis"
global OUTROOT   "${ROOT}/05_output/10_analysis"
global OUT       "${OUTROOT}/`vintage'"
global LOGS      "${OUT}/logs"
global PREPARED  "${OUT}/prepared.dta"
global HS6_FILE  "${OUT}/hs6_dyad_wide.dta"
global HS6_STATUS "${OUT}/hs6_build_status.json"
global NFLOW     "${OUT}/nflow.csv"

* ---------------------------------------------------------------- corrected2 / corrected2x only
* Exporter-reported mirror file read by A1_04 / A2_01_build. corrected2: the chapter build's file (trade is
* identical to corrected). corrected2x: the same file with both trade sides on the 30-code basket
* (built by C2_01_mirror_ex4907.py; v_ttl_k = importer-reported 30-code value, v_ttl_exporter_lb_k
* = exporter-reported 31-code LB minus exporter-reported HS 490700).
if "`vintage'" == "corrected2x" global MIRROR "${OUT}/mirror_analysis_ready_ex4907.dta"
if "`vintage'" == "corrected2"  global C2_OUTCOME "v_ttl_k = 31-code LB basket (as corrected)"
if "`vintage'" == "corrected2x" global C2_OUTCOME "v_ttl_k = 30-code LB basket (31 codes minus HS 490700) = v_ttl_ex4907"

* ---------------------------------------------------------------- platform-neutral helpers
* pkg_py runs the package's Python with the given arguments (quoted as on the command line). On Windows
* the whole line is wrapped in one more pair of double quotes, because cmd /c strips the outermost pair.
do "${CODE}/pkg_programs.do"
