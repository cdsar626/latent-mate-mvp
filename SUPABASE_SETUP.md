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
3.  Copy the connection string. It will look like this:
    ```
    postgresql://postgres.xxxx:[YOUR-PASSWORD]@aws-0-us-east-1.pooler.supabase.com:6543/postgres
    ```
4.  Replace `[YOUR-PASSWORD]` with the password you created in Step 1.

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

### "Network is unreachable" Error

If you see `error: error communicating with database: Network is unreachable`, it usually means your network cannot connect to the Supabase **IPv6** address or the **Transaction Pooler** (port 6543).

**Fix 1: Use the IPv4 (Direct) Connection**
1.  Go to **Project Settings** -> **Database**.
2.  Uncheck "Use connection pooling" (just to see the direct URI, or look for "Direct connection").
3.  Copy the URI which usually has port **5432** and might look like `db.ref.supabase.co`.
4.  Update your `backend/.env` file with this string.

**Fix 2: Change Port**
Try changing the port in your connection string from `6543` to `5432`.

### "Certificate Error"
If you get SSL/TLS errors, ensure you have `openssl` installed on your system (`sudo apt install libssl-dev` on Linux). The project is configured to use `native-tls` which relies on your OS certificate store.
