-- Gameplay effects of the extra rules: physics and movement patches,
-- powerup pacing, round delay, cooldown floor, cauldron target, spring pads and abandoned props.
-- Every patched field keeps its native base so a later change or removal restores it.
return function(M)
    local R,C=M.R,M.C
    local hooks=M.hooks
    local CORE,PROP,PAWN=M.CORE,M.PROP,M.PAWN
    local POTATO='/Game/Blueprints/Skills/Hunter/Potato/B_PotatoSkill.B_PotatoSkill_C'
    local FLY='/Game/Blueprints/Skills/Witch/Fly/B_FlySkill.B_FlySkill_C'
    local CANNON='/Game/Blueprints/Skills/Hunter/Cannonball/B_CannonballSkill.B_CannonballSkill_C'
    local PAD='/Game/Blueprints/Skills/B_SpringPad.B_SpringPad_C'
    local originals,abandoned={},{}
    local restoring=false
    local function record(o)
        local key=o:GetAddress()
        local row=originals[key]
        if not row then row={object=o,fields={}};originals[key]=row end
        return row
    end
    -- Set o[name] to value (or base*value when multiply), remembering the native base.
    -- value nil (or a factor of 1) returns the field to its base and forgets it.
    local function field(o,name,value,multiply)
        local row=originals[o:GetAddress()]
        local old=row and row.fields[name]
        if not old and (value==nil or multiply and value==1) then return end
        local current=o[name]
        if not old then old={base=current};record(o).fields[name]=old end
        if old.last~=nil and current~=old.last then old.base=current end
        local target=value==nil and old.base or multiply and old.base*value or value
        if current~=target then o[name]=target end
        old.last=target
        if value==nil or multiply and value==1 then record(o).fields[name]=nil end
    end
    local propFields={Force='propForce',AirForce='propAirForce',MaxSpeed='propMaxSpeed',JumpForce='propJumpForce',ExtraSpeedMultiplier='propSpeed'}
    local function patchProp(prop,owner)
        if restoring or not M.authority() and not owner then return end
        if owner then record(prop).pawn=owner end
        local e=M.extras()
        for name,key in pairs(propFields) do field(prop,name,e[key],true) end
        local row=originals[prop:GetAddress()]
        local factor=e.propMass
        if factor and factor~=1 then
            row=row or record(prop)
            row.mass=row.mass or prop.Mesh:GetMass()
            prop.Mesh:SetMassOverrideInKg(FName('None'),row.mass*factor,true)
        elseif row and row.mass then
            row.mass=nil
            prop:UpdateMass()
        end
    end
    local function patchPawn(pawn,team)
        if restoring or not M.ownerAllowed(pawn) then return end
        local e,row=M.extras(),originals[pawn:GetAddress()]
        local fly=row and R.valid(row.fly) and row.fly
        local cannon=row and R.valid(row.cannon) and row.cannon
        local movement=pawn.CharacterMovement
        if not (fly and fly.IsSkillActive) and not (cannon and cannon.IsStomping) then
            field(movement,'GravityScale',e[team..'Gravity'],true)
        end
        field(movement,'AirControl',e[team..'AirControl'],false)
        if originals[movement:GetAddress()] then record(pawn).movementKey=movement:GetAddress() end
        if cannon then
            local movementRow=originals[movement:GetAddress()]
            local gravity=movementRow and movementRow.fields.GravityScale
            if gravity then field(cannon,'GravityScale',gravity.base*(M.extras().hunterGravity or 1),false) end
        end
    end
    local function patchPotato(skill)
        if restoring then return end
        local owner=skill:GetOwner()
        if R.valid(owner) and M.ownerAllowed(owner) then field(skill,'StaminaRecharge',M.extras().potatoRecharge,false) end
    end
    -- A pad fires on every machine, so each one scales its own copy.
    local function patchPad(pad)
        if restoring then return end
        local factor=M.extras().padImpulse
        field(pad,'ImpulseCharacter',factor,true)
        field(pad,'ImpulsePhysicalObject',factor,true)
    end
    hooks.post(PAD..':ReceiveBeginPlay',patchPad)
    -- The bounce area under Witch Forest is no pad: it computes each launch toward a point.
    hooks.post('/Game/Features/Experimental/BounceToPointVolume/BounceToPoint.BounceToPoint_C:CalculateVelocity',function(_,_,_,_,velocity)
        local factor=M.extras().padImpulse
        if not factor then return end
        local value=velocity:get()
        velocity:set({X=value.X*factor,Y=value.Y*factor,Z=value.Z*factor})
    end)
    for _,team in ipairs({'Hunter','Witch'}) do
        for _,event in ipairs({'InitializeRules','ReceiveBeginPlay'}) do
            hooks.post(PAWN..'B_'..team..'.B_'..team..'_C:'..event,function(pawn) patchPawn(pawn,team:lower()) end)
        end
    end
    for _,event in ipairs({'InitializeRules','ReceiveBeginPlay'}) do hooks.post(POTATO..':'..event,patchPotato) end
    for _,event in ipairs({'ReceiveBeginPlay','UpdateScaledSpeed','UpdateMass'}) do
        hooks.post(PROP..':'..event,function(prop)
            local row=originals[prop:GetAddress()]
            local pawn=row and row.pawn
            local owner=R.valid(pawn) and pawn:IsLocallyControlled() and pawn.ControllingProp==prop and pawn or nil
            if not M.authority() and not owner then return end
            if event=='UpdateMass' and row then row.mass=nil end
            patchProp(prop,owner)
        end)
    end
    for _,event in ipairs({'SwitchProp','OnRep_ControllingProp'}) do
        hooks.post(PAWN..'B_PropPawnPhysics.B_PropPawnPhysics_C:'..event,function(pawn)
            if restoring or not M.ownerAllowed(pawn) then return end
            local prop=pawn.ControllingProp
            if R.valid(prop) then patchProp(prop,pawn) end
        end)
    end
    local function skillEvent(skill,team,name)
        if restoring then return end
        local owner=skill:GetOwner()
        if not R.valid(owner) or not M.ownerAllowed(owner) then return end
        record(owner)[name]=skill
        patchPawn(owner,team)
    end
    for _,event in ipairs({'ReleaseFlying','SetFlying','InitializeRules'}) do
        hooks.post(FLY..':'..event,function(skill) skillEvent(skill,'witch','fly') end)
    end
    for _,event in ipairs({'InitializeRules','OnSkillDownMulti','OnSkillUpMulti','HandleStomp'}) do
        hooks.post(CANNON..':'..event,function(skill) skillEvent(skill,'hunter','cannon') end)
    end

    -- The pending selection becomes the match's as soon as the match starts.
    local function begin() if C.session().role=='host' then M.promote() end end
    hooks.post(CORE..'B_SeekGameMode.B_SeekGameMode_C:InitializeSeekTime',begin)
    hooks.post(CORE..'B_GameMode.B_GameMode_C:ReceiveBeginPlay',function(gm)
        if gm==C.session().gm then begin() end
    end)
    hooks.post(CORE..'B_GameMode.B_GameMode_C:GetPickupSpawnDelay',function(gm,out)
        local e=M.extras()
        if M.authority() and e.pickupMin and
            (e.pickupMin~=gm.PickupMinSecondsUntilSpawn or e.pickupJitter~=gm.PickupFlexibleSecondsUntilSpawn) then
            out:set(e.pickupMin+(e.pickupJitter>0 and math.random(0,e.pickupJitter-1) or 0))
        end
    end)
    hooks.post(CORE..'B_SeekGameMode.B_SeekGameMode_C:GetRoundEndTimerUntilRestart',function(gm,out)
        local delay=M.extras().roundDelay
        if M.authority() and delay and delay~=22 then out:set(math.max(delay,gm.MapVoteTimeNeeded and 29 or 1)) end
    end)
    hooks.post(M.schema.subsystems.skills..':GetSkillCooldown',function(_,_,_,out)
        local minimum=M.extras().cooldownMin
        if minimum and out:get()<minimum then out:set(minimum) end
    end)
    -- Abandoned props: the native dissolve timer, re-armed for the selected lifetime.
    local timerName='DissolvePropServer'
    local function rearm(prop,row,lifetime)
        local lib=M.library('KismetSystemLibrary')
        local now=M.library('GameplayStatics'):GetTimeSeconds(prop)
        if row.lifetime=='never' then
            row.elapsed=row.elapsed+(row.paused and 0 or now-row.sampled)
        else
            row.elapsed=row.elapsed+lib:K2_GetTimerElapsedTime(prop,timerName)
            row.paused=lib:K2_IsTimerPaused(prop,timerName)
        end
        row.sampled,row.lifetime=now,lifetime
        lib:K2_ClearTimer(prop,timerName)
        if lifetime~='never' then
            lib:K2_SetTimer(prop,timerName,math.max(.001,lifetime-row.elapsed),false,false,0,0)
            if row.paused then lib:K2_PauseTimer(prop,timerName) end
        end
    end
    hooks.post(PROP..':StartDestroyCountdown',function(prop)
        local lifetime=M.extras().possessionLifetime or 5
        if not M.authority() or lifetime==5 or prop.IsControlledByWitch then return end
        local row={object=prop,elapsed=0,lifetime=5}
        abandoned[prop:GetAddress()]=row
        rearm(prop,row,lifetime)
    end)
    for _,event in ipairs({'StopDestroyCountdown','DissolvePropServer'}) do
        hooks.post(PROP..':'..event,function(prop) abandoned[prop:GetAddress()]=nil end)
    end
    function M.cleanupAbandoned()
        local old=abandoned
        abandoned={}
        for _,row in pairs(old) do
            if R.valid(row.object) and not row.object.IsControlledByWitch then row.object:DissolvePropServer() end
        end
    end
    hooks.on('match_end',function() if C.session().role=='host' then M.cleanupAbandoned() end end)
    -- Forgetting an ending actor is bookkeeping, needed in every session.
    R.pre('/Script/Engine.Actor:ReceiveEndPlay',function(actor)
        if not R.valid(actor) then return end
        local key=actor:GetAddress()
        local row=originals[key]
        if row and row.movementKey then originals[row.movementKey]=nil end
        originals[key],abandoned[key]=nil,nil
    end)

    -- Re-apply every effect after a change of selection: restore all bases, then let
    -- the native rule initializers and the patches above run once again.
    local actors={
        {path=PAWN..'B_Hunter.B_Hunter_C',method='InitializeRules'},
        {path=PAWN..'B_Witch.B_Witch_C',method='InitializeRules'},
        {path=PAWN..'B_PropPawnPhysics.B_PropPawnPhysics_C',method='RulesUpdated'},
        {path=M.CREATIVE..'B_CreativePropPawnPhysics.B_CreativePropPawnPhysics_C',method='RulesUpdated'}
    }
    for team,skills in pairs({Hunter={'Potato','Melee','Chicken','Hook','Cannonball','Garlic','Trap','PowerBall','Train'},
        Witch={'Decoy','Mushroom','Fly','JumpScare','Possess','FlyingEye'}}) do
        for _,name in ipairs(skills) do
            local asset='B_'..name..'Skill'
            local folder=name=='FlyingEye' and 'Eye' or name
            actors[#actors+1]={path='/Game/Blueprints/Skills/'..team..'/'..folder..'/'..asset..'.'..asset..'_C',method='InitializeRules'}
        end
    end
    function M.refreshEffects()
        restoring=true
        for key,row in pairs(originals) do
            local o=row.object
            if R.valid(o) then
                for name,old in pairs(row.fields) do
                    if o[name]==old.last then o[name]=old.base end
                end
                if row.mass then o:UpdateMass() end
            end
            originals[key]=nil
        end
        restoring=false
        local role=C.session().role
        if role=='host' or role=='client' then
            for _,pad in ipairs(R.find_all(PAD)) do patchPad(pad) end
            for _,path in ipairs({FLY,CANNON}) do
                for _,skill in ipairs(R.find_all(path)) do
                    skillEvent(skill,path==FLY and 'witch' or 'hunter',path==FLY and 'fly' or 'cannon')
                end
            end
            for _,spec in ipairs(actors) do
                for _,actor in ipairs(R.find_all(spec.path)) do
                    local owner=spec.method=='InitializeRules' and spec.path:find('/Skills/',1,true) and actor:GetOwner() or actor
                    if role=='host' or R.valid(owner) and owner:IsLocallyControlled() then
                        actor[spec.method](actor)
                        if spec.method=='RulesUpdated' and M.ownerAllowed(actor) then
                            local prop=actor.ControllingProp
                            if R.valid(prop) then patchProp(prop,actor) end
                        end
                    end
                end
            end
            for _,prop in ipairs(R.find_all(PROP)) do patchProp(prop) end
        end
        local lifetime=M.extras().possessionLifetime or 5
        for key,row in pairs(abandoned) do
            local prop=row.object
            if R.valid(prop) and not prop.IsControlledByWitch then
                rearm(prop,row,lifetime)
                if lifetime==5 then abandoned[key]=nil end
            else abandoned[key]=nil end
        end
        if M.authority() and lifetime~=5 then
            local lib=M.library('KismetSystemLibrary')
            for _,prop in ipairs(R.find_all(PROP)) do
                if not prop.IsControlledByWitch and not abandoned[prop:GetAddress()] and
                    (lib:K2_IsTimerActive(prop,timerName) or lib:K2_IsTimerPaused(prop,timerName)) then
                    local row={object=prop,elapsed=0,lifetime=5}
                    abandoned[prop:GetAddress()]=row
                    rearm(prop,row,lifetime)
                end
            end
        end
    end
    -- Entering a vanilla session returns every patched object to its native values.
    C.on_session(function(s)
        if s.mode=='vanilla' and (next(originals) or next(abandoned)) then M.refreshEffects() end
    end)
    -- Retired actors are discarded by their native lifetime. Never read them on travel.
    R.on('world_end',function()
        originals,abandoned={},{}
    end)
end
