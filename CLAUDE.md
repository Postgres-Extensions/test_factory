# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **test_factory**, a PostgreSQL extension that provides a framework for managing unit test data in databases. It solves the common problem of creating and maintaining test data by providing a system to register test data definitions once and retrieve them efficiently with automatic dependency resolution.

## Build System & Development Commands

This project uses PGXNtool for build management. Key commands:

### Building and Installation
```bash
make                    # Build the extension
make install           # Install to PostgreSQL
make clean             # Clean build artifacts
make distclean         # Clean all generated files including META.json
```

### Testing
```bash
make test              # Run full test suite (install, then test)
make installcheck      # Run tests only (no clean/install)
make results           # Update expected test results (only after verifying tests pass!)
```

### Distribution
```bash
make tag               # Create git tag for current version
make dist              # Create distribution zip file
make forcetag          # Force recreate tag if it exists
make forcedist         # Force tag + distribution
```

## Architecture & Key Components

### Core API Functions
- `tf.register(table_name, test_sets[])` - Register test data definitions for a table
- `tf.get(table_type, set_name)` - Retrieve test data, creating it if it doesn't exist
- `tf.tap(table_name, set_name)` - pgTAP integration wrapper for testing

### Database Schema Organization
- `tf` schema: User-facing API (functions, types)
- `_tf` schema: Internal implementation (tables, security definer functions)
- `_test_factory_test_data` schema: Cached test data storage
- Uses dedicated `test_factory__owner` role for security isolation

### Security Model
- Role-based access with `test_factory__owner` for data management
- Security definer functions with `search_path=pg_catalog`
- Proper permission isolation between user and system operations

### Key Data Structures
```sql
CREATE TYPE tf.test_set AS (
    set_name    text,     -- Name to reference this test data set
    insert_sql  text      -- SQL command that returns test data rows
);
```

### Test Data Workflow
1. **Registration**: Use `tf.register()` to define how test data is created
2. **Retrieval**: Call `tf.get()` to obtain test data (creates on first call)
3. **Caching**: Test data is stored permanently for fast subsequent access
4. **Dependencies**: Test sets can reference other test sets via embedded `tf.get()` calls

### Performance & Caching
- Test data created once and cached in permanent tables
- Subsequent `tf.get()` calls return cached data without recreation
- Data remains available even if source tables are modified/truncated
- Dependency resolution handled automatically during creation

## File Structure Key Points

### SQL Files
- `sql/test_factory.sql` and `sql/test_factory--0.5.0.sql`: Main extension code
- Complex role management and schema setup with proper cleanup
- Security definer functions for safe cross-schema operations

### Build Configuration  
- `META.in.json`: Template for PGXN metadata (processed to `META.json`)
- `test_factory.control`: PostgreSQL extension control file
- `Makefile`: Simple inclusion of pgxntool's build system

## Development Workflow

1. **Making Changes**: Modify source files in `sql/` directory
2. **Testing**: Run `make test` to ensure all tests pass
3. **Version Updates**: Update version in both `META.in.json` and `test_factory.control`  
4. **Distribution**: Use `make dist` to create release packages

## Extension Architecture Details

The extension handles complex bootstrapping during installation:
- Creates temporary role tracking for safe installation
- Sets up three schemas with proper ownership and permissions  
- Uses security definer pattern for controlled access to internal functions
- Automatically restores original database role after installation
- Implements dependency resolution through recursive `tf.get()` calls

## Usage Patterns

### Basic Registration
```sql
SELECT tf.register(
    'customer',
    array[
        row('base', 'INSERT INTO customer VALUES (DEFAULT, ''Test'', ''User'') RETURNING *')::tf.test_set
    ]
);
```

### With Dependencies
```sql 
SELECT tf.register(
    'invoice', 
    array[
        row('base', 'INSERT INTO invoice VALUES (DEFAULT, (tf.get(NULL::customer, ''base'')).customer_id, current_date) RETURNING *')::tf.test_set
    ]
);
```

### Data Retrieval
```sql
-- Gets customer test data, creating it if needed
SELECT * FROM tf.get(NULL::customer, 'base');

-- Gets invoice test data, automatically creating dependent customer data
SELECT * FROM tf.get(NULL::invoice, 'base'); 
```