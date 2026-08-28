import asyncio
import os
import re
from sqlalchemy import text
from core.database import engine
from core.config import settings


def parse_sql_statements(sql_text: str):
    # Remove single line comments
    clean_lines = []
    for line in sql_text.splitlines():
        # Remove -- comment
        line_without_comment = re.sub(r"--.*$", "", line)
        clean_lines.append(line_without_comment)
    clean_sql = "\n".join(clean_lines)
    # Split by semicolon
    raw_statements = clean_sql.split(";")
    return [s.strip() for s in raw_statements if s.strip()]


async def apply_schema():
    print(f"Connecting to database at: {settings.DATABASE_URL.split('@')[-1]}")
    
    schema_file_path = os.path.join(os.path.dirname(__file__), "schema.sql")
    with open(schema_file_path, "r", encoding="utf-8") as f:
        ddl_sql = f.read()

    statements = parse_sql_statements(ddl_sql)

    async with engine.begin() as conn:
        print(f"Applying {len(statements)} schema DDL statements from schema.sql...")
        for i, stmt in enumerate(statements, 1):
            print(f"  [{i}/{len(statements)}] Executing: {stmt.splitlines()[0][:60]}...")
            await conn.execute(text(stmt))
        print("All DDL statements executed successfully.")

    # Verification phase
    async with engine.connect() as conn:
        print("\n--- Verifying Tables in Database ---")
        tables_res = await conn.execute(
            text("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                ORDER BY table_name;
            """)
        )
        tables = [row[0] for row in tables_res.fetchall()]
        for t in tables:
            print(f"  ✓ Table: {t}")

        print("\n--- Verifying Indexes in Database ---")
        indexes_res = await conn.execute(
            text("""
                SELECT tablename, indexname, indexdef 
                FROM pg_indexes 
                WHERE schemaname = 'public' 
                ORDER BY tablename, indexname;
            """)
        )
        indexes = indexes_res.fetchall()
        for idx in indexes:
            print(f"  ✓ Index on '{idx[0]}': {idx[1]}")
            print(f"      Def: {idx[2]}")

        expected_indexes = [
            "idx_vault_user_sync",
            "idx_users_email",
            "idx_refresh_tokens_lookup",
            "idx_audit_logs_user",
        ]
        found_index_names = {idx[1] for idx in indexes}
        print("\n--- Checking Expected Critical Indexes ---")
        for expected in expected_indexes:
            if expected in found_index_names:
                print(f"  ✓ Found critical index: {expected}")
            else:
                print(f"  ❌ Missing expected index: {expected}")

    await engine.dispose()
    print("\nSchema application and verification completed successfully.")


if __name__ == "__main__":
    asyncio.run(apply_schema())
