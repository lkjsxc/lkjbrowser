# Public known-answer data for TLS primitives

`public_known_answers.json` contains **14 fixed cases**, transcribed from
official RFC/NIST publications. This is data preparation for a future lkjscript
adapter. It does not implement cryptography or demonstrate a working TLS client.
The protocol implementation plan targets the current
[RFC 9846](https://www.rfc-editor.org/info/rfc9846/).

Every key, private scalar, PRK and shared result here is **public published test
material**, not a user secret. No live keys were read or generated. These fixed
values, including repeated example key/IV pairs, must never be used as
operational randomness or connection keys.

## Contents and provenance

| JSON group | Cases | Official location | What the published expected values establish when a future implementation is compared |
| --- | ---: | --- | --- |
| `hkdf_sha256` | 3 | [RFC 5869 Appendix A.1–A.3](https://www.rfc-editor.org/rfc/rfc5869) | Extract and expand results for ordinary, longer, and empty-salt/info inputs. Both PRK and OKM are retained. |
| `x25519` | 2 scalar cases | [RFC 7748 section 5.2](https://www.rfc-editor.org/rfc/rfc7748) | Published scalar/u-coordinate input and output pairs. |
| `x25519` | 4 exchange cases | [RFC 7748 section 6.1](https://www.rfc-editor.org/rfc/rfc7748) | Alice/Bob public-key generation and both directions of their published shared-secret calculation. Each row uses the same scalar-multiplication schema. |
| `aes128_block` | 1 | [FIPS 197, Appendix B](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197-upd1.pdf), printed pages 34–35 | One AES-128 block encryption result. The output matrix was checked visually and serialized in column order. |
| `aes128_gcm` | 4 | [NIST AES-GCM examples](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/AES_GCM.pdf), GCM-AES128 examples 1, 2, 3 and 5 | Empty plaintext/AAD; 64-byte plaintext without AAD; 64-byte AAD without plaintext; and 60-byte plaintext with 20-byte AAD. |

The GCM corpus follows that specific NIST PDF. Its example 5 uses AAD beginning
`3ad77bb4`; do not substitute the different AAD from other commonly circulated
examples while retaining this tag.

## Adapter conventions

All `*_hex` fields are lowercase hexadecimal in the publication's octet order.
An empty string means zero bytes. Decode pairs of characters into bytes; do not
reverse an X25519 field as if it were a displayed big-endian integer.

Each case has an ID, source ID, precise locator and explicit `byte_lengths`.
HKDF `length` is the requested OKM byte count. X25519 inputs are the published
raw scalar bytes; normal algorithm decoding/clamping belongs to the later
implementation. The AES block case has no IV or padding. GCM ciphertext and tag
are separate; all selected GCM IVs are 12 bytes and tags are 16 bytes.

The JSON's source table carries direct URLs so an adapter can preserve provenance
without duplicating descriptions.

## Checks actually performed

Only JavaScript data checks were run:

- 14 unique vector IDs and valid source references.
- 60 hex fields: lowercase syntax, even length, exact expected byte count,
  and byte decoding/re-encoding equality.
- 1701 total decoded bytes across those fields.
- HKDF PRK length and requested/expected OKM length consistency.
- GCM key/IV/tag lengths and plaintext/ciphertext length equality.
- Alice/Bob exchange input/output cross-reference equality.
- JSON serialization/parsing equality.

No hash, HMAC, HKDF, curve, AES or GCM operation was evaluated. No builds,
cryptographic tests or service traffic were run. Length checks catch transcription
shape errors; correctness still depends on the official expected values and the
future adapter's actual comparisons. This finite corpus is a starting set, not
full primitive validation or TLS interoperability evidence.
