Înregistrarea fiecărui marcator în parte este cea mai bună decizie pentru precizia algoritmului, deoarece ne permite să vedem nu doar **cine** a câștigat, ci și **cine** a purtat echipa în spate. Totuși, pentru a nu deveni o corvoadă la finalul meciului (când toată lumea e obosită), interfața trebuie să fie de tip "Tally Counter" (un simplu plus/minus).

Iată documentul de specificații finale, gata de a fi copiat într-un fișier `specification.md` în **Cursor AI**.

---

# Specificație Tehnică: SIMF (Sistem Inteligent de Matchmaking Fotbal)

## 1. Viziune Produs
O aplicație de gestionare a meciurilor de fotbal 6+1 (sintetic) care utilizează un model de ranking bayesian pentru a genera echipe echilibrate, bazându-se pe performanțe individuale detaliate și voturi de tip peer-review.

## 2. Arhitectura Datelor (Supabase / PostgreSQL)

### 2.1 Schema Tabelelor
* **`players`**
    * `id`: UUID (Primary Key)
    * `name`: Text
    * `mu`: Float (Default: 25.0) - Abilitatea medie.
    * `sigma`: Float (Default: 8.33) - Gradul de incertitudine.
    * `is_permanent_gk`: Boolean (Default: false)
    * `matches_played`: Int (Default: 0)
* **`matches`**
    * `id`: UUID
    * `created_at`: Timestamp
    * `score_a`: Int
    * `score_b`: Int
    * `duration_minutes`: Int (Default: 90)
* **`match_player_stats`**
    * `match_id`: FK către `matches`
    * `player_id`: FK către `players`
    * `team`: Enum ('A', 'B')
    * `goals`: Int (Default: 0)
    * `saves`: Int (Default: 0)
    * `is_rotation_gk`: Boolean (Default: false)
    * `received_mvp_vote`: Boolean (Default: false) - Votat de adversari.
    * `clean_sheet`: Boolean (Default: false)

---

## 3. Logica de Business și Algoritmi

### 3.1 Algoritmul de Matchmaking (Echilibrare)
**Obiectiv:** Minimizarea diferenței de rating dintre cele două echipe.
1.  **Separarea Portarilor:** Dacă există 2 jucători cu `is_permanent_gk = true`, aceștia sunt alocați automat în echipe diferite.
2.  **Iterative Swap:**
    * Se împart restul jucătorilor aleatoriu.
    * Se execută 100 de iterații de schimb între jucători pentru a găsi combinația în care $|\sum \mu_{TeamA} - \sum \mu_{TeamB}|$ este minim.
3.  **Afișare:** Aplicația prezintă echipele și "Șansele de Câștig" bazate pe distribuția normală a ratingurilor.

### 3.2 Calculul Performanței ($P_i$)
După fiecare meci, se calculează un scor de performanță individuală pentru a ajusta $\mu$ și $\sigma$ prin modelul OpenSkill:

$$P_i = (Win \times 10) + (Goals \times 4) + (Saves \times W_{gk}) + (CleanSheet \times 8) + (OpponentMVP \times 7)$$

* **$W_{gk}$ (Pondere Portar):**
    * `3` dacă `is_permanent_gk` este `true`.
    * `1` dacă `is_rotation_gk` este `true` (jucător de câmp care a stat temporar în poartă).

---

## 4. UX & Interfață (Cerințe pentru Cursor AI)

### 4.1 "Rapid Fire" Scorer Entry (Post-Match)
* **Ecran de tip Split-Screen:** Partea stângă (Echipa Roșie), Partea dreaptă (Echipa Albastră).
* **Control:** Fiecare jucător are un rând cu butoane mari de `+` și `-` pentru goluri.
* **Toggle:** Un buton mic tip "Mănușă" lângă nume pentru a marca cine a stat în poartă (dacă nu e portar fix).
* **Vot MVP:** O stea în dreptul fiecărui jucător. Restricție: Administratorul poate bifa steaua doar pentru jucătorii din echipa adversă celui care votează (sau o singură stea per echipă decisă la comun).

### 4.2 Sincronizare
* Datele sunt salvate local în `SQLite` (prin `sqflite`) și trimise către `Supabase` când există conexiune la internet.

---

## 5. Instrucțiuni pentru Implementare (Prompt-uri de start)

1.  **Prompt 1 (Setup):** "Creează modelele de date în Dart conform specificației. Asigură-te că `is_permanent_gk` influențează logica de calcul a performanței."
2.  **Prompt 2 (Algoritm):** "Implementează serviciul `MatchmakingEngine` folosind pachetul `openskill_dart`. Adaugă funcția de swap iterativ care respectă constrângerea portarilor."
3.  **Prompt 3 (UI):** "Generează ecranul `MatchSummaryScreen`. Vreau un tabel cu două coloane (Echipa A/B) unde pot să apăs rapid pe '+' pentru a adăuga goluri fiecărui jucător. Designul trebuie să fie sportiv, dark mode, cu accente de verde gazon și roșu/albastru pentru echipe."

---