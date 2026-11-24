#!/usr/bin/env python3
import os
import sys
import time
from pathlib import Path

args = sys.argv[1:]
assert '-w' in args
assert args[args.index('-P') + 1] == 'pager=off'
assert args[args.index('-h') + 1] == 'host with spaces'
assert args[args.index('-d') + 1] == 'test_db'
assert args[args.index('-c') + 1].startswith("SELECT '__PG_RUNNER_PREFLIGHT__|'")
assert os.environ['PGCONNECT_TIMEOUT'] == '10'
assert os.environ.get('PSQL_PAGER', '') == ''
assert os.environ['PGPASSWORD'] == 'mock-only-secret'
assert sys.stdin.read() == ''
mode = os.environ['MOCK_MODE']
if mode == 'hang':
    Path(os.environ['PSQL_TEST_PID']).write_text(str(os.getpid()))
    time.sleep(120)
elif mode == 'auth-fail':
    print('FATAL: password authentication failed', file=sys.stderr)
    sys.exit(2)
elif mode == 'invalid':
    print('unexpected result')
elif mode == 'mismatch':
    print('__PG_RUNNER_PREFLIGHT__|other_db|test_user|127.0.0.1|5026|16.1')
elif mode == 'flood':
    for _ in range(4000):
        print('out' * 100)
        print('err' * 100, file=sys.stderr)
    sys.exit(2)
else:
    print('__PG_RUNNER_PREFLIGHT__|test_db|test_user|127.0.0.1|5026|16.1')
