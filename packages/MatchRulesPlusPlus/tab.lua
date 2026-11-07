-- The Match Rules ++ tab in Game Rules: rules as a code, and extra rules as plain sliders.
return function(M)
    local R,C,U,D=M.R,M.C,M.U,M.doc
    local settings=M.settings
    -- M.guestRules: a guest's own rules to play with. They reach other players only as a code.
    local function guest() return C.session().role=='client' end
    local function hostRules()
        local doc=D.clean(M.capture())
        if M.hostView then doc.extras[M.PKG]=D.clone(M.hostView.extras) end
        return doc
    end
    -- The rules a code carries: this mod's, and every other mod's beside them.
    local function rules()
        local doc=D.clone(guest() and (M.guestRules or hostRules()) or settings.pending or M.capture())
        for id,section in pairs(C.saved_rules.collect()) do
            if id~=M.PKG then doc.extras[id]=section end
        end
        return doc
    end
    local function shownExtras()
        if guest() then return M.guestRules and D.own(M.guestRules) or M.hostView and M.hostView.extras or {} end
        local doc=settings.pending or settings.selected
        return doc and D.own(doc) or {}
    end
    function M.guestEdited()
        M.guestRules=M.guestRules or hostRules()
        return M.guestRules
    end
    local function edited()
        if guest() then return M.guestEdited() end
        settings.pending=settings.pending or D.clean(M.capture(true))
        return settings.pending
    end
    local function set(spec,value)
        local own=D.own(edited())
        own[spec.key]=value~=spec.initial and value or nil
        -- The powerup pacing rule uses its two values together, and is off at the game's own.
        if own.pickupMin or own.pickupJitter then
            own.pickupMin,own.pickupJitter=own.pickupMin or 30,own.pickupJitter or 10
            if own.pickupMin==30 and own.pickupJitter==10 then own.pickupMin,own.pickupJitter=nil,nil end
        end
        if not guest() then M.persist() end
    end

    R.on('world_end',function() M.guestRules=nil end)
    U.rules_tab(M.TABS,'Match Rules ++',function(parent,scroll)
        local _,status=U.text(parent,{text=''})
        local refresh
        local export=U.button(parent,{label='Export rules as code',on_click=function()
            R.native.clipboard_set(D.encode(rules()));status('Rules code copied.')
        end})
        local import=U.button(parent,{label='Import rules from code',on_click=function()
            -- The native read fails when the clipboard holds no text.
            local read,code=pcall(R.native.clipboard_get)
            if not read then U.message('Import rules','Copy a rules code first.');return end
            local ok,doc=pcall(D.decode,code)
            if not ok then U.message('Import rules',M.problem(doc));return end
            if guest() then
                M.guestRules=doc
                C.saved_rules.load(doc.extras,M.PKG)
                status('Rules imported. The match keeps the host’s rules.')
            elseif M.stage(doc) then
                C.saved_rules.load(doc.extras,M.PKG)
                status('Rules selected for the next match.')
            end
            refresh()
        end})
        local pull=U.button(parent,{label='Pull rules from host',on_click=function()
            M.guestRules=nil
            C.saved_rules.load({},M.PKG)
            status('Showing the host’s rules.');refresh()
        end})
        local controls={export,import,pull}
        -- Extra rules: each starts at the game's own value, so it changes nothing until moved.
        U.text(parent,{text='Extra rules'})
        local paints={}
        for _,spec in ipairs(M.schema.extras) do
            local slider,paint=U.number(parent,{label=spec.label,min=spec.sliderMin or spec.min,max=spec.sliderMax or spec.max,
                step=spec.step,kind=spec.integer and 'int' or nil,input_min=spec.min,input_max=spec.max,default=spec.initial,
                value=spec.initial,on_commit=function(number) set(spec,number) end})
            controls[#controls+1]=slider
            paints[#paints+1]=function(own)
                paint(type(own[spec.key])=='number' and own[spec.key] or spec.initial)
            end
            if spec.key=='possessionLifetime' then
                local keep,paintKeep=U.checkbox(parent,{label='Keep abandoned props',editable=true,value=false,
                    on_change=function(value) set(spec,value and 'never' or spec.initial) end})
                controls[#controls+1]=keep
                paints[#paints+1]=function(own) paintKeep(own[spec.key]=='never') end
            end
        end
        U.navigate(controls,scroll)
        -- The screen can outlive a session, so the tab reads the role each time it opens.
        refresh=function()
            pull:SetVisibility(guest() and 0 or 1)
            local own=shownExtras()
            for _,paint in ipairs(paints) do paint(own) end
        end
        return refresh
    end)
    U.mod_options('Match Rules ++',function(rows)
        return {(U.checkbox(rows,{label='Keep match rules between launches',editable=true,value=settings.keepRules,
            on_change=function(value) settings.keepRules=value;M.persist() end}))}
    end)
    -- Custom Match and the host's in-game menu have a native Match Rules + button (AdvancedOptions),
    -- which opens this tab's screen. Only Creative's menu needs a row.
    local function open(origin) U.open_rules(origin,'Match Rules ++') end
    U.menu_entry('/Game/UserInterface/CreativeMode/WB_CreativeIngameMenu.WB_CreativeIngameMenu_C','Settings','Match Rules +',open,'LayoutEditor')
    -- The game shows its button to the host of a Tweakable match only; a guest of such a match
    -- reaches the rules from its own row. The flag lives on the server, so the host publishes it.
    U.menu_entry('/Game/UserInterface/WB_IngameMenu.WB_IngameMenu_C','Settings','Match Rules +',open,nil,
        function() return guest() and M.hostView~=nil and M.hostView.live end)
    R.key('mrpp.rules','F7',function() U.open_rules(nil,'Match Rules ++') end)
end
