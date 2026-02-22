# macOS QA Failure Investigation Tracker

Tracks remaining QA failures on the `macos-qa-uplift` branch. Updated as each group is
investigated. Goal: surface and fix real macOS bugs, not paper over them.

**Latest run**: #22203952418 — 2026-02-19 23:08 UTC — `f3bcd13c` (Pass 6)
**Stats**: Ran 80 | Passed 72 | **Failed 8**

**Branch HEAD** (unrun): `a5a4e90` — fixes for 702, 1204, 256 committed; 354 diagnostic step added to workflow

---

## Status Summary

| Group | Tests | Status |
|-------|-------|--------|
| A — Python/archive investigation needed | 707 | Open |
| B — Python ctypes repr / binding compat | 702, 707 | 702 **FIXED** ✓ (Pass 7 pending); 707 Open |
| C — pmlogger daemon cascade (macOS timing) | 068, 107 | Open |
| D — Individual output mismatches | 155, 256, 354, 1204 | 256 **FIXED** ✓, 1204 **FIXED** ✓ (Pass 7 pending); 155 Open; 354 **IN PROGRESS** 🔍 |
| E — Perl sort order (LC_COLLATE=POSIX macOS bug) | 369, 1418 | **FIXED** ✓ (Pass 6) |
| Z — Fixed (Pass 1–6) | 031, 112, 338, 437, 055, 369, 1418 | **FIXED** ✓ |

---

## Group A: Test 707 — Python/Archive Investigation Needed

**Tests**: 707
**Failures**: 1

Test 707 (Python) was originally grouped here as an "archive format v3" failure, but
that diagnosis was wrong for 369 and 1418 (see Group E). Test 707 still needs
independent investigation — its `.full` is a single empty line, suggesting it aborts
early.

**Investigation approach**:
```bash
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 707 -v 2>&1 | tee /tmp/707.log
cat /var/lib/pcp/testsuite/707.full
```

**Key files**: `qa/707`, `src/python/pcp/pmapi.py`

---

## ~~Group A original: Archive Format v3 vs v2~~ — DIAGNOSIS WAS WRONG

**Original claim**: Tests 369, 1418, 707 fail because `libpcp_import` writes v3 archives
and the tests expect v2.

**Why this was wrong**:

1. `PCP_ARCHIVE_VERSION=3` is in the **universal** `pcp.conf.in` — not Darwin-specific.
   Both Linux and macOS installs get it. Linux tests still pass.

2. Tests 369 and 1418 are a **complementary pair**, not equivalents:
   - `qa/369`: runs `check_import -V2`, expects `Log Format Version 2`
   - `qa/1418`: runs `check_import -V3`, expects `Log Format Version 3`
   Test 1418's reference file correctly expects v3. There is no "all expect v2" issue.

3. The actual `369.out.bad` diff (verified against CI run #22171493521) shows **zero**
   differences in the C section or archive output. The entire 175-line diff is confined
   to the Perl `PCP::LogImport` symbol dump — a sort order issue (see Group E).

---

## Group E: Perl Sort Order — LC_COLLATE=POSIX macOS Incompatibility

**Tests**: 369, 1418
**Failures**: 2
**Root cause**: `LC_COLLATE=POSIX sort` does not enforce byte-value (ASCII) ordering on
macOS. Linux treats it as case-sensitive (uppercase before lowercase); macOS treats it as
case-insensitive, scrambling the output.

**What the tests do**: Both 369 and 1418 run `check_import.perl` which dumps the full
`PCP::LogImport` namespace using `foreach (%PCP::LogImport::)`. Since Perl hash iteration
order is non-deterministic, the test's `_filter3()` function sorts part1 of the output:

```bash
_filter3()
{
    $PCP_AWK_PROG '
BEGIN       { part = "part1" }
NF == 0     { part = "part2" }
            { print >part }'
    if [ -f part1 ]
    then
        # first part of output is in non-deterministic order, so sort it
        _filter1 <part1 | LC_COLLATE=POSIX sort    # ← broken on macOS
    fi
    [ -f part2 ] && _filter1 <part2
}
```

**The mismatch**: The reference `369.out` was generated on Linux with correct byte-value
ordering — uppercase before lowercase:

```
*PCP::LogImport::PMI_DOMAIN     ← P (0x50) — before lowercase
*PCP::LogImport::VERSION        ← V (0x56)
*PCP::LogImport::a              ← a (0x61) — lowercase after uppercase
*PCP::LogImport::bootstrap
```

On macOS, `LC_COLLATE=POSIX sort` sorts case-insensitively, so `a` (treated as `A`)
lands before `P`, producing a completely different ordering. The entire 175-line diff
is this reshuffling of symbol names — no archive or functional difference at all.

**Fix**: Change `LC_COLLATE=POSIX sort` → `LC_ALL=C sort` in `_filter3()` inside both
`qa/369` and `qa/1418`. `LC_ALL=C` properly overrides all locale settings on macOS,
enforcing byte-value ordering consistent with the Linux-generated reference files.

No changes to `.out` reference files needed — the sorted output will match as-is.

**Key files**: `qa/369` (lines ~41–54, `_filter3`), `qa/1418` (same pattern)

---

## Group B: Python ctypes Repr / Binding Compat

**Tests**: 702, 707
**Failures**: 2 (707 also in Group A)

### Test 702 — **FIXED** ✓ (commit `a5a4e90`, Pass 7 pending)

**Root cause**: Two issues in `qa/702`:
1. Hostname filter used a literal hostname — replaced with platform-independent pattern
2. `pmGetChildren` output order is non-deterministic between Linux and macOS; added a sort

**Fix**: Updated `qa/702` to use generic hostname filtering and sort `pmGetChildren` output.

### Test 707 — Open

**Symptom**: `.full` is a single empty line — test aborts very early.

**Investigation approach**:
```bash
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 707 -v 2>&1 | tee /tmp/707.log
cat /var/lib/pcp/testsuite/707.full
```

**Key files**: `qa/707`, `qa/src/test_pcp.py`, `qa/src/test_pcp_archive.py`, `src/python/pcp/pmapi.py`

---

## Group C: pmlogger Daemon Cascade (macOS Timing)

**Tests**: 068, 107
**Failures**: 2 — cascade: 068 fails and leaves daemon state broken for 107

### Test 068 — pmlogger fails to restart after pmcd kill (cascade root)

**Symptom**: Test 068 exercises the "pmcd gone" scenario — deliberately kills pmcd
and waits for pmlogger to re-establish on restart. On the macOS GitHub Actions runner
pmlogger gets SIGTERM during the kill cycle and pmcd fails to come back within the
20-second wait budget:

```
Arrgh ... pmlogger (primary) failed to start after 20 seconds
pmprobe: Cannot connect to PMCD on host "local:": Connection refused
Unable to connect to primary pmlogger at local:: Connection refused
Boot-out failed: 5: Input/output error
```

**Root cause**: Timing — the macOS GitHub Actions runner is slower than the test's
baseline. The 20-second wait for pmcd/pmlogger restart is insufficient on this hardware.

**Cascade effect**: 068 leaves the daemon in a broken state. Test 107 then inherits
it: cannot connect to the primary pmlogger, finds zero metrics, and fails both
"at least one metric logging" and "at least 250 metrics" assertions.

**Investigation approach**:
```bash
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 068 -v 2>&1 | tee /tmp/068.log
cat /var/log/pcp/pmlogger/*.log

# Look for timing constants in the test
grep -n 'wait\|sleep\|timeout\|20' qa/068
```

**Key files**: `qa/068`, `qa/107`, `src/pmlogger/control.c`, `src/pmlogger/ports.c`

---

### Test 107 — pmlc loses pmlogger connection (cascade victim)

**Symptom**: Inherits broken daemon state from 068. pmlc cannot connect to the
primary pmlogger at all — finds zero metrics and fails metric-count assertions:

```
Unable to connect to primary pmlogger at local:: Connection refused
Error [<stdin>, line 2]
Not connected to any pmlogger instance
```

**Note**: If 068 is fixed (daemon restarts cleanly), 107 will likely pass on its own.
Investigate 068 first before touching 107's internals.

**Key files**: `src/pmlogger/control.c`, `src/pmlogger/ports.c`, `src/pmlogger/logger.h`

---

## Group D: Individual Output Mismatches

**Tests**: 155, 256, 354, 1204
**Failures**: 4 (each independent — different root causes)

### Test 155 — PM_ERR_AGAIN: first loop succeeds when it should fail

**Symptom**: First iteration (i=no) succeeds when the sample PMDA "not ready"
protocol should cause it to fail with `PM_ERR_AGAIN`.

**Hypothesis**: The sample PMDA's not-ready IPC handshake behaves differently on
macOS, possibly due to `AF_UNIX` vs `AF_INET` authentication differences.

```bash
cd /var/lib/pcp/testsuite
sudo -u pcpqa ./check 155 -v
grep -rn 'PM_ERR_AGAIN\|not.ready\|PMDA_INTERFACE' src/pmdas/sample/
```

---

### Test 256 — **FIXED** ✓ (commit `59214fe`, Pass 7 pending)

**Root cause**: Global derived metric configs (`src/derived/proc.conf`) reference
Linux-only `proc.io.*` metrics that don't exist on macOS. This produces
"Semantic error: derived metric" messages that leaked through `_filter_derived()`'s
grep (because they contain "derived"), adding 2 extra lines to the output.

**Fix**: Added a `sed` expression in `qa/256` to suppress these platform-specific
errors. No-op on Linux where the errors don't occur.

---

### Test 354 — IN PROGRESS 🔍 (pmlogger FQDN connectivity)

**Symptom**: pmlogger instances targeting `$host` (the macOS FQDN) never create
archive files (`.0/.index/.meta`). The `.log` and `.config` files DO exist — pmlogger
started — but it apparently fails to connect to pmcd via the FQDN.

**Known facts from pmcd.log**:
- pmcd resolved `localhost` → `192.168.64.23` (not `127.0.0.1`)
- Host access list: `localhost (192.168.64.23)` and `unix:` → ALLOWED; `0.0.0.0` → DENIED
- pmcd's hostname is the long FQDN (`iad20-fj917-...local`)

**Three possible failure modes**:
1. FQDN doesn't resolve (mDNS broken in CI) → pmlogger gets "host not found" immediately
2. FQDN resolves to a different IP (not 192.168.64.23) → pmcd access control denies it
3. pmcd only binds to loopback (127.0.0.1), not 192.168.64.23 → connection refused on FQDN

**Action**: Diagnostic step added to `qa-macos.yml` (after "Start pmie") — will run in
next CI push. Step checks FQDN resolution, pmcd listening interfaces, and `pmprobe -h $(hostname)`.

**Previous attempt**: LC_ALL=C sort fix (`bbd1b77`) was reverted (`da723c5c`) — not the right fix.

**Expected finding**: `pmprobe -h $(hostname)` fails AND lsof shows pmcd only on `127.0.0.1:44321`
(not `*:44321`), meaning FQDN connections go to an address pmcd isn't listening on.

**Next step**: Await diagnostic CI run output to confirm failure mode, then:
- If FQDN doesn't resolve: replace `$host` with `localhost` in `record` calls on Darwin
- If pmcd only on loopback: fix pmcd startup to bind all interfaces, OR use localhost on Darwin

**Key files**: `qa/354`, `.github/workflows/qa-macos.yml`

---

### Test 1204 — **FIXED** ✓ (commit `a5a4e90`, Pass 7 pending)

**Root cause**: On macOS, pmlogger startup log lines (prefixed with `+`) leaked to stdout
due to fd inheritance differences when `pmlogger_check` is invoked via `runaspcp`'s
`sh -c` wrapper. The `<pid>` filter in the test also had a date-collision problem
(`Feb <pid>` day-of-month digits matched as PID).

**Fix**: Added filter in `qa/1204` to suppress these leaked pmlogger startup log lines.

**Key files**: `qa/1204`, `src/pmlogger/pmlogctl`

---

## Completed Fixes (Pass 1–7)

| Test(s) | Fix | Pass |
|---------|-----|------|
| 031, 112 | Added `swap <s=1>` to `qa/031.out.darwin` PMNS reference | 5 |
| 338 (sed) | Swapped `$tmp→TMP` before `/private/tmp→/tmp` in `_filter()` | 5 |
| Various | Set `DYLD_LIBRARY_PATH` in `qa/common.rc` for library linking | 1–2 |
| Various | Rpath embedded in testsuite binaries via `GNUmakefile.install` | 3 |
| Various | PMNS `Rebuild` called explicitly in CI after `make install` | 2 |
| 055, 338, 437, 369, 1418 | `LC_ALL=C` sort fix in QA Darwin environment (`f3bcd13c`) | 6 |
| 256 | Filter Linux-only `proc.io.*` derived metric semantic errors in `qa/256` (`59214fe`) | 7 |
| 702 | Platform-independent hostname filter + sort `pmGetChildren` output (`a5a4e90`) | 7 |
| 1204 | Filter leaked pmlogger startup log lines on macOS (`a5a4e90`) | 7 |

---

## Session Notes

- Always run failing tests with `-v` to get `.full` debug output
- Upload `/var/log/pcp/` from CI runs for pmcd/pmlogger/pmie crash analysis
- Check `$seq.full` in the testsuite dir for extended debug after a test run
- Reference: `build/mac/plans/MACOS_QA_IMPLEMENTATION_PLAN.md` for broader context
- **Always verify a diagnosis against the actual `.out.bad` artifact before trusting it**
  — the original Group A analysis was completely wrong; the real issue was `LC_COLLATE`
- `gh run download <run-id> --name "qa-logs" --dir /tmp/...` to fetch test artifacts
- `diff qa/NNN.out /path/to/NNN.out.bad` gives the exact mismatch for any failing test
- Group E (Perl sort, 369+1418) **DONE** — fixed by `LC_ALL=C` in Pass 6
- Group D partial (256, 702, 1204) **DONE** in Pass 7 — awaiting CI confirmation
- Test 354 diagnostic step added to workflow — awaiting next CI run to identify failure mode
- Group C (daemon cascade, 068→107) is highest-leverage remaining target: one root cause, two failures
- Test 707 appears in Group A and Group B — investigate independently, its `.full` is near-empty
