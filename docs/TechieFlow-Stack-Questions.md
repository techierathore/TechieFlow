# TechieFlow — Stack Questions

| | |
|---|---|
| Purpose | The questions the framework asks the owner about a project's technology and conventions, when it asks them, and where the answers are recorded. The framework itself is technology-neutral; these answers are what make a project's documents and code specific. |
| Audience | Framework agents (the questionnaire is asked verbatim), project owners, contributors. |
| Status | Drafted in Session 2 of the reset (2026-09-04). Becomes a template under `.tfcore/templates/` in Session 3. Configuration document read by agents; not rendered to HTML. |
| Related | `TechieFlow-Stack-Defaults-DotNet.md` (an answer set), `TechieFlow-Requirements.md` (FR-01, FR-02) |

---

## 1. Principle

The framework never assumes a language, a UI library, a database, an authentication scheme, a test framework or a hosting target. Before any project document is written, the agent asks the questions below and records the answers in one place: the **Stack Decisions** section of the project's Architecture document. Every later command reads its stack facts from there and nowhere else.

An owner who always works in one stack answers once by naming an **answer set**, a file that holds their standard answers. The framework ships one answer set, `TechieFlow-Stack-Defaults-DotNet.md`, described as the defaults its author uses for their own .NET projects. Any owner may copy it, change it, or write a different one. Naming an answer set fills in every question it covers; the agent then asks only the questions the set leaves open.

---

## 2. When the questions are asked

| Moment | Questions | Why then |
|---|---|---|
| Day-1, before any document is written | Q1 to Q8 | Every document depends on the answers. |
| When the owner gives the go-ahead for user acceptance testing (UAT) | Q9 | Hosting decisions made earlier are guesses; by UAT the application is real. |
| When the owner asks for a production deployment pipeline, after UAT | Q10 | Production secrets and infrastructure are decided by the people who run production. |

In YOLO mode the agent does not skip the day-1 questions; it takes the answer set's value where one exists and stops with a clear message where none does. A document written without a recorded answer is a defect.

---

## 3. The questions

**Q1. Configuration.** Where does non-secret configuration live, and how is it layered per environment?

**Q2. Secrets in development.** Where do secrets live on a developer machine, and what must never be committed?

**Q3. Database.** Which database engine in development and which in production? Is a container for the database acceptable, and under what condition? What does the agent do if the database is not reachable?

**Q4. Authentication and authorisation.** Which identity mechanism: a shared platform, the framework's built-in identity, an external provider, or none? Who owns roles, licences and subscriptions?

**Q5. Logging.** Which logging library, which sinks, and is file logging mandatory?

**Q6. Tests.** Which test framework? Is a test project mandatory from day one? Which categories of test are expected (unit, integration, browser)?

**Q7. Solution layout and naming.** Folder layout for source and tests; naming rule for the primary executable project and for secondary heads.

**Q8. User interface.** Which UI framework or component library for each kind of head (web, mobile, desktop)? Which rendering mode by default?

**Q9. Hosting and deployment.** Where does the application run, in what form (container, service, static files), and is there a deployment guidance document to follow? Is a deployment checklist required?

**Q10. Production secrets and pipeline.** Where do production secrets live, and how does the pipeline inject them?

**Q11. Standing rules and prohibitions.** Anything an agent must always or never do in this repository that is not already enforced by a hook. Recorded as a list; the framework treats each item as a rule and tracks whether it is honoured. Two rules are present by default in every project, whatever the stack, and an owner may remove them only by saying so:

1. Log files are written under the build output folder, which is git-ignored. Never at the repository root.
2. No unnecessary folders at the repository root (`data`, `database`, `scripts` and the like). Everything sits under the source folder or the tests folder according to what it belongs to.

---

## 4. Where the answers go

The Architecture document gains a section, **Stack Decisions**, placed first, one row per question:

| Q | Decision | Source | Date |
|---|---|---|---|
| Q1 | `appsettings.json` plus `appsettings.{Environment}.json` | answer set: DotNet | 2026-09-04 |
| Q3 | PostgreSQL in a container for development and production | owner, day-1 | 2026-09-04 |
| … | | | |

"Source" is either the answer set name or "owner" with the moment it was asked. Q9 and Q10 rows are added when they are answered; until then they read "not yet asked (UAT)" and "not yet asked (production)". The Coding Standards document references this section instead of restating it.

---

## 5. What this replaces

Before this document, the framework had one standing technology decision (Serilog file logging) written into the day-1 tasks, the BRD template and the Architecture template, and no place for any other. Projects therefore invented their own arrangements at build time; TfLens ended with settings in three places. This questionnaire moves every such decision to day-1 and to one recorded location.
