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

-   **Connection Refused/Timeout:** Ensure you are using the "Transaction" (port 6543) or "Session" (port 5432) connection mode correctly. Supabase recommends port 6543 for serverless environments, but standard 5432 works for long-running servers like this Rust backend.
-   **SSL Errors:** If you encounter SSL errors, ensure your system has valid CA certificates. The backend uses `runtime-tokio-rustls` which relies on the system's trust store.
