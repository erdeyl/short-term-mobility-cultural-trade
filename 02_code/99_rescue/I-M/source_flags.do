version 18.0 // RESCUE C11b C11c
about // RESCUE C11b C11c
foreach cmd in ppmlhdfe reghdfe ftools ivreghdfe ivreg2 ppml_fe_bias jwdid boottest honestdid nflow { // RESCUE C11b C11c
    capture noisily which `cmd' // RESCUE C11b C11c
} // RESCUE C11b C11c
capture rescue_on C11b // RESCUE C11b I-M2
local rescue_on_C11b = (_rc==0 & r(on)==1) // RESCUE C11b I-M2
if `rescue_on_C11b' { // RESCUE C11b
    gen byte conf_sub = (visitors_notes=="Value represents overnight visitors (tourists) only. No data available for same-day visitors (excursionists)") if !missing(visitors_k) // RESCUE C11b
    label variable conf_sub "Confirmed tourists-only substitute in selected visitor series" // RESCUE C11b
    label variable visitors_k "Visitor-series arrivals, mixed coverage, thousand trips" // RESCUE C11b
    label variable visitors_trips "Visitor-series arrivals, mixed coverage, trips" // RESCUE C11b
} // RESCUE C11b
capture rescue_on C11c // RESCUE C11c I-M2
local rescue_on_C11c = (_rc==0 & r(on)==1) // RESCUE C11c I-M2
if `rescue_on_C11c' { // RESCUE C11c
    * Installed [D] egen: max(exp), by(varlist); [D] generate and string substr(). // RESCUE C11c
    foreach measure in tourists visitors { // RESCUE C11c
        local stub = cond("`measure'"=="tourists","tour","vis") // RESCUE C11c
        assert regexm(`measure'_source_file,"^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]\.xlsx$") if !missing(`measure'_k) // RESCUE C11c
        gen int `stub'_start = real(substr(`measure'_source_file,9,4)) if !missing(`measure'_k) // RESCUE C11c
        gen int `stub'_end = real(substr(`measure'_source_file,13,4)) if !missing(`measure'_k) // RESCUE C11c
        gen byte `stub'_span2020 = (`stub'_start==2020) if !missing(`measure'_k) // RESCUE C11c
        tempvar has_nat has_res // RESCUE C11c
        egen byte `has_nat' = max(cond(inrange(year,2007,2021) & !missing(`measure'_k),`measure'_basis=="nationality",.)), by(reporter_area_code partner_area_code) // RESCUE C11c
        egen byte `has_res' = max(cond(inrange(year,2007,2021) & !missing(`measure'_k),`measure'_basis=="residence",.)), by(reporter_area_code partner_area_code) // RESCUE C11c
        gen byte `stub'_study_switch = (`has_nat'==1 & `has_res'==1) if inrange(year,2007,2021) & !missing(`measure'_k) // RESCUE C11c
        label variable `stub'_study_switch "Observed selected series switches basis during 2007-2021" // RESCUE C11c
        drop `has_nat' `has_res' // RESCUE C11c
    } // RESCUE C11c
} // RESCUE C11c
