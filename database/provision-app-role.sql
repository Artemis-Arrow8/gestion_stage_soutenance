-- Ce script idempotent crée le rôle applicatif et prépare une base déjà migrée.
-- Les identifiants sont lus depuis l'environnement et cités par psql avant usage.
\getenv app_user DB_USER
\getenv app_password DB_PASSWORD
\getenv admin_password POSTGRES_PASSWORD

-- Refuser une configuration où le compte applicatif serait l'administrateur.
SELECT :'app_user' <> current_user AS app_role_is_separate \gset
\if :app_role_is_separate
\else
\echo 'Erreur : DB_USER doit être distinct de POSTGRES_USER.'
\quit 3
\endif

-- Le secret de connexion de l'application ne doit pas être celui de l'admin.
SELECT :'app_password' <> :'admin_password' AS app_password_is_separate \gset
\if :app_password_is_separate
\else
\echo 'Erreur : DB_PASSWORD doit être distinct de POSTGRES_PASSWORD.'
\quit 3
\endif

-- Refuser un secret administrateur faible avant d'ouvrir l'accès à la base.
SELECT length(:'admin_password') >= 32
    AND :'admin_password' !~ '^(replace-with-|dev-only-|changeme|change-me|your_)'
    AS admin_password_is_strong \gset
\if :admin_password_is_strong
\else
\echo 'Erreur : POSTGRES_PASSWORD doit être un secret personnalisé d’au moins 32 caractères.'
\quit 3
\endif

-- Réduire les attributs ou privilèges hérités d'un rôle préexistant.
SELECT format(
    'CREATE ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT',
    :'app_user',
    :'app_password'
)
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'app_user'
) \gexec

SELECT format(
    'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT',
    :'app_user',
    :'app_password'
) \gexec

SELECT format('REVOKE %I FROM %I', parent.rolname, app.rolname)
FROM pg_auth_members AS membership
JOIN pg_roles AS parent ON parent.oid = membership.roleid
JOIN pg_roles AS app ON app.oid = membership.member
WHERE app.rolname = :'app_user' \gexec

-- Accorder uniquement l'accès à la base et au schéma applicatifs.
SELECT format(
    'GRANT CONNECT ON DATABASE %I TO %I',
    current_database(),
    :'app_user'
) \gexec
GRANT USAGE, CREATE ON SCHEMA public TO :"app_user";

-- Les migrations déjà appliquées sous le compte administrateur doivent rester
-- modifiables par Django ; le compte admin conserve la propriété de la base.
SELECT set_config('sgsus.application_role', :'app_user', false);
DO $$
DECLARE
    object RECORD;
    app_role NAME := current_setting('sgsus.application_role')::NAME;
BEGIN
    FOR object IN
        SELECT namespace.nspname, relation.relname, relation.relkind
        FROM pg_class AS relation
        JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = 'public'
          AND relation.relkind IN ('r', 'p', 'S', 'v', 'm')
          AND relation.relowner <> (
              SELECT oid FROM pg_roles WHERE rolname = app_role
          )
          -- PostgreSQL transfère les séquences serial/identity avec leur table.
          AND (
              relation.relkind <> 'S'
              OR NOT EXISTS (
                  SELECT 1
                  FROM pg_depend AS dependency
                  WHERE dependency.classid = 'pg_class'::regclass
                    AND dependency.objid = relation.oid
                    AND dependency.refclassid = 'pg_class'::regclass
                    AND dependency.deptype IN ('a', 'i')
              )
          )
    LOOP
        IF object.relkind = 'S' THEN
            EXECUTE format(
                'ALTER SEQUENCE %I.%I OWNER TO %I',
                object.nspname, object.relname, app_role
            );
        ELSIF object.relkind = 'v' THEN
            EXECUTE format(
                'ALTER VIEW %I.%I OWNER TO %I',
                object.nspname, object.relname, app_role
            );
        ELSIF object.relkind = 'm' THEN
            EXECUTE format(
                'ALTER MATERIALIZED VIEW %I.%I OWNER TO %I',
                object.nspname, object.relname, app_role
            );
        ELSE
            EXECUTE format(
                'ALTER TABLE %I.%I OWNER TO %I',
                object.nspname, object.relname, app_role
            );
        END IF;
    END LOOP;
END
$$;

-- Conserver les droits nécessaires si des objets non transférés sont présents.
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON ALL TABLES IN SCHEMA public TO :"app_user";
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA public TO :"app_user";
