# Telvox mobile Postman snapshot

Copied on 30 October 2026 from `../themessenger/postman/mobile-api/`.
Contains **107 requests**. See [ENDPOINTS.md](ENDPOINTS.md) for the inventory and
[../../HANDOFF.md](../../HANDOFF.md) for implementation scope and caveats.

Import the collection and environment JSON into Postman and select the environment.
The copied environment defaults to `https://dev.themessenger.app`. Supply login
credentials privately; bearer/challenge/account variables are intentionally empty.
Use the collection's login/me/config and selection flow before scoped requests.
Example IDs are not automatically the authorized test contact's IDs.

Seventeen literal credential fields in example payloads were replaced with
`<REDACTED_SAMPLE>`; variable placeholders and scripts are retained. This snapshot
is deliberately sanitized, not byte-for-byte identical to the source. Original
and copied SHA-256 hashes are in `snapshot-manifest.json`. Source files were not
changed. Do not commit a populated environment or export live bearer tokens.

Do not run the whole collection blindly: sending messages, editing contacts,
assignment, notes and ticket actions are mutations. The collection also contains
capabilities outside the agreed mobile scope (for example AI/catalogue/realtime).

Runtime correction: media galleries use `type: media`, `document`, or `link`,
not `docs`/`links`. Treat live responses and current backend code as contract
verification sources when examples differ.

To refresh later: compare source changes, copy deliberately, scrub literal secrets,
keep credentials blank, regenerate the inventory/hashes and update the handoff
with the new date. Do not silently replace this tested snapshot during unrelated
feature work.
