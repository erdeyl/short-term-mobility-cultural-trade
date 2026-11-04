version 18.0 // RESCUE C11a
about // RESCUE C11a
foreach cmd in ppmlhdfe reghdfe ftools ivreghdfe ivreg2 ppml_fe_bias jwdid boottest honestdid nflow { // RESCUE C11a
    capture noisily which `cmd' // RESCUE C11a
} // RESCUE C11a
* RESCUE C11a: N1.6 historical comparison, never a corrected-data target.
* RESCUE C11a: installed [P] scalar; [P] file (file.sthlp:30-40,89-94,290-305).
scalar old_rows = 823446 // RESCUE C11a
scalar old_strict_vis = 25656 // RESCUE C11a
scalar old_strict_tour = 34830 // RESCUE C11a
if "${RUN_TAG}" == "LB" { // RESCUE C11a
    scalar old_vis_n = 20543 // RESCUE C11a
    scalar old_tour_n = 26682 // RESCUE C11a
    scalar old_vis_b = 0.242870166 // RESCUE C11a
    scalar old_tour_b = 0.240480434 // RESCUE C11a
} // RESCUE C11a
else if "${RUN_TAG}" == "UB" { // RESCUE C11a
    scalar old_vis_n = 20543 // RESCUE C11a
    scalar old_tour_n = 26694 // RESCUE C11a
    scalar old_vis_b = 0.243015 // RESCUE C11a: historical rounded reference
    scalar old_tour_b = 0.242037 // RESCUE C11a: historical rounded reference
} // RESCUE C11a
else { // RESCUE C11a
    display as error "UNKNOWN_RUN_TAG=${RUN_TAG}" // RESCUE C11a
    exit 198 // RESCUE C11a
} // RESCUE C11a
* RESCUE C11a: file.sthlp text-output syntax; explicit precision retains small deltas.
tempname delta // RESCUE C11a
file open `delta' using "${DIAG_DIR}/core_validation_delta.csv", write replace text // RESCUE C11a
file write `delta' "run_tag,metric,old_value,new_value,difference" _n // RESCUE C11a
foreach metric in rows strict_vis strict_tour vis_n tour_n vis_b tour_b { // RESCUE C11a
    file write `delta' "${RUN_TAG},`metric'," %24.17g (scalar(old_`metric')) "," %24.17g (scalar(validation_`metric')) "," %24.17g (scalar(validation_`metric')-scalar(old_`metric')) _n // RESCUE C11a
} // RESCUE C11a
file close `delta' // RESCUE C11a
