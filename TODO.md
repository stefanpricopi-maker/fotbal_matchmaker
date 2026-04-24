# TODO — SIMF (Sistem Inteligent de Matchmaking Fotbal)

Listă derivată din `specification.md`. Bifează incremental pe măsură ce implementezi.

---

## Roadmap (prioritate / „mai târziu”)

Idee păstrate din discuții; nu sunt blocate de bifările de mai sus.

- [ ] **CI**: GitHub Actions (sau echivalent) — `flutter analyze` + `flutter test` la fiecare PR.
- [ ] **Supabase multi-user**: RLS + autentificare (înlocuire politici permisive); eventual `user_id` / tenant pe rânduri.
- [ ] **Teste**: `SimfController` / flux sync cu `SupabaseService` mock; widget test minimal pe ecranul de scor (validare + stare).
- [ ] **UX sync**: mesaje clare când `loadPlayers` reușește parțial (ex. meciuri încă offline) sau eșuează.
- [ ] **Meciuri**: editare / ștergere locală + propagare cloud (după ce există model de „owner” dacă ai auth).
- [ ] **Performanță sync**: paginare / filtru la `fetchMatches` când istoricul devine mare.
- [ ] **Opțional vizual**: font dedicat (ex. `google_fonts`) pentru identitate mai puternică.

---

## Setup și fundație

- [x] Inițializare proiect Flutter + dependențe: `sqflite`, client Supabase, rating (TrueSkill/`matchmaker`).
- [x] Configurare mediu: URL Supabase, chei, variabile locale sigure (`--dart-define-from-file`).
- [x] Convenții: enum `team` (`A` / `B`), mapare la UI (Roșu/Albastru).

---

## Date: Supabase / PostgreSQL

- [x] Migrări / SQL pentru `players` (`id`, `name`, `mu`, `sigma`, `is_permanent_gk`, `matches_played`).
- [x] Migrări pentru `matches` (`id`, `created_at`, `score_a`, `score_b`, `duration_minutes`).
- [x] Migrări pentru `match_player_stats` (FK-uri, `team`, `goals`, `is_rotation_gk`, `received_mvp_vote`, `received_gk_vote`).
- [ ] Politici RLS / autentificare dacă e multi-user (deocamdată proto permisiv).

---

## Modele și persistență locală (SQLite)

- [x] Modele Dart aliniate la schema.
- [x] Schema SQLite locală: `players`, `matches`, `match_player_stats`, `player_aliases` (+ upgrade versions).
- [x] CRUD jucători (add/delete/rename).
- [x] Persistare offline-first: meci + statistici local mereu; sync către Supabase când e online + retry la `loadPlayers`.
- [x] Strategie conflicte multi-device: **last-write-wins** pe `players.updated_at` și `matches.updated_at` (îmbinare la `loadPlayers` + upsert-uri).

---

## Algoritmi și business logic

- [x] `MatchmakingEngine`: portari permanenți în echipe diferite; locked în swap.
- [x] Repartizare aleatoare inițială.
- [x] Swap iterativ + multi-restart + tie-break aleator.
- [x] Optimizare compusă: echilibru + omogenitate (spread mic în echipe).
- [x] Afișare „șanse de câștig”.
- [x] Rating update TrueSkill cu ponderare aproximativă după performanță (weights).

---

## UX: post-meci (Rapid Fire)

- [x] Ecran split-screen: stânga o echipă, dreapta cealaltă.
- [x] Goluri per jucător: counter compact (minge +/−) în rând.
- [x] Toggle „mănușă” pentru `is_rotation_gk`.
- [x] Vot MVP (stea): max. 1 per echipă (admin).
- [x] Vot “Portarul meciului” (scut): max. 1 pe meci, doar pentru GK rotație.
- [x] Validare: scorul de sus trebuie să fie egal cu suma golurilor jucătorilor.

---

## UI general și polish

- [x] Temă dark sport (gazon) + card styling + accente.
- [x] Flux: jucători → import WhatsApp → preview echipe → introducere scor → istoric/sync.
- [x] Ecran “Echipe generate” + “Generează iar”.
- [x] Ecran “Istoric meciuri” + detalii + sync manual.
- [x] Mesaje offline + status synced/offline.
- [x] **Introducere scor**: chip-uri șansă A/B, bară scor cu gradient discret, header coloane cu gradient, rânduri jucători tip „sheet” (separatori + chenar).
- [x] **Listă jucători**: avatar circular cu gradient după skill + badge vizibil portar permanent.

---

## Calitate și livrare

- [x] Teste unitare: matchmaking (portari + swap), ranking / ponderi (vezi `test/`).
- [ ] Teste minime UI pentru ecranul de scor (fără pierdere date).
- [ ] Verificare end-to-end: meci complet → ratinguri local + după sync în Supabase.

---

## Import WhatsApp (admin workflow)

- [x] Textarea paste listă WhatsApp + parsing robust (linii/virgule/numere).
- [x] Matching asistat cu sugestii (fuzzy) + dialog de alegere.
- [x] “Jucător nou” direct din modal.
- [x] “Învățare” alias-uri (mapare WhatsApp string → playerId).
- [x] Opțiune “Creează automat jucătorii lipsă” + rezumat import.
