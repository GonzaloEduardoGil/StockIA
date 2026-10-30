import 'package:flutter/material.dart';

import '../app.dart';
import '../data/inventory_api.dart';
import '../models/managed_user.dart';
import '../widgets/user_access_dialog.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({required this.api, this.onBusyChanged, super.key});
  final InventoryApi api;
  final ValueChanged<bool>? onBusyChanged;
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  List<ManagedUser> _users = [];
  int _loadRequest = 0;
  int _revision = 0;
  final _confirmedUsers = <int, ({int revision, ManagedUser user})>{};
  String _role = 'Vendedor';
  ManagedUser? _editing;
  bool _loading = true, _saving = false, _creating = false, _uncertain = false;
  String? _loadError, _error, _success, _actionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    final revision = _revision;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final users = await widget.api.loadUsers();
      if (!mounted || request != _loadRequest) return;
      setState(() {
        // Una lectura anterior al alta puede aportar otras cuentas, pero no
        // borrar las identidades confirmadas desde que empezó esa lectura.
        _users =
            {
              for (final user in users) user.id: user,
              for (final confirmed in _confirmedUsers.values)
                if (confirmed.revision > revision)
                  confirmed.user.id: confirmed.user,
            }.values.toList()..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
        _confirmedUsers.removeWhere(
          (_, confirmed) => confirmed.revision <= revision,
        );
        if (revision == _revision) _uncertain = false;
      });
    } catch (error) {
      if (!mounted || request != _loadRequest || revision != _revision) return;
      setState(
        () => _loadError = error is ApiFailure
            ? error.message
            : 'No se pudieron cargar los usuarios.',
      );
    } finally {
      if (mounted && request == _loadRequest) {
        setState(() => _loading = false);
      }
    }
  }

  void _rememberUser(ManagedUser user) {
    _confirmedUsers[user.id] = (revision: ++_revision, user: user);
    _users =
        {
          for (final existing in _users) existing.id: existing,
          user.id: user,
        }.values.toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    _loading = false;
    _loadError = null;
  }

  Future<void> _manage(ManagedUser user, String action) async {
    if (_saving || _uncertain) return;
    ({String value, String confirmation})? input;
    if (action == 'estado') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(user.active ? 'Desactivar usuario' : 'Reactivar usuario'),
          content: Text(
            '${user.name}\n${user.email}\n\n${user.active ? 'Se cerrarán sus sesiones abiertas.' : 'Podrá volver a ingresar con su email y contraseña.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(user.active ? 'Desactivar' : 'Reactivar'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    } else {
      input = await showDialog<({String value, String confirmation})>(
        context: context,
        builder: (_) =>
            UserAccessDialog(user: user, password: action == 'password'),
      );
      if (input == null || !mounted) return;
    }
    if (_saving || _uncertain) return;
    setState(() {
      _saving = true;
      _actionError = null;
      _success = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      final updated = action == 'estado'
          ? await widget.api.changeUserStatus(user.id, !user.active)
          : action == 'rol'
          ? await widget.api.changeUserRole(user.id, input!.value)
          : await widget.api.resetUserPassword(
              user.id,
              input!.value,
              input.confirmation,
            );
      if (!mounted) return;
      setState(() {
        _rememberUser(updated);
        if (_editing?.id == updated.id) _editing = updated;
        _success = action == 'estado'
            ? (updated.active ? 'Usuario reactivado.' : 'Usuario desactivado.')
            : action == 'rol'
            ? 'Rol actualizado.'
            : 'Contraseña restablecida.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _actionError = error is ApiFailure
            ? error.message
            : 'No se pudo confirmar la operación. Actualizá el listado.';
        _uncertain = error is! ApiFailure || error.mayHaveSaved;
        if (_uncertain) ++_revision;
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _uncertain || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _actionError = null;
      _success = null;
    });
    widget.onBusyChanged?.call(true);
    final editing = _editing;
    try {
      final user = editing != null
          ? await widget.api.editUser(
              editing.id,
              name: _name.text.trim(),
              email: _email.text.trim(),
            )
          : await widget.api.createUser(
              name: _name.text.trim(),
              email: _email.text.trim(),
              role: _role,
              password: _password.text,
              confirmation: _confirmation.text,
            );
      if (!mounted) return;
      setState(() {
        _rememberUser(user);
        _creating = false;
        _editing = null;
        _success =
            '${editing == null ? 'Usuario creado' : 'Usuario actualizado'}: ${user.name} · ${user.role}';
        _name.clear();
        _email.clear();
        _password.clear();
        _confirmation.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiFailure
            ? error.message
            : 'No se pudo confirmar la operación. Actualizá el listado.';
        _uncertain = error is! ApiFailure || error.mayHaveSaved;
        // Sólo una lectura posterior a un resultado incierto permite reintentar.
        if (_uncertain) ++_revision;
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  void _cancel() {
    _password.clear();
    _confirmation.clear();
    _name.clear();
    _email.clear();
    setState(() {
      _creating = false;
      _editing = null;
      _error = null;
    });
  }

  void _edit(ManagedUser user) {
    if (_saving || _uncertain) return;
    _form.currentState?.reset();
    _name.text = user.name;
    _email.text = user.email;
    _password.clear();
    _confirmation.clear();
    setState(() {
      _editing = user;
      _creating = true;
      _error = null;
      _success = null;
    });
  }

  Widget _editButton(ManagedUser user) => OutlinedButton(
    key: ValueKey('edit-user-${user.id}'),
    onPressed: _saving || _uncertain ? null : () => _edit(user),
    child: const Text('Editar'),
  );

  Widget _actions(ManagedUser user) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _editButton(user),
      const SizedBox(width: 8),
      PopupMenuButton<String>(
        key: ValueKey('user-access-${user.id}'),
        enabled: !_saving && !_uncertain,
        tooltip: 'Gestionar acceso',
        onSelected: (action) => _manage(user, action),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'estado',
            child: Text(user.active ? 'Desactivar' : 'Reactivar'),
          ),
          const PopupMenuItem(
            value: 'password',
            child: Text('Restablecer contraseña'),
          ),
          const PopupMenuItem(value: 'rol', child: Text('Cambiar rol')),
        ],
        icon: const Icon(Icons.more_vert),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.api.session.value?.role != 'Administrador') {
      return const Center(
        child: Text('Solo el administrador puede gestionar usuarios.'),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 650 ? 20 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Administración / Usuarios',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Usuarios',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              if (!_creating)
                FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _editing = null;
                          _role = 'Vendedor';
                          _creating = true;
                          _success = null;
                          _error = null;
                        }),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Nuevo usuario'),
                ),
              OutlinedButton.icon(
                onPressed: _saving || _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar listado'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_success != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _success!,
                style: const TextStyle(color: Color(0xFF237047)),
              ),
            ),
          if (_actionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _actionError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (_creating) _creationForm(),
          if (_loading)
            const LinearProgressIndicator()
          else if (_loadError != null)
            Text(_loadError!, style: const TextStyle(color: Colors.red))
          else if (_users.isEmpty)
            const Text('Todavía no hay encargados ni vendedores registrados.')
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: LayoutBuilder(
                builder: (context, box) => box.maxWidth < 650
                    ? Column(
                        children: _users
                            .map(
                              (u) => Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(u.email),
                                    Text(
                                      u.role,
                                      style: const TextStyle(color: muted),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(u.active ? 'Activo' : 'Inactivo'),
                                    _actions(u),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Nombre')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Rol')),
                            DataColumn(label: Text('Estado')),
                            DataColumn(label: Text('Acciones')),
                          ],
                          rows: _users
                              .map(
                                (u) => DataRow(
                                  cells: [
                                    DataCell(Text(u.name)),
                                    DataCell(Text(u.email)),
                                    DataCell(Text(u.role)),
                                    DataCell(
                                      Text(u.active ? 'Activo' : 'Inactivo'),
                                    ),
                                    DataCell(_actions(u)),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _creationForm() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 24),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editing == null ? 'Nuevo usuario' : 'Editar usuario',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth < 650
                  ? box.maxWidth
                  : (box.maxWidth - 16) / 2;
              Widget field(Widget child) =>
                  SizedBox(width: width, child: child);
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  field(
                    TextFormField(
                      key: const Key('user-name'),
                      controller: _name,
                      enabled: !_saving,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        counterText: '',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Ingresá el nombre.'
                          : null,
                    ),
                  ),
                  field(
                    TextFormField(
                      key: const Key('user-email'),
                      controller: _email,
                      enabled: !_saving,
                      maxLength: 255,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        counterText: '',
                      ),
                      validator: (v) {
                        final email = (v ?? '').trim().toLowerCase();
                        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(email)) {
                          return 'Ingresá un email válido.';
                        }
                        if (_users.any(
                          (u) =>
                              u.id != _editing?.id &&
                              u.email.toLowerCase() == email,
                        )) {
                          return 'Ya existe un usuario con ese email.';
                        }
                        return null;
                      },
                    ),
                  ),
                  if (_editing != null)
                    field(
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Rol'),
                        child: Text(_editing!.role),
                      ),
                    )
                  else
                    field(
                      DropdownButtonFormField<String>(
                        key: const Key('user-role'),
                        initialValue: _role,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Rol'),
                        items: ['Encargado de stock', 'Vendedor']
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _role = v!),
                      ),
                    ),
                  field(const SizedBox.shrink()),
                  if (_editing == null)
                    field(
                      TextFormField(
                        key: const Key('user-password'),
                        controller: _password,
                        enabled: !_saving,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        maxLength: 1024,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña',
                          helperText: 'Mínimo 8 caracteres',
                          counterText: '',
                        ),
                        validator: (v) =>
                            v == null || v.length < 8 || v.trim().isEmpty
                            ? 'Ingresá al menos 8 caracteres.'
                            : null,
                      ),
                    ),
                  if (_editing == null)
                    field(
                      TextFormField(
                        key: const Key('user-confirmation'),
                        controller: _confirmation,
                        enabled: !_saving,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        maxLength: 1024,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          counterText: '',
                        ),
                        validator: (v) => v != _password.text
                            ? 'Las contraseñas no coinciden.'
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: _saving || _uncertain ? null : _save,
                child: Text(
                  _editing != null
                      ? (_saving ? 'Guardando…' : 'Guardar cambios')
                      : (_saving ? 'Creando…' : 'Crear usuario'),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _cancel,
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
