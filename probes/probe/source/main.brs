' RSPROBE — Roku channel sandbox boundary probe
' Purpose: from inside a sideloaded BrightScript channel, test what the app
' sandbox actually lets us touch: filesystem roots, registry sections (read AND
' write), cross-app files, and which privileged components are reachable.
' Everything is printed to the debug console (tcp/8085) tagged [RSPROBE].

sub main()
    print "[RSPROBE] ===== run start ====="
    di = CreateObject("roDeviceInfo")
    L("model", Di(di, "GetModel"))
    L("os", Di(di, "GetVersion"))
    L("clientId", Di(di, "GetChannelClientId"))
    L("uniqueId", Di(di, "GetUniqueId"))
    L("ridA", Di(di, "GetRIDA"))
    L("displayType", Di(di, "GetDisplayType"))
    L("connection", Di(di, "GetConnectionInfo"))

    ProbePaths()
    ProbeWrite()
    ProbeRegistry()
    ProbeLogs()
    ProbeComponents()

    print "[RSPROBE] ===== run end ====="
    WaitForKey()
end sub

' ---------------------------------------------------------------- filesystem
sub ProbePaths()
    fs = CreateObject("roFileSystem")
    L("fs.volumes", J(fs.GetVolumeList()))
    roots = ["pkg:/", "common:/", "tmp:/", "cachefs:/", "settings:/", "auth:/", _
             "ext1:/", "ext2:/", "sdcard:/", "/", "/var/", "/mnt/", "/etc/", _
             "/root/", "/opt/", "/usr/", "/tmp/"]
    for each p in roots
        L("exists " + p, TryExists(fs, p))
    end for
    ' what does a listable system root actually contain?
    for each d in ["common:/", "settings:/", "auth:/", "/", "/var/", "/etc/", "/mnt/"]
        L("listdir " + d, J(ListDir(d)))
    end for
    ' path traversal out of the package sandbox
    for each t in ["pkg:/..", "pkg:/../common", "pkg:/../../", "common:/../pkg", "cachefs:/../common"]
        L("traverse " + t, TryExists(fs, t))
    end for
    try
        L("freespace common:/", fs.GetFreeSpace("common:/"))
    catch e
        L("freespace common:/", "THROW " + e)
    end try
end sub

' Call a roDeviceInfo method by name, surviving throws so one bad accessor
' can never abort the whole probe run.
function Di(di as object, fn as string) as string
    try
        if fn = "GetRIDA" then return di.GetRIDA()
        if fn = "GetUniqueId" then return di.GetUniqueId()
        if fn = "GetChannelClientId" then return di.GetChannelClientId()
        if fn = "GetModel" then return di.GetModel()
        if fn = "GetVersion" then return di.GetVersion()
        if fn = "GetDisplayType" then return di.GetDisplayType()
        if fn = "GetConnectionInfo" then return J(di.GetConnectionInfo())
        return "no-such-method"
    catch e
        return "THROW " + e
    end try
end function

function TryExists(fs as object, p as string) as string
    try
        return fs.Exists(p)
    catch e
        return "THROW " + e
    end try
end function

' ------------------------------------------------------- write / delete prims
sub ProbeWrite()
    ' Only probes we can clean up. common:/ is the shared system filesystem —
    ' if a channel can write here the sandbox boundary is broken.
    results = [
        ["tmp:/rsprobe.txt", "tmp"],
        ["cachefs:/rsprobe.txt", "cachefs"],
        ["common:/rsprobe.txt", "common"],
        ["/tmp/rsprobe.txt", "slash-tmp"],
        ["/var/rsprobe.txt", "slash-var"]
    ]
    for each pair in results
        path = pair[0]
        w = TryWrite(path, "rsprobe " + pair[1])
        r = "n/a"
        d = "n/a"
        if w = true or w = "true"
            r = ReadAsciiFile(path)
            d = DeleteFile(path)
        end if
        L("write " + pair[1], "write=" + Str(w) + " readback=" + Str(r) + " delete=" + Str(d))
    end for
end sub

function TryWrite(p as string, body as string) as string
    try
        return WriteAsciiFile(p, body)
    catch e
        return "THROW " + e
    end try
end function

' ------------------------------------------------------------------ registry
sub ProbeRegistry()
    reg = CreateObject("roRegistry")
    sections = reg.GetSectionList()
    L("reg.sections", J(sections))
    n = 0
    for each s in sections
        rs = CreateObject("roRegistrySection", s)
        keys = rs.GetKeyList()
        L("reg[" + s + "].keys", J(keys))
        ' dump a bounded number of values so we can hunt ad/ACR flags
        i = 0
        for each k in keys
            if i < 40
                L("reg[" + s + "]" + k, Str(rs.Read(k)))
            end if
            i = i + 1
        end for
        n = n + 1
        if n > 24 then exit for
    end for
    ' THE money probe: can a channel persist into a system registry section?
    for each target in ["common", "settings", "device", "system", "ads"]
        ok = TryRegWrite(target)
        L("regwrite " + target, ok)
    end for
end sub

function TryRegWrite(section as string) as string
    try
        rs = CreateObject("roRegistrySection", section)
        w = rs.Write("rsprobe", "1")
        f = rs.Flush()
        back = rs.Read("rsprobe")
        del = rs.Delete("rsprobe")
        rs.Flush()
        return "write=" + Str(w) + " flush=" + Str(f) + " readback=" + Str(back) + " cleanup=" + Str(del)
    catch e
        return "THROW " + e
    end try
end function

' ---------------------------------------------------------------- log access
sub ProbeLogs()
    try
        sl = CreateObject("roSystemLog")
        sl.EnableType("http.connect")
        L("roSystemLog", "created ok")
    catch e
        L("roSystemLog", "THROW " + e)
    end try
end sub

' ------------------------------------------------ privileged component sweep
sub ProbeComponents()
    names = ["roHtmlWidget", "roHtmlWidgetVideo", "roChannelStore", "roAudioPlayer", _
             "roVideoPlayer", "roInputStream", "roFileSystem", "roRegistry", _
             "roRegistrySection", "roDeviceInfo", "roAppManager", "roAppMemoryMonitor", _
             "roSystemLog", "roSocketAddress", "roStreamSocket", "roDatagramSocket", _
             "roUrlTransfer", "roTimespan", "roPath", "roBrightScriptComponent", _
             "roCECStatus", "roAudioGuide", "roInput", "roRemoteInfo", "roTextureManager", _
             "roRenderThreadQueue", "roSGScreen", "roOdex", "roNetworkConfiguration", _
             "roWifiConfiguration", "roDeviceCrypto", "roScreenCapture"]
    for each n in names
        L("obj " + n, TryObj(n))
    end for
end sub

function TryObj(n as string) as string
    try
        o = CreateObject(n)
        if o = invalid then return "invalid"
        return type(o)
    catch e
        return "THROW " + e
    end try
end function

' -------------------------------------------------------------------- helpers
sub L(k, v)
    print "[RSPROBE] "; k; " = "; ToStr(v)
end sub

function ToStr(v) as string
    t = type(v)
    if t = "String" then return v
    if t = "Boolean" then
        if v then return "true" else return "false"
    end if
    if t = "roList" or t = "roArray" then return J(v)
    return t + ":" + Str(v)
end function

function J(v) as string
    if v = invalid then return "<invalid>"
    t = type(v)
    if t = "String" then return v
    if t = "roList" or t = "roArray" then
        out = "["
        i = 0
        for each e in v
            if i > 60 then
                out = out + " ..."
                exit for
            end if
            out = out + ToStr(e) + ","
            i = i + 1
        end for
        return out + "]"
    end if
    return ToStr(v)
end function

sub WaitForKey()
    port = CreateObject("roMessagePort")
    while true
        msg = wait(3000, port)
        if type(msg) = "roDateTime" then
            ' idle tick — keep the app (and tcp/8085 stream) alive
        end if
    end while
end sub
