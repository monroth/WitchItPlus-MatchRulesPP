local M={}
M.collections={
    match={field='MatchRules',type='MatchRuleType_2_7A33ED664F8C0FBEE1C782B8057AEA07',params='UIParameters_6_D7D219FA47CFCDF8FCA3DB9DBCF39E11'},
    skills={field='SkillRules',type='SkillType_2_5808B66B468AC4EC8E4F7096273ED505',params='SkillParameters_6_41DDEB6C424E37EF4C61239795AF12B0',setter='AddSkillRule'},
    mods={field='GameModifiers',type='ModifierType_2_FEC4E34148D09164EA058CBDDCBE4C7F',params='UIParameters_6_270A78AB4625673AD2C87194A200889D',setter='AddGameModifier'},
    powerups={field='PowerupRules',type='PowerupType_5_07F0F6FF44288141C9331F8C816DF5AF',params='PowerupParameters_6_855163784BFC03D7EC9FB8B8D2C10128',setter='AddPowerupRule'}
}
M.extraSpecs={
    {key='mapSizeTimeFactor',nextMatch=true,label='Big-map extra search time (s per size step)',min=-600,max=600,step=1,kind='float',default=0},
    {key='cauldronTargetOffset',label='Extra cauldrons to win',min=-10,max=10,step=1,kind='int',default=0},
    {key='pickupMin',label='Powerup spawn interval (s)',min=1,max=600,step=1,kind='int'},
    {key='pickupJitter',label='Powerup spawn variation (s)',min=0,max=600,step=1,kind='int'},
    {key='roundDelay',label='Time between rounds (s)',min=1,max=300,step=1,kind='int'},
    {key='potatoRecharge',label='Potato stamina recharge per second',min=0,max=1000,step=1,kind='float'},
    {key='cooldownMin',label='Minimum cooldown (s)',min=.02,max=60,step=.02,kind='float'},
    {key='possessionLifetime',label='Abandoned prop lifetime (s)',min=.5,max=300,step=.5,kind='float',default=5,allowNever=true},
    {key='propForce',label='Prop push strength',min=.05,max=10,step=.05,kind='float',default=1},
    {key='propAirForce',label='Prop push strength in air',min=.05,max=10,step=.05,kind='float',default=1},
    {key='propMaxSpeed',label='Prop speed limit',min=.05,max=10,step=.05,kind='float',default=1},
    {key='propJumpForce',label='Prop jump strength',min=.05,max=10,step=.05,kind='float',default=1},
    {key='propSpeed',label='Prop speed',min=.05,max=10,step=.05,kind='float',default=1},
    {key='propMass',label='Prop weight',min=.05,max=10,step=.05,kind='float',default=1},
    {key='hunterGravity',label='Hunter gravity',min=.05,max=10,step=.05,kind='float',default=1},
    {key='witchGravity',label='Witch gravity',min=.05,max=10,step=.05,kind='float',default=1},
    {key='hunterAirControl',label='Hunter air control',min=0,max=1,step=.05,kind='float',default=.1},
    {key='witchAirControl',label='Witch air control',min=0,max=1,step=.05,kind='float',default=.1}
}
local labels={B_ObjectiveGameMode_C='Fill a Pot',B_HideAndSeekGameMode_C='Hide and Seek',B_SeekGameMode_C='Hide and Seek',B_MobificationGameMode_C='Mobification',IsListed='Available',IsLIsted='Available',IsEnabled='Enabled',GlobalMatchParameters='General',HunterMatchParameters='Hunters',WitchMatchParameters='Witches',MoveOrDamage='Move or take damage',PowerBall='Power ball',FlyingEye='Flying eye',JumpScare='Jump scare',IsInMatch='In match',Scale='Size',Pitch='Sound pitch',VoicePitch='Voice pitch',AirControl='Air control',GravityScale='Gravity',HealAmmount='Healing',OverHealReductionMultiplier='Overheal decay',ManaRegenMultiplicator='Mana regeneration',ExtraSpeedMultiplier='Prop speed',LastProps='Recent props'}
function M.label(key)
    if labels[key]then return labels[key]end
    for _,s in ipairs(M.extraSpecs)do if s.key==key then return s.label end end
    local words=key:gsub('^B_',''):gsub('GameMode_C$',''):gsub('(%l)(%u)','%1 %2'):gsub('[_]+',' ')
    words=words:gsub('^%s*(.-)%s*$','%1'):lower()
    return words:sub(1,1):upper()..words:sub(2)
end
function M.finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
function M.extraValidate(x)
    assert(type(x)=='table','extras must be object')
    local known={}; for _,s in ipairs(M.extraSpecs) do known[s.key]=s end
    for k,v in pairs(x) do
        local s=assert(known[k],'unknown extra '..tostring(k))
        assert((s.allowNever and v=='never') or (M.finite(v) and v>=s.min and v<=s.max and (s.kind~='int' or v==math.floor(v))),'invalid extra '..k)
    end
    assert((x.pickupMin==nil)==(x.pickupJitter==nil),'spawn minimum and jitter must be enabled together')
    return x
end
function M.init(schema,J)
    local api={schema=schema,label=M.label}; local index={}
    for _,g in ipairs(schema) do
        index[g.category]=index[g.category] or {}; index[g.category][g.id]={group=g,rows={},nativeRows={}}
        for _,s in ipairs(g.rows) do
            local group=index[g.category][g.id]
            group.rows[s.name]=s
            local key=s.name:lower()
            assert(not group.nativeRows[key],'ambiguous native parameter schema '..s.name)
            group.nativeRows[key]=s
        end
    end
    local function checked(v,s,bounds)
        if s.kind=='bool' then assert(type(v)=='boolean','expected boolean '..s.name)
        else
            assert(M.finite(v),'invalid number '..s.name)
            assert(s.kind~='int' or v==math.floor(v),'expected integer '..s.name)
            if bounds then assert(v>=s.min-1e-6 and v<=s.max+1e-6,'outside vanilla range '..s.name) end
        end
        return v
    end
    function api.validate(p,loading)
        assert(type(p)=='table' and p.format=='MatchRulesPlusPlus' and p.version==1,'unsupported preset schema')
        assert(type(p.mode)=='string' and #p.mode<512,'missing game mode')
        assert(type(p.collections)=='table','missing collections')
        for cat in pairs(p.collections) do assert(M.collections[cat],'unknown collection') end
        for cat in pairs(M.collections) do
            local rules=assert(p.collections[cat],'missing '..cat); local ids={}
            assert(type(rules)=='table' and #rules<=32,'invalid collection')
            local count=0
            for k in pairs(rules) do
                assert(type(k)=='number' and k==math.floor(k) and k>=1 and k<=#rules,'invalid rule array key'); count=count+1
            end
            assert(count==#rules,'sparse rule array')
            for _,r in ipairs(rules) do
                local group=assert(index[cat][r.id],'unknown rule type'); assert(not ids[r.id],'duplicate rule type'); ids[r.id]=true
                assert(type(r.values)=='table','missing values')
                for name,v in pairs(r.values) do
                    assert(type(name)=='string','parameter name must be string')
                    checked(v,assert(group.rows[name],'unknown parameter '..name),loading)
                end
            end
        end
        M.extraValidate(p.extras or {})
        return p
    end
    function api.clean(p)
        api.validate(p,true)
        -- Only the validated wire schema is retained. Discard display/effective metadata
        -- and unknown root/entry fields before imports, materialization or transfer.
        local out={format='MatchRulesPlusPlus',version=1,mode=p.mode,collections={},extras=J.decode(J.encode(p.extras or {}))}
        for cat in pairs(M.collections) do
            out.collections[cat]=J.array()
            for _,r in ipairs(p.collections[cat]) do
                out.collections[cat][#out.collections[cat]+1]={id=r.id,values=J.decode(J.encode(r.values))}
            end
        end
        return out
    end
    function api.capture(gs,getObject,values,text,extras)
        local p={format='MatchRulesPlusPlus',version=1,mode=text(gs.GameModeClass),savedAt=os.date('!%Y-%m-%dT%H:%M:%SZ'),collections={},effective={},extras=extras or {},extrasKnown=extras~=nil}
        for cat,def in pairs(M.collections) do
            local arr=J.array(); p.collections[cat]=arr
            for _,r in ipairs(values(gs[def.field])) do
                local id=r[def.type]; local group=assert(index[cat][id],'unrecognized replicated rule type')
                local entry={id=id,values={}}
                for _,v in ipairs(values(r[def.params])) do
                    local name=text(v.Name)
                    -- Native FName identity is case-insensitive; JSON imports stay
                    -- strict. Canonicalize only this recognized snapshot projection.
                    local s=assert(group.nativeRows[name:lower()],'unrecognized replicated parameter '..name)
                    entry.values[s.name]=checked(v[s.kind=='bool' and 'BoolValue' or s.kind=='int' and 'IntValue' or 'FloatValue'],s,false)
                end
                arr[#arr+1]=entry
            end
        end
        -- Read current world-subsystem objects, including mode overrides and omitted defaults.
        -- Never use table DefaultFloatValue (it is UI metadata, not a CDO default).
        for _,g in ipairs(schema) do
            local obj=assert(getObject(g),'effective subsystem not ready: '..g.property)
            local e={}; p.effective[g.category..':'..g.id]=e
            for _,s in ipairs(g.rows) do e[s.name]=checked(obj[s.name],s,false) end
            -- Modifier initialization clamps these only on the server. Clients' local
            -- parameter objects can still contain requested IsEnabled=true, so project
            -- the known authoritative mode restrictions into this plain-data view.
            if g.category=='mods' then
                local objective=p.mode:match('%.B_ObjectiveGameMode_C$')
                local impostor=p.mode:match('%.B_ImpostorGameMode_C$')
                if impostor or (objective and g.id~=1) then e.IsEnabled=false end
            end
        end
        return api.validate(p,false)
    end
    -- Allocate records inside a fresh UE-owned TArray, then mutate reflected scalar
    -- members. This experimental build grows TArray on indexed access (LuaTArray.cpp
    -- prepare_to_handle); nil initializes a zeroed StructProperty, never a Lua struct.
    -- Only the scalar/FName/array structs in these four schemas use this path.
    local function current(guard) return not guard or guard() end
    local function native(guard,fn)
        assert(current(guard),'proposal owner retired')
        local result=table.pack(fn())
        assert(current(guard),'proposal owner retired')
        return table.unpack(result,1,result.n)
    end
    function api.materialize(p,outer,spawn,guard)
        api.validate(p,false)
        local obj=assert(native(guard,function() return spawn(outer) end),'cannot construct native rule buffer')
        local reset=native(guard,function() return obj.ResetAll end)
        native(guard,function() reset(obj) end)
        for cat,def in pairs(M.collections) do
            local array=native(guard,function() return obj[def.field] end)
            assert(array and native(guard,function() return array.ForEach end),'native TArray support required')
            for i,r in ipairs(p.collections[cat]) do
                native(guard,function() array[i]=nil end)
                local record=assert(native(guard,function() return array[i] end),'cannot allocate native rule record')
                native(guard,function() record[def.type]=r.id end)
                local params=native(guard,function() return record[def.params] end)
                assert(params and native(guard,function() return params.ForEach end),'native parameter TArray required')
                local names={}; for k in pairs(r.values) do names[#names+1]=k end; table.sort(names)
                for j,k in ipairs(names) do
                    native(guard,function() params[j]=nil end)
                    local param=assert(native(guard,function() return params[j] end),'cannot allocate native parameter record')
                    local name=native(guard,function() return FName(k) end)
                    native(guard,function() param.Name=name end)
                    native(guard,function() param.FloatValue=0 end)
                    native(guard,function() param.IntValue=0 end)
                    native(guard,function() param.BoolValue=false end)
                    local kind=index[cat][r.id].rows[k].kind
                    native(guard,function() param[kind=='bool' and 'BoolValue' or kind=='int' and 'IntValue' or 'FloatValue']=r.values[k] end)
                end
            end
        end
        return obj
    end
    function api.stage(p,nextOptions,spawn,mode,guard)
        api.validate(p,true); assert(p.mode==mode,'preset mode differs from next match; select its game mode first')
        local buffer=api.materialize(p,nextOptions,spawn,guard)
        local obj=assert(native(guard,function() return spawn(nextOptions) end),'cannot construct GameRules')
        local reset=native(guard,function() return obj.ResetAll end);native(guard,function() reset(obj) end)
        local match=native(guard,function() return buffer.MatchRules end)
        native(guard,function() obj.MatchRules=match end)
        for _,cat in ipairs({'skills','mods','powerups'}) do
            local array=native(guard,function() return buffer[M.collections[cat].field] end)
            local each=native(guard,function() return array.ForEach end)
            native(guard,function() each(array,function(_,param)
                local get=native(guard,function() return param.get end)
                local value=native(guard,function() return get(param) end)
                local setter=native(guard,function() return obj[M.collections[cat].setter] end)
                native(guard,function() setter(obj,value) end)
            end) end)
        end
        local active=false
        for _,rules in pairs(p.collections) do if #rules>0 then active=true end end
        local oldRules=native(guard,function() return nextOptions.GameRules end)
        local oldSlot=native(guard,function() return nextOptions.GameRulesToLoad end)
        local oldActive=native(guard,function() return nextOptions.IsUsingCustomRules end)
        local ok,err=pcall(function()
            native(guard,function() nextOptions.GameRules=obj end)
            native(guard,function() nextOptions.GameRulesToLoad='' end)
            native(guard,function() nextOptions.IsUsingCustomRules=active end)
        end)
        if not ok then
            -- Never write through an outgoing owner or overwrite a reentrant replacement.
            if current(guard) then pcall(function()
                if native(guard,function() return nextOptions.GameRules end)~=obj then return end
                local slot=native(guard,function() return nextOptions.GameRulesToLoad end)
                local flag=native(guard,function() return nextOptions.IsUsingCustomRules end)
                native(guard,function() nextOptions.GameRules=oldRules end)
                if slot=='' then native(guard,function() nextOptions.GameRulesToLoad=oldSlot end) end
                if flag==active then native(guard,function() nextOptions.IsUsingCustomRules=oldActive end) end
            end) end
            error(err,0)
        end
        return obj
    end
    return api
end
return M
