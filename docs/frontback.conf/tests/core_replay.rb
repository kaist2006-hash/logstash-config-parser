# Runs inside the Logstash 8.17.6 JRuby/Event runtime. No Beats or ES access.
require 'json'
require 'digest'
require 'thread'
Thread.abort_on_exception = true

def fb_canonical(value)
  case value
  when Hash then value.keys.sort.map { |key| [key, fb_canonical(value[key])] }.to_h
  when Array then value.map { |item| fb_canonical(item) }
  else value
  end
end

def fb_put(buffer, offset, value)
  buffer[offset, value.bytesize] = value
end

def fb_contract_message(channel, flow, options = {})
  body = options.fetch(:body, 'UNPARSED-BODY').b
  payload = (' ' * 120).b
  nice = 'T00000000000000001'
  msg_type = channel == 'front' ? (flow == 'request' ? '0200' : '0210') : (flow == 'request' ? '0200' : '0110')
  process_code = channel == 'front' ? '010100ZZ' : "010100#{options.fetch(:institution, '02')}"
  format_code = channel == 'front' ? '010100ZZ01' : "010101#{options.fetch(:institution, '02')}00"
  correlation = options.fetch(:correlation, flow == 'response' ? 'ID:00025-M0000000A-NICE' : '').ljust(52)

  fb_put(payload, 0, format('%04d', payload.bytesize + body.bytesize))
  fb_put(payload, 4, msg_type)
  fb_put(payload, 8, options.fetch(:network_response_code, '0000'))
  fb_put(payload, 12, process_code)
  fb_put(payload, 20, nice)
  fb_put(payload, 38, correlation)
  fb_put(payload, 90, options.fetch(:header_direction, 'B'))
  fb_put(payload, 91, '20260919')
  fb_put(payload, 99, '123456')
  fb_put(payload, 105, format_code)
  fb_put(payload, 115, options.fetch(:service_instance_id, channel == 'back' ? '2' : '1'))
  fb_put(payload, 116, options.fetch(:response_code, '8373'))
  payload << body

  endpoints = if channel == 'front'
                flow == 'request' ? '[FT --> FC]' : '[FT <-- FC]'
              else
                flow == 'request' ? '[BC --> BT]' : '[BC <-- BT]'
              end
  ["20260919 12:34:56,789\t#{nice}\tINFO  \t#{endpoints} |#{payload.force_encoding(Encoding::UTF_8)}", nice]
end

directory = ENV.fetch('FRONTBACK_PARSER_DIR')
parser = Object.new
parser.instance_eval(File.read(File.join(directory, 'frontback_detail_parser.rb')), 'frontback_detail_parser.rb')
parser.register(
  'specs_path' => File.join(directory, 'frontback_detail_specs.json'),
  'max_message_bytes' => 131_072
)

workers = Integer(ENV.fetch('FRONTBACK_CORE_WORKERS', '1'))
raise 'workers must be 1..8' unless (1..8).cover?(workers)
report = {
  'runtime' => RUBY_DESCRIPTION,
  'event_class' => LogStash::Event.name,
  'workers' => workers
}
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

if ENV['FRONTBACK_CONTRACTS'] == '1'
  cases = [
    ['front_request_blank_defaults', 'front', 'request', { :header_direction => 'F', :service_instance_id => ' ', :response_code => '    ' }],
    ['front_response', 'front', 'response', { :response_code => '0000' }],
    ['back_request', 'back', 'request', { :institution => '07', :body => 'ISO0234000530200' }],
    ['back_response', 'back', 'response', { :institution => '11', :body => 'NHCARD   ISO0110' }]
  ]
  results = []
  cases.each do |id, channel, flow, options|
    message, nice = fb_contract_message(channel, flow, options)
    path = "C:/logs/#{channel == 'front' ? 'FrontChannelMgr' : 'BackChannelMgr'}.log"
    event = LogStash::Event.new('message' => message, 'nice_number' => nice, 'log' => { 'file' => { 'path' => path } })
    before = event.get('message')
    returned = parser.filter(event)
    detail = event.get('frontback_detail') || {}
    header = detail['nice_header'] || {}
    expected_msg_type = channel == 'front' ? (flow == 'request' ? '0200' : '0210') : (flow == 'request' ? '0200' : '0110')
    checks = {
      'status' => detail['status'] == 'ok',
      'channel' => detail['channel'] == channel && detail['flow_direction'] == flow,
      'header_size' => detail['header_bytes'] == 120,
      'documented_fields' => header.keys.sort == %w[direction message_correlation_id msg_format_code msg_length msg_type network_response_code nice_serial_no process_code response_code service_instance_id transaction_date transaction_time].sort,
      'values' => header['msg_type'] == expected_msg_type && header['nice_serial_no'] == nice && header['transaction_date'] == '20260919',
      'nice_number' => detail['nice_number_match'] == true,
      'no_body_fields' => (%w[partner_code protocol_marker inner_kind institution_code] & detail.keys).empty?,
      'retained' => returned.length == 1 && returned[0].equal?(event) && event.get('message') == before
    }
    results << { 'id' => id, 'checks' => checks, 'detail' => detail }
  end

  short, = fb_contract_message('front', 'request')
  short = short.sub(/\|.*/m, '|short')
  event = LogStash::Event.new('message' => short, 'log' => { 'file' => { 'path' => 'C:/logs/FrontChannelMgr.log' } })
  parser.filter(event)
  results << {
    'id' => 'short_payload',
    'checks' => {
      'failed' => event.get('[frontback_detail][status]') == 'failed',
      'tagged' => Array(event.get('tags')).include?('_frontback_parse_failure')
    }
  }

  event = LogStash::Event.new('message' => "20260919 12:34:56,789\tworker\tINFO\toperational", 'log' => { 'file' => { 'path' => 'C:/logs/FrontChannelMgr.log' } })
  parser.filter(event)
  results << { 'id' => 'operational_skip', 'checks' => { 'unchanged' => event.get('frontback_detail').nil? } }

  event = LogStash::Event.new('message' => 'keep', 'frontback_detail' => { 'keep' => 'existing' })
  parser.filter(event)
  results << {
    'id' => 'target_collision',
    'checks' => {
      'preserved' => event.get('[frontback_detail][keep]') == 'existing',
      'tagged' => Array(event.get('tags')).include?('_frontback_detail_target_collision')
    }
  }

  rejected = false
  begin
    invalid = Object.new
    invalid.instance_eval(File.read(File.join(directory, 'frontback_detail_parser.rb')))
    invalid.register('specs_path' => File.join(directory, 'frontback_detail_specs.json'), 'max_message_bytes' => 100)
  rescue ArgumentError
    rejected = true
  end
  results << { 'id' => 'invalid_limit_rejected', 'checks' => { 'rejected' => rejected } }

  report['contracts'] = results
  report['passed'] = results.count { |item| item['checks'].values.all? }
  report['failed'] = results.length - report['passed']
else
  queue = SizedQueue.new(2048)
  pool = workers.times.map do
    Thread.new do |; local, item, message, path, event, before_path, returned, returned_event, detail, header, key, digest|
      local = {
        'events' => 0,
        'counts' => Hash.new(0),
        'warnings' => Hash.new(0),
        'errors' => Hash.new(0),
        'message_mutations' => 0,
        'path_mutations' => 0,
        'return_proxy_identity_mismatches' => 0,
        'nice_number_mismatches' => 0,
        'digest_sum' => 0,
        'digest_xor' => 0
      }
      loop do
        item = queue.pop
        break unless item
        message, path = item
        event = LogStash::Event.new('message' => message, 'log' => { 'file' => { 'path' => path } })
        before_path = event.get('[log][file][path]')
        returned = parser.filter(event)
        raise 'event lost or duplicated' unless returned.is_a?(Array) && returned.length == 1
        returned_event = returned[0]
        raise 'returned event content mismatch' unless returned_event.get('message') == message && returned_event.get('[log][file][path]') == before_path
        local['return_proxy_identity_mismatches'] += 1 unless returned_event.equal?(event)
        local['message_mutations'] += 1 unless event.get('message') == message
        local['path_mutations'] += 1 unless event.get('[log][file][path]') == before_path
        detail = returned_event.get('frontback_detail')
        raise 'selected transaction not parsed' unless detail
        local['nice_number_mismatches'] += 1 unless detail['nice_number_match'] == true
        header = detail['nice_header'] || {}
        key = [detail['channel'], detail['flow_direction'], detail['status'], header['msg_type'], header['process_code'], header['msg_format_code'], header['response_code']].join('|')
        local['counts'][key] += 1
        detail.fetch('warnings', []).each { |warning| local['warnings'][warning] += 1 }
        detail.fetch('errors', []).each { |error| local['errors'][error['code']] += 1 }
        digest = Digest::SHA256.hexdigest(JSON.generate(fb_canonical(detail))).to_i(16)
        local['digest_sum'] = (local['digest_sum'] + digest) % (1 << 256)
        local['digest_xor'] ^= digest
        local['events'] += 1
      end
      local
    end
  end

  report['files'] = []
  Dir.glob(File.join(ENV.fetch('FRONTBACK_LOG_DIR'), '*ChannelMgr.log*')).sort.each do |path|
    basename = File.basename(path)
    next unless basename.include?('FrontChannelMgr') || basename.include?('BackChannelMgr')
    physical = 0
    selected = 0
    sha = Digest::SHA256.new
    File.open(path, 'rb') do |file|
      file.each_line do |raw|
        physical += 1
        sha.update(raw)
        next unless raw.include?('[FT --> FC]') || raw.include?('[FT <-- FC]') || raw.include?('[BC --> BT]') || raw.include?('[BC <-- BT]')
        message = raw.sub(/\r?\n\z/, '').force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
        queue.push([message, path])
        selected += 1
      end
    end
    report['files'] << { 'name' => basename, 'physical_lines' => physical, 'selected_transactions' => selected, 'sha256' => sha.hexdigest }
  end
  workers.times { queue.push(nil) }

  merged = {
    'events' => 0,
    'counts' => Hash.new(0),
    'warnings' => Hash.new(0),
    'errors' => Hash.new(0),
    'message_mutations' => 0,
    'path_mutations' => 0,
    'return_proxy_identity_mismatches' => 0,
    'nice_number_mismatches' => 0,
    'digest_sum' => 0,
    'digest_xor' => 0
  }
  pool.each do |thread|
    local = thread.value
    %w[counts warnings errors].each { |name| local[name].each { |key, value| merged[name][key] += value } }
    %w[events message_mutations path_mutations return_proxy_identity_mismatches nice_number_mismatches].each { |name| merged[name] += local[name] }
    merged['digest_sum'] = (merged['digest_sum'] + local['digest_sum']) % (1 << 256)
    merged['digest_xor'] ^= local['digest_xor']
  end
  %w[digest_sum digest_xor].each { |name| merged[name] = merged[name].to_s(16).rjust(64, '0') }
  report['summary'] = merged
end

report['elapsed_seconds'] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
File.write(ENV.fetch('FRONTBACK_CORE_REPORT'), JSON.pretty_generate(report))
puts JSON.generate(report.reject { |key, _| key == 'contracts' })
raise 'contract failures' if report.fetch('failed', 0).positive?
