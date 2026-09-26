# 2.9 Security & Privacy Requirements

## Security
- Usafirishaji wote wa data unalindwa wakati wa transmission (TLS/HTTPS).
- Passwords hazitahifadhiwa in plaintext (hashing + salting).
- Sensitive medical information inahitaji authorization madhubuti.
- Critical operations zina-activity audit logs.
- System inapaswa kuwa na ulinzi dhidi ya common web/API attacks (e.g. OWASP Top 10).
- Multi-factor approach inafikiwa baada ya implementation planning (prioritized).

## Access Control Model
Access ya medical record itafuata model ya layered:

```
Role
  + Permission
  + Patient Consent
  + Context
```

Ambapo:
- **Role** = kitu gani user ni (doctor, caregiver, admin...)
- **Permission** = what operations anaruhusiwa kufanya
- **Patient Consent** = patient ametoa ruhusa maalum
- **Context** = context ya request (medical vs admin vs blood workflow)

## Privacy
- Patient anaweza kuweka na kuondoa consent (grant/revoke).
- Access inaweza kuwa na muda (expiration).
- Data ya hospital/contact haishirikiwi kwa umma (e.g. BR-006).
- Medical records ni private by default (BR-002).
- Data protection principles: data minimization, purpose limitation, access on a need-to-know basis.

## Kumbuka
- Mfumo hautahifadhi **au kushiriki** data za kimatibabu kwa wahusika wasioauthorized.
- Kutolewa kwa data kwa wakati huu ni kwa documentation za SDLC; utekelezaji unahitaji kubainisha data retention/erasure policies kwenye design stage.