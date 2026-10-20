-- MatchRulesPlusPlus / common Core2 feature protocol package.
return function(api)
local log=api.log
local function module(name) return api.module(name) end
local J=api.json; local Rules=module('rules'); local R=Rules.init(module('schema'),J)
local Policy=module('features'); local Config=module('config')
Policy.validate(Config.features)
local Runtime=module('runtime'); local H=Runtime.init(api)
local NativeRules=module('native_rules').init(H,R,Rules)
local featuresReady=false; local effectExtras={}; local settingsFeatures
local dirty=2
H.wake=function() dirty=math.max(dirty,2) end
local refreshEffects; local closing=false
H.feature=function(name) return featuresReady and Policy.enabled(Config.features,settingsFeatures,name) end
local storage,UI,Probe,Extras,Creative,Sync,Physics,Proposals
local settings={version=1,probe=false,extras={},playtestPreset='off',debugViewer=false}
local extrasRevision,probeRevision=0,0
local snapshot,fingerprint,stable,lastGS;local pendingMatchGM
local function settingsValidate(s)
    assert(type(s)=='table' and s.version==1 and type(s.probe)=='boolean','invalid settings schema')
    Rules.extraValidate(s.extras)
    if s.nextMatchExtras then Rules.extraValidate(s.nextMatchExtras)end
    if s.features~=nil then Policy.validate(s.features) end
    s.debugViewer=s.debugViewer or false
    assert(type(s.debugViewer)=='boolean','invalid debug viewer preference')
    s.playtestPreset=s.playtestPreset or 'off'
    if s.playtestPreset~='off' then module('storage').name(s.playtestPreset) end
    return s
end
local function ensureStorage(guard,T)
    local H=T or (guard and H.held(guard) or H)
    if guard then assert(guard() and H.current(),'proposal owner retired') end
    if storage then return storage end
    local s=module('storage').init(api,H.savedDir(),R.validate,settingsValidate)
    -- A corrupt preference file disables writes until fixed; it is never silently overwritten.
    local existing=s.settingsRead()
    if existing then settings=settingsValidate(existing); extrasRevision=extrasRevision+1; probeRevision=probeRevision+1 end
    -- Re-enabling in the middle of the same match must not turn a staged
    -- proposal into a current-match extra override.
    if existing and settings.nextMatchExtras then
        local _,_,gm=H.world();if H.valid(gm)then pendingMatchGM=gm end
    end
    storage=s; settingsFeatures=settings.features; featuresReady=true
    log('local JSON storage: '..s.root)
    local flags={}; for _,name in ipairs(Policy.names) do flags[#flags+1]=name..'='..tostring(H.feature(name)) end
    log('feature switches: '..table.concat(flags,', ')..'; nativeTravelHooks='..tostring(Config.nativeTravelHooks))
    return s
end
local function clone(x) return J.decode(J.encode(x)) end
local function held(guard,T) return T or (guard and H.held(guard) or H) end
local function checkpoint(guard,T) assert(not guard or guard() and T.current(),'proposal owner retired') end
local function invoke(guard,T,fn,...) checkpoint(guard,T);local v=table.pack(fn(...));checkpoint(guard,T);return table.unpack(v,1,v.n) end
local guardedLoad

local function refresh()
    local pc,gs=H.world()
    if not H.valid(gs) then snapshot=nil; fingerprint=nil; stable=false; lastGS=nil; return end
    local subs=H.parameters(pc)
    local host=H.host()
    local activeExtras=settings.extras
    if Creative and H.feature('creative') and H.creative() then activeExtras=Creative.extras() end
    local p=R.capture(gs,function(g)
        local o=subs[g.category][g.property]; return H.valid(o) and o or nil
    end,H.values,H.text,(host and clone(activeExtras) or (Sync and Sync.extras())) )
    local mark=J.encode({mode=p.mode,collections=p.collections,effective=p.effective,extras=p.extras,extrasKnown=p.extrasKnown})
    stable=lastGS==H.key(gs) and fingerprint==mark
    snapshot=p; fingerprint=mark; lastGS=H.key(gs)
end
local A={extraSpecs=Rules.extraSpecs,extras=function(guard,T)
    local H=held(guard,T)
    if NativeRules.menuContext() then return clone(settings.nextMatchExtras or settings.extras) end
    if not H.host() then return clone((Sync and Sync.extras()) or {}) end
    local values=clone(settings.extras)
    if settings.nextMatchExtras then
        for _,spec in ipairs(Rules.extraSpecs)do
            if spec.nextMatch then values[spec.key]=settings.nextMatchExtras[spec.key]end
        end
    end
    return values
end,probeEnabled=function() return settings.probe end,isHost=function() return H.host() end}
A.extrasRevision=function() return extrasRevision+(Creative and Creative.revision or 0)+(Sync and Sync.revision or 0) end
A.debugViewer=function() return settings.debugViewer end
function A.setDebugViewer(value)
    assert(type(value)=='boolean','debugViewer must be boolean')
    local s=ensureStorage(); local after=clone(settings); after.debugViewer=value; s.settingsWrite(after); settings=after
    return value and 'Rules inspector enabled.' or 'Rules inspector disabled.'
end
A.probeRevision=function() return probeRevision end
A.ruleLabel=Rules.label
A.isCreative=function() return H.feature('creative') and H.creative() end
function A.prepareNativeRules()
    ensureStorage()
    if H.feature('creative') and H.creative() then
        Creative.ensureNativeContext(); Creative.sync(false)
    end
end
function A.bindNativeRulesView(widget)
    if H.feature('creative') and H.creative() then Creative.bindNativeView(widget) end
end
function A.save(name)
    local s=ensureStorage(); local p
    if NativeRules.menuContext() then p=NativeRules.capture(clone(settings.nextMatchExtras or settings.extras))
    elseif H.feature('creative') and H.creative() then p=Creative.snapshotNative()
    else
        refresh(); assert(snapshot and stable,'rules not ready or replication is settling; wait one second and retry')
        p=clone(snapshot)
    end
    local path=s.write(name,p);log('Saved local rules: '..path);return "Saved preset '"..name.."'."
end
function A.load(bucket,name,guard,T)
    if guard then return guardedLoad(bucket,name,guard,T) end
    local host,_,_,_,gi=H.host()
    local menuPC,menuGI=NativeRules.menuContext()
    assert(host or menuPC,'only the local host or native next-match editor may load rules')
    local s=ensureStorage(); local p=R.validate(s.read(bucket,name),true)
    gi=menuPC and menuGI or gi
    assert(H.valid(gi.NextMatchOptions),'NextMatchOptions unavailable')
    local creative=H.feature('creative') and H.creative(); local nextOptions=gi.NextMatchOptions
    if not creative then assert(p.mode==H.text(nextOptions.GameMode),'preset game mode differs from next match') end
    local before=clone(settings); local after=clone(settings)
    if menuPC then after.nextMatchExtras=clone(p.extras or {}) else after.extras=clone(p.extras or {}) end
    local previousRules,previousSlot,previousCustom=nextOptions.GameRules,nextOptions.GameRulesToLoad,nextOptions.IsUsingCustomRules
    s.settingsWrite(after); settings=after
    local ok,err=pcall(function()
        if creative then Creative.loadLocal(p)
        else R.stage(p,nextOptions,H.spawnRules,H.text(nextOptions.GameMode)) end
    end)
    if not ok then
        settings=before
        local failures={tostring(err)}
        local function rollback(label,fn)
            local restored,rerr=pcall(fn)
            if not restored then failures[#failures+1]=label..': '..tostring(rerr) end
        end
        rollback('restore native rules',function() nextOptions.GameRules=previousRules end)
        rollback('restore slot',function() nextOptions.GameRulesToLoad=previousSlot end)
        rollback('restore custom flag',function() nextOptions.IsUsingCustomRules=previousCustom end)
        rollback('restore settings',function() s.settingsWrite(before) end)
        if creative then rollback('restore prior playtest effects',function() Creative.sync(true) end) end
        error(table.concat(failures,'; '))
    end
    extrasRevision=extrasRevision+1; refreshEffects(); H.retryHooks(); if Sync then Sync.publish() end
    if host then Extras.scan(); if Physics then Physics.scan() end end
    stable=false
    if menuPC then return 'Rules saved for the next match.' end
    return creative and 'Rules applied to Playtest.'
        or 'Rules saved for the next match; extra rules applied.'
end
-- Cooked checkbox/slider commits persist next-match edits immediately. Closing
-- the native setup screen (Back/Create Game) does not invoke an Apply action.
function A.stageExtra(key,value)
    local menu=NativeRules.menuContext()
    assert(H.host() or menu,'next-match extras require the local host or native next-match editor')
    local spec
    for _,entry in ipairs(Rules.extraSpecs)do if entry.key==key then spec=entry;break end end
    assert(spec and spec.nextMatch,'not a next-match extra: '..tostring(key))
    Rules.extraValidate({[key]=value})
    local s=ensureStorage()
    local before=settings.nextMatchExtras or settings.extras
    if before[key]==value then return end
    local after=clone(settings);after.nextMatchExtras=clone(before);after.nextMatchExtras[key]=value
    local gm
    if not menu then local _,_,current=H.world();gm=current end
    s.settingsWrite(after);settings=after;pendingMatchGM=gm
    extrasRevision=extrasRevision+1
    H.log('Next-match extra staged: '..(key=='mapSizeTimeFactor' and 'K' or key)..'='..(value==nil and 'off (vanilla)' or tostring(value)))
    return 'Rule saved for the next match.'
end
function A.applyExtras(values)
    local menu=NativeRules.menuContext()
    assert(H.host() or menu,'extras require the local host or native next-match editor')
    Rules.extraValidate(values)
    local s=ensureStorage()
    if menu then
        local allowed={};for _,spec in ipairs(Rules.extraSpecs)do if spec.nextMatch then allowed[spec.key]=true end end
        for key in pairs(values)do assert(allowed[key],'extra requires a live hosted match: '..key)end
        local after=clone(settings);after.nextMatchExtras=clone(settings.nextMatchExtras or settings.extras)
        for key in pairs(allowed)do after.nextMatchExtras[key]=values[key]end
        s.settingsWrite(after);settings=after;pendingMatchGM=nil;extrasRevision=extrasRevision+1
        return 'Extra rules saved for the next match.'
    end
    local after=clone(settings); after.extras=clone(values)
    s.settingsWrite(after); settings=after; extrasRevision=extrasRevision+1
    if H.feature('creative') and H.creative() then Creative.sync(true) end
    refreshEffects(); H.retryHooks(); Extras.scan(); if Physics then Physics.scan() end; stable=false; if Sync then Sync.publish() end
    return 'Extra rules saved.'
end
function A.setProbe(value)
    assert(type(value)=='boolean','probe must be boolean')
    local s=ensureStorage(); local after=clone(settings); after.probe=value
    s.settingsWrite(after); settings=after; probeRevision=probeRevision+1
    return value and 'Connection test enabled.' or 'Connection test disabled.'
end
function A.localDraft(name)
    assert(not H.host(),'local proposal editing is for connected clients')
    local p=R.validate(ensureStorage().read('presets',name),true)
    refresh(); assert(snapshot and snapshot.effective,'host rule defaults unavailable')
    return p,name,p.effective or snapshot.effective,R.schema
end
function A.commitLocal(edits,name,extras)
    assert(not H.host(),'authority changed; reopen the editor')
    local s=ensureStorage(); local p=R.clean(s.read('presets',name))
    for _,e in ipairs(edits) do
        local found
        for _,entry in ipairs(p.collections[e.category]) do if entry.id==e.id then found=entry; break end end
        if not found then found={id=e.id,values={}}; p.collections[e.category][#p.collections[e.category]+1]=found end
        found.values[e.name]=e.value
    end
    p.extras=extras; R.validate(p,true); s.write(name,p)
    return 'Saved preset '..name..'.'
end
local Code=module('preset_code').new(J,R.clean)
local Clipboard=assert(api.Native.scope(api.id))
api.own(Clipboard.close)
local function activePreset()
    if NativeRules.menuContext()then return NativeRules.capture(clone(settings.nextMatchExtras or settings.extras))end
    if H.feature('creative')and H.creative()then return Creative.snapshotNative()end
    refresh();assert(snapshot,'current rules unavailable');return R.clean(snapshot)
end
function A.share(name)
    assert(H.feature('sync'),'sync feature disabled');return Sync.share(activePreset(),name)
end
function A.copyCode(name)
    local p=ensureStorage().read('presets',name)
    local value=Code.encode(p);local ok,why=Clipboard.clipboard('write',value);assert(ok,why)
    return 'Copied code for '..name..'.'
end
function A.importCode(name)
    local value,why=Clipboard.clipboard('read');assert(value,why)
    local p=Code.decode(value);local saved=ensureStorage().writeNew(name,p)
    return 'Imported preset '..saved..'.'
end
function A.propose(name) assert(H.feature('sync'),'sync feature disabled'); return Sync.propose(ensureStorage().read('presets',name)) end
function A.pendingOffers() return Proposals.inbox() end
function A.reviewOffer(id) return Proposals.show(id) end
function A.answerOffer(id,accepted) return Proposals.answer(id,accepted) end
function A.transportStatus()
    if NativeRules.menuContext() then return 'Rules for the next match' end
    if not H.feature('sync') then return 'Rules sharing is disabled.' end
    if H.host() then return '' end
    return Sync and Sync.extras() and 'The host controls match rules.' or 'Waiting for the host’s rules…'
end
function A.restoreClientRules()
    if H.host() then return end
    local _,gs=H.world(); if not H.valid(gs) then return end
    for _,f in ipairs({'OnRep_MatchRules','OnRep_SkillRules','OnRep_GameModifiers','OnRep_PowerupRules'}) do gs[f](gs) end
end
function A.describe()
    if not snapshot then return 'Rules unavailable. Join a lobby to view them.' end
    local lines={'Game mode: '..Rules.label(snapshot.mode),stable and '' or 'Receiving rules…',snapshot.extrasKnown and 'Extra rules received.' or 'Waiting for the host’s extra rules…'}
    for _,g in ipairs(R.schema) do
        lines[#lines+1]='\n'..Rules.label(g.property)
        local effective=snapshot.effective[g.category..':'..g.id]
        for _,s in ipairs(g.rows) do lines[#lines+1]=Rules.label(s.name)..' = '..tostring(effective[s.name]) end
    end
    lines[#lines+1]='\n'
    return table.concat(lines,'\n')
end
Creative=module('creative').init(H.group('creative'),R,Rules,J,{
    storage=ensureStorage,extras=function() return settings.extras end,
    effectsPrepared=function(guard,T,extras) T=held(guard,T);if refreshEffects then refreshEffects(guard,T,extras) end;T.retryHooks();checkpoint(guard,T) end,
    effectsChanged=function(guard,T,extras) T=held(guard,T);if refreshEffects then refreshEffects(guard,T,extras) end;if Extras then Extras.scan(true,guard,T) end;if Physics then Physics.scan(false,guard,T) end;checkpoint(guard,T);stable=false;fingerprint=nil;if Sync then Sync.publish(guard,T) end end,
})
local function effectiveExtras() return effectExtras end
refreshEffects=function(guard,T,override)
    local H=held(guard,T);T=H;checkpoint(guard,T)
    if closing then effectExtras={}; return end
    local value={}
    if override then value=clone(override)
    elseif H.creative() and H.feature('creative') then value=Creative.extras(guard,T)
    elseif H.host() then value=settings.extras
    elseif H.feature('sync') and Sync then value=Sync.extras() or {} end
    value=Policy.active(value)
    if not H.feature('physics') then
        for _,key in ipairs({'propForce','propAirForce','propMaxSpeed','propJumpForce','propSpeed','propMass','hunterGravity','witchGravity','hunterAirControl','witchAirControl'}) do value[key]=nil end
    end
    if not H.feature('possession') then value.possessionLifetime=nil end
    if not H.feature('cauldronOffset') then value.cauldronTargetOffset=nil end
    if not H.feature('extras') then for _,key in ipairs({'pickupMin','pickupJitter','roundDelay','potatoRecharge','cooldownMin','mapSizeTimeFactor'}) do value[key]=nil end end
    if Extras then Extras.prepare(value,guard,T) end
    if Physics then Physics.prepare(value,guard,T) end
    checkpoint(guard,T);effectExtras=value
    -- Pure-data bridge for FAPP restore; no dependency on MRPP when absent.
    local context=api.context(); local lifetime=value.possessionLifetime or 5
    if context.possession_lifetime~=lifetime then context.possession_lifetime=lifetime; WIR_RUNTIME.set_context(context) end
end
Extras=Runtime.extras(H,effectiveExtras,module('possession'),function() return H.feature('sync') and Sync and Sync.extras()~=nil end)
-- Decision hook is installed immediately, never deferred behind discovery/work jobs.
local function activateProposal(gm)
    if not H.valid(gm)or not H.authority(gm)or H.class(gm,'B_MenuGameMode_C')or H.class(gm,'B_LobbyGameMode_C')or H.class(gm,'B_CreativeGameMode_C')then return end
    if settings.nextMatchExtras and (not pendingMatchGM or not H.same(gm,pendingMatchGM))then
        local after=clone(settings);after.extras=after.nextMatchExtras;after.nextMatchExtras=nil
        ensureStorage().settingsWrite(after);settings=after;pendingMatchGM=nil
        extrasRevision=extrasRevision+1;refreshEffects();if Sync then Sync.publish()end
        H.wake();log('Staged extras activated for the next match.')
    end
end
local SeekTime=module('seek_time').init(H,function(gm,gi)
    ensureStorage()
    -- A starting authoritative GM is enough: H.host()/effectExtras can still
    -- describe the departing menu until the new local controller begins play.
    if not H.feature('extras') then return settings.extras,'extras disabled' end
    if gi.IsCustomMatch~=true and not H.class(gm,'B_CreativeGameMode_C') then return settings.extras,'not a custom match' end
    if H.class(gm,'B_CreativeGameMode_C') and H.feature('creative') then return Creative.extras() end
    return settings.extras
end,activateProposal)
api.on('begin_play_post',SeekTime.begin_play,{class_filter=function(name)
    return name:match('GameMode_C$')~=nil and name~='B_MenuGameMode_C' and name~='B_LobbyGameMode_C'
end})
api.hook('/Game/Blueprints/Core/B_SeekGameMode.B_SeekGameMode_C:InitializeSeekTime',SeekTime.initialize,{phase='post'})
Probe=module('probe').init(H.group('sync'),function() return H.feature('sync') and settings.probe end)
local PC='/Game/Blueprints/Player/B_PlayerController.B_PlayerController_C:'
local function guardedApply(p,name,guard,T)
    T=held(guard,T);checkpoint(guard,T)
    local host,_,gs,gm,gi=T.host();assert(H.feature('sync') and host,'proposal transport disabled or local host unavailable')
    local s=ensureStorage(guard,T);p=R.clean(p);checkpoint(guard,T)
    local options=T.read(gi,'NextMatchOptions');assert(T.valid(options),'NextMatchOptions unavailable')
    local creative=H.feature('creative') and T.creative()
    local mode=T.text(T.read(options,'GameMode'))
    if not creative then assert(p.mode==mode,'proposal mode differs from next match') end
    local before=settings;local beforeEffects=effectExtras;local after=clone(settings);after.extras=clone(p.extras or {})
    local appliedEffects;local live=false
    local ok,err=pcall(function()
        if creative then Creative.loadLocal(p,guard,T,after.extras)
        else
            R.stage(p,options,T.spawnRules,mode,guard)
            live=T.read(gm,'IsLiveRuleEditingAllowed')==true and p.mode==T.text(T.read(gs,'GameModeClass'))
            if live then for _,fn in ipairs({'UpdateMatchRules','UpdateSkillRules','UpdateModRules','UpdatePowerupRules'}) do T.call(gs,fn) end end
        end
        checkpoint(guard,T);refreshEffects(guard,T,after.extras);appliedEffects=effectExtras
        T.retryHooks();Extras.scan(false,guard,T);if Physics then Physics.scan(false,guard,T) end
        checkpoint(guard,T)
        -- Preferences commit follows Native preparation; outgoing transactions
        -- never install their draft settings into a replacement's global state.
        invoke(guard,T,s.settingsWrite,after);settings=after;extrasRevision=extrasRevision+1
        if creative and name then invoke(guard,T,s.write,name,p) end
        stable=false;if Sync then Sync.publish(guard,T) end
    end)
    if not ok then
        if appliedEffects and effectExtras==appliedEffects then effectExtras=beforeEffects end
        if settings==after then settings=before end
        error(err,0)
    end
    return creative and 'Rules applied to Playtest.'
        or live and 'Rules applied.'
        or 'Rules saved for the next match; extra rules applied.'
end
guardedLoad=function(bucket,name,guard,T)
    T=held(guard,T);local s=ensureStorage(guard,T)
    local p=invoke(guard,T,s.read,bucket,name);return guardedApply(p,name,guard,T)
end
local function acceptProposal(p,name,guard,T)
    T=held(guard,T);checkpoint(guard,T)
    local host,_,_,gm,gi=T.host();assert(H.feature('sync')and host,'local host required')
    local store=ensureStorage(guard,T);p=R.clean(p)
    local options=T.read(gi,'NextMatchOptions');assert(T.valid(options),'NextMatchOptions unavailable')
    local mode=T.text(T.read(options,'GameMode'));assert(p.mode==mode,'proposal mode differs from next match')
    local before=settings;local after=clone(settings);after.nextMatchExtras=clone(p.extras or {})
    invoke(guard,T,store.settingsWrite,after)
    local ok,why=pcall(R.stage,p,options,T.spawnRules,mode,guard)
    if not ok then invoke(guard,T,store.settingsWrite,before);error(why,0)end
    settings=after;pendingMatchGM=gm
    return 'Rules accepted for the next match.'
end
Proposals=module('proposals').init(H.group('sync'),{
    storage=ensureStorage,cleanPreset=R.clean,accept=acceptProposal,
    panelOpen=function()return UI and UI.offersOpen()or false end,
    saveShared=function(p,name,guard)
        assert(not guard or guard(),'share expired')
        local saved=ensureStorage().writeShared(name,p)
        return "Saved preset '"..saved.."'."
    end,
    summary=function(p,pc,name,guard)
        assert(not guard or guard(),'rules offer expired')
        local n=0; for _,list in pairs(p.collections) do for _,r in ipairs(list) do for _ in pairs(r.values) do n=n+1 end end end
        local e={}; for key,value in pairs(p.extras) do e[#e+1]=R.label(key)..': '..tostring(value) end; table.sort(e)
        local details={}
        for _,group in ipairs(R.schema) do
            for _,r in ipairs(p.collections[group.category]) do if r.id==group.id then
                for _,row in ipairs(group.rows) do
                    if r.values[row.name]~=nil and #details<6 then details[#details+1]=R.label(group.property)..' — '..R.label(row.name)..': '..tostring(r.values[row.name]) end
                end
            end end
        end
        local timing='Accept for the next match?'
        local sender=H.read and H.read(H.read(pc,'PlayerState'),'PlayerName')
        assert(not guard or guard(),'rules offer expired')
        return 'From '..(sender and H.text(sender)or 'Player')..'\nMode: '..R.label(p.mode)..'\n'..table.concat(details,'; ')..(n>#details and '; …' or '')..'\nExtra rules: '..(#e>0 and table.concat(e,', ') or 'None')..'\n'..timing
    end,
})
Sync=module('sync').init(H.group('sync'),J,{
    extras=effectiveExtras,validateExtras=Rules.extraValidate,cleanPreset=R.clean,
    proposal=function(p,pc,reply,current) return Proposals.receive(p,pc,reply,current) end,
    shared=function(p,name,pc,current)return Proposals.shared(p,name,pc,current)end,
    result=function(result) log('Proposal: '..result) end,changed=function() H.wake() end,
})
Physics=module('physics').init(H.group('physics'),effectiveExtras)
for _,f in ipairs({'OnRep_MatchRules','OnRep_SkillRules','OnRep_GameModifiers','OnRep_PowerupRules'}) do
    H.hook('/Game/Blueprints/Core/B_GameState.B_GameState_C:'..f,function() stable=false; fingerprint=nil end)
end
UI=module('ui').init(H.group('ui'),A)
-- Key callbacks queue owned game-thread work; no UObject access in key dispatch.
local requests={}; local drain
-- F7 opens native Match Rules +; F8 is FillAPotPlus's pause key. Debug viewer: Ctrl+F7.
api.hotkey({id='rules',default_chord='F7',description='Open Match Rules +',context={'lobby','match','creative'}},function() requests.native=true; api.game_thread(function() drain() end) end)
if type(ModifierKey)=="table" and ModifierKey.CONTROL then
    api.hotkey({id='debug',default_chord='Ctrl+F7',description='Rules inspector',context={'lobby','match','creative'}},function() requests.debug=true; api.game_thread(function() drain() end) end)
end
api.hotkey({id='probe',default_chord='F9',description='Connection test',context={'lobby','match','creative'}},function() requests.ping=true; api.game_thread(function() drain() end) end)
drain=function(menuOnly)
    H.menuDriver=menuOnly
    if requests.debug then requests.debug=nil; H.guard('F7 debug viewer',function()
        ensureStorage(); if H.feature('ui') and settings.debugViewer then UI.toggle() end
    end)() end
    if requests.native then requests.native=nil; H.guard('F7 native rules',function() ensureStorage(); if H.feature('ui') then UI.openNative() end end)() end
    if requests.ping then requests.ping=nil; H.guard('F9 probe',Probe.ping)() end
end
local function maintenance(menuOnly)
    H.menuDriver=menuOnly
    -- Rules exchange lifetime/publication is owned by Core connection events.
    -- Existing proposal/UI/effect maintenance remains a separate policy.
    if dirty==0 then
        if H.feature('sync') then
            local before=Sync.revision
            H.guard('proposals',Proposals.poll)()
            if Sync.revision~=before then H.wake() end
        end
        return
    end
    dirty=dirty-1
    H.guard('storage',ensureStorage)()
    local enabled=false
    for _,name in ipairs(Policy.names) do if H.feature(name) then enabled=true; break end end
    if not enabled then return end -- no native snapshot/effect work with every feature off
    if H.feature('creative') then H.guard('Creative playtest rules',Creative.poll)() end
    H.guard('active effects',refreshEffects)()
    H.guard('hook retry',H.retryHooks)()
    local ok,err=pcall(refresh)
    if not ok then snapshot=nil; stable=false; fingerprint=nil; H.guard('snapshot',function() error(err) end)() end
    H.guard('extras',Extras.scan)()
    if H.feature('sync') then
        H.guard('active effects',refreshEffects)()
        H.guard('proposals',Proposals.poll)()
    end
    H.guard('physics',Physics.scan)()
    if H.feature('ui') then H.guard('UI refresh',UI.poll)() end
end
local driverStop
H.lifetime.onReset(function()
    if driverStop then driverStop(); driverStop=nil end
    H.wake()
    snapshot=nil; stable=false; fingerprint=nil; requests={}; effectExtras={}; lastGS=nil
    for _,api in pairs({UI,Probe,Extras,Creative,Sync,Physics,Proposals}) do if api.reset then api.reset() end end
end)
H.installTravel(Config.nativeTravelHooks)
-- Existing bounded periodic driver for UI/effects and the bridge TTL.
H.actorChanged=Creative.actorChanged
api.game_thread(function()
    ensureStorage(); H.retryHooks()
    -- Seed the already-observed local controller without another object walk.
    local pc=WIR_RUNTIME.input and WIR_RUNTIME.input.controller
    if H.valid(pc) then
        for _,class in ipairs({'B_PlayerController_C','B_ObjectivePlayerController_C','B_CreativePlayerController_C','B_MenuPlayerController_C'}) do
            if H.class(pc,class) then H.admit(class,pc) end
        end
    end
    refreshEffects(); if Sync then Sync.publish() end
    H.resync(function()
        if H.feature('ui') then UI.discover() end
        maintenance(false)
    end)
end)
local function armDriver()
    if driverStop then driverStop(); driverStop=nil end
    local epoch=H.lifetime.epoch
    driverStop=api.loop(500,function()
        if epoch~=H.lifetime.epoch then return end
        H.core.event_clock.tick(.5)
        if H.lifetime.transition then return end
        Extras.heartbeat()
        maintenance(false)
    end)
end
armDriver()
-- The departing loop is canceled by reset; destination evidence starts a fresh
-- scalar-only driver. Notification bookkeeping remains in Core's owned registry.
api.on('world_ready',armDriver,{ungated=true})
-- Concrete birth settlement also works in fixtures/engines without world_ready.
local ready=H.destinationReady
H.destinationReady=function() if ready then ready() end; if not driverStop then armDriver() end end
api.command('mrpp',function(_,args)
    if args[1]=='timedump' then
        module('time_dump').dump(H,api)
    elseif args[1]=='resync' then
        api.game_thread(function() if H.lifetime.transition then return end; H.resync(); H.retryHooks(); UI.discover(); H.wake() end)
    else log('mrpp timedump: read-only calibration; mrpp resync: explicit controller/actor/open-menu bootstrap') end
    return true
end)
-- UIKit owns this cancellation resource; it also tears down menu sessions first.
UI.own(function()
    -- Restore owned gameplay patches synchronously while objects are still live.
    closing=true; Creative.close(); effectExtras={}
    local context=api.context(); context.possession_lifetime=5; WIR_RUNTIME.set_context(context)
    Extras.scan(true); Extras.close(); Physics.close()
    Extras.reset(); Proposals.close()
end)
log('Package loaded. F7: Match Rules +; Ctrl+F7: optional debug viewer; F9: opt-in transport ping. Maintenance: 500 ms runtime timer.')
end
