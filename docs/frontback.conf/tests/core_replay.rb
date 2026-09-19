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

def fb_contract_message(channel, direction, options = {})
  payload = (' ' * 132).b
  transaction_id = '202609191234567890'
  nice = 'T00000000000000001'
  fb_put(payload, 0, transaction_id)
  fb_put(payload, 18, channel == 'front' ? 'ZZ' : options.fetch(:institution, '02'))
  fb_put(payload, 20, nice)
  descriptor = direction == 'response' || channel == 'back' ? 'ID:00025-M0000000A-NICE'.ljust(50) : (' ' * 50)
  fb_put(payload, 38, descriptor)
  fb_put(payload, 88, direction == 'response' || channel == 'back' ? '1' : ' ')
  fb_put(payload, 89, ' ')
  fb_put(payload, 90, options.fetch(:message_class, 'B'))
  fb_put(payload, 91, '00000000000000000000')
  if channel == 'front'
    fb_put(payload, 111, direction == 'request' ? 'ZZ00 ' : 'ZZ012')
    fb_put(payload, 116, direction == 'request' ? options.fetch(:code, '8373') : options.fetch(:code, '0000'))
    fb_put(payload, 120, options.fetch(:partner, 'HOBT').ljust(8))
    endpoints = direction == 'request' ? '[FT --> FC]' : '[FT <-- FC]'
  else
    fb_put(payload, 111, '07002')
    fb_put(payload, 116, options.fetch(:code, '8373'))
    if options[:inline_iso]
      fb_put(payload, 120, 'ISO053020')
      body = "\x02\x00\x01\x02".b
    else
      fb_put(payload, 120, options.fetch(:partner, 'NHCARD').ljust(9))
      fb_put(payload, 129, 'ISO')
      body = options.fetch(:body, '02000000').b
    end
    payload << body
    endpoints = direction == 'request' ? '[BC --> BT]' : '[BC <-- BT]'
  end
  ["20260919 12:34:56,789\t#{nice}\tINFO  \t#{endpoints} |#{payload.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)}", nice]
end

directory = ENV.fetch('FRONTBACK_PARSER_DIR')
parser = Object.new
parser.instance_eval(File.read(File.join(directory, 'frontback_detail_parser.rb')), 'frontback_detail_parser.rb')
parser.register(
  'specs_path' => File.join(directory, 'frontback_detail_specs.json'),
  'source_encoding' => 'ISO-8859-1'
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
    ['front_request', 'front', 'request', {}, { 'status' => 'ok', 'code' => '8373', 'partner_code' => 'HOBT', 'code_role' => 'network_code' }],
    ['front_response', 'front', 'response', { :code => '0000' }, { 'status' => 'ok', 'code' => '0000', 'code_role' => 'response_code', 'session_descriptor_present' => true }],
    ['back_named_ascii', 'back', 'response', { :institution => '02', :partner => 'NHCARD', :body => '02100000' }, { 'status' => 'ok', 'institution_name' => 'KB국민카드', 'partner_code' => 'NHCARD', 'protocol_marker_offset' => 129, 'inner_kind' => 'iso8583_ascii_candidate' }],
    ['back_inline_binary', 'back', 'request', { :institution => '07', :inline_iso => true }, { 'status' => 'ok', 'institution_name' => '신한카드', 'protocol_marker_offset' => 120, 'inner_kind' => 'iso8583_binary_stx' }]
  ]
  results = []
  cases.each do |id, channel, direction, options, expected|
    message, nice = fb_contract_message(channel, direction, options)
    path = "C:/logs/#{channel == 'front' ? 'FrontChannelMgr' : 'BackChannelMgr'}.log"
    event = LogStash::Event.new('message' => message, 'nice_number' => nice, 'log' => { 'file' => { 'path' => path } })
    before = event.get('message')
    returned = parser.filter(event)
    detail = event.get('frontback_detail') || {}
    checks = {
      'fields' => expected.all? { |key, value| detail[key] == value },
      'channel' => detail['channel'] == channel && detail['direction'] == direction,
      'correlation' => detail['correlation_match'] == true,
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
    invalid.register('specs_path' => File.join(directory, 'frontback_detail_specs.json'), 'source_encoding' => 'NOT-A-REAL-ENCODING')
  rescue ArgumentError
    rejected = true
  end
  results << { 'id' => 'invalid_encoding_rejected', 'checks' => { 'rejected' => rejected } }

  report['contracts'] = results
  report['passed'] = results.count { |item| item['checks'].values.all? }
  report['failed'] = results.length - report['passed']
else
  queue = SizedQueue.new(2048)
  pool = workers.times.map do
    Thread.new do |; local, item, message, path, event, before_path, returned, returned_event, detail, key, digest|
      local = {
        'events' => 0,
        'counts' => Hash.new(0),
        'warnings' => Hash.new(0),
        'errors' => Hash.new(0),
        'message_mutations' => 0,
        'path_mutations' => 0,
        'return_proxy_identity_mismatches' => 0,
        'correlation_mismatches' => 0,
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
        local['correlation_mismatches'] += 1 unless detail['correlation_match'] == true
        key = [detail['channel'], detail['direction'], detail['status'], detail['institution_code'], detail['partner_code'], detail['inner_kind']].join('|')
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
    'correlation_mismatches' => 0,
    'digest_sum' => 0,
    'digest_xor' => 0
  }
  pool.each do |thread|
    local = thread.value
    %w[counts warnings errors].each { |name| local[name].each { |key, value| merged[name][key] += value } }
    %w[events message_mutations path_mutations return_proxy_identity_mismatches correlation_mismatches].each { |name| merged[name] += local[name] }
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
