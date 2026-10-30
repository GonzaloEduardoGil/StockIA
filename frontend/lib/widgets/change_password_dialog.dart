import 'package:flutter/material.dart';

import '../data/inventory_api.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({required this.api, super.key});
  final InventoryApi api;
  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false, _uncertain = false;
  String? _error;
  late final String? _token;

  @override
  void initState() {
    super.initState();
    _token = widget.api.session.value?.token;
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _uncertain || !_form.currentState!.validate()) return;
    if (widget.api.session.value?.token != _token) {
      setState(() {
        _error = 'La sesión cambió. Cerrá este formulario y volvé a abrirlo.';
        _uncertain = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.changeOwnPassword(
        _current.text,
        _next.text,
        _confirmation.text,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Contraseña actualizada. Ingresá con la nueva contraseña.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiFailure
            ? error.message
            : 'No se pudo confirmar el cambio. Volvé a ingresar.';
        _uncertain = error is! ApiFailure || error.mayHaveSaved;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _returnToLogin() {
    if (widget.api.session.value?.token == _token) {
      widget.api.session.value = null;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Cambiar mi contraseña'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const Key('own-current-password'),
                  controller: _current,
                  enabled: !_busy && !_uncertain,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 1024,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña actual',
                    counterText: '',
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Ingresá la contraseña actual.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('own-new-password'),
                  controller: _next,
                  enabled: !_busy && !_uncertain,
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
                      : v == _current.text
                      ? 'La nueva contraseña debe ser distinta.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('own-confirmation'),
                  controller: _confirmation,
                  enabled: !_busy && !_uncertain,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 1024,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    counterText: '',
                  ),
                  validator: (v) =>
                      v != _next.text ? 'Las contraseñas no coinciden.' : null,
                ),
                const SizedBox(height: 16),
                const Text('Se cerrarán todas tus sesiones.'),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: _uncertain
          ? [
              TextButton(
                onPressed: _returnToLogin,
                child: const Text('Volver a ingresar'),
              ),
            ]
          : [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Guardando…' : 'Cambiar contraseña'),
              ),
            ],
    ),
  );
}
