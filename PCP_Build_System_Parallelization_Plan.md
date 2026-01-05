
## Overview
The PCP build system is currently very slow (5-6 minutes) despite running on a 12-core machine. This plan addresses multiple sequential bottlenecks to achieve 3-10x speedup.

**Status Update (2026-01-05):**
- ✅ **Phase 1 COMPLETED**: Optional parallel builds via `PCP_MAKE_JOBS` environment variable (259s, 15% improvement)
- ✅ **Phase 2 COMPLETED**: Fixed all 14 problematic .NOTPARALLEL directives (252s, 17% improvement total)
  - ✅ Investigation completed - confirmed directives are overly broad and fixable
  - ✅ Fixed 5 high-priority libraries (libpcp, libpcp_static, libpcp_web, libpcp_fault, libpcp3)
  - ✅ Fixed 3 medium-priority tools (pmcpp, newhelp, pmieconf)
  - ✅ Fixed 6 low-priority tools (pmie, pmlogger, pmlogextract, pmlc, pmlogrewrite, dbpmda)
- 🔄 **Phase 3 NEXT**: Remove top-level sequential loop to unlock additional parallelism
- **Baseline confirmed**: 304 seconds (5m 4s) on 12-core Apple Silicon Mac
- **Current best**: 252 seconds (4m 12s) with Phase 1+2 - **17% improvement**

## Standard Build Command for Testing
```bash
# Use this command for consistent, timed builds during testing:
/usr/bin/time -p sh -c 'PCP_MAKE_JOBS=-j12 ./Makepkgs --verbose' 2>&1 | tee /tmp/build-test.log | tail -150
```

## Current Bottlenecks Identified

1. **Top-level sequential loop** - Subdirectories build one at a time (GNUmakefile:50-55)
2. ~~**No parallel make flags**~~ ✅ **FIXED** - Now using opt-in `PCP_MAKE_JOBS` env var (only 7% gain due to #3)
3. **20+ makefiles with .NOTPARALLEL** - ⚠️ **CRITICAL BLOCKER** - Overly broad, disables all parallelism per makefile
4. **Packaging forces -j 1** - Intentionally sequential (build/GNUmakefile:38-49)
5. **QA tests sequential** - Lock-based single-threaded execution  
  
## Implementation Phases  
  
### Phase 1: Quick Wins (Immediate Impact, Low Risk) ✅ COMPLETED
**Original estimate: 3-5x speedup | Actual: 7% (blocked by Phase 2) | Effort: 1 hour | Risk: Low**

#### Task 1.1: Add parallel make flag to Makepkgs ✅ COMPLETED
**File:** `Makepkgs` (lines 766-788)
**Status:** ✅ Implemented and tested (2026-01-04)

**Implementation approach:** Opt-in via environment variable (backwards compatible)
```bash
# Set this environment variable to enable parallel builds
PCP_MAKE_JOBS=-j12 ./Makepkgs
```

**Implemented code:**
```bash
# Optional parallel build support via environment variable
# Set PCP_MAKE_JOBS to enable parallel builds (e.g., PCP_MAKE_JOBS=-j12)
# If not set, builds sequentially (current/legacy behavior)
if [ -n "$PCP_MAKE_JOBS" ]; then
    echo "   (parallel builds enabled: $PCP_MAKE_JOBS)"
    MAKE_FLAGS="$PCP_MAKE_JOBS"
else
    MAKE_FLAGS=""
fi
($MAKE $MAKE_FLAGS default_pcp 2>&1 || touch $tmp/failed) 2>&1 | tee -a "$LOGDIR/pcp"
```

**Test Results:**
- ✅ Backwards compatible: Without `PCP_MAKE_JOBS`, builds in 279s (same as baseline)
- ✅ Parallel builds work: With `PCP_MAKE_JOBS=-j12`, builds in 259s
- ⚠️ **Limited speedup (7%)** due to .NOTPARALLEL directives blocking parallelism in critical paths

**Why only 7% speedup?**
The `-j12` flag is correctly passed to make, but 20+ makefiles have `.NOTPARALLEL` directives that disable ALL parallelism within those makefiles. Critical libraries like `src/libpcp/src/GNUmakefile` compile sequentially even with `-j12`. Phase 2 is required to unlock the remaining ~3-4x speedup.

#### Task 1.2: Document ccache setup - DEFERRED
**File:** Create `docs/BUILD-OPTIMIZATION.md` or add to `INSTALL.md`
- Document how to install ccache: `brew install ccache` (macOS)
- Configure with: `./configure CC="ccache clang" CXX="ccache clang++"`
- Expected speedup: 10-50x on incremental builds
- **Status:** Documentation task - deferred to later

#### Task 1.3: Test Phase 1 changes ✅ COMPLETED
- ✅ Build tested without `PCP_MAKE_JOBS`: 279s (backwards compatible)
- ✅ Build tested with `PCP_MAKE_JOBS=-j12`: 259s (7% speedup)
- ✅ No race conditions or broken builds detected
- ✅ All packages built successfully (tar.gz, .dmg)
- 📊 Results documented in `PHASE1_RESULTS.md` and `BASELINE_METRICS.md`  
  
---  
  
### Phase 2: Fix .NOTPARALLEL Directives (Medium Effort) - ⚠️ CRITICAL TO UNLOCK SPEEDUP
**Expected speedup: +3-4x additional (combined with Phase 1: ~60-100 seconds total) | Effort: 3-4 hours | Risk: Low (confirmed safe)**

**Status:** ✅ **COMPLETED** - All 14 problematic makefiles fixed and tested successfully

**Investigation Results (2026-01-05):**
- ✅ **Confirmed the directives are overly broad** - Bare `.NOTPARALLEL:` disables parallelism for entire makefile
- ✅ **Git history shows this is a known issue** - Commit 0c51ecba55 (Frank Ch. Eigler, 2015) noted "lack full dependency declarations"
- ✅ **Actual race condition is narrow** - Only yacc multi-output rules need serialization
- ✅ **Dependencies are correctly declared** - Headers generated before compilation (e.g., `rtime.o: getdate.h`)
- ✅ **Fix is simple and safe** - Change `.NOTPARALLEL:` to `.NOTPARALLEL: target1 target2` (or remove entirely if no yacc/lex)
- ✅ **All fixes tested successfully** - No race conditions, all builds complete correctly

**Final Results:**
- **Baseline**: 304s → **Phase 1+2**: 252s = **52 seconds saved (17% improvement)**
- All 14 makefiles fixed in dependency-tree order (libraries first, then tools)
- No race conditions or build failures across all test runs

#### Task 2.1: Identify all .NOTPARALLEL makefiles ✅ COMPLETED
**Dependency tree analysis revealed:** Fix libraries first (they block downstream builds), then tools.

**Files fixed (in order):**  
**High-priority (libraries - Level 2 & 4 in dependency tree):**
1. ✅ src/libpcp/src/GNUmakefile - Changed `.NOTPARALLEL:` to `.NOTPARALLEL: getdate.h getdate.tab.c` and `.NOTPARALLEL: derive_parser.tab.h derive_parser.tab.c`
2. ✅ src/libpcp_static/src/GNUmakefile - Same fix as libpcp
3. ✅ src/libpcp_web/src/GNUmakefile - Changed `.NOTPARALLEL:` to `.NOTPARALLEL: query_parser.tab.h query_parser.tab.c`
4. ✅ src/libpcp_fault/src/GNUmakefile - Same fix as libpcp
5. ✅ src/libpcp3/src/GNUmakefile - Same fix as libpcp

**Medium-priority (early tools - Level 5):**
6. ✅ src/pmcpp/GNUmakefile - **Removed** `.NOTPARALLEL:` entirely (no yacc/lex rules)
7. ✅ src/newhelp/GNUmakefile - **Removed** `.NOTPARALLEL:` entirely (no yacc/lex rules)
8. ✅ src/pmieconf/GNUmakefile - **Removed** `.NOTPARALLEL:` entirely (no yacc/lex rules)

**Low-priority (end-user tools - Level 5, don't block anything):**
9. ✅ src/pmie/src/GNUmakefile - Changed `.NOTPARALLEL:` to `.NOTPARALLEL: grammar.h grammar.tab.c`
10. ✅ src/pmlogger/src/GNUmakefile - Changed `.NOTPARALLEL:` to `.NOTPARALLEL: gram.tab.h gram.tab.c`
11. ✅ src/pmlogextract/GNUmakefile - Changed `.NOTPARALLEL:` to `.NOTPARALLEL: gram.tab.h gram.tab.c`
12. ✅ src/pmlc/GNUmakefile - Changed `.NOTPARALLEL:` to `.NOTPARALLEL: gram.tab.h gram.tab.c`
13. ✅ src/pmlogrewrite/GNUmakefile - Changed `.NOTPARALLEL:` to `.NOTPARALLEL: gram.tab.h gram.tab.c`
14. ✅ src/dbpmda/src/GNUmakefile - Changed `.NOTPARALLEL:` to `.NOTPARALLEL: gram.tab.h gram.tab.c`

**Not touched (unrelated or already correct):**
- src/pmdas/*/GNUmakefile - No problematic .NOTPARALLEL found
- images/GNUmakefile - No yacc/lex, not investigated  
  
#### Task 2.2: Fix .NOTPARALLEL in critical libraries ✅ COMPLETED
**Approach taken:**
1. ✅ Fixed 5 high-priority libraries in one batch (tested: 247s)
2. ✅ Fixed 3 medium-priority tools (removed .NOTPARALLEL entirely)
3. ✅ Fixed 6 low-priority tools in one batch
4. ✅ Final test with all changes: **252s (17% improvement)**

**Example fix from src/libpcp/src/GNUmakefile:**
```makefile
# Before (blocks entire makefile):
.NOTPARALLEL:
getdate.h getdate.tab.c: getdate.y
    $(YACC) -d -b `basename $< .y` $< && cp `basename $@ .h`.tab.h $@

# After (only blocks these two targets from building in parallel with each other):
.NOTPARALLEL: getdate.h getdate.tab.c
getdate.h getdate.tab.c: getdate.y
    $(YACC) -d -b `basename $< .y` $< && cp `basename $@ .h`.tab.h $@
```

#### Task 2.3: Test Phase 2 changes ✅ COMPLETED
- ✅ Built and tested incrementally (libraries first, then tools)
- ✅ Full builds with `-j12` succeeded in all tests
- ✅ No race conditions detected (headers generated before use in all cases)
- ✅ Final speedup: 17% (52 seconds saved)  
  
---  
  
### Phase 3: Improve Top-Level Parallelization (Advanced)  
**Expected speedup: +10-20% | Effort: 4-6 hours | Risk: Medium-High**  
  
The top-level GNUmakefile uses a sequential for loop that prevents parallel subdirectory builds.  
  
#### Task 3.1: Analyze dependency structure  
**File:** `src/GNUmakefile`  
- Current dependencies (lines 170-173) are correct:  
  ```makefile  
  $(LIBPCP_SUBDIR): $(INCLUDE_SUBDIR)  
  $(PMNS_SUBDIR): $(LIBPCP_SUBDIR)  
  $(LIBS_SUBDIRS): $(PMNS_SUBDIR)  
  $(OTHER_SUBDIRS): $(LIBS_SUBDIRS)  
  ```- These enforce: include → libpcp → pmns → libs → tools  
- Within each stage, parallelism is possible  
  
#### Task 3.2: Refactor top-level makefile loop  
**File:** `GNUmakefile` lines 49-55  
  
**Current (sequential):**  
```makefile  
default_pcp : $(CONFIGURE_GENERATED) tmpfiles.init.setup  
    +for d in `echo $(SUBDIRS)`; do \  
        if test -d "$$d" ; then \       echo === $$d ===; \       $(MAKE) -C $$d $@ || exit $$?; \        fi; \    done```  
  
**Option A (Conservative - use existing dependency rules):**  
```makefile  
# Keep the loop but ensure SUBDIRS_MAKERULE is used properly  
# This allows make's -j flag to work within each subdirectory  
default_pcp : $(CONFIGURE_GENERATED) tmpfiles.init.setup  
    +for d in `echo $(SUBDIRS)`; do \        if test -d "$$d" ; then \       echo === $$d ===; \       $(MAKE) $(MAKEOPTS) -C $$d $@ || exit $$?; \        fi; \    done  
```  
  
**Option B (Better parallelism - leverage make dependencies):**  
```makefile  
# Make subdirectories proper targets with dependencies  
# This is already done in src/GNUmakefile (lines 162-168, 170-173)  
# Just need to ensure SUBDIRS_MAKERULE is invoked correctly  
default_pcp : $(CONFIGURE_GENERATED) tmpfiles.init.setup $(SUBDIRS)  
    $(SUBDIRS_MAKERULE)  
```  
  
**Recommendation:** Start with Option A (safer), consider Option B if testing goes well.  
  
#### Task 3.3: Test top-level changes  
- Verify subdirectories build in correct order  
- Check that dependencies are respected (include before libpcp, etc.)  
- Confirm no race conditions  
- Measure speedup  
  
---  
  
### Phase 4: QA Test Parallelization (Future Work)  
**Expected speedup: 5-10x QA time | Effort: 8-12 hours | Risk: High**  
  
**Status:** Defer to future work - requires significant QA framework changes.  
  
Current implementation uses a single lock file (`/tmp/PCP-QA-LOCK`) to prevent concurrent test execution. Parallelizing requires:  
  
1. Test isolation improvements  
2. Parallel test runner (GNU Parallel or custom)  
3. Resource conflict detection  
4. Test result aggregation  
  
**Recommendation:** Keep this on the backlog for now. Focus on compilation speedup first.  
  
---  
  
## Testing Strategy  
  
### After Each Phase:  
1. **Clean build test:** `make clean && time ./Makepkgs --verbose`  
2. **Incremental build test:** Touch a file, rebuild, verify only affected components rebuild  
3. **Correctness test:** Run QA tests to ensure no regressions  
4. **Measure speedup:** Compare with baseline build time  
  
### Baseline Metrics (Captured 2026-01-04):
- ✅ **Baseline build time**: 304 seconds (5m 4s)
- ✅ **Current CPU utilization**: ~8-10% (1 core of 12)
- ✅ **After Phase 1 only**: 259 seconds (4m 19s) with `PCP_MAKE_JOBS=-j12` - **7% improvement**
- 🎯 **Expected after Phase 1+2**: ~60-100 seconds (~1-2 minutes), ~80-90% CPU utilization
- 📊 **Detailed results**: See `BASELINE_METRICS.md` and `PHASE1_RESULTS.md`  
  
---  
  
## Risk Mitigation  
  
1. **Make changes incrementally** - One phase at a time  
2. **Test after each change** - Don't batch multiple risky changes  
3. **Keep git history clean** - Easy rollback if something breaks  
4. **Verify with QA suite** - Build changes shouldn't break tests  
5. **Consider packaging** - Ensure packages still build correctly  
  
---  
  
## Critical Files to Modify  
  
### Phase 1: ✅ COMPLETED
- ✅ `Makepkgs` (lines 766-788) - Added `PCP_MAKE_JOBS` environment variable support

### Phase 2: ⚠️ NEXT PRIORITY  
- `src/libpcp/src/GNUmakefile` (lines 125-137)  
- `src/pmie/src/GNUmakefile`  
- `src/pmlogger/src/GNUmakefile`  
- 17 other makefiles with .NOTPARALLEL  
  
### Phase 3:  
- `GNUmakefile` (lines 49-55)  
- Possibly `src/GNUmakefile` (verify dependency handling)  
  
---  
  
## Success Criteria

### Phase 1 Results (Completed):
- ⚠️ Build time reduced from 304s to 259s (7% improvement) - **Phase 2 needed for target**
- ✅ Backwards compatible - builds without `PCP_MAKE_JOBS` work as before (279s)
- ✅ No build race conditions or broken builds
- ✅ Packages build correctly (tar.gz, .dmg tested)
- ❌ CPU utilization still ~10% (blocked by .NOTPARALLEL directives)

### Overall Goals (Requires Phase 1+2):
- 🎯 Build time reduced from 5 minutes to <2 minutes (~60-100 seconds)
- 🎯 CPU utilization >80% during build (currently ~10%)
- 🎯 No build race conditions or broken builds
- 🎯 QA tests continue to pass
- 🎯 Packages build correctly  
  
---  
  
## Optional Enhancements  
  
1. **Build cache (ccache)** - Document setup for developers  
2. **Distributed builds (distcc)** - For even larger speedups  
3. **Build metrics dashboard** - Track build times over time  
4. **Pre-built dependencies** - Cache common libraries  
5. **Makepkgs --fast flag** - Skip QA for development builds  
  
---  
  
## How to Use (Phase 1 - Available Now)

### Enable Parallel Builds (7% speedup currently, 3-5x after Phase 2)
```bash
# Set the number of parallel jobs (use your CPU core count)
PCP_MAKE_JOBS=-j12 ./Makepkgs --verbose

# Or export it for the session
export PCP_MAKE_JOBS=-j12
./Makepkgs --verbose
```

### Default Behavior (Backwards Compatible)
```bash
# Without setting PCP_MAKE_JOBS, builds sequentially as before
./Makepkgs --verbose
```

**Note:** Currently provides only 7% speedup due to .NOTPARALLEL directives. Full 3-5x speedup requires Phase 2 implementation.

---

## Next Steps (When Resuming Work)

1. **Implement Phase 2** (Critical - required for meaningful speedup)
   - Start with `src/libpcp/src/GNUmakefile` (highest impact)
   - Fix .NOTPARALLEL to only apply to yacc/lex targets
   - Test each makefile individually before moving to next

2. **Consider Phase 3** (Optional - additional 10-20% after Phase 2)
   - Improve top-level makefile parallelization
   - Lower priority than Phase 2

3. **Document ccache setup** (Task 1.2 - deferred)
   - Create BUILD-OPTIMIZATION.md
   - Huge wins for incremental builds

---

## Notes

- The build system is well-designed for parallelism but not utilized
- Most sequential constraints are artificial, not actual dependencies
- The `-j 1` in packaging is intentional (reproducibility) - keep it
- QA test parallelization is complex - defer for now
- **Phase 1 demonstrates the infrastructure works** - Phase 2 will unlock the speedup