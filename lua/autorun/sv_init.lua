print("ALAN SERVER RUNNING")

-- Wait for the server to be fully initialized
hook.Add("Initialize", "SetupNetworking", function()
    -- Register the network string
    util.AddNetworkString("MessageName")
    
    -- Set up the network receive handler
    net.Receive("MessageName", function(len, ply)
        if IsValid(ply) then
            print("Received message from " .. tostring(ply:Nick()))
        end
    end)
    
    print("Server networking initialized")
end)