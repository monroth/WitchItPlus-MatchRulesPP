-- Explicit opt-in probe on common Core2 readiness. No automatic hello/expiry loop.
local M={}
local PREFIX='MRPP2:'
function M.init(H,enabled,clock)
 clock=clock or H.now or os.time
 local owner=H.api;local Sync=assert(owner.shared('Core').package_sync,'Core 2 readiness required')
 local D=assert(owner.map_document,'central world/document service required')
 local Work=assert(H.core.work_budget,'finite Core work required')
 local L=H.lifetime or H.core.lifetime
 local api={};local roster,pending;local seen,jobs,pongs={},{},{};local serial=0;local lastSend=-math.huge
 local function live() return owner.is_live() and not L.transition and enabled() end
 local function current(r) return live() and D.current(r.token) and Sync.current(r.view) end
 local function close(r)
  if r.closed then return end;r.closed=true;if jobs[r.key]==r then jobs[r.key]=nil end;r.token=nil;r.view=nil;r.work=nil
 end
 local function ownsWork(r) return r.work~=nil and Work.keys[r.key]==r.work end
 local function cancelOwned(r) if owner.is_live() and ownsWork(r) then pcall(Work.cancel,r.key) end end
 local function clear()
  pending=nil;seen={};pongs={};local old=jobs;jobs={}
  for _,r in pairs(old) do cancelOwned(r);close(r) end
 end
 local function send(view,token,verb,id)
  if not live() or not D.current(token) or not Sync.current(view) then return false end
  serial=serial+1;local r={key='mrpp2-probe:'..serial,view=view,token=token,id=id};jobs[r.key]=r
  local step=Work.native(function()
   if r.closed or not current(r) then close(r);return end
   local v=r.view
   local text=PREFIX..verb..':'..v.local_session..':'..v.remote_session..':'..v.local_revision..':'..v.remote_revision..':'..id
   local ok,result=pcall(Sync.send,owner,v.pc_key,text,v)
   close(r)
   if not ok then if pending and pending.id==id then pending=nil end;error(result,0) end
   if not result and pending and pending.id==id then pending=nil end
  end)
  local ok,result=pcall(Work.submit,r.key,'Rules probe RPC',step)
  local record=Work.keys[r.key];if record and record.step==step then r.work=record end
  if not ok then cancelOwned(r);close(r);error(result,0) end
  if not result then close(r);return false end
  return true,r
 end
 local function sameScope(a,b)
  return a.local_session==b.local_session and a.remote_session==b.remote_session
   and a.local_revision==b.local_revision and a.remote_revision==b.remote_revision
 end
 local function respond(view,token,id)
  local outbound=Sync.peer(view.pc_key)
  if outbound and sameScope(outbound,view) then return send(outbound,token,'PONG',id) end
  -- One latest accepted response per admitted peer, released by session/doc revoke.
  pongs[view.pc_key]={view=view,token=token,id=id}
  return true
 end
 local function drainPongs()
  local old=pongs;pongs={}
  for key,r in pairs(old) do
   if current(r) then
    local outbound=Sync.peer(key)
    if outbound and sameScope(outbound,r.view) then send(outbound,r.token,'PONG',r.id) else pongs[key]=r end
   end
  end
 end
 function api.ping()
  if not enabled() then H.log('probe disabled; enable transport probe in Rules++ first');return end
  if not live() or not roster or not roster.ready or roster.host then H.log('F9 requires a ready connected client');return end
  local view=Sync.peer(roster.pc_key);local token=D.capture()
  if not view or view.host or not token or not D.current(token) then H.log('F9 requires a ready current host world');return end
  local now=clock();if now-lastSend<2 then return end
  serial=serial+1;local id=serial;assert(id<=2147483647,'probe sequence exhausted')
  local r={id=id,view=view,token=token};pending=r
  local ok,result,job=pcall(send,view,token,'PING',id)
  if not ok then if pending==r then pending=nil end;error(result,0) end
  if not result then if pending==r then pending=nil end;return end
  r.job=job;lastSend=now;H.log('probe ping '..id)
 end
 local function parse(value,verb)
  local text=H.text(H.unwrap(value));if #text>160 then return end
  local ss,ts,sr,tr,id=text:match('^'..PREFIX..verb..':([%x%-]+):([%x%-]+):(%d+):(%d+):(%d+)$')
  id=tonumber(id);if not id or id%1~=0 or id<1 or id>2147483647 then return end
  return ss,ts,tonumber(sr),tonumber(tr),id
 end
 function api.upstream(self,value)
  if not live() then return end
  local ss,ts,sr,tr,id=parse(value,'PING');if not id then return end
  local view=Sync.accept(H.unwrap(self),ss,ts,sr,tr);if not view or not view.host then return end
  local token=D.capture();if not token or not D.current(token) then return end
  local prior=seen[view.pc_key]
  if prior and Sync.current(prior.view) and D.current(prior.token) and id<=prior.id then return end
  seen[view.pc_key]={id=id,view=view,token=token}
  respond(view,token,id)
 end
 function api.downstream(self,value)
  if not live() then return end
  local ss,ts,sr,tr,id=parse(value,'PONG');if not id then return end
  local view=Sync.accept(H.unwrap(self),ss,ts,sr,tr);local r=pending
  if view and not view.host and r and r.id==id and current(r) then pending=nil;H.log('probe pong '..id..' received') end
 end
 function api.outcome()
  for _,r in pairs(jobs) do
   if not current(r) or not ownsWork(r) then
    local state=not current(r) and 'retired' or 'cancelled'
    cancelOwned(r);close(r);if pending and pending.job==r then pending=nil end
    return {state=state}
   end
  end
 end
 function api.maintenance() end
 function api.reset() roster=nil;clear() end
 L.onReset(api.reset);owner.own(api.reset,api.reset)
 Sync.observe(owner,function(value)
  roster=value
  if pending and not current(pending) then pending=nil end
  for k,r in pairs(seen) do if not current(r) then seen[k]=nil end end
  for _,r in pairs(jobs) do if not current(r) then cancelOwned(r);close(r) end end
  drainPongs()
 end)
 D.on_change(clear,{replay=true})
 local PC='/Game/Blueprints/Player/B_PlayerController.B_PlayerController_C:'
 owner.hook(PC..'ExecuteConsoleCommandFromClient',api.upstream,{finite_install=true})
 owner.hook(PC..'ClientSetRevisionNumber',api.downstream,{finite_install=true})
 return api
end
return M
