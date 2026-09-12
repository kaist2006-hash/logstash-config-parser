# Logstash 8.17.6 Ruby filter. Configuration is loaded/validated once per instance.
# No network, per-event disk I/O, mutable shared caches, or raw payment-field export.
require 'json'

def card_freeze(value)
  case value
  when Hash then value.each { |k, v| card_freeze(k); card_freeze(v) }
  when Array then value.each { |v| card_freeze(v) }
  end
  value.freeze
end

def register(params)
  document = JSON.parse(File.read(params.fetch('specs_path'), encoding: 'UTF-8'))
  raise ArgumentError, 'unsupported card schema version' unless document['schema_version'] == 1
  @max_message_bytes = Integer(params.fetch('max_message_bytes', 65_536))
  raise ArgumentError, 'invalid max_message_bytes' unless (1024..1_048_576).cover?(@max_message_bytes)
  @text_encoding = Encoding.find(params.fetch('text_encoding', 'UTF-8'))
  enabled = params['enabled_profiles']
  enabled = enabled.split(',').map(&:strip).reject(&:empty?) if enabled.is_a?(String)
  raise ArgumentError, 'invalid enabled_profiles' unless enabled.nil? || enabled.is_a?(Array)
  known = document.fetch('profiles').map { |p| p.fetch('id') }
  raise ArgumentError, 'unknown enabled profile' if enabled && !(enabled - known).empty?
  @profiles = {}
  @version = document.fetch('version')
  document.fetch('profiles').each do |profile|
    id = profile.fetch('id')
    raise ArgumentError, 'duplicate profile alias' if @profiles.key?(profile.fetch('alias'))
    raise ArgumentError, 'invalid wire format' unless %w[ascii binary].include?(profile.fetch('wire'))
    raise ArgumentError, 'invalid header offsets' unless profile.fetch('header_offsets').all? { |n| n.is_a?(Integer) && (0..32).cover?(n) }
    raise ArgumentError, 'invalid bitmap bound' unless (1..3).cover?(profile.fetch('max_bitmaps'))
    profile['enabled'] = enabled.include?(id) unless enabled.nil?
    raise ArgumentError, 'invalid enabled flag' unless [true, false].include?(profile['enabled'])
    compiled = Array.new(193)
    profile.fetch('fields').each do |key, spec|
      bit = Integer(key, 10)
      raise ArgumentError, 'invalid data element' unless (2..192).cover?(bit) && ![65,129].include?(bit)
      raise ArgumentError, 'invalid field kind' unless %w[fixed var blocked].include?(spec.fetch('kind'))
      if spec['kind'] == 'fixed'
        raise ArgumentError, 'invalid fixed length' unless (1..4096).cover?(spec.fetch('length'))
      elsif spec['kind'] == 'var'
        raise ArgumentError, 'invalid length prefix' unless %w[binary ascii2 ascii3].include?(spec.fetch('prefix'))
        raise ArgumentError, 'invalid length unit' unless %w[bytes digits].include?(spec.fetch('unit'))
        raise ArgumentError, 'invalid variable maximum' unless (1..4096).cover?(spec.fetch('max'))
      end
      ([spec] + spec.fetch('parts', [])).each do |part|
        next unless part['emit']
        raise ArgumentError, 'invalid exported name' unless /\A[a-z][a-z0-9_]{0,63}\z/.match?(part['emit'])
        raise ArgumentError, 'invalid exported encoding' unless %w[ascii bcd hex].include?(part.fetch('encoding'))
        if part != spec
          raise ArgumentError, 'invalid subfield bounds' unless part.fetch('offset').is_a?(Integer) && part['offset'] >= 0 && (1..512).cover?(part.fetch('length'))
        end
      end
      compiled[bit] = spec
    end
    profile['compiled'] = compiled
    @profiles[profile['alias']] = profile
  end
  @emv_export = document.fetch('emv_export')
  card_freeze(@profiles)
  card_freeze(@emv_export)
  @version.freeze
end

def card_error(result, code, bit = nil, offset = nil, expected = nil, available = nil)
  result['errors'] ||= []
  return if result['errors'].length >= 8
  item = { 'code' => code }
  item['field'] = bit if bit
  item['offset'] = offset unless offset.nil?
  item['expected'] = expected unless expected.nil?
  item['available'] = available unless available.nil?
  result['errors'] << item
end

def card_warn(result, code)
  result['warnings'] ||= []
  result['warnings'] << code unless result['warnings'].include?(code) || result['warnings'].length >= 16
end

def card_value(bytes, spec, result, bit, offset)
  value = case spec['encoding']
          when 'bcd', 'hex' then bytes.unpack1('H*').upcase
          when 'ascii'
            unless bytes.ascii_only? && bytes.each_byte.all? { |b| b >= 32 && b <= 126 }
              card_error(result, 'invalid_ascii_value', bit, offset)
              return nil
            end
            bytes.dup.force_encoding(Encoding::UTF_8).strip
          end
  if spec['encoding'] == 'bcd' && !/\A[0-9]*\z/.match?(value)
    card_error(result, 'invalid_bcd_value', bit, offset)
    return nil
  end
  if spec['numeric'] && !value.empty? && !/\A[0-9]+\z/.match?(value)
    card_error(result, 'invalid_numeric_value', bit, offset)
    return nil
  end
  value
end

def card_tlv(bytes, result, bit, start)
  pos = 0
  exported = {}
  count = 0
  while pos < bytes.bytesize
    tag_start = pos
    first = bytes.getbyte(pos)
    pos += 1
    if (first & 31) == 31
      loop do
        if pos >= bytes.bytesize || pos - tag_start >= 4
          card_error(result, 'invalid_tlv_tag', bit, start + pos)
          return
        end
        last = bytes.getbyte(pos)
        pos += 1
        break if (last & 128).zero?
      end
    end
    tag = bytes.byteslice(tag_start, pos - tag_start).unpack1('H*').upcase
    if pos >= bytes.bytesize
      card_error(result, 'truncated_tlv_length', bit, start + pos)
      return
    end
    length = bytes.getbyte(pos)
    pos += 1
    if length >= 128
      n = length & 127
      if n.zero? || n > 2 || pos + n > bytes.bytesize
        card_error(result, 'invalid_tlv_length', bit, start + pos - 1)
        return
      end
      length = 0
      n.times { length = (length << 8) | bytes.getbyte(pos); pos += 1 }
    end
    if pos + length > bytes.bytesize
      card_error(result, 'truncated_tlv_value', bit, start + pos, length, bytes.bytesize - pos)
      return
    end
    rule = @emv_export[tag]
    if rule
      if length != rule['length']
        card_error(result, 'invalid_tlv_export_length', bit, start + pos, rule['length'], length)
        return
      end
      if exported.key?(rule['name'])
        card_error(result, 'duplicate_tlv_export_tag', bit, start + tag_start)
        return
      end
      exported[rule['name']] = bytes.byteslice(pos, length).unpack1('H*').upcase
    end
    pos += length
    count += 1
  end
  result['emv'] = exported unless exported.empty?
  result['tlv_count'] = count
end

def card_parse(raw, profile, result)
  result['payload_bytes'] = raw.bytesize
  offset = profile['header_offsets'].find { |o| raw.byteslice(o, 3) == 'ISO' }
  unless offset && raw.bytesize >= offset + 12
    card_error(result, 'missing_iso_header')
    return
  end
  header = raw.byteslice(offset, 12)
  unless /\AISO[0-9]{9}\z/.match?(header)
    card_error(result, 'invalid_iso_header')
    return
  end
  result['header'] = header.dup.force_encoding(Encoding::UTF_8)
  result['header_offset'] = offset
  if profile['expected_headers'] && !profile['expected_headers'].include?(header)
    card_warn(result, 'header_differs_from_document')
  end
  binary = profile['wire'] == 'binary'
  pos = offset + 12
  width = binary ? 2 : 4
  if raw.bytesize < pos + width
    card_error(result, 'truncated_mti', nil, pos, width, raw.bytesize - pos)
    return
  end
  mti = binary ? raw.byteslice(pos, width).unpack1('H*') : raw.byteslice(pos, width)
  unless /\A[0-9]{4}\z/.match?(mti)
    card_error(result, 'invalid_mti', nil, pos)
    return
  end
  result['mti'] = mti.dup.force_encoding(Encoding::UTF_8)
  card_warn(result, 'mti_not_in_document') unless profile['mtis'].include?(mti)
  pos += width
  maps = []
  profile['max_bitmaps'].times do |index|
    width = binary ? 8 : 16
    if pos + width > raw.bytesize
      card_error(result, 'truncated_bitmap', nil, pos, width, raw.bytesize - pos)
      return
    end
    chunk = raw.byteslice(pos, width)
    if !binary && !/\A[0-9a-fA-F]{16}\z/.match?(chunk)
      card_error(result, 'invalid_bitmap', nil, pos)
      return
    end
    map = binary ? chunk : [chunk].pack('H*')
    maps << map
    pos += width
    break if (map.getbyte(0) & 128).zero?
    if index == profile['max_bitmaps'] - 1
      card_error(result, 'unsupported_bitmap_extension', nil, pos)
      return
    end
  end
  result['bitmap'] = maps.join.unpack1('H*').upcase
  active = []
  maps.each_with_index do |map, group|
    map.each_byte.with_index do |byte, index|
      8.times do |j|
        bit = group * 64 + index * 8 + j + 1
        active << bit if (byte & (128 >> j)) != 0 && ![1,65,129].include?(bit)
      end
    end
  end
  result['present_fields'] = active
  values = {}
  consumed_fields = 0
  active.each do |bit|
    spec = profile['compiled'][bit]
    if spec.nil? || spec['kind'] == 'blocked'
      card_error(result, spec.nil? ? 'unknown_field' : 'unresolved_spec_field', bit, pos)
      break
    end
    length = spec['length']
    if spec['kind'] == 'var'
      prefix_bytes = { 'binary' => 1, 'ascii2' => 2, 'ascii3' => 3 }[spec['prefix']]
      if pos + prefix_bytes > raw.bytesize
        card_error(result, 'truncated_length_prefix', bit, pos, prefix_bytes, raw.bytesize - pos)
        break
      end
      if spec['prefix'] == 'binary'
        count = raw.getbyte(pos)
      else
        prefix = raw.byteslice(pos, prefix_bytes)
        unless /\A[0-9]+\z/.match?(prefix)
          card_error(result, 'invalid_length_prefix', bit, pos)
          break
        end
        count = prefix.to_i
      end
      if count > spec['max']
        card_error(result, 'field_length_exceeds_limit', bit, pos, spec['max'], count)
        break
      end
      card_warn(result, "document_length_deviation_f#{bit}") if spec['document_max'] && count > spec['document_max']
      length = spec['unit'] == 'digits' ? (count + 1) / 2 : count
      pos += prefix_bytes
    end
    if pos + length > raw.bytesize
      card_error(result, 'truncated_field', bit, pos, length, raw.bytesize - pos)
      break
    end
    bytes = raw.byteslice(pos, length)
    if spec['emit']
      value = card_value(bytes, spec, result, bit, pos)
      values[spec['emit']] = value unless value.nil?
    end
    spec.fetch('parts', []).each do |part|
      next if part['offset'] + part['length'] > length
      value = card_value(bytes.byteslice(part['offset'], part['length']), part, result, bit, pos + part['offset'])
      values[part['emit']] = value unless value.nil?
    end
    card_tlv(bytes, result, bit, pos) if spec['tlv']
    pos += length
    consumed_fields += 1
  end
  result['fields'] = values unless values.empty?
  result['parsed_field_count'] = consumed_fields
  result['consumed_bytes'] = pos
  result['remaining_bytes'] = raw.bytesize - pos
  result['frame_status'] = consumed_fields == active.length ? 'complete' : 'partial'
  if result['frame_status'] == 'complete' && pos != raw.bytesize
    card_error(result, 'trailing_bytes', nil, pos, pos, raw.bytesize)
    result['frame_status'] = 'partial'
  end
end

def filter(event)
  # The original conf owns routing/drop policy. Never change its target_alias here.
  result = { 'parser_version' => @version, 'status' => 'failed', 'frame_status' => 'invalid' }
  if event.include?('[card_detail]')
    event.tag('_card_detail_target_collision')
    return [event]
  end
  profile = @profiles[event.get('[@metadata][target_alias]')]
  unless profile
    result['status'] = 'unconfigured'
    result['frame_status'] = 'not_parsed'
    event.set('[card_detail]', result)
    return [event]
  end
  result['profile'] = profile['id']
  result['issuer'] = profile['issuer']
  result['service'] = profile['service']
  unless profile['enabled']
    result['status'] = 'disabled'
    result['frame_status'] = 'not_parsed'
    event.set('[card_detail]', result)
    return [event]
  end
  message = event.get('message')
  if !message.is_a?(String)
    card_error(result, 'message_not_string')
  elsif message.bytesize > @max_message_bytes
    card_error(result, 'message_too_large', nil, nil, @max_message_bytes, message.bytesize)
  elsif message.include?("\uFFFD")
    card_error(result, 'lossy_input_encoding')
  else
    # Convert back only with the same codec charset used by the source reader.
    wire_message = message.encode(@text_encoding).b
    raw = nil
    if wire_message.include?('==>[')
      match = /len\[([0-9]+)\]\[([SR])\]==>\[([0-9a-fA-F]*)\]\s*\z/.match(wire_message)
      if match && match[3].bytesize.even?
        raw = [match[3]].pack('H*')
        result['declared_bytes'] = match[1].to_i
        result['direction'] = match[2] == 'S' ? 'OUT' : 'IN'
        result['log_encoding'] = 'hex'
      else
        card_error(result, 'invalid_hex_envelope')
      end
    else
      marker = /\b(get|put)\(data\[/.match(wire_message)
      tail = /\] len\[([0-9]+)\] uid\[[^\]]*\](?: linename\[[^\]]*\])?\)\s*\z/.match(wire_message)
      if marker && tail && tail.begin(0) >= marker.end(0)
        raw = wire_message.byteslice(marker.end(0), tail.begin(0) - marker.end(0))
        result['declared_bytes'] = tail[1].to_i
        result['direction'] = marker[1] == 'put' ? 'OUT' : 'IN'
        result['log_encoding'] = 'text'
      else
        card_error(result, 'incomplete_text_envelope')
      end
    end
    if raw
      result['logged_bytes'] = raw.bytesize
      card_warn(result, 'declared_length_mismatch') if raw.bytesize != result['declared_bytes']
      if raw.start_with?('RESPDATA') && profile['response_prefix'] == 'RESPDATA'
        raw = raw.byteslice(8, raw.bytesize - 8)
        result['response_prefix_bytes'] = 8
      end
      card_parse(raw, profile, result)
    end
  end
  if result['errors'] && !result['errors'].empty?
    result['status'] = result['parsed_field_count'].to_i > 0 ? 'partial' : 'failed'
    event.tag('_card_detail_parse_failure')
  elsif result['warnings'] && !result['warnings'].empty?
    result['status'] = 'warning'
    event.tag('_card_detail_warning')
  else
    result['status'] = 'ok'
  end
  event.set('[card_detail]', result)
  [event]
rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
  card_error(result, 'input_encoding_not_reversible')
  result['status'] = 'failed'
  event.set('[card_detail]', result)
  event.tag('_card_detail_parse_failure')
  [event]
rescue StandardError
  # Never interpolate exception.message: it can contain payment data.
  result ||= { 'parser_version' => @version }
  result['status'] = 'failed'
  card_error(result, 'unexpected_parser_exception')
  event.set('[card_detail]', result)
  event.tag('_card_detail_exception')
  [event]
end
