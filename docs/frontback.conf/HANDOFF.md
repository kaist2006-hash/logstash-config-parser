# frontback.conf 인수인계

## 현재 완료 상태

공식 `나이스헤더` Excel을 기준으로 FrontChannelMgr와 BackChannelMgr의 공통 영역을 정확히 120바이트로 수정했습니다. offset 120 이후는 불확실한 업무 본문이므로 파싱·분류·복제하지 않습니다.

기존 132바이트 추정 스키마의 `transaction_id`, `institution_code`, `partner_code`, `inner_kind` 등은 제거했습니다. 현재 결과는 `[frontback_detail][nice_header]` 아래 문서 필드 12개만 제공합니다.

## 최종 검증

- Logstash 8.17.6 `config.test_and_exit`: 통과
- 합성 계약: 8/8 통과
- 실로그: Back 24,715건 + Front 992건 = 25,707건
- 상태: ok 25,707 / warning 0 / failed 0
- message/path 변경: 0 / 0
- `nice_number`와 `nice_serial_no` 불일치: 0
- 1-worker/4-worker digest: 동일
- Beats/Elasticsearch 연결: 수행하지 않음

최종 재생 결과는 `validation/real-header120-opt-w1.json`, `validation/real-header120-opt-w4.json`입니다.

## 운영 반영 전 필수 확인

1. `FRONTBACK_PARSER_DIR`에 Ruby·JSON·conf를 함께 배치합니다.
2. ES 비밀번호는 Logstash keystore로 주입합니다.
3. `frontback_detail.mapping.json`을 기존 인덱스 템플릿에 병합합니다.
4. 운영 파이프라인 reload 또는 restart 후 `_frontback_parse_failure`, `_frontback_parse_warning` 태그를 모니터링합니다.
5. 초기 반영은 한 노드 또는 짧은 구간에서 canary로 확인한 뒤 전체 적용합니다.

## 후속 상세 파싱 원칙

offset 120 이후는 현재 범위 밖입니다. 추후 상세 파싱은 기관·업무별 규격 문서와 요청/응답 실로그가 정확히 매칭될 때 별도 프로파일로 추가해야 합니다. 공통 헤더 JSON에 임의 필드를 추가하지 않습니다.
