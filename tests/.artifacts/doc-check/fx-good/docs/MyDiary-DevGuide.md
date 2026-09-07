# MyDiary — Developer Guide

| | |
|---|---|
| App | MyDiary |
| Kind | app |
| Size | Small |
| Verified on | 2026-09-04 |
| Date | 2026-09-04 |

## Architecture cheat-sheet

| Layer | Project or folder | What lives here |
|---|---|---|
| UI | `src/MyDiary/Pages` | pages |

## Roles and menu map

| Role | Test user | Menu items and the screen each opens |
|---|---|---|
| Writer | 1 | Entries → Entries (`/entries`) |

## Screen-by-screen code map

### Login (`/login`)

![Login](screenshots/MyDiary/login.png)

**Call chain:** `Login.razor.cs:HandleLogin` → `AuthSvc.CheckLogin` → `UserDa.VerifyUser`

| File and line | Function | Watch | Expected value |
|---|---|---|---|
| `src/MyDiary/Pages/Login.razor.cs:127` | `HandleLogin` | `aLogin.Email` | the email typed in the box |

## Cross-cutting flows

### Sign-in
**Call chain:** as above.

## Known issues

- none
