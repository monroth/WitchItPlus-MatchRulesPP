-- Bounded rules inbox. Core owns the connection; Native owns dialog calls.
local M={}
local CLASS='/Game/UserInterface/Information/WB_QuestionDialog.WB_QuestionDialog_C'
local D=CLASS..':'
function M.init(H,A,clock)
 clock=clock or H.now or os.time
 local api={};local pending={};local active;local serial=0
 local N=assert(H.api.Native.scope(H.api.id),'rules dialog Native scope unavailable')
 H.api.own(N.close)
 local function current(r)return H.api.is_live() and (not r.current or r.current())end
 local function live(r)
  if not current(r)then return false end
  local host,_,gs=H.host()
  return (r.shared and not host or not r.shared and host) and H.valid(gs) and H.key(gs)==r.gs
   and H.valid(r.pc) and H.sameWorld(r.pc,gs)
 end
 local function call(o,name,...)
  local result,why=N.call(o,name,{...})
  assert(result,'rules dialog '..name..': '..tostring(why));return result.ReturnValue
 end
 local function changed()if H.wake then H.wake()end end
 local function labels(r,restore)
  if restore then
   for _,row in ipairs(r.labels or{})do if H.valid(row.widget)then
    assert(N.set(row.widget,'Text',FText(row.text)));assert(N.set(row.widget,'LabelText',FText(row.label)))
    call(row.widget.Label,'SetText',FText(row.label))
   end end
   r.labels=nil;return
  end
  if not r.shared then return end
  r.labels={}
  for _,item in ipairs({{'Yes','Save as preset'},{'No','Ignore'}})do
   local b=r.widget[item[1]];assert(H.valid(b),'rules offer button missing: '..item[1])
   r.labels[#r.labels+1]={widget=b,text=H.text(b.Text),label=H.text(b.LabelText)}
   assert(N.set(b,'Text',FText(item[2])));assert(N.set(b,'LabelText',FText(item[2])))
   call(b.Label,'SetText',FText(item[2]))
  end
 end
 local function remove(r,close)
  local _,_,gs=H.host()
  if H.valid(gs)and H.key(gs)==r.gs and H.valid(r.widget)then
   labels(r,true)
   if active==r then active=nil end -- CloseDialog may synchronously invoke OnBack.
   if close then call(r.widget,'CloseDialog')end
  end
  if active==r then active=nil end
  for i=#pending,1,-1 do if pending[i]==r then table.remove(pending,i)end end
  changed()
 end
 local function add(p,name,pc,guard,shared,reply)
  assert(guard==nil or type(guard)=='function','rules offer connection required')
  assert(#pending<8,'rules inbox is full')
  local host,_,gs=H.host()
  assert((shared and not host or not shared and host)and H.valid(gs)and H.sameWorld(pc,gs),'stale rules sender')
  assert(not guard or guard(),'stale rules connection')
  serial=serial+1
  local r={id=serial,shared=shared,current=guard,pc=pc,gs=H.key(gs),preset=A.cleanPreset(p),name=name,
   reply=reply or function()end,expires=clock()+120}
  pending[#pending+1]=r;changed();return r
 end
 function api.receive(p,pc,reply,guard)
  local name='proposal-'..math.floor(clock())..'-'..(serial+1)
  local r=add(p,name,pc,guard,false,reply)
  A.storage().importWrite(name,r.preset)
  H.log('Rules proposal received; saved imports/'..name..'.json; awaiting host decision')
 end
 function api.shared(p,name,pc,guard)
  add(p,name,pc,guard,true)
  H.log("Host shared rules '"..name.."'; waiting for Save as preset / Ignore")
 end
 local function find(id)for _,r in ipairs(pending)do if r.id==id then return r end end end
 local function decide(r,accepted,close)
  assert(live(r)and clock()<=r.expires,'rules offer expired or sender disconnected')
  remove(r,close)
  H.defer(H.guard('rules decision',function()
   if not live(r)then return end
   if accepted then
    local ok,message=pcall(r.shared and A.saveShared or A.accept,r.preset,r.name,r.current)
    H.log(ok and message or ('rules decision failed: '..tostring(message)))
    if current(r)then r.reply(ok and 'ACCEPTED'or'FAILED')end
   else H.log(r.shared and'Shared rules ignored'or'Rules proposal declined');if current(r)then r.reply('DECLINED')end end
  end))
  return accepted and (r.shared and'Saving preset…'or'Rules accepted for the next match.')or'Offer ignored.'
 end
 function api.answer(id,accepted)
  local r=assert(find(id),'rules offer no longer pending');return decide(r,accepted,true)
 end
 local function answer(self,accepted)
  local r=active
  if r and current(r)and H.valid(H.unwrap(self))and H.same(H.unwrap(self),r.widget)then
   if clock()>r.expires then remove(r,true);r.reply('DECLINED');H.log('Rules offer expired: '..r.name)
   else decide(r,accepted,false)end
  end
 end
 local function enabled()return active~=nil and current(active)end
 for _,event in ipairs({'BndEvt__Yes_K2Node_ComponentBoundEvent_1_Clicked__DelegateSignature','OnApply'})do
  H.hook(D..event,function(self)answer(self,true)end,enabled)
 end
 for _,event in ipairs({'BndEvt__No_K2Node_ComponentBoundEvent_2_Clicked__DelegateSignature','BndEvt__Cancel_K2Node_ComponentBoundEvent_3_Clicked__DelegateSignature','OnBack'})do
  H.hook(D..event,function(self)answer(self,false)end,enabled)
 end
 local function describe(r)
  return r.shared and ("Host shared rules '"..r.name.."'\nSave as a preset?")or A.summary(r.preset,r.pc,r.name,r.current)
 end
 local function present(r)
  if A.panelOpen and A.panelOpen()then
   return false,'Match Rules + is open; answer in Pending rules offers.',true
  end
  if active then return false,'Answer the open rules question first, or use the pending-offer buttons.'end
  local _,pc,_,_,gi=H.host();assert(H.valid(pc)and H.valid(gi),'local rules UI unavailable')
  local manager=gi.IngameUIManager;assert(H.valid(manager),'IngameUIManager unavailable')
  for _,w in ipairs(assert(N.find(CLASS,pc),'rules dialog query unavailable'))do
   if H.valid(w)and H.sameWorld(w,pc)then
    if call(w,'IsVisible')and call(w,'IsInViewport')then return false,'Answer the open question, or review this offer in Match Rules +.'end
   end
  end
  call(manager,'ShowQuestionDialog',FText(r.shared and'Save as preset / Ignore'or'Rules proposal'),FText(describe(r)),false,true,true,false)
  -- Query the actual world immediately; constructor registry notifications may
  -- be delivered later. A cached native dialog may be reused on this call.
  local candidate
  for _,w in ipairs(assert(N.find(CLASS,pc),'rules dialog query unavailable'))do
   if H.valid(w)and H.sameWorld(w,pc)and call(w,'IsVisible')then
    candidate=w;if call(w,'IsInViewport')then break end
   end
  end
  if candidate then
   local w=candidate;r.widget=w;active=r;r.error=nil;r.notice=nil;labels(r,false)
   if call(w,'IsInViewport')then call(w,'SetZOrderInViewport',10000)else call(w,'AddToViewport',10000)end
   -- Core.dialog_input restores the mode/focus displaced by this native question.
   H.retryHooks();H.log('Rules question shown: '..r.name);changed();return true,'Rules question opened.'
  end
  error('native question not found after ShowQuestionDialog; offer retained in Match Rules +')
 end
 function api.show(id)
  local r=assert(find(id),'rules offer no longer pending');assert(live(r)and clock()<=r.expires,'rules offer expired')
  if active==r then return'Answer the open rules question.'end
  r.presented=true
  if A.panelOpen and A.panelOpen()then return describe(r)..'\nChoose an answer in Pending rules offers.'end
  local _,why=present(r);return why
 end
 function api.inbox()
  local rows={}
  for _,r in ipairs(pending)do if live(r)and clock()<=r.expires then
   rows[#rows+1]={id=r.id,name=r.name,shared=r.shared,error=r.error,notice=r.notice}
  end end
  return rows
 end
 function api.poll()
  for i=#pending,1,-1 do
   local r=pending[i]
   if not live(r)or clock()>r.expires then
    local valid=live(r);remove(r,true)
    if valid then r.reply('DECLINED');H.log('Rules offer expired: '..r.name)end
   end
  end
  if active then
   if not H.valid(active.widget)or not call(active.widget,'IsVisible')then
    -- A menu may hide the native question without answering it. Keep the inbox.
    local r=active;labels(r,true);active=nil;r.error='Dialog closed; answer in Match Rules +.';changed()
   end
   return
  end
  for _,r in ipairs(pending)do if not r.presented then
   r.presented=true
   local ok,shown,why,inPanel=pcall(present,r)
   if ok and inPanel then
    r.notice=why;r.error=nil;H.log('Rules offer in panel: '..r.name..'; '..why);changed()
   elseif not ok or not shown then
    local detail=tostring(ok and why or shown);H.log('Rules question pending: '..r.name..': '..detail);r.error=ok and why or 'Could not open the question. Use the buttons here.';changed()
   end
   return
  end end
 end
 function api.close()for i=#pending,1,-1 do remove(pending[i],true)end end
 function api.reset()pending={};active=nil;changed()end
 H.api.shared('Core').package_sync.observe(H.api,function()
  for i=#pending,1,-1 do if not current(pending[i])then remove(pending[i],true)end end
 end)
 H.api.own(api.close,api.reset)
 return api
end
return M
