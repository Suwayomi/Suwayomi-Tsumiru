// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';

/// A bottom-sheet that collects username + password for credential-based
/// tracker login (i.e. trackers where [tracker.authUrl] is null).
///
/// Calls [onSubmit] with the entered (username, password) pair.
class TrackerCredentialsSheet extends StatefulWidget {
  const TrackerCredentialsSheet({
    super.key,
    required this.trackerName,
    required this.onSubmit,
  });

  final String trackerName;
  final void Function(String username, String password) onSubmit;

  @override
  State<TrackerCredentialsSheet> createState() =>
      _TrackerCredentialsSheetState();
}

class _TrackerCredentialsSheetState extends State<TrackerCredentialsSheet> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.trackerName,
            style: context.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: l10n.userName,
            ),
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: l10n.password,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            child: Text(l10n.logIn),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _submit() {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      return;
    }
    widget.onSubmit(
      _usernameController.text.trim(),
      _passwordController.text,
    );
  }
}
