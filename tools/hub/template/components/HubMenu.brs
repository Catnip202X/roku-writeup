sub init()
    m.menu = m.top.findNode("menu")
    content = CreateObject("roSGNode", "ContentNode")

    labels = HubLabels()
    for each label in labels
        item = content.CreateChild("ContentNode")
        item.title = label
    end for

    m.menu.content = content
    m.menu.setFocus(true)
    m.menu.observeField("itemSelected", "onSelect")
end sub

sub onSelect()
    index = m.menu.itemSelected
    keys = HubKeys()
    if index < 0 or index >= keys.Count() then return
    m.top.chosen = keys[index]
end sub
