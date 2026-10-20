-- Shared FAPM v1-v6 metadata + a world-scoped scalar bridge (Lua VMs need not be shared).
local M={}
local HOOK='/Game/Blueprints/Gamemodes/ObjectiveMode/B_ObjectiveGameMode.B_ObjectiveGameMode_C:HandleStartMatchOverride'
function M.decode(a,prefix)
    local start=prefix+1; local version=a[start+4]
    if version==5 or version==6 then
        -- Independent VM: validate bounded v5/v6 framing, then reuse the v4 fields.
        local ok,fixed=pcall(function()
            local size=#a-prefix; assert(size>=49 and size<=33000)
            local wire={}
            for i=start,#a do
                local v=a[i]; assert(type(v)=='number' and v%1==0 and v>=0 and v<=255)
                wire[#wire+1]=string.char(v)
            end
            local data=table.concat(wire)
            assert(data:sub(-4)==(version==6 and 'FAP6' or 'FAP5') and string.unpack('<I4',data,#data-7)==size)
            local count,at=string.unpack('<I2',data,40); assert(count<=64)
            local seen={}
            for _=1,count do
                local length; length,at=string.unpack('<I2',data,at)
                assert(length>0 and length<=512 and at+length-1<=#data-8)
                local path=data:sub(at,at+length-1); at=at+length
                assert(path:match('^/Game/[%w_/.%-]+%.[%w_]+_C$') and not seen[path]); seen[path]=true
            end
            if version==6 then
                local coefficient,revision; local remaining=#data-at-7; assert(remaining==12 or remaining==16)
                coefficient,revision,at=string.unpack(remaining==12 and '<fI8' or '<dI8',data,at)
                assert(coefficient==coefficient and math.abs(coefficient)<=100 and revision<=9007199254740991)
            end
            assert(at==#data-7)
            local result={}; for i=1,prefix+39 do result[i]=a[i] end
            result[start+4]=4; return result
        end)
        if not ok then return end
        return M.decode(fixed,prefix)
    end
    if a[start]~=70 or a[start+1]~=65 or a[start+2]~=80 or a[start+3]~=77 or a[start+5]~=1 then return end
    if version==1 and #a==prefix+6 then return nil,0,true end
    local size=({[2]=23,[3]=35,[4]=39})[version]
    if not size or #a~=prefix+size
        or (a[start+6]~=0 and a[start+6]~=1 and a[start+6]~=2) then return end
    local bytes={}
    for i=start+7,#a do
        local v=a[i]; if type(v)~='number' or v%1~=0 or v<0 or v>255 then return end
        bytes[#bytes+1]=string.char(v)
    end
    local data=table.concat(bytes); local r,g,b,alpha=string.unpack('<ffff',data)
    for _,v in ipairs({r,g,b}) do if v~=v or v<0 or v>1 then return end end
    if alpha~=1 then return end
    if version==2 then return nil,0,true end
    local target,revision=string.unpack('<I4I8',data,17)
    if alpha~=1 or target<1 or revision<0 or revision>9007199254740991 then return end
    if version==4 then
        local down,up=string.unpack('<I2I2',data,29)
        if down>2000 or up>2000 then return end
    end
    return target,revision,true
end
function M.init(H,getExtras)
    local api,records={},{}; local bridge,lastWire; local activeWorld,activeOffset,activeGuard,activeNative
    local function held(guard,T) return T or (guard and H.held(guard) or H) end
    local function current(guard,T) return not guard or guard() and T.current() end
    local function checkpoint(guard,T) assert(current(guard,T),'proposal owner retired') end
    local function read(guard,T,o,key) if guard then return T.read(o,key) end;return o[key] end
    local function write(guard,T,o,key,value) if guard then return T.write(o,key,value) end;o[key]=value end
    local function call(guard,T,o,key,...) if guard then return T.call(o,key,...) end;return o[key](o,...) end
    local function invoke(guard,T,fn,...) checkpoint(guard,T);local v=table.pack(fn(...));checkpoint(guard,T);return table.unpack(v,1,v.n) end
    local function work() return (not H.feature or H.feature('cauldronOffset')) and (getExtras().cauldronTargetOffset or 0)~=0 end

    local function context(gm,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not H.class or not H.object then return end -- lightweight optional runtime harnesses
        local host,pc,gs,current,gi=H.host()
        if not host or not H.class(current,'B_ObjectiveGameMode_C') or not H.class(gs,'B_ObjectiveGameState_C')
            or (gm and (not H.authority(gm) or H.key(gm)~=H.key(current))) then return end
        return current,gs,gi
    end
    local function writeBridge(offset,guard,T)
        T=held(guard,T);checkpoint(guard,T)
        local wire='MRPPCT1\n'..tostring(activeWorld)..'\n'..os.time()..'\n'..offset..'\n'
        if wire==lastWire then return end
        local file,err=invoke(guard,T,io.open,bridge..'.tmp','w')
        if not file then error('cauldron offset bridge: '..tostring(err)) end
        assert(invoke(guard,T,function() return file:write(wire) end));assert(invoke(guard,T,function() return file:close() end))
        if not invoke(guard,T,os.rename,bridge..'.tmp',bridge) then
            local dst=assert(invoke(guard,T,io.open,bridge,'w'));assert(invoke(guard,T,function() return dst:write(wire) end));assert(invoke(guard,T,function() return dst:close() end));invoke(guard,T,os.remove,bridge..'.tmp')
        end
        lastWire=wire
    end
    function api.publish(gs,offset,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not work() or offset==0 or not H.valid(gs) then return end
        bridge=bridge or H.module('storage').bridge(H.savedDir())
        local world=call(guard,T,gs,'GetWorld'); if not H.valid(world) then return end
        local address=call(guard,T,world,'GetAddress');checkpoint(guard,T)
        activeWorld=address;activeOffset=offset;activeGuard=guard;activeNative=T
        writeBridge(offset,guard,T)
    end
    function api.heartbeat()
        -- The FaP bridge expires after 3 seconds. Renew cached scalars on the
        -- wall-clock event, without scanning pots or querying any engine objects.
        if current(activeGuard,activeNative) and activeWorld and bridge and work() and getExtras().cauldronTargetOffset==activeOffset then writeBridge(activeOffset,activeGuard,activeNative) end
    end
    function api.base(gs,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not H.valid(gs) then return 3 end
        local target,revision,markers=3,-1,0
        for _,a in ipairs(H.values(H.findAll('BP_WitchCauldron_C') or {})) do
            if H.valid(a) and H.sameWorld(a,gs) and read(guard,T,a,'IsPreview')~=true then
                local n,r,marker=M.decode(H.values(read(guard,T,a,'SavedMaterialIndices') or {}),#H.values(read(guard,T,a,'MaterialOverwrites') or {}))
                if marker then markers=markers+1 end
                if n and r>0 then
                    if r>revision then target,revision=n,r elseif r==revision then target=math.max(target,n) end
                end
            end
        end
        return math.max(1,math.min(markers>0 and markers or target,target))
    end
    function api.apply(gm,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not work() then return end -- zero is wholly vanilla, including file I/O/metadata scans
        local current,gs,gi=context(gm,guard,T); if not current then return end
        local offset=getExtras().cauldronTargetOffset or 0
        api.publish(gs,offset,guard,T)
        local count=0
        for _,pot in ipairs(H.values(read(guard,T,gs,'Cauldrons') or {})) do
            if H.valid(pot) and H.sameWorld(pot,gs) then count=count+1 end
        end
        if count==0 then return end
        local manager=read(guard,T,gi,'ObjectiveMatchManager'); if not H.valid(manager) then return end
        local round=read(guard,T,manager,'CurrentRound')
        if round~=1 and round~=2 then return end
        local ceiling=math.max(1,math.min(count,255,api.base(gs,guard,T)+offset))
        local target=ceiling
        if round==2 then
            local first=H.values(read(guard,T,manager,'RoundStates'))[1]
            if not first then return end
            local filled=read(guard,T,first,'TotalCauldronsFilled');if type(filled)~='number' then return end
            target=math.min(filled+1,ceiling)
        end
        local sig=round..':'..ceiling..':'..target..':'..offset
        local id=H.key(gs)
        if read(guard,T,gs,'CauldronTarget')~=target then
            call(guard,T,gs,'FlushNetDormancy');write(guard,T,gs,'CauldronTarget',target)
            local lib=H.object('/Script/Engine.Default__NetPushModelHelpers');local name=invoke(guard,T,FName,'CauldronTarget')
            call(guard,T,lib,'MarkPropertyDirtyFromRepIndex',gs,46,name)
            call(guard,T,gs,'ForceNetUpdate')
        end
        if records[id]~=sig then records[id]=sig; H.log('Cauldrons to win: round '..round..' target='..target..' ceiling='..ceiling..' offset='..offset) end
        return target
    end
    H.hook(HOOK,function(self) if work() then api.apply(H.unwrap(self)) end end,work)
    function api.scan(guard,T)
        T=held(guard,T);checkpoint(guard,T)
        if work() then api.apply(nil,guard,T)
        elseif activeWorld and bridge then
            -- One-time restoration of our OWN nonzero publication, not idle zero writes.
            local f=io.open(bridge,'r'); local prior=f and f:read('*a'); if f then f:close() end
            if prior and prior:match('^MRPPCT1\n'..activeWorld..'\n') then os.remove(bridge) end
            activeWorld=nil; activeOffset=nil;activeGuard=nil;activeNative=nil;lastWire=nil;records={}
        end
    end
    function api.reset()
        -- No UObject/property/timer calls during native travel/EndPlay callbacks.
        if bridge and activeWorld then
            local f=io.open(bridge,'r'); local prior=f and f:read('*a'); if f then f:close() end
            if prior and prior:match('^MRPPCT1\n'..activeWorld..'\n') then os.remove(bridge) end
        end
        activeWorld=nil;activeOffset=nil;activeGuard=nil;activeNative=nil;records={};lastWire=nil
    end
    if H.lifetime then H.lifetime.onReset(api.reset) end
    return api
end
return M
