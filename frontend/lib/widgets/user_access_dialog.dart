import 'package:flutter/material.dart';

import '../models/managed_user.dart';

class UserAccessDialog extends StatefulWidget {
  const UserAccessDialog({
    required this.user,
    required this.password,
    super.key,
  });
  final ManagedUser user;
  final bool password;
  @override
  State<UserAccessDialog> createState() => _UserAccessDialogState();
}

class _UserAccessDialogState extends State<UserAccessDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late String _role;
  @override
  void initState() {
    super.initState();
    _role = widget.user.role;
  }

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, (
      value: widget.password ? _password.text : _role,
      confirmation: _confirmation.text,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.password ? 'Restablecer contraseña' : 'Cambiar rol'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.user.name}\n${widget.user.email}'),
              const SizedBox(height: 16),
              if (widget.password) ...[
                TextFormField(
                  key: const Key('reset-password'),
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 1024,
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña',
                    helperText: 'Mínimo 8 caracteres',
                    counterText: '',
                  ),
                  validator: (v) =>
                      v == null || v.length < 8 || v.trim().isEmpty
                      ? 'Ingresá al menos 8 caracteres.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reset-confirmation'),
                  controller: _confirmation,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 1024,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                    counterText: '',
                  ),
                  validator: (v) => v != _password.text
                      ? 'Las contraseñas no coinciden.'
                      : null,
                ),
              ] else
                DropdownButtonFormField<String>(
                  key: const Key('change-user-role'),
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: ['Encargado de stock', 'Vendedor']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setState(() => _role = v!),
                ),
              const SizedBox(height: 16),
              const Text('Se cerrarán las sesiones abiertas del usuario.'),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: !widget.password && _role == widget.user.role
            ? null
            : _submit,
        child: Text(widget.password ? 'Restablecer' : 'Guardar rol'),
      ),
    ],
  );
}
