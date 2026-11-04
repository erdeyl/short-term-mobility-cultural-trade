/*******************************************************************************
 A2_1.do -- item A2.1 bilateral vs directional (R1.3, R2.13; R1.5b)
 (a) zeros/near-zeros and reverse-share distribution; (b) PPML Frisch-Waugh-Lovell
 diagnostics; (c) one-step directed-pair cluster influence + refits; (d) directional
 models on zero-free / >=10-trip / never-zero samples; (e) composition specification;
 (f) exact directional equality p under directed and unordered-pair clustering.
 Baseline samples: s_base_vis, s_base_tour (= e(sample) of Table 2 cols 1 and 5).
 Specification (defaults): ppmlhdfe, absorb(exporter_year importer_year pair_id),
 vce(cluster pair_id). Help: ppmlhdfe.sthlp (d(newvar) mandatory before predict; predict
 mu / eta), reghdfe.sthlp (no indepvars allowed; aweights; residuals(newvar)),
 [P] matrix accum (iweights, noconstant), [R] lincom, [R] test.
 PPML-FWL logic: at the PPML solution the IRLS working variable z = eta + (y-mu)/mu
 satisfies b = (X~'WX~)^-1 X~'Wz with W = diag(mu) and X~ = X partialled on the three FE
 sets by WLS with weights mu (Correia, Guimaraes & Zylkin 2020, Stata Journal 20(1), IRLS
 with HDFE); one-step cluster influence b - b(-g) ~ (X~'WX~)^-1 X~_g'(y_g - mu_g).
*******************************************************************************/
args vintage
clear all
set more off
set varabbrev off
set linesize 200
version 18.0
do "00_config.do" `vintage'
version 18.0
do "A2_00_programs.do"
capture log close _all
log using "${LOGS}/A2_1_${VINTAGE}.log", text replace
display as result "A2_1_BEGIN vintage=${VINTAGE} " c(current_date) " " c(current_time)
use "${OUT}/A2_work.dta", clear
nflow start using "${OUT}/A2_nflow.csv", append
a2_open "${OUT}/results/A2_1.dta"
a2_topen "${OUT}/tables/A2_A2.1.dta"
local FE "exporter_year importer_year pair_id"
tempfile inflall
local inflfirst = 1

foreach m in vis tour {
    local smp "s_base_`m'"
    local mlab = cond("`m'" == "vis", "visitors", "tourists")
    quietly count if `smp'
    local N0 = r(N)

    *==========================================================================
    * (a) zeros and near-zeros; reverse share s = rev/(rev+same)
    *==========================================================================
    quietly count if `smp' & rev_`m'_raw == 0
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_rev_zero) value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'")
    quietly count if `smp' & same_`m'_raw == 0
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_same_zero) value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'")
    quietly count if `smp' & (rev_`m'_raw == 0 | same_`m'_raw == 0)
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_any_zero) value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'")
    quietly count if `smp' & rev_`m'_raw == 0 & same_`m'_raw == 0
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_both_zero) value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'")
    quietly count if `smp' & rev_`m'_raw < 10
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_rev_lt10) value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'; trips")
    quietly count if `smp' & same_`m'_raw < 10
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_same_lt10) value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'; trips")
    quietly count if `smp' & (rev_`m'_raw < 10 | same_`m'_raw < 10)
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_either_lt10) value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'; asinh(x)-log(2x) = 1/(4x^2) approx; at x=10 about 0.0025")
    * pairs ever with a directional zero (over has_both rows of the pair)
    tempvar zr anyz first
    gen byte `zr' = has_both_`m' & (rev_`m'_raw == 0 | same_`m'_raw == 0)
    bysort pair_id: egen byte anyz_`m' = max(`zr')
    label variable anyz_`m' "Pair has a directional zero in some year with both directions observed"
    quietly count if `smp' & anyz_`m'
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_rows_in_pairs_ever_zero) value(`=r(N)/`N0'') n(`N0') note("count=`r(N)'")
    bysort pair_id: gen byte `first' = _n == 1
    egen byte __insmp = max(`smp'), by(pair_id)
    quietly count if `first' & __insmp
    local npairs = r(N)
    quietly count if `first' & __insmp & anyz_`m'
    a2_tpost, item(A2.1a) table(zeros) sample(`smp') mobility(`mlab') stat(share_pairs_ever_zero) value(`=r(N)/`npairs'') n(`npairs') note("pairs with a zero=`r(N)'; N = directed pairs in sample")
    drop __insmp
    gen double sh_`m' = rev_`m'_raw / (rev_`m'_raw + same_`m'_raw) if `smp' & (rev_`m'_raw + same_`m'_raw) > 0
    label variable sh_`m' "Reverse share rev/(rev+same), `mlab'"
    quietly count if `smp' & missing(sh_`m')
    a2_tpost, item(A2.1a) table(reverse_share) sample(`smp') mobility(`mlab') stat(n_undefined_sum0) value(`r(N)') n(`N0')
    quietly summarize sh_`m' if `smp', detail
    local ns = r(N)
    foreach st in mean sd p1 p5 p10 p25 p50 p75 p90 p95 p99 min max {
        a2_tpost, item(A2.1a) table(reverse_share) sample(`smp') mobility(`mlab') stat(`st') value(`=r(`st')') n(`ns')
    }
    quietly count if `smp' & sh_`m' < 0.05
    a2_tpost, item(A2.1a) table(reverse_share) sample(`smp') mobility(`mlab') stat(share_s_lt_0.05) value(`=r(N)/`ns'') n(`ns') note("count=`r(N)'")
    quietly count if `smp' & sh_`m' > 0.95 & !missing(sh_`m')
    a2_tpost, item(A2.1a) table(reverse_share) sample(`smp') mobility(`mlab') stat(share_s_gt_0.95) value(`=r(N)/`ns'') n(`ns') note("count=`r(N)'")
    quietly count if `smp' & (sh_`m' < 0.05 | (sh_`m' > 0.95 & !missing(sh_`m')))
    a2_tpost, item(A2.1a) table(reverse_share) sample(`smp') mobility(`mlab') stat(share_s_outside_05_95) value(`=r(N)/`ns'') n(`ns') note("count=`r(N)'")
    * corr of the two raw directional IHS terms on the sample (descriptive)
    quietly correlate mob_rev_`m' mob_same_`m' if `smp'
    a2_tpost, item(A2.1a) table(raw_corr) sample(`smp') mobility(`mlab') stat(corr_mob_rev_same_raw) value(`=r(rho)') n(`=r(N)')

    *==========================================================================
    * (b) FWL diagnostics, bilateral model
    *==========================================================================
    quietly ppmlhdfe v_ttl_k mob_bilat_`m' if `smp', absorb(`FE') vce(cluster pair_id) d(dB_`m')
    a2_chk "A2.1b bilateral `mlab' on s_base"
    a2_post, item(A2.1b) spec(bilateral) sample(`smp') mobility(`mlab') term(mob_bilat_`m')
    local bB = _b[mob_bilat_`m']
    gen byte eB_`m' = e(sample)
    assert eB_`m' == `smp'
    estimates store B_`m'
    quietly predict double muB_`m' if eB_`m', mu
    quietly predict double etaB_`m' if eB_`m', eta
    gen double eB_res_`m' = v_ttl_k - muB_`m' if eB_`m'
    gen double zB_`m' = etaB_`m' + eB_res_`m' / muB_`m' if eB_`m'
    quietly reghdfe mob_bilat_`m' [aw=muB_`m'] if eB_`m', absorb(`FE') residuals(rB_`m') tolerance(1e-12)
    a2_chk "A2.1b reghdfe partialling mob_bilat `mlab' [aw=mu]"
    assert e(N) == `N0'
    quietly reghdfe mob_bilat_`m' if eB_`m', absorb(`FE') residuals(uB_`m') tolerance(1e-12)
    a2_chk "A2.1b reghdfe partialling mob_bilat `mlab' unweighted"
    assert e(N) == `N0'
    * weighted (PPML-relevant) and unweighted variance shares
    quietly summarize muB_`m' if eB_`m'
    local sw = r(sum)
    tempvar wx
    gen double `wx' = muB_`m' * mob_bilat_`m' if eB_`m'
    quietly summarize `wx'
    local xbw = r(sum) / `sw'
    quietly replace `wx' = muB_`m' * (mob_bilat_`m' - `xbw')^2 if eB_`m'
    quietly summarize `wx'
    local vraw_w = r(sum) / `sw'
    drop `wx'
    tempvar sq
    gen double `sq' = muB_`m' * rB_`m'^2 if eB_`m'
    quietly summarize `sq'
    local sumWr2 = r(sum)
    quietly summarize muB_`m' if eB_`m'
    local sumW = r(sum)
    local vres_w = `sumWr2' / `sumW'
    drop `sq'
    quietly summarize mob_bilat_`m' if eB_`m'
    local vraw_u = r(Var)
    quietly summarize uB_`m' if eB_`m'
    local vres_u = r(Var)
    a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_bilat_raw_var_w) value(`vraw_w') n(`N0') note("mu-weighted variance (weights = PPML mu, normalised)")
    a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_bilat_resid_var_w) value(`vres_w') n(`N0') note("mu-weighted variance of residual after WLS partialling on exporter-year, importer-year, pair FE")
    a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_bilat_resid_share_w) value(`=`vres_w'/`vraw_w'') n(`N0')
    a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_bilat_raw_var_u) value(`vraw_u') n(`N0') note("unweighted")
    a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_bilat_resid_var_u) value(`vres_u') n(`N0') note("unweighted OLS partialling")
    a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_bilat_resid_share_u) value(`=`vres_u'/`vraw_u'') n(`N0')
    * positive controls: score orthogonality and FWL reproduction of b
    tempname HB gB sB
    quietly matrix accum `HB' = rB_`m' if eB_`m' [iw=muB_`m'], noconstant
    quietly matrix vecaccum `gB' = zB_`m' rB_`m' if eB_`m' [iw=muB_`m'], noconstant
    quietly matrix vecaccum `sB' = eB_res_`m' rB_`m' if eB_`m', noconstant
    local bchk = `gB'[1,1] / `HB'[1,1]
    tempvar ab
    gen double `ab' = abs(rB_`m' * eB_res_`m') if eB_`m'
    quietly summarize `ab'
    local scale = r(sum)
    drop `ab'
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(bilat_b_ppmlhdfe) value(`bB') n(`N0')
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(bilat_b_fwl_working_var) value(`bchk') n(`N0') note("b = sum(mu*xres*z)/sum(mu*xres^2), z = eta + (y-mu)/mu")
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(bilat_score_sum_rel) value(`=`sB'[1,1]/`scale'') n(`N0') note("sum xres*(y-mu) / sum |xres*(y-mu)|; ~0 at the solution")
    display as result "A2_1_FWL_B `m' b=" %15.12f `bB' " fwl=" %15.12f `bchk' " score_rel=" `sB'[1,1]/`scale'
    assert abs(`bchk' - `bB') < 1e-4
    local HBinv = 1 / `HB'[1,1]

    *==========================================================================
    * (b) FWL diagnostics, joint directional model
    *==========================================================================
    quietly ppmlhdfe v_ttl_k mob_rev_`m' mob_same_`m' if `smp', absorb(`FE') vce(cluster pair_id) d(dJ_`m')
    a2_chk "A2.1b joint directional `mlab' on s_base"
    a2_post, item(A2.1b) spec(joint) sample(`smp') mobility(`mlab') term(mob_rev_`m')
    a2_post, item(A2.1b) spec(joint) sample(`smp') mobility(`mlab') term(mob_same_`m')
    local bJr = _b[mob_rev_`m']
    local bJs = _b[mob_same_`m']
    gen byte eJ_`m' = e(sample)
    quietly count if eJ_`m' != `smp'
    display as result "A2_1_JOINT_SAMPLE_DIFF_vs_base `m' = " r(N)
    quietly count if eJ_`m'
    local NJ = r(N)
    estimates store J_`m'
    quietly predict double muJ_`m' if eJ_`m', mu
    quietly predict double etaJ_`m' if eJ_`m', eta
    gen double eJ_res_`m' = v_ttl_k - muJ_`m' if eJ_`m'
    gen double zJ_`m' = etaJ_`m' + eJ_res_`m' / muJ_`m' if eJ_`m'
    foreach d in rev same {
        quietly reghdfe mob_`d'_`m' [aw=muJ_`m'] if eJ_`m', absorb(`FE') residuals(r`d'_`m') tolerance(1e-12)
        a2_chk "A2.1b reghdfe partialling mob_`d' `mlab' [aw=mu]"
        assert e(N) == `NJ'
        quietly reghdfe mob_`d'_`m' if eJ_`m', absorb(`FE') residuals(u`d'_`m') tolerance(1e-12)
        a2_chk "A2.1b reghdfe partialling mob_`d' `mlab' unweighted"
        quietly summarize muJ_`m' if eJ_`m'
        local sw = r(sum)
        tempvar wx
        gen double `wx' = muJ_`m' * mob_`d'_`m' if eJ_`m'
        quietly summarize `wx'
        local xbw = r(sum) / `sw'
        quietly replace `wx' = muJ_`m' * (mob_`d'_`m' - `xbw')^2 if eJ_`m'
        quietly summarize `wx'
        local vraw_w = r(sum) / `sw'
        drop `wx'
        tempvar sq
        gen double `sq' = muJ_`m' * r`d'_`m'^2 if eJ_`m'
        quietly summarize `sq'
        local s2 = r(sum)
        quietly summarize muJ_`m' if eJ_`m'
        local vres_w = `s2' / r(sum)
        drop `sq'
        quietly summarize mob_`d'_`m' if eJ_`m'
        local vraw_u = r(Var)
        quietly summarize u`d'_`m' if eJ_`m'
        local vres_u = r(Var)
        a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_`d'_raw_var_w) value(`vraw_w') n(`NJ') note("mu from the joint directional model")
        a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_`d'_resid_var_w) value(`vres_w') n(`NJ')
        a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_`d'_resid_share_w) value(`=`vres_w'/`vraw_w'') n(`NJ')
        a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_`d'_raw_var_u) value(`vraw_u') n(`NJ')
        a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_`d'_resid_var_u) value(`vres_u') n(`NJ')
        a2_tpost, item(A2.1b) table(fwl_variance) sample(`smp') mobility(`mlab') stat(mob_`d'_resid_share_u) value(`=`vres_u'/`vraw_u'') n(`NJ')
    }
    tempname HJ gJ sJ HJi bJc
    quietly matrix accum `HJ' = rrev_`m' rsame_`m' if eJ_`m' [iw=muJ_`m'], noconstant
    quietly matrix vecaccum `gJ' = zJ_`m' rrev_`m' rsame_`m' if eJ_`m' [iw=muJ_`m'], noconstant
    quietly matrix vecaccum `sJ' = eJ_res_`m' rrev_`m' rsame_`m' if eJ_`m', noconstant
    matrix `HJi' = invsym(`HJ')
    matrix `bJc' = `HJi' * `gJ''
    local rho_w = `HJ'[1,2] / sqrt(`HJ'[1,1] * `HJ'[2,2])
    quietly correlate urev_`m' usame_`m' if eJ_`m'
    local rho_u = r(rho)
    a2_tpost, item(A2.1b) table(fwl_collinearity) sample(`smp') mobility(`mlab') stat(corr_resid_rev_same_w) value(`rho_w') n(`NJ') note("mu-weighted correlation of FE-partialled mob_rev and mob_same")
    a2_tpost, item(A2.1b) table(fwl_collinearity) sample(`smp') mobility(`mlab') stat(vif_w) value(`=1/(1-`rho_w'^2)') n(`NJ') note("VIF = 1/(1-r^2), two regressors")
    a2_tpost, item(A2.1b) table(fwl_collinearity) sample(`smp') mobility(`mlab') stat(corr_resid_rev_same_u) value(`rho_u') n(`NJ') note("unweighted OLS partialling")
    a2_tpost, item(A2.1b) table(fwl_collinearity) sample(`smp') mobility(`mlab') stat(vif_u) value(`=1/(1-`rho_u'^2)') n(`NJ')
    tempvar ab
    gen double `ab' = abs(rrev_`m' * eJ_res_`m') + abs(rsame_`m' * eJ_res_`m') if eJ_`m'
    quietly summarize `ab'
    local scale = r(sum)
    drop `ab'
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(joint_b_rev_ppmlhdfe) value(`bJr') n(`NJ')
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(joint_b_rev_fwl) value(`=`bJc'[1,1]') n(`NJ')
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(joint_b_same_ppmlhdfe) value(`bJs') n(`NJ')
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(joint_b_same_fwl) value(`=`bJc'[2,1]') n(`NJ')
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(joint_score_sum_rel_rev) value(`=`sJ'[1,1]/`scale'') n(`NJ')
    a2_tpost, item(A2.1b) table(fwl_check) sample(`smp') mobility(`mlab') stat(joint_score_sum_rel_same) value(`=`sJ'[1,2]/`scale'') n(`NJ')
    display as result "A2_1_FWL_J `m' rev=" %15.12f `bJr' " fwl=" %15.12f `bJc'[1,1] " same=" %15.12f `bJs' " fwl=" %15.12f `bJc'[2,1] " rho_w=" `rho_w'
    assert abs(`bJc'[1,1] - `bJr') < 1e-4 & abs(`bJc'[2,1] - `bJs') < 1e-4

    *==========================================================================
    * (c) one-step directed-pair cluster influence
    *==========================================================================
    gen double scB_`m' = rB_`m' * eB_res_`m' if eB_`m'
    gen double scR_`m' = rrev_`m' * eJ_res_`m' if eJ_`m'
    gen double scS_`m' = rsame_`m' * eJ_res_`m' if eJ_`m'
    preserve
        keep if eB_`m' | eJ_`m'
        bysort pair_id: egen double gB = total(scB_`m')
        bysort pair_id: egen double gR = total(scR_`m')
        bysort pair_id: egen double gS = total(scS_`m')
        bysort pair_id: egen nobs = total(eB_`m')
        bysort pair_id: keep if _n == 1
        keep pair_id iso3_o iso3_d gB gR gS nobs
        gen double IF_bilat = `HBinv' * gB
        gen double IF_rev  = `HJi'[1,1] * gR + `HJi'[1,2] * gS
        gen double IF_same = `HJi'[2,1] * gR + `HJi'[2,2] * gS
        foreach c in bilat rev same {
            gen double aIF_`c' = abs(IF_`c')
            quietly summarize aIF_`c'
            gen double shIF_`c' = aIF_`c' / r(sum)
            gsort -aIF_`c' pair_id
            gen int rank_`c' = _n
        }
        tempfile inflm
        save `"`inflm'"'
        * long table of the top 10 per coefficient
        tempfile top
        local tfirst = 1
        foreach c in bilat rev same {
            use `"`inflm'"', clear
            keep if rank_`c' <= 10
            gen str12 mobility = "`mlab'"
            gen str8 coef = "`c'"
            gen str10 vintage = "${VINTAGE}"
            gen double IF = IF_`c'
            gen double share_abs_IF = shIF_`c'
            gen int rank = rank_`c'
            keep vintage mobility coef rank pair_id iso3_o iso3_d IF share_abs_IF nobs
            sort rank
            if `tfirst' == 0 append using `"`top'"'
            save `"`top'"', replace
            local tfirst = 0
        }
        if `inflfirst' == 0 append using `"`inflall'"'
        save `"`inflall'"', replace
        * locals of top pair ids
        use `"`inflm'"', clear
        foreach c in bilat rev same {
            foreach k in 1 5 10 {
                quietly levelsof pair_id if rank_`c' <= `k', local(L) separate(,)
                local top_`c'_`k' "`L'"
            }
            quietly summarize IF_`c' if rank_`c' == 1
            local if1_`c' = r(mean)
        }
    restore
    local inflfirst = 0
    * refits dropping the top 1, 5, 10 clusters
    foreach k in 1 5 10 {
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if `smp' & !inlist(pair_id, `top_bilat_`k''), absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.1c bilateral `mlab' drop top `k' influential pairs"
        a2_post, item(A2.1c) spec(bilateral_drop_top`k') sample(`smp') mobility(`mlab') term(mob_bilat_`m') note("dropped pair_id: `top_bilat_`k''")
        if `k' == 1 {
            local act = `bB' - _b[mob_bilat_`m']
            a2_postval, item(A2.1c) spec(bilateral_onestep_accuracy) sample(`smp') mobility(`mlab') label(b - b(-top1)) value(`act') note("actual change; one-step approximation IF = `if1_bilat'")
        }
        foreach c in rev same {
            quietly ppmlhdfe v_ttl_k mob_rev_`m' mob_same_`m' if `smp' & !inlist(pair_id, `top_`c'_`k''), absorb(`FE') vce(cluster pair_id)
            a2_chk "A2.1c joint `mlab' drop top `k' pairs ranked by |IF_`c'|"
            a2_post, item(A2.1c) spec(joint_drop_top`k'_by_`c') sample(`smp') mobility(`mlab') term(mob_rev_`m') note("dropped pair_id: `top_`c'_`k''")
            a2_post, item(A2.1c) spec(joint_drop_top`k'_by_`c') sample(`smp') mobility(`mlab') term(mob_same_`m') note("dropped pair_id: `top_`c'_`k''")
            if `k' == 1 {
                local bref = cond("`c'" == "rev", `bJr', `bJs')
                local act = `bref' - _b[mob_`c'_`m']
                a2_postval, item(A2.1c) spec(joint_onestep_accuracy_`c') sample(`smp') mobility(`mlab') label(b - b(-top1)) value(`act') note("actual change of mob_`c'; one-step approximation IF = `if1_`c''")
            }
        }
    }

    *==========================================================================
    * (d) directional models on restricted samples
    *==========================================================================
    gen byte rz0_`m' = rev_`m'_raw > 0 & same_`m'_raw > 0
    gen byte rz10_`m' = rev_`m'_raw >= 10 & same_`m'_raw >= 10 & !missing(rev_`m'_raw, same_`m'_raw)
    gen byte rzp_`m' = anyz_`m' == 0
    foreach r in none rz0 rz10 rzp {
        local cond "`smp'"
        if "`r'" != "none" local cond "`smp' & `r'_`m'"
        local rl = cond("`r'"=="none","none",cond("`r'"=="rz0","no directional zero in the pair-year",cond("`r'"=="rz10","both directions >= 10 trips","pair never has a directional zero")))
        quietly count if `cond'
        local nc = r(N)
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if `cond', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.1d bilateral `mlab' restriction `r'"
        a2_post, item(A2.1d) spec(`r'_bilateral) sample(`smp') mobility(`mlab') term(mob_bilat_`m') note("restriction: `rl'; candidate rows=`nc'")
        foreach d in rev same {
            quietly ppmlhdfe v_ttl_k mob_`d'_`m' if `cond', absorb(`FE') vce(cluster pair_id)
            a2_chk "A2.1d `d'-only `mlab' restriction `r'"
            a2_post, item(A2.1d) spec(`r'_`d'_only) sample(`smp') mobility(`mlab') term(mob_`d'_`m') note("restriction: `rl'; candidate rows=`nc'")
        }
        quietly ppmlhdfe v_ttl_k mob_rev_`m' mob_same_`m' if `cond', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.1d joint `mlab' restriction `r'"
        a2_post, item(A2.1d) spec(`r'_joint) sample(`smp') mobility(`mlab') term(mob_rev_`m') note("restriction: `rl'; candidate rows=`nc'")
        a2_post, item(A2.1d) spec(`r'_joint) sample(`smp') mobility(`mlab') term(mob_same_`m') note("restriction: `rl'; candidate rows=`nc'")
        a2_post, item(A2.1d) spec(`r'_joint) sample(`smp') mobility(`mlab') term(mob_rev_`m' - mob_same_`m') label(rev - same) note("restriction: `rl'")
        quietly test mob_rev_`m' = mob_same_`m'
        a2_posttest, item(A2.1d) spec(`r'_joint) sample(`smp') mobility(`mlab') label(test rev = same) chi2(`r(chi2)') df(`r(df)') p(`r(p)') note("restriction: `rl'")
    }

    *==========================================================================
    * (e) composition specification on identical observations
    *==========================================================================
    gen double dlt_`m' = mob_rev_`m' - mob_same_`m' if `smp'
    label variable dlt_`m' "mob_rev - mob_same (IHS difference), `mlab'"
    foreach c in sh dlt {
        gen byte cmp_`c'_`m' = `smp' & !missing(`c'_`m')
        a2_fix, touse(cmp_`c'_`m') models("v_ttl_k mob_bilat_`m' `c'_`m' ; v_ttl_k mob_bilat_`m'")
        local fixit = ${A2_FIX_IT}
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' `c'_`m' if cmp_`c'_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.1e composition `c' `mlab'"
        local ctxt = cond("`c'" == "sh", "s = rev/(rev+same)", "d = mob_rev - mob_same")
        a2_post, item(A2.1e) spec(composition_`c') sample(`smp' & common) mobility(`mlab') term(mob_bilat_`m') note("E[X]=exp(beta*mob_bilat + gamma*`ctxt' + FE); fixed-point iterations=`fixit'")
        a2_post, item(A2.1e) spec(composition_`c') sample(`smp' & common) mobility(`mlab') term(`c'_`m') label(gamma: `ctxt') note("fixed-point iterations=`fixit'")
        quietly test mob_bilat_`m' `c'_`m'
        a2_posttest, item(A2.1e) spec(composition_`c') sample(`smp' & common) mobility(`mlab') label(joint test beta = gamma = 0) chi2(`r(chi2)') df(`r(df)') p(`r(p)')
        quietly ppmlhdfe v_ttl_k mob_bilat_`m' if cmp_`c'_`m', absorb(`FE') vce(cluster pair_id)
        a2_chk "A2.1e bilateral on composition `c' rows `mlab'"
        a2_post, item(A2.1e) spec(bilateral_on_composition_`c'_sample) sample(`smp' & common) mobility(`mlab') term(mob_bilat_`m') note("bilateral model on the identical rows of composition_`c'")
    }

    *==========================================================================
    * (f) exact directional equality p, Table 2 specification (if has_both), two clusterings
    *==========================================================================
    foreach smpf in has_both_`m' `smp' {
        foreach cl in pair_id unordered_pair_id {
            quietly ppmlhdfe v_ttl_k mob_rev_`m' mob_same_`m' if `smpf', absorb(`FE') vce(cluster `cl')
            a2_chk "A2.1f joint `mlab' `smpf' cluster `cl'"
            a2_post, item(A2.1f) spec(joint_`cl') sample(`smpf') mobility(`mlab') term(mob_rev_`m')
            a2_post, item(A2.1f) spec(joint_`cl') sample(`smpf') mobility(`mlab') term(mob_same_`m')
            a2_post, item(A2.1f) spec(joint_`cl') sample(`smpf') mobility(`mlab') term(mob_rev_`m' - mob_same_`m') label(rev - same)
            quietly test mob_rev_`m' = mob_same_`m'
            local pp = r(p)
            a2_posttest, item(A2.1f) spec(joint_`cl') sample(`smpf') mobility(`mlab') label(test rev = same) chi2(`r(chi2)') df(`r(df)') p(`r(p)')
            display as result "A2_1F `m' `smpf' `cl' p=" %12.10f `pp' " clusters=" e(N_clust) " N=" e(N)
        }
    }
}

a2_close "${OUT}/results/A2_1.dta" "${OUT}/results/A2_1.csv"
a2_tclose "${OUT}/tables/A2_A2.1.dta" "${OUT}/tables/A2_A2.1.csv"
use `"`inflall'"', clear
format IF share_abs_IF %24.17g
export delimited using "${OUT}/tables/A2_A2.1c_influence.csv", datafmt replace
display as result "A2_1_DONE vintage=${VINTAGE} " c(current_time)
log close
