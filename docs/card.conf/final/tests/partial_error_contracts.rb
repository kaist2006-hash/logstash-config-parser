require 'json'
dir=ENV.fetch('CARD_PARSER_DIR',File.expand_path('..',__dir__))
p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
p.register('specs_path'=>File.join(dir,'card_detail_specs.json'))
profiles=p.instance_variable_get(:@profiles)
bitmap=lambda do |bits|
 b=Array.new(bits.max>64 ? 16 : 8,0);active=bits.dup;active<<1 if b.size==16
 active.each{|bit|b[(bit-1)/8]|=128>>((bit-1)%8)};b.pack('C*')
end
events=[]
wrap=lambda do |profile,raw|
 transport=profile['transport'];encoding=profile['_binary'] ? 'hex' : 'text'
 if rule=transport['embedded_length'][encoding]
  raw=(rule['prefix']=='bcd2' ? ['%04d'%raw.bytesize].pack('H*') : '%04d'%raw.bytesize)+raw
 end
 if profile['_binary']
  "len[#{raw.bytesize}][S]==>[#{raw.unpack1('H*')}]"
 else
  "put(data[#{raw}] len[#{raw.bytesize}])"
 end
end
profiles.each_value do |profile|
 fields=profile['compiled'];header=(profile['expected_headers']||['ISO023400053']).first;offset=profile['header_offsets'].min
 maps=bitmap.call([3,4,7]);maps=maps.unpack1('H*').upcase unless profile['_binary']
 mti=profile['mtis'].find{|value|!value.start_with?('08')}||profile['mtis'].first
 mti=[mti].pack('H*') if profile['_binary']
 encode=lambda{|bit,digit|spec=fields[bit];spec['encoding']=='bcd' ? [digit*spec['length']*2].pack('H*') : digit*spec['length']}
 [[3],[3,4]].each do |available|
  raw=' '*offset+header+mti+maps+available.map{|bit|encode.call(bit,bit==4 ? '1' : '0')}.join
  e=LogStash::Event.new('message'=>wrap.call(profile,raw),'@metadata'=>{'target_alias'=>profile['alias']})
  p.filter(e);d=e.get('card_detail')
  expected=available.to_h{|bit|[fields[bit]['emit'],(fields[bit]['encoding']=='bcd' ? (bit==4 ? '1' : '0')*fields[bit]['length']*2 : (bit==4 ? '1' : '0')*fields[bit]['length'])]}
  raise "#{profile['id']} short status #{d}" unless d['status']=='error' && Array(e.get('tags')).include?('error') && !Array(e.get('tags')).include?('fallback')
  raise "#{profile['id']} retained values differ #{d}" unless d.fetch('fields',{})==expected
  events<<{'profile'=>profile['id'],'case'=>'short_common_'+available.size.to_s,'status'=>d['status'],'fields'=>d['fields'].keys}
 end
 [3,4].each do |bad|
  values=[3,4,7].map do |bit|
   if bit==bad
    spec=fields[bit];spec['encoding']=='bcd' ? ['FA'+'00'*(spec['length']-1)].pack('H*') : 'X'+'0'*(spec['length']-1)
   else
    encode.call(bit,bit==4 ? '1' : '0')
   end
  end
  raw=' '*offset+header+mti+maps+values.join
  e=LogStash::Event.new('message'=>wrap.call(profile,raw),'@metadata'=>{'target_alias'=>profile['alias']});p.filter(e);d=e.get('card_detail')
  expected=bad==3 ? {} : {fields[3]['emit']=>encode.call(3,'0').unpack1('H*')}
  expected[fields[3]['emit']]='0'*fields[3]['length'] unless bad==3 || fields[3]['encoding']=='bcd'
  raise "invalid common value leaked #{profile['id']}: #{d}" unless d['status']=='error' && d.fetch('fields',{})==expected
  events<<{'profile'=>profile['id'],'case'=>'invalid_common_'+bad.to_s,'status'=>d['status'],'fields'=>d.fetch('fields',{}).keys}
 end
end
kb=profiles['s_service_cnb_ic']
fake={'iso_header'=>'ISO023400053','mti'=>'0800','present_fields'=>[7,118],'fields'=>{'transmission_datetime'=>'1104123456','terminal_id'=>'DETAIL_ONLY_ID'}}
raise 'non-exportable detail counted as network common evidence' if p.card_common_ready?(kb,fake)
events<<{'profile'=>'kb_ic','case'=>'detail_identifier_is_not_common_evidence','status'=>'error','fields'=>['transmission_datetime']}
iso='ISO000000000'+'0810'+'F23C66812EC098100000000000000400'+' '*60+'20260906035934'+'004850'+'301'+' '*80
[['photo_network',iso,'fallback',%w[transmission_datetime trace_number network_code]],['short_network_date_only',iso[0,122],'error',['transmission_datetime']],['short_network_partial_trace',iso[0,124],'error',['transmission_datetime']],['short_network_complete_trace',iso[0,128],'fallback',%w[transmission_datetime trace_number]]].each do |name,body,status,names|
 raw='NHCARD   '+body
 e=LogStash::Event.new('message'=>"get(data[#{raw}] len[#{raw.bytesize}] uid[])",'@metadata'=>{'target_alias'=>'s_service_nlc_ms'})
 p.filter(e);d=e.get('card_detail')
 raise "#{name}: #{d}" unless d['status']==status && d.fetch('fields',{}).keys.sort==names.sort
 events<<{'profile'=>'nh_ms','case'=>name,'status'=>status,'fields'=>names}
end
report={'result'=>'passed','cases'=>events}
File.write(File.join(dir,'PARTIAL_ERROR_CONTRACTS.json'),JSON.pretty_generate(report))
puts JSON.generate('result'=>'passed','cases'=>events.size)
