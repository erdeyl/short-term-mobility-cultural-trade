/*******************************************************************************
 02b_pc_programs.do -- harvesting programs for 02_positive_controls.do.
 Re-run after every original do-file that executes "clear all" (which drops programs).
 Reporting per the authors' ppmlhdfe reporting notes (checklist items 2-3) and the installed
 help: ppmlhdfe.sthlp / reghdfe.sthlp stored results e(N), e(N_full), e(num_singletons),
 e(num_separated), e(N_clustervars), e(N_clust), e(N_clust#), e(converged), e(ic),
 e(separation). Every fit must have e(converged)==1 (asserted); for ppmlhdfe the installed
 accounting N_full = N + num_singletons + num_separated is asserted.
*******************************************************************************/
capture program drop _hc
program define _hc
    * counts of the CURRENT e() into postfile handle `chandle'
    args chandle item est
    assert e(converged) == 1
    if "`e(cmd)'" == "ppmlhdfe" assert e(N_full) == e(N) + e(num_singletons) + e(num_separated)
    post `chandle' ("`item'") ("`est'") ("`e(cmd)'") (e(N)) (e(N_full)) (e(num_singletons)) (e(num_separated)) ///
        (e(N_clustervars)) (e(N_clust)) (e(N_clust1)) (e(N_clust2)) (e(converged)) (e(ic)) ("`e(separation)'")
end
capture program drop _hb
program define _hb
    * post b and se of one coefficient of a stored estimate under the esttab row label
    args handle tab col est var label
    quietly estimates restore `est'
    post `handle' ("`tab'.c`col'.`label'.b") (_b[`var']) ("b")
    post `handle' ("`tab'.c`col'.`label'.se") (_se[`var']) ("se")
end
capture program drop _hn
program define _hn
    * post N of a stored estimate and its estimator counts (asserting convergence)
    args handle chandle tab col est
    quietly estimates restore `est'
    post `handle' ("`tab'.c`col'.N.N") (e(N)) ("N")
    _hc `chandle' "`tab'.c`col'" "`est'"
end
global PC_COUNTS_SPEC "str40 item str16 est str12 cmd double N N_full num_singletons num_separated N_clustervars N_clust N_clust1 N_clust2 converged ic str24 separation"
