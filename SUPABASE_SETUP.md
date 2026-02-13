# Supabase Setup Guide for LatentMate

LatentMate's backend is configured to use a PostgreSQL database, making it fully compatible with Supabase.

## Environment Configuration

To run the application, you must set up the following configuration variables.

### Backend (`backend/.env`)

Create a file named `.env` in the `backend/` directory with the following content:

```env
DATABASE_URL=postgresql://postgres.xxxx:[YOUR-PASSWORD]@aws-0-us-east-1.pooler.supabase.com:5432/postgres
```

*   **DATABASE_URL:** Your Supabase PostgreSQL Connection URI.
    *   **Important:** Use port **5432** (Session Mode). Do NOT use port 6543 (Transaction Mode) because the backend uses prepared statements which are incompatible with transaction pooling.
    *   Get this from **Project Settings > Database > Connection string > URI** (Uncheck "Use connection pooling").

### Frontend (`frontend/lib/supabase_config.dart`)

This file is pre-generated but you should verify it contains your actual Supabase project keys.

```dart
class SupabaseConfig {
  static const String url = 'https://your-project-id.supabase.co';
  static const String anonKey = 'your-anon-key';
}
```

*   **url:** Your Supabase Project URL.
*   **anonKey:** Your Supabase Project `anon` (public) API Key.
*   Get these from **Project Settings > API**.

---

## Prerequisites

1.  **Supabase Account:** Sign up at [supabase.com](https://supabase.com).
2.  **Rust Toolchain:** Ensure you have Rust installed.
3.  **SQLX CLI:** Install the SQLX command line tool:
    ```bash
    cargo install sqlx-cli --no-default-features --features native-tls,postgres
    ```

## Step-by-Step Setup

1.  **Create Project:** Create a new project on Supabase.
2.  **Get Credentials:** Gather your URL, Anon Key, and Database Connection String as described above.
3.  **Configure Backend:** Create the `backend/.env` file.
4.  **Configure Frontend:** Update `frontend/lib/supabase_config.dart` with your keys.
5.  **Run Migrations:**
    ```bash
    cd backend
    sqlx migrate run
    ```
6.  **Run Backend:**
    ```bash
    cargo run
    ```
7.  **Run Frontend:**
    ```bash
    cd frontend
    flutter run
    ```

## Troubleshooting

### "prepared statement ... already exists" (Error 42P05)
**Fix:** Change the port in your `DATABASE_URL` from `6543` to **5432**.

### "Network is unreachable" Error
**Fix:** Use the IPv4 (Direct) Connection string. In Supabase Database settings, uncheck "Use connection pooling" to see the direct connection string (usually port 5432).

### "Email not confirmed" on Login
**Fix:** Supabase requires email verification by default.
1.  Check your inbox for the confirmation link after signing up.
2.  Or, disable "Confirm email" in Supabase Dashboard > Authentication > Providers > Email (Not recommended for production).
