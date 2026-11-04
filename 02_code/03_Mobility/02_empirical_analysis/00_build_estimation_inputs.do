version 18.0
args PROJECT_ROOT
if `"`PROJECT_ROOT'"' == "" {
    local PROJECT_ROOT : environment REPLICATION_ROOT
}
if `"`PROJECT_ROOT'"' == "" {
    display as error "Use RUN_01_PREPARE_DATABASE.bat or pass the project root."
    exit 198
}
local PROJECT_ROOT = subinstr(`"`PROJECT_ROOT'"', "\", "/", .)
do "`PROJECT_ROOT'/02_code/03_Mobility/01_database_preparation/04_build_analysis_inputs.do" "`PROJECT_ROOT'"
