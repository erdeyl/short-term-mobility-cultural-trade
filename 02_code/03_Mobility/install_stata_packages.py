from chapter_paths import *
from chapter_runtime import check_stata_environment, run_stata
ensure_dirs()
check_stata_environment()
run_stata(CHAPTER_CODE/'01_install_stata_packages.do', (ROOT.as_posix(),),
          DIAGNOSTICS/'STATA_PACKAGES_INSTALLED.txt')
check_stata_environment(packages=True)
