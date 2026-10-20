-- Rules exchange belongs to the live Core connection, never to a layout file.
-- Core owns world/peer lifetime; the bounded feature payload is ordinary JSON.
local M={VERSION=2,BYTES=384,BODY_LIMIT=36864,LIMIT=36864,PARTS=96}
local PREFIX='MRPP2:V2:'
local function hex(s) return (s:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
local function unhex(s) return (s:gsub('%x%x',function(c) return string.char(tonumber(c,16)) end)) end
local function integer(v,min,max) return type(v)=='number' and v%1==0 and v>=min and v<=max end
function M.chunks(text)
 assert(type(text)=='string' and #text>0 and #text<=M.LIMIT,'invalid rules transfer')
 local pieces={};for i=1,#text,M.BYTES do pieces[#pieces+1]=hex(text:sub(i,i+M.BYTES-1)) end;return pieces
end
function M.assemble(holder,rev,i,total,data)
 if not integer(rev,1,2147483647) or not integer(total,1,M.PARTS) or not integer(i,1,total)
  or type(data)~='string' or #data==0 or #data>M.BYTES*2 or #data%2~=0 or not data:match('^%x+$') then return end
 if rev<=(holder.received or 0) then return end
 local t=holder.transfer
 if t and rev<t.revision then return end
 if not t or rev>t.revision then t={revision=rev,total=total,parts={},count=0};holder.transfer=t end
 if t.total~=total then holder.transfer=nil;return end
 if t.parts[i] then if t.parts[i]~=data then holder.transfer=nil end;return end
 t.parts[i]=data;t.count=t.count+1
 if t.count~=total then return end
 holder.transfer=nil
 local raw=unhex(table.concat(t.parts));if #raw<=M.LIMIT then return raw end
end
local function scope(view)
 return table.concat({view.pc_key,view.local_session,view.remote_session,view.local_revision,view.remote_revision},'|')
end
function M.init(H,J,A,clock)
 clock=clock or H.now or os.time
 local owner=H.api;local Sync=assert(owner.shared('Core').package_sync,'Core 2 readiness required')
 local Work=assert(H.core.work_budget,'finite Core work required')
 local L=H.lifetime or H.core.lifetime
 local api={revision=0};local roster,publication,received,receiver
 local jobs,sent,proposals={},{},{};local serial,hostRevision,proposalID=0,0,0;local latest,localProposal,lastPropose,lastShare;local responses={}
 local function enabled() return not H.feature or H.feature('sync') end
 local function live() return owner.is_live() and not L.transition and enabled() end
 local function changed() api.revision=api.revision+1;if A.changed then A.changed() elseif H.wake then H.wake() end end
 local function finish(r,state,reason)
  if r.closed then return true end
  r.closed=true;if jobs[r.key]==r then jobs[r.key]=nil end
  r.state=state;if state~='completed' and r.verb=='STATE' and sent[r.scope]==r then sent[r.scope]=nil end
  if not latest or r.serial>=latest.serial then latest={serial=r.serial,state=state,reason=reason,verb=r.verb,revision=r.revision,pc_key=r.view.pc_key} end
  r.pieces=nil;r.work=nil;return true
 end
 local function ownsWork(r) return r.work~=nil and Work.keys[r.key]==r.work end
 local function cancelOwned(r) if owner.is_live() and ownsWork(r) then pcall(Work.cancel,r.key) end end
 local function cancelJobs(reason)
  local old=jobs;jobs={}
  for _,r in pairs(old) do cancelOwned(r);finish(r,'retired',reason) end
 end
 local function clear(reason)
  local had=publication~=nil or received~=nil or receiver~=nil or localProposal~=nil or next(proposals)~=nil or next(jobs)~=nil
  publication=nil;received=nil;receiver=nil;localProposal=nil;proposals={};responses={};sent={};hostRevision=0
  cancelJobs(reason);if had then changed() end
 end
 local function current(r) return not r.closed and live() and Sync.current(r.view) end
 local function enqueue(view,verb,rev,pieces)
  if not live() or not Sync.current(view) then return false,'retired' end
  serial=serial+1;local r={serial=serial,key='mrpp2-send:'..serial,scope=scope(view),view=view,verb=verb,revision=rev,pieces=pieces,index=1}
  jobs[r.key]=r
  local function step()
   if not current(r) then return finish(r,'retired','owner_or_connection_changed') end
   if r.index>#r.pieces then return finish(r,'completed','sent') end
   return {native=function()
    if not current(r) then finish(r,'retired','owner_or_connection_changed');return end
    local i=r.index;r.index=i+1;local v=r.view
    local text=PREFIX..verb..':'..v.local_session..':'..v.remote_session..':'..v.local_revision..':'..v.remote_revision..':'..rev..':'..i..':'..#r.pieces..':'..r.pieces[i]
    local ok,result,reason=pcall(Sync.send,owner,v.pc_key,text,v)
    if not ok then finish(r,'failed','action_error');error(result,0) end
    if r.closed then return end
    if not result then finish(r,'failed',reason or 'send_rejected')
    elseif not current(r) then finish(r,'retired','owner_or_connection_changed')
    elseif r.index>#r.pieces then finish(r,'completed','sent') end
   end}
  end
  local ok,result=pcall(Work.submit,r.key,'MRPP feature '..verb,step)
  local record=Work.keys[r.key];if record and record.step==step then r.work=record end
  if not ok then cancelOwned(r);finish(r,'failed','schedule_error');error(result,0) end
  if result==false then finish(r,'failed','schedule_rejected');return false,'schedule_rejected' end
  return true,'accepted',r
 end
 local function respond(view,rev,pieces)
  if not live() or not Sync.current(view) then return false,'retired' end
  local outbound=Sync.peer(view.pc_key)
  if outbound and scope(outbound)==scope(view) then return enqueue(outbound,'RESULT',rev,pieces) end
  -- A connection may change during receive; retain only this bounded intent.
  assert(#responses<8,'proposal response inbox is full')
  responses[#responses+1]={view=view,revision=rev,pieces=pieces}
  return true,'waiting_confirmation'
 end
 local function drainResponses()
  local old=responses;responses={}
  for _,r in ipairs(old) do
   if live() and Sync.current(r.view) then
    local outbound=Sync.peer(r.view.pc_key)
    if outbound and scope(outbound)==scope(r.view) then enqueue(outbound,'RESULT',r.revision,r.pieces)
    else responses[#responses+1]=r end
   end
  end
 end
 local function sendState(view)
  if not publication or not Sync.current(view) then return false,'retired' end
  local id=scope(view);local previous=sent[id]
  if previous and previous.revision==publication.revision and Sync.current(previous.view) then
   if previous.state=='completed' or ownsWork(previous) then return true,'unchanged' end
   finish(previous,'cancelled','work_cancelled')
  end
  local ok,reason,r=enqueue(view,'STATE',publication.revision,publication.pieces)
  if ok and (not r.closed or r.state=='completed') then sent[id]=r end
  return ok,reason
 end
 local function fanout()
  if not roster or not roster.ready or not roster.host or not publication then return true,'stored' end
  local state='unchanged'
  for _,p in ipairs(roster.peers) do local v=Sync.peer(p.pc_key);if v then
   local ok,reason=sendState(v);if not ok then return false,reason end;if reason=='accepted' then state='accepted' end
  end end
  return true,state
 end
 function api.publish(heldGuard,T)
  if not live() or not roster or not roster.ready or not roster.host then return false,'not_ready' end
  local guard=heldGuard or function() return live() end
   local extras=A.extras(guard,T);A.validateExtras(extras)
   if not guard() or not live() then return false,'retired' end
  local body=J.encode({extras=extras});assert(#body<=M.BODY_LIMIT,'extras exceeds36KiB')
  local raw=body
  if publication and publication.raw==raw then return fanout() end
  -- New STATE supersedes only older STATE jobs, not an unrelated accepted RESULT.
  for _,r in pairs(jobs) do if r.verb=='STATE' then cancelOwned(r);finish(r,'retired','superseded_state') end end
  hostRevision=hostRevision+1;sent={}
  publication={raw=raw,pieces=M.chunks(raw),revision=hostRevision}
  return fanout()
 end
 local function parse(value)
  local text=H.text(H.unwrap(value))
  if #text>900 or text:sub(1,#PREFIX)~=PREFIX then return end
  local verb,ss,ts,sr,tr,rev,i,n,data=text:sub(#PREFIX+1):match('^([A-Z]+):([%x%-]+):([%x%-]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%x+)$')
  if not verb then return end
  return verb,ss,ts,tonumber(sr),tonumber(tr),tonumber(rev),tonumber(i),tonumber(n),data
 end
 function api.upstream(self,value)
  if not live() then return end
  local verb,ss,ts,sr,tr,rev,i,n,data=parse(value);if verb~='PROPOSE' then return end
  local pc=H.unwrap(self);local view=Sync.accept(pc,ss,ts,sr,tr);if not view or not view.host then return end
  local id=scope(view);local peer=proposals[id]
  if not peer then peer={view=view,lastID=0,lastProposal=-math.huge};proposals[id]=peer end
  if not integer(rev,1,2147483647) or rev<=peer.lastID or not peer.transfer and clock()-peer.lastProposal<10 then return end
  local raw=M.assemble(peer,rev,i,n,data);if not raw then return end
  local body=raw
  local decoded,p=pcall(J.decode,body);if not decoded then return end
  local cleaned,preset=pcall(A.cleanPreset,p);if not cleaned then return end
  local function guard() return live() and Sync.current(view) end
  if not guard() then return end
  peer.received=rev;peer.lastID=rev;peer.lastProposal=clock()
  local function reply(result)
   if not guard() then return false,'retired' end
   assert(result=='ACCEPTED' or result=='DECLINED' or result=='FAILED' or result=='INVALID','invalid proposal result')
   local response=M.chunks(J.encode({result=result}))
   return respond(view,rev,response)
  end
  local ok,err=pcall(A.proposal,preset,pc,reply,guard)
  if not ok and guard() then H.log('proposal rejected');reply('INVALID') end
 end
 function api.downstream(self,value)
  if not live() then return end
  local verb,ss,ts,sr,tr,rev,i,n,data=parse(value);if verb~='STATE' and verb~='RESULT' and verb~='SHARE' then return end
  local pc=H.unwrap(self);local view=Sync.accept(pc,ss,ts,sr,tr);if not view or view.host then return end
  local id=scope(view)
  if not receiver or receiver.scope~=id or not Sync.current(receiver.view) then receiver={scope=id,view=view,STATE={},RESULT={},SHARE={}};received=nil end
  if verb=='RESULT' and (not localProposal or localProposal.id~=rev or not Sync.current(localProposal.view)) then return end
  local holder=receiver[verb];local raw=M.assemble(holder,rev,i,n,data);if not raw then return end
  local body=raw
  local ok,p=pcall(J.decode,body);if not ok or type(p)~='table' then return end
  if not live() or not Sync.current(view) or receiver.scope~=id then return end
  if verb=='STATE' then
   if not pcall(A.validateExtras,p.extras) then return end
   holder.received=rev;received=p.extras;changed();H.log('host extras revision '..rev..' synchronized')
  elseif verb=='SHARE' then
   if holder.lastShare and clock()-holder.lastShare<10 then return end
   if type(p.name)~='string' or #p.name<1 or #p.name>64 or p.name:find('[%c]') then return end
   local good,preset=pcall(A.cleanPreset,p.preset);if not good then return end
   holder.received=rev;holder.lastShare=clock()
   local function guard()return live()and Sync.current(view)end
   local accepted,why=pcall(A.shared,preset,p.name,pc,guard)
   if not accepted then H.log('host share refused: '..tostring(why))end
  elseif p.result=='ACCEPTED' or p.result=='DECLINED' or p.result=='FAILED' or p.result=='INVALID' then
   holder.received=rev;localProposal=nil;if A.result then A.result(p.result) end
  end
 end
 function api.extras()
  if not live() then clear('inactive');return end
  if receiver and (not Sync.current(receiver.view)) then received=nil;receiver=nil;changed() end
  return received
 end
 function api.propose(p)
  assert(live() and roster and roster.ready and not roster.host,'connected ready client required')
  local view=Sync.peer(roster.pc_key);assert(view and not view.host,'host readiness required')
  assert(not lastPropose or clock()-lastPropose>=10,'wait ten seconds between proposals')
  local preset=A.cleanPreset(p);local body=J.encode(preset);assert(#body<=M.BODY_LIMIT,'proposal exceeds36KiB')
  proposalID=proposalID+1;assert(proposalID<=2147483647,'proposal revision exhausted')
  local old=localProposal;local r={id=proposalID,view=view};localProposal=r
  local ok,accepted,reason=pcall(enqueue,view,'PROPOSE',proposalID,M.chunks(body))
  if not ok then if localProposal==r then localProposal=old end;error(accepted,0) end
  if not accepted then if localProposal==r then localProposal=old end;error(reason,0) end
  lastPropose=clock();return 'Proposal sent; the host must accept it.'
 end
 function api.share(p,name)
  H.log('Rules Share: roster='..(roster and #roster.peers or 0)..' ready='..tostring(roster and roster.ready)..' host='..tostring(roster and roster.host))
  assert(live()and roster and roster.ready and roster.host,'local host with compatible modded clients required')
  assert(not lastShare or clock()-lastShare>=10,'wait ten seconds between shares')
  assert(type(name)=='string'and #name>=1 and #name<=64 and not name:find('[%c]'),'invalid share name')
  local body=J.encode({name=name,preset=A.cleanPreset(p)});assert(#body<=M.BODY_LIMIT,'share exceeds 36 KiB')
  local pieces=M.chunks(body);proposalID=proposalID+1
  local count=0
  for _,peer in ipairs(roster.peers)do
   local view=Sync.peer(peer.pc_key)
   if view then
    local ok,why=enqueue(view,'SHARE',proposalID,pieces)
    H.log('Rules Share: peer='..peer.pc_key..' decision='..(ok and 'queued' or 'skipped')..' reason='..tostring(why))
    assert(ok,why);count=count+1
   else
    H.log('Rules Share: peer='..peer.pc_key..' decision=skipped status='..tostring(peer.status)..' packages_compatible='..tostring(peer.packages_compatible)..' reason='..tostring(peer.compatible and 'connection changed since roster' or peer.status or 'inventory pending')..' problems='..table.concat(peer.problems or{},'; '))
   end
  end
  assert(count>0,'no compatible modded clients connected');lastShare=clock()
  return 'Shared current rules with '..count..' player(s).'
 end
 function api.maintenance() end -- old HELLO/GET/TTL driver cannot produce protocol2 work
 function api.reset() roster=nil;clear('reset') end
 function api.outcome()
  if not owner.is_live() then clear('owner_retired')
  else for _,r in pairs(jobs) do
   if not current(r) then cancelOwned(r);finish(r,'retired','owner_or_connection_changed')
   elseif not ownsWork(r) then finish(r,'cancelled','work_cancelled') end
  end end
  if latest then local copy={};for k,v in pairs(latest) do copy[k]=v end;return copy end
 end
 L.onReset(api.reset);owner.own(api.reset,api.reset)
 Sync.observe(owner,function(value)
  if not owner.is_live() or L.transition then api.reset();return end
  roster=value
  local scopes={}
  for _,row in ipairs(roster.peers) do local v=Sync.peer(row.pc_key);if v then scopes[scope(v)]=true end end
  for id in pairs(sent) do if not scopes[id] then sent[id]=nil end end
  for id,p in pairs(proposals) do if not Sync.current(p.view) then proposals[id]=nil end end
  for _,r in pairs(jobs) do if not Sync.current(r.view) then cancelOwned(r);finish(r,'retired','session_changed') end end
  if receiver and not Sync.current(receiver.view) then received=nil;receiver=nil;localProposal=nil;changed() end
  drainResponses()
  if roster.ready and roster.host then api.publish() end
 end)
 local PC='/Game/Blueprints/Player/B_PlayerController.B_PlayerController_C:'
 owner.hook(PC..'ExecuteConsoleCommandFromClient',api.upstream,{finite_install=true})
 owner.hook(PC..'ClientSetRevisionNumber',api.downstream,{finite_install=true})
 return api
end
return M
