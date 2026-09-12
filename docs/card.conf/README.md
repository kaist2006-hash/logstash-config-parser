# 카드 전문 파서 검증 후보 — Logstash 8.17.6

이 묶음은 **원시 로그 → Ruby/JSON 상세 파싱** 검증용입니다. 운영 서버·Beats·Elasticsearch에는 접속하거나 설정을 적용하지 않았습니다. BGF 파서를 복사하지 않고 `card.conf → card_detail_parser.rb → card_detail_specs.json` 구조로 작성했습니다.

**1차 결과:** 국민 IC 302,191건은 모두 프레임 해석 완료(문서 차이 경고 포함). 롯데 MS 51,766건 중 23,989건 정상, 나머지는 규격 누락/잘린 로그 등으로 부분 해석 또는 실패입니다. 전체 결과는 [검증 보고서](validation/REPORT.md), 다른 채팅에서 이어갈 내용은 [작업 인수인계](HANDOFF.md)를 먼저 보세요. 운영 반영 전 후보이며 나머지 카드사 전체 파싱 완료본은 아닙니다.

## 파일과 변경 범위

- `card.conf`: 제공한 conf에 Ruby 필터 하나 추가. Beats 8801, 기존 필터, 16개 alias 분기, 3개 ES host 구조, `ilm_enabled=false`, `manage_template=false` 유지. 내부 주소는 공개 저장소 노출을 막기 위해 환경변수 참조로 변경.
- `card_detail_parser.rb`: 바이트 단위 전문·비트맵·가변 길이·선택 필드·EMV TLV 구조 해석.
- `card_detail_specs.json`: 카드사/서비스별 14개 프로파일, 길이 규칙, 내보낼 필드, 원문 파일명/SHA256, 보류 사유.
- `card_detail.mapping.json`: 새 `card_detail` 필드의 **매핑 본문 예시**. 기존 인덱스나 템플릿에 자동 적용하지 않음.
- `validation/`: 실제 실행 결과와 검증 보고서. 원시 전문 값은 제외.
- `tests/`: 합성 오류 테스트와 실제 8.17.6 Event/JRuby를 사용하는 오프라인 재생 도구.

기존 평문 비밀번호는 복사하지 않고 `${CARD_ES_PASSWORD}` 참조로 변경했습니다. 내부 주소는 `${CARD_ES_HOST_1}`, `${CARD_ES_HOST_2}`, `${CARD_ES_HOST_3}`이며 운영할 때 원본 conf의 각 URL 값을 넣어야 합니다. `message`, `a_header`, `b_body`, `gateway`, `status`는 기존 동작을 유지합니다. **상세 파서는 기존 `b_body`가 아니라 원본 `message`를 읽습니다.** 기존 dissect의 linename 분기는 `] `를 기준으로 본문이 분리되는 특성이 있어 상세 파싱의 입력으로 사용하지 않습니다.

## 현재 활성화 범위

| 카드사 | MS alias / 프로파일 | IC alias / 프로파일 | 상세 파싱 기본값 |
|---|---|---|---|
| 국민 | s_service_cnb_ms / kb_ms | s_service_cnb_ic / kb_ic | IC만 활성화 |
| 롯데 | s_service_ltc_ms / lotte_ms | s_service_ltc_ic / lotte_ic | MS만 활성화, 부분 실패 존재 |
| 농협 | s_service_nlc_ms / nh_ms | s_service_nlc_ic / nh_ic | 비활성화 |
| 삼성 | s_service_win_ms / samsung_ms | s_service_win_ic / samsung_ic | 비활성화 |
| 신한 | s_service_lgc_ms / shinhan_ms | s_service_lgc_ic / shinhan_ic | 비활성화 |
| 현대 | s_service_din_ms / hyundai_ms | s_service_din_ic / hyundai_ic | 비활성화 |
| 우리 | s_service_wrc_sum / woori_sum | 통합 | 비활성화 |
| 하나 | s_service_keb_sum / hana_sum | 통합 | 비활성화 |

BC의 기존 MS/IC 두 alias도 그대로 남습니다. BC 규격이 없어 `unconfigured`로 표시할 뿐 기존 수집 경로를 바꾸지 않습니다. 삼성의 WIN 경로 등 기관 식별은 기존 설정과 첨부 자료에 따른 것이며 다른 실로그 확인 때 다시 대조해야 합니다.

비활성화는 **추가 상세 파싱만** 중단합니다. 원래 conf의 수집·분류·저장 조건을 중단하지 않습니다. 나머지 프로파일은 문서 기반 초안이지 운영 검증 완료본이 아닙니다. `kind: blocked`는 문서 충돌/확인 부족 때문에 의도적으로 멈추는 필드이며, 미정의 필드를 무시하고 뒤쪽 값을 잘못 맞추지 않습니다.

## 파싱 결과의 의미

새 필드는 `[card_detail]` 아래에만 생성됩니다.

| status | 의미 |
|---|---|
| ok | 전체 프레임 소비, 선택 필드와 TLV 구조 검사 통과, 경고 없음 |
| warning | 프레임 소비 완료. 문서 최대길이/헤더 또는 기록 len과 다른 점 존재 |
| partial | 일부 필드까지만 해석했거나 필드값/후행 바이트 오류 존재 |
| failed | 전문 외곽/인코딩/초기 필드를 해석하지 못함 |
| disabled | 해당 프로파일 상세 파싱 비활성화 |
| unconfigured | 설정된 규격 없음. 예: 기존 BC 경로 |

`frame_status=complete`는 업무상 승인 성공을 뜻하지 않습니다. `response_code`도 전문에서 추출한 문자열일 뿐 `00` 등의 의미를 임의로 통합하지 않습니다. 업무별 필수 비트 조합·금액 합계·승인/취소 짝·암호 검증까지 인증한 것은 아닙니다.

`partial`의 `fields`는 오류 위치 이전에 읽을 수 있었던 값이며 정상 거래 집계에는 섞지 마세요. 기본 성공 조회는 `card_detail.status:ok`; 국민 실로그의 문서 차이를 수용한 뒤에만 `warning`을 포함하세요. `_card_detail_parse_failure`, `_card_detail_warning`, `_card_detail_exception`, `_card_detail_target_collision` 태그도 사용할 수 있습니다. 실패해도 추가 파서는 원문이나 이벤트를 삭제하지 않습니다. 기존 conf가 거래 로그가 아닌 행을 drop하는 동작은 그대로입니다.

## 내보내는 값과 보호 범위

MTI, 비트맵, 거래구분, 거래금액, 전송일시, 추적번호, POS 모드, 응답코드, 가맹점/단말기, 통화 등을 규격에 따라 선택 출력합니다. 국민 IC는 F118의 국가·할부·가맹점·승인번호·사업자·단말기·세금·봉사료, F61의 fallback/모델, F90의 원거래 정보도 선택 출력합니다. 롯데 MS는 할부·승인번호·사업자·기관코드·수수료 원문과 SETTLE/BILLING 금액을 추가합니다. 롯데 F5/F6은 할부값 38 등 업무 조건에 따라 봉사료/세금이 아닌 지원금 의미가 되므로 `settlement_amount`/`billing_amount`로 보존합니다.

식별 코드와 금액 원문은 **문자열**로 유지해 앞자리 0, 자리수, 금액의 단위 가정을 보존합니다. 현재 금액 필드는 집계용 숫자형이 아니므로 합계가 필요하면 업무 단위를 정한 뒤 별도 numeric 필드를 추가하세요. 시간은 연도를 추정해 `@timestamp`로 덮어쓰지 않습니다.

PAN, Track2, 유효기간, PIN, CVC, cryptogram, 주민번호 등의 원문은 상세 필드로 다시 내보내지 않습니다. 필드 경계를 지나가거나 TLV 길이를 확인할 뿐 복호화하지 않습니다. **기존 message/a_header/b_body에는 민감정보가 그대로 있을 수 있습니다. 이 설정은 기존 저장 데이터의 마스킹 작업이 아닙니다.**

## 인코딩: 가장 중요한 재현 조건

국민 IC는 본문이 HEX이므로 바이트 복원이 명확합니다. 롯데 MS는 텍스트처럼 보이지만 일부 전문에 실제 이진 바이트가 포함되어 있습니다.

이번 로컬 검증은 파일을 바이너리로 읽은 뒤 ISO-8859-1 → UTF-8로 옮겨 Event에 넣고, 파서는 반대로 ISO-8859-1로 복원했습니다. **ISO-8859-1은 한글 해석용이 아니라 모든 원본 바이트를 보존하기 위한 테스트 운반 인코딩입니다.** 한글 필드를 임의 복원해 출력하지 않습니다.

운영 conf의 기본 `CARD_TEXT_ENCODING`은 UTF-8입니다. 실제 수집 단계에서 무엇으로 디코딩하는지에 맞춰야 하며, 단순히 ISO-8859-1로 바꾸면 모든 입력이 고쳐지는 것은 아닙니다. 수집 전에 U+FFFD로 치환된 바이트는 복구할 수 없어 `lossy_input_encoding` 실패 처리합니다. 원본 자체가 잘리거나 행이 깨진 롯데 전문도 파서에서 복구할 수 없습니다. HEX 기록본 또는 손실 없는 message 추출본이 있으면 그 자료로 재검증할 수 있습니다.

## 오프라인 재실행 — ES 불필요

Python 3 표준 라이브러리와 풀어서 둔 Logstash **8.17.6** 배포본만 사용합니다. 인터넷 다운로드나 ES 연결은 하지 않습니다.

```text
python tests/run_core.py --logstash-home "C:/tools/logstash-8.17.6" --report "C:/tests/contracts.json"

python tests/run_core.py --logstash-home "C:/tools/logstash-8.17.6" --logs-dir "C:/tests/original-logs" --workers 1 --report "C:/tests/real-w1.json"

python tests/run_core.py --logstash-home "C:/tools/logstash-8.17.6" --logs-dir "C:/tests/original-logs" --workers 4 --report "C:/tests/real-w4.json"
```

로그 폴더에는 `GICNB_X25A_P01*.log`, `GCLTC_X25A_P01*.log`가 각각 하나씩 있어야 합니다. 리포트 경로는 매번 새 이름을 쓰세요. 합성 테스트만 실행할 때는 원시 로그가 필요 없습니다. 실제 값이 담긴 golden 비교 fixture는 전달 묶음에서 제외했습니다. 새 카드사 검증은 재생 도구의 대상 경로와 프로파일을 명시적으로 확장한 뒤 진행합니다.

`tests/card.replay.conf`도 제공합니다. 일반 Logstash 파일 input으로 원시 로그를 읽고, **ES 대신 로컬 파일**에 `[card_detail]` 결과만 남깁니다. Filebeat/ES 없이 실행 가능합니다. 이 보조 conf의 프로세스 재생은 이번 Windows 환경의 data lock 접근 문제 때문에 실행 완료 검증 대상에 포함하지 않았습니다. 핵심 Ruby 파서 전체 로그 재생은 위 core 도구로 수행했습니다.

재생 conf 환경변수: `CARD_PARSER_DIR`=이 묶음의 절대 경로, `CARD_TEST_INPUT_DIR`=원시 로그 폴더, `CARD_TEST_DIR`=별도 쓰기 가능한 테스트 폴더, `CARD_TEST_RUN`=매번 새 실행명, `CARD_TEXT_ENCODING`=`ISO-8859-1`. 절대 경로로 `logstash -f .../tests/card.replay.conf --path.data .../test-data`를 지정하세요. 완료 파일 동작은 `log`이며 입력 파일을 삭제하지 않습니다. 출력에는 선택한 가맹점/거래 값이 포함되므로 접근을 제한하세요.

## 나중에 운영 적용할 때의 확인 사항

1. 원본 conf를 백업하고 세 파일(conf/Ruby/JSON)을 같은 버전 묶음으로 관리하세요. 파일을 읽는 계정만 접근하도록 권한을 제한하세요.
2. `CARD_PARSER_DIR` 절대 경로, `CARD_ES_HOST_1/2/3`의 원래 운영 URL, `CARD_ES_PASSWORD` keystore/환경 참조를 준비하세요. 비밀번호를 다시 conf에 적지 마세요.
3. 새 namespace의 기존 매핑 유무를 확인하세요. 제공 매핑은 참고 본문이며, 기존 템플릿을 통째로 덮어쓰는 파일이 아닙니다. 이번 요청에서는 ES 매핑 적용/연결 검사를 수행하지 않습니다.
4. JSON은 register에서 한 번만 읽습니다. JSON 파일만 바꿔도 즉시 반영되는 구조가 아닙니다. 적용 시 pipeline 재시작/명시적 reload가 필요합니다. 먼저 별도 경로에 파일을 완성한 뒤 교체하세요.
5. 국민 문서 차이 및 롯데 미정의/손상 로그 문제를 검토하세요. 나머지는 원시 로그 검증 전에 enabled를 켜지 마세요.
6. 기존 별도 card pipeline에만 넣으세요. 테스트 conf까지 운영 `conf.d/*.conf`에 같이 넣으면 입력/필터/출력이 합쳐지므로 금지합니다. worker/heap/PQ는 이 묶음에서 운영값을 변경하지 않았습니다.

## 안정성 설계

한 번만 읽는 JSON, 필드번호 배열 조회, 초기화 후 재귀 freeze, 이벤트별 로컬 버퍼, 최대 message 크기, 최대 3개 비트맵, 길이·남은 바이트 검사, 제한된 TLV 반복, 예외 시 원문 값 없는 오류코드를 사용합니다. 이벤트마다 JSON 파일을 읽거나 새로운 외부 호출을 하지 않습니다. 비정상 입력 때문에 필드를 임의 이동시키거나 미정의 필드를 추정해서 건너뛰지 않습니다.

Ruby 필터의 외부 스크립트 및 다중 worker 공유 상태 설계는 [Elastic 공식 Ruby filter 문서](https://www.elastic.co/docs/reference/logstash/plugins/plugins-filters-ruby)를 참고했고, 실행 문법은 실제 8.17.6 배포본으로 확인했습니다. 현재 측정치는 로컬 파서+Event+검증 digest 비용을 포함하며 운영 전체 파이프라인 처리량 보증이 아닙니다.
