-- Convert fresh callback/property scalars only. UObject validity and scalar
-- type are separate contracts; never call IsValid on FString/FName/FText here.
local M={}
local supported={FString=true,FName=true,FText=true}
function M.text(H,input)
    local v=H.unwrap(input)
    if type(v)=='string' then return v end
    assert(type(v)=='userdata' or type(v)=='table','reflected text scalar unavailable')
    local ok,kind=pcall(function() return v:type() end)
    assert(ok and supported[kind],'expected fresh FString/FName/FText scalar')
    local converted,result=pcall(function() return v:ToString() end)
    assert(converted and type(result)=='string','reflected text scalar conversion failed')
    return result
end
return M
