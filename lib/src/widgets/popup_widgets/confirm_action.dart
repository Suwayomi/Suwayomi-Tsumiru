import 'package:flutter/material.dart';

import '../../utils/motion/reduce_motion.dart';
import 'pop_button.dart';

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          const PopButton(),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
      animationStyle: context.motionStyle,
    ) ==
    true;
