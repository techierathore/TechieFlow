<!-- FRAMEWORK REFERENCE SAMPLE — example of a per-project Coding-Standards doc the day-1 analyst task produces. AppManager illustrates the obj-field-prefix choice; AstroLyfe illustrates the no-prefix choice. Not a live project doc. -->
# AppManager Coding Standards

**Last Updated:** 2026-04-29
**Status:** Authoritative for all code under `src/`. Conformance enforced via `.editorconfig` at the repo root and (optionally) StyleCop analyzers. Pre-existing code is being brought into conformance under the [Coding Standards Conformance refactor](DevlopmentPlan.md#architectural-refactor--planned-coding-standards-conformance-2026-04-29).

## Database Naming Conventions

### Tables and Columns
- Use PascalCase for table names: `CustomerOrder` NOT `customer_order`
- Use singular table names : `CustomerOrder` NOT `CustomerOrders`
- Use PascalCase for column names: `FirstName` NOT `first_name`
- **NEVER use underscores** in database object names
- Foreign key columns: `{TableName}Id` (e.g., `CustomerId`)
- Primary key:`{TableName}Id` (e.g., `UserId`)

### Stored Procedures and Functions
- Use PascalCase with verb prefix: `GetCustomerOrders` NOT `get_customer_orders`
- Prefix with action: Get, Insert, Update, Delete, Calculate

### Indexes and Constraints
- Index naming: `IX{TableName}{ColumnName}`
- Primary key: `Pk{TableName}`
- Foreign key: `Fk{TableName}{ReferencedTable}`
- Unique constraint: `Uc{TableName}{ColumnName}`

## C# Coding Conventions

### Naming Conventions

#### Classes and Interfaces
- Use PascalCase for class names: `DatabaseConnection`
- Prefix interfaces with 'I': `IQueryExecutor`
- Use descriptive names: `SqlQueryBuilder` not `SqlQB`

#### Methods
- Use PascalCase: `ExecuteQuery()`
- Use verbs or verb phrases: `GetConnection()`, `SaveData()`
- Async methods end with 'Async': `GetDataAsync()`

#### Fields, Parameters, and Local Variables (project convention)

AppManager uses a deliberate prefix scheme so the role of every identifier is unambiguous on sight. **NEVER use underscores** anywhere in any identifier.

| Kind | Convention | Example |
|------|-----------|---------|
| **Instance fields** | PascalCase, **obj** prefix no underscores  | `private readonly HttpClient objHttpClient;`<br>`private readonly ILogger<AppManagerClient> objLogger;`<br>`private string objCachedPublicKey;` <br> **NOT** _httpClient or _logger or _cachedPublicKey |
| **Static / `const` fields** | PascalCase, no prefix | `private const string CachePrefix = "AppMgr_Feature_";`<br>`public const string AccessKey = "auth_access_token";` |
| **Method parameters** | `a` prefix + PascalCase tail | `LoginAsync(string aEmail, string aPassword)`<br>`Configure(IConfiguration aConfiguration)` |
| **Local variables** | `v` prefix + PascalCase tail | `var vResponse = await HttpClient.GetAsync(...);`<br>`var vBaseUrl = aConfiguration["AppManager:BaseUrl"];`<br>`var vEnvelope = JsonSerializer.Deserialize<...>(...);` |
| **Boolean fields/locals/params** | Same prefix + `Is`/`Has`/`Can` question form | field `IsAuthenticated`, local `vIsValid`, parameter `aHasAccess` |
| **Properties** | PascalCase, no prefix | `public string ConnectionString { get; set; }` |
| **Constants (`const`)** | PascalCase, **no underscores** | `MaxRetryCount` NOT `MAX_RETRY_COUNT` |
| **Test methods** | Short PascalCase, **no underscores** — full scenario in XML `<summary>` | `LoginRejectsBadPassword` (not `Login_BadPassword_ReturnsUnauthorized`) |

**Why this scheme:**
- The `a`/`v` prefixes make parameter-vs-local-vs-field unambiguous in long methods without IDE colour.
- Fields share PascalCase with properties — the real distinction is access modifier (`private` field vs. `public` property), which is already explicit in the declaration.
- The scheme is the canonical project convention. Enforcement (after the Coding Standards Conformance refactor lands) is via `.editorconfig` rules at the repo root plus reviewer discipline for cases the analyzer cannot express (e.g. parameter `a`-prefix is not currently expressible as a Roslyn naming-rule, so reviewers and CI greps catch it).

**Things this scheme deliberately rejects:**
- ❌ `_underscore` field prefixes (Microsoft .NET default style).
- ❌ snake_case anywhere.
- ❌ Hungarian-style type prefixes (`strName`, `intCount`).
- ❌ **Underscores in test method names** (`Method_State_Behavior`). Use a short PascalCase name and put the full scenario in the `<summary>` XML doc — long names get illegible quickly, and XML docs surface in IDE tooltips and test runner output anyway.

#### Controller-action parameters (uniform application — no exception)

The `a`-prefix rule for parameters applies **uniformly**, including to controller actions. Parameters bound from the request via `[FromQuery]`, `[FromForm]`, `[FromRoute]`, and `[FromBody]` carry the `a` prefix in code, and that prefix flows through to the public OpenAPI / Swagger schema. The query-string parameter is `aEmail`, not `email`. The route segment is `{aIssueId:int}`, not `{issueId:int}`.

```csharp
// Controller action — request-bound params still take the a-prefix
[HttpGet("issues/{aIssueId:int}")]
public async Task<IActionResult> GetIssueAsync(
    [FromRoute] int aIssueId,
    [FromQuery] string aIncludeComments)
{
    var vIssue = await IssueService.GetByIdAsync(aIssueId);
    return Ok(vIssue);
}
```

**Body fields are unaffected** — `[FromBody]` deserializes against DTO property names, and DTO properties remain PascalCase with no prefix (e.g. `LoginRequest.Email`, not `LoginRequest.aEmail`). Only the parameter symbol that holds the deserialized DTO carries the `a` prefix:

```csharp
[HttpPost("login")]
public async Task<IActionResult> LoginAsync([FromBody] LoginRequest aRequest)
{
    // aRequest.Email — DTO property is PascalCase, no prefix
    // aRequest is the parameter, gets a-prefix
}
```

This was a deliberate decision (see DevlopmentPlan.md "Architectural Refactor — Coding Standards Conformance, Q2"). External API consumers migrating from v1.3 → v1.4 must rename every request-bound parameter accordingly — see [`api-migration-notes-v1.4.md`](api-migration-notes-v1.4.md) for the full rename map.

### Code Organization

#### File Structure
```csharp
// 1. Using directives
using System;
using System.Collections.Generic;

// 2. File-scoped namespace
namespace AppCore.Services.Example;

// 3. Class/Interface
public class DatabaseService
{
    // 4. Instance fields — PascalCase with obj prefix (no underscore)
    private readonly ILogger<DatabaseService> objLogger;
    private readonly IConfiguration objConfiguration;
    private string objCachedConnectionString;

    // 5. Constructor — parameters use a-prefix
    public DatabaseService(ILogger<DatabaseService> aLogger, IConfiguration aConfiguration)
    {
        objLogger = aLogger;
        objConfiguration = aConfiguration;
    }

    // 6. Properties — PascalCase, no prefix
    public string ConnectionString { get; set; }

    // 7. Methods — async ends with "Async"; locals use v-prefix
    public async Task<DataTable> GetDataAsync(string aQueryName)
    {
        var vConnectionString = objConfiguration.GetConnectionString("Default");
        var vResult = await ExecuteQueryAsync(vConnectionString, aQueryName);
        return vResult;
    }
}
```

### Best Practices

#### General
- One class per file
- File name matches class name
- Use file-scoped namespaces
- Enable nullable reference types

#### Methods
- Keep methods small (< 20 lines)
- Single responsibility principle
- Avoid deep nesting (max 3 levels)
- Early returns for validation

#### Error Handling
```csharp
try
{
    // Operation
}
catch (SpecificException aEx)
{
    objLogger.LogError(aEx, "Specific error occurred");
    throw;
}
```

#### Async/Await
- Always use async/await for I/O operations
- Configure await: `ConfigureAwait(false)` in libraries
- Avoid async void except for event handlers

#### LINQ
- Use method syntax for simple queries
- Use query syntax for complex joins
- Avoid multiple enumerations

### Comments and Documentation

#### XML Documentation (MANDATORY)
**ALL public classes, methods, and properties MUST have XML documentation comments.**

```csharp
/// <summary>
/// Executes a SQL query and returns results.
/// </summary>
/// <remarks>
/// This method performs the following steps:
/// 1. Validates the input query
/// 2. Opens a database connection
/// 3. Executes the query with timeout handling
/// 4. Returns results in a DataTable format
/// </remarks>
/// <param name="aQuery">The SQL query to execute.</param>
/// <returns>Query results as DataTable.</returns>
/// <exception cref="ArgumentNullException">Thrown when query is null or empty.</exception>
/// <exception cref="SqlException">Thrown when database operation fails.</exception>
public async Task<DataTable> ExecuteQueryAsync(string aQuery)
```

**Required XML Documentation Elements:**
- `<summary>`: Brief description of what the member does
- `<remarks>`: Detailed explanation of code flow and logic (REQUIRED for all methods)
- `<param>`: Description for each parameter
- `<returns>`: Description of return value
- `<exception>`: Document all exceptions that can be thrown

#### Inline Comments
- Explain 'why', not 'what'
- Keep comments up to date
- Remove commented-out code
- Use inline comments sparingly - prefer XML documentation
- Complex algorithms should have step-by-step comments

### Testing

#### Unit Tests
- **Short PascalCase test method name, no underscores.** Full scenario goes in the `<summary>` XML doc — IDE tooltips and most test runners surface XML docs in their output, so nothing is lost.
- Arrange-Act-Assert pattern.
- One assertion per test.
- Use meaningful test data.

```csharp
/// <summary>
/// Verifies that GetConnectionAsync returns a connection in the Open state when
/// supplied with a valid AppManager connection string.
/// </summary>
[Test]
public async Task ConnReturnsOpen()
{
    // Arrange
    var vConnectionString = "Server=...;Database=AppManager;...";

    // Act
    var vConnection = await GetConnectionAsync(vConnectionString);

    // Assert
    Assert.That(vConnection.State, Is.EqualTo(ConnectionState.Open));
}

/// <summary>
/// Verifies that GetConnectionAsync throws ArgumentNullException when the connection
/// string is null or empty.
/// </summary>
[Test]
public Task ConnRejectsNull()
{
    return Assert.ThrowsAsync<ArgumentNullException>(() => GetConnectionAsync(null));
}
```

> **No underscores anywhere — including test methods.** The `<summary>` doc carries the "given/when/then" detail; the method name is just a short locator. If two tests would collapse to the same short name, the right move is splitting the production method, not lengthening the test name with underscores.

### Performance

- Use `StringBuilder` for string concatenation in loops
- Dispose IDisposable objects
- Use connection pooling
- Cache expensive operations
- Avoid premature optimization

### Security

- Never hardcode credentials
- Use parameterized queries
- Validate all inputs
- Sanitize user data
- Log security events

### MAUI UI testability — stable AutomationId (MAUI apps only)

- Every interactive or data-bound control the verifier must reach (buttons, entries, pickers, list/collection views, key labels/values) carries a stable, unique `AutomationId` — the native analogue of a stable DOM id for Playwright. Without it, Appium selectors drift and the runtime gates (`verify-phase §4a/§4b`) can't reliably find controls on the Android/iOS/Mac Catalyst heads.
- Name by intent, not layout: `AutomationId="LoginSubmitButton"`, `AutomationId="ClientsGrid"`, `AutomationId="TotalBalanceValue"` — never positional (`Button2`).
- Set it on the control whose data the gate asserts (the grid/list itself, the value label), so "rows present AND non-empty" / "value not blank" maps to one addressable element.
- (Blazor screens use the equivalent `data-testid`/stable element ids for Playwright — same principle.)

## Migration & Enforcement

### `.editorconfig` (repo root)

A repo-root `.editorconfig` encodes the machine-checkable subset of these standards. It enforces:

- File-scoped namespaces (`csharp_style_namespace_declarations = file_scoped:warning`)
- No `_` prefix on private fields (custom Roslyn naming rule with severity `warning`)
- Async method `Async` suffix
- `var` for locals (so the `v` prefix rule applies cleanly)
- Nullable reference types enabled

Rules that are **not machine-enforceable** today and rely on reviewer discipline + CI greps:
- `obj` prefix on instance fields (Roslyn naming-rule grammar cannot express "match `obj` + PascalCase tail" with high precision)
- `a` prefix on parameters (same limitation)
- `v` prefix on locals
- Test method short-name + summary doc

For these, the orchestrator's PR check runs the following greps and fails the build on any hit:

```bash
# Forbidden field forms
grep -rE "private(\s+readonly)?\s+\w+\s+_[a-z]" src/   # underscore prefix
grep -rE "private(\s+readonly)?\s+\w+\s+(?!obj)[A-Z]\w+\s*[;=]" src/ \
  | grep -v "static\|const"                              # field without obj prefix

# Forbidden test-method form
grep -rE "public\s+(async\s+)?Task\s+\w+_\w+\s*\(" tests/
```

### StyleCop (optional)

`StyleCop.Analyzers` is **not** currently installed in any `.csproj`. Adding it is an open question — the package is opinionated about XML doc placement and `this.` qualification in ways that conflict with project conventions (see `dotnet_diagnostic.SA1101.severity = none` in `.editorconfig` to suppress the conflict). Decision deferred until after the Coding Standards Conformance refactor (Phase B) lands and the codebase is conforming.

### Severity Levels (when violations are reported)
- **Error**: Must fix before commit (currently: file-scoped namespace, underscore field prefix)
- **Warning**: Should fix (currently: nullable annotations, async suffix)
- **Info**: Consider fixing
- **Hidden**: Suggestions only