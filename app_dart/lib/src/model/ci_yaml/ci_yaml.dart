// Copyright 2021 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:github/github.dart';

import '../proto/internal/scheduler.pb.dart' as pb;
import 'target.dart';

/// This is a wrapper class around S[pb.SchedulerConfig].
///
/// See //CI_YAML.md for high level documentation.
class CiYaml {
  /// Creates [CiYaml] from a [RepositorySlug], [branch], [pb.SchedulerConfig] and an optional [CiYaml] of tip of tree CiYaml.
  ///
  /// If [totConfig] is passed, the validation will verify no new targets have been added that may temporarily break the LUCI infrastructure (such as new prod or presubmit targets).
  CiYaml({
    required this.slug,
    required this.branch,
    required this.config,
    CiYaml? totConfig,
  }) {
    _validate(config, totSchedulerConfig: totConfig?.config);
  }

  /// The underlying protobuf that contains the raw data from .ci.yaml.
  pb.SchedulerConfig config;

  /// The [RepositorySlug] that [config] is from.
  final RepositorySlug slug;

  /// The git branch currently being scheduled against.
  final String branch;

  /// Gets all [Target] that run on presubmit for this config.
  List<Target> get presubmitTargets {
    final Iterable<Target> presubmitTargets =
        _targets.where((Target target) => target.value.presubmit && !target.value.bringup);

    final List<Target> enabledTargets = _filterEnabledTargets(presubmitTargets);
    if (enabledTargets.isEmpty) {
      throw Exception('$branch is not enabled for this .ci.yaml.\nAdd it to run tests against this PR.');
    }
    return enabledTargets;
  }

  /// Gets all [Target] that run on postsubmit for this config.
  List<Target> get postsubmitTargets {
    final Iterable<Target> postsubmitTargets = _targets.where((Target target) => target.value.postsubmit);

    return _filterEnabledTargets(postsubmitTargets);
  }

  /// Filters [targets] to those that should be started immediately.
  ///
  /// Targets with a dependency are triggered when there dependency pushes a notification that it has finished.
  /// This shouldn't be confused for targets that have the property named dependency, which is used by the
  /// flutter_deps recipe module on LUCI.
  List<Target> getInitialTargets(List<Target> targets) {
    return targets.where((Target target) => target.value.dependencies.isEmpty).toList();
  }

  Iterable<Target> get _targets => config.targets.map((pb.Target target) => Target(
        schedulerConfig: config,
        value: target,
        slug: slug,
      ));

  /// Filter [targets] to only those that are expected to run for [branch].
  ///
  /// A [Target] is expected to run if:
  ///   1. [Target.enabledBranches] exists and matches [branch].
  ///   2. Otherwise, [config.enabledBranches] matches [branch].
  List<Target> _filterEnabledTargets(Iterable<Target> targets) {
    final List<Target> filteredTargets = <Target>[];

    // 1. Add targets with local definition
    final Iterable<Target> overrideBranchTargets =
        targets.where((Target target) => target.value.enabledBranches.isNotEmpty);
    final Iterable<Target> enabledTargets = overrideBranchTargets
        .where((Target target) => enabledBranchesMatchesCurrentBranch(target.value.enabledBranches, branch));
    filteredTargets.addAll(enabledTargets);

    // 2. Add targets with global definition (this is the majority of targets)
    if (enabledBranchesMatchesCurrentBranch(config.enabledBranches, branch)) {
      final Iterable<Target> defaultBranchTargets =
          targets.where((Target target) => target.value.enabledBranches.isEmpty);
      filteredTargets.addAll(defaultBranchTargets);
    }

    return filteredTargets;
  }

  /// Whether any of the possible [RegExp] in [enabledBranches] match [branch].
  static bool enabledBranchesMatchesCurrentBranch(List<String> enabledBranches, String branch) {
    final List<String> regexes = <String>[];
    for (String enabledBranch in enabledBranches) {
      // Prefix with start of line and suffix with end of line
      regexes.add('^$enabledBranch\$');
    }
    final String rawRegexp = regexes.join('|');
    final RegExp regexp = RegExp(rawRegexp);

    return regexp.hasMatch(branch);
  }

  /// Validates [pb.SchedulerConfig] extracted from [CiYaml] files.
  ///
  /// A [pb.SchedulerConfig] file is considered good if:
  ///   1. It has at least one [pb.Target] in [pb.SchedulerConfig.targets]
  ///   2. It has at least one [branch] in [pb.SchedulerConfig.enabledBranches]
  ///   3. If a second [pb.SchedulerConfig] is passed in,
  ///   we compare the current list of [pb.Target] inside the current [pb.SchedulerConfig], i.e., [schedulerConfig],
  ///   with the list of [pb.Target] from tip of the tree [pb.SchedulerConfig], i.e., [totSchedulerConfig].
  ///   If a [pb.Target] is indentified as a new target compared to target list from tip of the tree, The new target
  ///   should have its field [pb.Target.bringup] set to true.
  ///   4. no cycle should exist in the dependency graph, as tracked by map [targetGraph]
  ///   5. [pb.Target] should not depend on self
  ///   6. [pb.Target] cannot have more than 1 dependency
  ///   7. [pb.Target] should depend on target that already exist in depedency graph, and already recorded in map [targetGraph]
  void _validate(pb.SchedulerConfig schedulerConfig, {pb.SchedulerConfig? totSchedulerConfig}) {
    if (schedulerConfig.targets.isEmpty) {
      throw const FormatException('Scheduler config must have at least 1 target');
    }

    if (schedulerConfig.enabledBranches.isEmpty) {
      throw const FormatException('Scheduler config must have at least 1 enabled branch');
    }

    final Map<String, List<pb.Target>> targetGraph = <String, List<pb.Target>>{};
    final List<String> exceptions = <String>[];
    final Set<String> totTargets = <String>{};
    if (totSchedulerConfig != null) {
      for (pb.Target target in totSchedulerConfig.targets) {
        totTargets.add(target.name);
      }
    }
    // Construct [targetGraph]. With a one scan approach, cycles in the graph
    // cannot exist as it only works forward.
    for (final pb.Target target in schedulerConfig.targets) {
      if (targetGraph.containsKey(target.name)) {
        exceptions.add('ERROR: ${target.name} already exists in graph');
      } else {
        // a new build without "bringup: true"
        // link to wiki - https://github.com/flutter/flutter/wiki/Reducing-Test-Flakiness#adding-a-new-devicelab-test
        if (totTargets.isNotEmpty && !totTargets.contains(target.name) && target.bringup != true) {
          exceptions.add(
              'ERROR: ${target.name} is a new builder added. it needs to be marked bringup: true\nIf ci.yaml wasn\'t changed, try `git fetch upstream && git merge upstream/master`');
          continue;
        }
        targetGraph[target.name] = <pb.Target>[];
        // Add edges
        if (target.dependencies.isNotEmpty) {
          if (target.dependencies.length != 1) {
            exceptions
                .add('ERROR: ${target.name} has multiple dependencies which is not supported. Use only one dependency');
          } else {
            if (target.dependencies.first == target.name) {
              exceptions.add('ERROR: ${target.name} cannot depend on itself');
            } else if (targetGraph.containsKey(target.dependencies.first)) {
              targetGraph[target.dependencies.first]!.add(target);
            } else {
              exceptions.add('ERROR: ${target.name} depends on ${target.dependencies.first} which does not exist');
            }
          }
        }
      }
    }
    _checkExceptions(exceptions);
  }

  void _checkExceptions(List<String> exceptions) {
    if (exceptions.isNotEmpty) {
      final String fullException = exceptions.reduce((String exception, _) => exception + '\n');
      throw FormatException(fullException);
    }
  }
}
