# CARD FINAL18 적용 안내 — 2026-11-04

사진에서 확인한 FINAL17 / CP949 / recover_lossy_prefix=true 값은 올바릅니다. 이번 보완은 JSON 인코딩 값을 바꾸는 작업이 아닙니다.

## 변경 내용

기존 RB는 추출한 텍스트 전체를 CP949 바이트로 역변환한 뒤 선언 길이로 잘랐습니다. 이미 버리도록 되어 있는 전문 밖의 문자라도 역변환할 수 없으면 `input_encoding_not_reversible`로 중단될 수 있습니다.

FINAL18은 기존 `trim_to_declared_length`가 켜진 일반 텍스트 전문에서, 선언 길이까지 전부 ASCII여서 문자 위치와 바이트 위치가 같음을 확인한 경우에만 변환 전에 경계를 자릅니다. 길이는 이벤트의 len 값으로 읽으며 985로 고정하지 않습니다. 경계 안의 비정상 데이터는 기존 필드 검증을 거칩니다. 멀티바이트 구간이 들어 있으면 이 선행 절단을 적용하지 않습니다.

카드사 16개 프로필의 필드 규격과 농협 `rest` 정책은 그대로입니다. JSON은 버전만 `2026-11-04.final18`로 변경했습니다. 새 공개 진단 필드와 script_params 옵션을 추가하지 않았습니다.

## 적용

1. 기존 CARD_PARSER_DIR의 card_detail_parser.rb와 card_detail_specs.json을 이 배포본의 두 파일로 함께 교체합니다.
2. Filebeat의 encoding: euc-kr과 현재 잘 동작하는 헤더·바디 분리, 카드사 라우팅, input/output 설정은 유지합니다.
3. Logstash 파이프라인을 재시작하거나 설정을 재로딩합니다. JSON은 register 시 한 번 읽으므로 파일만 덮어쓰면 현재 실행 인스턴스에 즉시 반영되지 않습니다.
4. 새로 수집한 같은 농협 IC 이벤트의 card_detail.status / errors.code / tags를 비교합니다. 기존 Elasticsearch 문서는 자동으로 바뀌지 않습니다.

```logstash
ruby {
  id => "card_detail_parser"
  path => "${CARD_PARSER_DIR}/card_detail_parser.rb"
  script_params => {
    "specs_path" => "${CARD_PARSER_DIR}/card_detail_specs.json"
  }
}
```

버전은 기본 minimal 출력에서 @metadata.card_detail_parser_version에 기록됩니다. script_params에 text_encoding을 별도로 지정했다면 JSON보다 그 값이 우선합니다. 이 배포본에는 별도 지정이 필요 없습니다.

## 검증 범위와 남은 확인

농협 IC 전체 원본 111,352건의 공개 결과와 tags는 FINAL17과 동일합니다: ok 98,855 / fallback 12,497 / error 0. 16개 프로필의 실제 Logstash 표본은 입력 990건 / 출력 984건이며 기존과 결과 차이가 없습니다. 이 가운데 2건은 의도적으로 만든 비정상 입력이고 실제 소스 표본 982건의 앞단 필터 오류는 0건입니다.

사진과 대조한 원본 5개에 두 종류의 디코딩을 적용한 9개 사례는 모두 필드 22개와 EMV 12개를 보존한 ok입니다. 이 중 기존 WHATWG 디코딩 재현에서 발생한 인코딩 오류 2건은 error에서 ok로 바뀌었습니다. 전문 밖 변환 불가 문자 6개 사례, 전문 안 손상 3개 사례, 짧은 본문 1개 사례, 멀티바이트 rest 1개 사례도 확인했습니다. 기존 출력 계약 43개와 삼성 가변 필드 160개 / 음성 경계 7개 검증을 통과했습니다.

이는 운영 Filebeat→Elasticsearch에 직접 접속한 시험이 아닙니다. 원본의 CP949 및 Go 테이블 기반 디코딩에서는 기존 FINAL17도 ok였습니다. 따라서 운영의 변환 후 message JSON을 확보하지 않은 상태에서 사진의 8건 모두를 동일 원인으로 확정하거나 운영 해결을 완료했다고 주장하지 않습니다. 이 보완은 실제로 재현한 전문 밖 변환 오류 경로를 막습니다.

기존 카드사별 미수령 규격과 미관측 변형에 대한 제한은 FINAL17 검증 문서 그대로입니다. 이번 결과는 모든 카드사 전문의 전체 재생을 새로 수행했다는 의미가 아닙니다.
