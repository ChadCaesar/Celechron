# SimpleQRCode regression tests

Run the suite from the repository root on macOS:

```sh
bash ios/CelechronWatchTests/run_tests.sh
```

The suite intentionally does not require an Xcode test target. It tests both the
pure Swift QR encoder and the shared campus-card response/client logic. It covers:

1. Exact Version 1, 2, and 3 matrices against fixtures produced by the independent
   Dart `qr` package used by the iPhone UI. These comparisons cover byte packing,
   terminator/padding, Reed–Solomon error correction, finder/timing/alignment
   patterns, format information, data placement, and mask 0.
2. Every capacity transition: 0, 1, 14, 15, 26, 27, 42, and 43 UTF-8 bytes.
   The 43-byte case must fail instead of silently truncating a payment token.
3. The watch-specific one-module quiet zone and deterministic output for all supported
   versions. The surrounding white SwiftUI container supplies additional visual margin.
4. UTF-8 boundary cases using three-byte CJK characters, ensuring capacity is
   measured in bytes rather than Swift `Character` values.
5. Apple Vision end-to-end decoding at 3 and 6 pixels per module, including numeric,
   ASCII, CJK, emoji, and decomposed Unicode payloads.
6. Seeded property tests: one independently decoded random payload at every supported
   length from 1 through 42 bytes.
7. Campus-card authentication evidence: HTTP 401/403/901, CAS redirects, HTTP 200
   login pages, JSON status codes, `kickout`, and explicit failed-auth messages.
8. Separation of expiry from retryable network/server failures and malformed
   responses, including 408/425/429/5xx and unexpected redirects/HTML/JSON.
9. ECardWidget-compatible card parsing, highest-balance selection, cached-account
   refresh on an empty barcode, and preservation of auth/network error categories.

To regenerate the independent matrix fixtures after an intentional encoding change:

```sh
dart run ios/CelechronWatchTests/generate_qr_fixtures.dart \
  > ios/CelechronWatchTests/reference_matrices.json
```

Always review the resulting matrix diff. Fixture regeneration must not be used merely
to make a failing encoder test pass.

The automated suite establishes QR conformance and software-decoder compatibility.
Before release, a real campus payment code should additionally be checked on the
smallest supported Apple Watch with the actual payment-terminal scanner, because
display brightness, glare, camera focus, and terminal firmware are outside the unit
test environment.
