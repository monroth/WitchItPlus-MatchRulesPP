-- Match Rules ++: extra match rules, and rules as a code. Rules apply only after an
-- explicit selection; opening a page only reads them.
local dir=debug.getinfo(1,'S').source:match('^@(.+[\\/])')
return function(R,C,U)
    local schema=dofile(dir..'schema.lua')
    local D=dofile(dir..'document.lua')(R,schema)
    local M={R=R,C=C,U=U,schema=schema,doc=D}
    M.PKG='MatchRulesPlusPlus'
    M.CORE='/Game/Blueprints/Core/'
    M.RULEUI='/Game/UserInterface/Play/GameRules/'
    M.TABS=M.RULEUI..'WB_GameRulesTabs.WB_GameRulesTabs_C'
    M.PROP='/Game/Blueprints/Props/Bases/B_StaticMeshProp.B_StaticMeshProp_C'
    M.PAWN='/Game/Blueprints/Player/Pawns/'
    M.CREATIVE='/Game/Blueprints/Gamemodes/CreativeMode/'
    local settings=R.settings(M.PKG,{name='My-rules',keepRules=false})
    M.settings=settings
    if settings.selected then settings.selected=D.clean(settings.selected) end
    if settings.pending then settings.pending=D.clean(settings.pending) end
    function M.persist() R.save_settings(M.PKG) end
    -- Kept rules wait for the next match, like any other staged rules.
    if settings.selected or settings.pending then
        settings.pending=settings.keepRules and (settings.pending or settings.selected) or nil
        settings.selected=nil
        M.persist()
    end
    -- State shared by the modules below.
    M.hostView=nil       -- a guest's copy of the host's published rules
    M.filling=false      -- native rule pages are being painted by code, not edited

    -- Scope: Match Rules + never touches a vanilla session. Every hook on native rules or
    -- gameplay registers through M.hooks. Inside a modded session, effects apply only
    -- while a rule document is selected: M.authority on the host, M.ownerAllowed per pawn.
    M.hooks=C.scoped(function(s) return s.mode~='vanilla' end)
    function M.editable()
        local s=C.session()
        return s.role~='client' and s.mode~='vanilla'
    end
    function M.playing()
        local s=C.session()
        return not s.is_creative or s.gs.IsPlayTestMode==true
    end
    -- The options the rules screen edits. In a match: the next match's. In the main menu:
    -- the Custom Match screen's own options object, which hosting copies into the match
    -- (the same object Fill a Pot+ marks as Plus).
    local customMatch='/Game/UserInterface/Play/WB_Custommatch.WB_Custommatch_C'
    function M.nextOptions()
        local gi=C.session().gi
        if gi.IsCurrentlyInMatch then return gi.NextMatchOptions end
        local menu=R.find(customMatch)
        return menu and menu.NextMatchOptions or gi.CustomMatchOptions
    end
    local function liveOptions(s) return s.is_creative and s.gi.NextMatchOptions or s.gi.UsedMatchOptions end
    function M.authority()
        local s=C.session()
        return s.role=='host' and s.mode~='vanilla' and M.playing() and settings.selected~=nil
            and liveOptions(s).IsUsingCustomRules==true
    end
    function M.guestSelected()
        local s=C.session()
        return s.role=='client' and s.mode~='vanilla' and M.playing() and M.hostView~=nil and M.hostView.selected
    end
    function M.ownerAllowed(pawn)
        return M.authority() or M.guestSelected() and pawn:IsLocallyControlled()
    end
    -- This mod's extra rules in force here; empty when no selection applies.
    function M.extras()
        local s=C.session()
        if s.role=='offline' or s.mode=='vanilla' or not M.playing() then return {} end
        if s.role=='client' then return M.hostView and M.hostView.selected and M.hostView.extras or {} end
        return settings.selected and liveOptions(s).IsUsingCustomRules==true and D.own(settings.selected) or {}
    end

    function M.library(name) return StaticFindObject('/Script/Engine.Default__'..name) end
    -- Write a push-model replicated property so clients receive it now.
    function M.replicate(object,name,rep,value)
        object:FlushNetDormancy()
        object[name]=value
        M.library('NetPushModelHelpers'):MarkPropertyDirtyFromRepIndex(object,rep,FName(name))
        object:ForceNetUpdate()
    end
    function M.text(value) return type(value)=='string' and value or value:ToString() end
    function M.pathOf(value) return value:GetFullName():match('(%S+)$') end
    local names={B_ObjectiveGameMode_C='Fill a Pot',B_HideAndSeekGameMode_C='Hide and Seek',B_SeekGameMode_C='Hide and Seek',
        B_MobificationGameMode_C='Mobification',IsListed='Available',IsLIsted='Available',IsEnabled='Enabled',
        GlobalMatchParameters='General',HunterMatchParameters='Hunters',WitchMatchParameters='Witches',
        HealAmmount='Healing',ManaRegenMultiplicator='Mana regeneration',MoveOrDamage='Move or take damage',
        PowerBall='Power ball',FlyingEye='Flying eye',JumpScare='Jump scare',IsInMatch='In match',Scale='Size',
        Pitch='Sound pitch',VoicePitch='Voice pitch',AirControl='Air control',GravityScale='Gravity',
        OverHealReductionMultiplier='Overheal decay',ExtraSpeedMultiplier='Prop speed',LastProps='Recent props'}
    function M.label(name)
        local words=name:gsub('^B_',''):gsub('GameMode_C$',''):gsub('(%l)(%u)','%1 %2'):gsub('_',' '):lower()
        return names[name] or words:sub(1,1):upper()..words:sub(2)
    end
    -- Error text for players: the assertion message without its source position.
    function M.problem(why)
        local message=tostring(why):gsub('^.-:%d+:%s*','')
        if message:find('attempt to',1,true) then return 'The preset contains invalid rules.' end
        return message
    end
    for _,name in ipairs({'effects','pages','sharing','tab'}) do dofile(dir..name..'.lua')(M) end
    return {clean=D.clean,encode=D.encode,decode=D.decode,capture=M.capture,stage=M.stage,schema=schema.groups}
end
