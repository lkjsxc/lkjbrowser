# Independent adversarial TLS test peer

`tools/tls-bad-finished-peer.cjs` is a test-only TLS 1.3 server implemented with
Node's independent OpenSSL cryptographic primitives. The browser never executes
or imports it. It uses only the public synthetic `tests/x509/localhost` key and
certificate, binds `127.0.0.1:0`, and writes `{port,pid,mode}` to its supplied JSON
path. SIGINT/SIGTERM close its sockets and listener. The caller owns and reaps it.
No ephemeral scalar, traffic key or live transcript is printed or saved.

```sh
node tools/tls-bad-finished-peer.cjs good target/peer-port.json
```

The supported profile is TLS_AES_128_GCM_SHA256, X25519, ECDSA P-256/SHA-256
CertificateVerify and HTTP/1.1. Each connection has fresh server randomness and
an ephemeral key pair. The five modes are:

| Mode | Deliberate behavior |
| --- | --- |
| `good` | Authenticate the client Finished and serve the fixed HTML page titled `Authenticated test peer`. |
| `fragmented` | Split the server's encrypted handshake across 37-byte protected-record fragments, including message-header/body boundaries. |
| `key-update` | After the GET, request a client KeyUpdate and send HTTP under the next server application traffic secret. |
| `bad-finished` | Alter the Finished verify_data before applying valid record authentication. |
| `bad-signature` | Alter the CertificateVerify signature before transcript hashing and valid record authentication. |

The two negative modes distinguish handshake authentication from record
protection: the corrupted handshake bytes still have a correct GCM tag. They
must produce the corresponding browser error, not an HTTP page. A successful
`good` run is the positive control for the otherwise identical peer.

On 2026-11-17 UTC, an independent OpenSSL 3.0.13 client with explicit
`tests/x509/root.pem` trust and `-verify_hostname localhost` accepted `good`,
`fragmented` and `key-update`, verified the response, and exited zero. It refused
`bad-finished` at `tls_process_finished` with `digest check failed`, and
`bad-signature` at `tls_process_cert_verify` with `bad signature`. The finite
manual peer-oracle proof is in the run log under
`target/adversarial-peer.QRo6GILA`; temporary captures are not the browser's
committed regression gate. All five owned peers were stopped and reaped.

## Native browser proof

The native lkjscript client subsequently passed all five modes through
tools/tls-local-test.sh, with explicit tests/x509/root.pem trust. Evidence is
retained in target/browser-tls-local.j0yZksmi:

| Mode | Native result |
| --- | --- |
| good | Authenticated test page rendered; TLS handshake 23,712 microseconds. |
| fragmented | Same authenticated page rendered across 37-byte handshake record fragments. |
| key-update | Same authenticated page rendered after the server update/request. |
| bad-finished | Ordinary error page; log says the TLS Finished authentication check failed. |
| bad-signature | Ordinary error page; log says the ECDSA signature did not verify. |

The gate checks the expected successful title and authenticated-connection log,
or the error-page title and corresponding refusal reason. These results are
native browser proof, separate from the earlier OpenSSL peer-oracle check.
The test processes were stopped and reaped. No public endpoint was needed.

Reproduce just the local interoperability/error pages with:

~~~sh
sh tools/tls-local-test.sh
~~~

The combined offline gate is tools/https-test.sh. This peer does not implement a
general-purpose TLS server, certificate policy, resumption or client identity.
