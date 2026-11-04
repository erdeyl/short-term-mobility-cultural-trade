"""Portable Python/Stata launch helpers, local to this chapter."""
from pathlib import Path
import tempfile
import csv
import os
import shutil
import subprocess
import sys
import time
from chapter_paths import *

def find_stata():
    explicit=os.environ.get('STATA_EXE','').strip().strip('"')
    setting=CHAPTER_CODE/'stata_path.txt'
    if not explicit and setting.is_file():
        explicit=setting.read_text(encoding='utf-8-sig').strip().strip('"')
    if explicit:
        p=Path(explicit)
        if not p.is_file():
            raise RuntimeError(f'The configured Stata executable does not exist: {p}')
        return p
    names=['StataMP-64.exe','StataSE-64.exe','StataBE-64.exe','StataIC-64.exe',
           'Stata-64.exe','StataMP.exe','StataSE.exe','Stata.exe','stata-mp','stata-se','stata']
    for name in names:
        found=shutil.which(name)
        if found:return Path(found)
    # replication package: machine-specific drive letters removed (run_all.py passes STATA_EXE);
    # Windows installs are found through the ProgramFiles environment variables
    locations=[Path('/usr/local/stata'),Path('/usr/local/stata18')]
    for key in ('ProgramFiles','ProgramFiles(x86)'):
        if os.environ.get(key):
            for version in (19,18,17):locations.append(Path(os.environ[key])/f'Stata{version}')
    for folder in locations:
        for name in names:
            if (folder/name).is_file():return folder/name
    raise RuntimeError('Stata executable not found. Set STATA_EXE or put its full path in stata_path.txt in this chapter folder.')

def stata_command(executable,dofile,args=()):
    flag='/e' if os.name=='nt' else '-b'
    return [str(executable),flag,'do',str(dofile),*[str(a) for a in args]]

def env_for_stata():
    tmp=ROOT/'00_stata_temp'
    tmp.mkdir(parents=True,exist_ok=True)
    # Check the actual destination before starting a fresh Stata process.
    with tempfile.NamedTemporaryFile(dir=tmp, prefix='python_write_check_', delete=True) as probe:
        probe.write(b'project temporary directory is writable\n')
        probe.flush()
        probe.seek(0)
        if not probe.read():
            raise RuntimeError(f'Temporary-directory readback failed: {tmp}')
    env=os.environ.copy()
    env.update(STATATMP=str(tmp),TEMP=str(tmp),TMP=str(tmp),TMPDIR=str(tmp),REPLICATION_ROOT=ROOT.as_posix(),
               PYTHONIOENCODING='utf-8',PYTHONUTF8='1')
    return env

def run_python(path,args=()):
    subprocess.run([sys.executable,'-u',str(path),*map(str,args)],cwd=ROOT,
                   env=env_for_stata(),check=True)

def run_stata(path,args=(),marker=None):
    path=Path(path)
    if not path.is_file():raise FileNotFoundError(path)
    if marker:
        marker=Path(marker)
        marker.parent.mkdir(parents=True,exist_ok=True)
        marker.unlink(missing_ok=True)
    ensure_dirs()
    executable=find_stata()
    batch=LOGS/'batch_transcripts'/path.stem
    batch.mkdir(parents=True,exist_ok=True)
    subprocess.run(stata_command(executable,path,args),cwd=batch,env=env_for_stata(),check=True)
    if marker and not marker.is_file():
        raise RuntimeError(f'Stata did not complete {path.name}. Check {LOGS}. Missing completion file: {marker}')

def require_common():
    if not COMMON_BASE.is_file() or not COMMON_MARKER.is_file():
        raise RuntimeError('A completed common base is required. Run 02_code/00_common/RUN_COMMON.bat first.')
    if 'COMMON_BASE_BUILD_COMPLETE=yes' not in COMMON_MARKER.read_text(encoding='utf-8-sig'):
        raise RuntimeError(f'Common-base completion file does not confirm success: {COMMON_MARKER}')

def invalidate_completion(stage):
    chapter = CHAPTER_ID
    database = (DIAGNOSTICS/'Master' if chapter=='DIGITALIZATION' else DIAGNOSTICS) / (chapter+'_DATABASE_COMPLETE.txt')
    empirical = DIAGNOSTICS/(chapter+'_ALL_EMPIRICS_COMPLETE.txt')
    if stage in ('build','all'):
        database.unlink(missing_ok=True)
        empirical.unlink(missing_ok=True)
    elif stage=='empirical':
        empirical.unlink(missing_ok=True)

def check_stata_environment(packages=False):
    ensure_dirs()
    marker = DIAGNOSTICS/'STATA_ENVIRONMENT_COMPLETE.txt'
    run_stata(CHAPTER_CODE/'00_check_stata_environment.do',
              (ROOT.as_posix(), 'empirical' if packages else 'data'), marker)
    print('STATA_ENVIRONMENT=PASS', flush=True)


def run_logged(steps,logname,completion):
    ensure_dirs()
    completion=Path(completion)
    completion.parent.mkdir(parents=True,exist_ok=True)
    completion.unlink(missing_ok=True)
    statuses=[]
    statuspath=LOGS/(Path(logname).stem+'_status.csv')
    statuspath.unlink(missing_ok=True)
    with (LOGS/logname).open('w',encoding='utf-8') as log:
        def emit(line):
            print(line,flush=True);log.write(line+'\n');log.flush()
        emit('Project root: '+str(ROOT))
        try:
            for label,command in steps:
                emit('\nRunning '+label)
                start=time.monotonic()
                with subprocess.Popen(command,cwd=ROOT,env=env_for_stata(),stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace') as proc:
                    for line in proc.stdout:emit(line.rstrip('\n'))
                    rc=proc.wait()
                statuses.append({'step':label,'status':'PASS' if rc==0 else 'FAIL','seconds':round(time.monotonic()-start,2)})
                with statuspath.open('w',encoding='utf-8-sig',newline='') as out:
                    writer=csv.DictWriter(out,fieldnames=['step','status','seconds'])
                    writer.writeheader();writer.writerows(statuses)
                if rc:raise RuntimeError(f'{label} stopped with exit {rc}.')
            completion.write_text('COMPLETE=PASS\n',encoding='utf-8')
            emit('\nCHAPTER_RUN=PASS')
        except Exception as exc:
            emit('\nCHAPTER_RUN=FAIL\n'+str(exc))
            raise

if __name__=='__main__':
    # A child process captures launcher failures in the chapter's main log.
    import argparse
    parser=argparse.ArgumentParser()
    parser.add_argument('dofile', nargs='?')
    parser.add_argument('--preflight', action='store_true')
    parser.add_argument('--packages', action='store_true')
    parser.add_argument('--marker')
    parser.add_argument('--no-root-arg',action='store_true')
    a=parser.parse_args()
    if a.preflight:
        check_stata_environment(a.packages)
    elif a.dofile:
        run_stata(Path(a.dofile),() if a.no_root_arg else (ROOT.as_posix(),),a.marker)
    else:
        parser.error('Supply a do-file or --preflight.')
