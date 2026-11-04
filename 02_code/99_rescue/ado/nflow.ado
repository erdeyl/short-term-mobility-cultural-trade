*! nflow 1.0.1 08oct2026  sample-size flow log: N with a reason at every data step, e(N) at each estimation
*! Idea: Scott Cunningham (re-implemented for L. Erdey)
program define nflow, rclass
	version 16
	gettoken sub 0 : 0, parse(" ,")
	if `"`sub'"' == "start"       nflow_start `0'
	else if `"`sub'"' == "step"   nflow_step `0'
	else if `"`sub'"' == "est"    nflow_est `0'
	else if `"`sub'"' == "report" nflow_report `0'
	else {
		di as err "nflow: subcommand must be start, step, est or report"
		exit 198
	}
	return add
end

program define nflow_start, rclass
	syntax using/ [, Expected(numlist max=1 integer >=0) REPLACE APPEND]
	if "`replace'" != "" & "`append'" != "" {
		di as err "nflow start: replace and append are mutually exclusive"
		exit 198
	}
	* store an absolute path, so a later cd does not move the log
	if !(inlist(substr(`"`using'"', 1, 1), "/", "~", "\") | regexm(`"`using'"', "^[A-Za-z]:")) {
		local using `"`c(pwd)'/`using'"'
	}
	capture confirm file `"`using'"'
	local exists = (_rc == 0)
	if `exists' & "`replace'`append'" == "" {
		di as err `"nflow start: `using' exists; specify replace (new log) or append (continue it)"'
		exit 602
	}
	tempname fh
	capture {
		if `exists' & "`append'" != "" {
			file open `fh' using `"`using'"', write append text
		}
		else {
			file open `fh' using `"`using'"', write replace text
			file write `fh' "date,time,kind,n_before,n_after,change,reason" _n
		}
		file close `fh'
	}
	if _rc {
		local rc = _rc
		capture file close `fh'
		di as err `"nflow: WARNING cannot create log `using' (r(`rc')); N is NOT being recorded"'
	}
	global NFLOW_file `"`using'"'
	global NFLOW_N = _N
	local src `"`c(filename)'"'
	if `"`src'"' == "" local src "data in memory"
	nflow_write start "" `=_N' `"start: `src'"'
	di as txt "nflow: log " as res `"`using'"' as txt ", start N = " as res %12.0fc _N
	if "`expected'" != "" {
		return scalar expected = `expected'
		return scalar mismatch = (_N != `expected')
		if _N != `expected' {
			di as err "nflow: WARNING start N = " _N " but expected(" `expected' ")"
			nflow_write note `=_N' `=_N' `"EXPECTED MISMATCH: expected `expected'"'
		}
	}
	return scalar N = _N
end

program define nflow_step, rclass
	nflow_text `0'
	local reason `"`r(text)'"'
	if `"`reason'"' == "" {
		di as err `"nflow step: a reason is required, e.g. nflow step "drop domestic flows""'
		exit 198
	}
	nflow_started
	local before = $NFLOW_N
	nflow_write step `before' `=_N' `"`reason'"'
	global NFLOW_N = _N
	di as txt "nflow: " as res %12.0fc `before' as txt " -> " as res %12.0fc _N as txt `"  `reason'"'
	return scalar change = _N - `before'
	return scalar N = _N
end

program define nflow_est, rclass
	nflow_text `0'
	local label `"`r(text)'"'
	nflow_started
	if `"`e(cmd)'"' == "" | missing(e(N)) {
		di as err "nflow est: no estimation results in memory"
		exit 301
	}
	if _N != $NFLOW_N {
		di as err "nflow: WARNING N changed from " $NFLOW_N " to " _N " without nflow step"
		nflow_write unlogged $NFLOW_N `=_N' "UNLOGGED CHANGE before estimation"
		global NFLOW_N = _N
	}
	local cmd `"`e(cmd)'"'
	if `"`label'"' != "" local label `"`label' | "'
	nflow_write est `=_N' `=e(N)' `"`label'`cmd' e(N); drop breakdown in the `cmd' output"'
	di as txt "nflow: estimation N = " as res %12.0fc e(N) as txt " (data N " %12.0fc _N as txt ") " `"`label'"'
	return scalar N = e(N)
	return scalar excluded = _N - e(N)
end

program define nflow_report
	syntax [using/]
	if `"`using'"' == "" local using `"$NFLOW_file"'
	if `"`using'"' == "" {
		di as err "nflow report: no log; run nflow start or give using"
		exit 198
	}
	preserve
	quietly import delimited using `"`using'"', clear varnames(1) stringcols(1 2 3 7) bindquote(strict) encoding(utf8)
	list, noobs sepby(kind) abbreviate(10) string(80)
	restore
end

* --- helpers ---
program define nflow_text, rclass
	* one quoted or unquoted free-text argument
	local t = strtrim(`"`0'"')
	if substr(`"`t'"', 1, 1) == `"""' | substr(`"`t'"', 1, 2) == char(96) + char(34) {
		gettoken t rest : 0
		if strtrim(`"`rest'"') != "" {
			di as err "nflow: put the whole reason in one pair of quotes"
			exit 198
		}
	}
	return local text `"`t'"'
end

program define nflow_started
	if `"$NFLOW_file"' == "" {
		di as err "nflow: run nflow start using <log.csv> first"
		exit 198
	}
end

program define nflow_write
	args kind nbefore nafter reason
	local reason : subinstr local reason `"""' `""""', all
	local change = cond("`nbefore'" == "", 0, `nafter' - 0`nbefore')
	local date = strtrim(c(current_date))
	tempname fh
	capture {
		file open `fh' using `"$NFLOW_file"', write append text
		file write `fh' `"`date',`c(current_time)',`kind',`nbefore',`nafter',`change',"`reason'""' _n
		file close `fh'
	}
	if _rc {
		local rc = _rc
		capture file close `fh'
		di as err `"nflow: WARNING cannot write to $NFLOW_file (r(`rc')); this `kind' row is NOT recorded"'
	}
end
