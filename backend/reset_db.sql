-- Danger: This script drops all data and tables.
-- Run this in the Supabase SQL Editor to reset your database state if migrations get stuck.

DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS matches;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS _sqlx_migrations;
