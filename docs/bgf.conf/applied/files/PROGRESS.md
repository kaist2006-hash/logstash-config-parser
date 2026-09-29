# bgf.conf 진행 현황

## 2026-09-29 · NICE POS 상세 파서 v15.3 운영본

`docs/bgf.conf/applied/files/`의 상세 파서와 규격을 운영용 v15.3으로 갱신했습니다.

### 반영 내용

- 네이버, 카카오, 페이먼츠, 우정국의 규격별 요청·응답 상세 필드를 분리했습니다.
- 정확한 규격이 일치하면 해당 업체의 상세 필드를 파싱합니다.
- 업체와 요청·응답 방향은 식별되지만 상세 규격이 없으면 `UNKNOWN`으로 표시하고, 해당 방향의 공통 필드만 추출합니다.
- `trade_code = 15`처럼 특정 코드에 고정하지 않고 구조가 일치하는 미등록 전문 전체에 공통 fallback을 적용합니다.
- 불완전하거나 실제 길이가 선언 길이보다 짧은 전문은 정상 fallback과 분리해 `error`로 남깁니다.
- 기존 NICE 고정길이, 사설 규격, 통합 TAG 규격 처리 흐름은 유지했습니다.
- RB는 실행 로직만 남긴 무주석 운영본이며, JSON은 실행에 불필요한 설명 키를 제거한 운영본입니다.

### 운영 경로 매핑

| 업체 | G/W·라인명 |
|---|---|
| 네이버 | `GCHND_0133_A01`, `GCHND_0227_A01`, `GCHND_0241_A01`, `GCHND_0242_A01` |
| 카카오 | `GCHND_0237_A01`, `GCHND_0238_A01`, `GCHND_0239_A01`, `GCHND_0240_A01` |
| 페이먼츠 | `GCHND_0230_A01`, `GNPG1_TCPD_S01` |
| 우정국 | `GCHND_0231_A01` |

### 처리 순서

1. `b_body`에서 실제 전문을 추출합니다.
2. 통합 TAG → 사설 → NICE 고정길이 순서로 형식을 판별합니다.
3. `gateway` 또는 `linename`으로 외부 4개 업체를 식별합니다.
4. 업체·요청/응답·메시지 조건이 정확히 일치하면 해당 상세 schema를 적용합니다.
5. 업체와 방향만 확인되고 상세 schema가 없으면 공통 fallback을 적용합니다.
6. 결과 태그는 정상, `fallback`, `error`로 단순화합니다.

### 검증 결과

- Ruby/JSON 구문 및 로딩 정상
- 전체 22개 schema, 21개 rule, 10개 공통 fallback profile 검증 통과
- 네이버 실로그 7,832건: 4개 포맷 exact 매칭
- 카카오 실로그 455,649건: 정상 응답 매칭, 실제 절단 전문 2건은 `error`
- 페이먼츠 실로그 78,442건 exact 매칭, 미등록 정상 전문 194건은 요청 97건·응답 97건 공통 fallback
- 우정국 실로그 92건: 4개 포맷 exact 매칭
- JSON 규격만 추가하는 확장 검증 및 기존 외부업체 오분류 방지 검증 통과

### 배포 파일

- `applied/files/nice_pos_detail_parser.rb`
- `applied/files/nice_pos_detail_specs.json`

Logstash 설정에서는 위 RB를 호출하고 `script_params.spec_path`에 같은 버전의 JSON 절대경로를 지정합니다.

