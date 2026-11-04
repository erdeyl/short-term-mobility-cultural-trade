# World Bank classifications by income (included)

- `CLASS.xlsx`: current classification by income (FY27), https://ddh-openapi.worldbank.org/resources/DR0095333/download , retrieved 2026-11-03.
- `OGHIST.xlsx`: historical classification by income (FY89–FY27), https://ddh-openapi.worldbank.org/resources/DR0095334/download , retrieved 2026-11-03.

Both are linked from the Data Help Desk article https://datahelpdesk.worldbank.org/knowledgebase/articles/906519-world-bank-country-and-lending-groups and listed in the Data Catalog under World Development Indicators (dataset 0037712), license CC BY 4.0. The files are unchanged. Attribution: The World Bank: World Bank Country and Lending Groups, classification by income (current and historical): World Development Indicators.

Use in the analysis (`02_code/10_analysis/01_prep.do`, part E): region and income group of each economy; for calendar year t the income group of fiscal year t+1 (set on 1 July of year t, based on GNI per capita of t−1); the FY(t) alternative is stored as well. Result: `../../derived/worldbank/wb_income_region_by_economy_year.csv`.
