# REQUEST DATA + RESULT DATA 검증

검사일: 2026-10-23

## 대상과 방법

Filebeat 날짜·시간 시작 경계, 빈 줄 제외 및 REQUEST DATA/RESULT DATA include_lines를 Python에서 재현했습니다. 생성된 digital.conf의 실제 grok 패턴을 대응시켜 요청 kv 상당 처리·응답 JSON 파싱을 검사했습니다. 응답 TR_ID 인코딩에는 실제 Java URLEncoder를 사용했습니다.

원본의 구간 제목 위치로 독립 추출한 요청·RESULT 응답 값과 비교했습니다. 실제 Filebeat/Logstash 실행 결과는 아닙니다.

| 항목 | 결과 |
|---|---:|
| 원본 줄 | 377,805 |
| 날짜 경계 레코드 | 48,376 |
| 선택한 레코드 | 2,002 |
| REQUEST 요청 | 1,056 |
| RESULT 응답 | 946 |
| POST RESPONSE DATA 선택 | 0 |
| 한 줄 응답 | 758 |
| 5줄 응답 | 181 |
| 6줄 응답 | 7 |
| 유효한 응답 JSON | 946 |
| 빈 배열 응답 | 7 |
| 독립 추출값 비교 | 모두 동일 |
| 완성 이벤트 순서를 섞은 뒤 비교 | 동일 |
| 대상 레코드 최대 줄 | 11 |
| 대상 레코드 최대 UTF-8 바이트 | 1,124 |
| 전체 레코드 최대 줄 | 51 |
| 인코딩으로 바뀐 응답 TR_ID | 488 |
| 바뀐 값 중 요청 TR_ID 집합에 존재 | 488 |
| 전체 응답 TR_ID 중 요청 집합에 존재 | 517 |
| 별도 구조 검사 | 16개 통과 |

본문 5줄 응답 181건과 6줄 응답 7건도 Filebeat 조합 뒤 한 이벤트로 파싱했습니다. 빈 배열 []은 TR_ID 없이 그대로 보존합니다.

## 수집 범위 변경의 영향

원본 RESULT DATA는 946건, POST RESPONSE DATA는 1,049건입니다. JSON을 파싱해 키 순서·표시 공백을 정규화한 뒤 출현 횟수까지 비교하면:

- 내용이 같은 응답 출현: 939건.
- RESULT에만 대응되는 출현: 7건, 모두 빈 배열.
- POST에만 대응되는 출현: 110건.

두 응답 구간을 함께 수집하지 않도록 바꿨지만, 전송 재시도 등으로 발생하는 중복까지 제거하는 설정은 아닙니다. TR_ID 집합 비교도 1:1 거래 결합 검증은 아닙니다.

## 추가 수정과 별도 검사

실로그에 종료 별표 행이 연속으로 나오는 구간이 있어, 응답 캡처를 GREEDYDATA에서 DATA로 변경했습니다. multiline 정규식에서 본문을 첫 종료 구분선까지만 가져오므로 구분선이 JSON에 섞이지 않습니다.

한 줄 배열, 빈 배열, 종료 구분선 반복, 다음 줄 닫는 대괄호, 중첩·여러 줄 JSON, RESULT_CODE 없는 응답, CRLF, POST RESPONSE DATA 제외, 단독 JSON 제외, 단독 URL 제외, 일반 로그 제외, JSON 문법 오류, 닫는 대괄호 누락, 종료 구분선 누락, query 없는 URL, 빈 query 값 보존의 16개 검사를 수행했습니다.

## 한계와 정적 비교

- 기존 요청 패턴·kv·응답 JSON target·TR_ID 인코딩은 유지했습니다.
- 기존 VAN·input·output 및 공개용 임시 password 네 곳을 유지했습니다.
- aggregate·map·Logstash 본문 조합이 없습니다.
- 정적 괄호 검사는 실제 Logstash -t를 대신하지 않습니다.
- 실제 Filebeat/Logstash 실행, 부하, 파일 회전·registry·재시작·본문 도착 간격과 timeout은 검증하지 않았습니다.
- 실제 Filebeat input 유형·ID·경로·encoding을 확인해 예시를 병합해야 합니다.
