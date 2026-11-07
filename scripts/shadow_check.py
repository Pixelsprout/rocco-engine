#!/usr/bin/env python3
"""Check live shadow values and startup presets on the native backend."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

import bridge
from bridge_check import binary_suffix, check


def run_case(label, args, out, logs):
    port = bridge.free_port()
    binary = Path('examples/mask/mask' + binary_suffix()).resolve()
    command = shlex.split(os.environ.get('RUN_PREFIX', '')) + [str(binary), *args]
    log_path = Path(logs) / (label + '.log')
    with log_path.open('w') as log:
        process = subprocess.Popen(command, cwd=binary.parent,
                                   env=dict(os.environ, ROCCO_BRIDGE=str(port)),
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            with bridge.Bridge.connect(port, wait=60) as driver:
                driver.hello()
                driver.step(1, tap=['Space'])
                default = driver.scene()['scene']['shadow']
                check(default == dict(distance=0, normal_bias=0.05, depth_bias=0,
                                      distribution=0.5, blend=0.1, filter='Pcf3'), 'default shadow appearance')
                shots = []
                for key, name, distance in [('L', 'Hard', 60), ('B', 'Pcf3', 150), ('H', 'Pcf5', 200)]:
                    driver.step(1, tap=[key])
                    settings = driver.scene()['scene']['shadow']
                    check(settings['filter'] == name and settings['distance'] == distance, 'live appearance preset')
                    path = out / (label + '-' + name + '.png')
                    driver.screenshot(str(path))
                    shots.append(path)
                before = driver.scene()['scene']['shadow']
                driver.step(30, held=['Up', 'K', 'T', 'I', 'M'])
                after = driver.scene()['scene']['shadow']
                check(all(after[field] > before[field] for field in
                          ('distance', 'normal_bias', 'depth_bias', 'distribution', 'blend')), 'live numeric controls')
                check(shots[0].read_bytes() != shots[-1].read_bytes(), 'appearance changes the rendered frame')
                driver.quit()
            check(process.wait(timeout=15) == 0, 'game exits after quit')
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=15)
    text = log_path.read_text()
    check('[error]' not in text.lower() and 'VALIDATION_FAILED' not in text, 'native graphics validation')
    return dict(case=label, args=args, effective_default=default, live=after, result='passed')


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/shadow-check').resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='shadow-check-') as logs:
        cases = [run_case(label, args, out, logs) for label, args in
                 [('single', []), ('multiple', ['--far-shadows']),
                  ('startup-low', ['--shadow-low']), ('startup-high', ['--shadow-high'])]]
    (out / 'shadow-evidence.json').write_text(json.dumps(dict(cases=cases, result='passed'), indent=2) + '\n')


if __name__ == '__main__':
    main()
