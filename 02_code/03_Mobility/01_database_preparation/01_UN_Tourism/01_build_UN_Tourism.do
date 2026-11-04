/****************************************************************************************
 UN TOURISM COUNTRY-PAIR DATABASE
 Portable construction from authorized UN Tourism Excel files + layered validation/audit

 PURPOSE
   Build a standalone, reproducible UN Tourism country-pair mobility database directly
   from the downloaded country-level Excel files. This script DOES NOT use or validate
   against any later cultural-trade dataset.

 SOURCE FOLDER STRUCTURE EXPECTED
   raw data/
      Tourists Arrivals by Nationality/   *.xlsx
      Tourists Arrivals by Residence/    *.xlsx
      Visitors Arrivals by Nationality/   *.xlsx
      Visitors Arrivals by Residence/    *.xlsx

 SOURCE DIRECTION CONVENTION
   reporter_area_code = tourism destination
   partner_area_code  = tourism origin

 CONSTRUCTION RULE
   For tourists and visitors separately:
      1. use the residence-classified series where available;
      2. otherwise fall back to the nationality-classified series;
      3. never add residence and nationality together.

 SOURCE UNIT
   thousand trips. The script keeps the source-unit variables (*_k) and also creates
   variables in trips by multiplying by 1,000. It does NOT round the converted values.

 OUTPUT LOGIC
   01_source_long_all_series.dta
       normalized long-form archive of all four raw source families
   02_source_wide_four_series.dta
       one reporter-partner-year row with all four source values and metadata
   03_un_tourism_country_pair_residence_first_full.dta
       residence-first final database, all years available in the raw archive
   04_un_tourism_country_pair_residence_first_2007_2021.dta
       same database restricted to the manuscript analysis window

 DIAGNOSTICS
   The script writes audit CSV/DTA files for:
      - source-file manifest and validation summary
      - label conflicts across source families
      - residence/nationality overlap and value differences
      - tourist > visitor hierarchy violations
      - mixed-basis hierarchy cases
      - same-basis hierarchy cases
      - same-basis cases with source metadata vs unexplained cases
      - selected visitor observations flagged "Definition differs"
      - fractional-trip precision inherited from source values
      - all selected-source flags/notes

 IMPORTANT PRINCIPLE
   The audit files diagnose source/construct issues. The script never silently rounds,
   overwrites, deletes, or repairs observations merely because they look anomalous.

 COMPATIBILITY
   Stata 18. Uses built-in commands only.
****************************************************************************************/

version 18.0
clear all
set more off
set varabbrev off
set type double

* ======================================================================================
* 0. PROJECT ROOT / RESTRICTED-SOURCE SETTINGS
* ======================================================================================

* UN Tourism country-level workbooks used here require authorized/subscription access.
* They are not intended to be redistributed with the public replication archive.
*
* Authorized users place the original files under:
*
*   replication_build/01_raw/05_Mobility/
*      Tourists Arrivals by Nationality/
*      Tourists Arrivals by Residence/
*      Visitors Arrivals by Nationality/
*      Visitors Arrivals by Residence/
*
* This do-file receives the replication-package root as argument 1.
*
* Example manual run:
*   do "<PROJECT_ROOT>/02_code/03_Mobility/01_database_preparation/01_UN_Tourism/01_build_UN_Tourism.do" ///
*      "<PROJECT_ROOT>"

args PROJECT_ROOT

if `"`PROJECT_ROOT'"' == "" {
    local PROJECT_ROOT : env REPLICATION_ROOT
}

if `"`PROJECT_ROOT'"' == "" {
    di as error "ERROR: replication-package root was not supplied."
    di as error "Run through RUN_01_PREPARE_DATABASE.bat or pass the project root as argument 1."
    exit 198
}

local PROJECT_ROOT = subinstr(`"`PROJECT_ROOT'"', "\", "/", .)

global ROOT       `"`PROJECT_ROOT'"'
global TOUR_RAW   "${ROOT}/01_raw/05_Mobility"
global TOUR_INT   "${ROOT}/03_intermediate/03_Mobility/01_UN_Tourism"
global TOUR_FINAL "${ROOT}/03_intermediate/03_Mobility/source_tables/UN_Tourism"
global TOUR_DIAG  "${ROOT}/05_output/03_Mobility/01_diagnostics/UN_Tourism"

global ANALYSIS_START 2007
global ANALYSIS_END   2021

* Frozen archive validation.
global STRICT_RELEASE 1

global NFILE_TOUR_NAT 61
global NFILE_TOUR_RES 131
global NFILE_VIS_NAT  45
global NFILE_VIS_RES  107

global NROW_TOUR_NAT 106612
global NROW_TOUR_RES 161471
global NROW_VIS_NAT   93476
global NROW_VIS_RES   127634

* ======================================================================================
* 0A. PRE-FLIGHT SOURCE-FOLDER CHECK
*     The four Excel folders must sit DIRECTLY inside ${TOUR_RAW}.
* ======================================================================================

foreach folder in ///
    "Tourists Arrivals by Nationality" ///
    "Tourists Arrivals by Residence" ///
    "Visitors Arrivals by Nationality" ///
    "Visitors Arrivals by Residence" {

    capture local __files : dir "${TOUR_RAW}/`folder'" files "*.xlsx"
    if _rc {
        di as error "ERROR: source folder not found:"
        di as error `"${TOUR_RAW}/`folder'"'
        di as error "The four folders must be directly under TOUR_RAW."
        di as error "These workbooks require authorized/subscription UN Tourism access and are not redistributed here."
        exit 601
    }

    local __n : word count `__files'
    if `__n' == 0 {
        di as error "ERROR: no XLSX files found in:"
        di as error `"${TOUR_RAW}/`folder'"'
        exit 601
    }

    di as result "PRE-FLIGHT: `folder' -> `__n' Excel files"
}

di as result "PRE-FLIGHT_SOURCE_FOLDERS=PASS"

capture mkdir "${TOUR_INT}"
capture mkdir "${TOUR_FINAL}"
capture mkdir "${TOUR_DIAG}"

capture log close _all
log using "${ROOT}/05_output/03_Mobility/03_logs/UN_Tourism_reproducible_build.log", text replace

noi di as text "============================================================"
noi di as result "UN TOURISM REPRODUCIBLE CONSTRUCTION START"
noi di as text "RAW: ${TOUR_RAW}"
noi di as text "INTERMEDIATE: ${TOUR_INT}"
noi di as text "FINAL: ${TOUR_FINAL}"
noi di as text "DIAGNOSTICS: ${TOUR_DIAG}"
noi di as text "Analysis window: ${ANALYSIS_START}-${ANALYSIS_END}"
noi di as text "Strict frozen-release validation: ${STRICT_RELEASE}"
noi di as text "Stata c(tmpdir): `c(tmpdir)' (v6 does not rely on it for construction scratch files)"
noi di as text "============================================================"

* ======================================================================================
* 1. HELPER PROGRAMS
* ======================================================================================

capture program drop __to_string
program define __to_string
    version 18.0
    syntax varname
    capture confirm string variable `varlist'
    if _rc {
        tostring `varlist', replace force format(%24.15g)
        replace `varlist' = "" if `varlist' == "."
    }
    replace `varlist' = strtrim(`varlist')
end

capture program drop __build_family
program define __build_family, rclass
    version 18.0
    * Do NOT use string asis here: with folder("...") Stata can retain the
    * literal quote characters, which then makes : dir look for a path whose
    * name includes quotes. string strips the option quotes while preserving spaces.
    syntax, FOLDER(string) OUTFILE(string) ///
        FAMILY(string) BASIS(string) INDICATOR(string) FILECODE(string) ///
        EXPECTFILES(integer) EXPECTROWS(integer)

    capture local files : dir "`folder'" files "*.xlsx"
    if _rc {
        noi di as error "SOURCE DIRECTORY NOT FOUND:"
        noi di as error `"`folder'"'
        noi di as error "Check global TOUR_RAW and the four source-folder names."
        exit 601
    }
    local nfiles : word count `files'

    noi di as text "------------------------------------------------------------"
    noi di as result "IMPORT FAMILY: `family' / `basis'"
    noi di as text "Folder: `folder'"
    noi di as result "Excel files found = `nfiles'"

    if `nfiles' == 0 {
        noi di as error "No Excel files found in `folder'"
        exit 601
    }
    if ${STRICT_RELEASE} == 1 & `nfiles' != `expectfiles' {
        noi di as error "Unexpected file count. Expected `expectfiles'; found `nfiles'."
        exit 459
    }

    * Use explicit scratch files inside the project intermediate folder rather than Stata tempfile.
    * This avoids failures when Stata's c(tmpdir) points to a non-writable location.
    local assembled "${TOUR_INT}/__scratch_`family'_`basis'_assembled.dta"
    local manifest  "${TOUR_INT}/__scratch_`family'_`basis'_manifest.dta"
    capture erase "`assembled'"
    capture erase "`manifest'"
    local first = 1
    local mfirst = 1
    local fileno = 0

    foreach f of local files {
        local ++fileno
        noi di as text "  [`fileno'/`nfiles'] `f'"

        capture noisily import excel using `"`folder'/`f'"', ///
            sheet("Data") firstrow case(lower) clear
        if _rc {
            noi di as error "IMPORT FAILED: `f'"
            exit _rc
        }

        * Required schema in the supplied UN Tourism workbooks.
        foreach v in reporter_area_code reporter_area_label indicator_code indicator_label ///
                     indicator_previous_code partner_area_code partner_area_label year value ///
                     flag flag_label unit notes {
            capture confirm variable `v'
            if _rc {
                noi di as error "Missing required variable `v' in `f'"
                exit 111
            }
        }

        keep reporter_area_code reporter_area_label indicator_code indicator_label ///
             indicator_previous_code partner_area_code partner_area_label year value ///
             flag flag_label unit notes

        * Normalize key/value types.
        foreach v in reporter_area_code partner_area_code year value {
            capture confirm numeric variable `v'
            if _rc destring `v', replace ignore(",")
        }
        foreach v in reporter_area_label indicator_code indicator_label ///
                     indicator_previous_code partner_area_label flag flag_label unit notes {
            __to_string `v'
        }

        * Structural source validation.
        assert indicator_code == "`indicator'" if indicator_code != ""
        assert lower(unit) == "thousand trips" if !missing(value)
        assert !missing(reporter_area_code, partner_area_code, year) if !missing(value)

        quietly summarize reporter_area_code, meanonly
        assert r(min) == r(max)

        * File naming convention in the current archive:
        * 1-4 reporter code; 5-8 indicator file code; 9-12 first year;
        * 13-16 last year; 17-22 release YYYYMM.
        local fn_reporter = real(substr("`f'",1,4))
        if missing(`fn_reporter') {
            noi di as error "Unexpected filename convention: `f'"
            exit 459
        }
        assert reporter_area_code == `fn_reporter'
        if substr("`f'",5,4) != "`filecode'" {
            noi di as error "Indicator code in filename does not match folder: `f'"
            exit 459
        }

        gen str100 source_file = "`f'"
        gen str12 source_family = "`family'"
        gen str12 source_basis  = "`basis'"
        gen int source_file_startyear = real(substr(source_file,9,4))
        gen int source_file_endyear   = real(substr(source_file,13,4))
        gen str6 source_release_yyyymm = substr(source_file,17,6)

        assert inrange(year,source_file_startyear,source_file_endyear)

        * A source family must contain only one row for a reporter-partner-year.
        capture isid reporter_area_code partner_area_code year
        if _rc {
            capture frame drop __dupcheck
            frame copy default __dupcheck, replace
            frame __dupcheck: duplicates tag reporter_area_code partner_area_code year, gen(__dup)
            frame __dupcheck: keep if __dup > 0
            frame __dupcheck: export delimited using ///
                "${TOUR_DIAG}/FAILED_duplicate_keys_`family'_`basis'.csv", replace
            frame drop __dupcheck
            noi di as error "Duplicate source keys detected in `f'. See diagnostics."
            exit 459
        }

        * Per-file manifest row before stacking.
        quietly count
        local __source_rows = r(N)
        quietly summarize year, meanonly
        local __observed_min_year = r(min)
        local __observed_max_year = r(max)

        capture frame drop __filemanifest
        frame copy default __filemanifest, replace
        frame __filemanifest: keep in 1
        frame __filemanifest: gen long source_rows = `__source_rows'
        frame __filemanifest: gen int observed_min_year = `__observed_min_year'
        frame __filemanifest: gen int observed_max_year = `__observed_max_year'
        frame __filemanifest: keep source_file source_family source_basis reporter_area_code reporter_area_label ///
             source_file_startyear source_file_endyear source_release_yyyymm ///
             source_rows observed_min_year observed_max_year

        if `mfirst' {
            frame __filemanifest: save "`manifest'", replace
            local mfirst = 0
        }
        else {
            frame __filemanifest: append using "`manifest'"
            frame __filemanifest: save "`manifest'", replace
        }
        frame drop __filemanifest

        if `first' {
            save "`assembled'", replace
            local first = 0
        }
        else {
            append using "`assembled'"
            save "`assembled'", replace
        }
    }

    use "`assembled'", clear
    sort reporter_area_code partner_area_code year
    isid reporter_area_code partner_area_code year
    quietly count
    local nrows = r(N)

    if ${STRICT_RELEASE} == 1 & `nrows' != `expectrows' {
        noi di as error "Unexpected imported row count for `family'/`basis'."
        noi di as error "Expected `expectrows'; found `nrows'."
        exit 459
    }

    * Do not compress numeric source values; preserve imported precision.
    recast double value
    capture rescue_on C12 // RESCUE C12 I-M2
    local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
    if `rescue_on_C12' { // RESCUE C12
        gen byte pry_res_quarantine = reporter_area_code==600 & source_basis=="residence" & inlist(source_file,"0600011220202024202512.xlsx","0600012220202024202512.xlsx") & inrange(year,2020,2022) // RESCUE C12
        gen double pry_res_raw_value = value if pry_res_quarantine // RESCUE C12
        label variable pry_res_raw_value "Original stored source value before PRY residence quarantine" // RESCUE C12
        replace value = . if pry_res_quarantine // RESCUE C12
    } // RESCUE C12
    save `"`outfile'"', replace

    use "`manifest'", clear
    sort reporter_area_code source_file
    save `"`outfile'_manifest.dta"', replace

    * Scratch files are no longer needed after the family outputs are frozen.
    capture erase "`assembled'"
    capture erase "`manifest'"

    return scalar nfiles = `nfiles'
    return scalar nrows  = `nrows'
end

* ======================================================================================
* 2. LAYER 1 -- IMPORT EACH EXCEL FAMILY DIRECTLY FROM SOURCE FILES
* ======================================================================================

__build_family, ///
    folder("${TOUR_RAW}/Tourists Arrivals by Nationality") ///
    outfile("${TOUR_INT}/01_tourists_nationality") ///
    family("tourists") basis("nationality") ///
    indicator("INBD_TRIP_NLTY_TOUR") filecode("0111") ///
    expectfiles(${NFILE_TOUR_NAT}) expectrows(${NROW_TOUR_NAT})
local f_tn = r(nfiles)
local r_tn = r(nrows)

__build_family, ///
    folder("${TOUR_RAW}/Tourists Arrivals by Residence") ///
    outfile("${TOUR_INT}/01_tourists_residence") ///
    family("tourists") basis("residence") ///
    indicator("INBD_TRIP_AREA_TOUR") filecode("0112") ///
    expectfiles(${NFILE_TOUR_RES}) expectrows(${NROW_TOUR_RES})
local f_tr = r(nfiles)
local r_tr = r(nrows)

__build_family, ///
    folder("${TOUR_RAW}/Visitors Arrivals by Nationality") ///
    outfile("${TOUR_INT}/01_visitors_nationality") ///
    family("visitors") basis("nationality") ///
    indicator("INBD_TRIP_NLTY_VSTR") filecode("0121") ///
    expectfiles(${NFILE_VIS_NAT}) expectrows(${NROW_VIS_NAT})
local f_vn = r(nfiles)
local r_vn = r(nrows)

__build_family, ///
    folder("${TOUR_RAW}/Visitors Arrivals by Residence") ///
    outfile("${TOUR_INT}/01_visitors_residence") ///
    family("visitors") basis("residence") ///
    indicator("INBD_TRIP_AREA_VSTR") filecode("0122") ///
    expectfiles(${NFILE_VIS_RES}) expectrows(${NROW_VIS_RES})
local f_vr = r(nfiles)
local r_vr = r(nrows)

noi di as result "VALIDATION_LAYER_1_EXCEL_IMPORT=PASS"

* Build source file manifest.
local manifest_all "${TOUR_INT}/__scratch_manifest_all.dta"
capture erase "`manifest_all'"
local mf_first = 1
foreach stem in 01_tourists_nationality 01_tourists_residence ///
                    01_visitors_nationality 01_visitors_residence {
    use "${TOUR_INT}/`stem'_manifest.dta", clear
    if `mf_first' {
        save "`manifest_all'", replace
        local mf_first = 0
    }
    else {
        append using "`manifest_all'"
        save "`manifest_all'", replace
    }
}
use "`manifest_all'", clear
sort source_family source_basis reporter_area_code
save "${TOUR_DIAG}/source_file_manifest.dta", replace
export delimited using "${TOUR_DIAG}/source_file_manifest.csv", replace

* Normalized long-form source archive: all four families in one file.
local source_long "${TOUR_INT}/__scratch_source_long.dta"
capture erase "`source_long'"
local sl_first = 1
foreach stem in 01_tourists_nationality 01_tourists_residence ///
                    01_visitors_nationality 01_visitors_residence {
    use "${TOUR_INT}/`stem'.dta", clear
    if `sl_first' {
        save "`source_long'", replace
        local sl_first = 0
    }
    else {
        append using "`source_long'"
        save "`source_long'", replace
    }
}
use "`source_long'", clear
sort source_family source_basis reporter_area_code partner_area_code year
recast double value
save "${TOUR_INT}/01_source_long_all_series.dta", replace

* ======================================================================================
* 3. LAYER 2 -- MERGE THE FOUR SOURCE SERIES TO ONE REPORTER-PARTNER-YEAR FRAME
* ======================================================================================

local rescue_q "" // RESCUE C12
capture rescue_on C12 // RESCUE C12 I-M2
local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
if `rescue_on_C12' local rescue_q "pry_res_quarantine" // RESCUE C12
local tn "${TOUR_INT}/__scratch_tn.dta"
local tr "${TOUR_INT}/__scratch_tr.dta"
local vn "${TOUR_INT}/__scratch_vn.dta"
local vr "${TOUR_INT}/__scratch_vr.dta"
foreach __scratch in "`tn'" "`tr'" "`vn'" "`vr'" {
    capture erase `"`__scratch'"'
}

use "${TOUR_INT}/01_tourists_nationality.dta", clear
keep reporter_area_code reporter_area_label partner_area_code partner_area_label year value ///
     flag flag_label unit notes source_file source_release_yyyymm `rescue_q' // RESCUE C12
rename reporter_area_label tn_reporter_label
rename partner_area_label  tn_partner_label
rename value       tourists_nat_k
rename flag        tourists_nat_flag
rename flag_label  tourists_nat_flag_label
rename notes       tourists_nat_notes
rename source_file tourists_nat_source_file
rename source_release_yyyymm tourists_nat_release
rename unit tourists_nat_unit
capture rescue_on C12 // RESCUE C12 I-M2
local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
if `rescue_on_C12' rename pry_res_quarantine pry_res_quarantine_tn // RESCUE C12
save "`tn'", replace

use "${TOUR_INT}/01_tourists_residence.dta", clear
keep reporter_area_code reporter_area_label partner_area_code partner_area_label year value ///
     flag flag_label unit notes source_file source_release_yyyymm `rescue_q' // RESCUE C12
rename reporter_area_label tr_reporter_label
rename partner_area_label  tr_partner_label
rename value       tourists_res_k
rename flag        tourists_res_flag
rename flag_label  tourists_res_flag_label
rename notes       tourists_res_notes
rename source_file tourists_res_source_file
rename source_release_yyyymm tourists_res_release
rename unit tourists_res_unit
capture rescue_on C12 // RESCUE C12 I-M2
local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
if `rescue_on_C12' rename pry_res_quarantine pry_res_quarantine_tr // RESCUE C12
save "`tr'", replace

use "${TOUR_INT}/01_visitors_nationality.dta", clear
keep reporter_area_code reporter_area_label partner_area_code partner_area_label year value ///
     flag flag_label unit notes source_file source_release_yyyymm `rescue_q' // RESCUE C12
rename reporter_area_label vn_reporter_label
rename partner_area_label  vn_partner_label
rename value       visitors_nat_k
rename flag        visitors_nat_flag
rename flag_label  visitors_nat_flag_label
rename notes       visitors_nat_notes
rename source_file visitors_nat_source_file
rename source_release_yyyymm visitors_nat_release
rename unit visitors_nat_unit
capture rescue_on C12 // RESCUE C12 I-M2
local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
if `rescue_on_C12' rename pry_res_quarantine pry_res_quarantine_vn // RESCUE C12
save "`vn'", replace

use "${TOUR_INT}/01_visitors_residence.dta", clear
keep reporter_area_code reporter_area_label partner_area_code partner_area_label year value ///
     flag flag_label unit notes source_file source_release_yyyymm `rescue_q' // RESCUE C12
rename reporter_area_label vr_reporter_label
rename partner_area_label  vr_partner_label
rename value       visitors_res_k
rename flag        visitors_res_flag
rename flag_label  visitors_res_flag_label
rename notes       visitors_res_notes
rename source_file visitors_res_source_file
rename source_release_yyyymm visitors_res_release
rename unit visitors_res_unit
capture rescue_on C12 // RESCUE C12 I-M2
local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
if `rescue_on_C12' rename pry_res_quarantine pry_res_quarantine_vr // RESCUE C12
save "`vr'", replace

use "`tn'", clear
merge 1:1 reporter_area_code partner_area_code year using "`tr'", nogen
merge 1:1 reporter_area_code partner_area_code year using "`vn'", nogen
merge 1:1 reporter_area_code partner_area_code year using "`vr'", nogen
isid reporter_area_code partner_area_code year

capture rescue_on C12 // RESCUE C12 I-M2
local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
if `rescue_on_C12' { // RESCUE C12
    egen byte pry_res_quarantine = rowmax(pry_res_quarantine_tn pry_res_quarantine_tr pry_res_quarantine_vn pry_res_quarantine_vr) // RESCUE C12: installed [D] egen rowmax()
    drop pry_res_quarantine_tn pry_res_quarantine_tr pry_res_quarantine_vn pry_res_quarantine_vr // RESCUE C12
    label variable pry_res_quarantine "PRY residence cell quarantined; original nationality fallback retained" // RESCUE C12
} // RESCUE C12
* Coalesce human-readable labels; keep component labels for validation.
gen str120 reporter_area_label = tr_reporter_label
replace reporter_area_label = tn_reporter_label if reporter_area_label==""
replace reporter_area_label = vr_reporter_label if reporter_area_label==""
replace reporter_area_label = vn_reporter_label if reporter_area_label==""

gen str160 partner_area_label = tr_partner_label
replace partner_area_label = tn_partner_label if partner_area_label==""
replace partner_area_label = vr_partner_label if partner_area_label==""
replace partner_area_label = vn_partner_label if partner_area_label==""

* Audit label inconsistencies rather than silently treating them as identical.
gen byte reporter_label_conflict = 0
foreach v in tn_reporter_label tr_reporter_label vn_reporter_label vr_reporter_label {
    replace reporter_label_conflict = 1 if `v'!="" & reporter_area_label!="" & `v'!=reporter_area_label
}
gen byte partner_label_conflict = 0
foreach v in tn_partner_label tr_partner_label vn_partner_label vr_partner_label {
    replace partner_label_conflict = 1 if `v'!="" & partner_area_label!="" & `v'!=partner_area_label
}

capture frame drop __audit_label_conflicts
frame copy default __audit_label_conflicts, replace
frame __audit_label_conflicts: keep if reporter_label_conflict | partner_label_conflict
frame __audit_label_conflicts: export delimited using "${TOUR_DIAG}/label_conflicts.csv", replace
frame drop __audit_label_conflicts

* Explicit source-direction labels.
label variable reporter_area_code  "UN Tourism reporter area code = tourism destination"
label variable reporter_area_label "UN Tourism reporter area = tourism destination"
label variable partner_area_code   "UN Tourism partner area code = tourism origin"
label variable partner_area_label  "UN Tourism partner area = tourism origin"

sort reporter_area_code partner_area_code year
foreach __v in tourists_nat_k tourists_res_k visitors_nat_k visitors_res_k {
    capture recast double `__v'
}
save "${TOUR_INT}/02_source_wide_four_series.dta", replace

noi di as result "VALIDATION_LAYER_2_FOUR_SERIES_MERGE=PASS"

* ======================================================================================
* 4. LAYER 3 -- RESIDENCE-FIRST CONSTRUCTION + FULL SOURCE PROVENANCE
* ======================================================================================

* Count how many classification bases exist for each construct.
egen byte tourists_sources_n = rownonmiss(tourists_res_k tourists_nat_k)
egen byte visitors_sources_n = rownonmiss(visitors_res_k visitors_nat_k)
gen byte tourists_both_bases = tourists_sources_n==2
gen byte visitors_both_bases = visitors_sources_n==2

* Residence-first: source units remain thousand trips.
gen double tourists_k = tourists_res_k
replace tourists_k = tourists_nat_k if missing(tourists_k)
gen str11 tourists_basis = cond(!missing(tourists_res_k),"residence", ///
                            cond(!missing(tourists_nat_k),"nationality",""))

gen double visitors_k = visitors_res_k
replace visitors_k = visitors_nat_k if missing(visitors_k)
gen str11 visitors_basis = cond(!missing(visitors_res_k),"residence", ///
                            cond(!missing(visitors_nat_k),"nationality",""))

* Prove the residence-first rule mechanically.
assert tourists_k == tourists_res_k if !missing(tourists_res_k)
assert tourists_k == tourists_nat_k if missing(tourists_res_k) & !missing(tourists_nat_k)
assert visitors_k == visitors_res_k if !missing(visitors_res_k)
assert visitors_k == visitors_nat_k if missing(visitors_res_k) & !missing(visitors_nat_k)
assert tourists_basis=="residence" if !missing(tourists_res_k)
assert tourists_basis=="nationality" if missing(tourists_res_k) & !missing(tourists_nat_k)
assert visitors_basis=="residence" if !missing(visitors_res_k)
assert visitors_basis=="nationality" if missing(visitors_res_k) & !missing(visitors_nat_k)

* Selected-source metadata: every final value keeps a direct pointer to its source workbook.
gen str100 tourists_source_file = tourists_res_source_file
replace tourists_source_file = tourists_nat_source_file if tourists_basis=="nationality"
gen str12 tourists_flag = tourists_res_flag
replace tourists_flag = tourists_nat_flag if tourists_basis=="nationality"
gen str100 tourists_flag_label = tourists_res_flag_label
replace tourists_flag_label = tourists_nat_flag_label if tourists_basis=="nationality"
gen strL tourists_notes = tourists_res_notes
replace tourists_notes = tourists_nat_notes if tourists_basis=="nationality"
gen str6 tourists_release = tourists_res_release
replace tourists_release = tourists_nat_release if tourists_basis=="nationality"

gen str100 visitors_source_file = visitors_res_source_file
replace visitors_source_file = visitors_nat_source_file if visitors_basis=="nationality"
gen str12 visitors_flag = visitors_res_flag
replace visitors_flag = visitors_nat_flag if visitors_basis=="nationality"
gen str100 visitors_flag_label = visitors_res_flag_label
replace visitors_flag_label = visitors_nat_flag_label if visitors_basis=="nationality"
gen strL visitors_notes = visitors_res_notes
replace visitors_notes = visitors_nat_notes if visitors_basis=="nationality"
gen str6 visitors_release = visitors_res_release
replace visitors_release = visitors_nat_release if visitors_basis=="nationality"

assert tourists_source_file!="" if !missing(tourists_k)
assert visitors_source_file!="" if !missing(visitors_k)

* Convert source-unit thousand trips to trips; deliberately retain double precision.
gen double tourists_trips = tourists_k*1000 if !missing(tourists_k)
gen double visitors_trips = visitors_k*1000 if !missing(visitors_k)

label variable tourists_k "Overnight tourists, residence-first, thousand trips"
label variable visitors_k "Total visitors, residence-first, thousand trips"
label variable tourists_trips "Overnight tourists, residence-first, trips (not rounded)"
label variable visitors_trips "Total visitors, residence-first, trips (not rounded)"
label variable tourists_basis "Selected classification basis for tourists"
label variable visitors_basis "Selected classification basis for visitors"

* Overlap diagnostics: when both bases are present, residence remains the selected source.
gen double tourists_res_minus_nat_k = tourists_res_k-tourists_nat_k if tourists_both_bases
gen double visitors_res_minus_nat_k = visitors_res_k-visitors_nat_k if visitors_both_bases

capture frame drop __audit_overlap
frame copy default __audit_overlap, replace
frame __audit_overlap: keep if tourists_both_bases | visitors_both_bases
frame __audit_overlap: keep reporter_area_code reporter_area_label partner_area_code partner_area_label year ///
     tourists_res_k tourists_nat_k tourists_res_minus_nat_k tourists_basis ///
     visitors_res_k visitors_nat_k visitors_res_minus_nat_k visitors_basis ///
     tourists_res_source_file tourists_nat_source_file ///
     visitors_res_source_file visitors_nat_source_file
frame __audit_overlap: sort reporter_area_code partner_area_code year
frame __audit_overlap: export delimited using "${TOUR_DIAG}/residence_nationality_overlap.csv", replace
frame drop __audit_overlap

noi di as result "VALIDATION_LAYER_3_RESIDENCE_FIRST=PASS"

* ======================================================================================
* 5. LAYER 4 -- SOURCE/CONSTRUCT ANOMALY AUDIT
* ======================================================================================

* Visitors should conceptually contain overnight tourists only when the two selected series
* are sufficiently comparable. We therefore distinguish same-basis and mixed-basis cases.
gen byte both_constructs_present = !missing(tourists_k,visitors_k)
gen byte basis_mismatch = both_constructs_present & tourists_basis!=visitors_basis
gen byte same_basis = both_constructs_present & tourists_basis==visitors_basis

gen byte hierarchy_violation = both_constructs_present & tourists_k>visitors_k
gen double hierarchy_gap_k = tourists_k-visitors_k if hierarchy_violation
gen double hierarchy_ratio = tourists_k/visitors_k if hierarchy_violation & visitors_k>0

* Source metadata potentially explains a hierarchy issue.
gen byte tourists_has_metadata = tourists_flag!="" | tourists_flag_label!="" | tourists_notes!=""
gen byte visitors_has_metadata = visitors_flag!="" | visitors_flag_label!="" | visitors_notes!=""
gen byte hierarchy_has_metadata = hierarchy_violation & (tourists_has_metadata | visitors_has_metadata)

* Definition-difference indicators from selected visitor source.
gen byte visitors_definition_diff = ///
    strpos(lower(visitors_flag_label),"definition differs")>0 | ///
    strpos(lower(visitors_notes),"definition differs")>0 | ///
    strpos(lower(visitors_notes),"overnight visitors")>0 | ///
    strpos(lower(visitors_notes),"same-day visitors")>0

* Classification of hierarchy audit status.
gen str40 hierarchy_audit_class = ""
replace hierarchy_audit_class = "mixed_basis_not_directly_nested" ///
    if hierarchy_violation & basis_mismatch
replace hierarchy_audit_class = "same_basis_with_source_metadata" ///
    if hierarchy_violation & same_basis & hierarchy_has_metadata
replace hierarchy_audit_class = "same_basis_unexplained_source_native" ///
    if hierarchy_violation & same_basis & !hierarchy_has_metadata

* Precision audit. Fractional converted trips can be inherited from a source reported in
* thousand trips; they are not automatically errors and are never rounded here.
gen byte tourists_fractional_trip = !missing(tourists_trips) & ///
    abs(tourists_trips-round(tourists_trips,1))>1e-8
gen byte visitors_fractional_trip = !missing(visitors_trips) & ///
    abs(visitors_trips-round(visitors_trips,1))>1e-8

* All selected rows carrying any flag/note, useful for manual source inspection.
gen byte selected_metadata_any = tourists_has_metadata | visitors_has_metadata

* Export audit files with enough provenance to open the exact original Excel workbook.
local audit_keep ///
    reporter_area_code reporter_area_label partner_area_code partner_area_label year ///
    tourists_k visitors_k tourists_trips visitors_trips ///
    tourists_basis visitors_basis basis_mismatch same_basis ///
    hierarchy_violation hierarchy_gap_k hierarchy_ratio hierarchy_audit_class ///
    tourists_source_file tourists_flag tourists_flag_label tourists_notes tourists_release ///
    visitors_source_file visitors_flag visitors_flag_label visitors_notes visitors_release ///
    visitors_definition_diff

capture frame drop __audit_hier_all
frame copy default __audit_hier_all, replace
frame __audit_hier_all: keep if hierarchy_violation
frame __audit_hier_all: keep `audit_keep'
frame __audit_hier_all: sort reporter_area_code year partner_area_code
frame __audit_hier_all: save "${TOUR_DIAG}/hierarchy_violations_all.dta", replace
frame __audit_hier_all: export delimited using "${TOUR_DIAG}/hierarchy_violations_all.csv", replace
frame drop __audit_hier_all

capture frame drop __audit_hier_mixed
frame copy default __audit_hier_mixed, replace
frame __audit_hier_mixed: keep if hierarchy_violation & basis_mismatch
frame __audit_hier_mixed: keep `audit_keep'
frame __audit_hier_mixed: sort reporter_area_code year partner_area_code
frame __audit_hier_mixed: export delimited using "${TOUR_DIAG}/hierarchy_violations_mixed_basis.csv", replace
frame drop __audit_hier_mixed

capture frame drop __audit_hier_same
frame copy default __audit_hier_same, replace
frame __audit_hier_same: keep if hierarchy_violation & same_basis
frame __audit_hier_same: keep `audit_keep'
frame __audit_hier_same: sort reporter_area_code year partner_area_code
frame __audit_hier_same: export delimited using "${TOUR_DIAG}/hierarchy_violations_same_basis.csv", replace
frame drop __audit_hier_same

capture frame drop __audit_hier_same_meta
frame copy default __audit_hier_same_meta, replace
frame __audit_hier_same_meta: keep if hierarchy_violation & same_basis & hierarchy_has_metadata
frame __audit_hier_same_meta: keep `audit_keep'
frame __audit_hier_same_meta: sort reporter_area_code year partner_area_code
frame __audit_hier_same_meta: export delimited using "${TOUR_DIAG}/hierarchy_same_basis_with_metadata.csv", replace
frame drop __audit_hier_same_meta

capture frame drop __audit_hier_same_unexpl
frame copy default __audit_hier_same_unexpl, replace
frame __audit_hier_same_unexpl: keep if hierarchy_violation & same_basis & !hierarchy_has_metadata
frame __audit_hier_same_unexpl: keep `audit_keep'
frame __audit_hier_same_unexpl: sort reporter_area_code year partner_area_code
frame __audit_hier_same_unexpl: export delimited using "${TOUR_DIAG}/hierarchy_same_basis_unexplained.csv", replace
frame drop __audit_hier_same_unexpl

capture frame drop __audit_defdiff
frame copy default __audit_defdiff, replace
frame __audit_defdiff: keep if visitors_definition_diff
frame __audit_defdiff: keep reporter_area_code reporter_area_label partner_area_code partner_area_label year ///
     visitors_k visitors_trips visitors_basis visitors_source_file ///
     visitors_flag visitors_flag_label visitors_notes visitors_release ///
     tourists_k tourists_basis tourists_source_file
frame __audit_defdiff: sort reporter_area_code year partner_area_code
frame __audit_defdiff: export delimited using "${TOUR_DIAG}/selected_visitors_definition_diff.csv", replace
frame drop __audit_defdiff

capture frame drop __audit_fractional
frame copy default __audit_fractional, replace
frame __audit_fractional: keep if tourists_fractional_trip | visitors_fractional_trip
frame __audit_fractional: keep reporter_area_code reporter_area_label partner_area_code partner_area_label year ///
     tourists_k tourists_trips tourists_fractional_trip tourists_basis tourists_source_file ///
     visitors_k visitors_trips visitors_fractional_trip visitors_basis visitors_source_file
frame __audit_fractional: sort reporter_area_code year partner_area_code
frame __audit_fractional: export delimited using "${TOUR_DIAG}/fractional_trip_precision_audit.csv", replace
frame drop __audit_fractional

capture frame drop __audit_metadata
frame copy default __audit_metadata, replace
frame __audit_metadata: keep if selected_metadata_any
frame __audit_metadata: keep reporter_area_code reporter_area_label partner_area_code partner_area_label year ///
     tourists_k tourists_basis tourists_source_file tourists_flag tourists_flag_label tourists_notes ///
     visitors_k visitors_basis visitors_source_file visitors_flag visitors_flag_label visitors_notes
frame __audit_metadata: sort reporter_area_code year partner_area_code
frame __audit_metadata: export delimited using "${TOUR_DIAG}/all_selected_source_flags_notes.csv", replace
frame drop __audit_metadata

noi di as result "VALIDATION_LAYER_4_ANOMALY_AUDIT=PASS"

* ======================================================================================
* 6. LAYER 5 -- SAVE REPRODUCIBLE FINAL DATABASES
* ======================================================================================

* Keep component series as well as residence-first final variables. This makes every
* selected value auditable without returning to an opaque derived dataset.
order reporter_area_code reporter_area_label partner_area_code partner_area_label year ///
      tourists_k tourists_trips tourists_basis ///
      visitors_k visitors_trips visitors_basis ///
      tourists_res_k tourists_nat_k visitors_res_k visitors_nat_k ///
      tourists_source_file visitors_source_file ///
      tourists_flag tourists_flag_label tourists_notes ///
      visitors_flag visitors_flag_label visitors_notes ///
      tourists_release visitors_release ///
      tourists_sources_n visitors_sources_n tourists_both_bases visitors_both_bases ///
      basis_mismatch same_basis hierarchy_violation hierarchy_audit_class ///
      visitors_definition_diff tourists_fractional_trip visitors_fractional_trip

capture rescue_on C11b // RESCUE C11b I-M2
local rescue_on_C11b = (_rc==0 & r(on)==1) // RESCUE C11b I-M2
local rescue_c11b = `rescue_on_C11b' // RESCUE C11b
capture rescue_on C11c // RESCUE C11c I-M2
local rescue_on_C11c = (_rc==0 & r(on)==1) // RESCUE C11c I-M2
if `rescue_c11b' | `rescue_on_C11c' { // RESCUE C11b C11c
    do "${ROOT}/02_code/99_rescue/I-M/source_flags.do" // RESCUE C11b C11c
} // RESCUE C11b C11c

isid reporter_area_code partner_area_code year
sort reporter_area_code partner_area_code year
foreach __v in tourists_k visitors_k tourists_trips visitors_trips ///
              tourists_res_k tourists_nat_k visitors_res_k visitors_nat_k {
    capture recast double `__v'
}
save "${TOUR_FINAL}/tourism_residence_first_full.dta", replace

capture frame drop __analysis_window
frame copy default __analysis_window, replace
frame __analysis_window: keep if inrange(year,${ANALYSIS_START},${ANALYSIS_END})
frame __analysis_window: isid reporter_area_code partner_area_code year
frame __analysis_window: save "${TOUR_FINAL}/tourism_residence_first_${ANALYSIS_START}_${ANALYSIS_END}.dta", replace
frame drop __analysis_window

noi di as result "VALIDATION_LAYER_5_FINAL_DATABASE=PASS"

* ======================================================================================
* 7. LAYER 6 -- MACHINE-READABLE VALIDATION SUMMARY + DATA DICTIONARY
* ======================================================================================

* Validation counts are descriptive checks, not automatic deletion rules.
quietly count
local N_all = r(N)
quietly count if inrange(year,${ANALYSIS_START},${ANALYSIS_END})
local N_window = r(N)
quietly count if !missing(tourists_k)
local N_tour = r(N)
quietly count if !missing(visitors_k)
local N_vis = r(N)
quietly count if tourists_basis=="residence"
local N_tour_R = r(N)
quietly count if tourists_basis=="nationality"
local N_tour_N = r(N)
quietly count if visitors_basis=="residence"
local N_vis_R = r(N)
quietly count if visitors_basis=="nationality"
local N_vis_N = r(N)
quietly count if both_constructs_present
local N_both = r(N)
quietly count if basis_mismatch
local N_basis_mismatch = r(N)
quietly count if hierarchy_violation
local N_hier = r(N)
quietly count if hierarchy_violation & basis_mismatch
local N_hier_mixed = r(N)
quietly count if hierarchy_violation & same_basis
local N_hier_same = r(N)
quietly count if hierarchy_violation & same_basis & hierarchy_has_metadata
local N_hier_same_meta = r(N)
quietly count if hierarchy_violation & same_basis & !hierarchy_has_metadata
local N_hier_same_unexpl = r(N)
quietly count if visitors_definition_diff
local N_defdiff = r(N)
quietly count if tourists_fractional_trip
local N_frac_tour = r(N)
quietly count if visitors_fractional_trip
local N_frac_vis = r(N)
quietly count if tourists_both_bases
local N_both_tour_basis = r(N)
quietly count if visitors_both_bases
local N_both_vis_basis = r(N)

* Stata variable names are limited to 32 characters. The compact srcfiles_* names
* below deliberately stay within that limit while preserving machine-readable meaning.
capture frame drop __validation_summary
frame create __validation_summary
frame __validation_summary: set obs 1
frame __validation_summary: gen long srcfiles_tourists_nationality = `f_tn'
frame __validation_summary: gen long source_files_tourists_residence   = `f_tr'
frame __validation_summary: gen long srcfiles_visitors_nationality = `f_vn'
frame __validation_summary: gen long source_files_visitors_residence   = `f_vr'
frame __validation_summary: gen long source_rows_tourists_nationality  = `r_tn'
frame __validation_summary: gen long source_rows_tourists_residence    = `r_tr'
frame __validation_summary: gen long source_rows_visitors_nationality  = `r_vn'
frame __validation_summary: gen long source_rows_visitors_residence    = `r_vr'
frame __validation_summary: gen long final_country_pair_year_rows       = `N_all'
frame __validation_summary: gen long analysis_window_rows               = `N_window'
frame __validation_summary: gen long tourists_nonmissing                = `N_tour'
frame __validation_summary: gen long visitors_nonmissing                = `N_vis'
frame __validation_summary: gen long tourists_selected_residence        = `N_tour_R'
frame __validation_summary: gen long tourists_selected_nationality      = `N_tour_N'
frame __validation_summary: gen long visitors_selected_residence        = `N_vis_R'
frame __validation_summary: gen long visitors_selected_nationality      = `N_vis_N'
frame __validation_summary: gen long tourists_both_bases_available      = `N_both_tour_basis'
frame __validation_summary: gen long visitors_both_bases_available      = `N_both_vis_basis'
frame __validation_summary: gen long tourist_visitor_both_present       = `N_both'
frame __validation_summary: gen long tourist_visitor_basis_mismatch     = `N_basis_mismatch'
frame __validation_summary: gen long hierarchy_violations_total         = `N_hier'
frame __validation_summary: gen long hierarchy_violations_mixed_basis   = `N_hier_mixed'
frame __validation_summary: gen long hierarchy_violations_same_basis    = `N_hier_same'
frame __validation_summary: gen long same_basis_with_metadata           = `N_hier_same_meta'
frame __validation_summary: gen long same_basis_unexplained             = `N_hier_same_unexpl'
frame __validation_summary: gen long selected_visitor_definition_diff   = `N_defdiff'
frame __validation_summary: gen long fractional_trip_tourists            = `N_frac_tour'
frame __validation_summary: gen long fractional_trip_visitors            = `N_frac_vis'
frame __validation_summary: save "${TOUR_DIAG}/validation_summary.dta", replace
frame __validation_summary: export delimited using "${TOUR_DIAG}/validation_summary.csv", replace
frame drop __validation_summary

* Compact machine-readable data dictionary for the final constructed measures.
capture frame drop __data_dictionary
frame create __data_dictionary
frame __data_dictionary: input str32 variable str90 definition str24 unit str20 construction
"reporter_area_code"  "UN Tourism reporter code; tourism destination" "source area code" "source field"
"partner_area_code"   "UN Tourism partner code; tourism origin" "source area code" "source field"
"year"                "Calendar year" "year" "source field"
"tourists_res_k"      "Overnight tourists classified by residence" "thousand trips" "raw source"
"tourists_nat_k"      "Overnight tourists classified by nationality" "thousand trips" "raw source"
"visitors_res_k"      "Total visitors classified by residence" "thousand trips" "raw source"
"visitors_nat_k"      "Total visitors classified by nationality" "thousand trips" "raw source"
"tourists_k"          "Overnight tourists; residence-first, nationality fallback" "thousand trips" "residence-first"
"visitors_k"          "Total visitors; residence-first, nationality fallback" "thousand trips" "residence-first"
"tourists_trips"      "tourists_k multiplied by 1000; not rounded" "trips" "derived"
"visitors_trips"      "Total visitors; residence-first, nationality fallback, multiplied by 1000; not rounded" "trips" "derived"
"tourists_basis"      "Classification basis selected for tourists" "residence/nationality" "provenance"
"visitors_basis"      "Classification basis selected for visitors" "residence/nationality" "provenance"
"hierarchy_violation" "1 when selected tourists exceed selected visitors" "indicator" "audit only"
"visitors_definition_diff" "1 when selected visitor metadata flags a definition difference" "indicator" "audit only"
end
capture rescue_on C11b // RESCUE C11b I-M2
local rescue_on_C11b = (_rc==0 & r(on)==1) // RESCUE C11b I-M2
if `rescue_on_C11b' { // RESCUE C11b
    frame __data_dictionary: replace definition = subinstr(definition,"Total visitors","Visitor-series arrivals (mixed coverage)",.) if substr(variable,1,8)=="visitors" // RESCUE C11b
} // RESCUE C11b
frame __data_dictionary: export delimited using "${TOUR_DIAG}/data_dictionary.csv", replace
frame drop __data_dictionary

* Re-open final database and record Stata's data signature in the log.
use "${TOUR_FINAL}/tourism_residence_first_full.dta", clear
isid reporter_area_code partner_area_code year
datasignature

* Completion sentinel for automated/package checks.
file open sentinel using "${TOUR_DIAG}/BUILD_COMPLETE.txt", write replace text
file write sentinel "UN_TOURISM_REPRODUCIBLE_BUILD_COMPLETE=yes" _n
file write sentinel "analysis_window=${ANALYSIS_START}-${ANALYSIS_END}" _n
file write sentinel "residence_first_rule=residence_else_nationality" _n
file write sentinel "source_unit=thousand_trips" _n
file close sentinel


* Clean explicit scratch files created only to avoid dependence on Stata's temp directory.
foreach __scratch in ///
    "${TOUR_INT}/__scratch_manifest_all.dta" ///
    "${TOUR_INT}/__scratch_source_long.dta" ///
    "${TOUR_INT}/__scratch_tn.dta" ///
    "${TOUR_INT}/__scratch_tr.dta" ///
    "${TOUR_INT}/__scratch_vn.dta" ///
    "${TOUR_INT}/__scratch_vr.dta" {
    capture erase `"`__scratch'"'
}

noi di as result "VALIDATION_LAYER_6_SUMMARY_AND_DICTIONARY=PASS"
noi di as text "============================================================"
noi di as result "UN_TOURISM_REPRODUCIBLE_BUILD_COMPLETE=yes"
noi di as text "Final full database:"
noi di as text "  ${TOUR_FINAL}/tourism_residence_first_full.dta"
noi di as text "Analysis-window database:"
noi di as text "  ${TOUR_FINAL}/tourism_residence_first_${ANALYSIS_START}_${ANALYSIS_END}.dta"
noi di as text "Audit folder:"
noi di as text "  ${TOUR_DIAG}"
noi di as text "============================================================"

log close
