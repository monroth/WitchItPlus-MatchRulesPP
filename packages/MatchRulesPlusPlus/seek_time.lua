-- TIME1 uses the starting GameMode/UsedMatchOptions, before a local controller
-- or the periodic effects cache necessarily exists. BeginPlay POST covers modes
-- that do not invoke the base Blueprint InitializeSeekTime implementation.
local M={EXTRA='NeedsExtraTime_43_B354AF0A49DCBA90CE3CC7A6C2FEF251'}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
function M.effective(base,k,s)
 for _,v in ipairs({base,k,s})do assert(finite(v),'invalid seek-time scalar')end
 return math.max(30,math.floor(base+k*s+.5))
end
function M.coefficient(map,custom,authored)
 if custom then return finite(authored)and authored or 0 end
 return map and map[M.EXTRA]==true and 1 or 0
end
function M.init(H,extras,beginMatch)
 local api={}
 local function apply(gm,row)
  assert(H.valid(gm),'GameMode unavailable')
  assert(H.authority(gm),'not authority')
  local gp=H.object('/Script/Engine.Default__GameplayStatics')
  local gi=gp:GetGameInstance(gm);local gs=gp:GetGameState(gm)
  assert(H.valid(gi)and H.valid(gs),'match context unavailable')
  if beginMatch then beginMatch(gm)end
  local values,refused=extras(gm,gi)
  local k=values.mapSizeTimeFactor or 0;row.k=k
  local options=gi.UsedMatchOptions;assert(H.valid(options),'UsedMatchOptions unavailable')
  row.slider=options.SeekTime;row.value=gs.SeekTime
  local custom=options.CustomMapSelected==true or H.class(gm,'B_CreativeGameMode_C')
  local authored
  local metadata=H.api.shared('Core').capabilities.get('layout_metadata')
  if metadata then
   if H.class(gm,'B_CreativeGameMode_C')and metadata.seek_coefficient then authored=metadata.seek_coefficient(gm)
   elseif metadata.for_options then
    local ok,info=pcall(metadata.for_options,gi)
    if ok then
     authored=info.seekCoefficient
     if authored~=nil and info.stock~=true then custom=true end
    end
   end
  end
  local s=M.coefficient(options.MapData,custom,authored);row.s=s
  if refused then row.applied='no '..refused;return end
  if k==0 then row.applied='no K=0 (vanilla)';return end
  local value=M.effective(options.SeekTime,k,s)
  gs:FlushNetDormancy();gs.SeekTime=value
  H.object('/Script/Engine.Default__NetPushModelHelpers'):MarkPropertyDirtyFromRepIndex(gs,44,FName('SeekTime'))
  gs:ForceNetUpdate();row.value=value;row.applied='yes'
 end
 local function run(self,report,className)
  local gm=H.unwrap(self)
  local row={slider='?',k='?',s='?',value='?',applied='no unknown'}
  local ok,why=pcall(apply,gm,row)
  if not ok then row.applied='no '..tostring(why):gsub('[\r\n]',' ')end
  if report then
   local mode=className
   if not mode then pcall(function()mode=gm:GetClass():GetFName():ToString()end)end
   H.log('TIME1 mode='..tostring(mode or '?')..' slider='..tostring(row.slider)..' K='..tostring(row.k)..
    ' S='..tostring(row.s)..' SearchTime='..tostring(row.value)..' applied='..row.applied)
  elseif not ok then H.log('TIME1 initialization: '..row.applied)end
 end
 function api.initialize(self)run(self,false)end
 function api.begin_play(self,className)run(self,true,className)end
 return api
end
return M
