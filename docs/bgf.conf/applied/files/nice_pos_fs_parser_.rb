# frozen_string_literal: true
# GUIDE_START: 교육용 사본. GUIDE_F04_3/4는 실제 추가 코드, F01/2/3는 기존 처리 위치 주석.

require "json"

# NICE POS FS parser
# 역할: FS 전문을 com_*로 분리하고 JSON 규격을 이용해 nice_pos 공통필드를 생성한다.
# 흐름: JSON 1회 로드(register) -> 업체 판별 -> FS 분리 -> 업체별 파싱 -> 공통필드 생성
# 신규 업체: 같은 규격이면 JSON routes만 추가, 다른 규격이면 JSON routes/mappings + RB 분기/함수 추가

# [시작 시 1회] JSON의 업체경로/필드매핑/SK 전문규칙을 메모리에 준비
def register(params)
  spec_path = params["spec_path"]
  raise "spec_path is required" if spec_path.nil? || spec_path.to_s.empty?

  # JSON 전체 규격 로드
  @spec = JSON.parse(File.read(spec_path))

  # com_N -> nice_pos 공통필드 매핑표
  @maps = @spec.fetch("mappings")

  # 로그 경로 -> 업체(GSX/SK/S-OIL) 판별표
  @routes = @spec.fetch("routes")

  # 파싱 후 삭제할 임시필드 목록
  @temporary_fields = @spec.fetch("temporary_fields")

  # SK 전문별 처리대상 정규식 준비
  sk = @spec.fetch("sk")
  @sk_regex = {
    "request_amount_trades" => Regexp.new(sk.fetch("request_amount_trades")),
    "installment_trades" => Regexp.new(sk.fetch("installment_trades")),
    "cancel_trades" => Regexp.new(sk.fetch("cancel_trades")),
    "common_response_trades" => Regexp.new(sk.fetch("common_response_trades")),
    "hk_response_trades" => Regexp.new(sk.fetch("hk_response_trades"))
  }
end

def filter(event)
  # 현재 이벤트에서 업체판별/방향/FS본문에 필요한 값 추출
  path = string_value(event.get("[log][file][path]"))
  status = string_value(event.get("status"))
  body = event.get("b_body")

  # JSON routes를 기준으로 현재 로그의 업체를 판별
  vendor = vendor_for(path)
  return [event] if vendor.nil? || body.nil?

  # [1] FS 제어문자 정리 후 com_9, com_10 ... 생성
  cleaned = body.to_s
                .gsub("\x01", "")
                .gsub("\x02", "")
                .gsub("\x1c", "|FS|")
                .gsub("\x1f", "/")
                .sub(/\x03[0-9]{4}\z/, "")

  parts = cleaned.split("|FS|")
  event.set("b_body", parts)

  parts.each_with_index do |value, index|
    next if value.nil? || value.strip.empty?

    event.set("com_#{9 + index}", value)
  end

  # [2] IN/OUT 값을 nice_pos.direction(request/response)으로 생성
  if status == "IN"
    event.set("[nice_pos][direction]", "request")
  elsif status == "OUT"
    event.set("[nice_pos][direction]", "response")
  end

  # [3] 업체별 규격 처리
  # 신규 규격 업체 추가 시: JSON routes/mappings 등록 후 아래 case와 parse_업체() 추가
  # 기존 업체와 규격이 완전히 같으면 case 추가 없이 JSON routes에 경로만 추가
  case vendor
  when "gsx"
    parse_gsx(event, status)
  when "sk"
    parse_sk(event, status)
  when "soil"
    parse_soil(event, status)
  # >>> GUIDE_F04_3: 실제 추가 1/2 — case vendor 안, 기존 soil 다음에 넣습니다.
  when "guide_shop"
    parse_guide_shop(event, status)
  # <<< GUIDE_F04_3
  # <신규 규격 업체 등록 예시>
  # when "test"
  #   parse_test(event, status)
  end

  # 파싱 판단에만 사용한 임시필드 제거
  @temporary_fields.each { |field| event.remove(field) }

  [event]
end

# 공통 함수: 필드 복사, 업체 판별 등 업체별 파싱에서 재사용

# nil은 그대로 두고, 값이 있으면 문자열로 변환
def string_value(value)
  value.nil? ? nil : value.to_s
end

# 이벤트 필드값 그대로 조회
def value(event, field)
  event.get(field)
end

# 이벤트 필드값을 문자열로 조회
def text(event, field)
  string_value(event.get(field))
end

# source 필드값이 있을 때만 target 공통필드로 복사
def copy_field(event, source, target)
  v = event.get(source)
  event.set(target, v) unless v.nil?
end

# JSON mappings의 매핑그룹을 한 번에 적용
def copy_map(event, name)
  @maps.fetch(name).each do |source, target|
    copy_field(event, source, target)
  end
end

# JSON routes를 기준으로 현재 로그가 어느 업체인지 판별
# >>> GUIDE_F01_READ: 수정 불필요 — JSON routes.gsx의 새 경로를 기존 GSX로 연결.
# GUIDE_F04_1도 여기서 guide_shop으로 판별한 뒤 GUIDE_F04_3으로 갑니다.
# <<< GUIDE_F01_READ
def vendor_for(path)
  return nil if path.nil?

  @routes.each do |vendor, tokens|
    return vendor if tokens.any? { |token| path.include?(token) }
  end
  nil
end

# GSX 승인일시가 허용된 날짜 형식인지 검증
def valid_gsx_datetime?(v)
  return false if v.nil?

  !!(v =~ /\A\d{4}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])(?:[01][0-9]|2[0-3])[0-5][0-9][0-5][0-9]\z/ ||
     v =~ /\A\d{4}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])\z/)
end

# GSX com_21의 RS(0x1E) 구조에서 가맹점번호 추출
def set_gsx_merchant_number(event)
  v = text(event, "com_21")
  return if v.nil?

  match = v.match(/\A[^\x1e]*\x1e[^\x1e]*\x1e[^\x1e]*\x1e([^\x1e]+)\z/)
  event.set("[nice_pos][detail][merchant_number]", match[1]) if match
end

# GSX/GSC 규격 처리

def parse_gsx(event, status)
  # GSX 전문코드(com_11)를 기준으로 취소/일반 승인 레이아웃 구분
  trade = text(event, "com_11")
  copy_field(event, "com_11", "[nice_pos][trade_code]") unless trade.nil?

  # 취소 요청(8xxx)
  if status == "IN" && trade&.match?(/\A8\d{3}\z/)
    copy_map(event, "gsx_cancel_request")

  # 취소 응답(8xxx)
  elsif status == "OUT" && trade&.match?(/\A8\d{3}\z/)
    copy_map(event, "gsx_cancel_response")

    dt = text(event, "com_20")
    event.set("[nice_pos][detail][approval_datetime]", dt) if valid_gsx_datetime?(dt)
    set_gsx_merchant_number(event)

  # 일반 승인 요청(CAT-ID/금액 위치로 정상 레이아웃 확인)
  elsif status == "IN" && text(event, "com_51")&.match?(/\A\d{10}\z/) && text(event, "com_25")&.match?(/\A\d+\z/)
    copy_map(event, "gsx_normal_request")

  # 일반 승인 응답(CAT-ID/금액/응답코드 위치 확인)
  elsif status == "OUT" && text(event, "com_49")&.match?(/\A\d{10}\z/) && text(event, "com_48")&.match?(/\A\d+\z/) && !value(event, "com_82").nil?
    # >>> GUIDE_F02_READ: 수정 불필요 — JSON의 com_83 → coupon_code 매핑도 같이 복사합니다.
    # 이 분기의 CAT-ID/금액/응답코드 판정 위치가 달라지면 해당 조건도 수정해야 합니다.
    # <<< GUIDE_F02_READ
    copy_map(event, "gsx_normal_response")

    dt = text(event, "com_20")
    event.set("[nice_pos][detail][approval_datetime]", dt) if valid_gsx_datetime?(dt)
    set_gsx_merchant_number(event)
  end
end

# SK 표준POS 규격 처리

def parse_sk(event, status)
  # SK com_9 Header에서 전문코드(D1/D2/H1/DW 등) 추출
  com9 = text(event, "com_9")
  sk_trade = nil

  unless com9.nil?
    if (match = com9.match(/([A-Za-z0-9]{2})=/))
      sk_trade = match[1]
    elsif (match = com9.match(/\A\[(?:IN|OUT)\]\s+\[(DW)(?:SK|sk)/))
      sk_trade = match[1]
    end
  end

  event.set("[nice_pos][trade_code]", sk_trade) unless sk_trade.nil?

  # 전문 종류별 CAT-ID 위치 처리
  com10 = text(event, "com_10")
  if !sk_trade.nil? && !%w[DW PL].include?(sk_trade) && com10&.match?(/\A\d{7,16}\s*\z/)
    event.set("[nice_pos][cat_id]", com10.strip)
  elsif sk_trade == "DW" && status == "IN"
    copy_field(event, "com_14", "[nice_pos][cat_id]")
  elsif sk_trade == "DW" && status == "OUT"
    copy_map(event, "sk_dw_response")
  elsif sk_trade == "PL"
    copy_field(event, "com_11", "[nice_pos][cat_id]")
  end

  # 응답 전문의 response_code 위치 처리
  if status == "OUT" && !sk_trade.nil? && !%w[DW PL].include?(sk_trade)
    copy_field(event, "com_11", "[nice_pos][response_code]")
  elsif status == "OUT" && sk_trade == "PL"
    copy_field(event, "com_12", "[nice_pos][response_code]")
  end

  # 요청 전문의 거래금액/세금 추출
  # >>> GUIDE_F03_READ: 수정 불필요 — JSON 정규식에 추가한 T1도 아래 com_13 처리에 들어옵니다.
  # <<< GUIDE_F03_READ
  if status == "IN" && sk_trade&.match?(@sk_regex.fetch("request_amount_trades"))
    com13 = text(event, "com_13")
    if com13&.match?(/\A\d+\/\d+\z/)
      amount, tax = com13.split("/", 2)
      event.set("[nice_pos][detail][transaction_amount]", amount)
      event.set("[nice_pos][detail][tax_amount]", tax)
    else
      copy_field(event, "com_13", "[nice_pos][detail][transaction_amount]")
    end
  end

  # 할부 대상 전문만 할부개월 생성
  if status == "IN" && sk_trade&.match?(@sk_regex.fetch("installment_trades"))
    copy_field(event, "com_12", "[nice_pos][detail][installment_months]")
  end

  # 취소 전문만 원승인번호 생성
  if status == "IN" && sk_trade&.match?(@sk_regex.fetch("cancel_trades"))
    original = text(event, "com_14")
    event.set("[nice_pos][detail][original_approval_number]", original.strip) unless original.nil?
  end

  # 응답 레이아웃에 따라 공통필드/승인일시 원본 추출
  sk_dt = nil
  if status == "OUT" && sk_trade&.match?(@sk_regex.fetch("common_response_trades"))
    copy_map(event, "sk_common_response")
    sk_dt = text(event, "com_14")
  elsif status == "OUT" && sk_trade&.match?(@sk_regex.fetch("hk_response_trades"))
    copy_map(event, "sk_hk_response")
    sk_dt = text(event, "com_14")
  end

  # 발급사명 앞 제어문자 1자리 제거
  issuer = text(event, "com_18")
  if status == "OUT" && sk_trade&.match?(@sk_regex.fetch("common_response_trades")) && issuer&.match?(/\A..+\z/)
    event.set("[nice_pos][detail][issuer_name]", issuer.sub(/\A./, ""))
  end

  # SK 승인일시 YYMMDDhhmmss + 체크자리 형식이면 마지막 1자리 제거
  if sk_dt&.match?(/\A\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])(?:[01][0-9]|2[0-3])[0-5][0-9][0-5][0-9]\d\z/)
    event.set("[nice_pos][detail][approval_datetime]", sk_dt[0, 12])
  end
end

# S-OIL 표준POS 규격 처리

def parse_soil(event, status)
  # S-OIL com_9 Header에서 CAT-ID / 메시지코드 / 서비스코드 추출
  com9 = text(event, "com_9")
  soil_cat = nil
  soil_msg = nil
  soil_trade = nil
  soil_func = nil

  unless com9.nil?
    if (m = com9.match(/\A\[(?:IN|OUT)\]\s+\[\d{4}.{7}(\d{10})\d{10}(.{4})(.{2})\d{10}/))
      soil_cat, soil_msg, soil_trade = m[1], m[2], m[3]
    elsif (m = com9.match(/\A\[(?:IN|OUT)\]\s+\[\d{4}.{7}(\d{9})\d{10}\s(.{4})(.{2})\d{9}\s/))
      soil_cat, soil_msg, soil_trade = m[1], m[2], m[3]
    elsif (m = com9.match(/\A\[(?:IN|OUT)\]\s+\[\d{4}.{7}(\d{7})\d{10}\s{3}(.{4})(.{2})\d{7}\s{3}/))
      soil_cat, soil_msg, soil_trade = m[1], m[2], m[3]
    end
  end

  # Header에서 추출한 CAT-ID / 서비스코드를 공통필드로 생성
  event.set("[nice_pos][cat_id]", soil_cat) if soil_cat&.match?(/\A\d{7,10}\z/)
  event.set("[nice_pos][trade_code]", soil_trade) if soil_trade&.match?(/\S/)

  # Header 서비스코드가 비어있는 70/7C~7F 전문은 Function byte로 구분
  if status == "IN" && !soil_msg.to_s.match?(/\S/) && !soil_trade.to_s.match?(/\S/) && !com9.nil?
    if (m = com9.match(/.*\d{12}([p|}~\x7f])R_/))
      soil_func = m[1]
    end
  end

  case soil_func
  when "p"
    event.set("[nice_pos][trade_code]", "70")
  when "|"
    event.set("[nice_pos][trade_code]", "7C")
  when "}"
    event.set("[nice_pos][trade_code]", "7D")
  when "~"
    event.set("[nice_pos][trade_code]", "7E")
  when "\x7f"
    event.set("[nice_pos][trade_code]", "7F")
  end

  # 일반 금융 요청 레이아웃 여부
  finance_request = status == "IN" &&
                    (((soil_msg == "0200" && %w[10 21 MC].include?(soil_trade)) ||
                      (soil_msg == "0420" && %w[10 30 MC].include?(soil_trade))) ||
                     soil_func == "p")

  # 빠른주유 요청 레이아웃 여부
  quick_request = status == "IN" &&
                  !soil_func.nil? && soil_func.match?(/\A[|}~\x7f]\z/) &&
                  text(event, "com_10")&.match?(/\A\d{18}\z/) &&
                  text(event, "com_11")&.match?(/\A.{24}\z/) &&
                  text(event, "com_12")&.match?(/\A\d{2}\z/) &&
                  text(event, "com_13")&.match?(/\A\d{10}\z/)

  # 일반 금융 응답 레이아웃 여부
  finance_response = status == "OUT" &&
                     ((soil_msg == "0210" && %w[10 21 MC].include?(soil_trade)) ||
                      (soil_msg == "0430" && %w[10 30 MC].include?(soil_trade)))

  # 금융 요청 공통필드 생성
  if finance_request
    copy_map(event, "soil_finance_request")

    installment = text(event, "com_15")
    event.set("[nice_pos][detail][installment_months]", installment) if installment&.match?(/\A\d+\z/)

    original = text(event, "com_18")
    if soil_msg == "0420" && original&.match?(/\A\d+\z/)
      event.set("[nice_pos][detail][original_approval_number]", original)
    end

  # 빠른주유 요청은 거래금액만 공통필드 생성
  elsif quick_request
    copy_field(event, "com_10", "[nice_pos][detail][transaction_amount]")

  # 금융 응답 공통필드 생성
  elsif finance_response
    copy_map(event, "soil_finance_response")

  # HP 응답 전용 레이아웃
  elsif status == "OUT" && soil_msg == "0200" && soil_trade == "HP"
    copy_map(event, "soil_hp_response")
    unique = text(event, "com_13")
    event.set("[nice_pos][detail][transaction_unique_number]", unique) if unique&.match?(/\A\d{10}\z/)

  # A3 응답 전용 레이아웃
  elsif status == "OUT" && soil_msg == "0210" && soil_trade == "A3"
    copy_map(event, "soil_a3_response")
    unique = text(event, "com_14")
    event.set("[nice_pos][detail][transaction_unique_number]", unique) if unique&.match?(/\A\d{10}\z/)

  # FO 빠른주유 응답 전용 레이아웃(묶음 금액/승인번호 일부 추출)
  elsif status == "OUT" && soil_msg == "0210" && soil_trade == "FO"
    copy_map(event, "soil_fo_response")

    amount = text(event, "com_11")
    event.set("[nice_pos][detail][transaction_amount]", amount[0, 12]) if amount&.match?(/\A\d{48}\z/)

    approval = text(event, "com_14")
    event.set("[nice_pos][detail][approval_number]", approval[0, 13]) if approval&.match?(/\A\d{52}\z/)

    unique = text(event, "com_18")
    event.set("[nice_pos][detail][transaction_unique_number]", unique) if unique&.match?(/\A\d{10}\z/)

    acquirer = text(event, "com_24")
    event.set("[nice_pos][detail][acquirer_code]", acquirer) if acquirer&.match?(/\A\d{4}\z/)
  end

  # S-OIL 응답 Header 끝의 승인일시(YYMMDDhhmmss) 추출
  if status == "OUT" && !com9.nil?
    if (m = com9.match(/\A.{154}(\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])(?:[01][0-9]|2[0-3])[0-5][0-9][0-5][0-9])\z/))
      event.set("[nice_pos][detail][approval_datetime]", m[1])
    end
  end
end

# -----------------------------------------------------------------------------
# <신규 규격 업체 함수 예시>
# JSON mappings에 test_request / test_response를 등록한 경우 아래 형태로 추가
# def parse_test(event, status)
#   if status == "IN"
#     copy_map(event, "test_request")
#   elsif status == "OUT"
#     copy_map(event, "test_response")
#   end
# end
# 특수 Header/분리/자리수 가공이 필요하면 parse_test() 안에 조건을 추가한다.
# -----------------------------------------------------------------------------

# >>> GUIDE_F04_4: 실제 추가 2/2 — 기존 함수들의 end가 끝난 뒤 파일 맨 아래에 넣습니다.
# 연결: JSON routes.guide_shop → 위 case → 이 함수 → JSON mappings의 같은 이름.
# 가정: 이 업체 T1 전문만 아래 자리 배치를 사용합니다.
def parse_guide_shop(event, status)
  trade = text(event, "com_11")
  return unless trade == "T1" # 내 실제 전문코드로 바꿀 자리. 다른 코드는 여기서 종료합니다.

  if status == "IN" # FS 요청
    copy_map(event, "guide_shop_request")
  elsif status == "OUT" # FS 응답
    copy_map(event, "guide_shop_response")
  end
end
# <<< GUIDE_F04_4
