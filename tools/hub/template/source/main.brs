' Hub entry point. Shows a menu, then hands off to the chosen app's entry point.
'
' Why the close-then-handoff dance: each bundled app's Main() creates its own
' roSGScreen and calls Show(). Only one screen can be live, so the hub screen is
' closed before the target app boots.

sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("HubMenu")
    screen.Show()

    if scene = invalid then
        print "[HUB] scene invalid"
        return
    end if

    scene.observeField("chosen", port)
    chosen = ""

    while true
        msg = wait(0, port)
        if type(msg) = "roSGNodeEvent" then
            if msg.GetField() = "chosen" then
                chosen = msg.GetData()
                if chosen <> "" then exit while
            end if
        else if type(msg) = "roSGScreenEvent" then
            if msg.IsScreenClosed() then return
        end if
    end while

    screen.Close()
    print "[HUB] launching "; chosen

    ok = HubLaunch(chosen, args)
    if not ok then
        print "[HUB] no entry for "; chosen
    end if
end sub
