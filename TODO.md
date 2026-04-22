# TODO — SIMF (Sistem Inteligent de Matchmaking Fotbal)

Listă derivată din `specification.md`. Bifează incremental pe măsură ce implementezi.

---

## Setup și fundație

- [ ] Inițializare proiect Flutter + dependențe: `sqflite`, client Supabase, `openskill_dart` (sau echivalent rating).
- [ ] Configurare mediu: URL Supabase, chei, variabile locale sigure.
- [ ] Convenții: enum `team` (`A` / `B`), mapare la UI (ex. Roșu/Albastru) dacă e cazul.

---

## Date: Supabase / PostgreSQL

- [ ] Migrări / SQL pentru `players` (`id`, `name`, `mu`, `sigma`, `is_permanent_gk`, `matches_played` cu default-urile din spec).
- [ ] Migrări pentru `matches` (`id`, `created_at`, `score_a`, `score_b`, `duration_minutes` default 90).
- [ ] Migrări pentru `match_player_stats` (FK-uri, `team`, `goals`, `saves`, `is_rotation_gk`, `received_mvp_vote`, `clean_sheet`).
- [ ] Politici RLS / autentificare dacă e multi-user (spec: „administrator” la vot MVP).

---

## Modele și persistență locală (SQLite)

- [ ] Modele Dart aliniate la schema; `is_permanent_gk` folosit în logica de calcul, nu doar ca câmp.
- [ ] Schema SQLite locală (tabele echivalente sau subset + coadă sincronizare).
- [ ] Repository / DAO: CRUD jucători, creare meci, statistici per jucător/meci.
- [ ] Sincronizare: scriere locală mereu; push către Supabase la reconectare; strategie conflicte (de clarificat: last-write / server-wins).

---

## Algoritmi și business logic

- [ ] `MatchmakingEngine`: dacă există 2 jucători cu `is_permanent_gk == true`, unul în A, unul în B.
- [ ] Repartizare aleatoare inițială a restului pe A/B.
- [ ] 100 iterații de swap pentru minimizarea |Σμ_A − Σμ_B|, păstrând constrângerea portarilor permanenți.
- [ ] Afișare „șanse de câștig” bazată pe distribuția normală a ratingurilor (agregat pe echipă).
- [ ] După meci: calcul P_i (Win×10, Goals×4, Saves×W_gk, CleanSheet×8, OpponentMVP×7).
- [ ] W_gk: 3 dacă `is_permanent_gk`, 1 dacă `is_rotation_gk`.
- [ ] OpenSkill: actualizare `mu` / `sigma`; increment `matches_played` unde e cazul.

---

## UX: post-meci (Rapid Fire)

- [ ] Ecran split-screen: stânga o echipă, dreapta cealaltă.
- [ ] Rând per jucător: butoane mari +/− pentru goluri.
- [ ] Toggle „mănușă” pentru `is_rotation_gk` (când nu e portar fix).
- [ ] Vot MVP (stea): reguli adversari / o stea per echipă — implementare clară (ex. admin sau consens).
- [ ] Scor meci, durată, `clean_sheet` per rând (sau regulă de propagare dacă simplifici).
- [ ] Salvare draft local la acțiuni (înainte de submit final).

---

## UI general și polish

- [ ] Temă dark, accente verde gazon, roșu/albastru pentru echipe.
- [ ] Flux: jucători → generare echipe → meci → rezumat → sincronizare.
- [ ] Mesaje offline: salvat local, trimis când există rețea.

---

## Calitate și livrare

- [ ] Teste unitare: matchmaking (portari + swap), P_i, ponderi portar.
- [ ] Teste minime UI pentru ecranul de scor (fără pierdere date).
- [ ] Verificare end-to-end: meci complet → ratinguri local + după sync în Supabase.
