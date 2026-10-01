/// A fixed read-only probe; user input is never interpolated into remote code.
struct RemoteRuntimeProbeScript {
    let source = #"""
import json, os, subprocess
with open('/opt/cmux/runtime.json') as f:
    marker = json.load(f)
with open('/data/.cmux/runtime.json') as f:
    saved = json.load(f)
binary = json.loads(subprocess.check_output(['/opt/cmux/bin/cmux-tui', 'remote-probe', '--json'], timeout=15))
print(json.dumps({
    'kind': marker['kind'], 'digest': marker['digest'],
    'mounted': os.path.ismount('/data'),
    'home': os.path.realpath(os.path.expanduser('~')),
    'workspace': os.path.realpath('/workspace'),
    'ready': saved == marker and os.path.isfile('/run/cmux-runtime-ready'),
    'binary': binary
}))
"""#
}
