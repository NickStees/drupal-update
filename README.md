## Description
Bash script for updating Drupal core and/or contributed modules with Composer.
It can be used as a GitHub action or as a standalone script/integrated into other CI tools.

## Features
* perform minor or major updates to Drupal core / contributed modules
* options to exclude modules from check and/or enable Drupal core checks
* outputs Markdown table of changes as a file or environment variable
* highlight failed patches
* can be used as a GitHub action
* can be used as a standalone script
* supports composer command prefixes for containerized environments (ddev, docker-compose, etc.)

## Notes
* supported update type modes are `semver-safe-update` and `all`. `All` represents full upgrade between major core versions.
* Semver necessarily does not mean minor versions only (etc 2.1.0, 2.1.2).
* If you requested package as `^11.0`, any release as `^11.5` is considered by this script as `minor`.
* The provided patch failures could be in some scenarios false-positive.
* This tool is not providing a one click upgrade - review release notes for each module, etc.

## GitHub Action Usage
![](https://vallic.com/sites/default/files/2023-11/github_example.png "GitHub Drupal Upgrades")

See [action.yml](action.yml)

```yaml
    steps:
      - uses: actions/checkout@v2
      - name: Check updates
        id: updates
        uses: valicm/drupal-update@v4

```

### GitHub action example to create PR with updates
* Runs each day once at midnight.
* Perform minor/security updates
* Creates automated PR with branch `drupal-automated-updates`
_(you need to set secret variable named MY_PERSONAL_TOKEN in your repo, so that PR can be created)_

```yaml
name: Automated Drupal updates

on:
  workflow_dispatch:
  schedule:
    - cron: '0 0 * * *'

jobs:
  check-available-updates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Check updates
        id: updates
        uses: valicm/drupal-update@v4

      - name: create pull-request
        uses: peter-evans/create-pull-request@v5
        with:
          token: ${{ secrets.MY_PERSONAL_TOKEN }}
          commit-message: Automated Drupal updates
          title: Automated Drupal updates
          body: ${{ env.DRUPAL_UPDATES_TABLE }}
          branch: drupal-automated-updates
          delete-branch: true

```

### GitHub Action with composer prefix

For environments where composer is not directly available in the GitHub runner but accessible through containerized tools:

```yaml
    steps:
      - uses: actions/checkout@v2
      - name: Setup DDEV
        # Add your DDEV setup steps here
      - name: Check updates with DDEV
        id: updates
        uses: valicm/drupal-update@v4
        with:
          composer_prefix: 'ddev'
```

## Standalone script usage
![](https://vallic.com/sites/default/files/2023-11/local_example.png "GitHub Drupal Upgrades")

| Example                                       | Command                                      |
|-----------------------------------------------|----------------------------------------------|
| Run all minor and security updates            | `bash drupal-update.sh`                      |
| Run any update (minor, security, major)       | `bash drupal-update.sh -t all`               |
| Run any update, except for Drupal core        | `bash drupal-update.sh -t all -c false`      |
| Run minor update, excluding some modules      | `bash drupal-update.sh -e pathauto,redirect` |
| Run all updates, saving summary in upgrade.md | `bash drupal-update.sh -t all -o upgrade.md` |
| Run updates with ddev prefix                  | `bash drupal-update.sh -p ddev`              |
| Run updates with docker-compose prefix        | `bash drupal-update.sh -p "docker-compose exec web"` |


Get all minor updates and output results in summary.md file.
```bash
curl -fsSL https://raw.githubusercontent.com/valicm/drupal-update/main/drupal-update.sh | bash -s -- -o summary.md
```

## Composer Prefix Support

The script supports prefixing composer commands for containerized development environments. This is useful when composer is not available directly on the host system but is accessible through container tools like ddev, docker-compose, or other container management systems.

### Usage Examples

**DDEV (recommended for Drupal development):**
```bash
bash drupal-update.sh -p ddev
```

**Docker Compose:**
```bash
bash drupal-update.sh -p "docker-compose exec web"
```

**Custom container setup:**
```bash
bash drupal-update.sh -p "docker exec my-container"
```

**Combined with other options:**
```bash
# Run all updates with ddev prefix
bash drupal-update.sh -t all -p ddev

# Run updates excluding modules with docker-compose
bash drupal-update.sh -e pathauto,redirect -p "docker-compose exec web"
```

The script will execute composer commands like:
- `ddev composer outdated "drupal/*"`
- `ddev composer update drupal/core-*`
- `ddev composer require module_name:version`
