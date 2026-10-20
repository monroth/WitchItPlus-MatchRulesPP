-- TIME0: explicit diagnostic observations only. No hooks, assets, setters or recurring scans.
local M={}
local fields={
    file='FileName_10_98BC71FF40A2DA9A28FA21B92157D6D9',
    name='InterfaceName_12_C1C05170469A93A0C7D243A1F45D7B13',
    size='MapSize_40_92FE6BF14A86B89C6A1CAFB408C75038',
    extra='NeedsExtraTime_43_B354AF0A49DCBA90CE3CC7A6C2FEF251',
    quick='UsedInQuickmatch_14_394D12A648FFAF00AC52CA8DD1704959',
    objective='UsedInObjectiveMode_16_14EC3F034A60C0E1B05A6499D0923C6F',
    impostor='UsedInImpostorMode_29_C6F869764DF92D5DEFE5F4AEE250FACB',
}
function M.dump(H,api)
    local X={text=H.text,get=H.unwrap,read=H.read,values=H.values,H=H,Lifetime=H.lifetime,
        live=H.valid,findAll=api.find_all,gameplay=function() return H.object('/Script/Engine.Default__GameplayStatics') end,
        reply=function(_,message) api.log(message) end}
    local function scalar(v)
        if v==nil then return '?' end
        if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
        local ok,s=pcall(X.text,v); return ok and s:gsub('[\r\n\t]',' ') or '?'
    end
    local function read(o,k) return X.get(X.read(o,k)) end
    local function emit(s) X.reply('TimeDump',s,true) end -- synchronous OutputDevice + UE4SS.log
    emit('TIME0 v1; read-only seconds; ? = unavailable; size 0=small, 1=big; offset belongs to MatchOptions, not maps')
    if X.Lifetime.transition then emit('World transition: retry after the menu/match settles'); return end
    local found=false
    for _,gi in ipairs(X.findAll('B_GameInstance_C')) do if X.live(gi) then
        found=true
        emit('IsCustomMatch='..scalar(read(gi,'IsCustomMatch')))
        -- Replicated initialized seek duration can expose stale client-side options.
        -- This getter is read-only, valid in menus, and installs no gameplay hooks.
        local ok,gs=pcall(function() return X.gameplay():GetGameState(gi) end)
        emit('CurrentGameState.SeekTime='..scalar(ok and X.H.valid(gs) and read(gs,'SeekTime') or nil))
        emit('CurrentGameState.Role='..scalar(ok and X.H.valid(gs) and read(gs,'Role') or nil)..
            ' CurrentOpenedMap='..scalar(read(read(gi,'CurrentOpenedMap'),fields.file)))
        for _,key in ipairs({'UsedMatchOptions','QuickMatchOptions','NextMatchOptions','CustomMatchOptions'}) do
            local o=read(gi,key)
            if X.H.valid(o) then
                local gm=read(o,'GameMode'); local mode='?'
                if gm~=nil then pcall(function() mode=gm:GetFName():ToString() end) end
                emit(key..' mode='..mode..' HideTime='..scalar(read(o,'HideTime'))..
                    ' SeekTime='..scalar(read(o,'SeekTime'))..' MapSizeTimeOffset='..scalar(read(o,'MapSizeTimeOffset'))..
                    ' IsPublic='..scalar(read(o,'IsPublic'))..' map='..scalar(read(read(o,'MapData'),fields.file)))
            else emit(key..' unavailable') end
        end
        local mm=read(gi,'MapManager'); if not X.H.valid(mm) then mm=nil end
        local used=read(gi,'UsedMatchOptions'); if not X.H.valid(used) then used=nil end
        local rows={}
        local function add(d,source)
            d=X.get(d); local file=scalar(read(d,fields.file))
            if file=='?' then return end
            local extra=read(d,fields.extra)
            local base,offset=read(used,'SeekTime'),read(used,'MapSizeTimeOffset')
            local predicted='?'
            if type(base)=='number' and (extra==false or (extra==true and type(offset)=='number')) then
                predicted=tostring(math.max(0,base+(extra and offset or 0)))
            end
            local line='map='..file..' name='..scalar(read(d,fields.name))..' size='..scalar(read(d,fields.size))..
                ' NeedsExtraTime='..scalar(extra)..' MapSizeTimeOffset='..scalar(offset)..
                ' quick='..scalar(read(d,fields.quick))..' fap='..scalar(read(d,fields.objective))..
                ' impostor='..scalar(read(d,fields.impostor))..' publicSeekUsingCurrentOptions='..predicted
            rows[line]=rows[line] or {}; rows[line][source]=true
        end
        for _,key in ipairs({'MapDataByFileName','MapDataByLevelName'}) do
            local a=read(mm,key)
            if a then
                local ok=pcall(function()
                    if type(a)=='table' and not a.ForEach then for _,v in pairs(a) do add(v,key) end
                    else a:ForEach(function(_,v) add(v,key) end) end
                end)
                if not ok then emit(key..' unreadable (other lists still inspected)') end
            end
        end
        for _,key in ipairs({'QuickmatchMapList','SmallMapList','BigMapList',
            'SmallBuiltInCustomMapList','BigBuiltInCustomMapList','BuiltInCustomMapList',
            'EmptyMapsForCreativeMode','CreativeTemplateMaps','ImpostorMaps'}) do
            local ok,values=pcall(X.values,read(mm,key))
            if ok then for _,d in ipairs(values) do add(d,key) end end
        end
        -- The currently selected entry may be absent from filtered lists.
        for _,key in ipairs({'UsedMatchOptions','QuickMatchOptions','NextMatchOptions','CustomMatchOptions'}) do
            local o=read(gi,key)
            local d=X.H.valid(o) and read(o,'MapData'); if d then add(d,key..'.MapData') end
        end
        local ordered={}; for line in pairs(rows) do ordered[#ordered+1]=line end; table.sort(ordered)
        emit('Map entries='..#ordered..'; predictions are not measured public server presets')
        for _,line in ipairs(ordered) do
            local sources={}; for key in pairs(rows[line]) do sources[#sources+1]=key end; table.sort(sources)
            emit(line..' sources='..table.concat(sources,','))
        end
        -- Existing menu sliders only; callable UFunction wrappers need not be Lua functions.
        for _,screen in ipairs(X.findAll('WB_Custommatch_C')) do if X.live(screen) then
            for _,key in ipairs({'Slider_HideTime','Slider_SearchTime'}) do
                local slider=read(screen,key)
                if X.H.valid(slider) then emit(key..' min='..scalar(read(slider,'MinimumValue'))..
                    ' max='..scalar(read(slider,'MaximumValue'))..' step='..scalar(read(slider,'StepSize'))) end
            end
        end end
    end end
    if not found then emit('No live GameInstance in registry; retry after menu initialization') end
end
return M
