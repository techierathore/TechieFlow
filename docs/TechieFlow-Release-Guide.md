# TechieFlow — Release Guide

| | |
|---|---|
| Purpose | How the owner publishes a new version of the npm package. |
| Audience | The framework owner. |
| Package | [`@techierathore/techieflow`](https://www.npmjs.com/package/@techierathore/techieflow) |
| Release workflow | [`.github/workflows/release.yml`](../.github/workflows/release.yml) |
| Check workflow | [`.github/workflows/validate.yml`](../.github/workflows/validate.yml) |
| Package manifest | [`package.json`](../package.json) |

After the one-time setup, nobody runs `npm publish` by hand and nobody creates a token. Publishing a GitHub release starts a workflow that runs the checks and publishes through npm Trusted Publishing. The release tag is the version.

**Why no token.** npm Trusted Publishing lets GitHub prove to npm which repository and which workflow file is running. npm then hands the run a credential that dies when the run ends. There is nothing to copy, store, rotate or leak. npm is retiring the old long-lived publishing tokens, so this is the only route to set up now. It is the same route the Playbook already uses.

---

## 0. One-time setup

Do this once. It has three parts: publish the first version from your own computer, then tell npm to trust this repository's workflow, then never publish by hand again.

The package has to exist on npm before its Trusted Publisher settings page appears. That is why the first version is published from your machine.

### 0.1 Check the account

Sign in at <https://www.npmjs.com> and confirm the profile is `techierathore`. That account already owns the `@techierathore` scope through the Playbook package.

Two-factor authentication must be on. If it is not, open **Account settings**, then **Two-Factor Authentication**, and follow the steps. Keep the recovery codes in your password manager. Never paste a password, code or token into a chat, a document or a screenshot.

### 0.2 Prepare the machine

You need Node 22.14.0 or newer and npm 11.5.1 or newer. Check:

```bash
node --version
```

```bash
npm --version
```

If npm is older, update it:

```bash
npm install --global npm@11
```

### 0.3 Publish the first version from your computer

The workflow file `release.yml` must already be on GitHub before step 0.4, so push the branch first if you have not.

Step 1. Open a terminal in the TechieFlow folder and sign in. A browser window opens and asks for your password and the two-factor code.

```bash
npm login
```

Step 2. Set the first version on your machine only. Do not commit this change; the next step puts the file back.

```bash
npm version 1.0.0 --no-git-tag-version
```

Step 3. Publish. npm runs the checks first (validate and the installer test), then asks for a two-factor code.

```bash
npm publish --access public
```

Step 4. Put `package.json` back to its placeholder version so nothing version-related is ever committed.

```bash
git checkout -- package.json
```

Step 5. Open <https://www.npmjs.com/package/@techierathore/techieflow> and confirm version 1.0.0 is there.

### 0.4 Tell npm to trust the GitHub workflow

Step 1. On the package page, select **Settings**.

Step 2. Under **Trusted publishing**, select **GitHub Actions**.

Step 3. Enter these values exactly.

| npm field | Value |
|---|---|
| Organization or user | `techierathore` |
| Repository | `TechieFlow` |
| Workflow filename | `release.yml` |
| Environment name | leave blank |
| Allowed actions | `npm publish` |

Enter only `release.yml`, not `.github/workflows/release.yml`. Leave the environment blank so a release publishes without a manual approval click.

Step 4. Save.

From now on, every version is published by the workflow. Do not create an npm access token and do not add a secret to the repository. The workflow needs neither.

---

## 1. Choose the new version

npm versions cannot be replaced. Once `1.0.0` is published it is published forever. Choose the next number by the size of the change.

| Change | Example tag |
|---|---|
| Fix, nothing new | `v1.0.1` |
| New task, template or flag, nothing removed | `v1.1.0` |
| Something removed or renamed that a project depends on | `v2.0.0` |
| Try-out build for testing | `v1.1.0-beta.1`. Published under the npm tag `next`, so `@latest` does not pick it up. |

The first version, `1.0.0`, was published by hand in section 0. Releases start at `v1.0.1`.

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

Step 3. Under **Choose a tag**, type the new tag, for example `v1.0.1`, and select **Create new tag on publish**.

Step 4. Target `main`, or the commit you want to ship.

Step 5. Give the release a title and a few lines saying what changed.

Step 6. Select **Publish release**.

Publishing the release starts the **Publish npm package** workflow. Pushing a tag by itself does not.

---

## 5. What the workflow does

1. Checks out the release tag.
2. Installs Node 22.14.0 and npm 11.
3. Reads the version from the tag. A tag that does not start with `v` fails the run.
4. Writes that version into `package.json` on the build machine.
5. Refuses to continue if that version is already on npm.
6. Runs the checks: validate, the installer test, and a dry-run pack. Any failure stops the run here.
7. On a second machine, checks out the tag again and runs `npm publish`. npm runs the checks once more, then publishes through Trusted Publishing with provenance, which ties the published files to this exact commit and run. A stable version goes to the npm tag `latest`. A pre-release goes to `next`.
8. Asks npm for the new version and fails if it is not listed within a minute.

---

## 6. Confirm

Step 1. Open the repository's **Actions** tab and select the **Publish npm package** run. Wait for the green tick.

Step 2. Open <https://www.npmjs.com/package/@techierathore/techieflow> and check the version number. The **Provenance** box on that page shows the workflow run that built it.

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
| `ENEEDAUTH` or `E404` on publish | The Trusted Publisher entry on npm does not match. Check all five values in section 0.4, especially that the workflow filename is exactly `release.yml`, and that the publish job has `id-token: write`. Do not add a token. |
| `E403` mentioning two-factor authentication | Only happens on a manual publish. Complete the two-factor prompt. The workflow never sees this. |
| The first manual publish returns `402` | The command is missing `--access public`. |
| The publish failed after the release was created and the cause is now fixed | Open **Actions**, select **Publish npm package**, select **Run workflow**, enter the existing tag. The run checks out that tag and publishes it. |
| npm still shows the old version | Wait for the run to finish, then reload the page. |
