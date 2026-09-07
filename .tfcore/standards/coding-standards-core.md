# TechieFlow — Coding Standards, core

<!-- How this file is used and edited.
     Applies to EVERY project, whatever the stack. It is loaded by the build and by the verifier's
     standards check together with the stack file named in the project's Coding Standards document
     (docs/<App>-Coding-Standards.md → "Standards applied"). Rules here are technology-neutral;
     anything that names a language, framework or package belongs in a stack file
     (.tfcore/standards/coding-standards-<stack>.md).
     To change a rule: edit this file in the TechieFlow repository, then run update-framework.sh on
     each project. Projects never edit their .tfcore/ copy. A rule an agent has ignored twice becomes
     a script or a hook, or is deleted; it never gets a second paragraph. -->

## 1. Names

- One naming style per kind of thing, declared in the stack file, used everywhere. Never mix styles in one project.
- Names say what a thing is or does. No abbreviations a newcomer would have to ask about.
- Files are named after the one type they hold.

## 2. Layout

- Source under `src/`, tests under `tests/`. No other folders at the repository root unless the stack file allows one.
- Log files go under the build output folder, never at the repository root.
- The primary executable project carries the product name. A project named `<App>.App` is not allowed.

## 3. Dependencies and configuration

- No package is added without a row in the Architecture Decisions log saying why.
- One configuration mechanism per project. A second one is a defect.
- A missing feature in an internal library (TrBlazeUI, TechieRag, TechieFlow) is recorded in that library's feedback file and the feature is held. No workaround is written.

## 4. Code shape

- One type per file. Small methods. Early returns for validation. At most three levels of nesting.
- Every public member has a documentation comment in the language's own form.
- No commented-out code. Comments say why, not what.

## 5. Tests

- A test project exists from day one.
- Test names are short; the scenario lives in the test's documentation comment.
- Arrange, act, assert. One behaviour per test.

## 6. Security

- No credentials in code or in committed configuration. Secrets come from the mechanism in Stack Q2.
- Database access uses parameters, never string-built queries.
- Every input from outside the process is validated at the boundary. Security events are logged.

## 7. Logging

- Every executable head writes a rolling log file, wired at startup before anything else can fail, and logs unhandled exceptions at its boundary.
- Libraries log through the logging abstraction only; they never reference a logging implementation.

## 8. Testability

- Every interactive or data-bound control the verifier must reach carries a stable test id, named by intent (`LoginSubmit`, `EntriesGrid`), never by position.

## 9. Enforcement

- The machine-checkable subset lives in the repository's editor configuration and analyzer settings, as the stack file specifies.
- The verifier's standards check runs the greps listed in the stack file's Enforcement section and records findings in the checklist Remarks and PROJECT-STATUS.
