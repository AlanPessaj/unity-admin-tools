print("opened")

util.AddNetworkString("MessageName")

net.Receive("MessageName", function(len, ply)
    print("works")
end)