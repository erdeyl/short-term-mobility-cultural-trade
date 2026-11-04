version 18.0
clear all
set more off
args PROJECT_ROOT MODE
if `"`PROJECT_ROOT'"' == "" {
    local PROJECT_ROOT : environment REPLICATION_ROOT
}
if `"`PROJECT_ROOT'"' == "" {
    display as error "Run the chapter BAT entry point or supply the project root."
    exit 198
}
local PROJECT_ROOT = subinstr(`"`PROJECT_ROOT'"', "\", "/", .)

capture log close _all
log using "`PROJECT_ROOT'/05_output/03_Mobility/03_logs/check_stata_environment.log", replace text
local ENV_STATATMP : environment STATATMP
display as text "Configured STATATMP: `ENV_STATATMP'"
display as text "Actual Stata tmpdir: " c(tmpdir)

* Test Stata itself after launch, including save/readback and preserve/restore.
clear
set obs 1
generate long temp_check = 1
tempfile stata_write_test
capture noisily save "`stata_write_test'", replace
if _rc {
    display as error "Stata cannot write its temporary file: `stata_write_test'"
    display as error "Start this chapter through its BAT file, which sets STATATMP before launching Stata."
    log close
    exit 603
}
use "`stata_write_test'", clear
assert temp_check == 1
preserve
replace temp_check = 2
restore
assert temp_check == 1
display as result "STATA_TEMPFILE_READ_WRITE=PASS"

if "`MODE'" == "empirical" {
    foreach command in ftools reghdfe ppmlhdfe esttab eststo estadd estpost hdfe gtools frmttable ppml_fe_bias {
        capture which `command'
        if _rc {
            display as error "Missing Stata command: `command'"
            display as error "Run INSTALL_STATA_PACKAGES.bat in this chapter, then rerun."
            log close
            exit 199
        }
        display as text "COMMAND_AVAILABLE=`command' PATH=`r(fn)'"
    }

    capture findfile lrowmat_utils.mlib
    if _rc {
        display as error "Missing rowmat_utils. Run INSTALL_STATA_PACKAGES.bat."
        log close
        exit 601
    }

}
display as result "STATA_ENVIRONMENT=PASS"
log close
file open checked using "`PROJECT_ROOT'/05_output/03_Mobility/01_diagnostics/STATA_ENVIRONMENT_COMPLETE.txt", write replace
file write checked "STATA_ENVIRONMENT=PASS" _n
file close checked
