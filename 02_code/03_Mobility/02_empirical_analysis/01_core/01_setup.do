/*******************************************************************************
 Fail-closed dependency, file, and schema gate.
*******************************************************************************/

version 18.0
capture confirm file "${DATA_FILE}"
if _rc {
    display as error "INPUT_DATA_MISSING=${DATA_FILE}"
    exit 601
}

foreach command in ftools reghdfe ppmlhdfe eststo esttab estpost {
    capture which `command'
    if _rc {
        display as error "REQUIRED_COMMAND_MISSING=`command'"
        display as error "Run 02_code/03_Mobility/INSTALL_STATA_PACKAGES.bat and rerun."
        exit 199
    }
    display as text "COMMAND_AVAILABLE=`command' PATH=`r(fn)'"
}

quietly use "${DATA_FILE}", clear

local required year iso3_o iso3_d tourists visitors v_ttl_k ///
    v_3706_k v_49_k v_8523_k v_97_k ///
    ln_dist contig comlang_off comcol col45 comrelig cul_dist fta_wto

foreach variable of local required {
    capture confirm variable `variable'
    if _rc {
        display as error "REQUIRED_VARIABLE_MISSING=`variable'"
        exit 111
    }
}

capture isid year iso3_o iso3_d
if _rc {
    display as error "DYAD_YEAR_KEY_NOT_UNIQUE=yes"
    exit 459
}

quietly count
display as result "INPUT_ROWS=" r(N)
display as result "SETUP_COMPLETE=yes"
