-- Instance-only physics overrides. Multipliers use each prop/pawn's native baseline.
-- A disabled knob (or multiplier 1) performs no initial write; no CDOs are modified.
local M={}
local PROP='/Game/Blueprints/Props/Bases/B_StaticMeshProp.B_StaticMeshProp_C:'
local PAWN='/Game/Blueprints/Player/Pawns/'
local FLY='/Game/Blueprints/Skills/Witch/Fly/B_FlySkill.B_FlySkill_C:'
local CANNON='/Game/Blueprints/Skills/Hunter/Cannonball/B_CannonballSkill.B_CannonballSkill_C:'
local fields={Force='propForce',AirForce='propAirForce',MaxSpeed='propMaxSpeed',JumpForce='propJumpForce',ExtraSpeedMultiplier='propSpeed'}
function M.init(H,getExtras)
    local Policy=H.module('features')
    local function enabled() return not H.feature or H.feature('physics') end
    local Work=H.core and H.core.work_budget
    local api={}; local records={}; local skillOwners={Hunter={},Witch={}}; local applying=false; local busy=false;local scanOwner;local queued=false; local rerun=false; local airDefaults={}
    local guardSerial=0
    local function held(guard,T) return T or (guard and H.held(guard) or H) end
    local function current(guard,T) return not guard or guard() and T.current() end
    local function checkpoint(guard,T) assert(current(guard,T),'proposal owner retired') end
    local function read(guard,T,o,key) if guard then return T.read(o,key) end;return o[key] end
    local function write(guard,T,o,key,value) if guard then return T.write(o,key,value) end;o[key]=value end
    local function call(guard,T,o,key,...) if guard then return T.call(o,key,...) end;return o[key](o,...) end
    local function invoke(guard,T,fn,...) checkpoint(guard,T);local v=table.pack(fn(...));checkpoint(guard,T);return table.unpack(v,1,v.n) end
    local function work() return enabled() and (Policy.physics(getExtras()) or next(records)~=nil) end
    local function retained(kind)
        for _,r in pairs(records) do if r.kind==kind then return true end end
        return false
    end
    local function massWork()
        local v=getExtras().propMass
        if v~=nil and v~=1 then return enabled() end
        for _,r in pairs(records) do if r.mass and r.mass.applied~=nil then return enabled() end end
        return false
    end
    local function propWork()
        if not enabled() then return false end
        for _,key in pairs(fields) do local v=getExtras()[key]; if v~=nil and v~=1 then return true end end
        for _,r in pairs(records) do if r.kind=='Prop' and next(r.fields) then return true end end
        return false
    end
    local function teamWork(team)
        if not enabled() then return false end
        local e=getExtras(); local key=team:lower()
        return (e[key..'Gravity']~=nil and e[key..'Gravity']~=1) or e[key..'AirControl']~=nil or retained(team)
    end
    local function propSpawnWork() return propWork() or massWork() end
    local function record(o,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        assert(H.valid(o),'stale physics object')
        local key=H.key(o); local r=records[key]
        if not r or not H.valid(r.object) then r={object=o,fields={}}; records[key]=r end
        return r
    end
    local function field(o,name,value,multiply,kind,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not H.valid(o) then return false end
        local existing=records[H.key(o)]
        local f=existing and existing.fields[name]
        if not f and (value==nil or (multiply and value==1)) then return false end
        local valueNow=read(guard,T,o,name)
        if type(valueNow)~='number' then return false end
        if not f and (value==nil or (multiply and value==1) or (not multiply and value==valueNow)) then return false end
        local r=existing or record(o,guard,T); r.kind=kind or r.kind
        if not f then f={base=valueNow}; r.fields[name]=f end
        -- Native initialization/other skills may replace a value we last wrote.
        if f.applied~=nil and valueNow~=f.applied then f.base=valueNow end
        local target=value==nil and f.base or (multiply and f.base*value or value)
        f.applied=target; f.active=value~=nil and (not multiply or value~=1)
        if valueNow~=target then write(guard,T,o,name,target); return true end
        return false
    end
    local function context(guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        local pc,gs,gm=H.world(); if not H.valid(pc) or not H.valid(gs) then return end
        if H.class(gs,'B_CreativeGameState_C') and read(guard,T,gs,'IsPlayTestMode')~=true then return pc,gs,false end
        return pc,gs,H.host()
    end
    local function owned(o,pc,host,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not H.valid(o) or not H.sameWorld(o,pc) or call(guard,T,o,'GetFullName'):find('Default__',1,true) then return false end
        if host then return H.authority(o) end
        local ok,v=pcall(function() return call(guard,T,o,'IsLocallyControlled') end);checkpoint(guard,T);return ok and v==true
    end
    local function all(cls,guard,T) local H=held(guard,T);return H.findAll(cls) or {} end
    local function mass(prop,e,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not H.valid(prop) then return end
        local r=records[H.key(prop)]; local factor=e.propMass
        if (not r or not r.mass) and (not factor or factor==1) then return end
        local mesh=read(guard,T,prop,'Mesh'); if not H.valid(mesh) or not H.sameWorld(mesh,prop) then return end
        r=r or record(prop,guard,T); r.kind='Prop'
        if not r.mass then
            local base=call(guard,T,mesh,'GetMass'); if type(base)~='number' or base~=base or base<=0 or base==math.huge then return end
            r.mass={mesh=mesh,base=base,override=read(guard,T,prop,'OverrideMass')}
        end
        local m=r.mass
        if not H.valid(m.mesh) or H.key(m.mesh)~=H.key(mesh) then r.mass=nil; return mass(prop,e,guard,T) end
        local target=factor and factor~=1 and m.base*factor or nil
        if target~=m.applied then
            if target then call(guard,T,mesh,'SetMassOverrideInKg',invoke(guard,T,FName,'None'),target,true)
            else
                -- Let native UpdateMass recompute material/scale/OverrideMass defaults.
                call(guard,T,prop,'UpdateMass')
            end
            m.applied=target
        end
    end
    local function patchPawn(p,team,e,pc,host,editing,fly,cannon,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        local key=team:lower()
        if owned(p,pc,host or (editing and H.authority(pc)),guard,T) and H.valid(read(guard,T,p,'CharacterMovement')) and H.sameWorld(read(guard,T,p,'CharacterMovement'),p) then
            local move=read(guard,T,p,'CharacterMovement'); local f,c=fly[H.key(p)],cannon[H.key(p)]
            -- Fly owns its vertical acceleration while flying. Cannonball owns
            -- stomp gravity; its cached pre-stomp gravity is adjusted.
            local mr=records[H.key(move)]; local normal=mr and mr.fields.GravityScale
            local cr=H.valid(c) and records[H.key(c)]
            -- A skill restoring our edited cache is still our own output.
            if normal and cr and cr.fields.GravityScale and read(guard,T,c,'IsStomping')~=true
                and read(guard,T,move,'GravityScale')==cr.fields.GravityScale.applied then normal.applied=read(guard,T,move,'GravityScale') end
            if not (H.valid(f) and read(guard,T,f,'IsSkillActive')==true) and not (H.valid(c) and read(guard,T,c,'IsStomping')==true) then
                field(move,'GravityScale',e[key..'Gravity'],true,team,guard,T)
            end
            field(move,'AirControl',e[key..'AirControl'],false,team,guard,T)
            if H.valid(c) then
                local mr=records[H.key(move)]; local f=mr and mr.fields.GravityScale
                if f then
                    local cr=record(c,guard,T); cr.kind=team; cr.fields.GravityScale=cr.fields.GravityScale or {base=f.base}
                    field(c,'GravityScale',e[key..'Gravity'] and f.base*e[key..'Gravity'] or nil,false,team,guard,T)
                end
            end
        end
    end
    local function patchProp(p,e,pc,host,predicted,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if H.valid(p) and H.sameWorld(p,pc) and not call(guard,T,p,'GetFullName'):find('Default__',1,true)
            and ((host and H.authority(p)) or predicted[H.key(p)] or records[H.key(p)]) then
            local pe=(host or predicted[H.key(p)]) and e or {}
            local changed=false
            for name,key in pairs(fields) do if field(p,name,pe[key],true,'Prop',guard,T) then changed=true end end
            if changed then call(guard,T,p,'UpdateScaledSpeed') end
            mass(p,pe,guard,T)
        end
    end
    -- Birth/rules/skill decisions patch just the delivered actor immediately. The
    -- queue is only for refreshing existing populations after a settings edit.
    local function decision(actor,kind)
        if applying or not work() or not H.valid(actor) then return end
        local pc,gs,host=context(); if not pc then return end
        local editing=H.class(gs,'B_CreativeGameState_C') and gs.IsPlayTestMode~=true
        local e=editing and {} or getExtras()
        local ok,err=pcall(function()
            applying=true
            if kind=='Prop' then patchProp(actor,e,pc,host,{})
            elseif kind=='PropPawnPhysics' then
                if owned(actor,pc,host) and H.valid(actor.ControllingProp) then
                    patchProp(actor.ControllingProp,e,pc,host,{[H.key(actor.ControllingProp)]=true})
                end
            else patchPawn(actor,kind,e,pc,host,editing,skillOwners.Witch,skillOwners.Hunter) end
        end)
        applying=false; if not ok then error(err) end
    end
    function api.prepare(e,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if not enabled() then return end
        for _,team in ipairs({'Hunter','Witch'}) do
            local key=team:lower()..'AirControl'
            if e[key]~=nil then
                if airDefaults[key]==nil then
                    local pc=H.world()
                    if H.valid(pc) then
                        for _,pawn in ipairs(all('B_'..team..'_C',guard,T)) do
                            if H.valid(pawn) and H.sameWorld(pawn,pc) and H.valid(read(guard,T,pawn,'CharacterMovement'))
                                and H.sameWorld(read(guard,T,pawn,'CharacterMovement'),pawn) then
                                local value=read(guard,T,read(guard,T,pawn,'CharacterMovement'),'AirControl')
                                if type(value)=='number' then airDefaults[key]=value; break end
                            end
                        end
                    end
                end
                if e[key]==airDefaults[key] then e[key]=nil end
            end
        end
    end
    local function advance()
        if not rerun then return end
        local pending=type(rerun)=='table' and rerun or {};rerun=false
        if not pending.guard or current(pending.guard,pending.T) then
            H.defer(function() if not pending.guard or current(pending.guard,pending.T) then api.scan(false,pending.guard,pending.T) end end)
        end
    end
    function api.scan(synchronous,guard,T)
        local H=held(guard,T);T=H;checkpoint(guard,T)
        if busy then rerun={guard=guard,T=T};return end
        if not work() then return end
        local pc,gs,host=context(guard,T)
        if not pc then records={}; return end
        local editing=H.class(gs,'B_CreativeGameState_C') and read(guard,T,gs,'IsPlayTestMode')~=true
        local e=editing and {} or getExtras()
        local configured=false
        for _,key in pairs(fields) do if e[key] and e[key]~=1 then configured=true end end
        for _,key in ipairs({'propMass','hunterGravity','witchGravity'}) do if e[key] and e[key]~=1 then configured=true end end
        if e.hunterAirControl~=nil or e.witchAirControl~=nil then configured=true end
        if not configured and not next(records) then return end
        busy=true;local own={};scanOwner=own
        local function release() if scanOwner==own then scanOwner=nil;busy=false;advance() end end
        local tasks={}
        local function each(items,fn)
            for _,item in ipairs(items) do tasks[#tasks+1]=function() checkpoint(guard,T);fn(item);checkpoint(guard,T);return true end end
        end
        local function build()
            local fly,cannon={},{}
            for _,spec in ipairs({{'Witch','B_FlySkill_C',fly},{'Hunter','B_CannonballSkill_C',cannon}}) do
                if teamWork(spec[1]) then each(all(spec[2],guard,T),function(skill)
                    if not H.valid(skill) or not H.sameWorld(skill,pc) then return end
                    local owner=call(guard,T,skill,'GetOwner')
                    if H.valid(owner) and H.sameWorld(skill,owner) then spec[3][H.key(owner)]=skill; skillOwners[spec[1]][H.key(owner)]=skill end
                end) end
            end
            for _,team in ipairs({'Hunter','Witch'}) do
                each(all('B_'..team..'_C',guard,T),function(p)
                    patchPawn(p,team,e,pc,host,editing,fly,cannon,guard,T)
                end)
            end
            local predicted={}
            if not host and not editing then
                for _,cls in ipairs({'B_PropPawnPhysics_C','B_CreativePropPawnPhysics_C'}) do
                    each(all(cls,guard,T),function(p) if owned(p,pc,false,guard,T) and H.valid(read(guard,T,p,'ControllingProp')) then predicted[H.key(read(guard,T,p,'ControllingProp'))]=true end end)
                end
            end
            each(all('B_StaticMeshProp_C',guard,T),function(p)
                patchProp(p,e,pc,host,predicted,guard,T)
            end)
            for addr,r in pairs(records) do
                tasks[#tasks+1]=function()
                    if not H.valid(r.object) or not H.sameWorld(r.object,pc) then records[addr]=nil
                    else
                        local active=r.mass and r.mass.applied~=nil
                        for _,f in pairs(r.fields) do if f.active then active=true end end
                        if not active then records[addr]=nil end
                    end
                    return true
                end
            end
            tasks[#tasks+1]=function()
                release()
                return true
            end
        end
        local ok,err=pcall(build)
        if not ok then release();error(err,0) end
        local epoch=H.lifetime and H.lifetime.epoch
        local index=0
        local function step()
            if scanOwner~=own then return true end
            if not current(guard,T) then tasks={};release();return true end
            if H.lifetime and (H.lifetime.transition or H.lifetime.epoch~=epoch) then release();return true end
            index=index+1
            if not tasks[index] then release();return true end
            local ok,err=pcall(tasks[index])
            if not ok then release();error(err,0) end
            return index==#tasks
        end
        if synchronous or not Work then while not step() do end
        else
            local key='mrpp-physics'
            if guard then guardSerial=guardSerial+1;key='mrpp-physics-guard:'..guardSerial end
            local accepted=Work.submit(key,'physics overrides',step)
            if not accepted and guard then release();error('physics work rejected') end
        end
    end
    function api.close()
        if Work then Work.cancel('mrpp-physics') end
        busy=false;scanOwner=nil;rerun=false;api.scan(true)
    end
    local function refresh()
        if busy then rerun=true; return end
        if queued or not work() then return end
        queued=true
        H.defer(H.guard('physics refresh',function() queued=false; api.scan() end))
    end
    for _,team in ipairs({'Hunter','Witch','PropPawnPhysics'}) do
        local prefix=PAWN..'B_'..team..'.B_'..team..'_C:'
        local gate=team=='PropPawnPhysics' and propSpawnWork or function() return teamWork(team) end
        for _,event in ipairs(team=='PropPawnPhysics' and {'SwitchProp','OnRep_ControllingProp'} or {'InitializeRules','ReceiveBeginPlay'}) do
            H.hook(prefix..event,function(self) if gate() then decision(H.unwrap(self),team); refresh() end end,gate)
        end
    end
    H.hook(PROP..'ReceiveBeginPlay',function(self) if propSpawnWork() then decision(H.unwrap(self),'Prop') end end,propSpawnWork)
    H.hook(PROP..'UpdateScaledSpeed',function(self) if propWork() then decision(H.unwrap(self),'Prop') end end,propWork)
    H.hook(PROP..'UpdateMass',function(self)
        if busy or applying or not massWork() then return end
        local p=H.unwrap(self); local r=H.valid(p) and records[H.key(p)]
        if r and r.mass and H.valid(r.object) and H.sameWorld(p,r.object) and H.valid(p.Mesh) then
            r.mass.base=p.Mesh:GetMass(); r.mass.applied=nil
        end
        decision(p,'Prop')
    end,massWork)
    -- No per-frame gravity stomp. Skill entry/exit/initialization owns its pawn.
    local function skillDecision(self,team)
        local skill=H.unwrap(self); if not H.valid(skill) then return end
        local owner=skill:GetOwner(); if not H.valid(owner) or not H.sameWorld(skill,owner) then return end
        skillOwners[team][H.key(owner)]=skill; decision(owner,team)
    end
    for _,event in ipairs({'ReleaseFlying','SetFlying','InitializeRules'}) do
        local gate=function() return teamWork('Witch') end
        H.hook(FLY..event,function(self) if gate() then skillDecision(self,'Witch') end end,gate)
    end
    for _,event in ipairs({'InitializeRules','OnSkillDownMulti','OnSkillUpMulti','HandleStomp'}) do
        local gate=function() return teamWork('Hunter') end
        H.hook(CANNON..event,function(self) if gate() then skillDecision(self,'Hunter') end end,gate)
    end
    function api.reset() if Work then Work.cancel('mrpp-physics') end; busy=false;scanOwner=nil;rerun=false;records={}; skillOwners={Hunter={},Witch={}}; applying=false; queued=false; airDefaults={} end
    return api
end
return M
