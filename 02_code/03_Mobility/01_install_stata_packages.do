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
log using "`PROJECT_ROOT'/05_output/03_Mobility/03_logs/install_stata_packages.log", replace text

* Explicit installation entry point. Existing packages are kept.

capture which ftools
if _rc {
    ssc install ftools
}

capture which reghdfe
if _rc {
    ssc install reghdfe
}

capture which ppmlhdfe
if _rc {
    ssc install ppmlhdfe
}

capture which esttab
if _rc {
    ssc install estout
}

capture which hdfe
if _rc {
    ssc install hdfe
}

capture which gtools
if _rc {
    ssc install gtools
}

capture which frmttable
if _rc {
    ssc install outreg
}

capture which ppml_fe_bias
if _rc {
    ssc install ppml_fe_bias
}

capture findfile lrowmat_utils.mlib
if _rc {
    ssc install rowmat_utils
}

display as result "STATA_PACKAGE_INSTALL=PASS"
log close
file open installed using "`PROJECT_ROOT'/05_output/03_Mobility/01_diagnostics/STATA_PACKAGES_INSTALLED.txt", write replace
file write installed "STATA_PACKAGE_INSTALL=PASS" _n
file close installed
