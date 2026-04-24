# SIMF — checklist E2E (local → sync)

Scop: să verificăm rapid că fluxul principal funcționează cap-coadă, inclusiv offline-first și sincronizarea în Supabase (când e disponibil).

## 0) Cloud — migrări și model de date

Înainte de teste cu **Supabase activ**, proiectul remote trebuie să aibă migrările aplicate (`supabase db push` sau SQL Editor), în ordinea din `supabase/migrations/`, astfel încât să existe cel puțin:

- `players.updated_at` (+ trigger `set_updated_at` la update)
- `matches.updated_at` (+ trigger pe `matches`)
- `match_player_stats` **fără** coloanele vechi `saves` / `clean_sheet` (doar goluri, GK rotație, voturi MVP / portar meci)

Aplicația folosește **last-write-wins** pe `updated_at` la îmbinarea jucătorilor și meciurilor la `loadPlayers`, și **upsert** idempotent pentru meciuri la upload.

## 1) Setup (1 minut)

- Rulează aplicația cu define-urile Supabase:

```bash
flutter run --dart-define-from-file=simf_defines.json
```

- În `SIMF — Jucători`, verifică icon-ul cloud:
  - cloud **plin** = sync disponibil
  - cloud **gol** = rulezi fără Supabase / fără chei / offline

## 2) Seed minim (jucători)

- Adaugă 8–14 jucători (nume distincte).
- Marchează 0–2 ca **portar permanent** (din dialogul de creare).

*(Debug)* Poți folosi meniul **Dev tools** → **Creează demo seed** pentru jucători + un meci demo, apoi verifică istoricul și sync-ul.

## 3) Import WhatsApp → selecție

- Mergi la `Meci nou`.
- Lipește în câmp o listă cu 8–14 nume.
- Apasă **Importă în selecția meciului**.
  - dacă apar neconcordanțe, rezolvă din dialogurile de matching
  - dacă ai „Jucători noi automat” ON, verifică faptul că îi creează fără prompt

## 4) Generează echipe → preview → introducere scor

- Apasă **Generare echipe**.
- În preview apasă **Introducere scor**.
- Completează scorul (A/B) și apoi adaugă golurile pe jucători.
- Verifică validarea: butonul de finalizare e dezactivat dacă suma golurilor nu bate cu scorul.
- (opțional) Marchează GK rotație + votează „Portarul meciului” (scut) conform regulilor UI.

## 5) Finalizare → Istoric

- Apasă **Finalizează meciul**.
- Deschide **Istoric** (din snackbar sau din ecranul dedicat dacă există shortcut).
- Verifică:
  - meciul apare cu scorul corect
  - status **offline/synced** e corect
  - detaliile pe meci arată golurile pe jucători corect

## 6) Sync (când revine internetul)

- Dacă ai făcut meciul offline sau fără Supabase:
  - repornește aplicația cu define-urile Supabase
  - intră în `SIMF — Jucători` (se face retry la `loadPlayers`: meciuri în așteptare + merge LWW)
- Verifică în Istoric că meciul trece pe **synced**.
- Reîncarcă lista (pull to refresh dacă există): datele locale rămân consistente după merge.

## 7) Verificare rating (sanity)

- După finalizare, în lista de jucători:
  - `matches played` crește pentru cei care au jucat
  - ratingurile (μ/σ) se schimbă rezonabil (câștigătorii în sus, pierzătorii în jos)

## 8) Multi-device / LWW (opțional, ~5 min)

Cu același proiect Supabase pe **două instanțe** ale app-ului (sau două device-uri):

- Creează sau modifică un jucător pe A, apoi deschide lista pe B și trage refresh / re-intră în ecran: câștigă versiunea cu `updated_at` mai nou; la egalitate, remote.
- Înregistrează un meci pe un device offline, sincronizează pe celălalt: după `loadPlayers`, meciul apare local și în cloud fără duplicate (upsert pe id meci).
