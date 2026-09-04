# TechieFlow — Stack Defaults: .NET

| | |
|---|---|
| Purpose | An answer set for `TechieFlow-Stack-Questions.md`. These are the defaults the framework's author uses for their own .NET / Blazor / MAUI projects. Naming this answer set at day-1 fills in the questions it covers; the agent asks the rest. |
| Audience | Owners of .NET projects using TechieFlow. Owners in other stacks write their own answer set with the same structure. |
| Status | Drafted in Session 2 of the reset (2026-09-04) from the author's answers. Becomes a file under `.tfcore/templates/stack-defaults/` in Session 3. Configuration document read by agents; not rendered to HTML. |
| Applies to | Projects that declare `stack: dotnet` and name this answer set. Change any row for a project by overriding it in that project's Architecture Stack Decisions section; the override wins. |

---

## Answers

| Q | Topic | Default | Still asked at day-1? |
|---|---|---|---|
| Q1 | Configuration | Non-secret configuration lives in `appsettings.json`, layered by `appsettings.{Environment}.json`. No other configuration mechanism is created. | No |
| Q2 | Secrets in development | Project user secrets (`dotnet user-secrets`), visible to the developer, never committed. `appsettings.Development.json` is committed and therefore never holds a real secret. A `secrets.example.json` in the project lists every key the application reads. | No |
| Q3 | Database | PostgreSQL, running in Docker, for development and production. Docker is always running on the development machine because WSL, where the harness runs, depends on it. If PostgreSQL is unreachable the container is stopped: the agent starts it and continues. Only if no PostgreSQL container exists at all does the agent stop and ask the owner for connection details. It never substitutes another engine and never creates its own database container. | No, unless no container exists |
| Q4 | Authentication | Two choices only: **AppManager**, the author's shared platform for identity, roles, licences and subscriptions, which counts as part of the application and not as an external integration; or a different mechanism named by the owner. | **Yes**: "AppManager, or something else?" |
| Q5 | Logging | Serilog, always, with file logging wired at startup before anything else can fail. | No |
| Q6 | Tests | xUnit, always. A test project exists from day-1. | No |
| Q7 | Layout and naming | `src/` and `tests/` at the root. The primary executable project is named exactly `<App>`; `<App>.App` is banned. Secondary heads take a descriptive suffix (`<App>.Api`, `<App>.Desktop`). | No |
| Q8 | User interface | TrBlazeUI for every Blazor head and every MAUI Blazor Hybrid head. Native controls for WinForms, WPF and non-Blazor MAUI heads. Rendering mode is chosen per project and recorded. | Rendering mode only |
| Q9 | Hosting | Web applications run containerised on a Bluehost VPS. The owner supplies a pipeline guidance document at UAT go-ahead, and a deployment checklist is produced from it. | Asked at UAT go-ahead, as the questionnaire specifies |
| Q10 | Production secrets | Decided when the owner asks for the production pipeline, after UAT. Until then no document states where production secrets live. | Asked after UAT |
| Q11 | Standing rules and prohibitions | 1. Never add a NuGet package without a line in the Architecture document saying why. 2. Never create a second configuration mechanism. 3. When TechieFlow, TrBlazeUI, TechieRag or any other internal library lacks something, record it in that library's feedback file and hold the feature until the library is fixed. Never implement a workaround. 4. Data access is always Dapper. 5. Database migrations live in a dedicated project named `<App>Db` (console or library) using the DbUp package. The web application runs the migration at startup, or the pipeline runs it after deployment. Never a `database` folder of loose scripts at the repository root. 6. Log files are written under the build output folder (`bin/`), which is git-ignored. Never at the repository root. 7. No unnecessary folders at the repository root (`data`, `database`, `scripts` and the like). Everything sits under `src/` or `tests/` according to what it belongs to. | No |

---

## Notes

- Q4 is asked on purpose even with this answer set, because the choice differs per product.
- Q3's "start the container, never create one" replaces the behaviour that produced TfLens's own database container: an agent that cannot reach the expected database restarts it or asks, and never builds an alternative.
- Q11.5 replaces the `database` folder of loose migration scripts that TfLens accumulated.
- Q11.3 is a standing framework convention restated as a stack rule so that it is recorded per project and its violations can be counted.
