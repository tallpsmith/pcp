# pmlogsynth — Phase 1 Specification
## Synthetic PCP Archive Generator: Core Tool

**Version:** 1.0-draft
**Status:** Proposed

---

## 1. Problem Statement

Testing PCP tooling — analysis, alerting, dashboards, ML-based anomaly detection — requires
archives with specific, reproducible performance characteristics. Real archives are hard to
curate: you must capture exactly the right event on real hardware, at the right time, with
the right metrics enabled. There is currently no way to say "give me an archive where this
specific failure mode occurs" without either hoping it happens in production or writing
throwaway one-off code against `libpcp_import` from scratch.

`pmlogsynth` fills this gap: a command-line tool that generates valid, self-consistent PCP
archives from a declarative YAML workload profile. Archives produced by `pmlogsynth` are
indistinguishable in format from those produced by `pmlogger` and are immediately usable
with all PCP tooling.

---

## 2. Naming

`pmlogsynth` follows the established `pmlog*` tool family convention:

```
pmlogger → pmlogrewrite → pmlogextract → pmlogcheck → pmlogdump → pmlogsummary → pmlogsynth
```

The name is unambiguous: synthetic archive generation, recognisably part of the PCP archive
toolchain.

---

## 3. Goals

- Produce archives indistinguishable in format from `pmlogger` output
- Support real PCP metric namespaces (kernel, disk, network, memory) with correct units
  and semantics
- Enforce internal metric consistency (e.g. CPU user + sys + idle = 100%)
- Accept a simple declarative profile format (YAML)
- Require no running `pmcd`, no real hardware, no root access
- Be usable in CI pipelines to regression-test PCP analysis tools
- Ship with a set of named hardware profiles; allow users to define their own

### Out of Scope (Phase 1)

The following are explicitly deferred and will not be addressed in this phase:

| Item | Notes |
|------|-------|
| Multi-host archives | Single host only |
| Event records | Not supported |
| Derived metrics | Not supported |
| Per-process metrics (`proc.*`) | Deferred to future enhancement |
| Hotplug instance domain changes | Instance domains are fixed for archive lifetime |
| GPU / PMDA-specific namespaces | Out of scope |
| Archive v2 format | v3 only; add `--format v2` only if a concrete need arises |
| Per-metric noise granularity | Per-domain override is sufficient |
| Natural language profile generation | Addressed in Phase 2 |

---

## 4. Architecture

```
profile.yaml
     │
     ▼
 ProfileLoader
     │  (parses + validates workload phases, timeline, host config)
     ▼
 MetricModel  (one per domain)
     │  (computes consistent values across related metrics at each tick)
     ▼
 ValueSampler
     │  (applies Gaussian noise, accumulates counters, coerces types)
     ▼
 libpcp_import  (via pmi.pmiLogImport Python bindings)
     │
     ▼
output.{0,index,meta}
```

### Implementation Language

Python 3. Depends only on the `pcp` Python module (included in any PCP installation).
No third-party dependencies are required.

---

## 5. Hardware Profile Library

### 5.1 Concept

A hardware profile is a named YAML document that describes the physical or virtual host
being simulated: CPU count, RAM, disk devices, and network interfaces. Profiles decouple
the "what hardware" question from the "what workload" question, making profiles reusable
across many workload scenarios.

### 5.2 Bundled Profiles

`pmlogsynth` ships with a small set of generic reference host profiles. These are loosely
inspired by common cloud instance tiers but are not tied to any vendor — they serve as
reasonable, recognisable starting points.

| Profile name        | CPUs | RAM    | Disk            | NIC         | Archetype              |
|---------------------|------|--------|-----------------|-------------|------------------------|
| `generic-small`     | 2    | 8 GB   | 1× NVMe         | 1× 10 GbE   | General purpose, small |
| `generic-medium`    | 4    | 16 GB  | 1× NVMe         | 1× 10 GbE   | General purpose, medium|
| `generic-large`     | 8    | 32 GB  | 2× NVMe         | 1× 10 GbE   | General purpose, large |
| `generic-xlarge`    | 16   | 64 GB  | 2× NVMe         | 2× 10 GbE   | General purpose, xlarge|
| `compute-optimized` | 8    | 16 GB  | 1× NVMe         | 1× 10 GbE   | High CPU, modest RAM   |
| `memory-optimized`  | 4    | 64 GB  | 1× NVMe         | 1× 10 GbE   | High RAM, modest CPU   |
| `storage-optimized` | 4    | 16 GB  | 4× HDD          | 1× 10 GbE   | High disk capacity     |

Bundled profiles live in `src/pmlogsynth/profiles/` as individual YAML files.

### 5.3 User-Defined Profiles

Users may define their own profiles — or override bundled ones — by placing YAML files in:

```
~/.pcp/pmlogsynth/profiles/
```

**Lookup order:** the user directory is checked first. A user file whose name matches a
bundled profile takes precedence, providing a clean override mechanism without touching
the installation.

```bash
# List all profiles available (bundled + user-defined, with source shown)
pmlogsynth --list-profiles
```

Example user-defined profile:

```yaml
# ~/.pcp/pmlogsynth/profiles/prod-web-tier.yaml
name: prod-web-tier
cpus: 32
memory_kb: 134217728      # 128 GB
disks:
  - name: nvme0n1
    type: nvme
  - name: nvme1n1
    type: nvme
interfaces:
  - name: bond0
    speed_mbps: 25000
```

### 5.4 Build-Time Validation

The build system runs a schema validation pass over all bundled profiles in
`src/pmlogsynth/profiles/`. Any malformed profile fails the build. Content review
of contributed profiles remains a human responsibility.

---

## 6. Profile Format

A profile is a YAML file that describes the simulated host and a timeline of workload
**phases**. Each phase has a duration and a set of **stressors** that drive one or more
metric domains.

### 6.1 Full Example

```yaml
# cpu-memory-spike.yaml
meta:
  hostname: synthetic-host
  timezone: UTC
  duration: 1800        # total archive length in seconds
  interval: 10          # sample interval in seconds
  noise: 0.03           # global Gaussian noise factor (3%); overridable per domain

host:
  profile: generic-large    # reference a named hardware profile...
  # ...or define the host inline (overrides a named profile if both are present):
  # name: web-server-01
  # cpus: 16
  # memory_kb: 65536000
  # disks:
  #   - name: sda
  #     type: ssd
  # interfaces:
  #   - name: eth0
  #     speed_mbps: 10000

phases:
  - name: baseline
    duration: 300
    cpu:
      utilization: 0.15     # 15% overall CPU utilisation
      user_ratio: 0.70      # fraction of busy time in user space
      sys_ratio: 0.20
      iowait_ratio: 0.10
    memory:
      used_ratio: 0.40      # fraction of total RAM in use
      cache_ratio: 0.30
    disk:
      read_mbps: 2.0
      write_mbps: 0.5
    network:
      rx_mbps: 10.0
      tx_mbps: 2.0

  - name: cpu-spike
    duration: 300
    cpu:
      utilization: 0.92
      user_ratio: 0.85
      sys_ratio: 0.10
      iowait_ratio: 0.05
    memory:
      used_ratio: 0.55
    disk:
      read_mbps: 8.0
      write_mbps: 3.0
    network:
      rx_mbps: 10.0
      tx_mbps: 2.0

  - name: recovery
    duration: 600
    transition: linear      # ramp from previous phase's end values over this duration
    cpu:
      utilization: 0.20
    memory:
      used_ratio: 0.42
    disk:
      read_mbps: 2.5
      write_mbps: 0.8
    network:
      rx_mbps: 10.0
      tx_mbps: 2.0
```

### 6.2 Phase Transitions

| Value | Behaviour |
|-------|-----------|
| `instant` (default) | Values jump immediately at the phase boundary |
| `linear` | Values interpolate linearly over the full phase duration from prior phase end values |

### 6.3 Repeating Phases

A phase may include a `repeat` key to express recurring patterns without copy-pasting.
The timeline sequencer expands repeats before writing begins.

```yaml
phases:
  - name: baseline
    duration: 39600         # 11 hours

  - name: noon-peak
    duration: 3600          # 1 hour, repeated each day
    repeat: daily           # valid values: daily, or an integer count
    transition: linear
    cpu:
      utilization: 0.93
      user_ratio: 0.88
      sys_ratio: 0.08
      iowait_ratio: 0.04
    disk:
      read_mbps: 25.0
      write_mbps: 12.0
```

When `repeat: daily` is used, the sequencer inserts the baseline phase between each
repetition to fill the 24-hour period. `meta.duration` must accommodate the full
expanded timeline; the validator will reject profiles where this does not hold.

### 6.4 Noise

A `noise:` key at domain level overrides `meta.noise` for that domain only:

```yaml
  - name: busy
    cpu:
      utilization: 0.80
      noise: 0.08           # noisier CPU; other domains use meta.noise
    disk:
      write_mbps: 5.0
```

### 6.5 Instance Domains

Disk and NIC instances are derived from the host configuration and remain **fixed**
for the lifetime of the archive. Instance names match the device names in the host
profile (e.g. `nvme0n1`, `eth0`).

### 6.6 Constraints Enforced at Validation

- `user_ratio + sys_ratio + iowait_ratio ≤ 1.0` (remainder is steal/other)
- Sum of phase durations == `meta.duration` (when no `repeat` key is present)
- `host.profile` must resolve to a known profile name
- All `noise` values must be in range [0.0, 1.0]
- `interval` must be a positive integer, in seconds

---

## 7. Metric Domains and Consistency Model

Each domain is a self-contained `MetricModel` subclass that accepts high-level stressor
values and derives all related PCP metrics, enforcing internal constraints at every sample.

### 7.1 CPU Domain

**PCP metrics:** `kernel.all.cpu.*`, `kernel.percpu.cpu.*`

| Input field | Derived PCP metrics |
|-------------|---------------------|
| `utilization` | `kernel.all.cpu.user`, `.sys`, `.idle`, `.wait`, `.steal` |
| `user_ratio`, `sys_ratio`, `iowait_ratio` | Partition the busy fraction accordingly |
| `host.cpus` | `kernel.percpu.cpu.*` distributed across N CPUs with per-CPU ±variance |

**Constraint enforced:** `user + sys + idle + wait + steal == total_ticks` per CPU per
interval.

**Metric type:** counter (cumulative milliseconds). The model maintains running totals
across samples so that rate-based tools (`pmval`, `pmrep`) produce correct results when
replaying the archive.

### 7.2 Memory Domain

**PCP metrics:** `mem.util.*`

| Input field | Derived PCP metrics |
|-------------|---------------------|
| `used_ratio` | `mem.util.used`, `.free`, `.cached`, `.bufmem`, `.available` |
| `cache_ratio` | `mem.util.cached` carved from the used portion |
| `host.memory_kb` | All values expressed as absolute KB |

**Constraint enforced:** `used + free == physmem`. `available ≈ free + cached`.

### 7.3 Disk Domain

**PCP metrics:** `disk.all.*`, `disk.dev.*`

| Input field | Derived PCP metrics |
|-------------|---------------------|
| `read_mbps`, `write_mbps` | `disk.all.read_bytes`, `.write_bytes`, `.read`, `.write` (ops) |
| `host.disks` | `disk.dev.*` split across named device instances |
| `iops_read`, `iops_write` (optional) | If omitted, estimated from throughput at 64 KB mean block size |

**Metric type:** counter (cumulative bytes and ops).

### 7.4 Network Domain

**PCP metrics:** `network.interface.*`

| Input field | Derived PCP metrics |
|-------------|---------------------|
| `rx_mbps`, `tx_mbps` | `network.interface.in.bytes`, `.out.bytes`, `.in.packets`, `.out.packets` |
| `host.interfaces` | Split across named interface instances |

Packet counts are estimated from byte totals assuming a 1400-byte mean packet size
(configurable via a top-level `meta.mean_packet_bytes` key).

### 7.5 Load Average Domain

**PCP metrics:** `kernel.all.load`

Derived from CPU utilisation: `load_1min ≈ utilization × num_cpus`. Exponential
smoothing is applied to correctly simulate the 1-minute, 5-minute, and 15-minute
UNIX load average decay constants.

---

## 8. CLI Interface

```
pmlogsynth [OPTIONS] PROFILE

Arguments:
  PROFILE                 Path to YAML profile file

Options:
  -o, --output PATH       Output archive base name [default: ./pmlogsynth-out]
  --start TIMESTAMP       Archive start time [default: now - meta.duration]
  --list-metrics          Print all PCP metrics this tool can generate, then exit
  --list-profiles         Print all available hardware profiles (bundled + user), then exit
  --validate              Validate profile without generating any output
  -v, --verbose           Print per-sample values to stderr as they are written
  -V, --version           Show version
  -h, --help              Show help
```

### Examples

```bash
# Basic generation
pmlogsynth -o ./out cpu-spike.yaml

# Archive anchored to a specific historical window
pmlogsynth --start "2024-01-15 09:00:00 UTC" -o ./incident-replay spike.yaml

# Validate a profile without writing any output
pmlogsynth --validate cpu-spike.yaml

# See all available hardware profiles and where they come from
pmlogsynth --list-profiles

# See all PCP metrics the tool can produce
pmlogsynth --list-metrics
```

---

## 9. Output

`pmlogsynth` produces a standard PCP v3 archive:

| File | Content |
|------|---------|
| `<name>.0` | Data volume |
| `<name>.index` | Temporal index |
| `<name>.meta` | Metric metadata |

The archive is immediately usable with all PCP tooling:

```bash
pmval   -a ./out kernel.all.cpu.user
pmrep   -a ./out -o csv kernel.all.cpu.user mem.util.used
pmlogcheck ./out
pcp     -a ./out atop
```

---

## 10. File Layout

```
src/pmlogsynth/
├── pmlogsynth                  # CLI entry point
├── profile.py                  # YAML loader and validator
├── timeline.py                 # Phase sequencer, transition interpolation,
│                               #   repeat expansion
├── sampler.py                  # Gaussian noise, counter accumulation,
│                               #   type coercion
├── writer.py                   # libpcp_import wrapper (pmi.pmiLogImport)
├── profiles/                   # Bundled hardware profiles
│   ├── generic-small.yaml
│   ├── generic-medium.yaml
│   ├── generic-large.yaml
│   ├── generic-xlarge.yaml
│   ├── compute-optimized.yaml
│   ├── memory-optimized.yaml
│   └── storage-optimized.yaml
└── domains/
    ├── cpu.py
    ├── memory.py
    ├── disk.py
    ├── network.py
    └── load.py

qa/
└── NNNNN                       # QA test: generate archive, verify with
                                #   pmlogcheck + pmval
```

**User profile directory:** `~/.pcp/pmlogsynth/profiles/`

---

## 11. QA Test Requirements

A QA test must be included that:

1. Generates an archive from a known profile
2. Runs `pmlogcheck` against the output and asserts it passes
3. Runs `pmval` against one metric per domain and asserts the values are within
   the expected range (stressor value ± noise tolerance)
4. Validates that the archive start and end timestamps match `--start` and
   `meta.duration`

The test must not require a running `pmcd` or root access.

---

## 12. Future Enhancements

The following items are explicitly deferred from Phase 1:

| Item | Notes |
|------|-------|
| Per-process metrics (`proc.*`) | Significant additional complexity; high value for profiling workloads |
| Hotplug instance domains | Disks/NICs appearing or disappearing mid-archive |
| Archive v2 format | Add `--format v2` only if a concrete compatibility need arises |
| Per-metric noise granularity | Per-domain override is considered sufficient for now |
| Multi-host archives | Out of scope for a single-tool use case |
| Profile composition (`include:`) | Merging multiple profile files |
| Python scripting API | `from pmlogsynth import Profile, generate` |
| Real-data seeding | Accept a real archive as baseline, overlay synthetic phases |
| Natural language profile generation | Addressed in Phase 2 |
