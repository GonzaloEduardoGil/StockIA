-- Sesiones opacas: se guarda el hash del token, nunca el token entregado al cliente.
-- No altera las cuentas, roles ni contraseñas existentes.
CREATE TABLE IF NOT EXISTS "STOCKIA_SESION" (
    token_hash CHAR(64) PRIMARY KEY,
    "idUsuario" INTEGER NOT NULL REFERENCES "USUARIO" ("idUsuario") ON DELETE CASCADE,
    creado TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expira TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS stockia_sesion_usuario_idx ON "STOCKIA_SESION" ("idUsuario");
ALTER TABLE "STOCKIA_SESION" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "STOCKIA_SESION" FROM PUBLIC;
-- Las credenciales y roles se consultan exclusivamente desde el backend.
ALTER TABLE "USUARIO" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "USUARIO" FROM PUBLIC;
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON TABLE "STOCKIA_SESION" FROM anon;
        REVOKE ALL ON TABLE "USUARIO" FROM anon;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        REVOKE ALL ON TABLE "STOCKIA_SESION" FROM authenticated;
        REVOKE ALL ON TABLE "USUARIO" FROM authenticated;
    END IF;
END $$;
