{smcl}
{* *! nflow 1.0.1 08oct2026}{...}
{title:Title}

{phang}
{bf:nflow} {hline 2} Sample-size flow log: N with a reason at every data step, e(N) at each estimation

{title:Syntax}

{p 8 16 2}{cmd:nflow start using} {it:log.csv} [{cmd:,} {opt replace}|{opt append} {opt e:xpected(#)}]{p_end}
{p 8 16 2}{cmd:nflow step} {cmd:"}{it:reason}{cmd:"}{p_end}
{p 8 16 2}{cmd:nflow est} [{cmd:"}{it:label}{cmd:"}]{p_end}
{p 8 16 2}{cmd:nflow report} [{cmd:using} {it:log.csv}]{p_end}

{title:Description}

{pstd}
{cmd:nflow} keeps an append-only CSV log (date, time, kind, n_before, n_after, change, reason) of the number of
observations through a pipeline. Call {cmd:nflow start} once the data are loaded, {cmd:nflow step} after every command
that may change N (drop, keep, merge, append, collapse, reshape), and {cmd:nflow est} after each estimation. A reason is
required for every step. {cmd:nflow} is a record beside the pipeline, not a gate: it never stops a correct run.

{pstd}
{cmd:nflow est} writes one row with the data N and {cmd:e(N)}. The breakdown of observations the estimator drops stays
in the estimator's own output and stored results (for {cmd:ppmlhdfe}/{cmd:reghdfe}: {cmd:e(N_full)},
{cmd:e(num_singletons)}, {cmd:e(num_separated)}). If N changed since the last {cmd:nflow step}, {cmd:nflow est} first
writes an {it:unlogged} row and a warning.

{pstd}
{opt expected(#)} pins the starting N; a mismatch prints a warning, writes a {it:note} row and returns
{cmd:r(mismatch)=1}. {opt replace} starts a new log; {opt append} continues an existing one (e.g. a second do-file).
A relative log path is stored as an absolute path, so a later {cmd:cd} does not move the log.
Run {cmd:nflow start} again after loading a different dataset. Log a {cmd:restore} with {cmd:nflow step} too
(the logger does not see it). Call {cmd:nflow est} right after the estimation; with weights, {cmd:e(N)} is in
weight units. {cmd:nflow} is r-class: save earlier {cmd:r()} results you still need. If the log cannot be written,
{cmd:nflow} prints a warning that the row is NOT recorded and the do-file continues.

{title:Example}

{phang2}{cmd:. nflow start using "logs/sample_flow.csv", replace expected(9000)}{p_end}
{phang2}{cmd:. drop if exporter == importer}{p_end}
{phang2}{cmd:. nflow step "drop domestic flows"}{p_end}
{phang2}{cmd:. ppmlhdfe trade lang fta, absorb(exp#year imp#year pair)}{p_end}
{phang2}{cmd:. nflow est "Table 2 col 3"}{p_end}
{phang2}{cmd:. nflow report}{p_end}

{title:Stored results}

{pstd}{cmd:start}: {cmd:r(N)}, and with {opt expected()} also {cmd:r(expected)}, {cmd:r(mismatch)}.
{cmd:step}: {cmd:r(N)}, {cmd:r(change)}. {cmd:est}: {cmd:r(N)} (= e(N)), {cmd:r(excluded)} (data N minus e(N)).{p_end}

{title:Source}

{pstd}Idea: Scott Cunningham (sample-size accounting). Re-implemented for
L. Erdey, 2026-10-08. Location: PERSONAL ado folder; copy {cmd:nflow.ado} and {cmd:nflow.sthlp} to other machines.{p_end}
