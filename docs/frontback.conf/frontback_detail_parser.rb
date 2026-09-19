# Logstash 8.17.6 Ruby filter.
# Parses only the documented 120-byte NICE SYSTEM_HEADER. Bytes at offset 120
# and later are intentionally neither classified nor copied to derived fields.
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
  raise ArgumentError, 'unsupported frontback schema version' unless document['schema_version'] == 2

  @max_message_bytes = Integer(params.fetch('max_message_bytes', 131_072))
  raise ArgumentError, 'invalid max_message_bytes' unless (1024..1_048_576).cover?(@max_message_bytes)
  @envelope_scan_bytes = Integer(params.fetch('envelope_scan_bytes', 512))
  raise ArgumentError, 'invalid envelope_scan_bytes' unless (256..4096).cover?(@envelope_scan_bytes)
  @envelope_pattern = /\A(\d{8} \d{2}:\d{2}:\d{2},\d{3})\t([^\t]{0,128})\t([A-Z]+)\s*\t\[([A-Z]{2})\s+(-->|<--)\s+([A-Z]{2})\]\s*\|/n.freeze

  @version = document.fetch('version')
  @header_bytes = Integer(document.fetch('header_bytes'))
  raise ArgumentError, 'header_bytes must be 120' unless @header_bytes == 120

  @fields = document.fetch('fields')
  raise ArgumentError, 'header fields required' unless @fields.is_a?(Array) && !@fields.empty?
  names = {}
  @fields.each do |spec|
    name = spec.fetch('name')
    raise ArgumentError, "invalid field name: #{name}" unless /\A[a-z][a-z0-9_]{0,63}\z/.match?(name)
    raise ArgumentError, "duplicate field name: #{name}" if names[name]
    names[name] = true

    offset = spec.fetch('offset')
    length = spec.fetch('length')
    unless offset.is_a?(Integer) && offset >= 0 && length.is_a?(Integer) && length.positive? && offset + length <= @header_bytes
      raise ArgumentError, "invalid field bounds: #{name}"
    end
    raise ArgumentError, "invalid data type: #{name}" unless %w[string integer].include?(spec.fetch('data_type'))
    raise ArgumentError, "invalid trim flag: #{name}" unless !spec.key?('trim') || [true, false].include?(spec['trim'])
    spec['compiled_pattern'] = Regexp.new(spec['pattern']) if spec['pattern']
  end

  covered = Array.new(@header_bytes, false)
  @fields.each do |spec|
    spec.fetch('length').times do |index|
      position = spec.fetch('offset') + index
      raise ArgumentError, "overlapping field at offset #{position}" if covered[position]
      covered[position] = true
    end
  end
  raise ArgumentError, 'header fields must cover all 120 bytes' unless covered.all?

  @channels = document.fetch('channels')
  raise ArgumentError, 'front/back channel definitions required' unless %w[front back].all? { |name| @channels.key?(name) }
  scope = document.fetch('scope')
  raise ArgumentError, 'body parsing must remain disabled' unless scope['body_start_offset'] == 120 && scope['body_parsing_enabled'] == false

  fb_freeze(@fields)
  fb_freeze(@channels)
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

def fb_ascii(value)
  value.dup.force_encoding(Encoding::UTF_8)
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

def fb_extract_header(payload, result)
  header = {}
  @fields.each do |spec|
    name = spec.fetch('name')
    raw = payload.byteslice(spec.fetch('offset'), spec.fetch('length'))
    if raw.nil? || raw.bytesize != spec.fetch('length')
      fb_error(result, "truncated_#{name}")
      next
    end
    unless raw.ascii_only?
      fb_error(result, "non_ascii_#{name}")
      next
    end

    text = fb_ascii(raw)
    fb_warning(result, "invalid_#{name}") if spec['compiled_pattern'] && !spec['compiled_pattern'].match?(text)
    text = text.strip if spec['trim']
    header[name] = spec.fetch('data_type') == 'integer' && /\A[0-9]+\z/.match?(text) ? text.to_i : text
  end
  header
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

  envelope = message.byteslice(0, [message.bytesize, @envelope_scan_bytes].min)
  envelope.force_encoding(Encoding::BINARY)
  match = @envelope_pattern.match(envelope)
  unless match
    return [event] unless message.include?(' --> ') || message.include?(' <-- ')
    fb_error(result, 'invalid_channel_envelope')
    fb_store_failure(event, result)
    return [event]
  end

  timestamp_raw, nice_number_raw, level_raw, source_raw, arrow_raw, target_raw = match.captures
  timestamp_text = fb_ascii(timestamp_raw)
  nice_number = fb_ascii(nice_number_raw).strip
  level = fb_ascii(level_raw)
  source = fb_ascii(source_raw)
  arrow = fb_ascii(arrow_raw)
  target = fb_ascii(target_raw)

  channel = fb_channel_from_endpoints(source, target)
  unless channel
    fb_error(result, 'unknown_channel_endpoints')
    fb_store_failure(event, result)
    return [event]
  end

  result['channel'] = channel
  result['flow_direction'] = arrow == '-->' ? 'request' : 'response'
  result['source_endpoint'] = source
  result['target_endpoint'] = target
  result['timestamp_text'] = timestamp_text
  result['level'] = level
  result['header_bytes'] = @header_bytes
  fb_warning(result, 'path_channel_mismatch') if path_channel && path_channel != channel

  header_raw = message.byteslice(match.end(0), @header_bytes)
  if header_raw.nil? || header_raw.bytesize < @header_bytes
    fb_error(result, 'short_payload')
    fb_store_failure(event, result)
    return [event]
  end
  header_raw.force_encoding(Encoding::BINARY)

  header = fb_extract_header(header_raw, result)
  if result['errors'] && !result['errors'].empty?
    fb_store_failure(event, result)
    return [event]
  end

  result['nice_header'] = header
  result['nice_number_match'] = header['nice_serial_no'] == nice_number
  fb_warning(result, 'nice_number_mismatch') unless result['nice_number_match']
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
