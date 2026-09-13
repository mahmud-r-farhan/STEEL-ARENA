# Security Policy — Steel Arena

Steel Arena takes security, game integrity, and player privacy seriously. This document outlines our security model, threat mitigations, and instructions for reporting vulnerabilities.

---

## 1. Security Architecture & Threat Model

Steel Arena uses an **authoritative server model** over UDP. Game state and physics calculations are computed on the server side to prevent client manipulation.

### Core Security Controls:

- **Input & Loadout Validation**:
  - `Protocol.sanitizeLoadout()` clamps tank selections and upgrade levels (0–3) to valid ranges regardless of client payload claims.
  - Unknown tank IDs fall back safely to `scout`.
- **Name & Chat Sanitization**:
  - `Protocol.sanitizeName()` strips control characters and limits callsigns to printable alphanumeric and basic punctuation characters (`[%w _-]`), max 16 characters.
  - `Protocol.sanitizeChat()` strips control characters and rate-limits messages (0.4s cooldown per connection) to prevent spam.
- **Connection Management & Flood Protection**:
  - UDP packet magic numbers are verified for every packet.
  - Inactive connections automatically time out after 12 seconds of silence.
  - Unauthenticated clients cannot execute remote commands or access filesystem functions.

---

## 2. Reporting Vulnerabilities

If you discover a security vulnerability or exploit in Steel Arena, please follow responsible disclosure:

1. **Do not disclose publicly**: Avoid opening public GitHub issues or sharing details on public forums prior to resolution.
2. **Report Details**: Email security disclosures to the maintainers with:
   - Description of the vulnerability or exploit vector.
   - Steps or proof-of-concept payload to reproduce the issue.
   - Potential impact on server stability or game state integrity.
3. **Response Timeline**:
   - Acknowledgment within 48 hours.
   - Patch deployment and disclosure timeline coordinated within 14 days.
