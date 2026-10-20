-- Pure Lua feature/default policy, safe to evaluate before any UObject access.
local M={}
M.names={'sync','physics','possession','cauldronOffset','extras','creative','ui'}
function M.validate(f)
    assert(type(f)=='table','features must be an object')
    local known={}; for _,name in ipairs(M.names) do known[name]=true end
    for key,value in pairs(f) do assert(known[key] and type(value)=='boolean','invalid feature switch '..tostring(key)) end
    return f
end
function M.enabled(startup,saved,name)
    return startup[name]~=false and (not saved or saved[name]~=false)
end
-- Only invariant, researched vanilla defaults are removed globally. Actor-specific
-- defaults (mass/air control/recharge/pacing) are compared with the live baseline.
local defaults={mapSizeTimeFactor=0,cauldronTargetOffset=0,possessionLifetime=5,cooldownMin=.02,roundDelay=22,
    propForce=1,propAirForce=1,propMaxSpeed=1,propJumpForce=1,propSpeed=1,propMass=1,hunterGravity=1,witchGravity=1}
function M.active(e)
    local out={}; for key,value in pairs(e or {}) do if defaults[key]~=value then out[key]=value end end
    return out
end
function M.physics(e)
    for _,key in ipairs({'propForce','propAirForce','propMaxSpeed','propJumpForce','propSpeed','propMass','hunterGravity','witchGravity'}) do
        if e[key]~=nil and e[key]~=1 then return true end
    end
    return e.hunterAirControl~=nil or e.witchAirControl~=nil
end
return M
