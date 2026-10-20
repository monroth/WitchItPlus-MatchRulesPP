-- Permission and snapshots for the native next-match editor. Gameplay authority
-- stays in H.host; a live guest never gains permission from NextMatchOptions.
local M={}
function M.init(H,R,Rules)
    local api={}; local Scalar=H.module('native_scalar')
    function api.menuContext(widget)
        if H.lifetime and H.lifetime.transition then return end
        local pc
        if widget then
            if not H.valid(widget) then return end
            pc=H.call(widget,'GetOwningPlayer')
        else
            for _,candidate in ipairs(H.findAll('B_MenuPlayerController_C') or {}) do
                if H.valid(candidate) and H.call(candidate,'IsLocalPlayerController')==true then pc=candidate; break end
            end
        end
        if not H.valid(pc) or not H.class(pc,'B_MenuPlayerController_C')
            or H.call(pc,'IsLocalPlayerController')~=true or not H.authority(pc) then return end
        if widget and not H.sameWorld(widget,pc) then return end
        local gameplay=H.object('/Script/Engine.Default__GameplayStatics')
        local gm=gameplay:GetGameMode(pc)
        -- The ordinary menu has B_MenuGameMode, never a running match mode.
        if H.valid(gm) and (not H.class(gm,'B_MenuGameMode_C') or not H.sameWorld(pc,gm)) then return end
        local gi=gameplay:GetGameInstance(pc)
        if not H.valid(gi) then return end
        local options=gi.NextMatchOptions
        if not H.valid(options) or not H.sameWorld(options,pc) then return end
        return pc,gi,options
    end
    function api.capture(extras)
        local pc,_,options=api.menuContext()
        assert(pc,'native next-match editor unavailable')
        local rules=options:GetGameRules()
        assert(H.valid(rules),'native next-match rules unavailable')
        local source={GameModeClass=options.GameMode}
        for _,def in pairs(Rules.collections) do source[def.field]=rules[def.field] end
        local subs=H.parameters(pc)
        return R.capture(source,function(g) return subs[g.category][g.property] end,H.values,H.text,extras or {})
    end
    function api.allowFileFields(child)
        assert(H.valid(child),'native Save/Load child unavailable')
        if child.FileEditingAllowed==true then return end
        child.FileEditingAllowed=true
        child:SetUITexts()
    end
    function api.allowFiles(page)
        local child=page.WB_SaveLoadScreen
        assert(H.valid(child) and H.sameWorld(child,page),'native Save/Load child unavailable')
        api.allowFileFields(child)
        -- The initial read-only refresh omitted the native default entry. Add only
        -- that entry through its own native function; keep existing list objects,
        -- input text, selected item, FileToSave, navigation and native delegates.
        local initial=Scalar.text(H,child.InitialEntryName); local present=false
        child.SaveEntries:ForEach(function(key)
            if Scalar.text(H,key)==initial then present=true end
        end)
        if not present then
            -- A genuine UObject OUT uses an empty output table in UE4SS; no
            -- array/struct or delegate is marshalled from a Lua container here.
            local output={}; child:CreateNewSaveEntry(initial,output)
            child:CheckForTooManySavegames()
        end
        page.FileEditingAllowed=true
    end
    return api
end
return M
