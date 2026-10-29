# Filebeat — 멀티라인 없는 단일 행 수집

업데이트: 2026-10-29

로그 생성부에서 시간과 OUTBOUND 헤더·본문을 한 줄로 합친 최신 형식을 사용합니다. Filebeat에서 멀티라인 조합을 하지 않습니다.

## 현재 type: log 입력

[입력 예시 파일](filebeat.epay-log.input.yml)은 전체 filebeat.yml이 아니라 filebeat.inputs에 합치는 입력 목록입니다.

~~~yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /CHANGE_ME/epay.out
~~~

/CHANGE_ME/epay.out은 실제 원본 경로로 바꾸세요. 기존 encoding, input 식별자, registry 관련 정책, output.logstash와 접속 설정은 임의 변경하지 않습니다. 예시에는 encoding을 강제로 지정하지 않았습니다.

현재 Logstash는 경로에 epay가 포함되는지 검사합니다. 실제 파일이 다른 이름/경로라면 필터와 Elasticsearch output의 조건도 같이 맞춰야 합니다.

## 기존 설정에서 제거할 항목

대상 파일 전용 input에 남은 예전 항목만 제거합니다.

- multiline.type / pattern / negate / match / timeout
- filestream의 multiline parser
- REQUEST DATA 또는 RESULT DATA 독립행을 찾는 옛 include_lines

현재 예시는 include_lines를 사용하지 않고 한 줄씩 전달하며, 대상 선별은 Logstash가 담당합니다. 다른 파일을 읽는 input의 설정은 변경하지 않습니다.

## 다중 input

기존 VAN 파일 input과 신규 로그 input의 paths가 겹치지 않게 유지합니다. 같은 파일을 두 input에서 동시에 읽게 만들지 마세요. 새 입력 예시를 적용한다고 기존 파일을 다시 읽는 registry를 삭제하지 마세요.

기존 input에 다른 파일도 함께 등록되어 있다면 대상 파일만 전용 input으로 분리하되, input 유형 변경이나 registry 초기화를 수집 변경과 동시에 임의 수행하지 않습니다.

## filestream 대안

[filebeat.epay-filestream.input.yml](filebeat.epay-filestream.input.yml)은 이미 filestream을 사용하는 경우의 대안 예시입니다. 현재 log 입력을 이번 변경 때문에 filestream으로 이관하라는 뜻이 아닙니다. 두 예시 중 실제 사용 중인 유형 하나만 적용합니다.

## 운영 확인

- 원본 파일이 실제 한 줄인지 확인합니다. 편집기 자동 줄바꿈과 실제 줄바꿈은 다릅니다.
- 파일의 문자 인코딩과 Filebeat encoding 설정을 일치시킵니다. 첨부 검증 파일은 CP949로 정상 해석됐으며 UTF-8 strict 해석은 실패했습니다. 운영 파일의 encoding이 같다고 단정하지 않습니다.
- 출력 장애·전송 재시도로 인한 중복 가능성은 별개의 문제입니다. 이번 필터는 영구 중복 제거를 제공하지 않습니다.
- 기존 포트 9900과 Logstash 연결 설정은 전체 digital.conf에 보존돼 있습니다.
- 실제 Filebeat 환경에서 설정 검사와 전송 검증이 필요합니다.

[Logstash 가이드](LOGSTASH_GUIDE.md) · [검증 결과](VALIDATION.md)

참고: [Filebeat 8.17 log input](https://www.elastic.co/guide/en/beats/filebeat/8.17/filebeat-input-log.html)
