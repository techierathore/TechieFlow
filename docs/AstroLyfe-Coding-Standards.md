<!-- FRAMEWORK REFERENCE SAMPLE — example of a per-project Coding-Standards doc the day-1 analyst task produces. AstroLyfe illustrates the no-prefix instance-field choice; AppManager illustrates the obj-prefix choice. Not a live project doc. -->
# AstroLyfe Coding Standards

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

AstroLyfe uses a deliberate prefix scheme so the role of every identifier is unambiguous on sight. **NEVER use underscores** anywhere in any identifier.

| Kind | Convention | Example |
|------|-----------|---------|
| **Instance fields** | PascalCase, **no prefix** | `private readonly HttpClient HttpClient;`<br>`private readonly ILogger<AppManagerClient> Logger;`<br>`private string CachedPublicKey;` |
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
- The scheme is enforced retroactively across the AstroAPI service layer (see F0-11 closure note in `docs/AstroLyfe-Development-Plan.md`) and is the canonical project convention.

**Things this scheme deliberately rejects:**
- ❌ `_underscore` field prefixes (Microsoft .NET default style).
- ❌ `obj`-prefix on fields or booleans (an earlier draft of this doc).
- ❌ snake_case anywhere.
- ❌ Hungarian-style type prefixes (`strName`, `intCount`).
- ❌ **Underscores in test method names** (`Method_State_Behavior`). Use a short PascalCase name and put the full scenario in the `<summary>` XML doc — long names get illegible quickly, and XML docs surface in IDE tooltips and test runner output anyway.
- ❌ **`UPPER_SNAKE_CASE` environment variable names** (`APPMANAGER_BASE_URL`). Use PascalCase env vars (`AppManagerBaseUrl`) per §"Environment Variables" below — bash and every modern CI/orchestrator handle case-sensitive env var names correctly, and a small custom .NET configuration provider bridges the PascalCase env var → `:`-nested config key.

### Environment Variables

Environment variable names follow the **same no-underscore rule** as every other identifier in the project: **PascalCase, no separator characters**.

| Style | Example | Verdict |
|-------|---------|---------|
| **PascalCase** | `AppManagerBaseUrl`, `JwtSecretKey`, `DbConnectionString` | ✅ canonical |
| `UPPER_SNAKE_CASE` | `APPMANAGER_BASE_URL`, `JWT_SECRET_KEY` | ❌ rejected — POSIX convention but breaks the project no-underscore rule |
| `kebab-case` | `app-manager-base-url` | ❌ illegal — POSIX shells forbid `-` in variable names |
| `lowercase` | `appmanagerbaseurl` | ❌ unreadable, no separator visible |
| double-underscore .NET style | `AppManager__BaseUrl` | ❌ rejected — same rule |

**Bash / POSIX shells are case-sensitive on env-var names**, so `export AppManagerBaseUrl=…` and `$AppManagerBaseUrl` work as written. This has been verified on bash, zsh, sh, dash; GitHub Actions, GitLab CI, CircleCI; Docker, Kubernetes ConfigMap/Secret, systemd `Environment=`. The only known historical exception is Jenkins ≤ 2.x on Windows agents, which is not in AstroLyfe's deployment scope.

**.NET configuration binding shim required.** ASP.NET Core's default `EnvironmentVariablesConfigurationProvider` translates `AppManager__BaseUrl` (double-underscore) into the `AppManager:BaseUrl` config path. Since we forbid underscores, we ship a small custom provider (F0-10 §2 in `docs/AstroLyfe-Development-Plan.md`) that maps each PascalCase env var to the corresponding `:`-nested config path. Do not enable both providers — pick the custom one and stop calling `builder.Configuration.AddEnvironmentVariables()` with the default behaviour.

**Application code** then reads values via `IConfiguration` exactly as it would from `appsettings.json`:
```csharp
public AppManagerClient(IConfiguration aConfiguration, ILogger<AppManagerClient> aLogger)
{
    var vBaseUrl = aConfiguration["AppManager:BaseUrl"];   // resolved from env if present, else appsettings.json
    var vApiKey  = aConfiguration["AppManager:ApiKey"];
    Logger = aLogger;
    HttpClient = new HttpClient { BaseAddress = new Uri(vBaseUrl) };
}
```
No `Environment.GetEnvironmentVariable("AppManagerBaseUrl")` calls scattered through service code — the env-var provider is the single ingestion point.

### Code Organization

#### File Structure
```csharp
// 1. Using directives
using System;
using System.Collections.Generic;

// 2. File-scoped namespace
namespace AstroAPI.Services.Example;

// 3. Class/Interface
public class DatabaseService
{
    // 4. Fields — PascalCase, no prefix
    private readonly ILogger<DatabaseService> Logger;
    private readonly IConfiguration Configuration;
    private string CachedConnectionString;

    // 5. Constructor — parameters use a-prefix
    public DatabaseService(ILogger<DatabaseService> aLogger, IConfiguration aConfiguration)
    {
        Logger = aLogger;
        Configuration = aConfiguration;
    }

    // 6. Properties — PascalCase, no prefix
    public string ConnectionString { get; set; }

    // 7. Methods — async ends with "Async"; locals use v-prefix
    public async Task<DataTable> GetDataAsync(string aQueryName)
    {
        var vConnectionString = Configuration.GetConnectionString("Default");
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
catch (SpecificException ex)
{
    Logger.LogError(ex, "Specific error occurred");
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
/// <param name="query">The SQL query to execute.</param>
/// <returns>Query results as DataTable.</returns>
/// <exception cref="ArgumentNullException">Thrown when query is null or empty.</exception>
/// <exception cref="SqlException">Thrown when database operation fails.</exception>
public async Task<DataTable> ExecuteQueryAsync(string query)
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
/// supplied with a valid AstroLyfe connection string.
/// </summary>
[Test]
public async Task ConnReturnsOpen()
{
    // Arrange
    var vConnectionString = "Server=...;Database=AstroLyfe;...";

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

### Logging — Serilog file sink (MANDATORY, every .NET app type)

- Every executable head (web host, API, MAUI, desktop, console/CLI, background service) wires **Serilog with a rolling file sink** at startup — `logs/{appname}-.log`, daily rolling, ~14 files retained, plus console. No exceptions; never wait for the owner to ask.
- Hosts: `builder.Host.UseSerilog()` / `builder.Services.AddSerilog()`; MAUI: `builder.Logging.AddSerilog()` in `MauiProgram.CreateMauiApp`, log path rooted in `FileSystem.AppDataDirectory` (desktop: `LocalApplicationData`), never the install dir. Read overrides from the `Serilog` section of `appsettings.json` where the host has one.
- Log unhandled exceptions at the head boundary (`Log.Fatal` around startup, `AppDomain.CurrentDomain.UnhandledException`, `TaskScheduler.UnobservedTaskException`) and `Log.CloseAndFlush()` on exit.
- Class libraries never reference Serilog — they log via `ILogger<T>` / logging abstractions only. App code logs through injected `ILogger<T>` with structured templates, not static `Log.*`.
- The `logs/` output folder is gitignored (owner adds the entry — agents never run git).

### MAUI UI testability — stable AutomationId (MAUI apps only)

- Every interactive or data-bound control the verifier must reach (buttons, entries, pickers, list/collection views, key labels/values) carries a stable, unique `AutomationId` — the native analogue of a stable DOM id for Playwright. Without it, Appium selectors drift and the runtime gates (`verify-phase §4a/§4b`) can't reliably find controls on the Android/iOS/Mac Catalyst heads.
- Name by intent, not layout: `AutomationId="LoginSubmitButton"`, `AutomationId="ClientsGrid"`, `AutomationId="TotalBalanceValue"` — never positional (`Button2`).
- Set it on the control whose data the gate asserts (the grid/list itself, the value label), so "rows present AND non-empty" / "value not blank" maps to one addressable element.
- (Blazor screens use the equivalent `data-testid`/stable element ids for Playwright — same principle.)

## Code Analysis Rules

StyleCop and .NET Analyzers are configured to enforce these standards automatically.

### Severity Levels
- **Error**: Must fix before commit
- **Warning**: Should fix
- **Info**: Consider fixing
- **Hidden**: Suggestions only