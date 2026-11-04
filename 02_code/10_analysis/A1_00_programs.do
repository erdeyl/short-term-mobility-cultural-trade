/*******************************************************************************
 A1_00_programs.do  --  shared programs for analysis block block A1 (2026-11-03)
 Called by the A1_* do-files after 00_config.do. Defines programs only.

 Help files consulted (installed versions): ppmlhdfe.sthlp 2.3.4 (absorb(),
 vce(cluster), e(N_full), e(num_singletons), e(num_separated), e(converged),
 e(sample)); [P] postfile; [R] test; [R] lincom; nflow.sthlp 1.0.1.
 Reporting checklist: the authors' ppmlhdfe reporting notes ("Report N_full and N,
 singleton/FE-drop and separated counts ... e(converged)").
 Stacked equality design: PKG/02_code/02_empirical_run/02_sensitivity/
 02_formal_equality_visitors_tourists.do lines 112-199 (expand, block-specific
 copies of all three FE, cluster by the original pair id, reproduce separate
 slopes to 1e-6 before testing).
*******************************************************************************/

global FE "exporter_year importer_year pair_id"

* ---------------------------------------------------------------- results file
capture program drop A1_open
program define A1_open
    args fname
    capture mkdir "${OUT}/results"
    capture mkdir "${OUT}/results/A1_parts"
    capture mkdir "${OUT}/tables"
    global A1PART "${OUT}/results/A1_parts/`fname'"
    capture postclose A1post
    postfile A1post str90 row_id str10 vintage str4 block str6 item str60 spec str60 sample ///
        str6 mobility str40 term double(b se p ci_lo ci_hi N N_full n_singletons n_separated n_clusters) ///
        str24 cluster_var str244 note using "${A1PART}.dta", replace
end

capture program drop A1_close
program define A1_close
    postclose A1post
    preserve
        use "${A1PART}.dta", clear
        format b se p ci_lo ci_hi %24.17g
        format N N_full n_singletons n_separated n_clusters %12.0f
        export delimited using "${A1PART}.csv", replace datafmt
    restore
end

* ---------------------------------------------------------------- one coefficient row
capture program drop A1_post1
program define A1_post1
    syntax , item(string) spec(string) sample(string) mobility(string) term(string) [note(string)]
    local rid "`item'.`spec'.`mobility'.`term'"
    capture local b = _b[`term']
    if _rc {
        post A1post ("`rid'") ("${VINTAGE}") ("A1") ("`item'") ("`spec'") ("`sample'") ("`mobility'") ("`term'") ///
            (.) (.) (.) (.) (.) (e(N)) (e(N_full)) (e(num_singletons)) (e(num_separated)) (e(N_clust)) ("`e(clustvar)'") ///
            ("TERM NOT IN e(b); `note'")
        exit
    }
    local se = _se[`term']
    if `se' == 0 | missing(`se') {
        post A1post ("`rid'") ("${VINTAGE}") ("A1") ("`item'") ("`spec'") ("`sample'") ("`mobility'") ("`term'") ///
            (.) (.) (.) (.) (.) (e(N)) (e(N_full)) (e(num_singletons)) (e(num_separated)) (e(N_clust)) ("`e(clustvar)'") ///
            ("TERM OMITTED (se=0, collinear); `note'")
        exit
    }
    local z = `b' / `se'
    local p = 2 * normal(-abs(`z'))
    local lo = `b' - invnormal(0.975) * `se'
    local hi = `b' + invnormal(0.975) * `se'
    post A1post ("`rid'") ("${VINTAGE}") ("A1") ("`item'") ("`spec'") ("`sample'") ("`mobility'") ("`term'") ///
        (`b') (`se') (`p') (`lo') (`hi') (e(N)) (e(N_full)) (e(num_singletons)) (e(num_separated)) (e(N_clust)) ///
        ("`e(clustvar)'") ("`note'")
end

* ---------------------------------------------------------------- after a ppmlhdfe fit
* usage:  capture noisily ppmlhdfe ...
*         A1_after, rc(`=_rc') item() spec() sample() mobility() terms() [gen(newvar) note()]
capture program drop A1_after
program define A1_after, rclass
    syntax , item(string) spec(string) sample(string) mobility(string) terms(string) ///
        [rc(integer 0) gen(name) note(string)]
    return scalar ok = 0
    if `rc' != 0 | e(converged) != 1 {
        local why = cond(`rc' != 0, "FAILED rc=`rc'", "FAILED e(converged)!=1")
        foreach t of local terms {
            post A1post ("`item'.`spec'.`mobility'.`t'") ("${VINTAGE}") ("A1") ("`item'") ("`spec'") ("`sample'") ///
                ("`mobility'") ("`t'") (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) ("") ("`why'; `note'")
        }
        display as error "A1_FAIL item=`item' spec=`spec' mobility=`mobility' `why'"
        if "`gen'" != "" gen byte `gen' = 0
        exit
    }
    assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
    foreach t of local terms {
        A1_post1, item(`item') spec(`spec') sample(`sample') mobility(`mobility') term(`t') note(`note')
    }
    display as result "A1_FIT item=`item' spec=`spec' mob=`mobility' N=" e(N) " N_full=" e(N_full) ///
        " sing=" e(num_singletons) " sep=" e(num_separated) " clusters=" e(N_clust) " conv=" e(converged)
    if "`gen'" != "" gen byte `gen' = e(sample)
    nflow est "A1 `item' `spec' `mobility'"
    return scalar ok = 1
end

* ---------------------------------------------------------------- a test row (statistic in b, df in se, p in p)
capture program drop A1_posttest
program define A1_posttest
    syntax , item(string) spec(string) sample(string) mobility(string) term(string) stat(string) df(string) p(string) ///
        [nobs(string) nfull(string) ncl(string) clv(string) note(string)]
    foreach v in stat df p nobs nfull ncl {
        local `v'_n = real("``v''")
    }
    post A1post ("`item'.`spec'.`mobility'.`term'") ("${VINTAGE}") ("A1") ("`item'") ("`spec'") ("`sample'") ///
        ("`mobility'") ("`term'") (`stat_n') (`df_n') (`p_n') (.) (.) (`nobs_n') (`nfull_n') (.) (.) (`ncl_n') ("`clv'") ("`note'")
end

* ---------------------------------------------------------------- a difference row from lincom
capture program drop A1_postlincom
program define A1_postlincom
    syntax , item(string) spec(string) sample(string) mobility(string) term(string) [note(string)]
    * uses r() of the lincom just run and e() of the model
    local d = r(estimate)
    local s = r(se)
    local p = 2 * normal(-abs(`d' / `s'))
    post A1post ("`item'.`spec'.`mobility'.`term'") ("${VINTAGE}") ("A1") ("`item'") ("`spec'") ("`sample'") ///
        ("`mobility'") ("`term'") (`d') (`s') (`p') (`d' - invnormal(.975) * `s') (`d' + invnormal(.975) * `s') ///
        (e(N)) (e(N_full)) (e(num_singletons)) (e(num_separated)) (e(N_clust)) ("`e(clustvar)'") ("lincom; `note'")
end

* ---------------------------------------------------------------- stacked equality test of one slope across two blocks
* Authors' design (02_formal_equality_visitors_tourists.do:112-199). Blocks may be disjoint
* (restricted vs complement) or identical observations (two measures on the same rows).
* Each block: separate fit of y on x with the three FE on its candidate rows; the stacked
* model uses the separate fits' e(sample), block-specific copies of the three FE, and
* clusters by the original id in cl() (default pair_id). The stacked slopes must reproduce
* the separate slopes to 1e-6 (authors' line 183) before the Wald test is run. Pass 1 uses
* the ppmlhdfe default convergence tolerance; if the 1e-6 check fails only for numerical
* reasons, pass 2 refits all three models with tolerance(1e-11) itol(1e-12) (ppmlhdfe help,
* Optimization: tolerance(#); itol(#) via reghdfe options). Same specification and sample.
capture program drop A1_stack
program define A1_stack
    syntax , y1(varname) x1(varname) s1(varname) y2(varname) x2(varname) s2(varname) ///
        item(string) spec(string) mobility(string) [cl(name) lab1(string) lab2(string) note(string) sample(string)]
    if "`cl'" == "" local cl pair_id
    if "`lab1'" == "" local lab1 "block1"
    if "`lab2'" == "" local lab2 "block2"
    if "`sample'" == "" local sample "stacked"
    tempvar e1 e2
    tempname E1 E2
    local passed 0
    local usedpass 0
    forvalues pass = 1/2 {
        local usedpass `pass'
        local tolopt ""
        if `pass' == 2 local tolopt "tolerance(1e-11) itol(1e-12)"
        capture drop `e1' `e2'
        capture noisily ppmlhdfe `y1' `x1' if `s1', absorb(${FE}) vce(cluster `cl') `tolopt'
        local rc1 = _rc
        if `rc1' == 0 & e(converged) != 1 local rc1 430
        if `rc1' != 0 {
            A1_after, rc(`rc1') item(`item') spec(`spec'_sep_`lab1') sample(`lab1') mobility(`mobility') terms(`x1') note("pass `pass'; rc 430 = not converged; `note'")
            A1_posttest, item(`item') spec(`spec'_test) sample(`sample') mobility(`mobility') term(`lab1'_eq_`lab2') ///
                stat(.) df(.) p(.) note("NOT RUN: separate fit `lab1' failed (pass `pass')")
            exit
        }
        assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
        estimates store `E1'
        gen byte `e1' = e(sample)
        local b1 = _b[`x1']
        local n1 = e(N)
        nflow est "A1 `item' `spec' separate `lab1' pass `pass' (immediate record, audit R1-10)"
        capture noisily ppmlhdfe `y2' `x2' if `s2', absorb(${FE}) vce(cluster `cl') `tolopt'
        local rc2 = _rc
        if `rc2' == 0 & e(converged) != 1 local rc2 430
        if `rc2' != 0 {
            estimates restore `E1'
            A1_after, item(`item') spec(`spec'_sep_`lab1') sample(`lab1') mobility(`mobility') terms(`x1') note("pass `pass'; `note'")
            A1_after, rc(`rc2') item(`item') spec(`spec'_sep_`lab2') sample(`lab2') mobility(`mobility') terms(`x2') note("pass `pass'; rc 430 = not converged; `note'")
            A1_posttest, item(`item') spec(`spec'_test) sample(`sample') mobility(`mobility') term(`lab1'_eq_`lab2') ///
                stat(.) df(.) p(.) note("NOT RUN: separate fit `lab2' failed (pass `pass')")
            exit
        }
        assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
        estimates store `E2'
        gen byte `e2' = e(sample)
        local b2 = _b[`x2']
        local n2 = e(N)
        nflow est "A1 `item' `spec' separate `lab2' pass `pass' (immediate record, audit R1-10)"
        local stok 0
        preserve
            keep if `e1' | `e2'
            nflow step "A1_stack `item' `spec' pass `pass': keep rows in either separate e(sample)"
            keep year iso3_o iso3_d exporter_year importer_year pair_id unordered_pair_id `y1' `x1' `y2' `x2' `e1' `e2'
            gen long __rid = _n
            expand 2
            nflow step "A1_stack `item' `spec' pass `pass': expand 2 (one copy per block)"
            bysort __rid: gen byte __block = _n
            drop if (__block == 1 & !`e1') | (__block == 2 & !`e2')
            nflow step "A1_stack `item' `spec' pass `pass': keep block copies inside their own e(sample)"
            quietly count
            assert r(N) == `n1' + `n2'
            gen double __y = cond(__block == 1, `y1', `y2')
            gen double __x1 = cond(__block == 1, `x1', 0)
            gen double __x2 = cond(__block == 2, `x2', 0)
            egen long __ey = group(exporter_year __block)
            egen long __iy = group(importer_year __block)
            egen long __pp = group(pair_id __block)
            capture noisily ppmlhdfe __y __x1 __x2, absorb(__ey __iy __pp) vce(cluster `cl') `tolopt'
            local rcs = _rc
            if `rcs' == 0 & e(converged) != 1 local rcs 430
            if `rcs' == 0 {
                local stok 1
                assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
                nflow est "A1 `item' `spec' stacked pass `pass'"
                local g1 = abs(_b[__x1] - `b1')
                local g2 = abs(_b[__x2] - `b2')
                local nst = e(N)
                if `g1' <= 1e-6 & `g2' <= 1e-6 & `nst' == `n1' + `n2' local passed 1
                if `nst' == `n1' + `n2' {
                    local sN = e(N)
                    local sNf = e(N_full)
                    local sS = e(num_singletons)
                    local sP = e(num_separated)
                    local sC = e(N_clust)
                    local sCv "`e(clustvar)'"
                    forvalues k = 1/2 {
                        local sb`k' = _b[__x`k']
                        local ss`k' = _se[__x`k']
                    }
                    quietly test __x1 = __x2
                    local chi2 = r(chi2)
                    local df = r(df)
                    local pp = r(p)
                    quietly lincom __x1 - __x2
                    local dd = r(estimate)
                    local ds = r(se)
                }
            }
        restore
        nflow step "A1_stack `item' `spec' pass `pass': restore"
        if !`stok' {
            estimates restore `E1'
            A1_after, item(`item') spec(`spec'_sep_`lab1') sample(`lab1') mobility(`mobility') terms(`x1') note("pass `pass'; `note'")
            estimates restore `E2'
            A1_after, item(`item') spec(`spec'_sep_`lab2') sample(`lab2') mobility(`mobility') terms(`x2') note("pass `pass'; `note'")
            A1_posttest, item(`item') spec(`spec'_test) sample(`sample') mobility(`mobility') term(`lab1'_eq_`lab2') ///
                stat(.) df(.) p(.) note("FAILED stacked fit rc=`rcs' (pass `pass')")
            exit
        }
        if `passed' continue, break
        display as text "A1_STACK pass `pass' reproduction gaps `g1' `g2' (N `nst' vs `n1'+`n2')"
    }
    local tolnote = cond(`usedpass' == 1, "default tolerance", "tolerance(1e-11) itol(1e-12) after pass-1 gap > 1e-6")
    estimates restore `E1'
    A1_after, item(`item') spec(`spec'_sep_`lab1') sample(`lab1') mobility(`mobility') terms(`x1') note("`tolnote'; `note'")
    estimates restore `E2'
    A1_after, item(`item') spec(`spec'_sep_`lab2') sample(`lab2') mobility(`mobility') terms(`x2') note("`tolnote'; `note'")
    local sfx ""
    if !`passed' {
        A1_posttest, item(`item') spec(`spec'_test) sample(`sample') mobility(`mobility') term(`lab1'_eq_`lab2') ///
            stat(.) df(.) p(.) nobs(`nst') note("NOT TESTED: stacked slopes do not reproduce separate fits to 1e-6 after both passes (gaps `g1' `g2'; N `nst' vs `n1'+`n2')")
        if `nst' != `n1' + `n2' | max(`g1', `g2') > 1e-4 exit
        * information only: the stacked results of pass 2 with the gap stated (authors' 1e-6 check not met)
        local sfx "_unverified"
        local tolnote "`tolnote'; REPRODUCTION GAP > 1e-6 (authors' threshold): information only"
    }
    local zc = invnormal(0.975)
    forvalues k = 1/2 {
        local lb = cond(`k' == 1, "`lab1'", "`lab2'")
        local gk = cond(`k' == 1, `g1', `g2')
        post A1post ("`item'.`spec'_stk`sfx'.`mobility'.__x`k'") ("${VINTAGE}") ("A1") ("`item'") ("`spec'_stk`sfx'") ("`sample'") ///
            ("`mobility'") ("__x`k'") (`sb`k'') (`ss`k'') (2 * normal(-abs(`sb`k'' / `ss`k''))) (`sb`k'' - `zc' * `ss`k'') ///
            (`sb`k'' + `zc' * `ss`k'') (`sN') (`sNf') (`sS') (`sP') (`sC') ("`sCv'") ("stacked slope `lb'; repro gap `gk'; `tolnote'")
    }
    A1_posttest, item(`item') spec(`spec'_test`sfx') sample(`sample') mobility(`mobility') term(`lab1'_eq_`lab2') ///
        stat(`chi2') df(`df') p(`pp') nobs(`sN') nfull(`sNf') ncl(`sC') clv(`sCv') ///
        note("Wald chi2 H0 b_`lab1'=b_`lab2'; stacked PPML, block-specific FE; N1=`n1' N2=`n2'; `tolnote'")
    post A1post ("`item'.`spec'_diff`sfx'.`mobility'.`lab1'_minus_`lab2'") ("${VINTAGE}") ("A1") ("`item'") ("`spec'_diff`sfx'") ("`sample'") ///
        ("`mobility'") ("`lab1'_minus_`lab2'") (`dd') (`ds') (2 * normal(-abs(`dd' / `ds'))) (`dd' - `zc' * `ds') (`dd' + `zc' * `ds') ///
        (`sN') (`sNf') (`sS') (`sP') (`sC') ("`sCv'") ("lincom on stacked model`sfx'")
    display as result "A1_STACK item=`item' spec=`spec' mob=`mobility' b1=`b1' b2=`b2' chi2=`chi2' p=`pp' N1=`n1' N2=`n2' cl=`cl' pass=`usedpass'"
end
