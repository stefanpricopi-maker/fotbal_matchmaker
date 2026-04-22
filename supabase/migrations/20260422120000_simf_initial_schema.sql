-- SIMF — schema inițială (PostgreSQL / Supabase), aliniată la specification.md
-- Rulează din CLI: `supabase db push` sau lipește în SQL Editor din dashboard.

-- ---------------------------------------------------------------------------
-- Tipuri
-- ---------------------------------------------------------------------------

CREATE TYPE public.match_team AS ENUM ('A', 'B');

GRANT USAGE ON TYPE public.match_team TO postgres, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Tabele
-- ---------------------------------------------------------------------------

CREATE TABLE public.players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
  name text NOT NULL,
  mu double precision NOT NULL DEFAULT 25.0,
  sigma double precision NOT NULL DEFAULT 8.33,
  is_permanent_gk boolean NOT NULL DEFAULT false,
  matches_played integer NOT NULL DEFAULT 0,
  CONSTRAINT players_name_nonempty CHECK (char_length(trim(name)) > 0),
  CONSTRAINT players_mu_reasonable CHECK (mu >= 0 AND mu <= 100),
  CONSTRAINT players_sigma_positive CHECK (sigma > 0),
  CONSTRAINT players_matches_non_negative CHECK (matches_played >= 0)
);

CREATE TABLE public.matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
  created_at timestamptz NOT NULL DEFAULT now(),
  score_a integer NOT NULL,
  score_b integer NOT NULL,
  duration_minutes integer NOT NULL DEFAULT 90,
  CONSTRAINT matches_scores_non_negative CHECK (score_a >= 0 AND score_b >= 0),
  CONSTRAINT matches_duration_positive CHECK (duration_minutes > 0)
);

CREATE TABLE public.match_player_stats (
  match_id uuid NOT NULL REFERENCES public.matches (id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.players (id) ON DELETE CASCADE,
  team public.match_team NOT NULL,
  goals integer NOT NULL DEFAULT 0,
  saves integer NOT NULL DEFAULT 0,
  is_rotation_gk boolean NOT NULL DEFAULT false,
  received_mvp_vote boolean NOT NULL DEFAULT false,
  clean_sheet boolean NOT NULL DEFAULT false,
  PRIMARY KEY (match_id, player_id),
  CONSTRAINT match_player_stats_goals_non_negative CHECK (goals >= 0),
  CONSTRAINT match_player_stats_saves_non_negative CHECK (saves >= 0)
);

CREATE INDEX match_player_stats_player_id_idx ON public.match_player_stats (player_id);
CREATE INDEX matches_created_at_idx ON public.matches (created_at DESC);

COMMENT ON TABLE public.players IS 'Jucători SIMF — rating μ/σ (OpenSkill/TrueSkill în app).';
COMMENT ON TABLE public.matches IS 'Meciuri înregistrate (scor + durată).';
COMMENT ON TABLE public.match_player_stats IS 'Statistici individuale pe meci (goluri, parade, MVP, etc.).';

-- ---------------------------------------------------------------------------
-- Row Level Security (proto-tip: anon + authenticated pot CRUD)
-- În producție: restrânge la auth.uid() sau roluri dedicate.
-- ---------------------------------------------------------------------------

ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_player_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "players_allow_all_anon_auth"
  ON public.players
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "matches_allow_all_anon_auth"
  ON public.matches
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "match_player_stats_allow_all_anon_auth"
  ON public.match_player_stats
  FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);
