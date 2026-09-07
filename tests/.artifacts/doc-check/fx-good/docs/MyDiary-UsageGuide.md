# MyDiary — Usage Guide

| | |
|---|---|
| App | MyDiary |
| Kind | app |
| Size | Small |
| Date | 2026-09-04 |

## Test users

| # | User | Password source | Role | Exists |
|---|---|---|---|---|
| 1 | writer@app.test | user secrets | Writer | no |

## Execution guide

Prerequisites: .NET 9 SDK, PostgreSQL in Docker.

```
dotnet restore
dotnet run --project src/MyDiary --urls http://localhost:5099
```

Open http://localhost:5099 and sign in as user 1.

## How to test, screen by screen

### Login
- **Sign in as:** 1
- **Steps:** 1) open /login 2) enter email and password 3) press Enter
- **Expected:** Entries opens
- **Covers:** REQ-UI-001

## Automated tests

```
dotnet test
```
Unit tests for the entry service.

## Known limitations

- none
