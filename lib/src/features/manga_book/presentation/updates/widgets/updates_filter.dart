// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import 'updates_filter_content.dart';

class UpdatesFilterSheet extends StatelessWidget {
  const UpdatesFilterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      animationDuration: context.reduceMotion
          ? Duration.zero
          : kTabScrollDuration,
      child: _UpdatesFilterBody(),
    );
  }
}

class _UpdatesFilterBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final filterTab = Tab(text: context.l10n.filter);
    final displayTab = Tab(text: context.l10n.display);
    final tabs = <Widget>[
      ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [UpdatesFilterHeader(), UpdatesFilterSegments()],
      ),
      ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [UpdatesGroupingSegment()],
      ),
    ];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            tabAlignment: TabAlignment.fill,
            tabs: [filterTab, displayTab],
          ),
          Flexible(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final content = ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: tabs[controller.index],
                );
                if (context.reduceMotion) return content;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: content,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
