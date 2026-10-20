-- Creative context adapter for the ordinary native NextMatchOptions rule buffer.
-- Reflected rules and cached event inventories; no array/struct OUT calls.
local M={}
local C='/Game/Blueprints/Gamemodes/CreativeMode/'
local P='/Game/Blueprints/Player/Pawns/'
local notify={match='OnRep_MatchRules',skills='OnRep_SkillRules',mods='OnRep_GameModifiers',powerups='OnRep_PowerupRules'}
local actors={
 {'B_Hunter_C','InitializeRules'},{'B_Witch_C','InitializeRules'},
 {'B_PropPawnPhysics_C','RulesUpdated'},{'B_CreativePropPawnPhysics_C','RulesUpdated'},
}
local skillNames={'Potato','Melee','Chicken','Hook','Cannonball','Garlic','Trap','PowerBall','Decoy','Mushroom','Fly','JumpScare','Possess','FlyingEye','Train'}
for _,name in ipairs(skillNames) do actors[#actors+1]={'B_'..name..'Skill_C','InitializeRules'} end
function M.init(H,R,Rules,J,D)
    local api={revision=0}; local state; local busy=false; local seen={}; local actorFailures={}; local boundViews={}; local readyViews={}; local epoch=0
    local refreshPending=false
    local function clone(x) return J.decode(J.encode(x)) end
    local function held(guard,T) return T or (guard and H.held(guard) or H) end
    local function current(guard,T) return not guard or guard() and T.current() end
    local function checkpoint(guard,T) assert(current(guard,T),'proposal owner retired') end
    local function read(guard,T,o,key)
        if guard then return T.read(o,key) end;return o[key]
    end
    local function write(guard,T,o,key,value)
        if guard then return T.write(o,key,value) end;o[key]=value
    end
    local function call(guard,T,o,key,...)
        if guard then return T.call(o,key,...) end;return o[key](o,...)
    end
    local function invoke(guard,T,fn,...)
        checkpoint(guard,T);local args=table.pack(...)
        local values=table.pack(fn(table.unpack(args,1,args.n)))
        checkpoint(guard,T);return table.unpack(values,1,values.n)
    end

    local function context(guard,T)
        local H=held(guard,T)
        if H.feature and not H.feature('creative') then return false end
        return H.creative()
    end
    -- Preserve native IDs, parameter names and all scalar lanes. Native saved
    -- rules do not pass through the narrower local-JSON import/export schema.
    local function snapshot(obj,guard,T)
        local H=held(guard,T);T=H
        local out={}
        for cat,def in pairs(Rules.collections) do
            local entries=J.array(); out[cat]=entries
            for _,entry in ipairs(H.values(read(guard,T,obj,def.field))) do
                local row={id=read(guard,T,entry,def.type),params=J.array()}; entries[#entries+1]=row
                for _,value in ipairs(H.values(read(guard,T,entry,def.params))) do
                    row.params[#row.params+1]={name=H.text(read(guard,T,value,'Name')),float=read(guard,T,value,'FloatValue'),
                        int=read(guard,T,value,'IntValue'),bool=read(guard,T,value,'BoolValue')}
                end
            end
        end
        return out
    end
    local function sameRules(left,right)
        -- Conservative equality: retain order, native IDs and every scalar lane.
        -- Only FName spelling is case-insensitive. Unknown rules are not omitted.
        for cat in pairs(Rules.collections) do
            local a,b=left[cat],right[cat]
            if #a~=#b then return false end
            for i,row in ipairs(a) do
                local other=b[i]
                if row.id~=other.id or #row.params~=#other.params then return false end
                for j,value in ipairs(row.params) do
                    local v=other.params[j]
                    if value.name:lower()~=v.name:lower() or value.float~=v.float
                        or value.int~=v.int or value.bool~=v.bool then return false end
                end
            end
        end
        return true
    end
    local function materialize(data,outer,guard,T)
        local H=held(guard,T);T=H
        local obj=assert(H.spawnRules(outer),'native rules buffer unavailable'); call(guard,T,obj,'ResetAll')
        for cat,def in pairs(Rules.collections) do
            local array=read(guard,T,obj,def.field)
            for i,row in ipairs(data[cat]) do
                write(guard,T,array,i,nil);local entry=read(guard,T,array,i);write(guard,T,entry,def.type,row.id)
                local params=read(guard,T,entry,def.params)
                for j,value in ipairs(row.params) do
                    write(guard,T,params,j,nil);local target=read(guard,T,params,j)
                    local name=invoke(guard,T,FName,value.name)
                    write(guard,T,target,'Name',name);write(guard,T,target,'FloatValue',value.float)
                    write(guard,T,target,'IntValue',value.int);write(guard,T,target,'BoolValue',value.bool)
                end
            end
        end
        return obj
    end
    local function editorState(gs,guard,T)
        local H=held(guard,T);T=H
        if not state or not H.valid(state.gs) or H.key(state.gs)~=H.key(gs) then
            local baseline=snapshot(gs,guard,T);checkpoint(guard,T)
            state={gs=gs,baseline=baseline,phase=false}; seen={}; actorFailures={}; epoch=epoch+1
        end
        return state
    end
    function api.ensureNativeContext(guard,T)
        local H=held(guard,T);T=H
        local host,pc,gs,_,gi=context(guard,T); assert(host,'Creative local host required')
        local s=editorState(gs,guard,T)
        assert(H.valid(gi),'NextMatchOptions unavailable')
        local options=assert(read(guard,T,gi,'NextMatchOptions'),'NextMatchOptions unavailable')
        assert(H.valid(options),'NextMatchOptions unavailable')
        if not s.options or not H.valid(s.options) or H.key(s.options)~=H.key(options) then
            local original=call(guard,T,options,'GetGameRules')
            local detached=assert(H.spawnRules(options),'cannot detach native rules')
            for _,def in pairs(Rules.collections) do
                local collection=read(guard,T,original,def.field);write(guard,T,detached,def.field,collection)
            end
            write(guard,T,options,'GameRules',detached);checkpoint(guard,T);s.options=options
        end
        return s,call(guard,T,options,'GetGameRules'),pc,gs
    end
    function api.nativeReady()
        local host=context()
        return host and state and H.valid(state.options) and H.valid(state.options.GameRules) or false
    end
    local function publish(gs,obj,bestEffort,guard,T)
        T=held(guard,T)
        local failures={}
        local function step(label,fn)
            checkpoint(guard,T)
            if not bestEffort then return invoke(guard,T,fn) end
            local ok,err=pcall(invoke,guard,T,fn)
            checkpoint(guard,T)
            if not ok then failures[#failures+1]=label..': '..tostring(err) end
        end
        step('FlushNetDormancy',function() call(guard,T,gs,'FlushNetDormancy') end)
        for _,def in pairs(Rules.collections) do
            step(def.field,function() local value=read(guard,T,obj,def.field);write(guard,T,gs,def.field,value) end)
        end
        for _,cat in ipairs({'skills','match','powerups','mods'}) do
            step(notify[cat],function() call(guard,T,gs,notify[cat]) end)
        end
        assert(#failures==0,table.concat(failures,'; '))
    end
    function api.extras(guard,T)
        local H=held(guard,T);T=H
        local ok,_,gs=context(guard,T)
        if ok and read(guard,T,gs,'IsPlayTestMode')==true and state and state.effect and H.valid(state.gs) and H.key(state.gs)==H.key(gs) then
            return state.effect.extras or {}
        end
        return {}
    end
    function api.snapshotNative()
        local _,obj,pc,gs=api.ensureNativeContext()
        local subs=H.parameters(pc); local source={GameModeClass=gs.GameModeClass}
        for _,def in pairs(Rules.collections) do source[def.field]=obj[def.field] end
        return R.capture(source,function(g) return subs[g.category][g.property] end,H.values,H.text,clone(D.extras()))
    end
    local function refreshActor(actor,fn,guard,T)
        local H=held(guard,T);T=H
        call(guard,T,actor,fn)
        -- Prop jump/acceleration read WitchMatchParameters at movement time. Recompute
        -- the cached template/size speed multiplier for a newly controlling prop too.
        if fn=='RulesUpdated' then
            local prop=read(guard,T,actor,'ControllingProp')
            if H.valid(prop) then call(guard,T,prop,'UpdateScaledSpeed') end
        end
    end
    function api.refreshActors(force,guard,T)
        local H=held(guard,T);T=H
        local ok,_,gs,gm=context(guard,T); if not ok then return end
        local found,failures={},{}
        for _,spec in ipairs(actors) do
            for _,actor in ipairs(H.values(H.findAll(spec[1]) or {})) do
                if H.authority(actor) and H.sameWorld(actor,gm) and not found[H.key(actor)] then
                    local key=H.key(actor); found[key]=true
                    if force or seen[key]~=epoch then
                        -- Attempt once per rule revision, including failed actors.
                        -- A birth scan must not retry an unrelated old failure.
                        seen[key]=epoch
                        local refreshed,err=pcall(refreshActor,actor,spec[2],guard,T)
                        checkpoint(guard,T)
                        if refreshed then actorFailures[key]=nil
                        else
                            actorFailures[key]=spec[1]..': '..tostring(err)
                            failures[#failures+1]=actorFailures[key]
                        end
                    end
                end
            end
        end
        for key in pairs(seen) do if not found[key] then seen[key]=nil; actorFailures[key]=nil end end
        assert(#failures==0,'Creative actor refresh incomplete: '..table.concat(failures,'; '))
    end
    local function warn(s,kind,err)
        s.warnings=s.warnings or {}; s.warnings[kind]=tostring(err)
        H.log('ERROR Creative '..kind..' incomplete; no heartbeat retry: '..tostring(err))
    end
    local function reconcile(s,force,guard,T,extras)
        T=held(guard,T);checkpoint(guard,T)
        local ok,err=pcall(api.refreshActors,force,guard,T)
        checkpoint(guard,T)
        if not ok then warn(s,'actor refresh',err)
        elseif not next(actorFailures) and s.warnings then s.warnings['actor refresh']=nil end
        -- Sidecar reconciliation is not part of the native rule transaction.
        -- A failed actor must not prevent restoring/applying extra physics knobs.
        ok,err=pcall(D.effectsChanged,guard,T,extras)
        checkpoint(guard,T)
        if not ok then warn(s,'effect reconciliation',err)
        elseif s.warnings then s.warnings['effect reconciliation']=nil end
    end
    local function restore(s,force,guard,T)
        T=held(guard,T);checkpoint(guard,T)
        if not s.effect and not force and not s.restorePending then return end
        if s.effect and s.effect.passive and not s.restorePending and not next(s.effect.extras)
            and sameRules(snapshot(s.gs,guard,T),s.baseline) then
            -- This phase never changed native rules or extras; native lifecycle
            -- already owns the baseline. Do not reinitialize it on the way out.
            s.effect=nil; s.signature=nil; refreshPending=false; return
        end
        s.restorePending=true
        s.effect=nil; s.signature=nil; epoch=epoch+1
        local prepared,perr=pcall(function() if D.effectsPrepared then invoke(guard,T,D.effectsPrepared,guard,T) end end)
        local restored,rerr=pcall(function()
            publish(s.gs,materialize(s.baseline,s.gs,guard,T),true,guard,T)
        end)
        if not current(guard,T) then error(not restored and rerr or not prepared and perr or 'proposal owner retired',0) end
        if restored then
            -- A later per-actor failure does not undo this committed restoration.
            s.restorePending=nil; reconcile(s,true,guard,T)
        else
            local ok,err=pcall(D.effectsChanged,guard,T)
            checkpoint(guard,T)
            if not ok then warn(s,'effect reconciliation',err) end
        end
        local failures={}
        if not prepared then failures[#failures+1]='restore preparation: '..tostring(perr) end
        if not restored then failures[#failures+1]='restore publication: '..tostring(rerr) end
        assert(#failures==0,table.concat(failures,'; '))
    end
    local viewSpecs={
        {'WB_MatchRules.WB_MatchRules_C','RefreshMatchRules','match',nil,'OnParamSliderRealValueChanged'},
        {'SkillRules/WB_SkillRules.WB_SkillRules_C','RefreshSkillRuleUI','skills','CurrentSkillType','OnParamSliderRealValueChanged'},
        {'Mods/WB_ModConfigure.WB_ModConfigure_C','RefreshModifierUI','mods','CurrentModType','OnFloatParamSliderRealValueChanged'},
        {'PowerupRules/WB_PowerupConfigure.WB_PowerupConfigure_C','RefreshPowerupUI','powerups','CurrentPowerupType','OnFloatParamSliderRealValueChanged'},
    }
    local function refreshNativeView(widget,spec,fallback)
        if busy then return end
        local host,_,gs=context(); widget=H.unwrap(widget)
        if not host or not H.valid(widget) or not H.sameWorld(widget,gs) then return end
        local controls=H.values(widget.UIElements)
        local first=controls[1] and H.key(controls[1])
        -- Native SetRealValue normalizes and broadcasts while building controls.
        -- Only a completed generation may trigger our live user-edit commits.
        if gs.IsPlayTestMode==true then readyViews[H.key(widget)]=first; return end
        if fallback and first and boundViews[H.key(widget)]==first then
            readyViews[H.key(widget)]=first; return
        end
        readyViews[H.key(widget)]=nil
        local _,obj=api.ensureNativeContext()
        local def=Rules.collections[spec[3]]; local values={}
        for _,entry in ipairs(H.values(obj[def.field])) do
            local id=entry[def.type]; values[id]=values[id] or {}
            for _,param in ipairs(H.values(entry[def.params])) do
                -- Copy scalar lanes only; never retain a borrowed struct wrapper.
                values[id][H.text(param.Name):lower()]={float=param.FloatValue,
                    int=param.IntValue,bool=param.BoolValue}
            end
        end
        local pending={}
        for _,control in ipairs(controls) do
            local isBool=H.class(control,'WB_CheckBoxWithEditableLabel_C')
            if isBool or H.class(control,'WB_SliderWithEditableLabel_C') then
                local metadata=isBool and control.BoolParameter or control.FloatParameter
                local id=spec[3]=='match' and control.Index or widget[spec[4]]
                local row=values[id] and values[id][H.text(metadata.Name):lower()]
                local value
                if row then
                    if isBool then value=row.bool
                    elseif metadata.RoundToInt==true then value=row.int
                    else value=row.float end
                elseif isBool then value=control.DefaultBoolValue
                else value=control.DefaultFloatValue end
                assert(type(value)==(isBool and 'boolean' or 'number'),
                    'native parameter default unavailable: '..H.text(metadata.Name))
                pending[#pending+1]={control=control,value=value,isBool=isBool}
            end
        end
        busy=true
        local ok,err=pcall(function()
            -- Keep the ordinary native widget tree, defaults, focus and delegates.
            -- Only hydrate scalar control values and native page-local Apply buffers.
            -- World providers remain untouched: native Apply/Initialize functions
            -- emit delegates, change gravity and create actors, even if restored.
            -- Booleans last retain native IsListed/IsEnabled gating. Do not call
            -- CheckForShouldEnable: it reads the original provider metadata.
            for _,row in ipairs(pending) do if not row.isBool then
                row.control:SetRealValue(row.value)
                widget[spec[5]](widget,row.control,row.control.RealValue)
            end end
            for _,row in ipairs(pending) do if row.isBool then
                row.control:SetIsCheckedWithoutEvent(row.value)
                row.control:CheckDefaultToUpdateUI()
                widget:OnCheckBoxValueChanged(row.control,row.value)
            end end
        end)
        busy=false
        if not ok then error(err) end
        boundViews[H.key(widget)]=first; readyViews[H.key(widget)]=first
    end
    function api.bindNativeView(widget)
        if busy or not H.valid(widget) then return end
        if H.class(widget,'WB_GameRulesTabs_C') then widget=widget.RulesSwitcher:GetActiveWidget() end
        if not H.valid(widget) then return end
        for _,spec in ipairs(viewSpecs) do
            if H.class(widget,spec[1]:match('%.([^%.]+)$')) then
                refreshNativeView(widget,spec,true); return
            end
        end
    end
    function api.sync(force,guard,T,extrasOverride)
        T=held(guard,T);checkpoint(guard,T)
        if busy then return end
        busy=true
        local attempted,attemptSignature,attemptPhase
        local ok,err=pcall(function()
            invoke(guard,T,D.storage)
            local host=context(guard,T)
            if not host then state=nil; seen={}; actorFailures={}; return end
            local s,obj,pc,gs=api.ensureNativeContext(guard,T)
            local desired=snapshot(obj,guard,T);local extras=clone(extrasOverride or invoke(guard,T,D.extras,guard,T))
            local signature=J.encode({rules=desired,extras=extras})
            local running=read(guard,T,gs,'IsPlayTestMode')==true
            -- Native notifications from our own failed transaction wake maintenance.
            -- They cannot authorize the same failed generation to apply/restore again.
            if not force and s.fault and s.fault.signature==signature and s.fault.phase==running then return end
            attempted,attemptSignature,attemptPhase=s,signature,running
            local hadFault=s.fault~=nil
            s.fault=nil
            if s.profileSignature~=signature then s.profileSignature=signature; api.revision=api.revision+1 end
            local restoredPending=s.restorePending==true
            if restoredPending then restore(s,true,guard,T) end
            if not running then
                if not restoredPending then restore(s,force,guard,T) end
                s.phase=false; return
            end
            if force or not s.phase or s.signature~=signature or not s.effect then
                local nativeCurrent=not hadFault and not restoredPending and sameRules(desired,snapshot(gs,guard,T))
                local extrasUnchanged=J.encode(extras)==J.encode(s.effect and s.effect.extras or {})
                local unchangedRules=s.phase and s.signature==signature
                    or not s.phase and sameRules(desired,s.baseline)
                if nativeCurrent and extrasUnchanged and unchangedRules
                    and not (s.warnings and next(s.warnings)) then
                    -- BeginPlayTest and native menu Apply may already have the
                    -- requested native rules. A healthy no-op owns no actor work.
                    s.effect=s.effect or {extras=extras,passive=true}
                    s.signature=signature; s.phase=running; return
                end
                s.effect={extras=extras}; epoch=epoch+1
                local applied,aerr=pcall(function()
                    if D.effectsPrepared then invoke(guard,T,D.effectsPrepared,guard,T,extras) end
                    if not nativeCurrent then publish(gs,obj,false,guard,T) end
                end)
                if not applied then
                    if not current(guard,T) then error(aerr,0) end
                    local restored,rerr=pcall(restore,s,true,guard,T)
                    if not restored then error(tostring(aerr)..'; editor restore failed: '..tostring(rerr)) end
                    error(aerr)
                end
                -- Publication is the commit boundary. Actor/sidecar warnings must
                -- not throw into A.load and roll back a successfully imported buffer.
                s.signature=signature; s.phase=running
                reconcile(s,true,guard,T,extras)
            end
            s.phase=running
        end)
        busy=false
        if not ok then
            if attempted and current(guard,T) then attempted.fault={signature=attemptSignature,phase=attemptPhase,error=tostring(err)} end
            error(err,0)
        end
    end
    function api.poll()
        api.sync(false)
        if state and state.effect and not state.effect.passive and refreshPending then
            refreshPending=false
            busy=true; local ok,err=pcall(api.refreshActors,false); busy=false
            if not ok then warn(state,'actor refresh',err)
            elseif not next(actorFailures) and state.warnings then state.warnings['actor refresh']=nil end
        end
    end
    function api.actorChanged()
        if state and state.effect and not state.effect.passive then refreshPending=true end
    end
    -- A completed native transaction is already authoritative in NextMatchOptions.
    -- Apply it in playtest, or undo only its editor-world side effects. No file I/O.
    function api.nativeEdit()
        if busy or not context() then return end
        api.sync(true)
    end
    function api.loadLocal(p,guard,T,extrasOverride)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        local s=api.ensureNativeContext(guard,T); local staged=clone(p)
        staged.mode=H.text(read(guard,T,s.options,'GameMode'))
        R.stage(staged,s.options,H.spawnRules,staged.mode,guard)
        api.sync(true,guard,T,extrasOverride)
    end
    H.hook(C..'B_CreativeGameMode.B_CreativeGameMode_C:BeginPlayTest',function(self)
        local host,_,gs,gm=context()
        if host and H.key(H.unwrap(self))==H.key(gm) and gs.IsPlayTestMode==true then api.sync(true) end
    end)
    H.hook(C..'B_CreativeGameMode.B_CreativeGameMode_C:EndPlayTest',function(self)
        local host,_,_,gm=context()
        if host and H.key(H.unwrap(self))==H.key(gm) then api.sync(false) end
    end)
    H.hook(C..'B_CreativeGameState.B_CreativeGameState_C:OnRep_IsPlayTestMode',function()
        local host,_,gs=context()
        if host and gs.IsPlayTestMode~=true then api.sync(false) end -- restore before editor pawns spawn
    end)
    for _,spec in ipairs({{'B_Hunter','InitializeRules'},{'B_Witch','InitializeRules'},{'B_PropPawnPhysics','SwitchProp'},{'B_PropPawnPhysics','OnRep_ControllingProp'}}) do
        H.hook(P..spec[1]..'.'..spec[1]..'_C:'..spec[2],function(self)
            if busy or not state or not state.effect or state.effect.passive then return end
            local a=H.unwrap(self); local host,_,gs,gm=context()
            if host and gs.IsPlayTestMode==true and H.authority(a) and H.sameWorld(a,gm) then
                -- Native initialization already reads current subsystem objects. A prop
                -- transform can add a new actor; repair its cached speed on the next owned pass.
                if spec[1]=='B_PropPawnPhysics' then seen[H.key(a)]=nil; refreshPending=true
                else seen[H.key(a)]=epoch end
            end
        end,function() return state~=nil and state.effect~=nil and not state.effect.passive end)
    end
    local U='/Game/UserInterface/Play/GameRules/'
    for _,spec in ipairs({
        {U..'WB_MatchRules.WB_MatchRules_C:Apply Rules','match'},
        {U..'SkillRules/WB_SkillRules.WB_SkillRules_C:ApplyRules','skills'},
        {U..'Mods/WB_ModConfigure.WB_ModConfigure_C:ApplyRules','mods'},
        {U..'PowerupRules/WB_PowerupConfigure.WB_PowerupConfigure_C:ApplyRules','powerups'},
        {U..'WB_GameRulesTabs.WB_GameRulesTabs_C:ResetAllToDefault'},
    }) do H.hook(spec[1],function() api.nativeEdit(spec[2]) end) end
    -- Native changes normally commit when leaving a page. In a running playtest,
    -- commit each completed value event immediately. Calling only Apply avoids the
    -- native OnApply navigation and keeps the user's current page/focus.
    for _,spec in ipairs({
        {'WB_MatchRules.WB_MatchRules_C',{'OnParamSliderRealValueChanged','OnCheckBoxValueChanged'},'ApplyChanges','match'},
        {'SkillRules/WB_SkillRules.WB_SkillRules_C',{'OnParamSliderRealValueChanged','OnCheckBoxValueChanged'},'ApplyRules','skills','CurrentSkillType'},
        {'Mods/WB_ModConfigure.WB_ModConfigure_C',{'OnFloatParamSliderRealValueChanged','OnCheckBoxValueChanged'},'ApplyRules','mods','CurrentModType'},
        {'PowerupRules/WB_PowerupConfigure.WB_PowerupConfigure_C',{'OnFloatParamSliderRealValueChanged','OnCheckBoxValueChanged'},'ApplyRules','powerups','CurrentPowerupType'},
    }) do
        for _,event in ipairs(spec[2]) do H.hook(U..spec[1]..':'..event,function(self,sender,value)
            if busy then return end
            local host,pc,gs=context(); local widget=H.unwrap(self); sender=H.unwrap(sender)
            if not host or gs.IsPlayTestMode~=true or not H.valid(widget) or not H.valid(sender) then return end
            local controls=H.values(widget.UIElements)
            local first=controls[1] and H.key(controls[1]); local current=false
            if not first or readyViews[H.key(widget)]~=first then return end
            for _,control in ipairs(controls) do if H.same(control,sender) then current=true; break end end
            if not current then return end
            local id=spec[4]=='match' and sender.Index or widget[spec[5]]
            local isBool=event=='OnCheckBoxValueChanged'
            local name=H.text((isBool and sender.BoolParameter or sender.FloatParameter).Name):lower()
            value=H.unwrap(value)
            -- Native Init/Refresh also emits value events. Compare against effective
            -- scalar properties so opening a tab never turns defaults into overrides.
            local subs=H.parameters(pc)
            for _,group in ipairs(R.schema) do if group.category==spec[4] and group.id==id then
                for _,row in ipairs(group.rows) do if row.name:lower()==name then
                    if row.kind=='int' then value=math.floor(value+.5) end
                    local previous=subs[group.category][group.property][row.name]
                    if previous==value or (type(value)=='number' and math.abs(previous-value)<=1e-6*math.max(1,math.abs(value))) then return end
                    widget[spec[3]](widget); return
                end end
            end end
        end) end
    end
    for _,spec in ipairs(viewSpecs) do H.hook(U..spec[1]..':'..spec[2],function(self)
        refreshNativeView(self,spec)
    end) end
    H.hook(U..'WB_SaveLoadGameRules.WB_SaveLoadGameRules_C:SaveFileLoaded',function(self,_,save)
        local host,_,gs,_,gi=context(); local w=H.unwrap(self); save=H.unwrap(save)
        if host and H.valid(w) and H.sameWorld(w,gs) and H.valid(save)
            and H.valid(gi.NextMatchOptions) and H.same(gi.NextMatchOptions.GameRules,save) then api.nativeEdit() end
    end)
    H.hook(U..'WB_SaveLoadGameRules.WB_SaveLoadGameRules_C:ResetRules',function(self)
        local host,_,gs=context(); local w=H.unwrap(self)
        if host and H.valid(w) and H.sameWorld(w,gs) then api.nativeEdit() end
    end)
    function api.close()
        if state and H.valid(state.gs) then
            if state.effect or state.restorePending then restore(state) end
        end
        -- Native working rules remain in NextMatchOptions across Back/reopen/travel.
        -- Never restore an old pointer over a committed native Load or edit.
    end
    function api.reset() state=nil; seen={}; actorFailures={}; boundViews={}; readyViews={}; refreshPending=false; epoch=epoch+1 end
    return api
end
return M
