-- The native Game Rules pages: reading the rules in force, staging a document for the
-- next match, Creative playtests, painting the pages and recording edits made on them.
return function(M)
    local R,C,U,D=M.R,M.C,M.U,M.doc
    local hooks,settings,schema=M.hooks,M.settings,M.schema
    local RULEUI,CREATIVE=M.RULEUI,M.CREATIVE
    local editorRules,activeCreative=nil,false
    local function subsystem(category)
        return M.library('SubsystemBlueprintLibrary'):GetWorldSubsystem(C.session().world,StaticFindObject(schema.subsystems[category]))
    end

    -- A document of the rules in force: the running match's, or the next match's.
    -- Guests read the host's published rules. `effective` holds every value the
    -- native subsystems use, for painting pages that show defaults too.
    function M.capture(fromNext,source)
        local s=C.session()
        if s.role=='client' and s.mode~='vanilla' and M.hostView then return D.clone(M.hostView.document) end
        local mode
        if source then mode=M.pathOf(source.GameModeClass)
        elseif (s.role=='host' or s.role=='client') and R.valid(s.gs) and (not s.is_creative or M.playing()) and not fromNext then
            source,mode=s.gs,M.pathOf(s.gs.GameModeClass)
        else
            local options=M.nextOptions()
            source,mode=options:GetGameRules(),M.pathOf(options.GameMode)
        end
        local extras=s.role~='client' and settings.selected and settings.selected.extras or {MatchRulesPlusPlus={}}
        local doc={format='MatchRulesPlusPlus',version=2,mode=mode,native={},extras=D.clone(extras),effective={}}
        for category in pairs(schema.collections) do doc.native[category]=D.read(source,category) end
        for _,group in ipairs(schema.groups) do
            local effective={}
            doc.effective[group.category..':'..group.id]=effective
            local parameters=subsystem(group.category)[group.property]
            for _,row in ipairs(group.rows) do
                local value=parameters[row.name]
                -- Modifiers other than Move or Damage are off in Fill a Pot, all are off in Impostor.
                if group.category=='mods' and row.name=='IsEnabled' and
                    (mode:find('B_ImpostorGameMode_C',1,true) or mode:find('B_ObjectiveGameMode_C',1,true) and group.id~=1) then value=false end
                effective[row.name]=value
            end
        end
        return doc
    end
    -- Select a document for the next match. It becomes the selection when that match starts.
    function M.stage(doc)
        if not M.editable() then U.message('Rules','Only the host can select rules in this session.');return end
        local options=M.nextOptions()
        if doc.mode~=M.pathOf(options.GameMode) then U.message('Rules','Select the preset’s game mode first.');return end
        options.GameRules=D.materialize(doc,options)
        options.GameRulesToLoad=''
        options.IsUsingCustomRules=true
        settings.pending=D.clone(doc)
        if C.session().role=='offline' then settings.selected=D.clone(doc) end
        M.persist()
        return true
    end
    -- Hosting from the main menu recomputes IsUsingCustomRules from the menu world's native
    -- rule subsystems (B_WitchHuntFunctionLibrary.AreAnyRulesCurrentlyEnabled), which a
    -- staged document never touches. Apply the staged document to the options being hosted
    -- and to the next-match options, from which every later match of the session is copied.
    hooks.pre('/Game/Blueprints/Core/B_GameInstance.B_GameInstance_C:HostGame',function(gi)
        local doc=settings.pending
        if not doc then return end
        for _,options in ipairs({gi.UsedMatchOptions,gi.NextMatchOptions}) do
            if doc.mode==M.pathOf(options.GameMode) then
                options.GameRules=D.materialize(doc,options)
                options.GameRulesToLoad=''
                options.IsUsingCustomRules=true
            end
        end
    end)
    -- The game's options start empty on each launch. Kept rules enter them the first time
    -- Custom Match reads them, which paints the native rule pages too.
    local restore=settings.keepRules
    hooks.pre('/Game/UserInterface/Play/WB_Custommatch.WB_Custommatch_C:LoadGameRules',function()
        if not restore or not M.editable() then return end
        restore=false
        local doc=settings.pending
        if not doc then return end
        local options=C.session().gi.NextMatchOptions
        options.GameRules=D.materialize(doc,options)
        options.GameRulesToLoad=''
        options.IsUsingCustomRules=true
    end)
    function M.promote()
        if not settings.pending then return end
        settings.selected,settings.pending=settings.pending,nil
        M.persist()
        -- Sliders change extra rules only, which leaves the flag of the options as it was.
        local s=C.session()
        local live=s.is_creative and s.gi.NextMatchOptions or s.gi.UsedMatchOptions
        live.IsUsingCustomRules=true
    end

    -- Creative playtests apply the selected document live and restore the editor's rules after.
    local function publishCollections(gs,rules)
        gs:FlushNetDormancy()
        for _,def in pairs(schema.collections) do
            gs[def.field]=rules[def.field]
            M.library('NetPushModelHelpers'):MarkPropertyDirtyFromRepIndex(gs,def.rep,FName(def.field))
            gs['OnRep_'..def.field](gs)
        end
        gs:ForceNetUpdate()
    end
    -- Only scalar rule values survive Play Test's native collection lifetime.
    local function saveEditor() editorRules=M.capture(false,C.session().gs) end
    function M.creativeApply(doc)
        local s=C.session()
        if not s.is_creative or s.role~='host' then return end
        if not editorRules then saveEditor() end
        activeCreative=true
        publishCollections(s.gs,D.materialize(doc,s.gi))
        M.refreshEffects()
    end
    function M.stopCreative()
        if not activeCreative then return end
        activeCreative=false
        M.cleanupAbandoned()
        if editorRules then
            publishCollections(C.session().gs,D.materialize(editorRules,C.session().gi))
            editorRules=nil
        end
        M.refreshEffects()
        M.publishView()
    end
    function M.useNativeRules()
        settings.selected,settings.pending=nil,nil
        M.persist()
        local options=M.nextOptions()
        options.GameRules,options.GameRulesToLoad,options.IsUsingCustomRules=D.nativeRules(options),'',false
        if activeCreative then M.stopCreative() else M.refreshEffects() end
        M.publishView()
    end
    hooks.pre(CREATIVE..'B_CreativeGameMode.B_CreativeGameMode_C:BeginPlayTest',function()
        if M.editable() and (settings.selected or settings.pending) then saveEditor() end
    end)
    hooks.post(CREATIVE..'B_CreativeGameMode.B_CreativeGameMode_C:BeginPlayTest',function()
        local s=C.session()
        if s.role~='host' or s.gs.IsPlayTestMode~=true then return end
        M.promote()
        if settings.selected then M.creativeApply(settings.selected);M.publishView() end
    end)
    hooks.post(CREATIVE..'B_CreativeGameMode.B_CreativeGameMode_C:EndPlayTest',M.stopCreative)
    for _,event in ipairs({'OnRep_IsPlayTestMode','TogglePlayTestMultiCast'}) do
        hooks.post(CREATIVE..'B_CreativeGameState.B_CreativeGameState_C:'..event,function(gs)
            if gs.IsPlayTestMode~=true and C.session().role=='host' then M.stopCreative() end
        end)
    end
    R.on('world_end',function() editorRules,activeCreative=nil,false end)

    -- The four native pages. Painting never captures or applies rules.
    local pages={
        {asset='WB_MatchRules.WB_MatchRules_C',refresh='RefreshMatchRules',category='match',
            slider='OnParamSliderRealValueChanged',apply='ApplyChanges'},
        {asset='SkillRules/WB_SkillRules.WB_SkillRules_C',refresh='RefreshSkillRuleUI',category='skills',
            typeField='CurrentSkillType',slider='OnParamSliderRealValueChanged',apply='ApplyRules'},
        {asset='Mods/WB_ModConfigure.WB_ModConfigure_C',refresh='RefreshModifierUI',category='mods',
            typeField='CurrentModType',slider='OnFloatParamSliderRealValueChanged',apply='ApplyRules'},
        {asset='PowerupRules/WB_PowerupConfigure.WB_PowerupConfigure_C',refresh='RefreshPowerupUI',category='powerups',
            typeField='CurrentPowerupType',slider='OnFloatParamSliderRealValueChanged',apply='ApplyRules'},
    }
    -- The schema group a page control belongs to; match rules number their controls.
    local function groupOf(page,widget,control)
        local id=page.typeField and widget[page.typeField] or control.Index
        return D.index[page.category][id],id
    end
    -- A guest's edits on these pages: their own rules, for a code. They never reach the match.
    local function guestEntry(doc,category,id)
        for _,entry in ipairs(doc.native[category]) do
            if entry.id==id then return entry end
        end
    end
    local function guestValue(category,id,name)
        local entry=M.guestRules and guestEntry(M.guestRules,category,id)
        return entry and entry.values[name]
    end
    local function setGuestValue(category,id,name,value)
        local doc=M.guestEdited()
        local entry=guestEntry(doc,category,id)
        if not entry then
            entry={id=id,values={}}
            doc.native[category][#doc.native[category]+1]=entry
        end
        entry.values[name]=value
    end
    for _,page in ipairs(pages) do
        local path=RULEUI..page.asset..':'..page.refresh
        hooks.pre(path,function() M.filling=true end)
        hooks.post(path,function(widget)
            local s=C.session()
            if s.role=='offline' then M.filling=false;return end
            local sub=subsystem(page.category)
            -- Creative authoring paints the detached next-match rules, not the running world.
            local draftValues
            if s.role=='host' and s.is_creative and not M.playing() then
                draftValues={}
                for _,entry in ipairs(D.read(M.nextOptions():GetGameRules(),page.category)) do draftValues[entry.id]=entry.values end
            end
            local paint={}
            for _,control in ipairs(D.values(widget.UIElements)) do
                if R.valid(control) then
                    local kind=control:GetClass():GetFName():ToString()
                    local isBool=kind=='WB_CheckBoxWithEditableLabel_C'
                    if isBool or kind=='WB_SliderWithEditableLabel_C' then
                        local group,id=groupOf(page,widget,control)
                        local metadata=isBool and control.BoolParameter or control.FloatParameter
                        local row=group.byNativeName[M.text(metadata.Name):lower()]
                        local value
                        if draftValues then
                            value=draftValues[id] and draftValues[id][row.name]
                            if value==nil then
                                if isBool then value=control.DefaultBoolValue else value=control.DefaultFloatValue end
                            end
                        elseif s.role=='client' then
                            local effective=M.hostView and M.hostView.document.effective
                            value=guestValue(page.category,id,row.name)
                            if value==nil then value=effective and effective[page.category..':'..id][row.name] end
                            if value==nil then value=sub[group.property][row.name] end
                        else value=sub[group.property][row.name] end
                        if value~=nil then paint[#paint+1]={control=control,value=value,bool=isBool} end
                    end
                end
            end
            for _,item in ipairs(paint) do
                if not item.bool then
                    item.control:SetRealValue(item.value)
                    widget[page.slider](widget,item.control,item.control.RealValue)
                end
            end
            for _,item in ipairs(paint) do
                if item.bool then
                    item.control:SetIsCheckedWithoutEvent(item.value)
                    item.control:CheckDefaultToUpdateUI()
                    widget:OnCheckBoxValueChanged(item.control,item.value)
                end
                if s.role=='host' and M.playing() and not s.gm.IsLiveRuleEditingAllowed then item.control:SetIsEnabled(false) end
            end
            M.filling=false
        end)
    end
    -- Guests of a modded host never change rules locally; the host's rules arrive by replication.
    local function guest() return C.session().role=='client' or nil end
    hooks.pre(RULEUI..'WB_MatchRules.WB_MatchRules_C:ApplyChanges',guest)
    for _,name in ipairs({'UpdateMatchRules','UpdateSkillRules','UpdateModRules','UpdatePowerupRules','ResetAllRules'}) do
        hooks.pre(M.CORE..'B_GameState.B_GameState_C:'..name,guest)
    end
    -- A native apply or reset on the host selects the rules it produced.
    local function selectCaptured()
        settings.selected=D.clean(M.capture(true))
        M.persist()
    end
    for _,path in ipairs({
        RULEUI..'WB_MatchRules.WB_MatchRules_C:Apply Rules',
        RULEUI..'SkillRules/WB_SkillRules.WB_SkillRules_C:ApplyRules',
        RULEUI..'Mods/WB_ModConfigure.WB_ModConfigure_C:ApplyRules',
        RULEUI..'PowerupRules/WB_PowerupConfigure.WB_PowerupConfigure_C:ApplyRules',
        M.TABS..':ResetAllToDefault',
        RULEUI..'WB_SaveLoadGameRules.WB_SaveLoadGameRules_C:ResetRules'
    }) do
        hooks.pre(path,guest)
        hooks.post(path,function()
            local s=C.session()
            if M.filling or not M.editable() then return end
            if s.is_creative and M.playing() and not s.gm.IsLiveRuleEditingAllowed then return end
            selectCaptured()
            if s.is_creative and M.playing() then M.creativeApply(settings.selected) end
            M.publishView()
        end)
    end
    -- Live editing during a Creative playtest applies each changed value immediately.
    for _,page in ipairs(pages) do
        for _,event in ipairs({page.slider,'OnCheckBoxValueChanged'}) do
            hooks.post(RULEUI..page.asset..':'..event,function(widget,sender,value)
                local s=C.session()
                local guest=s.role=='client'
                if M.filling or not guest and (not M.editable() or not s.is_creative or not M.playing() or not s.gm.IsLiveRuleEditingAllowed) then return end
                if not R.valid(sender) then return end
                local group,id=groupOf(page,widget,sender)
                local metadata=event=='OnCheckBoxValueChanged' and sender.BoolParameter or sender.FloatParameter
                local row=group.byNativeName[M.text(metadata.Name):lower()]
                if guest then setGuestValue(page.category,id,row.name,value);return end
                if subsystem(page.category)[group.property][row.name]==value then return end
                M.filling=true
                widget[page.apply](widget)
                M.filling=false
                selectCaptured()
                M.creativeApply(settings.selected)
                M.publishView()
            end)
        end
    end
    -- The native save/load screen: a saved file carries the extra rules beside it, and
    -- loading it selects them with its native rules for the next match.
    C.saved_rules.register(M.PKG,{
        save=function()
            local doc=settings.pending or settings.selected
            return doc and D.clone(D.own(doc)) or {}
        end,
        load=function(own)
            local s=C.session()
            settings.pending=D.clean(M.capture(true))
            settings.pending.extras[M.PKG]=D.cleanOwnExtras(own or {})
            M.persist()
            if s.is_creative and M.playing() and s.gm.IsLiveRuleEditingAllowed then
                M.promote();M.creativeApply(settings.selected)
            end
            M.publishView()
        end})
    local saveScreen=RULEUI..'WB_SaveLoadGameRules.WB_SaveLoadGameRules_C:Construct'
    hooks.post(saveScreen,function(page)
        if not M.editable() then return end
        local child=page.WB_SaveLoadScreen
        if child.FileEditingAllowed then return end
        local options=M.nextOptions()
        options.GameRules=D.materialize(M.capture(true),options)
        child.FileToSave=options.GameRules
        child.FileEditingAllowed=true;page.FileEditingAllowed=true;child:SetUITexts()
        local name=M.text(child.InitialEntryName)
        local present=false
        child.SaveEntries:ForEach(function(key) if M.text(key:get())==name then present=true end end)
        if not present then child:CreateNewSaveEntry(name,{});child:CheckForTooManySavegames() end
    end)
end
