"""Exercise only the extracted precheck with a local mock; never connect to a DB."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pwsh', default='pwsh')
    args = parser.parse_args()
    if os.name == 'nt':
        parser.error('The mock executable requires a POSIX host. See README for Windows validation.')
    pwsh = shutil.which(args.pwsh)
    if pwsh is None:
        parser.error('PowerShell was not found; specify --pwsh /path/to/pwsh.')
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix='impf-precheck-') as scratch:
        temp = Path(scratch)
        mock = temp / 'mock psql.py'
        shutil.copyfile(root / 'tests/mock_psql.py', mock)
        mock.chmod(0o700)
        env = os.environ.copy()
        env.update({
            'IMPF_TEST_RUNNER': str(root / 'iMPF-Run-Scripts.ps1'),
            'IMPF_TEST_MOCK': str(mock),
            'IMPF_TEST_PID': str(temp / 'mock.pid'),
        })
        subprocess.run(
            [pwsh, '-NoLogo', '-NoProfile', '-NonInteractive',
             '-File', str(root / 'tests/precheck-harness.ps1')],
            env=env, check=True, timeout=90,
        )


if __name__ == '__main__':
    main()
