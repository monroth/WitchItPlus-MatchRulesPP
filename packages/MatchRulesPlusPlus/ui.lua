-- Reuse cooked native widgets; no Lua delegate binding or cooked asset changes.
local M={}
local T='/Game/UserInterface/Play/GameRules/WB_GameRulesTabs.WB_GameRulesTabs_C:'
local E='/Game/UserInterface/UIElements/'
local SAVE='/Game/UserInterface/Play/GameRules/WB_SaveLoadGameRules.WB_SaveLoadGameRules_C:'
local SAVE_CHILD='/Game/UserInterface/SaveLoad/WB_SaveLoadScreen.WB_SaveLoadScreen_C:'
function M.init(H,A)
    local api={}; local screens={}; local standalone; local nativeSession; local nativeNavigation=0
    local same=H.same
    local kit=H.api.shared('UIKit').new(H.api)
    local nativeRules=H.module('native_rules').init(H)
    api.own=kit.own
    local scopes,rows={},{ }
    local function scope(w) return assert(scopes[H.key(w)],'no construction scope') end
    local function class(asset,folder)
        local path=(folder or E)..asset..'.'..asset..'_C'
        return H.object(path)
    end
    local function native(w,c) return scope(w).native(c) end
    local function text(w,p,s) return kit.header(scope(w),p,s) end
    local function label(b,s) rows[H.key(b)].set_label(s) end
    local function remember(w,row)
        local key=H.key(row.widget); rows[key]=row
        scope(w).own(function() rows[key]=nil end)
        return row.widget
    end
    local function button(w,p,s,fn)
        return remember(w,kit.button(scope(w),p,{label=s,on_click=function()
            fn(s); if H.wake then H.wake() end
        end}))
    end
    local function check(w,p,s,v,changed) return remember(w,kit.checkbox(scope(w),p,{label=s,value=v,on_change=changed})) end
    local function slider(w,p,s,v,changed)
        return remember(w,kit.slider(scope(w),p,{label=s.label,kind=s.kind,min=s.min,max=s.max,step=s.step,value=v,on_change=changed}))
    end
    local function getValue(w) return rows[H.key(w)].get() end
    local function setValue(w,v) rows[H.key(w)].set(v) end
    local nativeProperties={enabled={'GetIsEnabled','SetIsEnabled'},visibility={'GetVisibility','SetVisibility'}}
    local function setNative(r,w,property,value)
        if not H.valid(w) then return end
        local methods=nativeProperties[property]; local key=H.key(w)..':'..property
        r.nativeStates=r.nativeStates or {}
        local state=r.nativeStates[key]
        if not state then
            state={widget=w,methods=methods,original=w[methods[1]](w)}; r.nativeStates[key]=state
        end
        state.installed=value; w[methods[2]](w,value)
    end
    local function liveRecord(r)
        return r.scope and not r.scope.closed and H.valid(r.widget) and H.valid(r.page)
            and H.sameWorld(r.page,r.widget)
    end
    local function reconcile(r) return r.binding.reconcile() end
    local function nameField(r) return r.scope.find_native('EditableTextBox',r.rows) end
    local function focus(r)
        local field=nameField(r)
        field:SetUserFocus(r.widget:GetOwningPlayer()); field:SetKeyboardFocus()
    end
    local function setStatus(r,s) r.status:SetText(FText(s)); H.log(s) end
    local function editPreset(r)
        local preset,name,defaults,schema=A.localDraft(H.text(nameField(r):GetText()))
        r.editorLocal=true
        if r.editorScope then r.editorScope.close() end
        r.editorScope=kit.scope(r.widget,{parent=r.scope,enabled=function() return r.scope.live() end})
        scopes[H.key(r.widget)]=r.editorScope
        local scroll=kit.scroll(r.editorScope,r.rows,{})
        r.editor=scroll.widget; local editor=scroll.rows
        r.editorName=name; r.editorRows={}
        text(r.widget,editor,'Editing '..name)
        for _,g in ipairs(schema) do
            text(r.widget,editor,A.ruleLabel(g.property))
            local overrides={}
            for _,entry in ipairs(preset.collections[g.category]) do if entry.id==g.id then overrides=entry.values; break end end
            for _,s in ipairs(g.rows) do
                local value=overrides[s.name]
                if value==nil then value=defaults[g.category..':'..g.id][s.name] end
                local control
                if s.kind=='bool' then control=check(r.widget,editor,A.ruleLabel(s.name),value)
                else
                    -- Some native defaults exceed slider metadata. Display a bounded
                    -- starting point but do not save it unless the user actually edits.
                    value=math.min(s.max,math.max(s.min,value))
                    control=slider(r.widget,editor,{label=A.ruleLabel(s.name),min=s.min,max=s.max,step=s.step,kind=s.kind},value)
                end
                r.editorRows[#r.editorRows+1]={widget=control,category=g.category,id=g.id,spec=s,initial=value}
            end
        end
        r.draftExtras={}
        if r.editorLocal then
            text(r.widget,editor,'Extra rules')
            for _,spec in ipairs(A.extraSpecs) do
                local value=preset.extras[spec.key]
                local enabled=check(r.widget,editor,'Override '..spec.label,value~=nil)
                local never=spec.allowNever and check(r.widget,editor,'Keep abandoned props',value=='never') or nil
                local fallback=spec.default or ({pickupMin=30,pickupJitter=10,roundDelay=22,potatoRecharge=10,cooldownMin=.02})[spec.key]
                r.draftExtras[#r.draftExtras+1]={spec=spec,enable=enabled,never=never,widget=slider(r.widget,editor,spec,type(value)=='number' and value or fallback)}
            end
        end
        scopes[H.key(r.widget)]=r.scope
        if r.editorLocal then
            label(r.saveEdits,'Save local preset edits')
            setStatus(r,'Editing '..name)
        else
            label(r.saveEdits,'Save selected preset edits')
            setStatus(r,'Editing '..name)
        end
    end
    local function refreshOffers(r)
        if not A.pendingOffers then return end
        local offers=A.pendingOffers(); local parts={}
        for _,offer in ipairs(offers) do parts[#parts+1]=offer.id..':'..(offer.error or offer.notice or '') end
        local signature=table.concat(parts,'|')
        if signature==r.offerSignature then return end
        r.offerSignature=signature
        if r.offerScope then r.offerScope.close() end
        local scope=kit.scope(r.widget,{parent=r.scope});r.offerScope=scope
        kit.header(scope,r.offerRows,#offers==0 and 'No pending rules offers.' or 'Pending rules offers')
        for _,offer in ipairs(offers) do
            local id=offer.id
            kit.header(scope,r.offerRows,(offer.shared and 'Host shared: ' or 'Client proposal: ')..offer.name..((offer.error or offer.notice) and (' — '..(offer.error or offer.notice)) or ''))
            local function action(label,fn)
                kit.button(scope,r.offerRows,{label=label,on_click=function()
                    H.log('Rules inbox '..label..': pressed')
                    local ok,message=pcall(fn,id)
                    local status=ok and (message or 'Done') or ('ERROR: '..tostring(message))
                    H.log('Rules inbox '..label..': '..status)
                    local current=screens[H.key(r.widget)]
                    if current and liveRecord(current) then
                        local painted,why=pcall(function() current.status:SetText(FText(ok and status or (H.player_error and H.player_error(message)or 'Could not answer this offer. Try again.')));refreshOffers(current) end)
                        if not painted then H.log('Rules inbox status unavailable: '..tostring(why)) end
                    end
                    if H.wake then H.wake() end
                end})
            end
            action('Review '..offer.name,A.reviewOffer)
            action(offer.shared and 'Save as new preset' or 'Accept for next match',function(id) return A.answerOffer(id,true) end)
            action(offer.shared and 'Ignore' or 'Decline',function(id) return A.answerOffer(id,false) end)
        end
    end
    local function extraPermissions(r,host,nextMatch)
        local function enable(w,value)
            if w:GetIsEnabled()~=value then w:SetIsEnabled(value) end
        end
        enable(r.apply,host or nextMatch);enable(r.spawn,host)
        for _,row in ipairs(r.extraRows)do
            local allowed=host or (nextMatch and row.spec.nextMatch==true)
            enable(row.widget,allowed)
            if row.enable then enable(row.enable,allowed)end
            if row.never then enable(row.never,allowed)end
        end
    end
    local binding
    binding=kit.bind.match_rules_tab({label='Match Rules +',enabled=function() return not H.feature or H.feature('ui') end,build=function(scope,page,w,tab)
        local key=H.key(w); scopes[key]=scope
        local record={widget=w,page=tab.widget,rows=page,tab=tab.button,scope=scope,binding=tab,
            extraRows={},originalButtons=H.values(w.Buttons),originalTabs=H.values(w.RuleTabs),
            extrasRevision=A.extrasRevision and A.extrasRevision() or 0,probeRevision=A.probeRevision and A.probeRevision() or 0}
        -- UIKit has already appended its tab; snapshots contain native/other-mod entries only.
        table.remove(record.originalButtons); table.remove(record.originalTabs)
        screens[key]=record
        scope.own(function()
            screens[key]=nil; scopes[key]=nil
            for _,state in pairs(record.nativeStates or {}) do
                local w=state.widget; local methods=state.methods
                if H.valid(w) and w[methods[1]](w)==state.installed then w[methods[2]](w,state.original) end
            end
        end)
            text(w,page,'Presets and extra rules')
            record.status=text(w,page,'')
            local field=scope.native('EditableTextBox',page)
            field:SetHintText(FText('Preset name')); field:SetText(FText('host-rules'))
            local function action(fn)
                return function(label)
                    H.log('Rules action '..label..': pressed')
                    local current=screens[key]
                    local good,message=pcall(function()
                        assert(current and liveRecord(current),'current Rules tab unavailable')
                        return fn(H.text(nameField(current):GetText()),current)
                    end)
                    local status=good and (message or 'Done') or ('ERROR: '..tostring(message))
                    H.log('Rules action '..label..': '..status)
                    if current then
                        local ok,why=pcall(function() current.status:SetText(FText(good and status or (H.player_error and H.player_error(message)or 'Could not complete this action. Try again.'))) end)
                        if not ok then H.log('Rules status unavailable: '..tostring(why)) end
                    end
                end
            end
            record.save=button(w,page,'Save rules locally',action(A.save))
            record.load=button(w,page,'Load local preset',action(function(name) return A.load('presets',name) end))
            record.import=button(w,page,'Load received preset',action(function(name) return A.load('imports',name) end))
            record.transport=text(w,page,A.transportStatus and A.transportStatus() or '')
            if A.pendingOffers then record.offerRows=scope.native('VerticalBox',page);refreshOffers(record) end
            record.localEdit=button(w,page,'Edit preset',action(function(_,r) editPreset(r,true); return 'Save your changes before proposing.' end))
            record.propose=button(w,page,'Propose to host',action(function(name) return A.propose(name) end))
            record.share=button(w,page,'Share current rules',action(A.share))
            record.copyCode=button(w,page,'Copy as code',action(A.copyCode))
            record.importCode=button(w,page,'Import code',action(A.importCode))
            record.saveEdits=button(w,page,'Save local preset edits',action(function(_,r)
                assert(r.editorRows,'open the selected preset editor first')
                local edits={}
                for _,row in ipairs(r.editorRows) do
                    local value
                    if row.spec.kind=='bool' then value=getValue(row.widget) else value=getValue(row.widget) end
                    local changed=value~=row.initial
                    if type(value)=='number' then changed=math.abs(value-row.initial)>1e-6*math.max(1,math.abs(row.initial)) end
                    if changed then edits[#edits+1]={category=row.category,id=row.id,name=row.spec.name,value=value} end
                end
                if r.editorLocal then
                    local extras={}
                    for _,row in ipairs(r.draftExtras) do
                        if getValue(row.enable) then extras[row.spec.key]=row.never and getValue(row.never) and 'never' or getValue(row.widget) end
                    end
                    return A.commitLocal(edits,r.editorName,extras)
                end
            end))
            text(w,page,'')
            local extras=A.extras()
            record.spawn=check(w,page,'Override powerup spawn pacing',extras.pickupMin~=nil)
            for _,s in ipairs(A.extraSpecs) do
                text(w,page,s.nextMatch and 'Next match' or '')
                local row={spec=s}
                local function changed()
                    if not s.nextMatch or not liveRecord(record) then return end
                    local ok,message=pcall(function()
                        local value
                        if getValue(row.enable or record.spawn)then
                            value=row.never and getValue(row.never)and 'never' or getValue(row.widget)
                        end
                        return A.stageExtra(s.key,value)
                    end)
                    if not ok then H.log('Next-match extra refused: '..tostring(message));message=H.player_error and H.player_error(message)or 'Could not save this rule. Try again.' end
                    if message then setStatus(record,message)end
                    if H.wake then H.wake()end
                end
                if s.key~='pickupMin' and s.key~='pickupJitter' then row.enable=check(w,page,'Override '..s.label,extras[s.key]~=nil,changed) end
                row.never=s.allowNever and check(w,page,'Keep abandoned props',extras[s.key]=='never',changed) or nil
                local v=type(extras[s.key])=='number' and extras[s.key] or s.default or ({pickupMin=30,pickupJitter=10,roundDelay=22,potatoRecharge=10,cooldownMin=.02})[s.key]
                row.widget=slider(w,page,s,v,changed)
                record.extraRows[#record.extraRows+1]=row
            end
            record.apply=button(w,page,'Save extra rules',action(function(_,r)
                local values={}
                for _,row in ipairs(r.extraRows) do
                    if (A.isHost() or row.spec.nextMatch and nativeRules.menuContext(r.widget)) and getValue(row.enable or r.spawn) then values[row.spec.key]=row.never and getValue(row.never) and 'never' or getValue(row.widget) end
                end
                return A.applyExtras(values)
            end))
            record.probe=check(w,page,'Connection test (F9)',A.probeEnabled())
            record.probeApply=button(w,page,'Save connection test setting',action(function(_,r) return A.setProbe(getValue(r.probe)) end))
            record.debug=check(w,page,'Rules inspector',A.debugViewer and A.debugViewer() or false)
            record.debugApply=button(w,page,'Save inspector setting',action(function(_,r) return A.setDebugViewer(getValue(r.debug)) end))
            record.view=text(w,page,'')
            local debug=A.debugViewer and A.debugViewer() or false
            record.view:SetVisibility(debug and 0 or 1)
            record.saveEdits:SetVisibility(record.editorLocal and 0 or 1)
            local host=A.isHost()
            local nextMatch=nativeRules.menuContext(w)~=nil
            record.load:SetIsEnabled(host or nextMatch); record.import:SetIsEnabled(host or nextMatch)
            extraPermissions(record,host,nextMatch)
            record.saveEdits:SetIsEnabled((record.editorLocal and not host)==true)
            record.localEdit:SetIsEnabled(not host and not nextMatch); record.propose:SetIsEnabled(not host and not nextMatch);record.share:SetIsEnabled(host)
        tab.initial_focus=record.save
        kit.navigate({rows[H.key(record.save)],rows[H.key(record.load)],rows[H.key(record.import)],
            rows[H.key(record.localEdit)],rows[H.key(record.propose)],rows[H.key(record.share)],rows[H.key(record.copyCode)],rows[H.key(record.importCode)],rows[H.key(record.apply)]},tab.widget)
    end})
    local function inject(w)
        local tab=binding.ready(w)
        return tab and screens[H.key(w)]
    end
    local function open(w)
        if not w:IsVisible() then return false end
        if w:IsInViewport() then return true end
        local p=w:GetParent(); if not H.valid(p) then return false end
        for _=1,16 do if not H.valid(p) then break end; if not p:IsVisible() then return false end; p=p:GetParent() end
        return true
    end
    function api.offersOpen()
        for _,r in pairs(screens) do if liveRecord(r) and open(r.widget) then return true end end
        return false
    end
    local function restoreReadOnly(r)
        r.nativeReadOnly=nil
        for _,state in ipairs(r.readOnlyStates or {}) do
            if H.valid(state.widget) then state.widget:SetIsEnabled(state.enabled); state.widget:SetVisibility(state.visibility) end
        end
        r.readOnlyStates=nil
    end
    local function cachedMenu(manager,state)
        local found
        manager.MenuStateWidgets:ForEach(function(key,value)
            if H.unwrap(key)==state then found=H.unwrap(value) end
        end)
        return found
    end
    local function fileContext(w)
        local menuPC,gi=nativeRules.menuContext(w)
        if menuPC then return gi end
        if A.isCreative and A.isCreative() then
            local host,_,gs,_,creativeGI=H.creative()
            if host and H.sameWorld(w,gs) then return creativeGI end
        end
    end
    local function prepareFileBuffer(child,gi)
        if A.prepareNativeRules then A.prepareNativeRules() end
        -- Creative's first preparation can detach the next-match rule object.
        -- Point only the native save payload at that current buffer.
        local rules=gi.NextMatchOptions:GetGameRules()
        if H.valid(rules) and not H.same(child.FileToSave,rules) then child.FileToSave=rules end
    end
    local function prepareNativePage(w)
        if not H.valid(w) then return end
        if H.class(w,'WB_SaveLoadGameRules_C') then
            local gi=fileContext(w)
            local child=w.WB_SaveLoadScreen
            if gi and H.valid(child) and H.sameWorld(child,w)
                and (w.FileEditingAllowed~=true or child.FileEditingAllowed~=true) then
                prepareFileBuffer(child,gi); nativeRules.allowFiles(w)
            end
        end
        if A.bindNativeRulesView then A.bindNativeRulesView(w) end
    end
    local function restoreInput(session)
        local restore=session.restoreInput;session.restoreInput=nil
        if restore then restore() end
    end
    local function finishNative(restore)
        local session=nativeSession; if not session then return end
        nativeSession=nil
        if not H.valid(session.gi) then return end
        local manager=session.gi.MenuUIManager
        if restore~=false and H.valid(manager) then
            if H.valid(session.rules) and H.sameWorld(session.rules,session.gi) then manager:HideWidget(session.rules) end
            -- ChangeMenu owns cached-widget attachment, focus and input mode.
            -- CurrentWidget is a native function local, not a manager property.
            manager:ChangeMenu(session.state,true)
        end
        if restore~=false and H.valid(session.gi.IngameUIManager) then
            session.gi.IngameUIManager:CloseSubordinateMenu()
        end
        local r=H.valid(session.rules) and screens[H.key(session.rules)]
        if r then restoreReadOnly(r) end
        if restore~=false then restoreInput(session) end
    end
    function api.openNative()
        if nativeSession then
            local manager=nativeSession.gi.MenuUIManager
            finishNative(H.valid(manager) and nativeSession.family[manager.CurrentMenuState]
                and nativeNavigation==nativeSession.navigation)
            return
        end
        local pc,gs,_,gi=H.world(); if not (H.valid(pc) and H.valid(gs) and H.valid(gi)) or H.class(pc,'B_MenuPlayerController_C') then return end
        local manager=gi.MenuUIManager
        assert(H.valid(manager) and H.valid(gi.IngameUIManager),'native UI managers unavailable')
        if A.prepareNativeRules then A.prepareNativeRules() end
        local target; local family={}
        manager.MenuStateClasses:ForEach(function(key,value)
            local cls=H.unwrap(value); local menu=H.unwrap(key)
            if H.valid(cls) then
                if H.text(cls):find('/Game/UserInterface/Play/GameRules/',1,true) then family[menu]=true end
                if H.text(cls:GetFName())=='WB_GameRulesTabs_C' then target=menu; family[menu]=true end
            end
        end)
        assert(type(target)=='number','native Match Rules menu state unavailable')
        if manager.CurrentMenuState==target then
            -- A native/other-owned Rules page is already open. Keep its selected
            -- tab and never own, hide, or reopen that existing menu session.
            local w=cachedMenu(manager,target)
            if H.valid(w) and H.class(w,'WB_GameRulesTabs_C') and open(w) then
                local r=inject(w)
                if r then
                    if not A.isHost() and A.restoreClientRules then A.restoreClientRules() end
                    api.poll()
                end
            end
            return
        end
        local session={gi=gi,state=manager.CurrentMenuState,target=target,family=family,gs=H.key(gs)}
        session.restoreInput=H.api.shared('Core').dialog_input.save(pc)
        nativeSession=session
        local function attach(tries)
            if nativeSession~=session then return end
            local _,current=H.world()
            if not H.valid(current) or H.key(current)~=session.gs or not H.valid(manager) or manager.CurrentMenuState~=session.target then
                finishNative(false); return
            end
            local ok,err=pcall(function()
                local w=cachedMenu(manager,session.target)
                if not (H.valid(w) and H.class(w,'WB_GameRulesTabs_C') and open(w)) then
                    assert(tries<60,'native Match Rules window unavailable')
                    H.api.delay(16,function() attach(tries+1) end); return
                end
                session.rules=w
                prepareNativePage(w)
                local r=inject(w)
                if not r then
                    assert(tries<60,'native Match Rules controls unavailable')
                    H.api.delay(16,function() attach(tries+1) end); return
                end
                r.nativeReadOnly=not A.isHost()
                if r.nativeReadOnly and A.restoreClientRules then A.restoreClientRules() end
                api.poll()
            end)
            if not ok then finishNative(); H.log('ERROR native rules: '..tostring(err)) end
        end
        local ok,err=pcall(function()
            gi.IngameUIManager:OpenSubordinateMenu(true); manager:ChangeMenu(session.target,true)
            session.navigation=nativeNavigation
            H.api.retry_hooks(); attach(0)
        end)
        if not ok then finishNative(); error(err) end
    end
    H.hook('/Game/Blueprints/UserInterface/B_MenuUIManager.B_MenuUIManager_C:ChangeMenu',function(self)
        nativeNavigation=nativeNavigation+1
        local session=nativeSession; local manager=H.unwrap(self)
        if session and H.same(manager,session.gi.MenuUIManager) and session.family[manager.CurrentMenuState] then
            -- Save/Load and native rule configuration pages are child navigation
            -- inside this same native session, not a different Creative interface.
            session.navigation=nativeNavigation
            -- First-load Blueprint events may precede deferred hook registration.
            -- Bind only this completed native page, never a polling/foreign page.
            H.api.retry_hooks()
            prepareNativePage(cachedMenu(manager,manager.CurrentMenuState))
        end
        -- Ordinary Custom Match navigation has no F7-owned session. Its first
        -- Save/Load construction may precede BP hook availability too.
        if not session and H.valid(manager) then
            local w=cachedMenu(manager,manager.CurrentMenuState)
            if H.valid(w) and H.class(w,'WB_SaveLoadGameRules_C') then
                H.retryHooks(); prepareNativePage(w)
            end
        end
    end)
    H.hook(T..'SetActiveTab',function(self)
        local w=H.unwrap(self)
        if nativeSession and same(w,nativeSession.rules) then
            H.api.retry_hooks(); prepareNativePage(w)
        end
    end)
    H.hook(SAVE..'Construct',function(self) prepareNativePage(H.unwrap(self)) end)
    H.hook(SAVE_CHILD..'SetUITexts',function(self)
        local child=H.unwrap(self)
        local folder=H.read(child,'FolderName')
        if child.FileEditingAllowed==true or folder==nil or H.text(folder)~='GameRules' then return end
        local gi=fileContext(child); if not gi then return end
        -- Native Initialize invokes this before its one RefreshSaveEntryList.
        -- The recursive title refresh exits through the true permission guard.
        prepareFileBuffer(child,gi); nativeRules.allowFileFields(child)
    end)
    for _,event in ipairs({'OnBack','OnApply'}) do H.hook(T..event,function(self)
        local session=nativeSession
        if session and same(H.unwrap(self),session.rules) then
            local manager=session.gi.MenuUIManager
            local state=H.valid(manager) and manager.CurrentMenuState
            local navigation=nativeNavigation
            H.defer(function()
                if nativeSession==session then
                    finishNative(H.valid(manager) and manager.CurrentMenuState==state and nativeNavigation==navigation)
                    restoreInput(session) -- native Back may already have routed/closed
                end
            end)
        end
    end) end
    local creativeEntry=kit.bind.menu({asset='WB_CreativeIngameMenu',folder='/Game/UserInterface/CreativeMode/',
        anchor=function(w) return w.Settings end,direct_entry=true,
        enabled=function() return (not H.feature or H.feature('ui')) and A.isCreative and A.isCreative()==true end,
        build=function(scope,panel,w,record)
            local entry=kit.button(scope,panel,{class=w.Settings:GetClass(),label='Match Rules +',single_line=true,
                on_click=H.guard('Creative Match Rules',api.openNative)})
            record.widget=entry.widget
        end})
    H.hook('/Game/Blueprints/UserInterface/B_IngameUIManager.B_IngameUIManager_C:ShowMenu',function(self)
        local w=H.unwrap(self).MenuWidget
        if H.valid(w) and H.class(w,'WB_CreativeIngameMenu_C') then H.defer(function() creativeEntry.ready(w) end) end
    end)
    function api.discover()
        binding.resync(); creativeEntry.resync()
    end
    local function standaloneOnly(r)
        -- A private debug viewer keeps native trees attached; UIKit never reparents them.
        r.nativeReadOnly=not A.isHost()
    end
    function api.toggle()
        local pc=H.world(); assert(H.valid(pc),'join a lobby before opening Rules++')
        local lib=H.object('/Script/UMG.Default__WidgetBlueprintLibrary')
        if standalone and H.valid(standalone.widget) and standalone.widget:IsInViewport() then
            local r=standalone; standalone=nil; r.scope.close()
            return
        end
        local w=lib:Create(pc,class('WB_GameRulesTabs','/Game/UserInterface/Play/GameRules/'),pc)
        assert(H.valid(w),'cannot create RulesTabs viewer')
        local ok,r=pcall(function()
            w:AddToViewport(100); local record=assert(inject(w),'viewer bindings not ready')
            record.cursor=pc.bShowMouseCursor==true; standaloneOnly(record); w:SetActiveTab(record.page)
            record.scope.own(function()
                if H.valid(pc) and pc.bShowMouseCursor==true then
                    pc.bShowMouseCursor=record.cursor
                    if record.cursor then lib:SetInputMode_GameAndUIEx(pc,w,0,false,false) else lib:SetInputMode_GameOnly(pc,false) end
                end
                if H.valid(w) then w:RemoveFromParent() end
            end)
            return record
        end)
        if not ok then w:RemoveFromParent(); error(r) end
        standalone=r; pc.bShowMouseCursor=true
        lib:SetInputMode_GameAndUIEx(pc,nameField(r),0,false,false); focus(r); api.poll()
    end
    function api.poll()
        local debug=A.debugViewer and A.debugViewer() or false
        local content=debug and A.describe() or ''; local host=A.isHost()
        for key,r in pairs(screens) do
            if not liveRecord(r) then screens[key]=nil
            elseif open(r.widget) then
                refreshOffers(r)
                if r==standalone then standaloneOnly(r) else reconcile(r) end
                local revision=A.extrasRevision and A.extrasRevision() or 0
                if revision~=r.extrasRevision then
                    local extras=A.extras(); setValue(r.spawn,extras.pickupMin~=nil)
                    for _,row in ipairs(r.extraRows) do
                        local value=extras[row.spec.key]
                        if row.enable then setValue(row.enable,value~=nil) end
                        if row.never then setValue(row.never,value=='never') end
                        if type(value)=='number' then setValue(row.widget,value) end
                    end
                    r.extrasRevision=revision
                end
                local probeRevision=A.probeRevision and A.probeRevision() or 0
                if probeRevision~=r.probeRevision then setValue(r.probe,A.probeEnabled()); r.probeRevision=probeRevision end
                local nextMatch=nativeRules.menuContext(r.widget)~=nil
                r.load:SetIsEnabled(host or nextMatch); r.import:SetIsEnabled(host or nextMatch)
                extraPermissions(r,host,nextMatch)
                r.saveEdits:SetIsEnabled((r.editorLocal and not host)==true)
                r.localEdit:SetIsEnabled(not host and not nextMatch); r.propose:SetIsEnabled(not host and not nextMatch);r.share:SetIsEnabled(host)
                if A.transportStatus then r.transport:SetText(FText(A.transportStatus())) end
                if r.editorRows then
                    for _,row in ipairs(r.editorRows) do row.widget:SetIsEnabled(r.editorLocal and not host) end
                end
                r.view:SetVisibility(debug and 0 or 1)
                r.saveEdits:SetVisibility(r.editorLocal and 0 or 1)
                if H.valid(r.editor) then r.editor:SetVisibility((debug or r.editorLocal) and 0 or 1) end
                if r.draftExtras then
                    for _,row in ipairs(r.draftExtras) do
                        local allowed=r.editorLocal and not host
                        row.enable:SetIsEnabled(allowed); row.widget:SetIsEnabled(allowed)
                        if row.never then row.never:SetIsEnabled(allowed) end
                    end
                end
                if debug then r.view:SetText(FText(content)) end
                -- Native menu controllers edit NextMatchOptions before hosting;
                -- gameplay authority and connected guests keep their live policy.
                if liveRecord(r) then
                    if not (host or nextMatch) then r.nativeReadOnly=true elseif r.nativeReadOnly then restoreReadOnly(r) end
                    if r.nativeReadOnly then
                        if not r.readOnlyStates then
                            r.readOnlyStates={}
                            local function remember(w)
                                if H.valid(w) then r.readOnlyStates[#r.readOnlyStates+1]={widget=w,enabled=w:GetIsEnabled(),visibility=w:GetVisibility()} end
                            end
                            for _,page in ipairs(r.originalTabs) do remember(page) end
                            for _,b in ipairs(r.originalButtons) do remember(b) end
                            for _,key in ipairs({'Button_SaveLoad','Button_DefaultAll','Button_Apply'}) do remember(r.widget[key]) end
                        end
                        for _,page in ipairs(r.originalTabs) do setNative(r,page,'enabled',false) end
                        for _,b in ipairs(r.originalButtons) do setNative(r,b,'enabled',true) end
                        for _,key in ipairs({'Button_SaveLoad','Button_DefaultAll','Button_Apply'}) do
                            local b=r.widget[key]; if H.valid(b) then setNative(r,b,'enabled',false); setNative(r,b,'visibility',1) end
                        end
                    end

                end
            end
        end

    end
    api.inject=inject -- offline coexistence harness
    local function closeWorld()
        finishNative()
        local work={}; for _,r in pairs(screens) do work[#work+1]=r.scope end
        local errors={}
        for _,scope in ipairs(work) do local done,why=scope.close();if done==false then errors[#errors+1]=why end end
        standalone=nil
        return #errors==0,table.concat(errors,' | ')
    end
    H.travelAdapter(function() closeWorld(); kit.travel_begin() end,kit.destination_ready)
    kit.own(closeWorld)
    H.api.on('load_map_pre',closeWorld,{ungated=true})
    function api.reset() screens={}; scopes={}; standalone=nil; nativeSession=nil end
    return api
end
return M
