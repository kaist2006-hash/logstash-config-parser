# bgf.conf · 설정이 실제로 들어간 가이드

**이제 네 파일 안에 예시 설정이 들어 있습니다.** 아래 파일을 열어 GUIDE 번호를 찾으면 추가한 위치를 바로 볼 수 있습니다.

| 예시가 들어간 전체 파일 | 실제로 넣은 내용 |
|---|---|
| [nice_pos_detail_specs.json](applied/files/nice_pos_detail_specs.json) | 새 NICE 요청·응답, 사설 버전, TAG, 기존 폰타 코드, 가변길이 |
| [nice_pos_detail_parser.rb](applied/files/nice_pos_detail_parser.rb) | 위 JSON과 연결되는 기존 처리 위치에 주석 |
| [nice_pos_fs_specs_.json](applied/files/nice_pos_fs_specs_.json) | 새 업체 경로·매핑, 기존 필드·SK 코드 추가 |
| [nice_pos_fs_parser_.rb](applied/files/nice_pos_fs_parser_.rb) | 새 업체 when 분기와 실행 함수 추가 |

## 먼저 볼 예시: 새 FS 업체 하나 추가

- [① JSON 업체 경로](applied/files/nice_pos_fs_specs_.json#L23)
- [② JSON 요청·응답 매핑](applied/files/nice_pos_fs_specs_.json#L35)
- [③ Ruby case 안 호출 분기](applied/files/nice_pos_fs_parser_.rb#L83)
- [④ Ruby 맨 아래 실행 함수](applied/files/nice_pos_fs_parser_.rb#L410)

위 네 곳이 같은 이름으로 실제 연결되어 있습니다. JSON 값만 만들어 놓고 끝나는 예시가 아닙니다.

## 원본과 추가 위치를 나란히 보기

[START.html](applied/START.html)을 내려받아 브라우저에서 열면, 예시와 단계별로 원본/사본의 해당 줄을 비교합니다. HTML 안에 네 파일이 포함되어 있어 단독으로 사용할 수 있습니다. GitHub에서는 HTML 코드가 표시됩니다.

| 검색 번호 | 예시 |
|---|---|
| GUIDE_D01 | 새 NICE 요청·응답 schema/rules |
| GUIDE_D02 | 새 사설 versions/schema/rule |
| GUIDE_D03 | 새 통합 Q99 TAG |
| GUIDE_D04 | 기존 BGF text 배열에 PTX 추가 |
| GUIDE_D05 | 가변길이 dynamic 추가 |
| GUIDE_F01 | 동일 GSX 구조의 새 경로 |
| GUIDE_F02 | GSX 응답에 com_83 매핑 추가 |
| GUIDE_F03 | SK 기존 금액 처리에 T1 추가 |
| GUIDE_F04 | 새 FS 업체의 JSON/Ruby 네 곳 연결 |

[샘플 12개](applied/samples/events.json) · [Ruby 검증 스크립트](applied/verify_examples.rb) · [정적 확인 결과](applied/VALIDATION.md)

교육용 사본이며, 가정한 코드·필드 위치를 실제로 넣은 것입니다. 원본·운영 서버·bgf.conf는 변경하지 않았습니다. detail Ruby는 기존 기능으로 처리 가능해 주석만 추가했고, FS Ruby는 신규 분기·함수가 실행 코드로 들어갔습니다. Ruby/Logstash 실행 검증은 하지 못했습니다.
