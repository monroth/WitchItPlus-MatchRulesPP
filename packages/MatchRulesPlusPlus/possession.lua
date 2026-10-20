-- Authoritative abandoned-prop timers. Native gameplay timers are not Lua schedulers.
local M={}
local PROP='/Game/Blueprints/Props/Bases/B_StaticMeshProp.B_StaticMeshProp_C:'
local CORE='/Game/Blueprints/Core/'
function M.init(H,getExtras)
    local function enabled() return not H.feature or H.feature('possession') end
    local api={}; local pending={}; local discover=true
    local Work=H.core and H.core.work_budget; local queued=false;local scanOwner;local again=false
    local function held(guard,T) return T or (guard and H.held(guard) or H) end
    local function current(guard,T) return not guard or guard() and T.current() end
    local function checkpoint(guard,T) assert(current(guard,T),'proposal owner retired') end
    local function read(guard,T,o,key) if guard then return T.read(o,key) end;return o[key] end
    local function write(guard,T,o,key,value) if guard then return T.write(o,key,value) end;o[key]=value end
    local function call(guard,T,o,key,...) if guard then return T.call(o,key,...) end;return o[key](o,...) end
    local function invoke(guard,T,fn,...) checkpoint(guard,T);local v=table.pack(fn(...));checkpoint(guard,T);return table.unpack(v,1,v.n) end
    local guardSerial=0
    local function now(actor)
        return H.now()
    end
    local function timerLibrary(guard,T) local H=held(guard,T);return H.object('/Script/Engine.Default__KismetSystemLibrary') end
    local function lifetime() return getExtras().possessionLifetime or 5 end
    local function work() return enabled() and (lifetime()~=5 or next(pending)~=nil) end
    local function eligible(actor,gm,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        return H.authority(actor) and H.sameWorld(actor,gm) and read(guard,T,actor,'IsControlledByWitch')~=true
    end
    local function apply(r,value,guard,T)
        guard=guard or r.guard;T=T or r.native
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if r.applied==value or not enabled() then return end -- nil/5 preserves the native initial timer exactly
        local actor=r.actor
        local host,_,_,gm=H.host(); if not host or not eligible(actor,gm,guard,T) then return end
        local lib=timerLibrary(guard,T)
        call(guard,T,lib,'K2_ClearTimer',actor,'DissolvePropServer')
        if value~='never' then
            local remaining=value-math.max(0,now(actor)-r.started)
            if remaining<=0 then
                pending[H.key(actor)]=nil
                call(guard,T,actor,'DissolvePropServer')
                return
            end
            -- Same function-name timer as vanilla; ignore its struct return value.
            call(guard,T,lib,'K2_SetTimer',actor,'DissolvePropServer',remaining,false,false,0,0)
        end
        r.applied=value
    end
    function api.start(actor)
        if not enabled() or lifetime()==5 then return end
        local host,_,_,gm=H.host()
        if not host or not eligible(actor,gm) then return end
        local r={actor=actor,started=now(actor),applied=5}
        pending[H.key(actor)]=r
        apply(r,lifetime())
    end
    function api.forget(actor)
        if not next(pending) then return end
        if H.valid(actor) then pending[H.key(actor)]=nil end
    end
    local function advance()
        if not again then return end
        local intent=type(again)=='table' and again or {};again=false
        if not intent.guard or current(intent.guard,intent.T) then
            H.defer(function() if not intent.guard or current(intent.guard,intent.T) then api.scan(false,intent.guard,intent.T) end end)
        end
    end
    function api.scan(synchronous,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if queued then again={guard=guard,T=T};return end
        if not work() then discover=true; return end
        local host,_,_,gm=H.host()
        if not host then pending={}; discover=true; return end
        local value=lifetime();local tasks={};local own={}
        scanOwner=own;queued=true
        local function release()
            if scanOwner~=own then return end
            scanOwner=nil;queued=false
            if not current(guard,T) then discover=true end
            advance()
        end
        local built,builderError=pcall(function()
        if value==5 then discover=true
        elseif discover then
            discover=false
            local lib=timerLibrary(guard,T)
            for _,actor in ipairs(H.findAll('B_StaticMeshProp_C') or {}) do
                tasks[#tasks+1]=function()
                    if eligible(actor,gm,guard,T) and not pending[H.key(actor)] and call(guard,T,lib,'K2_IsTimerActive',actor,'DissolvePropServer') then
                        local elapsed=call(guard,T,lib,'K2_GetTimerElapsedTime',actor,'DissolvePropServer')
                        if type(elapsed)=='number' and elapsed>=0 then
                            local r={actor=actor,started=now(actor)-elapsed,applied=5,guard=guard,native=T}
                            pending[H.key(actor)]=r; apply(r,value,guard,T)
                        end
                    end
                    return true
                end
            end
        end
        for key,r in pairs(pending) do
            tasks[#tasks+1]=function()
                if pending[key]~=r then return true end
                local heldGuard=guard or r.guard;local heldNative=guard and T or r.native
                if not current(heldGuard,heldNative) then if pending[key]==r then pending[key]=nil end;return true end
                if not eligible(r.actor,gm,heldGuard,heldNative) then pending[key]=nil
                else apply(r,value,heldGuard,heldNative); if value==5 then pending[key]=nil end end
                return true
            end
        end
        tasks[#tasks+1]=function()
            release()
            return true
        end
        end)
        if not built then release();error(builderError,0) end
        if synchronous or not Work then
            local ok,err=pcall(function() for _,task in ipairs(tasks) do checkpoint(guard,T);task();checkpoint(guard,T) end end)
            if not ok then release();error(err,0) end
        else
            local step=Work.sequence(tasks)
            local jobKey='mrpp-possession'
            if guard then guardSerial=guardSerial+1;jobKey='mrpp-possession-guard:'..guardSerial end
            local accepted=Work.submit(jobKey,'possession timers',function()
                if scanOwner~=own then return true end
                if not current(guard,T) then tasks={};release();return true end
                local ok,done=pcall(step)
                if not ok then release();error(done,0) end
                return done
            end)
            if not accepted and guard then release();error('possession work rejected') end
        end
    end
    function api.cleanup(synchronous)
        if Work then Work.cancel('mrpp-possession') end
        queued=false;scanOwner=nil;again=false;discover=true
        if not work() then return end
        local host,_,_,gm=H.host(); if not host then return end
        -- Default 5-second timers remain wholly native, including at round end.
        local work=pending; pending={}
        local tasks={}
        for _,r in pairs(work) do tasks[#tasks+1]=function()
            local guard,T=r.guard,r.native
            if not current(guard,T) then return true end
            if r.applied~=5 and eligible(r.actor,gm,guard,T) then H.guard('abandoned prop round cleanup',function()
                checkpoint(guard,T)
                local lib=timerLibrary(guard,T)
                call(guard,T,lib,'K2_ClearTimer',r.actor,'DissolvePropServer')
                call(guard,T,r.actor,'DissolvePropServer')
            end)() end
            return true
        end end
        if synchronous or not Work then for _,task in ipairs(tasks) do task() end
        else Work.submit('mrpp-possession-cleanup','abandoned round cleanup',Work.sequence(tasks)) end
    end
    function api.close()
        if Work then Work.cancel('mrpp-possession'); Work.cancel('mrpp-possession-cleanup') end
        queued=false;scanOwner=nil;again=false;api.scan(true)
    end
    H.hook(PROP..'StartDestroyCountdown',function(self) if work() then api.start(H.unwrap(self)) end end,work)
    H.hook(PROP..'StopDestroyCountdown',function(self) if next(pending) then api.forget(H.unwrap(self)) end end,work)
    H.hook(PROP..'DissolvePropServer',function(self) if next(pending) then api.forget(H.unwrap(self)) end end,work)
    H.hook(CORE..'B_GameState.B_GameState_C:OnMatchEndedMulti',function(self)
        if not work() then return end
        local host,_,gs=H.host()
        if host and H.valid(gs) and H.valid(H.unwrap(self)) and H.key(H.unwrap(self))==H.key(gs) then api.cleanup() end
    end,work)
    H.hook('/Game/Blueprints/Gamemodes/CreativeMode/B_CreativeGameState.B_CreativeGameState_C:TogglePlayTestMultiCast',function(self)
        if not work() then return end
        local host,_,gs=H.creative()
        if host and H.valid(gs) and H.valid(H.unwrap(self)) and H.key(H.unwrap(self))==H.key(gs) and gs.IsPlayTestMode~=true then api.cleanup() end
    end,work)
    -- Native teardown owns cleanup. Do not dereference EndPlay's old actors here.
    function api.reset()
        if Work then Work.cancel('mrpp-possession'); Work.cancel('mrpp-possession-cleanup') end
        queued=false;scanOwner=nil;again=false;pending={};discover=true
    end
    return api
end
return M
