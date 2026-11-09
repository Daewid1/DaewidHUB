do
 local L = getgenv().__DAEWID_BALL_LUMEN
 local data = { grain=false, rollNumbers=true, toggleAction='Minimise', cascade=.035, shadow=.34, ['giorgio.sfx']=true, ['giorgio.sfxVolume']=.35 }
 L.Cfg = {data=data, feat=function(key,fallback) local value=data[key]; if value==nil then return fallback end return value end,
 set=function(key,value) data[key]=value end, setFeat=function(key,value) data[key]=value end,
 keyCode=function() return Enum.KeyCode.RightShift end}
 L.Video = {new=function() return nil end}
 L.Binds = {capturing=false}
 L.Hub = {}
end
