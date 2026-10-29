# digital.conf — 한 줄 OUTBOUND 로그 최종 설정

업데이트: 2026-10-29

현재 기준은 **시간값까지 같은 줄에 기록된 OUTBOUND 로그**입니다. 예전 REQUEST DATA / RESULT DATA 멀티라인 방식은 현재 설정에 사용하지 않습니다.

## 바로 사용할 파일

- [전체 digital.conf](digital.conf): input → 신규 OUTBOUND → 기존 VAN → 공통 처리 → output 전체.
- [설정·적용 가이드](GUIDE.md)
- [Logstash 필터 설명과 괄호 배치](LOGSTASH_GUIDE.md)
- [Filebeat 단일 행 입력 가이드](FILEBEAT_GUIDE.md)
- [실로그 재현 검증 결과](VALIDATION.md)
- [가변 형식과 지원 범위](VARIABLE_FORMATS.md)

**비밀번호 4곳은 보안상 00000000입니다. 적용 전에 기존 실제 비밀번호로 교체하세요.** 공개 저장소에 실제 비밀번호·원본 로그·실제 거래값은 올리지 않았습니다.

## 현재 동작

- 파일 조건: [log][file][path]에 epay가 포함된 경우. 필터와 Elasticsearch output에 같은 조건을 사용합니다.
- 요청: 시간·레벨·로거·status·헤더 업체코드·헤더 TR_ID·URL을 추출하고, URL 뒤의 모든 key=value를 request_data.*에 저장합니다.
- 응답: 공통 헤더를 추출하고, 표시용 바깥 대괄호를 제외한 JSON 객체 전체를 result_data.*에 저장합니다.
- URL 필드는 첫 & 앞까지입니다. 뒤의 파라미터는 버리지 않고 request_data에 파싱합니다.
- 공통 헤더 TR_ID는 요청·응답 매칭용입니다. 본문 TR_ID와 혼동하지 않습니다.
- 원문 값은 인코딩·디코딩하지 않습니다. 요청의 URL 인코딩과 응답의 디코딩 상태를 그대로 보존합니다.
- log_timestamp를 날짜로 변환합니다. **@timestamp에는 복사하지 않습니다.** 따라서 @timestamp 기반 Kibana 조회·인덱스 날짜는 입력 이벤트의 기존 시간을 사용합니다.
- 일반 로그만 제외합니다. 대상의 grok / kv / json / date 실패는 태그와 원문을 보존합니다.
- 멀티라인·aggregate·구간 버퍼·Ruby 필터를 사용하지 않습니다. 이 신규 분기는 워커 1을 요구하지 않습니다.

## 검증 범위

최신 첨부 로그 1,229개 물리적 줄 중 요청 2건·응답 2건 모두 추출·날짜 해석 성공, 공통 헤더 매칭 2쌍 일치입니다. 비대상 1,225줄은 선택 대상에서 제외됐습니다.

이는 **오프라인 정규식·KV·JSON·날짜 변환 재현 검사**입니다. 실제 Logstash/JRuby 실행, Elasticsearch 매핑 적용, 운영 처리량 시험은 완료한 것이 아닙니다. 사용자는 앞선 저장 미표시 현상이 Kibana 시간 범위 차이였음을 확인했습니다.

## 적용 전 필수 확인

1. 현재 conf를 백업하고 비밀번호를 복원합니다.
2. 실제 원본 로그 경로가 필터/output의 epay 조건과 일치하는지 확인합니다. digital.conf라는 설정 파일명은 log.file.path 조건과 무관합니다.
3. 기존 신규 파싱 분기를 교체합니다. 중복 추가하지 않습니다. 기존 VAN·공통 처리와 output은 유지합니다.
4. Filebeat 전용 input의 예전 multiline과 REQUEST DATA/RESULT DATA용 include_lines를 제거합니다. 다른 파일 input은 변경하지 않습니다.
5. log_timestamp의 Elasticsearch 매핑을 확인합니다. 기존 text 매핑은 Logstash date 필터로 date 타입으로 바뀌지 않습니다.
6. 실제 Logstash 설치 폴더에서 다음 명령으로 검사합니다.

~~~bash
./bin/logstash -t -f conf/digital.conf
~~~

괄호 주석 [MESSAGE] END → [FILE] END 뒤에 기존 VAN else if가 이어지고, 전체 [FILTER] END는 모든 공통 처리 뒤에 있습니다.

이 폴더 밖의 bgf.conf / card.conf / frontback.conf 자료는 이번 업데이트에서 변경하지 않습니다.
