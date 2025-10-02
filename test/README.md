# Bands Project Test Suite

Comprehensive test suite for the bands Norns script, covering unit tests, integration tests, and performance validation.

## Test Files

### `test_bands.lua` - Unit Tests

Core functionality testing:

- Snapshot system initialization and data integrity
- Blend weight calculation (bilinear interpolation)
- Grid coordinate validation
- Parameter validation and bounds checking
- Mathematical properties of blending algorithm
- Frequency array integrity

### `test_integration.lua` - Integration Tests

End-to-end workflow testing:

- Parameter system initialization
- Snapshot store/recall workflow
- Matrix blending with different snapshots
- Grid LED display simulation
- Glide state management
- Engine command generation
- Grid coordinate mapping

### `test_performance.lua` - Performance Tests

Real-time performance validation:

- Blend weight calculation speed
- Full parameter blending performance
- Grid redraw simulation timing
- Glide interpolation performance
- Memory allocation patterns
- Stress testing with rapid movements
- Real-time constraint validation
- Numerical stability

## Running Tests

### Run All Tests

```bash
cd /path/to/bands
lua test/run_tests.lua
```

### Run Specific Test Suite

```bash
lua test/run_tests.lua test_bands
lua test/run_tests.lua test_integration
lua test/run_tests.lua test_performance
```

### Run Individual Test Files

```bash
lua test/test_bands.lua
lua test/test_integration.lua
lua test/test_performance.lua
```

## Test Coverage

### Core Functions Tested

- `init_snapshots()` - Snapshot initialization
- `calculate_blend_weights()` - Bilinear interpolation
- `store_snapshot()` / `recall_snapshot()` - Snapshot management
- `apply_blend()` - Parameter blending
- Grid coordinate mapping and validation
- Parameter bounds checking
- Glide interpolation

### Performance Benchmarks

- **Blend calculation**: < 0.1ms per call
- **Parameter blending**: < 1ms per call
- **Grid redraw**: < 16ms (60fps compatible)
- **Glide step**: < 1ms per step
- **Memory growth**: < 100KB per 1000 operations

### Real-time Constraints

- **Audio rate**: Operations complete within 1ms (audio callback safe)
- **UI rate**: Updates complete within 16ms (60fps compatible)
- **Stress test**: 19,600 calculations in < 1 second

## Test Framework

Simple custom test framework with:

- `test(name, func)` - Define a test case
- `assert_equal(actual, expected, message)` - Exact equality
- `assert_near(actual, expected, tolerance, message)` - Floating point comparison
- `assert_true(condition, message)` - Boolean assertion
- `benchmark(name, func, iterations)` - Performance measurement

## Mock Environment

Tests use mock Norns environment:

- Mock `params` system for parameter management
- Mock `engine` for SuperCollider communication
- Mock `grid` device for Monome grid simulation
- Mock `util` and `controlspec` modules

## Expected Results

All tests should pass for a healthy codebase:

- **Unit tests**: Verify core algorithm correctness
- **Integration tests**: Ensure components work together
- **Performance tests**: Validate real-time performance

## Troubleshooting

### Common Issues

1. **Module not found**: Ensure you're running from the bands project root
2. **Performance failures**: May indicate need for optimization
3. **Integration failures**: Check mock environment setup

### Adding New Tests

1. Add test cases to appropriate test file
2. Use existing test framework functions
3. Include both positive and negative test cases
4. Add performance benchmarks for new algorithms

## Continuous Integration

These tests can be integrated into CI/CD pipelines:

- Exit code 0 = all tests pass
- Exit code 1 = some tests failed
- Detailed output shows which tests failed and why

## Test Philosophy

- **Unit tests**: Fast, isolated, test individual functions
- **Integration tests**: Test component interactions and workflows
- **Performance tests**: Ensure real-time constraints are met
- **Mock everything**: Tests should not depend on actual Norns hardware
