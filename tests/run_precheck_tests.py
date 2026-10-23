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
        for mode, expected_code in [('cancel', 2), ('precheck-fail', 1), ('decline', 2), ('confirm', 0)]:
            flow_root = temp / mode
            flow_root.mkdir()
            env.update(IMPF_FLOW_ROOT=str(flow_root), IMPF_FLOW_CASE=mode)
            result = subprocess.run(
                [pwsh, '-NoLogo', '-NoProfile', '-NonInteractive', '-File',
                 str(root / 'tests/startup-harness.ps1')],
                env=env, capture_output=True, text=True, timeout=15,
            )
            if result.returncode != expected_code:
                raise AssertionError(f'{mode}: unexpected exit {result.returncode}\n{result.stdout}\n{result.stderr}')
            reports = list(flow_root.glob('PostgreSQL_Run_*.log'))
            diagnostics = list(flow_root.rglob('iMPF_Startup_*.log'))
            assert len(reports) == len(diagnostics) == 1, (mode, reports, diagnostics)
            trace = diagnostics[0].read_text(encoding='utf-8-sig')
            assert 'EXIT cleanup completed' in trace, trace
            assert 'fake-password-with-no-real-access' not in trace
            marker = flow_root / 'executed.txt'
            if mode == 'confirm':
                assert marker.read_text().splitlines() == ['STEP 1 - BACKUP', 'STEP 2 - CUSTOMER SQL']
            else:
                assert not marker.exists(), f'{mode} started selected SQL'
            if mode == 'cancel':
                assert 'PASSWORD cancelled' in trace and 'PRECHECK simulated' not in trace
            else:
                assert 'PASSWORD ready' in trace and 'PRECHECK simulated' in trace
            print(f'PASS: startup {mode}, local stage log, execution gate', flush=True)


if __name__ == '__main__':
    main()
