enum InventoryAction {
  entry('Registrar entrada'),
  adjustment('Registrar ajuste'),
  edit('Editar producto'),
  minimum('Configurar stock mínimo'),
  deactivate('Dar de baja');

  const InventoryAction(this.label);
  final String label;
}
