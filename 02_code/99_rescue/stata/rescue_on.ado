*! rescue_on 1.0 2026-11-02  RESCUE correction switch for Stata (same semantics as 02_code/99_rescue/rescue_switch.py)
*! usage: rescue_on C11a   -> r(on) = 1 if RESCUE_CORRECTIONS is "all" or lists C11a; 0 if unset, "none" or not listed
program define rescue_on, rclass
    version 16.0
    args cid
    local v : env RESCUE_CORRECTIONS
    local v = strtrim(upper(`"`v'"'))
    local id = strtrim(upper(`"`cid'"'))
    local on 0
    if `"`v'"' == "ALL" local on 1
    else if !inlist(`"`v'"', "", "NONE") {
        local list = subinstr(`"`v'"', " ", "", .)
        if strpos("," + `"`list'"' + ",", "," + `"`id'"' + ",") local on 1
    }
    return scalar on = `on'
    return local setting `"`v'"'
end
