# TechieFlow — Release Guide

| | |
|---|---|
| Purpose | How the owner publishes a new version of the npm package. |
| Audience | The framework owner. |
| Package | [`@techierathore/techieflow`](https://www.npmjs.com/package/@techierathore/techieflow) |
| Release workflow | [`.github/workflows/release.yml`](../.github/workflows/release.yml) |
| Check workflow | [`.github/workflows/validate.yml`](../.github/workflows/validate.yml) |
| Package manifest | [`package.json`](../package.json) |

Nobody runs `npm publish` by hand. Publishing a GitHub release starts a workflow that runs the checks and publishes. The release tag is the version.

---

## 0. One-time setup

Do this once, before the first release.

Step 1. Sign in to npm at <https://www.npmjs.com> with the account that owns the `@techierathore` scope. The same scope already publishes the Playbook package.

Step 2. Create a token. Open **Access Tokens** under your avatar, then **Generate New Token**, then **Granular Access Token**.

- Name: `techieflow-github-actions`
- Packages and scopes: **Read and write**, limited to `@techierathore/techieflow` (or the whole `@techierathore` scope)
- Expiry: your choice. Put the date in your calendar. An expired token fails the publish with `ENEEDAUTH`.

Copy the token. It is shown once.

Step 3. Put the token in the repository. Open the GitHub repository, then **Settings**, then **Secrets and variables**, then **Actions**, then **New repository secret**.

- Name: `NPM_TOKEN`
- Value: the token you copied

Step 4. If your npm account requires two-factor authentication for publishing, set it to **Authorization only** under **Account settings**, or the workflow cannot publish with a token.

---

## 1. Choose the new version

npm versions cannot be replaced. Once `1.0.0` is published it is published forever. Choose the next number by the size of the change.

| Change | Example tag |
|---|---|
| Fix, nothing new | `v1.0.1` |
| New task, template or flag, nothing removed | `v1.1.0` |
| Something removed or renamed that a project depends on | `v2.0.0` |
| Try-out build for testing | `v1.1.0-beta.1`. Published under the npm tag `next`, so `@latest` does not pick it up. |

The first release is `v1.0.0`.

---

## 2. Do not edit the version in package.json

`package.json` says `0.0.0-development` and stays that way. The workflow checks out the release tag and writes the tag's number into `package.json` on the build machine only. Nothing is committed. There is no version commit to make and nothing to keep in step by hand.

---

## 3. Commit and push

Commit the changes as usual and push to `main`. Every push runs the **Validate** workflow. Wait for it to be green before you release. A red Validate means a red release.

The checks are the same ones the release runs:

| Check | What it proves |
|---|---|
| Mirror parity | Every file under `.claude/commands/TechieFlow/` equals its twin under `.tfcore/`. |
| OpenCode references | Every `{file:...}` in `opencode.jsonc` points at a file that exists. |
| Shell syntax | `bash -n` passes on every `.sh` file. |
| Package contents | `npm pack --dry-run` works, ships every file the shell scripts deploy, and ships no local-only file. |
| Installer test | The installer and the three shell scripts produce identical folders, for brownfield, greenfield and update. |

You can run them yourself before pushing:

```bash
npm run validate
```

```bash
npm run test:install
```

---

## 4. Publish the GitHub release

Step 1. Open <https://github.com/techierathore/TechieFlow/releases>.

Step 2. Select **Draft a new release**.

Step 3. Under **Choose a tag**, type the new tag, for example `v1.0.0`, and select **Create new tag on publish**.

Step 4. Target `main`, or the commit you want to ship.

Step 5. Give the release a title and a few lines saying what changed.

Step 6. Select **Publish release**.

Publishing the release starts the **Publish npm package** workflow. Pushing a tag by itself does not.

---

## 5. What the workflow does

1. Checks out the release tag.
2. Installs Node 22 and points npm at the public registry.
3. Reads the version from the tag. A tag that does not start with `v` fails the run.
4. Writes that version into `package.json` on the build machine.
5. Refuses to continue if that version is already on npm.
6. Runs `npm publish`. npm runs the checks first (`prepublishOnly`: validate and the installer test). Any failed check stops the publish.
7. Publishes with the `NPM_TOKEN` secret. A stable version goes to the npm tag `latest`. A pre-release goes to `next`.
8. Asks npm for the new version and fails if it is not listed within a minute.

---

## 6. Confirm

Step 1. Open the repository's **Actions** tab and select the **Publish npm package** run. Wait for the green tick.

Step 2. Open <https://www.npmjs.com/package/@techierathore/techieflow> and check the version number.

Step 3. Try it in an empty folder.

```bash
mkdir tf-check && cd tf-check && git init
```

```bash
npx @techierathore/techieflow@latest install --greenfield
```

```bash
ls -a
```

You should see `.tfcore`, `.claude`, `.opencode`, `.codex`, `.agents`, `opencode.jsonc`, `WORKFLOW.html`, `docs`, `src`, `tests` and no `node_modules`.

---

## 7. If something goes wrong

| Problem | What to do |
|---|---|
| Validate is red on `main` | Open the run, read the failing check, fix it, push again. Do not release until it is green. |
| The run says the version already exists | Create the next version. A published version cannot be replaced. |
| The run says the tag must start with `v` | Delete the release and the tag, and create them again with a tag like `v1.0.1`. |
| The workflow did not start | You pushed a tag without publishing a release. Open the Releases page and publish one for that tag. |
| `ENEEDAUTH` or `E401` | The `NPM_TOKEN` secret is missing, expired or has no publish right. Make a new token (section 0) and update the secret. |
| `E403` mentioning two-factor authentication | Set two-factor to **Authorization only** on npm, or make an automation token. |
| The publish failed after the release was created and the cause is now fixed | Open **Actions**, select **Publish npm package**, select **Run workflow**, enter the existing tag. The run checks out that tag and publishes it. |
| npm still shows the old version | Wait for the run to finish, then reload the page. |
