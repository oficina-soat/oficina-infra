CREATE USER oficina_os_user WITH PASSWORD 'oficina_os_password';
CREATE USER oficina_billing_user WITH PASSWORD 'oficina_billing_password';

CREATE DATABASE oficina_os OWNER oficina_os_user;
CREATE DATABASE oficina_billing OWNER oficina_billing_user;

REVOKE CONNECT ON DATABASE oficina_os FROM PUBLIC;
REVOKE CONNECT ON DATABASE oficina_billing FROM PUBLIC;
GRANT CONNECT ON DATABASE oficina_os TO oficina_os_user;
GRANT CONNECT ON DATABASE oficina_billing TO oficina_billing_user;

\connect oficina_os

GRANT ALL PRIVILEGES ON DATABASE oficina_os TO oficina_os_user;
GRANT ALL ON SCHEMA public TO oficina_os_user;
ALTER SCHEMA public OWNER TO oficina_os_user;

\connect oficina_billing

GRANT ALL PRIVILEGES ON DATABASE oficina_billing TO oficina_billing_user;
GRANT ALL ON SCHEMA public TO oficina_billing_user;
ALTER SCHEMA public OWNER TO oficina_billing_user;
