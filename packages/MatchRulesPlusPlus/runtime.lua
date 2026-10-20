-- Consumer policy over Core's lifetime/reflection; all resources belong to MRPP.
local M={}
local CORE='/Game/Blueprints/Core/'
local SUBS={match='/Game/Blueprints/Match/GameRules/MatchRules/B_MatchParametersSubsystem',skills='/Game/Blueprints/Skills/B_SkillParametersSubsystem',mods='/Game/Blueprints/Match/GameRules/GameModifiers/B_ModParametersSubsystem',powerups='/Game/Blueprints/Match/GameRules/PowerupRules/B_PowerupParametersSubsystem'}
function M.init(api)
    local Core=api.shared('Core')
    -- Class-specific birth/EndPlay hooks below avoid global BeginPlay engine work.
    local C=Core.new(api,{install_lifetime=false,budget={ms=6,reserve=3,items=64}})
    local H=C.runtime; H.api=api; H.core=C; H.module=function(n) return api.module(n) end
    H.key=C.lifetime.key; H.same=C.lifetime.same; H.now=C.event_clock.now
    local L=C.lifetime; local hooks,installed,errors={},{},{}
    local TextScalar=api.module('native_scalar')
    function H.text(v)
        if type(v)=='string' then return v end
        local typed,kind=pcall(function() return v:type() end)
        if typed and (kind=='FText' or kind=='FString' or kind=='FName') then return TextScalar.text(H,v) end
        if H.valid(v) then return v:GetFullName() end
        local objectOK,isObject=pcall(function() return type(v:IsValid())=='boolean' end)
        assert(not (objectOK and isObject),'stale reflected object cannot be converted to text')
        local ok,s=pcall(function() return v:ToString() end)
        assert(ok and type(s)=='string','cannot convert reflected text'); return s
    end
    function H.class(o,name) return H.valid(o) and o:GetClass():GetFName():ToString()==name end
    function H.guard(key,fn)
        return function(...)
            local args=table.pack(...); local ok,result=pcall(function() return fn(table.unpack(args,1,args.n)) end)
            if not ok and (not errors[key] or os.time()-errors[key]>=30) then
                errors[key]=os.time(); api.log('ERROR '..key..': '..tostring(result))
            end
            if ok then return result end
        end
    end
    local pending={}
    local function queued(schedule,fn)
        local token={}; local stop
        stop=schedule(function() token.done=true; pending[token]=nil; fn() end)
        local function cancel() pending[token]=nil; stop() end
        if not token.done then pending[token]=cancel end
        return cancel
    end
    local function later(ms,fn) return queued(function(callback) return api.delay(ms,callback) end,fn) end
    function H.defer(fn)
        local epoch=L.epoch
        return later(1,function() if epoch==L.epoch and not L.transition then fn() end end)
    end
    L.onReset(function()
        local jobs=pending; pending={}
        for _,cancel in pairs(jobs) do cancel() end
    end)
    function H.hook(path,callback,enabled,options,validate)
        hooks[#hooks+1]={path=path,fn=callback,enabled=enabled or function() return true end,options=options,validate=validate}
    end
    function H.travelAdapter(before,ready) H.beforeTravel=before; H.destinationReady=ready end
    function H.group(name)
        local group=setmetatable({},{__index=H})
        function group.hook(path,fn,active,options,validate)
            H.hook(path,fn,function() return (not H.feature or H.feature(name)) and (not active or active()) end,options,validate)
        end
        return group
    end
    local OUT={GetPickupSpawnDelay={2},GetRoundEndTimerUntilRestart={2},GetSkillCooldown={4}}
    function H.retryHooks()
        if not api.is_active() then return end
        for _,r in ipairs(hooks) do
            if not installed[r] and r.enabled() and not (H.menuDriver and r.path:find('/Game/Blueprints/',1,true)) then
                local opts=r.options or {out_params=OUT[r.path:match(':([^:]+)$')]}
                installed[r]=api.hook(r.path,function(self,...)
                    -- Pure Lua feature gate before unwrap/validation.
                    if not r.enabled() or L.transition then return end
                    if self~=nil then
                        if r.validate then if not r.validate(self) then return end
                        elseif not H.valid(H.unwrap(self)) then return end
                    end
                    if H.wake then H.wake() end
                    return r.fn(self,...)
                end,opts)
            end
        end
        -- Retry existing owned channels; never allocate/cancel throwaway subscribers.
        api.retry_hooks()
    end
    function H.installTravel(enabled)
        if not enabled then return end
        for _,path in ipairs({'/Script/Engine.GameplayStatics:OpenLevel','/Script/Engine.PlayerController:ClientTravel','/Script/Engine.PlayerController:ClientTravelInternal'}) do
            api.hook(path,function() if H.beforeTravel then H.beforeTravel() end; L.begin('native travel PRE') end,{phase='pre',ungated=true})
        end
    end
    local paths={
        B_GameState_C='/Game/Blueprints/Core/B_GameState.B_GameState_C',
        B_ObjectiveGameState_C='/Game/Blueprints/Gamemodes/ObjectiveMode/B_ObjectiveGameState.B_ObjectiveGameState_C',
        B_CreativeGameState_C='/Game/Blueprints/Gamemodes/CreativeMode/B_CreativeGameState.B_CreativeGameState_C',
        B_PlayerController_C='/Game/Blueprints/Player/B_PlayerController.B_PlayerController_C',
        B_ObjectivePlayerController_C='/Game/Blueprints/Gamemodes/ObjectiveMode/B_ObjectivePlayerController.B_ObjectivePlayerController_C',
        B_CreativePlayerController_C='/Game/Blueprints/Gamemodes/CreativeMode/B_CreativePlayerController.B_CreativePlayerController_C',
        B_MenuPlayerController_C='/Game/Blueprints/Player/B_MenuPlayerController.B_MenuPlayerController_C',
        B_StaticMeshProp_C='/Game/Blueprints/Props/Bases/B_StaticMeshProp.B_StaticMeshProp_C',
        B_Hunter_C='/Game/Blueprints/Player/Pawns/B_Hunter.B_Hunter_C',
        B_Witch_C='/Game/Blueprints/Player/Pawns/B_Witch.B_Witch_C',
        B_PropPawnPhysics_C='/Game/Blueprints/Player/Pawns/B_PropPawnPhysics.B_PropPawnPhysics_C',
        B_CreativePropPawnPhysics_C='/Game/Blueprints/Gamemodes/CreativeMode/B_CreativePropPawnPhysics.B_CreativePropPawnPhysics_C',
        B_PotatoSkill_C='/Game/Blueprints/Skills/Hunter/Potato/B_PotatoSkill.B_PotatoSkill_C',
        B_FlySkill_C='/Game/Blueprints/Skills/Witch/Fly/B_FlySkill.B_FlySkill_C',
        B_CannonballSkill_C='/Game/Blueprints/Skills/Hunter/Cannonball/B_CannonballSkill.B_CannonballSkill_C',
        BP_WitchCauldron_C='/Game/Blueprints/StaticProps/Placeable/StaticProps/BP_WitchCauldron.BP_WitchCauldron_C',
        WB_QuestionDialog_C='/Game/UserInterface/Information/WB_QuestionDialog.WB_QuestionDialog_C',
        WB_CreativeIngameMenu_C='/Game/UserInterface/CreativeMode/WB_CreativeIngameMenu.WB_CreativeIngameMenu_C',
    }
    local controllers={B_PlayerController_C=true,B_ObjectivePlayerController_C=true,B_CreativePlayerController_C=true,B_MenuPlayerController_C=true}
    local states={B_GameState_C=true,B_ObjectiveGameState_C=true,B_CreativeGameState_C=true}
    paths.B_GameInstance_C='/Game/Blueprints/Core/B_GameInstance.B_GameInstance_C'
    -- Stable registration order makes call numbers comparable between live runs.
    local pathKeys={}; for key in pairs(paths) do pathKeys[#pathKeys+1]=key end; table.sort(pathKeys)
    setmetatable(paths,{__pairs=function()
        local index=0
        return function() index=index+1; local key=pathKeys[index]; if key then return key,paths[key] end end
    end})
    local persistent={B_GameInstance_C=true}
    -- Controllers are world-owned. A retained menu controller can be freed after
    -- travel even though UE4SS IsValid only tests its non-null stored pointer.
    local registryApi=setmetatable({notify=function(path,fn,opts)
        return api.notify(path,function(object)
            -- Constructor notifications are not destination readiness. Do not
            -- unwrap/validate/reflection-walk objects while travel is latched.
            if L.transition then return end
            -- Runtime's native-frame barrier has completed construction before
            -- this subscriber runs. Destination readiness still gates tracking.
            fn(object)
        end,opts)
    end},{__index=api})
    local inventory=Core.registry.new(registryApi,L,paths,{persistent=persistent,ready_events=false})
    H.registry=inventory
    local cachedWorld
    local startupInventoryReady
    local function track(cls,o,ready)
        inventory.track(o,cls,ready)
    end
    H.admit=function(cls,o)
        if controllers[cls] and H.call(o,'IsLocalPlayerController')==true then L.observe(o,H.now()) end
        track(cls,o,true)
    end
    function H.findAll(cls)
        local out={}
        for _,o in ipairs(inventory.list(cls)) do
            local meta=inventory.metadata[cls][L.key(o)]
            if meta and meta.ready then out[#out+1]=o end
        end
        return out
    end
    function H.resync(done)
        if done then
            local W=H.core.work_budget
            local complete,epoch,step=false,nil,nil
            local function start()
                if complete or L.transition or not L.world or W.keys['startup-inventory'] then return end
                epoch=L.epoch
                local steps={}
                for cls in pairs(paths) do
                    local snapshot
                    steps[#steps+1]=W.native(function() snapshot=H.values(api.find_all(cls)) end)
                    steps[#steps+1]=W.defer(function() return W.each(snapshot,function(o) track(cls,o,true) end) end)
                end
                steps[#steps+1]=function() complete=true; done(); return true end
                step=W.sequence(steps)
                W.submit('startup-inventory','MRPP startup inventory',function()
                    if L.transition or epoch~=L.epoch then step=nil; return true end
                    return step()
                end)
            end
            -- Wait for concrete destination evidence; never spin during travel.
            L.onReset(function() step=nil; W.cancel('startup-inventory') end)
            startupInventoryReady=start
            api.on('world_ready',start,{ungated=true})
            start()
            return
        end
        -- Explicit startup/command bootstrap only. No timer calls this function.
        for cls in pairs(paths) do for _,o in ipairs(H.values(api.find_all(cls))) do track(cls,o,true) end end
    end
    local function scheduleReady(cls,id,epoch,passes)
        -- Retain identity only. Epoch is checked BEFORE touching inventory or
        -- calling any engine method; a reset cancels and clears the Lua closure.
        if not id then return end
        local sample=H.now()
        later(500,function()
            if epoch~=L.epoch then return end
            local object=inventory.buckets[cls] and inventory.buckets[cls][id]
            if not object or not L.rawValid(object) then return end
            if not L.observe(object,math.max(H.now(),sample+.5)) then
                if passes>1 then scheduleReady(cls,id,epoch,passes-1) end
                return
            end
            cachedWorld=nil; track(cls,object,true)
            if startupInventoryReady then startupInventoryReady() end
            if H.destinationReady then H.destinationReady() end
            if H.wake then H.wake() end
        end)
    end
    for cls,path in pairs(paths) do
        if cls:match('^WB_') then
            api.hook(path..':Construct',function(param) if not L.transition then track(cls,H.unwrap(param),true) end end)
            api.hook('/Script/UMG.UserWidget:Destruct',function(param)
                if L.transition then return end -- reset already removed departing widget buckets
                local object=H.unwrap(param); if L.key(object) then inventory.remove(object) end
            end,{ungated=true})
        end
    end
    -- Actor lifecycle is a native runtime event, not an optional Blueprint
    -- ReceiveBeginPlay/ReceiveEndPlay override on every declared class.
    local actorKinds,actorBuckets,births={},{},{}
    L.onReset(function() births={} end)
    local function actorKind(o,className)
        local known=actorKinds[className]
        if known~=nil then return known,actorBuckets[className] end
        if paths[className] and className~='B_GameInstance_C' and not className:match('^WB_') then
            known=states[className] and 'state' or controllers[className] and 'controller' or 'actor'
            actorBuckets[className]=className
        else
            -- Resolve inheritance once per concrete class, including subclasses
            -- whose constructor notification has not yet been delivered.
            known=false
            for cls,path in pairs(paths) do
                if cls~='B_GameInstance_C' and not cls:match('^WB_') and H.call(o,'IsA',path)==true then
                    known=states[cls] and 'state' or controllers[cls] and 'controller' or 'actor';actorBuckets[className]=cls;break
                end
            end
        end
        actorKinds[className]=known;return known,actorBuckets[className]
    end
    api.on('begin_play_post',function(param,className)
        if not className or className=='' or actorKinds[className]==false then return end
        local o=H.unwrap(param);if not L.rawValid(o) then return end
        if className=='Object' or className=='Actor' then
            className=H.call(H.call(H.call(o,'GetClass'),'GetFName'),'ToString')
            if not className or actorKinds[className]==false then return end
        end
        local kind,bucket=actorKind(o,className);if not kind then return end
        local key=L.key(o);if not key or births[key]==L.epoch then return end
        if kind=='state' or kind=='controller' and o:IsLocalPlayerController()==true then
            L.destination(o);L.observe(o,H.now());cachedWorld=nil
        end
        key=inventory.track(o,nil,true);if not key then return end
        births[key]=L.epoch
        if kind=='state' or kind=='controller' and o:IsLocalPlayerController()==true then
            scheduleReady(bucket,key,L.epoch,4)
        end
        if H.actorChanged then H.actorChanged() end
        if H.wake then H.wake() end
    end,{ungated=true})
    api.on('end_play_pre',function(param)
        if L.transition then return end -- no departing-world reflection after reset
        -- Native EndPlay PRE owns a currently executing actor. It may already
        -- be marked IsActorBeingDestroyed, so ordinary liveness rejects it.
        -- Read only its identity, as Registry.remove does, and use cached world
        -- membership rather than querying a dying actor's world/owner chain.
        local o=H.unwrap(param)
        local address,name=H.call(o,'GetAddress'),H.call(o,'GetFullName')
        if not address or not name then return end
        local key=tostring(address)..':'..name
        local owned,boundary=false,false
        for cls,bucket in pairs(inventory.buckets) do
            if bucket[key] then
                owned=true
                local meta=inventory.metadata[cls][key]
                if meta and L.world and meta.world==L.world then
                    if controllers[cls] and H.call(o,'IsLocalPlayerController')==true then boundary=true end
                    if states[cls] then
                        local nativeKey=WIR_RUNTIME.state_key
                        -- Runtime's native identity is the departure authority. A
                        -- cached world may already be superseded during teardown.
                        if nativeKey and nativeKey==tostring(address)..'|'..name then boundary=true end
                    end
                end
            end
        end
        if not owned then return end
        if boundary then
            if H.beforeTravel then H.beforeTravel() end;L.begin('controller EndPlay')
        end
        inventory.remove(o);L.retire(o)
        L.retired[key]=true -- retain the identity even if destruction flags reject L.key

    end,{ungated=true})
    api.on('load_map_pre',function() if H.beforeTravel then H.beforeTravel() end; L.begin('LoadMap PRE') end,{ungated=true})
    api.on('load_map_post',function()
        L.departed={}; L.retired={}; L.blocked=nil; L.world=nil
        if H.wake then H.wake() end
    end,{ungated=true})
    -- Runtime observes InitGameState/GameState birth, including Objective round travel.
    api.on('world_changed',function()
        if H.beforeTravel then H.beforeTravel() end
        L.begin('runtime world changed')
    end,{ungated=true})
    api.on('world_ready',function(actor)
        if not L.rawValid(actor) then return end
        local world=L.worldKey(actor); if not world then return end
        L.blocked=nil; L.departed[world]=nil
        local state=H.read(actor,'GameState')
        local destination=L.rawValid(state) and state or actor
        L.destination(destination); L.observe(destination,H.now())
        local pc=WIR_RUNTIME.input and WIR_RUNTIME.input.controller
        if L.rawValid(pc) then
            L.menuReady(pc)
            for cls in pairs(controllers) do if H.class(pc,cls) then track(cls,pc,true) end end
        end
        for cls in pairs(states) do if H.class(destination,cls) then track(cls,destination,true) end end
        for cls in pairs(states) do
            if H.class(destination,cls) then scheduleReady(cls,L.key(destination),L.epoch,4); break end
        end
    end,{ungated=true})
    L.onReset(function() cachedWorld=nil end)
    -- An immutable held owner guard is explicit per Native walk. No global guard
    -- state or UObject proxy changes unrelated callers or reentrant owners.
    function H.held(guard)
        assert(type(guard)=='function','held owner guard required')
        local G=assert(Core.guarded_native,'Core guarded Native factory required').new(api,L,guard)
        local T=setmetatable({native_guard=G},{__index=H})
        local function checked(fn)
            assert(G.current(),'proposal owner retired')
            local values=table.pack(fn())
            assert(G.current(),'proposal owner retired')
            return table.unpack(values,1,values.n)
        end
        T.current=G.current;T.native=checked
        for _,name in ipairs({'read','call','unwrap','valid','key','worldKey','authority','sameWorld'}) do
            T[name]=function(...) local args=table.pack(...);return checked(function() return G[name](table.unpack(args,1,args.n)) end) end
        end
        function T.write(o,key,value) return checked(function() o[key]=value end) end
        function T.object(path)
            local o=checked(function() return StaticFindObject(path) end)
            assert(T.valid(o),'object unavailable: '..path);return o
        end
        function T.text(v)
            if type(v)=='string' then assert(G.current(),'proposal owner retired');return v end
            if T.valid(v) then return T.call(v,'GetFullName') end
            return checked(function() return G.text(v) end)
        end
        function T.class(o,name)
            if not T.valid(o) then return false end
            local cls=T.call(o,'GetClass');local n=T.call(cls,'GetFName')
            return T.call(n,'ToString')==name
        end
        function T.values(array)
            local out={};if not array then return out end
            local each=T.read(array,'ForEach')
            if type(array)=='table' and not each then
                for _,v in ipairs(array) do out[#out+1]=T.unwrap(v) end
            elseif type(each)=='function' or type(each)=='userdata' then
                checked(function() each(array,function(_,v) out[#out+1]=T.unwrap(v) end) end)
            end
            return out
        end
        function T.findAll(cls)
            local out={};assert(G.current(),'proposal owner retired')
            local bucket=inventory.buckets[cls] or {};local meta=inventory.metadata[cls] or {}
            local keys={};for key in pairs(bucket) do keys[#keys+1]=key end;table.sort(keys)
            for _,key in ipairs(keys) do
                local r=meta[key]
                if r and r.ready and T.valid(bucket[key]) then out[#out+1]=bucket[key] end
            end
            return out
        end
        function T.world()
            if cachedWorld and T.authority(cachedWorld[1])==cachedWorld.authority
                and T.valid(cachedWorld[1]) and T.valid(cachedWorld[2]) then return table.unpack(cachedWorld,1,4) end
            local g=T.object('/Script/Engine.Default__GameplayStatics')
            for cls in pairs(controllers) do for _,pc in ipairs(T.findAll(cls)) do
                if T.call(pc,'IsLocalPlayerController') then
                    local gs=T.call(g,'GetGameState',pc)
                    if T.valid(gs) and T.sameWorld(pc,gs) then
                        local gm=T.call(g,'GetGameMode',pc);local gi=T.call(g,'GetGameInstance',pc)
                        if not T.valid(gm) or not T.sameWorld(pc,gm) then gm=nil end
                        if not T.valid(gi) then gi=nil end
                        -- Admission is an independent lifecycle producer; this held
                        -- consumer only observes already owned objects.
                        return pc,gs,gm,gi
                    end
                end
            end end
        end
        function T.host()
            local pc,gs,gm,gi=T.world()
            return T.authority(pc) and T.authority(gs) and T.authority(gm) and T.valid(gi)
                and (T.read(gi,'IsCustomMatch')==true or T.class(gm,'B_CreativeGameMode_C')),pc,gs,gm,gi
        end
        function T.creative()
            local pc,gs,gm,gi=T.world()
            return T.authority(pc) and T.authority(gs) and T.authority(gm)
                and T.class(gm,'B_CreativeGameMode_C') and T.class(gs,'B_CreativeGameState_C'),pc,gs,gm,gi
        end
        function T.spawnRules(outer)
            assert(T.valid(outer),'stale rules outer')
            local lib=T.object('/Script/Engine.Default__GameplayStatics')
            local cls=T.object('/Game/Blueprints/Match/GameRules/B_GameRules.B_GameRules_C')
            return T.call(lib,'SpawnObject',cls,outer)
        end
        function T.savedDir()
            local lib=T.object('/Script/Engine.Default__KismetSystemLibrary')
            return T.text(T.call(lib,'GetProjectSavedDirectory'))
        end
        function T.retryHooks()
            if not api.is_active() then return end
            for _,r in ipairs(hooks) do
                assert(G.current(),'proposal owner retired')
                if not installed[r] and r.enabled() and not (H.menuDriver and r.path:find('/Game/Blueprints/',1,true)) then
                    local opts=r.options or {out_params=OUT[r.path:match(':([^:]+)$')]}
                    local stop=checked(function() return api.hook(r.path,function(self,...)
                        if not r.enabled() or L.transition then return end
                        if self~=nil then
                        if r.validate then if not r.validate(self) then return end
                        elseif not H.valid(H.unwrap(self)) then return end
                    end
                        if H.wake then H.wake() end;return r.fn(self,...)
                    end,opts) end)
                    installed[r]=stop
                end
            end
            checked(api.retry_hooks)
        end
        return T
    end
    function H.world()
        if L.transition then return end
        if cachedWorld and cachedWorld.authority==H.authority(cachedWorld[1]) and H.valid(cachedWorld[1]) and H.valid(cachedWorld[2]) then return table.unpack(cachedWorld,1,4) end
        local g=H.object('/Script/Engine.Default__GameplayStatics')
        for cls in pairs(controllers) do for _,pc in ipairs(H.findAll(cls)) do
            if pc:IsLocalPlayerController() then
                local gs=g:GetGameState(pc)
                if H.valid(gs) and H.sameWorld(pc,gs) then
                    local gm,gi=g:GetGameMode(pc),g:GetGameInstance(pc)
                    if not H.valid(gm) or not H.sameWorld(pc,gm) then gm=nil end
                    if not H.valid(gi) then gi=nil else inventory.track(gi,'B_GameInstance_C',true) end
                    cachedWorld={pc,gs,gm,gi,authority=H.authority(pc)}; L.observe(pc,H.now()); return pc,gs,gm,gi
                end
            end
        end end
    end
    function H.creative()
        local pc,gs,gm,gi=H.world()
        return H.authority(pc) and H.authority(gs) and H.authority(gm)
            and H.class(gm,'B_CreativeGameMode_C') and H.class(gs,'B_CreativeGameState_C'),pc,gs,gm,gi
    end
    function H.host()
        local pc,gs,gm,gi=H.world()
        return H.authority(pc) and H.authority(gs) and H.authority(gm) and H.valid(gi)
            and (gi.IsCustomMatch==true or H.class(gm,'B_CreativeGameMode_C')),pc,gs,gm,gi
    end
    function H.parameters(context)
        local lib=H.object('/Script/Engine.Default__SubsystemBlueprintLibrary'); local objects={}
        for cat,p in pairs(SUBS) do
            local name=p:match('([^/]+)$'); local cls=H.object(p..'.'..name..'_C')
            assert(H.valid(context),'stale subsystem context')
            local sub=lib:GetWorldSubsystem(context,cls)
            assert(H.valid(sub) and H.sameWorld(sub,context),'missing '..cat..' subsystem'); objects[cat]=sub
        end
        return objects
    end
    function H.spawnRules(outer)
        assert(H.valid(outer),'stale rules outer')
        return H.object('/Script/Engine.Default__GameplayStatics'):SpawnObject(
            H.object('/Game/Blueprints/Match/GameRules/B_GameRules.B_GameRules_C'),outer)
    end
    function H.savedDir() return H.text(H.object('/Script/Engine.Default__KismetSystemLibrary'):GetProjectSavedDirectory()) end
    return H
end
function M.extras(H,getExtras,Possession,allowPrediction)
    local api={}; local originals={}; local potatoDefault; local pacingDefault
    local guardSerial=0
    local function held(guard,T) return T or (guard and H.held(guard) or H) end
    local function current(guard,T) return not guard or guard() and T.current() end
    local function checkpoint(guard,T) assert(current(guard,T),'proposal owner retired') end
    local function read(guard,T,o,key) if guard then return T.read(o,key) end;return o[key] end
    local function write(guard,T,o,key,value) if guard then return T.write(o,key,value) end;o[key]=value end
    local function call(guard,T,o,key,...) if guard then return T.call(o,key,...) end;return o[key](o,...) end
    local function invoke(guard,T,fn,...) checkpoint(guard,T);local out=table.pack(fn(...));checkpoint(guard,T);return table.unpack(out,1,out.n) end
    local function group(name) return H.group and H.group(name) or H end
    local function enabled(name) return not H.feature or H.feature(name) end
    local E=group('extras')
    local cauldrons=H.module('cauldrons').init(group('cauldronOffset'),getExtras)
    local possession=Possession and Possession.init(group('possession'),getExtras)
    local function potatoWork()
        local v=getExtras().potatoRecharge
        return enabled('extras') and ((v~=nil and v~=potatoDefault) or next(originals)~=nil)
    end
    local function pacingWork()
        local e=getExtras()
        return enabled('extras') and e.pickupMin~=nil and (not pacingDefault or e.pickupMin~=pacingDefault.min or e.pickupJitter~=pacingDefault.jitter)
    end
    local function roundWork() local v=getExtras().roundDelay; return enabled('extras') and v~=nil and v~=22 end
    local function cooldownWork() local v=getExtras().cooldownMin; return enabled('extras') and v~=nil and v~=.02 end
    function api.patchPotato(skill,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not potatoWork() or not H.valid(skill) then return end
        local host,pc,_,gm=H.host()
        if not H.sameWorld(skill,host and gm or pc) then return end
        if host then if not H.authority(skill) then return end
        else
            if not H.valid(pc) then return end
            local ok,owner=pcall(function() return call(guard,T,skill,'GetOwner') end)
            checkpoint(guard,T)
            if not ok or not H.valid(owner) or not H.sameWorld(owner,skill) or not call(guard,T,owner,'IsLocallyControlled') then return end
        end
        local key=H.key(skill); local r=originals[key]; local value=getExtras().potatoRecharge
        if not host and (not allowPrediction or not allowPrediction()) then value=nil end
        if not r and (value==nil or value==read(guard,T,skill,'StaminaRecharge')) then return end
        if not r or not H.valid(r.object) then r={object=skill,value=read(guard,T,skill,'StaminaRecharge')}; originals[key]=r end
        local target=value~=nil and value or r.value
        if read(guard,T,skill,'StaminaRecharge')~=target then write(guard,T,skill,'StaminaRecharge',target) end
        if value==nil or value==r.value then originals[key]=nil end
    end
    local potato='/Game/Blueprints/Skills/Hunter/Potato/B_PotatoSkill.B_PotatoSkill_C:'
    for _,event in ipairs({'InitializeRules','ReceiveBeginPlay'}) do
        E.hook(potato..event,function(self) if potatoWork() then api.patchPotato(H.unwrap(self)) end end,potatoWork)
    end
    E.hook(CORE..'B_GameMode.B_GameMode_C:GetPickupSpawnDelay',function(self,out)
        if not pacingWork() then return end
        local gm=H.unwrap(self); local host,_,_,current=H.host(); local e=getExtras()
        if not host or not H.authority(gm) or not H.sameWorld(gm,current) then return end
        if e.pickupMin==gm.PickupMinSecondsUntilSpawn and e.pickupJitter==gm.PickupFlexibleSecondsUntilSpawn then return end
        local value=e.pickupMin+(e.pickupJitter>0 and math.random(0,e.pickupJitter-1) or 0)
        if H.unwrap(out)~=value then out:set(value) end
    end,pacingWork)
    E.hook(CORE..'B_SeekGameMode.B_SeekGameMode_C:GetRoundEndTimerUntilRestart',function(self,out)
        if not roundWork() then return end
        local gm=H.unwrap(self); local host,_,_,current=H.host(); local e=getExtras()
        if host and H.authority(gm) and H.sameWorld(gm,current) then
            local target=math.max(e.roundDelay,gm.MapVoteTimeNeeded and 29 or 1)
            if H.unwrap(out)~=target then out:set(target) end
        end
    end,roundWork)
    E.hook(SUBS.skills..'.B_SkillParametersSubsystem_C:GetSkillCooldown',function(self,skillType,playerType,out)
        if not cooldownWork() then return end
        local sub=H.unwrap(self); local host,pc=H.host(); local e=getExtras()
        if (host or (allowPrediction and allowPrediction())) and H.valid(sub) and H.sameWorld(sub,pc) then
            local prior=H.unwrap(out); if prior<e.cooldownMin then out:set(e.cooldownMin) end
        end
    end,cooldownWork)
    function api.prepare(e,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        -- Resolve only explicitly requested, build/mode-specific defaults, on an armed pass,
        -- before registering feature hooks. No actor scans at untouched defaults.
        if not enabled('extras') then return end
        if e.potatoRecharge~=nil and potatoDefault==nil and type(StaticFindObject)=='function' then
            local cdo=invoke(guard,T,StaticFindObject,'/Game/Blueprints/Skills/Hunter/Potato/B_PotatoSkill.Default__B_PotatoSkill_C')
            if H.valid(cdo) then potatoDefault=read(guard,T,cdo,'StaminaRecharge') end
        end
        if e.potatoRecharge==potatoDefault then e.potatoRecharge=nil end
        if e.pickupMin~=nil then
            local host,_,_,gm=H.host()
            if host and H.valid(gm) then pacingDefault={min=read(guard,T,gm,'PickupMinSecondsUntilSpawn'),jitter=read(guard,T,gm,'PickupFlexibleSecondsUntilSpawn')} end
            if pacingDefault and e.pickupMin==pacingDefault.min and e.pickupJitter==pacingDefault.jitter then
                e.pickupMin=nil; e.pickupJitter=nil
            end
        end
    end
    function api.scan(synchronous,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if enabled('cauldronOffset') then cauldrons.scan(guard,T) end
        if enabled('possession') and possession then possession.scan(synchronous,guard,T) end
        if not enabled('extras') then return end
        local e=getExtras()
        if e.pickupMin~=nil then
            local host,_,_,gm=H.host()
            if host and H.valid(gm) then pacingDefault={min=read(guard,T,gm,'PickupMinSecondsUntilSpawn'),jitter=read(guard,T,gm,'PickupFlexibleSecondsUntilSpawn')} end
        end
        if not potatoWork() then return end
        if potatoDefault==nil and type(StaticFindObject)=='function' then
            local cdo=invoke(guard,T,StaticFindObject,'/Game/Blueprints/Skills/Hunter/Potato/B_PotatoSkill.Default__B_PotatoSkill_C')
            if H.valid(cdo) then potatoDefault=read(guard,T,cdo,'StaminaRecharge') end
        end
        if not potatoWork() then return end
        for key,r in pairs(originals) do if not H.valid(r.object) then originals[key]=nil end end
        local Work=H.core and H.core.work_budget
        if synchronous and Work and not guard then Work.cancel('mrpp-potato') end
        if Work and not synchronous then
            local key='mrpp-potato'
            if guard then guardSerial=guardSerial+1;key='mrpp-potato-guard:'..guardSerial end
            if not Work.keys[key] then
                local items=H.findAll('B_PotatoSkill_C') or {};local index=0
                local accepted=Work.submit(key,'potato recharge',function()
                    if not current(guard,T) then items={};return true end
                    index=index+1
                    if items[index] then api.patchPotato(items[index],guard,T) end
                    return index>=#items
                end)
                if guard then assert(accepted,'potato work rejected') end
            end
        else for _,skill in ipairs(H.values(H.findAll('B_PotatoSkill_C') or {})) do api.patchPotato(skill,guard,T) end end
    end
    function api.close()
        if H.core then H.core.work_budget.cancel('mrpp-potato') end
        if possession then possession.close() end
    end
    function api.heartbeat() if enabled('cauldronOffset') then cauldrons.heartbeat() end end
    function api.reset()
        originals={}; pacingDefault=nil; potatoDefault=nil
        cauldrons.reset(); if possession then possession.reset() end
    end
    if H.lifetime then H.lifetime.onReset(function() originals={}; pacingDefault=nil; potatoDefault=nil end) end
    return api
end
return M
