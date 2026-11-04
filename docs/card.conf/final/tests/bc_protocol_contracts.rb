require 'json'
dir=ENV.fetch('CARD_PARSER_DIR',__dir__)
p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
p.register('specs_path'=>File.join(dir,'card_detail_specs.json'),'diagnostics'=>'full')
cases=[]
parse=lambda do |name,message,expected,route='s_service_bcc_ms'|
 e=LogStash::Event.new('message'=>message,'@metadata'=>{'target_alias'=>route})
 p.filter(e);d=e.get('card_detail')
 raise 'message altered' unless e.get('message')==message
 raise "#{name}: #{d['status']} instead of #{expected}: #{d['errors']}" unless d['status']==expected
 raise 'error exports business fields' if expected=='error' && d['fields']
 cases<<{'name'=>name,'status'=>d['status'],'field_count'=>d.fetch('fields',{}).size}
 d
end
bitmap=lambda do |bits|
 width=bits.max>64 ? 128 : 64;active=bits.dup;active<<1 if width>64
 b=Array.new(width/8,0);active.each{|n|b[(n-1)/8]|=128>>((n-1)%8)};b.pack('C*')
end
100.times do |i|
 direction=i.even? ? 'OUT' : 'IN';mti=direction=='OUT' ? '0300' : '0310'
 amount='%016d'%(1000+i);date='1104123456';ref='%012d'%(100000+i)
 values={3=>['000000'].pack('H*'),4=>[amount].pack('H*'),7=>[date].pack('H*'),11=>['%06d'%i].pack('H*'),22=>['0021'].pack('H*'),37=>ref,42=>'123456789012345'}
 values[39]='00' if direction=='IN'
 raw='BCINTMSG0001'+[mti].pack('H*')+bitmap.call(values.keys)+values.sort.map{|_,v|v}.join
 encoded=('%04d'%raw.bytesize)+raw.unpack1('H*').upcase
 verb=direction=='OUT' ? 'put' : 'get'
 a=parse.call('integrated_text_hex_'+i.to_s,"#{verb}(data[#{encoded}] len[#{encoded.bytesize}])",'ok')
 wire=['%04d'%raw.bytesize].pack('H*')+raw
 b=parse.call('integrated_binary_hex_'+i.to_s,"len[#{wire.bytesize}][#{direction=='OUT' ? 'S' : 'R'}]==>[#{wire.unpack1('H*')} ]".sub(' ]',']'),'ok')
 c=parse.call('ic_shared_spec_'+i.to_s,"len[#{wire.bytesize}][#{direction=='OUT' ? 'S' : 'R'}]==>[#{wire.unpack1('H*')}]",'ok','s_service_bcc_ic')
 raise 'integrated fields differ by transport/profile' unless a['fields']==b['fields'] && b['fields']==c['fields'] && a['direction']==direction
 raise 'amount/reference split incorrect' unless a['fields']['transaction_amount']==amount && a['fields']['retrieval_reference']==ref && a['fields']['pos_entry_mode']=='0021'
end
build_fixed=lambda do |auth,direction|
 shift=direction=='IN' ? 8 : 0
 size=auth=='0000' && direction=='IN' ? 512 : 1024
 raw=' '*size
 code=direction=='OUT' ? '0480' : '0481'
 set=lambda{|offset,value|raw[offset+shift,value.bytesize]=value}
 set.call(9,'BCB');set.call(12,code);set.call(16,'000000123456');set.call(28,'20261104123456')
 set.call(80,auth);set.call(84,auth=='0000' ? '2' : '0');set.call(207,'1');set.call(208,'001');set.call(215,'123456789')
 if auth=='0000'
  set.call(85,'1')
  if direction=='IN'
   set.call(42,'00');set.call(276,'000001234567');set.call(288,'0000');set.call(292,'1234567890')
  end
 else
  set.call(235,'000012400');set.call(244,'000012400');set.call(757,'000001240');set.call(766,'000011160')
  if direction=='IN'
   set.call(42,'00');set.call(775,'10.00');set.call(780,'01');set.call(790,'000009876543');set.call(802,'0000')
  end
 end
 raw
end
wrap=lambda{|raw,direction|' '+(direction=='IN' ? 'get' : 'put')+"(data[#{'%04d'%raw.bytesize}#{raw}] len[#{raw.bytesize+4}])"}
%w[0000 M002 M003 0001].each do |auth|
 %w[IN OUT].each do |direction|
  raw=build_fixed.call(auth,direction)
  d=parse.call('fixed_'+auth+'_'+direction,wrap.call(raw,direction),'ok')
  f=d['fields'];raise 'fixed common fields incorrect' unless f['retrieval_reference']=='000000123456' && f['transmission_datetime']=='20261104123456' && f['merchant_number']=='123456789' && f['authentication_type']==auth
  raise 'unused generic amount exported' if auth=='0000' && f['transaction_amount']
  raise 'request response fields exported' if direction=='OUT' && (f['response_code'] || f['authentication_approval_number'] || f['processing_result'])
  if direction=='IN'
   expected=auth=='0000' ? '000001234567' : '000009876543'
   raise 'approval/result offset incorrect' unless f['authentication_approval_number']==expected && f['processing_result']=='0000' && f['response_code']=='00'
  end
 end
end
raw=build_fixed.call('0000','OUT')[0,512]
parse.call('document_general_request_512',wrap.call(raw,'OUT'),'ok')
raw=build_fixed.call('0000','IN')[8..-1]+' '*8
parse.call('document_general_response_origin',wrap.call(raw,'IN'),'ok')
raw=build_fixed.call('0000','IN');raw[8+42,2]='02'
d=parse.call('declined_response_is_valid_log',wrap.call(raw,'IN'),'ok')
raise 'approval leaked from declined response' if d['fields']['authentication_approval_number']
raw=build_fixed.call('M002','OUT');raw[253,12]='000009999999'
d=parse.call('original_approval_only_on_cancellation',wrap.call(raw,'OUT'),'ok')
raise 'original approval exported on normal request' if d['fields']['original_authentication_number']
raw=build_fixed.call('M002','IN');raw[8+802,4]='A000'
d=parse.call('invalid_detail_common_fallback',wrap.call(raw,'IN'),'fallback')
raise 'bad detail survived' if d['fields']['processing_result'] || d['fields']['authentication_approval_number']
raw=build_fixed.call('0000','OUT');raw[28,14]='2026A104123456'
parse.call('invalid_date_error',wrap.call(raw,'OUT'),'error')
raw=build_fixed.call('M002','OUT')[0,120]
parse.call('short_fixed_common_fallback',wrap.call(raw,'OUT'),'fallback')
raw=build_fixed.call('M002','OUT')[0,20]
parse.call('very_short_fixed_error',wrap.call(raw,'OUT'),'error')
raw=build_fixed.call('M002','OUT');raw[80,4]='XXXX'
parse.call('unknown_auth_common_fallback',wrap.call(raw,'OUT'),'fallback')
%w[HDRREQPOLL 0800].each do |marker|
 raw=marker=='0800' ? '0800'+' '*67 : 'HDRREQPOLL'+' '*10
 parse.call('control_'+marker,wrap.call(raw,'OUT'),'control')
end
puts JSON.pretty_generate('result'=>'passed','cases'=>cases)
File.write(ENV['CARD_REPORT_FILE'],JSON.pretty_generate('result'=>'passed','cases'=>cases)) if ENV['CARD_REPORT_FILE']
