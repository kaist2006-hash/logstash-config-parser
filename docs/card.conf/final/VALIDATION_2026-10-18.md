# 카드 상세파서 적용 설정 재검증 (2026-10-18)

## 적용 블록과 원인

사용자가 적용한 Ruby 블록은 `specs_path`만 전달한다. `2026-10-11.final6` RB의 기본 `text_encoding`은 UTF-8이었지만, 당시 실로그 재생기는 `ISO-8859-1`을 명시했다. 따라서 이전 검증 결과는 실제 적용 블록의 기본값을 검증한 것이 아니었다.

실로그의 신한 MS 6,283건, 우리 29,060건, 현대 MS 595건, BC MS 869건에는 8비트 바이트가 있었다. UTF-8 기본값으로 재생하면 현대 MS 391건과 신한 MS 2건의 `ok`가 `fallback`으로 바뀌었다. 현대 MS 391건의 추출 필드도 기준 설정과 달랐다. 차이가 발생한 필드는 `retrieval_reference` 391건, `terminal_id` 391건, `currency_code` 391건, `response_code` 362건, `merchant_number` 70건이다. 여기의 건수는 필드별 건수여서 합산하지 않는다.

`2026-10-18.final7`은 RB의 기본 `text_encoding`을 실로그 검증에 사용한 `ISO-8859-1`로 맞췄다. 전체 `card.conf`의 기본값도 동일하게 수정했다. JSON의 카드사별 필드 규격은 변경하지 않았으며 버전만 올렸다. 이제 아래 블록만으로도 해당 기본값을 사용한다.

```logstash
ruby {
  id => "card_detail_parser"
  path => "${CARD_PARSER_DIR}/card_detail_parser.rb"
  script_params => {
    "specs_path" => "${CARD_PARSER_DIR}/card_detail_specs.json"
  }
}
```

이 블록 앞에서 `[@metadata][target_alias]`가 카드사별로 설정되고 `message` 원문이 보존되어야 한다. `CARD_PARSER_DIR`은 수정된 RB와 JSON의 실제 위치여야 한다.

## 검증 방법과 결과

- Logstash 8.17.6 내장 JRuby와 실제 `LogStash::Event` 사용.
- 제공된 `keb_통합.7z`에서 추출한 9개 로그 파일의 후보 행 593,335건 재생.
- Ruby `register`에는 `specs_path`만 전달하여 적용 블록과 같은 기본값 사용. 카드사 `target_alias`는 파일별 경로표에 따라 주입.
- 수정 후 이전 `ISO-8859-1` 명시 검증 보고서와 `counts`, `errors`, `warnings`, `tags`를 전 항목 비교하여 차이 0건 확인.
- `message`와 `target_alias` 변경 0건. `card_detail.fields`가 하나 이상 나온 행 572,637건.

| 로그 | `ok` | `fallback` | `control` | `error` |
|---|---:|---:|---:|---:|
| BC IC | 48,892 | 0 | 7,200 | 42 |
| BC MS | 5,776 | 0 | 7,680 | 0 |
| 현대 IC | 5,474 | 0 | 0 | 0 |
| 현대 MS | 12,324 | 856 | 0 | 0 |
| 하나 통합 | 142,703 | 0 | 0 | 0 |
| 신한 IC | 194,098 | 0 | 0 | 0 |
| 신한 MS | 104,716 | 10,108 | 0 | 0 |
| 삼성 IC | 3,826 | 0 | 0 | 0 |
| 우리 통합 | 48,111 | 1,529 | 0 | 0 |
| **합계** | **565,920** | **12,493** | **14,880** | **42** |

수정 전 적용 블록의 UTF-8 기본값으로 같은 로그를 재생했을 때에는 `ok` 565,527건, `fallback` 12,886건이었다. `error` 42건은 BC IC의 다른 헤더·MTI 조합이고, `control` 14,880건은 정상 제어전문이다. `fallback`은 동일 카드사 규격에서 공통 필드를 확보한 결과이며, 이 실로그의 모든 `fallback`에 추출 필드가 남았다.

## 아직 상세 필드 파싱이 확인되지 않은 카드사

- BC MS는 구형 BCB/BCA/EPT 고정 전문이다. 현재 JSON은 5,776건의 업무 레코드 구조와 7,680건의 제어전문을 검증하지만, 공식 필드별 offset 규격이 없어 `card_detail.fields`를 출력하지 않는다. 따라서 `ok`도 상세 업무 필드 추출을 뜻하지 않는다.
- 국민 MS, 롯데 IC, 농협 IC/MS, 삼성 MS profile은 JSON에서 `enabled=false`다. 실로그 검증 자료가 없어 현재 블록에서는 `disabled`로 기록하고 상세 파싱하지 않는다.
- 국민 IC와 롯데 MS는 `enabled=true`이고 예전 샘플 검증 이력이 있지만, 이번 9개 로그 파일에는 없어 전량 재검증 대상이 아니었다.
- `win_ms` 파일은 `bcc_ms`와 동일한 SHA-256이어서 삼성 MS 실로그로 사용할 수 없다.

실제 운영 환경에서 여전히 기본 필드만 나온다면 해당 이벤트의 `card_detail.parser_version`, `profile`, `status`, `errors`, `warnings`, `log.file.path`를 먼저 확인해야 한다. 특히 `parser_version`이 `2026-10-18.final7`이 아니면 이전 RB/JSON을 읽고 있다. `status=disabled`이면 해당 profile이 비활성 상태이고, BC MS의 `status=ok`이면서 `fields`가 없는 것은 위 구조 검증 단계의 현재 한계다. 원본 로그가 이미 대체 문자(U+FFFD)로 손실되었다면 RB만으로 원래 바이트를 복원할 수 없다.

이 검증은 제공된 로그를 Ruby filter에 재생한 결과다. 운영 서버의 Filebeat/Beats 전달, 기존 conf의 라우팅, 멀티라인 병합 및 실제 운영 로그 자체는 이번 자료만으로 확인할 수 없다.

