# pmlogsynth — Phase 3 Specification
## Fleet Archive Generation: Bulk Synthetic Server Farm

**Version:** 1.0-draft
**Status:** Proposed
**Depends on:** pmlogsynth Phase 1 (complete), Phase 2 (optional but recommended)

---

## 1. Background and Prior Work

Phase 1 of `pmlogsynth` produces a single PCP archive from a declarative YAML workload
profile, with a hardware profile describing the simulated host. Phase 2 adds natural
language profile generation via Claude.

A single archive is sufficient for testing tools that analyse one host in isolation.
However, many real PCP use cases involve fleets: pmlogger archives arriving from dozens
or hundreds of hosts, analysed together to find outliers, detect coordinated failures,
or benchmark fleet-wide health. Testing these use cases requires a realistic set of
archives — mostly well-behaved "background" hosts, with a small number exhibiting
specific fault conditions.

Phase 3 adds fleet generation: the ability to produce a named, structured set of
archives from a single fleet profile, representing a heterogeneous server farm with
controllable fault injection.

---

## 2. Goals

- Generate a set of PCP archives in a single command, one per simulated host
- Support a majority of "healthy" hosts sharing a common baseline workload profile
- Support a minority of "anomalous" hosts with fault conditions overlaid on top of
  the baseline
- Introduce per-host variation among healthy hosts so archives are not identical
- Name output archives consistently so downstream tools can discover them
- Reuse Phase 1 profile and hardware profile formats without modification
- Support Phase 2 `--prompt` for fleet profile generation

### Out of Scope (Phase 3)

| Item | Notes |
|------|-------|
| Cross-host metric correlation | Each host archive is independent |
| Network topology simulation | No inter-host traffic modelling |
| Rolling failures / cascades | Faults are per-host, not triggered by other hosts |
| Live replay to pmcd | Out of scope; archives only |

---

## 3. Concepts

### 3.1 Fleet Profile

A fleet profile is a new YAML document type (distinct from a workload profile) that
describes a collection of host groups. Each group specifies a count of hosts, a
hardware profile, a base workload profile, and optionally one or more anomaly overlays.

### 3.2 Host Groups

A host group is a set of hosts that share the same hardware profile and base workload.
Groups are named; host archives are named `<group-prefix>-NN.{0,index,meta}`.

### 3.3 Anomaly Overlays

An anomaly overlay is a partial workload profile — it specifies only the fields that
deviate from the base workload, for a defined time window within the archive. The
overlay is merged on top of the base workload for the affected hosts only.

Overlays use the same stressor syntax as Phase 1 workload profiles. Any field not
present in the overlay retains its base workload value.

### 3.4 Per-Host Variation (Jitter)

Among hosts in the same group, values are not identical. A `jitter` factor (default 5%)
applies a small, per-host random offset to all stressor values at profile load time.
This simulates the natural variation seen in a real fleet without requiring separate
profiles per host.

Jitter is seeded per host name, so the same fleet profile with the same `--seed`
produces the same archives.

---

## 4. Fleet Profile Format

```yaml
# fleet: web-cluster.yaml

meta:
  name: web-cluster
  duration: 86400       # 24 hours — applies to all hosts in this fleet
  interval: 60          # 1 minute sampling — applies to all hosts
  timezone: UTC
  output_dir: ./fleet-archives   # base output directory

groups:

  - name: web-frontend
    count: 16
    host_prefix: web              # archives named web-01, web-02, ... web-16
    hardware: generic-large
    workload: profiles/normal-web.yaml
    jitter: 0.05                  # ±5% per-host variation on all stressor values

  - name: web-degraded
    count: 2
    host_prefix: web-degraded
    hardware: generic-large
    workload: profiles/normal-web.yaml
    jitter: 0.02
    anomalies:
      - name: cpu-saturation
        start_offset: 14400       # fault begins 4 hours in
        duration: 7200            # lasts 2 hours
        transition: linear        # ramp into and out of fault condition
        cpu:
          utilization: 0.96
          user_ratio: 0.90
          iowait_ratio: 0.06
        disk:
          read_mbps: 18.0
          write_mbps: 9.0

  - name: db-primary
    count: 1
    host_prefix: db-primary
    hardware: memory-optimized
    workload: profiles/normal-db.yaml

  - name: db-replica
    count: 3
    host_prefix: db-replica
    hardware: memory-optimized
    workload: profiles/normal-db.yaml
    jitter: 0.03
    anomalies:
      - name: memory-pressure
        start_offset: 28800       # 8 hours in
        duration: 14400           # 4 hours
        transition: linear
        memory:
          used_ratio: 0.91
          cache_ratio: 0.04
```

### 4.1 Anomaly Overlay Rules

- Only fields explicitly set in the anomaly override the base workload; all others
  are inherited unchanged
- Multiple anomalies can be listed per group; they are applied in order and may
  overlap in time
- `start_offset` is in seconds from the archive start (`meta.start` or `--start`)
- `transition: linear` ramps the anomaly values in over the first 10% of the
  anomaly duration and out over the last 10% (configurable via `transition_ramp`)
- An anomaly with no `duration` runs to the end of the archive

### 4.2 Per-Host Variation Detail

Jitter is applied as a multiplicative factor drawn from a Gaussian distribution with
mean 1.0 and standard deviation equal to `jitter`. It is applied independently per
stressor field, per host, at profile load time. The same host name always produces the
same jitter offsets for a given `--seed`.

```
effective_value = base_value × Normal(mean=1.0, stddev=jitter)
```

Values are clamped to valid ranges after jitter is applied (e.g. ratios to [0.0, 1.0]).

---

## 5. Output Layout

Archives are written into `meta.output_dir`, organised by group:

```
./fleet-archives/
├── web-01.{0,index,meta}
├── web-02.{0,index,meta}
│   ...
├── web-16.{0,index,meta}
├── web-degraded-01.{0,index,meta}
├── web-degraded-02.{0,index,meta}
├── db-primary-01.{0,index,meta}
├── db-replica-01.{0,index,meta}
├── db-replica-02.{0,index,meta}
├── db-replica-03.{0,index,meta}
└── fleet.manifest
```

### 5.1 Fleet Manifest

`fleet.manifest` is a machine-readable YAML file listing every archive in the fleet,
its group, hardware profile, and whether it carries any anomalies. This allows
downstream tooling to know which archives should be flagged as anomalous during
test assertions.

```yaml
# fleet.manifest — generated by pmlogsynth fleet
meta:
  name: web-cluster
  generated: "2024-01-15T09:00:00Z"
  pmlogsynth_version: "1.0"
  duration: 86400
  interval: 60

archives:
  - host: web-01
    path: web-01
    group: web-frontend
    hardware: generic-large
    anomalies: []

  - host: web-degraded-01
    path: web-degraded-01
    group: web-degraded
    hardware: generic-large
    anomalies:
      - name: cpu-saturation
        start_offset: 14400
        duration: 7200

  ...
```

---

## 6. CLI Interface

Fleet generation is a subcommand of `pmlogsynth`:

```
pmlogsynth fleet [OPTIONS] FLEET_PROFILE

Arguments:
  FLEET_PROFILE           Path to fleet YAML profile

Options:
  -o, --output-dir PATH   Override meta.output_dir from profile
  --start TIMESTAMP       Archive start time for all hosts [default: now - duration]
  --seed INT              PRNG seed for reproducible jitter and noise
  --jobs INT              Parallel archive generation workers [default: CPU count]
  --dry-run               Print what would be generated without writing any output
  --validate              Validate fleet profile without generating output
  -v, --verbose           Show per-host progress
  -h, --help              Show help
```

### Examples

```bash
# Generate a 22-host fleet
pmlogsynth fleet -o ./cluster web-cluster.yaml

# Reproducible fleet (same seed = same jitter offsets and noise)
pmlogsynth fleet --seed 42 -o ./cluster web-cluster.yaml

# See what would be generated without writing anything
pmlogsynth fleet --dry-run web-cluster.yaml

# Generate fleet anchored to a historical window
pmlogsynth fleet --start "2024-01-15 00:00:00 UTC" -o ./cluster web-cluster.yaml

# Use Phase 2 natural language to generate the fleet profile first
pmlogsynth --prompt \
  "A web cluster: 16 healthy frontend servers on generic-large hardware, \
   2 with CPU saturation faults starting 4 hours in, and 1 database server \
   on memory-optimized hardware." \
  -o web-cluster.yaml
pmlogsynth fleet -o ./cluster web-cluster.yaml
```

### Parallel Generation

Each host archive is independent and can be generated concurrently. `--jobs` defaults
to the number of available CPU cores, implemented via `concurrent.futures.ProcessPoolExecutor`
from the Python standard library — no additional dependency is required. For large fleets
this makes generation time scale with hardware rather than host count.

---

## 7. Phase 2 Integration: Natural Language Fleet Profiles

The Phase 2 `--prompt` flag works for fleet profiles as well as single-host profiles.
The system prompt (§5 of the Phase 2 specification) is extended with:

- The fleet profile schema and its additional fields (`groups`, `anomalies`, `jitter`)
- The anomaly overlay merge rules
- Common fault scenario archetypes (see below)

Claude infers from context whether the user wants a single-host profile or a fleet
profile and generates accordingly.

### Fleet Fault Archetypes

Named fault scenarios that Claude can reference when generating anomaly overlays:

| Archetype | Description |
|---|---|
| `cpu-saturation` | CPU utilisation at ceiling; user space dominant; iowait elevated |
| `memory-pressure` | RAM nearly exhausted; cache evicted; iowait rising |
| `disk-saturation` | Write throughput at device limit; iowait dominates CPU time |
| `network-degraded` | rx/tx throughput well below interface capacity |
| `noisy-neighbour` | CPU steal elevated (virtualisation contention) |
| `slow-drain` | Gradual linear degradation across all domains over archive lifetime |

---

## 8. Referencing Fleet Archives from Tests

The fleet manifest enables straightforward test assertions in any test framework:

```bash
# Shell example: verify a fleet-aware analysis tool flags the right hosts
pmlogsynth fleet --seed 42 -o ./cluster web-cluster.yaml

# Run the tool under test against the fleet
pcp-fleet-analyser --archives ./cluster --manifest ./cluster/fleet.manifest \
  --flag-threshold cpu:0.90 > ./results.txt

# Assert that exactly the anomalous hosts were flagged
expected=$(grep -l 'cpu-saturation' ./cluster/fleet.manifest | wc -l)
got=$(wc -l < ./results.txt)
[ "$expected" -eq "$got" ] || fail "Expected $expected flagged hosts, got $got"
```

In `pytest`:

```python
# tests/test_fleet_integration.py

def test_fleet_anomalous_hosts_are_identifiable(tmp_path):
    subprocess.run(
        ["pmlogsynth", "fleet", "--seed", "42", "-o", str(tmp_path), "tests/fixtures/web-cluster.yaml"],
        check=True,
    )
    manifest = yaml.safe_load((tmp_path / "fleet.manifest").read_text())
    anomalous = [a for a in manifest["archives"] if a["anomalies"]]
    assert len(anomalous) == 2
    assert all(a["group"] == "web-degraded" for a in anomalous)
```

---

## 9. Project Layout Changes

Phase 3 adds the following to the Phase 1 + Phase 2 layout:

```
pmlogsynth/
├── fleet.py                # fleet profile loader, group expander, manifest writer
├── overlay.py              # anomaly overlay merge logic
├── jitter.py               # per-host deterministic value variation
└── profiles/
    └── fleet/              # example fleet profiles (package data)
        ├── small-web-cluster.yaml
        └── mixed-db-web.yaml

tests/
├── test_fleet.py           # fleet profile loading, overlay merging, jitter
├── test_fleet_integration.py  # end-to-end fleet generation (requires PCP installed)
└── fixtures/
    └── web-cluster.yaml    # reference fleet profile used in tests
```

The example fleet profiles in `pmlogsynth/profiles/fleet/` are installed as package
data alongside the bundled hardware profiles.

---

## 10. Test Requirements

### Tier 1 — unit tests (no PCP required)

- Fleet profile loading and validation
- Anomaly overlay merge logic (field precedence, time window application)
- Jitter reproducibility: same host name + same seed → same offsets
- Jitter clamping: ratio fields stay in [0.0, 1.0] after jitter
- `--dry-run` output matches expected host list and group assignments

### Tier 2 — integration tests (PCP must be installed)

- Generate a small fleet (3–5 hosts) from the reference fixture
- Assert `fleet.manifest` is written and well-formed YAML
- Assert each archive passes `pmlogcheck`
- Assert anomalous hosts in the manifest match the fleet profile definition
- Assert `--seed` reproducibility: two runs with the same seed produce byte-identical archives

Tier 2 tests are skipped automatically if `pmlogcheck` is not found on `PATH`.

```bash
# Run all tests
pytest

# Run only fleet tests
pytest tests/test_fleet.py tests/test_fleet_integration.py

# Run only unit tests (no PCP needed)
pytest -m "not integration"
```

---

## 11. Future Enhancements

| Item | Notes |
|------|-------|
| Rolling / cascading faults | Fault on host A triggers fault onset on host B after a delay |
| Fleet profile via Phase 2 `--prompt` refinement (`--refine`) | Adjust specific groups after initial generation |
| Heterogeneous archive durations per group | Different groups covering different time windows |
| Archive merging | Combine fleet archives into a single multi-host archive (if PCP adds multi-host support) |
