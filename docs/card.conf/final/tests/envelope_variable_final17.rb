require 'json'
dir=ENV.fetch('CARD_PARSER_DIR',File.expand_path('..',__dir__))
parsers=[nil,'full'].map do |mode|
 p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
 params={'specs_path'=>File.join(dir,'card_detail_specs.json')};params['diagnostics']=mode if mode;p.register(params);p
end
parse=lambda do |message|
 ds=parsers.map do |p|
  e=LogStash::Event.new('message'=>message,'@metadata'=>{'target_alias'=>'s_service_win_ms'});p.filter(e)
  raise 'input changed' unless e.get('message')==message
  [e.get('card_detail'),Array(e.get('tags'))]
 end
 raise 'diagnostics changed values' unless %w[fields status direction mti].all?{|k|ds[0][0][k]==ds[1][0][k]} && ds[0][1]==ds[1][1]
 ds[1][0]
end
bitmap=lambda{|bits|s='0'*64;bits.each{|b|s[b-1]='1'};[s].pack('B*').unpack1('H*').upcase}
head='ISO0250000530210'
base='000030'+'000000012400'+'0403165948'
report={'result'=>'passed','real_orphan_responses'=>0,'source_lines'=>[],'removed_wrong_fields'=>Hash.new(0),'variable_field_cases'=>0,'negative_boundary_cases'=>0}
rng=Random.new(1730)
config=JSON.parse(File.read(File.join(dir,'card_detail_specs.json')))['profiles'].find{|x|x['id']=='samsung_ms'}
f32max=config['fields']['32']['max'];f35max=config['fields']['35']['max']
160.times do |i|
 amount='%012d'%rng.rand(1..999999999999);date='%02d%02d%02d%02d%02d'%[rng.rand(1..12),rng.rand(1..28),rng.rand(0..23),rng.rand(0..59),rng.rand(0..59)]
 rrn='%012d'%rng.rand(0..999999999999);response=%w[00 05 A1 99][i%4];merchant='M'+'%014d'%rng.rand(0..99999999999999)
 f32='7'*(1+i%f32max);f35='*'*(1+i%f35max);f55=(i%2==0 ? '7' : '12')
 name=' uid[] linename[INSIDE])'.ljust(40)
 processing='%06d'%rng.rand(0..999999)
 values={3=>processing,4=>amount,7=>date,37=>rrn,39=>response,42=>merchant}
 values[32]=('%02d'%f32.bytesize)+f32 unless i%3==0
 values[35]=('%02d'%f35.bytesize)+f35 unless i%5==0
 values[43]=name unless i%7==0
 values[55]=('%03d'%f55.bytesize)+f55 unless i%11==0
 header=(i%3==0 ? 'ISO023400053' : 'ISO025000053')+%w[0200 0210 0400 0410][i%4]
 body=header+bitmap.call(values.keys)+values.sort.map{|k,v|v}.join

 if i.even?
  # Counts vary with both LLVAR fields and F55; post-count bytes must never be parsed.
  buffer=body+"\xFF\xEF".b+'STALE_BUFFER linename[NOT_A_FIELD]'
  text=buffer.force_encoding('CP949').encode('UTF-8',invalid: :replace,undef: :replace,replace:"\uFFFD")
  message="put_msg_complete[#{text}][#{body.bytesize+2}] linename[동적_#{i}]"
 else
  message="get(data[RESPDATA#{body}] len[#{body.bytesize+8}] uid[#{i}] linename[ANY_SERVICE_#{i}])"
 end
 d=parse.call(message)
 raise "variable case #{i}: #{d['status']} #{d['errors']} #{d['warnings']}" unless d['status']=='ok'
 expected={'processing_code'=>processing,'transaction_amount'=>amount,'transmission_datetime'=>date,'retrieval_reference'=>rrn,'response_code'=>response,'merchant_number'=>merchant}
 expected['installment_months']=f55 if values.key?(55)
 expected.each{|k,v|raise "wrong #{k} in #{i}" unless d.fetch('fields',{})[k]==v}
 report['variable_field_cases']+=1
end
short=head+bitmap.call([3,4,7,35,37,39,42,43])+base+'37'+'*'*31
[
 "get(data[#{short} uid[] linename[VARIABLE_NAME])",
 "get(data[#{short}] len[INVALID] uid[other] linename[VARIABLE_NAME])",
 "get(data[#{short}] len[123 uid[] linename[VARIABLE_NAME])",
 "get(data[#{short} fd[999] linename[VARIABLE_NAME])"
].each do |msg|
 d=parse.call(msg);raise 'bad short classification' unless d['status']=='fallback'
 raise 'suffix leaked' if %w[retrieval_reference response_code merchant_number].any?{|k|d.fetch('fields',{}).key?(k)}
 report['negative_boundary_cases']+=1
end
simple=head+bitmap.call([3,4,7])+base
[
 "put_msg_complete[#{simple}XX][#{simple.bytesize+2}] linename[VARIABLE]",
 "put_msg_complete[#{simple}][BADCOUNT] linename[VARIABLE]",
 "put_msg_complete[#{simple[0...-1]}\uFFFD\uFFFD][#{simple.bytesize+2}] linename[VARIABLE]"
].each do |msg|
 d=parse.call(msg);raise 'invalid input accepted as ok' if d['status']=='ok'
 report['negative_boundary_cases']+=1
end
puts JSON.generate(report.reject{|k,v|%w[source_lines real_orphan_responses removed_wrong_fields].include?(k)})
