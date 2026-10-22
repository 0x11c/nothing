-- NORMAL Roblox executor; not Matcha. Observes only: no inputs/remotes/state writes.
-- F1: optional trial marker. End: copy recording and stop.
-- Automatically copies/stops after 180 seconds. Requires executor setclipboard.
local env = type(getgenv)=="function" and getgenv() or _G
assert(type(setclipboard)=="function", "This recorder requires setclipboard")
if env.SoloMovementLogger then env.SoloMovementLogger.Stop() end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local HTTP=game:GetService("HttpService")
local lp=Players.LocalPlayer
local stamp=os.time()
local R={Running=true,Connections={},Modules={}}
env.SoloMovementLogger=R
local D={Version=1,StartedUnix=stamp,LocalUserId=lp.UserId,PlaceId=game.PlaceId,
    Constants={},Samples={},Events={},Marks={},Errors={},Modules={},DroppedEvents=0}
R.Data=D
local start=os.clock()
local function times() return {LocalTime=os.clock()-start,ServerTime=workspace:GetServerTimeNow()} end
local function serial(v,depth,seen)
    depth=depth or 0;seen=seen or {}
    local t=typeof(v)
    if t=="nil" then return {Type="nil"} end
    if t=="number" then return v==v and math.abs(v)<math.huge and v or tostring(v) end
    if t=="string" or t=="boolean" then return v end
    if t=="Vector3" then return {Type=t,X=v.X,Y=v.Y,Z=v.Z} end
    if t=="Vector2" then return {Type=t,X=v.X,Y=v.Y} end
    if t=="CFrame" then return {Type=t,Components={v:GetComponents()}} end
    if t=="Instance" then return {Type=t,Class=v.ClassName,Path=v:GetFullName()} end
    if t=="EnumItem" then return {Type=t,Value=tostring(v)} end
    if t~="table" then return {Type=t} end
    if seen[v] then return {Type="cycle"} end
    if depth>=10 then return {Type="depth_limit"} end
    seen[v]=true
    local entries={};local n=0
    for k,x in pairs(v) do
        n=n+1;if n>500 then entries[#entries+1]={Truncated=true};break end
        entries[#entries+1]={Key=serial(k,depth+1,seen),Value=serial(x,depth+1,seen)}
    end
    seen[v]=nil
    return {Type="table",Entries=entries}
end
local function failure(label,e)
    local key=label..": "..tostring(e)
    D.Errors[key]=(D.Errors[key] or 0)+1
end
local function call(label,module,fn,...)
    if not module or type(module[fn])~="function" then return nil end
    local result=table.pack(pcall(module[fn],...))
    if not result[1] then failure(label,result[2]);return nil end
    return table.unpack(result,2,result.n)
end
local paths={Renderer="Client.Gameplay.Ball.Renderer",Dodge="Client.Gameplay.Actions.Dodge",
    DodgeRules="Modules.Actions.Dodge",Tackle="Modules.Actions.SlideTackle",
    Hitboxes="Modules.Gameplay.HitboxSettings",Controls="Modules.Gameplay.Controls",
    Sprint="Client.Gameplay.Player.Sprint",Charge="Modules.Actions.ActionChargeState",
    Effects="Client.Gameplay.Actions.TackleEffects",Kick="Modules.Actions.KickCore",
    Motion="Modules.Characters.CharacterMotion",Teams="Client.Gameplay.ActorTeams"}
local function resolve(path)
    local obj=RS
    for name in path:gmatch("[^.]+") do obj=obj and obj:FindFirstChild(name) end
    return obj
end
-- Isolate module loads so one yielding require cannot prevent recording or stopping.
for name,path in pairs(paths) do
    D.Modules[name]={Path=path,Status="loading"}
    task.spawn(function()
        local obj=resolve(path)
        if not obj then D.Modules[name].Status="missing";return end
        local ok,m=pcall(require,obj)
        if not R.Running then return end
        if ok and type(m)=="table" then
            R.Modules[name]=m;D.Modules[name].Status="loaded"
            D.Constants[name]=serial(name=="Hitboxes" and m or m.Constants)
        else D.Modules[name].Status="failed";failure("require "..name,m) end
    end)
end
function R.Save()
    D.Elapsed=os.clock()-start
    local ok,e=pcall(function()
        R.LastJSON=HTTP:JSONEncode(D)
        setclipboard(R.LastJSON)
    end)
    if not ok then warn("Clipboard copy failed; recording retained in SoloMovementLogger.Data",e) end
    return ok
end
function R.Stop()
    if not R.Running then return end
    R.Running=false
    for _,c in ipairs(R.Connections) do c:Disconnect() end
    if R.Save() then print("SOLO RECORDING COPIED TO CLIPBOARD:",#D.Samples,"samples",#D.Events,"events. Paste it into chat.") end
end
local function event(kind,data)
    if #D.Events>=4000 then D.DroppedEvents=D.DroppedEvents+1;return end
    D.Events[#D.Events+1]={Kind=kind,Time=times(),Data=serial(data)}
end
local remotes=RS:FindFirstChild("Remotes")
local ballRemotes=remotes and remotes:FindFirstChild("Ball")
for _,name in ipairs({"State","Tackle","ActionUpdate","ActionPresentationUpdate"}) do
    local remote=ballRemotes and ballRemotes:FindFirstChild(name)
    if remote and remote:IsA("RemoteEvent") then
        R.Connections[#R.Connections+1]=remote.OnClientEvent:Connect(function(...)
            local ok,e=pcall(event,name,table.pack(...));if not ok then failure(name,e) end
        end)
    else D.Modules["Remote."..name]={Status="missing"} end
end
local keys={W=true,A=true,S=true,D=true,Space=true,Q=true,E=true,F=true,
    LeftShift=true,LeftControl=true}
local function inputEvent(input,phase,processed)
    if UIS:GetFocusedTextBox() then return end
    local key=input.KeyCode.Name
    local kind=input.UserInputType.Name
    if keys[key] or kind=="MouseButton1" or kind=="MouseButton2" then
        event("input",{Phase=phase,Key=key,InputType=kind,Processed=processed==true})
    end
end
R.Connections[#R.Connections+1]=UIS.InputBegan:Connect(function(input,processed)
    if not processed and not UIS:GetFocusedTextBox() then
        if input.KeyCode==Enum.KeyCode.End then R.Stop();return end
        if input.KeyCode==Enum.KeyCode.F1 then
            D.Marks[#D.Marks+1]={Time=times(),Kind="trial marker"}
            print("Solo trial marker",#D.Marks)
        end
    end
    inputEvent(input,"begin",processed)
end)
R.Connections[#R.Connections+1]=UIS.InputEnded:Connect(function(input,processed)
    inputEvent(input,"end",processed)
end)
task.spawn(function()
    while R.Running do
        local ok,e=pcall(function()
            local M=R.Modules
            local ch=lp.Character;local root=ch and ch:FindFirstChild("HumanoidRootPart")
            local hum=ch and ch:FindFirstChildOfClass("Humanoid")
            local frame={Time=times()}
            frame.BallId=call("ball id",M.Renderer,"GetMatchBallId")
            frame.Owner=call("owner",M.Renderer,"GetOwnedUserId")
            frame.OwnsBall=frame.Owner==lp.UserId
            frame.Dribbling=call("dribbling",M.Dodge,"IsDribbling")
            frame.Available=call("available",M.Controls,"IsAvailable","Dribble")
            frame.OnCooldown=call("cooldown",M.Controls,"IsOnCooldown","Dribble")
            frame.CooldownRemaining=call("cooldown remaining",M.Controls,"GetCooldownRemaining","Dribble")
            local cost=M.DodgeRules and M.DodgeRules.Constants and M.DodgeRules.Constants.StaminaCost
            if cost then frame.CanSpendStamina=call("stamina",M.Sprint,"CanSpendStamina",cost,true) end
            if ch and root and hum then
                frame.Local={Position=serial(root.Position),CFrame=serial(root.CFrame),Velocity=serial(root.AssemblyLinearVelocity),
                    State=tostring(hum:GetState()),Attributes=serial(ch:GetAttributes())}
                frame.Local.SlidingUntil=call("local sliding",M.Tackle,"GetSlidingUntil",ch)
                frame.Local.Charging=call("local charge",M.Charge,"IsCharging",lp)
                local fill,compact=call("local charge fill",M.Effects,"GetObservedChargeFill",lp)
                frame.Local.ChargeFill=fill;frame.Local.CompactCharge=compact
                frame.Local.NativeCFrame=serial(call("native pose",M.Motion,"GetCFrame",ch))
                frame.Local.NativeVelocity=serial(call("native velocity",M.Motion,"GetVelocity",ch))
                frame.Local.WalkSpeed=hum.WalkSpeed
                frame.Local.JumpHeight=hum.JumpHeight
                frame.Local.JumpPower=hum.JumpPower
                frame.Local.UseJumpPower=hum.UseJumpPower
                frame.Local.HipHeight=hum.HipHeight
                frame.Local.FloorMaterial=tostring(hum.FloorMaterial)
                frame.Local.MoveDirection=serial(hum.MoveDirection)
                frame.Gravity=workspace.Gravity
                frame.ControlStates={}
                for _,name in ipairs({"Kick","Tackle","Dribble","Pass","Lob","RainbowFlick"}) do
                    frame.ControlStates[name]={Active=call("active "..name,M.Controls,"IsActive",name),
                        Cooldown=call("cooldown "..name,M.Controls,"IsOnCooldown",name)}
                end
                frame.Animations={}
                local animator=hum:FindFirstChildOfClass("Animator")
                if animator then
                    for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
                        frame.Animations[#frame.Animations+1]={Name=track.Name,
                            Id=track.Animation and track.Animation.AnimationId,
                            Time=track.TimePosition,Speed=track.Speed,Weight=track.WeightCurrent}
                    end
                end
            end
            D.Samples[#D.Samples+1]=frame
        end)
        if not ok then failure("sample",e) end
        local elapsed=os.clock()-start
        if elapsed>=180 then R.Stop();break end
        task.wait(1/30)
    end
end)
print("SOLO LOGGER STARTED. Kick, tackle, walk and jump normally. 3 minutes. F1 optional marker / End copy+stop.")
print("Recording will be copied to your clipboard on stop. No automated inputs or outgoing remotes.")
