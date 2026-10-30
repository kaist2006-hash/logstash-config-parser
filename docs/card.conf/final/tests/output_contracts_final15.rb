require 'json'
# Run with Logstash 8.17.x JRuby and logstash-core loaded. No source logs required.
dir=ENV.fetch('CARD_PARSER_DIR',File.expand_path('..',__dir__))
build=lambda do |mode|
 p=Object.new;p.instance_eval(File.read(File.join(dir,'card_detail_parser.rb')))
 p.register('specs_path'=>File.join(dir,'card_detail_specs.json'),'diagnostics'=>mode);p
end
full=build.call('full');minimal=build.call('minimal')
bitmap=lambda do |bits|
 width=bits.max>64 ? 128 : 64;active=bits.dup;active<<1 if width>64
 bytes=Array.new(width/8,0);active.each{|b|bytes[(b-1)/8]|=128>>((b-1)%8)}
 bytes.pack('C*').unpack1('H*').upcase
end
cases=[]
check=lambda do |name,route,body,status,block|
 length=body.gsub("\uFFFD",'').encode('CP949').bytesize
 message="put(data[#{body}] len[#{length}])"
 results=[full,minimal].map do |p|
  e=LogStash::Event.new('message'=>message,'@metadata'=>{'target_alias'=>route});p.filter(e)
  raise 'message changed' unless e.get('message')==message
  raise 'wrong version' unless e.get('[@metadata][card_detail_parser_version]')=='2026-10-30.final15'
  [e.get('card_detail'),Array(e.get('tags'))]
 end
 d=results[0][0];m=results[1][0]
 raise "#{name}: #{d['status']} instead of #{status}" unless [d['status'],m['status']]==[status,status]
 raise 'business outputs differ by diagnostics mode' unless %w[fields emv rest].all?{|k|d[k]==m[k]} && results[0][1]==results[1][1]
 raise 'diagnostics leaked' if %w[parser_version bitmap consumed_bytes frame_status present_fields].any?{|k|m.key?(k)}
 if status=='fallback'
  raise 'wrong fallback tags' unless results[0][1].include?('fallback') && !results[0][1].include?('error')
  raise 'detail survived fallback' if d['emv'] || d['rest']
  profile=full.instance_variable_get(:@profiles)[route]
  raise 'non-common field survived' unless d.fetch('fields',{}).keys.all?{|k|profile['_fallback_fields'][k]}
 elsif status=='error'
  raise 'wrong error tags' unless results[0][1].include?('error') && !results[0][1].include?('fallback')
  raise 'business output survived error' if d['fields'] || d['emv'] || d['rest']
 end
 block.call(d) if block
 cases<<{'name'=>name,'status'=>status,'fields'=>d.fetch('fields',{}).keys,'codes'=>d.fetch('errors',[]).map{|e|e['code']}}
end
head='ISO0234000530200';base='000000'+'000000001000'+'1030123456';bits=[3,4,7]
check.call('missing_iso_header','s_service_win_ms','garbage','error',nil)
check.call('very_short_common_prefix','s_service_win_ms',head+bitmap.call([3,4])+'000000'+'0000','error',nil)
check.call('short_detail_valid_common','s_service_win_ms',head+bitmap.call(bits+[11])+base+'12','fallback',nil)
check.call('samsung_blank_f55_length','s_service_win_ms',head+bitmap.call(bits+[37,42,49,55])+base+'123456789012'+'1234567890     '+'410'+'   ','fallback',lambda{|d|
 raise 'common amount lost' unless d['fields']['transaction_amount']=='000000001000'
 raise 'F55 cause lost' unless d['errors'].any?{|e|e['field']==55&&e['code']=='invalid_length_prefix'}
})
['00X0000000000010001030123456','00000000000000X0001030123456','0000000000000010001030AB1234'].each_with_index do |bad,i|
 check.call('invalid_required_common_'+i.to_s,'s_service_win_ms',head+bitmap.call(bits)+bad,'error',nil)
end
check.call('unknown_trailer_valid_common','s_service_cnb_ms',head+bitmap.call(bits)+base+'X','fallback',nil)
check.call('invalid_bitmap','s_service_win_ms',head+'Z'*16+base,'error',nil)
check.call('decoding_loss_after_common','s_service_win_ms',head+bitmap.call(bits+[35])+base+"\uFFFD"+'00200','fallback',nil)
check.call('decoding_loss_before_common','s_service_win_ms',head+bitmap.call(bits)+'000000'+"\uFFFD"+base[6..-1],'error',nil)
check.call('invalid_currency_after_valid_common','s_service_win_ms',head+bitmap.call(bits+[49])+base+'ABC','fallback',lambda{|d|
 raise 'invalid currency emitted' if d['fields'].key?('currency_code')
})
nhhead='0'*9+'ISO000000000'
nhbase='000000'+'000000001000'+'20261030123456'
check.call('network_detail_mismatch_common_only','s_service_nlc_ms',nhhead+'0800'+bitmap.call([7,11,70,118])+'20261030123456'+'123456'+'301'+'XXX','fallback',lambda{|d|
 raise 'network reference lost' unless d['fields']['trace_number']=='123456'
})
check.call('very_short_network','s_service_nlc_ms',nhhead+'0800'+bitmap.call([7,11])+'20261030123456'+'12','error',nil)
check.call('network_without_transmission_date','s_service_nlc_ms',nhhead+'0800'+bitmap.call([11,70,118])+'123456'+'301'+'XXX','fallback',nil)
check.call('network_time_and_merchant_common','s_service_nlc_ms',nhhead+'0800'+bitmap.call([12,42,118])+'123456'+'1234567890     '+'XXX','fallback',nil)
check.call('network_context_without_identifier','s_service_nlc_ms',nhhead+'0800'+bitmap.call([7,70,118])+'20261030123456'+'301'+'XXX','error',nil)
domestic=('00'+'1234567890'+'0'*24+' '*68)[0,104]
nh=nhhead+'0400'+bitmap.call(bits+[118,124])+nhbase+'104'+domestic
tlv='012'+'9F3303E0F0C8'
check.call('nh_padding_common_only','s_service_nlc_ic',nh+' '*7+tlv,'fallback',lambda{|d|
 raise 'slot correction lost' unless d['document_padding_bytes']==7 && d['tlv_count']==1
})
check.call('nh_bad_detail_padding_common_only','s_service_nlc_ic',nh+' '*6+'X'+tlv,'fallback',nil)
check.call('nh_short_detail_padding_common_only','s_service_nlc_ic',nh+' '*3,'fallback',nil)
bad_domestic='00'+'1234567890'+'X'*12+'0'*12+' '*75
check.call('compound_detail_failure_common_only','s_service_nlc_ic',nhhead+'0400'+bitmap.call(bits+[118])+nhbase+'111'+bad_domestic,'fallback',nil)
check.call('nh_accepted_rest_remains_ok','s_service_nlc_ms',nhhead+'0100'+bitmap.call(bits)+nhbase+'REST','ok',lambda{|d|
 raise 'rest not preserved' unless d['rest']=='52455354'
})

# Merchant field consumption is independent of the operational fallback policy.
{'s_service_keb_sum'=>11,'s_service_din_ms'=>10,'s_service_lgc_ms'=>10}.each do |route,width|
 profile=full.instance_variable_get(:@profiles)[route];header=profile.fetch('expected_headers',['ISO023400053']).first;mti=profile['mtis'].first
 binary=profile['wire']=='binary';maps=bitmap.call([3,42])
 prefix=(header+(binary ? [mti].pack('H*') : mti)+(binary ? [maps].pack('H*') : maps)+(binary ? ['000000'].pack('H*') : '000000')).b
 id='12345678901'[0,width];value={};full.card_parse(prefix+id+'A'*(15-width),profile,value)
 raise 'merchant flags included' unless value['fields']['merchant_number']==id
 invalid={};full.card_parse(prefix+id+"\xFF".b+'A'*(14-width),profile,invalid)
 raise 'unexported bytes not validated' unless invalid.fetch('errors',[]).any?{|e|e['field']==42&&e['code']=='invalid_ascii_value'}
 cases<<{'name'=>'merchant_boundary_'+profile['id'],'result'=>'passed'}
end
profile=full.instance_variable_get(:@profiles)['s_service_lgc_ic'];value={}
full.card_parse(('ISO023400053'+['0100'].pack('H*')+[bitmap.call([3,42])].pack('H*')+['000000'].pack('H*')+'ABCDEFGHIJKLMNO').b,profile,value)
raise 'IC layout inherited MS truncation' unless value['fields']['merchant_number']=='ABCDEFGHIJKLMNO'
cases<<{'name'=>'shinhan_ic_preserves_15_byte_definition','result'=>'passed'}
report={'result'=>'passed','cases'=>cases}
File.write(ENV['CARD_REPORT_FILE'],JSON.pretty_generate(report)) if ENV['CARD_REPORT_FILE']
puts JSON.pretty_generate(report)
