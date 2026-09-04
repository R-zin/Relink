"""Alembic environment. URL comes from DATABASE_URL (env var / backend/.env);
the asyncpg driver is swapped for psycopg2 since migrations run synchronously.
"""

import os
from logging.config import fileConfig

from alembic import context
from dotenv import load_dotenv
from sqlalchemy import engine_from_config, pool

load_dotenv()  # backend/.env (alembic runs from the backend/ directory)

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

url = os.environ.get("ALEMBIC_DATABASE_URL") or os.environ.get("DATABASE_URL")
if not url:
    raise RuntimeError("Set DATABASE_URL (or ALEMBIC_DATABASE_URL) before running migrations")
# Migrations run on a sync engine regardless of the app's async driver.
url = url.replace("+asyncpg", "+psycopg2").replace("postgresql+psycopg2://", "postgresql+psycopg2://")
config.set_main_option("sqlalchemy.url", url)


def run_migrations_offline() -> None:
    context.configure(url=url, target_metadata=None, literal_binds=True, dialect_opts={"paramstyle": "named"})
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=None)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
