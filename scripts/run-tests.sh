#!/bin/bash
# Regression runner: boots every mode and checks the results.
#   ./scripts/run-tests.sh          everything (about 5 minutes under emulation)
#   ./scripts/run-tests.sh quick    skip the GDB session
# Logs go to build/test-*.log. Exit status = number of failed checks.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
QUICK=${1:-}
pass=0; fail=0

ok()   { printf '  [ PASS ] %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  [ FAIL ] %s\n' "$1"; fail=$((fail + 1)); }
expect() {   # expect <log> <extended regex> <description>
    if grep -aqE "$2" "$1"; then ok "$3"; else bad "$3   (pattern: $2, log: $1)"; fi
}
refuse() {   # refuse <log> <extended regex> <description>: pattern must be ABSENT
    if grep -aqE "$2" "$1"; then bad "$3   (found: $2, log: $1)"; else ok "$3"; fi
}
boot() {     # boot <logfile> <timeout> <run-qemu args...>
    local log=$1 t=$2; shift 2
    timeout "$t" ./scripts/run-qemu.sh "$@" 2>&1 | tr -d '\r' > "$log"
}

echo "== 0. static checks"
if [ -f "${KDIR:-../work/linux}/scripts/checkpatch.pl" ]; then
    ./scripts/checkpatch.sh >build/test-checkpatch.log 2>&1 && ok "checkpatch clean" || bad "checkpatch findings (build/test-checkpatch.log)"
else
    echo "  [ skip ] checkpatch (no kernel tree; set KDIR)"
fi
for f in scripts/*.sh rootfs/init rootfs/selftest.sh rootfs/gdbdemo.sh; do
    bash -n "$f" 2>/dev/null || sh -n "$f" 2>/dev/null || bad "syntax error in $f"
done
ok "shell scripts parse"

echo "== 1. Device Tree boot (autotest + deliberate oops)"
L=build/test-dt.log; boot $L 300 autotest oopsdemo
expect $L 'probed via Device Tree'                      "platform_driver bound through the DT node"
expect $L '\[ PASS \] software-raised IRQ reached'      "interrupt handler ran"
expect $L '[0-9]+: +[1-9][0-9]* +GIC-0 .*mychardev'    "interrupt visible in /proc/interrupts"
expect $L '== ALL PASSED \(0 failures\) =='             "user-space test program: all checks"
expect $L 'lseek\(-2, SEEK_END\) == 3'                  "lseek SEEK_END check ran"
expect $L 'stats count opens, reads and writes'         "sysfs stats consistent with user space"
expect $L 'stress OK \(20 cycles\)'                     "20 load/unload cycles"
expect $L 'fault signatures in dmesg: 0$'               "no kernel faults before the deliberate oops"
expect $L 'fault signatures in dmesg: [1-9][0-9]* \(control' "fault detector fires on the deliberate oops (control)"
refuse $L 'buffer_size module parameter'                "no-DT step skipped when DT node present"

echo "== 2. oops -> source line"
T=build/test-trace.log; ./scripts/trace-oops.sh $L > $T 2>&1
expect $T 'oopsdemo_write_null\+0x14'                   "PC resolved to oopsdemo_write_null+0x14"
expect $T '\*p = 0xdead'                                "source line text shown (the faulting statement)"

echo "== 3. no-DT boot (fallback path + module parameter)"
L=build/test-nodt.log; boot $L 300 nodt autotest
expect $L 'no DT node found'                            "fallback path taken"
expect $L 'SKIP.*no IRQ wired up'                       "IRQ test skipped cleanly"
expect $L '== ALL PASSED \(0 failures\) =='             "user-space test program: all checks"
expect $L 'capacity = 8192 bytes'                       "buffer_size=8192 applied"
expect $L 'buffer_size=0 rejected'                      "buffer_size=0 rejected"
expect $L 'above the maximum rejected'                  "oversized buffer_size rejected"

if [ "$QUICK" != quick ]; then
    echo "== 4. GDB against QEMU's gdbstub"
    if command -v gdb-multiarch >/dev/null 2>&1; then
        L=build/test-gdb.log; timeout 400 ./scripts/gdb-demo.sh > $L 2>&1
        expect $L '^Breakpoint 1, mychar_write'         "stopped inside the module's write handler"
        expect $L 'ksys_write'                          "kernel call stack shows the syscall path"
        expect $L '"hello gdb\\n"'                      "kernel buffer content visible in GDB"
    else
        echo "  [ skip ] gdb-multiarch not installed"
    fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
exit "$fail"
