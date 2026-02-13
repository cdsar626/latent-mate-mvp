-- Add status column to matches table for suppression/archive/delete workflow
ALTER TABLE matches ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
