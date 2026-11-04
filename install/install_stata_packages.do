/*******************************************************************************
 install_stata_packages.do -- installs the community-contributed Stata packages used by the package (network).
 Run once:  python3 run_all.py --install-stata-packages   (or: do install/install_stata_packages.do in Stata)
 Tested setup (README.md, Software): StataNow 19.5 MP; every do-file sets version 18.
 SSC keeps only the current release of a package, so exact pins are not possible there; GitHub packages are
 installed from the repositories the tested setup used. check_stata_packages.do then verifies the exact tested
 versions (star-bang lines via require, [R] which; Distribution-Date lines in stata.trk) and stops on a difference.
 Help consulted: [R] ssc, [R] net, require.sthlp 1.3.1, ftools.sthlp ("ftools, compile").
*******************************************************************************/
args root
if `"`root'"' == "" local root "`c(pwd)'/.."
version 18
set more off
* SSC
foreach p in ppml_fe_bias gtools require estout hdfe outreg moremata rowmat_utils did_multiplegt_dyn whichdidshouldiuse did_had distinct {
    ssc install `p', replace
}
* GitHub (source recorded in the tested installation's stata.trk: sergiocorreia/reghdfe, sergiocorreia/ppmlhdfe and
* nppackages/nprobust, branch master; the source of the tested ftools 2.50.0 is not recorded there)
net install ftools,   from("https://raw.githubusercontent.com/sergiocorreia/ftools/master/src/") replace
net install reghdfe,  from("https://raw.githubusercontent.com/sergiocorreia/reghdfe/master/src/") replace
net install ppmlhdfe, from("https://raw.githubusercontent.com/sergiocorreia/ppmlhdfe/master/src/") replace
net install nprobust, from("https://raw.githubusercontent.com/nppackages/nprobust/master/stata/") replace
capture noisily ftools, compile
* nflow 1.0.1 and the correction switch rescue_on are shipped in 02_code/99_rescue (run_all.py puts them on the adopath)
do `"`root'/install/check_stata_packages.do"'
