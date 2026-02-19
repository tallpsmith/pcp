# macOS QA Failure Investigation Tracker

Tracks remaining QA failures on the `macos-qa-uplift` branch. Updated as each group is
investigated. Goal: surface and fix real macOS bugs, not paper over them.

## Status Summary

| Group | Tests | Status | Pass 5 |
|-------|-------|--------|--------|
| 1 — Confident fixes | 031, 112, 338 | **FIXED** | ✓ committed |
| 2 — pmlogger/pmie stability | 107, 055 | Open | — |
| 3 — Archive domain labels | 369, 1418, 707 | Open | — |
| 4 — Python pmapi compat | 702, 707 | Open | — |
| 5 — Behavioral/timing | 155, 354 | Open | — |

---

## Group 1: Confident Fixes (DONE — Pass 5)

### Test 338 — sed ordering in _filter()

**Root cause**: On macOS `/tmp` is a symlink to `/private/tmp`. When `$tmp` is set to
`/private/tmp/pcp-338-XXXX` (the real path), running the `/private/tmp→/tmp` substitution
first changes the path to `/tmp/pcp-338-XXXX`, after which the `$tmp→TMP` substitution no
longer matches.

**Fix**: In `qa/338 _filter()`, swap the two sed lines so `$tmp→TMP` runs first (while the
path is still intact), then `/private/tmp→/tmp` normalises any remaining instances.

**Files changed**: `qa/338`

---

### Tests 031 and 112 — Darwin PMDA swap PMNS entry

**Root cause**: The darwin PMDA gained a `swap` top-level PMNS entry (alongside `disk`,
`mem`, etc.). The `031.out.darwin` reference output predates this addition. Test 112 also
uses `031.out.darwin` as its reference.

**Fix**: Added `    swap                <s = 1>` after `sampledso` in the `children of ""`
section of `qa/031.out.darwin`. Alphabetical order: s-w > s-a.

**Files changed**: `qa/031.out.darwin`

---

## Group 2: pmlogger/pmie Runtime Stability

**Tests**: 107, 055
**Status**: Open — needs focused debugging session

### Test 107 — pmlogger IPC socket disappears mid-pmlc session

**Symptom**: pmlogger's control socket vanishes ~63 seconds after start, causing pmlc to
lose connection. Test fails with socket/connection errors.

**Hypothesis**: pmlogger may be crashing or exiting on macOS due to:
- A timeout (63s is suspiciously round — check signal handler or select() timeout)
- A signal difference (macOS signals SIGALRM, SIGPIPE handling)
- Resource exhaustion or file descriptor leak

**Investigation approach**:
```bash
# Run test with full pmlogger debugging
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 107 -v

# Check for crash logs
ls -la /var/log/pcp/pmlogger/
cat /var/log/pcp/pmlogger/*.log

# Look at pmlogger SIGALRM handler (alarm-based timeout?)
grep -r 'SIGALRM\|alarm(' src/pmlogger/
```

**Key files to examine**: `src/pmlogger/control.c`, `src/pmlogger/ports.c`,
`src/pmlogger/logger.h`

---

### Test 055 — pmie extra evaluation cycle with `unknown`

**Symptom**: pmie produces one extra evaluation cycle at the end of the run showing
`unknown` values instead of terminating cleanly.

**Hypothesis**: Timing or scheduler difference in pmie's macOS implementation. The extra
cycle may be triggered by SIGTERM handling or by a clock difference causing one additional
rule evaluation before exit.

**Investigation approach**:
```bash
# Run test with pmie debug output
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 055 -v

# Diff actual vs expected
diff 055.out.bad 055.out

# Look at pmie exit/signal handling on Darwin
grep -r 'SIGTERM\|atexit\|__pmtimevalNow' src/pmie/
```

**Key files to examine**: `src/pmie/eval.c`, `src/pmie/dstruct.c`

---

## Group 3: Archive Domain Label Encoding

**Tests**: 369, 1418, 707
**Status**: Open — needs archive inspection

### Tests 369 and 1418 — domain label value mismatch

**Symptom**:
- Got:      `domain=245  Domain 1027604480 labels`
- Expected: `domain=0    Domain 245 labels`

**Hypothesis**: `1027604480 = 245 << 22` — this is the raw PMID-packed form (domain shifted
into PMID bits) rather than the plain domain number. The domain label is being serialised
or deserialised using the wrong field. May be:
- A bug in `pmdumplog`'s label printing code
- A byte-ordering issue in archive label I/O on macOS
- A regression in how `__pmLogLoadLabel()` unpacks the domain

**Investigation approach**:
```bash
# Run tests to get full diff
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 369 -v 2>&1 | tee /tmp/369.log
sudo -u pcpqa ./check 1418 -v 2>&1 | tee /tmp/1418.log

# Inspect the archives used
pmdumplog -l archives/...   # identify which archives

# Look at label serialisation code
grep -rn 'domain.*label\|PM_LABEL_DOMAIN' src/libpcp/src/logutil.c
grep -rn 'domain.*label\|PM_LABEL_DOMAIN' src/pmlogrewrite/
```

**Key files**: `src/libpcp/src/logutil.c`, `src/libpcp/src/label.c`,
`src/pmdumplog/pmdumplog.c`

---

### Test 707 — Python pmapi archive test truncated output

**Symptom**: Test produces `archive -` only (no "OK"), fails to open or process archive.

**Hypothesis**: May be related to the domain label encoding mismatch in Group 3 (can't
parse archive created with wrong encoding), OR may be a Python pmapi issue (see Group 4).

---

## Group 4: Python pmapi Compatibility

**Tests**: 702, 707
**Status**: Open — needs Python traceback

### Test 702 — Python pmapi live test: no "OK"

**Symptom**: `test_pcp.py` runs but produces no "OK" from unittest. Either crashes silently
or assertions fail.

**Hypothesis**: Line 26 of `test_pcp.py` contains `type(long())` — Python 2 only. This
throws `NameError: name 'long' is not defined` in Python 3. macOS CI uses Python 3.

However, `dump_seq()` (which contains `long()`) may not be on the hot test path. Need the
actual traceback to confirm.

**Investigation approach**:
```bash
# Run test_pcp.py directly to get full traceback
cd /var/lib/pcp/testsuite
python3 src/test_pcp.py 2>&1 | head -50

# Check for Python 2/3 issues
grep -n 'long()\|print \|basestring\|unicode(' src/test_pcp.py

# Check darwin PMDA metric availability
pminfo kernel.all.load mem.physmem
```

**Key files**: `qa/src/test_pcp.py`, `qa/src/test_pcp_archive.py`

---

## Group 5: Behavioral / Timing

**Tests**: 155, 354
**Status**: Open — needs local reproduction

### Test 155 — PM_ERR_AGAIN: first loop succeeds when it should fail

**Symptom**: First iteration (i=no) succeeds when the PMDA "not ready" protocol should
cause it to fail with PM_ERR_AGAIN. The not-ready handshake isn't working on macOS.

**Hypothesis**: The sample PMDA's "not ready" mechanism uses credential-passing or IPC
that behaves differently on macOS when connecting via hostname vs local socket. May be a
difference in how `AF_UNIX` vs `AF_INET` connections are authenticated.

**Investigation approach**:
```bash
# Run test with full tracing
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 155 -v

# Look at PMDA not-ready protocol
grep -rn 'PM_ERR_AGAIN\|not.ready\|PMDA_INTERFACE' src/pmdas/sample/
grep -rn 'PM_ERR_AGAIN' src/libpcp/src/
```

---

### Test 354 — pmRecord/pmafm path normalization dialog differs

**Symptom**: Dialog message content differs on macOS — likely path normalization producing
`/private/tmp/...` vs `/tmp/...` in user-facing messages.

**Hypothesis**: The same `/private/tmp` symlink issue as test 338, but in pmafm output.
The filter patterns in `354` may need updating for macOS.

**Investigation approach**:
```bash
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 354 -v
diff 354.out.bad 354.out

# Check if filter needs /private/tmp normalisation
grep -n 'private\|/tmp' qa/354
```

---

## Notes for Future Sessions

- Always run failing tests with `-v` to get `.full` debug output
- Upload `/var/log/pcp/` from CI runs for pmcd/pmlogger/pmie crash analysis
- Check `$seq.full` file (in testsuite dir) for extended debug output after a test run
- Reference: `build/mac/plans/MACOS_QA_IMPLEMENTATION_PLAN.md` for broader context
