-- Rule documents: a game mode, its native rules, and extra rules per mod.
--   {format='MatchRulesPlusPlus', version=2, mode=<GameMode class path>,
--    native={match={{id=,values={}}}, skills=…, mods=…, powerups=…},
--    extras={MatchRulesPlusPlus={…}, <other package id>={…}}}
-- Documents from files, codes and other players are reduced to this shape once, by clean().
return function(R,schema)
    local D={}
    local FORMAT='MatchRulesPlusPlus'
    local OWN='MatchRulesPlusPlus'
    local index,ownSpecs={},{}
    for _,group in ipairs(schema.groups) do
        index[group.category]=index[group.category] or {}
        index[group.category][group.id]=group
        group.byName,group.byNativeName={},{}
        for _,row in ipairs(group.rows) do
            group.byName[row.name],group.byNativeName[row.name:lower()]=row,row
        end
    end
    for _,spec in ipairs(schema.extras) do ownSpecs[spec.key]=spec end
    D.index=index

    function D.clone(value)
        if type(value)~='table' then return value end
        local out={}
        for key,item in pairs(value) do out[key]=D.clone(item) end
        return out
    end
    local function values(array)
        local result={}
        array:ForEach(function(_,value) result[#result+1]=value:get() end)
        return result
    end
    D.values=values
    local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
    function D.checked(value,row)
        if row.kind=='bool' then
            assert(type(value)=='boolean','Expected a checkbox value: '..row.name)
        else
            assert(finite(value),'Expected a number: '..row.name)
            assert(row.kind~='int' or value==math.floor(value),'Expected a whole number: '..row.name)
        end
        return value
    end
    function D.cleanOwnExtras(source)
        assert(type(source)=='table','Missing extra rules')
        local out={}
        for key,value in pairs(source) do
            -- Saved settings and old codes can name a rule that no longer exists.
            local spec=ownSpecs[key]
            if spec then
                assert(key=='possessionLifetime' and value=='never' or finite(value) and value>=spec.min and value<=spec.max
                    and (not spec.integer or value%1==0),'Extra rule outside range: '..spec.label)
                out[key]=value
            end
        end
        assert((out.pickupMin==nil)==(out.pickupJitter==nil),'Enable both powerup interval controls together')
        return out
    end
    -- Another mod's section is kept as given: names with plain values.
    local function cleanOtherExtras(source)
        assert(type(source)=='table','Invalid extra rules')
        local out={}
        for key,value in pairs(source) do
            assert(type(key)=='string' and #key<=128,'Invalid extra rule name')
            assert(type(value)=='boolean' or finite(value) or type(value)=='string' and #value<=256,'Invalid extra rule value')
            out[key]=value
        end
        return out
    end
    function D.clean(p)
        assert(type(p)=='table' and p.format==FORMAT,'Unsupported preset version')
        -- Version 1 kept native rules in `collections` and only this mod's extras.
        if p.version==1 then p={format=FORMAT,version=2,mode=p.mode,native=p.collections,extras={[OWN]=p.extras}} end
        assert(p.version==2,'Unsupported preset version')
        assert(type(p.mode)=='string' and #p.mode>0 and #p.mode<512,'Missing game mode')
        assert(type(p.native)=='table' and type(p.extras)=='table','Incomplete preset')
        local out={format=FORMAT,version=2,mode=p.mode,native={},extras={}}
        for category in pairs(p.native) do assert(schema.collections[category],'Unknown rule collection') end
        for category in pairs(schema.collections) do
            local rows,seen=p.native[category],{}
            assert(type(rows)=='table' and #rows<=32,'Invalid rule collection')
            local count=0
            for key in pairs(rows) do
                count=count+1
                assert(type(key)=='number' and key%1==0 and key>=1 and key<=#rows,'Invalid rule list')
            end
            assert(count==#rows,'Incomplete rule list')
            out.native[category]={}
            for _,entry in ipairs(rows) do
                local group=index[category][entry.id]
                assert(group and not seen[entry.id],'Unknown or repeated rule group')
                assert(type(entry.values)=='table','Missing rule values')
                seen[entry.id]=true
                local row={id=entry.id,values={}}
                for name,value in pairs(entry.values) do
                    row.values[name]=D.checked(value,assert(group.byName[name],'Unknown rule property'))
                end
                out.native[category][#out.native[category]+1]=row
            end
            table.sort(out.native[category],function(a,b) return a.id<b.id end)
        end
        for id,section in pairs(p.extras) do
            assert(type(id)=='string' and #id<=64,'Invalid extra rules')
            out.extras[id]=id==OWN and D.cleanOwnExtras(section) or cleanOtherExtras(section)
        end
        out.extras[OWN]=out.extras[OWN] or {}
        return out
    end
    -- This mod's extra rules of a document.
    function D.own(doc) return doc.extras[OWN] end

    -- Portable codes: MRPP2:<base64 of the JSON document>:<crc32>.
    local function crc(bytes)
        local c=0xffffffff
        for i=1,#bytes do
            c=c~bytes:byte(i)
            for _=1,8 do c=(c>>1)~((c&1)==1 and 0xedb88320 or 0) end
        end
        return string.format('%08x',c~0xffffffff)
    end
    D.LIMIT=36864
    function D.encode(doc)
        local bytes=R.json.encode(D.clean(doc))
        assert(#bytes<=D.LIMIT,'Preset exceeds 36 KiB')
        return 'MRPP2:'..R.base64.encode(bytes)..':'..crc(bytes)
    end
    function D.decode(code)
        assert(type(code)=='string' and #code<=49168,'Rules code exceeds size limit')
        code=code:match('^%s*(.-)%s*$')
        local bytes,sum=code:match('^MRPP[12]:([^:]+):(%x%x%x%x%x%x%x%x)$')
        assert(bytes,'Unsupported or corrupt rules code')
        local ok,raw=pcall(R.base64.decode,bytes)
        assert(ok,'Corrupt rules code')
        bytes=raw
        assert(#bytes<=D.LIMIT and crc(bytes)==sum:lower(),'Corrupt code: checksum mismatch')
        -- Native values can sit outside the sliders: fields take typed numbers, and saved
        -- rules files hold them. Types and extra rules are still checked.
        return D.clean(R.json.decode(bytes))
    end

    -- Native rule records. read() is the one place that turns them into document rows.
    local function kindField(kind) return kind=='bool' and 'BoolValue' or kind=='int' and 'IntValue' or 'FloatValue' end
    function D.read(rules,category)
        local def=schema.collections[category]
        local rows={}
        for _,record in ipairs(values(rules[def.field])) do
            local group=index[category][record[def.type]]
            local entry={id=group.id,values={}}
            for _,param in ipairs(values(record[def.params])) do
                local row=group.byNativeName[param.Name:ToString():lower()]
                entry.values[row.name]=param[kindField(row.kind)]
            end
            rows[#rows+1]=entry
        end
        return rows
    end
    local function spawnRules(outer)
        return StaticFindObject('/Script/Engine.Default__GameplayStatics'):SpawnObject(
            StaticFindObject('/Game/Blueprints/Match/GameRules/B_GameRules.B_GameRules_C'),outer)
    end
    function D.nativeRules(outer)
        local rules=spawnRules(outer)
        rules:ResetAll()
        return rules
    end
    -- Build a native B_GameRules object holding the document's native rules.
    function D.materialize(doc,outer)
        local buffer=D.nativeRules(outer)
        for category,def in pairs(schema.collections) do
            local array=buffer[def.field]
            for i,row in ipairs(doc.native[category]) do
                array[i]=nil
                local record=array[i]
                record[def.type]=row.id
                local params,keys=record[def.params],{}
                for name in pairs(row.values) do keys[#keys+1]=name end
                table.sort(keys)
                for j,name in ipairs(keys) do
                    params[j]=nil
                    local param=params[j]
                    param.Name=FName(name)
                    param.FloatValue,param.IntValue,param.BoolValue=0,0,false
                    param[kindField(index[category][row.id].byName[name].kind)]=row.values[name]
                end
            end
        end
        -- Skills, modifiers and powerups are registered through their native setters.
        local result=D.nativeRules(outer)
        result.MatchRules=buffer.MatchRules
        for _,category in ipairs({'skills','mods','powerups'}) do
            local def=schema.collections[category]
            for _,record in ipairs(values(buffer[def.field])) do result[def.setter](result,record) end
        end
        return result
    end
    return D
end
