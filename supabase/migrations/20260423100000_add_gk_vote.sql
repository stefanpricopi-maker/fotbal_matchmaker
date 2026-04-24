-- Add goalkeeper-of-match vote (rotation GK) to stats table
ALTER TABLE public.match_player_stats
  ADD COLUMN IF NOT EXISTS received_gk_vote boolean NOT NULL DEFAULT false;

-- Optional index for filtering (not required, but cheap)
CREATE INDEX IF NOT EXISTS match_player_stats_received_gk_vote_idx
  ON public.match_player_stats (received_gk_vote);

 