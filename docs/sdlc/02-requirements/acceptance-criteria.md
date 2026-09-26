# 2.11 Acceptance Criteria

Kila requirement itakayoingia coding lazima iwe na kipimo (acceptance criteria). Format:

```
Given [context]
When [action]
Then [expected result]
```

## Mfano 1: FR-MED-004 — Record medication taken

- **Requirement:** Patient anaweza kuweka medication status.
- **Acceptance Criteria:**
  - Given patient is authenticated, when patient opens medication tracker, then active medications should be displayed.
  - Given medication exists, when patient marks it as taken, then system should save the medication event.
  - Given event is saved, then adherence statistics should be updated.

## Mfano 2: FR-AUTH-002 — Authenticate users

- Given user alijisajili, when ana login na sifa sahihi, then anapewa access token.
- Given user anatoa sifa zisizo sahihi, then system inakataa na kurudisha error sahihi.
- Given session ipo, when logout, then token inainvalidate.

## Mfano 3: FR-BLD-007 — Identify suitable donors

- Given blood request imeundwa, when matching inaendeshwa, then system inarudisha donors waliofit (blood group, location, availability).
- Given hakuna donors wanaofaa, then system inarudisha empty result kwa tracking/awareness.

## Mfano 4: FR-MEDREC-004 — Access expiration

- Given patient amegrant doctor access kwa muda, when muda unamalizika, then access inazimika automatically kwa hiari na hakuna data mpya inayoonwa.

---

> Kila functional requirement (FR) itapata acceptance criteria kamili wakati wa testing planning (Stage ya Testing). Hapa tunaweka pattern na mifano.