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
    * `updated_at`: Timestamp — folosit la sincronizare multi-device (**last-write-wins**).
* **`matches`**
    * `id`: UUID
    * `created_at`: Timestamp
    * `score_a`: Int
    * `score_b`: Int
    * `duration_minutes`: Int (Default: 90)
    * `updated_at`: Timestamp — LWW la îmbinarea cu cloud-ul.
* **`match_player_stats`**
    * `match_id`: FK către `matches`
    * `player_id`: FK către `players`
    * `team`: Enum ('A', 'B')
    * `goals`: Int (Default: 0)
    * `is_rotation_gk`: Boolean (Default: false)
    * `received_mvp_vote`: Boolean (Default: false) - Votat de adversari.
    * `received_gk_vote`: Boolean (Default: false) - Vot “Portarul meciului” (doar pentru GK de rotație).

---

## 3. Logica de Business și Algoritmi

### 3.1 Algoritmul de Matchmaking (Echilibrare)
**Obiectiv:** Echipe **echilibrate** și cât mai **omogene** (jucători de valori apropiate în interiorul aceleiași echipe), nu doar suma totală.
1.  **Separarea Portarilor:** Dacă există 2 jucători cu `is_permanent_gk = true`, aceștia sunt alocați automat în echipe diferite.
2.  **Iterative Swap:**
    * Se împart restul jucătorilor aleatoriu.
    * Se execută iterații de schimb între jucători pentru a minimiza un obiectiv compus:
        * diferența de “putere” între echipe (ex. sumă pe \( \mu \) sau skill conservator \( \mu - 3\sigma \))
        * spread-ul din interiorul fiecărei echipe (omogenitate)
3.  **Afișare:** Aplicația prezintă echipele și "Șansele de Câștig" bazate pe distribuția normală a ratingurilor.

### 3.2 Calculul Performanței ($P_i$)
După fiecare meci, se calculează un scor de performanță individuală pentru a ajusta $\mu$ și $\sigma$ prin modelul TrueSkill/OpenSkill (în app: pachetul `matchmaker`):

$$P_i = (Win \times 10) + (Goals \times 4) + (MVP \times 7) + (PortarMeci \times 6)$$

* **Win:** 10 puncte dacă echipa jucătorului a câștigat meciul, altfel 0.
* **MVP:** 7 dacă `received_mvp_vote` este adevărat.
* **PortarMeci:** 6 dacă `received_gk_vote` este adevărat **și** jucătorul este GK de rotație (`is_rotation_gk`, nu portar permanent). În caz contrar 0 (inclusiv portarul permanent nu primește bonus din acest vot).

---

## 4. UX & Interfață (Cerințe pentru Cursor AI)

### 4.1 "Rapid Fire" Scorer Entry (Post-Match)
* **Ecran de tip Split-Screen:** Partea stângă (Echipa Roșie), Partea dreaptă (Echipa Albastră).
* **Control:** Fiecare jucător are un rând cu butoane mari de `+` și `-` pentru goluri.
* **Toggle:** Un buton mic tip "Mănușă" lângă nume pentru a marca cine a stat în poartă (dacă nu e portar fix).
* **Vot MVP:** O stea în dreptul fiecărui jucător (administrat de “admin”; max. 1 per echipă).
* **Vot “Portarul meciului”:** Un scut în dreptul jucătorilor marcați ca GK de rotație (max. 1 pe meci).

### 4.2 Sincronizare
* Datele sunt salvate local în `SQLite` (prin `sqflite`) și trimise către `Supabase` când există conexiune la internet (**offline-first**).
* La revenirea online, `players` și `matches` se îmbină cu remote folosind **last-write-wins** pe `updated_at` (la egalitate câștigă varianta din cloud). Meciurile în așteptare se urcă cu **upsert** idempotent.

### 4.3 Flux recomandat
* **Roster** (listă jucători) cu metrici și căutare/sortare.
* **Adaugă listă jucători pentru joc**: lipire listă din WhatsApp, matching asistat + auto-creare jucători lipsă, apoi bifare automată.
* **Echipe generate**: preview fără editare scor, cu posibilitate de “Generează iar”.
* **Introducere scor**: doar după confirmarea echipelor, se introduce scorul și golurile per jucător.

---

## 5. Instrucțiuni pentru Implementare (Prompt-uri de start)

1.  **Prompt 1 (Setup):** "Creează modelele de date în Dart conform specificației. Asigură-te că `is_permanent_gk` influențează logica de calcul a performanței."
2.  **Prompt 2 (Algoritm):** "Implementează serviciul `MatchmakingEngine` și ratingul cu pachetul `matchmaker` (TrueSkill). Adaugă funcția de swap iterativ care respectă constrângerea portarilor."
3.  **Prompt 3 (UI):** "Generează ecranul `MatchSummaryScreen`. Vreau un tabel cu două coloane (Echipa A/B) unde pot să apăs rapid pe '+' pentru a adăuga goluri fiecărui jucător. Designul trebuie să fie sportiv, dark mode, cu accente de verde gazon și roșu/albastru pentru echipe."

---