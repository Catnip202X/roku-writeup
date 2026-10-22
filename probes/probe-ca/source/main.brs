' CAPROBE — read the TV's bundled TLS trust store and ship it off-device.
'
' Question: does Roku OS 15.3.4 (built Sep 2026) still trust CA roots that were
' distrusted after the October 2026 eMudhra intermediate-key compromise? If it
' does, and there is no pinning, TLS interception of the TV becomes feasible —
' which is the gate on pulling the OTA firmware image.
'
' common:/ is read-only for a channel but readable, so this is a plain read.
' Plain 2D app: main() runs on the MAIN thread, where roUrlTransfer works.
'
' NOTE: no identifier here may collide with a BrightScript builtin. `pos` and
' `log` are both builtins and both have already cost a compile failure.

sub main()
    print "[CA] ===== start ====="

    target = "common:/certs/ca-bundle.crt"
    body = invalid
    try
        body = ReadAsciiFile(target)
    catch e
        print "[CA] read-threw"
    end try

    if body = invalid then
        print "[CA] unreadable: "; target
        Idle()
        return
    end if

    print "[CA] path="; target
    print "[CA] bytes="; body.Len()
    print "[CA] certificates="; CountOcc(body, "BEGIN CERTIFICATE")

    ' Cheap local checks so a failed upload still tells us something.
    lowered = LCase(body)
    needles = ["emudhra", "cca india", "india", "sectigo", "digicert", "isrg", "amazon"]
    for each needle in needles
        print "[CA] find '"; needle; "' at="; Instr(1, lowered, needle)
    end for

    ' Full bundle off-device.
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl("http://HOST_IP_EN0:8899/ca")
    xfer.SetPort(CreateObject("roMessagePort"))
    posted = xfer.PostFromString(body)
    print "[CA] post="; posted
    print "[CA] ===== end ====="

    Idle()
end sub

function CountOcc(hay as string, needle as string) as integer
    count = 0
    cursor = 1
    while true
        hit = Instr(cursor, hay, needle)
        if hit = 0 then exit while
        count = count + 1
        cursor = hit + 1
    end while
    return count
end function

sub Idle()
    port = CreateObject("roMessagePort")
    while true
        wait(2000, port)
    end while
end sub
