do
-- Source-clocked media with a bounded set of display objects.
local L=getgenv().__DAEWID_BALL_LUMEN
local G=L.Giorgio or {}; L.Giorgio=G;
local M,T=L.Motion,L.T
G.assets={["icons"]={["gauge"]={["type"]="atlas",["usage"]="Rep Root",["fps"]=120,["fps_ratio"]="120/1",["frames"]=253,["duration"]=2.1083333333333334,["folder"]="icons",["prefix"]="gauge-",["ext"]="png",["first"]=1,["digits"]=2,["count"]=253,["tileWidth"]=72,["tileHeight"]=72,["cols"]=14,["pageCount"]=2,["width"]=72,["height"]=72,["columns"]=14,["rows"]=14,["frames_per_page"]=196,["loop"]=false,["pages"]={{["path"]="icons/gauge-01.png",["bytes"]=47452,["sha256"]="90add73206515311714f5ebe5980dfa104f85e5e9dea4bfbbdb86697623f42f8",["first_frame"]=0,["frame_count"]=196,["width"]=1008,["height"]=1008},{["path"]="icons/gauge-02.png",["bytes"]=20367,["sha256"]="782f1a6ee1b6150a2860d15f553bf97a0c68482e08e294053f38cbd350d030bc",["first_frame"]=196,["frame_count"]=57,["width"]=1008,["height"]=360}},["source_url"]="https://api.github.com/repos/cyberalien/line-md/contents/svg-frames-120fps/gauge",["license"]="MIT",["attribution"]="Vjacheslav Trushkin (cyberalien), line-md"},["account"]={["type"]="atlas",["usage"]="Players",["fps"]=120,["fps_ratio"]="120/1",["frames"]=97,["duration"]=0.8083333333333333,["folder"]="icons",["prefix"]="account-",["ext"]="png",["first"]=1,["digits"]=2,["count"]=97,["tileWidth"]=72,["tileHeight"]=72,["cols"]=14,["pageCount"]=1,["width"]=72,["height"]=72,["columns"]=14,["rows"]=14,["frames_per_page"]=196,["loop"]=false,["pages"]={{["path"]="icons/account-01.png",["bytes"]=14674,["sha256"]="da73526f2556ac722d63206253ab8d3a741b93799554246d3b8265b54497ade0",["first_frame"]=0,["frame_count"]=97,["width"]=1008,["height"]=504}},["source_url"]="https://api.github.com/repos/cyberalien/line-md/contents/svg-frames-120fps/account",["license"]="MIT",["attribution"]="Vjacheslav Trushkin (cyberalien), line-md"},["compass"]={["type"]="atlas",["usage"]="Offsets",["fps"]=120,["fps_ratio"]="120/1",["frames"]=133,["duration"]=1.1083333333333334,["folder"]="icons",["prefix"]="compass-",["ext"]="png",["first"]=1,["digits"]=2,["count"]=133,["tileWidth"]=72,["tileHeight"]=72,["cols"]=14,["pageCount"]=1,["width"]=72,["height"]=72,["columns"]=14,["rows"]=14,["frames_per_page"]=196,["loop"]=false,["pages"]={{["path"]="icons/compass-01.png",["bytes"]=41479,["sha256"]="c4c8054315b8ad72f79cf2974f56ffd3b7fda8b6fa9d412e9638363ed730da36",["first_frame"]=0,["frame_count"]=133,["width"]=1008,["height"]=720}},["source_url"]="https://api.github.com/repos/cyberalien/line-md/contents/svg-frames-120fps/compass",["license"]="MIT",["attribution"]="Vjacheslav Trushkin (cyberalien), line-md"},["grid-3"]={["type"]="atlas",["usage"]="Presets",["fps"]=120,["fps_ratio"]="120/1",["frames"]=73,["duration"]=0.6083333333333333,["folder"]="icons",["prefix"]="grid-3-",["ext"]="png",["first"]=1,["digits"]=2,["count"]=73,["tileWidth"]=72,["tileHeight"]=72,["cols"]=14,["pageCount"]=1,["width"]=72,["height"]=72,["columns"]=14,["rows"]=14,["frames_per_page"]=196,["loop"]=false,["pages"]={{["path"]="icons/grid-3-01.png",["bytes"]=8182,["sha256"]="14ae547566a8b5bda2f47a47bbb6d46d89c184044cd4d384a35c7a9681b60ad3",["first_frame"]=0,["frame_count"]=73,["width"]=1008,["height"]=432}},["source_url"]="https://api.github.com/repos/cyberalien/line-md/contents/svg-frames-120fps/grid-3",["license"]="MIT",["attribution"]="Vjacheslav Trushkin (cyberalien), line-md"},["cog"]={["type"]="atlas",["usage"]="Interface",["fps"]=120,["fps_ratio"]="120/1",["frames"]=121,["duration"]=1.0083333333333333,["folder"]="icons",["prefix"]="cog-",["ext"]="png",["first"]=1,["digits"]=2,["count"]=121,["tileWidth"]=72,["tileHeight"]=72,["cols"]=14,["pageCount"]=1,["width"]=72,["height"]=72,["columns"]=14,["rows"]=14,["frames_per_page"]=196,["loop"]=false,["pages"]={{["path"]="icons/cog-01.png",["bytes"]=41305,["sha256"]="7305f885c4ceb11136797b0994a3f10825ed8eb69fa188326b322834aebccf3c",["first_frame"]=0,["frame_count"]=121,["width"]=1008,["height"]=648}},["source_url"]="https://api.github.com/repos/cyberalien/line-md/contents/svg-frames-120fps/cog",["license"]="MIT",["attribution"]="Vjacheslav Trushkin (cyberalien), line-md"},["document-list"]={["type"]="atlas",["usage"]="Activity",["fps"]=120,["fps_ratio"]="120/1",["frames"]=157,["duration"]=1.3083333333333333,["folder"]="icons",["prefix"]="document-list-",["ext"]="png",["first"]=1,["digits"]=2,["count"]=157,["tileWidth"]=72,["tileHeight"]=72,["cols"]=14,["pageCount"]=1,["width"]=72,["height"]=72,["columns"]=14,["rows"]=14,["frames_per_page"]=196,["loop"]=false,["pages"]={{["path"]="icons/document-list-01.png",["bytes"]=15701,["sha256"]="adb92d7315241f391dbd3627d4d1caed3d152eeef32ef437aea8303d305a3b29",["first_frame"]=0,["frame_count"]=157,["width"]=1008,["height"]=864}},["source_url"]="https://api.github.com/repos/cyberalien/line-md/contents/svg-frames-120fps/document-list",["license"]="MIT",["attribution"]="Vjacheslav Trushkin (cyberalien), line-md"},["loading-twotone-loop"]={["type"]="atlas",["usage"]="Loading",["fps"]=120,["fps_ratio"]="120/1",["frames"]=325,["duration"]=2.7083333333333335,["folder"]="icons",["prefix"]="loading-twotone-loop-",["ext"]="png",["first"]=1,["digits"]=2,["count"]=325,["tileWidth"]=72,["tileHeight"]=72,["cols"]=14,["pageCount"]=2,["width"]=72,["height"]=72,["columns"]=14,["rows"]=14,["frames_per_page"]=196,["loop"]=true,["pages"]={{["path"]="icons/loading-twotone-loop-01.png",["bytes"]=86066,["sha256"]="d837f46aaa2bf938959e35e3bc9cf9fd86db0e831bf01ba18ba108e97dd7339e",["first_frame"]=0,["frame_count"]=196,["width"]=1008,["height"]=1008},{["path"]="icons/loading-twotone-loop-02.png",["bytes"]=64982,["sha256"]="e561ece00a96a3bf84721f4b1f57c471bcb853d6ddd822db2d88b017ab37ccca",["first_frame"]=196,["frame_count"]=129,["width"]=1008,["height"]=720}},["source_url"]="https://api.github.com/repos/cyberalien/line-md/contents/svg-frames-120fps/loading-twotone-loop",["license"]="MIT",["attribution"]="Vjacheslav Trushkin (cyberalien), line-md"}},["sounds"]={["hover"]="sounds/hover.ogg",["click"]="sounds/click.ogg",["tab"]="sounds/tab.ogg",["toggle_on"]="sounds/toggle_on.ogg",["toggle_off"]="sounds/toggle_off.ogg",["open"]="sounds/open.ogg",["close"]="sounds/close.ogg",["saved"]="sounds/saved.ogg",["loader"]="sounds/loader.ogg"}}
G.assetRoot="DaewidHUB/ui/giorgio/"
G.players={}
G.booting=true
local assetIds={}
local registrationEpoch,registeredEpoch=0,-1
L.hold(L.RunService.Heartbeat:Connect(function() registrationEpoch+=1 end))
function G.asset(path)
  if not path then return nil end
  if assetIds[path] then return assetIds[path] end
  local full=G.assetRoot..path
  local ok,present=pcall(isfile,full)
  if not ok or not present then return nil end
  -- This executor flattens getcustomasset paths to basenames. Frame 00001 from
  -- different films must never register as the same underlying texture.
  local prepared,cached=pcall(function()
    local bytes=readfile(full)
    local stem,ext=path:match("^(.*)(%.[^%.]+)$")
    stem,ext=stem or path,ext or ""
    local unique="g_"..stem:gsub("[/\\]","__").."_"..tostring(#bytes)..ext
    local directory="DaewidHUB/ui/cache"
    if not isfolder(directory) then makefolder(directory) end
    local destination=directory.."/"..unique
    if not isfile(destination) then writefile(destination,bytes) end
    return destination
  end)
  if not prepared then return nil end
  local loaded,id=pcall(getcustomasset,cached)
  if loaded then assetIds[path]=id; return id end
  return nil
end
local function visible(object)
  local node=object
  while node and node~=game do
    if node:IsA("GuiObject") and not node.Visible then return false end
    if node:IsA("ScreenGui") and not node.Enabled then return false end
    node=node.Parent
  end
  return node~=nil
end
local function fileFor(spec,index)
  local cells=(spec.cols or 1)*(spec.rows or 1)
  local page=math.floor((index-1)/cells)+(spec.first or 1)
  local ext=spec.ext or ".jpg"; if ext:sub(1,1)~="." then ext="."..ext end
  return spec.folder.."/"..string.format((spec.prefix or "f").."%0"..tostring(spec.digits or 5).."d"..ext,page),(index-1)%cells
end
G.Media={}
local DECODE_ALPHA=.999999
local function imageAlpha(picture,value)
  if L.uiWrite then L.uiWrite(picture,"ImageTransparency",value) else picture.ImageTransparency=value end
end
local function decodeHost()
  if G.decodeHost and G.decodeHost.Parent then return G.decodeHost end
  local gui=L.mk("ScreenGui",{Name="DaewidHUBDecoder",IgnoreGuiInset=true,ResetOnSpawn=false,DisplayOrder=-20000,Parent=L.host()})
  L.own(gui)
  G.decodeHost=L.mk("Frame",{Name="DecodeSurface",Size=UDim2.fromOffset(1,1),BackgroundTransparency=1,Parent=gui})
  return G.decodeHost
end
function G.Media.new(parent,spec,opts)
  opts=opts or {}
  if not spec or not spec.count or spec.count<1 or not spec.fps or spec.fps<=0 then return nil,"missing sequence" end
  local self={spec=spec,playing=false,position=0,elapsed=0,shown=0,dead=false,rate=1,rest=opts.transparency or 0,
    ready={},mirrors={},revision=0,buffering=true,warming=true,ended=false,stats={presented=0,skipped=0,late=0,preloaded=0,maxBuffered=0,preloadErrors=0}}
  local content=game:GetService("ContentProvider")
  local layer=opts.ZIndex or (parent:IsA("GuiObject") and parent.ZIndex+1 or 1)
  local cells=(spec.cols or 1)*(spec.rows or 1)
  local ahead=math.clamp(opts.prefetchFrames or 36,1,60)
  local function pageOf(index) return math.floor((index-1)/cells) end
  local function frameAt(seconds) return math.clamp(math.floor(seconds*spec.fps)+1,1,spec.count) end
  -- Signed distance from `from` to `index`, measured the short way around when the
  -- film loops. Without this every comparison below reads frame 1 as ~a whole film
  -- *behind* frame N, so the pictures fetched across the join are discarded on
  -- arrival and the wrap has to decode from cold.
  local function offsetFrom(index,from)
    local delta=index-from
    if opts.loop then
      if delta>spec.count/2 then delta-=spec.count
      elseif delta<-spec.count/2 then delta+=spec.count end
    end
    return delta
  end
  local function ring(index)
    if not opts.loop then return index end
    return (index-1)%spec.count+1
  end
  self.frameObj=L.mk("Frame",{Name=opts.name or "DaewidHUBMedia",Size=opts.Size or UDim2.fromScale(1,1),
    Position=opts.Position or UDim2.fromScale(0,0),BackgroundTransparency=1,ClipsDescendants=false,
    ZIndex=layer,Parent=parent})
  self.image=L.mk("ImageLabel",{Name="Picture",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
    ScaleType=opts.cover and Enum.ScaleType.Crop or Enum.ScaleType.Fit,ImageTransparency=self.rest,
    ZIndex=layer,Parent=self.frameObj})
  self.back=L.mk("ImageLabel",{Name="NextPicture",Size=UDim2.fromOffset(1,1),BackgroundTransparency=1,
    ScaleType=opts.cover and Enum.ScaleType.Crop or Enum.ScaleType.Fit,ImageTransparency=DECODE_ALPHA,
    Visible=true,ZIndex=layer,Parent=decodeHost()})
  if spec.cols then self.image.ImageRectSize=Vector2.new(spec.tileWidth,spec.tileHeight) end
  if spec.cols then self.back.ImageRectSize=Vector2.new(spec.tileWidth,spec.tileHeight) end
  self.buffers={{image=self.back}}
  if not spec.cols then
    for index=2,8 do
      local picture=L.mk("ImageLabel",{Name="Decode"..index,Size=UDim2.fromOffset(1,1),BackgroundTransparency=1,
        ScaleType=opts.cover and Enum.ScaleType.Crop or Enum.ScaleType.Fit,ImageTransparency=DECODE_ALPHA,
        Visible=true,ZIndex=layer,Parent=decodeHost()})
      self.buffers[index]={image=picture}
    end
  end
  if opts.cornerRadius then
    L.mk("UICorner",{CornerRadius=opts.cornerRadius,Parent=self.image})
    for _,slot in ipairs(self.buffers) do L.mk("UICorner",{CornerRadius=opts.cornerRadius,Parent=slot.image}) end
  end
  local function reveal(picture,previous)
    picture.Size=UDim2.fromScale(1,1); picture.Parent=self.frameObj
    imageAlpha(picture,self.rest); picture.Visible=true
    imageAlpha(previous,DECODE_ALPHA); previous.Size=UDim2.fromOffset(1,1); previous.Parent=decodeHost()
  end
  if spec.audio then
    local id=G.asset(spec.audio)
    if id then self.audio=L.mk("Sound",{Name="EditAudio",SoundId=id,Volume=L.Cfg.feat("giorgio.editVolume",.65),Parent=self.frameObj}) end
  end
  local function presentFilm(index)
    local best
    for _,slot in ipairs(self.buffers) do
      if slot.index and offsetFrom(slot.index,index)<=0 and (self.buffering or offsetFrom(slot.index,self.shown)>0) and slot.image.IsLoaded
        and (not best or offsetFrom(slot.index,best.index)>0) then best=slot end
    end
    if best then
      local previous=self.image
      reveal(best.image,previous)
      self.image=best.image; best.image=previous
      local completed=best.index; best.index=nil
      if self.shown>0 then self.stats.skipped+=math.max(0,offsetFrom(completed,self.shown)-1) end
      self.shown=completed; self.stats.presented+=1
    end
    for _,slot in ipairs(self.buffers) do
      local behind=slot.index and offsetFrom(slot.index,self.shown)
      local relative=slot.index and offsetFrom(slot.index,index)
      if slot.index and (behind<=0 and not self.buffering or relative<-30 or relative>#self.buffers) then slot.index=nil end
    end
    local queued={}
    for _,slot in ipairs(self.buffers) do if slot.index then queued[slot.index]=true end end
    local candidates={}
    if not self.buffering then
      for step=1,30 do
        local earlier=ring(index-step)
        if earlier<1 or offsetFrom(earlier,self.shown)<=0 then break end
        local entry=self.ready[pageOf(earlier)]
        if entry and entry.loaded then candidates[#candidates+1]=earlier; break end
      end
    end
    for step=0,#self.buffers-1 do
      local wanted=index+step
      if opts.loop then wanted=ring(wanted) elseif wanted>spec.count then break end
      candidates[#candidates+1]=wanted
    end
    for _,wanted in ipairs(candidates) do
      local entry=self.ready[pageOf(wanted)]
      if wanted~=self.shown and not queued[wanted] and entry and entry.loaded then
        local free
        for _,slot in ipairs(self.buffers) do if not slot.index then free=slot; break end end
        if not free then break end
        free.index=wanted; imageAlpha(free.image,DECODE_ALPHA); free.image.Visible=true; free.image.Image=entry.id
        queued[wanted]=true
      end
    end
    self.back=self.buffers[1].image
    self.pending=nil
    for _,slot in ipairs(self.buffers) do if slot.index then self.pending={index=slot.index};break end end
    return self.shown==index and self.image.IsLoaded
  end
  local function present(index)
    if self.dead then return false end
    if not spec.cols then return presentFilm(index) end
    -- Never replace the displayed texture. Prepare a second picture, let the
    -- renderer load it, then reveal it before hiding the previous picture.
    if self.pending then
      if not self.back.IsLoaded then return false end
      local previous=self.image
      reveal(self.back,previous)
      self.image,self.back=self.back,previous
      local completed=self.pending.index; self.pending=nil
      if self.shown>0 then self.stats.skipped+=math.max(0,offsetFrom(completed,self.shown)-1) end
      self.shown=completed; self.stats.presented+=1
    end
    if index==self.shown then return self.image.IsLoaded end
    local entry=self.ready[pageOf(index)]
    if not entry or not entry.loaded then
      self.stats.late+=1
      -- Decode can trail the audio clock. Present the newest ready picture,
      -- instead of waiting forever for an exact frame that is already past.
      if not self.buffering then
        for earlier=index-1,math.max(self.shown+1,index-30),-1 do
          local candidate=self.ready[pageOf(earlier)]
          if candidate and candidate.loaded then entry=candidate; index=earlier; break end
        end
      end
      if not entry or not entry.loaded then return false end
    end
    local cell=(index-1)%cells
    if spec.cols and self.image.Image==entry.id and self.image.IsLoaded then
      self.image.ImageRectOffset=Vector2.new((cell%spec.cols)*spec.tileWidth,math.floor(cell/spec.cols)*spec.tileHeight)
      self.shown=index; self.stats.presented+=1; return true
    end
    imageAlpha(self.back,DECODE_ALPHA); self.back.Visible=true; self.back.Image=entry.id
    if spec.cols then self.back.ImageRectOffset=Vector2.new((cell%spec.cols)*spec.tileWidth,math.floor(cell/spec.cols)*spec.tileHeight) end
    self.pending={index=index}
    return false
  end
  self.present=present
  self.duration=spec.duration or spec.count/spec.fps
  -- Register the first picture on creation. Every later registration and decode runs
  -- in the bounded worker below, never on RenderStepped.
  local firstPath=fileFor(spec,1)
  local firstId=G.asset(firstPath)
  if firstId then self.image.Image=firstId; self.shown=1; self.stats.presented=1; self.ready[0]={id=firstId,loaded=false}
  else self.error="Media file missing: "..firstPath end
  local function pauseAudio()
    if self.audio then self.audio.Playing=false end
    self.audioActive=false; self.audioSample=nil
  end
  local function audioClock(fallback)
    local sound=self.audio
    if not sound or not sound.IsLoaded or self.audioExhausted then return fallback end
    if not self.audioActive then
      -- Playing preserves TimePosition; Play() would reset a paused or sought film.
      sound.TimePosition=self.position; sound.PlaybackSpeed=self.rate; sound.Playing=true
      self.audioActive=true; self.audioSample=self.position
      return self.position
    end
    sound.PlaybackSpeed=self.rate
    if sound.IsPlaying then
      -- TimePosition updates in coarse bursts on this client. Driving every
      -- picture directly from it drops source frames even when already decoded.
      -- Advance on the render clock and use fresh audio samples to correct drift.
      local sample=sound.TimePosition
      if sample~=self.audioSample then
        self.audioSample=sample
        local drift=sample-fallback
        if math.abs(drift)>.75 then return math.max(self.position,sample) end
        if math.abs(drift)>.08 then
          local step=math.max(0,fallback-self.position)*.2
          fallback+=math.clamp(drift,-step,step)
        end
      end
      return fallback
    end
    self.audioActive=false; self.audioExhausted=true
    return fallback
  end
  if self.audio then self.audioEnded=self.audio.Ended:Connect(function() self.audioExhausted=true; self.audioActive=false end) end
  function self:seek(seconds)
    if self.dead or type(seconds)~="number" or seconds~=seconds or math.abs(seconds)==math.huge then return false end
    self.revision+=1
    self.pending=nil; imageAlpha(self.back,DECODE_ALPHA); self.back.Visible=true
    for _,slot in ipairs(self.buffers) do slot.index=nil end
    self.position=math.clamp(seconds,0,self.duration); self.elapsed=self.position
    self.ended=false; self.audioExhausted=false; self.warming=true
    pauseAudio()
    if self.audio and self.audio.IsLoaded then self.audio.TimePosition=self.position end
    self.buffering=not present(frameAt(self.position))
    return true
  end
  function self:play()
    if self.dead or L.Cfg.data.reduceMotion then return end
    if self.ended or self.position>=self.duration then self:seek(0) end
    self.playing=true
    self.audioExhausted=false
  end
  function self:pause() self.playing=false; pauseAudio() end
  function self:stop() self:pause(); if self.audio then self.audio:Stop() end; self:seek(0) end
  function self:setFrame(index) self:seek((math.clamp(index,1,spec.count)-1)/spec.fps) end
  function self:destroy()
    if self.dead then return end
    self.dead=true; self.playing=false
    if self.connection then self.connection:Disconnect() end
    for _,worker in ipairs(self.workers or {}) do if worker~=coroutine.running() then pcall(task.cancel,worker) end end
    if self.audioEnded then self.audioEnded:Disconnect() end
    if self.audio then self.audio:Stop() end
    for mirror in pairs(self.mirrors) do mirror:destroy() end
    for _,slot in ipairs(self.buffers) do slot.image:Destroy() end
    if self.frameObj then self.frameObj:Destroy() end
    table.clear(self.ready)
    G.players[self]=nil
  end
  local function preloadWorker()
    while not self.dead and L.live() and self.frameObj.Parent do
      local revision=self.revision
      local current=frameAt(self.position)
      local wanted={}
      local limit=self.playing and ahead or 0
      for offset=-30,limit do
        local index=current+offset
        if opts.loop then index=(index-1)%spec.count+1 end
        if index>=1 and index<=spec.count then wanted[pageOf(index)]=index end
      end
      local keepPage=pageOf(math.max(1,self.shown))
      for page in pairs(self.ready) do if not wanted[page] and page~=keepPage then self.ready[page]=nil end end
      local batch,entries={},{}
      -- Current picture first, followed by forward lookahead. Do not spend a seek
      -- decoding pictures behind the new position, or preload an entire film.
      local visited={}
      for offset=0,limit do
        if revision~=self.revision then break end
        local index=current+offset
        if opts.loop then index=(index-1)%spec.count+1 end
        if index>spec.count then break end
        local page=pageOf(index)
        if not visited[page] then
          visited[page]=true
          local entry=self.ready[page]
          if not entry or (not entry.loaded and not entry.loading and os.clock()>=(entry.retryAt or 0)) then
            local path=fileFor(spec,index)
            entry=entry or {loaded=false}; entry.loading=true; self.ready[page]=entry
            -- File registration is synchronous in the executor. Spread new
            -- registrations across heartbeats instead of blocking one frame
            -- with several workers' entire batches of full-resolution images.
            local id=entry and entry.id or assetIds[path]
            if not id then
              while registeredEpoch==registrationEpoch and not self.dead and revision==self.revision do task.wait() end
              if self.dead then return end
              if revision~=self.revision then entry.loading=false; break end
              registeredEpoch=registrationEpoch
              id=G.asset(path)
            end
            if id then
              entry.id=id
              batch[#batch+1]=id; entries[#entries+1]=entry
            else
              self.error="Media file missing: "..path
              self.ready[page]={loaded=false,retryAt=os.clock()+1}
            end
          end
          if #batch>=6 then break end
        end
      end
      local buffered=0; for _ in pairs(self.ready) do buffered+=1 end
      self.stats.maxBuffered=math.max(self.stats.maxBuffered,buffered)
      if revision~=self.revision then
        for _,entry in ipairs(entries) do entry.loading=false end
      elseif #batch>0 then
        local statuses={}
        local ok=pcall(function()
          content:PreloadAsync(batch,function(id,status) statuses[id]=status end)
        end)
        if self.dead then return end
        for index,entry in ipairs(entries) do
          entry.loading=false
          entry.loaded=ok and statuses[batch[index]]==Enum.AssetFetchStatus.Success
          if entry.loaded then self.stats.preloaded+=1
          else entry.retryAt=os.clock()+1; self.stats.preloadErrors+=1; self.error="A media frame could not be loaded." end
        end
        task.wait()
      else task.wait(.04) end
    end
    self:destroy()
  end
  self.workers={}
  for _=1,(spec.cols and 1 or spec.fps>=50 and 3 or 2) do self.workers[#self.workers+1]=task.spawn(preloadWorker) end
  self.worker=self.workers[1]
  self.connection=L.RunService.RenderStepped:Connect(function(dt)
    if self.dead or not L.live() then self:destroy(); return end
    if not self.frameObj.Parent then self:destroy(); return end
    if self.buffering then
      self.buffering=not present(frameAt(self.position))
      if self.buffering then return end
    end
    if not self.playing then return end
    if opts.pauseHidden~=false and not visible(self.frameObj) then
      local mirrored=false
      for mirror in pairs(self.mirrors) do if visible(mirror.frameObj) then mirrored=true; break end end
      if not mirrored then pauseAudio(); return end
    end
    if self.warming then
      local current=frameAt(self.position)
      for step=0,math.min(ahead,18) do
        local index=current+step
        if opts.loop then index=ring(index) elseif index>spec.count then break end
        local entry=self.ready[pageOf(index)]
        if not entry or not entry.loaded then return end
      end
      self.warming=false
    end
    local rate=tonumber(self.rate) or 1
    self.rate=(rate==rate) and math.clamp(rate,.1,4) or 1
    local clock=audioClock(self.position+dt*self.rate)
    if clock>=self.duration then
      if opts.loop then
        -- Roll the clock over and keep playing. seek() would bump the preload
        -- revision, drop every decoded picture and re-warm -- the right response to
        -- someone jumping the timeline, and the wrong one for a join the preloader
        -- has already fetched both sides of.
        self.position=clock%self.duration; self.elapsed=self.position
        if self.audio and self.audio.IsLoaded then self.audio.TimePosition=self.position end
        self.buffering=not present(frameAt(self.position))
        return
      else
        self.position=self.duration; self.elapsed=self.duration; self.ended=true; self:pause()
        self.buffering=not present(spec.count)
        if self.onEnded then self.onEnded() end
        return
      end
    end
    self.position=clock; self.elapsed=clock
    present(frameAt(clock))
  end)
  G.players[self]=true
  if opts.autoplay then self:play() end
  return self
end
function G.Media.mirror(parent,source,opts)
  if not source or source.dead then return nil end
  opts=opts or {}
  local self={dead=false,source=source}
  self.frameObj=L.mk("Frame",{Name=opts.name or "MediaMirror",Size=opts.Size or UDim2.fromScale(1,1),
    Position=opts.Position or UDim2.fromScale(0,0),BackgroundTransparency=1,ClipsDescendants=false,ZIndex=opts.ZIndex or 0,Parent=parent})
  local function picture(host,size)
    local img=L.mk("ImageLabel",{Size=size,ImageTransparency=DECODE_ALPHA,BackgroundTransparency=1,
      ScaleType=opts.cover and Enum.ScaleType.Crop or Enum.ScaleType.Fit,ZIndex=opts.ZIndex or 0,Parent=host})
    if opts.cornerRadius then L.mk("UICorner",{CornerRadius=opts.cornerRadius,Parent=img}) end
    return img
  end
  self.image=picture(self.frameObj,UDim2.fromScale(1,1))
  self.back=picture(decodeHost(),UDim2.fromOffset(1,1))
  function self:destroy()
    if self.dead then return end; self.dead=true
    if self.connection then self.connection:Disconnect() end
    source.mirrors[self]=nil; self.back:Destroy(); self.frameObj:Destroy()
  end
  source.mirrors[self]=true
  self.connection=L.RunService.RenderStepped:Connect(function()
    if source.dead or not self.frameObj.Parent or not L.live() then self:destroy(); return end
    if not visible(self.frameObj) then return end
    if self.pending and self.back.IsLoaded then
      local previous=self.image
      self.back.Size=UDim2.fromScale(1,1); self.back.Parent=self.frameObj
      imageAlpha(self.back,opts.transparency or source.rest)
      imageAlpha(previous,DECODE_ALPHA); previous.Size=UDim2.fromOffset(1,1); previous.Parent=decodeHost()
      self.image,self.back=self.back,previous; self.pending=nil
    end
    local id=source.image.Image
    if not self.pending and id~="" and self.image.Image~=id then self.back.Image=id; self.pending=true end
  end)
  return self
end
local lastSound={}
function G.sound(name,volume)
  if G.booting and name~="loader" then return end
  if L.Cfg.feat("giorgio.sfx",true)==false then return end
  local now=os.clock()
  if now-(lastSound[name] or -10)<(name=="hover" and .09 or .025) then return end
  lastSound[name]=now
  local spec=G.assets.sounds and G.assets.sounds[name]
  local id=G.asset(type(spec)=="table" and spec.file or spec)
  if not id then return end
  local sound=L.mk("Sound",{Name="DaewidHUB_"..name,SoundId=id,
    Volume=(volume or 1)*L.Cfg.feat("giorgio.sfxVolume",.35),Parent=game:GetService("SoundService")})
  L.own(sound); sound:Play()
  sound.Ended:Connect(function() sound:Destroy() end)
  task.delay(12,function() if sound.Parent then sound:Destroy() end end)
  return sound
end
local function text(parent,name,word,pos,size,fs,font)
  return L.mk("TextLabel",{Name=name,Text=word,Position=pos,Size=size,BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(235,233,226),Font=font or Enum.Font.Gotham,TextSize=fs or 13,
    TextXAlignment=Enum.TextXAlignment.Left,Parent=parent})
end
G.text=text
function G.button(parent,name,word,pos,size,callback)
  local button=L.mk("TextButton",{Name=name,Text=word,Position=pos,Size=size,BackgroundColor3=Color3.fromRGB(31,31,29),
    BorderSizePixel=0,TextColor3=Color3.fromRGB(235,233,226),TextSize=12,Font=Enum.Font.Gotham,AutoButtonColor=false,Parent=parent})
  L.corner(4,button)
  button.MouseEnter:Connect(function() M.to(button,"BackgroundColor3",Color3.fromRGB(48,48,44),"fast"); G.sound("hover",.35) end)
  button.MouseLeave:Connect(function() M.to(button,"BackgroundColor3",Color3.fromRGB(31,31,29),"fast") end)
  button.Activated:Connect(function() G.sound("click",.7); L.try("giorgio."..name,callback) end)
  return button
end
function G.drag(root,grip,scale,onMove)
  local connections,drag={},nil
  connections[#connections+1]=grip.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
      drag={input=input,touch=input.UserInputType==Enum.UserInputType.Touch,start=Vector2.new(input.Position.X,input.Position.Y),position=root.Position}
    end
  end)
  connections[#connections+1]=L.UIS.InputChanged:Connect(function(input)
    if not drag or not root.Parent then return end
    if input==drag.input or not drag.touch and input.UserInputType==Enum.UserInputType.MouseMovement then
      local delta=Vector2.new(input.Position.X,input.Position.Y)-drag.start
      root.Position=drag.position+UDim2.fromOffset(delta.X,delta.Y)
      if onMove then onMove() end
    end
  end)
  connections[#connections+1]=L.UIS.InputEnded:Connect(function(input)
    if drag and (input==drag.input or not drag.touch and input.UserInputType==Enum.UserInputType.MouseButton1) then drag=nil end
  end)
  connections[#connections+1]=L.UIS.WindowFocusReleased:Connect(function() drag=nil end)
  return function() for _,connection in ipairs(connections) do connection:Disconnect() end end
end

end
