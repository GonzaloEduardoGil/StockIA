-- Preparación idempotente. No elimina cuentas ni altera contraseñas o roles.
ALTER TABLE "USUARIO" ADD COLUMN IF NOT EXISTS activo BOOLEAN NOT NULL DEFAULT TRUE;
CREATE UNIQUE INDEX IF NOT EXISTS stockia_usuario_email_ci ON "USUARIO" (lower(btrim(email)));
