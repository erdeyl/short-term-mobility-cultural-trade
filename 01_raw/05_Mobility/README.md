# UN Tourism inbound arrivals, and the Hofstede workbook used by the build

## UN Tourism

UN Tourism's terms do not allow redistribution or derivative compilations (`../../LICENSES_AND_SOURCES.md`, section 2), so no workbook and no row-level value is included. Researchers can obtain the data from UN Tourism; the database page (https://www.untourism.int/tourism-statistics/tourism-statistics-database) states that "to be able to obtain data from the UN Tourism database free of charge you should send a formal request in writing".

Series: arrivals of non-resident tourists (overnight visitors) and of visitors at national borders, by country of residence and by nationality, unit "thousand trips", country-level workbooks of the release "Last release / revision 23 December 2025" (data years to 2024). The build reads sheet `Data` of every workbook and asserts the indicator code and unit per folder (`02_code/03_Mobility/01_database_preparation/01_UN_Tourism/01_build_UN_Tourism.do`).

| Subfolder (exact name) | Workbooks | Indicator code |
|---|---|---|
| `Tourists Arrivals by Nationality` | 61 | `INBD_TRIP_NLTY_TOUR` |
| `Tourists Arrivals by Residence` | 131 | `INBD_TRIP_AREA_TOUR` |
| `Visitors Arrivals by Nationality` | 45 | `INBD_TRIP_NLTY_VSTR` |
| `Visitors Arrivals by Residence` | 107 | `INBD_TRIP_AREA_VSTR` |

Keep the provider file names (pattern `<reporter code><series code><first year><last year><release>.xlsx`, for example `0012011220202024202512.xlsx`); `../RAW_MANIFEST.sha256` lists each one with its SHA-256. Rules applied to these data (residence first, nationality fallback, the Paraguay, Pakistan and Belarus–Liechtenstein quarantines): `../../README.md`, Section 6.

## Hofstede workbook of the submitted paper (optional)

`6-dimensions-for-website-2015-08-16 (1).xls` (SHA-256 `18eaa61be9227d285923c08af5915f3029872c0becd71de9ca95c9eac2978bb7`) is the workbook of the submitted paper: the official 2015-08-16 file (`../08_Hofstede_official/README.md`) with 36 countries added and 14 countries' missing scores filled from the official regional rows "Arab countries", "Africa West" and "Africa East". `../../derived/hofstede/hofstede_regional_proxy_construction.csv` lists every such country, the dimensions concerned and the regional row used. The provider does not address redistribution, so the workbook is not included, and it is optional: without it, `run_all.py` rebuilds its first sheet from the official file (`../../tools/rebuild_hofstede_inputs.py` with `../../derived/hofstede/hofstede_package_workbook_layout.csv`). The rebuilt sheet equals the workbook in every cell, so every output is unchanged; the build reads the workbook or the rebuilt sheet with `02_code/03_Mobility/01_database_preparation/02_Hofstede/00_extract_and_audit_hofstede_source.py`. With the workbook present, `python tools/rebuild_hofstede_inputs.py <official .xls> <folder> --verify <workbook>` checks the identity.
