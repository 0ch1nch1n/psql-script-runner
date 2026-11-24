"""Exercise the precheck and startup execution gates with local mocks."""
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
        blocked = {
            'gbk-backup': ('backup.sql', 'SELECT \'中文\';'.encode('gbk'), '[INVALID UTF-8]'),
            'truncated-customer': ('customer.sql', b'SELECT 1; -- \xe4\xb8', '[INVALID UTF-8]'),
            'utf16-customer': ('customer.sql', 'SELECT 1;'.encode('utf-16-le'), 'File contains a NUL byte'),
            'missing-customer': ('customer.sql', None, '[CHECK FAILED:'),
        }
        modes = {'cancel': 2, 'precheck-fail': 1, 'decline': 2, 'confirm': 0}
        modes.update(dict.fromkeys(blocked, 1))
        for mode, expected_code in modes.items():
            flow_root = temp / mode
            flow_root.mkdir()
            fixtures = {
                'backup.sql': 'SELECT \'中文\';\n'.encode('utf-8-sig'),
                # Start a multibyte character at the end of the first 4096-byte read.
                'customer.sql': ('--' + ' ' * 4093 + '中文\nSELECT 1;').encode('utf-8'),
            }
            if mode in blocked:
                filename, content, _ = blocked[mode]
                fixtures[filename] = content
            for filename, content in fixtures.items():
                if content is not None:
                    (flow_root / filename).write_bytes(content)
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
            confirmation = flow_root / 'confirmation.txt'
            failure = flow_root / 'encoding-blocked.txt'
            report = reports[0].read_text(encoding='utf-8-sig')
            if mode in blocked:
                assert not confirmation.exists(), f'{mode} offered execution'
                overview = failure.read_text(encoding='utf-8-sig')
                filename, _, expected_status = blocked[mode]
                for output in (overview, report):
                    assert any(filename in line and expected_status in line
                               for line in output.splitlines()), output
                    assert output.count('[UTF-8 OK]') == 1, output
                assert 'FINAL STATUS: FAILED' in report
            elif mode in ('decline', 'confirm'):
                assert not failure.exists()
                overview = confirmation.read_text(encoding='utf-8-sig')
                assert 'Script encoding check: PASS' in overview
                assert overview.count('[UTF-8 OK]') == report.count('[UTF-8 OK]') == 2
            print(f'PASS: startup {mode}, local stage log, execution gate', flush=True)


if __name__ == '__main__':
    main()
