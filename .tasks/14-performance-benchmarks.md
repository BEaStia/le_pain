# Performance & Benchmarks

## Status
Open — no dedicated benchmark suite, profiler API, regression checks, or framework comparison implementation found.

## Problem
No baseline performance metrics. Can't measure impact of changes or compare with alternatives.

## Goal
Add benchmark suite and optimize hot paths.

## Tasks

### 1. Benchmark Suite
- [ ] Request dispatch throughput (req/s)
- [ ] Handler execution latency (p50, p95, p99)
- [ ] Memory usage per request
- [ ] Concurrent request handling
- [ ] MQ message throughput

### 2. Optimization Targets
- [ ] Router pattern matching (cache compiled regexes)
- [ ] Context creation (reduce allocations)
- [ ] JSON serialization (use oj or faster_json)
- [ ] Thread pool tuning
- [ ] GC pressure reduction

### 3. CI Integration
- [ ] Run benchmarks on PR
- [ ] Compare against baseline
- [ ] Fail if regression > 10%

### 4. Profiling Support
- [ ] `LePain::Profiler.start` / `stop`
- [ ] StackProf integration
- [ ] Memory profile export

### 5. Documentation
- [ ] Publish benchmark results
- [ ] Compare with Sinatra, Grape, Roda
- [ ] Memory footprint comparison

## Acceptance Criteria
- Benchmark suite runs in CI
- Results are reproducible
- Hot paths are optimized
- Profiling tools work correctly
