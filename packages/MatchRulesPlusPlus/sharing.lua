-- Rules between players: guests see the rules in force, extra rules included.
return function(M)
    local R,C,D=M.R,M.C,M.doc

    function M.publishView()
        local s=C.session()
        if s.role~='host' or s.mode=='vanilla' then return end
        local own=D.clone(M.extras())
        C.net.publish('mrpp.rules',{selected=M.authority(),document=M.capture(),extras=own})
    end
    C.net.watch('mrpp.rules',function(value)
        if C.session().role~='client' then return end
        local ok,result=pcall(function()
            assert(type(value)=='table' and type(value.selected)=='boolean','Invalid host rules')
            local doc=D.clean(value.document)
            doc.effective={}
            for _,group in ipairs(M.schema.groups) do
                local key=group.category..':'..group.id
                local source=assert(value.document.effective[key],'Missing current host rules')
                local effective={}
                for _,row in ipairs(group.rows) do effective[row.name]=D.checked(source[row.name],row) end
                doc.effective[key]=effective
            end
            return {document=doc,extras=D.cleanOwnExtras(value.extras),selected=value.selected}
        end)
        if not ok then R.log(M.PKG,'%s',tostring(result));return end
        local old=M.hostView and R.json.encode(M.hostView.extras)
        M.hostView=result
        if old~=R.json.encode(M.hostView.extras) then M.refreshEffects() end
    end)
    R.on('world_end',function() M.hostView=nil end)

    M.hooks.on('match_start',function()
        if C.session().role~='host' then return end
        M.promote()
        if M.settings.selected then M.refreshEffects() end
        M.publishView()
    end)
    M.hooks.on('round_start',M.publishView)
    M.hooks.session(function(s)
        if s.role=='host' and R.valid(s.gi) and R.valid(s.gs) and s.gs:IsA(StaticFindObject(M.CORE..'B_GameState.B_GameState_C')) then
            M.publishView()
        end
    end)
end
