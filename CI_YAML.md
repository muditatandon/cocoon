# Cocoon Scheduler

This Dart project contains logic for constructing infrastructure configs
to validate commits in the repositories owned by Flutter.

## ci.yaml

This is the config file in a repository used to tell Cocoon what tasks are used
to validate commits. It includes both the tasks used in presubmit and postsubmit.

In addition, it supports tasks from different infrastructures as long as cocoon
supports that `scheduler`. Only `luci` and `cocoon` are supported, but contributions
are welcome.

Example config:
```yaml
# /.ci.yaml

# Enabled branches is a list of regexes, with the assumption that these are full line matches.
# Internally, Cocoon prefixes these with $ and suffixes with ^ to enable matches.
enabled_branches:
  - main
  - flutter-\\d+\\.\\d+-candidate\\.\\d+

targets:
# A Target is an individual unit of work that is scheduled by Flutter infra
# Target's are composed of the following properties:
# name: A human readable string to uniquely identify this target.
# bringup: Whether this target is under active development and should not block the tree.
#          If true, will not run in presubmit and will not block postsubmit.
# scheduler: String identifying where this target is triggered.
#            Currently supports cocoon and luci.
# presubmit: Whether to run this target on presubmit (defaults to true).
# postsubmit: Whether to run this target on postsubmit (defaults to true).
# run_if: List of path regexes that can trigger this target on presubmit.
#         If none are passed, will always run in presubmit.
# enabled_branches: List of strings of branches this target can run on.
#                   This overrides the global enabled_branches.
# properties: A map of string, string. Values are parsed to their closest data model.
# postsubmit_properties: Properties that are only run on postsubmit.
#
# Minimal example:
# Linux analyze will run on all presubmit and in postsubmit.
 - name: Linux analyze
#
# Bringup example:
# Linux licenses will run on postsubmit, but it also passes the properties
# `analyze=true` to the builder. Since `bringup=true`, presubmit is not run,
# and postsubmit runs will not block the tree.
 - name: Linux licenses
   bringup: true
   properties:
     - analyze: license

#
# Tags example:
# This test will be categorized as host only framework test.
# Postsubmit runs will be passed "upload_metrics: true".
 - name: Linux analyze
   properties:
     tags: >-
       ["framework", "hostonly"]
   postsubmit_properties:
     - upload_metrics: "true"
```

## Adding new targets

All new targets should be added as `bringup: true` to ensure they do not block the tree.

Targets based on the LUCI or Cocoon schedulers will first need to be mirrored to flutter/infra
before they will be run. This propagation takes about 30 minutes, and will only run as non-blocking
in postsubmit.

The target will show runs in https://ci.chromium.org/p/flutter (under the repo). See
https://github.com/flutter/flutter/wiki/Adding-a-new-Test-Shard for up to date information
on the steps to promote your target to blocking.

For flutter/flutter, there's a GitHub bot that will
promote a test that has been passing for the past 50 runs.

### Test Ownership

**This only applies to flutter/flutter***

To prevent tests from rotting, all targets are required to have a clear owner. Add an
owner in [TESTOWNERS](https://github.com/flutter/flutter/blob/master/TESTOWNERS)

## Properties

Targets support specifying properties that can be passed throughout infrastructure. The
following are a list of keys that are reserved for special use.

**Properties is a Map<String, String> and any special values must be JSON encoded
(i.e. no trailing commas). Additionally, these strings must be compatible with YAML multiline strings**

**add_recipes_cq**: String boolean whether to add this target to flutter/recipes CQ. This ensures
changes to flutter/recipes pass on this target before landing.

**caches**: JSON representation of swarming caches the bot running the target should have.
Name is what flutter/recipes will refer to it as, and path is where it will be stored on the bot.

Path should be versioned to ensure bots do not incorrectly reuse the version. Paths originally not versioned
are legacy from when Flutter originally migrated to LUCI, and have not been updated since.

Example
```yaml
caches: >-
  [
    {"name": "openjdk", "path": "java11"}
  ]
```

**dependencies**: JSON list of objects with "dependency" and optionally "version".
The list of supported deps is in [flutter_deps recipe_module](https://cs.opensource.google/flutter/recipes/+/master:recipe_modules/flutter_deps/api.py)

Versions can be located in [CIPD](https://chrome-infra-packages.appspot.com/)

Example
``` yaml
dependencies: >-
  [
    {"dependency": "android_sdk"},
    {"dependency": "chrome_and_driver", "version": "latest"},
    {"dependency": "clang"},
    {"dependency": "goldctl"}
  ]
```

**tags**: JSON list of strings. These are currently only used in flutter/flutter to help
with TESTOWNERSHIP and test flakiness.

Example
```yaml
tags: >
  ["devicelab","hostonly"]
```

## Upgrading dependencies
1. Find the cipd ref to upgrade to
    - If this is a Flutter managed package, look up its docs on uploading a new version
    - For example, JDK is at https://chrome-infra-packages.appspot.com/p/flutter_internal/java/openjdk/linux-amd64
2. In `ci.yaml`, find a target that would be impacted by this change
    - Override the `version` specified in dependencies
      ```yaml
      - name: Linux Host Engine
        recipe: engine
        properties:
          build_host: "true"
          dependencies: >-
          [
              {"dependency": "open_jdk", "version": "11"}
          ]
          # Some dependencies are large, and stored in a cache for reuse
          # between runs. Ensure any paths are versioned correctly.
          caches: >-
          [
              {"name": "openjdk", "path": "java11"}
          ]
        timeout: 60
        scheduler: luci
    ```
    - Send PR, wait for the checks to go green (the change takes effect on presubmit)
3. If the check is red, add patches to get it green
4. Once the PR has landed, infrastructure may take 1 or 2 commits to apply the latest properties

## External Tests

Cocoon supports tests that are not owned by Flutter infrastructure. By default, these should not block the tree but act as FYI to the gardeners.

1. Contact flutter-infra@ with your request (go/flutter-infra-office-hours)
2. Add your system to SchedulerSystem (https://github.com/flutter/cocoon/blob/master/app_dart/lib/src/model/proto/internal/scheduler.proto)
3. Add your service account to https://github.com/flutter/cocoon/blob/master/app_dart/lib/src/request_handling/swarming_authentication.dart
4. Add a custom frontend icon - https://github.com/flutter/cocoon/blob/master/dashboard/lib/widgets/task_icon.dart
5. Add a custom log link - https://github.com/flutter/cocoon/blob/master/dashboard/lib/logic/qualified_task.dart
6. Wait for the next prod roll (every weekday)
7. Add a target to `.ci.yaml`
   ```yaml
   # .ci.yaml
   # Name is an arbitrary string that will show on the build dashboard
   - name: my_external_test_a
     # External tests should not block the tree
     bringup: true
     presubmit: false
     # Scheduler must match what was added to scheduler.proto (any unique name works)
     scheduler: my_external_location
   ```
8. Send updates to `https://flutter-dashboard.appspot.com/api/update-task-status` - https://github.com/flutter/cocoon/blob/master/app_dart/lib/src/request_handlers/update_task_status.dart
