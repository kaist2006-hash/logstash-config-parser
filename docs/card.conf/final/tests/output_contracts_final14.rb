require 'json'
# Run with Logstash 8.17.x JRuby and logstash-core loaded. No source logs required.
dir=ENV.fetch('CARD_PARSER_DIR',File.expand_path('..',__dir__))
build=lambda do |mode|
 p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
 params={'specs_path'=>File.join(dir,'card_detail_specs.json')};params['diagnostics']=mode if mode
 p.register(params);p
end
full=build.call('full');minimal=build.call(nil)
bitmap=lambda do |bits|
 width=bits.max>64 ? 128 : 64
 active=bits.dup;active << 1 if width>64
 bytes=Array.new(width/8,0);active.each{|b|bytes[(b-1)/8] |= 128>>((b-1)%8)}
 bytes.pack('C*').unpack1('H*').upcase
end
cases=[]
check=lambda do |name,route,body,expected,block|
 message="put(data[#{body}] len[#{body.encode('CP949').bytesize}])"
 results=[full,minimal].map do |p|
  e=LogStash::Event.new('message'=>message,'@metadata'=>{'target_alias'=>route});p.filter(e)
  raise 'message changed' unless e.get('message')==message
  raise 'metadata version missing' unless e.get('[@metadata][card_detail_parser_version]')=='2026-10-30.final14'
  [e.get('card_detail'),e.get('tags')]
 end
 d=results[0][0];m=results[1][0]
 raise "#{name}: wrong status" unless d['status']==expected && m['status']==expected
 raise 'business fields differ by output mode' unless d['fields']==m['fields'] && d['emv']==m['emv'] && d['rest']==m['rest'] && results[0][1]==results[1][1]
 raise 'diagnostic leaked' if %w[parser_version bitmap consumed_bytes present_fields frame_status].any?{|k|m.key?(k)}
 raise 'error offsets leaked' if m.fetch('errors',[]).any?{|e|(e.keys-%w[code field]).any?}
 block.call(d)
 cases << {'name'=>name,'status'=>expected,'field_names'=>d.fetch('fields',{}).keys,'minimal_keys'=>m.keys}
end
head='ISO0234000530200'
check.call('error_stops_after_invalid_currency','s_service_win_ms',head+bitmap.call([3,49,56])+'000000'+'ABC'+'008TEST0001','error',lambda{|d|
 raise 'field after bad currency exported' unless d['fields'].keys==['processing_code']
 raise 'wrong error field' unless d['errors'].first['field']==49
})
domestic='00'+'1234567890'+'0'*24+' '*68
domestic=domestic[0,104]
nh='0'*9+'ISO000000000'+'0400'+bitmap.call([3,118,124])+'000000'+'104'+domestic
tlv='012'+'9F3303E0F0C8'
check.call('nh_document_slot_padding','s_service_nlc_ic',nh+' '*7+tlv,'fallback',lambda{|d|
 raise 'padding missing' unless d['document_padding_bytes']==7
 raise 'TLV not recovered' unless d['emv']['terminal_capabilities']=='E0F0C8'
 raise 'unexpected errors' if d['errors']
})
check.call('nh_bad_padding_is_error','s_service_nlc_ic',nh+' '*6+'X'+tlv,'error',lambda{|d|
 raise 'bad compound field survived' unless d['fields'].keys==['processing_code']
 raise 'wrong padding error' unless d['errors'].last['code']=='invalid_field_slot_padding'
})
check.call('nh_short_padding_falls_back','s_service_nlc_ic',nh+' '*3,'fallback',lambda{|d|
 raise 'wrong short padding code' unless d['errors'].last['code']=='truncated_field'
 raise 'short compound field survived' unless d['fields'].keys==['processing_code']
})
bad_domestic='00'+'1234567890'+'X'*12+'0'*12+' '*75
body='0'*9+'ISO000000000'+'0400'+bitmap.call([3,118])+'000000'+'111'+bad_domestic
check.call('compound_field_atomic_failure','s_service_nlc_ic',body,'error',lambda{|d|
 raise 'partial invalid compound exported' unless d['fields'].keys==['processing_code']
})
{'s_service_keb_sum'=>11,'s_service_din_ms'=>10,'s_service_lgc_ms'=>10}.each do |route,width|
 profile=full.instance_variable_get(:@profiles)[route]
 header=profile.fetch('expected_headers',['ISO023400053']).first
 mti=profile['mtis'].first
 binary=profile['wire']=='binary'
 maps=bitmap.call([3,42])
 prefix=(header+(binary ? [mti].pack('H*') : mti)+(binary ? [maps].pack('H*') : maps)+(binary ? ['000000'].pack('H*') : '000000')).b
 identifier='12345678901'[0,width]
 merchant=identifier+'A'*(15-width)
 result={'direction'=>'OUT'}
 full.card_parse(prefix+merchant.b,profile,result)
 raise 'merchant flags included in identifier' unless result['fields']['merchant_number']==identifier
 invalid={'direction'=>'OUT'}
 full.card_parse(prefix+identifier.b+"\xFF".b+'A'*(14-width),profile,invalid)
 raise 'unexported flag bytes not validated' unless invalid.fetch('errors',[]).any?{|e|e['code']=='invalid_ascii_value'&&e['field']==42}
 raise 'invalid merchant field survived' if invalid.fetch('fields',{}).key?('merchant_number')
 cases<<{'name'=>'merchant_subfield_'+profile['id'],'identifier_bytes'=>width,'wire_field_bytes'=>15,'result'=>'passed'}
end
profile=full.instance_variable_get(:@profiles)['s_service_lgc_ic']
maps=bitmap.call([3,42]);raw=('ISO023400053'+['0100'].pack('H*')+[maps].pack('H*')+['000000'].pack('H*')+'ABCDEFGHIJKLMNO').b
value={};full.card_parse(raw,profile,value)
raise 'IC merchant was truncated using MS layout' unless value['fields']['merchant_number']=='ABCDEFGHIJKLMNO'
cases<<{'name'=>'shinhan_ic_preserves_independent_15_byte_layout','result'=>'passed'}
report={'result'=>'passed','cases'=>cases}
File.write(ENV['CARD_REPORT_FILE'],JSON.pretty_generate(report)) if ENV['CARD_REPORT_FILE']
puts JSON.pretty_generate(report)
