/*******************************************************************************
 check_stata_packages.do -- verifies the Stata version and the exact package versions of the tested setup.
 Run by run_all.py (stage check). Stops with r(459) if a command is missing or a version differs, unless the
 environment variable PKG_ALLOW_VERSION_DIFF is 1 (then differences are listed and the run continues).
 Help consulted: require.sthlp 1.3.1 (require package == version), [R] which, [P] file, [P] creturn (c(sysdir_plus)).
*******************************************************************************/
version 18
set more off
local fail 0
local allow : environment PKG_ALLOW_VERSION_DIFF
display as result "STATA version " c(stata_version) " edition `c(edition_real)' born `c(born_date)' os `c(os)'"
if c(stata_version) < 18 {
    display as error "PKG_CHECK Stata 18 or newer is required"
    local fail 1
}
* 1. commands and Mata libraries
foreach c in ftools reghdfe ppmlhdfe ppml_fe_bias gtools require esttab estout eststo estadd estpost hdfe frmttable ///
    did_multiplegt_dyn whichdidshouldiuse did_had lprobust distinct nflow rescue_on {
    capture which `c'
    if _rc {
        display as error "PKG_MISSING command `c'"
        local fail 1
    }
}
foreach f in lftools.mlib ppmlhdfe.mata lrowmat_utils.mlib {
    capture findfile `f'
    if _rc {
        display as error "PKG_MISSING file `f'"
        local fail 1
    }
}
* 2. exact versions from the star-bang lines (require)
local vdiff 0
foreach spec in "ftools 2.50.0" "reghdfe 6.14.1" "ppmlhdfe 2.3.4" "gtools 1.10.1" "require 1.3.1" "estout 3.33" "whichdidshouldiuse 1.0.0" "nflow 1.0.1" {
    gettoken p v : spec
    local v = strtrim("`v'")
    capture noisily require `p' == `v'
    if _rc {
        display as error "PKG_VERSION `p': tested `v', installed version differs or cannot be read (rc " _rc ")"
        local vdiff 1
    }
    else display as result "PKG_OK `p' == `v'"
}
* 3. packages without a version line: Distribution-Date in stata.trk (PLUS)
local trk "`c(sysdir_plus)'stata.trk"
capture confirm file "`trk'"
if _rc {
    display as error "PKG_CHECK stata.trk not found in `c(sysdir_plus)'"
    local vdiff 1
}
else {
    foreach spec in "ppml_fe_bias 20210306" "hdfe 20160806" "outreg 20150918" "rowmat_utils 20140815" "moremata 20260111" ///
        "did_multiplegt_dyn 20260629" "did_had 20240824" "distinct 20120321" "nprobust 20260517" {
        gettoken p d : spec
        local d = strtrim("`d'")
        local found ""
        local in 0
        tempname fh
        file open `fh' using "`trk'", read text
        file read `fh' line
        while r(eof) == 0 {
            if substr(`"`macval(line)'"', 1, 2) == "N " local in = (`"`macval(line)'"' == "N `p'.pkg")
            if `in' & strpos(`"`macval(line)'"', "Distribution-Date:") {
                local found = strtrim(substr(`"`macval(line)'"', strpos(`"`macval(line)'"', ":") + 1, .))
            }
            file read `fh' line
        }
        file close `fh'
        if "`found'" == "`d'" display as result "PKG_OK `p' Distribution-Date `d'"
        else {
            display as error "PKG_VERSION `p': tested Distribution-Date `d', installed [`found']"
            local vdiff 1
        }
    }
}
if `vdiff' & "`allow'" != "1" local fail 1
if `vdiff' & "`allow'" == "1" display as text "PKG_CHECK version differences accepted (PKG_ALLOW_VERSION_DIFF=1)"
if `fail' {
    display as error "PKG_CHECK=FAIL (install: python3 run_all.py --install-stata-packages; README.md, Software)"
    exit 459
}
display as result "PKG_CHECK=PASS"
