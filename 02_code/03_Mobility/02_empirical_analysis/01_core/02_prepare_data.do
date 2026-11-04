/*******************************************************************************
 Reconstruct direction-specific and strict bilateral mobility variables.

 Direction convention for a trade row iso3_o -> iso3_d:
   stored visitors/tourists = iso3_d -> iso3_o (reverse direction)
   opposite dyad-year       = iso3_o -> iso3_d (same direction)
   bilateral raw flow       = observed reverse + observed same direction

 Missing directions are not coded as zero in the strict bilateral measures.
*******************************************************************************/

version 18.0
use "${DATA_FILE}", clear
compress
isid year iso3_o iso3_d

egen long exporter_id = group(iso3_o), label
egen long importer_id = group(iso3_d), label
egen long exporter_year = group(iso3_o year), label
egen long importer_year = group(iso3_d year), label
egen long pair_id = group(iso3_o iso3_d), label
gen str3 iso_low = cond(iso3_o < iso3_d, iso3_o, iso3_d)
gen str3 iso_high = cond(iso3_o < iso3_d, iso3_d, iso3_o)
egen long unordered_pair_id = group(iso_low iso_high), label

gen double rev_tour_raw = tourists
gen double rev_vis_raw = visitors


local rescue_rev "" // RESCUE C11b C11c C12
local rescue_same "" // RESCUE C11b C11c C12
capture rescue_on C12 // RESCUE C12 I-M2
local rescue_on_C12 = (_rc==0 & r(on)==1) // RESCUE C12 I-M2
if `rescue_on_C12' { // RESCUE C12
    rename pry_res_quarantine pry_res_quarantine_rev // RESCUE C12
    local rescue_rev "pry_res_quarantine_rev" // RESCUE C12
    local rescue_same "pry_res_quarantine_same" // RESCUE C12
} // RESCUE C12
capture rescue_on C11b // RESCUE C11b I-M2
local rescue_on_C11b = (_rc==0 & r(on)==1) // RESCUE C11b I-M2
if `rescue_on_C11b' { // RESCUE C11b
    rename conf_sub conf_sub_rev // RESCUE C11b
    local rescue_rev "`rescue_rev' conf_sub_rev" // RESCUE C11b C12
    local rescue_same "`rescue_same' conf_sub_same" // RESCUE C11b C12
} // RESCUE C11b
capture rescue_on C11c // RESCUE C11c I-M2
local rescue_on_C11c = (_rc==0 & r(on)==1) // RESCUE C11c I-M2
if `rescue_on_C11c' { // RESCUE C11c
    gen byte hier_rev = hierarchy_violation if !missing(tourists,visitors) // RESCUE C11c
    gen byte basis_mismatch_rev = basis_mismatch if !missing(tourists,visitors) // RESCUE C11c
    gen byte visitors_definition_diff_rev = visitors_definition_diff if !missing(visitors) // RESCUE C11c
    rename visitors_basis basis_rev_vis // RESCUE C11c
    rename tourists_basis basis_rev_tour // RESCUE C11c
    local rescue_rev "`rescue_rev' hier_rev basis_mismatch_rev visitors_definition_diff_rev basis_rev_vis basis_rev_tour" // RESCUE C11c
    local rescue_same "`rescue_same' hier_same basis_mismatch_same visitors_definition_diff_same basis_same_vis basis_same_tour" // RESCUE C11c
} // RESCUE C11c
capture rescue_on C11b // RESCUE C11b I-M2
local rescue_on_C11b = (_rc==0 & r(on)==1) // RESCUE C11b I-M2
local rescue_c11b = `rescue_on_C11b' // RESCUE C11b
capture rescue_on C11c // RESCUE C11c I-M2
local rescue_on_C11c = (_rc==0 & r(on)==1) // RESCUE C11c I-M2
local rescue_c11c = `rescue_on_C11c' // RESCUE C11c
foreach measure in vis tour { // RESCUE C11b C11c C12
    local source = cond("`measure'"=="vis","visitors","tourists") // RESCUE C11b C11c C12
    if `rescue_c11c' | (`rescue_c11b' & "`measure'"=="vis") { // RESCUE C11b C11c C12
        foreach pair in "source_file file" "flag flag" "flag_label flaglabel" "notes notes" "release release" { // RESCUE C11b C11c C12
            gettoken old new : pair // RESCUE C11b C11c: installed [P] macro gettoken
            local new = strtrim("`new'") // RESCUE C11b C11c: gettoken rest retains its leading delimiter
            rename `source'_`old' `measure'_`new'_rev // RESCUE C11b C11c C12
            local rescue_rev "`rescue_rev' `measure'_`new'_rev" // RESCUE C11b C11c C12
            local rescue_same "`rescue_same' `measure'_`new'_same" // RESCUE C11b C11c C12
        } // RESCUE C11b C11c C12
    } // RESCUE C11b C11c C12
    if `rescue_c11c' { // RESCUE C11c
        foreach prop in start end span2020 study_switch { // RESCUE C11c
            local target "`measure'_`prop'" // RESCUE C11c
            if "`prop'"=="study_switch" local target "basis_switch_rev_`measure'" // RESCUE C11c
            else local target "`measure'_`prop'_rev" // RESCUE C11c
            rename `measure'_`prop' `target' // RESCUE C11c
            local rescue_rev "`rescue_rev' `target'" // RESCUE C11c
            local mate = subinstr("`target'","_rev","_same",.) // RESCUE C11c
            local rescue_same "`rescue_same' `mate'" // RESCUE C11c
        } // RESCUE C11c
    } // RESCUE C11c
} // RESCUE C11b C11c C12

preserve
    keep year iso3_o iso3_d tourists visitors `rescue_rev' // RESCUE C11b C11c C12
    local meta_i 0 // RESCUE C11b C11c C12
    foreach field of local rescue_rev { // RESCUE C11b C11c C12
        local ++meta_i // RESCUE C11b C11c C12
        local mate : word `meta_i' of `rescue_same' // RESCUE C11b C11c C12
        rename `field' `mate' // RESCUE C11b C11c C12
    } // RESCUE C11b C11c C12
    rename tourists same_tour_raw
    rename visitors same_vis_raw
    rename iso3_o old_iso3_o
    rename iso3_d iso3_o
    rename old_iso3_o iso3_d
    tempfile opposite_flows
    save `"`opposite_flows'"', replace
restore

merge 1:1 year iso3_o iso3_d using `"`opposite_flows'"', keep(master match) nogen

capture rescue_on C11b // RESCUE C11b I-M2
local rescue_on_C11b = (_rc==0 & r(on)==1) // RESCUE C11b I-M2
if `rescue_on_C11b' { // RESCUE C11b
    gen byte vis_defok = !missing(rev_vis_raw,same_vis_raw) & conf_sub_rev==0 & conf_sub_same==0 // RESCUE C11b
    label variable visitors "Visitor-series arrivals, mixed coverage, trips" // RESCUE C11b
} // RESCUE C11b

if `rescue_on_C12' { // RESCUE C12 I-M2
    label variable pry_res_quarantine_rev "PRY source residence quarantined; reverse flow" // RESCUE C12 I-M2
    label variable pry_res_quarantine_same "PRY source residence quarantined; same flow" // RESCUE C12 I-M2
} // RESCUE C12 I-M2
if `rescue_on_C11b' { // RESCUE C11b I-M2
    label variable conf_sub_rev "Guarded confirmed tourists-only substitute; reverse visitors" // RESCUE C11b I-M2
    label variable conf_sub_same "Guarded confirmed tourists-only substitute; same visitors" // RESCUE C11b I-M2
    label variable vis_defok "Strict bilateral visitors without either confirmed substitute" // RESCUE C11b I-M2
} // RESCUE C11b I-M2
if `rescue_on_C11c' { // RESCUE C11c I-M2
    foreach direction in rev same { // RESCUE C11c I-M2
        label variable hier_`direction' "Guarded tourists>visitors comparison; `direction' flow" // RESCUE C11c I-M2
        label variable basis_mismatch_`direction' "Guarded visitor/tourist basis mismatch; `direction' flow" // RESCUE C11c I-M2
        label variable visitors_definition_diff_`direction' "Guarded generic visitor definition flag; `direction' flow" // RESCUE C11c I-M2
    } // RESCUE C11c I-M2
} // RESCUE C11c I-M2

gen byte has_rev_tour = !missing(rev_tour_raw)
gen byte has_same_tour = !missing(same_tour_raw)
gen byte has_both_tour = has_rev_tour & has_same_tour
gen byte has_rev_vis = !missing(rev_vis_raw)
gen byte has_same_vis = !missing(same_vis_raw)
gen byte has_both_vis = has_rev_vis & has_same_vis

gen double bilat_tour_raw = rev_tour_raw + same_tour_raw if has_both_tour
gen double bilat_vis_raw = rev_vis_raw + same_vis_raw if has_both_vis
gen double mob_rev_tour = asinh(rev_tour_raw) if has_rev_tour
gen double mob_same_tour = asinh(same_tour_raw) if has_same_tour
gen double mob_bilat_tour = asinh(bilat_tour_raw) if has_both_tour
gen double mob_rev_vis = asinh(rev_vis_raw) if has_rev_vis
gen double mob_same_vis = asinh(same_vis_raw) if has_same_vis
gen double mob_bilat_vis = asinh(bilat_vis_raw) if has_both_vis

gen byte positive_trade = (v_ttl_k > 0) if !missing(v_ttl_k)

label variable v_ttl_k "Trade (thousand USD)"
label variable bilat_vis_raw "Bilateral visitors"
label variable rev_vis_raw "Reverse visitors: importer to exporter"
label variable same_vis_raw "Same-direction visitors: exporter to importer"
label variable bilat_tour_raw "Bilateral tourists"
label variable rev_tour_raw "Reverse tourists: importer to exporter"
label variable same_tour_raw "Same-direction tourists: exporter to importer"
label variable mob_bilat_vis "IHS bilateral visitors"
label variable mob_bilat_tour "IHS bilateral tourists"

xtset pair_id year, yearly
sort pair_id year
gen double lag_bilat_vis = L.mob_bilat_vis
gen double lead_bilat_vis = F.mob_bilat_vis
gen double lag_bilat_tour = L.mob_bilat_tour
gen double lead_bilat_tour = F.mob_bilat_tour

file open support using "${DIAG_DIR}/support-ledger.csv", write replace
file write support "measure,N" _n
foreach item in rev_vis same_vis both_vis rev_tour same_tour both_tour {
    quietly count if has_`item'
    local support_n = r(N)
    file write support "`item',`support_n'" _n
}
quietly count if !missing(v_ttl_k)
local trade_n = r(N)
file write support "trade_nonmissing,`trade_n'" _n
file close support

quietly count if !missing(visitors, tourists) & visitors < tourists
display as result "VISITOR_TOURIST_HIERARCHY_VIOLATIONS=" r(N)

save "${CACHE_DIR}/analysis_prepared.dta", replace
display as result "PREPARED_DATA_ROWS=" _N
display as result "PREPARE_DATA_COMPLETE=yes"
