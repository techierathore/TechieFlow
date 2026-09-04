# MyDiary — UI Design

| | |
|---|---|
| App | MyDiary |
| Kind | app |
| Size | Small |
| UI library | TrBlazeUI 2.0 |
| Theme | both |

## Design system

- **Layout shell:** top nav.
- **Theme:** light and dark.
- **Shared controls:** TrNavMenu, TrCard.
- **Rules:** 8px grid.

## Screens

### Screen: Login (`/login`)

**Mockup:** [mockups/login.html](mockups/login.html) · **Roles:** Writer · **BRD:** BRD-1

| Region | Control | Shows or binds |
|---|---|---|
| Form | TrForm | email, password |

| Field | Type | Required | Validation |
|---|---|---|---|
| Email | text | yes | email form |
| Password | password | yes | 8 or more |

**Dialogs opened here:** none

**States:** empty: form blank · loading: button spinner · error: red alert under the form

### Screen: Entries (`/entries`)

**Mockup:** [mockups/entries.html](mockups/entries.html) · **Roles:** Writer · **BRD:** BRD-2

| Region | Control | Shows or binds |
|---|---|---|
| Search | TrTextBox | search term |
| List | TrDataGrid | entries |

| Field | Type | Required | Validation |
|---|---|---|---|
| Search | text | no | none |

**Dialogs opened here:** Edit entry: title, body

**States:** empty: "No entries yet" · loading: skeleton rows · error: alert
