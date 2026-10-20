-- MRPP schemas over the runtime store. Legacy files are only read, never moved.
local M={}
local reserved={CON=true,PRN=true,AUX=true,NUL=true}
function M.name(name)
    assert(type(name)=='string' and #name>=1 and #name<=64 and name:match('^[A-Za-z0-9][A-Za-z0-9_%-]*$'),'name: 1-64 letters, digits, dash or underscore')
    local upper=name:upper()
    assert(not reserved[upper] and not upper:match('^COM[1-9]$') and not upper:match('^LPT[1-9]$'),'reserved filename')
    return name
end
-- The legacy scalar bridge remains at its agreed cross-VM path for FAPP compatibility.
function M.bridge(savedDir)
    local path=savedDir:gsub('[/\\]+$','')..'/MatchRulesPlusPlus'
    assert(not path:find('[%z\r\n]'),'invalid bridge directory')
    -- Provisioned by the runtime at installation bootstrap, never during a match.
    return path..'/cauldron_target_offset.txt'
end
local function read(file)
    local f=io.open(file,'rb'); if not f then return end
    local bytes=f:read(262145) or ''; assert(f:close()); assert(#bytes<=262144,'legacy file too large'); return bytes
end
local function list(path,store)
    assert(not path:find('[%z\r\n]'),'invalid legacy directory')
    -- Optional manifest produced by WitchItRuntime/provision.py. No subprocess
    -- directory listing in Lua: absent legacy files need no migration work.
    local bytes=read(path..'/wir-legacy-files.txt') or ''
    local names={}; for file in bytes:gmatch('[^\r\n]+') do
        local name=file:match('^(.*)%.json$')
        if name and pcall(M.name,name) then names[#names+1]=name end
    end
    table.sort(names); assert(#names<=1024,'too many legacy presets'); return names
end
function M.init(api,savedDir,validatePreset,validateSettings,listLegacy)
    local store=api.shared('Core').storage.new(api).open()
    local J=api.json; local S={root=store.root}
    local function leaf(bucket,name)
        assert(bucket=='presets' or bucket=='imports','invalid bucket')
        return bucket..'-'..M.name(name)..'.json'
    end
    function S.read(bucket,name) return assert(store.read_json(leaf(bucket,name)),'missing preset') end
    function S.bytes(bucket,name) return store.read(leaf(bucket,name)) end
    function S.write(name,value) validatePreset(value,false); store.write_json(leaf('presets',name),value); return store.path(leaf('presets',name)) end
    local function writeUnique(name,value,firstSuffix)
        M.name(name); validatePreset(value,true)
        local candidate=name
        for i=firstSuffix,9999 do
            if not S.bytes('presets',candidate) then return candidate,S.write(candidate,value) end
            local suffix='-'..i;candidate=name:sub(1,64-#suffix)..suffix
        end
        error('too many presets with that name; choose another name')
    end
    function S.writeNew(name,value) return writeUnique(name,value,1) end
    function S.writeShared(offeredName,value)
        -- Host labels are display text; turn invalid filename characters into
        -- dashes, while preserving an already valid offered name exactly.
        local name=offeredName:gsub('[^A-Za-z0-9_%-]','-'):gsub('^[^A-Za-z0-9]+',''):sub(1,64)
        if not pcall(M.name,name) then name='shared-rules' end
        return writeUnique(name,value,2)
    end
    function S.importWrite(name,value) validatePreset(value,true); store.write_json(leaf('imports',name),value); return store.path(leaf('imports',name)) end
    function S.settingsRead() return store.read_json('settings.json') end
    function S.settingsWrite(value) validateSettings(value); api.save_settings(value); return store.path('settings.json') end
    local legacy=savedDir:gsub('[/\\]+$','')..'/MatchRulesPlusPlus'
    local migration=store.read_json('legacy-migration.json')
    local indexed=read(legacy..'/presets/wir-legacy-files.txt') or read(legacy..'/imports/wir-legacy-files.txt')
    if not migration or migration.listing==false and indexed then
        local imported={}
        local bytes=read(legacy..'/settings.json')
        if bytes then
            local value=validateSettings(J.decode(bytes))
            if not store.read('settings.json') then api.save_settings(value); imported[#imported+1]='settings.json' end
        end
        for _,bucket in ipairs({'presets','imports'}) do
            for _,name in ipairs((listLegacy or list)(legacy..'/'..bucket,store)) do
                local value=J.decode(assert(read(legacy..'/'..bucket..'/'..name..'.json')))
                validatePreset(value,bucket=='imports')
                local file=leaf(bucket,name)
                if not store.read(file) then store.write_json(file,value); imported[#imported+1]=bucket..'/'..name..'.json' end
            end
        end
        store.write_json('legacy-migration.json',{version=1,source=legacy,listing=indexed~=nil,files=J.array(imported)})
        api.log('legacy migration complete; originals preserved at '..legacy)
    end
    return S
end
return M
