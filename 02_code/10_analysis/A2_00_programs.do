/*******************************************************************************
 A2_00_programs.do -- shared programs for block A2 (re-run after every `clear all`).

 Help files consulted (installed versions): ppmlhdfe.sthlp 2.3.4 (absorb(), vce(cluster),
 d(newvar) "mandatory if running predict afterwards", e(N_full) "number of observations,
 including dropped singleton and separated observations", e(num_singletons),
 e(num_separated), e(converged) "1 if converged"; singletons "dropped iteratively"),
 reghdfe.sthlp 6.14.1 ([indepvars] optional, weights, residuals(newvar)), [R] lincom
 (r(estimate) r(se) r(p) r(lb) r(ub)), [R] test (r(chi2) r(df) r(p)), [P] postfile,
 [M-5] order(). Reporting checklist (authors' ppmlhdfe notes): every ppmlhdfe fit
 asserts e(converged)==1 and N_full = N + num_singletons + num_separated (installed accounting).
*******************************************************************************/

* ---------------------------------------------------------------- results postfile
capture program drop a2_open
program define a2_open
    args file
    capture postclose A2H
    postfile A2H str10 vintage str3 block str8 item str64 spec str48 sample str12 mobility ///
        str80 term double(b se p ci_lo ci_hi N N_full n_singletons n_separated n_clusters) ///
        str20 cluster_var str244 note using "`file'", replace
end

capture program drop a2_close
program define a2_close
    * close the postfile and write the lossless CSV next to it (stat-dev data-result-contracts:
    * doubles %24.17g, export with datafmt)
    args dtafile csvfile
    postclose A2H
    preserve
        use "`dtafile'", clear
        format b se p ci_lo ci_hi N N_full n_singletons n_separated n_clusters %24.17g
        export delimited using "`csvfile'", datafmt replace
    restore
end

* ---------------------------------------------------------------- fit checks
capture program drop a2_chk
program define a2_chk
    * a2_chk ["label"]: asserts the ppmlhdfe accounting of the CURRENT e(); with a label it also
    * writes the nflow est record (nflow.sthlp: "Call nflow est right after the estimation").
    * Called with a label after EVERY fit in block A2 (audit check); called without a label
    * only as a guard inside the posting programs.
    args label
    if "`e(cmd)'" == "ppmlhdfe" {
        assert e(converged) == 1
        assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
    }
    if `"`label'"' != "" nflow est `"`label'"'
end

* (restore cannot be wrapped in a program: preserve/restore are scoped to the program level,
*  so callers write `restore' followed by `nflow step "restore: ..."' -- nflow.sthlp: "Log a
*  restore with nflow step too")

* ---------------------------------------------------------------- post a linear combination
capture program drop a2_post
program define a2_post
    syntax, item(string) spec(string) sample(string) mobility(string) term(string) ///
        [label(string) note(string) nuniq(real -1) level(real 95)]
    a2_chk
    local N = e(N)
    local stk ""
    if `nuniq' >= 0 {
        local N = `nuniq'
        local stk "stacked fit e(N)=`e(N)'; N = unique pair-years. ${A2_STACK_NOTE}"
    }
    local nf = .
    local ns = .
    local nsep = .
    if "`e(cmd)'" == "ppmlhdfe" {
        local nf = e(N_full)
        local ns = e(num_singletons)
        local nsep = e(num_separated)
    }
    if "`e(cmd)'" == "reghdfe" local ns = e(num_singletons)
    local ncl = e(N_clust)
    if missing(`ncl') local ncl = e(N_clust1)
    local cv "`e(clustvar)'"
    if "`label'" == "" local label "`term'"
    quietly lincom `term', level(`level')
    post A2H ("${VINTAGE}") ("A2") ("`item'") ("`spec'") ("`sample'") ("`mobility'") ("`label'") ///
        (r(estimate)) (r(se)) (r(p)) (r(lb)) (r(ub)) (`N') (`nf') (`ns') (`nsep') (`ncl') ("`cv'") ///
        (`"`stk'`note'"')
end

* ---------------------------------------------------------------- post a Wald test (b = chi2, se = df)
capture program drop a2_posttest
program define a2_posttest
    syntax, item(string) spec(string) sample(string) mobility(string) label(string) ///
        chi2(real) df(real) p(real) [note(string) nuniq(real -1)]
    a2_chk
    local N = e(N)
    local stk ""
    if `nuniq' >= 0 {
        local N = `nuniq'
        local stk "stacked fit e(N)=`e(N)'; N = unique pair-years. ${A2_STACK_NOTE}"
    }
    local nf = .
    local ns = .
    local nsep = .
    if "`e(cmd)'" == "ppmlhdfe" {
        local nf = e(N_full)
        local ns = e(num_singletons)
        local nsep = e(num_separated)
    }
    local ncl = e(N_clust)
    if missing(`ncl') local ncl = e(N_clust1)
    post A2H ("${VINTAGE}") ("A2") ("`item'") ("`spec'") ("`sample'") ("`mobility'") ("`label'") ///
        (`chi2') (`df') (`p') (.) (.) (`N') (`nf') (`ns') (`nsep') (`ncl') ("`e(clustvar)'") ///
        (`"Wald test: b = chi2, se = df, p = p. `stk'`note'"')
end

* ---------------------------------------------------------------- post a descriptive value
capture program drop a2_postval
program define a2_postval
    syntax, item(string) spec(string) sample(string) mobility(string) label(string) value(real) ///
        [N(real -1) note(string) se(real -999) p(real -999) lo(real -999) hi(real -999)]
    foreach s in se p lo hi {
        if ``s'' == -999 local `s' = .
    }
    local nn = cond(`n' >= 0, `n', .)
    post A2H ("${VINTAGE}") ("A2") ("`item'") ("`spec'") ("`sample'") ("`mobility'") ("`label'") ///
        (`value') (`se') (`p') (`lo') (`hi') (`nn') (.) (.) (.) (.) ("") (`"`note'"')
end

* ---------------------------------------------------------------- descriptive tables (long format)
capture program drop a2_topen
program define a2_topen
    args file
    capture postclose A2T
    postfile A2T str10 vintage str8 item str40 table str48 sample str12 mobility str60 stat ///
        double(value N) str200 note using "`file'", replace
end
capture program drop a2_tpost
program define a2_tpost
    syntax, item(string) table(string) sample(string) mobility(string) stat(string) value(real) ///
        [n(real -1) note(string)]
    local nn = cond(`n' >= 0, `n', .)
    post A2T ("${VINTAGE}") ("`item'") ("`table'") ("`sample'") ("`mobility'") ("`stat'") (`value') (`nn') (`"`note'"')
end
capture program drop a2_tclose
program define a2_tclose
    args dtafile csvfile
    postclose A2T
    preserve
        use "`dtafile'", clear
        format value N %24.17g
        export delimited using "`csvfile'", datafmt replace
    restore
end

* ---------------------------------------------------------------- Holm step-down adjustment
capture mata: mata drop a2_holm_m()
mata:
real colvector a2_holm_m(real colvector p)
{
    real scalar m, i
    real colvector o, adj, out
    m = rows(p)
    o = order(p, 1)
    adj = J(m, 1, .)
    for (i = 1; i <= m; i++) adj[i] = min((1, (m - i + 1) * p[o[i]]))
    for (i = 2; i <= m; i++) adj[i] = max((adj[i], adj[i - 1]))
    out = J(m, 1, .)
    out[o] = adj
    return(out)
}
end
capture program drop a2_holm
program define a2_holm, rclass
    * usage: a2_holm p1 p2 ... pm  -> r(h1) ... r(hm), r(m)
    local m : word count `0'
    tempname P H
    matrix `P' = J(`m', 1, .)
    forvalues i = 1/`m' {
        local v : word `i' of `0'
        matrix `P'[`i', 1] = `v'
    }
    mata: st_matrix("`H'", a2_holm_m(st_matrix("`P'")))
    forvalues i = 1/`m' {
        return scalar h`i' = `H'[`i', 1]
    }
    return scalar m = `m'
end

* ---------------------------------------------------------------- common-sample fixed point
capture program drop a2_fix
program define a2_fix
    * Intersect the realized e(sample) of several ppmlhdfe models until stable
    * (design of PKG 02_sensitivity/01_common_support_visitors_tourists.do:116-170 and
    * File S1 run_tests.do:59-69). models(): "depvar indepvars ; depvar indepvars ; ..."
    syntax, touse(varname) models(string asis) [fe(string) maxit(integer 20) cluster(name)]
    if "`fe'" == "" local fe "exporter_year importer_year pair_id"
    if "`cluster'" == "" local cluster "pair_id"
    local models = subinstr(`"`models'"', `"""', "", .)
    local it = 0
    local done = 0
    while `done' == 0 {
        local ++it
        if `it' > `maxit' {
            display as error "a2_fix: common sample did not converge in `maxit' iterations"
            exit 430
        }
        quietly count if `touse'
        local n0 = r(N)
        local rest "`models'"
        while "`rest'" != "" {
            gettoken m rest : rest, parse(";")
            if "`m'" == ";" continue
            quietly ppmlhdfe `m' if `touse', absorb(`fe') vce(cluster `cluster')
            a2_chk "a2_fix iteration `it': `m'"
            quietly replace `touse' = `touse' & e(sample)
        }
        quietly count if `touse'
        if r(N) == `n0' local done = 1
    }
    global A2_FIX_IT = `it'
    global A2_FIX_N = `n0'
end

* ---------------------------------------------------------------- stacked PPML with block FE
capture program drop a2_stack
program define a2_stack
    * Authors' stacked design (PKG 02_sensitivity/02_formal_equality_visitors_tourists.do:112-188):
    * K blocks on identical rows, block-specific copies of all three FE, cluster by an
    * original-row cluster id, and the stacked slopes must reproduce the separate fits to 1e-6.
    * ys(): K outcome variables; xs(): K regressor lists separated by ";" (same length m).
    * Leaves the STACKED data in memory (caller must preserve/restore). Regressors s<k>_<j>.
    syntax, touse(varname) ys(string) xs(string asis) cluster(name) [tol(real 1e-6) keepv(string)]
    local fe "exporter_year importer_year pair_id"
    local K : word count `ys'
    local xs = subinstr(`"`xs'"', `"""', "", .)
    local k = 0
    local rest "`xs'"
    while "`rest'" != "" {
        gettoken g rest : rest, parse(";")
        if "`g'" == ";" continue
        local ++k
        local x_`k' "`g'"
    }
    if `k' != `K' {
        display as error "a2_stack: `K' outcomes but `k' regressor groups"
        exit 198
    }
    local m : word count `x_1'
    quietly count if `touse'
    local nu = r(N)
    global A2_NUNIQ = `nu'
    forvalues k = 1/`K' {
        local y_`k' : word `k' of `ys'
        quietly ppmlhdfe `y_`k'' `x_`k'' if `touse', absorb(`fe') vce(cluster `cluster')
        a2_chk "a2_stack separate fit `k': `y_`k'' on `x_`k''"
        if e(N) != `nu' {
            display as error "a2_stack: separate fit `k' (`y_`k'' on `x_`k'') N=" e(N) " != rows `nu' (not a common sample)"
            exit 459
        }
        forvalues j = 1/`m' {
            local xv : word `j' of `x_`k''
            tempname sep_`k'_`j'
            scalar `sep_`k'_`j'' = _b[`xv']
        }
    }
    local allx ""
    forvalues k = 1/`K' {
        local allx "`allx' `x_`k''"
    }
    local ally : list uniq ys
    local allx : list uniq allx
    quietly keep if `touse'
    local kv "year iso3_o iso3_d exporter_year importer_year pair_id unordered_pair_id `cluster' `ally' `allx' `keepv'"
    local kv : list uniq kv
    keep `kv'
    nflow step "a2_stack: keep the `nu' common rows (inside caller's preserve)"
    quietly expand `K'
    nflow step "a2_stack: expand to `K' blocks"
    bysort year iso3_o iso3_d: gen byte __blk = _n
    quietly gen double __y = .
    forvalues k = 1/`K' {
        quietly replace __y = `y_`k'' if __blk == `k'
    }
    local sreg ""
    forvalues k = 1/`K' {
        forvalues j = 1/`m' {
            local xv : word `j' of `x_`k''
            quietly gen double s`k'_`j' = cond(__blk == `k', `xv', 0)
            local sreg "`sreg' s`k'_`j'"
        }
    }
    egen long __ey = group(exporter_year __blk)
    egen long __iy = group(importer_year __blk)
    egen long __pr = group(pair_id __blk)
    quietly ppmlhdfe __y `sreg', absorb(__ey __iy __pr) vce(cluster `cluster')
    a2_chk "a2_stack stacked fit: `K' blocks (`ys'), cluster `cluster'"
    if e(N) != `K' * `nu' {
        display as error "a2_stack: stacked N=" e(N) " != `K' x `nu'"
        exit 459
    }
    local maxgap = 0
    forvalues k = 1/`K' {
        forvalues j = 1/`m' {
            local gap = abs(_b[s`k'_`j'] - `sep_`k'_`j'')
            if `gap' > `maxgap' local maxgap = `gap'
        }
    }
    global A2_STACK_NOTE ""
    if `maxgap' > `tol' {
        * Default ppmlhdfe convergence (tolerance 1e-8 on the deviance; ppmlhdfe.sthlp) leaves
        * coefficient error near 1e-6. Refit the separate block models (block k of the stacked
        * data with the block-specific FE = the separate model on the same rows) and the stacked
        * model with tolerance(1e-11), then require the 1e-6 reproduction.
        local gap0 = `maxgap'
        forvalues k = 1/`K' {
            local sk ""
            forvalues j = 1/`m' {
                local sk "`sk' s`k'_`j'"
            }
            quietly ppmlhdfe __y `sk' if __blk == `k', absorb(__ey __iy __pr) vce(cluster `cluster') tolerance(1e-11)
            a2_chk "a2_stack separate block `k' refit, tolerance(1e-11)"
            forvalues j = 1/`m' {
                scalar `sep_`k'_`j'' = _b[s`k'_`j']
            }
        }
        quietly ppmlhdfe __y `sreg', absorb(__ey __iy __pr) vce(cluster `cluster') tolerance(1e-11)
        a2_chk "a2_stack stacked refit, tolerance(1e-11)"
        * After the refit the criterion is 1e-6 relative to max(1,|b|): on very small samples with
        * many zeros (e.g. 228-row film matched sample) the stacked and separate optima agree to
        * about 7e-7 of |b| ~ 2.2 for every tolerance tried (1e-8 ... 1e-11, itol to 1e-14;
        * a separate probe run), i.e. the likelihood is flat in b to that order.
        local maxgap = 0
        local maxrel = 0
        forvalues k = 1/`K' {
            forvalues j = 1/`m' {
                local gap = abs(_b[s`k'_`j'] - `sep_`k'_`j'')
                local rel = `gap' / max(1, abs(`sep_`k'_`j''))
                if `gap' > `maxgap' local maxgap = `gap'
                if `rel' > `maxrel' local maxrel = `rel'
            }
        }
        global A2_STACK_NOTE "default-tolerance reproduction gap `: display %9.3e `gap0''; separate and stacked fits refitted with tolerance(1e-11): gap `: display %9.3e `maxgap'', relative to max(1,|b|) `: display %9.3e `maxrel''. "
        local maxgap = `maxrel'
        if `maxgap' > `tol' {
            display as error "a2_stack: stacked slopes do not reproduce separate fits; max gap " `maxgap'
            exit 459
        }
    }
    global A2_STACK_GAP = `maxgap'
    global A2_STACK_N = e(N)
end
