hook.Add("PlayerSay", "UniquieName", function(ply, text, team)
    print("Player said something")

    if text == "ni**a" then
        ply:Kill()
    end
end)
