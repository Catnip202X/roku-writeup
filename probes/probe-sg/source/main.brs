' SGPROBE v3 — probe from the MAIN thread.
'
' Lesson from v1/v2: a SceneGraph component's init() runs on the RENDER thread.
' There, roUrlTransfer fails ("MAIN|TASK-only component failed on RENDER thread"),
' roDeviceInfo returns dummy values ("999.99E99999A", "L000X"), and roHtmlWidget
' reports "unknown classname". So the render thread proves nothing about whether
' a component exists. Everything that matters now runs from Main() instead.

sub Main()
    port = CreateObject("roMessagePort")
    screen = CreateObject("roSGScreen")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.Show()

    ' Let the render context come up before touching renderables.
    sleep(1500)

    lines = []
    P(lines, "--- main-thread run ---")
    P(lines, "os=" + OsVersion())
    P(lines, "model=" + ModelName())
    P(lines, "clientId=" + ClientId())

    Sweep(lines)
    ProbeWidget(lines)

    SendReport(lines)

    ' Hold so the widget and any JS timers get a chance to run.
    elapsed = 0
    while elapsed < 40000
        msg = wait(1000, port)
        elapsed = elapsed + 1000
        if type(msg) = "roSGScreenEvent" and msg.IsScreenClosed() then return
    end while
end sub

sub P(lines as object, s as string)
    print "[SGPROBE] "; s
    lines.Push(s)
end sub

function TN(o as dynamic) as string
    if o = invalid then return "invalid"
    return type(o)
end function

function OsVersion() as string
    try
        return CreateObject("roDeviceInfo").GetOSVersion()
    catch e
        return "os-unknown"
    end try
end function

function ModelName() as string
    try
        return CreateObject("roDeviceInfo").GetModel()
    catch e
        return "model-unknown"
    end try
end function

function ClientId() as string
    try
        return CreateObject("roDeviceInfo").GetChannelClientId()
    catch e
        return "clientid-unknown"
    end try
end function

' Which classes are constructible on the MAIN thread? The render thread gave
' dummy answers for these, so the earlier sweep has to be redone here.
sub Sweep(lines as object)
    ' Built with Push(), not an array literal with "_" continuations — those
    ' produced a gapped array and for-each handed back an uninitialized variable.
    names = []
    names.Push("roHtmlWidget")
    names.Push("roHtmlWidgetVideo")
    names.Push("roNetworkConfiguration")
    names.Push("roWifiConfiguration")
    names.Push("roScreenCapture")
    names.Push("roDeviceCrypto")
    names.Push("roSystemLog")
    names.Push("roChannelStore")
    names.Push("roAppManager")
    names.Push("roInput")
    names.Push("roCECStatus")
    names.Push("roAudioGuide")
    names.Push("roTextureManager")
    names.Push("roRenderThreadQueue")
    names.Push("roSGScreen")
    names.Push("roDeviceInfo")
    names.Push("roFileSystem")
    names.Push("roRegistry")
    names.Push("roUrlTransfer")
    names.Push("roHdmiStatus")
    for each n in names
        P(lines, "obj " + n + "=" + Make(n))
    end for
end sub

function Make(n as string) as string
    try
        o = CreateObject(n)
        if o = invalid then return "invalid"
        return type(o)
    catch e
        return "unknown-classname"
    end try
end function

sub ProbeWidget(lines as object)
    made = false

    try
        w = CreateObject("roHtmlWidget")
        P(lines, "noargs=" + TN(w))
        if w <> invalid then
            m.html = w
            made = true
        end if
    catch e
        P(lines, "noargs-throw")
    end try

    if not made then
        try
            r = { x: 0, y: 0, w: 1280, h: 720 }
            w2 = CreateObject("roHtmlWidget", r)
            P(lines, "rect=" + TN(w2))
            if w2 <> invalid then
                m.html = w2
                made = true
            end if
        catch e2
            P(lines, "rect-throw")
        end try
    end if

    if not made then
        P(lines, "widget=UNAVAILABLE-on-main")
        return
    end if
    P(lines, "widget=CREATED-on-main")

    try
        P(lines, "ua=" + m.html.GetUserAgent())
    catch e3
        P(lines, "ua-unavailable")
    end try

    try
        m.html.SetFocus(true)
        P(lines, "focus=ok")
    catch e4
        P(lines, "focus-throw")
    end try

    page = "<html><head><title>sgprobe</title></head><body>"
    page = page + "<script>"
    page = page + "var b='http://HOST_IP_EN0:8899/beacon?src=html&ua='+encodeURIComponent(navigator.userAgent);"
    page = page + "function go(){try{fetch(b);}catch(e){var i=new Image();i.src=b;}}"
    page = page + "go();setTimeout(go,1200);setTimeout(go,3000);"
    page = page + "</script></body></html>"

    htmlok = false
    try
        m.html.SetHtml(page)
        P(lines, "sethtml=ok")
        htmlok = true
    catch e5
        P(lines, "sethtml-throw")
    end try

    if not htmlok then
        try
            m.html.SetUrl("pkg:/index.html")
            P(lines, "seturl-pkg=ok")
        catch e6
            P(lines, "seturl-pkg-throw")
        end try
    end if
end sub

' roUrlTransfer is MAIN|TASK-only — which is exactly why v2's report vanished.
sub SendReport(lines as object)
    body = ""
    for each line in lines
        body = body + line + chr(10)
    end for

    try
        xfer = CreateObject("roUrlTransfer")
        xfer.SetUrl("http://HOST_IP_EN0:8899/report")
        xfer.SetPort(CreateObject("roMessagePort"))
        ok = xfer.PostFromString(body)
        P(lines, "post=" + B2S(ok))
    catch e
        print "[SGPROBE] post-throw"
    end try
    print "[SGPROBE] === end ==="
end sub

function B2S(b as dynamic) as string
    if b = true then return "true"
    return "false"
end function
