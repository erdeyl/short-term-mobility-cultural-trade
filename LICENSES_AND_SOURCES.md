# Licenses and sources of the data

For each provider: the files used, the provider's governing text (quoted verbatim from the page named, accessed 2026-11-04), and what the package does. Where redistribution is not clearly allowed, the package ships retrieval instructions and the SHA-256 of the exact files used (`01_raw/RAW_MANIFEST.sha256`) instead of the files, and `run_all.py` stops with a clear message if a file is missing. Nothing below is an inference from reputation: where a page is silent or could not be read, this is stated.

| # | Provider | Files | Terms (classification) | In the package |
|---|---|---|---|---|
| 1 | UN Comtrade (UNSD) | API extracts, reference files, data availability | raw records: not without UNSD permission; reference files: not clearly allowed | no; acquisition scripts, query specification, manifest and checksums |
| 2 | UN Tourism | inbound arrivals workbooks (344) | no redistribution, no derivative compilations | no; retrieval instructions and checksums; no row-level values anywhere |
| 3 | CEPII Gravity V202211 | `Gravity_V202211.dta`, `Countries_V202211.dta` | Etalab Open Licence 2.0 (redistribution allowed, attribution) | no, for size (1.4 GB); URL and checksums |
| 4 | CEPII Language | `ling_web.dta` | Etalab Open Licence 2.0 (redistribution allowed, attribution) | yes |
| 5 | World Bank | `CLASS.xlsx`, `OGHIST.xlsx` | CC BY 4.0 (redistribution allowed, attribution) | yes |
| 6 | Hofstede dimension data | official 2015-08-16 `.xls`; the build's workbook | research use free; redistribution not addressed | no; URL, checksums, construction table without scores |
| 7 | UNESCO FCS 2009 | (document; the package ships a code list compiled from Table 3) | quotation within UNESCO's limits | code list only (no document text) |
| 8 | HS 2007 reference list (UN Comtrade `H3.json`) | code descriptions | not clearly allowed | not shipped; only code numbers are used in `derived/` |

## 1. UN Comtrade (United Nations Statistics Division)

Files: importer-reported HS six-digit imports (330 CSV), exporter-reported mirror files (338 CSV, 60 availability files, 2 manifests), data-availability responses (15 JSON), `partnerAreas.json`, `Reporters.json`, `HS-SITC-BEC_Correlations_2022.xlsx`, `download_manifest.csv`.

- Policy on Comtrade Data Use, https://uncomtrade.org/docs/policy-on-comtrade-data-use/ : "UN Comtrade data are provided for internal use only and may not be re-disseminated in any form without UNSD's permission." Citation: "Regarding citation, refer to the data source as “UN Comtrade.”"
- Re-dissemination of data, https://uncomtrade.org/docs/re-dissemination-of-data/ : "Data that has been meaningfully enhanced, modified, or combined with other information may be considered transformed" … "Such data may be re-disseminated without a distribution license fee." The same page lists, among the uses for which "permission is not required", the "Publication of limited amounts of UN Comtrade data in a few tables, graphs, visualization in printed or digital platform".
- The current license agreement (https://comtradeplus.un.org/LicenseAgreement) is rendered by JavaScript and could not be read.

Package: the raw extracts and the reference files are not included. `02_code/00_acquisition/01_UN_Comtrade_importer/` (importer side) and `02_code/03_Mobility/01_database_preparation/04_UN_Comtrade_mirror/` (exporter side) re-query the API with the archived query specifications (an API key is needed); the manifest gives the SHA-256 of every file used. The shared derived files contain HS code numbers, concordance rules and flags, which are transformed data in the sense of the re-dissemination page; the reported tables contain estimates only. Source: UN Comtrade.

## 2. UN Tourism

Files: inbound arrivals of tourists and of visitors, by country of residence and by nationality (four folders, 344 workbooks, release of 23 December 2025).

- Copyright and terms, https://www.untourism.int/copyright : UN Tourism "grants permission to Users to visit the Site and to download and copy the information, documents and materials" … "for the User's personal, non-commercial use, without any right to resell or redistribute them" … "or to compile or create derivative works there from".
- Tourism Statistics Database, https://www.untourism.int/tourism-statistics/tourism-statistics-database : "to be able to obtain data from the UN Tourism database free of charge you should send a formal request in writing" (arrangement for students and university researchers).
- The e-Library terms (https://www.e-unwto.org/terms-and-conditions) returned HTTP 403 and were not read.

Package: no workbook and no row-level value or derived row-level file is included; logs are released with the value listings removed (`tools/make_release.py`). `01_raw/05_Mobility/README.md` lists the workbooks and how to request them; the manifest gives their SHA-256.

## 3. CEPII Gravity database, V202211

- Database page, https://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=8 : "Licence: Etalab 2.0"; "This is the 202211 version." Download (Stata): https://www.cepii.fr/DATA_DOWNLOAD/gravity/data/Gravity_dta_V202211.zip
- Etalab Open Licence 2.0 (linked from that page): the reuser may "share, disseminate, redistribute, publish and transmit it", "Subject to: An acknowledgement of the authorship of the “Information”: its source (at least, the name of the “Grantor”) and the date of the most recent update of the reused “Information”."

Attribution: CEPII Gravity database, version V202211; Conte, M., P. Cotterlaz and T. Mayer (2022), "The CEPII Gravity database", CEPII Working Paper 2022-05. Package: not included because of its size (1.4 GB; above common repository file limits); URL and checksums in `01_raw/01_Gravity/README.md`. That `Countries_V202211.dta` is contained in the Stata zip was not verified from the provider's page.

## 4. CEPII Language database (Melitz and Toubal)

- Database page, https://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=19 : "Licence: Etalab 2.0" (same license text as in 3). File: https://www.cepii.fr/DATA_DOWNLOAD/language/ling_web.dta

Attribution: CEPII Language database, `ling_web.dta`, retrieved 2026-11-03 (the page shows no update date); Melitz, J. and F. Toubal (2014), "Native language, spoken language, translation and trade", Journal of International Economics 92(2): 351–363. Package: included unchanged (`01_raw/07_CEPII_Language/`).

## 5. World Bank country classifications by income

- Data Catalog, World Development Indicators (dataset 0037712), https://datacatalog.worldbank.org/search/dataset/0037712/World-Development-Indicators , which lists the resources "Current classification by income" and "Historical classification by income": "License: Creative Commons Attribution 4.0".
- Terms of Use for Datasets, https://www.worldbank.org/ext/en/legal/terms-conditions/datasets : "Unless specifically labeled otherwise, these Datasets are provided to you under a Creative Commons Attribution 4.0" "International License (CC BY 4.0), with the additional terms below." Attribution format: "The World Bank: Dataset name: Data source (if known)."
- Downloads used (Data Help Desk article 906519): https://ddh-openapi.worldbank.org/resources/DR0095333/download (CLASS.xlsx, FY27) and https://ddh-openapi.worldbank.org/resources/DR0095334/download (OGHIST.xlsx), retrieved 2026-11-03.

Attribution: The World Bank: World Bank Country and Lending Groups, current and historical classification by income: World Development Indicators. No change was made to the files. Package: included (`01_raw/06_WorldBank/`).

## 6. Hofstede cultural dimensions (Geert Hofstede BV)

- Dimension data matrix, https://geerthofstede.com/research-and-vsm/dimension-data-matrix/ : "Researchers can use them without asking for permission." and "Those who are considering commercial use should contact us."
- Contact page, https://geerthofstede.com/contact/ : "Geert's research data and his questionnaires are free to use for research purposes." and "No permission can be given to print material published on websites." The site has no page on redistribution.

Package: research use is covered; redistribution of the data matrix is not addressed, so neither the official file (https://geerthofstede.com/wp-content/uploads/2016/08/6-dimensions-for-website-2015-08-16.xls) nor the build's workbook derived from it is included, and no derived table with scores is shipped. `derived/hofstede/` lists codes and the construction rules only (including the cell-by-cell layout from which `tools/rebuild_hofstede_inputs.py` rebuilds the build's workbook from the official file, so a user needs only the official file). `run_all.py` stops with the retrieval instructions (URL, file name, SHA-256) if the official file is missing.

## 7. UNESCO Framework for Cultural Statistics 2009

- Copy used: https://unstats.un.org/unsd/statcom/doc10/BG-FCS-E.pdf ; imprint: "©UNESCO-UIS 2009", no open license on the imprint page.
- UNESCO Terms of Use, https://www.unesco.org/en/terms-use : "Permitted Quotation of individual Materials is authorized for up to 1,000 words or 25% of the source Material" (whichever is less); citation format "UNESCO (year), Title, URL."

Package: the document is not included. `derived/products/` lists the HS codes compiled from FCS 2009 Table 3 with the FCS status and domain (codes and category labels, no document text). Citation: UNESCO Institute for Statistics (2009), 2009 UNESCO Framework for Cultural Statistics, https://unstats.un.org/unsd/statcom/doc10/BG-FCS-E.pdf . The license of the UIS 2016 report "The Globalisation of Cultural Trade" (cited in the manuscript) could not be verified; it is not included.

## 8. HS 2007 reference list (UN Comtrade `H3.json`)

- https://comtradeapi.un.org/files/v1/app/reference/H3.json : no separate license statement was found; the UN Comtrade texts in 1 apply on their face, and the HS nomenclature itself is World Customs Organization material, whose terms were not found.

Package: the HS descriptions are not shipped; the derived files use code numbers only.

## Software

Stata packages are installed from SSC and GitHub by `install/install_stata_packages.do` and are not redistributed, except `nflow` 1.0.1 (a small sample-size logging command) and the correction switch `rescue_on`, which are distributed with the package code.
