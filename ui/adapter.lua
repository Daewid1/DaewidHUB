local UI = { Flags = {} }
local L = getgenv().__DAEWID_BALL_LUMEN
local C, A, M, T = L.C, L.A, L.Motion, L.T
local Window, Tab = {}, {}
Window.__index, Tab.__index = Window, Tab
local owner
local function keyFrom(value)
 if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then return value end
 if type(value) == "string" and value ~= "None" then local ok,key=pcall(function() return Enum.KeyCode[value] end); if ok then return key end end
 return nil
end
local function keyName(key) return key and key.Name or "None" end
local function refreshBindings() if owner and owner.refreshBindings then owner.refreshBindings() end end
local function mount(tab)
 if tab.body then return tab.body end
 local native = owner.native:tab({name=tab.name,desc=tab.subtitle or "Interface, shortcuts and saved configurations"})
 tab.native, tab.body = native,native.body
 if tab.initialize then local initialize=tab.initialize; tab.initialize=nil; initialize(tab) end
 return tab.body
end
local function register(tab,opts,kind,constructor)
 local entry = {Type=kind,Value=opts.Default}
 local api
 local callbackGeneration=0
 local function changed(value)
  callbackGeneration+=1
  local previous=entry.Value
  entry.Value=value
  local ok,result,why=true,nil,nil
  if opts.Callback then ok,result,why=pcall(opts.Callback,value) end
  if not ok or result==false then entry.Value=previous; if not ok then error(result,0) end; return false,why end
  refreshBindings()
  return result
 end
 api=constructor({id=opts.Flag or tab.name.."_"..tostring(opts.Text),text=opts.Text,desc=opts.Description,
  default=opts.Default,callback=changed,items=table.clone(opts.Options or {}),min=opts.Min,max=opts.Max,
  step=opts.Increment or 1,placeholder=opts.Placeholder,multi=opts.Multi==true,persist=false})
 entry.Value=api:get()
 entry.Set=function(value)
  if kind=="Toggle" then value=value==true
  elseif kind=="Keybind" then value=keyFrom(value)
  elseif kind=="Slider" then value=tonumber(value); if not value or value~=value or math.abs(value)==math.huge then return end
  elseif kind=="Input" then value=tostring(value or "") end
  local generation=callbackGeneration
  api:set(value)
  entry.Value=api:get()
  if callbackGeneration==generation then changed(entry.Value) end
  refreshBindings()
 end
 entry._api=api
 if not opts.NoFlag then UI.Flags[opts.Flag or (tab.name.."_"..tostring(opts.Text))]=entry end
 return entry,api
end
function Tab:AddSection(title,description)
 self.mount=mount(self)
 local header=C.section(self.mount,title)
 self.disclosure=nil
 if description then C.paragraph(self.mount,description) end
 return header
end
function Tab:AddDisclosure(title)
 local parent=self.mount or mount(self)
 local section=A.surface({Parent=parent,elev=1,radius=T.r.md,Size=UDim2.new(1,0,0,42),Name="Disclosure"})
 local header=A.text({Text=title,font=T.font.medium,size=T.size.body,colour=T.c.text,Position=UDim2.fromOffset(12,0),Size=UDim2.new(1,-42,0,42),Parent=section})
 local arrow=A.Icon.chevron(section,14,T.c.textMute,"down"); arrow.Position=UDim2.new(1,-28,0,14)
 local body=L.mk("Frame",{Name="DisclosureBody",Position=UDim2.fromOffset(12,42),Size=UDim2.new(1,-24,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Visible=false,Parent=section})
 L.list(T.px("gap"),nil,body)
 local expanded=false
 body:SetAttribute("DaewidDisclosure",true)
 A.interactive(header,{onClick=function() expanded=not body.Visible; body.Visible=expanded; section.AutomaticSize=expanded and Enum.AutomaticSize.Y or Enum.AutomaticSize.None; section.Size=UDim2.new(1,0,0,42); M.to(arrow,"Rotation",expanded and 180 or 0,"base") end})
 self.mount=body
 return {frame=section,body=body}
end
function Tab:AddLabel(content)
 local frame=C.paragraph(self.mount or mount(self),content)
 local label=frame:FindFirstChildOfClass("TextLabel")
 return {SetText=function(_,value) label.Text=tostring(value or "") end,frame=frame}
end
function Tab:AddToggle(opts)
 opts=table.clone(opts); opts.Default=opts.Default==true
 local entry,api=register(self,opts,"Toggle",function(config) return C.toggle(self.mount or mount(self),config) end)
 if opts.Bind~=false and not opts.NoFlag then
  local key=keyFrom(opts.Key)
  local bind={Type="Bind",Value=keyName(key)}
  local chip=A.surface({Parent=api.frame,elev=2,radius=T.r.sm,Size=UDim2.fromOffset(62,24),Name="BindChip"})
  chip.AnchorPoint=Vector2.new(1,.5); chip.Position=UDim2.new(1,-62,.5,0); chip.ZIndex=4
  local label=A.text({Text=keyName(key),font=T.font.mono,size=T.size.tiny,colour=T.c.textDim,align=Enum.TextXAlignment.Center,Parent=chip})
  for _,child in ipairs(api.frame:GetChildren()) do if child:IsA("TextLabel") then child.Size=UDim2.new(1,-148,child.Size.Y.Scale,child.Size.Y.Offset) end end
  bind.Set=function(value) key=keyFrom(value); bind.Value=keyName(key); label.Text=keyName(key); refreshBindings() end
  UI.Flags[(opts.Flag or self.name.."_"..tostring(opts.Text)).."_bind"]=bind
  A.interactive(chip,{onClick=function() owner.capture={apply=bind.Set,label=label,key=function() return key end}; L.Binds.capturing=true; label.Text="press..." end})
  table.insert(owner.bindings,{key=function() return key end,pressed=function() entry.Set(not entry.Value) end})
  if not opts.NoList then table.insert(owner.listed,{text=opts.Text,key=function() return key end,on=function() return entry.Value end}) end
 end
 return entry
end
function Tab:AddButton(opts)
 return C.button(self.mount or mount(self),{text=opts.Text,desc=opts.Description,callback=opts.Callback})
end
function Tab:AddSlider(opts)
 return register(self,opts,"Slider",function(config) return C.slider(self.mount or mount(self),config) end)
end
function Tab:AddDropdown(opts)
 opts=table.clone(opts); if opts.Default==nil then opts.Default=opts.Multi and {} or (opts.Options or {})[1] end
 local entry,api=register(self,opts,"Dropdown",function(config) return C.dropdown(self.mount or mount(self),config) end)
 entry.SetOptions=function(values) if type(values)~="table" then return end; api:setItems(values); entry.Value=api:get() end
 return entry
end
function Tab:AddKeybind(opts)
 opts=table.clone(opts); opts.Default=keyFrom(opts.Default)
 local entry,api=register(self,opts,"Keybind",function(config) return C.keybind(self.mount or mount(self),config) end)
 table.insert(owner.bindings,{key=function() return entry.Value end,pressed=opts.Pressed})
 if opts.Pressed and not opts.NoList then table.insert(owner.listed,{text=opts.Text,always=true,key=function() return entry.Value end,on=function() return entry.Value~=nil end}) end
 return entry
end
function Tab:AddInput(opts)
 opts=table.clone(opts); opts.Default=tostring(opts.Default or "")
 local entry,api=register(self,opts,"Input",function(config) return C.input(self.mount or mount(self),config) end)
 L.hold(api.box:GetPropertyChangedSignal("Text"):Connect(function() entry.Value=api.box.Text end))

 return entry
end
function Tab:AddStatRow(specs)
 local items={}
 for index,spec in ipairs(specs) do items[index]={key=index,label=spec.Title,value="-"} end
 local tiles=C.tiles(self.mount or mount(self),items)
 local elapsed=1
 L.hold(L.RunService.Heartbeat:Connect(function(delta)
  if not L.live() or not tiles.frame.Parent then return end
  elapsed+=delta; if elapsed<.3 then return end; elapsed=0
  for index,spec in ipairs(specs) do local ok,value,_,detail=pcall(spec.Get); if ok then tiles:set(index,tostring(value or "-")); tiles.cells[index]:SetAttribute("Detail",detail or "") end end
 end))
 return tiles
end
function Window:CreateCategory(name) self.native:navSection(name) end
function Window:CreateTab(name,icon,subtitle)
 local tab=setmetatable({name=name,subtitle=subtitle},Tab)
 mount(tab); table.insert(self.tabs,tab)
 return tab
end
function Window:Select(tab) self.native:select(type(tab)=="number" and tab or tab.native.index) end
function Window:IsOpen() return not self.native.hidden end
function Window:Toggle(value)
 if value==nil then self.native:toggle()
 elseif value and self.native.hidden then self.native:restore()
 elseif not value and not self.native.hidden then self.native:minimise() end
 refreshBindings()
end
function Window:Notify(opts) L.Toast.push({title=opts.Title,body=opts.Text,duration=opts.Duration,kind="info"}) end
function Window:Refit() self.native:fitViewport() end
function Window:StyleButton(button,color)
 local base=color or T.c.raised
 L.hold(button.MouseEnter:Connect(function() M.to(button,"BackgroundColor3",T.c.hover,"fast"); L.Giorgio.sound("hover",.2) end))
 L.hold(button.MouseLeave:Connect(function() M.to(button,"BackgroundColor3",base,"fast") end))
 L.hold(button.Activated:Connect(function() L.Giorgio.sound("click",.5) end))
 return button
end

function Window:CreatePanel(opts)
 local gui=L.mk("ScreenGui",{Name=opts.Name or "DaewidHUBPanel",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=25,Enabled=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,Parent=L.host()}); L.own(gui)
 local root=L.mk("CanvasGroup",{Name="Root",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(opts.Width or 940,opts.Height or 680),BackgroundColor3=T.c.surface,BorderSizePixel=0,ClipsDescendants=true,GroupTransparency=1,Parent=gui})
 L.corner(T.r.lg,root); L.stroke(T.c.line,1,.45,root)
 local scale=L.mk("UIScale",{Scale=1,Parent=root})
 local header=L.mk("Frame",{Name="Header",Size=UDim2.new(1,0,0,84),BackgroundTransparency=1,Parent=root})
 A.text({Text=opts.Title or "DaewidHUB",font=T.font.display,size=32,colour=T.c.text,Position=UDim2.fromOffset(24,22),Size=UDim2.new(1,-94,0,36),Parent=header})
 local close=L.mk("TextButton",{Name="Close",Text="×",Font=T.font.body,TextSize=24,TextColor3=T.c.textDim,BackgroundColor3=T.c.raised,BorderSizePixel=0,Size=UDim2.fromOffset(32,32),Position=UDim2.new(1,-52,0,24),Parent=header})
 L.corner(T.r.sm,close); self:StyleButton(close)
 local body=L.mk("Frame",{Name="Body",Position=UDim2.fromOffset(18,90),Size=UDim2.new(1,-36,1,-108),BackgroundTransparency=1,ClipsDescendants=true,Parent=root})
 local panel={gui=gui,root=root,body=body,header=header,revision=0,visible=false}
 function panel:Refit()
  local viewport=L.viewport()
  root.Size=UDim2.fromOffset(math.max(1,math.min(opts.Width or 940,viewport.X-24)),math.max(1,math.min(opts.Height or 680,viewport.Y-24)))
 end
 function panel:Show()
  self.visible=true; self.revision+=1; self:Refit(); gui.Enabled=true
  A.groupSet(root,1); M.set(scale,"Scale",.95); A.groupTo(root,0,"base"); M.to(scale,"Scale",1,"slow")
 end
 function panel:Hide()
  self.visible=false; self.revision+=1; local revision=self.revision
  A.groupTo(root,1,"fast"); M.to(scale,"Scale",.97,"fast")
  task.delay(.3,function() if self.revision==revision then gui.Enabled=false end end)
 end
 function panel:Toggle() if self.visible then self:Hide() else self:Show() end end
 L.hold(close.Activated:Connect(function() panel:Hide() end))
 L.cleanup(L.Giorgio.drag(root,header))
 L.hold(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() panel:Refit() end))
 panel:Refit()
 return panel
end


function UI:CreateWindow(opts)
 local native=L.Window.new({title=opts.Title,subtitle=opts.Subtitle,width=960,height=660,toggleKey=opts.ToggleKey,guiName="DaewidBallUI"})
 local window=setmetatable({native=native,tabs={},toggleKey=opts.ToggleKey},Window)
 owner={native=native,window=window,bindings={},listed={},onDestroy=opts.OnDestroy}
 UI._owner=owner; L.Hub.window=native; L.Giorgio.booting=false; L.Window.BLUR=0
 window:Refit()
 local function placeholder(name,value,callback)
  local entry={Type="Toggle",Value=value}
  entry.Set=function(value) entry.Value=value==true; if callback then callback(entry.Value) end; refreshBindings() end
  UI.Flags[name]=entry
 end
 placeholder("ui_blur",false,function(on) L.Window.BLUR=on and 16 or 0; A.blurTo(not native.hidden and L.Window.BLUR or 0,"base") end)
 placeholder("ui_reduceMotion",false)
 placeholder("ui_keylist",true)
 placeholder("ui_keylistAll",false)
 placeholder("ui_widgets",opts.Widgets==true)
 local quickGui=L.mk("ScreenGui",{Name="DaewidHUBQuickKeys",IgnoreGuiInset=true,ResetOnSpawn=false,DisplayOrder=30,Parent=L.host()}); L.own(quickGui)
 local keyHost=L.mk("ScrollingFrame",{Name="KeybindList",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,72),Size=UDim2.fromOffset(228,180),BackgroundColor3=T.c.surface,BackgroundTransparency=.12,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=2,ScrollBarImageColor3=T.c.accent,Visible=false,ClipsDescendants=true,Parent=quickGui})
 L.corner(T.r.lg,keyHost); L.stroke(T.c.lineStrong,1,.45,keyHost); L.pad(12,12,12,12,keyHost); L.list(4,nil,keyHost)
 owner.keyHost=keyHost
 owner.refreshBindings=function()
  for _,child in ipairs(keyHost:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
  A.text({Text="Q U I C K   K E Y S",font=T.font.mono,size=9,colour=T.c.textMute,Size=UDim2.new(1,0,0,18),Parent=keyHost})
  local count=0
  local function add(label,key,on)
   count+=1
   local row=L.mk("Frame",{Name="KeyRow",Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Parent=keyHost})
   A.text({Text=label,font=T.font.body,size=10,colour=on and T.c.text or T.c.textMute,Size=UDim2.new(1,-76,1,0),truncate=true,Parent=row})
   local badge=A.text({Text=keyName(key),font=T.font.mono,size=9,colour=T.c.textDim,align=Enum.TextXAlignment.Center,AnchorPoint=Vector2.new(1,0),Position=UDim2.fromScale(1,0),Size=UDim2.fromOffset(68,24),Parent=row})
   badge.BackgroundColor3=T.c.raised; badge.BackgroundTransparency=.3; L.corner(T.r.sm,badge)
  end
  add("Console",native.toggleKey,true)
  for _,info in ipairs(owner.listed) do
   local key,on=info.key(),info.on()
   if key and (info.always or on or UI.Flags.ui_keylistAll.Value) then
    local label=info.text:gsub(" on/off key$",""):gsub("Open / close key","Servers"):gsub("Old HUD show/hide key","Classic HUD")
    add(label,key,on)
   end
  end
  local viewport=L.viewport()
  keyHost.Size=UDim2.fromOffset(math.max(1,math.min(228,viewport.X-24)),math.max(1,math.min(46+count*28,248,viewport.Y-84)))
  keyHost.Visible=UI.Flags.ui_keylist.Value and native.hidden==true
 end
 local priorHidden=native.hidden
 local elapsed=0
 L.hold(L.RunService.Heartbeat:Connect(function(delta)
  if not L.live() then return end
  if priorHidden~=native.hidden then priorHidden=native.hidden; refreshBindings() end
  elapsed+=delta; if elapsed<.4 then return end; elapsed=0
  if owner.widget and owner.widget.Parent then owner.widget.Visible=UI.Flags.ui_widgets.Value and not native.hidden end
 end))
 L.hold(L.UIS.InputBegan:Connect(function(input,typing)
  if not L.live() or input.UserInputType~=Enum.UserInputType.Keyboard then return end
  if owner.capture then
   local capture=owner.capture; owner.capture=nil
   if input.KeyCode==Enum.KeyCode.Escape then capture.label.Text=keyName(capture.key())
   elseif input.KeyCode==Enum.KeyCode.Backspace then capture.apply(nil)
   else capture.apply(input.KeyCode) end
   task.defer(function() L.Binds.capturing=false end)
   return
  end
  if typing or L.UIS:GetFocusedTextBox() or L.Binds.capturing then return end
  if input.KeyCode==Enum.KeyCode.K and (L.UIS:IsKeyDown(Enum.KeyCode.LeftControl) or L.UIS:IsKeyDown(Enum.KeyCode.RightControl)) then return end
  for _,bind in ipairs(owner.bindings) do if bind.pressed and bind.key()==input.KeyCode then L.try("daewid.bind",bind.pressed) end end
 end))
 L.hold(quickGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() window:Refit(); refreshBindings() end))
 task.defer(function()
  if not L.live() then return end
  L.Theme.setMotion("Silk")
  refreshBindings()
  if opts.Intro and not UI.Flags.ui_reduceMotion.Value then
   L.Giorgio.load(function() if L.live() then native:show() end end)
  else native:show() end
 end)
 shared.__DaewidBallUI=UI
 return window
end
function Window:AddWidget(spec)
 local card=A.surface({Parent=owner.keyHost.Parent,elev=1,radius=T.r.lg,Size=UDim2.fromOffset(220,80),AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-12,1,-12),Name="SessionWidget"})
 owner.widget=card; card.Visible=UI.Flags.ui_widgets.Value
 A.text({Text=spec.Title,font=T.font.mono,size=10,colour=T.c.textMute,Position=UDim2.fromOffset(12,10),Size=UDim2.new(1,-24,0,15),Parent=card})
 local label=A.text({Text="-",font=T.font.display,size=24,colour=T.c.text,Position=UDim2.fromOffset(12,30),Size=UDim2.new(1,-24,0,32),Parent=card})
 local elapsed=0
 L.hold(L.RunService.Heartbeat:Connect(function(delta) elapsed+=delta; if elapsed<.5 or not card.Visible then return end; elapsed=0; local ok,value=pcall(spec.Get); if ok then label.Text=tostring(value) end end))
 return card
end
function UI:Destroy()
 if self._destroyed then return end
 self._destroyed=true
 local callback=owner and owner.onDestroy
 if L.live() then getgenv().__DAEWID_BALL_LUMEN_GEN+=1 end
 L.teardown()
 if shared.__DaewidBallUI==self then shared.__DaewidBallUI=nil end
 if callback then L.try("daewid.destroy",callback) end
 table.clear(self.Flags)
end
return UI
