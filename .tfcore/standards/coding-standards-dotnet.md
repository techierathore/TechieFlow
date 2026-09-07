# TechieFlow — Coding Standards, .NET

<!-- How this file is used and edited.
     The .NET answer set's coding standards. Loaded with coding-standards-core.md when a project's
     Coding Standards document names it. Owners in another stack write their own
     coding-standards-<stack>.md with the same section names.
     Seeded from the framework author's projects (the two sample files in the TechieFlow docs folder).
     To change a rule: edit this file in the TechieFlow repository, then run update-framework.sh on
     each project. Per-project choices this file leaves open are recorded in
     docs/<App>-Coding-Standards.md → "Standards applied"; project-only rules go in "Project rules". -->

## 1. Names

**Never use underscores** in any identifier, database object or environment variable name.

| Kind | Convention | Example |
|---|---|---|
| Classes, records, structs | PascalCase, descriptive | `SqlQueryBuilder`, not `SqlQB` |
| Interfaces | `I` prefix | `IQueryExecutor` |
| Methods | PascalCase verb phrase; async methods end in `Async` | `GetConnectionAsync()` |
| Properties | PascalCase, no prefix | `ConnectionString` |
| Instance fields | **per-project choice**: `obj` prefix (`objLogger`) or bare PascalCase (`Logger`). Default `obj`. Recorded in the project's Coding Standards | `private readonly ILogger<X> objLogger;` |
| Static and const fields | PascalCase, no prefix | `MaxRetryCount`, not `MAX_RETRY_COUNT` |
| Method parameters | `a` prefix + PascalCase | `LoginAsync(string aEmail)` |
| Local variables | `v` prefix + PascalCase | `var vResponse = …` |
| Booleans | same prefix, question form | `IsValid`, `vHasRows`, `aCanEdit` |
| Test methods | short PascalCase; scenario in the XML `<summary>` | `LoginRejectsBadPassword` |
| Environment variables | PascalCase, no separators; read through `IConfiguration` via a provider that maps them to `Section:Key` | `AppManagerBaseUrl` |

Rejected: `_field` prefixes, snake_case, Hungarian type prefixes (`strName`), `Method_State_Result` test names, `UPPER_SNAKE` or `Section__Key` environment variables.

Controller actions: the `a` prefix applies to `[FromRoute]`, `[FromQuery]` and `[FromBody]` parameters and flows into the OpenAPI schema. DTO **property** names stay PascalCase without prefix.

## 2. Database

- PascalCase, singular table names: `CustomerOrder`. PascalCase columns: `FirstName`.
- Primary key `<Table>Id`; foreign key `<ReferencedTable>Id`.
- Stored procedures and functions: verb prefix, PascalCase: `GetCustomerOrders`, `InsertOrder`.
- Index `IX<Table><Column>` · primary key `Pk<Table>` · foreign key `Fk<Table><Ref>` · unique `Uc<Table><Column>`.
- Data access is Dapper. Migrations live in a dedicated `<App>Db` project using DbUp, run at application startup or by the pipeline. Never a `database` folder of loose scripts at the root.

## 3. Projects and files

- `src/` and `tests/` at the root. The primary head is `src/<App>/<App>.csproj`; `<App>.App` is banned. Secondary heads take a descriptive suffix: `<App>.Api`, `<App>.Desktop`, `<App>.Cli`. Satellites: `<App>.Core`, `<App>UI` (Razor class library), `<App>.Tests`.
- One class per file; file-scoped namespaces; nullable reference types enabled.
- File order: usings, namespace, type; inside the type: fields, constructor, properties, methods.
- Configuration: `appsettings.json` layered by `appsettings.{Environment}.json`; development secrets in `dotnet user-secrets`, with a `secrets.example.json` listing every key. No second mechanism.

## 4. Code

- Methods under about 20 lines; single responsibility; at most three levels of nesting; early returns.
- `async`/`await` for all I/O; `ConfigureAwait(false)` in libraries; no `async void` outside event handlers.
- LINQ method syntax for simple queries; avoid multiple enumeration.
- `StringBuilder` in loops; dispose `IDisposable`; cache expensive work.
- XML documentation on every public member: `<summary>`, `<param>`, `<returns>`, `<exception>`; `<remarks>` where the flow is not obvious.

## 5. Tests

- xUnit. A test project from day one.
- Short PascalCase names, scenario in `<summary>`; arrange, act, assert; one assertion per test where practical.

## 6. Logging

- Serilog with a rolling file sink in every executable head (web, API, MAUI, desktop, console, background service), wired before anything else can fail: `Log.Logger = new LoggerConfiguration().MinimumLevel.Information().WriteTo.Console().WriteTo.File("<build output>/logs/<app>-.log", rollingInterval: RollingInterval.Day, retainedFileCountLimit: 14).CreateLogger();` then `builder.Services.AddSerilog()` or `builder.Host.UseSerilog()`; MAUI: `builder.Logging.AddSerilog()` in `MauiProgram`, path under `FileSystem.AppDataDirectory`.
- `Log.Fatal` around startup, handlers for `AppDomain.CurrentDomain.UnhandledException` and `TaskScheduler.UnobservedTaskException`, `Log.CloseAndFlush()` on exit.
- Class libraries reference only `Microsoft.Extensions.Logging.Abstractions` and log through `ILogger<T>` with structured templates.
- Brownfield: an existing structured file-logging stack is compliant; new heads still use Serilog.

## 7. Testability

- Blazor: a stable `data-testid` (or element id) on every control the verifier must reach.
- MAUI: a stable, unique `AutomationId` on every interactive or data-bound control, named by intent (`LoginSubmitButton`, `ClientsGrid`), set on the element whose data the gate asserts.

## 8. Security

- No credentials in code. Parameterised queries. Validate inputs. Log security events.

## 9. Enforcement

`.editorconfig` at the repository root (created at day-1) enforces: file-scoped namespaces (warning), `Async` suffix (warning), `var` for locals (warning), nullable enabled, no `_` prefix on private fields (custom naming rule, warning). `StyleCop.Analyzers` is optional and off by default.

The verifier's standards check runs:

```bash
# underscore-prefixed fields
grep -rE "private(\s+readonly)?\s+\w+\s+_[a-z]" src/ 2>/dev/null
# underscores in test method names
grep -rE "public\s+(async\s+)?Task\s+\w+_\w+\s*\(" tests/ 2>/dev/null
# fields missing the obj prefix (obj-style projects only)
grep -rPE "private(\s+readonly)?\s+\w+\s+(?!obj)[A-Z]\w+\s*[;=]" src/ 2>/dev/null | grep -v "static\|const"
```

Severity: error for file-scoped namespace and underscore field prefix; warning for nullable and the `Async` suffix; the rest informational.
