/// Admin screen to manage user accounts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/shell.dart';
import 'user_models.dart';

/// Lists users; lets an admin add, disable, reset and delete them.
class UsersScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      setState(() => _error = null);
      ref.invalidate(usersProvider);
    } on Object catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _toggle(AdminUser u) => _run(() async {
        await ref
            .read(dioProvider)
            .patch<void>('/users/${u.id}', data: {'disabled': !u.disabled});
      });

  Future<void> _add() async {
    final data = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const _AddUserDialog(),
    );
    if (data == null) return;
    await _run(() async {
      await ref.read(dioProvider).post<void>('/users', data: data);
    });
  }

  Future<void> _reset(AdminUser u) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _ResetPasswordDialog(username: u.username),
    );
    if (password == null) return;
    await _run(() async {
      await ref
          .read(dioProvider)
          .patch<void>('/users/${u.id}', data: {'password': password});
    });
  }

  Future<void> _delete(AdminUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('delete-dialog'),
        title: Text('Delete ${u.username}?'),
        content: const Text(
            'All data of this user is deleted. You cannot undo this.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(dioProvider).delete<void>('/users/${u.id}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    return AppShell(
      title: 'Users',
      backTo: '/admin',
      body: Column(
        children: [
          if (_error != null)
            ErrorBanner(
              message: _error!,
              onDismiss: () => setState(() => _error = null),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('add-user'),
                onPressed: _add,
                icon: const Icon(Icons.person_add),
                label: const Text('Add user'),
              ),
            ),
          ),
          Expanded(
            child: users.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(apiErrorMessage(e)),
                  TextButton(
                    key: const Key('reload-users'),
                    onPressed: () => ref.invalidate(usersProvider),
                    child: const Text('Retry'),
                  ),
                ]),
              ),
              data: (list) => ListView(
                children: [
                  for (final u in list)
                    ListTile(
                      key: Key('user-${u.id}'),
                      title: Text(u.username),
                      subtitle: Text([
                        if (u.isAdmin) 'Admin',
                        if (u.disabled) 'Disabled',
                        u.timezone,
                      ].join(' - ')),
                      trailing: Wrap(spacing: 4, children: [
                        TextButton(
                          key: Key('toggle-${u.id}'),
                          onPressed: () => _toggle(u),
                          child: Text(u.disabled ? 'Enable' : 'Disable'),
                        ),
                        TextButton(
                          key: Key('reset-${u.id}'),
                          onPressed: () => _reset(u),
                          child: const Text('Reset password'),
                        ),
                        IconButton(
                          key: Key('delete-${u.id}'),
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(u),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _name = TextEditingController();
  final _pass = TextEditingController();
  bool _admin = false;

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const Key('new-username'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        TextField(
          key: const Key('new-password'),
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        SwitchListTile(
          key: const Key('new-admin'),
          title: const Text('Administrator'),
          value: _admin,
          onChanged: (v) => setState(() => _admin = v),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('new-save'),
          onPressed: () => Navigator.of(context).pop(<String, Object?>{
            'username': _name.text.trim(),
            'password': _pass.text,
            'is_admin': _admin,
          }),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.username});

  final String username;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _pass = TextEditingController();

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset password for ${widget.username}'),
      content: TextField(
        key: const Key('reset-password'),
        controller: _pass,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'New password'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('reset-save'),
          onPressed: () => Navigator.of(context).pop(_pass.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
