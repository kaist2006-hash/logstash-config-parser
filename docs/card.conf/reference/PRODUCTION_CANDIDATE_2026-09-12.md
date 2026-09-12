# Card parser production candidate - 2026-09-12

## 현재 상태

- Logstash target: 8.17.x
- Parser: `card_detail_parser_v2.rb`
- Base spec: `card_detail_specs.json`
- TAPS spec overlay: `card_detail_specs_taps_overlay.json`
- Pipeline: `card.conf`
- Default enabled profiles: `kb_ic,lotte_ms`

## 실로그 검증

### KB IC

- physical rows: 453,297
- selected S/R rows: 302,191
- frame complete: 302,191
- partial: 0
- failed: 0
- OUT(S): 151,100 / complete 151,100
- IN(R): 151,091 / complete 151,091

Warnings are retained for document-vs-real-log length differences such as F55/F60. Warning does not mean frame parse failure.

### Lotte MS

- physical rows: 51,818
- selected get/put rows: 51,766
- frame complete: 46,984
- partial: 1,918
- failed envelope: 2,864
- OUT(put): 25,883 / complete 23,033 / partial 3 / failed 2,847
- IN(get): 25,883 / complete 23,951 / partial 1,915 / failed 17

Remaining partials are source-log anomalies retained deliberately:

- truncated F35: 1,915
- invalid numeric F49: 3

The previous unknown F57/F61 failures were resolved from the 20230321 Lotte MS specification. Lotte-only declared-length trimming and the observed 0420 trailing F61 omission rule are profile-scoped and generate warnings.

## Optimization review

- JSON files are loaded only in Ruby `register()`.
- No per-event file/network I/O.
- Profile field specifications compile into an Array indexed by ISO8583 field number.
- Regexes and prefix widths are prepared once at register time.
- Parsed configuration and lookup structures are frozen before event processing.
- Unknown/blocked/truncated fields stop parsing before offsets can drift.
- Sensitive card/track/PIN data are consumed for boundaries but not exported.

## Common field normalization

`card.conf` now copies equivalent values into BGF-compatible common field paths without removing the original parser fields. This is additive and does not alter bitmap/offset/length parsing.

See `reference/CARD_COMMON_FIELDS.md`.

## Production gate

This package is a production candidate, not a claim that it has already been executed on the user's production Logstash host.

Before production cutover on the actual server:

1. Run Logstash `--config.test_and_exit` with the actual environment variables and paths.
2. Confirm the JSON/Ruby files are readable by the Logstash service account.
3. Start with `CARD_ENABLED_PROFILES=kb_ic,lotte_ms` only.
4. Replay/sample-check both directions and confirm `_card_detail_exception` remains zero.
5. Confirm the new `[card_detail][detail]`, `[card_detail][iso8583]`, `[card_detail][terminal]` object paths do not conflict with an existing Elasticsearch mapping.
6. Check Logstash worker utilization, queue backpressure and event rate after enabling the Ruby filter.
7. Keep the previous card.conf/package available for immediate rollback.

Profiles without real logs remain configured but disabled by default. Their disabled state reflects validation coverage, not missing documentation.
