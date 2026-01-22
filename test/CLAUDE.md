# Test Framework Documentation

This file provides guidance for understanding and working with the test_factory extension test suite.

## Test Framework Overview

The test_factory extension uses **pgTAP** (PostgreSQL's unit testing framework) for comprehensive testing. Tests are organized using PGXNtool's standardized testing infrastructure.

## Test Structure

### Test Files
- `test/sql/base.sql` - Core functionality tests (22 tests)
- `test/sql/install.sql` - Extension installation/uninstallation tests  
- `test/sql/pgtap.sql` - pgTAP integration and `tf.tap()` function tests

### Expected Results
- `test/expected/*.out` - Expected test output for regression testing
- `test/results/*.out` - Actual test output (generated during test runs)

### Test Helpers
- `test/helpers/setup.sql` - Test environment initialization and pgTAP setup
- `test/helpers/create.sql` - Test data registration and security validation
- `test/helpers/create_extension.sql` - Extension creation wrapper
- `test/helpers/deps.sql` - Test dependency management
- Other helper files for role management and pgTAP integration

## Test Coverage Analysis

### Core Functionality Tests (`base.sql`)
1. **Extension Setup** - Creates extension and test tables
2. **Data Registration** - Tests `tf.register()` with multiple test sets
3. **Basic Retrieval** - Tests `tf.get()` returns correct data
4. **Dependency Resolution** - Tests automatic creation of dependent data (customer → invoice)
5. **Caching Behavior** - Verifies data consistency across multiple `tf.get()` calls  
6. **Table Independence** - Tests that cached data persists after source table changes
7. **Function-based Test Data** - Tests using functions as test data sources

### Security Tests (`create.sql`)
- **Role Management** - Validates proper role restoration after installation
- **Security Definer Functions** - Ensures all privileged functions use `search_path=pg_catalog`
- **Permission Isolation** - Tests with unprivileged `test_role`
- **Temp Table Cleanup** - Verifies temporary installation objects are removed

### Installation Tests (`install.sql`) 
- **Dependency Validation** - Tests extension dependency requirements
- **Clean Installation** - Tests CREATE EXTENSION without conflicts
- **Clean Removal** - Tests DROP EXTENSION without orphaned objects

### pgTAP Integration Tests (`pgtap.sql`)
- **tf.tap() Function** - Tests pgTAP wrapper functionality
- **Error Handling** - Tests proper error reporting for invalid inputs
- **Extension Dependencies** - Validates test_factory_pgtap requires test_factory

## Test Data Model

### Test Tables
```sql
CREATE TABLE customer(
    customer_id   serial  PRIMARY KEY,
    first_name    text    NOT NULL, 
    last_name     text    NOT NULL
);

CREATE TABLE invoice(
    invoice_id      serial  PRIMARY KEY,
    customer_id     int     NOT NULL REFERENCES customer,
    invoice_date    date    NOT NULL,
    due_date        date
);
```

### Test Data Sets
- **customer 'insert'** - Simple INSERT statement returning customer data
- **customer 'function'** - Function-based test data creation  
- **invoice 'base'** - Invoice with dependency on customer 'insert' set

## Running Tests

### Basic Test Execution
```bash
make test              # Full test suite with clean install
make installcheck      # Run tests against already installed extension
```

### Test Development Workflow
```bash
# Make changes to test files
vim test/sql/base.sql

# Run tests to verify
make test

# If tests pass but output differs, update expected results
make results
```

### Test Debugging
- Test output appears in `test/results/`
- Differences shown in `test/regression.diffs` if tests fail
- Use `\set ECHO all` in test SQL files for detailed debugging

## Test Architecture Details

### pgTAP Integration
- Tests use pgTAP assertion functions: `is()`, `results_eq()`, `bag_eq()`, `lives_ok()`
- `no_plan()` allows dynamic test counting
- Tests run in transactions with automatic rollback

### Security Testing Strategy
- Creates unprivileged `test_role` to validate security boundaries
- Tests run with restricted permissions to catch privilege escalation issues
- Validates all security definer functions use safe search_path settings

### Dependency Testing
- Tests multi-level dependencies (invoice → customer)
- Validates data creation order and consistency
- Tests that dependency data is created automatically and cached

### Error Condition Testing
- Tests invalid table names and missing test sets
- Validates proper error messages and SQL state codes
- Tests edge cases like non-existent tables in tf.tap()

## Test Data Lifecycle

1. **Setup Phase** - Creates test role, schemas, and tables
2. **Registration Phase** - Registers test data definitions  
3. **Execution Phase** - Calls tf.get() to trigger data creation
4. **Validation Phase** - Verifies data correctness and caching behavior
5. **Cleanup Phase** - Transaction rollback removes all test data

This comprehensive test suite ensures the test_factory extension works correctly across different PostgreSQL versions and usage patterns, with particular attention to security and data integrity.