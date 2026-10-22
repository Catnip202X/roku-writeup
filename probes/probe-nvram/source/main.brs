' NVRAMPROBE — follow the filesystem paths leaked by the console's r2d2_bitmaps
' command (/nvram/plugins/..., /RokuOS/..., /tmp/plugin/<hash>/pkg:/) and test
' whether any BrightScript volume alias maps into them.
'
' Plain 2D app, no SceneGraph, so main() runs on the MAIN thread — that is the
' thread where roUrlTransfer and the file APIs actually work (see ROADMAP §Path 1).
' Everything prints as [NVRAM] and the app then idles so tcp/8085 can be read.

sub main()
    print "[NVRAM] ==== start ===="
    fs = CreateObject("roFileSystem")

    print "[NVRAM] volumes=" + J(VolList(fs))

    ' Alias names guessed from the leaked absolute paths.
    aliases = ["nvram:", "NVRAM:", "nv:", "os:", "OS:", "rokuos:", "RokuOS:",
               "brandvisual:", "theme:", "themes:", "tmp:", "common:", "cachefs:"]
    for each a in aliases
        print "[NVRAM] alias " + a + " exists=" + S(Exists(fs, a)) + " list=" + LDir(a)
    end for

    ' Absolute paths straight, the way the native layer used them.
    paths = ["/nvram/", "/nvram/plugins", "/nvram/themes", "/RokuOS/",
             "/RokuOS/Artwork", "/tmp/plugin", "/etc/", "/"]
    for each p in paths
        print "[NVRAM] path " + p + " exists=" + S(Exists(fs, p)) + " list=" + LDir(p)
    end for

    ' Read a file we *know* exists from the bitmap dump, using each addressing style.
    known = "/nvram/plugins/837.unloaded/sg_poster_hd.jpg"
    print "[NVRAM] known exists=" + S(Exists(fs, known))
    print "[NVRAM] known as nvram:/ = " + S(Exists(fs, "nvram:/plugins/837.unloaded/sg_poster_hd.jpg"))

    ' If any alias is writable, that is the tamper primitive we have been after.
    for each a in ["nvram:", "NVRAM:", "os:", "RokuOS:", "theme:"]
        print "[NVRAM] WRITE " + a + " -> " + S(TryWrite(a + "nprobe.txt"))
    end for

    print "[NVRAM] ==== end ===="
    ' idle so the console stays readable
    port = CreateObject("roMessagePort")
    while true
        wait(2000, port)
    end while
end sub

function VolList(fs as object) as object
    try
        return fs.GetVolumeList()
    catch e
        return "THROW"
    end try
end function

function Exists(fs as object, p as string) as boolean
    try
        return fs.Exists(p)
    catch e
        return false
    end try
end function

function TryWrite(p as string) as string
    try
        return WriteAsciiFile(p, "x")
    catch e
        return "THROW"
    end try
end function

function LDir(p as string) as string
    try
        d = ListDir(p)
        return J(d)
    catch e
        return "THROW"
    end try
end function

function S(b as dynamic) as string
    if b = true then return "true"
    return "false"
end function

function J(v) as string
    if v = invalid then return "<invalid>"
    t = type(v)
    if t = "String" then return v
    if t = "roList" or t = "roArray" then
        out = "["
        i = 0
        for each e in v
            if i > 40 then
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

function ToStr(v) as string
    t = type(v)
    if t = "String" then return v
    if t = "Boolean" then
        if v then return "true" else return "false"
    end if
    return t
end function
