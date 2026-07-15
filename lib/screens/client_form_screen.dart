import 'package:flutter/material.dart';
import '../models/client.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'auth/auth_widgets.dart';

/// Add a new client or edit an existing one. Returns `true` via [Navigator.pop]
/// when something changed, so the caller can refresh its list.
class ClientFormScreen extends StatefulWidget {
  final Client? client;
  const ClientFormScreen({super.key, this.client});

  bool get isEditing => client != null;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  late final _name = TextEditingController(text: widget.client?.name ?? '');
  late final _phone = TextEditingController(text: widget.client?.phone ?? '');
  late final _email = TextEditingController(text: widget.client?.email ?? '');
  late final _company =
      TextEditingController(text: widget.client?.company ?? '');
  late final _notes = TextEditingController(text: widget.client?.notes ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _company.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('Enter the client name.');
      return;
    }
    if (_phone.text.trim().isEmpty) {
      _toast('Enter the contact number.');
      return;
    }
    setState(() => _saving = true);
    try {
      final svc = SupabaseService.instance;
      if (widget.isEditing) {
        await svc.updateClient(
          id: widget.client!.id,
          name: name,
          phone: _text(_phone),
          email: _text(_email),
          company: _text(_company),
          notes: _notes.text.trim(),
        );
      } else {
        await svc.createClient(
          name: name,
          phone: _text(_phone),
          email: _text(_email),
          company: _text(_company),
          notes: _notes.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save: $e');
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete client?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Remove ${widget.client!.name} from your contacts? This can\'t be '
          'undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.instance.deleteClient(widget.client!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not delete: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.isEditing ? 'Edit client' : 'New client'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            AuthField(
              controller: _name,
              label: 'Full name *',
              hint: 'e.g. Anjali Mehta',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _phone,
              label: 'Contact number *',
              hint: '+91 98765 43210',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _email,
              label: 'Email',
              hint: 'client@email.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _company,
              label: 'Company / site',
              hint: 'e.g. Mehta Residence',
              icon: Icons.business_outlined,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 18),
            AuthField(
              controller: _notes,
              label: 'Notes',
              hint: 'Preferences, budget, follow-up date…',
              icon: Icons.notes_rounded,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              maxLines: 4,
            ),
            const SizedBox(height: 28),
            AuthButton(
              label: widget.isEditing ? 'Save changes' : 'Add client',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
