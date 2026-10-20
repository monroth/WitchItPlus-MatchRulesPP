-- Portable local preset codes; canonical JSON is provided by the runtime encoder.
local M={LIMIT=36864,PREFIX='MRPP1:'}
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function crc(s)
 local c=0xffffffff
 for i=1,#s do c=c~s:byte(i);for _=1,8 do c=(c>>1)~((c&1)==1 and 0xedb88320 or 0)end end
 return string.format('%08x',c~0xffffffff)
end
local function encode(s)
 local out={}
 for i=1,#s,3 do
  local a,b,c=s:byte(i,i+2);local n=(a<<16)|((b or 0)<<8)|(c or 0)
  out[#out+1]=alphabet:sub((n>>18)+1,(n>>18)+1)..alphabet:sub(((n>>12)&63)+1,((n>>12)&63)+1)..(b and alphabet:sub(((n>>6)&63)+1,((n>>6)&63)+1)or '=')..(c and alphabet:sub((n&63)+1,(n&63)+1)or '=')
 end
 return table.concat(out)
end
local function decode(s)
 assert(#s>0 and #s%4==0 and not s:find('[^A-Za-z0-9+/=]'),'corrupt code: invalid base64')
 local out={}
 for i=1,#s,4 do
  local chunk=s:sub(i,i+3);local n=0
  for j=1,4 do local c=chunk:sub(j,j);local v=c=='='and 0 or alphabet:find(c,1,true);assert(v,'corrupt code: invalid base64');n=(n<<6)|(c=='='and 0 or v-1)end
  out[#out+1]=string.char((n>>16)&255)..(chunk:sub(3,3)~='='and string.char((n>>8)&255)or '')..(chunk:sub(4,4)~='='and string.char(n&255)or '')
 end
 local raw=table.concat(out);assert(encode(raw)==s,'corrupt code: noncanonical base64');return raw
end
function M.new(J,clean)
 local C={}
 function C.encode(p)
  local bytes=J.encode(clean(p));assert(#bytes<=M.LIMIT,'preset exceeds 36 KiB')
  return M.PREFIX..encode(bytes)..':'..crc(bytes)
 end
 function C.decode(code)
  assert(type(code)=='string' and #code<=49168,'code exceeds size limit')
  code=code:match('^%s*(.-)%s*$')
  assert(code:sub(1,#M.PREFIX)==M.PREFIX,'unsupported rules code version (expected MRPP1)')
  local payload,sum=code:sub(#M.PREFIX+1):match('^([^:]+):(%x%x%x%x%x%x%x%x)$')
  assert(payload,'corrupt code: missing checksum')
  local bytes=decode(payload);assert(#bytes<=M.LIMIT,'preset exceeds 36 KiB')
  assert(crc(bytes)==sum:lower(),'corrupt code: checksum mismatch')
  local ok,p=pcall(J.decode,bytes);assert(ok,'corrupt code: invalid JSON')
  return clean(p)
 end
 return C
end
return M
