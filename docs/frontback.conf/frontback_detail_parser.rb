# Logstash 8.17.6 Ruby filter.
# Loads immutable JSON once and enriches only FrontChannelMgr/BackChannelMgr
# transaction lines. It never drops an event or exports the inner payment body.
require 'json'

def fb_freeze(value)
  case value
  when Hash
    value.each { |key, item| fb_freeze(key); fb_freeze(item) }
  when Array
    value.each { |item| fb_freeze(item) }
  end
  value.freeze
end

def register(params)
  document = JSON.parse(File.read(params.fetch('specs_path'), encoding: 'UTF-8'))
  raise ArgumentError, 'unsupported frontback schema version' unless document['schema_version'] == 1

  @max_message_bytes = Integer(params.fetch('max_message_bytes', 131_072))
  raise ArgumentError, 'invalid max_message_bytes' unless (1024..1_048_576).cover?(@max_message_bytes)
  @source_encoding = Encoding.find(params.fetch('source_encoding', 'UTF-8'))
  @version = document.fetch('version')
  @minimum_payload_bytes = Integer(document.fetch('minimum_payload_bytes'))
  raise ArgumentError, 'invalid minimum payload size' unless (120..4096).cover?(@minimum_payload_bytes)

  @slices = document.fetch('slices')
  @slices.each do |name, spec|
    raise ArgumentError, "invalid slice name: #{name}" unless /\A[a-z][a-z0-9_]{0,63}\z/.match?(name)
    offset = spec.fetch('offset')
    length = spec.fetch('length')
    raise ArgumentError, "invalid slice bounds: #{name}" unless offset.is_a?(Integer) && offset >= 0 && length.is_a?(Integer) && length.positive? && offset + length <= @minimum_payload_bytes
    spec['compiled_pattern'] = Regexp.new(spec['pattern']) if spec['pattern']
    raise ArgumentError, "invalid emit flag: #{name}" unless !spec.key?('emit') || [true, false].include?(spec['emit'])
  end

  @channels = document.fetch('channels')
  raise ArgumentError, 'front/back channel definitions required' unless %w[front back].all? { |name| @channels.key?(name) }
  @institutions = document.fetch('institution_codes')
  @institutions.each do |code, label|
    raise ArgumentError, 'invalid institution code' unless /\A[0-9A-Z]{2}\z/.match?(code)
    raise ArgumentError, 'invalid institution label' unless label.is_a?(String) && !label.empty?
  end
  document.fetch('inner_profiles').each do |profile|
    raise ArgumentError, 'invalid inner profile enabled flag' unless [true, false].include?(profile.fetch('enabled'))
  end

  fb_freeze(@slices)
  fb_freeze(@channels)
  fb_freeze(@institutions)
  @version.freeze
end

def fb_tag(event, value)
  event.tag(value) unless Array(event.get('tags')).include?(value)
end

def fb_warning(result, code)
  result['warnings'] ||= []
  result['warnings'] << code unless result['warnings'].include?(code) || result['warnings'].length >= 12
end

def fb_error(result, code)
  result['errors'] ||= []
  result['errors'] << { 'code' => code } unless result['errors'].any? { |item| item['code'] == code } || result['errors'].length >= 8
end

def fb_trim_ascii(value)
  value.sub(/[ ]+\z/, '').sub(/\A[ ]+/, '')
end

def fb_extract(payload, name, result)
  spec = @slices.fetch(name)
  value = payload.byteslice(spec.fetch('offset'), spec.fetch('length'))
  if value.nil? || value.bytesize != spec.fetch('length')
    fb_error(result, "truncated_#{name}")
    return nil
  end
  unless value.ascii_only?
    fb_error(result, "non_ascii_#{name}")
    return nil
  end
  value = value.dup.force_encoding(Encoding::UTF_8)
  if spec['expected'] && value != spec['expected']
    fb_warning(result, "unexpected_#{name}")
  end
  if spec['compiled_pattern'] && !spec['compiled_pattern'].match?(value)
    fb_warning(result, "invalid_#{name}")
  end
  fb_trim_ascii(value)
end

def fb_channel_from_path(path)
  return 'front' if path.include?(@channels.fetch('front').fetch('path_token'))
  return 'back' if path.include?(@channels.fetch('back').fetch('path_token'))
  nil
end

def fb_channel_from_endpoints(source, target)
  @channels.each do |name, spec|
    return name if source == spec.fetch('source') && target == spec.fetch('target')
  end
  nil
end

def fb_inner_kind(body)
  return 'empty' if body.nil? || body.empty?
  return 'iso8583_binary_stx' if body.getbyte(0) == 2
  head = body.byteslice(0, 4)
  return 'fixed_text_3hdr' if head == '3HDR'
  return 'test_text' if head == 'ETes'
  return 'iso8583_ascii_candidate' if head && /\A[0-9]{4}\z/.match?(head)
  'custom_or_opaque'
end

def fb_store_failure(event, result)
  result['status'] = 'failed'
  event.set('[frontback_detail]', result)
  fb_tag(event, '_frontback_parse_failure')
end

def filter(event)
  if event.get('[frontback_detail]')
    fb_tag(event, '_frontback_detail_target_collision')
    return [event]
  end

  message = event.get('message')
  return [event] unless message.is_a?(String)

  path = event.get('[log][file][path]').to_s
  path_channel = fb_channel_from_path(path)
  looks_like_channel = path_channel || message.include?('[FT --> FC]') || message.include?('[FT <-- FC]') || message.include?('[BC --> BT]') || message.include?('[BC <-- BT]')
  return [event] unless looks_like_channel

  result = { 'schema_version' => @version }
  if message.bytesize > @max_message_bytes
    fb_error(result, 'message_too_large')
    fb_store_failure(event, result)
    return [event]
  end

  match = /\A(\d{8} \d{2}:\d{2}:\d{2},\d{3})\t([^\t]*)\t([A-Z]+)\s*\t\[([A-Z]{2})\s+(-->|<--)\s+([A-Z]{2})\]\s*\|(.*)\z/m.match(message)
  unless match
    # Operational/stack-trace lines in these files are intentionally left unchanged.
    return [event] unless message.include?(' --> ') || message.include?(' <-- ')
    fb_error(result, 'invalid_channel_envelope')
    fb_store_failure(event, result)
    return [event]
  end

  timestamp_text, nice_number, level, source, arrow, target, payload_text = match.captures
  channel = fb_channel_from_endpoints(source, target)
  unless channel
    fb_error(result, 'unknown_channel_endpoints')
    fb_store_failure(event, result)
    return [event]
  end

  result['channel'] = channel
  result['direction'] = arrow == '-->' ? 'request' : 'response'
  result['source_endpoint'] = source
  result['target_endpoint'] = target
  result['timestamp_text'] = timestamp_text
  result['level'] = level
  fb_warning(result, 'path_channel_mismatch') if path_channel && path_channel != channel

  begin
    payload = payload_text.encode(@source_encoding).b
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    # The verified 132-byte header is ASCII. Parse that prefix even when the
    # downstream binary/body was already replaced by the input codec.
    payload = payload_text.byteslice(0, @minimum_payload_bytes).to_s.b
    fb_warning(result, 'lossy_input_encoding')
  end

  result['payload_bytes'] = payload.bytesize
  if payload.bytesize < @minimum_payload_bytes
    fb_error(result, 'short_payload')
    fb_store_failure(event, result)
    return [event]
  end

  values = {}
  @slices.each_key { |name| values[name] = fb_extract(payload, name, result) }
  if result['errors'] && !result['errors'].empty?
    fb_store_failure(event, result)
    return [event]
  end

  %w[transaction_id institution_code correlation_id connection_slot message_class route_code code].each do |name|
    result[name] = values[name] unless values[name].nil? || values[name].empty?
  end
  result['session_descriptor_present'] = !values['session_descriptor'].to_s.strip.empty?
  result['correlation_match'] = values['correlation_id'] == nice_number.strip
  fb_warning(result, 'correlation_mismatch') unless result['correlation_match']

  if channel == 'front'
    result['institution_code'] = 'ZZ'
    partner = values['front_partner_code']
    partner = nil unless partner && /\A[A-Z$][A-Z0-9$ ]{1,7}\z/.match?(partner)
    result['partner_code'] = partner unless partner.nil? || partner.empty?
    result['code_role'] = result['direction'] == 'request' ? 'network_code' : 'response_code'
    if result['direction'] == 'request' && values['code'] != @channels.fetch('front').fetch('request_code')
      fb_warning(result, 'unexpected_front_request_code')
    end
    result['inner_kind'] = 'front_fixed_width'
  else
    institution = @institutions[values['institution_code']]
    result['institution_name'] = institution || 'unmapped'
    result['institution_mapping_status'] = institution ? 'mapped' : 'unmapped'
    result['code_role'] = 'network_code'
    fb_warning(result, 'unexpected_back_network_code') if values['code'] != @channels.fetch('back').fetch('network_code')

    marker_offset = nil
    partner = nil
    if payload.byteslice(129, 3) == 'ISO'
      marker_offset = 129
      partner = fb_trim_ascii(payload.byteslice(120, 9).dup.force_encoding(Encoding::UTF_8))
    elsif payload.byteslice(120, 3) == 'ISO'
      marker_offset = 120
    end
    result['protocol_marker'] = marker_offset ? 'ISO' : 'unidentified'
    result['protocol_marker_offset'] = marker_offset if marker_offset
    result['partner_code'] = partner unless partner.nil? || partner.empty?

    inner_offset = @channels.fetch('back').fetch('inner_offset')
    body = payload.byteslice(inner_offset, payload.bytesize - inner_offset)
    result['inner_offset'] = inner_offset
    result['inner_bytes'] = body ? body.bytesize : 0
    result['inner_kind'] = fb_inner_kind(body)
  end

  result['status'] = result['warnings'] && !result['warnings'].empty? ? 'warning' : 'ok'
  event.set('[frontback_detail]', result)
  fb_tag(event, '_frontback_parse_warning') if result['status'] == 'warning'
  [event]
rescue StandardError
  result ||= { 'schema_version' => @version }
  fb_error(result, 'parser_exception')
  fb_store_failure(event, result)
  fb_tag(event, '_frontback_parse_exception')
  [event]
end
