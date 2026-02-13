# Supabase Setup Guide for LatentMate

LatentMate's backend is configured to use a PostgreSQL database, making it fully compatible with Supabase.

## Prerequisites

1.  **Supabase Account:** Sign up at [supabase.com](https://supabase.com).
2.  **Rust Toolchain:** Ensure you have Rust installed.
3.  **SQLX CLI:** Install the SQLX command line tool:
    ```bash
    cargo install sqlx-cli --no-default-features --features native-tls,postgres
    ```

## Step 1: Create a Project

1.  Log in to your Supabase dashboard.
2.  Click "New Project".
3.  Enter a Name (e.g., `LatentMate`) and a Database Password.
4.  Select a Region close to you.
5.  Click "Create new project".

## Step 2: Get Connection String

1.  Once the project is ready, go to **Project Settings** (cog icon) -> **Database**.
2.  Under **Connection string**, make sure **URI** is selected.
3.  **IMPORTANT:** Uncheck "Use connection pooling". You MUST use the **Session Mode** connection (Port **5432**) because the Rust backend (`sqlx`) uses prepared statements, which are incompatible with the Transaction Pooler (Port 6543).
4.  Copy the connection string. It will look like this:
    ```
    postgresql://postgres.xxxx:[YOUR-PASSWORD]@aws-0-us-east-1.pooler.supabase.com:5432/postgres
    ```
5.  Replace `[YOUR-PASSWORD]` with the password you created in Step 1.

## Step 3: Configure Backend

1.  Navigate to the `backend/` directory in your local project.
2.  Create or update the `.env` file:
    ```bash
    echo "DATABASE_URL=postgresql://postgres.xxxx:password@host:5432/postgres" > .env
    ```
    *(Paste your actual connection string here)*.

## Step 4: Run Migrations

Run the following command in the `backend/` directory to create the `users`, `matches`, and `messages` tables in your Supabase database:

```bash
sqlx migrate run
```

## Step 5: Run the Backend

Start the server:

```bash
cargo run
```

## Troubleshooting

### "prepared statement ... already exists" (Error 42P05)

If you see this error, you are likely connecting to port **6543** (Transaction Pooler). `sqlx` requires a direct session connection or a session-mode pooler.

**Fix:**
1.  Change the port in your `DATABASE_URL` from `6543` to **5432**.
2.  If you are stuck in a bad state (tables partially created or migration failed), you can reset the database by running the SQL in `backend/reset_db.sql` via the **Supabase SQL Editor** in your dashboard. Then run `sqlx migrate run` again.

### "Network is unreachable" Error

If you see `error: error communicating with database: Network is unreachable`, it usually means your network cannot connect to the Supabase **IPv6** address.

**Fix:**
Use the IPv4 (Direct) Connection string if available in Supabase settings (look for "Direct connection" or disable pooling). Ensure you are using port **5432**.

### "Certificate Error"
If you get SSL/TLS errors, ensure you have `openssl` installed on your system (`sudo apt install libssl-dev` on Linux). The project is configured to use `native-tls` which relies on your OS certificate store.
