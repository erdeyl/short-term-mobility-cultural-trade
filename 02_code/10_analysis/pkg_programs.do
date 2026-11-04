* pkg_programs.do -- helper programs of the replication package (loaded by 00_config.do).
* pkg_py <arguments>: runs the package's Python interpreter (${PYTHON}, set from PKG_PYTHON by run_all.py)
* with the rest of the line passed verbatim to the operating system shell ([D] shell).
* POSIX: the line is  "<python>" <arguments> . Windows: cmd /c removes the outermost pair of double quotes
* when a line starts with a quote, so the whole line is wrapped in one extra pair (char(34)).
capture program drop pkg_py
program define pkg_py
    version 18.0
    local q ""
    if c(os) == "Windows" local q = char(34)
    shell `q'"${PYTHON}" `0'`q'
end
