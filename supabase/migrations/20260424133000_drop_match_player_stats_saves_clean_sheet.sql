-- Remove unused stats columns (app no longer tracks saves / clean sheet)

ALTER TABLE public.match_player_stats
DROP COLUMN IF EXISTS saves;

ALTER TABLE public.match_player_stats
DROP COLUMN IF EXISTS clean_sheet;
