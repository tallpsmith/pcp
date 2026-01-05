
## Overview
The PCP build system is currently very slow (5-6 minutes) despite running on a 12-core machine. This plan addresses multiple sequential bottlenecks to achieve 3-10x speedup.

**Status Update (2026-01-05):**
- ✅ **Phase 1 COMPLETED**: Optional parallel builds via `PCP_MAKE_JOBS` environment variable (259s, 15% improvement)
- ✅ **Phase 2 COMPLETED**: Fixed all 14 problematic .NOTPARALLEL directives (252s, 17% improvement total)
  - ✅ Investigation completed - confirmed directives are overly broad and fixable
  - ✅ Fixed 5 high-priority libraries (libpcp, libpcp_static, libpcp_web, libpcp_fault, libpcp3)
  - ✅ Fixed 3 medium-priority tools (pmcpp, newhelp, pmieconf)
  - ✅ Fixed 6 low-priority tools (pmie, pmlogger, pmlogextract, pmlc, pmlogrewrite, dbpmda)
- ✅ **Phase 3A COMPLETED**: Refactored src/GNUmakefile for parallel subdirectory builds (238s, 22% improvement total)
- 🔄 **Phase 3B NEXT**: Refactor top-level GNUmakefile for additional 2-5% improvement
- **Baseline confirmed**: 304 seconds (5m 4s) on 12-core Apple Silicon Mac
- **Current best**: 238 seconds (3m 58s) with Phase 1+2+3A - **22% improvement**

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
**Expected speedup: +10-20% additional | Effort: 4-6 hours | Risk: Medium-High**
**Status:** 🔄 **Stage 3A COMPLETED** - src/GNUmakefile refactored, Stage 3B pending

#### Problem Analysis

**The Issue:**
Both top-level `GNUmakefile` and `src/GNUmakefile` use shell `for` loops to iterate through subdirectories:

```makefile
# GNUmakefile:49-55 and builddefs.in:401-407
+for d in `echo $(SUBDIRS)`; do \
    $(MAKE) -C $$d $@ || exit $$?; \
done
```

Even though `src/GNUmakefile` declares correct dependencies (lines 170-173):
```makefile
$(LIBPCP_SUBDIR): $(INCLUDE_SUBDIR)
$(PMNS_SUBDIR): $(LIBPCP_SUBDIR)
$(LIBS_SUBDIRS): $(PMNS_SUBDIR)
$(OTHER_SUBDIRS): $(LIBS_SUBDIRS)
```

**These dependencies only control the order in the shell loop, NOT make-level parallelization.**

The shell `for` loop serializes everything - make can't parallelize across the loop iterations even with `-j12`.

#### Why Was It Built This Way?

**Historical Context:**
1. **Recursive Make Pattern (1990s-2000s era)** - Each subdirectory has its own makefile
2. **Portability** - Shell loops work across all make implementations (BSD make, GNU make, etc.)
3. **Modularity** - Each component is self-contained and easy to maintain
4. **Known issue** - The paper "Recursive Make Considered Harmful" (Peter Miller, 1997) documented this exact problem

**What Modern C Projects Do:**

- **CMake/Meson/Ninja**: Build entire project from ONE makefile with full dependency graph. Parallel by default.
- **Linux Kernel (Kbuild)**: Uses proper target-based parallelism instead of shell loops
- **Proper Make Approach**: Each subdirectory becomes a real make target with dependencies:
  ```makefile
  include: ; $(MAKE) -C include default_pcp
  libpcp: include ; $(MAKE) -C libpcp default_pcp
  pmns: libpcp ; $(MAKE) -C pmns default_pcp
  # Make can now parallelize within each stage
  ```

#### Proposed Solution

Convert subdirectories from shell loop iterations to proper make targets while preserving existing dependency relationships.

**Key insight:** The dependency declarations already exist - we just need to make them **actionable** for make's parallelism engine instead of feeding them through a serializing shell loop.

#### Implementation Tasks

**Task 3.1: Refactor `src/GNUmakefile` SUBDIRS_MAKERULE**
Replace shell loop with target-based rules that let make parallelize within each dependency stage.

**Task 3.2: Update top-level `GNUmakefile`**
Apply same approach to top-level subdirectory iteration.

**Task 3.3: Test cross-directory parallelism**
- Verify correct build order (include → libpcp → pmns → libs → tools)
- Confirm parallel builds within each stage (e.g., multiple libs building simultaneously)
- Check for race conditions
- Measure speedup

**Risk factors:**
- Breaking dependency order could cause race conditions
- Must preserve backwards compatibility
- May need platform-specific testing (macOS, Linux, etc.)

#### Stage 3A Results (2026-01-05) ✅ COMPLETED

**Implementation:**
Modified `src/GNUmakefile` to use modern GNU make parallel pattern:
- Converted subdirectories to phony targets (`.PHONY: $(SUBDIRS)`)
- Used target-specific variables for default_pcp and install_pcp targets
- Added `+` prefix for jobserver coordination across recursive make calls
- Discovered and fixed hidden dependency: `libpcp_static` depends on `libpcp` (they share source files via symlinks)

**Key Code Changes (src/GNUmakefile:162-193):**
```makefile
.PHONY: $(SUBDIRS)

default_pcp: TARGET = default_pcp
default_pcp: $(SUBDIRS)

install_pcp: TARGET = install_pcp
install_pcp: $(SUBDIRS)

$(SUBDIRS):
	+@if [ -d "$@" -a -f "$@/GNUmakefile" ]; then \
		echo === $@ ===; \
		$(MAKE) $(MAKEOPTS) -C $@ $(TARGET) || exit $$?; \
	fi

# Fixed hidden dependency
libpcp_static: libpcp  # Cannot build in parallel, share source
```

**Test Results:**
- ✅ Serial build: 284.70s (verified correctness)
- ✅ Parallel build: 228.93s with `-j12`
- ✅ Repeatability: 3 consecutive successful builds (237.08s, 228.77s, 248.83s)
- ✅ Average: 238.23s
- ✅ No race conditions detected

**Speedup Analysis:**
- **Phase 2 baseline**: 255.33s
- **Phase 3A result**: 238.23s (average of 3 runs)
- **Phase 3A improvement**: 17.1 seconds (~7% additional)
- **Combined Phase 1+2+3A**: 304s → 238.23s = **21.6% total improvement**

**What This Achieved:**
- 13 libraries in `LIBS_SUBDIRS` now build in parallel (after pmns completes)
- ~100 tools in `OTHER_SUBDIRS` now build in parallel (after libs complete)
- Make's jobserver properly coordinates `-j12` across all recursive make calls
- Dependency chain preserved: include → libpcp → libpcp_static → pmns → libs (parallel) → tools (parallel)

**Issues Discovered & Resolved:**
1. **Race condition**: libpcp and libpcp_static tried to build in parallel but share source directory
   - **Solution**: Added explicit dependency `libpcp_static: libpcp`
2. **Syntax issue**: `+` prefix must come before `@` in recipe (`+@command`, not `@+command`)

**Next Steps:**
Stage 3B: Apply same pattern to top-level `GNUmakefile` for additional 2-5% improvement

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
- ✅ **Achieved with Phase 1+2**: 252 seconds (4m 12s) - **17% improvement**
- 🎯 **Target with Phase 3**: Further 10-20% improvement by enabling cross-directory parallelism  
  
---  
  
## Risk Mitigation  
  
1. **Make changes incrementally** - One phase at a time  
2. **Test after each change** - Don't batch multiple risky changes  
3. **Keep git history clean** - Easy rollback if something breaks  
4. **Verify with QA suite** - Build changes shouldn't break tests  
5. **Consider packaging** - Ensure packages still build correctly  
  
---  
  
## Critical Files Modified

### Phase 1: ✅ COMPLETED (Commit: 33122d0df2)
- ✅ `Makepkgs` (lines 766-788) - Added `PCP_MAKE_JOBS` environment variable support

### Phase 2: ✅ COMPLETED (Commits: b269850e4c, 77ce1861f2)
- ✅ `src/libpcp/src/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/libpcp_static/src/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/libpcp_web/src/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/libpcp_fault/src/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/libpcp3/src/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/pmcpp/GNUmakefile` - Removed .NOTPARALLEL entirely (no yacc/lex)
- ✅ `src/newhelp/GNUmakefile` - Removed .NOTPARALLEL entirely (no yacc/lex)
- ✅ `src/pmieconf/GNUmakefile` - Removed .NOTPARALLEL entirely (no yacc/lex)
- ✅ `src/pmie/src/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/pmlogger/src/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/pmlogextract/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/pmlc/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/pmlogrewrite/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules
- ✅ `src/dbpmda/src/GNUmakefile` - Fixed .NOTPARALLEL for yacc rules

### Phase 3A: ✅ COMPLETED (Commit: 3f68a2a91e)
- ✅ `src/GNUmakefile` (lines 162-193) - Converted to parallel subdirectory pattern

### Phase 3B: 🔄 NEXT
- ⏳ `GNUmakefile` (lines 49-55 + install_pcp) - Apply same parallel pattern  
  
---  
  
## Progress Summary

### Completed Work (Phases 1, 2, 3A)

| Phase | Description | Improvement | Cumulative Time | Status |
|-------|-------------|-------------|-----------------|--------|
| **Baseline** | Original build system | - | 304s (5m 4s) | - |
| **Phase 1** | Add `PCP_MAKE_JOBS` env var | 7% (limited by .NOTPARALLEL) | 259s (4m 19s) | ✅ Complete |
| **Phase 2** | Fix .NOTPARALLEL directives (14 files) | +10% | 252s (4m 12s) | ✅ Complete |
| **Phase 3A** | Parallel subdirs in src/GNUmakefile | +7% | 238s (3m 58s) | ✅ Complete |
| **Phase 3B** | Parallel subdirs in top-level (pending) | Est. +2-5% | Est. 225s (3m 45s) | 🔄 Next |
| **Target** | Original goal | 60-70% | <120s (2m) | 🎯 In Progress |

**Current Achievement: 22% faster (304s → 238s), 66 seconds saved**

### Test Results Summary

All phases tested on 12-core Apple Silicon Mac:

**Phase 3A Verification:**
- Serial build: 284.70s ✅
- Parallel build: 228.93s ✅
- Repeatability (3 runs): 237.08s, 228.77s, 248.83s ✅
- Average: 238.23s
- Race conditions: None detected ✅
- Build artifacts: All packages built successfully ✅

### Success Criteria

**Achieved So Far:**
- ✅ Backwards compatible - builds without `PCP_MAKE_JOBS` work as before
- ✅ No build race conditions or broken builds (extensive testing)
- ✅ Packages build correctly (tar.gz, .dmg tested)
- ✅ 22% speedup achieved (66 seconds saved)
- ⚠️ CPU utilization improved but not yet >80% (more work needed)

**Remaining Goals:**
- 🎯 Build time <2 minutes (currently 3m 58s, need 48% more improvement)
- 🎯 CPU utilization >80% during build (Phase 3B should help)
- 🎯 QA tests continue to pass (to be verified after Phase 3B)

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

## What to Do Next

### Immediate Next Step: Phase 3B (Est. 1-2 hours)

**Goal:** Apply parallel pattern to top-level `GNUmakefile` for additional 2-5% speedup

**Files to modify:**
- `GNUmakefile` (lines 49-55)

**Current code (GNUmakefile:49-55):**
```makefile
default_pcp : $(CONFIGURE_GENERATED) tmpfiles.init.setup
	+for d in `echo $(SUBDIRS)`; do \
	    if test -d "$$d" ; then \
		echo === $$d ===; \
		$(MAKE) -C $$d $@ || exit $$?; \
	    fi; \
	done
```

**Proposed change (same pattern as Phase 3A):**
```makefile
.PHONY: vendor src qa man html images build debian

default_pcp: $(CONFIGURE_GENERATED) tmpfiles.init.setup vendor src qa man html images build debian

# Pattern rule with jobserver participation
vendor src qa man html images build debian:
	+@if [ -d "$@" ]; then \
		echo === $@ ===; \
		$(MAKE) -C $@ default_pcp || exit $$?; \
	fi

# Dependencies: vendor must complete first, then src, then everything else can run in parallel
src: vendor
qa man html images build debian: src
```

**Expected outcome:**
- `qa`, `man`, `html`, `images`, `build`, `debian` will build in parallel after `src` completes
- Estimated improvement: 2-5% (5-12 seconds)
- Target time: ~225s (3m 45s)

**Testing checklist:**
1. Serial build test (verify correctness)
2. Parallel build with `-j12` (measure speedup)
3. Repeatability test (3 builds, check for race conditions)
4. Update plan document with results
5. Commit changes

### Future Work

**Phase 4:** QA Test Parallelization (Defer - requires significant QA framework changes)

**Optional Enhancements:**
1. Document ccache setup for developers
2. Investigate distributed builds (distcc)
3. Build metrics dashboard

---

## Key Learnings & Best Practices

### What Worked Well

1. **Incremental approach**: Tackling one phase at a time made it safe and easy to rollback
2. **Extensive testing**: 3 repeatability runs caught the libpcp/libpcp_static race condition
3. **Modern make patterns**: Using `.PHONY` targets and `+` prefix is the correct approach
4. **Documentation**: Keeping detailed notes made it easy to understand and resume work

### Common Pitfalls Discovered

1. **Hidden dependencies**: Always check for symlinks and shared source directories
   - `libpcp_static` shares source with `libpcp` via symlinks → cannot build in parallel
2. **Syntax matters**: `+` must come before `@` in recipe (`+@command`, not `@+command`)
3. **Jobserver coordination**: The `+` prefix is critical for `-jN` to work across recursive make
4. **Test thoroughly**: A single successful build doesn't prove there are no race conditions

### Build System Architecture Notes

- The build system is well-designed with correct dependencies declared
- Most sequential constraints were artificial (shell loops), not actual dependencies
- The `-j 1` in packaging is intentional (reproducibility) - keep it
- QA test parallelization is complex (single lock file) - defer for now
- Dependencies are properly declared in makefiles, just not utilized by shell loops